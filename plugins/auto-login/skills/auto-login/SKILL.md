---
name: auto-login
description: Auto-login to a local dev app via browser MCP. Discovers login forms from source code, persists config, supports Playwright (Chrome) and Firefox. Triggers on "auto-login", "log me in", "connect me", "login to the app".
---

# Auto-login

Automatically logs into a local dev app by discovering the login form from source code, reading credentials, and driving a browser via MCP.

---

## Step 1 — Check for existing config

Look for `.auto-login.json` in the current working directory, then walk up parent directories until the git root.

```bash
# Check current dir and parents up to git root
cat .auto-login.json 2>/dev/null
```

- **Config found** → validate it (Step 4), then login (Step 5).
- **Config not found** → proceed to Step 2 (discovery).

---

## Step 2 — Select browser MCP

Detect which browser MCPs are available by checking for their tools:

1. Try `mcp__playwright__browser_navigate` → Playwright available
2. Try `mcp__firefox-devtools__navigate_page` → Firefox available

Present available options as a select:

> Which browser do you want to use?
> 1. Chrome (Playwright)
> 2. Firefox (DevTools)

- If only one is available, use it directly without asking.
- If none is available, abort:
  > No browser MCP detected. Install the Playwright or Firefox DevTools MCP server to use auto-login.

Save the choice for Step 5.

---

## Step 3 — Discover login from source code

Ask the user:

> What's the path to your project? (Enter for current directory)

Then explore the project code to find:

### 3a — Login URL

Search for login-related routes/pages:

- Look for files containing `login`, `sign-in`, `signin`, `connexion` in route definitions, page components, or URL paths
- Check framework-specific patterns:
  - **Next.js**: `app/**/login/page.tsx`, `pages/login.tsx`
  - **Rails**: `config/routes.rb` for devise/session routes
  - **Generic**: any file with `/login` or `/sign-in` URL patterns
- Check for a running dev server port (from workspace config, `.env.local`, `package.json` scripts, etc.)

### 3b — Credentials

Search for credential files in this order:

1. `.env.local` → look for variables containing `EMAIL`, `PASSWORD`, `USER`, `CREDENTIALS`, `LOGIN`
2. `.env.test` → same patterns
3. `.env.development` → same patterns
4. `cypress/`, `e2e/`, `test/` directories → look for test fixtures with login credentials

### 3c — Propose config

Present what was found:

> Here's what I found:
> - **Login URL**: `http://localhost:3000/fr/login`
> - **Credentials file**: `front/.env.local`
>   - Email var: `E2E_TEST_EMAIL`
>   - Password var: `E2E_TEST_PASSWORD`
> - **Browser**: Playwright (Chrome)
>
> Does this look right?
> 1. Yes — save and login
> 2. Edit — let me adjust
> 3. Cancel

If **2**, ask what to change and update accordingly.

### 3d — Save config

Write `.auto-login.json` at the project root (same level as `.git`):

```json
{
  "login_url": "http://localhost:3000/fr/login",
  "credentials": {
    "file": "front/.env.local",
    "email_var": "E2E_TEST_EMAIL",
    "password_var": "E2E_TEST_PASSWORD"
  },
  "browser": "playwright",
  "success_indicator": {
    "redirect_away_from": "/login"
  }
}
```

Also check if `.auto-login.json` is in `.gitignore`. If not, warn:

> `.auto-login.json` is not in `.gitignore`. It may contain credential variable names. Add it?
> 1. Yes
> 2. No, I'll handle it

---

## Step 4 — Validate existing config

When a config exists, verify:

1. The credentials file still exists at the specified path
2. The credential variables are still defined in that file
3. The login URL port matches a running dev server (if detectable)

If anything is wrong:

> Config issue: `front/.env.local` no longer contains `E2E_TEST_EMAIL`.
> 1. Re-discover (scan project again)
> 2. Edit config manually
> 3. Cancel

---

## Step 5 — Login via browser MCP

### 5a — Read credentials

```bash
grep "^<email_var>=" <credentials_file> | cut -d= -f2-
grep "^<password_var>=" <credentials_file> | cut -d= -f2-
```

**NEVER display the password in your response.** Keep it in memory only long enough to fill the form.

### 5b — Navigate to login page

**Playwright:**
```
mcp__playwright__browser_navigate → url: <login_url>
```

**Firefox:**
```
mcp__firefox-devtools__navigate_page → url: <login_url>
```

### 5c — Snapshot and identify form

**Playwright:**
```
mcp__playwright__browser_snapshot
```

**Firefox:**
```
mcp__firefox-devtools__take_snapshot
```

From the snapshot, identify:
- Email/username input (look for: `email`, `e-mail`, `utilisateur`, `username`, `user`)
- Password input (look for: `password`, `mot de passe`, `mdp`)
- Submit button (look for: `login`, `connexion`, `se connecter`, `sign in`, `submit`, `entrer`)

### 5d — Fill and submit

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

### 5e — Verify success

Wait ~2 seconds, then check the current URL:

**Playwright:**
```
mcp__playwright__browser_snapshot
```

**Firefox:**
```
mcp__firefox-devtools__take_snapshot
```

Check if the URL has changed away from the login page (based on `success_indicator.redirect_away_from`).

- **Success**: display a short confirmation message:
  > Auto-login OK. Browser is now on `<current_url>`.

- **Failure**: take a screenshot and check for error messages in the snapshot:
  > Login failed — `<error_message_if_found>`. Check your credentials.

---

## Rules

- **Never display the password** in responses, tool output, or commit messages.
- **Never commit `.auto-login.json`** or credential files.
- **Never add auto-login to CI or prod configs.** This is strictly for local dev.
- **If the login form has changed** (captcha, 2FA, new field), do not brute-force. Abort and inform the user.
- **One question at a time.** Never batch questions.
- **Always validate config** before using it — files and variables may have changed.
