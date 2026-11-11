/// La FACTURE PROFORMA A4 du poste (PO, 07/11/2026) — document NON FISCAL, même structure et même
/// rendu que `pdf/proforma.blade.php` du serveur : en-tête (logo, activités en gras souligné,
/// Facebook, e-mail, RCCM – IFU, Tel / Qtier, double filet), ville et date longue, titre, Réf.,
/// client, IFU, Tel, Objet, tableau à en-tête VERT (jeton du thème `PaletteMaitre.vert700`), TOTAL,
/// « Arrêté la présente… » et le montant EN LETTRES sur lignes pointillées, validité enregistrée,
/// bloc signature selon l'interrupteur.
///
/// ## Jamais fiscal
/// Aucun champ, aucun texte ni aucun widget MECeF, QR, NIM ou normalisation : la classe n'a rien
/// pour les porter (`proforma_a4_test.dart` le mord). Aucun `pw.Text` littéral dans le rendu :
/// tous les textes passent par [ProformaA4Composee.textes] (garde-fou des caractères).
library;

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/database/app_database.dart';
import '../../../core/impression/bloc_signature_a4.dart';
import '../../../core/impression/entete_etablissement.dart';
import '../../../core/impression/texte_ticket.dart';
import '../../../core/theme/app_assets.dart';
import '../../../core/theme/app_colors.dart';
import '../domain/mise_en_page_proforma.dart';
import '../domain/montant_en_lettres.dart';
import '../domain/reglages_documents.dart';

const PdfPageFormat formatProformaA4 = PdfPageFormat(
  21.0 * PdfPageFormat.cm,
  29.7 * PdfPageFormat.cm,
  marginAll: 1.4 * PdfPageFormat.cm,
);

/// Le vert de l'en-tête du tableau : le jeton du thème, jamais un hexadécimal posé ici.
PdfColor get vertEnteteTableau =>
    PdfColor.fromInt(PaletteMaitre.vert700.toARGB32());

final class ProformaA4Composee {
  const ProformaA4Composee({
    required this.logo,
    required this.activites,
    required this.facebook,
    required this.email,
    required this.rccmIfu,
    required this.contact,
    required this.villeDate,
    required this.titre,
    required this.identification,
    required this.colonnes,
    required this.lignesTableau,
    required this.libelleTotal,
    required this.montantTotal,
    required this.arrete,
    required this.montantEnLettres,
    required this.validite,
    required this.signature,
  });

  final Uint8List? logo;
  final String? activites;
  final String? facebook;
  final String? email;
  final String? rccmIfu;
  final String? contact;
  final String villeDate;
  final String titre;

  /// Réf., Client, IFU, Tel, Objet : libellé puis valeur (valeur vide imprimée vide, comme le web).
  final List<(String, String)> identification;
  final List<String> colonnes;
  final List<List<String>> lignesTableau;
  final String libelleTotal;
  final String montantTotal;
  final String arrete;
  final String montantEnLettres;
  final String? validite;
  final BlocSignatureA4? signature;

  /// **Tous** les textes du document.
  List<String> get textes => [
    ?activites,
    ?facebook,
    ?email,
    ?rccmIfu,
    ?contact,
    villeDate,
    titre,
    for (final (l, v) in identification) ...[l, v],
    ...colonnes,
    for (final ligne in lignesTableau) ...ligne,
    libelleTotal,
    montantTotal,
    arrete,
    montantEnLettres,
    ?validite,
    ...?signature?.textes,
  ];

  String get texteBrut => textes.join('\n');

