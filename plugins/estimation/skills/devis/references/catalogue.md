# Catalogue des briques

Un devis s'assemble avec ces briques. Pour chacune : ce qu'elle couvre, l'attention humaine, le temps Claude, les points d'arrêt et ce qui la fait exploser. Les trois mesures ne s'additionnent jamais entre elles.

**D'où viennent les chiffres (état au 26/10/2026)**
- **mesuré** : heures relevées dans les sessions Claude par `ws-actuals.py`, sur les livraisons de la base « Historique des livraisons ». Seules 11 livraisons de septembre et octobre 2026 ont des heures : les sessions plus anciennes sont effacées au bout d'environ 30 jours.
- **à confirmer** : jugement tiré des devis passés et des cartes, pas d'une mesure. À remplacer dès que 2 ou 3 livraisons mesurées utilisent la brique.
- L'attention mesurée ne compte que le temps passé dans Claude. Les réunions, les appels, les tests dans le navigateur et la relecture sur GitHub n'y sont pas : c'est un minimum.
- Conversion pour le devis client : 1 jour = 7 h de temps humain (convention à confirmer).

## Repères transverses (mesurés)

- **Temps Claude ≈ 0,5 à 2 fois l'attention.** Le rapport monte quand Claude code seul une feature neuve (rubriques partielles du DA : 1,9). Il baisse quand il faut vérifier des données avec le client (reprise des tiers Polo : 0,5).
- **L'attention s'étale dans le calendrier.** 8 à 19 h d'attention ont pris 10 à 15 jours calendaires, à cause du travail en parallèle et de l'attente de recette.
- **Sur une feature, la recette et les échanges dominent.** Pour les rubriques partielles du DA : 6,8 h sur 8,3 d'attention. Le cadrage et le code ont pris environ 1 h.
- **Ce qui ne s'est pas effondré : les données et l'après-MEP.** La reprise des tiers et la mise en production Polo ont demandé 60 h d'attention, deux fois le temps Claude.

## Les briques

### Cadrage
Comprendre la demande, lire l'existant, écrire la spécification et le plan de tests, poser les questions au client, chiffrer.
- **Attention** : 0,5 à 2 h si le domaine est connu (mesuré : cadrage NumIA 1,1 h, rubriques DA 0,3 h, MCP Arthur 0,6 h). 5 à 9 h pour un concept nouveau sans spécification (mesuré : cerveau Arthur 9,1 h sur deux jours). Les réunions s'ajoutent, non mesurées.
- **Claude** : 0,5 à 1,5 h (mesuré). Jusqu'à 11 h pour un concept nouveau (mesuré : cerveau Arthur).
- **Points d'arrêt** : disponibilité du client pour répondre, accès à la documentation, fichiers d'exemple.
- **Explose quand** les prises de besoin s'enchaînent (Polo Offshore : 1,5 à 2 j de prise de besoin, 10 décisions ouvertes en juin) ou quand il manque un fichier d'exemple (import crew change : 2,5 h à cartographier sans le fichier qui avait planté).

### Auth API
Obtenir et brancher les accès à l'outil externe : clés, connexion OAuth, stockage chiffré, test de connexion, un accès par entité si besoin.
- **Attention** : 0,5 à 2 h. **Claude** : 0,5 à 1,5 h. Les deux à confirmer : aucune mesure isolée. Les devis passés comptaient 0,5 à 1 j.
- **Points d'arrêt** : réception des clés et d'un environnement de test (sandbox). C'est souvent le premier blocage du délai (le devis Filiz prévoit +2 j si les clés manquent au jour 5 ; ABC Car a eu une carte « connecter les bonnes sandbox »).
- **Explose quand** il n'y a pas de sandbox, qu'il faut une clé par entité, ou que l'accès est lié à une personne.

