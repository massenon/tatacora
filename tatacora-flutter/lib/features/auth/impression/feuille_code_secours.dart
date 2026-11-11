// Vue Blade maîtresse (PA-183) : pwa/transverse/mon-profil.blade.php
// Vue Blade maîtresse (PA-183) : pwa/livewire/code-secours.blade.php
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/impression/texte_ticket.dart';

/// La feuille du CODE DE SECOURS à imprimer et ranger au coffre (29/10/2026,
/// option A du PO) : le titre, le compte, le code en gros, la consigne.
///
/// Ce n'est pas un document remis à un client ni un état : une feuille interne,
/// sans en-tête d'établissement ni zone de signatures (aucun gabarit d'état
/// n'est composé ici, `pdf_directive_test` n'a rien à y classer). Tout texte
/// passe par `texteTicket` : les polices intégrées du PDF ne couvrent que
/// Latin-1 (l'apostrophe typographique disparaîtrait du papier).
///
/// Le code n'est écrit nulle part : il n'existe que dans les octets du PDF
/// remis au dialogue d'impression, jamais dans un fichier.
class FeuilleCodeSecours {
  const FeuilleCodeSecours({
    required this.code,
    required this.login,
    required this.date,
  });

  final String code;
  final String login;
  final DateTime date;

  static const String titre = "Code de secours de l'administrateur";
  static const String consigne =
      'Ce code ne sera plus affiché. Rangez cette feuille au coffre : il ne '
      "sert qu'une fois, puis un nouveau code est remis.";

  static String _t(String s) => texteTicket(s);

  static String _deux(int n) => n.toString().padLeft(2, '0');

  Future<Uint8List> pdf() async {
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              _t(titre),
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              _t(
                'Compte : $login — posé le ${_deux(date.day)}/${_deux(date.month)}/${date.year}',
              ),
              style: const pw.TextStyle(fontSize: 10),
            ),
            pw.SizedBox(height: 24),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(14),
              decoration: pw.BoxDecoration(border: pw.Border.all(width: 2)),
              child: pw.Text(
                code,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  font: pw.Font.courierBold(),
                  fontSize: 18,
                  letterSpacing: 1.5,
                ),
              ),
            ),
            pw.SizedBox(height: 18),
            pw.Text(_t(consigne), style: const pw.TextStyle(fontSize: 10)),
          ],
        ),
      ),
    );
    return doc.save();
  }
}

/// L'impression du code — une action INJECTABLE, jamais un `layoutPdf` dans un
/// écran (un test de widget n'ouvre pas de dialogue d'impression).
final imprimerCodeSecoursProvider =
    Provider<Future<void> Function(String code, String login)>(
      (ref) =>
          (code, login) => Printing.layoutPdf(
            onLayout: (_) => FeuilleCodeSecours(
              code: code,
              login: login,
              date: DateTime.now(),
            ).pdf(),
            name: FeuilleCodeSecours.titre,
            format: PdfPageFormat.a5,
          ),
    );
