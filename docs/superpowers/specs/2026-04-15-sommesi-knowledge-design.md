# Sommesi Knowledge — Design Spec

## Overview

A shared knowledge repository that captures Sommesi's domain expertise, API patterns, coding conventions, and edge cases. Used by both Claude Code (for better code generation) and the AI Studio (for context-aware assistance). The competitive moat — domain knowledge that generic AI tools can never have.

## Architecture

### Repository

Private Git repo `sommesi-knowledge` on the SommeSi org. Added as a **git submodule** in both:
- `backend-sommesi-app/knowledge/`
- `frontend-sommesi-app/knowledge/`

### Structure

```
sommesi-knowledge/
  domain/                     # Business domain knowledge
    polo/                     # Maritime, shipping folders, port management
      overview.md             # What Polo does, key concepts
      workflows.md            # Folder lifecycle, status transitions
      data-model.md           # Key models and relationships
    pennylane/                # Accounting system
      overview.md
      api-quirks.md           # Rate limits, pagination, weird behaviors
    furious/                  # ERP system
      overview.md
      project-reporting.md
    lucca/                    # HR system
      overview.md
      leave-types.md

  api/                        # Sommesi API surface
    endpoints.md              # All endpoints with request/response formats
    auth.md                   # JWT flow, token refresh, OTP
    errors.md                 # Error codes, retry patterns
    filters.md                # Filter syntax, operators, pagination

  patterns/                   # Coding conventions
    backend.md                # Rails: services, blueprints, controllers, jobs
    frontend.md               # Next.js: Server Actions, Shadcn, components, i18n
    testing.md                # Test patterns, fixtures, E2E

  edge-cases/                 # Known pitfalls
    pennylane-sync.md         # Race conditions, API limits, retry logic
    furious-invoices.md       # Special cases in invoice processing
    polo-documents.md         # Document classification gotchas

  team/                       # Team preferences
    conventions.md            # Naming, git flow, PR format, commit style
    preferences.md            # Accumulated feedback from Claude sessions
```

## Feeding the Knowledge

### Automatic (via Claude plugins)

**`/workspace:finish`** — after a workspace is done:
1. Claude proposes learnings from the session (Step 3a)
2. User validates which to save
3. Claude determines the right file in `knowledge/` (e.g. `edge-cases/pennylane-sync.md`)
4. Appends the learning to that file
5. Commits in the submodule
6. Pushes the submodule

**`/knowledge:learn`** (new skill, future) — bootstraps knowledge by:
1. Scanning a repo's code (models, routes, services, components)
2. Generating structured documentation
3. Writing to the appropriate knowledge files
4. User reviews and validates before commit

### Manual

Developers edit/restructure knowledge files directly. The auto-feed adds raw learnings; humans organize and refine them periodically.

## Consumption

### By AI Studio (frontend)

Context-aware selection — no RAG needed initially:

1. The app knows which module the user is in (Polo, Furious, etc.)
2. System prompt is assembled from:
   - `domain/<module>/` — all files for the current module
   - `api/endpoints.md` — filtered to relevant endpoints
   - `patterns/frontend.md` — coding patterns
   - `edge-cases/<module>.md` — known pitfalls
3. Total context stays manageable (< 50k tokens per module)

If knowledge grows too large, migrate to RAG (vector search) later.

### By Claude Code (development)

Claude reads the `knowledge/` submodule as a local directory. The project's `CLAUDE.md` references it:

```markdown
## Knowledge base
Consult `knowledge/` for domain knowledge, conventions, edge cases, and API patterns before writing code. Key files:
- `knowledge/patterns/backend.md` — Rails conventions
- `knowledge/patterns/frontend.md` — Next.js conventions
- `knowledge/edge-cases/` — known pitfalls to avoid
```

### By E2E Tests

Tests can reference knowledge for fixture data, expected behaviors, and domain constants:

```typescript
// Knowledge-driven test helpers
import { POLO_STATUSES } from '../knowledge/domain/polo/data-model'
```

## Submodule Workflow

### Initial setup (per repo)

```bash
cd backend-sommesi-app
git submodule add git@github.com:SommeSi/sommesi-knowledge.git knowledge
git commit -m "chore: add sommesi-knowledge submodule"
```

### Updating knowledge

```bash
cd knowledge
git pull origin main
cd ..
git add knowledge
git commit -m "chore: update knowledge submodule"
```

### `/workspace:finish` auto-update

The finish skill handles this automatically:
1. `cd knowledge && git pull origin main` (get latest)
2. Edit the relevant file
3. `git add . && git commit -m "learn: <description>"`
4. `git push origin main`
5. `cd .. && git add knowledge` (update submodule pointer in parent repo)

## Security

- No secrets in the knowledge repo — only documentation and patterns
- Credentials, API keys, and tokens stay in `.env.local` (gitignored)
- The repo is private (SommeSi org only)

## Success Criteria

1. Claude Code generates better code when knowledge is present vs without
2. AI Studio answers are accurate and domain-aware
3. New team members can onboard faster by reading the knowledge
4. Edge cases are documented and not re-discovered
