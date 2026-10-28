/// L'adresse e-mail FACULTATIVE d'un employé ou d'un compte (décision du Product
/// Owner du 28/10/2026) — la règle du serveur
/// (`App\Shared\Mail\Support\AdresseEmailFacultative`), rejouée mot pour mot :
///
/// - **facultative** : un blanc vaut « non renseignée » (`null`), jamais une erreur ;
/// - **normalisée** : `trim` puis minuscules, avant toute validation ;
/// - **format** : celui de `email:filter` de Laravel, c'est-à-dire le
///   `FILTER_VALIDATE_EMAIL` de PHP (partie locale en atomes séparés par un point,
///   64 caractères au plus ; domaine en étiquettes de 63 au plus, au moins deux,
///   la dernière non numérique), sans guillemets ni crochets (écartés aussi par
///   le serveur : `not_regex`) ;
/// - **255 caractères** au plus ;
/// - **aucune unicité** : deux salariés peuvent partager une boîte.
///
/// Le test `email_facultatif_contre_serveur_test.dart` confronte cette règle au
/// vrai PHP sur une liste d'adresses ; les écarts ne se corrigent pas ici à l'œil.
library;

abstract final class AdresseEmailFacultative {
  /// `lang/fr/rh_pwa.php` : `email_invalide` — relue du serveur par le test.
  static const String messageInvalide = 'Adresse email invalide.';

  /// `lang/fr/rh_pwa.php` : `email_enregistre` — relue du serveur par le test.
  static const String messageEnregistree = 'Adresse email enregistrée.';

  static const int longueurMax = 255;

  static final RegExp _atomeLocal = RegExp(
    r"^[A-Za-z0-9!#$%&'*+/=?^_`{|}~-]+$",
  );
  static final RegExp _etiquette = RegExp(
    r'^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$',
  );

  /// `trim` + minuscules ; `null` quand il ne reste rien.
  static String? normaliser(String? saisie) {
    final propre = (saisie ?? '').trim().toLowerCase();
    return propre.isEmpty ? null : propre;
  }

  /// Une dernière étiquette toute en chiffres (`a@b.123`) est refusée par PHP.
  static final RegExp _chiffres = RegExp(r'^[0-9]+$');

  /// Le format d'une adresse DÉJÀ normalisée (non vide).
  static bool estValide(String adresse) {
    if (adresse.runes.length > longueurMax) return false;
    final arobase = adresse.indexOf('@');
    if (arobase <= 0 || arobase != adresse.lastIndexOf('@')) return false;
    final local = adresse.substring(0, arobase);
    final domaine = adresse.substring(arobase + 1);
    if (local.length > 64) return false;
    if (!local.split('.').every(_atomeLocal.hasMatch)) return false;
    final etiquettes = domaine.split('.');
    return etiquettes.length >= 2 &&
        etiquettes.every(_etiquette.hasMatch) &&
        !_chiffres.hasMatch(etiquettes.last);
  }

  /// Le refus d'une saisie brute : `null` quand elle est acceptable (vide
  /// comprise), la phrase du serveur sinon.
  static String? erreur(String? saisie) {
    final adresse = normaliser(saisie);
    if (adresse == null) return null;
    return estValide(adresse) ? null : messageInvalide;
  }
}
