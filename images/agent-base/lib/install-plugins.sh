#!/usr/bin/env bash
# Installe les plugins Claude Code déclarés par les couches d'image.
#
# Format de /etc/devcontainer/plugins.d/*.txt, trois champs :
#   <dépôt-marketplace> <nom-marketplace> <plugin>
# Le nom de la marketplace (déclaré dans son marketplace.json) diffère du chemin
# du dépôt : `marketplace add` prend le second, `plugin install` le premier.
#
# ~/.claude est un volume persistant : au rebuild suivant, les deux commandes
# retombent sur du déjà-installé. On tolère leur code de retour et on ne juge
# que l'état final via `details`, qui sort en 1 tant que le plugin n'est pas
# installé — être présent dans une marketplace ne suffit pas.
#
# La marketplace officielle n'est enregistrée d'office qu'au premier lancement
# *interactif* de `claude` ; ce script ne l'étant pas, l'ajout est explicite.
set -uo pipefail

warn() { printf '\033[1;33m /!\\ %s\033[0m\n' "$1" >&2; }

dir=/etc/devcontainer/plugins.d
[ -d "$dir" ] || exit 0

for file in "$dir"/*.txt; do
  [ -e "$file" ] || continue
  while read -r repo marketplace plugin _rest; do
    case "${repo:-}" in ''|'#'*) continue ;; esac
    [ -n "${marketplace:-}" ] && [ -n "${plugin:-}" ] || {
      warn "ligne mal formée dans $(basename "$file") : $repo $marketplace $plugin"
      continue
    }

    claude plugin marketplace add "$repo" >/dev/null 2>&1
    claude plugin install "${plugin}@${marketplace}" >/dev/null 2>&1

    if claude plugin details "${plugin}@${marketplace}" >/dev/null 2>&1; then
      echo "plugin installé : ${plugin}@${marketplace}"
    else
      warn "Installation de ${plugin} échouée. À rejouer à la main :"
      warn "  claude plugin marketplace add ${repo}"
      warn "  claude plugin install ${plugin}@${marketplace}"
    fi
  done < "$file"
done

exit 0
