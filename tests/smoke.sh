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

PUSH='{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}'
PUSH_BRANCHE='{"tool_name":"Bash","tool_input":{"command":"git push -u origin ma-branche"}}'
PUSH_ENCHAINE='{"tool_name":"Bash","tool_input":{"command":"git push origin main; echo ok"}}'
GH_PR='{"tool_name":"Bash","tool_input":{"command":"gh pr create --title x --body y"}}'
GH_MERGE='{"tool_name":"Bash","tool_input":{"command":"gh pr merge 12"}}'
BUILD='{"tool_name":"Bash","tool_input":{"command":"pnpm nx build app"}}'
DOTENV='{"tool_name":"Read","tool_input":{"file_path":"/w/.env"}}'

section "Garde-fou"
check  "git push sur main est bloqué"             blocks "$PUSH"
check  "git push sur une branche passe"           allows "$PUSH_BRANCHE"
check  "git push sur main enchaîné par ; est bloqué" blocks "$PUSH_ENCHAINE"
check  "gh pr create passe"                       allows "$GH_PR"
check  "gh pr merge est bloqué"                   blocks "$GH_MERGE"
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
# usermod --login ne suit ni /etc/subuid ni /etc/subgid, qui portaient encore
# `vscode`. Ils sont vidés dans l'image : une plage subuid n'a aucun usage dans
# un container qui ne doit jamais créer de user namespace. L'assertion existe
# pour qu'une mise à jour de l'image de base ne les réintroduise pas en silence.
# `-f` puis `! -s` et non `! -s` seul : ce dernier est vrai aussi pour un
# fichier absent, et l'absence n'est pas ce qu'on veut vérifier.
check  "/etc/subuid existe et est vide"          in_base 'test -f /etc/subuid && test ! -s /etc/subuid'
check  "/etc/subgid existe et est vide"          in_base 'test -f /etc/subgid && test ! -s /etc/subgid'
check  "mise est sur le PATH"                    in_base 'command -v mise'
check  "claude est sur le PATH"                  in_base 'command -v claude'
check  "gh est sur le PATH"                      in_base 'command -v gh'
# Les deux chemins de chargement, parce que l'installeur de codegraph ne touche
# à aucun fichier rc : il compte sur un PATH déjà bon. C'est exactement le mode
# de panne que le Dockerfile documente — l'outil marche dans les scripts et reste
# introuvable dans le terminal de l'IDE.
check  "codegraph est sur le PATH"               in_base 'command -v codegraph'
check  "codegraph est sur le PATH en non-login"  in_base_i 'command -v codegraph'
# lib/codegraph.sh détache l'indexation avec setsid. S'il manquait, l'indexation
# ne partirait jamais et l'agent n'aurait qu'un graphe vide, sans message.
check  "setsid est disponible"                   in_base 'command -v setsid'
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

section "État de Claude Code"

# Sans shell du tout, donc sans /etc/profile ni fichier rc : c'est ce qu'un ENV
# d'image garantit et qu'un containerEnv ne garantit pas. Le lifecycle script,
# le terminal de l'IDE et un `docker exec` la voient tous les trois.
check "CLAUDE_CONFIG_DIR est exportée à tout processus" \
  test "$(docker run --rm -u dev "${HARD[@]}" "$BASE_IMAGE" printenv CLAUDE_CONFIG_DIR)" = /home/dev/.claude

# /etc/profile réécrit PATH de zéro — d'où le rattrapage documenté dans le
# Dockerfile. On vérifie que la variable, elle, traverse bien un shell de login.
check "CLAUDE_CONFIG_DIR survit au shell de login" \
  test "$(in_base 'printf %s "$CLAUDE_CONFIG_DIR"')" = /home/dev/.claude

# Le témoin est écrit À TRAVERS la variable, jamais à un chemin en dur : le test
# échoue donc dès que la variable et le montage cessent de désigner le même
# endroit. Ce qu'il prouve est la plomberie — que Claude Code écrive réellement
# là relève d'une vérification manuelle, elle demande une session authentifiée.
CFG_VOL="smoke-claude-$$"
check "un fichier écrit dans CLAUDE_CONFIG_DIR survit à la recréation" bash -c '
  docker run --rm -u dev -v '"$CFG_VOL"':/home/dev/.claude '"$BASE_IMAGE"' \
    bash -lc "echo temoin > \$CLAUDE_CONFIG_DIR/.claude.json" &&
  docker run --rm -u dev -v '"$CFG_VOL"':/home/dev/.claude '"$BASE_IMAGE"' \
    bash -lc "grep -q temoin \$CLAUDE_CONFIG_DIR/.claude.json"'
docker volume rm "$CFG_VOL" >/dev/null 2>&1 || true

# Valeur détournée, et pas la valeur par défaut : avec celle-ci, un script resté
# en dur sur $HOME/.claude passerait le test sans suivre la variable.
check "claude-settings.sh suit CLAUDE_CONFIG_DIR" in_base '
  CLAUDE_CONFIG_DIR=/tmp/cfg /usr/local/share/devcontainer/lib/claude-settings.sh
  [ "$(jq -r .skipDangerousModePermissionPrompt /tmp/cfg/settings.json)" = true ]'

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

