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

## Descriptions de pull request

**Aucun retour à la ligne manuel à l'intérieur d'un paragraphe.** Un paragraphe
s'écrit sur une seule ligne, aussi longue qu'il le faut, et une ligne vide sépare
deux paragraphes. GitHub rend un saut de ligne simple comme un `<br>` : un texte
replié à 80 colonnes y ressort en lignes courtes et déchiquetées. Le défaut ne
s'arrête pas à l'affichage de la PR — la description sert de corps au message de
commit lors d'un squash merge, et le hachis y reste.

Les listes gardent bien sûr un élément par ligne : c'est la structure du
Markdown, pas un repli.

Cette règle ne vaut que pour ce qui est **rendu par GitHub** — descriptions de
PR, commentaires. Les fichiers du dépôt (`README.md`, contenu des skills, specs
et plans) conservent leur repli à ~80 colonnes : ils se lisent dans un éditeur et
se relisent en diff, où le repli aide au lieu de nuire.

## Langue

Français partout : commentaires, messages, documentation, contenu des skills et
sorties utilisateur — y compris la `description` en frontmatter des skills, où
l'écosystème pousse pourtant à l'anglais.
