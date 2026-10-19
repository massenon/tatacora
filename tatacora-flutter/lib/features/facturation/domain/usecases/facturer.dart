import '../../../hebergement/domain/entities/reservation.dart';
import '../../../pos/domain/entities/panier.dart';
import '../../../pos/domain/place_hebergement.dart';
import '../entities/piece_facturation.dart';
import '../repositories/facture_repository.dart';

/// Cas d'usage de la facturation — ce que le comptoir appelle.
///
/// ## Une facture consomme un panier ; elle ne le recopie pas vivant
///
/// Les lignes du panier sont **copiées** dans la pièce à l'émission. Le panier
/// reste ce qu'il est, la facture ne le relit plus jamais. C'est ce qui fait
/// qu'une facture rouverte dans trois mois affiche encore le montant remis au
/// client, même si le panier avait été corrigé entre-temps par une reprise de
/// données.
///
/// ## Dépendance assumée à deux autres domaines
///
/// Ce cas d'usage lit `Panier` (M5, via D2) et `Reservation` (M1). C'est la
/// relation documentée de M2 : *« lignes issues de tous les modules »* (RG-04).
/// Elle est **descendante et en lecture seule** — ni le panier ni la
/// réservation ne connaissent la facturation.
final class Facturer {
  const Facturer(this._depot);

  final FactureRepository _depot;

  /* ================================================================== */
  /* Origine 1 — POS au comptant                                         */
  /* ================================================================== */

  /// Émet le ticket d'une vente au comptant, à partir du panier **clôturé**.
  ///
  /// Le panier doit être clôturé : facturer un panier encore ouvert
  /// produirait une pièce que la ligne suivante rendrait fausse, sans que rien
  /// ne la corrige — une facture est immuable, le panier ne l'est plus.
  Future<PieceFacturation> emettreAuComptant(Panier panier) async {
    if (panier.typeVente != TypeVente.comptant) {
      throw PanierIncompatible(
        'Ce panier est un panier de séjour : il se facture au départ, '
        'hébergement compris.',
      );
    }
    _exigerPanierCloture(panier);
    await _exigerPanierNonFacture(panier);

    return _depot.emettre(
      BrouillonFacture(
        origine: OrigineFacture.posComptant,
        clientNom: panier.clientNom ?? 'Client de passage',
        panierId: panier.id,
        modePaiement: panier.modePaiement,
        pointVente: panier.pointVente,
        lignes: _lignesDuPanier(panier),
      ),
    );
  }

  /* ================================================================== */
  /* Origine 2 — facture de départ d'un séjour                           */
  /* ================================================================== */

  /// Émet la facture de départ d'un séjour : **hébergement et consommations**.
  ///
  /// ## ⚠ Q3 traverse ce cas d'usage, et il ne la tranche pas
  ///
  /// La composition passe par [CompositionFactureSejour.composer], **seul
  /// endroit du client où Q3 est lue**. Sous la position retenue
  /// ([PlaceHebergement.horsPanier]), la nuitée vient de la réservation et les
  /// consommations du panier — deux montants nommés séparément, jamais un total
  /// opaque. Sous l'autre branche, `composer` **refuse**, et ce refus remonte
  /// jusqu'ici : personne ne peut émettre une facture de séjour sur une
  /// hypothèse que l'arbitrage n'a pas rendue.
  ///
  /// Un total fondu paraîtrait juste dans les deux cas, et serait faux dans
  /// l'un des deux — amputé d'une nuit ou comptant la nuitée deux fois. C'est
  /// exactement le genre d'erreur qu'aucun test ne peut distinguer après coup.
  ///
  /// La nuitée est portée **comme une ligne de la facture**, avec son tarif
  /// figé et son nombre de nuits. Ce n'est pas une contradiction avec Q3 : Q3
  /// demande si l'hébergement est une ligne de **panier**. Une facture de
  /// départ porte la chambre, sans quoi elle ne serait pas une facture.
  Future<PieceFacturation> emettrePourSejour({
    required Panier panier,
    required Reservation reservation,
    PlaceHebergement place = placeHebergementRetenue,
  }) async {
    if (panier.typeVente != TypeVente.surSejour) {
      throw PanierIncompatible(
        'Ce panier est une vente au comptant : il n’a pas de séjour à '
        'facturer.',
      );
    }
    if (panier.reservationId != reservation.id) {
      // Sans ce contrôle, une erreur de sélection à l'écran porterait les
      // consommations d'un client sur la facture d'un autre — et les deux
      // documents paraîtraient normaux.
      throw PanierIncompatible(
        'Ce panier n’appartient pas à la réservation ${reservation.reference}.',
      );
    }
    _exigerPanierCloture(panier);
    await _exigerPanierNonFacture(panier);

    if (reservation.nuits <= 0) {
      // Une nuitée à zéro nuit donnerait une ligne d'hébergement à 0 F sur une
      // facture remise au client. Refuser nomme le problème ; l'imprimer le
      // dissimule.
      throw SejourSansNuit(reservation.reference);
    }

    // Le refus de l'autre branche remonte d'ici — délibérément non rattrapé.
    final composition = CompositionFactureSejour.composer(
      montantHebergement: reservation.montantTotal,
      totalPanier: panier.total,
      place: place,
    );

    final lignes = <LigneBrouillon>[
      LigneBrouillon(
        module: ModuleFacturable.m1Hebergement,
        libelle:
            'Hébergement — ${reservation.nuits} nuit(s) '
            '(${reservation.reference})',
        // Tarif FIGÉ à la réservation (PA-55). Il ne vient pas de la grille du
        // jour : un changement de grille ne doit pas réécrire le montant d'un
        // séjour déjà pris.
        prixUnitaire: reservation.tarifNuit,
        quantite: reservation.nuits,
      ),
      ..._lignesDuPanier(panier),
    ];

    final total = lignes.fold(0, (t, l) => t + l.montant);
    if (total != composition.total) {
      // Garde-fou d'assemblage : si la somme des lignes s'écarte de la
      // composition, c'est le report qui est faux, et il vaut mieux ne rien
      // émettre qu'émettre un document dont le total ne se justifie pas.
      throw CompositionIncoherente(attendu: composition.total, obtenu: total);
    }

    return _depot.emettre(
      BrouillonFacture(
        origine: OrigineFacture.posSejour,
        clientNom: reservation.clientNom,
        clientId: reservation.clientId,
        reservationId: reservation.id,
        panierId: panier.id,
        modePaiement: panier.modePaiement,
        pointVente: panier.pointVente,
        lignes: lignes,
      ),
    );
  }

