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

- [ ] **B1** L'état M14 « Locations » exclut les contrats annulés (serveur + aperçu poste).
- [ ] **B2** L'archivage d'un véhicule : même règle de date au serveur et au poste
      (le jour de restitution engage encore), avec test de parité.

## C. Cohérence de la carte du restaurant

- [ ] **C1** La carte du restaurant (filtre, groupes de la couverture, impressions) classe par
      **catégorie du plat** comme la vue web (aujourd'hui par type de menu).

## D. Recette sur un vrai poste (par le PO, à signaler ici)

- [ ] **D1** Installer `LogiReStock_Setup_<version>.exe` (`build_windows.bat`) sur un poste Windows.
- [ ] **D2** Envoyer un vrai e-mail par le relais SMTP du Gîte (notification d'un client).
- [ ] **D3** Essai à plusieurs postes avec coupures réseau, puis synchronisation désactivée.
- [ ] **D4** Déposer le reçu d'une dépense et le revoir sur un second poste.

## Plus tard (hors périmètre, décisions du PO ou impossible hors ligne)

- Relevé de géométrie en navigateur de la vue « Correspondance des comptes » (script de capture absent du dépôt).
- WhatsApp, SMS, Android (aucun contrat de transport) ; certification MECeF et numéro `F-` (serveur seul).
- Réduction automatique de l'image d'un reçu (au-delà de 400 Ko : refus, comme au web).
- IP de l'ordinateur dans le journal d'audit du poste (le nom de la machine est la norme retenue).