### Lecture source
Récupérer les données de l'outil source : appels API, notifications reçues (webhooks), boîte mail, dépôt ou import de fichiers.
- **Attention** : 1 à 3 h, **Claude** : 2 à 4 h pour une API documentée (à confirmer). Pour des fichiers fournis par le client (CSV, PDF) : 5,9 h d'attention et 6,7 h de Claude mesurées sur l'import crew change, qui n'est toujours pas en production.
- **Points d'arrêt** : fichiers d'exemple, vraies réponses de l'API.
- **Explose quand** les vraies réponses diffèrent de la documentation (c'est la borne haute du devis Filiz), quand le format n'est pas documenté, ou quand l'échantillon manque.

### Mapping
Faire correspondre les deux outils : clients et fournisseurs (tiers), comptes comptables (706/708, 411/401), TVA, analytique, entités.
- **Attention** : 1 à 3 h, **Claude** : 1 à 3 h quand les règles sont connues (à confirmer). Quand l'identité des tiers est à refaire : environ 15 h d'attention en trois jours (mesuré : Polo, du 22 au 28/09).
- **Points d'arrêt** : validation des correspondances par le comptable du client (règle 706/708 inconnue chez NumIA : +0,5 j).
- **Explose quand** l'identité repose sur des libellés (environ 15 bugs Polo), qu'il y a plusieurs entités (21 bugs Polo où l'entité était oubliée), ou que l'analytique change de règle (libellés analytiques Polo repris environ 8 fois).

### Écriture cible
Créer ou mettre à jour dans l'outil cible : factures, avoirs, PDF, lettrage et délettrage, achats, écritures.
- **Attention** : 1 à 4 h, **Claude** : 2 à 6 h (à confirmer : la brique est incluse dans les rubriques DA, sans mesure séparée).
- **Points d'arrêt** : environnement de test de la cible, validation comptable.
- **Explose quand** la cible se comporte autrement que prévu (18 bugs Polo venus d'une hypothèse fausse sur l'API Pennylane ; incident de génération de PDF côté Pennylane en octobre 2026), quand il faut mettre à jour ou supprimer sans doublon (1 j de recherche pour Pigment), ou quand il faut lettrer et délettrer.

### Écran
Écrans dans l'application : liste de suivi, détail, configuration, import.
- **Attention** : 1 à 2 h par écran, **Claude** : 1 à 3 h (à confirmer). Mesuré : passage aux nouvelles couleurs de l'app 1,7 h d'attention et 1,3 h de Claude, dont 1,1 h pour refaire le thème sombre.
- **Points d'arrêt** : validation du rendu (couleurs : 8 jours de délai pour moins de 2 h d'attention).
- **Explose quand** le rendu fait des allers-retours ou que l'écran n'est pas spécifié (le correctif d'import crew change est devenu une page d'import complète).

### Jobs / sync
Tâches qui tournent seules : synchronisations planifiées, relances automatiques, traitement des notifications, reprise après échec.
- **Attention** : 0,5 à 2 h, **Claude** : 1 à 3 h (à confirmer).
- **Points d'arrêt** : rarement.
- **Explose quand** l'API limite le débit sans prévenir (cas Furious), quand le volume monte (workers à court de mémoire en production) ou quand deux traitements se marchent dessus.

### Codes erreur
Rendre visibles les échecs : message clair dans l'écran de suivi, alerte, erreur critique quand un cas « impossible » arrive, journaux sans données personnelles.
- **Attention** : 0,5 à 1,5 h, **Claude** : 1 à 2 h (à confirmer).
- **Points d'arrêt** : liste des cas d'erreur à valider avec le client.
- **Explose quand** on a laissé des échecs silencieux : les bugs vivent alors des jours avant d'être vus (constat récurrent dans l'historique Polo).

### Reprise historique
Importer les données passées dans le nouveau flux : factures des mois précédents, analytique historique.
- **Attention** : 4 à 20 h, **Claude** : 2 à 10 h (à confirmer). Les devis passés la chiffraient 1,25 à 2 j.
- **Points d'arrêt** : exports fournis par le client, vérification par son comptable.
- **Explose quand** les données sources sont sales (doublons, codes tronqués), quand les périodes se recouvrent, ou quand une période est déjà clôturée.

