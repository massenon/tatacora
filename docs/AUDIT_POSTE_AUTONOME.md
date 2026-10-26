# Audit du poste autonome — « le poste est plus privilégié »

Décision du Product Owner (26/10/2026) : **tous les modules doivent être
opérationnels sur le poste, que la synchronisation soit active ou non.
Désactivée, le poste fonctionne sans le serveur.**

Ce document mesure, module par module (M1 à M14, puis les écrans transverses),
ce qui fonctionne sans serveur, ce qui ne fonctionnait pas, ce qui a été
corrigé, et ce qui reste impossible hors ligne avec sa raison.

## 1. L'interrupteur « Synchronisation activée »

- **Où** : Paramètres du poste, onglet « Synchronisation » (Administrateurs
  seulement). Le voyant de la barre supérieure le dit : « Synchronisation
  désactivée » (gris, avec le nombre d'opérations en attente).
- **Stockage : `poste.json`** (clé `synchronisation_activee`, absente = activée),
  et non `etat_synchronisation_local`, pour quatre raisons : le choix est PAR
  POSTE comme l'appairage (il ne doit pas voyager par la synchronisation :
  qu'un autre poste éteigne celui-ci n'aurait aucun sens) ; il survit à la
  réinitialisation de la base (`etat_synchronisation_local` est vidé) ; il se
  lit sans ouvrir la base ; aucun changement de schéma n'est nécessaire.
  L'appairage est conservé : réactiver ne demande aucun nouvel appairage.
- **Désactivée, aucune requête réseau** — gardée à CHAQUE point d'entrée, relue
  du fichier avant chaque passage :
  `SyncManager.synchroniserMaintenant` (envoi et descente du catalogue),
  `SyncManager.suivreDemandeDuServeur`, `ControleCoherence.controler`,
  `ServiceAppairage` (appairer, tester la connexion, dissocier sans `POST
  /logout`), `ServiceSuiviPostes` (lire, demander, révoquer).
- **L'écran `/synchronisation`** dit « Synchronisation désactivée » en tête de
  son état et grise « Synchroniser maintenant ».
- **La file continue de se remplir** (les écrivains enfilent comme avant) ; les
  opérations restent `en_attente` et partent, dans l'ordre d'enfilement, à la
  réactivation, qui lance aussitôt un passage (envoi puis descente).
- **Preuve** : `test/features/synchronisation/synchronisation_desactivee_test.dart`
  joue la journée complète du scénario (vente, dépense, réservation, stock,
  paie, factures, règlement…) avec un transport qui LÈVE au moindre appel :
  aucun appel, la file pleine et intacte ; réactivée, tout part dans l'ordre et
  la descente a lieu. Mutation éprouvée (retirer la garde du moteur fait
  rougir). `onglet_synchronisation_test.dart` prouve la bascule par l'écran.
- **Ce que l'interrupteur ne coupe pas** : l'envoi SMTP (Contact éditeur, e-mail
  de test). Ce n'est pas la synchronisation ; le message est écrit d'abord, son
  envoi échoue gracieusement (il reste en file avec sa raison) sans bloquer.

## 2. La source des états comptables

Avant : le compte de résultat et le bilan du poste ne lisaient que les
écritures REÇUES du serveur — vides hors ligne. Désormais
(`sourceEtatsFinanciersProvider`) :

| Situation | Source |
|---|---|
| synchronisation active ET écritures reçues du serveur | miroir du serveur (tous les postes) |
| synchronisation désactivée, ou rien reçu | écritures validées passées PAR CE POSTE |

Les deux sources ne sont jamais mêlées (le serveur passe sa propre pièce pour
chaque document reçu : les additionner compterait chaque vente deux fois). La
ligne « Chiffres calculés sur les écritures validées passées par ce poste »
le dit à l'écran. Le Journal, la Balance, le Grand livre et l'Analytique du hub
se lisent toujours sur les pièces du poste.

## 3. Tableau d'audit

Légende : **O** fonctionne sans serveur ; **N→O** ne fonctionnait pas, corrigé ;
**N** ne fonctionne pas hors ligne (voir §4) ; **P** partiel.

