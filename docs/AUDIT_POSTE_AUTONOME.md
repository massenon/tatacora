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
- **Ce que l'interrupteur ne coupe pas : l'envoi SMTP** (e-mails de
  notification M12, Contact éditeur, e-mail de test). Ce n'est pas de la
  synchronisation : le poste parle DIRECTEMENT au relais SMTP configuré dans
  Paramètres → Email (le courriel ne passe pas par le serveur TATACORA).
  Synchronisation désactivée, un e-mail part donc quand même dès qu'un réseau
  existe ; hors réseau il reste dans la boîte d'envoi locale avec sa raison
  (§4 point 2). Comportement voulu, testé
  (`boite_envoi_emails_test.dart`, groupe « L'interrupteur … ne coupe PAS
  l'e-mail » : `poste.json` porte `synchronisation_activee: false`, l'e-mail
  part).

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
| M4 | « Prix », « Historique des prix » | changement rapide de prix et sa trace | N→O | `RestaurantDao.modifierPrix` trace chaque changement dans `historique_prix_carte_local` (v38) ; l'historique se lit localement (§4 point 4) |
| M5 Bar | Carte, Catalogue des boissons, lien au stock, retraits | tout | O | — |
| M5 | **Ventes du Bar** (onglet) + export | lignes de vente | N→O | même calcul local (`BoissonsApi.ventes` branché sur les paniers) |
| M5 | « Historique des prix » | trace des changements | N→O | même table locale, écrite par `CatalogueDao` à chaque changement de prix, descente seule du serveur (§4 point 4) |
| M6 Stocks | Articles, mouvements, inventaire, archivage | tout | O | — |
| M7 Achats | Commandes, réception, règlements, fournisseurs | tout | O | — |
| M8 Véhicules | Parc, contrats, planning, immobilisations | tout | O | — |
| M8 | Annulation d'un contrat de location | la PWA l'offre | N→O | colonne `contrats_location_local.statut` (v38), `VehiculeDao.annulerContrat`, envoyée au serveur et descendue (§4 point 5) |
| M9 Tourisme | Circuits, départs, réservations | tout | O | — |
| M10 Comptabilité | Passer écriture, Journal (et son export), Balance, Plan (création de compte), Ouvrir un exercice, Immobilisations | tout | O | **création de compte : une seule règle, 2 à 4 chiffres** (mission A) |
| M10 | **Compte de résultat, Bilan** | états financiers | N→O (vides hors ligne) | calculés sur les pièces du poste quand la synchronisation est désactivée (§2) |
| M10 | **Grand livre** | un compte à la fois, solde progressif, ouverture/clôture, à-nouveaux provisoires | N→O | `grand_livre_analytique.dart`, confronté au vrai `GrandLivreService` (filtres de statut, ouverture provisoire, ouverture inconnue) |
| M10 | **Analytique** | marge par centre | N→O | `analytiqueDe`, confronté au vrai `AnalytiqueService` |
| M10 | **Six indicateurs du bandeau** + alerte « Comptabilité déséquilibrée » | CA, VA, EBE, résultat net, trésorerie, total bilan | N→O | `indicateursDe` (assembleur du compte de résultat, du bilan, de la balance) |
| M10 | **Tuiles Flux de trésorerie (TAFIRE), Notes annexes, États financiers** | trois pages séparées de la vue | N→O | fenêtres calculées sur le poste (`tafire_notes.dart`), confrontées au vrai `TafireService` et `NotesAnnexesService` sur quatre exercices |
| M10 | **Clôtures** | clôture annuelle : provisoire, pièces CL et AN, réouverture, archive SHA-256 | N→O (v40) | `ClotureExerciceLocale` (seul écrivain), pièces par `MoteurComptable`, confrontées au vrai `ClotureExerciceService` (`cloture_contre_serveur_test`, 9 scénarios), demandes rejouées par le vrai `SynchronisationService` |
| M11 Tableau de bord | Bande d'indicateurs | 7 sur 8 | O | — |
| M11 | **Dépenses cumulées** | écritures de classe 6 | N→O (« — ») | calculées (`depensesCumuleesCentimes`), confrontées au vrai `TableauDeBordService`, bornes du serveur comprises |
| M11 | **Série mensuelle** (graphique) | CA encaissé et dépenses sur N mois | N→O (« non disponible ») | `serieMensuelleLocale`, confrontée à `serieMensuelle` |
| M11 | **Pilotage consolidé** : Résultat net, alertes comptables | M10 | N→O (« Non consulté ») | alimentés par les mêmes états que le hub |
| M12 Notifications | Modèles, déclencheurs, journal | tout | O | — |
| M12 | **Envoi réel d'un e-mail de notification** | SMTP direct, boîte d'envoi locale (v39) | N→O (réseau requis pour PARTIR) | écrit d'abord, envoyé ensuite, statuts/tentatives/repli/cause, « Envoyer » / « Renvoyer », jamais « envoyé » avant l'accusé SMTP (§4 point 2) |
| M13 RH | Employés, paie, congés et plannings | tout | O | — |
| M14 États | 11 états sur 12 | aperçus | O | — |
| M14 | **Balance générale** | aperçu | N→O (« listée, refusée ») | `apercuBalance` (écritures validées, à-nouveaux provisoires compris) |
| M14 | Exports PDF/archive des états | la vue n'en offre pas (décision PO) | sans objet | — |
| Transverse | Import & Export : importer (CSV), sauvegarde de la base (« Enregistrer sous »), exporter une table, réinitialiser | tout | O | — |
| Transverse | Import & Export : « Restaurer » (registre des éléments archivés), purge | registre transverse | **N** | reste (§4) |
| Transverse | Journal d'audit | lecture de la file d'envoi | N→O | colonnes « Utilisateur » et « Poste » conservées par la file (v38) ; « — » seulement pour les entrées d'avant la v38 (§4 point 7) |
| Transverse | Mon profil, Rôles et permissions, Comptes utilisateurs, Aide, Paramètres | tout (mot de passe SMTP dans `poste.json`) | O | — |
| Transverse | Contact éditeur, e-mail de test | SMTP | O (réseau requis pour PARTIR) | boîte d'envoi v25 + relance ; la cause du dernier échec est désormais DITE en ligne sous l'envoi (comme la PWA) |
| Transverse | Synchronisation, Postes & Appairage, contrôle de cohérence | exigent le serveur | **N** par nature | désactivée : les écrans le DISENT, aucune requête |

