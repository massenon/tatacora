import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:uuid/uuid.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/fichiers/selecteur_fichiers.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/auth/domain/session.dart';
import 'package:tatacora_flutter/features/depenses/domain/recu_depense.dart';
import 'package:tatacora_flutter/features/facturation/data/depot_images_document.dart';
import 'package:tatacora_flutter/features/facturation/data/images_document_poste.dart';
import 'package:tatacora_flutter/features/parametres/data/apparence_poste.dart';
import 'package:tatacora_flutter/features/parametres/presentation/ecran_parametres.dart';
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/data/telechargement_images_document.dart';
import 'package:tatacora_flutter/features/synchronisation/data/transport_synchronisation.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';

import '../../support/selecteur_essai.dart';
import '../../support/vue_blade.dart';

/// Téléverser la SIGNATURE et le CACHET depuis le poste (PO, 11/11/2026) : validation locale
/// (octets magiques, réduction à 400 Ko), enregistrement local immédiat, opération dans la file
/// d'envoi, descente sans boucle, et l'écran (bouton, aperçu, refus, droit administrateur).
Uint8List _png({int cote = 8}) {
  final image = img.Image(width: cote, height: cote)
    ..clear(img.ColorRgb8(10, 80, 160));
  return Uint8List.fromList(img.encodePng(image));
}

