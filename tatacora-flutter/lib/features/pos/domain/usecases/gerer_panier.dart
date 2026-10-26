import '../../../hebergement/domain/entities/fiche_reservation.dart'
    show TypeRemise;
import '../entities/article_vendable.dart';
import '../entities/panier.dart';
import '../repositories/panier_repository.dart';
import 'quantite_saisie.dart';

/// Cas d'usage du panier — ce que les deux écrans de point de vente appellent.
///
/// ⚠ **Portage d'une PROPOSITION non ratifiée**
/// (`docs/PROPOSITION_MODELE_PANIER_POS.md`, Q1/Q2/Q3).
///
/// ## Pourquoi une seule classe pour les deux POS
///
/// Parce qu'il n'y a qu'un seul panier. La différence entre les deux points de
/// vente tient dans deux attributs — `typeVente` et `reservationId` — et rien
/// d'autre. Deux jeux de cas d'usage dupliqueraient la logique de rattachement
/// des consommations, et c'est cette duplication qui produit ensuite les
/// divergences de comportement entre le bar et la réception.
final class GererPanier {
  const GererPanier(this._depot);

  final PanierRepository _depot;

  /// Ouvre un panier au comptant.
  ///
  /// [pointVente] dit **où se trouve l'argent** — la caisse ouverte —, jamais
  /// ce qui est vendu. Confondre les deux avait rendu impossible une addition
  /// mêlant bar et restaurant (PA-79).
  /// Ouvre un panier au comptant, sur une table **ou au comptoir**.
  ///
  /// [tableId] nul signifie le comptoir : une vente de passage n'a aucune
  /// table, et lui en inventer une creerait une table a ouvrir et fermer qui
  /// ne correspond a rien dans la salle.
  Future<Panier> ouvrirAuComptant({
    String? pointVente,
    String? clientNom,
    String? tableId,
    String? espace,
  }) => _depot.ouvrir(
    typeVente: TypeVente.comptant,
    pointVente: pointVente,
    clientNom: clientNom,
    tableId: tableId,
    espace: espace,
  );

  /// Ouvre le panier d'un séjour.
  ///
  /// ⚠ **Q2** — lève `PanierDejaOuvertException` si le séjour en a déjà un
  /// d'ouvert. La garantie est portée par le dépôt, dans une transaction ; voir
  /// `unicite_panier_ouvert.dart`.
  Future<Panier> ouvrirPourSejour({
    required String reservationId,
    required DateTime dateDepartPrevue,
    String? clientNom,
    String? pointVente,
  }) => _depot.ouvrir(
    typeVente: TypeVente.surSejour,
    reservationId: reservationId,
    clientNom: clientNom,
    pointVente: pointVente,
    dateDepartPrevue: dateDepartPrevue,
  );

  /// Ajoute une consommation depuis une **saisie** de quantité.
  ///
  /// C'est le seul chemin que l'écran doit emprunter quand la quantité vient
  /// d'un champ : il distingue « absente » de « zéro » (voir
  /// [QuantiteSaisie]). Passer par `ajouter` avec un `int` déjà décidé
  /// contournerait cette distinction.
  Future<Panier> ajouterDepuisSaisie(
    String panierId,
    ArticleVendable article, {
    String? quantiteSaisie,
  }) {
    final lue = QuantiteSaisie.depuisTexte(quantiteSaisie);
    return switch (lue) {
      QuantiteAbsente() => _depot.ajouterLigne(panierId, article),
      QuantiteValide(valeur: final v) => _depot.ajouterLigne(
        panierId,
        article,
        quantite: v,
      ),
      QuantiteRefusee(motif: final m) => Future.error(
        ArgumentError.value(quantiteSaisie, 'quantite', m),
      ),
    };
  }

  /// Ajoute une consommation, quantité déjà décidée.
  ///
  /// [quantite] à `null` signifie « non précisée » et vaut 1.
  Future<Panier> ajouter(
    String panierId,
    ArticleVendable article, {
    int? quantite,
  }) => _depot.ajouterLigne(panierId, article, quantite: quantite);

