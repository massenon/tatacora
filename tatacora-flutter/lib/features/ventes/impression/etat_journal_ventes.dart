// Vue Blade maîtresse (PA-183) : pwa/pos/historique-ventes.blade.php
/// Les deux documents du journal des ventes.
///
///  - [EtatJournalVentes] — la liste, « Export Excel » et « Export PDF »
///    (`prototype_v2/pages/historique-ventes.html` l.52-53) ;
///  - [EtatVente] — une vente, « Télécharger » de la modale Détail (l.316).
///
/// ## Un export porte sur CE QUI EST AFFICHÉ, et il DIT son filtre (PA-119)
///
/// La règle est du maître, écrite au-dessus de ses deux boutons (l.366) :
/// *« L'export porte sur CE QUI EST AFFICHÉ, jamais sur la liste complète. »*
/// Quelqu'un qui filtre sur les ventes annulées de juillet et clique sur
/// « Export PDF » attend les ventes annulées de juillet ; lui rendre le journal
/// entier lui ferait envoyer au comptable un document qu'il croit avoir
/// vérifié. [FiltreVentes.mention] s'imprime donc sous le titre, et elle dit
/// « Aucun filtre » quand il n'y en a pas — le taire est une information de
/// moins.
///
/// ## Une liste vide se REFUSE
///
/// Le maître refuse (l.372, l.377) : *« Rien à exporter : la liste filtrée est
/// vide. »* Une page blanche remise au Gérant se lit comme « aucune vente »,
/// alors qu'elle veut dire « le filtre n'a rien retenu ».
///
/// ## ⚠ Aucune mention de certification n'est FIGÉE, et une vente n'en affirme
/// aucune
///
/// PA-119. La mention se **dérive des pièces** : combien de ventes du document
/// portent réellement une facture. Une vente sans facture ne dit rien de
/// fiscal — ni « certifiée », ni « non certifiée », qui laisserait croire
/// qu'une pièce existe et qu'elle attend son cachet. Et quand une facture
/// existe, la phrase vient de `CertificationMecef`, jamais d'une chaîne écrite
/// ici : le jour de l'inscription DGI (PA-17), elle changera parce que les
/// pièces auront changé.
///
/// ## Le tableur est un CSV
///
/// BOM UTF-8 et point-virgule — convention du serveur (RG-19) et ce qu'attend
/// un Excel en configuration française. Le maître écrit « Excel » sur le
/// bouton ; l'écart est nommé, pas masqué (PA-111). Les colonnes de montants
/// partent en **nombres bruts** : un tableur ne sait pas additionner
/// « 56 000 FCFA ».
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/format/formats.dart';
import '../../../core/impression/entete_a4.dart';
import '../../../core/impression/entete_etablissement.dart';
import '../../../core/impression/texte_ticket.dart';
import '../../../core/impression/visas.dart';
import '../../facturation/domain/certification_mecef.dart';
import '../domain/entities/vente.dart';
import '../domain/journal_ventes.dart';

/// Le refus opposé à un export vide — **le mot du maître** (l.372).
const messageExportVentesVide = 'Rien à exporter : la liste filtrée est vide.';

/// Ce qu'un document du journal dit de lui-même avant sa première ligne.
///
/// La phrase de certification est **dérivée**, jamais posée : elle compte les
/// ventes qui portent réellement une facture parmi celles du document.
String mentionPiecesFiscales({required int ventes, required int avecFacture}) {
  if (ventes == 0) return 'Aucune vente';
  if (avecFacture == 0) {
    // Ni « certifiées » ni « non certifiées » : il n'y a aucune pièce. Écrire
    // « non certifiées » laisserait croire qu'une facture existe et qu'elle
    // attend son cachet.
    return 'Aucune facture émise pour ces ventes';
  }
  return '$avecFacture vente(s) sur $ventes avec facture — '
      '${CertificationMecef.libelleDemonstration}';
}

/// L'état **« Historique des ventes »** — la liste filtrée.
final class EtatJournalVentes {
  const EtatJournalVentes({
    required this.ventes,
    required this.kpis,
    required this.filtre,
    this.entete = const EnteteEtablissement(),
  });

