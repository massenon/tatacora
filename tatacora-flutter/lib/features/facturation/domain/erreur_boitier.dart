/// Les ERREURS du boîtier de facturation CC300 et leurs phrases françaises
/// (`docs/SPEC_FACTURATION_NORMALISEE_MECEF.md` §7). Aucune phrase ne cite un
/// secret ; aucune n'affirme qu'une facture est normalisée quand elle ne l'est pas.
library;

/// Pourquoi une opération sur le boîtier n'a pas abouti. Registre fermé : un
/// `switch` exhaustif décide de ce que devient la facture.
enum CauseBoitier {
  /// Le mode de ce poste n'est pas « boîtier » : aucune requête n'est faite.
  desactive,

  /// L'adresse du pilote est illisible.
  adresseInvalide,

  /// Le pilote répond, le boîtier n'est pas branché (503).
  appareilAbsent,

  /// Rien n'écoute à l'adresse du pilote.
  piloteInjoignable,

  /// Le pilote n'a pas répondu à temps.
  delai,

  /// Le pilote a répondu, mais pas par un code de facture valide.
  reponseInvalide,

  /// Le boîtier ou le pilote a refusé la facture (400, message d'erreur).
  refus,

  /// Les lignes, le total et les paiements ne concordent pas : refusé AVANT envoi.
  montantsIncoherents,

  /// L'IFU du boîtier n'est pas celui de l'entreprise.
  ifuDifferent,

  /// Un autre envoi est en cours sur ce poste (jamais deux `POST /bill`).
  enCours,

  /// La facture n'est pas convertible (mode de paiement inconnu, non réglée…).
  nonConvertible,
}

final class ErreurBoitier implements Exception {
  const ErreurBoitier(this.cause, this.message);

  final CauseBoitier cause;

  /// La phrase française, affichable telle quelle.
  final String message;

  @override
  String toString() => message;
}

/// Les phrases du boîtier.
abstract final class TextesBoitier {
  static const desactive =
      'Ce poste ne certifie pas par le boîtier : aucune requête n’a été faite.';
  static const appareilAbsent =
      'Le boîtier de facturation n’est pas branché, ou son pilote ne le voit '
      'pas. Vérifiez le câble USB, puis réessayez.';
  static String piloteInjoignable(String adresse) =>
      'Le pilote du boîtier ne répond pas à l’adresse $adresse. Vérifiez '
      'qu’il est démarré sur ce poste.';
  static const delaiVerification =
      'Le boîtier n’a pas répondu à temps. Réessayez dans un instant.';
  static const delaiEnvoi =
      'Le boîtier n’a pas répondu en 30 secondes. La facture a peut-être été '
      'enregistrée par le boîtier : le poste vérifie son compteur avant tout nouvel essai.';
  static const reponseInvalide =
      'Le boîtier a répondu sans code de facture valide : la facture n’est '
      'pas normalisée.';
  static String refus(String detail) =>
      'Le boîtier a refusé la facture : $detail';
  static String montants(int lignes, int paiements) =>
      'Les montants ne concordent pas (lignes $lignes FCFA, paiements '
      '$paiements FCFA) : corrigez avant de normaliser.';
  static String ifuDifferent(String boitier, String entreprise) =>
      'L’IFU du boîtier ($boitier) n’est pas celui de l’entreprise '
      '($entreprise).';
  static const enCours =
      'Une normalisation est déjà en cours sur ce poste : attendez qu’elle '
      'se termine.';
  static const sansReponseNiCompteur =
      'Le boîtier n’a pas répondu et son compteur n’a pas pu être relu : '
      'impossible de savoir si la facture a été enregistrée. Ne la rejouez '
      'pas : vérifiez le boîtier.';
  static String enregistreeSansCode(int avant, int apres) =>
      'Le boîtier a enregistré une facture (compteur $avant → $apres) mais sa '
      'réponse n’a pas été reçue : ne la rejouez pas, vérifiez le boîtier.';
}