  Future<Uint8List> pdf() async {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: formatProformaA4,
        build: (context) => [
          _entete(),
          pw.SizedBox(height: 6),
          _doubleFilet(),
          pw.SizedBox(height: 10),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(villeDate),
          ),
          pw.SizedBox(height: 8),
          pw.Center(
            child: pw.Text(
              titre,
              style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 10),
          for (final (libelle, valeur) in identification)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 3),
              child: pw.RichText(
                text: pw.TextSpan(
                  children: [
                    pw.TextSpan(
                      text: '$libelle : ',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                    pw.TextSpan(text: valeur),
                  ],
                ),
              ),
            ),
          pw.SizedBox(height: 10),
          _tableau(),
          pw.SizedBox(height: 16),
          pw.Text(arrete),
          pw.SizedBox(height: 2),
          _pointilles(
            pw.Text(
              montantEnLettres,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 10),
          _pointilles(pw.SizedBox(height: 12)),
          if (validite != null) ...[
            pw.SizedBox(height: 10),
            pw.Text(
              validite!,
              style: pw.TextStyle(fontStyle: pw.FontStyle.italic),
            ),
          ],
          if (signature != null) ...[
            pw.SizedBox(height: 18),
            signature!.widget(),
          ],
        ],
      ),
    );
    return doc.save();
  }

  pw.Widget _entete() => pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        flex: 38,
        child: logo == null
            ? pw.SizedBox()
            : pw.Align(
                alignment: pw.Alignment.centerLeft,
                child: pw.SizedBox(
                  width: AppAssets.logoFactureA4LargeurPt,
                  height: AppAssets.logoFactureA4HauteurPt,
                  child: pw.Image(
                    pw.MemoryImage(logo!),
                    fit: pw.BoxFit.contain,
                    alignment: pw.Alignment.centerLeft,
                  ),
                ),
              ),
      ),
      pw.Expanded(
        flex: 62,
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            if (activites != null)
              pw.Text(
                activites!,
                textAlign: pw.TextAlign.right,
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  decoration: pw.TextDecoration.underline,
                ),
              ),
            for (final ligne in [?facebook, ?email, ?rccmIfu, ?contact])
              pw.Text(
                ligne,
                textAlign: pw.TextAlign.right,
                style: const pw.TextStyle(fontSize: 9),
              ),
          ],
        ),
      ),
    ],
  );

  pw.Widget _doubleFilet() => pw.Column(
    children: [
      pw.Divider(height: 1, thickness: 1, color: PdfColors.black),
      pw.SizedBox(height: 2),
      pw.Divider(height: 1, thickness: 1, color: PdfColors.black),
    ],
  );

  pw.Widget _pointilles(pw.Widget enfant) => pw.Container(
    padding: const pw.EdgeInsets.symmetric(vertical: 3),
    decoration: const pw.BoxDecoration(
      border: pw.Border(
        bottom: pw.BorderSide(width: 0.8, style: pw.BorderStyle.dotted),
      ),
    ),
    child: enfant,
  );

  pw.Widget _tableau() {
    pw.Widget cellule(
      String t, {
      bool gras = false,
      pw.Alignment? al,
      PdfColor? couleur,
    }) => pw.Container(
      alignment: al ?? pw.Alignment.centerLeft,
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
      child: pw.Text(
        t,
        style: pw.TextStyle(
          fontSize: 9.5,
          fontWeight: gras ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: couleur,
        ),
      ),
    );
    return pw.Table(
      border: pw.TableBorder.all(width: 0.8),
      columnWidths: const {
        0: pw.FlexColumnWidth(46),
        1: pw.FlexColumnWidth(12),
        2: pw.FlexColumnWidth(21),
        3: pw.FlexColumnWidth(21),
      },
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: vertEnteteTableau),
          children: [
            cellule(colonnes[0], gras: true, couleur: PdfColors.white),
            cellule(
              colonnes[1],
              gras: true,
              al: pw.Alignment.center,
              couleur: PdfColors.white,
            ),
            cellule(
              colonnes[2],
              gras: true,
              al: pw.Alignment.center,
              couleur: PdfColors.white,
            ),
            cellule(
              colonnes[3],
              gras: true,
              al: pw.Alignment.center,
              couleur: PdfColors.white,
            ),
          ],
        ),
        for (final l in lignesTableau)
          pw.TableRow(
            children: [
              cellule(l[0]),
              cellule(l[1], al: pw.Alignment.center),
              cellule(l[2], al: pw.Alignment.centerRight),
              cellule(l[3], al: pw.Alignment.centerRight),
            ],
          ),
        pw.TableRow(
          children: [
            cellule(libelleTotal, gras: true),
            cellule(''),
            cellule(''),
            cellule(montantTotal, gras: true, al: pw.Alignment.centerRight),
          ],
        ),
      ],
    );
  }
}

