/// Le vocabulaire de la FILE D'ENVOI (`operations_sync_local`, schéma v26,
/// lot F1 du 15/10/2026).
///
/// Trois registres FERMÉS (`enum` + `switch` exhaustif) : un cas ajouté demain
/// n'obtient aucun comportement par omission.
library;

/// Les tables que le poste pousse — le registre `TABLES_SYNCHRONISABLES` du
/// serveur (`RegistreSynchronisation.php`), et lui seul.
///
/// ⚠ Aucune table d'écritures comptables n'y figure, et il ne doit jamais en
/// entrer une (D246, décision du PO du 15/10/2026) : le poste pousse des
/// documents SOURCES, le serveur produit lui-même les pièces. Un test relit le
/// registre PHP pour que cette liste ne puisse pas diverger du serveur, et un
/// autre balaie `lib/` pour qu'aucun écrivain n'enfile une écriture.
///
/// L'ordre de déclaration reprend celui du registre serveur (un élément cité
/// avant celui qui le cite) ; il ne commande rien ici : c'est `seq`, l'ordre
/// d'ÉCRITURE sur le poste, qui ordonne l'envoi.
enum TableSynchronisee {
  reservations('reservations', accepteModification: false),
  clients('clients', accepteModification: true),
  fournisseurs('fournisseurs', accepteModification: true),
  pointsStockage('points_stockage', accepteModification: true),
  articles('articles', accepteModification: true),
  cartesBoisson('cartes_boisson', accepteModification: true),
  menus('menus', accepteModification: true),
  recettes('recettes', accepteModification: true),
  plats('plats', accepteModification: true),
  categoriesHebergement('categories_hebergement', accepteModification: true),
  unitesHebergement('unites_hebergement', accepteModification: true),
  commandesAchat('commandes_achat', accepteModification: false),
  bonsReception('bons_reception', accepteModification: false),

  /// L'ouverture est une `creation`, la clôture la SEULE `modification` admise.
  sessionsCaisse('sessions_caisse', accepteModification: true),
  ventes('ventes', accepteModification: false),
  depenses('depenses', accepteModification: false);

  const TableSynchronisee(this.nomServeur, {required this.accepteModification});

  /// Le nom au registre du serveur — jamais le nom local (`_local`).
  final String nomServeur;

  /// Le gestionnaire serveur accepte-t-il une `modification` ? Une table qui
  /// la refuse la rejetterait (`sync.modification_non_synchronisable`) :
  /// `OperationsSyncDao.enfiler` refuse donc de l'enfiler.
  final bool accepteModification;

  static TableSynchronisee? depuisNom(String nom) {
    for (final t in values) {
      if (t.nomServeur == nom) return t;
    }
    return null;
  }
}

/// `operations.*.type` du protocole.
enum TypeOperationSync {
  creation('creation'),
  modification('modification');

  const TypeOperationSync(this.code);
  final String code;

  static TypeOperationSync depuisCode(String code) => switch (code) {
    'creation' => creation,
    'modification' => modification,
    _ => throw StateError('Type d’opération inconnu : « $code ».'),
  };
}

/// Le cycle d'une opération dans la file.
enum StatutOperationSync {
  /// Écrite, pas encore envoyée (ou rendue après un échec transitoire).
  enAttente('en_attente'),

  /// Réclamée par un lot, sous bail ([OperationSync.verrouJusqua]).
  enCours('en_cours'),

  /// Acceptée par le serveur (fusion et clôture sans session serveur
  /// comprises — le détail est dans [OperationSync.resultatJson]).
  synchronise('synchronise'),

  /// Refusée DÉFINITIVEMENT par le serveur, avec son motif.
  rejete('rejete'),

  /// Conflit financier à arbitrer côté serveur (RG-17).
  conflit('conflit'),

  /// Jamais envoyée : une opération ANTÉRIEURE sur le même élément a été
  /// rejetée — l'envoyer la ferait s'appliquer sur un état que le serveur n'a
  /// pas.
  bloque('bloque');

  const StatutOperationSync(this.code);
  final String code;

  static StatutOperationSync depuisCode(String code) {
    for (final s in values) {
      if (s.code == code) return s;
    }
    throw StateError('Statut d’opération inconnu : « $code ».');
  }
}

/// Une ligne de la file, lue.
final class OperationSync {
  const OperationSync({
    required this.seq,
    required this.uuidOperation,
    required this.table,
    required this.entiteId,
    required this.type,
    required this.payload,
    required this.horodatageClient,
    required this.dateMetier,
    required this.statut,
    required this.lotId,
    required this.verrouJusqua,
    required this.tentatives,
    required this.prochaineTentative,
    required this.derniereErreur,
    required this.codeHttp,
    required this.resultatJson,
    required this.idServeur,
    required this.creeLe,
    required this.synchroniseLe,
  });

  final int seq;
  final String uuidOperation;
  final TableSynchronisee table;
  final String entiteId;
  final TypeOperationSync type;

  /// Le JSON figé, tel qu'il sera envoyé.
  final String payload;
  final String horodatageClient;
  final String? dateMetier;
  final StatutOperationSync statut;
  final String? lotId;
  final DateTime? verrouJusqua;
  final int tentatives;
  final DateTime? prochaineTentative;
  final String? derniereErreur;
  final int? codeHttp;
  final String? resultatJson;
  final String? idServeur;
  final DateTime creeLe;
  final DateTime? synchroniseLe;
}

/// Une ligne de la liste « À traiter » de l'écran de synchronisation (lot
/// F2b) : une opération rejetée, en conflit ou bloquée.
final class OperationATraiter {
  const OperationATraiter({required this.operation, required this.debloquable});

  final OperationSync operation;

  /// Bloquée, et son blocage est levé : « Débloquer » est proposé.
  final bool debloquable;
}
