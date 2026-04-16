---
allowed-tools: Bash(git *), Bash(gh *)
description: Analyze feature changes and guide user to configure playground via Avo
disable-model-invocation: false
---

Analyze what the current feature changes, then guide the user step by step to configure playground so the feature works with real data.

## Step 1 — Analyze the feature changes

1. Detect the worktree root. The worktree contains two repos: `front/` and `back/`.
2. Get the feature branch name: `git -C <repo> branch --show-current`
3. Get the diff between the feature branch and develop for the backend:
   ```bash
   git -C back/ fetch origin develop
   git -C back/ diff origin/develop..HEAD --stat
   git -C back/ diff origin/develop..HEAD
   ```
4. Also check the frontend diff for context:
   ```bash
   git -C front/ fetch origin develop
   git -C front/ diff origin/develop..HEAD --stat
   ```

## Step 2 — Identify what needs to be configured

From the diff analysis, identify:

**Models & migrations:**
- New models created (new migration files in `db/migrate/`)
- New columns added to existing tables
- New associations between models

**Feature subscriptions & configuration:**
- New feature slugs referenced in code
- New `FeatureConfiguration` or `FeatureConfigurationTemplate` entries needed
- New `ConfigurationLink` setups required
- New API provider connections needed

**Seeds & reference data:**
- New entries in `db/seeds/` files
- New analytical slugs, VAT mappings, contract types, etc.
- New `ApiProvider` entries

**Routes & controllers:**
- New API endpoints (may need test data to be useful)
- New Avo resources (admin panels for new models)

## Step 3 — Generate a setup checklist

Present the user with a clear, numbered checklist in French. Each item should be:
- **What** to do (in plain language, no jargon)
- **Where** to do it (exact Avo URL when possible)
- **Why** it's needed (brief context)

Format:

```
🔧 Setup playground pour <feature-name>

Voici ce qu'il faut configurer sur Avo (https://api.playground.sommesi.com/admin) :

1. **Activer la feature "<feature_slug>"**
   → Avo > FeatureSubscriptions > New
   → Sélectionne ton organisation et la feature "<feature_slug>"
   → Ça permet d'activer la feature pour ton orga

2. **Créer la configuration <config_name>**
   → Avo > FeatureConfigurations > New
   → Renseigne : [fields]
   → C'est nécessaire pour [reason]

3. **Ajouter des données de test**
   → Avo > <Model> > New
   → Crée au moins 1-2 entrées avec [suggested values]
   → Pour que la page ne soit pas vide

...
```

## Step 4 — Offer to generate a seed file (optional)

After presenting the checklist, ask:
> "Tu veux que je génère aussi un fichier seed pour automatiser ce setup ? Comme ça, la prochaine fois que playground est reset, tout sera reconfiguré automatiquement."

If yes:
1. Generate an idempotent seed file using `find_or_create_by!` for all entries
2. Save it in `db/seeds/playground/<feature-name>.rb`
3. The user can then use `deploy:preview` to push it

## Rules

- **Always read the actual code** before generating the checklist. Don't guess model fields — read the migration files and model validations.
- **Be specific with Avo URLs**: use `https://api.playground.sommesi.com/admin/resources/<resource_name>/new` when possible.
- **Explain in French**, in plain language. The user is not a developer.
- **Don't overwhelm**: if the feature only needs 1-2 things configured, keep it short.
- **Prioritize**: list the most critical items first (feature activation > configuration > test data).
- **Check existing seeds**: read `db/seeds/` to understand what data already exists and avoid duplicates.
