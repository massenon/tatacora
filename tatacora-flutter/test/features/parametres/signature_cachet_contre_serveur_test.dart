@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/facturation/data/depot_images_document.dart';
import 'package:tatacora_flutter/features/facturation/data/images_document_poste.dart';
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/data/telechargement_images_document.dart';
import 'package:tatacora_flutter/features/synchronisation/data/transport_synchronisation.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';

import '../comptabilite/support/outils_comptabilite.dart';

/// Signature et cachet déposés DEPUIS LE POSTE, CONTRE le vrai moteur du serveur (11/11/2026).
///
/// `tool/facturation/rejouer_images_document.php` pousse les opérations EXACTES de la file du
/// poste A (compte d'appairage : un barman) au vrai `SynchronisationService`, puis rend ce que la
/// descente livrerait. Le poste B (vide) et le poste A redescendent : l'image déposée au poste
/// arrive aux autres postes, sans boucle ; une image déposée au web (le service du web) arrive au
/// poste. Base privée : `TATACORA_BASE_ESSAI=tatacora_<nom>_test`.
Uint8List _png(int cote) => Uint8List.fromList(
  img.encodePng(
    img.Image(width: cote, height: cote)..clear(img.ColorRgb8(1, 2, 3)),
  ),
);

Uint8List _grosPng() {
  final image = img.Image(width: 900, height: 900);
  var v = 4242;
  for (final p in image) {
    v = (v * 1103515245 + 12345) & 0x7fffffff;
    p
      ..r = v & 255
      ..g = (v >> 8) & 255
      ..b = (v >> 16) & 255;
  }
  return Uint8List.fromList(img.encodePng(image));
}

class _Serveur implements TransportSynchronisation {
  _Serveur(this.data);
  final Map<String, Object?> data;
  Uri? derniere;

  @override
  Future<IssueHttp> get(Uri url, {String? jeton}) async {
    derniere = url;
    // Comme `ImagesDocumentController` : pas d'octets si l'empreinte annoncée est la bonne.
    final reponse = <String, Object?>{};
    for (final nature in ['signature', 'cachet']) {
      final d = data[nature];
      if (d is! Map) {
        reponse[nature] = null;
        continue;
      }
      reponse[nature] = {
        'empreinte': d['empreinte'],
        'type': 'image/png',
        'octets_base64': url.queryParameters[nature] == d['empreinte']
            ? null
            : d['octets_base64'],
      };
    }
    return ReponseHttp(statut: 200, corps: {'data': reponse});
  }

  @override
  Future<IssueHttp> post(
    Uri url, {
    Map<String, Object?>? corps,
    String? jeton,
  }) => throw UnimplementedError();
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late Directory dossierA;
  late Directory dossierB;
  late ImagesDocumentPoste imagesA;
  late ImagesDocumentPoste imagesB;

  setUp(() {
    db = AppDatabase.enMemoire();
    dossierA = Directory.systemTemp.createTempSync('poste_a_');
    dossierB = Directory.systemTemp.createTempSync('poste_b_');
    imagesA = ImagesDocumentPoste(() async => dossierA);
    imagesB = ImagesDocumentPoste(() async => dossierB);
  });
  tearDown(() async {
    await db.close();
    dossierA.deleteSync(recursive: true);
    dossierB.deleteSync(recursive: true);
  });

  /// Pousse la file du poste A au serveur, consigne les résultats, rend la réponse du script.
  Future<Map<String, dynamic>> pousser({
    Map<String, String?> prealable = const {},
  }) async {
    final dao = OperationsSyncDao(db);
    final ops = await dao.operations(
      table: TableSynchronisee.depotsImagesDocument,
    );
    final reponse = await executerPhp(
      'rejouer_images_document.php',
      dossier: 'facturation',
      entree: {
        'prealable': prealable,
        'operations': [
          for (final o in ops)
            {
              'uuid_operation': o.uuidOperation,
              'table': o.table.nomServeur,
              'type': o.type.code,
              'entite_id': o.entiteId,
              'payload': jsonDecode(o.payload),
              'horodatage_client': o.horodatageClient,
            },
        ],
      },
    );
    final resultats = reponse['resultats'] as List;
    expect(resultats, hasLength(ops.length));
    for (var i = 0; i < ops.length; i++) {
      final r = Map<String, Object?>.from(resultats[i] as Map);
      await dao.marquerResultat(ops[i].uuidOperation, resultat: r);
    }
    return reponse;
  }

