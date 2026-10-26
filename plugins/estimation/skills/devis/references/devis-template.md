# Modèle de devis client (page Notion)

Mise en page reprise de la « vue devis » Filiz, adaptée aux trois mesures du skill. On recopie la partie « Modèle » dans une page Notion et on remplace les `{…}`.

## Règles (à ne pas recopier dans la page)

- **Jours affichés = temps humain** : attention (piloter Claude, relire, tester), recette avec le client et échanges, y compris ce qui se passe hors de Claude (réunions, appels). Partir de la fiche interne : somme des heures basses ÷ 7 h pour la borne basse, somme des heures hautes ÷ 7 h pour la borne haute, arrondi au quart de jour supérieur (0,25 / 0,5 / 0,75). La base de 7 h est une convention à confirmer. Le temps Claude n'entre pas dans les jours affichés.
- **Toujours une fourchette** « bas à haut » sur ce qui dépend d'une inconnue (accès, format, règle comptable). Ce qui ne dépend de rien est chiffré ferme : une seule valeur.
- **Jamais dans la page** : heures Claude, noms internes, autres clients, noms de code, outils internes. Pas de prix ni de taux journalier, sauf demande explicite.
- **Marge** : si une marge commerciale est ajoutée, l'écrire en clair (« marge de 15 % incluse ») au lieu de la répartir dans les lignes.
- **Vérifier les sommes** : sous-parties = étape, étapes = lot, lots = synthèse, synthèse = total annoncé.
- Chaque sous-partie dit ce qu'elle apporte : **Sécurité**, **Tests**, **Reprise sur erreur**, **Recette**.
- La recette, la mise en production et les échanges sont **toujours une étape à part** : c'est du temps de vérification, il ne se raccourcit pas.

---

## Modèle

Icône 🧾 · Titre : `Devis — {Connecteur Source → Cible | Nom de la fonctionnalité}` · sous-page de la page de la feature.

> {Ce que fait la livraison, en une phrase} pour {Client}. Chiffrage en jours de travail de notre équipe. Version du {JJ/MM/AAAA}.

# Synthèse

| Lot | Résultat pour {Client} | Jours |
|---|---|---|
| **Lot 1 — {titre}** | {ce que le client obtient, en mots métier} | **{bas} à {haut}** |
| **Lot 2 — {titre}** | {…} | **{valeur ferme}** |

**Total : {bas} à {haut} jours.** Options et hors périmètre en fin de document.

## Pourquoi une fourchette

{La cause en une phrase : accès de test pas encore transmis, format non documenté, règle comptable à valider…}

