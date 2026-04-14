# Auto-login Plugin v1.0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rewrite the auto-login plugin SKILL.md to support shared team config (`.auto-login.json` committed in project repo), company/feature navigation flows, workspace integration, and dynamic port resolution.

**Architecture:** Single SKILL.md file rewrite. The config format changes from flat to nested (`login` + `companies` sections). Navigation flows are persisted per-workspace in `CLAUDE.local.md`. Port is resolved dynamically from `.env.local` or workspace registry instead of being hardcoded in the config.

**Tech Stack:** Pure markdown (Claude Code skill), JSON config, browser MCP (Playwright + Firefox DevTools)

---

### Task 1: Rewrite SKILL.md with new config format

**Files:**
- Modify: `plugins/auto-login/skills/auto-login/SKILL.md`

- [ ] **Step 1: Replace the entire SKILL.md with the v1.0 skill**

Replace the content of `plugins/auto-login/skills/auto-login/SKILL.md` with the following:

```markdown
---
name: auto-login
description: Auto-login to a local dev app via browser MCP. Reads shared .auto-login.json config, resolves port dynamically, navigates to company/feature. Supports Playwright (Chrome) and Firefox. Triggers on "auto-login", "log me in", "connect me", "login to the app".
---

# Auto-login

Automatically logs into a local dev app using shared team config, then navigates to the right company and feature page.

---

## Step 1 — Find and read config

Look for `.auto-login.json` starting from the current directory, walking up to the git root. Also check if a workspace is active by reading `CLAUDE.local.md` in the current directory or parent.

```bash
# Find config — check current dir and parents
config_path=""
dir="$PWD"
while [ "$dir" != "/" ]; do
  [ -f "$dir/.auto-login.json" ] && config_path="$dir/.auto-login.json" && break
  dir=$(dirname "$dir")
done
cat "$config_path" 2>/dev/null
```

- **Config found** → read it, then validate (Step 3), then login (Step 4).
- **Config not found** → proceed to Step 2 (discovery).

Also check for a memorized flow in `CLAUDE.local.md`:

```bash
grep "Auto-login flow" CLAUDE.local.md 2>/dev/null
```

If found (e.g. `humann-taconet/disbursement-accounts`), store for use in Step 5.

---

## Step 2 — First-time setup (no config)

### 2a — Select browser MCP

Detect which browser MCPs are available by checking for their tools:

1. Try `mcp__playwright__browser_navigate` → Playwright available
2. Try `mcp__firefox-devtools__navigate_page` → Firefox available

- If both available → ask with select (Playwright first):
  > Which browser do you want to use?
  > 1. Chrome (Playwright)
  > 2. Firefox (DevTools)
- If only one → use it directly.
- If none → abort: "No browser MCP detected."

### 2b — Discover login from source code

Ask the user:

> What's the path to your project? (Enter for current directory)

Then explore the project code to find:

**Login URL** — search for login-related routes/pages:
- Next.js: `app/**/login/page.tsx`, `pages/login.tsx`
- Rails: `config/routes.rb` for devise/session routes
- Generic: files with `/login` or `/sign-in` URL patterns

**Credentials** — search for credential files:
1. `.env.local` → variables containing `EMAIL`, `PASSWORD`
2. `.env.test` → same patterns
3. `.env.development` → same patterns
4. `cypress/`, `e2e/`, `test/` → test fixtures with login credentials

**Form labels** — will be discovered on first login via browser snapshot (Step 4c).

### 2c — Propose and save config

Present what was found:

> Here's what I found:
> - **Login path**: `/fr/login`
> - **Credentials file**: `.env.local`
>   - Email var: `E2E_TEST_EMAIL`
>   - Password var: `E2E_TEST_PASSWORD`
>
> Does this look right?
> 1. Yes — save and login
> 2. Edit — let me adjust
> 3. Cancel

If **2**, ask what to change.

Write `.auto-login.json` at the project root (same level as `.git`):

```json
{
  "login": {
    "url": "/fr/login",
    "form_fields": null,
    "credentials": {
      "file": ".env.local",
      "email_var": "E2E_TEST_EMAIL",
      "password_var": "E2E_TEST_PASSWORD"
    },
    "success_indicator": {
      "redirect_away_from": "/login"
    }
  },
  "companies": {}
}
```

`form_fields` starts as `null` — populated after first successful login (Step 4f).
`companies` starts empty — populated interactively (Step 5c).

**Do NOT add `.auto-login.json` to `.gitignore`** — this file is meant to be committed and shared with the team. It contains no secrets (only variable names, not values).

---

## Step 3 — Validate existing config

When config exists, verify before login:

1. The credentials file exists at the path specified in `login.credentials.file`
2. The credential variables (`email_var`, `password_var`) are defined in that file
3. Port is resolvable (see Step 4a)

If `form_fields` is present, it will be validated during login (Step 4c). If labels don't match the snapshot, they're cleared and fresh detection is used.

If validation fails:

> Config issue: `.env.local` no longer contains `E2E_TEST_EMAIL`.
> 1. Re-discover (scan project again)
> 2. Edit config manually
> 3. Cancel

---

## Step 4 — Login via browser MCP

### 4a — Resolve port and build login URL

The port is NOT in `.auto-login.json` — it's dynamic per workspace. Resolve it in this order:

1. Read `PORT` from the front repo's `.env.local`
2. If in a workspace, check the workspace registry (`~/.claude-workspaces/registry.json`) for the front repo port
3. Fall back to common defaults: 3000, 4000

Build the full URL: `http://localhost:<port><login.url>`

