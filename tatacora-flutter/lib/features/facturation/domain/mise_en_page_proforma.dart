/// Les petites règles de MISE EN PAGE de la proforma, jumelles de
/// `MiseEnPageProforma.php` (confrontées par `rejouer_proforma.php`) : date
/// longue française et milliers séparés par une espace insécable.
library;

const List<String> moisLongsFr = [
  'Janvier',
  'Février',
  'Mars',
  'Avril',
  'Mai',
  'Juin',
  'Juillet',
  'Août',
  'Septembre',
  'Octobre',
  'Novembre',
  'Décembre',
];

/// « 02 Novembre 2026 ».
String dateLongueFr(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')} ${moisLongsFr[date.month - 1]} ${date.year}';

/// « 1 234 567 » avec l'espace insécable U+00A0 (jamais coupée en fin de ligne).
String montantAvecEspaces(int montant) {
  final chiffres = montant.abs().toString();
  final groupes = <String>[];
  for (var fin = chiffres.length; fin > 0; fin -= 3) {
    final debut = fin - 3 < 0 ? 0 : fin - 3;
    groupes.insert(0, chiffres.substring(debut, fin));
  }
  return '${montant < 0 ? '-' : ''}${groupes.join(' ')}';
}