### Recette
Tests des cas limites et de bout en bout, essais du client sur l'environnement de test, démonstration, mise en production, suivi des premiers jours.
- **Attention** : 60 à 80 % de l'attention d'une feature (mesuré : rubriques DA 6,8 h sur 8,3, dont 5,3 h de tests de cas limites et 1,5 h d'échanges client). Après une grosse mise en production : 3 à 5 h par jour actif pendant environ 2 semaines (mesuré : Polo 28,6 h en 8 jours actifs).
- **Claude** : environ 60 % du temps Claude d'une feature (mesuré : rubriques DA 9,8 h sur 15,6).
- **Points d'arrêt** : essais du client sur l'environnement de test (2 à 7 jours, à confirmer), relecture et fusion par un second développeur.
- **Explose quand** il n'y a pas de données de test réalistes, quand le client est peu disponible, ou quand les vraies données révèlent des cas imprévus.

### Migration données
Transformer des données déjà en place, chez nous ou dans la comptabilité du client, quand une règle change : ré-identifier les tiers, ré-imputer des écritures, corriger en production. Inclut les montées de version techniques.
- **Attention** : mesuré 60,3 h, avec 29,9 h de Claude sur 32 jours, pour la mise en production Polo, l'identité des tiers et la ré-imputation d'écritures. Une montée de version technique bien couverte par les tests : 1,5 h d'attention et 1,4 h de Claude (Rails 8.1).
- **Points d'arrêt** : fichiers de correspondance produits par le client (plusieurs versions), décisions, mise à jour chez un éditeur tiers.
- **Explose quand** il y a plusieurs entités, des doublons, ou des écritures comptables impossibles à annuler simplement.

## Ancres réelles

« Attention en jours » = attention mesurée ÷ 7 h. Délai = jours calendaires mesurés, du premier au dernier jour d'activité.

| Livraison | Estimé | Attention | Claude | Délai | Écart | Leçon |
|---|---|---|---|---|---|---|
| Rubriques partielles du DA (Polo) | devis 4 j, carte 2 j | 8,3 h | 15,6 h | 15 j | ≈ 1,2 j d'attention | 2/3 de l'attention en tests de cas limites, puis recette client |
| Cerveau en régions (Arthur) | 4 j | 18,8 h | 23,5 h | 10 j | ≈ 2,7 j | concept neuf : la moitié de l'attention en cadrage et plan de tests |
| MEP Polo Consignation + identité des tiers | ≈ 10 j (7 cartes) | 60,3 h (min.) | 29,9 h | 32 j | ≈ 8,6 j | la migration de données ne s'effondre pas : attention = 2 × Claude |
| Retours client après MEP (Polo) | 3 j | 28,6 h | 16,4 h | 12 j, en cours | ≈ 4,1 j | 3 à 5 h par jour pendant 2 semaines ; absent de tous les devis |
| Import crew change (Polo Offshore) | 1 j | 5,9 h | 6,7 h | 26 j, pas en prod | ≈ 0,8 j | correctif devenu une page ; pas de fichier d'exemple |
| Rails 8.0 → 8.1 | 1,25 j | 1,5 h | 1,4 h | 2 j | ≈ 0,2 j | estimation à l'échelle jour-humain |
| Nouvelles couleurs de l'app | 0,25 j | 1,7 h | 1,3 h | 8 j | juste | le délai vient de l'aller-retour sur le rendu |
| Analytique du flux 3 | 0,25 j | 0,4 h | 1,0 h | 2 j | ≈ 0,1 j | petit correctif |
| Cadrage et devis NumIA (Filiz) | 0,75 j | 1,1 h | 0,4 h | — | ≈ 0,2 j | cadrage + devis ≈ 1 h dans Claude, réunions en plus |
| Corrections de prod Ornikar (Pigment) | — | 2,6 h | 1,2 h | 22 j | — | 3 semaines d'attente du retour client |
| MCP Arthur (en cours) | 2 j | 0,6 h | 1,7 h | en cours | — | la recette donnera le vrai chiffre |
| ABC Car → Pennylane | vendu 5 j, spec 13,5 j | non mesuré | non mesuré | échéance du 1/09 dépassée | « 7 jours actifs » cités | périmètre revu, sandbox, validation comptable |
| Pennylane → Pigment (Ornikar) | vendu 5 j | non mesuré | non mesuré | mi-juillet → septembre | 7,25 j de cartes (+45 %) | API jamais utilisée : 4 j de besoins et de recherche |
| Besoins client, lignes et suivi (Offshore) | 5 j | non mesuré | non mesuré | 2 j jusqu'au code testé en local | — | le code va vite ; la suite jusqu'à la prod n'est pas tracée |
| Polo Offshore (projet) | 35 j | non mesuré | non mesuré | en recette depuis juin | « 57 j réels » mi-juillet, 78,4 j de cartes | le périmètre grossit à chaque prise de besoin |
| Polo Consignation (projet) | 67,5 j, 39 j calendaires prévus | non mesuré | non mesuré | 220 j | 56,8 j de cartes | délai × 5,6 alors que les cartes restent sous le volume prévu |

## Comment on se trompe

1. **On chiffre en jours-humains.** Rails 8.1 : 1,25 j estimé, 1,5 h d'attention. Rubriques DA : 4 j vendus, 8,3 h d'attention. Besoins client Offshore : 5 j estimés, code fait en 2 jours calendaires. Pour le code seul, l'ancienne échelle surestime de 3 à 6 fois.
2. **Deux échelles pour la même chose.** Le devis client vaut environ le double de la carte : 4 j contre 2 pour les rubriques DA, 10 j contre 3,5 pour le flux d'achat ATS. L'écart, c'est la recette et les échanges, jamais écrits sur la carte. Il faut les chiffrer en lignes à part.
3. **On oublie la recette, les échanges et l'après-MEP.** C'est là que va l'attention : 2/3 pour les rubriques DA, 28,6 h de retours client après la mise en production Polo, alors qu'aucun devis ne prévoyait de ligne de stabilisation.
4. **On ignore les points d'arrêt.** Polo Consignation : 39 jours calendaires prévus, mise en production 220 jours après le démarrage, alors que les cartes cumulées restent sous le volume prévu. ABC Car a dépassé son échéance, et les corrections Ornikar ont attendu 3 semaines un retour du client. Le délai se chiffre à partir des attentes, pas à partir du code.
5. **Le périmètre grossit après la signature.** Polo Offshore : 35 j au départ, 61,5 j dans le devis signé (45 j facturés), 66 à 92 j ré-estimés fin juin, 57 j « réels » mi-juillet, 78,4 j de cartes fin octobre. Chaque prise de besoin ajoute des fonctions. La ligne ABC Car est passée de 5 à 13,5 j avant le développement, et un correctif d'import est devenu une page entière.
6. **On sous-estime les données.** Reprise et migration ne profitent presque pas de Claude : il faut vérifier ligne à ligne avec le comptable du client (60 h d'attention pour les tiers Polo).
7. **On mélange estimation et ajustement commercial.** Marges de 15 à 30 %, remises et prix plancher (19 j estimés, 15 j vendus) se fondent dans les lignes : l'écart entre estimé et réel devient illisible. Garder l'estimation brute dans la fiche interne et écrire la marge à part.
8. **On découvre l'API en route.** Pigment (API jamais utilisée) a demandé 4 j de besoins et de recherche, et Filiz reste en fourchette tant que les accès de test manquent. Découverte forte : haut de fourchette × 1,5, comme le prévoit le skill.

Après chaque livraison, `/workspace:finish` ajoute une ligne à l'Historique. Recalculer les fourchettes ci-dessus quand une brique a 2 ou 3 mesures, et retirer alors la mention « à confirmer ».
