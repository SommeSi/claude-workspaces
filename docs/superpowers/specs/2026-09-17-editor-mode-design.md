# Mode éditeur (VS Code) + récap des fichiers modifiés par tour — Design

**Date** : 2026-09-17
**Plugin** : `workspace` (`plugins/ws`), version actuelle 0.8.14
**Statut** : validé en brainstorming, en attente de relecture

## Objectif

Reprendre la main sur le code quand on travaille en workspace : articuler le workspace autour de **VS Code** (pas Cursor) plutôt que de la grille WezTerm, et afficher à la fin de chaque tour de Claude **la liste cliquable des fichiers qu'il a modifiés**, comme le faisait Cursor.

## Contrainte principale : non-régression

- Les modes existants de `/workspace:open` (1. WezTerm, 2. Background) ne changent pas. `ws-open.sh` n'est pas modifié.
- Les hooks existants (`Stop` → `notify.sh`, `ws-progress-capture.sh` ; `PostCompact` ; `Notification`) ne changent pas. Les nouveaux hooks sont **ajoutés** à la suite.
- Les nouveaux hooks ne peuvent jamais bloquer ni faire échouer un tour : `exit 0` systématique, timeout court, silencieux hors workspace.

## Partie 1 — Option « VS Code » dans `/workspace:open`

### Déclenchement

Uniquement par choix explicite : 3ᵉ option du menu de `/workspace:open` (Step 1d). Pas d'ouverture automatique à la fin de `start-worktree`, pas de nouvelle clé de config.

```
How do you want to launch the servers?
1. WezTerm — separate terminal panes (requires WezTerm)
2. Background — launch servers as background processes in this Claude session
3. VS Code — open the editor with servers in integrated terminals + Claude Code tab
```

### Nouveau script `scripts/ws-open-editor.sh <workspace_path>`

