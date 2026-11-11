import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/synchronisation/data/transport_synchronisation.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';
import 'package:uuid/uuid.dart';

import 'support/faux_transport.dart';

/// L'ÉPOQUE du serveur (décision du PO du 03/11/2026, « les données envoyées par un
/// poste reviennent aux autres postes », SANS WebSocket) : le serveur rend un
/// compteur de changements dans la réponse du battement de 30 s ; le poste le
/// compare à la dernière époque vue et, s'il a changé, lance une DESCENTE (pas un
/// envoi, pas un passage complet).
///
/// DEUX postes simulés autour d'UN faux serveur : A envoie, B reçoit via l'époque.
void main() {
  late BancSync a;
  late BancSync b;
  late _FauxServeur serveur;
  late FauxTransport tA;
  late FauxTransport tB;

  setUp(() async {
    a = await BancSync.creer();
    b = await BancSync.creer();
    await a.semerAuteur();
    await b.semerAuteur();
    serveur = _FauxServeur();
    tA = serveur.transport();
    tB = serveur.transport();
  });
  tearDown(() async {
    await a.fermer();
    await b.fermer();
  });

  Future<void> enfilerPoint(BancSync poste, String libelle) async {
    await poste.db.transaction(
      () => poste.dao.enfiler(
        table: TableSynchronisee.pointsStockage,
        entiteId: const Uuid().v4(),
        type: TypeOperationSync.creation,
        payload: {'libelle': libelle, 'type': 'bar'},
      ),
    );
  }

  Future<List<String>> points(BancSync poste) async => [
    for (final p in await poste.db.select(poste.db.pointsStockageLocal).get())
      p.libelle,
  ];

  test(
    'A envoie, B reçoit par l’époque : une DESCENTE, jamais d’envoi',
    () async {
      final mA = a.manager(tA, descente: a.descente(tA));
      final mB = b.manager(tB, descente: b.descente(tB));

      // Avant tout changement : la première lecture de B descend une fois (« une de
      // plus, jamais une de moins »), et B n'envoie rien.
      expect(await mB.suivreDemandeDuServeur(), isTrue);
      expect(tB.descentes, hasLength(1));
      expect(await points(b), isEmpty);

      await enfilerPoint(a, 'Cave');
      await mA.synchroniserMaintenant();
      expect(
        serveur.epoque,
        1,
        reason: 'une opération ACCEPTÉE change l’époque',
      );

      // Le battement de B voit la nouvelle époque.
      expect(await mB.suivreDemandeDuServeur(), isTrue);
      expect(await points(b), ['Cave']);
      expect(tB.lots, isEmpty, reason: 'B n’envoie RIEN : une descente seule');
      expect(tB.descentes, hasLength(2));
    },
  );

  test(
    'REJEU : la même époque ne relance rien (une lecture, pas de descente)',
    () async {
      final mB = b.manager(tB, descente: b.descente(tB));
      await enfilerPoint(a, 'Cave');
      await a.manager(tA, descente: a.descente(tA)).synchroniserMaintenant();

      expect(await mB.suivreDemandeDuServeur(), isTrue);
      final avant = tB.requetes.length;
      expect(await mB.suivreDemandeDuServeur(), isFalse);
      expect(await mB.suivreDemandeDuServeur(), isFalse);
      expect(tB.requetes.length, avant + 2, reason: 'les seules lectures');
      expect(tB.descentes, hasLength(1));
    },
  );

  test('COUPURE RÉSEAU : rien ne casse, l’époque n’est retenue qu’APRÈS une '
      'descente réussie', () async {
    final mB = b.manager(tB, descente: b.descente(tB));
    await enfilerPoint(a, 'Cave');
    await a.manager(tA, descente: a.descente(tA)).synchroniserMaintenant();

    // Le serveur est injoignable : la lecture échoue, B ne lève pas.
    serveur.coupe = true;
    expect(await mB.suivreDemandeDuServeur(), isFalse);
    expect(await points(b), isEmpty);

    // La lecture passe mais la DESCENTE échoue : l'époque n'est pas retenue.
    serveur.coupe = false;
    serveur.descenteCoupee = true;
    expect(await mB.suivreDemandeDuServeur(), isTrue);
    expect(await points(b), isEmpty);

    // Le réseau revient (le repli propre de la descente est échu) : la même
    // époque est rejouée, et B reçoit.
    serveur.descenteCoupee = false;
    b.maintenant = b.maintenant.add(const Duration(minutes: 2));
    expect(await mB.suivreDemandeDuServeur(), isTrue);
    expect(await points(b), ['Cave']);

    // Retenue, maintenant : plus rien à faire.
    expect(await mB.suivreDemandeDuServeur(), isFalse);
  });

  test(
    'un repli non échu n’est PAS martelé toutes les 30 s : l’époque attend',
    () async {
      final mB = b.manager(tB, descente: b.descente(tB));
      await enfilerPoint(a, 'Cave');
      await a.manager(tA, descente: a.descente(tA)).synchroniserMaintenant();
      serveur.descenteCoupee = true;
      await mB.suivreDemandeDuServeur();
      final descentesApresEchec = tB.descentes.length;

      serveur.descenteCoupee = false;
      // Repli non échu (30 s après l'échec) : la descente ne fait aucune requête.
      b.maintenant = b.maintenant.add(const Duration(seconds: 10));
      await mB.suivreDemandeDuServeur();
      expect(tB.descentes.length, descentesApresEchec);
      expect(await points(b), isEmpty);
    },
  );

  test(
    'INTERRUPTEUR éteint : aucune requête, pas même la lecture de l’époque',
    () async {
      await b.ecrivain.enregistrerSynchronisationActivee(
        false,
        par: 'gerant',
        le: DateTime(2026, 10, 15),
      );
      await enfilerPoint(a, 'Cave');
      await a.manager(tA, descente: a.descente(tA)).synchroniserMaintenant();

      final mB = b.manager(tB, descente: b.descente(tB));
      expect(await mB.suivreDemandeDuServeur(), isFalse);
      expect(tB.requetes, isEmpty);
      expect(await points(b), isEmpty);

      // Rallumé : la prochaine lecture descend.
      await b.ecrivain.enregistrerSynchronisationActivee(
        true,
        par: 'gerant',
        le: DateTime(2026, 10, 15),
      );
      expect(await mB.suivreDemandeDuServeur(), isTrue);
      expect(await points(b), ['Cave']);
    },
  );

  test('un serveur d’avant l’époque (champ absent) : le battement ne fait rien '
      'de plus qu’avant', () async {
    serveur.sansEpoque = true;
    final mB = b.manager(tB, descente: b.descente(tB));
    expect(await mB.suivreDemandeDuServeur(), isFalse);
    expect(tB.requetes, hasLength(1));
    expect(tB.descentes, isEmpty);
  });

  test(
    'une synchronisation déjà en cours n’est pas doublée par l’époque',
    () async {
      final mB = b.manager(tB, descente: b.descente(tB));
      await enfilerPoint(a, 'Cave');
      await a.manager(tA, descente: a.descente(tA)).synchroniserMaintenant();

      final enCours = mB.synchroniserMaintenant();
      expect(await mB.suivreDemandeDuServeur(), isFalse);
      await enCours;
      // La descente du passage complet a tout reçu ; la lecture suivante rattrape
      // l'époque sans rien changer d'autre.
      expect(await points(b), ['Cave']);
    },
  );

  test('un faux pas du serveur : une demande « Synchroniser » ET une époque '
      'nouvelle ne font qu’UN passage complet', () async {
    serveur.demande = '2026-11-03T10:00:00+00:00';
    final mB = b.manager(tB, descente: b.descente(tB));
    expect(await mB.suivreDemandeDuServeur(), isTrue);
    final avant = tB.requetes.length;
    expect(await mB.suivreDemandeDuServeur(), isFalse);
    expect(tB.requetes.length, avant + 1);
  });

  test('le battement tourne même en mode « Manuelle seulement » (relu dans le '
      'code) : seul le minuteur périodique est annulé', () {
    final code = File(
      'lib/features/synchronisation/presentation/providers_synchronisation.dart',
    ).readAsStringSync();
    // Le passage court est armé SANS condition sur la fréquence…
    final passageCourt = RegExp(
      r'final passageCourt = Timer\.periodic\(\s*periodeDemandeServeur',
    );
    expect(passageCourt.hasMatch(code), isTrue);
    // … tandis que `armer` ne gouverne que le minuteur de la fréquence choisie.
    expect(code, contains('minuteur = periode == null'));
    final avantArmer = code.substring(
      0,
      code.indexOf('armer(FrequenceSynchronisation.parDefaut)'),
    );
    expect(avantArmer, isNot(contains('passageCourt')));
  });
}

/// Un faux serveur partagé par les deux postes.
final class _FauxServeur {
  int epoque = 0;
  bool coupe = false;
  bool descenteCoupee = false;
  bool sansEpoque = false;
  String? demande;
  final _catalogue = FauxCatalogue(<Map<String, Object?>>[]);

  FauxTransport transport() => FauxTransport((r) {
    if (coupe) return const ServeurInjoignable('coupé');
    if (r.url.path.endsWith('/sync/demande')) {
      return ReponseHttp(
        statut: 200,
        corps: {
          'data': {
            'demandee_le': demande,
            if (!sansEpoque) 'epoque': 'x.$epoque',
          },
        },
      );
    }
    if (r.url.path.endsWith('/referentiels')) {
      if (descenteCoupee) return const ServeurInjoignable('coupé');
      return _catalogue.repondre(r);
    }
    return reponseLot(
      r,
      particulier: (op) {
        if (op['table'] == 'points_stockage') {
          _catalogue.elements.add(
            element(
              'points_stockage',
              op['entite_id']! as String,
              (op['payload']! as Map).cast<String, Object?>(),
            ),
          );
        }
        epoque++;
        return null;
      },
    );
  });
}
