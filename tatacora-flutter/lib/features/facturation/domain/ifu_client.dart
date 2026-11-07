/// L'IFU du CLIENT d'une facture — décision du PO du 07/11/2026 (point 2).
///
/// UNE règle, au poste comme au web (miroir de `App\Domain\Facturation\Support\IfuClient`,
/// parité prouvée par `tool/facturation/rejouer_regles_communes.php`) :
///
///  * FACULTATIF : vide = client sans IFU (le boîtier — `buyer_ifu` facultatif — et
///    e-MECeF — `client.ifu` facultatif — l'acceptent) ;
///  * renseigné : EXACTEMENT 13 chiffres (espaces, points et tirets de saisie ôtés).
///
/// Les phrases sont celles de `lang/fr/facturation.php` (clés `ifu_client.*`,
/// `mode.*`, `avoir_en_ligne*`) : même champ, mêmes règles, mêmes phrases.
library;

abstract final class IfuClient {
  static final RegExp _format = RegExp(r'^[0-9]{13}$');

  /// Retire espaces, points et tirets ; `null` si rien ne reste.
  static String? nettoyer(String? saisie) {
    final propre = (saisie ?? '').trim().replaceAll(RegExp(r'[\s.\-]+'), '');
    return propre.isEmpty ? null : propre;
  }

  /// Vide = valide ; sinon exactement 13 chiffres.
  static bool valide(String? saisie) {
    final propre = nettoyer(saisie);
    return propre == null || _format.hasMatch(propre);
  }

  /// Le nom de l'acheteur à la normalisation : celui saisi, sinon [repli], sinon
  /// « Client divers ».
  static String nomPourNormalisation(String? nom, {String? repli}) {
    final net = (nom ?? '').trim();
    if (net.isNotEmpty) return net.length > 100 ? net.substring(0, 100) : net;
    final r = (repli ?? '').trim();
    if (r.isNotEmpty) return r.length > 100 ? r.substring(0, 100) : r;
    return TextesIfuClient.nomDivers;
  }
}

/// Les mots du champ « IFU du client » (lang/fr/facturation.php, `ifu_client.*`).
abstract final class TextesIfuClient {
  static const String label = 'IFU du client';
  static const String nomLabel = 'Nom du client';
  static const String aide =
      'Facultatif : 13 chiffres. Laissez vide pour un client sans IFU.';
  static const String invalide =
      'L\'IFU du client doit compter exactement 13 chiffres (laissez vide '
      'pour un client sans IFU).';
  static const String retenir = 'Retenir pour ce client';
  static const String nomDivers = 'Client divers';
  static const String normaliserMaintenant = 'Normaliser maintenant';
}

/// Les phrases du comportement par mode et de l'avoir en ligne
/// (lang/fr/facturation.php, `mode.*` et `avoir_en_ligne*`).
abstract final class TextesFacturationModes {
  /// Un avoir sur une facture normalisée se fait EN LIGNE (décision du PO, point 4).
  static const String avoirEnLigne =
      'Un avoir sur une facture normalisée se fait en ligne : reconnectez le '
      'poste au serveur.';

  /// La normalisation e-MECeF depuis le poste se fait EN LIGNE.
  static const String normalisationEnLigne =
      'La normalisation e-MECeF se fait en ligne : reconnectez le poste au '
      'serveur.';

  static const String enAttenteDeNormalisation =
      'Facture en attente de normalisation';
}
