/// L'écriture d'un classeur `.xlsx` d'import (demande du PO du 30/10/2026).
///
/// Pourquoi : le modèle était un CSV au point-virgule, qu'un Excel réglé sur
/// la virgule ouvre en UNE seule colonne. Un classeur n'a pas ce défaut : une
/// colonne = une cellule, quel que soit le réglage régional.
///
/// Un `.xlsx` est une archive ZIP de fichiers XML ; on l'écrit ici en Dart pur
/// (`archive`), sans paquet de tableur. Deux feuilles, comme le serveur
/// (`TableurService::ecrireClasseur`) :
///
///  - « Modèle » : en-têtes en gras (figés), largeurs, ligne d'exemple grisée
///    ou lignes de données ; nombres et montants en cellules NUMÉRIQUES, le
///    reste en TEXTE ; listes fermées en menu déroulant ;
///  - « Aide » : une ligne par colonne — obligatoire, format, valeurs, exemple.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Une colonne du classeur — indépendante des modules, pour rester dans `core`.
final class ColonneTableur {
  const ColonneTableur({
    required this.libelle,
    required this.requis,
    required this.format,
    this.numerique = false,
    this.montant = false,
    this.valeurs,
    this.exemple = '',
  });

  final String libelle;
  final bool requis;

  /// Le format dit en clair dans la feuille « Aide ».
  final String format;
  final bool numerique;
  final bool montant;
  final List<String>? valeurs;
  final String exemple;
}

/// Marque de la ligne d'exemple du modèle : elle n'est jamais importée.
const String prefixeExemple = '(exemple) ';

abstract final class TextesClasseur {
  static const String feuilleModele = 'Modèle';
  static const String feuilleAide = 'Aide';
  static String aideTitre(String module) => 'Import — $module';
  static const String aideConsigne =
      'Remplissez la feuille « Modèle », une ligne par fiche. Ne changez ni '
      "l'ordre ni le nom des en-têtes de la ligne 1.";
  static const String aideExemple =
      'La ligne grisée de la feuille « Modèle », marquée « (exemple) », '
      "n'est pas importée : supprimez-la ou remplacez-la par vos données.";
  static const List<String> aideEntetes = [
    'Colonne',
    'Obligatoire',
    'Format',
    'Valeurs admises',
    'Exemple',
  ];
  static const String oui = 'Oui';
  static const String non = 'Non';
}

