import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/impression/entete_etablissement.dart';
import 'package:tatacora_flutter/core/impression/texte_ticket.dart';
import 'package:tatacora_flutter/core/theme/app_colors.dart';
import 'package:tatacora_flutter/features/facturation/data/proforma_dao.dart';
import 'package:tatacora_flutter/features/facturation/domain/reglages_documents.dart';
import 'package:tatacora_flutter/features/facturation/impression/proforma_a4.dart';

/// La proforma A4 du POSTE (PO, 07/11/2026) : même structure que le rendu serveur
/// (`pdf/proforma.blade.php`), jamais fiscale, signature et validité selon les réglages.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late ProformaDao dao;
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
  );

  setUp(() {
    db = AppDatabase.enMemoire();
    dao = ProformaDao(db, maintenant: () => DateTime(2026, 11, 2, 9));
  });
  tearDown(() => db.close());

  final entete = EnteteEtablissement.depuisParametres({
    'entreprise_ifu': '0202011344660',
    'entreprise_rccm': 'RB/NAT/12 B 345',
    'entreprise_telephone': '+229 01 97 35 59 74',
  });

  ReglagesDocuments reglages({
    bool signature = false,
    bool validite = false,
  }) => ReglagesDocuments.depuis({
    ClesReglagesDocuments.activites:
        'Tourisme, Hébergement, Restauration, Formation, Location, Transport',
    ClesReglagesDocuments.facebook: 'Gîte Chez Noël',
    ClesReglagesDocuments.villeEmission: 'Natitingou',
    ClesReglagesDocuments.signatureAffichee: '$signature',
    ClesReglagesDocuments.signataireNom: 'NABOGOU Winribassé Noël',
    ClesReglagesDocuments.signataireFonction: 'Directeur Général',
    ClesReglagesDocuments.validiteAffichee: '$validite',
  });

  Future<ProformaA4Composee> composee(
    ReglagesDocuments r, {
    Uint8List? signature,
    Uint8List? cachet,
    int prix = 100000,
  }) async {
    final p = await dao.creer(
      clientNom: 'SARL KORA',
      clientTelephone: '0190123456',
      objet: 'Séjour de groupe',
      lignes: [
        (
          designation: 'Hébergement chambre double',
          quantite: 4,
          prixUnitaire: prix,
        ),
      ],
      emettre: true,
      reglages: r,
    );
    return ProformaA4.composer(
      proforma: (await dao.parId(p.id))!,
      lignes: await dao.lignes(p.id),
      entete: entete,
      reglages: r,
      maintenant: DateTime(2026, 11, 2),
      signature: signature,
      cachet: cachet,
    );
  }

  test(
    'la structure du modèle : en-tête, ville et date longue, titre, tableau, lettres',
    () async {
      final d = await composee(reglages());
      final brut = d.texteBrut;

      for (final attendu in [
        'Tourisme, Hébergement, Restauration, Formation, Location, Transport',
        'Facebook : Gîte Chez Noël',
        'N°RCCM : RB/NAT/12 B 345 - N°IFU : 0202011344660',
        'Natitingou, le 02 Novembre 2026',
        'FACTURE PROFORMA',
        'PROV-FP-2026-00001',
        'SARL KORA',
        'Séjour de groupe',
        'DÉSIGNATION',
        'Prix unitaire (FCFA)',
        'Montant (FCFA)',
        'TOTAL',
        '100 000',
        '400 000',
        'Arrêté la présente FACTURE PROFORMA à la somme de :',
        'QUATRE CENT MILLE FRANCS CFA',
      ]) {
        expect(brut, contains(attendu), reason: attendu);
      }
      expect(d.identification.map((e) => e.$1), [
        'Réf.',
        'Client',
        'IFU',
        'Tel',
        'Objet',
      ]);
    },
  );

  test(
    'le vert de l\'en-tête est le jeton du thème, pas un hexadécimal posé ici',
    () {
      expect(vertEnteteTableau.toInt(), PaletteMaitre.vert700.toARGB32());
      final source = File(
        'lib/features/facturation/impression/proforma_a4.dart',
      ).readAsStringSync();
      expect(
        RegExp(r'0x[0-9A-Fa-f]{6,8}|PdfColor\.fromHex').hasMatch(source),
        isFalse,
      );
    },
  );

  test(
    'JAMAIS de mention fiscale : ni MECeF, ni QR, ni NIM, ni normalisation, ni démonstration',
    () async {
      final d = await composee(
        reglages(signature: true, validite: true),
        signature: png,
        cachet: png,
      );
      final brut = d.texteBrut.toUpperCase();
      for (final interdit in [
        'MECEF',
        'QR',
        'NIM',
        'NORMALIS',
        'DEMO',
        'CERTIFI',
      ]) {
        expect(brut, isNot(contains(interdit)), reason: interdit);
      }
      // Mutation éprouvée : la classe n'a aucun champ pour porter un code fiscal, le PDF non plus.
      final source =
          File('lib/features/facturation/impression/proforma_a4.dart')
              .readAsLinesSync()
              .where((l) => !l.trimLeft().startsWith('//'))
              .join('\n');
      expect(
        RegExp(
          r'BarcodeWidget|qrCode|numeroMecef|normalis',
          caseSensitive: false,
        ).hasMatch(source),
        isFalse,
      );
    },
  );

  test(
    'la validité n\'apparaît que si elle a été ENREGISTRÉE à l\'émission',
    () async {
      expect((await composee(reglages())).validite, isNull);
      final d = await composee(reglages(validite: true));
      expect(d.validite, 'Valable jusqu\'au 02 Décembre 2026');
    },
  );

  test(
    'la signature suit l\'interrupteur : Non = rien ; Oui = nom, fonction, images',
    () async {
      final non = await composee(reglages(), signature: png, cachet: png);
      expect(non.signature, isNull);
      expect(non.texteBrut, isNot(contains('NABOGOU')));
      expect(non.texteBrut, isNot(contains('Pour ')));

      final oui = await composee(
        reglages(signature: true),
        signature: png,
        cachet: png,
      );
      expect(oui.signature, isNotNull);
      expect(oui.texteBrut, contains('Pour TATACORA AFRIQUE'));
      expect(oui.texteBrut, contains('NABOGOU Winribassé Noël'));
      expect(oui.texteBrut, contains('Directeur Général'));

      // Oui sans image déposée : nom et fonction seulement.
      final sansImage = await composee(reglages(signature: true));
      expect(sansImage.signature!.signature, isNull);
      expect(sansImage.signature!.cachet, isNull);
      expect(sansImage.texteBrut, contains('Directeur Général'));
    },
  );

  test(
    'aucun caractère hors de la police du PDF, et le PDF est produit',
    () async {
      final d = await composee(reglages(signature: true, validite: true));
      for (final t in d.textes) {
        expect(caracteresNonImprimables(t), isEmpty, reason: t);
      }
      final pdf = await d.pdf();
      // Avec images : le PDF se compose aussi.
      final avecImages = await (await composee(
        reglages(signature: true),
        signature: png,
        cachet: png,
      )).pdf();
      expect(String.fromCharCodes(avecImages.sublist(0, 5)), '%PDF-');
      expect(String.fromCharCodes(pdf.sublist(0, 5)), '%PDF-');
      expect(pdf.length, greaterThan(2000));
    },
  );
}
