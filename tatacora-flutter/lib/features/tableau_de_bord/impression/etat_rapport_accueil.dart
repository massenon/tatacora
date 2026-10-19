/// Un rapport de la modale « Générer un rapport » (et la synthèse du bouton
/// « Exporter ») de l'accueil — traduction de `pdf/dashboard-rapport.blade.php`
/// (lot C du plan du PO, 14/10/2026).
///
/// ## Ce document n'est PAS une facture
///
/// Ni IFU, ni RCCM, ni cachet MECeF : un état de gestion interne, et son pied
/// le dit (« il ne vaut pas facture »), au mot du gabarit du serveur.
///
/// ## Un EXPORT : en-tête, signatures, pied de rapport (Directive §6)
///
/// Comme le gabarit du serveur depuis le 11/09/2026 (PA-194) : en-tête A4 de
/// l'établissement, zone de signatures aux visas de la directive, pied de
/// rapport paginé. Le registre des états classés de
/// `test/core/impression/pdf_directive_test.dart` doit le connaître.
///
/// ## Le tableur est un CSV
///
/// `Accueil::exporterExcel` écrit un `.xlsx` quand Maatwebsite/Excel est
/// installé, un CSV (BOM UTF-8, point-virgule) sinon. Ce poste n'embarque
/// aucune bibliothèque XLSX : il écrit le CSV du repli du serveur — titre,
/// période, ligne vide, en-têtes, lignes —, la convention RG-19 (écart nommé,
/// comme PA-111).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/impression/entete_a4.dart';
import '../../../core/impression/entete_etablissement.dart';
import '../../../core/impression/texte_ticket.dart';
import '../../../core/impression/visas.dart';

final class EtatRapportAccueil {
  const EtatRapportAccueil({
    required this.titre,
    required this.periode,
    required this.entetes,
    required this.lignes,
    required this.code,
    this.entete = const EnteteEtablissement(),
  });

  /// Le libellé du rapport (`accueil_pwa.modale_rapport.<type>`).
  final String titre;

  /// `$periode->libelle()`.
  final String periode;

  final List<String> entetes;
  final List<List<String>> lignes;

  /// Le code du rapport (`synthese`, `reservations`…) — le nom du fichier.
  final String code;

  final EnteteEtablissement entete;

  /// Le même document sous l'en-tête lu des paramètres au moment d'éditer
  /// (`lireEnteteEtablissementProvider`).
  EtatRapportAccueil avecEntete(EnteteEtablissement autre) =>
      EtatRapportAccueil(
        titre: titre,
        periode: periode,
        entetes: entetes,
        lignes: lignes,
        code: code,
        entete: autre,
      );

  /// Le pied du gabarit du serveur, au mot.
  static const String piedInterne =
      'Document de gestion interne — il ne vaut pas facture et ne porte '
      'aucune mention fiscale. Les chiffres portent sur la période indiquée '
      'ci-dessus et sur elle seule.';

  /// `tableau_de_bord_<type>_<AAAAMMJJ_HHMMSS>` — le nom du serveur, sans
  /// extension.
  String nomFichier(DateTime instant) {
    String deux(int n) => n.toString().padLeft(2, '0');
    return 'tableau_de_bord_${code}_${instant.year}${deux(instant.month)}'
        '${deux(instant.day)}_${deux(instant.hour)}${deux(instant.minute)}'
        '${deux(instant.second)}';
  }

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
        footer: (c) => piedRapportA4(
          c.pageNumber,
          c.pagesCount,
          entete: entete,
          edition: editeLe,
        ),
        build: (c) => [
          pw.TableHelper.fromTextArray(
            headers: entetes.map(texteTicket).toList(),
            data: [for (final l in lignes) l.map(texteTicket).toList()],
            // `th { background: #14213D; color: #ffffff; }`.
            headerStyle: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
            headerDecoration: const pw.BoxDecoration(
              color: PdfColor.fromInt(0xFF14213D),
            ),
            cellStyle: const pw.TextStyle(fontSize: 8),
            // `@if ($index > 0) class="nombre"` : toute colonne sauf la
            // première est alignée à droite.
            cellAlignments: {
              for (var i = 1; i < entetes.length; i++)
                i: pw.Alignment.centerRight,
            },
            headerAlignments: {
              for (var i = 1; i < entetes.length; i++)
                i: pw.Alignment.centerRight,
            },
          ),
          pw.SizedBox(height: 14),
          pw.Text(
            texteTicket(piedInterne),
            style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
          ),
          zoneSignaturesA4(visas: Visas.directive),
        ],
      ),
    );

    return document.save();
  }

  /// Le CSV du repli du serveur : BOM UTF-8, point-virgule, titre, période,
  /// ligne vide, en-têtes, lignes (`fputcsv` : guillemets doublés, champ
  /// entouré dès qu'il contient le séparateur, un guillemet ou un blanc).
  Uint8List csvOctets() {
    String champ(String v) {
      final aProteger =
          v.contains(';') ||
          v.contains('"') ||
          v.contains('\n') ||
          v.contains('\r') ||
          v.contains(' ') ||
          v.contains('\t');
      return aProteger ? '"${v.replaceAll('"', '""')}"' : v;
    }

    final tampon = StringBuffer()
      ..write('﻿')
      ..write('${champ(titre)}\n')
      ..write('${champ(periode)}\n')
      ..write('\n')
      ..write('${entetes.map(champ).join(';')}\n');
    for (final l in lignes) {
      tampon.write('${l.map(champ).join(';')}\n');
    }
    return Uint8List.fromList(utf8.encode(tampon.toString()));
  }
}
