// Vue Blade maîtresse (PA-183) : pwa/facturation/facturation.blade.php
import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/format/formats.dart';
import '../../../core/impression/entete_a4.dart';
import '../../../core/impression/entete_etablissement.dart';
import '../../../core/impression/texte_ticket.dart';
import '../../../core/impression/visas.dart';
import '../domain/certification_mecef.dart';
import '../domain/entities/piece_facturation.dart';

/// L'état **« Registre des factures »** — `m2-facturation.html` l.182-215.
///
/// ## Il porte CE QUI EST AFFICHÉ, jamais la liste complète
///
/// Le maître l'écrit en commentaire au-dessus de sa fonction : *« L'export
/// porte sur CE QUI EST AFFICHÉ, jamais sur la liste complète. »* C'est une
/// règle, pas une commodité : quelqu'un qui filtre sur les avoirs de septembre
/// et clique sur « Export PDF » attend les avoirs de septembre. Lui rendre le
/// registre entier lui ferait envoyer au comptable un document qu'il croit
/// avoir vérifié.
///
/// ## ⚠ La ligne de certification NE MENT PAS, et elle est DÉRIVÉE
///
/// Le maître écrit en dur `'non certifiées — démonstration'`, avec ce
/// commentaire : *« Jamais "certifiées : N". MECeF est factice ici, et
/// l'écrire autrement serait affirmer une certification qui n'a pas eu lieu. »*
///
/// Le portage garde l'intention et **améliore le mécanisme** : au lieu d'une
/// phrase figée, le compte est calculé depuis les pièces réellement présentes
/// (`CertificationMecef.estReelle`). Une constante resterait vraie aujourd'hui
/// et deviendrait fausse le jour de l'inscription DGI — c'est-à-dire le jour
/// où elle compterait vraiment (PA-61, PA-100). Aujourd'hui, elle rend
/// exactement la phrase du maître, parce que c'est la vérité.
///
/// @see prototype_v2/pages/m2-facturation.html — `donnees()`
/// @see RG-19 — tout export passe par le même gabarit d'en-tête
final class EtatRegistreFactures {
  const EtatRegistreFactures({
    required this.pieces,
    required this.filtre,
    this.entete = const EnteteEtablissement(),
  });

  static const String titre = 'Registre des factures';

  /// Les six colonnes du maître, dans son ordre.
  static const List<String> entetes = [
    'N°',
    'Date',
    'Client',
    'Origine',
    'Montant',
    'Statut',
  ];

  /// Les pièces **telles que l'écran les affiche**, filtre appliqué.
  final List<PieceFacturation> pieces;

  /// Ce qui est filtré, dit en clair sur le document.
  ///
  /// « Toutes périodes » quand rien n'est filtré — la mention du maître. Sans
  /// elle, un extrait se lirait comme un registre complet, et c'est sur un
  /// registre qu'on rapproche une caisse.
  final String filtre;

  final EnteteEtablissement entete;

  /// Le même document sous l'en-tête lu des paramètres au moment d'éditer
  /// (`lireEnteteEtablissementProvider`).
  EtatRegistreFactures avecEntete(EnteteEtablissement autre) =>
      EtatRegistreFactures(pieces: pieces, filtre: filtre, entete: autre);

  bool get estVide => pieces.isEmpty;

  int get montantTotal => pieces.fold(0, (total, p) => total + p.montantTotal);

  int get nombreAvoirs => pieces.where((p) => p.estAvoir).length;

  /// Combien de pièces portent une certification fiscale **réelle**.
  int get nombreCertifiees => pieces.where((p) => p.estCertifiee).length;

  /// La ligne de certification — dérivée, jamais figée.
  String get mentionCertification => nombreCertifiees == 0
      ? CertificationMecef.libelleDemonstration
      : '$nombreCertifiees certifiée(s) sur ${pieces.length}';

  /// Une ligne du tableau — **source unique** des deux rendus.
  List<String> cellules(PieceFacturation p) => [
    p.numero,
    formaterDate(p.dateEmission),
    p.clientNom,
    p.origine.libelle,
    '${p.montantTotal}',
    // Un avoir n'est pas un statut de cycle de vie, mais c'est ce qu'on
    // cherche en lisant la colonne : le maître écrit « avoir » à la place du
    // statut, et le portage le suit.
    p.estAvoir ? 'avoir' : p.statut.code,
  ];

