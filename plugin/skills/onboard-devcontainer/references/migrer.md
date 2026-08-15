# Mode « migrer »

Le dépôt porte sa propre configuration de dev container. C'est le mode qui peut
détruire du travail : **rien n'est supprimé avant que le diff ait été montré et
validé.**

## 1. Extraire ce qui appartient réellement au projet

Du `devcontainer.json` existant, ne garde que :

- le nom lisible du projet — le champ `name` de l'ancien fichier, débarrassé de
  son suffixe ` (agent sandbox)` : le template le réinjecte, le garder
  produirait un doublon. C'est cette source qui prime dans ce mode, et non la
  règle générale de `SKILL.md` (`package.json`, à défaut le nom du
  répertoire) : l'ancien fichier est ce que le projet a déjà choisi comme nom
  lisible, ne le redérive pas d'ailleurs ;
- les ports (`forwardPorts`, `portsAttributes`) ;
- les variables d'émulateur et l'identifiant de projet Firebase ;
- toute personnalisation d'IDE propre au projet.

Tout le reste vient désormais de l'image — à l'exception d'une variable
d'environnement propre au projet et sans rapport avec Firebase ou le
garde-fou (une clé d'API tierce, par exemple) : celle-là n'a pas d'équivalent
dans l'image, elle se garde. En particulier, ne recopie **jamais** :

- une variable qui prétendait activer le garde-fou (`CDF_SANDBOX` et
  apparentées) — il s'active maintenant sur `/etc/claude-guard/enabled`, root et
  non falsifiable, et la variable n'aurait plus aucun effet ;
- un `build`/`dockerFile` — l'image remplace le Dockerfile ;
- un `postCreateCommand` pointant dans le workspace ;
- des `runArgs` supplémentaires : le parser d'IntelliJ échoue sur ce qu'il ne
  connaît pas, et le template porte déjà ce qu'il faut.

Si l'ancien fichier portait un réglage que tu ne sais pas classer, **demande**
plutôt que de trancher.

## 2. Écrire la version courte

Pars de `references/devcontainer.template.json` comme au mode « brancher »,
avec les valeurs extraites ci-dessus. Le `devcontainer.json` existant est
écrasé : montre le diff proposé et attends la validation avant d'écrire,
exactement comme pour les suppressions de l'étape 4 — le gate des règles
communes de `SKILL.md` s'applique à tout ce qui écrase du contenu existant, pas
seulement à ce qui supprime des fichiers.

## 3. Les volumes changent de nom

C'est la conséquence à annoncer explicitement, parce qu'elle a un effet visible :

- le volume de login devient `agent-claude`, partagé entre projets. Si l'ancien
  était propre au projet, **le login de l'agent est à refaire une fois** ;
- l'ancien volume de cache reste sur le disque et n'est plus monté. Il n'est pas
  supprimé : c'est à l'humain de décider quand.

Liste les anciens volumes et donne la commande pour les retirer plus tard, sans
la lancer. `<ancien-prefixe>` est le préfixe commun aux anciennes sources de
`mounts` — par exemple `cdf` si l'ancien fichier montait
`cdf-agent-claude` et `cdf-agent-cache` :

```bash
docker volume ls --filter name=<ancien-prefixe>
docker volume rm <volume>
```

## 4. Signaler les fichiers devenus inutiles

L'image fournit désormais le Dockerfile, le provisionnement, le garde-fou et ses
managed settings. Dans `.devcontainer/`, deviennent inutiles :

- `Dockerfile`
- `post-create.sh`
- `agent-guard.cjs` (et tout module de règles qui l'accompagne)
- `managed-settings.json`

Montre la liste, montre le diff, demande. Ne supprime que ce qui a été validé.
Si l'un de ces fichiers contenait des règles de garde-fou propres au projet,
elles ne se perdent pas : elles se réécrivent en
`.devcontainer/guard-rules.json`, qui **ajoute** au socle.

```json
{
  "bash":  [{ "pattern": "\\bstripe\\s+", "flags": "i", "reason": "…" }],
  "paths": [{ "pattern": "fixtures/prod-.*\\.json$", "reason": "…" }]
}
```

Un `README.md` de `.devcontainer/` se réduit à ce qui est propre au projet, le
reste renvoyant à `https://github.com/charlouze/devcontainer`.

## 5. La tâche `setup`

Comme au mode « brancher » : ce que faisait l'ancien `post-create.sh` **au titre
du projet** — et lui seul — devient la tâche `setup` du `mise.toml`. Ce qu'il
faisait au titre de l'environnement (mise, pnpm, plugins, réglages de l'agent)
est déjà fait par l'image : ne le recopie pas.

Si le dépôt n'a pas de `package.json`, la présence de `@playwright/test` n'est
pas vérifiable : n'ajoute pas la ligne Playwright plutôt que de deviner.

## 6. Terminer

Repasse la liste de contrôle finale de `SKILL.md`. Annonce qu'aucun changement
fonctionnel n'est attendu côté développeur — mêmes ports, mêmes tâches, mêmes
garde-fous — et que la première ouverture reconstruira le container.

Dis-lui aussi que **le workspace, à partir de cette reconstruction, vivra dans
un volume Docker et pas sur le disque de l'hôte** — c'est justement le
changement que l'étape 3 vient d'annoncer sur le nom des volumes. Et qu'il **ne
survivra pas aux recréations suivantes** : JetBrains re-clone depuis le distant
dans un volume de sources neuf, donc ce qui n'a pas été poussé disparaît, sur un
rebuild réussi comme sur un accident. C'est un changement d'habitude à annoncer
franchement quand le dépôt travaillait jusque-là sur le disque de l'hôte, où
rien ne se perdait à reconstruire. Le garde-fou bloque `git push origin main`,
pas le push d'une branche : c'est désormais ce qui met le travail à l'abri.

Enchaîne sur `references/github.md` : le montage `agent-gh` ne sert à rien tant
que la connexion `gh` n'a pas été faite une fois dans le container.
