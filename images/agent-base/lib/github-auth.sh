#!/usr/bin/env bash
# Connecte git au compte GitHub, si le volume porte déjà une connexion gh.
#
# Le jeton n'entre jamais par ici : la connexion est un geste humain, fait une
# fois (`gh auth login --with-token`), et le volume `agent-gh` la garde d'un
# container à l'autre. Ce script ne fait que recâbler ce qui ne persiste pas —
# ~/.gitconfig vit dans la couche inscriptible.
#
# Sort toujours en 0 : post-create.sh tourne sous `set -e`, et l'absence de
# connexion est un état normal, pas une erreur.
set -uo pipefail

warn() { printf '\033[1;33m /!\\ %s\033[0m\n' "$1" >&2; }

if ! command -v gh >/dev/null 2>&1; then
  warn "gh est introuvable : ni push ni pull request depuis cette session."
  exit 0
fi

if ! gh auth status >/dev/null 2>&1; then
  cat <<'EOF'
GitHub : non connecté. Une fois pour toutes, dans ce terminal :

    gh auth login --with-token

puis colle le jeton et Ctrl-D. Il passe par stdin, donc il n'entre pas dans
l'historique de shell — et le volume agent-gh le garde d'une recréation à
l'autre.
EOF
  exit 0
fi

# git emprunte l'authentification de gh : un seul mécanisme pour les deux
# outils, et aucune variable d'environnement dans la boucle — l'outil Bash de
# l'agent n'est ni interactif ni un shell de login, il ne lirait ni
# /etc/profile.d ni /etc/bash.bashrc.
gh auth setup-git

# Un seul appel réseau, dont on tolère l'échec : sans réseau, la connexion reste
# utilisable, seule l'identité manque. La renseigner est ce qui rend le premier
# commit possible — sans user.email, git refuse de commiter.
if utilisateur="$(gh api user 2>/dev/null)" && [ -n "$utilisateur" ]; then
  login="$(printf '%s' "$utilisateur" | jq -r '.login')"
  identifiant="$(printf '%s' "$utilisateur" | jq -r '.id')"
  nom="$(printf '%s' "$utilisateur" | jq -r '.name // .login')"

  # L'adresse noreply du compte, jamais l'adresse publique : elle suffit à ce
  # que GitHub attribue les commits, sans publier d'adresse personnelle dans
  # l'historique de tous les dépôts touchés.
  git config --global user.name "$nom"
  git config --global user.email "${identifiant}+${login}@users.noreply.github.com"
  echo "GitHub : connecté comme ${login}"
else
  warn "Connexion gh présente, mais l'API est injoignable : identité git non posée."
fi

exit 0