  /* ================================================================== */
  /* Origine 3 — facture directe                                         */
  /* ================================================================== */

  /// Émet une facture saisie à la main, sans panier ni séjour.
  Future<PieceFacturation> emettreDirecte({
    required String clientNom,
    required List<LigneBrouillon> lignes,
    String? clientId,
    String? modePaiement,
    String? pointVente,
  }) => _depot.emettre(
    BrouillonFacture(
      origine: OrigineFacture.factureDirecte,
      clientNom: clientNom,
      clientId: clientId,
      modePaiement: modePaiement,
      pointVente: pointVente,
      lignes: lignes,
    ),
  );

  /* ================================================================== */
  /* Annulation                                                          */
  /* ================================================================== */

  /// Annule une facture **par avoir**. Rien n'est effacé.
  ///
  /// [auteurId] : le compte qui annule — une facture d'un AUTRE poste ne
  /// s'annule que par l'administration ou le comptable (Q3, lot F6).
  Future<AnnulationParAvoir> annuler(
    String pieceId,
    String motif, {
    String? auteurId,
  }) => _depot.annuler(pieceId, motif, auteurId: auteurId);

  /// La facture émise d'une réservation, **avoirs exclus**.
  ///
  /// C'est ce que l'écran doit appeler avant de proposer un téléchargement :
  /// proposer un document qui ne pointe vers rien est pire qu'un bouton absent,
  /// et proposer l'avoir à la place de la facture met un montant négatif entre
  /// les mains du client.
  Future<PieceFacturation?> facturePourReservation(String reservationId) =>
      _depot.facturePourReservation(reservationId);

  /* ================================================================== */
  /* Internes                                                            */
  /* ================================================================== */

  /// Garde d'**idempotence**, et elle protège un geste très ordinaire.
  ///
  /// Au comptoir, un bouton qui ne réagit pas tout de suite se presse deux
  /// fois. Sans cette garde, le second appui émettrait une seconde pièce
  /// numérotée pour la même vente : le registre porterait un montant que
  /// personne n'a encaissé, et seul un avoir pourrait ensuite le défaire.
  ///
  /// Elle rend aussi réparable le seul état bancal du parcours — un panier
  /// clôturé dont l'émission a échoué : on peut réémettre sans risquer le
  /// doublon.
  Future<void> _exigerPanierNonFacture(Panier panier) async {
    final existante = await _depot.facturePourPanier(panier.id);
    if (existante != null) throw FactureDejaEmise(existante.numero);
  }

  void _exigerPanierCloture(Panier panier) {
    if (panier.statut != StatutPanier.cloture) {
      throw PanierNonFacturable(panier.statut);
    }
  }

  /// Copie les lignes du panier en lignes de facture.
  ///
  /// Le prix et le libellé viennent du **panier**, où ils sont déjà figés
  /// (règle 3 de D2), et non du catalogue. Deux copies successives d'une même
  /// valeur figée valent mieux qu'une jointure : la seconde n'introduit aucune
  /// dépendance vivante.
  List<LigneBrouillon> _lignesDuPanier(Panier panier) => [
    for (final l in panier.lignes)
      LigneBrouillon(
        module: ModuleFacturable.depuisModuleVendableCode(
          l.reference.module.code,
        ),
        libelle: l.libelle,
        prixUnitaire: l.prixUnitaire,
        quantite: l.quantite,
        codeArticle: l.reference.code,
      ),
  ];
}

