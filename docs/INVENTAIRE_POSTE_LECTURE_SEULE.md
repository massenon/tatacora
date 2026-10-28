# Inventaire du poste : écrans en lecture seule ou partiels, par rapport au web

Date : 27/10/2026. Branche `claude/quirky-johnson-2pbs4t`. L'inventaire a été mesuré
sans modification de code, à la **v40, 76 tables**. **Mise à jour du lot L3-S + L3
(27/10/2026, décisions D1 et D2 du PO) : A6, A7, A8 et A10 sont LIVRÉS**, schéma
**v41** (dix colonnes nullables, toujours 76 tables) ; voir la section 8. Les lignes
concernées portent la mention « FAIT (L3) » ; le reste de l'inventaire est inchangé.

Sources lues : `tatacora-flutter/CLAUDE.md`, `docs/AUDIT_POSTE_AUTONOME.md`, tous les
composants `tatacora-api/app/Pwa/Livewire/**` (58 fichiers), les vues Blade
correspondantes, `PwaActionsReluesTest.php`, `PwaEcritureAutoriseeTest.php`, les
gestionnaires de synchronisation `app/Shared/Sync/Gestionnaires/*`, les DAO et écrans de
`tatacora-flutter/lib`, les jetons `blade-refuse:` / `libelles-du-serveur:` et
`tool/conformite_blade/dette-blade-flutter.json`. Chaque ligne cite le fichier ou la
méthode qui l'établit ; ce qui n'a pas pu être prouvé est marqué « à confirmer ».

## 0. Résumé chiffré

Unité de compte : une **action web d'écriture** = un geste métier qui persiste, exporte ou
imprime (« ouvrir / fermer la modale » et les états de formulaire sont rattachés à leur
geste d'enregistrement et ne comptent pas). Les composants en lecture pure (États M14,
Journal d'audit, Recherche globale, Aide) n'ont aucune action et ne sont pas comptés.

| Indicateur | Nombre |
|---|---|
| Actions web d'écriture inventoriées | **150** |
| Couvertes (OUI complet) | **146** (135 à la mesure, +4 par le lot L3, +5 par les lots L1-L2 : A11, A1, A3, A2, A4, +1 par le lot L5-A12 : A12, +1 par le lot L5-A5 : A5) |
| Partielles | **1** (7 à la mesure, −4 par le lot L3, −1 par A11, −1 par L5-A12 : A9 reste) |
| Lecture seule | **0** |
| Absentes | **3** (8 à la mesure, −4 par L1-L2, −1 par L5-A5 : les journaux hors périmètre restent) |

Parmi les absentes et partielles, certaines sont des écarts voulus (section 3) : 
**9 lignes relèvent des vrais manques (section 2 ; 13 à la mesure, 4 livrés par le lot L3)** et **2 sont des écarts voulus ou impossibles hors ligne (section 3)**. 
Les lignes OUI portant une référence B sont des gestes complets dont une conséquence serveur est voulue (MECeF, stock, pièces manuelles).

| Module | Actions | OUI | PARTIEL | ABSENT |
|---|---|---|---|---|
| M1 Hébergement | 14 | 14 | 0 | 0 |
| M2 Facturation | 3 | 3 | 0 | 0 |
| M3 CRM / Clients | 7 | 7 | 0 | 0 |
| M4 Restaurant | 10 | 10 | 0 | 0 |
| M5 Bar | 6 | 6 | 0 | 0 |
| M6 Stocks | 10 | 10 | 0 | 0 |
| M7 Achats | 8 | 8 | 0 | 0 |
| M8 Véhicules / Locations | 7 | 7 | 0 | 0 |
| M9 Tourisme | 7 | 7 | 0 | 0 |
| M10 Comptabilité | 9 | 8 | 1 | 0 |
| M11 Tableau de bord | 7 | 7 | 0 | 0 |
| M12 Notifications | 7 | 7 | 0 | 0 |
| M13 RH / Paie / Congés | 11 | 9 | 1 | 1 |
| Dépenses | 3 | 2 | 1 | 0 |
| POS comptant, POS hébergés, Historique des ventes, Caisse | 14 | 14 | 0 | 0 |
| Transverse : Paramètres, Rôles, Profil, Contact, Import/Export, Alertes, Session, Synchronisation | 27 | 20 | 0 | 7 |

**Lecture clé : le poste n'est presque plus en « lecture seule ».** Aucune action web n'est
restée purement lisible sur le poste ; les écarts réels sont (a) huit lignes absentes (six gestes à construire, deux journaux du
serveur hors périmètre), (b) une fiche dont un champ n'a pas de transport (A9, le reçu de
dépense ; les quatre autres fiches sont livrées par le lot L3), (c) deux écarts de droit ou de
synchronisation (A11, A12). Plusieurs en-têtes de code Dart qui parlent encore de « lecture seule »
ou de « non porté » sont **périmés** (section 6) : ils ne doivent pas servir de source.

## 1. Légende

