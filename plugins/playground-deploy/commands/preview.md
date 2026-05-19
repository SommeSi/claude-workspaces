---
allowed-tools: Bash(git *), Bash(gh *)
description: Déploie la branche courante sur playground (front + back)
disable-model-invocation: false
---

> **Pour l'utilisateur non-technique** : tu veux voir le code que tu viens d'écrire tourner sur `playground.sommesi.com` ? Lance cette commande, c'est tout. Tu n'as **rien à faire d'autre** pendant l'exécution.
>
> - Pas besoin de comprendre git, rebase, merge, conflits.
> - Playground sert à tester **une seule feature à la fois** : ton déploiement va remplacer ce qui tournait avant (c'est voulu).
> - À la fin, playground sera **une copie exacte de ta branche locale**.

Déploie la branche courante du worktree (= dossier de travail isolé) sur `playground` (= environnement de test partagé) en forçant playground à devenir une copie exacte de ta branche — sans merge, sans PR, sans conflits possibles.

## Pré-vol (= vérifications avant déploiement)

1. Repère la racine du worktree. Il contient deux dépôts : `front/` (interface) et `back/` (serveur).
2. Pour chaque dépôt (`front/`, `back/`) :
   - Récupère le nom de la branche courante : `git -C <repo> branch --show-current`
   - Si la branche est `playground` ou `develop`, **STOP** :
     > "Tu es directement sur `<branche>`. Crée d'abord une branche de feature (= une branche dédiée à ton travail en cours)."
   - Vérifie les changements non commités : `git -C <repo> status --porcelain`
   - S'il y a des changements non commités, **fais un commit automatique silencieux** (pour ne rien perdre) :
     ```bash
     git -C <repo> add -A
     git -C <repo> commit -m "wip: auto-commit before playground deploy"
     ```
     Préviens brièvement l'utilisateur : `"Auto-commit dans <repo>."`

## Calculer le "scope" normalisé pour le message de commit

Le hook conventional commit du backend refuse les `/` et les préfixes `feat/`, `fix/`, etc. dans le scope. On normalise donc le nom de la branche avant de l'utiliser :

```bash
SCOPE=$(echo "<branche>" | sed -E 's|^(feat|fix|chore|refactor|docs|test|perf|build|ci|style|revert)/||; s|/|-|g')
```

Exemples :
- `feat/polo-offshore-folders` → `polo-offshore-folders`
- `fix/auth/redirect-loop` → `auth-redirect-loop`
- `chore/cleanup` → `cleanup`
- `wip-stuff` → `wip-stuff` (rien à normaliser)

## Pré-flight diff résumé (informatif, non bloquant)

Pour chaque dépôt, calcule l'écart entre la branche locale et `develop` :

```bash
git -C <repo> fetch origin develop
DIFF_COUNT=$(git -C <repo> diff --name-only origin/develop..<branche> | wc -l | tr -d ' ')
```

Affiche à l'utilisateur **avant** de pousser :

```
🚀 Playground va devenir une copie exacte de ta branche `<branche>` :
   - front : <DIFF_COUNT> fichiers diffèrent de develop
   - back  : <DIFF_COUNT> fichiers diffèrent de develop

(Ce qui tournait avant sur playground sera remplacé — c'est normal en mono-feature.)
```

Pas de demande de confirmation : on continue automatiquement.

## Déploiement (à répéter pour front/ puis back/)

Pour chaque dépôt, en séquence (= l'un après l'autre, jamais en parallèle — si l'un échoue, on annule les deux) :

1. Récupère les dernières versions distantes :
   ```bash
   git -C <repo> fetch origin develop playground
   ```
   (`fetch` = télécharge les nouveautés du serveur sans modifier ta copie locale.)

2. Stratégie "playground = ma branche, en un commit propre" — **on n'utilise plus `merge`** (qui peut générer des conflits). On utilise `reset`, qui ne peut **jamais** produire de conflit :

   ```bash
   # a. Basculer sur playground.
   git -C <repo> checkout playground

   # b. Forcer playground à pointer exactement sur le contenu de ta branche.
   git -C <repo> reset --hard <branche>

   # c. Garder ce contenu mais ramener l'historique au niveau de develop
   #    (toutes tes modifs deviennent un seul "paquet" prêt à être commité).
   git -C <repo> reset --soft origin/develop

   # d. Créer un commit unique et propre avec le scope normalisé.
   #    --allow-empty couvre le cas où ta branche est identique à develop.
   git -C <repo> commit --allow-empty -m "feat($SCOPE): deploy to playground"
   ```

   - **Aucun conflit possible** : on n'a pas mergé, on a remplacé.
   - Un seul commit propre sur playground, scope normalisé, accepté par le hook conventional.

3. Pousse playground sur le serveur distant (force sécurisée — playground sert à ça) :
   ```bash
   git -C <repo> push --force-with-lease origin playground
   ```
   (`--force-with-lease` = écrase la branche distante seulement si personne n'a poussé entre-temps — plus sûr qu'un `--force` brutal.)

4. Reviens sur la branche de feature :
   ```bash
   git -C <repo> checkout <branche>
   ```

## En cas d'échec

Si un dépôt échoue à n'importe quelle étape :

1. Reviens sur la branche de feature : `git -C <repo> checkout <branche>`.
2. Dis clairement à l'utilisateur ce qui a foiré et sur quel dépôt — en langage simple, sans jargon git.
3. **N'enchaîne pas** sur l'autre dépôt (sinon front et back seraient désynchronisés).

## Résultat à afficher

Adapte selon ce qui a vraiment été déployé :

```
✅ Playground tourne maintenant ta branche `<branche>` :
   - front : déployé (1 commit propre sur playground)
   - back  : déployé (1 commit propre sur playground)

🌐 Va tester sur https://playground.sommesi.com
```

Si un seul des deux dépôts avait des changements, mentionne-le explicitement :

```
✅ Playground mis à jour :
   - front : déployé
   - back  : aucun changement par rapport à develop (skip)
```
