#!/usr/bin/env bash
# Tout le durcissement repose sur le fait que l'agent tourne en `dev` : le
# garde-fou est protégé par les permissions du système de fichiers, pas par
# autre chose. Si le container exécutait les lifecycle scripts en root, la
# garantie tomberait — autant s'en apercevoir ici plutôt qu'après coup.
set -euo pipefail

warn() { printf '\033[1;33m /!\\ %s\033[0m\n' "$1" >&2; }

echo "utilisateur : $(id -un) (uid $(id -u))"

if [ "$(id -u)" = "0" ]; then
  warn "Les lifecycle scripts tournent en ROOT."
  warn "Le garde-fou root-only n'est alors plus une barrière : l'agent pourrait"
  warn "le réécrire. Vérifie remoteUser dans devcontainer.json avant tout YOLO."
fi

if [ ! -w . ]; then
  warn "Le workspace n'est pas inscriptible par $(id -un) — le chown de mise en"
  warn "place a échoué. Voir containerUser/runArgs dans devcontainer.json."
fi
