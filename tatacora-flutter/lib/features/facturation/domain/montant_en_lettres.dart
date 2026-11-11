/// Montant en lettres, en FRANÇAIS, pour « Arrêté la présente facture à la
/// somme de » (PO, 07/11/2026).
///
/// Jumeau de `MontantEnLettres.php` (serveur) : mêmes règles, confrontées sur la
/// même table de cas (`tool/proforma/cas_montant_en_lettres.json`) et sur une
/// plage de montants par `rejouer_proforma.php`.
///
/// Règles (orthographe traditionnelle, le modèle papier : « QUATRE CENT MILLE
/// FRANCS CFA ») :
///  - « vingt » et « cent » prennent un s quand ils sont multipliés ET
///    terminent le nombre ou précèdent « million(s) » / « milliard(s) » :
///    « quatre-vingts », « deux cents », « deux cents millions » ; jamais devant
///    « mille » (invariable) ni suivis d'un autre nombre : « quatre-vingt mille »,
///    « deux cent un », « quatre-vingt-un » ;
///  - « et » seulement pour 21, 31, 41, 51, 61 et 71 ;
///  - trait d'union entre dizaines et unités ; « mille » vaut 1000 ;
///  - un multiple exact du million prend « de » : « un million de francs CFA » ;
///  - FRANC au singulier pour 0 et 1, sinon FRANCS ; tout en MAJUSCULES.
/// Entiers de 0 à 999 999 999 999.
library;

const int montantEnLettresMax = 999999999999;

const List<String> _unites = [
  'zéro',
  'un',
  'deux',
  'trois',
  'quatre',
  'cinq',
  'six',
  'sept',
  'huit',
  'neuf',
  'dix',
  'onze',
  'douze',
  'treize',
  'quatorze',
  'quinze',
  'seize',
];

const Map<int, String> _dizaines = {
  2: 'vingt',
  3: 'trente',
  4: 'quarante',
  5: 'cinquante',
  6: 'soixante',
};

/// « QUATRE CENT MILLE FRANCS CFA ».
String francsCfaEnLettres(int montant) {
  final lettres = nombreEnLettres(montant);
  final de = montant >= 1000000 && montant % 1000000 == 0 ? ' de' : '';
  final unite = montant == 0 || montant == 1 ? 'franc' : 'francs';
  return '$lettres$de $unite CFA'.toUpperCase();
}

/// Le nombre en lettres minuscules.
String nombreEnLettres(int n) {
  if (n < 0 || n > montantEnLettresMax) {
    throw ArgumentError('Montant hors limites : $n');
  }
  if (n == 0) return 'zéro';

  final milliards = n ~/ 1000000000;
  final millions = (n % 1000000000) ~/ 1000000;
  final milliers = (n % 1000000) ~/ 1000;
  final reste = n % 1000;
  final parties = <String>[];

  if (milliards > 0) {
    parties.add(
      '${_groupe(milliards, true)} milliard${milliards > 1 ? 's' : ''}',
    );
  }
  if (millions > 0) {
    parties.add('${_groupe(millions, true)} million${millions > 1 ? 's' : ''}');
  }
  if (milliers > 0) {
    parties.add(milliers == 1 ? 'mille' : '${_groupe(milliers, false)} mille');
  }
  if (reste > 0) {
    parties.add(_groupe(reste, true));
  }
  return parties.join(' ');
}

String _groupe(int n, bool accorde) {
  final centaines = n ~/ 100;
  final reste = n % 100;
  var texte = '';

  if (centaines == 1) {
    texte = 'cent';
  } else if (centaines > 1) {
    texte = '${_unites[centaines]} cent${reste == 0 && accorde ? 's' : ''}';
  }
  if (reste > 0) {
    texte += '${texte.isEmpty ? '' : ' '}${_dizainesEtUnites(reste, accorde)}';
  }
  return texte;
}

String _dizainesEtUnites(int n, bool accorde) {
  if (n <= 16) return _unites[n];
  if (n < 20) return 'dix-${_unites[n - 10]}';

  final dizaine = n ~/ 10;
  final unite = n % 10;

  if (dizaine >= 2 && dizaine <= 6) {
    final base = _dizaines[dizaine]!;
    if (unite == 0) return base;
    if (unite == 1) return '$base et un';
    return '$base-${_unites[unite]}';
  }
  if (dizaine == 7) {
    return n == 71
        ? 'soixante et onze'
        : 'soixante-${_dizainesEtUnites(n - 60, false)}';
  }
  // 80 à 99 : « quatre-vingts » seulement s'il termine le nombre.
  return n == 80
      ? 'quatre-vingt${accorde ? 's' : ''}'
      : 'quatre-vingt-${_dizainesEtUnites(n - 80, false)}';
}
