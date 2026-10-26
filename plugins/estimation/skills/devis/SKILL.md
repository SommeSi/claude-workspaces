---
name: devis
description: Chiffrer une feature, un connecteur ou une correction pour SommeSi et rédiger le devis client dans Notion, en « dev IA » (attention humaine, temps Claude, délai) calé sur l'historique réel des livraisons. À utiliser pour « fais un devis », « chiffre ce connecteur », « combien de jours », « combien ça coûte », « estime cette carte », « recale le chiffrage ».
---

# Devis SommeSi : estimer en dev IA

Chez SommeSi, le code est écrit avec Claude. Un « jour de dev » ne mesure plus rien : Arthur MCP était estimé à 2,75 j, et le code a pris environ 2 h. On estime donc **trois choses séparées**, jamais additionnées entre elles :

| Mesure | Ce que c'est | Ce qui la fait varier |
|---|---|---|
| **Attention humaine** | Le temps d'une personne de l'équipe : piloter Claude, relire, tester, échanger avec le client | Nombre de décisions, de recettes, d'allers-retours |
| **Temps Claude** | Claude qui code et teste | La taille du travail ; rarement le problème |
| **Délai** | Du démarrage à la mise en production | Les points d'arrêt : accès API, clés, sandbox, réponses du client, relecture |

Le délai explose presque toujours à cause des **points d'arrêt** et de la **découverte d'une API externe**, presque jamais à cause du code.

## Étape 1 : comprendre la demande

Si la demande ne le dit pas déjà, poser ces questions **en une seule fois**, avec des mots simples. « Je ne sais pas » est une réponse acceptée.

1. Quel outil externe faut-il connecter ? Sa documentation API est-elle publique ? A-t-on déjà un accès de test (sandbox, clés) ?
2. Qui valide côté client, et à quelle vitesse répond-il d'habitude ?
3. Combien d'entités (sociétés avec leur propre comptabilité) et quels volumes (factures par mois, etc.) ?
4. Faut-il de nouveaux écrans, ou réutilise-t-on l'existant ?
5. Faut-il reprendre de l'historique (données passées) ?

Chaque « je ne sais pas » devient une **hypothèse écrite** dans le devis et élargit la fourchette.

## Étape 2 : comparer à ce qui a déjà été livré

- Lire la base Notion **« Historique des livraisons »** (https://app.notion.com/p/284daf55c3e64a7bba160c8b47de8aff) avec le connecteur Notion. Prendre les 2 ou 3 livraisons les plus proches (même type, mêmes briques). Leur réel (attention, temps Claude, délai) sert d'ancre. Leur écart entre estimé et réel montre dans quel sens on se trompe d'habitude.
- Lire `references/catalogue.md` : les briques déjà chiffrées sur du réel.
- Si rien de proche n'existe, le dire clairement : la fourchette sera plus large.

## Étape 3 : chiffrer brique par brique

Pour chaque lot, à partir du catalogue et des ancres :

- **Attention humaine** : une fourchette en heures (bas – haut).
- **Temps Claude** : en heures.
- **Points d'arrêt** : qui doit fournir quoi (accès, décision, recette), avec l'attente habituelle.
- **Découverte API** : faible, moyenne ou forte. Forte = documentation incomplète, pas de sandbox ou API jamais utilisée chez nous ; on multiplie alors le haut de fourchette par 1,5, sur l'attention comme sur le délai.

Additionner les bas et les hauts séparément. Le **délai** = l'attente des points d'arrêt sur le chemin critique + les jours de travail. **Vérifier les sommes** : sous-parties = lot, lots = total, en-tête = total.

## Étape 4 : les deux livrables

1. **Le devis client**, une page Notion au format `references/devis-template.md` :
   - en langage clair, par sous-partie, en disant ce que chaque partie apporte (sécurité, tests, reprise sur erreur, recette) ;
   - avec la fourchette, les hypothèses, et ce qu'on attend du client (ses points d'arrêt) ;
   - sans nom interne : ni autres clients, ni noms de code, ni outils internes.
2. **La fiche interne**, dans la réponse et pas dans le devis : un tableau *lot | attention | temps Claude | points d'arrêt | découverte API*, plus les livraisons de l'historique utilisées comme ancres, avec leur écart.

## Étape 5 : après la livraison

Côté devs, `/workspace:finish` ajoute automatiquement la ligne réelle dans l'Historique. Si le travail a été livré autrement, créer la ligne à la main : c'est ce qui rend les devis suivants justes.

## Règles

- Ne jamais modifier l'estimation d'une carte Notion sans demande explicite.
- Ne jamais présenter un chiffre comme certain quand une hypothèse est ouverte : donner une fourchette.
- Pour re-chiffrer un travail en cours, partir du réel déjà mesuré, pas de zéro.
