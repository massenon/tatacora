import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/format/formats.dart';
import '../../../core/impression/entete_a4.dart';
import '../../../core/impression/entete_etablissement.dart';
import '../../../core/impression/texte_ticket.dart';
import '../../../core/impression/visas.dart';
import '../domain/entities/carte_bar.dart';
import '../domain/entities/ventes_bar.dart';

/// Le document de l'onglet « Ventes du Bar » — traduction de
/// `tatacora-api/resources/views/pdf/carte-ventes.blade.php` (PA-197).
///
/// ## Le JEU FILTRÉ entier, et il DIT son filtre (PA-119)
///
/// Les lignes sont toutes celles du filtre (`BoissonsApi.toutesLesVentes`),
/// jamais la page affichée ; « Filtre appliqué » et le résumé — la phrase même
/// du compteur de l'écran, alimentée par les totaux du SERVEUR — les précèdent.
///
/// ## Le stock est celui du jour de l'ÉDITION
///
/// Et le document le dit (`ventes_stock_aide`). Un article hors carte, un
/// stock non consulté ou une absence de lien rendent « — » : aucun des trois
/// n'est un stock nul, et « 0 » se lirait comme une rupture (PA-129).
///
/// ## Un EXPORT : en-tête RG-19, zone de signatures, pied de rapport
///
/// Visas de la directive, comme le gabarit serveur (Directive §6, PA-194/195).
final class EtatVentesBar {
  const EtatVentesBar._();

  /// `carte_pwa.bar.onglet_ventes` — le titre de l'onglet et du document.
  static const titre = 'Ventes du Bar';

  static const aideStock =
      "Le stock affiché est celui d'aujourd'hui, jamais celui du jour de la vente.";

  /// Les colonnes du tableau de l'écran — les mêmes, clés comprises : les
  /// recopier autrement ferait redevenir « Stock actuel » un simple « Stock ».
  static const entetes = [
    'Date',
    'N° vente',
    'Article',
    'Stock actuel',
    'Prix unitaire',
    'Quantité',
    'Montant',
    'Statut',
    'Utilisateur',
  ];

  /// Une ligne du document, en chaînes — source unique du PDF et du CSV.
  static List<String> cellules(LigneVenteBar l, Map<String, LigneCarte> carte) {
    final article = l.code == null ? null : carte[l.code];
    final date = l.date;
    return [
      date == null
          ? '—'
          : '${formaterDate(date)} '
                '${date.hour.toString().padLeft(2, '0')}:'
                '${date.minute.toString().padLeft(2, '0')}',
      l.numero ?? '—',
      l.nom,
      article?.stock?.toStringAsFixed(0) ?? '—',
      formaterMontantDecimal(l.prixUnitaire, suffixe: 'FCFA') ?? '—',
      '${l.quantite}',
      formaterMontantDecimal(l.montant, suffixe: 'FCFA') ?? '—',
      l.annulee
          ? StatutVenteBar.annulee.libelle
          : StatutVenteBar.validee.libelle,
      l.utilisateur ?? '—',
    ];
  }

  static String resume(TotauxVentesBar totaux) => resumeVentes(
    totaux,
    formaterMontantDecimal(totaux.totalValide, suffixe: 'FCFA') ?? '—',
  );

  /// CSV — BOM UTF-8 et point-virgule (convention serveur RG-19). Les
  /// montants partent en NOMBRES BRUTS : un tableur ne sait pas additionner
  /// « 2 400 FCFA ».
  static String csv(
    List<LigneVenteBar> lignes,
    TotauxVentesBar totaux, {
    required String filtre,
    required List<LigneCarte> carte,
    String titreDocument = titre,
  }) {
    final parId = {for (final l in carte) l.id: l};
    String sans(String v) => v.replaceAll(';', ',');
    final tampon = StringBuffer('\u{FEFF}')
      ..writeln(sans(titreDocument))
      ..writeln(sans('Filtre appliqué : $filtre'))
      ..writeln(sans(resume(totaux)))
      ..writeln()
      ..writeln(entetes.map(sans).join(';'));

    for (final l in lignes) {
      final c = cellules(l, parId);
      tampon.writeln(
        [
          c[0],
          c[1],
          c[2],
          // Le stock : chiffre ou case VIDE — jamais « 0 », jamais « — »
          // dans un tableur qui l'additionnerait comme du texte.
          c[3] == '—' ? '' : c[3],
          l.prixUnitaire,
          '${l.quantite}',
          l.montant,
          c[7],
          c[8],
        ].map(sans).join(';'),
      );
    }
    return tampon.toString();
  }

  static List<int> csvOctets(
    List<LigneVenteBar> lignes,
    TotauxVentesBar totaux, {
    required String filtre,
    required List<LigneCarte> carte,
    String titreDocument = titre,
  }) => utf8.encode(
    csv(
      lignes,
      totaux,
      filtre: filtre,
      carte: carte,
      titreDocument: titreDocument,
    ),
  );

  static Future<Uint8List> pdf(
    List<LigneVenteBar> lignes,
    TotauxVentesBar totaux, {
    required String filtre,
    required List<LigneCarte> carte,
    EnteteEtablissement entete = const EnteteEtablissement(),
    DateTime? edition,
    String titreDocument = titre,
  }) async {
    final parId = {for (final l in carte) l.id: l};
    final editeLe = edition ?? DateTime.now();
    final document = pw.Document();

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        header: (c) =>
            enTeteA4(entete: entete, titre: titreDocument, sousTitre: filtre),
        footer: (c) => piedRapportA4(
          c.pageNumber,
          c.pagesCount,
          entete: entete,
          edition: editeLe,
        ),
        build: (contexte) => [
          pw.Text(
            texteTicket('Filtre appliqué : $filtre'),
            style: const pw.TextStyle(fontSize: 9),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            texteTicket(resume(totaux)),
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            texteTicket(aideStock),
            style: const pw.TextStyle(fontSize: 8),
          ),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
            ),
            cellStyle: const pw.TextStyle(fontSize: 8),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            cellAlignments: {
              for (var i = 3; i < entetes.length; i++)
                i: pw.Alignment.centerRight,
            },
            headers: entetes.map(texteTicket).toList(),
            data: [
              for (final l in lignes)
                cellules(l, parId).map(texteTicket).toList(),
            ],
          ),
          zoneSignaturesA4(visas: Visas.directive),
        ],
      ),
    );

    return document.save();
  }
}
