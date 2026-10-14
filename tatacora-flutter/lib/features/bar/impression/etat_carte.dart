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

/// Les documents de la carte du bar — `m5-bar-carte.html` l.36-45.
///
/// ## DEUX documents, pas deux formats du même
///
/// Le maître le commente en toutes lettres : le bouton « PDF » exporte le
/// **tableau de gestion**, qui se consulte ; « Imprimer la fiche des prix »
/// rend un document qui **se lit**, groupé par catégorie, destiné au comptoir
/// et au client. Les fondre en un seul laisserait croire à un seul usage.
///
/// C'est le même raisonnement que ticket et facture (PA-101) : deux papiers
/// pour la même matière, et le domaine ne connaît ni l'un ni l'autre.
final class EtatCarteBar {
  const EtatCarteBar._();

  static const titre = 'Carte du bar';
  static const titreFiche = 'Fiche des prix — Bar';

  /// CSV du tableau — BOM UTF-8 et point-virgule (convention serveur RG-19).
  static String csv(List<LigneCarte> lignes, {required String filtre}) {
    final tampon = StringBuffer('﻿')
      ..writeln('$titre;${filtre.replaceAll(';', ',')}')
      ..writeln()
      ..writeln('Article;Categorie;Prix;Lie au stock;Stock');

    for (final l in lignes) {
      tampon.writeln(
        [
          l.libelle.replaceAll(';', ','),
          l.categorie.replaceAll(';', ','),
          // Nombre brut : un tableur ne sait pas additionner « 1 000 FCFA ».
          l.prix,
          l.estLieAuStock ? 'oui' : 'non',
          // Une case vide dit « on ne sait pas » ; un zero dirait « rupture ».
          l.stock?.toStringAsFixed(0) ?? '',
        ].join(';'),
      );
    }

    return tampon.toString();
  }

  static List<int> csvOctets(
    List<LigneCarte> lignes, {
    required String filtre,
  }) => utf8.encode(csv(lignes, filtre: filtre));

  /// Le **tableau de gestion** — ce que l'écran affiche, filtres compris.
  static Future<Uint8List> pdf(
    List<LigneCarte> lignes, {
    required String filtre,
    EnteteEtablissement entete = const EnteteEtablissement(),
    DateTime? edition,
  }) async {
    final document = pw.Document();
    final editeLe = edition ?? DateTime.now();

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        header: (c) =>
            enTeteA4(entete: entete, titre: titre, sousTitre: filtre),
        // Un EXPORT : pied de rapport et zone de signatures de la Directive §6
        // (PA-195), comme `pdf/carte.blade.php`.
        footer: (c) => piedRapportA4(
          c.pageNumber,
          c.pagesCount,
          entete: entete,
          edition: editeLe,
        ),
        build: (contexte) => [
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
            ),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellAlignments: {2: pw.Alignment.centerRight},
            headers: [
              'Article',
              'Categorie',
              'Prix',
              'Stock',
            ].map(texteTicket).toList(),
            data: [
              for (final l in lignes)
                [
                  texteTicket(l.libelle),
                  texteTicket(l.categorie),
                  texteTicket(l.sansPrix ? 'sans tarif' : formaterFcfa(l.prix)),
                  texteTicket(
                    l.stock?.toStringAsFixed(0) ??
                        (l.estLieAuStock ? 'non consulte' : 'sans lien'),
                  ),
                ],
            ],
          ),
          zoneSignaturesA4(visas: Visas.directive),
        ],
      ),
    );

    return document.save();
  }

  /// La **fiche des prix** : un document qui se lit, groupé par catégorie.
  ///
  /// **Les articles sans tarif en sont écartés, et leur nombre est rendu.** La
  /// règle est du maître, et sa raison y est écrite : *« on ne masque pas : un
  /// tarif absent devient négociable au comptoir »*. Les écarter en silence
  /// produirait une fiche qui a l'air complète ; les imprimer à zéro ferait
  /// croire à la gratuité.
  static Future<(Uint8List, int)> ficheDesPrix(
    List<LigneCarte> lignes, {
    EnteteEtablissement entete = const EnteteEtablissement(),
  }) async {
    final retenues = lignes.where((l) => !l.sansPrix).toList()
      ..sort((a, b) {
        final parCategorie = a.categorie.compareTo(b.categorie);
        return parCategorie != 0
            ? parCategorie
            : a.libelle.compareTo(b.libelle);
      });
    final ecartes = lignes.length - retenues.length;

    final parCategorie = <String, List<LigneCarte>>{};
    for (final l in retenues) {
      parCategorie.putIfAbsent(l.categorie, () => []).add(l);
    }

    final document = pw.Document();
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        header: (c) => enTeteA4(
          entete: entete,
          titre: titreFiche,
          sousTitre: 'Tarifs en vigueur',
        ),
        footer: (c) => piedA4(c.pageNumber, c.pagesCount),
        build: (contexte) => [
          for (final entree in parCategorie.entries) ...[
            pw.Text(
              texteTicket(
                entree.key.isEmpty ? 'Autres' : entree.key.toUpperCase(),
              ),
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            for (final l in entree.value)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 2),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      texteTicket(l.libelle),
                      style: const pw.TextStyle(fontSize: 10),
                    ),
                    pw.Text(
                      texteTicket(formaterFcfa(l.prix)),
                      style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            pw.SizedBox(height: 10),
          ],
        ],
      ),
    );

    return (await document.save(), ecartes);
  }
}
