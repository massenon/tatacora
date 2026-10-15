import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:tatacora_flutter/core/impression/texte_ticket.dart';

/// Impression du ticket — Sprint D0, point 6.
///
/// ## Ce que ces tests prouvent, et ce qu'ils ne prouvent pas
///
/// Ils prouvent que **le chemin d'impression existe** sur la cible Windows :
/// le greffon atteint le sous-système d'impression du système, un document se
/// compose, et il sort en octets exploitables.
///
/// Ils **ne prouvent pas** qu'un ticket sort lisible d'une thermique réelle —
/// largeur du papier, jeu de caractères, accents. Cela demande la machine du
/// comptoir, et relève du Sprint D3.
///
/// La distinction compte : rapporter « l'impression fonctionne » sur la foi de
/// ces tests serait exactement l'indicateur que cette campagne a démonté.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// Format d'un rouleau thermique courant : 80 mm de large, hauteur libre.
  ///
  /// C'est ce format qui fait la différence avec une page A4, et c'est lui
  /// qu'il faut éprouver — un ticket composé en A4 sort tronqué sur la moitié
  /// droite, ou minuscule, selon le pilote.
  const rouleau = PdfPageFormat(
    80 * PdfPageFormat.mm,
    double.infinity,
    marginAll: 4 * PdfPageFormat.mm,
  );

  Future<List<int>> composerTicket() async {
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: rouleau,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Text(
              texteTicket('GÎTE CHEZ NOËL'),
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              texteTicket('Natitingou — Bénin'),
              style: const pw.TextStyle(fontSize: 8),
            ),
            pw.SizedBox(height: 6),
            pw.Text('V-2026-00016', style: const pw.TextStyle(fontSize: 9)),
            pw.Divider(),
            for (final ligne in const [
              ['Béninoise 33cl', '2', '2 000 F'],
              ['Poulet braisé', '1', '4 500 F'],
            ])
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Expanded(
                    child: pw.Text(
                      texteTicket('${ligne[0]} × ${ligne[1]}'),
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  ),
                  pw.Text(ligne[2], style: const pw.TextStyle(fontSize: 9)),
                ],
              ),
            pw.Divider(),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'TOTAL',
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  '6 500 F',
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              texteTicket('DOCUMENT DE DÉMONSTRATION — NON CERTIFIÉ MECeF'),
              style: const pw.TextStyle(fontSize: 7),
            ),
          ],
        ),
      ),
    );
    return doc.save();
  }

  group('D0.6 — le chemin d’impression', () {
    testWidgets('le greffon atteint le sous-système d’impression', (
      tester,
    ) async {
      // Si le greffon Windows n'était pas lié, cet appel lèverait — et c'est
      // exactement la panne qu'on cherche ici, pas un défaut de mise en page.
      final imprimantes = await Printing.listPrinters();
      expect(
        imprimantes,
        isNotEmpty,
        reason: 'aucune imprimante vue : le greffon n’atteint pas le système',
      );
    });

    testWidgets('un ticket se compose au format rouleau 80 mm', (tester) async {
      final octets = await composerTicket();

      expect(octets.length, greaterThan(500));
      // Un PDF commence par `%PDF`. Le vérifier évite de valider un tableau
      // d'octets vide qui aurait l'air d'un succès.
      expect(String.fromCharCodes(octets.take(4)), '%PDF');
    });

    testWidgets('le ticket sort sur le disque, lisible par un tiers', (
      tester,
    ) async {
      // Le fichier est conservé : c'est la seule pièce de D0.6 qu'un humain
      // peut ouvrir et regarder. Le rendu — accents compris — se juge à l'œil,
      // pas par une assertion.
      final dossier = await getApplicationDocumentsDirectory();
      final fichier = File('${dossier.path}/tatacora-ticket-essai.pdf');
      await fichier.writeAsBytes(await composerTicket());

      expect(fichier.existsSync(), isTrue);
      expect(fichier.lengthSync(), greaterThan(500));
    });

    testWidgets('les accents Latin-1 sont conservés', (tester) async {
      // Constaté en D0.6 : les polices intégrées du PDF couvrent Latin-1. Les
      // accents passent — les retirer appauvrirait le ticket sans raison.
      expect(
        texteTicket('Béninoise braisé GÎTE NOËL'),
        'Béninoise braisé GÎTE NOËL',
      );
    });

    testWidgets('les caractères hors Latin-1 sont substitués, jamais perdus', (
      tester,
    ) async {
      // Le défaut réel : ils ne provoquent aucune erreur, ils DISPARAISSENT.
      // « Natitingou — Bénin » sortait « Natitingou  Bénin », et
      // « l’addition » sortirait « laddition ».
      expect(texteTicket('Natitingou — Bénin'), 'Natitingou - Bénin');
      expect(texteTicket('l’addition'), "l'addition");
      expect(texteTicket('2 × 1 000 F…'), '2 x 1 000 F...');
    });

    testWidgets('aucun caractère du ticket ne sera perdu à l’impression', (
      tester,
    ) async {
      // Le garde-fou qui compte : plutôt que de constater l'amputation sur le
      // papier, on refuse en amont tout caractère que la police ne rend pas.
      const source =
          'GÎTE CHEZ NOËL — Natitingou · l’addition « soldée »… 2 × 500 F';
      final restants = caracteresNonImprimables(texteTicket(source));
      expect(
        restants,
        isEmpty,
        reason:
            'ces caractères disparaîtraient en silence : ${restants.join(' ')}',
      );
    });

    testWidgets('un ticket réel ne contient aucun caractère perdu', (
      tester,
    ) async {
      // La même garantie, sur le document effectivement composé.
      const lignes = [
        'GÎTE CHEZ NOËL',
        'Natitingou — Bénin',
        'V-2026-00016',
        'Béninoise 33cl × 2',
        'Poulet braisé × 1',
        'TOTAL',
        'DOCUMENT DE DÉMONSTRATION — NON CERTIFIÉ MECeF',
      ];
      for (final l in lignes) {
        expect(caracteresNonImprimables(texteTicket(l)), isEmpty, reason: l);
      }
    });
  });
}
