import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/impression/entete_a4.dart';
import '../../../core/impression/entete_etablissement.dart';
import '../../../core/impression/texte_ticket.dart';
import '../../../core/impression/visas.dart';
import '../domain/entities/fiche_stock.dart';

/// Les deux exports de la fiche — `m6-inventaires.html` l.78-79.
///
/// ## Le drapeau de cohérence atteint le PAPIER
///
/// C'est la raison d'être de ce fichier. Une fiche de stock est le document
/// qu'on présente pour justifier un solde ; si le calcul a constaté un écart
/// entre le cumul des lignes et le stock théorique, un mouvement a été écrit
/// hors de `StocksDao` — donc sans le contrôle de disponibilité — et la fiche
/// **ne vaut pas justificatif**.
///
/// L'afficher à l'écran sans l'imprimer serait le pire des deux mondes : le
/// document sortirait de l'application débarrassé de la seule mention qui en
/// borne la portée, et il circulerait comme une pièce probante.
///
/// ## Le filtre de point est DIT
///
/// Une fiche restreinte au bar qui ne le dirait pas serait lue comme la fiche
/// complète de l'article, et son solde final passerait pour le stock total
/// (PA-119).
final class EtatFicheStock {
  const EtatFicheStock._();

  static const titre = 'Fiche de stock';

  static const mentionIncoherente =
      'ATTENTION — cette fiche NE VAUT PAS JUSTIFICATIF : le cumul des '
      'mouvements ne correspond pas au stock theorique. Un mouvement a ete '
      "ecrit hors de la voie d'ecriture dediee.";

  /// Le sous-titre du document : période, et portée.
  static String sousTitre(FicheStock f, {String? pointLibelle}) =>
      'Du ${f.debut} au ${f.fin} — '
      '${pointLibelle ?? 'tous points confondus'}';

  /// CSV — BOM UTF-8 et point-virgule (convention serveur RG-19).
  static String csv(FicheStock f, {String? pointLibelle}) {
    final tampon = StringBuffer('﻿')
      ..writeln('$titre;${f.article.libelle}')
      ..writeln(sousTitre(f, pointLibelle: pointLibelle).replaceAll(';', ','));

    if (!f.coherent) {
      tampon.writeln(mentionIncoherente.replaceAll(';', ','));
    }

    tampon
      ..writeln()
      ..writeln('Stock initial;${f.stockInitial}')
      ..writeln('Entrees;${f.entrees}')
      ..writeln('Sorties;${f.sorties}')
      ..writeln('Pertes;${f.pertes}')
      ..writeln('Regularisations;${f.regularisations}')
      ..writeln('Stock theorique;${f.stockTheorique}')
      ..writeln('Valeur du stock theorique;${f.valeurStockTheorique}')
      ..writeln()
      ..writeln('Date;Type;Motif;Entree;Sortie;Solde;Par');

    for (final l in f.lignes) {
      tampon.writeln(
        [
          l.date,
          _type(l),
          l.motif.replaceAll(';', ','),
          // Nombres bruts : un tableur ne sait pas additionner « 4 casiers ».
          l.entree,
          l.sortie,
          l.solde,
          (l.par ?? '—').replaceAll(';', ','),
        ].join(';'),
      );
    }

    return tampon.toString();
  }

  /// Le type d'une ligne. La décision de forcer une rupture est écrite sur le
  /// PAPIER aussi : une fiche qui montre un stock négatif sans dire qu'il a été
  /// décidé se lirait comme une erreur de saisie.
  static String _type(LigneFiche l) =>
      l.ruptureForcee ? '${l.type} - rupture forcee' : l.type;

  static List<int> csvOctets(FicheStock f, {String? pointLibelle}) =>
      utf8.encode(csv(f, pointLibelle: pointLibelle));

  static Future<Uint8List> pdf(
    FicheStock f, {
    String? pointLibelle,
    EnteteEtablissement entete = const EnteteEtablissement(),
    DateTime? edition,
  }) async {
    final document = pw.Document();
    final editeLe = edition ?? DateTime.now();

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        header: (c) => enTeteA4(
          entete: entete,
          titre: '$titre — ${f.article.libelle}',
          sousTitre: sousTitre(f, pointLibelle: pointLibelle),
        ),
        // Un EXPORT : pied de rapport et zone de signatures de la Directive
        // §6 (PA-195), aux visas de `pdf/fiche-stock.blade.php`.
        footer: (c) => piedRapportA4(
          c.pageNumber,
          c.pagesCount,
          entete: entete,
          edition: editeLe,
        ),
        build: (contexte) => [
          if (!f.coherent) ...[
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(6),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(width: 1, color: PdfColors.red800),
              ),
              child: pw.Text(
                texteTicket(mentionIncoherente),
                style: pw.TextStyle(
                  fontSize: 9,
                  color: PdfColors.red800,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 10),
          ],
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
            ),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellAlignments: {1: pw.Alignment.centerRight},
            headers: ['Recapitulatif', 'Quantite'].map(texteTicket).toList(),
            data: [
              ['Stock initial', f.stockInitial],
              ['Entrees', f.entrees],
              ['Sorties', f.sorties],
              ['Pertes', f.pertes],
              ['Regularisations', f.regularisations],
              ['Stock theorique', f.stockTheorique],
              ['Valeur du stock theorique', f.valeurStockTheorique],
            ].map((l) => l.map(texteTicket).toList()).toList(),
          ),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
            ),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellAlignments: {
              3: pw.Alignment.centerRight,
              4: pw.Alignment.centerRight,
              5: pw.Alignment.centerRight,
            },
            headers: [
              'Date',
              'Type',
              'Motif',
              'Entree',
              'Sortie',
              'Solde',
              'Par',
            ].map(texteTicket).toList(),
            data: [
              for (final l in f.lignes)
                [
                  l.date,
                  _type(l),
                  l.motif,
                  l.entree,
                  l.sortie,
                  l.solde,
                  l.par ?? '-',
                ].map(texteTicket).toList(),
            ],
          ),
          zoneSignaturesA4(visas: Visas.ficheStock),
        ],
      ),
    );

    return document.save();
  }
}
