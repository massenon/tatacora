/// Les refus d'une vente encaissée — ceux de `lang/fr/ventes.php` et de
/// `lang/fr/pos_pwa.php` (`comptant.refus_*`), RELUS par PHP dans
/// `test/features/pos/ventes_contre_serveur_test.dart` : une phrase recopiée
/// sans cette épreuve ne vérifierait qu'elle-même.
///
/// Les « écarts du poste » en fin de fichier sont les SEULS textes qui n'ont pas
/// d'équivalent au serveur ; chacun dit lequel de ses comportements il remplace.
library;

/// Un refus de la vente : rien n'a été écrit (ni la clôture, ni la pièce).
final class RefusVente implements Exception {
  const RefusVente(this.message);

  final String message;

  @override
  String toString() => 'RefusVente: $message';
}

abstract final class MessagesVentes {
  /// `ventes.module_non_encaissable` — [module] est le libellé du serveur
  /// (`VenteService::MODULES`), « Véhicules » pour M8 et non « Location ».
  static String moduleNonEncaissable(String module) =>
      // Fin de phrase « …anti-patron que le prototype porte et que ce dépôt
      // refuse » retirée de l'écran le 14/10/2026 (directive du PO).
      '$module ne dispose pas encore de catalogue encaissable au comptoir.';

  /// `ventes.reference_inconnue`.
  static String referenceInconnue(String reference) =>
      'L\'article $reference est introuvable au catalogue. '
      'Le prix et le libellé d\'une vente sont figés depuis le catalogue, '
      'jamais saisis : sans référence, il n\'y a rien à figer.';

  /// `ventes.mode_paiement_inconnu`.
  static String modeInconnu(String mode) => 'Mode de paiement inconnu : $mode.';

  /// ⚠ ÉCART DU POSTE — aucun équivalent au serveur. Appelé sans mode, le
  /// serveur retombe sur les espèces ; le poste refuse, parce que son journal
  /// des ventes distingue « non renseigné » d'« espèces » exprès : ranger au
  /// hasard une vente en espèces ferait entrer en caisse un argent que
  /// personne n'a compté. L'écran envoie toujours un mode.
  static const String modeReglementAbsent =
      'Aucun mode de règlement n\'a été choisi : la vente n\'est pas '
      'enregistrée. Choisissez comment le client règle — une vente rangée en '
      'espèces par défaut ferait entrer en caisse un argent que personne n\'a '
      'compté.';

  /// `ventes.compte_produit_absent`.
  static String compteProduitAbsent(String module) =>
      'Aucun compte de produits n\'est déclaré pour $module. '
      'La vente est refusée : créditer un compte choisi au plus proche '
      'imputerait le chiffre d\'affaires au mauvais poste, sur une pièce '
      'immuable.';

  /// `pos_pwa.comptant.refus_note_chambre_comptoir`.
  static const String noteChambreAuComptoir =
      '« Porté sur la note de chambre » n\'existe pas au comptoir : aucune '
      'chambre n\'y porte de note. Utilisez le point de vente des clients '
      'hébergés.';

  /// `ventes.deja_annulee`.
  static String dejaAnnulee(String numero) =>
      'La vente $numero est déjà annulée.';

  /// `pos_pwa.comptant.refus_motif_obligatoire` (le même mot que
  /// `pos_pwa.journal.refus_motif_obligatoire`).
  static const String motifAnnulationObligatoire =
      "Le motif de l'annulation est obligatoire : une vente annulée reste au journal, et le journal doit dire pourquoi.";

  /// `pos_pwa.journal.refus_vente_absente`.
  static const String venteAbsente = "Cette vente n'existe plus au registre.";

  /// `ventes.libelle_contrepassation` — le libellé de la pièce inverse.
  static String libelleContrepassation(String numero) =>
      'Annulation vente $numero';

  /// `pos_pwa.journal.vente_annulee`. (Le comptoir du serveur ajoute « Les
  /// sorties de stock sont compensées » : ce poste n'écrit aucune sortie, le
  /// serveur compense à la réception de l'annulation — la phrase serait fausse
  /// ici.)
  static String venteAnnulee(String numero) =>
      'Vente $numero annulée. Elle reste au journal.';

  /// `ventes.libelle_ecriture` — seul le gabarit est celui du serveur ; voir
  /// [libelleDeLaPiece] pour ce que le poste y met.
  static String libelleDeLaPiece(String reference) => 'Vente $reference';

  /// Les libellés de module du serveur (`VenteService::MODULES`) : c'est CE
  /// registre que les phrases de refus nomment, pas celui du catalogue du poste
  /// (`ModuleVendable.libelle`, qui dit « Location » là où le serveur dit
  /// « Véhicules »).
  static const Map<String, String> modulesDuServeur = {
    'M1': 'Hébergement',
    'M4': 'Restaurant',
    'M5': 'Bar',
    'M8': 'Véhicules',
    'M9': 'Tourisme',
  };
}