- **Borne basse** : {ce qui se passe si tout est conforme, par exemple les réponses correspondent à la documentation}.
- **Borne haute** : {ce qui se passe si l'inconnue tourne mal, par exemple des écarts sur les vraies données}.
- **Engagement** : nous resserrons le chiffrage dans les {2} jours ouvrés qui suivent {la réception des accès}.

Seules les parties qui dépendent de {l'inconnue} sont en fourchette ; le reste est chiffré ferme. Les étapes {1.1, 1.5} peuvent démarrer sans attendre, sur des données simulées.

## Ce que comprend un jour chiffré

> Un jour correspond au temps réellement passé par notre équipe : conception, développement assisté par IA, relecture du code par un second développeur, tests automatisés, essais sur les environnements de test, recette avec vous et échanges.
>
> {Pourquoi la fiabilité prime. Exemple pour un connecteur comptable : il n'a pas droit à l'erreur silencieuse. Une facture en double, oubliée ou imputée sur le mauvais compte fausse la comptabilité, la TVA et le recouvrement.} L'essentiel du temps va donc à la **vérification** : cas limites, essais sur des données réelles, recette.

## Comment lire ce chiffrage

- Chaque étape est découpée en sous-parties. Pour chacune, la colonne « Ce que ça apporte » dit à quoi sert le temps : **sécurité** des accès et des données, **tests** automatiques, **reprise sur erreur** (rien ne se perd, rien ne se crée en double), **recette** avec vous.
- Les jours mesurent le travail, pas la durée. Le calendrier dépend surtout de ce dont nous avons besoin de votre côté (voir plus bas).
- Une hypothèse qui se révèle fausse peut changer le périmètre. Nous la chiffrons alors avant de démarrer.

## Sécurité et données

Dans tous les lots :
- {accès stockés chiffrés, un accès par entité} ;
- {notifications reçues vérifiées par signature, échanges en HTTPS} ;
- {documents conservés le temps du transfert seulement} ;
- {journaux sans données personnelles, historique conservé pour l'audit}.

---

# Lot 1 — {titre} ({bas} à {haut} j)

| Étape | Jours |
|---|---|
| 1.1 {titre} | {…} |
| 1.2 {titre} | {bas} à {haut} |
| 1.{n} Recette, démonstration et mise en production | {bas} à {haut} |
| **Total lot 1** | **{bas} à {haut}** |

## 1.1 {Titre} ({jours} j)

**Enjeu** : {une phrase côté client : ce qui casse si cette étape est mal faite}.

| Sous-partie | Ce qui est livré | Ce que ça apporte | Jours |
|---|---|---|---|
| {nom} | {résultat concret} | **Sécurité** : {…} | {0,25} |
| {nom} | {…} | **Reprise sur erreur** : {…} | {0,5 à 0,75} |

{Répéter pour chaque étape. Pour une écriture dans un outil du client, l'écrire en gras : « On **écrit dans votre logiciel comptable** ». Pour une partie non chiffrable, mettre « À chiffrer » et dire à réception de quoi.}

# Ce dont nous avons besoin de votre côté

| Ce qu'il nous faut | Pour quelle étape | Date souhaitée | Si c'est en retard |
|---|---|---|---|
| {Accès de test (sandbox, clés) à l'outil source} | {1.2 à 1.4} | {JJ/MM} | **Bloquant** : chaque semaine de retard décale d'autant la livraison |
| {Réponses aux questions des hypothèses} | {1.3} | {JJ/MM} | {la fourchette reste large} |
| {Fichiers d'exemple ou export de données réelles} | {1.2} | {JJ/MM} | {…} |
| {Validation des correspondances par votre comptable} | {1.3} | {JJ/MM} | {…} |
| {Disponibilité pour la recette : {n} demi-journées} | {1.{n}} | {semaine du JJ/MM} | {la mise en production attend la recette} |

# Hypothèses

Le chiffrage repose sur les hypothèses ci-dessous. Une réponse différente peut faire évoluer le périmètre ; nous la chiffrerons avant de démarrer.

| Question | Hypothèse retenue | Impact si différent |
|---|---|---|
| {Combien d'entités ?} | {une seule} | {+0,25 à 0,5 j par entité} |
| {Faut-il reprendre l'historique ?} | {non} | {voir Options} |

# Options

| Option | Contenu | Jours |
|---|---|---|
| {Reprise de l'historique} | {…} | {…} |

# Hors périmètre

- {…}

# Délai indicatif

Environ {n} semaines ouvrées, recette comprise, à compter de la réception des éléments marqués « Bloquant ».

---

## Exemple rempli (court)

> Connecteur Outil X → Pennylane pour Société Exemple. Chiffrage en jours de travail de notre équipe. Version du 26/10/2026.

| Lot | Résultat pour Société Exemple | Jours |
|---|---|---|
| **Lot 1 — Factures Outil X → Pennylane** | Chaque facture émise dans Outil X arrive dans Pennylane, avec son PDF, sans saisie | **3,5 à 4,5** |

**Total : 3,5 à 4,5 jours.**

**Pourquoi une fourchette** : nous n'avons pas encore d'accès de test à Outil X. **Borne basse** : les réponses sont conformes à la documentation. **Borne haute** : écarts sur les vraies factures. **Engagement** : chiffrage resserré dans les 2 jours ouvrés qui suivent la réception des accès.

| Étape | Jours |
|---|---|
| 1.1 Mise en place et connexion sécurisée | 0,5 |
| 1.2 Lecture et création des factures | 1,5 à 2 |
| 1.3 Écran de suivi | 0,5 |
| 1.4 Recette, démonstration et mise en production | 1 à 1,5 |
| **Total lot 1** | **3,5 à 4,5** |

**1.2 Lecture et création des factures (1,5 à 2 j)** · **Enjeu** : une facture oubliée ou créée deux fois fausse la comptabilité.

| Sous-partie | Ce qui est livré | Ce que ça apporte | Jours |
|---|---|---|---|
| Lecture des factures | Récupération des nouvelles factures et de leur PDF | **Tests** : rejoués sur de vraies factures anonymisées | 0,5 à 0,75 |
| Création dans Pennylane | Facture et avoirs créés sur le bon client et le bon compte | **Recette** : contrôlé avec votre comptable | 0,75 à 1 |
| Reprise sur erreur | Une facture en échec est signalée et relancée, jamais dupliquée | **Reprise sur erreur** | 0,25 |

| Ce qu'il nous faut | Pour quelle étape | Date souhaitée | Si c'est en retard |
|---|---|---|---|
| Accès de test à Outil X et à Pennylane | 1.2 | 03/11 | **Bloquant** : chaque semaine de retard décale d'autant la livraison |
| Validation du plan de comptes produits | 1.2 | 07/11 | La création reste en fourchette haute |
| Deux demi-journées de recette | 1.4 | semaine du 17/11 | La mise en production attend la recette |

**Hypothèses** : une seule entité ; pas de reprise de l'historique ; TVA au taux normal uniquement (sinon +0,25 à 0,5 j).

**Délai indicatif** : environ 3 semaines ouvrées à compter de la réception des accès.
