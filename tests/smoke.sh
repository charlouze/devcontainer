#!/usr/bin/env bash
# Vérifications au niveau container. Ce qui est protégé ici n'est vérifiable
# que par exécution : les permissions, l'ordre des montages, la persistance.
set -uo pipefail

# Sous Git Bash (Windows), la couche MSYS réécrit tout argument qui ressemble à
# un chemin Unix avant de le passer à docker.exe : `-w /home/dev` devient
# `-w C:/Program Files/Git/home/dev`. Sans effet sur un vrai Linux, donc la CI
# n'est pas concernée.
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL='*'

BASE_IMAGE="${1:?usage: smoke.sh <image-base> [<image-web>]}"
WEB_IMAGE="${2:-}"

failures=0
section() { printf '\n\033[1;36m== %s\033[0m\n' "$1"; }
ok()      { printf '  \033[32mok\033[0m   %s\n' "$1"; }
ko()      { printf '  \033[31mKO\033[0m   %s\n' "$1"; failures=$((failures + 1)); }

# check <description> <commande...> : succès attendu
check() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$desc"; else ko "$desc"; fi
}

# refute <description> <commande...> : échec attendu
refute() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then ko "$desc"; else ok "$desc"; fi
}

# Exécute un shell de login dans l'image, sous dev.
in_base() { docker run --rm -u dev -w /home/dev "$BASE_IMAGE" bash -lc "$1"; }

# Soumet un payload de hook au garde-fou et rend son code de sortie.
guard_code() {
  local payload="$1"; shift
  docker run --rm -i -u dev "$@" "$BASE_IMAGE" \
    /usr/local/lib/claude-guard/run >/dev/null 2>&1 <<<"$payload"
  echo $?
}

blocks()  { [ "$(guard_code "$1" "${@:2}")" = "2" ]; }
allows()  { [ "$(guard_code "$1" "${@:2}")" = "0" ]; }

PUSH='{"tool_name":"Bash","tool_input":{"command":"git push"}}'
BUILD='{"tool_name":"Bash","tool_input":{"command":"pnpm nx build app"}}'
DOTENV='{"tool_name":"Read","tool_input":{"file_path":"/w/.env"}}'

section "Garde-fou"
check  "git push est bloqué"                      blocks "$PUSH"
check  "une commande anodine passe"               allows "$BUILD"
check  "la lecture d'un .env est bloquée"         blocks "$DOTENV"
check  "un payload illisible ne bloque pas"       allows 'pas du json'

# Le garde-fou ne doit dépendre d'aucune variable d'environnement : l'agent
# contrôle l'environnement des processus qu'il lance.
check  "bloque toujours avec un environnement vidé" \
  bash -c 'docker run --rm -i -u dev '"$BASE_IMAGE"' \
    sh -c "exec env -i /usr/local/lib/claude-guard/run" <<<'"'$PUSH'"' >/dev/null 2>&1; [ $? = 2 ]'

# NODE_OPTIONS permettrait de précharger un module qui neutralise le script.
check  "bloque toujours malgré une injection NODE_OPTIONS" \
  bash -c 'docker run --rm -i -u dev '"$BASE_IMAGE"' \
    sh -c "echo \"process.reallyExit=function(){};process.exit=function(){};\" > /tmp/x.cjs;
           NODE_OPTIONS=--require=/tmp/x.cjs exec /usr/local/lib/claude-guard/run" \
    <<<'"'$PUSH'"' >/dev/null 2>&1; [ $? = 2 ]'

section "Immuabilité du garde-fou"
refute "dev ne peut pas modifier agent-guard.cjs" \
  in_base 'echo compromis > /usr/local/lib/claude-guard/agent-guard.cjs'
refute "dev ne peut pas modifier le wrapper" \
  in_base 'echo compromis > /usr/local/lib/claude-guard/run'
refute "dev ne peut pas supprimer le marqueur" \
  in_base 'rm -f /etc/claude-guard/enabled'
refute "dev ne peut pas modifier les managed settings" \
  in_base 'echo "{}" > /etc/claude-code/managed-settings.json'

printf '\n'
if [ "$failures" -gt 0 ]; then
  printf '\033[31m%d vérification(s) en échec\033[0m\n' "$failures"
  exit 1
fi
printf '\033[32mToutes les vérifications passent\033[0m\n'
