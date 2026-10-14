/// Les règles de saisie des modales de l'accueil — `validerEcriture([...])`
/// de `App\Pwa\Livewire\Accueil`, répliquées en fonctions PURES (lot C,
/// 14/10/2026).
///
/// ## Les messages sont ceux de Laravel, au mot
///
/// `lang/fr/validation.php` (accents compris — et leur ABSENCE dans `min` et
/// `max`, « doit etre au minimum de », telle qu'écrite au serveur). Le nom du
/// champ est celui que Laravel imprime pour une propriété Livewire sans entrée
/// dans `validation.attributes` : la propriété passée en `snake_case`, tirets
/// bas remplacés par des espaces (« resa nuits », « checkin client nom »). Un
/// nom technique devant l'opérateur est une incohérence du SERVEUR, déjà
/// signalée pour l'encaissement (D233) — répliquée, pas corrigée ici.
///
/// ## Un message par champ, le premier
///
/// Laravel évalue les règles d'un champ dans l'ordre et la vue affiche
/// `@error(champ)` — le premier. Une valeur vide n'est éprouvée QUE par
/// `required` : les autres règles ne s'appliquent pas à un champ vide.
library;

/// `validation.required` — vide au sens de Laravel : `null`, ou une chaîne
/// qui ne contient que des blancs.
String obligatoireLaravel(String attribut) =>
    'Le champ $attribut est obligatoire.';

/// `validation.max.string`.
String maxChaineLaravel(String attribut, int max) =>
    'Le champ $attribut ne peut pas contenir plus de $max caracteres.';

/// `validation.integer`.
String entierLaravel(String attribut) =>
    'Le champ $attribut doit être un entier.';

/// `validation.min.numeric`.
String minNombreLaravel(String attribut, int min) =>
    'Le champ $attribut doit etre au minimum de $min.';

/// `validation.max.numeric`.
String maxNombreLaravel(String attribut, int max) =>
    'Le champ $attribut ne peut pas etre superieur a $max.';

/// `validation.date`.
String dateLaravel(String attribut) =>
    "Le champ $attribut n'est pas une date valide.";

bool _videLaravel(String? valeur) => valeur == null || valeur.trim().isEmpty;

/// `['required', 'string', 'max:255']`.
String? texteRequis255(String? valeur, String attribut) {
  if (_videLaravel(valeur)) return obligatoireLaravel(attribut);
  // `max:255` sur une chaîne compte les CARACTÈRES (`mb_strlen`).
  if (valeur!.runes.length > 255) return maxChaineLaravel(attribut, 255);
  return null;
}

/// `['required', …]` d'un choix dans une liste (client, unité, canal) : la
/// liste ne propose que des valeurs existantes, seul le vide se refuse ici.
String? choixRequis(Object? valeur, String attribut) =>
    valeur == null || (valeur is String && valeur.trim().isEmpty)
    ? obligatoireLaravel(attribut)
    : null;

/// `['required', 'integer', 'min:1', 'max:365']` — le nombre de nuits.
/// Rend `(erreur, nuits)` : `nuits` n'est renseigné que si la saisie passe.
(String?, int?) nuitsValides(String? brut, String attribut) {
  if (_videLaravel(brut)) return (obligatoireLaravel(attribut), null);
  final nuits = int.tryParse(brut!.trim());
  if (nuits == null) return (entierLaravel(attribut), null);
  if (nuits < 1) return (minNombreLaravel(attribut, 1), null);
  if (nuits > 365) return (maxNombreLaravel(attribut, 365), null);
  return (null, nuits);
}

/// Les noms de champs, tels que Laravel les imprime — UN endroit.
abstract final class AttributsAccueil {
  static const String clientNom = 'client nom';
  static const String clientTelephone = 'client telephone';
  static const String resaClientId = 'resa client id';
  static const String resaClientNom = 'resa client nom';
  static const String resaClientTelephone = 'resa client telephone';
  static const String resaUniteId = 'resa unite id';
  static const String resaCanalId = 'resa canal id';
  static const String resaDateArrivee = 'resa date arrivee';
  static const String resaNuits = 'resa nuits';
  static const String checkinClientId = 'checkin client id';
  static const String checkinClientNom = 'checkin client nom';
  static const String checkinClientTelephone = 'checkin client telephone';
  static const String checkinNuits = 'checkin nuits';
}

/// `hebergement.chevauchement` — le message du conflit RG-01 que le composant
/// affiche sous l'unité (`ChevauchementDetecteException`).
const String messageChevauchementServeur =
    'Cette unité est déjà réservée sur cette période.';
