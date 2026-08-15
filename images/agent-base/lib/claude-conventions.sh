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
  #
  # Forme en flux, pas `"$(cat "$memoire")"` : la substitution de commande
  # aurait mangé les retours à la ligne finaux du fichier, qui cesserait
  # d'être un texte POSIX bien formé et romprait un `>>` ultérieur.
  #
  # Nom temporaire tiré par mktemp et non figé à « $memoire.tmp » : le volume
  # agent-claude est partagé entre projets, deux containers peuvent donc
  # provisionner en même temps et se disputer le même fichier intermédiaire.
  # Dans le MÊME répertoire, pour que le mv reste un renommage sur un seul
  # système de fichiers, donc atomique. L'écriture ne vise jamais $memoire, et
  # un échec laisse l'original intact — le mv n'a alors pas lieu.
  if temporaire="$(mktemp "$memoire.XXXXXX")"; then
    if { printf '%s\n\n' "$import"; cat "$memoire"; } > "$temporaire"; then
      mv "$temporaire" "$memoire"
    else
      rm -f "$temporaire"
    fi
  fi
fi

exit 0
