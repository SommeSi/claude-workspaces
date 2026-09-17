# Mode éditeur VS Code + récap par tour — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ajouter une option « VS Code » à `/workspace:open` et un récap cliquable des fichiers modifiés à chaque tour de Claude.

**Architecture:** Un script `ws-turn.sh {snapshot|diff}` branché sur les hooks `UserPromptSubmit` et `Stop` compare l'état git des repos du workspace entre début et fin de tour. Un script `ws-open-editor.sh` fusionne des tâches VS Code (`runOn: folderOpen`) dans le `.code-workspace`, lance `code`, puis ouvre l'onglet Claude via URI.

**Tech Stack:** bash + python3 inline (convention du plugin), git, CLI `code`.

**Spec:** `docs/superpowers/specs/2026-09-17-editor-mode-design.md`

## Global Constraints

- `ws-open.sh`, `notify.sh`, `ws-progress-capture.sh` ne sont pas modifiés. Les hooks existants restent dans le même ordre ; les nouveaux sont ajoutés en fin de liste.
- Les hooks ne bloquent jamais : `exit 0` toujours, aucune sortie hors workspace, timeout 5 s.
- `UserPromptSubmit` : **aucune sortie stdout** (elle serait injectée dans le contexte de Claude).
- Tâches VS Code générées : label préfixé `ws: `. Les autres tâches du fichier sont préservées.
- Éditeur : VS Code (`code`) uniquement, pas Cursor.
- Pas de bump de version (géré par l'utilisateur).

### Écarts assumés vs spec

- `ws-turn-snapshot.sh` + `ws-turn-diff.sh` fusionnés en **un** script `ws-turn.sh snapshot|diff` : ils partagent la détection du workspace et le relevé git (DRY).
- Le spike d'affichage dans l'extension est fait **en fin de plan** (Task 5) sur le vrai hook : le plugin tourne depuis le cache, un hook jetable demande la même installation. Seul le format de ligne est ajusté selon le résultat.
- Ports : lus dans le registry (`repos[].port`, déjà calculé à la création) plutôt que recalculés depuis la config.

---

### Task 1: `ws-turn.sh` — snapshot et diff des fichiers modifiés

**Files:**
- Create: `plugins/ws/scripts/ws-turn.sh`
- Test: `plugins/ws/scripts/test-ws-turn.sh`

**Interfaces:**
- Consumes: JSON hook sur stdin (`session_id`, `cwd`).
- Produces: `ws-turn.sh snapshot` → écrit `$TMPDIR/ws-turn/<session_id>.json`, stdout vide. `ws-turn.sh diff` → stdout `{"systemMessage": "..."}` ou rien. Variable `WS_TURN_DIR` pour surcharger le dossier (tests).

- [ ] **Step 1: Écrire le test** `plugins/ws/scripts/test-ws-turn.sh` (contenu dans le fichier livré) couvrant : M sur fichier propre, A nouveau fichier, D suppression, fichier sale avant et non retouché (absent), fichier sale retouché (M), fichier sale rétabli (R), aucun changement (vide), hors workspace (vide), snapshot absent (vide), lien `vscode://file/...`.
- [ ] **Step 2: Lancer** `bash plugins/ws/scripts/test-ws-turn.sh` → FAIL (script absent).
- [ ] **Step 3: Implémenter** `plugins/ws/scripts/ws-turn.sh` (contenu dans le fichier livré).
- [ ] **Step 4: Relancer le test** → `✓ all ws-turn checks passed`.
- [ ] **Step 5: Commit** `feat(ws): per-turn changed files recap script`

### Task 2: Brancher les hooks

**Files:**
- Modify: `plugins/ws/hooks/hooks.json`

- [ ] **Step 1:** Ajouter `UserPromptSubmit` → `ws-turn.sh snapshot` et, en **dernier** hook de `Stop`, `ws-turn.sh diff` (timeout 5).
- [ ] **Step 2:** `python3 -m json.tool plugins/ws/hooks/hooks.json` → JSON valide ; vérifier que les 2 hooks `Stop` existants sont inchangés et en tête.
- [ ] **Step 3: Commit** `feat(ws): register per-turn recap hooks`

### Task 3: `ws-open-editor.sh`

**Files:**
- Create: `plugins/ws/scripts/ws-open-editor.sh`
- Test: `plugins/ws/scripts/test-ws-open-editor.sh`

**Interfaces:**
- Consumes: `<workspace_path>` (arg), registry (`WS_REGISTRY` surcharge `~/.claude-workspaces/registry.json`), `.claude-workspaces.json` (`terminal.panes`, `terminal.claude_tab`), `WS_PANES_JSON` optionnel (prioritaire), `WS_EDITOR_NO_LAUNCH=1` (n'ouvre ni `code` ni l'URI — tests).
- Produces: `<workspace_path>/<slug>.code-workspace` avec `folders`, `settings`, `tasks.tasks[]` (labels `ws: <repo> — <cmd>`).

- [ ] **Step 1: Écrire le test** : registry + config temporaires, `.code-workspace` existant avec une tâche perso et des `settings` → après exécution : tâches `ws: ` présentes avec `$PORT` substitué et `cwd` absolu, pane `cmd: null` ignoré, tâche perso et `settings` préservés, 2ᵉ exécution idempotente, `WS_PANES_JSON` prioritaire, mono-repo sans fichier → fichier créé.
- [ ] **Step 2: Lancer** → FAIL.
- [ ] **Step 3: Implémenter** `ws-open-editor.sh`.
- [ ] **Step 4: Relancer** → `✓ all ws-open-editor checks passed`.
- [ ] **Step 5: Commit** `feat(ws): VS Code editor launcher with folderOpen tasks`

### Task 4: Skill `open` + docs

**Files:**
- Modify: `plugins/ws/skills/open/SKILL.md` (frontmatter, Step 1c, Step 1d, nouveau Step 7, Rules)
- Modify: `plugins/ws/README.md`, `README.md` (table des skills + section « VS Code mode » + « Per-turn recap »)

- [ ] **Step 1:** Step 1c : ne plus stopper sans section `terminal` si l'utilisateur choisit Background ou VS Code. Step 1d : option 3 « VS Code », proposée seulement si `command -v code` réussit.
- [ ] **Step 2:** Step 7 : recap (dossiers, tâches, onglet Claude) + confirmation, `WS_PANES_JSON` si pas de `terminal`, exécution de `ws-open-editor.sh`, résumé avec la note « Allow automatic tasks ».
- [ ] **Step 3:** Docs README.
- [ ] **Step 4: Commit** `docs(ws): document VS Code mode and per-turn recap`

### Task 5: Vérification réelle (utilisateur)

- [ ] **Step 1:** Installer la branche dans le cache (bump/`ws-update.sh` par l'utilisateur), redémarrer.
- [ ] **Step 2:** Dans un workspace, `/workspace:open` → option 3 : VS Code s'ouvre, tâches lancées, onglet Claude ouvert.
- [ ] **Step 3:** Dans l'extension **et** en CLI : demander à Claude de modifier un fichier → le récap s'affiche-t-il ? le lien est-il cliquable ?
- [ ] **Step 4:** Selon résultat : garder le format ; ou basculer sur chemin absolu ; ou repli notification (`notify.sh`) + `.claude/last-turn.md` (spec, section Spike).
