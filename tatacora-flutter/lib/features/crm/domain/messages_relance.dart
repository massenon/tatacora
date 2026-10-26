// Vue Blade maîtresse (PA-183) : pwa/crm/clients-creances.blade.php
/// Les phrases de refus et de succès d'une relance — celles du SERVEUR,
/// confrontées à son code par `messages_relance_test.dart` (PHP exécuté).
///
/// * `lang/fr/crm.php` : les trois refus de `RelanceClientService::enregistrer`
///   (canal hors registre, client inconnu, montant invalide) ;
/// * `lang/fr/validation.php` : les trois règles de la validation Livewire du
///   montant (`required`, `numeric`, `min:0`), avec l'attribut tel que Laravel
///   l'écrit pour la propriété `relanceMontant` ;
/// * `lang/fr/pwa.php` : le succès (`pwa.clients.relance_succes`).
library;

abstract final class MessagesRelance {
  /// `crm.relance_canal_inconnu`.
  static String canalInconnu(String canal) =>
      "Le canal de relance « $canal » n'existe pas au registre.";

  /// `crm.relance_client_inconnu`.
  static const String clientInconnu =
      "Ce client n'existe pas dans le référentiel.";

  /// `crm.relance_montant_invalide`.
  static const String montantInvalide =
      'Le montant réclamé doit être un nombre positif ou nul.';

  /// L'attribut de la propriété `relanceMontant` dans les messages de
  /// validation de Laravel (`Str::snake` + espaces).
  static const String attributMontant = 'relance montant';

  /// `validation.required`.
  static const String montantObligatoire =
      'Le champ relance montant est obligatoire.';

  /// `validation.numeric`.
  static const String montantIllisible =
      'Le champ relance montant doit être un nombre.';

  /// `validation.min.numeric` (avec `:min` = 0).
  static const String montantNegatif =
      'Le champ relance montant doit etre au minimum de 0.';

  /// `validation.date` (attribut `relance promesse`).
  static const String promesseIllisible =
      "Le champ relance promesse n'est pas une date valide.";

  /// `pwa.clients.relance_succes`.
  static String succes(String client) => 'Relance de « $client » enregistrée.';

  /// Le droit d'écrire sur M3 manque.
  static const String droitManquant =
      "Vous n'avez pas le droit d'enregistrer une relance.";
}

/// Une relance refusée : rien n'a été écrit.
final class RefusRelance implements Exception {
  const RefusRelance(this.message);

  final String message;

  @override
  String toString() => message;
}
