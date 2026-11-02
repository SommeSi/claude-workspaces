# Extension d'équipe : revue façon Cursor et dashboard de worktrees

Date : 2026-11-02. Statut : en attente de validation de Sébastien. Remplace la version Electron du même jour.

## Pourquoi

L'équipe SommeSi code avec Claude Code sur de nombreux worktrees multi-repo, via le plugin `workspace` (v0.8.24). Il manque deux choses : voir et valider ce que Claude vient de changer, comme dans Cursor, et avoir une vue d'ensemble des worktrees.

Le blocage du marché vient de la recherche et d'un test réel : Zed et la fenêtre Agents de VS Code ne font passer Claude que par une clé API ou Copilot, et la fenêtre Agents ne gère pas le multi-root. Sébastien refuse les clés API. Un prototype a validé le 2 novembre la revue par bloc sur le vrai `claude`, avec l'abonnement : `~/projects/claude-review-spike/`.

Un rapport interne (`~/projects/reports/Travail des équipes dev avec agents.md`) montre que le blocage du marché se situe à la revue. L'extension s'attaque à ce point, mais elle ne remplace pas une revue par un second humain.

## Objectifs, dans l'ordre de livraison

1. Revue bloc par bloc de ce que Claude a changé, sur un vrai workspace multi-repo.
2. Dashboard des worktrees classés par dernier message Claude, avec description courte.
3. Fermeture d'un worktree depuis le dashboard, avec contrôle et corbeille.

## Hors périmètre

Agents en cloud, vue partagée entre développeurs, serveur central, PR à relire dans l'appli, Windows et Linux. Rien de tout ça n'est bloqué par la conception.

## Échecs à éviter

- Exiger une clé API, ou utiliser l'Agent SDK ou `--bare`.
- Perdre du travail, par la revue comme par la fermeture.
- Ralentir ou faire échouer l'envoi d'un message à Claude.
- Dupliquer la logique du plugin, qui finirait par diverger.
- Présenter l'acceptation d'un bloc comme une revue de code : elle reste une validation par l'auteur.

## Contraintes et décisions

- **Abonnement seulement (Sébastien).** Tout passe par le vrai `claude`, lancé dans un terminal VS Code. Toute fonction automatique qui appelle `claude -p` a un repli sans IA.
- **Extension VS Code (Sébastien).** Pas d'Electron. Theia ou un fork seulement face à un blocage réel. Le code de revue et de dashboard reste séparé de l'API VS Code autant que possible.
- **Exigence de qualité (Sébastien).** « Un truc bien » plutôt qu'un truc rapide : ce n'est pas un portage du prototype, mais une version testée.
- **Une fenêtre VS Code par worktree (décision de Claude).** Changer de dossier recharge la fenêtre et coupe ses terminaux.
- **Plateforme (décision de Claude).** macOS. Hypothèse à confirmer pour toute l'équipe.

## 1. Revue bloc par bloc

### Fonctionnement validé par le prototype

- Un hook `UserPromptSubmit` prend un instantané du worktree dans un commit, avec un index temporaire, sans toucher à la branche, à l'index réel ni aux fichiers.
- `Stop`, `StopFailure` et `SessionEnd` retirent l'indicateur « Claude travaille ».
- L'extension compare les fichiers à l'instantané : les éditions faites par Bash sont donc visibles.
- Refuser un bloc réapplique l'inverse dans le fichier puis l'enregistre. Accepter avance la référence pour ce seul bloc.
- Tant que des blocs ne sont pas relus, l'instantané ne bouge pas et les changements s'accumulent.
- Accepter et Refuser sont bloqués pendant que Claude travaille, avec un bouton Forcer, car `Stop` ne se déclenche peut-être pas sur Échap. Avant d'appliquer, l'extension relit le fichier et refuse si le bloc a bougé.

Mesures du prototype : hook sous 100 ms à chaud sur le dépôt de démo, 45 ms environ sur `back`.

### Ce qui doit changer par rapport au prototype