  Future<Panier> retirer(String panierId, String ligneId) =>
      _depot.retirerLigne(panierId, ligneId);

  Future<Panier> changerQuantite(
    String panierId,
    String ligneId,
    int quantite,
  ) => _depot.modifierQuantite(panierId, ligneId, quantite);

  /// Pose la remise du panier (type + valeur saisie) — voir
  /// [PanierRepository.appliquerRemise].
  Future<Panier> appliquerRemise(
    String panierId,
    TypeRemise type,
    String valeurSaisie,
  ) => _depot.appliquerRemise(panierId, type, valeurSaisie);

  /// Diminue d'une unité, ou retire la ligne si elle tombe à zéro.
  ///
  /// Le geste du comptoir est « moins » ; à une unité, il vaut « retirer ».
  /// Sans ce cas, le bouton laisserait une ligne à zéro sur l'addition — un
  /// article annoncé au client et facturé à rien.
  Future<Panier> diminuer(String panierId, LignePanier ligne) =>
      ligne.quantite <= 1
      ? _depot.retirerLigne(panierId, ligne.id)
      : _depot.modifierQuantite(panierId, ligne.id, ligne.quantite - 1);

  /// Clôture le panier.
  ///
  /// Règle 5 : sans [anticipe], une clôture antérieure au jour du départ est
  /// **refusée** par `ClotureAnticipeeNonConfirmee`. Ce refus n'est pas une
  /// erreur, c'est une question — l'écran la pose et rappelle avec
  /// [anticipe] à `true` si l'utilisateur confirme.
  ///
  /// [auteurId] est celui qui encaisse : la vente passe sa pièce comptable dans
  /// la même transaction, et une pièce sans auteur est refusée (RG-15).
  Future<Panier> cloturer(
    String panierId, {
    bool anticipe = false,
    String? modePaiement,
    required String auteurId,
  }) => _depot.cloturer(
    panierId,
    anticipe: anticipe,
    modePaiement: modePaiement,
    auteurId: auteurId,
  );

  Future<Panier> annuler(String panierId, String motif) =>
      _depot.annuler(panierId, motif);

  /// Annule une vente ENCAISSÉE — le geste du journal du jour et du détail
  /// d'une vente (`VenteService::annuler`). Voir `PanierRepository.annulerVente`.
  Future<Panier> annulerVente(
    String panierId,
    String motif, {
    required String auteurId,
  }) => _depot.annulerVente(panierId, motif, auteurId: auteurId);
}

/// Les indicateurs de l'en-tête du point de vente.
///
/// **Chaque champ se dérive de ce qui est réellement en base**, jamais d'un
/// compteur tenu à part : un compteur incrémenté à l'ouverture et oublié à la
/// clôture afficherait « 3 paniers ouverts » sur une base qui n'en a plus un
/// seul — l'indicateur qui affirme un état qu'il n'a pas vérifié
/// (PA-59/60/61).
final class KpisPanier {
  const KpisPanier({
    required this.ouverts,
    required this.paniersSejour,
    required this.encours,
    required this.encoursSejours,
    required this.clotures,
  });

  final int ouverts;
  final int paniersSejour;

  /// En-cours de tous les paniers ouverts, en francs CFA.
  final int encours;

  /// En-cours des seuls paniers de séjour — isolé du comptant, parce que ce
  /// n'est pas le même argent : l'un est dans le tiroir, l'autre est une
  /// créance qui se règle au départ.
  final int encoursSejours;

  final int clotures;

  static Future<KpisPanier> calculer(PanierRepository depot) async {
    final tous = await depot.paniers();
    final ouverts = tous.where((p) => p.estOuvert).toList();
    final sejours = ouverts
        .where((p) => p.typeVente == TypeVente.surSejour)
        .toList();

    return KpisPanier(
      ouverts: ouverts.length,
      paniersSejour: sejours.length,
      encours: ouverts.fold(0, (t, p) => t + p.total),
      encoursSejours: sejours.fold(0, (t, p) => t + p.total),
      clotures: tous.where((p) => p.statut == StatutPanier.cloture).length,
    );
  }
}
