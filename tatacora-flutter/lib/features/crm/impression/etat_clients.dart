import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../caisse/domain/montant_caisse.dart' show formaterCentimesEnFcfa;
import '../../comptabilite/domain/montant_comptable.dart'
    show chaineDepuisCentimes;
import '../../../core/impression/entete_a4.dart';
import '../../../core/impression/entete_etablissement.dart';
import '../../../core/impression/texte_ticket.dart';
import '../../../core/impression/visas.dart';
import '../domain/entities/registre_clients.dart';

/// Les deux exports du registre clients — `m3-clients-creances.html` l.65-66.
///
/// ## L'export porte sur ce qui est AFFICHÉ, et il DIT son filtre
///
/// Règle du maître, tenue partout depuis PA-119 : quelqu'un qui filtre puis
/// exporte attend son filtre. Lui rendre le registre entier lui ferait
/// transmettre au comptable un document qu'il croit avoir vérifié.
///
/// ## Le document DIT ce qu'est son solde
///
/// Un état de créances remis sans la définition de son chiffre servirait à
/// décider sur un nombre dont le lecteur ignore le contenu. Depuis le lot 5
/// (12/10/2026) c'est le solde du serveur : le reste dû des factures impayées,
/// encaissements actifs, avoirs et acomptes DÉDUITS. L'ancienne mention (« les
/// règlements postérieurs à l'acompte ne sont pas déduits ») est devenue FAUSSE
/// avec le premier encaissement, et elle est retirée.
final class EtatClients {
  const EtatClients._();

  static const titre = 'Registre des clients';

  static const mentionSolde =
      'Solde = reste dû des factures émises non soldées, après déduction des '
      'avoirs, des encaissements et des acomptes de réservation.';

  /// CSV — BOM UTF-8 et point-virgule, convention serveur RG-19.
  ///
  /// Le maître écrit « Excel » sur le bouton ; aucune bibliothèque XLSX n'est
  /// embarquée, et l'écart est nommé plutôt que masqué (PA-111). Les montants
  /// partent en **nombres bruts** : un tableur ne sait pas additionner
  /// « 56 000 FCFA ».
  static String csv(List<LigneClient> lignes, {required String filtre}) {
    final tampon = StringBuffer('﻿');

    tampon.writeln('$titre;$filtre');
    tampon.writeln(mentionSolde.replaceAll(';', ','));
    tampon.writeln();
    tampon.writeln('Client;Telephone;Type;Solde du;Pieces;Synchronisation');

    for (final l in lignes) {
      tampon.writeln(
        [
          _echapper(l.client.nomComplet),
          _echapper(l.client.telephone),
          _echapper(l.client.type.libelle),
          chaineDepuisCentimes(l.soldeCentimes),
          l.nbPieces,
          l.client.enAttenteDeSynchronisation ? 'en attente' : 'synchronise',
        ].join(';'),
      );
    }

    return tampon.toString();
  }

  static List<int> csvOctets(
    List<LigneClient> lignes, {
    required String filtre,
  }) => utf8.encode(csv(lignes, filtre: filtre));

  static Future<Uint8List> pdf(
    List<LigneClient> lignes, {
    required String filtre,
    required EnteteEtablissement entete,
    DateTime? edition,
  }) async {
    final document = pw.Document();
    final kpis = KpisClients.calculer(lignes);
    final editeLe = edition ?? DateTime.now();

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        // Le point unique de `core/impression/` — le filtre passe en
        // sous-titre, comme la periode de l'historique.
        header: (contexte) => enTeteA4(
          entete: entete,
          titre: titre,
          sousTitre: filtre,
          logo: entete.logo,
        ),
        // Un EXPORT : pied de rapport et zone de signatures de la Directive
        // §6 (PA-195), comme `pdf/clients-creances.blade.php`.
        footer: (contexte) => piedRapportA4(
          contexte.pageNumber,
          contexte.pagesCount,
          entete: entete,
          edition: editeLe,
        ),
        build: (contexte) => [
          pw.Text(
            texteTicket(mentionSolde),
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
            ),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.centerLeft,
              3: pw.Alignment.centerRight,
              4: pw.Alignment.centerRight,
            },
            headers: [
              'Client',
              'Telephone',
              'Type',
              'Solde du',
              'Pieces',
            ].map(texteTicket).toList(),
            data: [
              for (final l in lignes)
                [
                  texteTicket(l.client.nomComplet),
                  texteTicket(l.client.telephone),
                  texteTicket(l.client.type.libelle),
                  texteTicket(formaterCentimesEnFcfa(l.soldeCentimes)),
                  '${l.nbPieces}',
                ],
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Text(
            texteTicket(
              '${kpis.nbClients} client(s) — ${kpis.nbDebiteurs} debiteur(s) — '
              'total du ${formaterCentimesEnFcfa(kpis.totalDuCentimes)}',
            ),
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
          zoneSignaturesA4(visas: Visas.directive),
        ],
      ),
    );

    return document.save();
  }

  /// Le point-virgule sépare les colonnes : le laisser passer décalerait
  /// toutes les suivantes, sur un fichier que personne ne relit.
  static String _echapper(String valeur) => valeur.replaceAll(';', ',');
}