- **Multi-repo :** le prototype ne traite qu'un repo. Le worktree SommeSi est un dossier non git avec `back`, `front`, etc. Le hook doit couvrir chaque repo du workspace, en parallèle, en lisant le registre, et la revue doit les regrouper. C'est le plus gros point à construire et il n'a pas été testé.
- **Hooks distribués par le plugin `workspace`,** et non plus dans `.claude/settings.local.json`, pour toute l'équipe.
- **Référence par worktree :** `refs/worktree/claude-review/baseline`, car la référence du prototype est partagée entre worktrees.
- **Persistance :** les acceptations survivent à un rechargement de la fenêtre.
- **État `pending` fiable :** il ne doit pas figer l'instantané si VS Code a été fermé.
- **Interface visible :** les CodeLens grises sont trop discrètes, Sébastien ne les a pas vues. Ajouter une barre flottante ou une action nette sur le bloc courant, façon Cursor, avec le compteur de blocs. Forme à valider sur maquette. Les raccourcis fonctionnent sur AZERTY.
- **Nettoyage :** les objets orphelins créés par les comparaisons ne doivent pas s'accumuler.

## 2. Dashboard

Vue dans VS Code, dans une webview. Une vue dans la barre latérale et un panneau complet sont laissés au choix du constructeur, tant que la « version B » reste respectée :

- Les 4 worktrees les plus récents en carrés, tous les autres en liste compacte.
- Par worktree : pastille de couleur, nom, description, date du dernier message, sessions ouvertes, fichiers modifiés.
- Worktrees sans message en bas, par date de création. `agent-*` masqués par défaut.
- Un badge « PR mergée ». Il ne prouve pas que le sujet est fini.
- Un clic ouvre ou ramène la fenêtre du worktree, sur son `.code-workspace`, via `vscode.openFolder` en nouvelle fenêtre. Le comportement sur une fenêtre déjà ouverte reste à vérifier.

| Donnée | Source |
|---|---|
| Worktrees | `~/.claude-workspaces/registry.json`, plus le contenu de `~/projects/worktrees` |
| Dernier message | `~/.claude/projects/<chemin encodé>*/*.jsonl`, dernier `user` ou `assistant` avec `timestamp` |
| Sessions ouvertes | `~/.claude/sessions/*.json`, `cwd` dans le worktree et `pid` vivant |
| Fichiers modifiés | `git status` par repo, filtré avec les motifs `NOISE` de `ws-finish-preflight.sh` |
| PR | `gh pr list --head <branche>`, avec cache |

Le chemin encodé remplace tout caractère non alphanumérique par `-`. Un script a classé 16 worktrees en 2,4 s sur le Mac de Sébastien, sans les appels `gh`. Le `pid` peut compter une session à tort, `procStart` peut aider à le fiabiliser.

**Description.** Claude résume les derniers messages en une ligne, en français, avec mise en cache par worktree et régénération seulement après un nouveau message. Sans résumé disponible : titre de PR, puis nom de branche. Le coût n'est pas mesuré.

## 3. Fermeture et corbeille

Un worktree hors registre ou en mode `attached` n'a pas de bouton de fermeture.

1. Lancer `ws-finish-preflight.sh <chemin>`, lecture seule, avec un état de chargement car il fait un `git fetch`.
2. Lire `OVERALL`, `WS_PATH`, `WS_SLOT`. Si l'un manque, aucune suppression n'est proposée. Les autres clés sont lues avec tolérance.
3. Fenêtre selon `OVERALL` (maquette `fermer-worktree.html`) :
   - `safe` : Annuler ou Fermer le worktree.
   - `warn` : liste de ce qui serait perdu, puis Annuler, Demander à Claude de vérifier, ou Supprimer quand même.
   - `none` : pas de suppression.
4. Le choix par défaut ne supprime rien.
5. Sauvegarder dans la corbeille. Si cela échoue sur un repo, annuler.
6. Lancer `ws-destroy.sh` avec `CONFIG` et `PROJECT_ROOT`. Il tue les ports, supprime les bases `_w<slot>`, retire les worktrees et le dossier.

Les sessions ouvertes s'affichent en avertissement, sans jamais bloquer. « Demander à Claude de vérifier » lance `claude -p` en lecture seule dans le worktree et affiche la réponse dans la fenêtre. La fermeture fait seulement le nettoyage local, sans Notion ni historique de livraison, et le dit.

