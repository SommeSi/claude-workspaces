# Auto-login Plugin v1.0 — Design Spec

## Overview

Redesign the auto-login plugin to support shared navigation flows, team-wide configuration, and integration with workspace context. The config file is committed in the project repo and usable by both Claude Code and E2E tests.

## Architecture

Two files, two responsibilities:

- **`.auto-login.json`** (committed in project repo) — shared config: login URL, form structure, companies, navigation flows
- **`.env.local`** (gitignored) — each dev's local credentials

## Config Format — `.auto-login.json`

```json
{
  "login": {
    "url": "/fr/login",
    "form_fields": {
      "email_label": "Email",
      "password_label": "Mot de passe",
      "submit_label": "Se connecter"
    },
    "credentials": {
      "file": ".env.local",
      "email_var": "E2E_TEST_EMAIL",
      "password_var": "E2E_TEST_PASSWORD"
    },
    "success_indicator": {
      "redirect_away_from": "/login"
    }
  },
  "companies": {
    "humann-taconet": {
      "label": "Humann & Taconet",
      "features": {
        "scale-folders": {
          "label": "Dossiers d'escale",
          "path": ["Polo", "Dossiers d'escale"],
          "url": "/fr/features/polo/scale-folders"
        },
        "disbursement-accounts": {
          "label": "Comptes de décaissement",
          "path": ["Polo", "Configuration"],
          "url": "/fr/features/polo/settings"
        },
        "supplier-situation": {
          "label": "Situation fournisseurs",
          "path": ["Polo", "Situation fournisseurs"],
          "url": "/fr/features/polo/supplier-situation"
        }
      }
    }
  }
}
```

### Key decisions

- **JSON format** — parsable by Playwright tests, Firefox DevTools MCP, Claude Code, and readable by devs
- **Relative URL paths** — port is dynamic (depends on workspace slot), resolved at runtime from `.env.local` PORT or workspace registry
- **Companies grouped with features** — supports multi-tenant apps where each company has different test data

## Plugin Flow

### First run (no config)

1. Select browser MCP (Playwright first, Firefox second) — auto-select if only one available
2. Explore project source code to discover: login route, credential file/vars, form labels
3. Propose config to user for validation
4. Save `.auto-login.json` at project root
5. Login via browser MCP
6. Ask which company + feature to navigate to → memorize in workspace `CLAUDE.local.md`

### Subsequent runs (config exists)

1. Read `.auto-login.json` + `.env.local` credentials
2. Read memorized flow from workspace `CLAUDE.local.md` (e.g. `auto_login_flow: humann-taconet/disbursement-accounts`)
3. Login → navigate to company → navigate to feature page — zero questions

### No workspace context

1. Login
2. Select company → select feature (not memorized)

## Workspace Integration

In the workspace `CLAUDE.local.md`, a line is added after first auto-login:

```
- **Auto-login flow**: humann-taconet/disbursement-accounts
```

The `/workspace:start-worktree` skill may optionally ask for the flow at workspace creation time.

## Login URL Resolution

The login URL is constructed by combining:
- The path from `.auto-login.json` (`/fr/login`)
- The port from the front repo's `.env.local` (`PORT=3040`) or the workspace registry

Result: `http://localhost:3040/fr/login`

## Navigation Flow

After successful login:

1. If `company` is set in the memorized flow, take a snapshot and click on the matching company label in the UI
2. For each step in `path`, take a snapshot and click on the matching menu item label
3. Verify the final URL matches `url` from the config

If a click doesn't match (label changed, page restructured), abort and inform the user.

## E2E Test Integration

Tests can import the same config:

```ts
import config from '../.auto-login.json'
const loginUrl = `${baseUrl}${config.login.url}`
const company = config.companies['humann-taconet']
```

## Browser MCP Support

Both Playwright (Chrome) and Firefox DevTools MCP are supported. Selection via select prompt on first run. The choice is NOT persisted in `.auto-login.json` (it's a local preference).

## Credentials Security

- Credentials stay in `.env.local` (gitignored) — never in `.auto-login.json`
- `.auto-login.json` only references variable names, not values
- Never display passwords in Claude responses
- Never commit credential files

## OTP / 2FA

OTP is bypassed in dev. If the login form shows an OTP step, the plugin should abort and inform the user rather than trying to bypass it.

## Config Discovery

When `.auto-login.json` doesn't exist, the plugin explores the project code:

1. **Login route**: Next.js `app/**/login/page.tsx`, Rails devise routes, generic `/login` patterns
2. **Credentials**: `.env.local`, `.env.test`, `.env.development` — vars containing EMAIL, PASSWORD
3. **Form labels**: discovered on first login via browser snapshot, saved to config

When `.auto-login.json` exists but `companies` is empty, the plugin can discover companies/features by navigating the app after login and recording the user's clicks.

## Validation

Before each login, validate:
1. Credentials file exists and contains the referenced variables
2. Port is resolvable (from `.env.local` or workspace)
3. If form labels are set, verify they still match (clear and re-detect if not)
