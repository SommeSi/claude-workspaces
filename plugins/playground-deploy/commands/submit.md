---
allowed-tools: Bash(git *), Bash(gh pr *), Bash(gh api *), Bash(gh pr checks *), Bash(gh run *)
description: Promeut playground vers develop avec code review et vérification CI (front + back)
disable-model-invocation: false
---

Promeut `playground` (= environnement de test partagé) vers `develop` (= branche de référence du code prêt pour la prod) en créant des PR (= Pull Requests, propositions de modification). Un seul commit squashé (= compressé en un seul) par feature, identifié par le nom de la branche du worktree. C'est develop qui fait foi (= la source de vérité du code).

## Détecter le nom de la feature

1. Récupère le nom de la branche courante du worktree :
   ```bash
   git -C <repo> branch --show-current
   ```
2. Si c'est une branche de feature (ex. `feat/demo-playground`), utilise-la comme nom de feature dans les messages de commit.
3. Si la branche est `playground` ou `develop` (pas de worktree / pas sur une branche de feature), utilise un nom générique : `promote-playground`.

## Pré-vol (= vérifications) sur les deux dépôts

Pour chaque dépôt (`front/`, `back/`) :

1. Vérifie l'état de la CI (= les tests automatiques) sur la branche playground :
   ```bash
   gh run list --branch playground --limit 1 --json status,conclusion,name
   ```
   - Si la CI n'est pas verte (`conclusion != "success"`), **STOP** :
     > "La CI n'est pas verte sur playground. Voici les tests en échec :"
     > (lister les checks qui plantent)

## Code Review (= relecture automatique du code)

Avant de créer les PR, fais une code review du diff (= des différences) entre `playground` et `develop` :

1. Pour chaque dépôt, récupère le diff :
   ```bash
   git -C <repo> fetch origin develop playground
   git -C <repo> diff origin/develop..origin/playground
   ```

2. Fais relire le diff par un agent Sonnet. L'agent doit :
   - Repérer les bugs évidents, les soucis de sécurité, les erreurs de logique.
   - Signaler tout ce qui paraît risqué pour la production.
   - Rester concis et actionnable.

3. Présente la review à l'utilisateur :
   > "Voici la review avant de promouvoir sur develop :"
   > (résultats de la review)

4. Demande à l'utilisateur :
   > "Tu veux continuer avec la PR vers develop ?"
   - Si non → on arrête.

## Promotion (à répéter pour front/ puis back/)

Pour chaque dépôt, en séquence (= un après l'autre — si l'un échoue, on annule les deux) :

1. Récupère les dernières versions distantes :
   ```bash
   git -C <repo> fetch origin develop playground
   ```

2. Crée une branche locale à partir de playground :
   ```bash
   git -C <repo> checkout -B promote/<nom-feature> origin/playground
   ```
   (`checkout -B` = crée ou réinitialise une branche.)

3. Compresse tous les commits en un seul par-dessus develop :
   ```bash
   git -C <repo> reset --soft origin/develop
   git -C <repo> commit -m "feat(<nom-feature>): promote to develop"
   ```
   - Résultat : un seul commit propre qui contient toutes les modifs playground pour cette feature.
   - S'il n'y a rien à commiter (playground == develop), saute ce dépôt.
   - Si le `reset` échoue, retombe sur un `rebase` :
     ```bash
     git -C <repo> rebase origin/develop
     ```
     - Si la résolution est trop complexe (plus de 3 fichiers en conflit, ou logique ambiguë), **STOP** :
       > "Le rebase a des conflits trop complexes dans `<repo>`. Demande à un dev de t'aider. Fichiers en conflit : <liste>"
     - Puis annule : `git -C <repo> rebase --abort`

4. Pousse sur le serveur distant (force sécurisée) :
   ```bash
   git -C <repo> push --force-with-lease origin promote/<nom-feature>
   ```

5. Crée la PR :
   ```bash
   gh pr create --base develop --head promote/<nom-feature> --title "feat(<nom-feature>): promote to develop" --body "<body>"
   ```
   - **Body** (= description de la PR) : inclure le résumé de la code review + la liste des changements. Termine par :
     ```
     ✅ CI verte sur playground
     ✅ Code review passée

     🤖 Promoted with [Playground Deploy](https://github.com/sommesi/playground-deploy)
     ```

6. Reviens sur la branche de feature :
   ```bash
   git -C <repo> checkout <branche-originale>
   ```

## En cas d'échec

Si un dépôt échoue :
1. Annule le rebase en cours : `git -C <repo> rebase --abort`.
2. Nettoie la branche de promotion : `git -C <repo> checkout <branche-originale> && git -C <repo> branch -D promote/<nom-feature>`.
3. Dis clairement à l'utilisateur ce qui a foiré.
4. **N'enchaîne pas** sur l'autre dépôt (sinon front et back seraient désynchronisés).

## Résultat à afficher

```
✅ PR créées sur develop :
   - front : <URL_PR>
   - back  : <URL_PR>

📋 Résumé de la review :
   <résumé bref de la review>
```
