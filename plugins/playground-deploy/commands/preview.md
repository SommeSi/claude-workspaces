---
allowed-tools: Bash(git *), Bash(gh *)
description: Déploie la branche courante sur playground (front + back)
disable-model-invocation: false
---

Déploie la branche courante du worktree (= dossier de travail isolé) sur `playground` (= environnement de test partagé) en fusionnant directement — sans PR, sans friction.

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

## Déploiement (à répéter pour front/ puis back/)

Pour chaque dépôt, en séquence (= l'un après l'autre, jamais en parallèle — si l'un échoue, on annule les deux) :

1. Récupère les dernières versions distantes :
   ```bash
   git -C <repo> fetch origin playground
   ```
   (`fetch` = télécharge les nouveautés du serveur sans modifier ta copie locale.)

2. Bascule sur playground et fusionne ta branche en mode "squash" (= toutes tes modifs deviennent un seul commit propre) :
   ```bash
   git -C <repo> checkout playground
   git -C <repo> merge --squash <branche>
   git -C <repo> commit -m "feat(<branche>): deploy to playground"
   ```
   - Résultat : un seul commit sur playground pour cette feature.
   - En cas de conflits (= deux versions différentes du même bout de code) : résous-les librement. Lis les fichiers en conflit, comprends l'intention, corrige, puis `git -C <repo> add .` et continue.

3. Pousse playground directement sur le serveur distant :
   ```bash
   git -C <repo> push origin playground
   ```

4. Reviens sur la branche de feature :
   ```bash
   git -C <repo> checkout <branche>
   ```

## En cas d'échec

Si un dépôt échoue à n'importe quelle étape :

1. Annule le merge en cours : `git -C <repo> merge --abort` (= remet le dépôt dans l'état d'avant le merge).
2. Reviens sur la branche de feature : `git -C <repo> checkout <branche>`.
3. Dis clairement à l'utilisateur ce qui a foiré et sur quel dépôt.
4. **N'enchaîne pas** sur l'autre dépôt (sinon front et back seraient désynchronisés).

## Résultat à afficher

```
✅ Déployé sur playground :
   - front : pushed (1 commit squashé)
   - back  : pushed (1 commit squashé)
```
