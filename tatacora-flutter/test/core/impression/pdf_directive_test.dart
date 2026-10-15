import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:tatacora_flutter/core/impression/entete_a4.dart';
import 'package:tatacora_flutter/core/impression/entete_etablissement.dart';
import 'package:tatacora_flutter/core/impression/visas.dart';

import '../../support/vue_blade.dart';

/// Les PDF d'EXPORT du client Flutter tiennent la Directive §6 — décision du
/// Product Owner du 11/09/2026 (PA-192 (a)), portée côté Flutter en PA-195
/// après le serveur (PA-194) : zone de signatures, pied de rapport (mention
/// institutionnelle, date d'édition, pagination). Un document REMIS AU CLIENT
/// n'en porte jamais.
///
/// ## Trois niveaux, parce qu'aucun ne suffit seul
///
/// 1. Le REGISTRE : chaque fichier `impression/` est classé, et le nombre de
///    zones de signatures et de pieds de rapport qu'il compose est celui de
///    ses documents d'export. Un fichier non classé fait échouer.
/// 2. Les LIBELLÉS : [Visas] est relu contre les gabarits SERVEUR
///    (`resources/views/pdf/*.blade.php`) et `lang/fr/rapports.php`. Une liste
///    recopiée côté Dart sans cette garde ne vérifierait qu'elle-même.
/// 3. Le RENDU : les deux blocs sont réellement composés, et leurs textes
///    lus dans le PDF produit.
void main() {
  /* ================================================================== */
  group('Le registre des documents — chaque fichier est classé', () {
    // Le nombre de documents d'EXPORT que chaque fichier compose.
    const exports = <String, int>{
      'achats/impression/etat_liste_achats.dart': 1,
      'bar/impression/etat_ventes_bar.dart': 1,
      'bar/impression/etat_carte.dart':
          1, // + la fiche des prix, remise au client
      'crm/impression/etat_clients.dart': 1,
      'facturation/impression/etat_registre_factures.dart': 1,
      'hebergement/impression/etat_historique.dart': 1,
      'restaurant/impression/etat_carte_restaurant.dart':
          1, // + la fiche des prix
      'stocks/impression/etat_fiche_stock.dart': 1,
      'tableau_de_bord/impression/etat_pilotage.dart': 1,
      // La synthèse « Exporter » de l'accueil (lot A du 14/10/2026, D413).
      'tableau_de_bord/impression/etat_rapport_accueil.dart': 1,
      'ventes/impression/etat_journal_ventes.dart':
          1, // + le détail d'une vente
    };
    // Remis au client (ou pièce fiscale) : ni visa, ni pied de rapport.
    const documentsClient = {
      'facturation/impression/essai_qr_thermique.dart',
      'facturation/impression/facture_a4.dart',
      'facturation/impression/ticket_facture.dart',
      'hebergement/impression/confirmation_reservation.dart',
    };
    // Tableur seulement : aucun PDF composé.
    const sansPdf = {
      'bar/impression/etat_catalogue_boissons.dart',
      'vehicules/impression/etat_vehicules.dart',
      // Portés le 14/09/2026 avec les modules d'exploitation. Les deux
      // exportent en CSV (BOM UTF-8 + point-virgule, RG-19) et ne composent
      // AUCUN PDF : un A4 devrait porter visa et pied de rapport, donc se
      // classer au registre ci-dessus — c'est un travail à part, pas un oubli.
      'depenses/impression/etat_depenses.dart',
      'notifications/impression/etat_notifications.dart',
      // Personnel & Paie, 09/10/2026 : le bouton « Exporter » de `rh/paie`
      // écrit un CSV et REFUSE le choix PDF avec son message (aucun A4 de la
      // paie n'existe : en-tête unique et visas, arbitrage PA-192).
      'rh/impression/etat_paie.dart',
      // Parc d'hébergement, 09/10/2026 : le bouton « Générer & Télécharger » du
      // plan écrit un CSV et REFUSE le choix PDF avec son message (aucun A4 du
      // parc n'existe : en-tête unique et visas, arbitrage PA-192).
      'hebergement/impression/etat_parc.dart',
      // Tourisme, 09/10/2026 : le bouton « Exporter » de `tourisme/departs`
      // écrit un CSV par onglet et REFUSE le choix PDF avec son message (aucun
      // A4 de M9 n'existe : en-tête unique et visas, arbitrage PA-192).
      'tourisme/impression/etat_tourisme.dart',
      // Gestion des Stocks, 09/10/2026 : le bouton « Exporter » de
      // `stocks/stocks` écrit un CSV (les lignes AFFICHÉES, le filtre dit) et
      // REFUSE le choix PDF avec son message (aucun A4 des stocks n'existe :
      // en-tête unique et visas, arbitrage PA-192). La fiche de stock, elle,
      // compose un PDF et reste classée plus haut.
      'stocks/impression/etat_stocks.dart',
    };

    final fichiers = <String, String>{
      for (final f in Directory('lib/features').listSync(recursive: true))
        if (f is File &&
            f.path.endsWith('.dart') &&
            f.path.replaceAll('\\', '/').contains('/impression/'))
          f.path.replaceAll('\\', '/').replaceFirst('lib/features/', ''): f
              .readAsStringSync(),
    };

    int compte(String source, String motif) =>
        RegExp(RegExp.escape(motif)).allMatches(source).length;

    test('chaque fichier est classé, et le balayage n’est pas vide', () {
      // Prouvé NON VIDE : un dossier renommé rendrait la garde verte à vide.
      expect(fichiers.length, greaterThanOrEqualTo(15));
      final nonClasses = fichiers.keys
          .where(
            (f) =>
                !exports.containsKey(f) &&
                !documentsClient.contains(f) &&
                !sansPdf.contains(f),
          )
          .toList();
      expect(
        nonClasses,
        isEmpty,
        reason:
            'Document non classé : dites s’il est un EXPORT (Directive §6) ou '
            'un document remis au client.',
      );
    });

    for (final MapEntry(key: fichier, value: nombre) in exports.entries) {
      test(
        '$fichier : $nombre zone(s) de signatures et pied(s) de rapport',
        () {
          final source = fichiers[fichier];
          expect(source, isNotNull, reason: '$fichier introuvable');
          expect(compte(source!, 'zoneSignaturesA4('), nombre);
          expect(compte(source, 'piedRapportA4('), nombre);
        },
      );
    }

    for (final fichier in documentsClient) {
      test(
        '$fichier est remis au client : aucun visa, aucun pied de rapport',
        () {
          final source = fichiers[fichier];
          expect(source, isNotNull, reason: '$fichier introuvable');
          expect(compte(source!, 'zoneSignaturesA4('), 0);
          expect(compte(source, 'piedRapportA4('), 0);
        },
      );
    }

    for (final fichier in sansPdf) {
      test('$fichier ne compose aucun PDF', () {
        final source = fichiers[fichier];
        expect(source, isNotNull, reason: '$fichier introuvable');
        expect(RegExp(r'pw\.(Multi)?Page\(').hasMatch(source!), isFalse);
      });
    }

    test('aucun état ne recompose son propre pied de page', () {
      // Le registre des factures en portait une COPIE jusqu'au 11/09/2026 :
      // en-tête et pied recomposés à la main, la non-conformité n° 1 de
      // `RESPECT_TABLEAU_RAPPORT.md` §4.
      final copies = fichiers.entries
          .where((e) => e.value.contains(r"'Page $"))
          .map((e) => e.key)
          .toList();
      expect(copies, isEmpty);
    });
  });

  /* ================================================================== */
  group('Les libellés sont ceux du SERVEUR', () {
    /// Les visas passés à `pdf.partials.signatures` par un gabarit serveur —
    /// `null` s'il prend ceux de la directive (inclusion sans `visas`).
    List<String>? visasDuGabarit(String gabarit) {
      final source = VueBlade.resoudre(
        VueBlade.fichier(
          'resources/views/pdf/$gabarit.blade.php',
          role: 'gabarit PDF serveur',
        ),
      );
      final avec = RegExp(
        r"@include\('pdf\.partials\.signatures',\s*\['visas'\s*=>\s*\[(.*?)\]\]\)",
      ).firstMatch(source);
      if (avec != null) {
        return RegExp(r"'((?:[^'\\]|\\.)*)'")
            .allMatches(avec[1]!)
            .map((m) => m[1]!.replaceAll(r"\'", "'"))
            .toList();
      }
      expect(
        source,
        contains("@include('pdf.partials.signatures')"),
        reason: '« $gabarit » n’a aucune zone de signatures côté serveur.',
      );
      return null;
    }

    test('les visas de la directive sont ceux de rapports.signatures', () {
      expect(Visas.directive, [
        VueBlade.libelle('rapports.signatures.visa_ordonnateur'),
        VueBlade.libelle('rapports.signatures.visa_direction'),
      ]);
    });

    test('la mention du pied est celle du serveur', () {
      expect(
        const EnteteEtablissement().mentionInstitutionnelle,
        VueBlade.libelle('rapports.entete.mention_institutionnelle'),
      );
    });

    // Chaque liste de [Visas] contre le gabarit serveur du même document.
    final correspondances = <String, List<String>>{
      'achats': Visas.achats,
      'fournisseurs-liste': Visas.achats,
      'approvisionnement-bon': Visas.approvisionnement,
      'fiche-stock': Visas.ficheStock,
      'ventes-rapport': Visas.journalVentes,
    };
    for (final MapEntry(key: gabarit, value: visas)
        in correspondances.entries) {
      test('pdf/$gabarit : mêmes visas', () {
        expect(visas, visasDuGabarit(gabarit));
      });
    }

    // Les exports Flutter aux visas de la directive : leur gabarit serveur
    // prend lui aussi ceux de la directive.
    for (final gabarit in [
      'carte',
      'carte-ventes',
      'clients-creances',
      'facturation-registre',
      'hebergement',
      'dashboard-rapport',
    ]) {
      test('pdf/$gabarit prend les visas de la directive', () {
        expect(visasDuGabarit(gabarit), isNull);
      });
    }
  });

  /* ================================================================== */
  group('Les deux blocs sont réellement composés', () {
    test(
      'la zone de signatures et le pied de rapport sortent sur le papier',
      () async {
        // Non compressé : les textes se lisent dans les octets du document.
        final document = pw.Document(compress: false);
        document.addPage(
          pw.MultiPage(
            pageFormat: PdfPageFormat.a4,
            footer: (c) => piedRapportA4(
              c.pageNumber,
              c.pagesCount,
              entete: const EnteteEtablissement(),
              edition: DateTime(2026, 9, 11, 16, 5),
            ),
            build: (c) => [zoneSignaturesA4(visas: Visas.directive)],
          ),
        );
        // dart_pdf écrit chaque MOT dans son propre opérateur `[(mot)]TJ` : le
        // texte se relit en rejoignant ces chaînes, dans leur ordre.
        final brut = latin1.decode(await document.save());
        final texte = RegExp(
          r'\(((?:[^()\\]|\\.)*)\)\]TJ',
        ).allMatches(brut).map((m) => m[1]!).join(' ');

        for (final attendu in [
          'Visa Ordonnateur / Caissier :',
          'Visa Direction / Contr',
          'Projet PAEB',
          '11/09/2026 16:05',
          '1 / 1',
        ]) {
          expect(texte, contains(attendu));
        }
      },
    );
  });
}