## 4. Ce qui reste impossible hors ligne, et pourquoi

1. **Certification MECeF et numéro officiel des factures** — un service fiscal
   externe et la séquence continue du serveur. Hors ligne le poste émet une
   facture provisoire, que le serveur régularise à la synchronisation.
2. **Envoi réel d'e-mails** — IMPLÉMENTÉ (décision du PO du 26/10/2026 :
   « l'envoi réel d'e-mails DOIT ÊTRE IMPLÉMENTÉ EN POSTE ET WEB »). Reste vrai :
   un relais SMTP exige un réseau pour que le courriel PARTE ; le message,
   lui, n'attend jamais le réseau pour être écrit.
   - **Web** (`EnvoiEmailNotificationService`, `ConfigurationMailService`) :
     le mot de passe SMTP est chiffré en base (`secrets_configuration`, 19/10).
     Un e-mail de notification composé avec une adresse est mis en file
     d'envoi (`EnvoyerNotificationEmailJob`, unique par message, 3 essais à
     1 puis 5 min, `queue:work` planifié chaque minute) ; la détection tourne
     chaque heure (`notifications:detecter`, idempotente) et
     `notifications:relancer-emails` (15 min) reprend les échecs (15 min par
     tentative, 5 tentatives automatiques). Colonnes ajoutées à
     `notifications_composees` et `messages_editeur` : `tentatives`,
     `derniere_erreur` (cause lisible, mot de passe expurgé),
     `derniere_tentative_le`, `envoye_le`. « Envoyer » devient « Renvoyer » après
     une tentative ; le hub dit « Tentatives d'envoi : n · Dernière erreur : … ·
     Relances automatiques épuisées ». Jamais deux e-mails : verrou par message
     + relecture du statut. « Contactez l'éditeur » passe aussi par un job
     (`EnvoyerMessageEditeurJob`) et note tentatives et cause.
   - **Poste** (schéma **v39**, table `boite_envoi_emails_local`,
     `BoiteEnvoiEmailsDao` écrivain unique, `ServiceBoiteEnvoiEmails`
     expéditeur unique, lib `mailer` déjà au `pubspec.lock`, transport
     injectable) : à la détection, un message M12 de canal e-mail dont
     l'adresse du client est lue est mis en boîte AVEC son message (même
     transaction) ; la relance (au démarrage puis toutes les 5 min, repli ×2 jusqu'à 6 h, 30 tentatives) et « Envoyer »
     / « Renvoyer » l'envoient par SMTP. Statuts `en_attente` / `envoye` /
     `echec` / `annule` (message transmis à la main ou abandonné : il ne part
     jamais). Clé d'idempotence unique `notification:<id du message>`. Le
     message de notification ne passe « Envoyé par le système » (donc
     « Réellement envoyés » ≥ 1) que dans la transaction qui écrit `envoye`,
     après l'accusé SMTP. Le mot de passe reste dans `poste.json`, jamais en
     base ni dans une cause d'échec. Le canal e-mail est « branché » quand la
     configuration SMTP du poste est complète (dérivé, relu).
   - **Preuves** : `boite_envoi_emails_test.dart` (dont un VRAI serveur SMTP sur
     socket locale : succès, mauvais mot de passe, refus 554, réseau absent
     puis retour du serveur), `notifications_envoi_email_test.dart`,
     `ecran_notifications_envoi_email_test.dart`,
     `migration_v39_boite_envoi_emails_test.dart` (fichier réel), côté web
     `EnvoiEmailNotificationTest` et `EnvoiMessageEditeurTest`.
   - **Limites assumées** : seul le canal e-mail part (WhatsApp, Android, SMS :
     aucun contrat, « à transmettre à la main ») ; un message composé AVANT la
     v39 n'a jamais eu son adresse lue : elle se lit au clic « Envoyer » ou à
     la détection suivante (rattrapage), jamais affirmée ; seuls les
     déclencheurs détectés sur le poste (séjour demain, départ du jour) ont une
     adresse ; l'e-mail du poste est expédié sous le nom « LogiRestock -
     TATACORA AFRIQUE » avec l'utilisateur SMTP comme expéditeur.
3. **Clôture annuelle SYSCOHADA** — IMPLÉMENTÉE EN POSTE ET WEB (décision du PO
   du 26/10/2026, schéma v40). Le web était complet (provisoire, pièces CL et AN,
   résultat 131/139, réouverture par le comptable, archive légale SHA-256).
   Le poste porte la même chose : onglet « Clôtures » du hub, pièces CL et AN
   équilibrées passées par `MoteurComptable` (RG-11), table
   `clotures_exercices_local` à écrivain unique. **Contrat de synchronisation** :
   le poste n'envoie JAMAIS une pièce de clôture (D246) ; chaque geste enfile une
   DEMANDE (`demandes_cloture_exercice`, démarrer / reprendre la saisie /
   clôturer / rouvrir), le serveur rejoue ses règles et passe les siennes. Une
   demande déjà satisfaite est acceptée sans rien réécrire. Preuves : pièces du
   serveur identiques à celles du poste, refus aux mots du serveur, 25 mutations
   toutes tuées. **Écarts assumés** : le résultat du poste ne compte que ses
   pièces (le serveur peut refuser, la clôture locale demeure et le refus se lit
   dans « À traiter ») ; pas de relevés bancaires (avertissement absent) ; PDF
   d'archive composé par le gabarit tabulaire commun (pas DomPDF) ; archives
   écrites dans `archives/` à côté de `poste.json` (hors sauvegarde de base) ;
   une demande non acceptée protège la clôture locale contre la descente.
4. **Historique des prix** (bar et restaurant) et **« Prix »** du restaurant —
   FAIT en v38. Table `historique_prix_carte_local`, miroir de
   `historique_prix_carte` ; seuls `CatalogueDao.enregistrerBoisson` et
   `RestaurantDao` l'écrivent, dans la transaction du changement de prix
   (`HistoriquePrixCarteDao.tracer` exige une transaction), avec la fonction
   pure `changementsDePrix` confrontée au vrai serveur
   (`tool/carte/rejouer_historique_prix.php`). Le serveur reste l'unique auteur
   de la trace (observateurs) : le poste ne la pousse PAS ; la trace locale est
   ADOPTÉE à celle du serveur équivalente quand elle descend (correspondance
   retenue), jamais doublée. Côté serveur, `historique_prix_carte` descend dans
   `CatalogueDescendantService` (`par` = login de l'auteur, restreint aux
   modules lisibles : M5 boisson, M4 plat). Écart : la colonne « Poste » de la
   vue serveur est une adresse IP, le poste n'a que le nom de machine.
5. **Annulation d'un contrat de location** — FAIT en v38. Colonne
   `contrats_location_local.statut` (nullable : `null` = actif), écrivain
   unique `VehiculeDao.annulerContrat`, refus aux phrases du serveur (relues par
   PHP), opération `modification {statut: annule}` (serveur :
   `GestionnaireContratsLocation::modifier`, rejeu accepté) et descente vers
   l'avant seulement. Un contrat annulé libère le véhicule (RG-08) et ne bloque
   plus l'archivage d'un client ni d'un véhicule : la règle d'archivage des
   clients « location non annulée » est reportée. Défaut serveur corrigé en
   chemin : un contrat annulé bloquait encore RG-08. Pas de restriction « document
   d'un autre poste » (la PWA n'en a pas). À signaler : l'état M14
   « Locations » du serveur liste encore tous les contrats, annulés compris.