  /// Composé depuis ce que l'écran affiche — **les mêmes ventes, les mêmes
  /// indicateurs**. Recalculer ici créerait une seconde vérité, et c'est le
  /// papier qui l'emporterait sur l'écran.
  factory EtatJournalVentes.composer({
    required List<Vente> ventes,
    required FiltreVentes filtre,
    EnteteEtablissement entete = const EnteteEtablissement(),
  }) => EtatJournalVentes(
    ventes: ventes,
    kpis: KpisJournalVentes.calculer(ventes),
    filtre: filtre.mention,
    entete: entete,
  );

  /// Le titre de l'EN-TÊTE D'IMPRESSION de la vue
  /// (`pwa/pos/historique-ventes.blade.php` l.71, `pos_pwa.document.journal_titre`)
  /// — celui du PDF serveur `pdf/ventes-rapport` aussi. « Historique des
  /// ventes » est le titre de l'ÉCRAN ; il figurait ici jusqu'au 11/09/2026
  /// (PA-195).
  static const String titre = 'JOURNAL DES VENTES';

  /// Les huit colonnes du maître (l.354), dans son ordre.
  ///
  /// Sans accent sur « Reglement » et « Encaisse » : ce sont les libellés
  /// **du maître**, qui les écrit ainsi parce que les polices intégrées du
  /// format PDF ne portent pas tout le Latin étendu. Les « corriger » ici
  /// ferait diverger le document du maître sans rien gagner.
  static const List<String> entetes = [
    'N°',
    'Date',
    'Poste',
    'Table',
    'Reglement',
    'Montant',
    'Encaisse',
    'Statut',
  ];

  /// Le maître aligne à droite la seule colonne de montant (`[5]`).
  static const Set<int> colonnesNumeriques = {5};

  final List<Vente> ventes;
  final KpisJournalVentes kpis;

  /// Ce qui est filtré, dit en clair sur le document.
  final String filtre;

  final EnteteEtablissement entete;

  /// Le même état sous un autre en-tête — celui lu des paramètres au moment
  /// d'éditer (`lireEnteteEtablissementProvider`).
  EtatJournalVentes avecEntete(EnteteEtablissement autre) => EtatJournalVentes(
    ventes: ventes,
    kpis: kpis,
    filtre: filtre,
    entete: autre,
  );

  bool get estVide => ventes.isEmpty;

  /// Une ligne du tableau — **source unique** des deux rendus. Deux
  /// constructions donneraient deux documents pour une seule liste.
  List<String> cellules(Vente v) => [
    v.referenceLocale,
    formaterDate(v.date),
    v.pointVente ?? '',
    v.tableLibelle ?? '',
    v.mode?.libelle ?? 'non renseigné',
    // Nombre BRUT : un tableur ne sait pas additionner « 56 000 FCFA ».
    '${v.montant}',
    switch (v.encaisse) {
      // Les deux mots du maître (l.360).
      true => 'oui',
      false => 'non (note)',
      // Le troisième cas, que le maître n'a pas : le ranger avec l'un des deux
      // affirmerait un état que personne n'a vérifié.
      null => 'inconnu',
    },
    v.statut.code,
  ];

  /// Les indicateurs du PDF du maître (l.379-383), plus la mention des pièces.
  Map<String, String> get indicateurs => {
    'Ventes': '${kpis.ventes}',
    'Chiffre d’affaires': formaterFcfa(kpis.chiffreAffaires),
    'Encaisse': formaterFcfa(kpis.encaisse),
    'Pièces fiscales': mentionPiecesFiscales(
      ventes: ventes.length,
      avecFacture: kpis.avecFacture,
    ),
  };

  /* ================================================================== */
  /* CSV                                                                 */
  /* ================================================================== */