Example: `http://localhost:3040/fr/login`

### 4b — Read credentials

```bash
grep "^<email_var>=" <credentials_file> | cut -d= -f2-
grep "^<password_var>=" <credentials_file> | cut -d= -f2-
```

**NEVER display the password in your response.**

### 4c — Navigate to login page

**Playwright:**
```
mcp__playwright__browser_navigate → url: <full_login_url>
```

**Firefox:**
```
mcp__firefox-devtools__navigate_page → url: <full_login_url>
```

### 4d — Snapshot and identify form

Take a snapshot of the login page.

**If `login.form_fields` is set in the config**, use the saved labels to find fields by matching label text. If saved labels don't match, fall back to generic detection.

**Generic detection (no `form_fields` or fallback)**:
- Email input: look for labels/placeholders containing `email`, `e-mail`, `utilisateur`, `username`
- Password input: look for `password`, `mot de passe`, `mdp`
- Submit button: look for `login`, `connexion`, `se connecter`, `sign in`, `submit`

### 4e — Fill and submit

**Playwright:**
```
mcp__playwright__browser_fill_form → fields based on snapshot refs
mcp__playwright__browser_click → submit button ref
```

**Firefox:**
```
mcp__firefox-devtools__fill_by_uid → email input uid + value
mcp__firefox-devtools__fill_by_uid → password input uid + value
mcp__firefox-devtools__click_by_uid → submit button uid
```

### 4f — Verify success

Wait ~2 seconds, then take a snapshot. Check if the URL has changed away from the login page (based on `login.success_indicator.redirect_away_from`).

- **Success** → save form labels if not already saved (update `login.form_fields` in `.auto-login.json`), then proceed to Step 5.
- **Failure** → if `form_fields` was used, clear it and retry with generic detection. If still fails:
  > Login failed — `<error_message>`. Check your credentials.

---

## Step 5 — Post-login navigation

### 5a — Check for memorized flow

If a flow was found in `CLAUDE.local.md` (Step 1), parse it as `<company-key>/<feature-key>`.

Look up the company and feature in `.auto-login.json` → `companies.<company-key>.features.<feature-key>`.

If found → navigate directly (Step 5b). No questions asked.

### 5b — Navigate using flow

For each step in the feature's `path` array:
1. Take a snapshot of the current page
2. Find and click the menu item matching the label
3. Wait for navigation

After all steps, verify the URL contains the feature's `url` path.

> Auto-login OK. Browser is on `<current_url>`.

### 5c — First-time flow discovery (no memorized flow, companies exist)

If `companies` is populated in the config but no flow is memorized, present a select:

> Where do you want to go?

List all companies and their features:

> 1. Humann & Taconet > Dossiers d'escale
> 2. Humann & Taconet > Comptes de décaissement
> 3. Humann & Taconet > Situation fournisseurs
> 4. Just the dashboard (no navigation)

If the user picks a feature, navigate using Step 5b, then save the flow to `CLAUDE.local.md`:

Add this line under `## Workspace info`:
```
- **Auto-login flow**: <company-key>/<feature-key>
```

### 5d — No companies in config

If `companies` is empty and login succeeded:

