/// La lecture d'un fichier d'import choisi par l'utilisateur : classeur
/// `.xlsx` d'abord, CSV en secours (demande du PO du 30/10/2026).
///
/// Le type se reconnaît au CONTENU, jamais à l'extension : signature ZIP
/// (`PK`) pour un `.xlsx`, signature OLE pour un ancien `.xls` (refusé avec la
/// marche à suivre). Le reste est du CSV : BOM UTF-8, UTF-16 ou Windows-1252
/// (l'encodage du « CSV (séparateur : point-virgule) » d'Excel Windows),
/// séparateur `;` `,` ou tabulation choisi sur la première ligne, ligne
/// `sep=;` d'Excel respectée — comme `TableurService` du serveur.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import 'lecture_csv.dart';

/// Un fichier que le poste ne sait pas lire — le message est dit à l'écran.
final class TableurIllisible implements Exception {
  const TableurIllisible(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract final class TextesTableur {
  static const String vide = 'Le fichier est vide.';
  static const String xlsAncien =
      'Ce fichier est un ancien classeur .xls. Ouvrez-le dans Excel et '
      'enregistrez-le au format « Classeur Excel (.xlsx) », ou repartez du '
      'modèle .xlsx téléchargé.';
  static const String xlsxIllisible =
      'Le classeur .xlsx est illisible ou protégé. Repartez du modèle .xlsx '
      'téléchargé, ou enregistrez-le de nouveau depuis Excel.';
  static String tropLong(int maximum) =>
      'Le fichier compte plus de $maximum lignes : découpez-le en plusieurs '
      'fichiers.';
}

/// La feuille lue quand le classeur en compte plusieurs.
const String feuilleModele = 'Modèle';

/// Au-delà, ce n'est pas un fichier d'import.
const int lignesMaximumTableur = 5000;

/// Lit [octets] : lignes brutes, l'en-tête en premier. LÈVE
/// [TableurIllisible] avec un message destiné à l'utilisateur.
List<List<String>> lireTableur(List<int> octets) {
  if (octets.isEmpty) throw const TableurIllisible(TextesTableur.vide);
  if (octets.length >= 4 &&
      octets[0] == 0x50 &&
      octets[1] == 0x4B &&
      octets[2] == 3 &&
      octets[3] == 4) {
    return _lireXlsx(octets);
  }
  if (octets.length >= 4 &&
      octets[0] == 0xD0 &&
      octets[1] == 0xCF &&
      octets[2] == 0x11 &&
      octets[3] == 0xE0) {
    throw const TableurIllisible(TextesTableur.xlsAncien);
  }
  return lireCsvTolerant(octets);
}

/// Le CSV : encodage, `sep=`, séparateur.
List<List<String>> lireCsvTolerant(List<int> octets) {
  var texte = _enUtf8(octets);
  String? separateur;
  final sep = RegExp(r'^sep=(.)\r?\n', caseSensitive: false).firstMatch(texte);
  if (sep != null) {
    separateur = sep.group(1);
    texte = texte.substring(sep.end);
  }
  return lireCsv(texte, separateur: separateur ?? separateurDe(texte));
}

String _enUtf8(List<int> o) {
  if (o.length >= 3 && o[0] == 0xEF && o[1] == 0xBB && o[2] == 0xBF) {
    return utf8.decode(o.sublist(3), allowMalformed: true);
  }
  if (o.length >= 2 &&
      ((o[0] == 0xFF && o[1] == 0xFE) || (o[0] == 0xFE && o[1] == 0xFF))) {
    final petit = o[0] == 0xFF;
    final unites = <int>[];
    for (var i = 2; i + 1 < o.length; i += 2) {
      unites.add(petit ? o[i] | (o[i + 1] << 8) : (o[i] << 8) | o[i + 1]);
    }
    return String.fromCharCodes(unites);
  }
  try {
    return utf8.decode(o);
  } on FormatException {
    return _windows1252(o);
  }
}

const List<int> _cp1252 = [
  0x20AC, 0x81, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, //
  0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x8D, 0x017D, 0x8F, //
  0x90, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, //
  0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x9D, 0x017E, 0x0178,
];

String _windows1252(List<int> o) => String.fromCharCodes([
  for (final b in o) (b >= 0x80 && b <= 0x9F) ? _cp1252[b - 0x80] : b,
]);

// ------------------------------------------------------------------ xlsx

List<List<String>> _lireXlsx(List<int> octets) {
  try {
    final zip = ZipDecoder().decodeBytes(Uint8List.fromList(octets));
    String? lire(String chemin) {
      final f = zip.findFile(chemin);
      return f == null ? null : utf8.decode(f.readBytes() ?? const []);
    }

    final classeur = XmlDocument.parse(lire('xl/workbook.xml')!);
    final rels = XmlDocument.parse(lire('xl/_rels/workbook.xml.rels')!);
    final feuilles = classeur.findAllElements('sheet').toList();
    final feuille = feuilles.firstWhere(
      (f) => f.getAttribute('name') == feuilleModele,
      orElse: () => feuilles.first,
    );
    final rid = feuille.attributes
        .firstWhere((a) => a.name.local == 'id')
        .value;
    var cible = rels
        .findAllElements('Relationship')
        .firstWhere((r) => r.getAttribute('Id') == rid)
        .getAttribute('Target')!;
    cible = cible.startsWith('/') ? cible.substring(1) : 'xl/$cible';

    final partages = <String>[];
    final xmlPartages = lire('xl/sharedStrings.xml');
    if (xmlPartages != null) {
      for (final si in XmlDocument.parse(xmlPartages).findAllElements('si')) {
        partages.add(_texte(si));
      }
    }

    final lignes = <int, Map<int, String>>{};
    var derniere = 0;
    for (final c in XmlDocument.parse(lire(cible)!).findAllElements('c')) {
      final ref = c.getAttribute('r')!;
      final m = RegExp(r'^([A-Z]+)(\d+)$').firstMatch(ref)!;
      final col = _colonne(m.group(1)!);
      final ligne = int.parse(m.group(2)!);
      if (ligne > lignesMaximumTableur) {
        throw const TableurIllisible('trop');
      }
      final v = c.getElement('v')?.innerText ?? '';
      final valeur = switch (c.getAttribute('t')) {
        's' => partages[int.parse(v)],
        'inlineStr' => _texte(c.getElement('is')!),
        'b' => v == '1' ? '1' : '0',
        'e' => '',
        'str' => v,
        _ => _nombre(v),
      };
      if (valeur.trim().isEmpty) continue;
      (lignes[ligne] ??= {})[col] = valeur.trim();
      if (ligne > derniere) derniere = ligne;
    }

    return [
      for (var l = 1; l <= derniere; l++)
        () {
          final cellules = lignes[l];
          if (cellules == null) return <String>[''];
          final largeur = cellules.keys.reduce((a, b) => a > b ? a : b) + 1;
          return [for (var i = 0; i < largeur; i++) cellules[i] ?? ''];
        }(),
    ];
  } on TableurIllisible catch (e) {
    throw e.message == 'trop'
        ? TableurIllisible(TextesTableur.tropLong(lignesMaximumTableur))
        : e;
  } on Object {
    throw const TableurIllisible(TextesTableur.xlsxIllisible);
  }
}

String _texte(XmlElement e) => e
    .findAllElements('t')
    .where(
      (t) => !t.ancestors.any((a) => a is XmlElement && a.name.local == 'rPh'),
    )
    .map((t) => t.innerText)
    .join();

int _colonne(String lettres) {
  var n = 0;
  for (final c in lettres.codeUnits) {
    n = n * 26 + (c - 64);
  }
  return n - 1;
}

/// Un nombre de cellule redevient le texte qu'Excel affiche : « 1500 ».
String _nombre(String v) {
  final d = double.tryParse(v);
  if (d == null) return v;
  if (d == d.truncateToDouble() && d.abs() < 1e15) return d.toInt().toString();
  return double.parse(d.toStringAsFixed(10)).toString();
}
