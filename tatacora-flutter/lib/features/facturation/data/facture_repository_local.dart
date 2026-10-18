import '../domain/entities/piece_facturation.dart';
import '../domain/repositories/facture_repository.dart';
import 'facture_dao.dart';

/// Dépôt de facturation — **strictement local**.
///
/// ## Pourquoi il n'existe pas de dépôt « composite » ici, contrairement à M1
///
/// M1 a un `ReservationRepositoryComposite` parce qu'une réservation part au
/// serveur. Une facture n'y va pas, et ce n'est pas un manque du portage :
/// `SynchronisationService::TABLES_SYNCHRONISABLES` ne connaît que
/// `reservations` et `clients`, et `routes/api.php` n'expose aucune route de
/// facturation. Écrire une enveloppe réseau « pour plus tard » donnerait un
/// chemin que rien n'emprunte — et un chemin jamais exécuté est faux jusqu'à
/// preuve du contraire (PA-59, PA-63).
///
/// Le jour où M2 entrera au registre du serveur, c'est ici que le composite
/// s'ajoutera, sur le patron de M1 — après l'arbitrage PA-99, qui doit dire
/// lequel des deux registres locaux (`factures_local`, transcrite du schéma
/// serveur et sans aucun appelant, ou celui-ci) fait foi.
final class FactureRepositoryLocal implements FactureRepository {
  const FactureRepositoryLocal(this._dao);

  final FactureDao _dao;

  @override
  Future<List<PieceFacturation>> pieces({
    OrigineFacture? origine,
    StatutPiece? statut,
    ModuleFacturable? module,
  }) => _dao.pieces(origine: origine, statut: statut, module: module);

  @override
  Future<PieceFacturation?> parId(String id) => _dao.parId(id);

  @override
  Future<PieceFacturation?> parNumero(String numero) => _dao.parNumero(numero);

  @override
  Future<PieceFacturation?> facturePourReservation(String reservationId) =>
      _dao.facturePourReservation(reservationId);

  @override
  Future<PieceFacturation?> facturePourPanier(String panierId) =>
      _dao.facturePourPanier(panierId);

  @override
  Future<PieceFacturation> emettre(BrouillonFacture brouillon) =>
      _dao.emettre(brouillon);

  @override
  Future<AnnulationParAvoir> annuler(
    String pieceId,
    String motif, {
    String? auteurId,
  }) => _dao.annuler(pieceId, motif, auteurId: auteurId);
}
