---
allowed-tools: Bash(git *), Bash(gh pr *), Bash(gh api *), Bash(gh run *)
description: Affiche l'état des déploiements — toutes les PR sur playground, tes PR sur develop
disable-model-invocation: false
---

Affiche l'état actuel des déploiements sur playground (= environnement de test partagé) et develop (= branche de référence du code prêt à partir en prod) pour les deux dépôts.

## Détecter le contexte

1. Repère la racine du worktree (= dossier de travail isolé). Il contient deux dépôts : `front/` (interface) et `back/` (serveur).

## Playground — Vue complète (les deux dépôts)

Pour chaque dépôt (`front/`, `back/`) :

1. Liste toutes les PR ouvertes (= Pull Requests, = propositions de modification du code) qui ciblent playground :
   ```bash
   gh pr list --base playground --state open --json number,title,author,url,createdAt,statusCheckRollup
   ```

2. Liste les PR récemment fusionnées (les 10 dernières) :
   ```bash
   gh pr list --base playground --state merged --limit 10 --json number,title,author,url,mergedAt
   ```

3. Vérifie l'état de la CI (= les tests automatiques qui vérifient que le code marche) sur la branche playground :
   ```bash
   gh run list --branch playground --limit 3 --json name,status,conclusion,createdAt
   ```

## Develop — Tes PR uniquement (les deux dépôts)

Pour chaque dépôt (`front/`, `back/`) :

1. Liste tes PR ouvertes qui ciblent develop :
   ```bash
   gh pr list --base develop --state open --author @me --json number,title,url,createdAt,statusCheckRollup,reviewDecision
   ```

2. Liste tes PR récemment fusionnées (les 5 dernières) :
   ```bash
   gh pr list --base develop --state merged --author @me --limit 5 --json number,title,url,mergedAt
   ```

## Affichage à présenter

Présente un récap clair et lisible :

```
📦 Playground
   🔵 PR ouvertes :
      - front #42 : "feat: ajout formulaire" (par alice) — CI ✅
      - back  #18 : "feat: ajout endpoint" (par alice) — CI ⏳
   ✅ Récemment fusionnées :
      - front #41 : "fix: typo" (par bob) — fusionnée il y a 2h
      - back  #17 : "fix: validation" (par bob) — fusionnée il y a 2h
   CI : ✅ Tous les tests passent

🚀 Develop (tes PR)
   🔵 Ouvertes :
      - front #39 : "chore: promote playground" — review en attente
   ✅ Fusionnées :
      - back  #15 : "chore: promote playground" — fusionnée hier
```

S'il n'y a aucune PR dans une section, écris "Aucune PR" plutôt que de laisser vide.
