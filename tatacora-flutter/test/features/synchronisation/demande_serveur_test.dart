import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/synchronisation/data/transport_synchronisation.dart';

import 'support/faux_transport.dart';

/// Le bouton « Synchroniser » du serveur (décision PO du 18/10/2026) : le
/// passage court lit la dernière demande faite à la PWA ; une demande
/// NOUVELLE lance aussitôt la synchronisation complète (envoi, puis
/// descente — qui déclare la file encore à envoyer), une demande déjà suivie
/// ne relance rien.
void main() {
  late BancSync b;

  setUp(() async => b = await BancSync.creer());
  tearDown(() => b.fermer());

  FauxTransport serveur(String? demande) => FauxTransport((r) {
    if (r.url.path.endsWith('/sync/demande')) {
      return ReponseHttp(
        statut: 200,
        corps: {
          'data': {'demandee_le': demande},
        },
      );
    }
    if (r.url.path.endsWith('/referentiels')) {
      return const ReponseHttp(
        statut: 200,
        corps: {
          'data': {'elements': <Object>[], 'correspondances': <Object>[]},
          'meta': {'curseur': 'c1', 'complet': true, 'limite': 200},
        },
      );
    }
    return reponseLot(r);
  });

  test('une demande nouvelle lance la synchronisation complète, une seule '
      'fois ; la descente déclare la file', () async {
    final t = serveur('2026-10-18T10:00:00+00:00');
    final m = b.manager(t, descente: b.descente(t));

    expect(await m.suivreDemandeDuServeur(), isTrue);
    final lecture = t.requetes.first;
    expect(lecture.url.path, endsWith('/sync/demande'));
    expect(lecture.url.queryParameters['poste_id'], BancSync.poste);
    expect(lecture.jeton, BancSync.jeton);
    final descente = t.requetes.lastWhere(
      (r) => r.url.path.endsWith('/referentiels'),
    );
    expect(descente.url.queryParameters['en_attente'], '0');

    final avant = t.requetes.length;
    expect(await m.suivreDemandeDuServeur(), isFalse);
    expect(t.requetes.length, avant + 1, reason: 'la seule lecture');
  });

  test(
    'aucune demande, serveur muet, poste non appairé : rien ne part',
    () async {
      final rien = serveur(null);
      expect(await b.manager(rien).suivreDemandeDuServeur(), isFalse);
      expect(rien.requetes, hasLength(1));

      final muet = FauxTransport((_) => const ServeurInjoignable('coupé'));
      expect(await b.manager(muet).suivreDemandeDuServeur(), isFalse);

      final nu = await BancSync.creer(appaire: false);
      addTearDown(nu.fermer);
      final t = serveur('2026-10-18T10:00:00+00:00');
      expect(await nu.manager(t).suivreDemandeDuServeur(), isFalse);
      expect(t.requetes, isEmpty);
    },
  );
}