| Module | Écran | Fonction | Sans serveur | Correction faite |
|---|---|---|---|---|
| M1 Hébergement | Plan, Réservations, Disponibilités, Services | création, déplacement, annulation avec conditions, acompte et sa pièce | O | — |
| M1 | Import (plan) | refusé par la vue elle-même | sans objet | — |
| M2 Facturation | Registre, émission, avoir (total, partiel), encaissement | tout | O | — |
| M2 | Numéro officiel `F-` et certification MECeF | attribués par le serveur | **N** | le poste émet `PROV-…` imprimé « FACTURE PROVISOIRE » ; le numéro du serveur est posé à l'accusé (§4) |
| M3 CRM | Clients, créances, relances, archivage | tout | O | — |
| M4 Restaurant | Carte du jour, Couverture, Plats/fiches/menus, lien au stock | tout | O | — |
| M4 | **Ventes du Restaurant** (onglet) + son export | lignes de vente | N→O | calculées sur les paniers du poste (`lignes_vente_du_rayon.dart`, réplique de `LignesVenteDuRayonService`), filtres, pagination, total des validées, export PDF/tableur du jeu filtré |
| M4 | « Prix », « Historique des prix » | changement rapide de prix et sa trace | **N** | reste (§4) |
| M5 Bar | Carte, Catalogue des boissons, lien au stock, retraits | tout | O | — |
| M5 | **Ventes du Bar** (onglet) + export | lignes de vente | N→O | même calcul local (`BoissonsApi.ventes` branché sur les paniers) |
| M5 | « Historique des prix » | trace des changements | **N** | reste (§4) |
| M6 Stocks | Articles, mouvements, inventaire, archivage | tout | O | — |
| M7 Achats | Commandes, réception, règlements, fournisseurs | tout | O | — |
| M8 Véhicules | Parc, contrats, planning, immobilisations | tout | O | — |
| M8 | Annulation d'un contrat de location | la PWA l'offre | **N** | reste (§4) |
| M9 Tourisme | Circuits, départs, réservations | tout | O | — |
| M10 Comptabilité | Passer écriture, Journal (et son export), Balance, Plan (création de compte), Ouvrir un exercice, Immobilisations | tout | O | **création de compte : une seule règle, 2 à 4 chiffres** (mission A) |
| M10 | **Compte de résultat, Bilan** | états financiers | N→O (vides hors ligne) | calculés sur les pièces du poste quand la synchronisation est désactivée (§2) |
| M10 | **Grand livre** | un compte à la fois, solde progressif, ouverture/clôture, à-nouveaux provisoires | N→O | `grand_livre_analytique.dart`, confronté au vrai `GrandLivreService` (filtres de statut, ouverture provisoire, ouverture inconnue) |
| M10 | **Analytique** | marge par centre | N→O | `analytiqueDe`, confronté au vrai `AnalytiqueService` |
| M10 | **Six indicateurs du bandeau** + alerte « Comptabilité déséquilibrée » | CA, VA, EBE, résultat net, trésorerie, total bilan | N→O | `indicateursDe` (assembleur du compte de résultat, du bilan, de la balance) |
| M10 | **Tuiles Flux de trésorerie (TAFIRE), Notes annexes, États financiers** | trois pages séparées de la vue | N→O | fenêtres calculées sur le poste (`tafire_notes.dart`), confrontées au vrai `TafireService` et `NotesAnnexesService` sur quatre exercices |
| M10 | Clôtures | **clôture annuelle** (pièces CL et AN, réouverture) | **N** | reste (§4) |
| M11 Tableau de bord | Bande d'indicateurs | 7 sur 8 | O | — |
| M11 | **Dépenses cumulées** | écritures de classe 6 | N→O (« — ») | calculées (`depensesCumuleesCentimes`), confrontées au vrai `TableauDeBordService`, bornes du serveur comprises |
| M11 | **Série mensuelle** (graphique) | CA encaissé et dépenses sur N mois | N→O (« non disponible ») | `serieMensuelleLocale`, confrontée à `serieMensuelle` |
| M11 | **Pilotage consolidé** : Résultat net, alertes comptables | M10 | N→O (« Non consulté ») | alimentés par les mêmes états que le hub |
| M12 Notifications | Modèles, déclencheurs, journal | tout | O | — |
| M12 | Envoi réel d'un e-mail de notification | transport SMTP | **N** | aucun envoi n'est tenté ni bloquant (§4) |
| M13 RH | Employés, paie, congés et plannings | tout | O | — |
| M14 États | 11 états sur 12 | aperçus | O | — |
| M14 | **Balance générale** | aperçu | N→O (« listée, refusée ») | `apercuBalance` (écritures validées, à-nouveaux provisoires compris) |
| M14 | Exports PDF/archive des états | la vue n'en offre pas (décision PO) | sans objet | — |
| Transverse | Import & Export : importer (CSV), sauvegarde de la base (« Enregistrer sous »), exporter une table, réinitialiser | tout | O | — |
| Transverse | Import & Export : « Restaurer » (registre des éléments archivés), purge | registre transverse | **N** | reste (§4) |
| Transverse | Journal d'audit | lecture de la file d'envoi | P | colonnes « Utilisateur » et « Poste » : « — » (la file ne les conserve pas) |
| Transverse | Mon profil, Rôles et permissions, Comptes utilisateurs, Aide, Paramètres | tout (mot de passe SMTP dans `poste.json`) | O | — |
| Transverse | Contact éditeur, e-mail de test | SMTP | **N** (réseau) | message écrit d'abord, envoi qui échoue gracieusement, relance |
| Transverse | Synchronisation, Postes & Appairage, contrôle de cohérence | exigent le serveur | **N** par nature | désactivée : les écrans le DISENT, aucune requête |

