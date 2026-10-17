# Spécification — Synchronisation complète entre postes (lots F4 à F7)

**Produit :** TATACORA — Gîte Chez Noël, Natitingou (Bénin)
**Demande du Product Owner :** 17/10/2026 — « on doit avoir aussi les ventes, dépenses, caisses, commandes et réceptions, les activités et réservations liées au tourisme, les deux modules POS vente et POS hébergés des autres postes, et en synchronisation. NE PLUS LIMITER. » « Deux PC était une illustration : on peut aller à 3, 4, 5 postes. »
**Branche :** `claude/quirky-johnson-2pbs4t` — PR vers `main` à ouvrir une fois les lots de cette spécification livrés et corrigés.
**Prérequis côté PO :** déploiement du serveur sur `logirestock.digitonpro.com` + `php artisan migrate` (le PO s'en charge).

---

## 1. Problème

Aujourd'hui (fin du lot F3), un poste Windows **envoie** au serveur ses ventes, dépenses, caisses, commandes, réceptions, clients et réservations, mais n'en **reçoit** que le catalogue, les clients et les réservations. Sur un Gîte qui tourne à 3, 4 ou 5 postes (réception, bar, restaurant, économat, direction), chaque poste ne voit donc que **sa** part de l'activité : le bar ne voit pas les ventes du restaurant, le stock d'un poste ignore les réceptions faites sur un autre, la direction ne peut pas lire la journée consolidée sur son poste, et le tourisme et les ventes sur note de chambre ne se synchronisent pas du tout.

Le coût : des chiffres faux affichés de bonne foi (stock, caisse, tableau de bord), des décisions prises sur une vue partielle, et l'obligation de passer par la PWA du serveur pour tout ce qui est consolidé.

## 2. Objectifs

1. **Convergence :** tout document saisi sur n'importe quel poste est présent sur **tous** les autres postes **≤ 10 minutes** après que les deux postes ont été en ligne en même temps (cible : 1 passage automatique de 5 min + marge).
2. **Aucune limite au nombre de postes :** le même mécanisme fonctionne à 2, 5 ou 10 postes, sans configuration par poste au-delà de l'appairage.
3. **Aucune perte et aucun doublon :** zéro opération perdue, zéro document en double après n'importe quelle combinaison de coupures (mesuré par le contrôle de cohérence, §6).
4. **Chiffres identiques partout :** pour une journée close, le total des ventes, dépenses et espèces par point de vente est **le même** sur chaque poste et sur le serveur.
5. **Les règles d'exclusivité tiennent à N postes :** une chambre, une caisse ouverte par point de vente et une table de restaurant ne sont jamais attribuées deux fois, même hors ligne. Un conflit est refusé par le serveur et signalé dans « À traiter », jamais absorbé en silence.

## 3. Hors périmètre (cette version)

| Hors périmètre | Raison |
|---|---|
| Synchronisation **temps réel** (push, websocket) | Le réseau du Gîte coupe. Le modèle « file + curseur toutes les 5 min + bouton » est déjà en place et robuste ; le temps réel ne change pas la convergence quand un poste est hors ligne. |
| Échange **direct entre postes** (sans serveur) | Le serveur reste l'arbitre unique (RG-01, caisses, numérotation). Un réseau pair à pair dédoublerait cet arbitrage. |
| **Multi-établissement** | Un seul Gîte. Le modèle de données n'a pas d'établissement. |
| **Fusion automatique** de deux saisies d'argent contradictoires | Une vente ou une caisse en conflit va dans « À traiter » pour un humain. Aucun montant n'est recalculé ou fusionné par la machine. |
| Paramètres, comptes utilisateurs, mots de passe | Les comptes restent locaux (PA-103) ; les paramètres ont leur propre circuit. À rouvrir à part. |

RH / paie, véhicules (M8) et notifications ne sont pas cités par le PO. Ils figurent en **question ouverte Q5** plutôt qu'en hors périmètre, puisque la consigne est « ne plus limiter ».

## 4. Récits utilisateurs

**Caissier du bar (poste 2)**
- En tant que caissier du bar, je veux voir le stock calculé avec les réceptions saisies à l'économat (poste 4), pour ne pas annoncer une boisson en rupture alors qu'elle vient d'arriver.
- En tant que caissier du bar, je veux que l'ouverture de caisse me soit refusée si la caisse du bar est déjà ouverte sur un autre poste, pour qu'il n'y ait jamais deux tiroirs « bar » ouverts en même temps.

**Réceptionniste (poste 1)**
- En tant que réceptionniste, je veux voir les consommations portées sur la note de chambre au restaurant (poste 3), pour présenter au client une facture complète au départ.
- En tant que réceptionniste, je veux voir les arrivées, départs et annulations faits sur les autres postes, pour connaître l'état réel des chambres.
- En tant que réceptionniste, je veux voir les réservations de circuits et d'activités touristiques prises ailleurs, pour ne pas sur-réserver un guide ou un véhicule.

**Gérant / direction (poste 5)**
- En tant que gérant, je veux lire sur mon poste les ventes, dépenses et caisses de **tous** les postes, avec le poste d'origine de chaque document, pour piloter la journée sans ouvrir la PWA.
- En tant que gérant, je veux un contrôle de cohérence qui me dise si mon poste a bien tout reçu, pour faire confiance aux chiffres affichés.

**Administrateur**
- En tant qu'administrateur, je veux appairer un 6ᵉ poste neuf et qu'il reçoive tout l'historique sans intervention, pour ajouter un poste en quelques minutes.
- En tant qu'administrateur, je veux voir dans « À traiter » chaque conflit entre postes (chambre, caisse, table, numéro) avec ses deux saisies, pour trancher.

**Cas limites**
- Un poste reste hors ligne 3 jours puis revient : il envoie sa file, reçoit tout ce qu'il a manqué, et rien n'est en double.
- Deux postes vendent hors ligne sur la même session de caisse : les deux ventes arrivent, elles sont rattachées à la même session.
- Un document est annulé sur un poste pendant qu'un autre le modifie : la dernière saisie gagne si les deux sont permises ; sinon le second geste est refusé et signalé.

## 5. Exigences

### P0 — indispensables

**P0-1. Descente de tous les documents, de tous les postes.**
Le flux de descente (aujourd'hui `GET /referentiels`, catalogue + clients + réservations) porte aussi, dans l'ordre des clés étrangères :

| Domaine | Tables |
|---|---|
| Caisse | `sessions_caisse` |
| POS vente (comptant) | `ventes` + `lignes_vente`, ventes du bar (`ventes_bar` + lignes) |
| Restaurant | `commandes_restaurant` + lignes, occupation des `tables_salle` |
| POS hébergés (note de chambre) | `sejours`, ventes `sur_sejour`, `factures` + `lignes_facture`, `paiements` de facture, avoirs |
| Dépenses | `depenses` + `lignes_depense` |
| Achats | `commandes_achat` + lignes, `bons_reception` + lignes, `reglements_fournisseur` |
| Stock | `mouvements_stock` (tous postes) — le stock local est **recalculé** à partir des mouvements, jamais descendu comme valeur |
| Tourisme | `circuits`, `guides`, `reservations_tour` |

Critères d'acceptation :
- [ ] Étant donné 5 postes appairés, quand le poste A enregistre une vente, une dépense, une réception et une réservation de circuit, alors après un passage de synchronisation de A puis de chacun des autres, les 4 autres postes les affichent avec le **poste d'origine**.
- [ ] Un document descendu n'est **jamais renvoyé** au serveur (aucune opération enfilée par la descente).
- [ ] Le stock d'un article sur chaque poste est identique au stock calculé par le serveur après la descente.
- [ ] Le curseur ne perd ni ne double aucun document, y compris quand plusieurs documents partagent la même seconde (même garantie que le catalogue).
- [ ] Un document descendu est en **lecture seule** sur les postes qui ne l'ont pas saisi, sauf les gestes listés en P0-3.

**P0-2. Montée de tout ce qui manque.**
Le serveur accepte, depuis un poste, en plus de l'existant :
- le **tourisme** (circuits, réservations de circuit) ;
- la **note de chambre** : vente `sur_sejour`, séjour (arrivée / départ), facture et son paiement — c'est la « phase 2 » levée par cette demande ;
- les **règlements fournisseur** et les **paiements de facture**.

Chaque type passe par son **service de domaine** au serveur (comme aujourd'hui pour les ventes et les réservations), jamais par une écriture brute.

- [ ] Une vente sur note de chambre saisie hors ligne au restaurant arrive au serveur, est rattachée au bon séjour, et apparaît sur la facture du client sur **tous** les postes.
- [ ] Une réservation de circuit qui chevauche celle d'un autre poste (même guide ou même véhicule) est refusée par le serveur et apparaît dans « À traiter ».

**P0-3. Le cycle de vie des documents part aussi (plus seulement la création).**
Aujourd'hui le poste n'envoie que la **création** d'une réservation ; une annulation, un déplacement, une arrivée ou un départ faits sur le poste restent locaux. Cette version envoie chaque geste par son propre service :
- réservation : déplacement (repasse RG-01), annulation avec conditions, arrivée, départ ;
- vente : annulation ;
- commande d'achat : envoi, clôture ;
- caisse : clôture (déjà en place).

À la descente, l'état du serveur **remplace** l'état local pour tout document qui n'a plus rien en attente. La règle de F3 « le statut ne recule jamais » devient inutile une fois que chaque geste local part au serveur.

- [ ] Une réservation déplacée sur le poste A apparaît déplacée sur les postes B à E ; si les nouvelles dates sont prises, le déplacement est refusé et signalé, et la réservation garde ses anciennes dates partout.

**P0-4. Comptabilité : jamais doublée.**
Le serveur reste le seul comptable (D246) : un poste n'envoie jamais d'écriture. Sur le poste, **un document descendu ne passe aucune pièce locale.** Ce qui figure dans la comptabilité locale est tranché par la question **Q1** (bloquante).

- [ ] Après la descente d'une vente du poste A sur le poste B, le nombre de pièces comptables de B est inchangé (option A de Q1) ou augmenté exactement des pièces du serveur pour cette vente (option B), jamais des deux.

**P0-5. Exclusivités arbitrées par le serveur, à N postes.**
- Chambre (RG-01), caisse ouverte par point de vente, table de restaurant occupée, guide ou véhicule d'un circuit : le poste contrôle **localement** sur tout ce qu'il a reçu, et le serveur tranche en dernier ressort.
- Un refus du serveur est consigné dans « À traiter » avec les deux saisies en conflit.

**P0-6. Numérotation des documents à N postes hors ligne.**
Un numéro de facture continu (« F-2026-00042 ») ne peut pas être alloué par deux postes hors ligne sans collision. La règle est tranchée par la question **Q2** (bloquante) avant le lot de la note de chambre.

**P0-7. Un poste neuf reçoit tout l'historique.**
Un poste appairé pour la première fois télécharge l'historique complet, page par page. Cela doit pouvoir s'interrompre et reprendre sans tout recommencer : le curseur est posé à chaque page, comme aujourd'hui.

- [ ] Un poste neuf, sur une base d'un an d'exploitation, est complet après une reprise sur coupure, sans doublon.

### P1 — fortement souhaitées

- **P1-1. Contrôle de cohérence :** dans la modale de synchronisation, « Ce poste a tout reçu jusqu'au … ». Le serveur rend, par table et par jour, un nombre de documents et un total. Le poste compare avec ses propres chiffres et affiche les écarts.
- **P1-2. Poste d'origine visible :** une colonne ou pastille « Poste » sur les listes (ventes, dépenses, caisses, réservations), et un filtre « Ce poste / Tous les postes ».
- **P1-3. Liste des postes connus :** l'écran de synchronisation liste les postes appairés au serveur et la date de leur dernier passage, pour repérer un poste qui ne synchronise plus.
- **P1-4. Accélération du premier téléchargement :** un instantané compressé pour un poste neuf, si la mesure du P0-7 dépasse la cible (voir §6).

### P2 — à préparer, pas à construire maintenant

- **P2-1.** Temps réel (le serveur signale aux postes en ligne qu'il y a du nouveau) : le curseur actuel le permet sans changer le format.
- **P2-2.** Archivage des documents de plus de N ans sur les postes, pour limiter la taille de la base locale. Le format du flux doit permettre de ne descendre qu'à partir d'une date.
- **P2-3.** RH / paie, véhicules, notifications, selon la réponse à Q5.

## 6. Mesures de réussite

| Indicateur | Cible | Comment on le mesure |
|---|---|---|
| Délai de convergence (deux postes en ligne) | ≤ 10 min, cible 5 min | horodatage de saisie sur A → présence sur B (journal de synchronisation) |
| Opérations perdues ou en double | 0 | contrôle de cohérence P1-1, chaque soir, sur chaque poste |
| Écart des totaux journaliers entre postes et serveur | 0 FCFA | contrôle de cohérence, par point de vente |
| Conflits non signalés | 0 | essai à 5 postes avec coupures (§8) |
| Premier téléchargement d'un poste neuf, 1 an d'historique | ≤ 15 min sur la liaison du Gîte | essai chronométré avant mise en service |
| Opérations « À traiter » non résolues depuis plus de 48 h | 0 en régime établi | écran de synchronisation |

Évaluation : à la mise en service, puis à 1 semaine et à 1 mois d'exploitation à plusieurs postes.

## 7. Questions ouvertes

| # | Question | Qui | Bloquante ? |
|---|---|---|---|
| **Q1** | **Comptabilité sur le poste.** (A) Le journal local ne contient que les pièces passées **par ce poste** ; la comptabilité consolidée se lit sur le serveur. (B) Le serveur fait aussi descendre **ses** pièces pour les documents des autres postes (lecture seule) : la balance du poste devient complète, mais il faut marquer l'origine de chaque pièce au serveur. **Recommandation : A pour F4, B en lot à part (F7).** | PO + comptable | Oui, pour F4 |
| **Q2** | **Numéros de facture hors ligne à N postes.** (A) Le poste émet une facture **provisoire**, le serveur attribue le numéro continu à l'arrivée (seul cas sans trou ni collision). (B) Une série par poste (« F-P3-2026-00012 »), à valider fiscalement (MECeF). **Recommandation : A.** | PO + comptable | Oui, pour F5 |
| Q3 | Un document descendu d'un autre poste peut-il être **annulé** ici (vente, dépense) ? Proposition : oui pour un administrateur ou un gérant, le geste part au serveur comme tout geste local. | PO | Non |
| Q4 | Les ventes du bar (`ventes_bar`) et celles du comptant (`ventes`) restent-elles deux circuits distincts, ou convergent-elles ? Elles coexistent aujourd'hui au serveur. | Ingénierie + PO | Non |
| Q5 | « Ne plus limiter » couvre-t-il aussi la **paie / RH**, les **véhicules** (M8) et les **notifications** ? | PO | Non |
| Q6 | Un poste peut-il **effacer** sa base et redescendre tout l'historique (réinstallation) sans perdre sa file non envoyée ? Proposition : refus tant que la file n'est pas vide, avec un message clair. | PO | Non |

## 8. Phasage proposé

Chaque lot est livré sur la branche avec ses tests (suite complète verte, mutation sur chaque garde neuve, essai contre le vrai serveur). La PR vers `main` s'ouvre après F6, ou plus tôt si le PO le demande.

| Lot | Contenu | Dépend de |
|---|---|---|
| **F4** | Descente des documents en lecture : caisses, ventes (comptant, bar), commandes restaurant, dépenses, commandes d'achat, réceptions, règlements, **mouvements de stock** ; tourisme **montée et descente** ; poste d'origine sur chaque document. | Q1 |
| **F5** | POS hébergés : séjours, vente sur note de chambre, factures, paiements de facture, montée et descente. | Q2 |
| **F6** | Cycle de vie : déplacement, annulation, arrivée et départ des réservations, annulation de vente, statuts des commandes, envoyés au serveur par leurs services. Arbitrage des tables de restaurant et des guides. | F4, F5 |
| **F7** | (si Q1 = B) Pièces du serveur descendues en lecture seule ; contrôle de cohérence complet (P1-1). | F4–F6 |

**Essai de réception à la fin de F6 (avant la PR) :** 5 postes simulés contre le vrai serveur sur `tatacora_test`. Une journée complète : réservations, arrivées, ventes comptant et sur note, dépenses, réceptions, circuits, coupures aléatoires d'un ou plusieurs postes. Puis contrôle de cohérence : mêmes documents, mêmes totaux, mêmes stocks partout, et chaque conflit présent dans « À traiter ».

## 9. Ce qui ne change pas

- La file d'envoi, l'idempotence par `uuid_operation`, les replis 30 s → 1 h, la bissection sur 422, le bail entre processus.
- Les déclencheurs : démarrage, toutes les 5 minutes, après une clôture de caisse, le bouton de la barre supérieure.
- Aucune synchronisation en démonstration ; rien ne part sans appairage par un administrateur.
- Aucun geste ne dépend du réseau : on vend, on encaisse et on clôture une caisse hors ligne, toujours.
