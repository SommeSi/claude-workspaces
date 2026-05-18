---
allowed-tools: Bash(git *), Bash(gh *)
description: Met à jour playground depuis develop, et éventuellement ta branche aussi
disable-model-invocation: false
---

Met à jour `playground` (= environnement de test partagé) à partir de `develop` (= branche de référence du code prêt pour la prod), puis propose de mettre à jour la branche courante.

## Détecter le contexte

1. Repère la racine du worktree (= dossier de travail isolé). Il contient deux dépôts : `front/` (interface) et `back/` (serveur).
2. Pour chaque dépôt, récupère la branche courante : `git -C <repo> branch --show-current`
3. Vérifie s'il y a des changements non commités : `git -C <repo> status --porcelain`
   - Si oui, **fais un commit automatique silencieux** (pour ne rien perdre) :
     ```bash
     git -C <repo> add -A
     git -C <repo> commit -m "wip: auto-commit before playground sync"
     ```
     Préviens brièvement : `"Auto-commit dans <repo>."`

## Étape 1 — Mettre playground à jour depuis develop (toujours)

Pour chaque dépôt (`front/`, `back/`) :

1. Récupère les dernières versions distantes :
   ```bash
   git -C <repo> fetch origin develop playground
   ```
   (`fetch` = télécharge les nouveautés du serveur sans toucher à ta copie locale.)

2. Compte le nombre de commits que playground a de retard sur develop :
   ```bash
   git -C <repo> rev-list --count origin/playground..origin/develop
   ```
   - Si 0 : playground est déjà à jour, on saute ce dépôt.

3. Bascule sur playground et rejoue les commits de playground par-dessus develop (= rebase) :
   ```bash
   git -C <repo> checkout playground
   git -C <repo> rebase origin/develop
   ```
   - En cas de conflits : résous-les librement.

4. Pousse sur le serveur distant en écrasant la version précédente (de façon sécurisée) :
   ```bash
   git -C <repo> push --force-with-lease origin playground
   ```
   (`--force-with-lease` = écrase la branche distante seulement si personne d'autre n'a poussé entre-temps — plus sûr qu'un `--force` brutal.)

5. Reviens sur la branche d'origine :
   ```bash
   git -C <repo> checkout <branche_originale>
   ```

Rapport à afficher :
```
🔄 Playground mise à jour :
   - front : +N commits depuis develop
   - back  : déjà à jour
```

## Étape 2 — Mettre à jour la branche courante (demander avant)

Demande à l'utilisateur :
> "Tu veux aussi mettre ta branche `<branche>` à jour par rapport à playground ?"

Si oui, pour chaque dépôt :

1. Rejoue ta branche par-dessus la playground mise à jour :
   ```bash
   git -C <repo> rebase origin/playground
   ```
   - En cas de conflits : résous-les librement.

2. Pousse ta branche (force sécurisée) :
   ```bash
   git -C <repo> push --force-with-lease origin <branche>
   ```

Rapport :
```
✅ Branche `<branche>` à jour :
   - front : rebasée sur playground
   - back  : rebasée sur playground
```

Si non, dis :
> "OK, playground est à jour. Ta branche reste en l'état."
