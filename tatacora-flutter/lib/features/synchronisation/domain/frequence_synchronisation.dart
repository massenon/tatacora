/// La FRÉQUENCE de la synchronisation automatique du poste (29/10/2026) : le
/// réveil périodique du planificateur (`synchronisationAutomatiqueProvider`).
///
/// ## Ce que la fréquence règle, et ce qu'elle ne règle pas
///
/// Elle règle UNIQUEMENT le réveil périodique. Les déclencheurs par événement
/// (démarrage, clôture de caisse, réactivation de l'interrupteur, bouton
/// « Synchroniser maintenant ») et la lecture de la demande du serveur toutes
/// les 30 secondes ne dépendent pas d'elle. Le choix est PAR POSTE
/// (`poste.json`, clé `synchronisation_frequence_minutes`) : il ne voyage pas
/// par la synchronisation.
library;

enum FrequenceSynchronisation {
  uneMinute(1, 'Toutes les minutes'),
  deuxMinutes(2, 'Toutes les 2 minutes'),
  cinqMinutes(5, 'Toutes les 5 minutes (défaut)'),
  dixMinutes(10, 'Toutes les 10 minutes'),
  quinzeMinutes(15, 'Toutes les 15 minutes'),
  trenteMinutes(30, 'Toutes les 30 minutes'),
  uneHeure(60, 'Toutes les heures'),
  manuelle(0, 'Manuelle seulement');

  const FrequenceSynchronisation(this.minutes, this.libelle);

  /// La valeur écrite dans `poste.json` ; 0 : aucun réveil périodique.
  final int minutes;
  final String libelle;

  static const FrequenceSynchronisation parDefaut = cinqMinutes;

  /// La période du réveil, `null` en manuel.
  Duration? get periode => minutes == 0 ? null : Duration(minutes: minutes);

  /// La fréquence portant [minutes] ; toute autre valeur (fichier édité à la
  /// main) retombe sur le défaut — jamais une période inventée.
  static FrequenceSynchronisation depuisMinutes(Object? minutes) {
    for (final f in values) {
      if (f.minutes == minutes) return f;
    }
    return parDefaut;
  }
}

/// L'aide de la carte « Synchronisation automatique » — ne promet que ce que
/// le code fait (déclencheurs vérifiés : `providers_synchronisation.dart`,
/// `bilan_synchronisation.dart`, `sync_manager.dart`).
abstract final class TextesFrequenceSynchronisation {
  static const aide =
      'Toutes les 5 minutes par défaut. Le poste se synchronise aussi au '
      'démarrage de l’application, après chaque clôture de caisse, à la '
      'réactivation de la synchronisation et au bouton « Synchroniser '
      'maintenant ». Il demande aussi au serveur, toutes les 30 secondes, si '
      'une synchronisation lui est demandée. Après un échec réseau ou une '
      'erreur du serveur, chaque opération est réessayée après 30 s, 2 min, '
      '5 min, 15 min, puis toutes les heures. Un jeton ou un poste refusé par '
      'le serveur arrête les envois jusqu’au réappairage. « Manuelle '
      'seulement » supprime le réveil périodique, pas ces déclencheurs.';
  static const enregistree = 'Fréquence enregistrée : ';
}