# Idempotence sur le nombre d'occurrences, pas sur « au moins une » : ce script
# tourne à chaque recréation sur un volume qui persiste, un ajout aveugle
# empilerait la même ligne indéfiniment.
check "l'import des conventions est ajouté une seule fois" in_base '
  export CLAUDE_CONFIG_DIR=/tmp/cfg-conv
  /usr/local/share/devcontainer/lib/claude-conventions.sh
  /usr/local/share/devcontainer/lib/claude-conventions.sh
  [ "$(grep -cxF "@/etc/devcontainer/conventions.md" $CLAUDE_CONFIG_DIR/CLAUDE.md)" = 1 ]'

# Le volume est partagé : un CLAUDE.md écrit à la main par l'humain ne doit pas
# disparaître au provisionnement suivant.
check "l'import ne détruit pas la mémoire existante" in_base '
  export CLAUDE_CONFIG_DIR=/tmp/cfg-conv2
  mkdir -p $CLAUDE_CONFIG_DIR
  echo "ma memoire a moi" > $CLAUDE_CONFIG_DIR/CLAUDE.md
  /usr/local/share/devcontainer/lib/claude-conventions.sh
  grep -q "ma memoire a moi" $CLAUDE_CONFIG_DIR/CLAUDE.md &&
  grep -qxF "@/etc/devcontainer/conventions.md" $CLAUDE_CONFIG_DIR/CLAUDE.md'

check "les conventions sont en lecture seule pour dev" \
  in_base 'test -r /etc/devcontainer/conventions.md'
refute "dev ne peut pas réécrire les conventions" \
  in_base 'echo compromis > /etc/devcontainer/conventions.md'

# Les deux vérifications ci-dessus pointent sur un CLAUDE_CONFIG_DIR de test :
# elles prouvent que le script marche, pas qu'il écrit là où Claude Code lira
# vraiment. Celle-ci n'override rien et vise le chemin posé par l'image.
check "l'import atterrit dans le vrai CLAUDE_CONFIG_DIR" in_base '
  /usr/local/share/devcontainer/lib/claude-conventions.sh
  grep -qxF "@/etc/devcontainer/conventions.md" "$CLAUDE_CONFIG_DIR/CLAUDE.md"'

# Le point de montage du volume agent-gh, vérifié par exécution et non par
# lecture du Dockerfile : il doit être inscriptible par `dev`, et gh doit
# réellement résoudre sa configuration là. Une dérive du chemin ou un montage
# resté root:root livrerait un volume auquel gh n'écrit jamais — la connexion
# mourrait à chaque recréation sans qu'aucun message ne le signale.
check "dev peut écrire dans le point de montage de gh" \
  in_base 'test -w /home/dev/.config/gh'

# `gh config set` n'exige aucune authentification : le test tient donc en CI,
# sans jeton, et prouve le seul point qui compte ici — où gh écrit.
check "gh écrit sa configuration dans /home/dev/.config/gh" in_base '
  gh config set git_protocol https
  test -n "$(find /home/dev/.config/gh -type f)"'

check "identity.sh réussit sous dev"              in_base '/usr/local/share/devcontainer/lib/identity.sh'
check "identity.sh avertit sous root" \
  bash -c 'docker run --rm -u root '"$BASE_IMAGE"' \
    /usr/local/share/devcontainer/lib/identity.sh 2>&1 | grep -qi root'

# Sans connexion gh — l'état de tout container tant que l'humain ne s'est pas
# connecté, et de tout container recréé après expiration du jeton. Le
# provisionnement doit continuer, pas s'arrêter là.
check "github-auth sans connexion sort en 0 et dit quoi faire" in_base '
  sortie="$(/usr/local/share/devcontainer/lib/github-auth.sh)" &&
  printf "%s" "$sortie" | grep -q "gh auth login --with-token"'

section "CodeGraph"

# Sans shell du tout, pour la même raison que CLAUDE_CONFIG_DIR plus haut : c'est
# ce qu'un ENV d'image garantit. Sur la télémétrie, la valeur par défaut de
# l'outil est « active » — l'absence de cette variable ne se verrait donc nulle
# part, sinon dans le trafic sortant.
check "la télémétrie codegraph est coupée pour tout processus" \
  test "$(docker run --rm -u dev "${HARD[@]}" "$BASE_IMAGE" printenv CODEGRAPH_TELEMETRY)" = 0

# `status` en plus d'`explore` : c'est ce qui permet à l'agent de distinguer un
# « aucun appelant » vrai d'un index encore en construction. Non listé par
# défaut, donc invisible sans cette variable.
check "l'outil MCP status est exposé en plus d'explore" \
  test "$(docker run --rm -u dev "${HARD[@]}" "$BASE_IMAGE" printenv CODEGRAPH_MCP_TOOLS)" = explore,status

