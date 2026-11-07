import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/facturation/data/images_document_poste.dart';
import 'package:tatacora_flutter/features/synchronisation/data/telechargement_images_document.dart';
import 'package:tatacora_flutter/features/synchronisation/data/transport_synchronisation.dart';

/// La SIGNATURE et le CACHET descendent du serveur (07/11/2026) : seule une image CHANGÉE est
/// renvoyée (l'empreinte suffit), une image retirée du serveur l'est du poste, une image
/// illisible n'est jamais rangée.
final _png = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3, 4];

class _Faux implements TransportSynchronisation {
  _Faux(this.reponse);
  Map<String, Object?> reponse;
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

void main() {
  late Directory dossier;
  late ImagesDocumentPoste images;

  setUp(() {
    dossier = Directory.systemTemp.createTempSync('images_doc');
    images = ImagesDocumentPoste(() async => dossier);
  });
  tearDown(() => dossier.deleteSync(recursive: true));

  Map<String, Object?> image(List<int> o, {bool octets = true}) => {
    'empreinte': ImagesDocumentPoste.empreinteDe(o),
    'type': 'image/png',
    'octets_base64': octets ? base64Encode(o) : null,
  };

  Future<int> rafraichir(_Faux t) => TelechargementImagesDocument(
    t,
    images,
  ).rafraichir(serveur: 'https://s.test', posteId: 'p', jeton: 't');

  test(
    'une image nouvelle est rangée ; inchangée, elle n\'est pas renvoyée',
    () async {
      final t = _Faux({'signature': image(_png), 'cachet': null});
      expect(await rafraichir(t), 1);
      expect(await images.lire(ImageDocument.signature), _png);
      expect(await images.lire(ImageDocument.cachet), isNull);

      // Le poste annonce son empreinte ; le serveur répond sans octets : rien ne change.
      t.reponse = {'signature': image(_png, octets: false), 'cachet': null};
      expect(await rafraichir(t), 0);
      expect(
        t.derniere!.queryParameters['signature'],
        ImagesDocumentPoste.empreinteDe(_png),
      );
      expect(await images.lire(ImageDocument.signature), _png);
    },
  );

  test('une image retirée du serveur est retirée du poste', () async {
    await images.ranger(ImageDocument.cachet, _png);
    expect(await rafraichir(_Faux({'signature': null, 'cachet': null})), 1);
    expect(await images.lire(ImageDocument.cachet), isNull);
  });

  test('une image illisible ou trop lourde n\'est jamais rangée', () async {
    final t = _Faux({
      'signature': {
        'octets_base64': base64Encode([1, 2, 3, 4, 5, 6, 7, 8]),
      },
      'cachet': {
        'octets_base64': base64Encode([..._png, ...List.filled(401 * 1024, 0)]),
      },
    });
    expect(await rafraichir(t), 0);
    expect(await images.lire(ImageDocument.signature), isNull);
    expect(await images.lire(ImageDocument.cachet), isNull);
  });
}
