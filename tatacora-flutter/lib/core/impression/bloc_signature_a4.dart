/// Le BLOC SIGNATURE des documents A4 — factures et proformas (PO, 07/11/2026). Jumeau de
/// `pdf/partials/bloc-signature.blade.php` et de `BlocSignature.php` (serveur).
///
/// L'interrupteur « Afficher la signature et le cachet sur les factures » (réglage du serveur,
/// descendu en lecture) : sur Non, [BlocSignatureA4.depuis] rend `null` — ni nom, ni fonction,
/// ni images. Sur Oui sans image déposée : nom et fonction seulement. Le ticket 80 mm
/// n'appelle jamais ce bloc.
library;

import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;

import '../../features/facturation/domain/reglages_documents.dart';
import 'texte_ticket.dart';

final class BlocSignatureA4 {
  const BlocSignatureA4({
    required this.entreprise,
    required this.nom,
    required this.fonction,
    this.signature,
    this.cachet,
  });

  /// `null` quand l'interrupteur est sur Non.
  static BlocSignatureA4? depuis(
    ReglagesDocuments reglages, {
    required String raisonSociale,
    Uint8List? signature,
    Uint8List? cachet,
  }) {
    final bloc = blocSignature(reglages);
    if (bloc == null) return null;
    return BlocSignatureA4(
      entreprise: raisonSociale,
      nom: bloc.nom,
      fonction: bloc.fonction,
      signature: signature,
      cachet: cachet,
    );
  }

  final String entreprise;
  final String nom;
  final String fonction;
  final Uint8List? signature;
  final Uint8List? cachet;

  /// « Pour GÎTE CHEZ NOËL » — la raison sociale en majuscules, comme le serveur.
  String get libellePour => texteTicket('Pour ${entreprise.toUpperCase()}');

  /// Tous les textes du bloc (pour le garde-fou des caractères imprimables).
  List<String> get textes => [
    libellePour,
    if (nom.isNotEmpty) texteTicket(nom),
    if (fonction.isNotEmpty) texteTicket(fonction),
  ];

  pw.Widget widget() => pw.Row(
    children: [
      pw.Spacer(flex: 55),
      pw.Expanded(
        flex: 45,
        child: pw.Column(
          children: [
            pw.Text(
              libellePour,
              style: pw.TextStyle(
                fontSize: 9.5,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(
              height: 80,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  if (signature != null)
                    pw.SizedBox(
                      width: 110,
                      height: 70,
                      child: pw.Image(
                        pw.MemoryImage(signature!),
                        fit: pw.BoxFit.contain,
                      ),
                    ),
                  if (cachet != null)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(left: 6),
                      child: pw.SizedBox(
                        width: 80,
                        height: 75,
                        child: pw.Image(
                          pw.MemoryImage(cachet!),
                          fit: pw.BoxFit.contain,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (nom.isNotEmpty)
              pw.Text(
                texteTicket(nom),
                style: pw.TextStyle(
                  fontSize: 9.5,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            if (fonction.isNotEmpty)
              pw.Text(
                texteTicket(fonction),
                style: const pw.TextStyle(fontSize: 9.5),
              ),
          ],
        ),
      ),
    ],
  );
}
