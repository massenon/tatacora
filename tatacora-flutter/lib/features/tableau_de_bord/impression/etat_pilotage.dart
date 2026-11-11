/// Le document « Pilotage consolidé — tous modules » — bouton PDF de
/// l'onglet (`tableau-de-bord.html` l.169, `m11-pilotage.js` `etatCourant`).
///
/// ## Les réserves PARTENT dans le document, et c'est le point
///
/// Le maître l'écrit : « un état exporté qui les perdrait circulerait comme un
/// chiffre définitif. » Chaque réserve affichée à l'écran devient une ligne
/// `RÉSERVE` du tableau — un document sans elles donnerait à des
/// approximations l'autorité d'un total.
///
/// ## Il porte ce qui est AFFICHÉ, sources indisponibles comprises
///
/// Une source refusée ou injoignable s'imprime « — » (Article 7) : omettre la
/// rubrique laisserait croire que le document est complet. PA-119 : un export
/// porte sur ce qui est affiché, et il dit son périmètre.
library;

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/impression/entete_a4.dart';
import '../../../core/impression/entete_etablissement.dart';
import '../../../core/impression/texte_ticket.dart';
import '../../../core/impression/visas.dart';

final class EtatPilotage {
  const EtatPilotage({
    required this.periode,
    required this.kpis,
    required this.lignes,
    this.entete = const EnteteEtablissement(),
  });

  /// Le titre du maître, au mot (`etatCourant`).
  static const String titre = 'Pilotage consolidé — tous modules';

  /// La fenêtre de la bande (« Du 11/09/2026 au 10/10/2026 »), à défaut
  /// l'exercice — jamais une période devinée.
  final String periode;

  /// Cinq cartes de l'écran, aux libellés de la vue — « Chiffre d'affaires
  /// encaissé », « Résultat net », « Trésorerie (caisse) », « Créances
  /// clients », « Valeur du stock » —, valeur de la carte ou « — ». La masse
  /// salariale part en ligne (ses trois états ne tiennent pas dans un chiffre).
  /// (Revu le 12/10/2026, R1 : « Chiffre d'affaires » et « Trésorerie » étaient
  /// des lectures M10 jamais établies sur ce poste ; « Valeur du stock » était
  /// une ligne lue en M6.)
  final Map<String, String> kpis;

  /// Les lignes `[Rubrique, Indicateur, Valeur]`, réserves comprises.
  final List<List<String>> lignes;

  final EnteteEtablissement entete;

  /// Le même document sous l'en-tête lu des paramètres au moment d'éditer
  /// (`lireEnteteEtablissementProvider`).
  EtatPilotage avecEntete(EnteteEtablissement autre) =>
      EtatPilotage(periode: periode, kpis: kpis, lignes: lignes, entete: autre);

  /// Les en-têtes du maître, au mot.
  static const List<String> entetes = ['Rubrique', 'Indicateur', 'Valeur'];

  /// `accueil_pwa.etat_consolide.rubrique_indicateurs` : la rubrique des cartes
  /// de la bande, que ce document imprime en tête, au-dessus des cartes.
  static const String rubriqueIndicateurs = 'Indicateurs consolidés';

  Future<Uint8List> pdf() async {
    final document = pw.Document();
    final editeLe = DateTime.now();

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        header: (c) => enTeteA4(
          entete: entete,
          titre: titre,
          sousTitre: periode,
          logo: entete.logo,
        ),
        // Un EXPORT : pied de rapport et zone de signatures de la Directive
        // §6 (PA-195), comme `pdf/dashboard-rapport.blade.php` — dont le
        // retrait délibéré des signatures a été revu par le PO (PA-194).
        footer: (c) => piedRapportA4(
          c.pageNumber,
          c.pagesCount,
          entete: entete,
          edition: editeLe,
        ),
        build: (c) => [
          pw.Text(
            texteTicket(rubriqueIndicateurs),
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Row(
            children: [
              for (final e in kpis.entries)
                pw.Expanded(
                  child: pw.Container(
                    margin: const pw.EdgeInsets.only(right: 6),
                    padding: const pw.EdgeInsets.all(6),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(width: 0.5),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          texteTicket(e.key),
                          style: const pw.TextStyle(fontSize: 7),
                        ),
                        pw.Text(
                          texteTicket(e.value),
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
          ),
          pw.SizedBox(height: 10),
          if (lignes.isEmpty)
            pw.Text(
              texteTicket(
                'Aucune source ne remonte de données : rien à consolider.',
              ),
              style: const pw.TextStyle(fontSize: 10),
            )
          else
            pw.TableHelper.fromTextArray(
              headers: entetes.map(texteTicket).toList(),
              data: [for (final l in lignes) l.map(texteTicket).toList()],
              headerStyle: pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
              ),
              cellStyle: const pw.TextStyle(fontSize: 8),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.grey300,
              ),
              // La colonne « Valeur » à droite — les montants à droite,
              // toujours (`colonnesNumeriques: [2]` du maître).
              cellAlignments: const {2: pw.Alignment.centerRight},
            ),
          zoneSignaturesA4(visas: Visas.directive),
        ],
      ),
    );

    return document.save();
  }
}
