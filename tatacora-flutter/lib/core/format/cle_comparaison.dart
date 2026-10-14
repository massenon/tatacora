/// La clé de comparaison d'un texte saisi : minuscules et SANS accent.
///
/// La collation du serveur (`utf8mb4_unicode_ci`) range « Éts » avec « Ets » et
/// `LIKE '%ets%'` le retrouve ; Dart, lui, rangerait « É » après « z » (point
/// de code) et « é » ne serait pas « e ». Quelqu'un qui tape « ets » doit
/// trouver « Éts Kora », comme sur la vue.
///
/// UN seul auteur : M7 (fournisseurs, commandes) et M4 (plats, fiches, menus)
/// comparent des libellés saisis, et deux tables d'accents écrites à deux
/// endroits finiraient par ranger « œuf » différemment.
library;

String cleDeComparaison(String texte) {
  final b = StringBuffer();
  for (final c in texte.toLowerCase().split('')) {
    b.write(_sansAccent[c] ?? c);
  }
  return b.toString();
}

const _sansAccent = <String, String>{
  'à': 'a',
  'â': 'a',
  'ä': 'a',
  'á': 'a',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ë': 'e',
  'î': 'i',
  'ï': 'i',
  'í': 'i',
  'ô': 'o',
  'ö': 'o',
  'ó': 'o',
  'ù': 'u',
  'û': 'u',
  'ü': 'u',
  'ú': 'u',
  'ç': 'c',
  'ñ': 'n',
  'œ': 'oe',
  'æ': 'ae',
};