  String csv() {
    final tampon = StringBuffer('\u{FEFF}')
      ..writeln(_ligneCsv([titre]))
      ..writeln(_ligneCsv([filtre]))
      ..writeln();

    for (final entree in indicateurs.entries) {
      tampon.writeln(_ligneCsv([entree.key, entree.value]));
    }
    tampon
      ..writeln()
      ..writeln(_ligneCsv(entetes));

    for (final v in ventes) {
      tampon.writeln(_ligneCsv(cellules(v)));
    }
    return tampon.toString();
  }

  Uint8List csvOctets() => Uint8List.fromList(utf8.encode(csv()));

  /* ================================================================== */
  /* PDF                                                                 */
  /* ================================================================== */

  Future<Uint8List> pdf() async {
    final document = pw.Document();
    final editeLe = DateTime.now();

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        header: (c) => enTeteA4(
          entete: entete,
          titre: titre,
          sousTitre: filtre,
          logo: entete.logo,
        ),
        // Un EXPORT : pied de rapport et zone de signatures de la Directive
        // §6 (PA-195), aux visas de `pdf/ventes-rapport.blade.php`. Le
        // « Détail de la vente », plus bas, est remis au client : il n'en a pas.
        footer: (c) => piedRapportA4(
          c.pageNumber,
          c.pagesCount,
          entete: entete,
          edition: editeLe,
        ),
        build: (c) => [
          _bandeIndicateurs(indicateurs),
          pw.SizedBox(height: 10),
          if (estVide)
            // Second rideau : l'écran refuse déjà d'exporter une liste vide.
            // Le document DIT plutôt que de rendre une page blanche, qu'on
            // prendrait pour un journal réellement vide.
            pw.Text(
              texteTicket('Aucune vente ne correspond à ces critères.'),
              style: const pw.TextStyle(fontSize: 10),
            )
          else
            pw.TableHelper.fromTextArray(
              headers: entetes.map(texteTicket).toList(),
              data: [
                for (final v in ventes) cellules(v).map(texteTicket).toList(),
              ],
              headerStyle: pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
              ),
              cellStyle: const pw.TextStyle(fontSize: 8),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.grey300,
              ),
              cellAlignments: {
                for (final i in colonnesNumeriques) i: pw.Alignment.centerRight,
              },
            ),
          zoneSignaturesA4(visas: Visas.journalVentes),
        ],
      ),
    );

    return document.save();
  }
}

/// Le document d'**une** vente — « Télécharger » de la modale Détail.
///
/// ⚠ **Ce n'est ni un ticket de caisse ni une facture**, et le titre le dit.
/// Le maître l'intitule « Vente V-2026-00016 ». Ici, ni numéro de séquence ni
/// cachet MECeF : intituler ce papier « Facture » ou « Ticket » en ferait un
/// faux document fiscal — la version papier de PA-61, déjà tranchée pour la
/// confirmation de réservation (PA-113). Le titre est donc « Détail de la
/// vente », et le corps porte la mention qui borne sa portée.
///
/// Quand la vente porte réellement une facture, son numéro est **rappelé** —
/// c'est ce qui permet d'aller chercher la pièce au registre, sans que ce
/// papier prétende en être une.
final class EtatVente {
  const EtatVente({
    required this.vente,
    this.entete = const EnteteEtablissement(),
  });

  final Vente vente;
  final EnteteEtablissement entete;

  /// Le même document sous l'en-tête lu des paramètres.
  EtatVente avecEntete(EnteteEtablissement autre) =>
      EtatVente(vente: vente, entete: autre);

  static const String titre = 'Détail de la vente';

  /// La mention qui BORNE la portée du document, imprimée avec lui — jamais
  /// seulement affichée (même règle que la fiche de stock incohérente,
  /// PA-135) : sinon le papier circule débarrassé de la seule phrase qui en
  /// limite la lecture.
  String get mentionPortee => vente.aUneFacture
      ? 'Ce document ne vaut pas facture. La facture de cette vente porte le '
            'numéro ${vente.numeroFacture}.'
      : 'Ce document ne vaut pas facture : aucune facture n’a été émise pour '
            'cette vente.';

  /// Les cinq colonnes du maître (l.336).
  static const List<String> entetes = [
    'Article',
    'Activite',
    'Quantite',
    'Prix unitaire',
    'Montant',
  ];

