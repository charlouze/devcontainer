#!/usr/bin/env bash
# Provisionnement du dev container. Rejoué à chaque rebuild, donc idempotent.
set -euo pipefail

lib="$(dirname "$0")/lib"
say() { printf '\n\033[1;36m==> %s\033[0m\n' "$1"; }

say "Identité";            "$lib/identity.sh"
say "Toolchain mise";      mise trust --yes && mise install --yes
say "Store pnpm";          "$lib/configure-pnpm.sh"
say "Réglages Claude";     "$lib/claude-settings.sh"
say "Conventions";         "$lib/claude-conventions.sh"
say "Plugins";             "$lib/install-plugins.sh"
say "CodeGraph";           "$lib/codegraph.sh"
say "Git";                 git config --global --add safe.directory "$PWD"
say "GitHub";              "$lib/github-auth.sh"

# Contrat base <-> projet : le projet décrit son provisionnement dans son
# mise.toml, au même endroit que ses tâches de dev. Un dépôt vide n'a pas encore
# de tâche `setup` : c'est un cas normal, pas une erreur.
if mise tasks ls 2>/dev/null | grep -qE '^setup\b'; then
  say "Provisionnement du projet"
  mise run setup
fi

regles=".devcontainer/guard-rules.json"
cat <<EOF

  Environnement prêt.

    claude          première fois : login
    yolo            claude --dangerously-skip-permissions
    codegraph       graphe du code, interrogé par l'agent via MCP
                    (l'indexation tourne en fond, elle vient de démarrer)

  Garde-fous actifs dans ce container :
    - aucun credential Google/GCP : le SDK Admin ne peut viser que l'émulateur
    - firebase deploy, gcloud, publish npm : bloqués par hook
    - git push : ouvert sur une branche, bloqué sur main
    - gh : création et modification de PR seulement, jamais le merge
      (ces deux dernières tiennent par la consigne autant que par le hook —
      le jeton présent ici permettrait de les enfreindre)
    - non-root, capabilities Linux réduites, pas de socket Docker
    - règles projet : $( [ -f "$regles" ] && echo "chargées depuis $regles" || echo "aucune" )

EOF
