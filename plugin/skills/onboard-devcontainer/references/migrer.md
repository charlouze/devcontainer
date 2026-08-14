# Mode « migrer »

Le dépôt porte sa propre configuration de dev container. C'est le mode qui peut
détruire du travail : **rien n'est supprimé avant que le diff ait été montré et
validé.**

## 1. Extraire ce qui appartient réellement au projet

Du `devcontainer.json` existant, ne garde que :

- le nom lisible du projet ;
- les ports (`forwardPorts`, `portsAttributes`) ;
- les variables d'émulateur et l'identifiant de projet Firebase ;
- toute personnalisation d'IDE propre au projet.

Tout le reste vient désormais de l'image. En particulier, ne recopie **jamais** :

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
avec les valeurs extraites ci-dessus.

## 3. Les volumes changent de nom

C'est la conséquence à annoncer explicitement, parce qu'elle a un effet visible :

- le volume de login devient `agent-claude`, partagé entre projets. Si l'ancien
  était propre au projet, **le login de l'agent est à refaire une fois** ;
- l'ancien volume de cache reste sur le disque et n'est plus monté. Il n'est pas
  supprimé : c'est à l'humain de décider quand.

Liste les anciens volumes et donne la commande pour les retirer plus tard, sans
la lancer :

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

## 6. Terminer

Repasse la liste de contrôle finale de `SKILL.md`. Annonce qu'aucun changement
fonctionnel n'est attendu côté développeur — mêmes ports, mêmes tâches, mêmes
garde-fous — et que la première ouverture reconstruira le container.
