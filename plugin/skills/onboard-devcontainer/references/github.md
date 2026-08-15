# Credentials GitHub

À faire une fois par poste, quel que soit le mode. Le container peut pousser des
branches et ouvrir des pull requests ; il ne merge pas.

## 1. Le jeton

Un **PAT fine-grained**, créé sur github.com, à dépôts sélectionnés :

| Permission | Niveau | Pourquoi |
|---|---|---|
| Contents | lecture/écriture | pousser une branche |
| Pull requests | lecture/écriture | ouvrir et modifier une PR |
| Metadata | lecture | exigée par les deux précédentes |

**Ni `Administration`, ni `Workflows`.** Ce n'est pas une précaution
décorative : sans `Workflows`, GitHub refuse lui-même tout push qui touche
`.github/workflows/`, ce qui est la seule barrière réellement structurelle de ce
dispositif. Sans `Administration`, le jeton ne peut pas défaire la ruleset du §3
ni changer les réglages du dépôt.

Le PAT est partagé par tous les containers, comme le volume de login. Un
container peut donc pousser sur tous les dépôts qu'il couvre : c'est le
prolongement de la portée déjà admise pour `.claude.json`, à dire à l'humain
plutôt qu'à laisser découvrir.

## 2. La connexion

Elle se fait **dans le container**, une fois, à la main :

```bash
gh auth login --with-token
```

puis coller le jeton et Ctrl-D. Le jeton passe par stdin : il n'apparaît dans
aucune ligne de commande, donc pas dans l'historique de shell — qui est
persistant ici. Le volume `agent-gh` garde la connexion d'une recréation à
l'autre ; le provisionnement suivant recâble git tout seul.

Tu ne peux pas la faire à la place de l'humain : le jeton ne doit pas transiter
par une commande que tu composes.

## 3. La ruleset, si GitHub l'accepte

À lancer **depuis le poste**, avec le `gh` de l'humain : créer une ruleset
demande la permission `Administration`, que le PAT du container n'a pas — et ne
doit pas avoir.

Vérifier d'abord ce qui existe, pour ne pas écraser :

```bash
gh api repos/{owner}/{repo}/rulesets --jq '.[].name'
```

Si aucune ne porte ce nom, la créer :

```bash
gh api --method POST repos/{owner}/{repo}/rulesets --input - <<'JSON'
{ "name": "main protégée", "target": "branch", "enforcement": "active",
  "conditions": { "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] } },
  "bypass_actors": [],
  "rules": [ {"type": "pull_request", "parameters": {"required_approving_review_count": 0}},
             {"type": "deletion"}, {"type": "non_fast_forward"} ] }
JSON
```

`bypass_actors` reste **vide**, y compris du rôle administrateur : le PAT agit au
nom de son propriétaire, donc un bypass accordé à ce rôle serait hérité par le
container et la ruleset ne protégerait plus rien. Conséquence à annoncer :
l'humain non plus ne pousse plus sur `main`, et publie par PR.

Si une ruleset du même nom existe déjà mais diffère, **signale-la sans la
modifier** : elle peut avoir été réglée à la main.

Si GitHub refuse — plan, permission, dépôt privé — dis-le et continue. Ce n'est
pas un prérequis du branchement : c'est un renfort gratuit là où il est
disponible.

## 4. Ce qu'il faut dire à l'humain

Que « pas de push sur `main` » et « pas de merge » sont tenus par le garde-fou et
par les conventions du container, **pas par construction** : le jeton présent
dans la session permettrait de les enfreindre en appelant l'API directement. Les
seules garanties dures sont la portée du PAT et les deux permissions non
accordées.
