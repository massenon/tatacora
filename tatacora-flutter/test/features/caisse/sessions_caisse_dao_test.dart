import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/common.dart' show SqliteException;
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/caisse/data/sessions_caisse_dao.dart';
import 'package:tatacora_flutter/features/caisse/domain/entities/session_caisse.dart';
import 'package:tatacora_flutter/features/caisse/domain/messages_caisse.dart';
import 'package:tatacora_flutter/features/caisse/domain/regles_caisse.dart';

import '../comptabilite/support/outils_comptabilite.dart';
import 'support/outils_caisse.dart';

/// `SessionsCaisseDao` sur une vraie base locale : ce qui est ÉCRIT, ce qui est
/// REFUSÉ, et l'ordre dans lequel les refus tombent.
///
/// Le comportement du serveur est confronté à part (`caisse_contre_serveur_test`,
/// le vrai composant PHP) ; ce fichier tient les propriétés propres au poste :
/// l'atomicité, l'absence de pièce comptable, la clé étrangère, les deux
/// lectures « session ouverte ».
void main() {
  late AppDatabase db;
  late SessionsCaisseDao dao;

  setUp(() async {
    db = await baseCaisse();
    dao = daoCaisseSur(db);
  });

  tearDown(() => db.close());

  Future<SessionCaisse> ouvrir(
    String fond, {
    PointDeVenteCaisse point = PointDeVenteCaisse.bar,
    bool peutEcrire = true,
    String auteur = ouvreurEssai,
  }) => dao.ouvrir(
    point: point,
    fondSaisi: fond,
    auteurId: auteur,
    peutEcrire: peutEcrire,
  );

  group('ouvrir', () {
    test(
      'écrit UNE ligne : point, auteur (RG-15), date, fond en centimes',
      () async {
        final s = await ouvrir('25000');

        final lues = await db.select(db.sessionsCaisseLocal).get();
        expect(lues, hasLength(1));
        expect(lues.single.id, s.id);
        expect(lues.single.pointVente, 'bar');
        expect(lues.single.utilisateurOuvertureId, ouvreurEssai);
        expect(lues.single.dateOuverture, ouvertureDeReference);
        expect(lues.single.montantFondCentimes, 2500000);
        // Ouverte : rien de la clôture n'est écrit.
        expect(lues.single.dateCloture, isNull);
        expect(lues.single.montantTheoriqueCentimes, isNull);
        expect(lues.single.montantConstateCentimes, isNull);
      },
    );

    test('le fond est ARRONDI comme DECIMAL(15,2), jamais tronqué', () async {
      final s = await ouvrir('1000.555');
      expect(s.fondCentimes, 100056);
    });

    test(
      'une seconde caisse au MÊME point est refusée, rien n’est écrit',
      () async {
        await ouvrir('10000');

        await expectLater(
          ouvrir('99999'),
          throwsA(
            isA<RefusCaisse>()
                .having(
                  (e) => e.message,
                  'message',
                  MessagesCaisse.refusDejaOuverte,
                )
                .having((e) => e.champ, 'champ', ChampCaisse.fond),
          ),
        );
        final lues = await db.select(db.sessionsCaisseLocal).get();
        expect(lues, hasLength(1));
        expect(lues.single.montantFondCentimes, 1000000);
      },
    );

    test('une caisse OUVERTE à un autre point ne bloque pas celle-ci (comme '
        'le serveur)', () async {
      await ouvrir('20000', point: PointDeVenteCaisse.reception);
      final bar = await ouvrir('10000');

      expect(bar.point, PointDeVenteCaisse.bar);
      expect((await dao.sessions()), hasLength(2));
    });

    test('une caisse CLOSE n’empêche pas d’en ouvrir une nouvelle', () async {
      await ouvrir('10000');
      await dao.cloturer(
        point: PointDeVenteCaisse.bar,
        constateSaisi: '10000',
        peutEcrire: true,
        especesEncaisseesCentimes: 0,
      );
      final seconde = await ouvrir('15000');

      expect(seconde.estOuverte, isTrue);
      expect(await dao.sessions(), hasLength(2));
    });

    test(
      'le droit est contrôlé AVANT la validation (le serveur répond 403)',
      () async {
        // Un fond invalide ET pas de droit : c'est le droit qui parle.
        await expectLater(
          ouvrir('abc', peutEcrire: false),
          throwsA(
            isA<RefusCaisse>()
                .having((e) => e.message, 'message', MessagesCaisse.refusDroit)
                .having((e) => e.champ, 'champ', isNull),
          ),
        );
        expect(await compterLignes(db, 'sessions_caisse_local'), 0);
      },
    );

    test('la forme est contrôlée AVANT « déjà ouverte »', () async {
      await ouvrir('10000');

      await expectLater(
        ouvrir(''),
        throwsA(
          isA<RefusCaisse>().having(
            (e) => e.message,
            'message',
            'Le champ fond caisse saisi est obligatoire.',
          ),
        ),
      );
    });

    test(
      '« déjà ouverte » est contrôlé AVANT la plage de la colonne',
      () async {
        await ouvrir('10000');

        await expectLater(
          ouvrir('99999999999999999'),
          throwsA(
            isA<RefusCaisse>().having(
              (e) => e.message,
              'message',
              MessagesCaisse.refusDejaOuverte,
            ),
          ),
        );
      },
    );

    test('un fond hors plage est refusé, rien n’est écrit', () async {
      await expectLater(
        ouvrir('99999999999999999'),
        throwsA(
          isA<RefusCaisse>().having(
            (e) => e.message,
            'message',
            MessagesCaisse.horsPlage,
          ),
        ),
      );
      expect(await compterLignes(db, 'sessions_caisse_local'), 0);
    });

    test('sans auteur, la caisse ne s’ouvre pas (RG-15)', () async {
      await expectLater(
        ouvrir('10000', auteur: ''),
        throwsA(isA<RefusCaisse>()),
      );
      expect(await compterLignes(db, 'sessions_caisse_local'), 0);
    });

    test('un auteur INCONNU est refusé par la clé étrangère réelle', () async {
      await expectLater(
        ouvrir('10000', auteur: 'fantome'),
        throwsA(isA<SqliteException>()),
      );
      expect(await compterLignes(db, 'sessions_caisse_local'), 0);
    });
  });

  group('clôturer', () {
    test('écrit la date, le constaté et le théorique, ne touche ni le fond ni '
        'l’ouvreur', () async {
      final ouverte = await ouvrir('25000');
      final horlogeCloture = ouvertureDeReference.add(const Duration(hours: 9));
      final daoCloture = daoCaisseSur(db, horloge: horlogeCloture);

      final c = await daoCloture.cloturer(
        point: PointDeVenteCaisse.bar,
        constateSaisi: '37500.50',
        peutEcrire: true,
        especesEncaisseesCentimes: 1234567,
      );

      final l = (await db.select(db.sessionsCaisseLocal).get()).single;
      expect(l.id, ouverte.id);
      expect(l.dateCloture, horlogeCloture);
      expect(l.montantConstateCentimes, 3750050);
      // théorique = fond 25 000 + espèces 12 345,67
      expect(l.montantTheoriqueCentimes, 2500000 + 1234567);
      expect(l.montantFondCentimes, 2500000);
      expect(l.utilisateurOuvertureId, ouvreurEssai);
      expect(l.dateOuverture, ouvertureDeReference);
      // L'écart est ANNONCÉ, jamais stocké : constaté 37 500,50 - 37 345,67.
      expect(c.ecartCentimes, 3750050 - (2500000 + 1234567));
      expect(c.session.estOuverte, isFalse);
    });

    test('une session ouverte sans ses espèces est une ERREUR D’APPEL : le '
        'serveur calcule TOUJOURS le théorique, le poste ne le fabrique pas '
        'null', () async {
      // Avant le lot 5 (12/10/2026) ce cas rendait un théorique `null` : le poste
      // n'avait aucune vente rattachée à une session. Il en a une source ; la
      // branche « sans théorique » n'existe plus, et l'oublier de la fournir
      // lève au lieu de clore une caisse sans écart.
      await ouvrir('25000');

      await expectLater(
        dao.cloturer(
          point: PointDeVenteCaisse.bar,
          constateSaisi: '24500',
          peutEcrire: true,
        ),
        throwsA(isA<StateError>()),
      );

      final l = (await db.select(db.sessionsCaisseLocal).get()).single;
      expect(l.dateCloture, isNull, reason: 'la session reste ouverte');
      expect(l.montantTheoriqueCentimes, isNull);
      expect(l.montantConstateCentimes, isNull);
    });

    test(
      'zéro espèce n’est pas « inconnu » : le théorique est le fond',
      () async {
        await ouvrir('25000');

        final c = await dao.cloturer(
          point: PointDeVenteCaisse.bar,
          constateSaisi: '25000',
          peutEcrire: true,
          especesEncaisseesCentimes: 0,
        );

        expect(c.session.theoriqueCentimes, 2500000);
        expect(c.ecartCentimes, 0);
      },
    );

    test('sans caisse ouverte : refus aux mots du serveur, sous le montant '
        'compté', () async {
      await expectLater(
        dao.cloturer(
          point: PointDeVenteCaisse.bar,
          constateSaisi: '1000',
          peutEcrire: true,
        ),
        throwsA(
          isA<RefusCaisse>()
              .having(
                (e) => e.message,
                'message',
                MessagesCaisse.refusSansCaisse,
              )
              .having((e) => e.champ, 'champ', ChampCaisse.constate),
        ),
      );
    });

    test(
      'une caisse ouverte à un AUTRE point ne se clôture pas par ce point',
      () async {
        await ouvrir('20000', point: PointDeVenteCaisse.reception);

        await expectLater(
          dao.cloturer(
            point: PointDeVenteCaisse.bar,
            constateSaisi: '20000',
            peutEcrire: true,
          ),
          throwsA(isA<RefusCaisse>()),
        );
        final l = (await db.select(db.sessionsCaisseLocal).get()).single;
        expect(l.dateCloture, isNull, reason: 'la réception reste ouverte');
      },
    );

    test('ne clôt QUE la session du point visé', () async {
      await ouvrir('20000', point: PointDeVenteCaisse.reception);
      await ouvrir('10000');

      await dao.cloturer(
        point: PointDeVenteCaisse.bar,
        constateSaisi: '10000',
        peutEcrire: true,
        especesEncaisseesCentimes: 0,
      );

      final par = {for (final s in await dao.sessions()) s.point: s.estOuverte};
      expect(par[PointDeVenteCaisse.bar], isFalse);
      expect(par[PointDeVenteCaisse.reception], isTrue);
    });

    test('un montant mal formé pour bcsub est refusé APRÈS « aucune caisse » '
        'et AVANT d’écrire', () async {
      // Sans caisse : « aucune caisse » d'abord (comme le serveur).
      await expectLater(
        dao.cloturer(
          point: PointDeVenteCaisse.bar,
          constateSaisi: '1.5e3',
          peutEcrire: true,
        ),
        throwsA(
          isA<RefusCaisse>().having(
            (e) => e.message,
            'message',
            MessagesCaisse.refusSansCaisse,
          ),
        ),
      );

      await ouvrir('1000');
      await expectLater(
        dao.cloturer(
          point: PointDeVenteCaisse.bar,
          constateSaisi: '1.5e3',
          peutEcrire: true,
        ),
        throwsA(
          isA<RefusCaisse>().having(
            (e) => e.message,
            'message',
            MessagesCaisse.malForme,
          ),
        ),
      );
      expect((await dao.sessionOuverte(PointDeVenteCaisse.bar)), isNotNull);
    });

    test(
      'un constaté hors plage est refusé, la session reste ouverte',
      () async {
        await ouvrir('1000');

        await expectLater(
          dao.cloturer(
            point: PointDeVenteCaisse.bar,
            constateSaisi: '99999999999999999',
            peutEcrire: true,
            especesEncaisseesCentimes: 0,
          ),
          throwsA(
            isA<RefusCaisse>().having(
              (e) => e.message,
              'message',
              MessagesCaisse.horsPlage,
            ),
          ),
        );
        final l = (await db.select(db.sessionsCaisseLocal).get()).single;
        expect(l.dateCloture, isNull);
        expect(l.montantConstateCentimes, isNull);
      },
    );

    test(
      'le droit est contrôlé AVANT tout, la session reste ouverte',
      () async {
        await ouvrir('1000');

        await expectLater(
          dao.cloturer(
            point: PointDeVenteCaisse.bar,
            constateSaisi: 'abc',
            peutEcrire: false,
          ),
          throwsA(
            isA<RefusCaisse>().having(
              (e) => e.message,
              'message',
              MessagesCaisse.refusDroit,
            ),
          ),
        );
        expect((await dao.sessionOuverte(PointDeVenteCaisse.bar)), isNotNull);
      },
    );

    test(
      'l’écart annoncé est TRONQUÉ, le constaté stocké est ARRONDI',
      () async {
        await ouvrir('1500');

        final c = await dao.cloturer(
          point: PointDeVenteCaisse.bar,
          constateSaisi: '1500.999',
          peutEcrire: true,
          especesEncaisseesCentimes: 0,
        );

        expect(c.ecartCentimes, 99);
        expect(c.session.constateCentimes, 150100);
      },
    );
  });

  group('les deux lectures « session ouverte »', () {
    test('par point : celle du POS ; tous points : celle de l’encaissement de '
        'facture et de l’indicateur', () async {
      await ouvrir('20000', point: PointDeVenteCaisse.reception);
      final daoBar = daoCaisseSur(
        db,
        horloge: ouvertureDeReference.add(const Duration(minutes: 5)),
      );
      await daoBar.ouvrir(
        point: PointDeVenteCaisse.bar,
        fondSaisi: '10000',
        auteurId: ouvreurEssai,
        peutEcrire: true,
      );

      expect(
        (await dao.sessionOuverte(PointDeVenteCaisse.reception))!.point,
        PointDeVenteCaisse.reception,
      );
      expect(
        (await dao.sessionOuverte(PointDeVenteCaisse.bar))!.point,
        PointDeVenteCaisse.bar,
      );
      expect(await dao.sessionOuverte(PointDeVenteCaisse.restaurant), isNull);
      // La plus RÉCENTE, tous points confondus : le bar, ouvert 5 min plus tard.
      expect(
        (await dao.sessionOuverteLaPlusRecente())!.point,
        PointDeVenteCaisse.bar,
      );
    });

    test('la plus récente ignore les sessions closes', () async {
      await ouvrir('20000', point: PointDeVenteCaisse.reception);
      final plusTard = daoCaisseSur(
        db,
        horloge: ouvertureDeReference.add(const Duration(minutes: 5)),
      );
      await plusTard.ouvrir(
        point: PointDeVenteCaisse.bar,
        fondSaisi: '10000',
        auteurId: ouvreurEssai,
        peutEcrire: true,
      );
      await plusTard.cloturer(
        point: PointDeVenteCaisse.bar,
        constateSaisi: '10000',
        peutEcrire: true,
        especesEncaisseesCentimes: 0,
      );

      expect(
        (await dao.sessionOuverteLaPlusRecente())!.point,
        PointDeVenteCaisse.reception,
      );
    });

    test('aucune session : null, jamais une session fabriquée', () async {
      expect(await dao.sessionOuverteLaPlusRecente(), isNull);
      expect(await dao.sessionOuverte(PointDeVenteCaisse.bar), isNull);
      expect(await dao.sessions(), isEmpty);
    });
  });

  group('la caisse n’est PAS un mouvement d’argent du grand livre', () {
    test('ouvrir et clôturer n’écrivent aucune pièce comptable (le serveur '
        'n’en passe aucune)', () async {
      // Le référentiel est INSTALLÉ : si un geste de caisse passait une pièce,
      // il le pourrait. Aucune ne naît.
      await baseInstalleeSur(db, ouvertureDeReference);
      final avant = await compterLignes(db, 'ecritures_local');
      final sequencesAvant = await compterLignes(db, 'sequences_piece_local');

      await ouvrir('25000');
      await dao.cloturer(
        point: PointDeVenteCaisse.bar,
        constateSaisi: '25000',
        peutEcrire: true,
        especesEncaisseesCentimes: 0,
      );

      expect(await compterLignes(db, 'ecritures_local'), avant);
      expect(await compterLignes(db, 'sequences_piece_local'), sequencesAvant);
    });
  });

  group('le registre fermé des points', () {
    test(
      'la base refuse un point que le serveur ne connaît pas (CHECK)',
      () async {
        await expectLater(
          db
              .into(db.sessionsCaisseLocal)
              .insert(
                SessionsCaisseLocalCompanion.insert(
                  id: 'x',
                  pointVente: 'plage',
                  utilisateurOuvertureId: ouvreurEssai,
                  dateOuverture: ouvertureDeReference,
                  montantFondCentimes: 0,
                ),
              ),
          throwsA(isA<SqliteException>()),
        );
      },
    );

    test('la clé étrangère de l’ouvreur est réelle', () async {
      await expectLater(
        db
            .into(db.sessionsCaisseLocal)
            .insert(
              SessionsCaisseLocalCompanion.insert(
                id: 'y',
                pointVente: 'bar',
                utilisateurOuvertureId: 'fantome',
                dateOuverture: ouvertureDeReference,
                montantFondCentimes: 0,
              ),
            ),
        throwsA(isA<SqliteException>()),
      );
    });
  });
}
