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

# Le durcissement runtime que pose le devcontainer.json du projet. Il fait
# partie de ce qu'on teste : sans no-new-privileges, `dev` garde son sudo
# passwordless hérité de l'image de base et le garde-fou root-only n'est plus
# une barrière du tout. Le smoke test doit exercer l'image telle qu'elle tourne.
HARD=(--security-opt no-new-privileges)

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

# Deux chemins de chargement distincts, donc deux helpers :
#   -l  shell de login, lit /etc/profile puis /etc/profile.d — les terminaux
#       de l'IDE et les lifecycle scripts.
#   -i  shell interactif non-login, lit /etc/bash.bashrc puis ~/.bashrc — un
#       `docker exec -it bash`. Les rc sortent immédiatement quand $- ne
#       contient pas « i », d'où l'obligation du -i pour observer alias et
#       réglages d'historique.
in_base()   { docker run --rm -u dev "${HARD[@]}" -w /home/dev "$BASE_IMAGE" bash -lc "$1"; }
in_base_i() { docker run --rm -u dev "${HARD[@]}" -w /home/dev "$BASE_IMAGE" bash -ic "$1"; }

# Soumet un payload de hook au garde-fou et rend son code de sortie.
guard_code() {
  local payload="$1"; shift
  docker run --rm -i -u dev "${HARD[@]}" "$@" "$BASE_IMAGE" \
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
  bash -c 'docker run --rm -i -u dev --security-opt no-new-privileges '"$BASE_IMAGE"' \
    sh -c "exec env -i /usr/local/lib/claude-guard/run" <<<'"'$PUSH'"' >/dev/null 2>&1; [ $? = 2 ]'

# NODE_OPTIONS permettrait de précharger un module qui neutralise le script.
check  "bloque toujours malgré une injection NODE_OPTIONS" \
  bash -c 'docker run --rm -i -u dev --security-opt no-new-privileges '"$BASE_IMAGE"' \
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
refute "dev ne peut pas repasser root pour contourner" \
  in_base 'sudo -n tee /etc/claude-guard/enabled'

section "Utilisateur et toolchain"
check  "l'utilisateur par défaut est dev"        test "$(in_base 'id -un')" = dev
check  "dev n'est pas root"                      test "$(in_base 'id -u')" != 0
refute "sudo est neutralisé"                     in_base 'sudo -n true'
check  "mise est sur le PATH"                    in_base 'command -v mise'
check  "claude est sur le PATH"                  in_base 'command -v claude'
check  "l'alias yolo existe"                     in_base_i 'alias yolo'
check  "mise installe un outil à chaud sous dev" in_base 'mise install node@24 && mise exec node@24 -- node --version'

section "Historique bash"
HIST_VOL="smoke-history-$$"
check  "l'historique survit à la recréation du container" bash -c '
  docker run --rm -u dev -v '"$HIST_VOL"':/home/dev/.history '"$BASE_IMAGE"' \
    bash -lc "echo commande-temoin >> \$HISTFILE" &&
  docker run --rm -u dev -v '"$HIST_VOL"':/home/dev/.history '"$BASE_IMAGE"' \
    bash -lc "grep -q commande-temoin \$HISTFILE"'
docker volume rm "$HIST_VOL" >/dev/null 2>&1 || true

# Sur la valeur et pas sur « non vide » : bash interactif définit HISTFILE tout
# seul, à ~/.bash_history. L'assertion serait vraie même sans notre snippet.
check  "HISTFILE pointe vers le volume dans un shell non-login" \
  in_base_i '[ "$HISTFILE" = /home/dev/.history/bash_history ]'

section "Provisionnement"

# `claude` est bouchonné : on vérifie les commandes émises, pas une vraie
# installation, qui demanderait réseau et authentification en CI.
check "install-plugins émet les bonnes commandes" in_base '
  mkdir -p /tmp/bin
  printf "%s\n" "#!/bin/sh" "echo \"\$@\" >> /tmp/appels" "exit 0" > /tmp/bin/claude
  chmod +x /tmp/bin/claude
  PATH=/tmp/bin:$PATH /usr/local/share/devcontainer/lib/install-plugins.sh
  grep -q "plugin marketplace add anthropics/claude-plugins-official" /tmp/appels &&
  grep -q "plugin install superpowers@claude-plugins-official" /tmp/appels'

check "install-plugins survit à un plugin en échec" in_base '
  mkdir -p /tmp/bin
  printf "%s\n" "#!/bin/sh" "exit 1" > /tmp/bin/claude
  chmod +x /tmp/bin/claude
  PATH=/tmp/bin:$PATH /usr/local/share/devcontainer/lib/install-plugins.sh'

check "configure-pnpm écrit storeDir et packageImportMethod" in_base '
  /usr/local/share/devcontainer/lib/configure-pnpm.sh
  grep -q "storeDir: /home/dev/.cache/pnpm-store" ~/.config/pnpm/config.yaml &&
  grep -q "packageImportMethod: copy" ~/.config/pnpm/config.yaml'

check "claude-settings pose skipDangerousModePermissionPrompt" in_base '
  /usr/local/share/devcontainer/lib/claude-settings.sh
  [ "$(jq -r .skipDangerousModePermissionPrompt ~/.claude/settings.json)" = true ]'

check "claude-settings préserve les réglages existants" in_base '
  mkdir -p ~/.claude && echo "{\"theme\":\"dark\"}" > ~/.claude/settings.json
  /usr/local/share/devcontainer/lib/claude-settings.sh
  # Les deux clés, pas seulement theme : sans la seconde, un script absent ou
  # inerte passerait le test.
  [ "$(jq -r .theme ~/.claude/settings.json)" = dark ] &&
  [ "$(jq -r .skipDangerousModePermissionPrompt ~/.claude/settings.json)" = true ]'

check "identity.sh réussit sous dev"              in_base '/usr/local/share/devcontainer/lib/identity.sh'
check "identity.sh avertit sous root" \
  bash -c 'docker run --rm -u root '"$BASE_IMAGE"' \
    /usr/local/share/devcontainer/lib/identity.sh 2>&1 | grep -qi root'

check "post-create tolère l'absence de tâche setup" in_base '
  mkdir -p /tmp/vide && cd /tmp/vide
  mkdir -p /tmp/bin && printf "%s\n" "#!/bin/sh" "exit 0" > /tmp/bin/claude
  chmod +x /tmp/bin/claude
  PATH=/tmp/bin:$PATH /usr/local/share/devcontainer/post-create.sh'

check "post-create appelle mise run setup s'il existe" in_base '
  mkdir -p /tmp/avec && cd /tmp/avec
  printf "%s\n" "[tasks.setup]" "run = \"touch /tmp/setup-appele\"" > mise.toml
  mkdir -p /tmp/bin && printf "%s\n" "#!/bin/sh" "exit 0" > /tmp/bin/claude
  chmod +x /tmp/bin/claude
  PATH=/tmp/bin:$PATH /usr/local/share/devcontainer/post-create.sh
  test -f /tmp/setup-appele'

check "post-create est idempotent" in_base '
  mkdir -p /tmp/bin && printf "%s\n" "#!/bin/sh" "exit 0" > /tmp/bin/claude
  chmod +x /tmp/bin/claude
  cd /tmp
  PATH=/tmp/bin:$PATH /usr/local/share/devcontainer/post-create.sh &&
  PATH=/tmp/bin:$PATH /usr/local/share/devcontainer/post-create.sh'

if [ -n "$WEB_IMAGE" ]; then
  in_web() { docker run --rm -u dev "${HARD[@]}" -w /home/dev "$WEB_IMAGE" bash -lc "$1"; }

  # `check` invoque une commande : une fonction du script convient, un `bash -c`
  # non — les fonctions ne sont pas exportées vers le sous-shell.
  matches() { case "$2" in $1) return 0 ;; *) return 1 ;; esac; }

  section "Image web"
  check "node 22 est préinstallé"   matches 'v22.*' "$(in_web 'node --version')"
  check "pnpm est préinstallé"      in_web 'pnpm --version'
  check "java est préinstallé"      in_web 'java -version'
  check "impeccable est déclaré"    in_web 'grep -q impeccable /etc/devcontainer/plugins.d/10-web.txt'
  check "le garde-fou survit à la couche web" \
    in_web '/usr/local/lib/claude-guard/node --version'

  # Le cœur du réglage pnpm : le store doit atterrir dans le volume, et surtout
  # PAS dans le projet — c'est le store dans le projet qui fait que l'IDE ne
  # démarre jamais.
  STORE_VOL="smoke-store-$$"
  check "le store pnpm tombe dans le volume et pas dans le projet" bash -c '
    docker run --rm -u dev -v '"$STORE_VOL"':/home/dev/.cache/pnpm-store '"$WEB_IMAGE"' bash -lc "
      /usr/local/share/devcontainer/lib/configure-pnpm.sh
      mkdir -p /tmp/w && cd /tmp/w
      printf \"{\\\"name\\\":\\\"w\\\",\\\"version\\\":\\\"0.0.0\\\",\\\"dependencies\\\":{\\\"is-odd\\\":\\\"3.0.1\\\"}}\" > package.json
      pnpm install --silent >/dev/null 2>&1
      case \"\$(pnpm store path)\" in /home/dev/.cache/pnpm-store*) ;; *) exit 1 ;; esac
      [ -z \"\$(find /tmp/w -maxdepth 3 -name \\\"*pnpm-store*\\\" -o -maxdepth 3 -name \\\".pnpm-store\\\")\" ]
    "'
  docker volume rm "$STORE_VOL" >/dev/null 2>&1 || true

  # Les montages imbriqués reposent sur l'ordonnancement de Docker par
  # profondeur de chemin — parent d'abord. Vérifié plutôt que supposé.
  # Les deux volumes imbriqués du template, pas un seul : chacun a besoin que son
  # point de montage préexiste dans l'image, sinon Docker le crée en root:root et
  # `dev` ne peut rien y écrire.
  A="smoke-cache-$$"; B="smoke-nested-$$"; C="smoke-pw-$$"
  check "les montages imbriqués s'établissent dans le bon ordre et sous dev" bash -c '
    docker run --rm -u dev \
      -v '"$A"':/home/dev/.cache \
      -v '"$B"':/home/dev/.cache/pnpm-store \
      -v '"$C"':/home/dev/.cache/ms-playwright \
      '"$WEB_IMAGE"' bash -lc "
        touch /home/dev/.cache/pnpm-store/temoin &&
        touch /home/dev/.cache/ms-playwright/temoin &&
        mountpoint -q /home/dev/.cache/pnpm-store &&
        mountpoint -q /home/dev/.cache/ms-playwright"'
  docker volume rm "$A" "$B" "$C" >/dev/null 2>&1 || true
fi

printf '\n'
if [ "$failures" -gt 0 ]; then
  printf '\033[31m%d vérification(s) en échec\033[0m\n' "$failures"
  exit 1
fi
printf '\033[32mToutes les vérifications passent\033[0m\n'
