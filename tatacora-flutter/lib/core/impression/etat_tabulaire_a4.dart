/// L'**état tabulaire A4** générique — « PDF Officiel A4 Imprimable » d'une
/// liste d'écran (directive du PO du 14/10/2026).
///
/// ## Pourquoi un gabarit commun
///
/// Neuf écrans refusaient leur PDF faute d'état A4 ; chacun aurait recopié la
/// même page — en-tête, ligne de portée, tableau, totaux, signatures, pied —
/// et la recopie est la non-conformité n° 1 de `RESPECT_TABLEAU_RAPPORT.md`
/// §4. Ce fichier ne décide que de la MISE EN PAGE ; l'en-tête et le pied
/// restent ceux du point unique (`entete_a4.dart`), l'identité celle de
/// [EnteteEtablissement] lue des paramètres (`entete_parametree.dart`).
///
/// ## Ce qu'un module fournit
///
/// Les cellules, **déjà en chaînes** et formatées pour le papier (montants en
/// FCFA par `formaterFcfa`) : aucune conversion n'a lieu ici. Les colonnes et
/// les lignes sont celles du CSV du même écran — un PDF qui ne dirait pas la
/// même chose que le tableur ferait deux vérités.
///
/// ## Orientation
///
/// Portrait jusqu'à six colonnes, PAYSAGE à partir de sept ([seuilPaysage]) :
/// au-delà, une cellule de libellé se réduit à quelques caractères par ligne.
library;

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'entete_a4.dart';
import 'entete_etablissement.dart';
import 'texte_ticket.dart';
import 'visas.dart';

/// L'alignement d'une colonne : les montants et les quantités à DROITE.
enum AlignementColonne { gauche, centre, droite }

/// Une colonne de l'état.
final class ColonneEtat {
  const ColonneEtat(
    this.libelle, {
    this.alignement = AlignementColonne.gauche,
    this.largeur,
  });

  /// Une colonne de montant ou de quantité, alignée à droite.
  const ColonneEtat.nombre(this.libelle, {this.largeur})
    : alignement = AlignementColonne.droite;

  final String libelle;
  final AlignementColonne alignement;

  /// La part RELATIVE de la largeur du tableau (`FlexColumnWidth`), ou `null`
  /// pour la largeur intrinsèque. Dès qu'une colonne en porte une, toutes
  /// passent en largeur relative (1 par défaut).
  final double? largeur;
}

/// Un état tabulaire prêt à composer.
final class EtatTabulaireA4 {
  const EtatTabulaireA4({
    required this.titre,
    required this.portee,
    required this.colonnes,
    required this.lignes,
    this.totaux,
    this.mentions = const [],
    this.resume,
    this.visas = Visas.directive,
    this.paysage,
  });

  /// À partir de ce nombre de colonnes, l'état passe en paysage.
  static const int seuilPaysage = 7;

  /// Le titre du document, à droite de l'en-tête.
  final String titre;

  /// La portée : période, périmètre, filtre appliqué — imprimée sous le titre.
  /// Un export porte sur ce qui est AFFICHÉ et le DIT (PA-119).
  final String portee;

  final List<ColonneEtat> colonnes;

  /// Les cellules, une liste par ligne, de la longueur de [colonnes].
  final List<List<String>> lignes;

  /// La ligne de totaux, en gras sous le tableau, ou `null`. Une cellule vide
  /// laisse la colonne sans total.
  final List<String>? totaux;

  /// Les mentions qui BORNENT la lecture du document, imprimées avant le
  /// tableau (une mention montrée à l'écran sans être imprimée laisserait le
  /// papier circuler sans elle).
  final List<String> mentions;

  /// Une phrase de synthèse après le tableau (« 12 véhicule(s) »), ou `null`.
  final String? resume;

  /// Les visas de la zone de signatures — ceux de la directive par défaut.
  final List<String> visas;

  /// L'orientation imposée, ou `null` : décidée par [seuilPaysage].
  final bool? paysage;

  bool get estVide => lignes.isEmpty;

  bool get enPaysage => paysage ?? colonnes.length >= seuilPaysage;

  PdfPageFormat get format =>
      enPaysage ? PdfPageFormat.a4.landscape : PdfPageFormat.a4;

  /// Compose le PDF. [edition] est passée pour une composition déterministe ;
  /// `null` : maintenant.
  Future<Uint8List> pdf({
    required EnteteEtablissement entete,
    DateTime? edition,
  }) async {
    assert(
      lignes.every((l) => l.length == colonnes.length) &&
          (totaux == null || totaux!.length == colonnes.length),
      'Chaque ligne porte une cellule par colonne.',
    );
    final document = pw.Document();
    final editeLe = edition ?? DateTime.now();
    final alignements = <int, pw.Alignment>{
      for (final (i, c) in colonnes.indexed) i: _alignement(c.alignement),
    };
    final relatives = colonnes.any((c) => c.largeur != null);
    final donnees = [
      for (final ligne in lignes) ligne.map(texteTicket).toList(),
      if (totaux != null) totaux!.map(texteTicket).toList(),
    ];
    // Avec un en-tête de tableau, la première ligne de données porte le
    // numéro 1 : la ligne de totaux est donc la n° `lignes.length + 1`.
    final rangTotaux = totaux == null ? -1 : lignes.length + 1;

    document.addPage(
      pw.MultiPage(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(28),
        header: (c) => enTeteA4(
          entete: entete,
          titre: titre,
          sousTitre: portee,
          logo: entete.logo,
        ),
        // Un EXPORT : pied de rapport (mention, date d'édition, « Page x / y »)
        // et zone de signatures de la Directive §6 (PA-195).
        footer: (c) => piedRapportA4(
          c.pageNumber,
          c.pagesCount,
          entete: entete,
          edition: editeLe,
        ),
        build: (contexte) => [
          for (final mention in mentions)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 2),
              child: pw.Text(
                texteTicket(mention),
                style: const pw.TextStyle(
                  fontSize: 7.5,
                  color: PdfColors.grey700,
                ),
              ),
            ),
          if (mentions.isNotEmpty) pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headers: [for (final c in colonnes) texteTicket(c.libelle)],
            data: donnees,
            headerStyle: pw.TextStyle(
              fontSize: 8.5,
              fontWeight: pw.FontWeight.bold,
            ),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellPadding: const pw.EdgeInsets.symmetric(
              horizontal: 4,
              vertical: 3,
            ),
            cellAlignments: alignements,
            headerAlignments: alignements,
            columnWidths: relatives
                ? {
                    for (final (i, c) in colonnes.indexed)
                      i: pw.FlexColumnWidth(c.largeur ?? 1),
                  }
                : null,
            textStyleBuilder: (index, donnee, rang) => rang == rangTotaux
                ? pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)
                : null,
            cellDecoration: (index, donnee, rang) => rang == rangTotaux
                ? const pw.BoxDecoration(color: PdfColors.grey200)
                : const pw.BoxDecoration(),
          ),
          if (resume != null) ...[
            pw.SizedBox(height: 8),
            pw.Text(
              texteTicket(resume),
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            ),
          ],
          zoneSignaturesA4(visas: visas),
        ],
      ),
    );

    return document.save();
  }

  static pw.Alignment _alignement(AlignementColonne a) => switch (a) {
    AlignementColonne.gauche => pw.Alignment.centerLeft,
    AlignementColonne.centre => pw.Alignment.center,
    AlignementColonne.droite => pw.Alignment.centerRight,
  };
}