1. **Détection du workspace** : même lookup registry que `ws-open.sh` (longest-prefix sur `workspace_path` et `repos[].path`), même chargement de `.claude-workspaces.json`.
2. **Prérequis** : la CLI `code` doit exister (`command -v code`, sinon `/usr/local/bin/code`). Sinon : message d'erreur explicite (« Shell Command: Install 'code' command in PATH ») et `exit 1`.
3. **Tâches** : écrit/fusionne une section `tasks` dans `<workspace_path>/<slug>.code-workspace` :
   - Source : `terminal.panes` de la config. Une tâche par pane dont `cmd` est non nul. Les panes `cmd: null` sont ignorés.
   - Sans section `terminal` : pas de tâches générées ; le script l'indique (la détection automatique des commandes reste faite par le skill, comme le mode Background, qui passe alors les panes au script — voir « Interface skill ↔ script »).
   - Forme d'une tâche :
     ```json
     {
       "label": "ws: front — bun run dev",
       "type": "shell",
       "command": "bun run dev",
       "options": { "cwd": "/abs/path/to/workspace/front" },
       "isBackground": true,
       "problemMatcher": [],
       "presentation": { "panel": "dedicated", "reveal": "always", "group": "ws-servers" },
       "runOptions": { "runOn": "folderOpen" }
     }
     ```
   - Substitution dans `cmd` au moment de l'écriture : `$PORT` (port du repo), `$SLOT`, `$BRANCH` — mêmes règles que le mode Background.
   - `repo: "."` → `cwd` = `workspace_path`.
   - Fusion : on conserve `folders` et `settings` existants ; on remplace uniquement les tâches dont le label commence par `ws: ` (idempotent, les tâches perso de l'utilisateur sont préservées).
   - Mono-repo : aucun `.code-workspace` n'existe aujourd'hui → le script le crée avec `folders: [{ "path": "<repo>" }]` et les couleurs du workspace (mêmes `workbench.colorCustomizations` que `ws-generate-files.sh`).
4. **Ouverture** : `code "<workspace_path>/<slug>.code-workspace"`.
5. **Onglet Claude** : si `terminal.claude_tab` est vrai (ou absent de la config), `open "vscode://anthropic.claude-code/open"` (macOS ; `xdg-open` sous Linux). URI documentée : https://code.claude.com/docs/en/vs-code.md.

### Skill `skills/open/SKILL.md`

- Step 1d : ajoute l'option 3. Si `code` est absent, l'option 3 n'est pas proposée.
- Nouveau Step 7 (VS Code flow) : recap + confirmation (même format que les autres modes : dossiers, tâches, onglet Claude), puis `ws-open-editor.sh`, puis résumé.
- Mentionner dans le résumé : au premier lancement, VS Code demande « Allow automatic tasks » — répondre « Allow ».
- `description`/`trigger` du frontmatter : ajouter « vs code, editor ».

### Interface skill ↔ script

Le script lit `terminal.panes` depuis la config. Si la config n'a pas de section `terminal`, le skill détecte les commandes (règles du Step 6a) et les passe via une variable d'environnement `WS_PANES_JSON` (même format que `panes`). Le script donne priorité à `WS_PANES_JSON` si elle est définie.

## Partie 2 — Récap des fichiers modifiés pendant le tour

### Hooks (ajoutés à `hooks/hooks.json`)

- `UserPromptSubmit` → `scripts/ws-turn-snapshot.sh` (timeout 5 s)
- `Stop` → `scripts/ws-turn-diff.sh` (timeout 5 s), **après** les deux hooks `Stop` existants

### Détection du workspace et des repos

Même logique que `ws-progress-capture.sh` : remonter depuis `PWD` jusqu'à un `CLAUDE.local.md` contenant `## Workspace info` (fallback registry), puis repos = dossiers contenant `.git` à profondeur ≤ 2. Hors workspace → `exit 0` sans sortie.

### Snapshot (`ws-turn-snapshot.sh`)

- Lit `session_id` dans le JSON stdin.
- Pour chaque repo : `git status --porcelain -z --untracked-files=all` → pour chaque chemin, empreinte = `git hash-object <fichier>` (ou `DELETED` si absent).
- Écrit `$TMPDIR/ws-turn/<session_id>.json` : `{ "<repo_abs_path>": { "<rel_path>": "<hash|DELETED>" } }`.
- Rien n'est écrit dans les repos.

### Diff (`ws-turn-diff.sh`)

- Relit le snapshot de la session. Pas de snapshot → `exit 0` silencieux.
- Refait le même relevé. Un fichier est « modifié pendant le tour » si :
  - présent à la fin, absent au début (il était propre ou n'existait pas), ou
  - présent au début et à la fin avec une empreinte différente, ou
  - présent au début, absent à la fin (revenu à l'état commité → affiché `R` pour « rétabli »).
- Statut affiché : `A` (non suivi / ajouté), `M` (modifié), `D` (supprimé), `R` (rétabli).
- Aucun fichier → pas de sortie.
- Sinon, sortie JSON `{"systemMessage": "..."}` :
  ```
  📝 3 fichiers modifiés ce tour
    back   M [app/models/account.rb](vscode://file//abs/ws/back/app/models/account.rb:1)
    front  A [src/features/account/AccountCard.tsx](vscode://file//abs/ws/front/src/features/account/AccountCard.tsx:1)
    front  D src/old.ts
  ```
  - Fichiers supprimés : pas de lien.
  - Au-delà de 20 fichiers : les 20 premiers + « … et N autres ».
- Supprime le snapshot après lecture.
- Chemins encodés pour l'URI (espaces, caractères spéciaux).

### Liens cliquables

Cible : un clic ouvre le fichier dans VS Code, depuis le panneau de l'extension comme depuis WezTerm. `vscode://file/<abs>:<ligne>` est le handler standard de VS Code. Le format exact (lien markdown, URI brute, chemin absolu) est **choisi par le spike** (ci-dessous) selon ce que rend cliquable le panneau de l'extension.

## Spike préalable (étape 1 de l'implémentation)

La doc ne précise pas où l'extension VS Code affiche le `systemMessage` d'un hook `Stop`, ni si les liens y sont cliquables. Avant toute implémentation de la partie 2 :

1. Hook `Stop` jetable dans un projet de test, qui émet un `systemMessage` contenant : un lien markdown `vscode://file/…`, une URI brute `vscode://file/…`, un chemin absolu.
2. Vérifier dans l'extension VS Code **et** dans la CLI (WezTerm) : le message s'affiche-t-il ? lequel des trois formats est cliquable ?
3. Décision :
   - Affiché + un format cliquable → retenir ce format.
   - Affiché mais rien de cliquable → garder le récap, chemins absolus (cliquables au moins en terminal via détection de chemins).
   - Non affiché dans l'extension → repli : notification desktop via `notify.sh` (« 📝 3 fichiers modifiés ») + écriture du récap cliquable dans `<workspace>/.claude/last-turn.md` et `code -r` n'est **pas** lancé automatiquement (intrusif) ; le chemin du fichier est donné dans la notif.

Le spike est jetable : aucun code conservé.

## Tests

Pas de framework de test dans le repo (scripts bash + markdown). Un script de vérification `scripts/test-ws-turn.sh` :
- crée un repo git temporaire dans `$TMPDIR` avec un faux `CLAUDE.local.md` de workspace ;
- cas : fichier propre modifié (M), nouveau fichier (A), fichier supprimé (D), fichier déjà sale avant le tour et non retouché (absent du récap), fichier déjà sale retouché (M), fichier sale remis à l'état commité (R), aucun changement (pas de sortie), hors workspace (pas de sortie), snapshot manquant (pas de sortie) ;
- `assert` via comparaison de sortie ; `exit 1` au premier échec.

Pour `ws-open-editor.sh` : vérification manuelle sur le workspace mono-app (3 tâches créées, `.code-workspace` fusionné sans perte de `folders`/`settings`, relance idempotente, onglet Claude ouvert) + mono-repo (fichier créé).

## Hors périmètre

- Ouverture automatique de VS Code en fin de `start-worktree`.
- Support Cursor pour ce mode.
- Suppression du mode WezTerm.
- Accepter/refuser les modifications depuis le récap (VS Code le fait déjà pendant le tour en mode manuel ; checkpoints pour revenir en arrière).

## Fichiers touchés

| Fichier | Changement |
|---|---|
| `plugins/ws/scripts/ws-open-editor.sh` | nouveau |
| `plugins/ws/scripts/ws-turn-snapshot.sh` | nouveau |
| `plugins/ws/scripts/ws-turn-diff.sh` | nouveau |
| `plugins/ws/scripts/test-ws-turn.sh` | nouveau |
| `plugins/ws/hooks/hooks.json` | ajout `UserPromptSubmit` + 1 hook `Stop` en fin de liste |
| `plugins/ws/skills/open/SKILL.md` | option 3 + Step 7 |
| `plugins/ws/README.md`, `README.md` | doc du mode VS Code et du récap |
| `plugins/ws/.claude-plugin/plugin.json` | bump version (géré par l'utilisateur) |
