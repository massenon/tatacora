/// Les réglages des documents commerciaux (factures A4, proformas) — PO, 07/11/2026.
///
/// Écrits au serveur (Paramètres > Identité & Légal), DESCENDUS au poste en lecture
/// (`parametres_local`) : le poste ne les modifie pas. Jumeau de `ReglagesDocuments.php`
/// (mêmes clés, mêmes défauts : référence `GCN`, 30 jours, interrupteurs sur Non).
/// Un texte vide reste vide : la ligne n'est pas imprimée.
library;

abstract final class ClesReglagesDocuments {
  static const activites = 'entreprise_activites';
  static const facebook = 'entreprise_facebook';
  static const villeEmission = 'entreprise_ville_emission';
  static const referenceFacture = 'facture_reference';
  static const signataireNom = 'signataire_nom';
  static const signataireFonction = 'signataire_fonction';
  static const signatureAffichee = 'facture_signature_affichee';
  static const validiteAffichee = 'proforma_validite_affichee';
  static const validiteJours = 'proforma_validite_jours';
}

const String referenceFactureParDefaut = 'GCN';
const int validiteProformaParDefautJours = 30;

final class ReglagesDocuments {
  const ReglagesDocuments._(this._valeurs);

  /// Depuis la table des paramètres descendus (clé -> valeur).
  factory ReglagesDocuments.depuis(Map<String, String?> valeurs) =>
      ReglagesDocuments._(valeurs);

  /// Aucun réglage descendu : tous les défauts.
  static const ReglagesDocuments parDefaut = ReglagesDocuments._({});

  final Map<String, String?> _valeurs;

  String _texte(String cle) => (_valeurs[cle] ?? '').trim();

  String get activites => _texte(ClesReglagesDocuments.activites);
  String get facebook => _texte(ClesReglagesDocuments.facebook);
  String get villeEmission => _texte(ClesReglagesDocuments.villeEmission);
  String get signataireNom => _texte(ClesReglagesDocuments.signataireNom);
  String get signataireFonction =>
      _texte(ClesReglagesDocuments.signataireFonction);

  /// La référence facture en MAJUSCULES ; `GCN` tant qu'elle est vide.
  String get referenceFacture {
    final r = _texte(ClesReglagesDocuments.referenceFacture).toUpperCase();
    return r.isEmpty ? referenceFactureParDefaut : r;
  }

  bool get signatureAffichee =>
      _booleen(_texte(ClesReglagesDocuments.signatureAffichee));

  bool get validiteAffichee =>
      _booleen(_texte(ClesReglagesDocuments.validiteAffichee));

  int get validiteJours {
    final v = _texte(ClesReglagesDocuments.validiteJours);
    final n = int.tryParse(v);
    return n != null && n > 0 && RegExp(r'^[0-9]+$').hasMatch(v)
        ? n
        : validiteProformaParDefautJours;
  }

  /// Comme `FILTER_VALIDATE_BOOLEAN` du serveur.
  static bool _booleen(String v) =>
      const {'1', 'true', 'on', 'yes'}.contains(v.toLowerCase());
}

/// Le bloc signature des documents A4 : `null` quand l'interrupteur est sur Non (ni nom ni
/// image), sinon nom et fonction — les images viennent en plus quand elles sont déposées.
/// Jumeau de `BlocSignature.php` ; le ticket ne l'appelle jamais.
({String nom, String fonction})? blocSignature(ReglagesDocuments r) =>
    r.signatureAffichee
    ? (nom: r.signataireNom, fonction: r.signataireFonction)
    : null;
