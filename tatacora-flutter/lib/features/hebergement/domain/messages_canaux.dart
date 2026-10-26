/// Les phrases de refus et de succès de la gestion des canaux de réservation —
/// CELLES du serveur (`lang/fr/parametres.php`, `canal_*`), relues par PHP
/// dans `messages_canaux_test.dart`.
///
/// Elles vivent dans la couche domaine : le DAO les lève, l'onglet de
/// Paramètres les affiche telles quelles, sans les reformuler.
abstract final class MessagesCanaux {
  /// `parametres.canal_nom_requis`.
  static const String nomRequis = 'Le nom du canal est obligatoire.';

  /// `parametres.canal_nom_deja_utilise`.
  static String nomDejaUtilise(String nom) =>
      'Un canal nommé « $nom » existe déjà. Renommez-le plutôt que d’en créer '
      'un second : deux canaux du même nom rendraient l’analyse par canal '
      'ambiguë.';

  /// `parametres.canal_introuvable`.
  static const String introuvable = 'Ce canal n’existe plus.';

  /// `parametres.canal_enregistre`.
  static const String enregistre = 'Canal enregistré.';

  /// `parametres.canal_bascule`.
  static const String bascule = 'État du canal mis à jour.';

  /// La borne du formulaire du serveur (`canalNom` : `max:100`).
  static const int longueurMax = 100;

  /// Le refus d'un nom trop long, dit en toutes lettres.
  static const String nomTropLong =
      'Le nom du canal ne doit pas dépasser 100 caractères.';
}

/// Un geste refusé, avec sa phrase. Jamais une exception générique : l'onglet
/// l'affiche sous le champ.
final class RefusCanal implements Exception {
  const RefusCanal(this.message);

  final String message;

  @override
  String toString() => message;
}
