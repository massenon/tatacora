/// **Planche d'essai — un QR code sort-il lisible d'une thermique 80 mm ?**
///
/// ## Une question physique, posée par le Product Owner, et qu'aucun test ne
/// tranchera
///
/// La facture normalisée MECeF porte un cachet fiscal **matérialisé par un QR
/// code** (`MECEF_INTEGRATION_SPEC.md` §1). Si ce QR doit être scannable et que
/// la thermique du comptoir ne le rend pas de façon fiable, alors la facture
/// certifiée **doit** sortir en A4 — indépendamment de toute préférence, et
/// indépendamment du confort de lecture. C'est un argument matériel, pas un
/// arbitrage de goût.
///
/// Ce module ne répond pas à la question : il fabrique **l'objet qui permet de
/// la trancher**. Un humain imprime la planche sur le rouleau du comptoir et
/// tente de scanner chaque carré avec un téléphone. La plus petite taille
/// lisible est la réponse.
///
/// ## ⚠ Le contenu est MANIFESTEMENT non fiscal, et ce n'est pas un détail
///
/// Chaque carré encode `TATACORA-ESSAI-QR-<taille>mm` — rien d'autre. La
/// planche ne porte **aucun numéro de facture, aucun NIM, aucun cachet**, et
/// elle dit en clair ce qu'elle est.
///
/// Un QR d'apparence officielle sorti d'une imprimante de comptoir, même « pour
/// essayer », finirait par être agrafé à une facture : ce serait PA-61 sous
/// forme physique, sur du papier qu'on ne rattrape pas. Le contenu de test est
/// donc choisi pour qu'un scan révèle immédiatement qu'il ne s'agit de rien.
///
/// ## Aucun accès réseau
///
/// Le générateur de code-barres est celui que `package:pdf` re-exporte déjà
/// (`package:barcode`, pur Dart, dépendances `meta` et `qr` seulement — aucun
/// `dart:io`, aucun client HTTP). Le poste du Gîte encaisse hors connexion :
/// une planche d'essai qui exigerait Internet serait la seule pièce du logiciel
/// à le faire.
library;

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/impression/texte_ticket.dart';
import 'ticket_facture.dart' show formatRouleau80mm;

/// Les tailles éprouvées, en millimètres de côté.
///
/// La borne haute est contrainte par le papier : un rouleau de 80 mm avec
/// 4 mm de marge de chaque côté laisse 72 mm utiles. La borne basse part sous
/// ce qu'on croit lisible, précisément pour que l'essai puisse le démentir.
const List<int> taillesEssaiQrMm = [10, 15, 20, 25, 30, 35];

/// Ce qu'encode le carré d'une taille donnée — **manifestement pas un cachet**.
String contenuEssaiQr(int tailleMm) => 'TATACORA-ESSAI-QR-${tailleMm}mm';

/// Une planche composée : les textes réellement imprimés, et le PDF.
///
/// Même principe que le ticket et la facture A4 : le document est un objet
/// avant d'être un PDF, et [textes] est par construction ce que le papier
/// recevra — la normalisation des caractères s'y applique donc aussi.
final class PlancheEssaiQr {
  const PlancheEssaiQr({
    required this.tailles,
    required this.entete,
    required this.legendes,
    required this.pied,
  });

  final List<int> tailles;
  final List<String> entete;

  /// La légende de chaque carré, dans l'ordre de [tailles].
  final List<String> legendes;

  final List<String> pied;

  List<String> get textes => [...entete, ...legendes, ...pied];

  String get texteBrut => textes.join('\n');

  /// Le contenu encodé, dans l'ordre de [tailles].
  ///
  /// Exposé pour qu'un test puisse vérifier qu'il ne ressemble à aucun cachet
  /// fiscal — la vérification porte alors sur ce qui sera réellement encodé,
  /// pas sur une chaîne écrite à côté.
  List<String> get contenus => [for (final t in tailles) contenuEssaiQr(t)];

  Future<Uint8List> pdf() async {
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: formatRouleau80mm,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            for (final ligne in entete)
              pw.Text(
                ligne,
                style: ligne == entete.first
                    ? pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)
                    : const pw.TextStyle(fontSize: 7),
              ),
            pw.Divider(height: 6),
            for (var i = 0; i < tailles.length; i++) ...[
              pw.Center(
                child: pw.Text(
                  legendes[i],
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Center(
                child: pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(),
                  data: contenuEssaiQr(tailles[i]),
                  width: tailles[i] * PdfPageFormat.mm,
                  height: tailles[i] * PdfPageFormat.mm,
                  drawText: false,
                ),
              ),
              pw.SizedBox(height: 6),
            ],
            pw.Divider(height: 6),
            for (final ligne in pied)
              pw.Text(ligne, style: const pw.TextStyle(fontSize: 7)),
          ],
        ),
      ),
    );
    return doc.save();
  }
}

/// Compose la planche d'essai.
final class EssaiQrThermique {
  const EssaiQrThermique._();

  static PlancheEssaiQr composer({
    List<int> tailles = taillesEssaiQrMm,
  }) => PlancheEssaiQr(
    tailles: tailles,
    entete: [
      _t('ESSAI DE LISIBILITÉ QR'),
      _t('Rouleau thermique 80 mm — planche de contrôle'),
      _t(
        'Ce papier n\'est PAS un document fiscal et ne porte aucun cachet. '
        'Chaque carré encode seulement son propre libellé d\'essai.',
      ),
    ],
    legendes: [for (final t in tailles) _t('$t mm de côté')],
    pied: [
      _t(
        'À faire : scanner chaque carré au téléphone, du plus petit au plus '
        'grand, et noter le premier qui se lit du premier coup.',
      ),
      _t(
        'Si aucun ne se lit de façon fiable, la facture certifiée MECeF '
        'devra sortir en A4 : le cachet fiscal doit être scannable.',
      ),
    ],
  );

  static String _t(String source) => texteTicket(source);
}