- **OUI** : le poste a l'équivalent complet (DAO écrivain + écran + bouton).
- **PARTIEL** : le geste existe mais des champs, une règle, un droit ou la synchronisation manquent (préciser).
- **LECTURE SEULE** : le poste affiche mais n'écrit pas (aucun cas relevé au niveau d'une action).
- **ABSENT** : ni DAO, ni écran, ni bouton.
- Effort : S (moins d'une journée), M (1 à 3 jours), L (plus de trois jours ou dépend du serveur).
- Schéma ? : « non » ou « v41 » (colonne/table à ajouter, migration additive conditionnelle).
- Dans les tableaux, la colonne Réf. renvoie aux sections 2 (A, vrais manques) et 3 (B, écarts voulus).

## 2. (A) Vrais manques CRUD du poste, à convertir

| Réf. | Manque | Statut | Cause | Effort | Schéma ? |
|---|---|---|---|---|---|
| A1 | **FAIT (L1, 27/10/2026)** Verrou de session (`VerrouSession::deverrouiller`) | OUI | voile + minuteur d'inactivité, limiteur d'essais du serveur (`tool/session/rejouer_verrou.php`) | - | non |
| A2 | **FAIT (L1, 27/10/2026)** Modales d'ouverture de session : check-out inline, relance inline (`AlertesOuvertureModales`) | OUI | `HoteModalesOuverture` : stock critique puis départs/créances, droits M1/M3 relus, 3 collecteurs et mots comparés au serveur (`tool/alertes/rejouer_modales_ouverture.php`) ; l'aide du paramètre est désormais vraie | - | non |
| A3 | **FAIT (L1, 27/10/2026)** Bulletin de paie sur papier A4 : « Imprimer » et « PDF » (`Paie::exporterPdf`) | OUI | `rh/impression/bulletin_paie_a4.dart` (gabarit commun `entete_a4.dart`, `texteTicket`), actions injectables ; classé document REMIS (sans visas), comme le gabarit serveur | - | non |
| A4 | **FAIT (L2, 27/10/2026)** Archives : « Restaurer » un élément (`ImportExport::restaurerArchive`) | OUI | registre DÉRIVÉ des unités et véhicules `hors_service` (`registre_archives.dart`, `archives_poste.dart`), « archivé le/par » lu de la file d'envoi, aucune table ; preuve contre le serveur `tool/transverse/rejouer_archives.php`. Écarts : archives d'un autre poste absentes, « — » sans opération locale | - | non |
| A5 | **FAIT (L5-A5, 28/10/2026, schéma v43)** Archives : « Purger » définitivement (`purgerArchive`) | OUI | corbeille de chaque ligne (super_admin seul), confirmation forte de la vue, verrous des services de parc rejoués aux phrases du serveur (`ParcDao.purger`, `VehiculeDao.purger`) ; opération `suppression` du protocole (registre fermé : unités d'hébergement et véhicules), rejouée par le serveur (`GestionnaireUnitesHebergement/Vehicules::supprimer` -> `purger`) ; la suppression redescend (`suppressions_synchronisation`) et se rejoue chez les autres postes SEULEMENT si aucune saisie locale n'y est rattachée. Preuves : `tool/transverse/rejouer_purge.php`, `PurgeSynchronisationTest`, `archives_purger_test`, `purge_descente_test`, `migration_v43_suppression_operations_test` | - | v43 (CHECK de la file) |
| A6 | Véhicule : Places, Année, Transmission (`Locations::enregistrerVehicule`) | **FAIT (L3, 27/10/2026)** | `vehicules_local.annee/capacite/transmission` (v41), `VehiculeDao.enregistrerVehicule` (bornes et phrases du serveur), `GestionnaireVehicules::modifier` les accepte, descente (`COLONNES` portait déjà les trois) | - | v41 |
| A7 | Contrat : N° `LOC-`, Remise, Acompte, Reste dû (`Locations::enregistrerContrat`) | **FAIT (L3, 27/10/2026)** | `contrats_location_local.numero/remise/acompte/montant` (v41) : montant net FIGÉ à la signature (plus de recalcul au tarif courant), reste dû = montant − acompte, N° du serveur posé à l'accusé ; `GestionnaireContratsLocation` accepte remise et acompte (phrases `lte` de la vue) ; anciens contrats : colonnes nulles, « — » | - | v41 |
| A8 | Plat : champ « Catégorie » (dix valeurs, `Restauration::enregistrerPlat`) | **FAIT (L3, 27/10/2026)** | `plats_local.categorie` (v41), modale, colonne et filtre du catalogue, import M4 ; `GestionnairePlats` accepte `categorie` en synchronisation (registre fermé de la vue ; `CHAMPS_REFUSES` de l'API inchangé) ; `COLONNES` descend `plats.categorie`. Écart assumé : la CARTE du restaurant classe encore par type de menu | - | v41 |
| A9 | **LIVRÉ le 27/10/2026 (lot L4, v42)** — Dépense : reçu / justificatif image (`Depenses::enregistrerDepense`, `photoRecu`) | OUI | aucune colonne ni sélecteur (`ecran_depenses.dart:90`) ; la synchronisation est du JSON, aucun transport de fichier ; la pastille « sans reçu » est vraie pour toutes les lignes | L | v41 (chemin du reçu) + serveur |
| A10 | Guide : Certification et Tarif/jour (`Departs::enregistrerGuide`) | **FAIT (L3, 27/10/2026)** | `guides_local.certification/tarif_jour` (v41) rangés par `TourismeDao.enregistrerGuide` (ils partaient déjà au serveur) et redescendus | - | v41 |
| A11 | **FAIT (L1, 27/10/2026)** Archivage des employés : règle « administrateur / super_admin OU bascule » (`Paie::archiverEmployes`) | OUI | `core/rbac/regle_archivage.dart` (D272) relue à chaque geste | - | non |
| A12 | Création d'un compte du plan comptable (`Hub::enregistrerCompte`) | PARTIEL | écrit sur le poste seulement : aucune table au registre de synchronisation (`ecran_comptabilite.dart:69`) ; un compte web n'arrive pas au poste, et inversement | L | non (serveur : gestionnaire + descente) |

Notes sur A4 : la restauration passée (« déjà restaurées ») se lit au web du journal d'audit ;
sur le poste, la file d'envoi (`operations_sync_local.auteur_login`, v38) porte déjà l'auteur
et l'instant, donc aucun schéma n'est nécessaire.

## 3. (B) Écarts voulus ou impossibles hors ligne, à ne PAS convertir

| Réf. | Écart | Décision ou raison citée |
|---|---|---|
| B1 | Numéro officiel `F-` et certification MECeF | `AUDIT_POSTE_AUTONOME.md` §4.1 : service fiscal externe + séquence du serveur ; le poste émet `PROV-…` |
| B2 | E-mail réel : seul le canal e-mail part ; WhatsApp, Android, SMS « à transmettre à la main » | `AUDIT` §4.2 (décision PO 26/10/2026 limitée à l'e-mail), aucun contrat de transport |
| B3 | Sorties de stock d'une vente (RG-05) : le poste ne les écrit pas, il ESTIME « −X en attente d'envoi » | D240 + `CLAUDE.md` « Stock estimé hors ligne » : le serveur sort le stock à la réception, un mouvement local serait compté deux fois |
| B4 | ~~Pièces comptables saisies à la main restent sur le poste~~ **LEVÉ le 28/10/2026** : D246 rouvert par décision du PO, la pièce SOURCE de la saisie part (`pieces_saisie`), le serveur la rejoue et passe la sienne (section 10) | D246 rouvert par décision du PO du 28/10/2026 |
| B5 | « Ouvrir un exercice » local non poussé ; le serveur ouvre le sien | D210 « écart assumé » ; l'exercice descend avec son statut (`TableDescendue.exercicesComptables`) |
| B6 | Clôture annuelle : pas de relevés bancaires, PDF d'archive au gabarit commun, archives hors sauvegarde, résultat sur les seules pièces du poste | `AUDIT` §4.3, `CLAUDE.md` v40 « Écarts nommés » |
| B7 | Onglets « Réception » et « Envoi » de Postes & Appairage (corriger, relancer, ignorer une opération reçue ; redescente) | données du SERVEUR (`journal_reception_synchronisation`, `journal_envoi_synchronisation`) ; le poste a sa propre file (« À traiter », Renvoyer/Débloquer) ; exige le serveur par nature (`AUDIT` §3, dernière ligne) |
| B8 | Tableur = CSV, pas de .xlsx | décision PO 14/10/2026 (`modale_export.dart`, `TextesExport.noteCsv`) |
| B9 | Journal d'audit : n'affiche que les écritures de CE poste ; « Poste » = nom de machine, pas IP | `AUDIT` §4 point 7 ; lecture seule aussi au web |
| B10 | Annulation d'un règlement fournisseur ou d'un paiement de facture : DAO présent, aucun écran | aucun appelant au web (D257) |
| B11 | « Délier » une boisson du stock | la vue du bar ne la rend jamais (`$page['delier']=false`) ; `cartes_boisson.article_id` NOT NULL (jeton `blade-refuse:bar/carte#modale:modal-delier`) |
| B12 | « Nouvelle / Modifier la boisson » dans la carte du restaurant | la vue ne la rend pas côté restaurant (jetons `blade-refuse:restaurant/carte#modale:commun.modale_*`) |
| B13 | Tourisme : pas de « Supprimer », tout s'annule ; colonnes N°, Véhicule, Acompte, Indicatif € sans source | RG-02/RG-15 ; ces colonnes n'existent pas non plus au schéma serveur (jeton `blade-refuse:tourisme/departs#modale:modale-archivage` = vocabulaire, le geste équivalent existe : annuler) |
| B14 | Immobilisation d'un véhicule : pas de date de fin (« Au ») | aucune colonne de fin au schéma serveur non plus |
| B15 | Comptes utilisateurs (créer, désactiver, réinitialiser le mot de passe) | écran propre au poste, **le web n'a aucun écran de gestion des comptes** (`comptes_utilisateurs.dart`) : rien à convertir côté poste |
| B16 | Restaurer une sauvegarde de base | hors périmètre PO (`sauvegarde_locale.dart:17`) ; le web n'a que générer, télécharger, retirer |
| B17 | Rythme automatique des sauvegardes « — » | une application de bureau n'est pas allumée à 02h00 |

## 4. Tableaux par module (toutes les actions web d'écriture)

### M1 Hébergement (`Hebergement\Hebergement`, `Hebergement\Reservations`)

| Action web | Poste | Preuve / cause | Effort | Schéma ? | Réf. |
|---|---|---|---|---|---|
| `Hebergement::effectuerCheckIn` | **OUI** | `SejourDao.checkin`, `vue_plan_hebergement.dart:810` | - | non |  |
| `Hebergement::effectuerCheckOut` | **OUI** | `SejourDao.checkout`, `vue_plan_hebergement.dart:842` | - | non |  |
| `Hebergement::marquerNettoye` | **OUI** | `ParcDao.marquerNettoyee`, `vue_plan_hebergement.dart:780` | - | non |  |
| `Hebergement::ouvrirReservationRapide` / `enregistrerReservationRapide` | **OUI** | `modale_reservation_rapide.dart` (`CreerReservation`) | - | non |  |
| `Hebergement::enregistrerUnite` (créer / modifier, nouvelle catégorie) | **OUI** | `modale_unite.dart:386-408` : `ParcDao.creerCategorie/creerUnite/modifierUnite` | - | non |  |
| `Hebergement::confirmerArchivageUnite` / `archiverUnite` | **OUI** | `ParcDao.archiver`, `modale_archivage_unite.dart:240`, bascule `suppressionActive` (`vue_plan_hebergement.dart:696`) | - | non |  |
| `Hebergement::restaurerUnite` | **OUI** | `ParcDao.restaurer`, `vue_plan_hebergement.dart:709` | - | non |  |
| `Hebergement::genererExport` | **OUI** | `exporterParcProvider` / `exporterParcPdfProvider` | - | non |  |
| `Reservations::enregistrerReservation` (créer ; services et lignes de la fiche) | **OUI** | `fiche_reservation.dart`, `CreerReservation` | - | non |  |
| `Reservations::enregistrerReservation` (modifier) | **OUI** | `ModifierReservation`, `fiche_reservation.dart:936` | - | non |  |
| `Reservations::confirmerAnnulation` / `annulerReservation` | **OUI** | `ReservationDao.annulerAvecConditions` (v19), `modale_annulation_reservation.dart` | - | non |  |
| `Reservations::enregistrerClient` | **OUI** | `dialogue_nouveau_client.dart`, `ClientDao.creer` | - | non |  |
| `Reservations::imprimerConfirmation` | **OUI** | `impression/confirmation_reservation.dart` | - | non |  |
| `Reservations::genererExport` | **OUI** | `panneau_historique.dart:500` | - | non |  |

### M2 Facturation (`Facturation\Facturation`)

| Action web | Poste | Preuve / cause | Effort | Schéma ? | Réf. |
|---|---|---|---|---|---|
| `Facturation::enregistrerAvoir` | **OUI** | `FactureDao.annuler` / `emettreAvoirPartiel` ; numéro `PROV-` hors ligne (B1) | - | non | B1 |
| `Facturation::imprimerFacture` | **OUI** | `impression/facture_a4.dart` (imprimé « FACTURE PROVISOIRE » tant que non régularisée) | - | non | B1 |
| `Facturation::genererExport` | **OUI** | `ecran_facturation.dart:396` | - | non |  |

### M3 CRM / Clients (`Crm\ClientsCreances`)

| Action web | Poste | Preuve / cause | Effort | Schéma ? | Réf. |
|---|---|---|---|---|---|
| `enregistrerClient` | **OUI** | `ClientDao.creer` (le web ne modifie pas un client) | - | non |  |
| `enregistrerRecouvrement` | **OUI** | `PaiementsFactureDao.recouvrer` | - | non |  |
| `enregistrerRelance` | **OUI** | `RelancesClientsDao.enregistrer` | - | non |  |
| `confirmerArchivageClient` / `archiverClients` | **OUI** | `archivage_clients.dart`, règle `regle_archivage.dart` | - | non |  |
| `restaurerClient` | **OUI** | `providers_crm.dart:336` | - | non |  |
| `imprimerReleveClient` | **OUI** | `impression/releve_client.dart` | - | non |  |
| `genererExport` | **OUI** | `barre_exports_clients.dart:61` | - | non |  |

### M4 Restaurant (`Restaurant\Restauration`, `Restaurant\CarteRestaurant`, trait `EcranDeCarte`)

| Action web | Poste | Preuve / cause | Effort | Schéma ? | Réf. |
|---|---|---|---|---|---|
| `Restauration::enregistrerPlat` (créer / modifier) | **OUI** | `RestaurantDao.enregistrerPlat` ; catégorie (dix valeurs) portée depuis la v41 (A8, FAIT L3) | - | v41 | A8 |
| `Restauration::enregistrerMenu` (créer / modifier) | **OUI** | `RestaurantDao.enregistrerMenu` | - | non |  |
| `Restauration::enregistrerRecette`, `ajouterIngredient`, `retirerIngredient` | **OUI** | `RestaurantDao.enregistrerRecette` | - | non |  |
| `Restauration::confirmerRetraitDuPlat` | **OUI** | `ecran_restauration.dart:1381`, `RetraitsPlats.retirer` | - | non |  |
| `CarteRestaurant::enregistrerLienAuStock` | **OUI** | `RestaurantDao.lierAuStock` | - | non |  |
| `CarteRestaurant::confirmerRetraitDuLien` | **OUI** | `RestaurantDao.delierDuStock` | - | non |  |
| `enregistrerRetraitDeLaCarte` / `remettreALaCarte` | **OUI** | `IndisponibilitesCarteDao.retirer/remettre` | - | non |  |
| `enregistrerModificationPrix` | **OUI** | `RestaurantDao.modifierPrix` + historique v38 | - | non |  |
| `genererExport` (carte) et onglet Ventes | **OUI** | `ecran_carte_restaurant.dart:520`, `vue_ventes_restaurant.dart:579` | - | non |  |
| `imprimerFichePrix` | **OUI** | `ecran_carte_restaurant.dart:533` | - | non |  |

### M5 Bar (`Bar\CarteBar`, trait `EcranDeCarte`)

| Action web | Poste | Preuve / cause | Effort | Schéma ? | Réf. |
|---|---|---|---|---|---|
| `CarteBar::enregistrerCreationBoisson` | **OUI** | `CatalogueDao.enregistrerBoisson` via `modale_boisson.dart` | - | non |  |
| `CarteBar::enregistrerModificationBoisson` | **OUI** | idem | - | non |  |
| `enregistrerLienAuStock` | **OUI** | `modale_lien_stock.dart` | - | non |  |
| `enregistrerRetraitDeLaCarte` / `remettreALaCarte` | **OUI** | `IndisponibilitesCarteDao` | - | non |  |
| `enregistrerModificationPrix` | **OUI** | `CatalogueDao.enregistrerBoisson` + historique v38 | - | non |  |
| `genererExport`, `imprimerFichePrix`, onglet Ventes | **OUI** | `barre_exports_carte.dart:55`, `vue_ventes_bar.dart:156` | - | non |  |

### M6 Stocks (`Stocks\Stocks`, `Stocks\Inventaires`)

| Action web | Poste | Preuve / cause | Effort | Schéma ? | Réf. |
|---|---|---|---|---|---|
| `Stocks::enregistrerArticle` (créer / modifier, entrée depuis la fiche) | **OUI** | `StocksDao.creerArticle/modifierArticle`, `modale_article.dart` | - | non |  |
| `Stocks::enregistrerMouvement` | **OUI** | `StocksDao.ajouterMouvement` | - | non |  |
| `Stocks::forcerMouvement` | **OUI** | `modale_mouvement.dart:206` (rupture forcée tracée) | - | non |  |
| `Stocks::lancerImport` (+ `telechargerModeleCsv`) | **OUI** | `importeurs_locaux.dart` (M6) | - | non |  |
| `Stocks::genererExport` | **OUI** | `ecran_stocks.dart:340` | - | non |  |
| `confirmerArchivageArticle` / `archiverArticles` | **OUI** | `StocksDao.archiverArticle/archiverLot`, règle `regle_archivage.dart` | - | non |  |
| `restaurerArticle` | **OUI** | `StocksDao.restaurerArticle` | - | non |  |
| `Inventaires::enregistrerComptage` | **OUI** | `StocksDao.figerComptage` | - | non |  |
| `Inventaires::cloturer` | **OUI** | `StocksDao.cloturerInventaire` | - | non |  |
| `Inventaires::genererExport` | **OUI** | `ecran_inventaires.dart:1624` | - | non |  |

### M7 Achats (`Achats\Achats`, `Achats\Approvisionnement`)

| Action web | Poste | Preuve / cause | Effort | Schéma ? | Réf. |
|---|---|---|---|---|---|
| `Achats::enregistrerFournisseur` (créer / modifier) | **OUI** | `AchatsDao.creerFournisseur/modifierFournisseur` | - | non |  |
| `confirmerArchivageFournisseur` / `archiverFournisseurs` | **OUI** | `AchatsDao.archiverFournisseur/archiverLot`, règle D272 | - | non |  |
| `Achats::restaurerFournisseur` | **OUI** | `AchatsDao.restaurerFournisseur` | - | non |  |
| `Achats::genererExport` | **OUI** | `barre_outils_achats.dart:146` | - | non |  |
| `Approvisionnement::enregistrerCommande` | **OUI** | `AchatsDao.creerCommande` | - | non |  |
| `Approvisionnement::enregistrerReception` | **OUI** | `AchatsDao.enregistrerReception` (sans valorisation, D265) | - | non |  |
| `Approvisionnement::enregistrerReglement` | **OUI** | `ReglementsFournisseurDao.regler` | - | non |  |
| `Approvisionnement::genererExport` | **OUI** | `vue_commandes_achats.dart` | - | non |  |

### M8 Véhicules / Locations (`Vehicules\Locations`)

| Action web | Poste | Preuve / cause | Effort | Schéma ? | Réf. |
|---|---|---|---|---|---|
| `enregistrerVehicule` (créer / modifier) | **OUI** | `VehiculeDao.enregistrerVehicule` ; Places, Année, Transmission portées depuis la v41 (A6, FAIT L3) | - | v41 | A6 |
| `remettreEnService` | **OUI** | `vue_parc.dart:399` (`changerStatut`) | - | non |  |
| `enregistrerContrat` | **OUI** | `VehiculeDao.creerContrat` (RG-08/RG-09 tenues) ; N°, Remise, Acompte, Reste dû portés et montant FIGÉ depuis la v41 (A7, FAIT L3) | - | v41 | A7 |
| `enregistrerImmobilisation` (entretien) | **OUI** | `VehiculeDao.enregistrerEntretien` (v32) ; pas de date de fin non plus au serveur | - | non | B14 |
| `confirmerArchivage` / `executerSuppression` (véhicule) | **OUI** | `VehiculeDao.archiverVehicule`, `vue_parc.dart:446` | - | non |  |
| `confirmerArchivage` / `executerSuppression` (contrat = annuler) | **OUI** | `VehiculeDao.annulerContrat` (v38), `vue_contrats.dart:418` | - | non |  |
| `genererExport` | **OUI** | `barre_filtres_vehicules.dart:169` | - | non |  |

### M9 Tourisme (`Tourisme\Departs`)

| Action web | Poste | Preuve / cause | Effort | Schéma ? | Réf. |
|---|---|---|---|---|---|
| `enregistrerReservation` | **OUI** | `TourismeDao.reserver` (RG-13 sur ce poste) | - | non |  |
| `enregistrerGuide` | **OUI** | `TourismeDao.enregistrerGuide` ; certification et tarif/jour rangés depuis la v41 (A10, FAIT L3) | - | v41 | A10 |
| `enregistrerReaffectationGuide` | **OUI** | `TourismeDao.reaffecterGuide` | - | non |  |
| `enregistrerPrestation` (créer / modifier) | **OUI** | `TourismeDao.enregistrerCircuit` | - | non |  |
| `executerSuppression` (réservation = annuler) | **OUI** | `TourismeDao.annulerReservation` | - | non | B13 |
| `executerSuppression` (départ = annuler) | **OUI** | `TourismeDao.annulerDepart` | - | non | B13 |
| `genererExport` | **OUI** | `barre_filtres_tourisme.dart:171` | - | non |  |

### M10 Comptabilité (`Comptabilite\Hub`, `Comptabilite\CorrespondanceComptes`)

| Action web | Poste | Preuve / cause | Effort | Schéma ? | Réf. |
|---|---|---|---|---|---|
| `Hub::enregistrerPieceBrouillon` | **OUI** | `MoteurComptable.saisirPiece(valider: false)` (v44), synchronisée (`pieces_saisie`) | - | non | B4 |
| `Hub::enregistrerPieceValidee` | **OUI** | `MoteurComptable.saisirPiece(valider: true)` (v44), synchronisée (`pieces_saisie`) | - | non | B4 |
| `Hub::enregistrerCompte` | **OUI** | `MoteurComptable.creerCompte` (v44), synchronisé (`plan_comptable`, création seule), plan descendu du serveur | - | non | A12 |
| `Hub::enregistrerImmo` (+ plan d'amortissement) | **OUI** | `ImmobilisationsDao.creer` (v35), synchronisée | - | non |  |
| `Hub::enregistrerExercice` | **OUI** | `ComptabiliteDao.insererExercice` ; non poussé, le serveur ouvre le sien | - | non | B5 |
| `Hub::demarrerCloture` / `reprendreSaisie` / `cloturerExercice` / `rouvrirExercice` | **OUI** | `ClotureExerciceLocale` (v40) ; demandes `demandes_cloture_exercice` | - | non | B6 |
| `Hub::genererArchive` / `telechargerArchive` | **OUI** | `ArchiveClotureLocale` | - | non | B6 |
| `Hub::genererExport` (journal) | **OUI** | `ecran_comptabilite.dart:367` | - | non |  |
| `CorrespondanceComptes::enregistrerRole` / `retablirRole` | **OUI** | `ecran_correspondance_comptes.dart:412`, clés `compte_<rôle>` synchronisées | - | non |  |

### M11 Tableau de bord (`Accueil`)

| Action web | Poste | Preuve / cause | Effort | Schéma ? | Réf. |
|---|---|---|---|---|---|
| `enregistrerClientRapide` | **OUI** | `modales_rapides_accueil.dart:91` | - | non |  |
| `enregistrerReservationRapide` | **OUI** | `modales_rapides_accueil.dart:327` | - | non |  |
| `confirmerCheckin` | **OUI** | `reservations_du_jour.dart:501` | - | non |  |
| `confirmerCheckout` | **OUI** | `reservations_du_jour.dart:594` | - | non |  |
| `confirmerCheckinDepuisChambre` | **OUI** | `modales_rapides_accueil.dart:659,751` | - | non |  |
| `confirmerRecouvrementDuJour` (« Payer ») | **OUI** | `reservations_du_jour.dart:315`, `PaiementsFactureDao.recouvrer` | - | non |  |
| `genererExport` (rapports) | **OUI** | `modale_rapport_accueil.dart` | - | non |  |

### M12 Notifications (`Notifications\Hub`)

| Action web | Poste | Preuve / cause | Effort | Schéma ? | Réf. |
|---|---|---|---|---|---|
| `detecterMaintenant` | **OUI** | `NotificationsDao.detecter` | - | non |  |
| `enregistrerTransmission` | **OUI** | `NotificationsDao.marquerTransmis` | - | non |  |
| `envoyerMessage` | **OUI** | e-mail seulement ; autres canaux « à transmettre à la main » | - | non | B2 |
| `enregistrerAbandon` | **OUI** | `NotificationsDao.abandonner` | - | non |  |
| `enregistrerModele` (créer / modifier) | **OUI** | `creerModele` / `modifierModele` | - | non |  |
| `basculerModele` | **OUI** | `basculerActivation` | - | non |  |
| `genererExport` | **OUI** | `ecran_notifications.dart:293` | - | non |  |

### M13 RH / Paie / Congés (`Rh\Paie`, `Rh\CongesPlannings`)

| Action web | Poste | Preuve / cause | Effort | Schéma ? | Réf. |
|---|---|---|---|---|---|
| `Paie::enregistrerEmploye` (créer / modifier) | **OUI** | `EmployeDao.creer/mettreAJour` (homonymes avertis) | - | non |  |
| `Paie::etablirBulletin` | **OUI** | `PaieDao.etablir` | - | non |  |
| `Paie::genererBulletinsManquants` | **OUI** | `panneaux_paie.dart:890` | - | non |  |
| `Paie::annulerBulletin` | **OUI** | `PaieDao.annuler` | - | non |  |
| `Paie::confirmerArchivage` / `archiverEmployes` | **OUI (L1)** | `EmployeDao.archiver` + règle unique d'archivage | - | non | A11 |
| `Paie::genererExport` (livre de paie) | **OUI** | `ecran_paie.dart:220` | - | non |  |
| `Paie::exporterPdf` (bulletin A4) | **OUI (L1)** | `bulletin_paie_a4.dart` | - | non | A3 |
| `CongesPlannings::enregistrerPlanning` | **OUI** | `CongesPlanningsDao.planifier` | - | non |  |
| `CongesPlannings::enregistrerConge` | **OUI** | `CongesPlanningsDao.demander` | - | non |  |
| `CongesPlannings::validerConge` | **OUI** | `CongesPlanningsDao.valider` | - | non |  |
| `CongesPlannings::refuserConge` | **OUI** | `CongesPlanningsDao.refuser` | - | non |  |

### Dépenses (`Depenses\Depenses`)

| Action web | Poste | Preuve / cause | Effort | Schéma ? | Réf. |
|---|---|---|---|---|---|
| `enregistrerDepense` (multi-lignes, centre, trésorerie, reçu image) | **OUI** (L4, 27/10/2026) | `DepenseDao.enregistrer(recu:)`, `EnvoiRecusDepenses`, `PUT /sync/depenses/{id}/recu` | - | v42 | A9 |
| `comptabiliserDepense` | **OUI** | `DepenseDao.comptabiliser` (centre explicite) | - | non |  |
| `genererExport` | **OUI** | `barre_filtres_depenses.dart:260` | - | non |  |

### POS comptant, POS hébergés, Historique des ventes, Caisse (`Pos\*`)

| Action web | Poste | Preuve / cause | Effort | Schéma ? | Réf. |
|---|---|---|---|---|---|
| `PosComptant::ajouterAuPanier` / `incrementerLigne` / `decrementerLigne` / `retirerLigne` | **OUI** | `PanierDao.ajouterLigne/modifierQuantite/retirerLigne` | - | non |  |
| `PosComptant::viderPanier` | **OUI** | `vue_panier.dart:880` | - | non |  |
| `PosComptant::appliquerRemise` | **OUI** | `PanierDao.appliquerRemise` | - | non |  |
| `PosComptant::abandonnerPanier` | **OUI** | `vue_panier.dart:892` | - | non |  |
| `PosComptant::encaisser` | **OUI** | `PanierDao.cloturer` (pièce `VTE`) ; sorties de stock non écrites | - | non | B3 |
| `PosComptant::encaisserMalgreRupture` | **OUI** | `rupture_comptoir.dart` | - | non |  |
| `PosComptant::ouvrirCaisse` | **OUI** | `SessionsCaisseDao.ouvrir` | - | non |  |
| `PosComptant::cloturerCaisse` | **OUI** | `SessionsCaisseDao.cloturer` | - | non |  |
| `PosComptant::annulerVente` | **OUI** | `PanierDao.annulerVente`, `barre_session_caisse.dart:191` | - | non |  |
| `PosHeberges::ajouterAuPanier` / `incrementerLigne` / `decrementerLigne` / `retirerLigne` / `appliquerRemise` | **OUI** | `ecran_pos_heberges.dart` (panier du séjour) | - | non |  |
| `PosHeberges::cloturerEtFacturer` | **OUI** | `modale_cloture_sejour.dart` | - | non |  |
| `HistoriqueVentes::annulerVente` | **OUI** | `providers_ventes.dart:259`, `dialogue_detail_vente.dart` | - | non |  |
| `HistoriqueVentes::telechargerTicket` | **OUI** | `impression/ticket_vente.dart` | - | non |  |
| `HistoriqueVentes::genererExport` | **OUI** | `barre_filtres_ventes.dart:355` | - | non |  |

### Transverse : Paramètres, Rôles, Profil, Contact, Import/Export, Alertes, Session, Synchronisation

| Action web | Poste | Preuve / cause | Effort | Schéma ? | Réf. |
|---|---|---|---|---|---|
| `Parametres::enregistrerParametre` | **OUI** | `EnregistrerParametres`, registre fermé de 46 clés relu du serveur | - | non |  |
| `Parametres::enregistrerCanal` / `basculerCanal` / `demanderDesactivationCanal` | **OUI** | `CanauxReservationDao.ajouter/renommer/basculer` | - | non |  |
| `Parametres::basculerOption` | **OUI** | `ecran_parametres.dart` (onglet Activation) | - | non |  |
| `Parametres::envoyerEmailTest` | **OUI** | SMTP direct du poste | - | non |  |
| `Parametres::enregistrerMotDePasseSmtp` / `effacerMotDePasseSmtp` | **OUI** | écrit dans `poste.json`, jamais en base | - | non |  |
| `Parametres::enregistrerLogo` / `enregistrerFavicon` | **OUI** | `onglet_apparence.dart` | - | non |  |
| `Parametres::enregistrerTable` / `basculerTable` / `retablirTables` | **OUI** | `TablesPosDao.creer/renumeroter/basculer/retablirJeuInitial` | - | non |  |
| `RolesPermissions::enregistrerRole` | **OUI** | `RolesDao.creerRole` | - | non |  |
| `RolesPermissions::enregistrerDroits` / `toutRetirer` | **OUI** | `RolesDao.definirDroits` | - | non |  |
| `RolesPermissions::retablirSocle` | **OUI** | `RolesDao.retablirSocle` | - | non |  |
| `MonProfil::changerMotDePasse` | **OUI** | `SessionRepositoryLocal.changerMotDePasse` | - | non |  |
| `ContactEditeur::envoyerMessage` | **OUI** | `MessagesEditeurDao` + boîte d'envoi | - | non |  |
| `ContactEditeur::signalerBug` (capture jointe) | **OUI** | `captures_editeur.dart` | - | non |  |
| `ImportExport::controlerFichierImport` / `confirmerImport` (+ modèle CSV) | **OUI** | `importeurs_locaux.dart` : 8 modules | - | non |  |
| `ImportExport::genererSauvegarde` / `telechargerSauvegarde` | **OUI** | `SauvegardesPoste` (`VACUUM INTO`) | - | non |  |
| `ImportExport::retirerSauvegarde` / `confirmerRetraitSauvegarde` | **OUI** | `SauvegardesPoste.retirer` | - | non |  |
| `ImportExport::exporterTable` | **OUI** | `ecran_import_export.dart` | - | non |  |
| `ImportExport::restaurerArchive` | **OUI (L2)** | registre dérivé, `ArchivesPoste.restaurer` | - | non | A4 |
| `ImportExport::purgerArchive` | **OUI (L5-A5)** | corbeille de ligne, `_ModalePurge`, `ArchivesPoste.purger`, `purgerArchiveProvider` (super_admin puis écriture Paramètres) ; jeton `#modale:import_export.purge_titre` levé | - | v43 | A5 |
| `ImportExport::reinitialiserDonneesTest` | **OUI** | `reinitialisation_locale.dart` | - | non |  |
| `VerrouSession::deverrouiller` | **OUI (L1)** | `voile_verrou_session.dart`, `verrou_session.dart` | - | non | A1 |
| `AlertesOuvertureModales::effectuerCheckOutOuverture` | **OUI (L1)** | `ModalesOuvertureNotifier.effectuerCheckOut` | - | non | A2 |
| `AlertesOuvertureModales::tracerRelanceOuverture` | **OUI (L1)** | `ModalesOuvertureNotifier.tracerRelance` | - | non | A2 |
| `ClocheNotifications::marquerLu` / `marquerToutLu` | **OUI** | `AlertesVuesDao.marquerVues` | - | non |  |
| `SynchronisationPostes::synchroniser` / `revoquer` | **OUI** | `ServiceSuiviPostes` (exige le serveur) | - | non |  |
| `ReceptionSynchronisation::enregistrerCorrection` / `relancer` / `ignorer` | **ABSENT** | journal de réception du SERVEUR ; le poste a sa propre file | - | non | B7 |
| `EnvoiSynchronisation::demanderRedescente` / `redescendre` | **ABSENT** | journal d'envoi du SERVEUR | - | non | B7 |


## 5. Plan de lots proposé

Principe : d'abord ce qui ne demande **ni schéma ni serveur**, puis un seul lot de schéma
**v41** groupé (une migration additive conditionnelle, un seul retour arrière à écrire
dans `retour_arriere_schema.dart`), puis ce qui exige une décision du PO.

| Lot | Contenu | Dépend de | Effort | Schéma |
|---|---|---|---|---|
| **L0** | Nettoyage des commentaires et jetons périmés (section 6), sans changer le comportement | rien | S | non |
| **L1** | Gestes sans schéma : A11 (règle d'archivage de la Paie, après décision D272), A1 (verrou de session), A3 (bulletin de paie PDF/impression), A2 (modales d'ouverture de session) | L0 (facultatif) | S + S + M + M | non |
| **L2** | A4 : « Restaurer » depuis un registre dérivé (unités + véhicules `hors_service`, restaurations passées lues de la file d'envoi) | rien | M | non |
| **L3-S** | **FAIT (27/10/2026)** — serveur d'abord : `GestionnaireVehicules::modifier` accepte année, places, transmission ; `GestionnaireContratsLocation` accepte remise et acompte (phrases de la vue) et range le montant net ; `GestionnairePlats` accepte `categorie` en synchronisation ; guides déjà prêts ; `COLONNES` descend `plats.categorie` et `contrats_location.acompte` | décisions D1, D2 | L | côté serveur seulement |
| **L3** | **FAIT (27/10/2026)** — **poste v41** : `vehicules_local` (capacité, année, transmission), `contrats_location_local` (numéro, remise, acompte, montant figé ; le reste dû se calcule), `plats_local` (catégorie), `guides_local` (certification, tarif jour) ; modales A6, A7, A8, A10, import M8/M4, états (Contrats, M14 « Locations », tableau de bord), descente, `retour_arriere_schema`, `migration_v41_champs_du_web_test` sur fichier réel | L3-S | L | **v41** |
| **L4 (LIVRÉ 27/10/2026, v42)** | A9 reçu de dépense : colonne `recu_chemin` + sélecteur de fichier (mécanisme `captures_editeur.dart` existant) + transport de fichier à la synchronisation | décision D4, serveur | L | **v41 ou v42** (v42 si L3 est déjà livré) |
| **L5** | Décisions structurantes : A5 purge (protocole `suppression`) — **LIVRÉ 28/10/2026, v43** —, A12 plan comptable synchronisé, B4/D246 pièces manuelles partagées — **LIVRÉS 28/10/2026, v44** | décisions D5, D6 | L chacun | v43 (A5), v44 |

Ordre recommandé : L0, L1 (A11 → A1 → A3 → A2), L2, puis L3-S et L3 ensemble, puis L4, et
L5 seulement sur décision. Lots exigeant un schéma ≥ v41 : **L3** et **L4**.

## 6. Documentation et jetons périmés (piège 8 : un commentaire n'est pas une garantie)

Relevés au cours de la lecture, à corriger au lot L0 pour qu'ils cessent de désigner comme
« lecture seule » ce qui est livré :

- `lib/features/hebergement/presentation/ecran_hebergement.dart:54-65` : dit que le check-in/out n'est pas enregistré et que la table des séjours n'est pas répliquée ; faux, `SejourDao.checkin/checkout` sont appelés (`vue_plan_hebergement.dart:810`, `:842`).
- `lib/features/vehicules/presentation/ecran_vehicules.dart:71` : « Immobilisations : vide, aucune table locale » ; faux depuis la v32 (`modale_immobilisation.dart:250`, `VehiculeDao.enregistrerEntretien`).
- `lib/features/tourisme/presentation/ecran_tourisme.dart:79-82` : dit que `reservations_tour` n'est au registre d'aucune synchronisation et qu'une prestation reste sur le poste ; faux, `circuits`, `guides`, `reservations_tour` sont dans `TableSynchronisee`.
- `lib/features/hebergement/presentation/ecran_reservations.dart` (onglet Annulations « sans source ») : périmé depuis la v19 (huit colonnes d'annulation).
- (CORRIGÉ au lot L2) `lib/features/transverse/presentation/ecran_import_export.dart` : attribuait le refus de « Restaurer » à une table d'archives à créer ; le web n'en a pas (A4).
- `lib/features/restaurant/presentation/ecran_carte_restaurant.dart:110` : jeton `blade-refuse:…#modale:modal-retirerdelacartedujour` alors que la phrase voisine dit que le refus est retiré et que le retrait est livré (`IndisponibilitesCarteDao.retirer`).
- `lib/features/rh/presentation/providers_rh.dart:79` : la condition de réouverture (« si les Paramètres deviennent locaux ») est remplie depuis la v11.
- `CLAUDE.md` du poste : le titre « schéma v21, 53 tables » côtoie v38/v40 ; `AUDIT_POSTE_AUTONOME.md` §5 s'arrête à la v40 mais le titre du tableau §3 est inchangé.

Dette de conformité Blade (`dette-blade-flutter.json`, régénérée le 27/10/2026) : 8 blocs et
11 libellés absents, purement d'affichage (`accueil|page`, `accueil|pilotage`,
`notifications/hub|page`, `aide-a-propos|page` ×2, `parametres|email`, `hub|modale-titre-calcule`,
`import-export|retrait_titre`, `import-export|sauvegardes` ×3). Aucun n'est un manque CRUD,
sauf `import-export|retrait_titre` et `sauvegardes` à rapprocher de la modale « Retirer de
la liste » (le geste existe : `SauvegardesPoste.retirer`).

## 7. Décisions que le PO doit trancher

- **D1** *(TRANCHÉ : OUI, 27/10/2026, livré par le lot L3)* : lever l'arbitrage D100/D148 : la catégorie d'un plat (dix valeurs du web) est-elle portée par le poste, ce qui oblige le serveur à l'accepter en synchronisation (aujourd'hui interdite par `CHAMPS_REFUSES`) ? Sinon le web garde un champ que le poste n'aura jamais.
- **D2** *(TRANCHÉ : OUI, 27/10/2026, livré par le lot L3)* : le contrat de location du poste doit-il porter remise et acompte comme le web (le serveur fixe aujourd'hui l'acompte d'un contrat de poste à 0) ? Et le montant doit-il être **figé** à la signature (aujourd'hui recalculé au tarif courant) ?
- **D3** : brancher la règle d'archivage unique (administrateur / super_admin OU bascule) sur la Paie (D272) ?
- **D4** : justificatif de dépense : accepte-t-on un transport de fichier dans la synchronisation (aujourd'hui JSON seul) ?
- **D5** *(TRANCHÉ : OUI, 28/10/2026, livré par le lot L5-A5)* : la purge définitive d'une unité ou d'un véhicule archivé existe au poste, par une opération `suppression` du protocole (registre fermé à ces deux tables).
- **D6** *(TRANCHÉ : OUI, 28/10/2026, livré par le lot L5-A12)* : D246 est rouvert par décision du PO pour le plan comptable (A12) et les pièces saisies à la main (B4) : le poste fait ce que le web fait, avec sa synchronisation.
- **D7** (TRANCHÉ en pratique, A3 : document remis, sans visas, comme le gabarit serveur) : PA-192, PDF « certifié A4 » : le bulletin de paie A4 (A3) reprend-il le gabarit tabulaire commun ou exige-t-il visas et en-tête propres ?

## 8. Lot L3-S + L3 livré (27/10/2026, schéma v41)

Décisions D1 (catégorie d'un plat) et D2 (remise, acompte, N° et montant FIGÉ d'un contrat)
prises par le PO : « convertir en CRUD, même logique que le web ». Le détail technique est
dans `tatacora-flutter/CLAUDE.md`, section « Les champs du web portés : véhicule, contrat,
plat, guide ».

- **Serveur** (`tatacora-api`, `app/Shared/Sync`) : `GestionnaireVehicules::modifier` accepte
  `annee` (1950 à l'an prochain), `capacite` (1 à 99) et `transmission` ;
  `GestionnaireContratsLocation::creer` accepte `remise` et `acompte`, les juge dans l'ordre
  de `Locations::enregistrerContrat` (remise > brut, puis acompte > net, phrases `lte` de la
  vue) et range montant net, acompte et reste dû ; `GestionnairePlats` accepte `categorie`
  (dix clés de `CarteRestaurant::CATEGORIES`, `required`, jamais nulle) sans lever
  `EnregistrerPlatRequest::CHAMPS_REFUSES` pour l'API ; `GestionnaireGuides` rangeait déjà
  certification et tarif. `CatalogueDescendantService::COLONNES` : `plats.categorie` et
  `contrats_location.acompte` descendent. Tests : `VehiculesSynchronisationTest`,
  `CatalogueRestaurantSynchronisationTest`, `TourismeSynchronisationTest`,
  `ChampsPosteDescendantsTest`.
- **Poste** : v41, dix colonnes nullables, aucune table neuve (76 tables). Rien n'est déduit
  pour l'existant : un ancien contrat garde N°, montant, acompte et remise nuls (« — », le
  montant n'est PAS recalculé au tarif courant ; la descente le comble avec le chiffre du
  serveur là où il est nul), un ancien véhicule n'a ni année ni places, un ancien plat n'a
  pas de catégorie, un ancien guide ni certification ni tarif.
- **Mentions retirées** : « Places / Année / Transmission non enregistrées » (modale et
  colonne), « Remise / Acompte / Reste à payer sans colonne » (modale, aperçu, liste, état),
  « montant recalculé au tarif courant » (liste, état, aide du tarif), « catégorie du plat =
  type du menu, arbitrage D100 ouvert » (modale et catalogue du restaurant), « le poste ne
  saisit ni année ni capacité » et « le tarif du guide n'est pas saisi au poste » (commentaires
  des gestionnaires du serveur).
- **Guide** : la mention « certification et tarif partent au serveur mais ne sont pas rangés »
  (A10) est périmée : `guides_local.certification` et `.tarif_jour` existent, la fiche les écrit
  et les relit, la descente les redonne.
- **Écarts assumés** : (1) la CARTE du restaurant (filtre, couverture du stock, impressions)
  classe toujours par type de menu, comme `CarteRestaurantService` de l'API, alors que la vue
  PWA la classe par la catégorie du plat ; (2) le serveur ne garde pas la remise : un contrat
  descendu d'ailleurs n'a pas de remise ; (3) si le tarif d'un véhicule change entre la
  signature au poste et la réception, le serveur range SON montant (tarif de sa réception) et
  le poste garde le sien — la descente ne réécrit jamais le montant figé du poste ; (4) les
  KPI et la ligne TOTAL des contrats rendent « — » dès qu'un contrat actif de la période est
  d'avant la v41 et pas encore reçu du serveur (une somme amputée serait plausible et fausse).

## 8. Suite du lot L4 (27/10/2026)

D4 = OUI. A9 est livré : colonnes `depenses_local.recu_*` (schéma **v42**, après la v41 de L3), fichier rangé dans `recus_depenses/` à côté de `poste.json`, dépôt `PUT /api/v1/sync/depenses/{id}/recu` (idempotent par SHA-256, 400 Ko, mêmes droits que la dépense, journal de réception `recus_depenses`), référence redescendue (`donnees.recu`), téléchargement à la demande. Détail et écarts : `tatacora-flutter/CLAUDE.md`, section « Le reçu en image d'une dépense ».

## 9. Lots L0, L1, L2 livrés (27/10/2026, sans schéma)
- **L0** : en-têtes et jetons `blade-refuse:` périmés corrigés (section 6) après vérification ; le jeton `#restaurer` est levé (A4), il ne reste que `#modale:import_export.purge_titre` (A5, hors périmètre).
- **L1** : A11 (règle d'archivage unique), A1 (verrou de session), A3 (bulletin A4), A2 (modales d'ouverture) livrés ; chacun avec preuve contre le serveur PHP réel et mutation-tests.
- **L2** : A4 (Restaurer) sur registre dérivé. Gardes web `PwaActionsReluesTest` et `PwaEcritureAutoriseeTest` : 15 tests verts, aucune garde Livewire manquante à inscrire.
- **Écarts assumés** : le bulletin A4 n'a pas de visas ; durée du circuit non composée dans les départs à échéance ; export Immobilisations absent ; registre d'archives limité à CE poste (« — » sans opération locale) ; A5 (purge) livré ensuite (section 11) et A12 (section 10).

## 10. Lot L5-A12 / B4 livré (28/10/2026, schéma v44) — D246 rouvert par décision du PO du 28/10/2026

- **A12, compte du plan** : `MoteurComptable.creerCompte` enfile une `creation` (`plan_comptable`, numéro + libellé + nature) dans sa transaction. Serveur : `GestionnairePlanComptable` rejoue `PlanComptableService::creerCompte` (mêmes validations, mêmes phrases), idempotent sur l'identifiant du poste ; un numéro déjà pris est FONDU si libellé et nature sont les mêmes (`fusionne_avec`), sinon REFUSÉ à la phrase « Le compte … existe déjà » (À traiter). Le web n'a aucune modification de libellé : création seule. Descente : `TableDescendue.planComptable`, après les exercices et AVANT les écritures ; l'aligneur ajoute un compte absent (clé : le numéro), n'en réécrit jamais un, n'enfile rien.
- **B4, pièce saisie à la main** : `MoteurComptable.saisirPiece` (seul chemin qui enfile une pièce) passe la pièce, la marque (`pieces_saisie_local`, identifiant d'origine) et enfile la SOURCE (`pieces_saisie` : journal, date, libellé, statut, lignes en centimes, centre par son libellé). Serveur : `GestionnairePiecesSaisie` rejoue `PasserEcritureService` (équilibre, exercice ouvert ou en clôture, compte imputable, RG-12, journaux CL/AN refusés) et passe SA pièce, brouillon ou validée, avec `ecritures_comptables.piece_origine_id`. Les pièces des modules (vente, dépense, règlement, clôture) ne partent jamais, ni une pièce descendue.
- **Pas de double comptage** : les états ne lisent que le miroir `ecritures_serveur_local`, jamais `ecritures_local`. Une pièce redescendue y arrive avec `piece_origine_id` : `ComptabiliteDao.piecesSaisiesNonReprises` la reconnaît (plus « en attente de reprise »), et une pièce validée non encore reprise n'est dans aucun état (le bandeau de provenance compte l'opération en attente).
- **Écarts assumés** : une pièce saisie AVANT la v44 n'est ni marquée ni envoyée (le serveur ne peut pas la distinguer d'une pièce de module) ; un brouillon du poste reste brouillon au serveur (ni le web ni le poste n'ont de validation différée) ; interrupteur « Synchronisation activée » éteint : rien n'est enfilé.

## 11. Lot L5-A5 livré (28/10/2026, schéma v43) — D5 = OUI

Décision du PO : « OUI » à la purge définitive d'une unité d'hébergement ou d'un véhicule archivé, et aux tests d'écran manquants.

- **Protocole** : `TypeOperationSync.suppression` (registre FERMÉ : `TableSynchronisee.accepteSuppression` = `unites_hebergement` et `vehicules`, miroir de `GestionnaireSynchronisation::accepteSuppression` ; un test relit les gestionnaires PHP). Serveur : `SynchroniserRequest` l'admet, `SynchronisationService::traiterSuppression` exige le super administrateur puis l'écriture `PARAM` (l'ordre de l'écran, refus tracé au journal de sécurité), puis le gestionnaire rejoue `ParcHebergementService::purger` / `ParcVehiculeService::purger` (mêmes verrous, mêmes phrases) ; un élément déjà absent est un accusé (`deja_supprime`), donc idempotent. Hors registre : `suppression_non_synchronisable`.
- **Descente** : la purge (web comme synchronisation) note `suppressions_synchronisation` (migration `2026_10_28_100000`) dans la transaction du `delete()` ; `CatalogueDescendantService` la sert comme élément `supprime: true` sous son curseur (`suppressions`), après les tables, pour les seuls postes qui lisent le module. Le poste la rejoue (`AligneurCatalogue._suppression`) SEULEMENT si aucune opération en attente ni réservation / contrat / entretien local n'y est rattaché ; sinon `ConserveLocalement` et le journal de réception le dit (`raisonPurgeSaisieRattachee` / `raisonPurgeSaisieEnAttente`). Rien n'est enfilé par la descente.
- **Poste** : `ParcDao.purger` et `VehiculeDao.purger` (écrivains uniques) rejouent les verrous dans l'ordre du serveur (non archivé ; engagé : réservation à venir / contrat non annulé finissant aujourd'hui ou plus tard, phrase `vehicules.verrou` et ses trois premiers contrats ; cité par un enregistrement passé) et enfilent la `suppression` (libellé) dans la transaction ; écran : corbeille (super_admin seul), `_ModalePurge` (refus motivé affiché DANS la modale), `purgerArchiveProvider` relit le rôle puis le droit d'écrire Paramètres.
- **Schéma v43** (indispensable : le `CHECK` du type de `operations_sync_local` n'admettait que création et modification) : table RECRÉE par `elargirTypesOperationsSync` (conditionnel, copie intégrale avant tout abandon, `seq` AUTOINCREMENT reporté, index recréés), fixture `_ajoutsParVersion[43]` + retour arrière qui RÉTRÉCIT la contrainte, `migration_v43_suppression_operations_test` sur fichier réel (v42, v38, v30, v26, rejeu).
- **Écarts assumés** : une purge refusée par le serveur APRÈS l'effacement local (réservation d'un autre poste qu'on ne connaît pas) laisse l'élément effacé sur ce poste jusqu'à « Redescendre depuis le début » ; l'opération rejetée est visible dans « À traiter » avec la phrase du serveur ; la purge n'a pas de retour (comme au web).
- **Tests d'écran ajoutés** : modales véhicule (Places / Année / Transmission), contrat (Remise / Acompte / Reste à payer), plat (Catégorie) et import M4 (colonne « Catégorie » contre le vrai `ControleImportService`, `tool/transverse/rejouer_import_m4.php`).

