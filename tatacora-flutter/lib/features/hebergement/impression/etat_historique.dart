import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/format/formats.dart';
import '../../../core/impression/entete_a4.dart';
import '../../../core/impression/entete_etablissement.dart';
import '../../../core/impression/texte_ticket.dart';
import '../../../core/impression/visas.dart';
import '../domain/entities/historique_reservations.dart';

/// L'**état** « Historique des réservations » — PDF et CSV.
///
/// ## Ce module est un RENDU, et rien d'autre
///
/// Aucun calcul métier ici : les lignes et les indicateurs arrivent déjà
/// calculés par `filtrerHistorique` et `KpisHistorique`. Recalculer un total
/// au moment d'imprimer créerait une seconde vérité, et c'est le papier —
/// remis au client — qui l'emporterait sur l'écran.
///
/// ## ⚠ ÉCART ASSUMÉ : le maître exporte en Excel, ce module écrit un CSV
///
/// `historique-reservations.js` appelle `ExportEngine.excel(...)`, qui produit
/// un vrai classeur via SheetJS. Aucun équivalent n'est embarqué côté Flutter,
/// et en ajouter un est une décision de dépendance qui ne se prend pas en
/// passant.
///
/// Le CSV est retenu parce que c'est **déjà la convention du serveur** :
/// `GenerateurEtatService` (RG-19) exporte en PDF et en CSV, jamais en XLSX.
/// Excel ouvre nativement le fichier. Deux détails rendent cet accord réel
/// plutôt que théorique, et ils sont dans le code : le **BOM UTF-8**, sans
/// lequel « Réservations » s'affiche « RÃ©servations » dans Excel, et le
/// **point-virgule** comme séparateur, qu'attend un Excel en configuration
/// française.
///
/// Le bouton porte donc le mot du maître — « Excel » — pour un fichier `.csv`.
/// L'écart est inscrit au registre PA plutôt que masqué derrière un libellé
/// inventé.
///
/// @see prototype_v2/assets/js/historique-reservations.js — `etatExport()`
/// @see RG-19
final class EtatHistorique {
  const EtatHistorique({
    required this.lignes,
    required this.kpis,
    required this.periode,
    this.entete = const EnteteEtablissement(),
  });

  /// Composé depuis ce que l'écran affiche — **les mêmes lignes**, filtres
  /// compris. Un export qui repartirait de la base entière contredirait le
  /// tableau que l'utilisateur a sous les yeux au moment où il clique.
  factory EtatHistorique.composer({
    required List<LigneHistorique> lignes,
    required KpisHistorique kpis,
    required FiltreHistorique filtre,
    EnteteEtablissement entete = const EnteteEtablissement(),
  }) {
    final debut = filtre.debut;
    final fin = filtre.fin;

    return EtatHistorique(
      lignes: lignes,
      kpis: kpis,
      // Le maître écrit « Toutes périodes » quand aucune borne n'est posée —
      // et c'est une information : sans elle, un état partiel se lirait comme
      // un état complet.
      periode: (debut == null && fin == null)
          ? 'Toutes périodes'
          : 'Du ${debut == null ? '…' : formaterDate(debut)} '
                'au ${fin == null ? '…' : formaterDate(fin)}',
      entete: entete,
    );
  }

  static const String titre = 'Historique des réservations';

  /// Les en-têtes de colonnes, dans l'ordre du maître (`etatExport()`).
  static const List<String> entetes = [
    'Client',
    'Canal',
    'Arrivée',
    'Départ',
    'Nuits',
    'Unités',
    'Services',
    'Total',
    'Reste dû',
    'État',
  ];

  final List<LigneHistorique> lignes;
  final KpisHistorique kpis;
  final String periode;
  final EnteteEtablissement entete;

  /// Le même document sous l'en-tête lu des paramètres au moment d'éditer
  /// (`lireEnteteEtablissementProvider`).
  EtatHistorique avecEntete(EnteteEtablissement autre) => EtatHistorique(
    lignes: lignes,
    kpis: kpis,
    periode: periode,
    entete: autre,
  );

  /// Une ligne du tableau, en texte — **source unique** des deux rendus.
  ///
  /// Le PDF et le CSV partent d'ici : composer deux fois les mêmes cellules
  /// les ferait diverger, et personne ne compare un PDF à un CSV avant de les
  /// envoyer.
  List<String> cellules(LigneHistorique l) => [
    l.client,
    l.canal ?? '',
    formaterDate(l.reservation.periode.arrivee),
    formaterDate(l.reservation.periode.depart),
    '${l.nuits}',
    l.unites.join(' / '),
    l.services.map((s) => s.nom).join(' / '),
    '${l.totalAPayer}',
    '${l.resteAPayer}',
    l.etat.libelle,
  ];

  /// Les quatre indicateurs que le maître porte à l'état — pas les six de
  /// l'écran. Les comptes par état se lisent dans la colonne « État ».
  Map<String, String> get indicateurs => {
    'Réservations': '${kpis.total}',
    'Nuitées': '${kpis.nuitees}',
    'Chiffre d’affaires': formaterFcfa(kpis.chiffreAffaires),
    'Reste à encaisser': formaterFcfa(kpis.resteAEncaisser),
  };

  /* ================================================================== */
  /* CSV                                                                 */
  /* ================================================================== */