## 4. Ce qui reste impossible hors ligne, et pourquoi

1. **Certification MECeF et numéro officiel des factures** — un service fiscal
   externe et la séquence continue du serveur. Hors ligne le poste émet une
   facture provisoire, que le serveur régularise à la synchronisation.
2. **Envoi réel d'e-mails** (notifications, contact éditeur) — un relais SMTP
   exige un réseau. Le message est écrit, la raison est dite, il part à la
   relance ; rien ne bloque.
3. **Clôture annuelle SYSCOHADA** (pièces de clôture et d'à-nouveaux, archive
   DGI, réouverture) — c'est un acte du comptable sur le registre UNIQUE : le
   serveur ne reçoit aucune écriture du poste (il passe sa propre pièce pour
   chaque document reçu). Une clôture locale diverge de celle du serveur dès la
   réactivation. Elle demande une décision du Product Owner (qui clôture quand
   le poste est seul ?) et un contrat de synchronisation d'exercice ; elle n'a
   pas été portée.
4. **Historique des prix** (bar et restaurant) et **« Prix »** du restaurant —
   le serveur trace les changements (observateurs) ; le poste n'a aucune table
   de trace. Demande un schéma (table additive) et un lecteur ; non fait pour ne
   pas entrer en collision avec la version 37 prise par l'agent des écrans de
   synchronisation. Le prix en cours reste modifiable depuis « Modifier » du
   plat ou de la boisson.
5. **Annulation d'un contrat de location** — la PWA porte une colonne `statut`
   que le poste n'a pas (PA-50) ; elle demande une colonne (schéma), une
   opération de modification côté serveur et sa descente.
6. **Restaurer / purge** de l'onglet Import & Export — registre transverse des
   éléments archivés de tous les modules ; chaque module restaure déjà ses
   propres éléments depuis son écran.
7. **Journal d'audit : utilisateur et poste** — la file d'envoi ne les conserve
   pas.
8. **Numéros de vente `V-`, auteur de la vente** — absents du panier du poste
   (« — » dans les ventes du bar et du restaurant).
9. **Particularités de calcul** : les états comptables du poste ne portent que
   les écritures VALIDÉES (le filtre de statut du hub ne s'y applique pas) ; la
   balance de M14 ne compte pas les brouillons ; la note annexe n° 7 (événements
   postérieurs) est « non saisie » : son texte libre vit au serveur.

## 5. Schéma

Non modifié par cette mission : la version courante est 37 (prise par l'agent
des écrans de synchronisation) et aucune correction ci-dessus n'a exigé de
colonne ni de table. Les points 4, 5 et 7 en demanderaient une (version 38).