> You're logged in. Want me to learn the navigation to your feature?
> 1. Yes — guide me through the app
> 2. No — just the login is enough

If **1**:
- Take a snapshot, show what's on screen
- Ask what to click (or let the user navigate manually and take snapshots to record)
- Record the company name, path (menu clicks), and final URL
- Save to `.auto-login.json` under `companies`
- Save the flow to `CLAUDE.local.md`

If **2**, proceed without navigation.

---

## Rules

- **Never display the password** in responses, tool output, or commit messages.
- **`.auto-login.json` IS meant to be committed** — it contains no secrets, only variable names and navigation flows.
- **Never commit `.env.local`** or other credential files.
- **Never add auto-login to CI or prod configs.** This is strictly for local dev.
- **If the login form has changed** (captcha, 2FA, new field), do not brute-force. Abort and inform the user.
- **One question at a time.** Never batch questions.
- **Always validate config** before using it — files and variables may have changed.
- **Port is always resolved dynamically** — never hardcode it in `.auto-login.json`.
```

- [ ] **Step 2: Verify the SKILL.md is valid**

Read back the file and check:
- Frontmatter has `name` and `description`
- All steps are numbered consistently
- No references to the old flat config format (`login_url`, `browser`, `post_login`)
- New config format uses `login.url` (relative path, no port)
- Companies section is properly documented

- [ ] **Step 3: Commit**

```bash
git add plugins/auto-login/skills/auto-login/SKILL.md
git commit -m "feat(auto-login): rewrite skill for shared team config v1.0

- Config split: .auto-login.json (committed) + .env.local (gitignored)
- Dynamic port resolution from workspace/env
- Company/feature navigation flows
- Workspace integration via CLAUDE.local.md memorized flow
- First-time interactive flow discovery"
```

---

### Task 2: Update plugin.json and marketplace.json

**Files:**
- Modify: `plugins/auto-login/.claude-plugin/plugin.json`
- Modify: `.claude-plugin/marketplace.json`

- [ ] **Step 1: Bump version to 1.0.0 in plugin.json**

```json
{
  "name": "auto-login",
  "version": "1.0.0",
  "description": "Auto-login to local dev apps via browser MCP — shared team config with company/feature navigation flows, supports Playwright and Firefox",
  "author": {
    "name": "sommesi"
  },
  "repository": "https://github.com/sommesi/claude-workspaces",
  "license": "MIT",
  "keywords": ["auto-login", "browser", "mcp", "playwright", "firefox", "dev", "navigation"]
}
```

- [ ] **Step 2: Update version in marketplace.json**

Change the auto-login entry version to `1.0.0` and update description.

- [ ] **Step 3: Commit**

```bash
git add plugins/auto-login/.claude-plugin/plugin.json .claude-plugin/marketplace.json
git commit -m "chore: bump auto-login to v1.0.0"
```

---

### Task 3: Update local plugin cache

**Files:**
- Modify: `~/.claude/plugins/cache/claude-workspaces/auto-login/*/skills/auto-login/SKILL.md`
- Modify: `~/.claude/plugins/installed_plugins.json`

- [ ] **Step 1: Copy updated plugin to cache**

```bash
# Remove old cache
rm -rf ~/.claude/plugins/cache/claude-workspaces/auto-login/

# Copy new version
cp -R plugins/auto-login ~/.claude/plugins/cache/claude-workspaces/auto-login/1.0.0
```

- [ ] **Step 2: Update installed_plugins.json**

Update the `auto-login@claude-workspaces` entry to point to `1.0.0` with the correct install path and git commit sha.

- [ ] **Step 3: Push to remote**

```bash
git push origin main
```

---

### Task 4: Manual test

- [ ] **Step 1: Restart Claude Code**

Exit and relaunch Claude in the workspace.

- [ ] **Step 2: Run `/auto-login` with no config**

Verify the full first-run flow:
- Browser MCP selection
- Code discovery
- Config proposal and save
- Login
- Company/feature selection
- Flow saved to `CLAUDE.local.md`

- [ ] **Step 3: Run `/auto-login` again (with config)**

Verify the fast path:
- No questions asked
- Login + navigation automatic
- Correct page reached

- [ ] **Step 4: Test in a different workspace**

Create or use another workspace to verify:
- Config is read from the project (shared)
- Flow is memorized per-workspace (different)
