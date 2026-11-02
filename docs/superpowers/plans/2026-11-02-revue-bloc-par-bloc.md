# Revue bloc par bloc multi-repo : plan de construction

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Livrer l'objectif 1 de la spec : accepter ou refuser chaque bloc changé par le vrai `claude`, sur un workspace multi-repo, dans VS Code, avec l'abonnement.

**Architecture:** Le plugin `workspace` possède un hook Python qui prend un instantané par repo à chaque message. Une extension VS Code en TypeScript compare les fichiers à ces instantanés, affiche les blocs et avance l'instantané à chaque acceptation. Dashboard et corbeille feront l'objet de deux plans suivants.

**Tech Stack:** Python 3 stdlib (hook), TypeScript, API VS Code, esbuild, Vitest, `@vscode/test-electron`, `@vscode/vsce`.

**Spec:** `docs/superpowers/specs/2026-11-02-worktree-dashboard-design.md`. Prototype de référence : `~/projects/claude-review-spike/`.

## Global Constraints

- Aucune clé API, pas d'Agent SDK, pas de `--bare`. Tout passe par le vrai `claude`.
- Le hook sort toujours en code 0 et n'écrit jamais sur stdout. Un message à Claude ne doit jamais être bloqué.
- Référence d'instantané par repo : `refs/worktree/claude-review/baseline`.
- État par worktree : `~/.claude-workspaces/review/<slug>/`.
- L'extension ne modifie aucun réglage de Claude Code et exige le plugin `workspace` à la version qui contient le hook.
- macOS seulement. Raccourcis utilisables sur AZERTY : `cmd+alt+j`, `cmd+alt+y`, `cmd+alt+n`.
- Budget du hook : 300 ms sur un workspace de 5 repos à chaud (décision du plan).
- Le plugin n'a pas de dépendance : Python stdlib uniquement.
- Commits : conventionnels, sans push vers `main` du plugin sans accord de Sébastien.

## Review Focus

- Rebase, merge ou `index.lock` en cours sur un repo : l'instantané de ce repo échoue proprement, l'échec s'affiche, le message part. Test : Task 1.
- Sébastien tape dans un fichier pendant le tour de Claude : son texte apparaît comme un bloc, et rien n'est perdu au refus sans confirmation du contenu vu. Test : Task 5.
- Fichier binaire ou de plus de 2 Mo : listé, sans bloc, jamais tronqué. Test : Task 4.
- Chemin avec espaces ou accents, comme `app/données client.rb` : traité comme les autres. Test : Task 4.
- Repo optionnel du registre absent du disque, comme `webhook` : ignoré sans erreur. Test : Task 1.

---

### Task 1: Hook d'instantané multi-repo

**Files:**
- Create: `plugins/ws/scripts/ws-review.py`
- Create: `plugins/ws/scripts/test_ws_review.py`