/// Une image de bruit : incompressible, donc bien plus lourde que 400 Ko en PNG.
Uint8List _grosPng() {
  final image = img.Image(width: 900, height: 900);
  var v = 12345;
  for (final p in image) {
    v = (v * 1103515245 + 12345) & 0x7fffffff;
    p
      ..r = v & 255
      ..g = (v >> 8) & 255
      ..b = (v >> 16) & 255;
  }
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  late AppDatabase db;
  late Directory dossier;
  late ImagesDocumentPoste images;
  late DepotImagesDocumentPoste depot;

  setUp(() {
    db = AppDatabase.enMemoire();
    dossier = Directory.systemTemp.createTempSync('signature_cachet_');
    images = ImagesDocumentPoste(() async => dossier);
    depot = DepotImagesDocumentPoste(db, images);
  });
  tearDown(() async {
    await db.close();
    if (dossier.existsSync()) dossier.deleteSync(recursive: true);
  });

  Future<List<OperationSync>> file() => OperationsSyncDao(
    db,
  ).operations(table: TableSynchronisee.depotsImagesDocument);

  group('Préparation — le type est lu des octets, jamais du nom', () {
    test('vide, PDF et texte sont refusés avec les phrases du web', () async {
      await expectLater(
        preparerImageDocument(const []),
        throwsA(
          isA<RefusImageDocument>().having(
            (e) => e.message,
            'message',
            TextesRecu.vide,
          ),
        ),
      );
      for (final faux in [
        utf8.encode('%PDF-1.4 pas une image'),
        utf8.encode('juste du texte'),
      ]) {
        await expectLater(
          preparerImageDocument(faux),
          throwsA(
            isA<RefusImageDocument>().having(
              (e) => e.message,
              'message',
              TextesRecu.nonImage,
            ),
          ),
        );
      }
    });

    test('un PNG de moins de 400 Ko est gardé TEL QUEL', () async {
      final png = _png();
      final prete = await preparerImageDocument(png);
      expect(prete.octets, png);
      expect(prete.mime, 'image/png');
    });

    test(
      'une image de plus de 400 Ko est RÉDUITE en JPEG de 400 Ko au plus',
      () async {
        final gros = _grosPng();
        expect(gros.length, greaterThan(tailleMaxRecuOctets));
        final prete = await preparerImageDocument(gros);
        expect(prete.octets.length, lessThanOrEqualTo(tailleMaxRecuOctets));
        expect(prete.mime, 'image/jpeg');
        expect(typeRecuDepuisOctets(prete.octets), TypeRecu.jpeg);
      },
    );

    test('un GIF est converti en PNG ; un faux PNG trop lourd, illisible, '
        'est refusé', () async {
      final gif = Uint8List.fromList(
        img.encodeGif(img.Image(width: 4, height: 4)),
      );
      final converti = await preparerImageDocument(gif);
      expect(converti.mime, 'image/png');

      final faux = Uint8List(tailleMaxRecuOctets + 10)
        ..setAll(0, _png().sublist(0, 33));
      await expectLater(
        preparerImageDocument(faux),
        throwsA(
          isA<RefusImageDocument>().having(
            (e) => e.message,
            'message',
            TextesRecu.illisible,
          ),
        ),
      );
    });
  });

  group('Dépôt — local d’abord, puis la file d’envoi', () {
    test(
      'déposer range le fichier et enfile UN dépôt (nature, type, base64)',
      () async {
        final png = _png();
        await depot.deposer(ImageDocument.signature, png);

        expect(await images.lire(ImageDocument.signature), png);
        final ops = await file();
        expect(ops, hasLength(1));
        expect(ops.single.type, TypeOperationSync.creation);
        expect(ops.single.statut, StatutOperationSync.enAttente);
        final charge = jsonDecode(ops.single.payload) as Map;
        expect(charge['nature'], 'signature');
        expect(charge['action'], 'deposer');
        expect(charge['type_mime'], 'image/png');
        expect(base64Decode(charge['octets_base64'] as String), png);
        expect(
          (charge['octets_base64'] as String).length,
          lessThan(600 * 1024),
          reason: '400 Ko en base64 au plus',
        );
        expect(await depot.naturesEnSuspens(), {ImageDocument.signature});
      },
    );

    test('un refus n’écrit RIEN : ni fichier, ni opération', () async {
      await expectLater(
        depot.deposer(ImageDocument.cachet, utf8.encode('pas une image')),
        throwsA(isA<RefusImageDocument>()),
      );
      expect(await images.lire(ImageDocument.cachet), isNull);
      expect(await file(), isEmpty);
    });

    test('chaque geste a son identifiant ; retirer enfile un retrait, et '
        'sans image il n’y a rien à retirer', () async {
      await depot.retirer(ImageDocument.cachet);
      expect(await file(), isEmpty);

      await depot.deposer(ImageDocument.cachet, _png());
      await depot.deposer(ImageDocument.cachet, _png(cote: 16));
      await depot.retirer(ImageDocument.cachet);

      expect(await images.lire(ImageDocument.cachet), isNull);
      final ops = await file();
      expect(ops, hasLength(3));
      expect(ops.map((o) => o.entiteId).toSet(), hasLength(3));
      expect(jsonDecode(ops.last.payload), {
        'nature': 'cachet',
        'action': 'retirer',
      });
    });

    test('si l’enfilement échoue, l’image précédente est rétablie', () async {
      final avant = _png();
      await depot.deposer(ImageDocument.signature, avant);
      final casse = DepotImagesDocumentPoste(db, images, uuid: _UuidQuiCasse());
      await expectLater(
        casse.deposer(ImageDocument.signature, _png(cote: 32)),
        throwsA(isA<StateError>()),
      );
      expect(await images.lire(ImageDocument.signature), avant);
      await expectLater(
        casse.retirer(ImageDocument.signature),
        throwsA(isA<StateError>()),
      );
      expect(await images.lire(ImageDocument.signature), avant);
      expect(await file(), hasLength(1), reason: 'seul le premier dépôt');
    });
  });

  group('Descente — sans boucle ni écrasement', () {
    final ancienne = <int>[
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
      9,
      9,
    ];

    test('tant que le dépôt n’est pas accusé, l’image du serveur n’écrase '
        'pas celle du poste ; accusé, elle redevient la règle', () async {
      final png = _png();
      await depot.deposer(ImageDocument.signature, png);

      final transport = _Faux({
        'signature': {
          'empreinte': ImagesDocumentPoste.empreinteDe(ancienne),
          'type': 'image/png',
          'octets_base64': base64Encode(ancienne),
        },
        'cachet': null,
      });
      final descente = TelechargementImagesDocument(
        transport,
        images,
        depot.naturesEnSuspens,
      );
      Future<int> passer() => descente.rafraichir(
        serveur: 'https://s.test',
        posteId: 'p',
        jeton: 't',
      );

      expect(await passer(), 0);
      expect(await images.lire(ImageDocument.signature), png);

      // Accusé par le serveur : la file n'est plus en suspens.
      final dao = OperationsSyncDao(db);
      final lot = await dao.reclamerLot();
      for (final o in lot) {
        await dao.marquerResultat(
          o.uuidOperation,
          resultat: {'statut': 'synchronise'},
        );
      }
      expect(await depot.naturesEnSuspens(), isEmpty);
      expect(await passer(), 1);
      expect(await images.lire(ImageDocument.signature), ancienne);
    });

    test('l’empreinte envoyée au serveur est celle des octets déposés : le '
        'serveur ne les renvoie pas (pas de boucle)', () async {
      final png = _png();
      await depot.deposer(ImageDocument.cachet, png);
      final transport = _Faux({'signature': null, 'cachet': null});
      await TelechargementImagesDocument(
        transport,
        images,
      ).rafraichir(serveur: 'https://s.test', posteId: 'p', jeton: 't');
      expect(
        transport.derniere!.queryParameters['cachet'],
        ImagesDocumentPoste.empreinteDe(png),
      );
    });
  });

  group('L’écran — Paramètres › Identité & Légal', () {
    Future<void> monter(
      WidgetTester tester, {
      String role = 'administrateur',
      String niveau = 'C',
      SelecteurEssai? selecteur,
    }) async {
      tester.view
        ..physicalSize = const Size(1600, 2400)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final droits = GardeAcces({'PARAM': niveau});
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            baseLocaleProvider.overrideWithValue(db),
            droitsProvider.overrideWithValue(droits),
            dossierApparenceProvider.overrideWithValue(() async => dossier),
            if (selecteur != null)
              selecteurFichiersProvider.overrideWithValue(selecteur),
            sessionProvider.overrideWithBuild(
              (ref, n) => Session(
                utilisateurId: 'u-essai',
                login: 'essai',
                nom: 'Essai',
                role: role,
                droits: droits,
              ),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.clair,
            home: const Scaffold(body: EcranParametres()),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    const cle = 'signature-sous-interrupteur';

    testWidgets('les mots du web, plus aucune phrase « version web »', (
      tester,
    ) async {
      await monter(tester);
      expect(
        find.text(
          VueBlade.libelle('pwa.parametres.apparence_signature_titre')!,
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          VueBlade.libelle('pwa.parametres.apparence_signature_bouton')!,
        ),
        findsOneWidget,
      );
      expect(
        find.text(VueBlade.libelle('pwa.parametres.apparence_cachet_bouton')!),
        findsOneWidget,
      );
      expect(
        find.text(VueBlade.libelle('pwa.parametres.apparence_image_absente')!),
        findsNWidgets(2),
      );
      expect(find.textContaining('version web'), findsNothing);
      expect(find.byKey(const Key('$cle-retirer')), findsNothing);
    });

    testWidgets('choisir une image : aperçu, fichier local, opération, toast ; '
        'Retirer la retire', (tester) async {
      final png = _png();
      await monter(
        tester,
        selecteur: SelecteurEssai(
          lu: FichierLu(nom: 'sign.png', octets: png),
        ),
      );
      await tester.tap(find.byKey(const Key('$cle-changer')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('$cle-apercu')), findsOneWidget);
      expect(find.byKey(const Key('$cle-absente')), findsNothing);
      expect(
        find.text(
          VueBlade.libelle('pwa.parametres.apparence_signature_enregistre')!,
        ),
        findsOneWidget,
      );
      expect(File('${dossier.path}/signature.png').readAsBytesSync(), png);
      expect((await file()), hasLength(1));

      await tester.tap(find.byKey(const Key('$cle-retirer')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('$cle-absente')), findsOneWidget);
      expect(File('${dossier.path}/signature.png').existsSync(), isFalse);
      expect((await file()).last.payload, contains('retirer'));
      expect(
        find.text(
          VueBlade.libelle('pwa.parametres.apparence_signature_retire')!,
        ),
        findsOneWidget,
      );
    });

    testWidgets('un fichier qui n’est pas une image est refusé, rien d’écrit', (
      tester,
    ) async {
      await monter(
        tester,
        selecteur: SelecteurEssai(
          lu: FichierLu(
            nom: 'faux.png', // l'extension ment : seuls les octets comptent
            octets: Uint8List.fromList(utf8.encode('%PDF-1.4 ...')),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('$cle-changer')));
      await tester.pumpAndSettle();
      expect(find.text(TextesRecu.nonImage), findsOneWidget);
      expect(find.byKey(const Key('$cle-apercu')), findsNothing);
      expect(dossier.listSync(), isEmpty);
      expect(await file(), isEmpty);
    });

    testWidgets('un fichier trop lourd et illisible est refusé ; un lourd '
        'lisible est réduit à 400 Ko', (tester) async {
      final faux = Uint8List(tailleMaxRecuOctets + 10)
        ..setAll(0, _png().sublist(0, 33));
      await monter(
        tester,
        selecteur: SelecteurEssai(
          lu: FichierLu(nom: 'gros.png', octets: faux),
        ),
      );
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('$cle-changer')));
        await Future<void>.delayed(const Duration(seconds: 2));
      });
      await tester.pumpAndSettle();
      expect(find.text(TextesRecu.illisible), findsOneWidget);
      expect(dossier.listSync(), isEmpty);
      expect(await file(), isEmpty);

      final gros = _grosPng();
      await tester.runAsync(() async {
        await depot.deposer(ImageDocument.cachet, gros);
      });
      final rangee = await images.lire(ImageDocument.cachet);
      expect(rangee!.length, lessThanOrEqualTo(tailleMaxRecuOctets));
    });

    testWidgets('réservé aux administrateurs : sans ce rôle (ou en lecture '
        'seule), l’image se voit sans bouton', (tester) async {
      await monter(tester, role: 'barman');
      expect(find.byKey(const Key('$cle-changer')), findsNothing);
      expect(
        find.text(
          VueBlade.libelle('pwa.parametres.apparence_signature_titre')!,
        ),
        findsOneWidget,
      );
    });

    testWidgets('administrateur en lecture seule sur PARAM : aucun bouton', (
      tester,
    ) async {
      await monter(tester, niveau: 'L');
      expect(find.byKey(const Key('$cle-changer')), findsNothing);
    });
  });
}

class _Faux implements TransportSynchronisation {
  _Faux(this.reponse);
  final Map<String, Object?> reponse;
  Uri? derniere;

  @override
  Future<IssueHttp> get(Uri url, {String? jeton}) async {
    derniere = url;
    return ReponseHttp(statut: 200, corps: {'data': reponse});
  }

  @override
  Future<IssueHttp> post(
    Uri url, {
    Map<String, Object?>? corps,
    String? jeton,
  }) => throw UnimplementedError();
}

class _UuidQuiCasse implements Uuid {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('panne simulée');
}
