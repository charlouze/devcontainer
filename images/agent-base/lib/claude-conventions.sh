#!/usr/bin/env bash
# Rattache les conventions de l'image au CLAUDE.md du volume partagé.
#
# Une ligne d'import, pas une copie : le contenu vit dans l'image et suit donc
# ses versions, au lieu de se figer au jour où le volume a été créé.
#
# Ajout idempotent et jamais d'écrasement : le volume est partagé entre projets
# et peut porter les mémoires propres de l'utilisateur.
set -uo pipefail

conventions=/etc/devcontainer/conventions.md
[ -f "$conventions" ] || exit 0

config="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
memoire="$config/CLAUDE.md"
import="@${conventions}"

mkdir -p "$config"
[ -f "$memoire" ] || : > "$memoire"

if ! grep -qxF "$import" "$memoire"; then
  # Ajouté en tête : ce fichier est de la mémoire utilisateur, on ne veut pas
  # que l'import se retrouve collé à la fin d'un paragraphe écrit à la main.
  printf '%s\n\n%s' "$import" "$(cat "$memoire")" > "$memoire.tmp" \
    && mv "$memoire.tmp" "$memoire"
fi

exit 0
