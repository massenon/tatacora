/// ⚠ **POINT Q3 — l'hébergement est-il une ligne de panier ?**
///
/// Ce fichier est le **seul endroit** du client Flutter où cette question
/// atterrit. Si l'Architecte et le Product Owner tranchent dans l'autre sens,
/// c'est ici qu'on rouvre — plus l'ajout de `M1` au registre fermé
/// `ModuleVendable`. Rien d'autre : les écrans, le dépôt et la base
/// n'expriment aucune opinion sur la question.
///
/// ## Les deux lectures, telles que le document les pose
///
/// `docs/PROPOSITION_MODELE_PANIER_POS.md` §5 :
///
///  - **L'hébergement reste sur la réservation** — le panier ne porte que les
///    consommations, et la facture de départ additionne les deux. C'est la
///    position du document : la nuitée est déjà engagée à la réservation, avec
///    son tarif figé (PA-55/PA-73), et cela évite qu'un même montant existe à
///    deux endroits.
///  - **L'hébergement devient une ligne de panier** — plus simple à afficher,
///    mais duplique un montant déjà porté par la réservation, et deux sources
///    pour un même montant finissent toujours par diverger.
///
/// Le document ajoute que la réponse « change l'écran de clôture, pas le
/// modèle » et peut donc être tranchée **après** le début du lot. C'est ce qui
/// rend ce point isolable — et c'est aussi ce qui oblige à l'isoler pour de
/// bon, plutôt qu'à supposer la réponse en trente endroits.
///
/// ## Ce qui est porté, et comment il se voit
///
/// [PlaceHebergement.horsPanier], la position du document. Elle se lit à un
/// seul endroit du code, et elle est **structurelle** : `ModuleVendable` — le
/// registre fermé des catalogues vendables — ne contient **pas** M1. Une ligne
/// d'hébergement n'est donc pas seulement absente, elle est inexprimable.
///
/// L'autre branche n'est **pas implémentée à moitié**. Elle refuse
/// explicitement, en nommant Q3. Un calcul plausible écrit « en attendant »
/// serait pris pour une décision, et personne ne le rouvrirait — c'est
/// exactement ce que le dépôt refuse depuis PA-19 et PA-53.
library;

/// Où vit le montant de l'hébergement, dans la chaîne séjour → facture.
enum PlaceHebergement {
  /// Sur la réservation. Le panier ne porte que les consommations.
  horsPanier,

  /// Au panier, comme une ligne parmi les autres. **Non implémenté** : Q3
  /// n'est pas tranchée.
  ligneDePanier,
}

/// La position portée par ce client, en attendant l'arbitrage Q3.
const PlaceHebergement placeHebergementRetenue = PlaceHebergement.horsPanier;

/// Ce qui compose la facture de départ d'un séjour.
///
/// Deux montants **nommés séparément**, jamais un total opaque : c'est la seule
/// forme qui reste juste quelle que soit la réponse à Q3, et c'est aussi ce
/// que le comptoir doit pouvoir annoncer — « votre chambre, vos consommations »
/// est une phrase qu'on prononce, « 87 400 F » n'en est pas une.
final class CompositionFactureSejour {
  const CompositionFactureSejour({
    required this.hebergement,
    required this.consommations,
  });

  /// Montant de la nuitée, tel que la **réservation** le porte (tarif figé ×
  /// nombre de nuits). Il ne vient jamais du panier.
  final int hebergement;

  /// Total des lignes du panier.
  final int consommations;

  int get total => hebergement + consommations;

  /// Compose la facture de départ selon la place retenue pour l'hébergement.
  ///
  /// [place] n'est un paramètre que pour rendre l'autre branche **atteignable
  /// par un test** : sans cela, le refus serait écrit et jamais éprouvé, ce qui
  /// est précisément le défaut que la campagne PA-59 → PA-67 a démonté.
  factory CompositionFactureSejour.composer({
    required int montantHebergement,
    required int totalPanier,
    PlaceHebergement place = placeHebergementRetenue,
  }) {
    switch (place) {
      case PlaceHebergement.horsPanier:
        return CompositionFactureSejour(
          hebergement: montantHebergement,
          consommations: totalPanier,
        );

      case PlaceHebergement.ligneDePanier:
        // Le refus EST le livrable, comme pour le taux d'IS (PA-19) et le
        // taux CNSS de risques professionnels (PA-53).
        //
        // Écrire ici `consommations: totalPanier` en supposant que la nuitée
        // s'y trouve déjà donnerait un total juste **si** quelqu'un avait
        // pensé à l'y mettre, et un total amputé d'une nuit sinon — sans
        // qu'aucun test ne puisse distinguer les deux cas.
        throw UnimplementedError(
          'Q3 non tranchée : l\'hébergement comme ligne de panier suppose que '
          'la nuitée soit portée au panier ET retirée de la réservation. '
          'Tant que l\'arbitrage n\'est pas rendu, composer une facture sur '
          'cette hypothèse produirait un montant faux ou compté deux fois. '
          'Voir docs/PROPOSITION_MODELE_PANIER_POS.md §5, Q3.',
        );
    }
  }
}
