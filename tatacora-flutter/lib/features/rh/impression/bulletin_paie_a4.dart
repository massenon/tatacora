// Vue Blade maîtresse (PA-183) : pwa/rh/paie.blade.php
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/format/formats.dart' show formaterDate, formaterFcfa;
import '../../../core/impression/entete_a4.dart';
import '../../../core/impression/entete_etablissement.dart';
import '../../../core/impression/texte_ticket.dart';
import '../domain/entities/bulletin_paie.dart';
import '../domain/services/bulletin_paie_service.dart';

/// Le **bulletin de paie sur papier A4** — `Paie::exporterPdf` et son gabarit
/// `pdf/paie-bulletin.blade.php`, le papier des boutons « Imprimer » et « PDF »
/// de la modale du bulletin.
///
/// ## Un document REMIS AU SALARIÉ
///
/// Comme le gabarit serveur, il ne porte NI zone de signatures NI pied de
/// rapport : un bulletin se remet, il ne s'ordonnance pas. Il se classe donc
/// parmi les documents remis de `pdf_directive_test.dart`, au pied NEUTRE
/// ([piedA4], pagination). Son pied de texte est celui du gabarit : la phrase
/// `rh_pwa.bulletin_pied`, un tiret, puis le login de qui édite.
///
/// ## Il n'invente AUCUN montant
///
/// Tout vient des colonnes FIGÉES du bulletin (`BulletinPaie`) et du coût
/// employeur du [RecapitulatifBulletin] : le papier ne recalcule rien, un
/// bulletin réimprimé six mois plus tard porte les mêmes chiffres. Le coût
/// employeur y reste une FOURCHETTE (PA-53) : le taux de risques professionnels
/// n'est pas confirmé pour l'hôtellerie-restauration.
///
/// ## Aucun IFU, aucun RCCM, aucun cachet
///
/// `enTeteA4` écarte les identifiants fiscaux non renseignés ; un bulletin n'est
/// pas une facture.
///
/// ## Écarts nommés
///
/// * « Imprimer » est, au web, `window.print()` sur la modale ; ici c'est la
///   boîte d'impression du système avec CE même papier A4 (le poste n'a pas de
///   navigateur dont imprimer la fenêtre).
/// * Le gabarit serveur compose l'en-tête avec `ReportHeaderService` ; ici c'est
///   `EnteteEtablissement`, lu des mêmes paramètres.
final class BulletinPaieA4 {
  const BulletinPaieA4({
    required this.recapitulatif,
    required this.periodeLongue,
    required this.auteur,
    this.entete = const EnteteEtablissement(),
  });

  final RecapitulatifBulletin recapitulatif;

  /// « septembre 2026 » (`periodeLongue`).
  final String periodeLongue;

  /// Le login de qui édite (`$utilisateur->login`) ; `null` : « — ».
  final String? auteur;

  final EnteteEtablissement entete;

  /// Le même document sous l'en-tête lu des paramètres au moment d'éditer.
  BulletinPaieA4 avecEntete(EnteteEtablissement autre) => BulletinPaieA4(
    recapitulatif: recapitulatif,
    periodeLongue: periodeLongue,
    auteur: auteur,
    entete: autre,
  );

  BulletinPaie get bulletin => recapitulatif.bulletin;

  /// Le nom du fichier téléchargé : `bulletin_<numero>` (`bulletin_BUL-…`).
  String get prefixeFichier => 'bulletin_${bulletin.numero}';

  // --- Les mots du gabarit (`lang/fr/rh_pwa.php`) ---------------------------
  static const String titre = 'BULLETIN DE PAIE';
  static const String salarie = 'Salarié';
  static const String affectation = 'Affectation';
  static const String cnssAbsent = 'non communiqué';
  static const List<String> colonnes = [
    'Désignation',
    'Base',
    'Taux',
    'Gain',
    'Retenue',
  ];
  static const String brutLibelle = 'Salaire brut soumis à cotisations';
  static const String cnssSalarialeLibelle = 'CNSS — cotisation salariale';
  static const String imposableLibelle = 'Revenu imposable (brut − CNSS)';
  static const String itsLibelle =
      'ITS — Impôt sur les Traitements et Salaires';
  static const String autresLibelle = 'Autres retenues';
  static const String netLibelle = 'NET À PAYER';
  static const String patronalesTitre =
      'Charges patronales — à la charge de l’employeur, hors bulletin salarié';
  static const String confirmeesLibelle = 'Total charges patronales confirmées';
  static const String rpLibelle = 'CNSS — risques professionnels';
  static const String coutTotalLibelle = 'Coût total employeur';

  /// `rh_pwa.bulletin_note_rp` SANS ses balises (`<strong>` : le gras n'est pas
  /// rendu dans la note, le texte est le même).
  static const String noteRp =
      'Le taux de risques professionnels dépend du niveau de risque de '
      'l’entreprise et n’est pas confirmé pour l’hôtellerie-restauration. Il '
      'n’est pas supposé : le coût est donné en fourchette. Le VPS et les '
      'cotisations CNSS ci-dessus sont, eux, confirmés. Le VPS est dû par '
      'l’employeur — il n’apparaît jamais en retenue sur salaire.';
  static const String pied =
      'Les montants sont calculés, aucun n’est saisi. Document à conserver '
      'sans limitation de durée.';

  static String matricule(String valeur) => 'Matricule $valeur';
  static String cnss(String valeur) => 'N° CNSS $valeur';
  static String etabliLe(String date) => 'Établi le $date';
  static String annule(String motif) => 'Annulé — $motif';