/* ====================================================================== */
/* Refus propres à l'émission                                              */
/* ====================================================================== */

/// Le panier ne correspond pas à l'origine demandée.
final class PanierIncompatible implements Exception {
  const PanierIncompatible(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Un panier encore ouvert — ou annulé — ne se facture pas.
final class PanierNonFacturable implements Exception {
  const PanierNonFacturable(this.statut);
  final StatutPanier statut;

  @override
  String toString() => switch (statut) {
    StatutPanier.ouvert =>
      'Ce panier est encore ouvert : la ligne suivante rendrait la facture '
          'fausse, et une facture ne se corrige que par un avoir. Clôturez-le '
          'd’abord.',
    StatutPanier.annule => 'Ce panier a été annulé : il n’y a rien à facturer.',
    StatutPanier.cloture => 'Ce panier est facturable.',
  };
}

/// Ce panier a déjà sa facture.
final class FactureDejaEmise implements Exception {
  const FactureDejaEmise(this.numero);
  final String numero;

  @override
  String toString() =>
      'La facture $numero a déjà été émise pour ce panier. Une seconde pièce '
      'porterait au registre un montant que personne n’a encaissé.';
}

/// Un séjour de zéro nuit ne se facture pas.
final class SejourSansNuit implements Exception {
  const SejourSansNuit(this.reference);
  final String reference;

  @override
  String toString() =>
      'Le séjour $reference ne compte aucune nuit : la ligne d’hébergement '
      'sortirait à 0 FCFA sur un document remis au client.';
}

/// La somme des lignes s'écarte de la composition attendue.
final class CompositionIncoherente implements Exception {
  const CompositionIncoherente({required this.attendu, required this.obtenu});
  final int attendu;
  final int obtenu;

  @override
  String toString() =>
      'Composition incohérente : la somme des lignes vaut $obtenu FCFA pour un '
      'total attendu de $attendu FCFA. Aucune pièce n’a été émise.';
}

/* ====================================================================== */
/* Indicateurs                                                             */
/* ====================================================================== */

/// Les indicateurs de l'écran Facturation.
///
/// **Chaque champ se dérive du registre réellement lu**, jamais d'un compteur
/// tenu à part : un compteur incrémenté à l'émission et oublié à l'annulation
/// afficherait un chiffre d'affaires que rien ne justifie — l'indicateur qui
/// affirme un état qu'il n'a pas vérifié (PA-59/60/61).
final class KpisFacturation {
  const KpisFacturation({
    required this.pieces,
    required this.factures,
    required this.annulees,
    required this.avoirs,
    required this.montantNet,
    required this.certifiees,
  });

  /// Toutes les pièces du registre, avoirs compris.
  final int pieces;

  /// Les factures émises, **hors avoirs**.
  final int factures;

  final int annulees;
  final int avoirs;

  /// Somme de **toutes** les pièces du registre, annulées et avoirs compris.
  ///
  /// ## Divergence avec le prototype, et c'est lui qui a tort
  ///
  /// `facture-engine.js` calcule ce chiffre en filtrant sur `statut === EMISE`.
  /// Or annuler retire la facture du total **et** y ajoute l'avoir : le montant
  /// est donc **déduit deux fois**. Sur le jeu de `t-facture.js` — 6 500 F
  /// encaissés, 10 000 F annulés — le prototype rend **-3 500 F** là où le
  /// registre vaut 6 500 F. Aucune assertion du prototype ne couvre ce champ,
  /// ce qui explique qu'il ait tenu.
  ///
  /// La somme correcte est celle de **toutes** les pièces, et c'est
  /// exactement ce que signifie « corriger par contre-passation » : l'avoir
  /// neutralise l'original **arithmétiquement**. Le statut `annulee` est une
  /// étiquette, pas une exclusion du total — l'exclure reviendrait à corriger
  /// deux fois la même erreur.
  ///
  /// Écart consigné en PA-99 ; le prototype n'a pas été modifié par ce lot.
  final int montantNet;

  /// **Toujours 0**, et l'écran le dit. MECeF est factice ; un compteur de
  /// pièces certifiées qui monterait affirmerait une certification fiscale qui
  /// n'a pas eu lieu (PA-61).
  final int certifiees;

  static Future<KpisFacturation> calculer(FactureRepository depot) async {
    final toutes = await depot.pieces();
    final emises = toutes.where((p) => p.estEmise).toList(growable: false);

    return KpisFacturation(
      pieces: toutes.length,
      factures: emises.where((p) => !p.estAvoir).length,
      annulees: toutes.where((p) => p.estAnnulee).length,
      avoirs: toutes.where((p) => p.estAvoir).length,
      // Sur TOUTES les pièces : facture annulée (+) et son avoir (-)
      // s'annulent, ce qui est le propre d'une contre-passation.
      montantNet: toutes.fold(0, (t, p) => t + p.montantTotal),
      certifiees: toutes.where((p) => p.estCertifiee).length,
    );
  }
}
