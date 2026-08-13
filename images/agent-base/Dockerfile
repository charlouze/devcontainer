# Dev container pour faire tourner un agent de code en mode autonome.
# Base Debian glibc : requis par le backend IDE JetBrains (pas d'Alpine/musl).
FROM mcr.microsoft.com/devcontainers/base:bookworm

# L'image de base fournit un utilisateur non-root nommé `vscode`. On le renomme :
# l'IDE ici est IntelliJ, autant que l'environnement le reflète. Fait dès cette
# couche parce que tout le durcissement qui suit se définit par rapport à `dev`.
ARG USERNAME=dev
RUN usermod --login ${USERNAME} --home /home/${USERNAME} --move-home vscode \
 && groupmod --new-name ${USERNAME} vscode \
 && mv /etc/sudoers.d/vscode /etc/sudoers.d/${USERNAME} \
 && sed -i "s/\bvscode\b/${USERNAME}/g" /etc/sudoers.d/${USERNAME}

# nodejs du dépôt Debian : il sert UNIQUEMENT d'interprète au garde-fou. C'est
# ce qui permet à mise de redescendre en user-level sans que l'agent puisse
# remplacer l'interpréteur qui exécute le garde-fou.
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends nodejs \
 && rm -rf /var/lib/apt/lists/*

# Le garde-fou, hors de portée de l'agent.
#
# Les répertoires sont créés explicitement : laissé à COPY --chmod, BuildKit
# applique le mode du fichier au parent qu'il crée, et un dossier en 0444 n'est
# pas traversable. Le fichier deviendrait illisible par `dev`, donc les managed
# settings ne seraient jamais chargés — panne silencieuse du garde-fou.
RUN mkdir -p /usr/local/lib/claude-guard /etc/claude-guard /etc/claude-code \
 && chmod 0755 /usr/local/lib/claude-guard /etc/claude-guard /etc/claude-code \
 # Le nom du binaire varie selon les paquets Debian ; on fige ici le chemin que
 # le wrapper utilisera, et on échoue au build si aucun n'existe.
 && ln -s "$(command -v nodejs || command -v node)" /usr/local/lib/claude-guard/node \
 && touch /etc/claude-guard/enabled \
 && chmod 0444 /etc/claude-guard/enabled

COPY --chown=root:root --chmod=0555 guard/run              /usr/local/lib/claude-guard/run
COPY --chown=root:root --chmod=0555 guard/agent-guard.cjs  /usr/local/lib/claude-guard/agent-guard.cjs
COPY --chown=root:root --chmod=0555 guard/rules.cjs        /usr/local/lib/claude-guard/rules.cjs
COPY --chown=root:root --chmod=0444 guard/managed-settings.json /etc/claude-code/managed-settings.json

USER ${USERNAME}
