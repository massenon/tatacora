# Inventaire du poste : écrans en lecture seule ou partiels, par rapport au web

Date : 27/10/2026. Branche `claude/quirky-johnson-2pbs4t`. Aucune modification de
code : cet inventaire est le seul livrable. Schéma du poste au moment de la mesure :
**v40, 76 tables** (`AppDatabase.schemaVersion`).

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
| Couvertes (OUI complet) | **135** |
| Partielles | **7** |
| Lecture seule | **0** |
| Absentes | **8** |

Parmi les absentes et partielles, certaines sont des écarts voulus (section 3) : 
**13 lignes relèvent des vrais manques (section 2)** et **2 sont des écarts voulus ou impossibles hors ligne (section 3)**. 
Les lignes OUI portant une référence B sont des gestes complets dont une conséquence serveur est voulue (MECeF, stock, pièces manuelles).

| Module | Actions | OUI | PARTIEL | ABSENT |
|---|---|---|---|---|
| M1 Hébergement | 14 | 14 | 0 | 0 |
| M2 Facturation | 3 | 3 | 0 | 0 |
| M3 CRM / Clients | 7 | 7 | 0 | 0 |
| M4 Restaurant | 10 | 9 | 1 | 0 |
| M5 Bar | 6 | 6 | 0 | 0 |
| M6 Stocks | 10 | 10 | 0 | 0 |
| M7 Achats | 8 | 8 | 0 | 0 |
| M8 Véhicules / Locations | 7 | 5 | 2 | 0 |
| M9 Tourisme | 7 | 6 | 1 | 0 |
| M10 Comptabilité | 9 | 8 | 1 | 0 |
| M11 Tableau de bord | 7 | 7 | 0 | 0 |
| M12 Notifications | 7 | 7 | 0 | 0 |
| M13 RH / Paie / Congés | 11 | 9 | 1 | 1 |
| Dépenses | 3 | 2 | 1 | 0 |
| POS comptant, POS hébergés, Historique des ventes, Caisse | 14 | 14 | 0 | 0 |
| Transverse : Paramètres, Rôles, Profil, Contact, Import/Export, Alertes, Session, Synchronisation | 27 | 20 | 0 | 7 |

