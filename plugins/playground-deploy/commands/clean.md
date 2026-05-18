---
allowed-tools: Bash(git *), Bash(gh *)
description: Réinitialise playground pour qu'elle redevienne une copie exacte de develop
disable-model-invocation: false
---

Remet à zéro la branche `playground` (l'environnement de test partagé) pour qu'elle redevienne identique à `develop` (la branche de référence du code prêt à partir en prod). Toutes les features actuellement déployées sur playground seront effacées de playground (mais restent intactes sur leurs branches de feature).

⚠️ **Action destructive** (= on écrase l'historique de playground). Demande confirmation à l'utilisateur avant d'exécuter.

## Étape 1 — Détecter le contexte

1. Repère la racine du worktree (= dossier de travail isolé). Le worktree contient deux dépôts : `front/` (le code de l'interface) et `back/` (le code du serveur).
2. Pour chaque dépôt, retiens la branche courante : `git -C <repo> branch --show-current` (= la branche sur laquelle tu es actuellement).

## Étape 2 — Confirmer avec l'utilisateur

Avant de toucher à quoi que ce soit, affiche un avertissement clair :

> ⚠️ Tu es sur le point de **réinitialiser playground** sur les deux dépôts (`front/` et `back/`).
>
> Concrètement :
> - La branche `playground` va être écrasée et remplacée par une copie exacte de `develop`.
> - Toutes les features actuellement déployées sur playground (et non encore mergées sur develop) **disparaîtront de playground**.
> - Leurs branches de feature ne sont pas touchées, donc rien n'est perdu : il suffira de relancer `/playground-deploy:preview` pour les redéployer.
>
> Tu es sûr de vouloir continuer ?

Si l'utilisateur dit non → on arrête tout.

## Étape 3 — Auto-commit si changements en cours

Pour chaque dépôt (`front/`, `back/`) :

1. Vérifie s'il y a des changements non commités : `git -C <repo> status --porcelain` (= liste compacte des fichiers modifiés).
2. S'il y en a, fais un commit automatique silencieux pour ne rien perdre :
   ```bash
   git -C <repo> add -A
   git -C <repo> commit -m "wip: auto-commit before playground clean"
   ```
   Informe brièvement : `"Auto-commit dans <repo> pour sauver tes changements en cours."`

## Étape 4 — Réinitialiser playground (pour chaque dépôt)

Pour chaque dépôt, en séquence (= un après l'autre, pas en parallèle, pour pouvoir arrêter proprement si l'un échoue) :

1. Récupère les dernières versions distantes de develop et playground :
   ```bash
   git -C <repo> fetch origin develop playground
   ```
   (`fetch` = télécharge les nouveautés du dépôt distant sans modifier ta copie locale.)

2. Bascule sur playground :
   ```bash
   git -C <repo> checkout playground
   ```
   (`checkout` = "passer sur" une branche.)

3. Force playground à être identique à develop :
   ```bash
   git -C <repo> reset --hard origin/develop
   ```
   (`reset --hard` = remplace complètement la branche locale par celle indiquée, sans rien préserver.)

4. Pousse cette nouvelle version sur le serveur distant en écrasant l'historique précédent :
   ```bash
   git -C <repo> push --force-with-lease origin playground
   ```
   (`push --force-with-lease` = écrase la branche distante, mais seulement si personne d'autre n'a poussé entre-temps — plus sûr qu'un `--force` brutal.)

5. Reviens sur la branche d'origine de l'utilisateur :
   ```bash
   git -C <repo> checkout <branche_originale>
   ```

## En cas d'échec

Si un dépôt plante à une étape :

1. Reviens sur la branche d'origine : `git -C <repo> checkout <branche_originale>`.
2. Explique clairement à l'utilisateur ce qui a foiré et sur quel dépôt.
3. **N'enchaîne pas** sur l'autre dépôt — laisse-le tel quel pour éviter d'avoir un front et un back désynchronisés.

## Résultat à afficher

```
🧹 Playground réinitialisée (= copie exacte de develop) :
   - front : ✅ remise à zéro
   - back  : ✅ remise à zéro

ℹ️  Les features qui étaient sur playground ne sont pas perdues : elles existent toujours sur leurs branches.
   Pour en redéployer une, va sur le worktree concerné et lance /playground-deploy:preview.
```
