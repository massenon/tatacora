import '../domain/entities/article_vendable.dart';
import '../domain/entities/panier.dart';
import '../domain/repositories/panier_repository.dart';
import 'panier_dao.dart';

/// Dépôt de paniers — **strictement local**.
///
/// ⚠ **Portage d'une PROPOSITION non ratifiée** (Q1/Q2/Q3), voir
/// `domain/entities/panier.dart`.
///
/// ## Pourquoi il n'existe pas de dépôt « composite » ici, contrairement à M1
///
/// M1 a un `ReservationRepositoryComposite` parce qu'une réservation part au
/// serveur. Un panier n'y va pas : `paniers` n'est pas au registre
/// `TABLES_SYNCHRONISABLES`. Écrire une enveloppe réseau « pour plus tard »
/// donnerait un chemin que rien n'emprunte — et un chemin jamais exécuté est
/// faux jusqu'à preuve du contraire (PA-59, PA-63).
///
/// Le jour où le modèle sera ratifié et la table inscrite au registre, c'est
/// ici que le composite s'ajoutera, sur le patron de M1.
final class PanierRepositoryLocal implements PanierRepository {
  const PanierRepositoryLocal(this._dao);

  final PanierDao _dao;

  @override
  Future<List<Panier>> paniers({StatutPanier? statut, TypeVente? typeVente}) =>
      _dao.paniers(statut: statut, typeVente: typeVente);

  @override
  Future<Panier?> parId(String id) => _dao.parId(id);

  @override
  Future<Panier?> panierOuvertPour(String reservationId) =>
      _dao.panierOuvertPour(reservationId);

  @override
  Future<Panier> ouvrir({
    required TypeVente typeVente,
    String? reservationId,
    String? clientNom,
    String? pointVente,
    DateTime? dateDepartPrevue,
    String? tableId,
    String? espace,
  }) => _dao.ouvrir(
    typeVente: typeVente,
    reservationId: reservationId,
    clientNom: clientNom,
    pointVente: pointVente,
    dateDepartPrevue: dateDepartPrevue,
    tableId: tableId,
    espace: espace,
  );

  @override
  Future<Panier> ajouterLigne(
    String panierId,
    ArticleVendable article, {
    int? quantite,
  }) => _dao.ajouterLigne(panierId, article, quantite: quantite);

  @override
  Future<Panier> retirerLigne(String panierId, String ligneId) =>
      _dao.retirerLigne(panierId, ligneId);

  @override
  Future<Panier> vider(String panierId) => _dao.vider(panierId);

  @override
  Future<Panier> annulerVente(
    String panierId,
    String motif, {
    required String auteurId,
  }) => _dao.annulerVente(panierId, motif, auteurId: auteurId);

  @override
  Future<Panier> modifierQuantite(
    String panierId,
    String ligneId,
    int quantite,
  ) => _dao.modifierQuantite(panierId, ligneId, quantite);

  @override
  Future<Panier> cloturer(
    String panierId, {
    bool anticipe = false,
    String? modePaiement,
    required String auteurId,
  }) => _dao.cloturer(
    panierId,
    anticipe: anticipe,
    modePaiement: modePaiement,
    auteurId: auteurId,
  );

  @override
  Future<Panier> annuler(String panierId, String motif) =>
      _dao.annuler(panierId, motif);
}
