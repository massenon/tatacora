import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;

import 'entete_etablissement.dart';
import 'texte_ticket.dart';

/// L'en-tête et le pied des documents A4 — **point unique**.
///
/// `RESPECT_TABLEAU_RAPPORT.md` §4 recense « l'en-tête recopiée localement »
/// comme non-conformité n° 1 des états. Elle vivait dans `EtatHistorique`, où
/// elle était juste ; le deuxième état l'aurait dupliquée, et le troisième
/// aurait eu deux modèles à choisir. Elle est ici, et les états l'appellent.
///
/// Le contenu, lui, reste dans {@link EnteteEtablissement} : ce fichier ne
/// décide **que** de la mise en page.
///
/// Tout texte passe par `texteTicket` : les polices intégrées du format PDF
/// couvrent Latin-1 et rien de plus — l'apostrophe typographique de « Chiffre
/// d'affaires » disparaissait réellement du papier, sans erreur ni trace.
pw.Widget enTeteA4({
  required EnteteEtablissement entete,
  required String titre,
  required String sousTitre,
  Uint8List? logo,
}) => pw.Container(
  padding: const pw.EdgeInsets.only(bottom: 8),
  margin: const pw.EdgeInsets.only(bottom: 10),
  decoration: const pw.BoxDecoration(
    border: pw.Border(bottom: pw.BorderSide(width: 0.8)),
  ),
  child: pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      if (logo != null)
        pw.Padding(
          padding: const pw.EdgeInsets.only(right: 10),
          child: pw.Image(pw.MemoryImage(logo), width: 38, height: 38),
        ),
      pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // `lignesA4` porte déjà l'ordre du gabarit et écarte les
            // identifiants fiscaux non renseignés — imprimer un exemple de
            // format sur un document remis serait un faux identifiant fiscal.
            for (final (index, ligne) in entete.lignesA4.indexed)
              pw.Text(
                texteTicket(ligne),
                style: index == 0
                    ? pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)
                    : const pw.TextStyle(fontSize: 8),
              ),
          ],
        ),
      ),
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Text(
            texteTicket(titre),
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(
            texteTicket(sousTitre),
            style: const pw.TextStyle(fontSize: 9),
          ),
        ],
      ),
    ],
  ),
);

/// Le pied de page, numéroté — celui des documents REMIS AU CLIENT.
///
/// Un état de plusieurs pages remis sans numérotation ne se vérifie pas : rien
/// ne dit qu'il en manque une. Un export interne prend [piedRapportA4].
pw.Widget piedA4(int page, int total) => pw.Container(
  alignment: pw.Alignment.centerRight,
  margin: const pw.EdgeInsets.only(top: 8),
  child: pw.Text('Page $page / $total', style: const pw.TextStyle(fontSize: 8)),
);

/// Le pied d'un ÉTAT D'EXPORT — Directive §6, décision du Product Owner du
/// 11/09/2026 (PA-192 (a), PA-195) : mention institutionnelle, date d'édition,
/// pagination. Traduction de `pdf/partials/pied-rapport.blade.php`.
///
/// [edition] est passée, jamais lue ici : la composition reste déterministe.
pw.Widget piedRapportA4(
  int page,
  int total, {
  required EnteteEtablissement entete,
  required DateTime edition,
}) => pw.Container(
  margin: const pw.EdgeInsets.only(top: 8),
  padding: const pw.EdgeInsets.only(top: 4),
  decoration: const pw.BoxDecoration(
    border: pw.Border(top: pw.BorderSide(width: 0.5)),
  ),
  child: pw.Row(
    children: [
      pw.Expanded(
        child: pw.Text(
          texteTicket(entete.mentionInstitutionnelle),
          style: const pw.TextStyle(fontSize: 7.5),
        ),
      ),
      pw.Expanded(
        child: pw.Text(
          texteTicket('Édité le ${_horodatage(edition)}'),
          textAlign: pw.TextAlign.center,
          style: const pw.TextStyle(fontSize: 7.5),
        ),
      ),
      pw.Expanded(
        // « Page x / y » (demande du PO du 14/10/2026) : la même forme que
        // `piedA4`, sur tous les états d'export.
        child: pw.Text(
          'Page $page / $total',
          textAlign: pw.TextAlign.right,
          style: const pw.TextStyle(fontSize: 7.5),
        ),
      ),
    ],
  ),
);

/// La ZONE DE SIGNATURES d'un état d'export — Directive §6.2, traduction de
/// `pdf/partials/signatures.blade.php`. Les libellés viennent de [Visas], qui
/// relit ceux du gabarit serveur correspondant — jamais écrits ici.
///
/// Un document REMIS AU CLIENT n'en porte jamais : un « Visa Ordonnateur » sur
/// un papier client le ferait lire comme une pièce d'ordonnancement interne.
pw.Widget zoneSignaturesA4({
  required List<String> visas,
  String ligne = '____________________',
}) => pw.Padding(
  padding: const pw.EdgeInsets.only(top: 30),
  child: pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      for (final visa in visas)
        pw.Expanded(
          child: pw.Column(
            children: [
              pw.Text(
                texteTicket('$visa :'),
                style: pw.TextStyle(
                  fontSize: 8.5,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 36),
              pw.Text(ligne, style: const pw.TextStyle(fontSize: 8.5)),
            ],
          ),
        ),
    ],
  ),
);

String _horodatage(DateTime d) {
  String deux(int n) => n.toString().padLeft(2, '0');
  return '${deux(d.day)}/${deux(d.month)}/${d.year} ${deux(d.hour)}:${deux(d.minute)}';
}