final class ProformaA4 {
  const ProformaA4._();

  static ProformaA4Composee composer({
    required ProformasLocalData proforma,
    required List<LignesProformaLocalData> lignes,
    required EnteteEtablissement entete,
    required ReglagesDocuments reglages,
    required DateTime maintenant,
    Uint8List? signature,
    Uint8List? cachet,
  }) {
    final date = proforma.dateEmission ?? maintenant;
    final ville = (proforma.ville ?? '').trim();
    final rccm = (entete.rccm ?? '').trim();
    final ifu = (entete.ifu ?? '').trim();
    final tel = (entete.telephone ?? '').trim();
    final adresse = (entete.adresse ?? '').trim();
    final activites = reglages.activites;
    final facebook = reglages.facebook;
    final email = (entete.email ?? '').trim();

    String? aucun(String s, String Function(String) f) =>
        s.isEmpty ? null : _t(f(s));

    return ProformaA4Composee(
      logo: entete.logo,
      activites: aucun(activites, (s) => s),
      facebook: aucun(facebook, (s) => 'Facebook : $s'),
      email: aucun(email, (s) => 'E-mail : $s'),
      rccmIfu: rccm.isEmpty && ifu.isEmpty
          ? null
          : _t(
              [
                if (rccm.isNotEmpty) 'N°RCCM : $rccm',
                if (ifu.isNotEmpty) 'N°IFU : $ifu',
              ].join(' – '),
            ),
      contact: tel.isEmpty && adresse.isEmpty
          ? null
          : _t(
              '${tel.isEmpty ? '' : 'Tel : $tel'}'
              '${adresse.isEmpty ? '' : ' / Qtier : $adresse'}',
            ),
      villeDate: _t(
        '${ville.isEmpty ? 'Le ' : '$ville, le '}${dateLongueFr(date)}',
      ),
      titre: _t('FACTURE PROFORMA'),
      identification: [
        (_t('Réf.'), _t(proforma.numero ?? 'BROUILLON — non numérotée')),
        (_t('Client'), _t(proforma.clientNom)),
        (_t('IFU'), _t(proforma.clientIfu ?? '')),
        (_t('Tel'), _t(proforma.clientTelephone ?? '')),
        (_t('Objet'), _t(proforma.objet ?? '')),
      ],
      colonnes: [
        _t('DÉSIGNATION'),
        _t('Quantité'),
        _t('Prix unitaire (FCFA)'),
        _t('Montant (FCFA)'),
      ],
      lignesTableau: [
        for (final l in lignes)
          [
            _t(l.designation),
            _t('${l.quantite}'),
            _t(montantAvecEspaces(l.prixUnitaire)),
            _t(montantAvecEspaces(l.montant)),
          ],
      ],
      libelleTotal: _t('TOTAL'),
      montantTotal: _t(montantAvecEspaces(proforma.total)),
      arrete: _t('Arrêté la présente FACTURE PROFORMA à la somme de :'),
      montantEnLettres: _t(francsCfaEnLettres(proforma.total)),
      validite: proforma.valideJusquAu == null
          ? null
          : _t('Valable jusqu’au ${dateLongueFr(proforma.valideJusquAu!)}'),
      signature: BlocSignatureA4.depuis(
        reglages,
        raisonSociale: entete.raisonSociale ?? 'TATACORA AFRIQUE',
        signature: signature,
        cachet: cachet,
      ),
    );
  }

  static String _t(String s) => texteTicket(s);
}