**Lecture clé : le poste n'est presque plus en « lecture seule ».** Aucune action web n'est
restée purement lisible sur le poste ; les écarts réels sont (a) huit lignes absentes (six gestes à construire, deux journaux du
serveur hors périmètre), (b) cinq fiches dont des champs n'ont pas de colonne locale ou de
transport, (c) deux écarts de droit ou de synchronisation (A11, A12). Plusieurs en-têtes de code Dart qui parlent encore de « lecture seule »
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
| A1 | Verrou de session (`VerrouSession::deverrouiller`) | ABSENT | écran non construit | S | non |
| A2 | Modales d'ouverture de session : check-out inline, relance inline (`AlertesOuvertureModales`) | ABSENT | écran non construit ; l'aide du paramètre « Alertes à l'ouverture » le dit (`registre_parametres_local.dart:474`) | M | non |
| A3 | Bulletin de paie sur papier A4 : « Imprimer » et « PDF » (`Paie::exporterPdf`) | ABSENT | gabarit non construit ; les deux boutons s'affichent et répondent `VueBulletin.impressionAbsente` (`modales_paie.dart:1320`, `:1442-1451`) | M | non |
| A4 | Archives : « Restaurer » un élément (`ImportExport::restaurerArchive`) | ABSENT | refusé sur un motif **inexact** : le web n'a pas de table d'archives, son registre est un agrégat DÉRIVÉ des unités et véhicules `hors_service` (`RegistreArchivesService`). Le poste a ces deux états (`ParcDao.archiver/restaurer`, `VehiculeDao.changerStatut`) | M | non |
| A5 | Archives : « Purger » définitivement (`purgerArchive`) | ABSENT | suppression physique d'une unité ou d'un véhicule archivé (`ParcHebergementService::purger`, `ParcVehiculeService::purger`) ; le protocole de synchronisation ne connaît que création et modification, le serveur ne recevrait jamais la suppression | L | non (protocole serveur) |
| A6 | Véhicule : Places, Année, Transmission (`Locations::enregistrerVehicule`) | PARTIEL | `vehicules_local` n'a que `id, categorie, immatriculation, tarifJour, statut` ; trois champs rendus inertes (`modale_vehicule.dart:177-205`) ; le serveur accepte les trois à la création (`GestionnaireVehicules`) mais refuse leur modification (`champ_non_modifiable`) | M | v41 (3 colonnes) + serveur |
| A7 | Contrat : N° `LOC-`, Remise, Acompte, Reste dû (`Locations::enregistrerContrat`) | PARTIEL | `contrats_location_local` n'a aucune de ces colonnes ; le montant est recalculé au tarif COURANT (pas figé) ; champs inertes (`modale_contrat.dart:285-310`). Le serveur fixe acompte à 0 pour un contrat venu d'un poste (`GestionnaireContratsLocation`) | L | v41 (4 colonnes) + serveur |
| A8 | Plat : champ « Catégorie » (dix valeurs, `Restauration::enregistrerPlat`) | PARTIEL | `plats_local` n'a pas `categorie` ; décision PO D100/D148 ouverte (`modale_plat.dart:31`) ; **le web l'écrit en direct** par `CartePlatMenuService`, mais `EnregistrerPlatRequest::CHAMPS_REFUSES` l'interdit par l'API et donc par la synchronisation | M | v41 (1 colonne) + serveur |
| A9 | Dépense : reçu / justificatif image (`Depenses::enregistrerDepense`, `photoRecu`) | PARTIEL | aucune colonne ni sélecteur (`ecran_depenses.dart:90`) ; la synchronisation est du JSON, aucun transport de fichier ; la pastille « sans reçu » est vraie pour toutes les lignes | L | v41 (chemin du reçu) + serveur |
| A10 | Guide : Certification et Tarif/jour (`Departs::enregistrerGuide`) | PARTIEL | `guides_local` n'a que `id, nom, zoneCompetence` ; les deux valeurs PARTENT au serveur (`chargeGuide`) mais ne sont pas rangées ici | S | v41 (2 colonnes) |
| A11 | Archivage des employés : règle « administrateur / super_admin OU bascule » (`Paie::archiverEmployes`) | PARTIEL | `peutArchiverPaieProvider` réduit la règle aux deux rôles ; la règle unique `core/rbac/regle_archivage.dart` existe et sert déjà Fournisseurs, Clients, Articles (D272) | S | non |
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
| B4 | Pièces comptables saisies à la main (`enregistrerPieceBrouillon/Validee`) restent sur le poste | D246 : « le poste n'envoie JAMAIS une écriture » ; à rouvrir seulement si le PO veut une saisie manuelle partagée |
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
| `Restauration::enregistrerPlat` (créer / modifier) | **PARTIEL** | `RestaurantDao.enregistrerPlat` ; **catégorie** (dix valeurs) non portée | M | v41 | A8 |
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
| `enregistrerVehicule` (créer / modifier) | **PARTIEL** | `VehiculeDao.enregistrerVehicule` ; **Places, Année, Transmission** inertes | M | v41 | A6 |
| `remettreEnService` | **OUI** | `vue_parc.dart:399` (`changerStatut`) | - | non |  |
| `enregistrerContrat` | **PARTIEL** | `VehiculeDao.creerContrat` (RG-08/RG-09 tenues) ; **N°, Remise, Acompte, Reste dû** absents, montant non figé | L | v41 | A7 |
| `enregistrerImmobilisation` (entretien) | **OUI** | `VehiculeDao.enregistrerEntretien` (v32) ; pas de date de fin non plus au serveur | - | non | B14 |
| `confirmerArchivage` / `executerSuppression` (véhicule) | **OUI** | `VehiculeDao.archiverVehicule`, `vue_parc.dart:446` | - | non |  |
| `confirmerArchivage` / `executerSuppression` (contrat = annuler) | **OUI** | `VehiculeDao.annulerContrat` (v38), `vue_contrats.dart:418` | - | non |  |
| `genererExport` | **OUI** | `barre_filtres_vehicules.dart:169` | - | non |  |

### M9 Tourisme (`Tourisme\Departs`)

