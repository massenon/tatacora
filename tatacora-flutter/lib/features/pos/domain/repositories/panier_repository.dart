import '../entities/article_vendable.dart';
import '../entities/panier.dart';

/// Contrat d'accès aux paniers.
///
/// ⚠ **Portage d'une proposition non ratifiée** (Q1/Q2/Q3) — voir
/// `entities/panier.dart`.
///
/// ## Toutes les lectures viennent du local
///
/// Comme pour M1 : aucune méthode de ce contrat n'atteint le réseau. Le panier
/// est aujourd'hui **strictement local** — `paniers` n'est pas au registre
/// `TABLES_SYNCHRONISABLES` du serveur — et le dire dans le contrat évite
/// qu'un écran suppose une synchronisation qui n'existe pas.
abstract interface class PanierRepository {
  /// Les paniers, filtrables par statut et par type de vente.
  Future<List<Panier>> paniers({StatutPanier? statut, TypeVente? typeVente});

  Future<Panier?> parId(String id);

  /// Le panier **ouvert** d'un séjour, s'il existe.
  ///
  /// ⚠ Q2 — c'est cette lecture qui fait la garde de [ouvrir]. Voir
  /// `unicite_panier_ouvert.dart`.
  Future<Panier?> panierOuvertPour(String reservationId);

  /// Ouvre un panier. Lève [PanierDejaOuvertException] si le séjour en a déjà
  /// un d'ouvert.
  /// [tableId] et [espace] sont nuls au COMPTOIR — une vente de passage n'a
  /// aucune table, et lui en inventer une creerait une table a ouvrir et
  /// fermer qui ne correspond a rien dans la salle.
  Future<Panier> ouvrir({
    required TypeVente typeVente,
    String? reservationId,
    String? clientNom,
    String? pointVente,
    DateTime? dateDepartPrevue,
    String? tableId,
    String? espace,
  });

  /// Ajoute une consommation, en **copiant** son prix et son libellé.
  Future<Panier> ajouterLigne(
    String panierId,
    ArticleVendable article, {
    int? quantite,
  });

  Future<Panier> retirerLigne(String panierId, String ligneId);

  /// Retire toutes les lignes **sans fermer** le panier — « Vider » du
  /// maitre (`pos.html`). A distinguer d'[annuler], qui ferme le panier
  /// et libere la table.
  Future<Panier> vider(String panierId);

  Future<Panier> modifierQuantite(
    String panierId,
    String ligneId,
    int quantite,
  );

  /// Clôture le panier, fige son montant et passe la pièce comptable de la
  /// vente dans la MÊME transaction (règle du PO du 31/08/2026).
  ///
  /// [auteurId] nomme celui qui encaisse (RG-15) : une pièce sans auteur est
  /// refusée. Lève `RefusVente`, `RefusTva` ou `RefusComptable` quand le serveur
  /// aurait refusé, et n'écrit alors RIEN.
  Future<Panier> cloturer(
    String panierId, {
    bool anticipe = false,
    String? modePaiement,
    required String auteurId,
  });

  Future<Panier> annuler(String panierId, String motif);
}

/// Le catalogue vendable, tel que le poste le connaît **hors ligne**.
abstract interface class CatalogueRepository {
  /// Les rayons, dans l'ordre d'affichage.
  ///
  /// Un rayon dont le catalogue n'est pas répliqué localement est rendu
  /// **vide avec sa raison**, jamais omis.
  Future<List<RayonCatalogue>> rayons();

  /// Le lien de stock des boissons répliquées — id → article (PA-199).
  ///
  /// Une LECTURE, comme [rayons] : le contrat reste en lecture seule.
  Future<Map<String, String>> liensDeStockDesBoissons();
}

/// Le panier demandé n'existe pas.
final class PanierIntrouvable implements Exception {
  const PanierIntrouvable(this.id);
  final String id;

  @override
  String toString() => 'Panier introuvable ($id).';
}

/// Le panier n'est plus modifiable — règle 2.
///
/// Le message nomme le **statut réel** : « ce panier est clôturé » se corrige,
/// « opération impossible » s'endure.
final class PanierNonModifiable implements Exception {
  const PanierNonModifiable(this.statut);
  final StatutPanier statut;

  @override
  String toString() =>
      'Ce panier est ${statut.code} : il ne peut plus être modifié.';
}

/// La ligne demandée n'appartient pas à ce panier.
final class LigneIntrouvable implements Exception {
  const LigneIntrouvable(this.ligneId);
  final String ligneId;

  @override
  String toString() => 'Ligne introuvable dans ce panier ($ligneId).';
}

/// L'article n'a pas de tarif — refus, jamais un zéro silencieux.
final class PrixInconnu implements Exception {
  const PrixInconnu(this.libelle);
  final String libelle;

  @override
  String toString() =>
      'Prix inconnu pour « $libelle ». Renseignez le tarif avant de l’ajouter.';
}

/// La clôture serait anticipée et n'a pas été confirmée — règle 5.
///
/// **Ce n'est pas une erreur, c'est une question.** L'écran la pose ; il ne
/// laisse pas l'utilisateur devant un message qu'il ne peut pas lever.
final class ClotureAnticipeeNonConfirmee implements Exception {
  const ClotureAnticipeeNonConfirmee(this.dateDepartPrevue);
  final DateTime dateDepartPrevue;

  String get dateLisible =>
      '${dateDepartPrevue.day.toString().padLeft(2, '0')}/'
      '${dateDepartPrevue.month.toString().padLeft(2, '0')}/'
      '${dateDepartPrevue.year}';

  @override
  String toString() =>
      'Le départ est prévu le $dateLisible. Clôturer maintenant empêche '
      'd’ajouter toute consommation d’ici là, puisqu’un second panier ne peut '
      'pas être ouvert.';
}

/// Un panier vide n'a rien à facturer.
final class PanierVide implements Exception {
  /// La phrase historique du poste : « rien à facturer ».
  const PanierVide()
    : message = 'Le panier est vide : il n’y a rien à facturer.';

  /// Au comptoir, `PosComptant` dit « rien à ENCAISSER »
  /// (`pos_pwa.comptant.refus_panier_vide`) — la phrase du serveur, mot pour mot,
  /// avec l'apostrophe droite de son fichier de langue.
  const PanierVide.auComptoir()
    : message = 'Le panier est vide : il n\'y a rien à encaisser.';

  /// Pour un séjour, `PosHeberges` dit « Le panier du séjour est vide »
  /// (`pos_pwa.heberges.refus_panier_vide`).
  const PanierVide.duSejour()
    : message = 'Le panier du séjour est vide : il n\'y a rien à facturer.';

  final String message;

  @override
  String toString() => message;
}

/// Le code d'article ne désigne rien dans le catalogue local.
///
/// ⚠ Q1 — c'est la vérification qui remplace, sur ce client, la clé étrangère
/// de l'option A. Voir `entities/reference_catalogue.dart`.
final class ArticleHorsCatalogue implements Exception {
  const ArticleHorsCatalogue(this.reference);
  final String reference;

  @override
  String toString() =>
      'L’article $reference ne figure pas au catalogue local : la ligne '
      'désignerait un article qui n’existe pas.';
}
