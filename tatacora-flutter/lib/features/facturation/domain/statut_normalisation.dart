/// Le STATUT DE NORMALISATION d'une pièce — registre fermé, miroir de
/// `StatutNormalisation` du serveur (`docs/SPEC_FACTURATION_NORMALISEE_MECEF.md`
/// §6, parité prouvée par `rejouer_regles_communes.php`).
///
/// `null` n'est PAS un statut : il dit « non concernée » (démonstration, mode
/// désactivé, pièce d'avant la v50). Aucune valeur inconnue n'est devinée.
library;

enum StatutNormalisation {
  /// Le boîtier ou la DGI a rendu un code : la pièce a une valeur fiscale.
  normalisee('normalisee', 'Normalisée'),

  /// Rien n'a été enregistré : la pièce attend (appareil absent, délai,
  /// réponse invalide…) et se rejoue par « Réessayer ».
  enAttente('en_attente', 'En attente de normalisation'),

  /// Le boîtier (ou la DGI) a explicitement refusé la pièce.
  refusee('refusee', 'Refusée'),

  /// Le boîtier a PEUT-ÊTRE enregistré la pièce et on ne peut pas trancher :
  /// jamais rejouée automatiquement.
  aVerifier('a_verifier', 'À vérifier');

  const StatutNormalisation(this.code, this.libelle);

  final String code;
  final String libelle;

  /// `null` sur un code absent ou inconnu — jamais un repli.
  static StatutNormalisation? depuisCode(String? code) {
    for (final s in values) {
      if (s.code == code) return s;
    }
    return null;
  }

  /// Une pièce « Réessayer »-able : en attente ou refusée. Une pièce « à
  /// vérifier » ne se rejoue pas sans une vérification du compteur.
  bool get rejouable => this == enAttente || this == refusee;
}

/// La voie qui a normalisé (ou tenté de).
enum VoieNormalisation {
  boitier('boitier'),
  emecef('emecef');

  const VoieNormalisation(this.code);
  final String code;

  static VoieNormalisation? depuisCode(String? code) {
    for (final v in values) {
      if (v.code == code) return v;
    }
    return null;
  }
}