  /// Les trois indicateurs du PDF du maître.
  Map<String, String> get indicateurs => {
    'Pièces': '${pieces.length}',
    'Montant': formaterFcfa(montantTotal),
    'Certification MECeF': mentionCertification,
  };

  /* ================================================================== */
  /* CSV                                                                 */
  /* ================================================================== */

  /// Le fichier tableur. BOM UTF-8 et point-virgule — mêmes raisons qu'à
  /// l'état de l'historique : sans le premier, Excel affiche
  /// « RÃ©servations » ; sans le second, tout arrive dans une seule colonne.
  String csv() {
    final tampon = StringBuffer()
      ..write('\u{FEFF}')
      ..writeln(_ligneCsv([titre]))
      ..writeln(_ligneCsv([filtre]))
      ..writeln();

    for (final entree in indicateurs.entries) {
      tampon.writeln(_ligneCsv([entree.key, entree.value]));
    }
    tampon
      ..writeln()
      ..writeln(_ligneCsv(entetes));

    for (final p in pieces) {
      tampon.writeln(_ligneCsv(cellules(p)));
    }
    return tampon.toString();
  }

  Uint8List csvOctets() => Uint8List.fromList(utf8.encode(csv()));

  static String _ligneCsv(List<String> valeurs) =>
      valeurs.map((v) => '"${v.replaceAll('"', '""')}"').join(';');

  /* ================================================================== */
  /* PDF                                                                 */
  /* ================================================================== */

  static String _t(String source) => texteTicket(source);

  Future<Uint8List> pdf() async {
    final doc = pw.Document();
    final editeLe = DateTime.now();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        // Le point unique `core/impression/entete_a4.dart` : ce fichier en
        // portait une COPIE (en-tête et pied), la non-conformité n° 1 de
        // `RESPECT_TABLEAU_RAPPORT.md` §4 — retirée le 11/09/2026 (PA-195).
        header: (context) => enTeteA4(
          entete: entete,
          titre: titre,
          sousTitre: filtre,
          logo: entete.logo,
        ),
        // Un EXPORT : pied de rapport et zone de signatures de la Directive
        // §6, comme `pdf/facturation-registre.blade.php`.
        footer: (context) => piedRapportA4(
          context.pageNumber,
          context.pagesCount,
          entete: entete,
          edition: editeLe,
        ),
        build: (context) => [
          _indicateurs(),
          pw.SizedBox(height: 12),
          _tableau(),
          zoneSignaturesA4(visas: Visas.directive),
        ],
      ),
    );
    return doc.save();
  }

  pw.Widget _indicateurs() => pw.Row(
    children: [
      for (final entree in indicateurs.entries)
        pw.Expanded(
          child: pw.Container(
            margin: const pw.EdgeInsets.only(right: 6),
            padding: const pw.EdgeInsets.all(6),
            decoration: const pw.BoxDecoration(color: PdfColors.grey200),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  _t(entree.key.toUpperCase()),
                  style: const pw.TextStyle(fontSize: 7),
                ),
                pw.Text(
                  _t(entree.value),
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
    ],
  );

  pw.Widget _tableau() {
    if (estVide) {
      // Le cas ne devrait pas se produire : l'écran refuse d'exporter une
      // liste vide, avec le message du maître. La garde est ici en second
      // rideau, et elle DIT plutôt que de rendre une page blanche — qu'on
      // prendrait pour un document tronqué.
      return pw.Text(
        _t('Aucune pièce ne correspond à ce filtre.'),
        style: const pw.TextStyle(fontSize: 10),
      );
    }

    return pw.TableHelper.fromTextArray(
      headers: entetes.map(_t).toList(),
      data: [for (final p in pieces) cellules(p).map(_t).toList()],
      headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
      cellStyle: const pw.TextStyle(fontSize: 8),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
      // Le montant est la seule colonne numérique du maître
      // (`colonnesNumeriques: [4]`).
      cellAlignments: {4: pw.Alignment.centerRight},
    );
  }
}
