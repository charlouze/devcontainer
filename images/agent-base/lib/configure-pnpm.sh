#!/usr/bin/env bash
# pnpm veut son store sur le même système de fichiers que le projet, pour
# hardlinker vers node_modules au lieu de copier. Or le workspace et le store
# sont deux montages distincts : le lien dur est impossible. Sans storeDir
# explicite, pnpm ignore le volume et se fabrique un store *dans le projet* —
# ~900 Mo, 51 000 fichiers. L'IDE l'embarque alors dans son scan « detecting
# project structure », qu'il fait fichier par fichier via IJent : mesuré à 1 Go
# poussé sur le socket gRPC. Le symptôme n'est pas « pnpm est lent », c'est
# « l'IDE ne finit jamais de démarrer ».
#
# packageImportMethod est écrit explicitement plutôt que laissé au repli
# automatique de pnpm : un comportement de repli n'est pas un contrat, et cette
# image suit pnpm@latest.
#
# Réglage volontairement global et pas dans pnpm-workspace.yaml : ce dernier est
# versionné et partagé avec la CI, où /home/dev/.cache n'existe pas. pnpm 11 ne
# lit ni .npmrc ni ~/.config/pnpm/rc pour ça — uniquement config.yaml.
set -euo pipefail

mkdir -p "$HOME/.config/pnpm" "$HOME/.cache/pnpm-store"
printf 'storeDir: %s/.cache/pnpm-store\npackageImportMethod: copy\n' "$HOME" \
  > "$HOME/.config/pnpm/config.yaml"
