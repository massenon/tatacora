// Vue Blade maîtresse (PA-183) : pwa/crm/clients-creances.blade.php
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/format/formats.dart' show formaterDate;
import '../../../core/impression/entete_a4.dart';
import '../../../core/impression/entete_etablissement.dart';
import '../../../core/impression/texte_ticket.dart';
import '../../caisse/domain/montant_caisse.dart' show formaterCentimesEnFcfa;

/// Un mouvement du relevé : un encaissement, ou une relance.
typedef MouvementReleve = ({DateTime date, String type, int montantCentimes});

/// Le **relevé de compte client** — `pdf/releve-client.blade.php`, le papier du
/// bouton « Imprimer PDF » de la modale « Historique d'un client »
/// (`imprimerReleveClient`).
///
/// ## Un document REMIS AU CLIENT
///
/// Ni visa ni pied de rapport interne : le serveur le dit en tête de son
/// gabarit (PA-194) — un « Visa Ordonnateur » sur un papier client le ferait
/// lire comme une pièce d'ordonnancement. Le pied est NEUTRE : la raison
/// sociale et la pagination (`piedA4`). Il se classe donc parmi les documents
/// remis au client de `pdf_directive_test.dart`.
///
/// ## Trois colonnes, comme le gabarit
///
/// `Date · Type · Montant`, du plus récent au plus ancien : les encaissements
/// d'abord, puis les relances (le gabarit les boucle dans cet ordre). Un client
/// sans mouvement le DIT (« Aucun mouvement pour ce client. ») plutôt que
/// d'imprimer un tableau sans ligne, qu'on prendrait pour une panne d'édition.
///
/// ## Les relances y figurent (21/10/2026)
///
/// Le gabarit boucle les encaissements PUIS les relances du client
/// (`Relance`, montant RÉCLAMÉ ce jour-là). Le poste les détient désormais
/// (`relances_clients_local`) : elles sont des lignes du relevé, au même titre
/// que les encaissements — le papier remis au client ne tait plus rien.
final class ReleveClient {
  const ReleveClient({
    required this.clientNom,
    required this.mouvements,
    required this.editeLe,
    this.entete = const EnteteEtablissement(),
  });

  /// Le titre du document (`pwa.clients.releve_document`).
  static const String titre = 'Relevé de compte client';

  static const List<String> entetes = ['Date', 'Type', 'Montant'];

  static const String aucunMouvement = 'Aucun mouvement pour ce client.';

  final String clientNom;

  /// Du plus récent au plus ancien — l'ordre de l'appelant est conservé.
  final List<MouvementReleve> mouvements;

  /// Injectée, jamais lue de l'horloge à la composition.
  final DateTime editeLe;

  final EnteteEtablissement entete;

  /// Le même document sous l'en-tête lu des paramètres au moment d'éditer.
  ReleveClient avecEntete(EnteteEtablissement autre) => ReleveClient(
    clientNom: clientNom,
    mouvements: mouvements,
    editeLe: editeLe,
    entete: autre,
  );

  bool get estVide => mouvements.isEmpty;

  /// Les lignes du tableau, telles qu'elles s'impriment.
  List<List<String>> get lignes => [
    for (final m in mouvements)
      [formaterDate(m.date), m.type, formaterCentimesEnFcfa(m.montantCentimes)],
  ];

  static String _t(String source) => texteTicket(source);

  Future<Uint8List> pdf() async {
    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        header: (context) => enTeteA4(
          entete: entete,
          titre: titre,
          sousTitre: clientNom,
          logo: entete.logo,
        ),
        // Pied NEUTRE d'un document remis au client : jamais le pied de rapport.
        footer: (context) => piedA4(context.pageNumber, context.pagesCount),
        build: (context) => [_tableau()],
      ),
    );
    return doc.save();
  }

  pw.Widget _tableau() {
    if (estVide) {
      return pw.Text(
        _t(aucunMouvement),
        textAlign: pw.TextAlign.center,
        style: const pw.TextStyle(fontSize: 10),
      );
    }
    return pw.TableHelper.fromTextArray(
      headers: entetes.map(_t).toList(),
      data: [for (final l in lignes) l.map(_t).toList()],
      headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
      cellStyle: const pw.TextStyle(fontSize: 8.5),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
      cellAlignments: {2: pw.Alignment.centerRight},
    );
  }
}