**Corbeille.** `ws-destroy.sh` garde les branches locales, mais efface fichiers non commités et nouveaux fichiers. Avant lui, pour chaque repo :
1. Instantané des fichiers suivis et des nouveaux fichiers non ignorés, dans un commit avec index temporaire.
2. Référence `refs/trash/<slug>/<date>` dans le repo principal, avec le SHA de la branche.
3. Vérification que la référence existe.
4. Ligne dans `~/.claude-workspaces/trash.jsonl`.

Une vue Corbeille affiche l'âge des entrées, propose Restaurer et Purger, avec confirmation. Rien n'expire tout seul.

Limites assumées : corbeille locale au Mac, fichiers ignorés et bases `_w<slot>` non sauvés, fichiers de plus de 50 Mo exclus et signalés avant fermeture.

## Règles d'état (décisions de Claude après relecture)

- **Propriété :** le plugin `workspace` possède les hooks et leurs scripts. L'extension exige le plugin et une version minimale, et l'annonce clairement sinon. Elle ne modifie aucun réglage de Claude Code.
- **Emplacement de l'état :** par worktree, sous `~/.claude-workspaces/review/<slug>/`. Seule la référence d'instantané reste dans chaque repo.
- **Claude travaille :** état du worktree entier, avec un fichier par `session_id`. Le hook de début le crée, `Stop`, `StopFailure` et `SessionEnd` le retirent, et un fichier dont le processus est mort est ignoré. Le worktree travaille si au moins un fichier est valide. Plusieurs sessions et plusieurs fenêtres sont donc gérées.
- **Instantané par repo :** si `front` n'a aucun bloc en attente, il reçoit un nouvel instantané à chaque message, même si `back` en a. Si un instantané échoue, la revue de ce repo se désactive et l'échec est affiché. Le message à Claude part quand même.
- **Blocs en attente :** l'extension renouvelle un signal de vie. Si le signal est périmé, le hook ignore `pending` et avance l'instantané. Les blocs non relus sortent alors de la revue, les fichiers ne changent pas, et la revue suivante l'indique une fois.
- **Fenêtre `warn` :** elle affiche tel quel le récapitulatif du contrôle, partie avant `===WS-FINISH-MACHINE===`. `WS_MODE` y est lu, le registre servant à masquer le bouton en amont.
- **Clic :** le `.code-workspace` s'il existe, sinon le dossier du worktree. Tout worktree présent sur disque reste cliquable.
- **Restaurer :** recréer le workspace avec les scripts du plugin, sur sa branche, puis réappliquer l'instantané. Les bases sont neuves, et la fenêtre de restauration le dit. Si le repo principal a disparu, la corbeille correspondante est perdue.
- **Résumés :** générés seulement à l'ouverture du dashboard, pour les worktrees avec un nouveau message, un seul à la fois, au plus 20 par heure, avec le modèle le plus léger disponible, et un réglage pour les couper.

## Dépendance au plugin

L'extension trouve les scripts via `~/.claude/plugins/installed_plugins.json`. Le format de sortie de `ws-finish-preflight.sh` devient un contrat entre plugin et extension.

## Tests

Le calcul des blocs garde des tests automatiques, dont des essais aléatoires. La revue multi-repo, la persistance et la corbeille ont des tests dans un vrai VS Code et sur de vrais dépôts git. La restauration depuis la corbeille est testée avant toute utilisation sur un vrai worktree.

## Laissé au constructeur

Structure du projet, emplacement du repo hors du plugin, composants, gestion du cache, fréquence de rafraîchissement, distribution interne en `.vsix`, découpage en PR.

## Décisions prises par Claude, à relire

- Une fenêtre VS Code par worktree.
- Tri des worktrees sans message par date de création, `agent-*` masqués.
- Fermeture limitée au nettoyage local.
- Corbeille locale, sans expiration, seuil de 50 Mo.
- Sessions ouvertes en simple avertissement.
- Pas de bouton de fermeture hors registre ou en `attached`.
- `claude -p` en lecture seule pour la vérification.
- macOS seulement au départ.
