# Conventions du dépôt

## Git

**Ne travaille jamais directement sur `main`.** Crée une branche avant la
première modification — pas au moment de committer, où il est déjà trop tard
pour que la relecture ait lieu ailleurs que sur la branche par défaut. Le dépôt
utilise des worktrees (`.claude/worktrees/`, ignoré par git) ; la skill
`superpowers:using-git-worktrees` en pose un correctement.

L'intégration se fait ensuite par pull request.

Messages de commit : **en français**, descriptifs, **sans préfixe conventionnel**
(`feat:`, `docs:`, `chore:`…) — ce n'est pas l'usage ici. **Aucune mention
d'assistant** : ni `Co-Authored-By`, ni `Claude-Session`, ni « Generated with ».

## Langue

Français partout : commentaires, messages, documentation, contenu des skills et
sorties utilisateur — y compris la `description` en frontmatter des skills, où
l'écosystème pousse pourtant à l'anglais.
