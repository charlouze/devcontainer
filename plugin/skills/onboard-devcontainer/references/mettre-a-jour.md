# Mode « mettre à jour »

Le dépôt est déjà branché sur les images du dépôt. C'est le mode le plus
fréquent dans la durée : quand la base passe une majeure, il faut repasser sur
chaque projet.

## 1. Le tag

Le tag de référence est celui de `references/devcontainer.template.json`, et
lui seul. Le plugin est versionné avec les images : ce tag existe forcément,
celui que tu inventerais, non.

- même majeure que le fichier du dépôt, et déjà sur le tag flottant (`…:1`,
  pas `…:1.x.y`) → rien à changer dans le fichier ;
- même majeure mais tag figé (`…:1.x.y`) → réaligne sur le tag flottant du
  template : l'invariant `image-tag` de la liste de contrôle finale refuse un
  tag figé, un projet doit suivre les correctifs ;
- majeure supérieure → aligne le fichier, et **annonce-le comme un changement de
  majeure** : dis ce qui change, et propose de lire les notes de version plutôt
  que de faire le saut à l'aveugle.

Le fichier réglé, l'image du poste ne l'est pas pour autant. **Docker ne
re-télécharge pas un tag dont il détient déjà une copie locale** : le container
se recrée sur l'ancienne image, sans qu'aucun message ne le signale. C'est le
cas le plus fréquent — même majeure, tag flottant inchangé, et pourtant tout le
travail de mise à jour reste sans effet.

Propose donc le rafraîchissement, et ne le lance qu'une fois validé. Le gate du
§3 vaut ici aussi, en l'étendant de ce qu'on écrit à ce qu'on exécute :

```bash
docker pull ghcr.io/charlouze/devcontainer-web:1
```

Le tag est celui du fichier du dépôt, `-web` ou `-agent-base` selon le projet.

Si `docker` est injoignable, **ne conclus pas que c'est réglé** : c'est ce qui
arrive quand tu tournes dans le container, dont le garde-fou refuse le socket
Docker par construction. Dis-le, et donne la commande à lancer sur l'hôte — tu
ne peux pas la faire à sa place.

## 2. Les écarts avec le template

Compare le fichier du dépôt au template, clé par clé, et **rapporte** :

- une clé du template absente du fichier — typiquement un montage ajouté depuis
  la dernière fois ;
- une clé du template dont la valeur diffère **sans raison propre au projet** :
  `containerUser`, `remoteUser`, `postCreateCommand`, `runArgs`, et les sources
  des volumes partagés `agent-*` ;
- les commentaires du template qui manquent ;
- **tout port publié** : un `forwardPorts` ou un `appPort` non vide, une entrée
  de `portsAttributes`, ou un `otherPortsAttributes` qui ne vaut pas
  `{ "onAutoForward": "ignore" }`. C'est l'écart le plus courant sur un projet
  branché avant cette règle — il date d'une époque où le template publiait
  quatre ports, et c'est exactement ce qui empêche deux containers de tourner
  ensemble et prend les ports de ce qu'on lance sur le poste.

Ne rapporte pas comme écart ce qui appartient légitimement au projet : `name`,
`containerEnv`, les sources de volumes préfixées par le slug, les
personnalisations d'IDE.

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
- Si `firebase.json` ou `.firebaserc` existe, relis-les avec les règles de
  lecture du mode « brancher » §1, et corrige les variables d'émulateur de
  `containerEnv` et l'identifiant de projet — **en retrait comme en ajout**. Un
  émulateur apparu depuis le branchement gagne sa variable ; un émulateur retiré
  de `firebase.json` perd la sienne ; un port déplacé se corrige à la nouvelle
  valeur dans la variable ; un `demo-<slug>` posé faute de mieux au mode
  « amorcer » se remplace par le véritable identifiant dès que `.firebaserc` en
  fournit un. C'est la seule exception à la règle du §2 qui laisse `containerEnv`
  au projet : elle ne vaut que pour ce que `firebase.json` ou `.firebaserc`
  disent explicitement, et seulement quand l'un des deux existe — en leur
  absence, rien ne change.
- Si `.devcontainer/` contient encore un `Dockerfile`, un `post-create.sh`, un
  `agent-guard.cjs` ou un `managed-settings.json`, le dépôt est en fait à moitié
  migré : bascule sur `references/migrer.md` et dis-le.

## 5. Terminer

Repasse la liste de contrôle finale de `SKILL.md`. Si le tag a changé de majeure,
rappelle que la prochaine ouverture reconstruira le container.

Et dès qu'une image a été rafraîchie au §1, dis qu'il faut **recréer** le
container pour en profiter : un `pull` seul ne change rien, celui qui tourne
reste sur l'image avec laquelle il a été créé.

Enchaîne sur `references/github.md` : le montage `agent-gh` ne sert à rien tant
que la connexion `gh` n'a pas été faite une fois dans le container.
