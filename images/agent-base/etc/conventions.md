# Conventions de ce container

## Commits

**Aucune mention d'assistant dans les messages de commit** : ni
`Co-Authored-By`, ni `Claude-Session`, ni « Generated with ». L'historique dit
ce que fait le changement, pas avec quel outil il a été écrit.

## Pull requests

**Aucun retour à la ligne manuel à l'intérieur d'un paragraphe.** Un paragraphe
s'écrit sur une seule ligne, aussi longue qu'il le faut, et une ligne vide sépare
deux paragraphes. GitHub rend un saut de ligne simple comme un `<br>` : un texte
replié à 80 colonnes y ressort en lignes courtes et déchiquetées, et le défaut
survit au squash merge, où la description devient le corps du message de commit.

Les listes gardent un élément par ligne : c'est la structure du Markdown, pas un
repli. La règle ne vaut que pour ce que GitHub rend — les fichiers du dépôt
conservent le repli de leur projet.

## Publication

**Ne pousse jamais sur `main`.** Ouvre une branche, pousse-la, ouvre une pull
request. **Ne merge jamais** : l'intégration est un geste humain, fait dans
l'interface.

Ces deux règles sont tenues par la consigne, pas par le container : le jeton
présent ici permettrait de les enfreindre. C'est dit franchement pour que la
confiance porte sur ce qui la mérite.

## Méthode

L'implémentation d'un plan se fait **en subagents**, les tâches indépendantes
étant lancées dans le même message plutôt que l'une après l'autre. Voir la skill
`superpowers:subagent-driven-development`, qui porte le critère d'indépendance.
