/// La DESCENTE du catalogue (lot F2b, 15/10/2026) — schéma v27, DEUX tables
/// neuves, migration additive.
///
/// ## Pourquoi elles existent (décisions du Product Owner des 14–15/10/2026)
///
/// L'offline-first est TOTAL : le poste crée et modifie son catalogue hors
/// ligne, le serveur fusionne (dernier saisi gagnant sur
/// `horodatage_client`), et le catalogue du serveur DESCEND sur chaque poste
/// (`GET /api/v1/referentiels`) pour que les identifiants convergent. La file
/// d'envoi (v26) est la moitié MONTANTE ; ces deux tables portent ce qu'il
/// faut à la moitié DESCENDANTE (piège 11 : une table répliquée a deux
/// moitiés).
///
/// ## `etat_synchronisation_local` — une petite table clé/valeur
///
/// | Clé | Qui l'écrit | Qui la lit |
/// |---|---|---|
/// | `descente.curseur` | `DescenteCatalogueDao.appliquerPage`, dans la transaction de la page, APRÈS l'application de ses éléments | `DescenteCatalogue` (paramètre `depuis`) |
/// | `descente.derniere` (bilan JSON de la dernière descente) | `DescenteCatalogueDao.consignerBilan` | l'écran de synchronisation (`derniereDescenteProvider`) |
/// | `descente.echecs`, `descente.prochaine_tentative` (repli PROPRE à la descente) | `DescenteCatalogueDao` | `DescenteCatalogue` |
/// | `element_differe:<table>:<id>` (élément reçu, à rejouer : dépendance absente ou modification locale en attente) | `DescenteCatalogueDao` | `DescenteCatalogue` (reprise en fin de descente) |
/// | `coherence.dernier` (le dernier contrôle de cohérence mesuré, JSON, avec ses écarts) | `DescenteCatalogueDao.consignerCoherence` | la partie « Réception » de l'écran de synchronisation |
/// | `operation_remplacee:<uuid>` (« Renvoyer » : l'opération rejetée et celle qui la remplace) | `OperationsSyncDao.renvoyer`, dans la transaction de l'enfilement | `OperationsSyncDao` (réclamation, déblocage, liste « À traiter ») |
///
/// ## `correspondances_sync_local` — identifiant serveur → identifiant local
///
/// Le poste ne réécrit JAMAIS une clé primaire locale (ses documents la
/// citent). Quand le serveur a fusionné un élément du poste sur le sien, ou
/// quand un centre de coût local se reconnaît à son libellé, la
/// correspondance est retenue ici et chaque élément descendu, chaque clé
/// étrangère qu'il cite, est traduit par elle.
///
/// | Colonne | Qui l'écrit | Qui la lit |
/// |---|---|---|
/// | toutes | `DescenteCatalogueDao.retenirCorrespondance` (flux `correspondances` du serveur, `fusionne_avec` des opérations de la file, centres reconnus par libellé) | `DescenteCatalogueDao.idLocal` (alignement) |
///
/// Le mode démonstration n'y écrit rien : la descente ne tourne jamais en
/// démonstration.
library;

import 'package:drift/drift.dart';

/// L'état de la synchronisation, clé par clé (voir l'en-tête).
@DataClassName('EtatSynchronisationLigne')
class EtatSynchronisationLocal extends Table {
  TextColumn get cle => text()();
  TextColumn get valeur => text()();
  DateTimeColumn get modifieLe => dateTime()();

  @override
  Set<Column> get primaryKey => {cle};
}

/// Une correspondance : l'élément serveur [idServeur] de [tableServeur] est,
/// sur ce poste, la ligne [idLocal].
@DataClassName('CorrespondanceSyncLigne')
class CorrespondancesSyncLocal extends Table {
  /// Le nom au registre du serveur (`articles`, `centres_cout`…).
  TextColumn get tableServeur => text()();
  TextColumn get idServeur => text()();
  TextColumn get idLocal => text()();

  /// D'où vient la correspondance : `flux` (rendue par `/referentiels`),
  /// `file` (le `fusionne_avec` d'une opération poussée), `libelle` (centre
  /// de coût reconnu à son libellé).
  TextColumn get origine => text()();
  DateTimeColumn get creeLe => dateTime()();

  @override
  Set<Column> get primaryKey => {tableServeur, idServeur};

  @override
  List<String> get customConstraints => [
    "CHECK (origine IN ('flux', 'file', 'libelle'))",
  ];
}