6. **Restaurer / purge** de l'onglet Import & Export — registre transverse des
   éléments archivés de tous les modules ; chaque module restaure déjà ses
   propres éléments depuis son écran.
7. **Journal d'audit : utilisateur et poste** — FAIT en v38 : la file
   (`operations_sync_local.auteur_login`, `poste_nom`) conserve le login connecté
   et le nom de la machine (`AppDatabase.auteurEcriture`, câblé sur la session) ;
   `renvoyer` les recopie. Les entrées antérieures à la v38 gardent « — » (on ne
   déduit pas de donnée), et le journal ne montre que les écritures de CE poste.
8. **Numéros de vente `V-`, auteur de la vente** — FAIT en v38
   (`paniers_local.numero_vente`, `auteur_login`). Le numéro est une séquence du
   serveur : le poste ne l'invente jamais, il le reçoit à l'accusé du `POST /sync`
   ou à la descente de la vente ; avant, « — ». L'auteur est le compte connecté à
   la clôture, ou le `par` rendu par le serveur pour la vente d'un autre poste.
9. **Particularités de calcul** : les états comptables du poste ne portent que
   les écritures VALIDÉES (le filtre de statut du hub ne s'y applique pas) ; la
   balance de M14 ne compte pas les brouillons ; la note annexe n° 7 (événements
   postérieurs) est « non saisie » : son texte libre vit au serveur.

## 5. Schéma

Version **38** (74 tables) : une table neuve, `historique_prix_carte_local`, et six
colonnes NULLABLES (`contrats_location_local.statut`,
`operations_sync_local.auteur_login` / `poste_nom`,
`paniers_local.numero_vente` / `auteur_login`). Migration additive et
conditionnelle (`PRAGMA table_info`), le curseur de descente est oublié pour que
l'historique et les statuts redescendent ; prouvée sur fichier réel depuis
plusieurs versions (`migration_v38_poste_comme_le_web_test.dart`).

Version **39** (75 tables, mission « l'envoi réel d'e-mails », 26/10/2026) : UNE
table neuve, `boite_envoi_emails_local`, aucune colonne ajoutée, migration
additive CONDITIONNELLE (`from < 39`), fixture `_ajoutsParVersion[39]`, test sur
fichier réel (`migration_v39_boite_envoi_emails_test.dart`, depuis les versions
38, 26 et 10). La table apparaît vide : aucune ligne n'est fabriquée pour les
messages d'avant.

Version **40** (76 tables, mission « clôture annuelle », 26/10/2026) : UNE table
neuve, `clotures_exercices_local`, migration additive CONDITIONNELLE
(`from < 40`), fixture `_ajoutsParVersion[40]`, test sur fichier réel
(`migration_v40_clotures_exercices_test.dart`). Les journaux `AN` et `CL` sont
installés avec le référentiel. Aucune clôture n'est déduite pour les exercices
d'avant.