  /// Le fichier tableur, prêt à écrire.
  ///
  /// Les montants partent en **nombres bruts**, sans espace ni « FCFA » : un
  /// tableur ne sait pas additionner « 56 000 FCFA ». C'est ce que fait le
  /// maître, qui déclare `colonnesNumeriques: [4, 7, 8]`.
  String csv() {
    final tampon = StringBuffer()
      // Le BOM. Sans lui, Excel lit le fichier en ANSI et tous les accents
      // deviennent illisibles — un état qu'on n'ose pas envoyer au comptable.
      ..write('\u{FEFF}')
      ..writeln(_ligneCsv([titre]))
      ..writeln(_ligneCsv([periode]))
      ..writeln();

    for (final entree in indicateurs.entries) {
      tampon.writeln(_ligneCsv([entree.key, entree.value]));
    }
    tampon
      ..writeln()
      ..writeln(_ligneCsv(entetes));

    for (final l in lignes) {
      tampon.writeln(_ligneCsv(cellules(l)));
    }
    return tampon.toString();
  }

  /// Les octets à écrire sur le disque.
  Uint8List csvOctets() => Uint8List.fromList(utf8.encode(csv()));

  /// Point-virgule, et guillemets doublés quand la valeur en contient.
  ///
  /// La virgule serait le séparateur « standard », mais un Excel en
  /// configuration française l'attend en point-virgule — et c'est la
  /// configuration des postes du Gîte. Un fichier qui s'ouvre en une seule
  /// colonne passe pour cassé.
  static String _ligneCsv(List<String> valeurs) =>
      valeurs.map((v) => '"${v.replaceAll('"', '""')}"').join(';');

  /// Les textes **du PDF**, normalisés — et seulement ceux-là.
  ///
  /// ## Le défaut que cette méthode répare, constaté à l'exécution
  ///
  /// Les polices intégrées du format PDF couvrent Latin-1, pas davantage. La
  /// composition rendait donc, en clair : *« Unable to find a font to draw ’
  /// (U+2019) »* — l'apostrophe typographique de « Chiffre d'affaires ».
  /// Le document se sérialisait quand même : le caractère était simplement
  /// **absent du papier**, et rien à l'écran ne le disait. C'est la même
  /// décision que pour la facture A4 — normaliser, plutôt qu'embarquer une
  /// police de 300 ko sur un poste qui doit rester léger.
  ///
  /// Le CSV n'y passe PAS : il est écrit en UTF-8 avec son BOM, et l'apostrophe
  /// typographique y est parfaitement lisible. Normaliser des deux côtés
  /// dégraderait un fichier qui n'en a pas besoin.
  static String _t(String source) => texteTicket(source);

  /* ================================================================== */
  /* PDF                                                                 */
  /* ================================================================== */

  /// Le document, en A4 **paysage**.
  ///
  /// Dix colonnes ne tiennent pas en portrait : elles s'y écraseraient jusqu'à
  /// l'illisible, et le premier réflexe serait de retirer des colonnes de
  /// l'état — donc de l'information.
  Future<Uint8List> pdf() async {
    final doc = pw.Document();
    final logo = entete.logo;
    final editeLe = DateTime.now();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        // En-tete et pied viennent du point unique `core/impression/` :
        // les composer ici en ferait une seconde version, qui divergerait du
        // jour ou l'un des deux etats changerait (non-conformite n. 1 de
        // `RESPECT_TABLEAU_RAPPORT.md` §4).
        header: (context) => enTeteA4(
          entete: entete,
          titre: titre,
          sousTitre: periode,
          logo: logo,
        ),
        // Un EXPORT : pied de rapport et zone de signatures de la Directive
        // §6 (PA-195), comme `pdf/hebergement.blade.php` (historique).
        footer: (context) => piedRapportA4(
          context.pageNumber,
          context.pagesCount,
          entete: entete,
          edition: editeLe,
        ),
        build: (context) => [
          _indicateurs(),
          pw.SizedBox(height: 12),
          _tableau(),
          zoneSignaturesA4(visas: Visas.directive),
        ],
      ),
    );
    return doc.save();
  }

  pw.Widget _indicateurs() => pw.Row(
    children: [
      for (final entree in indicateurs.entries)
        pw.Expanded(
          child: pw.Container(
            margin: const pw.EdgeInsets.only(right: 6),
            padding: const pw.EdgeInsets.all(6),
            decoration: const pw.BoxDecoration(color: PdfColors.grey200),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  _t(entree.key.toUpperCase()),
                  style: const pw.TextStyle(fontSize: 7),
                ),
                pw.Text(
                  _t(entree.value),
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
    ],
  );

  pw.Widget _tableau() {
    if (lignes.isEmpty) {
      // Un état vide le DIT. Une page blanche laisserait croire à un document
      // tronqué, et l'utilisateur le rééditerait sans savoir quoi changer.
      return pw.Text(
        _t('Aucune réservation ne correspond à ces filtres.'),
        style: const pw.TextStyle(fontSize: 10),
      );
    }

    return pw.TableHelper.fromTextArray(
      headers: entetes.map(_t).toList(),
      data: [for (final l in lignes) cellules(l).map(_t).toList()],
      headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
      cellStyle: const pw.TextStyle(fontSize: 8),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
      cellAlignments: {
        4: pw.Alignment.centerRight,
        7: pw.Alignment.centerRight,
        8: pw.Alignment.centerRight,
      },
    );
  }
}
