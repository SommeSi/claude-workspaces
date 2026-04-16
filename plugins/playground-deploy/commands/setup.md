---
allowed-tools: Bash(git *), Bash(gh *)
description: Analyze feature changes and guide user to configure playground via Avo
disable-model-invocation: false
---

Analyze what the current feature changes, then guide the user step by step to configure playground so the feature works with real data.

**Avo playground URL:** `https://api.playground.sommesi.com/admin`

## Step 1 — Analyze the feature changes

1. Detect the worktree root. The worktree contains two repos: `front/` and `back/`.
2. Get the feature branch name: `git -C <repo> branch --show-current`
3. Get the full diff between the feature branch and develop for the backend:
   ```bash
   git -C back/ fetch origin develop
   git -C back/ diff origin/develop..HEAD --stat
   git -C back/ diff origin/develop..HEAD
   ```
4. Also check the frontend diff for context (what pages/components were added):
   ```bash
   git -C front/ fetch origin develop
   git -C front/ diff origin/develop..HEAD --stat
   ```

## Step 2 — Read existing code for context

Before generating the checklist, read the relevant files to understand the data model:

1. **New migrations**: read all new migration files to understand the schema
2. **New models**: read model files to understand validations, associations, scopes
3. **Existing seeds**: check `db/seeds/` to understand what data already exists
4. **Routes**: check `config/routes/` to understand what endpoints exist
5. **Avo resources**: check `app/avo/resources/` to know which models have an Avo admin panel
6. **Feature configuration**: check references to `FeatureSubscription`, `FeatureConfiguration`, `ConfigurationLink` in the diff

## Step 3 — Generate setup checklist

Present the user with a clear, numbered checklist **in French**. Group by priority:

### Priority 1 — Activation de la feature (si nécessaire)

If the feature references a new feature slug:

```
1. **Activer la feature "<feature_slug>" pour ton organisation**
   → Va sur https://api.playground.sommesi.com/admin/resources/feature_subscriptions/new
   → Sélectionne ton organisation
   → Sélectionne la feature "<feature_slug>"
   → Clique sur "Create"
```

### Priority 2 — Configuration requise

If the feature needs `FeatureConfiguration`, `ConfigurationLink`, or API credentials:

```
2. **Créer la configuration <nom>**
   → Va sur https://api.playground.sommesi.com/admin/resources/<resource>/new
   → Renseigne les champs : <list specific fields from the migration>
   → C'est nécessaire pour <reason from code analysis>
```

### Priority 3 — Données de démonstration

If the feature introduces new models with pages that display data:

```
3. **Créer des données de test**
   → Va sur https://api.playground.sommesi.com/admin/resources/<model_plural>/new
   → Crée au moins 2-3 entrées
   → Champs importants : <list required fields from model validations>
   → Valeurs suggérées : <suggest realistic values based on the domain>
```

## Step 4 — Identify missing Avo resources

If a new model does NOT have a corresponding Avo resource in `app/avo/resources/`:

> "⚠️ Le modèle `<Model>` n'a pas de page admin Avo. Tu ne pourras pas créer de données via l'interface. Tu veux que je crée la resource Avo pour ce modèle ?"

If the user says yes, generate the Avo resource file and include it in the next `deploy:preview`.

## Rules

- **Always read the actual code** before generating the checklist. Don't guess model fields — read the migration files and model validations.
- **Be specific with Avo URLs**: use `https://api.playground.sommesi.com/admin/resources/<resource_name>/new` format.
- **Explain in French**, in plain language. The user is not a developer.
- **Don't overwhelm**: if the feature only needs 1-2 things configured, keep it short. If nothing needs to be configured, say so.
- **Prioritize**: feature activation > configuration > test data.
- **Suggest realistic values**: when proposing test data, use domain-appropriate values (real-looking company names, plausible amounts, etc.), not "test123".
- **Check what already exists**: read `db/seeds/` to understand what organizations, features, and configurations already exist. Don't ask the user to create something that's already seeded.
