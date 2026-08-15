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

RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      build-essential ca-certificates curl git gnupg jq less procps ripgrep \
      unzip xz-utils \
 && rm -rf /var/lib/apt/lists/*

# Points de montage des volumes. Créés avec le bon propriétaire ici pour que
# Docker initialise les volumes vides avec cet ownership plutôt que root : un
# chemin absent de l'image donne un point de montage root:root, et `dev` ne peut
# alors rien y écrire. Les deux montages imbriqués sous .cache sont donc listés
# explicitement, même s'ils sont vides — c'est leur seule raison d'être ici.
RUN mkdir -p /home/${USERNAME}/.claude \
             /home/${USERNAME}/.cache \
             /home/${USERNAME}/.cache/pnpm-store \
             /home/${USERNAME}/.cache/ms-playwright \
             /home/${USERNAME}/.config/gh \
             /home/${USERNAME}/.history \
             /home/${USERNAME}/.local/bin \
 && chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}

# /etc/profile réécrit PATH de zéro, ce qui efface ce qui vient des directives
# ENV. Les terminaux de l'IDE étant des shells de login, il faut réinjecter
# après coup — sinon les outils sont introuvables dans le terminal alors qu'ils
# marchent dans les scripts. Et un `docker exec bash` n'est PAS un shell de
# login : il ne lit que /etc/bash.bashrc. D'où le double chargement.
#
# /etc/devcontainer est créé avant le COPY, pour la même raison que les
# répertoires du garde-fou plus bas : laissé à COPY --chmod, BuildKit applique
# le mode du fichier au parent qu'il crée. Un dossier en 0444 n'est pas
# traversable, /etc/profile.d/20-history.sh pointe alors sur un fichier
# illisible et l'historique tombe en silence.
RUN mkdir -p /etc/devcontainer && chmod 0755 /etc/devcontainer
COPY --chown=root:root --chmod=0444 etc/history.sh /etc/devcontainer/history.sh
RUN printf '%s\n' \
      'export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"' \
      > /etc/profile.d/10-mise.sh \
 && chmod 0644 /etc/profile.d/10-mise.sh \
 && ln -s /etc/devcontainer/history.sh /etc/profile.d/20-history.sh \
 && printf '%s\n' \
      '. /etc/profile.d/10-mise.sh' \
      '. /etc/devcontainer/history.sh' \
      >> /etc/bash.bashrc

USER ${USERNAME}
ENV PATH=/home/dev/.local/bin:/home/dev/.local/share/mise/shims:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin

# Claude Code range son état dans le répertoire `.claude`, mais son fichier de
# configuration principal est `~/.claude.json` — un FRÈRE du répertoire, pas un
# enfant. Sans cette variable il reste hors du volume et meurt avec le
# container : onboarding rejoué, dialogue de confiance reposé, et connexion
# redemandée malgré un jeton pourtant persisté — l'identité vit dans ce fichier
# (`oauthAccount`), pas dans les credentials. Avec la variable, il atterrit dans
# `/home/dev/.claude/.claude.json`, donc dans le volume.
#
# Ici et non dans `containerEnv` du template : un `containerEnv` que l'IDE
# cesserait d'honorer revient vide, Claude Code retombe sur $HOME, et les
# réglages se remettent à mourir à chaque rebuild sans erreur nulle part. Un ENV
# d'image ne peut pas être ignoré, et il est atteignable par le smoke test.
#
# La valeur doit rester identique à la cible du montage `agent-claude` du
# template ; tests/unit/image-config-dir.test.cjs tient les deux en accord.
ENV CLAUDE_CONFIG_DIR=/home/dev/.claude

# mise en user-level : l'arbre appartient à `dev`, donc `mise install`
# fonctionne à chaud et chaque projet applique son mise.toml sans rebuild. Le
# garde-fou n'en dépend plus (cf. guard/run).
RUN curl -fsSL https://mise.run | sh

# Installeur natif : l'agent vit dans ~/.local/bin et se met à jour lui-même
# sans jamais avoir besoin de root.
RUN curl -fsSL https://claude.ai/install.sh | bash

RUN printf '%s\n' "alias yolo='claude --dangerously-skip-permissions'" \
      >> /home/dev/.bashrc

# gh sert à ouvrir et modifier des pull requests depuis la session. En
# user-level comme le reste de la toolchain : rien de ce que l'agent utilise au
# quotidien n'a à appartenir à root.
#
# Sa configuration vit dans ~/.config/gh, l'emplacement par défaut — c'est ce
# qui permet au template d'y monter un volume sans poser la moindre variable
# d'environnement, donc sans rien qu'un IDE puisse ignorer en silence.
RUN mise use --global --yes gh@latest

USER root

# Provisionnement. Le chmod explicite qui suit n'est pas décoratif : COPY
# --chmod=0444 sur une arborescence applique aussi 0444 au répertoire créé, qui
# n'est alors plus traversable et dont les fichiers deviennent illisibles.
COPY --chown=root:root --chmod=0555 post-create.sh /usr/local/share/devcontainer/post-create.sh
COPY --chown=root:root --chmod=0555 lib/           /usr/local/share/devcontainer/lib/
COPY --chown=root:root --chmod=0444 etc/plugins.d/ /etc/devcontainer/plugins.d/
COPY --chown=root:root --chmod=0444 etc/conventions.md /etc/devcontainer/conventions.md
RUN chmod 0755 /usr/local/share/devcontainer \
               /usr/local/share/devcontainer/lib \
               /etc/devcontainer/plugins.d

# Le garde-fou, hors de portée de l'agent. Dernière couche : une modification du
# garde-fou ne doit réinvalider ni l'apt ni les installeurs qui précèdent.
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
