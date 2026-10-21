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
  /// Lot F6 : l'annulation (avec ses conditions) et le déplacement.
  reservations('reservations', accepteModification: true),

  /// Lot F5 (17/10/2026) : l'arrivée (création) et le départ (modification)
  /// réels, par `SejourService`.
  sejours('sejours', accepteModification: true),
  clients('clients', accepteModification: true),
  fournisseurs('fournisseurs', accepteModification: true),
  pointsStockage('points_stockage', accepteModification: true),
  articles('articles', accepteModification: true),
  cartesBoisson('cartes_boisson', accepteModification: true),
  menus('menus', accepteModification: true),
  recettes('recettes', accepteModification: true),
  plats('plats', accepteModification: true),

  /// 21/10/2026 : le retrait (création) et la remise à la carte (modification).
  indisponibilitesCarte('indisponibilites_carte', accepteModification: true),
  categoriesHebergement('categories_hebergement', accepteModification: true),
  unitesHebergement('unites_hebergement', accepteModification: true),

  /// Lot F6 : l'envoi et la clôture (le statut seul).
  commandesAchat('commandes_achat', accepteModification: true),
  bonsReception('bons_reception', accepteModification: false),

  /// Audit de couverture (18/10/2026) : le règlement d'une commande, et son
  /// annulation (contre-passation au serveur).
  reglementsFournisseur('reglements_fournisseur', accepteModification: true),

  /// L'ouverture est une `creation`, la clôture la SEULE `modification` admise.
  sessionsCaisse('sessions_caisse', accepteModification: true),

  /// Lot F6 : le serveur annule une vente (`VenteService::annuler`) ; le
  /// poste n'annule qu'un panier OUVERT, jamais envoyé — rien ne part.
  /// Lot F6 (18/10/2026) : le plan de salle (numéro, places, activation),
  /// puis l'OCCUPATION d'une table (le panier ouvert : création = ouverture,
  /// modification = fermeture), arbitrée par le serveur entre postes.
  tablesSalle('tables_salle', accepteModification: true),
  paniers('paniers', accepteModification: true),
  ventes('ventes', accepteModification: true),
  depenses('depenses', accepteModification: false),

  /// Lots F5c et F5d (17/10/2026) : la facture APRÈS la vente qu'elle porte,
  /// l'encaissement après sa facture ; l'ANNULATION est leur seule
  /// modification (avoir, contre-passation).
  factures('factures', accepteModification: true),
  paiements('paiements', accepteModification: true),

  /// Tourisme (lot F4, 17/10/2026) : les définitions (dernier écrit gagnant)
  /// avant la réservation qui les cite ; la réservation se modifie par trois
  /// gestes (annulation, clôture, réaffectation du guide).
  circuits('circuits', accepteModification: true),
  guides('guides', accepteModification: true),
  reservationsTour('reservations_tour', accepteModification: true),

  /// Audit de couverture (18/10/2026) : le parc M8 (retouches et statut par
  /// ses gestes), puis les contrats (création seule, RG-08 au serveur).
  vehicules('vehicules', accepteModification: true),
  contratsLocation('contrats_location', accepteModification: false),

  /// Audit de couverture (18/10/2026) : M13 — le dossier (matricule du
  /// serveur), puis le bulletin (recalculé au serveur ; l'annulation).
  employes('employes', accepteModification: true),
  bulletinsPaie('bulletins_paie', accepteModification: true),

  /// Lot 10e (18/10/2026) : un ENREGISTREMENT de l'écran Paramètres (le lot
  /// soumis, sous un identifiant propre au geste — création seule), puis le
  /// référentiel des rôles (libellé et matrice). Jamais un compte.
  parametresSysteme('parametres_systeme', accepteModification: false),
  roles('roles', accepteModification: true),

  /// Lot 10f (18/10/2026) : les mouvements de stock SAISIS sur ce poste
  /// (stock d'ouverture, entrée, sortie, perte, transfert) — création seule.
  /// Ceux d'un document (réception, vente) ne partent pas : le serveur les
  /// écrit en appliquant le document.
  mouvementsStock('mouvements_stock', accepteModification: false),

  /// Lot 10f : la configuration M12 (couple événement × canal) ; les
  /// messages tracés restent sur leur poste.
  modelesNotification('modeles_notification', accepteModification: true);

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
