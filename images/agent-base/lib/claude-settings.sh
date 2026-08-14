#!/usr/bin/env bash
# En sandbox, le prompt d'avertissement du mode YOLO n'apporte rien : le
# container *est* la barrière de sécurité.
set -euo pipefail

# Le repli garde le script utilisable hors de l'image, où la variable n'est pas
# posée. Dans l'image, les deux valeurs coïncident — le point est qu'elles ne
# puissent pas diverger si le chemin change un jour d'un seul côté.
config="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
settings="$config/settings.json"
mkdir -p "$config"
[ -f "$settings" ] || echo '{}' > "$settings"

tmp="$(mktemp)"
jq '.skipDangerousModePermissionPrompt = true' "$settings" > "$tmp" && mv "$tmp" "$settings"