  /// Les colonnes que la vue aligne à droite (`pwa/pos/historique-ventes.blade.php`
  /// l.404-405). « Quantité » n'en est PAS : la vue la CENTRE (l.403) — voir
  /// [colonnesCentrees] (PA-185).
  static const Set<int> colonnesNumeriques = {3, 4};

  /// La colonne que la vue centre (l.403) : « Quantité ».
  static const Set<int> colonnesCentrees = {2};

  List<String> cellules(LigneVente l) => [
    l.libelle,
    l.module.libelle,
    '${l.quantite}',
    '${l.prixUnitaire}',
    '${l.montant}',
  ];

  /// Les trois indicateurs du maître (l.331-335).
  Map<String, String> get indicateurs => {
    'Poste': vente.pointVente ?? vente.clientNom ?? '—',
    'Reglement': vente.mode?.libelle ?? 'non renseigné',
    'Total': formaterFcfa(vente.montant),
  };

  Future<Uint8List> pdf() async {
    final document = pw.Document();

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        header: (c) => enTeteA4(
          entete: entete,
          titre: titre,
          sousTitre: '${vente.referenceLocale} · ${formaterDate(vente.date)}',
          logo: entete.logo,
        ),
        footer: (c) => piedA4(c.pageNumber, c.pagesCount),
        build: (c) => [
          _bandeIndicateurs(indicateurs),
          pw.SizedBox(height: 10),
          _encadre(mentionPortee),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headers: entetes.map(texteTicket).toList(),
            data: [
              for (final l in vente.lignes)
                cellules(l).map(texteTicket).toList(),
            ],
            headerStyle: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
            ),
            cellStyle: const pw.TextStyle(fontSize: 8),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            cellAlignments: {
              for (final i in colonnesCentrees) i: pw.Alignment.center,
              for (final i in colonnesNumeriques) i: pw.Alignment.centerRight,
            },
          ),
          if (vente.encaisse == false) ...[
            pw.SizedBox(height: 10),
            // La phrase du maître (l.298-301), imprimée et non seulement
            // affichée : c'est elle qui empêche de lire ce papier comme un reçu.
            _encadre(
              'Porté en note de chambre : ce montant n’est PAS dans le tiroir. '
              'Il devient une créance, réglée au départ du client.',
            ),
          ],
          if (vente.encaisse == null) ...[
            pw.SizedBox(height: 10),
            _encadre(
              'Mode de règlement non renseigné : ce document ne dit pas si le '
              'montant est entré en caisse.',
            ),
          ],
          if (vente.estAnnulee) ...[
            pw.SizedBox(height: 10),
            _encadre(
              'Vente annulée'
              '${vente.motifAnnulation == null ? '' : ' — ${vente.motifAnnulation}'}. '
              'Elle reste au journal : rien n’est effacé. Aucun montant n’a été '
              'encaissé puis rendu — le service a été abandonné avant paiement.',
            ),
          ],
        ],
      ),
    );

    return document.save();
  }
}

/* ====================================================================== */
/* Briques communes aux deux documents                                     */
/* ====================================================================== */

pw.Widget _bandeIndicateurs(Map<String, String> indicateurs) => pw.Row(
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
                texteTicket(entree.key.toUpperCase()),
                style: const pw.TextStyle(fontSize: 7),
              ),
              pw.Text(
                texteTicket(entree.value),
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
  ],
);

pw.Widget _encadre(String texte) => pw.Container(
  width: double.infinity,
  padding: const pw.EdgeInsets.all(6),
  decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.8)),
  child: pw.Text(
    // Tout texte d'un PDF passe par `texteTicket` : les polices intégrées
    // couvrent Latin-1 et rien de plus, et l'apostrophe typographique de
    // « Chiffre d'affaires » disparaissait réellement du papier.
    texteTicket(texte),
    style: const pw.TextStyle(fontSize: 9),
  ),
);

String _ligneCsv(List<String> valeurs) =>
    valeurs.map((v) => '"${v.replaceAll('"', '""')}"').join(';');