| Action web | Poste | Preuve / cause | Effort | Schéma ? | Réf. |
|---|---|---|---|---|---|
| `enregistrerReservation` | **OUI** | `TourismeDao.reserver` (RG-13 sur ce poste) | - | non |  |
| `enregistrerGuide` | **PARTIEL** | `TourismeDao.enregistrerGuide` ; certification et tarif/jour partent au serveur mais ne sont pas rangés | S | v41 | A10 |
| `enregistrerReaffectationGuide` | **OUI** | `TourismeDao.reaffecterGuide` | - | non |  |
| `enregistrerPrestation` (créer / modifier) | **OUI** | `TourismeDao.enregistrerCircuit` | - | non |  |
| `executerSuppression` (réservation = annuler) | **OUI** | `TourismeDao.annulerReservation` | - | non | B13 |
| `executerSuppression` (départ = annuler) | **OUI** | `TourismeDao.annulerDepart` | - | non | B13 |
| `genererExport` | **OUI** | `barre_filtres_tourisme.dart:171` | - | non |  |

### M10 Comptabilité (`Comptabilite\Hub`, `Comptabilite\CorrespondanceComptes`)

| Action web | Poste | Preuve / cause | Effort | Schéma ? | Réf. |
|---|---|---|---|---|---|
| `Hub::enregistrerPieceBrouillon` | **OUI** | `MoteurComptable` (local) ; non synchronisée | - | non | B4 |
| `Hub::enregistrerPieceValidee` | **OUI** | `MoteurComptable.passerEtValider` ; non synchronisée | - | non | B4 |
| `Hub::enregistrerCompte` | **PARTIEL** | `MoteurComptable.creerCompte` ; reste sur le poste, aucune table au registre de synchronisation | L | non | A12 |
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
| `Paie::confirmerArchivage` / `archiverEmployes` | **PARTIEL** | `EmployeDao.archiver` ; règle réduite aux deux rôles d'administration (bascule non lue) | S | non | A11 |
| `Paie::genererExport` (livre de paie) | **OUI** | `ecran_paie.dart:220` | - | non |  |
| `Paie::exporterPdf` (bulletin A4) | **ABSENT** | boutons « Imprimer » et « PDF » sans document | M | non | A3 |
| `CongesPlannings::enregistrerPlanning` | **OUI** | `CongesPlanningsDao.planifier` | - | non |  |
| `CongesPlannings::enregistrerConge` | **OUI** | `CongesPlanningsDao.demander` | - | non |  |
| `CongesPlannings::validerConge` | **OUI** | `CongesPlanningsDao.valider` | - | non |  |
| `CongesPlannings::refuserConge` | **OUI** | `CongesPlanningsDao.refuser` | - | non |  |

### Dépenses (`Depenses\Depenses`)

| Action web | Poste | Preuve / cause | Effort | Schéma ? | Réf. |
|---|---|---|---|---|---|
| `enregistrerDepense` (multi-lignes, centre, trésorerie) | **PARTIEL** | `DepenseDao.enregistrer` ; **reçu (photo)** absent | L | v41 | A9 |
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
| `ImportExport::restaurerArchive` | **ABSENT** | jeton `blade-refuse:transverse/import-export#restaurer` | M | non | A4 |
| `ImportExport::purgerArchive` | **ABSENT** | jeton `blade-refuse:…#modale:import_export.purge_titre` | L | non | A5 |
| `ImportExport::reinitialiserDonneesTest` | **OUI** | `reinitialisation_locale.dart` | - | non |  |
| `VerrouSession::deverrouiller` | **ABSENT** | aucun minuteur d'inactivité ni voile dans `lib/` | S | non | A1 |
| `AlertesOuvertureModales::effectuerCheckOutOuverture` | **ABSENT** | la cloche existe (`alertes_ouverture.dart`), pas les modales | M | non | A2 |
| `AlertesOuvertureModales::tracerRelanceOuverture` | **ABSENT** | idem ; `RelancesClientsDao` et `SejourDao` existent déjà | M | non | A2 |
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
| **L3-S** | **Serveur d'abord** : `GestionnaireVehicules::modifier` accepte année, capacité, transmission ; `GestionnaireContratsLocation` accepte remise et acompte et renvoie le `numero` ; `EnregistrerPlatRequest` / `GestionnairePlats` acceptent `categorie` en synchronisation ; guides déjà prêts | décisions D1, D2 | L | côté serveur seulement |
| **L3** | **Poste v41** (colonnes nullables, jamais de valeur inventée) : `vehicules_local` (capacité, année, transmission), `contrats_location_local` (numéro, remise, acompte, reste), `plats_local` (catégorie), `guides_local` (certification, tarif jour). Modales A6, A7, A8, A10, import M8/M4, états, descente (`AligneurCatalogue`), `retour_arriere_schema`, `migration_v41_*_test` sur fichier réel | L3-S pour A6, A7, A8 ; A10 immédiat | L | **v41** |
| **L4** | A9 reçu de dépense : colonne `recu_chemin` + sélecteur de fichier (mécanisme `captures_editeur.dart` existant) + transport de fichier à la synchronisation | décision D4, serveur | L | **v41 ou v42** (v42 si L3 est déjà livré) |
| **L5** | Décisions structurantes : A5 purge (protocole `suppression`), A12 plan comptable synchronisé, B4/D246 pièces manuelles partagées | décisions D5, D6 | L chacun | non (protocole/serveur) |

