/// Le MODE de la facturation normalisée du Bénin, tel que ce poste le lit —
/// miroir de `ModeFacturation` du serveur (`docs/SPEC_FACTURATION_NORMALISEE_MECEF.md` §1).
///
/// ## Trois choses, à ne pas confondre
///
///  * le mode du SERVEUR ([ModeFacturation]) : `desactive`, `emecef`,
///    `boitier`. Réglé au serveur par un administrateur, DESCENDU ici en
///    lecture seule avec les autres paramètres (clé [cleModeFacturation]) ;
///  * la SURCHARGE LOCALE du poste ([SurchargeFacturation], `poste.json`) :
///    « ce poste certifie par : serveur / boîtier / rien ». Elle existe parce
///    que le boîtier n'existe que sur CE poste ;
///  * ce que ce poste FAIT réellement ([CertifiePar]) : le résultat des deux.
///
/// Une valeur inconnue (clé absente, base ancienne, valeur illisible) vaut
/// « désactivé » : se tromper dans ce sens donne des factures DEMO, visibles ;
/// l'autre sens enverrait une facture à un boîtier ou à la DGI sans que
/// personne l'ait voulu. Aucune requête au pilote tant que le résultat n'est
/// pas [CertifiePar.boitier].
library;

/// La clé du paramètre système (reçu du serveur, jamais écrit ici).
const String cleModeFacturation = 'facturation_mode';

enum ModeFacturation {
  desactive('desactive', 'Désactivé'),
  emecef('emecef', 'e-MECeF (en ligne)'),
  boitier('boitier', 'Boîtier CC300 (poste)');

  const ModeFacturation(this.code, this.libelle);

  final String code;
  final String libelle;

  /// Jamais d'exception : une valeur inconnue est « désactivé ».
  static ModeFacturation depuisCode(String? valeur) {
    final v = (valeur ?? '').trim().toLowerCase();
    for (final m in values) {
      if (m.code == v) return m;
    }
    return ModeFacturation.desactive;
  }
}

/// La surcharge locale de ce poste. Absente (`null`) : il suit le serveur.
enum SurchargeFacturation {
  serveur('serveur', 'Le serveur (e-MECeF)'),
  boitier('boitier', 'Le boîtier CC300 de ce poste'),
  rien('rien', 'Rien (démonstration)');

  const SurchargeFacturation(this.code, this.libelle);

  final String code;
  final String libelle;

  static SurchargeFacturation? depuisCode(String? valeur) {
    for (final s in values) {
      if (s.code == valeur) return s;
    }
    return null;
  }
}

/// Qui certifie les factures émises sur ce poste.
enum CertifiePar {
  /// Personne : factures de démonstration, bandeau DEMO conservé.
  rien,

  /// Le serveur (e-MECeF) : le poste n'appelle ni le boîtier ni la DGI ; la
  /// facture part au serveur et y reçoit sa normalisation à la descente.
  serveur,

  /// Le boîtier CC300 branché sur ce poste (hors ligne possible).
  boitier,
}

/// Le mode effectif de CE poste : la surcharge locale, sinon le mode du
/// serveur ; le mode « boîtier » du serveur vaut « boîtier » ici, « e-MECeF »
/// vaut « le serveur », « désactivé » vaut « rien ».
CertifiePar certifiePar({
  required ModeFacturation modeServeur,
  SurchargeFacturation? surcharge,
}) {
  if (surcharge != null) {
    return switch (surcharge) {
      SurchargeFacturation.serveur => CertifiePar.serveur,
      SurchargeFacturation.boitier => CertifiePar.boitier,
      SurchargeFacturation.rien => CertifiePar.rien,
    };
  }
  return switch (modeServeur) {
    ModeFacturation.desactive => CertifiePar.rien,
    ModeFacturation.emecef => CertifiePar.serveur,
    ModeFacturation.boitier => CertifiePar.boitier,
  };
}

/// Le mode du serveur lu des paramètres reçus (`null` : jamais reçu, donc
/// « désactivé »).
ModeFacturation modeDesParametres(Map<String, String> valeurs) =>
    ModeFacturation.depuisCode(valeurs[cleModeFacturation]);

/// La phrase qui dit, en français, ce que ce poste fait.
String phraseCertifiePar(CertifiePar c, {required bool surchargeLocale}) {
  final base = switch (c) {
    CertifiePar.rien =>
      'Ce poste ne normalise pas : les factures sont des factures simples, sans mention de normalisation.',
    CertifiePar.serveur =>
      'Ce poste laisse le serveur certifier (e-MECeF) : la normalisation arrive après la synchronisation.',
    CertifiePar.boitier =>
      'Ce poste certifie par son boîtier CC300, même hors ligne.',
  };
  return surchargeLocale ? '$base (réglage local de ce poste)' : base;
}
