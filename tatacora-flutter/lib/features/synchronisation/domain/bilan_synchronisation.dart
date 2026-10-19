/// Le BILAN d'une synchronisation et la politique de repli (lot F2a,
/// 15/10/2026).
library;

import 'descente_catalogue.dart';

/// Comment s'est terminée une synchronisation. Registre FERMÉ.
enum EtatSynchronisation {
  /// Plus aucune opération échue à envoyer (ou rien à envoyer du tout).
  termine,

  /// Le poste n'a pas de jeton : rien n'est tenté.
  nonAppaire,

  /// Démonstration : jamais de synchronisation.
  demonstration,

  /// L'appairage a été fait vers un autre serveur que celui de ce build.
  autreServeur,

  /// Pas de réponse, 5xx, 408, 429 : le lot est rendu à la file, avec repli.
  serveurIndisponible,

  /// 401 : le serveur refuse le jeton. Plus rien avant un nouvel appairage.
  jetonRefuse,

  /// 403 : le `poste_id` n'est pas celui du jeton. Idem.
  posteNonReconnu,

  /// 409 `generation_perimee` (19/10/2026) : le serveur a été réinitialisé
  /// depuis la dernière synchronisation de ce poste. Le lot est rendu
  /// INTACT ; plus rien ne part ni n'arrive avant la réinitialisation de CE
  /// poste (Import & Export → Réinitialiser comme neuf).
  serveurReinitialise,

  /// Un refus que le moteur ne sait pas rejouer (4xx inattendu, réponse
  /// illisible) : les opérations en cause sont consignées, la synchronisation
  /// s'arrête.
  alerte;

  /// La phrase de l'état — ce que l'écran de synchronisation (F2b) dira.
  String get libelle => switch (this) {
    termine => 'Synchronisation à jour.',
    nonAppaire => 'Poste non appairé : aucune synchronisation.',
    demonstration => 'Démonstration : aucune synchronisation.',
    autreServeur =>
      'Poste appairé à un autre serveur que celui de ce logiciel — '
          'réappairer le poste.',
    serveurIndisponible =>
      'Serveur injoignable ou indisponible : nouvel essai automatique plus '
          'tard.',
    jetonRefuse => 'Jeton refusé — réappairer le poste.',
    posteNonReconnu =>
      'Poste non reconnu par le serveur — réappairer le poste.',
    serveurReinitialise =>
      'Le serveur a été réinitialisé : réinitialisez ce poste (Import & '
          'Export → Réinitialiser comme neuf) avant de reprendre.',
    alerte => 'Synchronisation interrompue : des opérations sont refusées.',
  };
}

/// Ce qu'a fait UNE synchronisation.
final class BilanSynchronisation {
  const BilanSynchronisation({
    required this.etat,
    this.lots = 0,
    this.envoyees = 0,
    this.synchronisees = 0,
    this.rejetees = 0,
    this.conflits = 0,
    this.codeHttp,
    this.detail,
    this.prochaineTentative,
    this.descente,
  });

  final EtatSynchronisation etat;

  /// Requêtes `POST /sync` émises (une bissection en émet plusieurs).
  final int lots;

  /// Opérations dont le serveur a rendu un résultat définitif.
  final int envoyees;
  final int synchronisees;
  final int rejetees;
  final int conflits;

  /// Le code HTTP de l'arrêt, s'il y en a un.
  final int? codeHttp;

  /// Le détail technique de l'arrêt (journal), jamais un corps de réponse.
  final String? detail;

  /// Quand la file sera de nouveau échue, après un repli.
  final DateTime? prochaineTentative;

  /// La DESCENTE du catalogue de ce passage (lot F2b) — `null` quand elle
  /// n'a pas été tentée (poste non appairé, démonstration, refus 401/403 de
  /// l'envoi, moteur sans descente).
  final BilanDescente? descente;

  BilanSynchronisation copierAvec({
    EtatSynchronisation? etat,
    int? codeHttp,
    String? detail,
    DateTime? prochaineTentative,
    BilanDescente? descente,
  }) => BilanSynchronisation(
    etat: etat ?? this.etat,
    lots: lots,
    envoyees: envoyees,
    synchronisees: synchronisees,
    rejetees: rejetees,
    conflits: conflits,
    codeHttp: codeHttp ?? this.codeHttp,
    detail: detail ?? this.detail,
    prochaineTentative: prochaineTentative ?? this.prochaineTentative,
    descente: descente ?? this.descente,
  );

  @override
  String toString() =>
      'BilanSynchronisation(${etat.name}, lots $lots, envoyées $envoyees, '
      'synchronisées $synchronisees, rejetées $rejetees, conflits $conflits'
      '${codeHttp == null ? '' : ', HTTP $codeHttp'}'
      '${descente == null ? '' : ', $descente'})';
}

/// Le repli après un échec transitoire : 30 s → 2 min → 5 min → 15 min →
/// 1 h, puis 1 h. [tentatives] : le nombre d'envois déjà tentés de
/// l'opération (`operations_sync_local.tentatives`, incrémenté à chaque
/// réclamation), donc 1 au premier échec.
Duration delaiDeRepli(int tentatives) => switch (tentatives) {
  <= 1 => const Duration(seconds: 30),
  2 => const Duration(minutes: 2),
  3 => const Duration(minutes: 5),
  4 => const Duration(minutes: 15),
  _ => const Duration(hours: 1),
};

/// Le plafond d'un `Retry-After` honoré : au-delà, c'est une valeur aberrante
/// (un serveur ne demande pas d'attendre une semaine), et un poste qui
/// dormirait autant perdrait sa file de vue.
const Duration plafondRetryAfter = Duration(hours: 24);

/// `Retry-After` : un nombre de secondes ou une date HTTP. `null` si absent
/// ou illisible.
Duration? lireRetryAfter(String? valeur, DateTime maintenant) {
  if (valeur == null || valeur.trim().isEmpty) return null;
  final secondes = int.tryParse(valeur.trim());
  Duration? delai;
  if (secondes != null) {
    delai = Duration(seconds: secondes < 0 ? 0 : secondes);
  } else {
    final date = _dateHttp(valeur.trim());
    if (date == null) return null;
    final ecart = date.difference(maintenant.toUtc());
    delai = ecart.isNegative ? Duration.zero : ecart;
  }
  return delai > plafondRetryAfter ? plafondRetryAfter : delai;
}

/// Une date HTTP (RFC 7231, IMF-fixdate) : `Wed, 21 Oct 2026 07:28:00 GMT`.
DateTime? _dateHttp(String texte) {
  const mois = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final m = RegExp(
    r'^\w{3}, (\d{2}) (\w{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT$',
  ).firstMatch(texte);
  if (m == null) return null;
  final rang = mois.indexOf(m.group(2)!);
  if (rang < 0) return null;
  return DateTime.utc(
    int.parse(m.group(3)!),
    rang + 1,
    int.parse(m.group(1)!),
    int.parse(m.group(4)!),
    int.parse(m.group(5)!),
    int.parse(m.group(6)!),
  );
}
