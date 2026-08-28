#!/usr/bin/env bash
# Câble codegraph à l'agent, et lance l'indexation du projet.
#
# Deux gestes distincts, pour deux raisons distinctes.
#
# L'enregistrement MCP vise `~/.claude.json`, qui vit dans le volume
# `agent-claude`. Une couche d'image ne peut donc pas le poser : le volume
# l'écraserait au premier montage. C'est du provisionnement, comme les plugins,
# et au scope `user` pour la même raison qu'eux — le volume étant partagé entre
# projets, un seul câblage les sert tous.
#
# L'index, lui, est propre au projet et vit dans le workspace. Il est construit
# DÉTACHÉ : sur un gros dépôt l'indexation se compte en minutes, que le
# provisionnement n'a pas à faire attendre. Contrepartie assumée, désamorcée
# dans /etc/devcontainer/conventions.md — pendant cette fenêtre le graphe est
# incomplet, et l'agent doit interroger `codegraph_status` avant de conclure
# qu'un symbole n'a pas d'appelant.
#
# Rien ici ne fait échouer le provisionnement : pas de `set -e`, et sortie en 0
# quoi qu'il arrive. Un câblage raté doit se voir et se rejouer à la main, pas
# empêcher le container de démarrer — l'agent reste utilisable sans son graphe.
set -uo pipefail

warn() { printf '\033[1;33m /!\\ %s\033[0m\n' "$1" >&2; }

command -v codegraph >/dev/null 2>&1 || {
  warn "codegraph introuvable sur le PATH, étape ignorée"
  exit 0
}

# Même contrat que install-plugins.sh : on tolère le code de retour de `add`,
# qui échoue sur un serveur déjà enregistré — le volume étant persistant, c'est
# le cas NORMAL dès le deuxième provisionnement — et on ne juge que l'état final.
claude mcp add --scope user codegraph -- codegraph serve --mcp >/dev/null 2>&1

# Sous `timeout` parce que `mcp get` ne lit pas une configuration : il
# health-checke le serveur, donc le lance pour de vrai. Une vérification qui
# pend suspendrait tout le provisionnement, et la panne serait bien pire que
# celle qu'on cherche à détecter.
if timeout 30 claude mcp get codegraph >/dev/null 2>&1; then
  echo "serveur MCP enregistré : codegraph"
else
  warn "Enregistrement du serveur MCP codegraph échoué. À rejouer à la main :"
  warn "  claude mcp add --scope user codegraph -- codegraph serve --mcp"
fi

# L'index s'auto-ignore : le dépôt du projet n'a rien à changer à son .gitignore
# pour ne pas committer une base SQLite. Écrit AVANT l'indexation, qui crée
# sinon le répertoire sans ce fichier — et la fenêtre où l'index est visible de
# git est précisément celle où l'agent lit `git status`.
mkdir -p "$PWD/.codegraph"
[ -f "$PWD/.codegraph/.gitignore" ] || printf '%s\n' '*' > "$PWD/.codegraph/.gitignore"

# `init` construit le graphe, `sync` le met à jour. Le distinguer sur la présence
# de la base, et non sur celle du répertoire, que la ligne ci-dessus vient de
# créer dans tous les cas.
if [ -f "$PWD/.codegraph/codegraph.db" ]; then
  action=sync
else
  action=init
fi

# Le journal atterrit dans ~/.cache, monté sur un volume propre au projet :
# l'échec d'un processus détaché reste lisible après coup au lieu de partir avec
# lui.
journal="$HOME/.cache/codegraph-$action.log"

# `setsid` et pas seulement `nohup` : nohup n'ignore que SIGHUP, alors que ce
# qui menace ici est l'IDE tuant le groupe de processus du lifecycle script à sa
# terminaison. Une nouvelle session met l'indexation hors de cette portée.
setsid codegraph "$action" "$PWD" >"$journal" 2>&1 &

echo "indexation lancée en tâche de fond — $action, journal dans $journal"

exit 0
