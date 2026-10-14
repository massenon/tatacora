// Vue Blade maîtresse (PA-183) : pwa/hebergement/reservations.blade.php (modale d'annulation)
/// Les mots de l'annulation d'une réservation avec commission et remboursement
/// (EF-M1-06) — ceux de `lang/fr/hebergement.php`, `lang/fr/hebergement_pwa.php`
/// (`reservations.annulation_*`) et `lang/fr/validation.php`, RELUS par PHP dans
/// `test/features/hebergement/annulation_contre_serveur_test.dart` : une phrase
/// recopiée sans cette épreuve ne vérifierait qu'elle-même.
///
/// Les « écarts du poste » en fin de fichier sont les SEULS textes qui n'ont pas
/// d'équivalent au serveur ; chacun dit lequel de ses comportements il remplace.
library;

/// Un refus de l'annulation : rien n'a été écrit (ni le statut, ni la pièce).
final class RefusAnnulation implements Exception {
  const RefusAnnulation(this.message, {this.champ});

  final String message;

  /// Le champ du formulaire auquel le serveur rattache le refus : `aTaux`,
  /// `aModeRemboursement`, `aRembourseValeur`, ou `annulation` (la bannière de
  /// la page, hors formulaire).
  final String? champ;

  @override
  String toString() => 'RefusAnnulation($champ): $message';
}

abstract final class MessagesAnnulation {
  // --- Refus du SERVICE (`AnnulationReservationService`) ---------------------

  /// `hebergement_pwa.reservations.annulation_impossible`.
  static const String dejaAnnulee = 'Cette réservation est déjà annulée.';

  /// `hebergement.annulation_montant_total_inconnu`.
  static const String montantTotalInconnu =
      'Le montant total de cette réservation est inconnu (aucun tarif n\'a été '
      'figé à sa création) : le calcul de la commission est refusé plutôt '
      'qu\'approximé.';

  /// `hebergement.annulation_taux_invalide`.
  static const String tauxInvalide =
      'Le taux d\'annulation doit être compris entre 0 et 100 %.';

  /// `hebergement.annulation_remboursement_negatif`.
  static const String remboursementNegatif =
      'Le montant ou le pourcentage remboursé ne peut pas être négatif.';

  /// `hebergement.annulation_mode_remboursement_inconnu`.
  static String modeInconnu(String mode) =>
      'Mode de saisie du remboursement inconnu : « $mode ».';

  /// `hebergement.annulation_remboursement_superieur_acompte`.
  static const String remboursementSuperieurAcompte =
      'Le montant remboursé ne peut pas dépasser l\'acompte réellement '
      'encaissé.';

  /// `hebergement.annulation_libelle_ecriture`.
  static String libelleDeLaPiece(String client) =>
      'Remboursement annulation — $client';

  /// `Acompte réservation — :id` : le libellé n'est PAS une clé de langue, le
  /// serveur le compose avec `sprintf` dans `ReservationService`.
  static String libelleDeLAcompte(String reservationId) =>
      'Acompte réservation — $reservationId';

  // --- La modale (`hebergement_pwa.reservations.annulation_*`) ---------------

  /// `annulation_titre`.
  static const String titre = 'Annuler cette réservation';

  /// `annulation_element` — [client], [arrivee] et [depart] sont déjà mis en
  /// forme (`d/m/Y`).
  static String element(String client, String arrivee, String depart) =>
      'la réservation de $client du $arrivee au $depart';

  /// `annulation_delai`.
  static String delai(String heures) => 'Prestation dans $heures heure(s).';

  /// `annulation_delai_passe`.
  static const String delaiPasse = 'La date d\'arrivée est déjà passée.';

  /// `annulation_sous_seuil`.
  static const String sousSeuil =
      'moins de 24h avant la prestation (cas de référence client : 50 %).';

  /// `annulation_montant_total`.
  static const String montantTotal = 'Montant total de la réservation';

  /// `annulation_acompte_verse`.
  static const String acompteVerse = 'Acompte déjà encaissé';

  /// `annulation_champ_taux`.
  static const String champTaux =
      'Taux d\'annulation (commission retenue sur le montant total)';

  /// `annulation_taux_aide`.
  static const String tauxAide =
      'Pré-rempli depuis le paramètre système (Paramètres → Exploitation) — '
      'modifiable pour cette annulation.';

  /// `annulation_champ_remboursement`.
  static const String champRemboursement = 'Montant remboursé au client';

  /// `annulation_mode_pourcentage`.
  static const String modePourcentage = '% de l\'acompte';

  /// `annulation_mode_montant`.
  static const String modeMontant = 'FCFA';

  /// `annulation_remboursement_aide`.
  static const String remboursementAide =
      'Ne peut jamais dépasser l\'acompte réellement encaissé. Saisissez l\'une '
      'des deux façons — l\'autre se déduit à l\'enregistrement.';

  /// `annulation_aucun_acompte`.
  static const String aucunAcompte =
      'Aucun acompte n\'a été encaissé sur cette réservation : rien à '
      'rembourser.';

  /// `annulation_rappel` — la chaîne du serveur porte un `<strong>` autour de
  /// « conservée » ; le poste le rend en gras, et [rappelAvant]/[rappelGras]/
  /// [rappelApres] sont les trois morceaux de la même phrase.
  static const String rappelAvant =
      'L\'unité réservée redevient disponible immédiatement. La réservation est ';
  static const String rappelGras = 'conservée';
  static const String rappelApres =
      ' et reste consultable — rien n\'est effacé.';

  /// `annulation_confirmer`.
  static const String confirmer = 'Annuler la réservation';

  /// `pwa.modale.annuler`.
  static const String renoncer = 'Annuler';

  /// `pwa.reservations.annulee_flash` — le message de succès.
  static const String annuleeFlash =
      'Réservation annulée — l\'unité est libérée.';

  // --- Validation Livewire (`lang/fr/validation.php`) -------------------------
  //
  // ⚠ Le serveur nomme le champ par le nom de la PROPRIÉTÉ Livewire passée à
  // `snake_case` : « a taux », « a mode remboursement », « a rembourse valeur ».
  // Aucune entrée de `validation.attributes` ne les traduit. Le message est
  // répliqué tel quel — un nom technique devant l'opérateur est une
  // incohérence du serveur, signalée, pas corrigée ici.

  /// `validation.required`.
  static String obligatoire(String attribut) =>
      'Le champ $attribut est obligatoire.';

  /// `validation.numeric`.
  static String nombre(String attribut) =>
      'Le champ $attribut doit être un nombre.';

  /// `validation.in`.
  static String invalide(String attribut) =>
      'La valeur sélectionnée pour $attribut est invalide.';

  /// `validation.min.numeric` — sans accent, comme le fichier de langue.
  static String minimum(String attribut, String min) =>
      'Le champ $attribut doit etre au minimum de $min.';

  /// `validation.max.numeric` — sans accent, comme le fichier de langue.
  static String maximum(String attribut, String max) =>
      'Le champ $attribut ne peut pas etre superieur a $max.';

  static const String attributTaux = 'a taux';
  static const String attributMode = 'a mode remboursement';
  static const String attributValeur = 'a rembourse valeur';

  // --- Écarts du poste : AUCUN équivalent au serveur --------------------------

  /// Le serveur accepte « 1e3 » au contrôle `numeric` puis `bcadd` lève une
  /// `ValueError` (HTTP 500) AVANT d'écrire. Le poste refuse avec une phrase.
  static const String malForme =
      'Cette valeur n\'est pas un nombre décimal simple (ni exposant, ni '
      'espace) : elle ne peut pas être calculée. Rien n\'est enregistré.';
}
