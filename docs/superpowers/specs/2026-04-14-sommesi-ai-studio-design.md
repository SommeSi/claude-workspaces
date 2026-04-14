# Sommesi AI Studio — POC Design Spec

## Overview

An AI assistant integrated into the Sommesi dashboard that lets any user (including non-devs) create custom dashboards and views by describing what they want in natural language. The AI generates React/Shadcn components that render live data from the Sommesi API.

## Goal

POC for Thursday 2026-04-17 demo to management. Show that Sommesi's accumulated domain knowledge (APIs, edge cases, business rules) is a competitive moat that powers AI-assisted customization no generic tool can match.

## Architecture

```
User → Chat UI (Shadcn) → API Route /api/chat (Vercel AI SDK + Claude)
                                    ↓
                              Knowledge base (system prompt)
                                    ↓
                              Generated code (React + Shadcn + Recharts)
                                    ↓
                              Sandpack iframe (client-side execution)
                                    ↓
                              Sommesi API (live data via fetch)
```

## Tech Stack

- **Vercel AI SDK v6** — streaming chat with tool calling
- **Claude API** (Anthropic) — code generation model
- **Sandpack** (@codesandbox/sandpack-react) — sandboxed React execution in iframe
- **Recharts** — charting library (already in the app or easy to add)
- **Shadcn/ui** — component library (already installed)

## Pages & Components

### New page: `/[locale]/ai-studio`

A dedicated page in the app with two panels:
- **Left panel**: Chat interface (messages + input)
- **Right panel**: Live preview (Sandpack iframe rendering generated code)

### Components to create

| Component | Path | Purpose |
|-----------|------|---------|
| `AiStudioPage` | `app/[locale]/ai-studio/page.tsx` | Page layout with chat + preview panels |
| `Chat` | `components/ai-studio/chat.tsx` | Chat messages list + input, uses AI SDK `useChat` |
| `Preview` | `components/ai-studio/preview.tsx` | Sandpack wrapper that renders generated React code |
| `MessageBubble` | `components/ai-studio/message-bubble.tsx` | Individual message (user or assistant) |

### API Route

| Route | Path | Purpose |
|-------|------|---------|
| Chat endpoint | `app/api/chat/route.ts` | AI SDK streamText with Claude, system prompt with knowledge |

## Knowledge Base

A structured system prompt that gives Claude the context to generate correct Sommesi code. Stored as a markdown/text file at `lib/ai-studio/knowledge.ts`.

### Contents

1. **API Surface** — available endpoints with request/response formats
   - Polo: folders, suppliers, supplier-invoices, documents
   - Furious-Pennylane: invoices, payments, analytical
   - Execution errors, webhooks
   - Filter syntax: `?filter=[{"field":"status","operator":"eq","value":"active"}]`
   - Auth: Bearer token via session

2. **Available Components** — Shadcn components the AI can use
   - Card, Table, Badge, Button
   - Recharts: BarChart, LineChart, PieChart
   - Data display patterns used in the app

3. **Code Patterns** — how to fetch data and render it
   - Fetch pattern with Bearer token
   - Error handling
   - Loading states
   - Responsive layout patterns

4. **Business Context** — domain knowledge
   - What a "dossier d'escale" is
   - Supplier invoice statuses and meanings
   - Sync error types and their significance

## Sandpack Configuration

The generated code runs in a Sandpack iframe with:
- React 19 + Shadcn CSS (via CDN or bundled)
- Recharts available as import
- A pre-configured `fetch` wrapper that includes the auth token and base URL
- Access to the real Sommesi API (same-origin or proxied)

The AI generates a single self-contained React component that:
1. Fetches data from the API on mount
2. Renders using Shadcn/Recharts components
3. Handles loading and error states

## Demo Scenarios (must work Thursday)

1. **"Montre-moi les dossiers d'escale ouverts"**
   → Table with folder name, status, dates, vessel name
   → Uses `GET /api/v1/polo/folders` with status filter

2. **"Graphique des factures fournisseurs par mois"**
   → Recharts BarChart grouped by month
   → Uses `GET /api/v1/polo/supplier-invoices`

3. **"Quelles erreurs de sync cette semaine ?"**
   → Filtered table with error type, date, message
   → Uses `GET /api/v1/execution_errors`

## Auth Flow for Sandpack

The Sandpack iframe needs to call the Sommesi API with the user's auth token. Options:

- **Recommended**: Pass the session token to Sandpack via `postMessage`. The generated code uses it in fetch headers.
- **Alternative**: Proxy API calls through a Next.js API route that injects the token server-side.

## Knowledge Visibility (for demo)

A small section in the UI showing what knowledge the AI has access to:
- "API endpoints: 47 endpoints across 8 modules"
- "Components: 12 Shadcn components, 6 chart types"
- "Business rules: 15 domain concepts documented"

This demonstrates to management that the knowledge base is the differentiator.

## Out of Scope (for Thursday)

- Saving/persisting generated views
- Sharing views between users
- Editing generated code manually
- Workflows/automations
- Full CRUD pages
- Multi-turn refinement of generated views (nice to have but not required)

## Projection (slides for management)

Phase 1 (now): Custom dashboards via chat — read-only views on live data
Phase 2: Workflows & automations — "when X happens, do Y"
Phase 3: Full feature building — CRUD pages with review before deploy
Phase 4: Knowledge flywheel — more usage = more knowledge = better code generation

The competitive moat: Sommesi's domain knowledge (maritime, accounting, HR edge cases) is embedded in the AI. Generic tools (Lovable, Bolt) can never have this.
