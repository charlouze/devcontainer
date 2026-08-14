# Historique bash persistant. Sourcé depuis /etc/profile.d et /etc/bash.bashrc.
[ -n "${DEVCONTAINER_HISTORY_LOADED:-}" ] && return
DEVCONTAINER_HISTORY_LOADED=1

export HISTFILE=/home/dev/.history/bash_history
export HISTSIZE=100000
export HISTFILESIZE=200000
# ignoreboth plutôt qu'erasedups : la déduplication rétroactive réécrit la liste
# en mémoire alors que `history -a` ne pousse que les nouvelles lignes, et les
# deux ensemble finissent par perdre des entrées.
export HISTCONTROL=ignoreboth

# histappend empêche qu'un shell qui se ferme tronque ce que les autres ont
# écrit.
shopt -s histappend

# `history -a` après chaque commande, et non à la sortie du shell : un rebuild
# de container tue les processus sans passer par la terminaison normale de bash
# — c'est précisément le cas à couvrir, et celui où l'écriture différée perd
# tout.
PROMPT_COMMAND="history -a${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
