#!/usr/bin/env bash
# En sandbox, le prompt d'avertissement du mode YOLO n'apporte rien : le
# container *est* la barrière de sécurité.
set -euo pipefail

settings="$HOME/.claude/settings.json"
mkdir -p "$HOME/.claude"
[ -f "$settings" ] || echo '{}' > "$settings"

tmp="$(mktemp)"
jq '.skipDangerousModePermissionPrompt = true' "$settings" > "$tmp" && mv "$tmp" "$settings"
