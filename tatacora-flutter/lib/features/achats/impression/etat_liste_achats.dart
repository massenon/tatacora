/// Les exports des quatre listes de M7 — « Export Excel » et « Export PDF »
/// (`m7-approvisionnement.html` l.127-128, `barreOutils`).
///
/// ## Un export porte sur CE QUI EST AFFICHÉ, et il DIT sa portée (PA-119)
///
/// La règle est du maître lui-même (l.135-138) : *« l'export porte sur ce qui
/// est affiché, jamais sur la liste complète. Exporter autre chose que ce
/// qu'on voit est le défaut classique de ce genre de barre — et il ne se
/// remarque qu'une fois le fichier ouvert. »*
///
/// Ici s'ajoute un danger que le maître n'a pas : **deux de ces quatre listes
/// sont paginées par le serveur**. Un document qui montrerait 50 commandes sur
/// 213 sans le dire serait lu comme le registre entier, et quelqu'un décidérait
/// d'un règlement fournisseur sur cette base. [Portee] est donc **obligatoire**
/// et s'imprime sous le titre : le filtre appliqué, et le nombre de lignes
/// rapportées au total du serveur.
///
/// ## Une liste vide se REFUSE
///
/// Le maître refuse (l.157, l.167) : *« Rien a exporter : la liste filtree est
/// vide. »* Une page blanche remise au Gérant se lit comme « aucune commande »,
/// alors qu'elle veut dire « le filtre n'a rien retenu ».
///
/// ## Le tableur est un CSV
///
/// BOM UTF-8 et point-virgule — la convention du serveur (RG-19) et ce
/// qu'attend un Excel en configuration française. Le maître écrit « Excel » sur
/// le bouton ; l'écart est nommé, pas masqué (PA-111). Les colonnes de montants
/// partent en **nombres bruts** : un tableur ne sait pas additionner
/// « 56 000 FCFA ».
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/impression/entete_a4.dart';
import '../../../core/impression/entete_etablissement.dart';
import '../../../core/impression/texte_ticket.dart';
import '../../../core/impression/visas.dart';

/// Ce qu'un document dit de lui-même avant sa première ligne.
final class Portee {
  const Portee({
    required this.filtre,
    required this.lignesRapportees,
    required this.totalServeur,
  });

  /// Le filtre appliqué, en clair — « Statut : Envoyée · recherche « SODIS » ».
  /// « Aucun filtre » quand il n'y en a pas : le dire est une information, le
  /// taire en est une autre.
  final String filtre;

  final int lignesRapportees;

  /// Le total que le filtre retient. Égal au premier quand la
  /// liste n'est pas paginée.
  final int totalServeur;

  bool get estTronquee => lignesRapportees < totalServeur;

  /// La phrase imprimée sous le titre. Elle nomme la troncature **quand elle
  /// existe**, et seulement alors.
  String get mention {
    final base = '$filtre — $lignesRapportees ligne(s)';
    if (!estTronquee) return base;

    return '$base sur $totalServeur retenue(s) par le filtre. '
        'CE DOCUMENT NE PORTE PAS SUR LE REGISTRE ENTIER.';
  }
}

/// Une liste prête à exporter : des en-têtes, des lignes de texte, et une
/// portée qui dit ce qu'elle couvre.
final class ListeAchats {
  const ListeAchats({
    required this.titre,
    required this.portee,
    required this.entetes,
    required this.lignes,
    required this.visas,
    this.colonnesNumeriques = const {},
  });

  final String titre;

  /// Les visas de la zone de signatures — ceux du gabarit serveur du même
  /// document ([Visas.achats] ou [Visas.approvisionnement]). REQUIS : une
  /// liste ajoutée demain ne doit pas recevoir des visas par omission.
  final List<String> visas;
  final Portee portee;
  final List<String> entetes;

  /// Les cellules, **déjà en chaînes** — aucune conversion n'a lieu ici. Les
  /// montants sont ceux du serveur, au caractère près.
  final List<List<String>> lignes;

  /// Les index alignés à droite au PDF et écrits en nombre brut au CSV.
  final Set<int> colonnesNumeriques;

  bool get estVide => lignes.isEmpty;
}

/// Le refus opposé à un export vide — même mot que le maître (l.157).
const messageExportVide =
    'Rien à exporter : la liste filtrée est vide. Une page blanche se lirait '
    'comme « aucun élément », alors qu’elle veut dire « le filtre n’a rien '
    'retenu ».';

/// CSV — BOM UTF-8 et point-virgule.
String csvListeAchats(ListeAchats liste) {
  final tampon = StringBuffer('\u{FEFF}')
    ..writeln(_sansPointVirgule(liste.titre))
    ..writeln(_sansPointVirgule(liste.portee.mention))
    ..writeln()
    ..writeln(liste.entetes.map(_sansPointVirgule).join(';'));

  for (final ligne in liste.lignes) {
    tampon.writeln(ligne.map(_sansPointVirgule).join(';'));
  }

  return tampon.toString();
}

List<int> csvOctetsListeAchats(ListeAchats liste) =>
    utf8.encode(csvListeAchats(liste));

/// PDF A4, en-tête et pied par le point unique `core/impression/entete_a4.dart`.
Future<Uint8List> pdfListeAchats(
  ListeAchats liste, {
  EnteteEtablissement entete = const EnteteEtablissement(),
  DateTime? edition,
}) async {
  final document = pw.Document();
  final editeLe = edition ?? DateTime.now();

  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      header: (c) => enTeteA4(
        entete: entete,
        titre: liste.titre,
        sousTitre: liste.portee.mention,
      ),
      // Un EXPORT : pied de rapport et zone de signatures de la Directive §6
      // (PA-195), aux visas du gabarit serveur du même document.
      footer: (c) => piedRapportA4(
        c.pageNumber,
        c.pagesCount,
        entete: entete,
        edition: editeLe,
      ),
      build: (contexte) => [
        if (liste.portee.estTronquee) ...[
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(6),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(width: 1, color: PdfColors.red800),
            ),
            child: pw.Text(
              // La mention qui BORNE la portée s'imprime avec le document, pas
              // seulement à l'écran (même règle que la fiche de stock
              // incohérente, PA-135) : sinon le papier circule débarrassé de la
              // seule phrase qui en limite la lecture.
              texteTicket(
                'Ce document ne porte que sur les '
                '${liste.portee.lignesRapportees} ligne(s) affichees, sur '
                '${liste.portee.totalServeur} retenue(s) par le filtre.',
              ),
              style: pw.TextStyle(
                fontSize: 9,
                color: PdfColors.red800,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.SizedBox(height: 10),
        ],
        pw.TableHelper.fromTextArray(
          headerStyle: pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
          ),
          cellStyle: const pw.TextStyle(fontSize: 8),
          cellAlignments: {
            for (final i in liste.colonnesNumeriques)
              i: pw.Alignment.centerRight,
          },
          headers: liste.entetes.map(texteTicket).toList(),
          data: [
            for (final ligne in liste.lignes)
              ligne.map(texteTicket).toList(growable: false),
          ],
        ),
        zoneSignaturesA4(visas: liste.visas),
      ],
    ),
  );

  return document.save();
}

/// Le point-virgule est le séparateur du CSV : le laisser dans une cellule
/// décalerait toutes les colonnes suivantes, en silence.
String _sansPointVirgule(String texte) => texte.replaceAll(';', ',');