  /// La fourchette « min — max » (`MontantFcfa::format(min) — …`).
  static String fourchette(int min, int max) =>
      '${formaterFcfa(min)} — ${formaterFcfa(max)}';

  static String _t(String source) => texteTicket(source);

  pw.Widget _texte(
    String valeur, {
    bool gras = false,
    double taille = 8.5,
    PdfColor? couleur,
    pw.TextAlign align = pw.TextAlign.left,
  }) => pw.Text(
    _t(valeur),
    textAlign: align,
    style: pw.TextStyle(
      fontSize: taille,
      fontWeight: gras ? pw.FontWeight.bold : pw.FontWeight.normal,
      color: couleur,
    ),
  );

  pw.Widget _encart(String etiquette, List<pw.Widget> enfants) => pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    decoration: pw.BoxDecoration(
      color: PdfColors.grey100,
      border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _texte(etiquette.toUpperCase(), taille: 7.5, gras: true),
        pw.SizedBox(height: 3),
        ...enfants,
      ],
    ),
  );

  pw.TableRow _ligne(
    List<String> cellules, {
    bool sousTotal = false,
    bool fort = false,
  }) {
    final fond = fort
        ? PdfColors.blueGrey900
        : (sousTotal ? PdfColors.grey200 : null);
    return pw.TableRow(
      decoration: pw.BoxDecoration(color: fond),
      children: [
        for (final (i, c) in cellules.indexed)
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
            child: _texte(
              c,
              gras: sousTotal || fort,
              couleur: fort ? PdfColors.white : null,
              align: i == 0 ? pw.TextAlign.left : pw.TextAlign.right,
            ),
          ),
      ],
    );
  }

  pw.Widget _tableau() {
    final b = bulletin;
    final brut = formaterFcfa(b.brut);
    return pw.Table(
      border: const pw.TableBorder(
        bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
        horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
      ),
      columnWidths: const {
        0: pw.FlexColumnWidth(5),
        1: pw.FlexColumnWidth(2),
        2: pw.FlexColumnWidth(1),
        3: pw.FlexColumnWidth(2),
        4: pw.FlexColumnWidth(2),
      },
      children: [
        _ligne(colonnes, sousTotal: true),
        _ligne([brutLibelle, '', '', brut, ''], sousTotal: true),
        _ligne([
          cnssSalarialeLibelle,
          brut,
          '',
          '',
          formaterFcfa(b.cnssSalarie),
        ]),
        _ligne([
          imposableLibelle,
          '',
          '',
          formaterFcfa(b.revenuImposable),
          '',
        ], sousTotal: true),
        _ligne([itsLibelle, '', '', '', formaterFcfa(b.its)]),
        if (b.autresRetenues > 0)
          _ligne([autresLibelle, '', '', '', formaterFcfa(b.autresRetenues)]),
        _ligne([netLibelle, '', '', formaterFcfa(b.netAPayer), ''], fort: true),
      ],
    );
  }

  pw.Widget _patronales() {
    final b = bulletin;
    final cout = recapitulatif.cout;
    pw.Widget ligne(String libelle, String valeur, {bool gras = false}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 2),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _texte(libelle, gras: gras),
              _texte(valeur, gras: true, align: pw.TextAlign.right),
            ],
          ),
        );
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 12),
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: PdfColors.amber50,
        border: pw.Border.all(color: PdfColors.amber200, width: 0.5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _texte(patronalesTitre.toUpperCase(), taille: 7.5, gras: true),
          ligne(confirmeesLibelle, formaterFcfa(b.chargesPatronalesConfirmees)),
          ligne(rpLibelle, fourchette(cout.rpMin, cout.rpMax), gras: true),
          ligne(
            coutTotalLibelle,
            fourchette(cout.coutMin, cout.coutMax),
            gras: true,
          ),
          pw.SizedBox(height: 4),
          _texte(noteRp, taille: 7.5),
        ],
      ),
    );
  }

  /// Le PDF A4 portrait — le papier de « Imprimer » comme de « PDF ».
  ///
  /// [compresse] n'est à `false` que pour les essais, qui relisent les textes
  /// dans les octets du document.
  Future<Uint8List> pdf({bool compresse = true}) async {
    final doc = pw.Document(compress: compresse);
    final b = bulletin;
    final e = b.employe;

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        header: (context) => enTeteA4(
          entete: entete,
          titre: titre,
          sousTitre: '$periodeLongue · ${b.numero}',
          logo: entete.logo,
        ),
        // Pied NEUTRE d'un document remis : jamais le pied de rapport.
        footer: (context) => pw.Column(
          children: [
            _texte(
              '$pied — ${auteur ?? '—'}',
              taille: 7.5,
              align: pw.TextAlign.center,
            ),
            piedA4(context.pageNumber, context.pagesCount),
          ],
        ),
        build: (context) => [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: _encart(salarie, [
                  _texte(e.nomComplet(), gras: true),
                  _texte(e.poste),
                  _texte(matricule(e.matricule)),
                  _texte(
                    cnss(e.sansNumeroCnss ? cnssAbsent : (e.numeroCnss ?? '')),
                  ),
                ]),
              ),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: _encart(affectation, [
                  _texte(e.serviceLibelle ?? '—'),
                  _texte(etabliLe(formaterDate(b.etabliLe))),
                  if (b.estAnnule)
                    _texte(
                      annule(b.motifAnnulation ?? ''),
                      gras: true,
                      couleur: PdfColors.red700,
                    ),
                ]),
              ),
            ],
          ),
          pw.SizedBox(height: 12),
          _tableau(),
          _patronales(),
        ],
      ),
    );
    return doc.save();
  }
}