**Interfaces:**
- Produces (fichiers lus par l'extension), sous `$WS_HOME/review/<slug>/` :
  - `running/<session_id>` : vide, présent tant que la session travaille.
  - `pending/<repo>.json` : `{"count": int}`, écrit par l'extension.
  - `alive/<window_id>` : date de modification rafraîchie toutes les 10 s par l'extension.
  - `failed/<repo>.json` : `{"reason": str, "at": iso8601}`, retiré au prochain instantané réussi.
- Produces (Python) : `find_workspace(cwd: str, registry: dict) -> dict | None`, `snapshot(repo_path: str) -> str` (SHA), `on_prompt(payload: dict, home: str) -> None`, `on_stop(payload: dict, home: str) -> None`.

- [ ] **Step 1: Write the failing tests** dans `test_ws_review.py`, avec `unittest` et de vrais dépôts git temporaires

```python
def test_snapshot_keeps_branch_and_index(self):
    head, status = self.head(), self.status()
    self.write("new.txt", "x")
    snapshot(self.repo)
    assert self.head() == head and self.status() == status | {"?? new.txt"}
    assert self.ref_tree_has("new.txt")

def test_prompt_covers_each_repo_in_parallel(self): ...  # back et front ont chacun leur référence
def test_pending_keeps_baseline_when_window_alive(self): ...
def test_stale_alive_ignores_pending_and_moves_baseline(self): ...  # alive vieux de plus de 60 s
def test_repo_without_pending_moves_while_other_keeps(self): ...
def test_missing_optional_repo_is_skipped(self): ...
def test_index_lock_writes_failed_and_other_repo_succeeds(self): ...
def test_success_clears_previous_failed(self): ...
def test_running_created_then_removed_by_session_id(self): ...
def test_cwd_outside_registry_uses_git_toplevel(self): ...
def test_never_raises_on_invalid_json(self): ...
```

- [ ] **Step 2: Run** `python3 -m unittest plugins/ws/scripts/test_ws_review.py`. Expected: FAIL, module absent.

- [ ] **Step 3: Implement `ws-review.py`.** Sous-commandes `prompt` et `stop`, JSON lu sur stdin. `find_workspace` prend le `workspace_path` le plus long qui préfixe `cwd`, comme `ws-finish-preflight.sh`. Hors registre, slug = chemin de `git rev-parse --show-toplevel` avec les caractères non alphanumériques remplacés par `-`, et un seul repo. `snapshot` reprend `hooks/on-prompt.sh` du prototype, identité fixe et index temporaire copié de l'index réel compris. Repos en `ThreadPoolExecutor`. `WS_HOME` vaut `~/.claude-workspaces` par défaut. Toute exception finit en sortie 0 silencieuse.

- [ ] **Step 4: Run** the tests. Expected: PASS.

- [ ] **Step 5: Commit** `feat(ws-review): per-repo baseline snapshots on each prompt`

### Task 2: Branchement des hooks et mesure

**Files:**
- Modify: `plugins/ws/hooks/hooks.json`

**Interfaces:**
- Consumes: `ws-review.py prompt|stop` (Task 1).

- [ ] **Step 1: Ajouter** `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/ws-review.py" prompt` à `UserPromptSubmit`, après le hook existant, et `... stop` à `Stop`, `StopFailure`, `SessionEnd`.

- [ ] **Step 2: Vérifier le JSON.** Run: `python3 -m json.tool plugins/ws/hooks/hooks.json`. Expected: code 0.

- [ ] **Step 3: Mesurer** sur un worktree de 5 repos mergé, en ne touchant qu'à sa référence `refs/worktree/` : `time` sur 3 exécutions à chaud. Expected: moins de 300 ms, chiffres notés dans le commit.

- [ ] **Step 4: Vérifier** avec un vrai `claude -p --model haiku` dans un worktree mergé : chaque repo a sa référence et `running/` est vide à la fin.

- [ ] **Step 5: Commit** `feat(ws-review): wire review hooks into the plugin`

### Task 3: Extension et calcul des blocs

**Files:**
- Create dans le nouveau dépôt `~/projects/claude-review` : `package.json`, `tsconfig.json`, `esbuild.mjs`, `src/hunks.ts`, `src/hunks.test.ts`

**Interfaces:**
- Produces: `type Hunk = { oldStart: number; oldLines: string[]; newStart: number; newLines: string[] }`, `parseHunks(diff: string): Hunk[]`, `applyHunk(base: string, h: Hunk): string`, `revertHunk(current: string, h: Hunk): string | null` (`null` si le bloc a bougé).

- [ ] **Step 1: Porter les cas** de `extension/check.js` du prototype en tests Vitest, dont les 300 essais aléatoires, avec `applyHunk` et `revertHunk` en aller-retour sur du vrai `git diff --no-index -U0`.

- [ ] **Step 2: Run** `npx vitest run src/hunks.test.ts`. Expected: FAIL, module absent.

- [ ] **Step 3: Porter** `extension/hunks.js` en TypeScript strict. Commande déclarée : aucune encore.

- [ ] **Step 4: Run** the tests, puis `npx tsc --noEmit`. Expected: PASS.

- [ ] **Step 5: Commit** `feat: hunk parsing and apply, with round-trip tests`

### Task 4: Comparaison git par repo

**Files:**
- Create: `src/repo.ts`, `src/repo.test.ts`

**Interfaces:**
- Consumes: `Hunk`, `parseHunks` (Task 3).
- Produces: `type Change = { rel: string; status: 'A'|'M'|'D'; hunks: Hunk[]; kind: 'text'|'binary'|'large' }`, `class ReviewRepo { constructor(name: string, path: string); baseline(): Promise<string|null>; changes(): Promise<Change[]>; baselineText(rel: string): Promise<string|null>; advance(rel: string, content: string|null): Promise<void> }`.

- [ ] **Step 1: Write the failing tests**, sur de vrais dépôts temporaires : changement suivi, fichier non suivi, suppression, édition par `sh`, binaire, fichier de plus de 2 Mo, chemin `app/données client.rb`, et absence de nouvel objet dans `.git/objects` après `changes()`.

```ts
it('advance persists one accepted file across instances', async () => {
  await repo.advance('a.rb', 'accepted\n')
  expect(await new ReviewRepo('a', dir).baselineText('a.rb')).toBe('accepted\n')
  expect(head()).toBe(headBefore)
})
```

- [ ] **Step 2: Run** `npx vitest run src/repo.test.ts`. Expected: FAIL.

- [ ] **Step 3: Implement.** `changes()` : index temporaire, `git add -A`, `write-tree`, `git diff-tree -z`, avec `GIT_OBJECT_DIRECTORY` temporaire et `GIT_ALTERNATE_OBJECT_DIRECTORIES` pour ne laisser aucun objet orphelin. `advance()` : nouvel arbre depuis l'instantané avec le seul fichier remplacé ou retiré, `commit-tree`, `update-ref`. C'est ce qui rend les acceptations persistantes.

- [ ] **Step 4: Run** the tests. Expected: PASS.

- [ ] **Step 5: Commit** `feat: per-repo change detection and persistent accept`

### Task 5: État du worktree et moteur de revue

**Files:**
- Create: `src/state.ts`, `src/review.ts`, `src/review.test.ts`

**Interfaces:**
- Consumes: `ReviewRepo`, `Change` (Task 4), fichiers de la Task 1.
- Produces: `class ReviewState { isClaudeWorking(): boolean; failures(): Record<string,string>; beat(windowId: string): void; setPending(repo: string, count: number): void }`, `class ReviewEngine { refresh(): Promise<ReviewItem[]>; accept(item: ReviewItem): Promise<Result>; reject(item: ReviewItem, read: (rel: string)=>Promise<string>): Promise<Result>; next(from?: ReviewItem): ReviewItem|null }`, `type Result = 'ok'|'blocked-working'|'hunk-moved'`, `type ReviewItem = { repo: string; rel: string; hunk: Hunk|null }`.

- [ ] **Step 1: Write the failing tests** :

```ts
it('blocks while a live session works, and force overrides', ...)
it('ignores a running file whose session has no live pid', ...)  // via ~/.claude/sessions/*.json
it('two sessions: still working until the last one stops', ...)
it('reject refuses when the file changed since display', ...)    // 'hunk-moved', fichier intact
it('a user edit during a turn appears as a hunk', ...)
it('groups changes by repo and walks next across repos', ...)
```

- [ ] **Step 2: Run** `npx vitest run src/review.test.ts`. Expected: FAIL.

- [ ] **Step 3: Implement.** Le refus compare au texte relu juste avant d'écrire, comme `findLive` du prototype. `setPending` écrit `pending/<repo>.json` et retire le fichier à zéro.

- [ ] **Step 4: Run** the tests. Expected: PASS.

- [ ] **Step 5: Commit** `feat: review engine with multi-session state and race handling`

### Task 6: Intégration VS Code

**Files:**
- Create: `src/extension.ts`, `src/ui/decorations.ts`, `src/ui/lens.ts`, `src/plugin.ts`, `src/test/suite/review.test.ts`

**Interfaces:**
- Consumes: `ReviewEngine`, `ReviewState` (Task 5).
- Produces: commandes `claudeReview.accept`, `.reject`, `.next`, `.acceptAll`, `.rejectAll`, raccourcis des contraintes.
- Produces: `ensurePlugin(): { ok: true; scriptsDir: string } | { ok: false; reason: string }`.

- [ ] **Step 1: Write the failing test** avec `@vscode/test-electron`, sur un workspace à 2 repos : édition hors éditeur, CodeLens présentes, accepter un bloc dans `back`, refuser un bloc dans `front`, `next` traverse les deux, rechargement sans perdre l'acceptation. Reprendre les 16 contrôles du prototype.

- [ ] **Step 2: Run** `npm run test:vscode`. Expected: FAIL.

- [ ] **Step 3: Implement.** Reprendre le rendu de `extension/extension.js`. Repos résolus depuis `registry.json`, ou dossier git unique. Échec de repo et plugin absent affichés une fois. Message unique quand des blocs ont quitté la revue.

- [ ] **Step 4: Run** the tests. Expected: PASS.

- [ ] **Step 5: Commit** `feat: multi-repo review in VS Code`

### Task 7: Interface visible

**Files:**
- Modify: `src/ui/lens.ts`, `src/extension.ts`, `package.json`

**Interfaces:**
- Consumes: commandes de la Task 6.

- [ ] **Step 1: Montrer à Sébastien** une maquette de la barre de revue et du bloc courant. Contrainte : VS Code n'offre pas de barre libre posée dans l'éditeur. Candidats : boutons `editor/title`, élément de barre d'état coloré avec compteur, icônes de gouttière. Attendre son choix avant de coder.

- [ ] **Step 2: Write the failing test** : les commandes sont exposées à l'emplacement choisi et le compteur suit les blocs restants.

- [ ] **Step 3: Implement** le choix validé.

- [ ] **Step 4: Run** `npm run test:vscode`. Expected: PASS.

- [ ] **Step 5: Faire tester à Sébastien** sans lui indiquer où cliquer. Expected: il trouve Accepter seul.

- [ ] **Step 6: Commit** `feat: visible review controls`

### Task 8: Paquet et essai réel

**Files:**
- Create: `README.md`, `.vscodeignore`

- [ ] **Step 1: Construire** avec `npx vsce package`. Expected: un `.vsix` sans `node_modules` inutiles.

- [ ] **Step 2: Installer** le `.vsix` et le plugin à jour sur le Mac de Sébastien, dans un worktree multi-repo jetable créé pour l'occasion.

- [ ] **Step 3: Vérifier** un tour interactif touchant `back` et `front`, avec Échap en plein tour, Forcer, puis fermeture et réouverture de VS Code.

- [ ] **Step 4: Écrire** l'installation pour l'équipe dans le README, en une commande.

- [ ] **Step 5: Commit** `docs: install and first review`
