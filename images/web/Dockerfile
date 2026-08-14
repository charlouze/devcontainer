# Modèle « web » : Nx + Angular + pnpm + émulateurs Firebase.
ARG BASE=ghcr.io/charlouze/devcontainer-agent-base:1
FROM ${BASE}

USER root
# `playwright install-deps` ne fait qu'installer des paquets système, mais il
# passe par npx — et le paquet Debian `nodejs` de la couche base (interprète du
# garde-fou) n'embarque pas npm. On l'ajoute donc ici. Il est conservé plutôt
# que purgé : un `autoremove` risquerait d'emporter `nodejs`, donc l'interprète
# du garde-fou, et la panne serait silencieuse.
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends npm \
 && npx -y playwright@1.54.0 install-deps chromium webkit \
 && rm -rf /var/lib/apt/lists/* /root/.npm \
 # Filet : le garde-fou dépend de cet interprète, une régression apt le casserait
 # sans bruit.
 && test -x /usr/local/lib/claude-guard/node

COPY --chown=root:root --chmod=0444 etc/plugins.d/ /etc/devcontainer/plugins.d/
RUN chmod 0755 /etc/devcontainer/plugins.d

USER dev
# Préinstallation à titre de cache chaud, pas de contrainte : mise étant en
# user-level, un projet qui demande d'autres versions les installera lui-même.
# java sert aux émulateurs Firestore, Realtime Database et Pub/Sub — préinstallé
# pour que le premier `mise run emulators` ne parte pas en téléchargement de
# 300 Mo.
RUN mise use --global --yes node@22 pnpm@latest java@25