String _x(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    // Caractères de contrôle interdits en XML 1.0.
    .replaceAll(RegExp('[\u0000-\u0008\u000B\u000C\u000E-\u001F]'), '');

String _lettre(int index) {
  var n = index + 1;
  final s = StringBuffer();
  final lettres = <String>[];
  while (n > 0) {
    final r = (n - 1) % 26;
    lettres.add(String.fromCharCode(65 + r));
    n = (n - 1) ~/ 26;
  }
  s.writeAll(lettres.reversed);
  return s.toString();
}

// Indices de style (cellXfs) de `styles.xml`.
const int _sDefaut = 0;
const int _sEntete = 1;
const int _sTexte = 2;
const int _sEntier = 3;
const int _sMontant = 4;
const int _sExempleTexte = 5;
const int _sExempleNombre = 6;
const int _sTitre = 7;
const int _sHaut = 8;

const int _zoneSaisie = 1000;

String _celluleTexte(String ref, String v, int style) => v.isEmpty
    ? '<c r="$ref" s="$style"/>'
    : '<c r="$ref" s="$style" t="inlineStr"><is><t xml:space="preserve">${_x(v)}</t></is></c>';

/// Le classeur : feuilles « Modèle » et « Aide ». [lignes] absent : le modèle
/// vide, avec UNE ligne d'exemple ; sinon les lignes données ([colonnes]
/// dans l'ordre, `null` ou vide : cellule vide).
Uint8List ecrireClasseurXlsx({
  required String nomModule,
  required String description,
  required List<ColonneTableur> colonnes,
  List<List<String?>>? lignes,
}) {
  final exemple = lignes == null;
  final donnees =
      lignes ??
      [
        [
          for (final (i, c) in colonnes.indexed)
            (i == 0 ? prefixeExemple : '') + c.exemple,
        ],
      ];

  // ---- feuille Modèle
  final cols = StringBuffer('<cols>');
  for (var i = 0; i < colonnes.length; i++) {
    final c = colonnes[i];
    var largeur = c.libelle.length + 4;
    for (final l in donnees) {
      final t = (i < l.length ? l[i] : null)?.length ?? 0;
      if (t + 2 > largeur) largeur = t + 2;
    }
    if (largeur < 14) largeur = 14;
    if (largeur > 60) largeur = 60;
    final style = c.numerique ? (c.montant ? _sMontant : _sEntier) : _sTexte;
    cols.write(
      '<col min="${i + 1}" max="${i + 1}" width="$largeur" customWidth="1" style="$style"/>',
    );
  }
  cols.write('</cols>');

  final rows = StringBuffer();
  rows.write('<row r="1" ht="24" customHeight="1">');
  for (var i = 0; i < colonnes.length; i++) {
    rows.write(_celluleTexte('${_lettre(i)}1', colonnes[i].libelle, _sEntete));
  }
  rows.write('</row>');
  for (var r = 0; r < donnees.length; r++) {
    rows.write('<row r="${r + 2}">');
    for (var i = 0; i < colonnes.length; i++) {
      final c = colonnes[i];
      final v = i < donnees[r].length ? donnees[r][i] : null;
      final ref = '${_lettre(i)}${r + 2}';
      if (v == null || v.isEmpty) continue;
      if (c.numerique && num.tryParse(v) != null) {
        final s = exemple
            ? _sExempleNombre
            : (c.montant ? _sMontant : _sEntier);
        rows.write('<c r="$ref" s="$s"><v>${num.parse(v)}</v></c>');
      } else {
        rows.write(_celluleTexte(ref, v, exemple ? _sExempleTexte : _sTexte));
      }
    }
    rows.write('</row>');
  }

  final listes = StringBuffer();
  var nbListes = 0;
  for (var i = 0; i < colonnes.length; i++) {
    final v = colonnes[i].valeurs;
    if (v == null || v.isEmpty || v.any((e) => e.contains(','))) continue;
    final formule = v.join(',');
    if (formule.length > 250) continue;
    nbListes++;
    final l = _lettre(i);
    listes.write(
      '<dataValidation type="list" errorStyle="warning" allowBlank="1" '
      'showErrorMessage="1" errorTitle="Valeur hors liste" '
      'error="${_x('Valeurs admises : ${v.join(', ')}')}" '
      'sqref="${l}2:$l$_zoneSaisie">'
      '<formula1>"${_x(formule)}"</formula1></dataValidation>',
    );
  }

  final modele =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<sheetViews><sheetView workbookViewId="0" tabSelected="1">'
      '<pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/>'
      '</sheetView></sheetViews>'
      '$cols<sheetData>$rows</sheetData>'
      '${nbListes > 0 ? '<dataValidations count="$nbListes">$listes</dataValidations>' : ''}'
      '</worksheet>';

  // ---- feuille Aide
  final aide = StringBuffer('<row r="1">')
    ..write(_celluleTexte('A1', TextesClasseur.aideTitre(nomModule), _sTitre))
    ..write('</row><row r="2">')
    ..write(_celluleTexte('A2', description, _sDefaut))
    ..write('</row><row r="3">')
    ..write(_celluleTexte('A3', TextesClasseur.aideConsigne, _sDefaut))
    ..write('</row>');
  if (exemple) {
    aide
      ..write('<row r="4">')
      ..write(_celluleTexte('A4', TextesClasseur.aideExemple, _sDefaut))
      ..write('</row>');
  }
  aide.write('<row r="6">');
  for (var i = 0; i < TextesClasseur.aideEntetes.length; i++) {
    aide.write(
      _celluleTexte('${_lettre(i)}6', TextesClasseur.aideEntetes[i], _sEntete),
    );
  }
  aide.write('</row>');
  for (var i = 0; i < colonnes.length; i++) {
    final c = colonnes[i];
    final r = 7 + i;
    final vals = [
      c.libelle,
      c.requis ? TextesClasseur.oui : TextesClasseur.non,
      c.format,
      c.valeurs?.join(' ; ') ?? '',
      c.exemple,
    ];
    aide.write('<row r="$r">');
    for (var k = 0; k < vals.length; k++) {
      aide.write(_celluleTexte('${_lettre(k)}$r', vals[k], _sHaut));
    }
    aide.write('</row>');
  }
  final feuilleAide =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<cols><col min="1" max="1" width="34" customWidth="1"/>'
      '<col min="2" max="2" width="14" customWidth="1"/>'
      '<col min="3" max="3" width="44" customWidth="1"/>'
      '<col min="4" max="4" width="60" customWidth="1"/>'
      '<col min="5" max="5" width="34" customWidth="1"/></cols>'
      '<sheetData>$aide</sheetData></worksheet>';

  const styles =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<numFmts count="1"><numFmt numFmtId="164" formatCode="#,##0"/></numFmts>'
      '<fonts count="5">'
      '<font><sz val="11"/><name val="Calibri"/></font>'
      '<font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font>'
      '<font><i/><sz val="11"/><color rgb="FF6B7280"/><name val="Calibri"/></font>'
      '<font><b/><sz val="14"/><name val="Calibri"/></font>'
      '<font><sz val="11"/><name val="Calibri"/></font>'
      '</fonts>'
      '<fills count="3"><fill><patternFill patternType="none"/></fill>'
      '<fill><patternFill patternType="gray125"/></fill>'
      '<fill><patternFill patternType="solid"><fgColor rgb="FF1B2A41"/><bgColor indexed="64"/></patternFill></fill></fills>'
      '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
      '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
      '<cellXfs count="9">'
      '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
      '<xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1" applyAlignment="1"><alignment vertical="center" wrapText="1"/></xf>'
      '<xf numFmtId="49" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>'
      '<xf numFmtId="1" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyAlignment="1"><alignment horizontal="right"/></xf>'
      '<xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyAlignment="1"><alignment horizontal="right"/></xf>'
      '<xf numFmtId="49" fontId="2" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1"/>'
      '<xf numFmtId="1" fontId="2" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1" applyAlignment="1"><alignment horizontal="right"/></xf>'
      '<xf numFmtId="0" fontId="3" fillId="0" borderId="0" xfId="0" applyFont="1"/>'
      '<xf numFmtId="0" fontId="4" fillId="0" borderId="0" xfId="0" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf>'
      '</cellXfs>'
      '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
      '</styleSheet>';

  final fichiers = <String, String>{
    '[Content_Types].xml':
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
        '<Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
        '</Types>',
    '_rels/.rels':
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
        '</Relationships>',
    'xl/workbook.xml':
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<sheets><sheet name="${TextesClasseur.feuilleModele}" sheetId="1" r:id="rId1"/>'
        '<sheet name="${TextesClasseur.feuilleAide}" sheetId="2" r:id="rId2"/></sheets></workbook>',
    'xl/_rels/workbook.xml.rels':
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/>'
        '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
        '</Relationships>',
    'xl/styles.xml': styles,
    'xl/worksheets/sheet1.xml': modele,
    'xl/worksheets/sheet2.xml': feuilleAide,
  };

  final archive = Archive();
  fichiers.forEach((nom, contenu) {
    final octets = utf8.encode(contenu);
    archive.addFile(ArchiveFile(nom, octets.length, octets));
  });
  return Uint8List.fromList(ZipEncoder().encode(archive));
}