  Future<int> descendre(
    ImagesDocumentPoste images,
    Map<String, dynamic> reponse,
  ) => TelechargementImagesDocument(
    _Serveur(Map<String, Object?>.from(reponse['descente'] as Map)),
    images,
  ).rafraichir(serveur: 'https://s.test', posteId: 'p', jeton: 't');

  test(
    'poste A dépose signature et cachet : le serveur les range comme le web, '
    'le poste B les reçoit octet pour octet, A ne les redescend pas',
    () async {
      final depot = DepotImagesDocumentPoste(db, imagesA);
      final signature = _png(8);
      final cachet = _png(16);
      await depot.deposer(ImageDocument.signature, signature);
      await depot.deposer(ImageDocument.cachet, cachet);

      final reponse = await pousser();
      for (final r in reponse['resultats'] as List) {
        expect((r as Map)['statut'], 'synchronise', reason: '$r');
      }
      expect(
        (reponse['descente'] as Map)['signature']['octets_base64'],
        base64Encode(signature),
      );

      expect(await descendre(imagesB, reponse), 2);
      expect(await imagesB.lire(ImageDocument.signature), signature);
      expect(await imagesB.lire(ImageDocument.cachet), cachet);

      // A : tout est accusé, rien en suspens, et l'empreinte rend 0 changement (pas de boucle).
      expect(await depot.naturesEnSuspens(), isEmpty);
      expect(await descendre(imagesA, reponse), 0);
      expect(await imagesA.lire(ImageDocument.signature), signature);
    },
  );

  test('une image lourde est réduite AU POSTE, le serveur la garde telle '
      'quelle : même empreinte des deux côtés', () async {
    final depot = DepotImagesDocumentPoste(db, imagesA);
    await depot.deposer(ImageDocument.signature, _grosPng());
    final locale = (await imagesA.lire(ImageDocument.signature))!;
    expect(locale.length, lessThanOrEqualTo(400 * 1024));

    final reponse = await pousser();
    expect((reponse['resultats'] as List).single['statut'], 'synchronise');
    expect(
      (reponse['descente'] as Map)['signature']['empreinte'],
      ImagesDocumentPoste.empreinteDe(locale),
    );
    expect(await descendre(imagesA, reponse), 0);
  });

  test('le retrait du poste retire l’image au serveur, donc aux autres '
      'postes', () async {
    final depot = DepotImagesDocumentPoste(db, imagesA);
    await depot.deposer(ImageDocument.cachet, _png(8));
    await depot.retirer(ImageDocument.cachet);

    final reponse = await pousser();
    expect((reponse['resultats'] as List).map((r) => (r as Map)['statut']), [
      'synchronise',
      'synchronise',
    ]);
    expect((reponse['descente'] as Map)['cachet'], isNull);

    // Le poste B avait reçu le cachet d'avant : la descente le lui retire.
    await imagesB.ranger(ImageDocument.cachet, _png(8));
    expect(await descendre(imagesB, reponse), 1);
    expect(await imagesB.lire(ImageDocument.cachet), isNull);
  });

  test('une image déposée au WEB (service du web) arrive au poste', () async {
    final duWeb = _png(24);
    final reponse = await pousser(
      prealable: {'signature': base64Encode(duWeb)},
    );
    expect(await descendre(imagesA, reponse), 1);
    expect(await imagesA.lire(ImageDocument.signature), duWeb);
  });
}