Ordre recommandé : L0, L1 (A11 → A1 → A3 → A2), L2, puis L3-S et L3 ensemble, puis L4, et
L5 seulement sur décision. Lots exigeant un schéma ≥ v41 : **L3** et **L4**.

## 6. Documentation et jetons périmés (piège 8 : un commentaire n'est pas une garantie)

Relevés au cours de la lecture, à corriger au lot L0 pour qu'ils cessent de désigner comme
« lecture seule » ce qui est livré :

- `lib/features/hebergement/presentation/ecran_hebergement.dart:54-65` : dit que le check-in/out n'est pas enregistré et que la table des séjours n'est pas répliquée ; faux, `SejourDao.checkin/checkout` sont appelés (`vue_plan_hebergement.dart:810`, `:842`).
- `lib/features/vehicules/presentation/ecran_vehicules.dart:71` : « Immobilisations : vide, aucune table locale » ; faux depuis la v32 (`modale_immobilisation.dart:250`, `VehiculeDao.enregistrerEntretien`).
- `lib/features/tourisme/presentation/ecran_tourisme.dart:79-82` : dit que `reservations_tour` n'est au registre d'aucune synchronisation et qu'une prestation reste sur le poste ; faux, `circuits`, `guides`, `reservations_tour` sont dans `TableSynchronisee`.
- `lib/features/hebergement/presentation/ecran_reservations.dart` (onglet Annulations « sans source ») : périmé depuis la v19 (huit colonnes d'annulation).
- `lib/features/transverse/presentation/ecran_import_export.dart:63-75` : attribue le refus de « Restaurer » à une table d'archives à créer ; le web n'en a pas (A4).
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

- **D1** : lever l'arbitrage D100/D148 : la catégorie d'un plat (dix valeurs du web) est-elle portée par le poste, ce qui oblige le serveur à l'accepter en synchronisation (aujourd'hui interdite par `CHAMPS_REFUSES`) ? Sinon le web garde un champ que le poste n'aura jamais.
- **D2** : le contrat de location du poste doit-il porter remise et acompte comme le web (le serveur fixe aujourd'hui l'acompte d'un contrat de poste à 0) ? Et le montant doit-il être **figé** à la signature (aujourd'hui recalculé au tarif courant) ?
- **D3** : brancher la règle d'archivage unique (administrateur / super_admin OU bascule) sur la Paie (D272) ?
- **D4** : justificatif de dépense : accepte-t-on un transport de fichier dans la synchronisation (aujourd'hui JSON seul) ?
- **D5** : la purge définitive d'une unité ou d'un véhicule archivé doit-elle exister au poste (impose une opération `suppression` dans le protocole) ?
- **D6** : D246 est-il rouvert pour le plan comptable (A12) et les pièces saisies à la main (B4) ?
- **D7** : PA-192, PDF « certifié A4 » : le bulletin de paie A4 (A3) reprend-il le gabarit tabulaire commun ou exige-t-il visas et en-tête propres ?
