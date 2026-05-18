---
allowed-tools: Bash(git *), Bash(gh *)
description: Analyse les changements de la feature et guide pas-à-pas la configuration playground via Avo
disable-model-invocation: false
---

Analyse ce que la feature courante modifie, puis guide l'utilisateur pas à pas pour configurer playground (= environnement de test partagé) afin que la feature marche avec de vraies données.

**URL Avo playground** (Avo = l'interface d'administration en ligne) : `https://api.playground.sommesi.com/admin`

## Étape 1 — Analyser les changements de la feature

1. Repère la racine du worktree (= dossier de travail isolé). Il contient deux dépôts : `front/` (interface) et `back/` (serveur).
2. Récupère le nom de la branche de feature : `git -C <repo> branch --show-current`
3. Récupère le diff complet (= les différences) entre la branche de feature et develop côté backend :
   ```bash
   git -C back/ fetch origin develop
   git -C back/ diff origin/develop..HEAD --stat
   git -C back/ diff origin/develop..HEAD
   ```
4. Regarde aussi le diff côté frontend pour le contexte (quelles pages/composants ont été ajoutés) :
   ```bash
   git -C front/ fetch origin develop
   git -C front/ diff origin/develop..HEAD --stat
   ```

## Étape 2 — Lire le code existant pour le contexte

Avant de générer la checklist, lis les fichiers pertinents pour comprendre le modèle de données :

1. **Nouvelles migrations** (= scripts qui modifient la structure de la base de données) : lis tous les nouveaux fichiers de migration pour comprendre le schéma.
2. **Nouveaux modèles** (= classes qui représentent une table en base) : lis-les pour comprendre les validations, associations, scopes.
3. **Seeds existants** (= données initiales préchargées) : regarde `db/seeds/` pour comprendre ce qui existe déjà.
4. **Routes** : regarde `config/routes/` pour savoir quels endpoints (= points d'entrée de l'API) existent.
5. **Resources Avo** : regarde `app/avo/resources/` pour savoir quels modèles ont un panneau d'admin dans Avo.
6. **Configuration de feature** : repère les références à `FeatureSubscription`, `FeatureConfiguration`, `ConfigurationLink` dans le diff.

## Étape 3 — Générer la checklist de configuration

Présente à l'utilisateur une checklist numérotée et claire, **en français**. Regroupe par priorité :

### Priorité 1 — Activation de la feature (si nécessaire)

Si la feature référence un nouveau slug de feature (= identifiant court) :

```
1. **Activer la feature "<feature_slug>" pour ton organisation**
   → Va sur https://api.playground.sommesi.com/admin/resources/feature_subscriptions/new
   → Sélectionne ton organisation
   → Sélectionne la feature "<feature_slug>"
   → Clique sur "Create"
```

### Priorité 2 — Configuration requise

Si la feature a besoin de `FeatureConfiguration`, `ConfigurationLink`, ou d'identifiants d'API :

```
2. **Créer la configuration <nom>**
   → Va sur https://api.playground.sommesi.com/admin/resources/<resource>/new
   → Renseigne les champs : <liste des champs spécifiques tirés de la migration>
   → C'est nécessaire parce que <raison tirée de l'analyse du code>
```

### Priorité 3 — Données de démonstration

Si la feature introduit de nouveaux modèles avec des pages qui affichent des données :

```
3. **Créer des données de test**
   → Va sur https://api.playground.sommesi.com/admin/resources/<modele_pluriel>/new
   → Crée au moins 2-3 entrées
   → Champs importants : <liste des champs requis tirée des validations du modèle>
   → Valeurs suggérées : <propose des valeurs réalistes basées sur le métier>
```

## Étape 4 — Repérer les resources Avo manquantes

Si un nouveau modèle n'a PAS de resource Avo correspondante dans `app/avo/resources/` :

> "⚠️ Le modèle `<Model>` n'a pas de page admin Avo. Tu ne pourras pas créer de données via l'interface. Tu veux que je crée la resource Avo pour ce modèle ?"

Si l'utilisateur dit oui, génère le fichier de resource Avo et inclus-le dans le prochain `deploy:preview`.

## Règles

- **Lis toujours le code réel** avant de générer la checklist. Ne devine pas les champs d'un modèle — lis les fichiers de migration et les validations du modèle.
- **Sois précis avec les URLs Avo** : utilise le format `https://api.playground.sommesi.com/admin/resources/<nom_resource>/new`.
- **Explique en français**, en langage simple. L'utilisateur n'est pas développeur.
- **N'inonde pas** : si la feature n'a besoin que d'1-2 choses, fais court. Si rien n'a besoin d'être configuré, dis-le.
- **Priorise** : activation de feature > configuration > données de test.
- **Propose des valeurs réalistes** : pour les données de test, utilise des valeurs cohérentes avec le métier (noms d'entreprises crédibles, montants plausibles, etc.), pas "test123".
- **Vérifie ce qui existe déjà** : lis `db/seeds/` pour comprendre quelles organisations, features et configurations sont déjà en place. Ne demande pas à l'utilisateur de créer quelque chose qui est déjà seedé.
