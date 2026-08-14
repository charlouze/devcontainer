# Mode « mettre à jour »

Le dépôt est déjà branché sur les images du dépôt. C'est le mode le plus
fréquent dans la durée : quand la base passe une majeure, il faut repasser sur
chaque projet.

## 1. Le tag

Le tag de référence est celui de `references/devcontainer.template.json`, et
lui seul. Le plugin est versionné avec les images : ce tag existe forcément,
celui que tu inventerais, non.

- même majeure que le fichier du dépôt → rien à faire côté tag ;
- majeure supérieure → aligne le fichier, et **annonce-le comme un changement de
  majeure** : dis ce qui change, et propose de lire les notes de version plutôt
  que de faire le saut à l'aveugle.

## 2. Les écarts avec le template

Compare le fichier du dépôt au template, clé par clé, et **rapporte** :

- une clé du template absente du fichier — typiquement un montage ajouté depuis
  la dernière fois ;
- une clé du template dont la valeur diffère **sans raison propre au projet** :
  `containerUser`, `remoteUser`, `postCreateCommand`, `runArgs`, et les sources
  des volumes partagés `agent-*` ;
- les commentaires du template qui manquent ;
- un port de `forwardPorts` sans libellé.

Ne rapporte pas comme écart ce qui appartient légitimement au projet : `name`,
`containerEnv`, la liste des ports, les sources de volumes préfixées par le
slug, les personnalisations d'IDE.

## 3. Corriger

Montre le diff des corrections proposées, demande, et n'écris que ce qui a été
validé : ce mode écrase des clés d'un fichier existant, le gate des règles
communes de `SKILL.md` s'applique. Vaut pour tout, y compris les écarts de
durcissement — un `devcontainer.json` qui a perdu `no-new-privileges` ou
`--cap-drop ALL` n'est pas une variante locale, c'est une régression, mais elle
se montre et se fait valider comme le reste avant d'être corrigée.

## 4. Le reste du dépôt

- Si le `mise.toml` n'a pas de tâche `setup`, ajoute-la comme au mode
  « brancher ». Si elle existe, **n'y touche pas** : c'est le projet qui la tient.
- Si des émulateurs ont été ajoutés au `firebase.json` depuis le branchement,
  leurs ports et variables manquent probablement : applique les mêmes règles de
  lecture qu'au mode « brancher ».
- Si `.devcontainer/` contient encore un `Dockerfile`, un `post-create.sh`, un
  `agent-guard.cjs` ou un `managed-settings.json`, le dépôt est en fait à moitié
  migré : bascule sur `references/migrer.md` et dis-le.

## 5. Terminer

Repasse la liste de contrôle finale de `SKILL.md`. Si le tag a changé de majeure,
rappelle que la prochaine ouverture reconstruira le container.
