---
allowed-tools: Bash(pg_dump *), Bash(pg_restore *), Bash(psql *), Bash(curl *), Bash(cat *), Bash(grep *), Bash(awk *), Bash(sed *), Bash(echo *), Bash(test *), Bash(read *)
description: Copie tes données locales vers la DB playground (Postgres)
disable-model-invocation: false
---

> **Pour l'utilisateur non-technique** : tu as des données dans ta base locale (= la base PostgreSQL qui tourne sur ton Mac) et tu veux les retrouver sur `playground.sommesi.com` pour tester ta feature avec ? Lance cette commande, c'est tout.
>
> - Pas besoin de comprendre `pg_dump`, `pg_restore`, ou la moindre commande Postgres.
> - Playground n'accueille **qu'un seul jeu de données à la fois** — tes données vont remplacer ce qui était là (c'est voulu).
> - L'opération ne touche **pas du tout** à ton code ni à git — c'est purement de la donnée.

Copie le contenu de ta DB Postgres locale (= du worktree si tu es dans un worktree, sinon la DB de dev par défaut) vers la DB Postgres de playground (= hébergée chez Scaleway). À la fin, la DB playground contient exactement ce que tu avais en local.

## Étape 0 — Vérifier les pré-requis système

Avant tout, vérifie que ces outils sont installés (= disponibles sur la machine de l'utilisateur) :

```bash
for tool in pg_dump pg_restore psql curl; do
  command -v "$tool" >/dev/null 2>&1 || MISSING="$MISSING $tool"
done
```

Si quelque chose manque, **STOP** :
> "Outils manquants :<MISSING>. Installe-les avec `brew install postgresql@16 curl` puis relance."

## Étape 1 — Détecter la DB source locale

1. Repère la racine du worktree (= dossier de travail isolé). Il contient `back/` (= le code du serveur).
2. **Si `back/.env.local` existe** (= source de vérité pour Rails dans un worktree) : extrais la `DATABASE_URL` :
   ```bash
   SOURCE_URL=$(grep -E '^DATABASE_URL=' back/.env.local | head -1 | sed -E 's|^DATABASE_URL=||; s|^"||; s|"$||')
   ```
3. **Sinon, fallback** : utilise la DB de développement par défaut. Lis `back/config/database.yml`, section `development`, et reconstruis l'URL :
   ```
   SOURCE_URL="postgresql://localhost:5432/<database_name>"
   ```
   (Si l'utilisateur a un user/password local, lis-les aussi depuis le yml.)
4. **Vérifier que la source contient des tables** (sinon il n'y a rien à pousser) :
   ```bash
   TABLE_COUNT=$(psql "$SOURCE_URL" -t -A -c "SELECT count(*) FROM information_schema.tables WHERE table_schema='public';" 2>/dev/null)
   ```
   - Si vide ou 0, **STOP** :
     > "Ta DB locale (`<SOURCE_URL>`) est vide — il n'y a rien à pousser. Lance d'abord les seeds/migrations dans ton worktree."

## Étape 2 — Récupérer l'URL de la DB playground

L'URL de la DB playground est stockée localement dans `~/.config/sommesi/playground.env` (= fichier secret partagé une fois pour toutes par dépôt → utilisateur).

```bash
PLAYGROUND_ENV="$HOME/.config/sommesi/playground.env"
if [ -f "$PLAYGROUND_ENV" ]; then
  PLAYGROUND_URL=$(grep -E '^PLAYGROUND_DATABASE_URL=' "$PLAYGROUND_ENV" | head -1 | sed -E 's|^PLAYGROUND_DATABASE_URL=||; s|^"||; s|"$||')
fi
```

Si `PLAYGROUND_URL` est vide ou si le fichier n'existe pas, **STOP** avec des instructions claires :

> "Je n'ai pas trouvé l'URL de la DB playground.
>
> **Pour la configurer** (une seule fois) :
>
> 1. Va sur la [console Scaleway](https://console.scaleway.com) → Managed Databases → instance playground → copie la "Connection string".
> 2. Crée le fichier :
>    ```bash
>    mkdir -p ~/.config/sommesi
>    echo 'PLAYGROUND_DATABASE_URL=postgresql://USER:PASSWORD@HOST:PORT/DBNAME' > ~/.config/sommesi/playground.env
>    chmod 600 ~/.config/sommesi/playground.env
>    ```
> 3. Relance `/playground-deploy:push-data`."

## Étape 3 — Vérifier l'accès réseau à playground (= ACL Scaleway)

La DB playground est protégée par une liste d'IPs autorisées (= ACL, Access Control List). On tente une connexion rapide pour vérifier que l'IP publique de l'utilisateur est bien dans la liste :

```bash
if ! timeout 5 psql "$PLAYGROUND_URL" -c "SELECT 1;" >/dev/null 2>&1; then
  MY_IP=$(curl -s --max-time 5 ifconfig.me)
  # STOP avec message ACL
fi
```

Si la connexion échoue (timeout ou refus), **STOP** :

> "Impossible de me connecter à la DB playground depuis ton IP.
>
> Ton IP publique : `<MY_IP>`
>
> **Pour autoriser ton IP** :
>
> 1. Va sur la [console Scaleway](https://console.scaleway.com) → Managed Databases → instance playground → onglet **"Allowed IPs"**.
> 2. Clique **"Add IP"** → colle `<MY_IP>/32` → enregistre.
> 3. Attends 30 secondes que ça se propage.
> 4. Relance `/playground-deploy:push-data`.
>
> (Si l'IP est déjà autorisée, le souci vient peut-être de l'URL playground dans `~/.config/sommesi/playground.env` — vérifie qu'elle est correcte.)"

## Étape 4 — Récap + confirmation

Calcule la taille estimée de la DB source (= ordre de grandeur, pas exact) :

```bash
SOURCE_SIZE=$(psql "$SOURCE_URL" -t -A -c "SELECT pg_size_pretty(pg_database_size(current_database()));")
```

Affiche un récap clair :

```
📤 Push de tes données locales vers playground :

   source : <SOURCE_URL_masqué_password>
            (<TABLE_COUNT> tables, ~<SOURCE_SIZE>)

   cible  : <PLAYGROUND_URL_masqué_password>

⚠️  Toutes les données actuellement sur playground seront ÉCRASÉES.

Tape `yes` pour confirmer :
```

(Pour masquer le mot de passe dans l'affichage : `echo "$URL" | sed -E 's|://([^:]+):[^@]+@|://\1:****@|'`.)

Lis la saisie de l'utilisateur. **Si autre chose que `yes` (exact, sensible à la casse), abort proprement** :
> "Annulé. Aucune donnée n'a été modifiée."

## Étape 5 — Dump + restore (streaming)

Lance le transfert en pipe (= les données circulent directement de la source vers la cible, sans fichier intermédiaire sur disque) :

```bash
pg_dump \
  --format=custom \
  --no-owner \
  --no-acl \
  --no-privileges \
  --no-comments \
  "$SOURCE_URL" \
  | pg_restore \
      --clean \
      --if-exists \
      --no-owner \
      --no-acl \
      --exit-on-error \
      --dbname="$PLAYGROUND_URL"
```

- `--format=custom` : format binaire optimisé.
- `--clean --if-exists` : nettoie les tables existantes sur playground avant restore (= c'est ça qui écrase les données précédentes).
- `--exit-on-error` : on s'arrête à la première erreur (pas de restore partiel).
- `--no-comments` : évite les soucis si des extensions Postgres (`pg_trgm`, `uuid-ossp`, etc.) sont déclarées par des commentaires que la cible ne supporte pas exactement pareil.

Affiche la sortie de `pg_restore` en temps réel (pas de filtrage agressif — l'utilisateur veut voir que ça avance, mais reste concis dans le récap final).

## Étape 6 — Gestion d'erreurs spécifiques

Pendant ou après le dump/restore, certains messages d'erreur méritent une explication dédiée :

### Version mismatch (`pg_dump: error: server version: 16.x; pg_dump version: 14.x`)

> "Ton `pg_dump` local (= la commande qui exporte les données) est en version X, mais la DB playground tourne en version Y. Il te faut une version de Postgres au moins aussi récente.
>
> Installe-la avec :
> ```bash
> brew install postgresql@<Y>
> brew link --force --overwrite postgresql@<Y>
> ```
> Puis relance la commande."

### Schéma incompatible (`relation "X" does not exist` ou `column "Y" does not exist`)

> "Le schéma de ta DB locale ne correspond pas à celui de playground. Ça arrive quand tes migrations locales sont en avance (ou en retard) par rapport à ce qui tourne sur playground.
>
> **Solution** :
> 1. Lance d'abord `/playground-deploy:preview` (qui resynchronise le schéma de playground sur celui de ta branche).
> 2. Puis relance `/playground-deploy:push-data`."

### Extension manquante (`could not open extension control file ... extension "X" does not exist`)

> "L'extension Postgres `<X>` est utilisée par ta DB locale mais n'est pas activée sur playground. Demande à un dev d'ajouter l'extension côté Scaleway, ou retire-la de tes seeds locaux."

## Étape 7 — Succès

Si tout s'est bien passé :

```
✅ Données poussées sur playground.
   Va vérifier sur https://playground.sommesi.com
```

## Garde-fous

- **Aucune modification git**, **aucun push**, **aucun déploiement** déclenché. C'est purement une opération DB.
- **Aucune écriture** dans le worktree de l'utilisateur (à part éventuellement un fichier temporaire qui doit être nettoyé en fin de commande).
- **Pas d'autre demande de confirmation** que le `yes` final.
- **Ne JAMAIS afficher** le mot de passe complet d'une URL Postgres dans la sortie (masquer avec `:****@`).
