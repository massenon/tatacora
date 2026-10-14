import '../entities/piece_facturation.dart';

/// Contrat d'accès au registre de facturation.
///
/// ## Toutes les lectures viennent du local, et il n'y a pas d'autre source
///
/// Comme pour le panier (D2) : aucune méthode de ce contrat n'atteint le
/// réseau. Ce n'est pas une étape de portage restée à faire, c'est un fait du
/// serveur — `SynchronisationService::TABLES_SYNCHRONISABLES` ne connaît que
/// `reservations` et `clients`, et `routes/api.php` n'expose **aucune** route
/// de facturation. Écrire une enveloppe réseau « pour plus tard » donnerait un
/// chemin que rien n'emprunte, et un chemin jamais exécuté est faux jusqu'à
/// preuve du contraire (PA-59, PA-63).
///
/// Le jour où M2 entrera au registre du serveur, c'est ici que le dépôt
/// composite s'ajoutera, sur le patron de M1 — et il faudra d'abord trancher
/// lequel des deux registres locaux fait foi (PA-99).
///
/// ## Aucune suppression n'est exposée, et c'est la propriété n°4
///
/// Il n'y a ni `supprimer`, ni `modifier`. Une pièce émise est immuable ;
/// [annuler] conserve l'original et **émet un avoir**. C'est la règle RG-11 des
/// écritures comptables : la correction passe exclusivement par
/// contre-passation. Un trou dans une séquence de numéros est indistinguable
/// d'une pièce dissimulée.
abstract interface class FactureRepository {
  /// Le registre, filtré.
  ///
  /// [origine], [statut] et [module] sont des **filtres sur un seul registre**,
  /// jamais la désignation d'un entrepôt. [module] retient les pièces dont au
  /// moins une ligne relève de cette activité.
  Future<List<PieceFacturation>> pieces({
    OrigineFacture? origine,
    StatutPiece? statut,
    ModuleFacturable? module,
  });

  Future<PieceFacturation?> parId(String id);

  Future<PieceFacturation?> parNumero(String numero);

  /// La facture **émise** d'une réservation, s'il y en a une.
  ///
  /// ⚠ **Les avoirs sont exclus, et c'est le piège de ce module.** Un avoir
  /// porte le **même** `reservationId` et le statut `emise`. Sans cette
  /// exclusion, annuler une facture ferait proposer l'avoir au téléchargement —
  /// un document à **montant négatif**, remis au client à la place de sa
  /// facture.
  Future<PieceFacturation?> facturePourReservation(String reservationId);

  /// La facture **émise** d'un panier, s'il y en a une.
  ///
  /// Sert de garde d'idempotence : sans elle, un second appui sur « Clôturer et
  /// facturer » émettrait une **seconde pièce numérotée** pour la même vente.
  /// Deux factures pour un encaissement gonflent le registre d'un montant que
  /// personne n'a reçu, et seul un avoir peut ensuite le défaire.
  ///
  /// Les avoirs sont exclus, pour la même raison que
  /// [facturePourReservation] : ils portent le même `panierId`.
  Future<PieceFacturation?> facturePourPanier(String panierId);

  /// Émet une pièce. Les lignes de [brouillon] sont **copiées**.
  Future<PieceFacturation> emettre(BrouillonFacture brouillon);

  /// Annule une facture **par avoir**, jamais par effacement.
  ///
  /// Rend le couple (facture marquée annulée, avoir émis).
  Future<AnnulationParAvoir> annuler(String pieceId, String motif);
}

/// Ce qu'il faut pour émettre une pièce — les lignes y sont déjà **décidées**.
///
/// Le brouillon ne connaît ni le numéro, ni la date d'émission : les deux sont
/// posés par le registre, dans la transaction qui écrit la pièce. Les laisser
/// au brouillon permettrait à un appelant de réutiliser un numéro.
final class BrouillonFacture {
  const BrouillonFacture({
    required this.origine,
    required this.lignes,
    this.clientNom = 'Client de passage',
    this.clientId,
    this.reservationId,
    this.panierId,
    this.modePaiement,
    this.pointVente,
  });

  final OrigineFacture origine;

  /// Les lignes à copier. Une pièce sans ligne n'existe pas.
  final List<LigneBrouillon> lignes;

  final String clientNom;
  final String? clientId;
  final String? reservationId;
  final String? panierId;
  final String? modePaiement;
  final String? pointVente;

  int get montantTotal => lignes.fold(0, (t, l) => t + l.montant);
}

/// Une ligne de brouillon — la forme d'entrée, avant copie au registre.
final class LigneBrouillon {
  const LigneBrouillon({
    required this.module,
    required this.libelle,
    required this.prixUnitaire,
    required this.quantite,
    this.codeArticle,
  });

  final ModuleFacturable module;
  final String libelle;
  final int prixUnitaire;
  final int quantite;
  final String? codeArticle;

  int get montant => prixUnitaire * quantite;
}

/// Le résultat d'une annulation : la pièce d'origine **conservée**, et l'avoir.
final class AnnulationParAvoir {
  const AnnulationParAvoir({required this.facture, required this.avoir});

  /// La facture d'origine, marquée `annulee`. Elle **existe toujours**, et son
  /// montant n'a pas été effacé.
  final PieceFacturation facture;

  /// L'avoir : une pièce à part entière, avec son **propre** numéro de
  /// séquence et des montants de sens inverse. C'est lui qui neutralise, pas la
  /// modification de l'original.
  final PieceFacturation avoir;
}

/* ====================================================================== */
/* Refus                                                                   */
/* ====================================================================== */

/// Une pièce sans ligne ne peut pas être émise.
final class FactureSansLigne implements Exception {
  const FactureSansLigne();

  @override
  String toString() =>
      'Une facture sans ligne ne peut pas être émise : il n’y aurait rien à '
      'réclamer, et rien à justifier.';
}

/// La pièce demandée n'existe pas.
final class PieceIntrouvable implements Exception {
  const PieceIntrouvable(this.reference);
  final String reference;

  @override
  String toString() => 'Pièce de facturation introuvable ($reference).';
}

/// Une facture déjà annulée ne se réannule pas.
///
/// Le refus n'est pas une formalité : une seconde annulation émettrait un
/// **second avoir**, et le registre porterait alors deux fois le montant en
/// négatif pour une seule facture.
final class FactureDejaAnnulee implements Exception {
  const FactureDejaAnnulee(this.numero);
  final String numero;

  @override
  String toString() =>
      'La facture $numero est déjà annulée : un second avoir porterait deux '
      'fois le même montant en négatif.';
}

/// Un avoir ne s'annule pas — il est déjà la correction.
final class AvoirNonAnnulable implements Exception {
  const AvoirNonAnnulable(this.numero);
  final String numero;

  @override
  String toString() =>
      'La pièce $numero est un avoir : il neutralise déjà une facture. '
      'L’annuler reviendrait à ré-émettre le montant sans le dire.';
}

/// Une annulation sans motif est indistinguable d'une erreur de manipulation.
final class MotifAnnulationRequis implements Exception {
  const MotifAnnulationRequis();

  @override
  String toString() =>
      'Un motif est requis : une annulation sans raison est indistinguable '
      'd’une erreur.';
}