# L'index est une base SQLite dans le workspace. Sans auto-ignore, il apparaît
# dans le premier `git status` du projet, et c'est au dépôt de se défendre.
check "codegraph.sh rend l'index invisible de git" in_base '
  mkdir -p /tmp/projet-cg && cd /tmp/projet-cg
  mkdir -p /tmp/bin-ok && printf "%s\n" "#!/bin/sh" "exit 0" > /tmp/bin-ok/claude
  chmod +x /tmp/bin-ok/claude
  PATH=/tmp/bin-ok:$PATH /usr/local/share/devcontainer/lib/codegraph.sh &&
  [ "$(cat /tmp/projet-cg/.codegraph/.gitignore)" = "*" ]'

# Le graphe est un confort, pas une dépendance : un câblage raté doit se dire et
# se rejouer, jamais interrompre le provisionnement. Ici `claude` échoue à tous
# les coups — l'état d'un container dont le volume de login est neuf.
check "un câblage MCP raté n'arrête pas le provisionnement" in_base '
  mkdir -p /tmp/projet-cg2 && cd /tmp/projet-cg2
  mkdir -p /tmp/bin-ko && printf "%s\n" "#!/bin/sh" "exit 1" > /tmp/bin-ko/claude
  chmod +x /tmp/bin-ko/claude
  sortie="$(PATH=/tmp/bin-ko:$PATH /usr/local/share/devcontainer/lib/codegraph.sh 2>&1)" &&
  printf "%s" "$sortie" | grep -q "claude mcp add"'

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
  check "gh traverse la couche web"   in_web 'command -v gh'
  check "impeccable est déclaré"    in_web 'grep -q impeccable /etc/devcontainer/plugins.d/10-web.txt'
  check "le garde-fou survit à la couche web" \
    in_web '/usr/local/lib/claude-guard/node --version'

  # La couche web repasse USER root puis USER dev : on vérifie que la variable
  # héritée de l'image de base traverse quand même, plutôt que de le supposer.
  check "CLAUDE_CONFIG_DIR traverse la couche web" \
    test "$(docker run --rm -u dev "${HARD[@]}" "$WEB_IMAGE" printenv CLAUDE_CONFIG_DIR)" = /home/dev/.claude

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

  # Le volume `agent-playwright` est partagé entre projets, or le cache de
  # Playwright est compté par références et non content-addressed : chaque
  # `playwright install` y écrit le chemin absolu du paquet playwright-core qui
  # installe, puis supprime tout navigateur qu'aucun lien encore résolvable ne
  # réclame. D'un container à l'autre le chemin du projet voisin n'existe pas,
  # donc son lien est déclaré cassé et ses navigateurs partent avec.
  # PLAYWRIGHT_SKIP_BROWSER_GC coupe ce ramassage.
  #
  # Vérifié par le comportement et non par la présence de la variable : elle
  # n'est pas documentée par Playwright, et le jour où elle cesserait d'être
  # honorée la panne serait silencieuse — des navigateurs qui disparaissent
  # ressemblent à un cache froid, pas à une régression.
  #
  # Scénario : deux projets, deux versions de Playwright, le même volume. Le
  # chemin du premier est déplacé avant l'installation du second, ce qui
  # reproduit dans un seul container ce que sont deux containers l'un pour
  # l'autre. `ffmpeg` plutôt qu'un navigateur : même chemin de code de ramassage,
  # 1,3 Mio au lieu de 500.
  cache_playwright_partage() {
    local vol="smoke-pw-gc-$$" code
    docker run --rm -i -u dev -v "$vol":/home/dev/.cache/ms-playwright "$WEB_IMAGE" bash -l <<'EOS'
set -e
cache=/home/dev/.cache/ms-playwright
pose() {
  mkdir -p "$1" && cd "$1"
  printf '{"name":"p","version":"0.0.0","dependencies":{"playwright-core":"%s"}}' "$2" > package.json
  pnpm install --silent
  node node_modules/playwright-core/cli.js install ffmpeg
}
pose /tmp/projet-a 1.54.0
apres_a=$(ls "$cache")
mv /tmp/projet-a /tmp/projet-a-invisible
pose /tmp/projet-b 1.49.0

for entree in $apres_a; do
  [ -e "$cache/$entree" ] || { echo "$entree a disparu du cache"; exit 1; }
done
# Les deux versions demandent bien deux révisions distinctes : sans cela le
# scénario ne prouverait rien.
[ "$(ls "$cache" | grep -c '^ffmpeg-')" -ge 2 ]
EOS
    code=$?
    docker volume rm "$vol" >/dev/null 2>&1 || true
    return $code
  }
  check "un projet ne vide plus le cache Playwright des autres" cache_playwright_partage
fi

printf '\n'
if [ "$failures" -gt 0 ]; then
  printf '\033[31m%d vérification(s) en échec\033[0m\n' "$failures"
  exit 1
fi
printf '\033[32mToutes les vérifications passent\033[0m\n'
