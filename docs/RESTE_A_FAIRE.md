# Reste à faire — liste FINIE (28/10/2026)

> Règle : rien ne s'ajoute sans qu'autre chose en sorte. Une idée nouvelle va dans
> « Plus tard ». Le projet est « terminé à 100 % » quand chaque case de A à D est cochée.
> Principe directeur du PO : **le poste continue de travailler SANS la synchronisation
> vers le web**, et il est privilégié sur tous les modules.

## A. Obstacles comptables à lever (poste autonome)

- [x] **A1** Les états du poste (compte de résultat, bilan, indicateurs, balance) incluent
      les pièces saisies à la main du poste **pas encore reprises** par le serveur
      (reconnues par leur identifiant d'origine : jamais de double comptage), même quand
      la synchronisation est active et que le miroir du serveur contient des écritures.
- [x] **A2** Une pièce refusée par le serveur reste validée, immuable et **comptée** dans les
      états du poste ; l'écran le dit (bandeau) et le refus se lit dans « À traiter ».
- [x] **A3** Les pièces saisies à la main **avant la v44** : un geste explicite, réservé aux
      administrateurs et confirmé (« Envoyer mes anciennes pièces saisies »), les marque et
      les envoie — jamais déduit en silence. Sans ce geste, elles restent comptées au poste.

## B. Corrections serveur (PRD `PRD_CORRECTIONS_LOCATIONS_ET_ARCHIVAGE_VEHICULE.md`)

- [x] **B1** L'état M14 « Locations » exclut les contrats annulés (serveur + aperçu poste).
- [x] **B2** L'archivage d'un véhicule : même règle de date au serveur et au poste
      (le jour de restitution engage encore), avec test de parité.

## C. Cohérence de la carte du restaurant

- [x] **C1** La carte du restaurant (filtre, groupes de la couverture, impressions) classe par
      **catégorie du plat** comme la vue web (aujourd'hui par type de menu).

## D. Recette sur un vrai poste (par le PO, à signaler ici)

> 09/11/2026 : D1, D2, D3, D5, D6, D7 (et G5) FAITS ET VALIDÉS par le PO. Reste D4.

- [x] **D1** Installer `LogiReStock_Setup_<version>.exe` (`build_windows.bat`) sur un poste Windows.
- [x] **D2** Envoyer un vrai e-mail par le relais SMTP du Gîte (notification d'un client).
- [x] **D3** Essai à plusieurs postes avec coupures réseau, puis synchronisation désactivée.
- [ ] **D4** Déposer le reçu d'une dépense et le revoir sur un second poste.
- [x] **D6** Mot de passe perdu : réinitialiser un compte (temporaire affiché une fois, 24 h), se connecter avec lui (écran « Définissez votre nouveau mot de passe »), puis perdre le mot de passe administrateur et le retrouver avec le code de secours — au web et sur le poste Windows (impression du code comprise).
- [x] **D7** Facture proforma : émettre UNE proforma réelle sur un vrai poste (hors ligne), l'imprimer en A4 et la comparer au modèle papier (en-tête, ligne des activités, date longue, tableau vert, montant en lettres, bloc signature/cachet) ; rebrancher le réseau, vérifier le numéro `N°… FP-GCN/…` régularisé, puis la convertir en facture.
- [x] **D5** Désinstaller : l'avertissement Oui/Non s'affiche ; Non annule ; Oui supprime `%LOCALAPPDATA%\TATACORA` et `%APPDATA%\TATACORA` ; une mise à jour (même AppId) garde les données.

## E. Démarrage résilient (PRD `PRD_REINSTALLATION_ET_DEMARRAGE_RESILIENT.md`)

- [x] **E1** (R1) Écran « L'application ne peut pas démarrer » + journal `demarrage.log` (5 fichiers, secrets expurgés) ; base ouverte et migrée avant le premier écran métier, « préparation bloquée » au-delà de 45 s.
- [x] **E2** (R2) `reconcilierSchema` : tables, colonnes, index et déclencheurs RG-11 manquants rétablis à la fin de `onUpgrade` et à l'ouverture, jamais destructive, journalisée.
- [x] **E3** (R3) Migration prouvée depuis de vrais anciens schémas (`test/fixtures/schemas_anciens/vNN.sql`) : écart zéro avec une base neuve.

## F. Mot de passe perdu SANS e-mail (décision du PO du 29/10/2026, option A)

- [x] **F1** Réinitialisation par un administrateur (mot de passe temporaire de 24 h, changement obligatoire), code de secours de l'administrateur à usage unique (5 essais puis 15 min), journal d'audit sans aucun secret — au web et sur le poste (schéma v46), comptes distincts, rien ne se synchronise. Détail : `JOURNAL_DES_LOTS.md`.

## Plus tard (hors périmètre, décisions du PO ou impossible hors ligne)

- Relevé de géométrie en navigateur de la vue « Correspondance des comptes » (script de capture absent du dépôt).
- WhatsApp, SMS, Android (aucun contrat de transport) ; certification MECeF et numéro `F-` (serveur seul).
- Réduction automatique de l'image d'un reçu (au-delà de 400 Ko : refus, comme au web).
- Limitation d'essais sur la connexion par mot de passe du POSTE (le web limite à 5 par identifiant et adresse) : à décider.
- IP de l'ordinateur dans le journal d'audit du poste (le nom de la machine est la norme retenue).

## G. Facture proforma — poste (livré le 07/11/2026)

- [x] **G1** Régularisation du numéro à l'accusé (`SyncManager`), descente des proformas (`TableDescendue.proformas`, `AligneurCatalogue._proforma`) et des images signature/cachet (`TelechargementImagesDocument`, `GET /api/v1/sync/apparence-documents`, dossier d'apparence du poste).
- [x] **G2** Écran « Proformas » du poste (`ecran_proformas.dart`, route `/facturation/proformas`, lien depuis Facturation) : liste, filtre par statut, recherche, brouillon à lignes libres, émission, annulation avec motif, conversion confirmée, état « expirée », droits M2, libellés du web relus du serveur.
- [x] **G3** PDF A4 du poste (`proforma_a4.dart`, vert = `PaletteMaitre.vert700`), impression par `Printing.layoutPdf`, classé dans `pdf_directive_test`.
- [x] **G4** Boutons « Créer une proforma » (location, tourisme, hébergement, restauration pour événement : proforma vide, aucun module événement n'existe) avec le même préremplissage que le web ; signature et cachet sur la facture A4 du poste selon l'interrupteur.
- [x] **G5** Essai terrain D7 (une proforma réelle sur un vrai poste, comparée au modèle papier).
