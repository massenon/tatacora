/// Le règlement d'une commande fournisseur (M7, D66) — réplique de
/// `ReglementFournisseur` du serveur.
library;

import '../../../depenses/domain/categories_depense.dart';

/// `reglements_fournisseur.statut` — registre fermé de deux valeurs.
enum StatutReglement {
  actif('actif'),
  annule('annule');

  const StatutReglement(this.code);

  final String code;

  /// `null` sur un code inconnu — jamais un repli sur `actif`, qui déduirait
  /// d'une dette un règlement que personne n'a compris. La base borne les deux
  /// valeurs par un `CHECK` ; un autre code ne peut venir de ce poste.
  static StatutReglement? depuisCode(String code) {
    for (final s in values) {
      if (s.code == code) return s;
    }
    return null;
  }
}

final class ReglementFournisseur {
  const ReglementFournisseur({
    required this.id,
    required this.commandeId,
    required this.montantCentimes,
    required this.tresorerie,
    required this.dateReglement,
    required this.statut,
    required this.motifAnnulation,
    required this.annuleParId,
    required this.dateAnnulation,
    required this.utilisateurCreationId,
  });

  final String id;
  final String commandeId;

  /// Centimes entiers, strictement positifs.
  final int montantCentimes;
  final TresorerieDepense tresorerie;

  /// `AAAA-MM-JJ`.
  final String dateReglement;
  final StatutReglement statut;
  final String? motifAnnulation;
  final String? annuleParId;
  final DateTime? dateAnnulation;
  final String utilisateurCreationId;

  bool get estActif => statut == StatutReglement.actif;
}

/// Ce que le serveur prépare à l'ouverture de la modale « Régler »
/// (`Approvisionnement::ouvrirFormulaireReglement`) : le fournisseur nommé au
/// titre, le reste dû proposé comme montant, la trésorerie de départ.
final class OuvertureReglement {
  const OuvertureReglement({
    required this.commandeId,
    required this.fournisseurNom,
    required this.resteDuCentimes,
  });

  final String commandeId;

  /// Vide si la relation manque (`?? ''` du serveur), jamais un nom inventé.
  final String fournisseurNom;
  final int resteDuCentimes;

  /// `regTresorerie = 'caisse'` à l'ouverture.
  TresorerieDepense get tresorerieDeDepart => TresorerieDepense.caisse;
}
