import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Variable;

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/refus_comptable.dart';
import 'package:tatacora_flutter/features/depenses/data/depense_dao.dart';
import 'package:tatacora_flutter/features/depenses/data/recus_depenses_locaux.dart';
import 'package:tatacora_flutter/features/depenses/domain/categories_depense.dart';
import 'package:tatacora_flutter/features/depenses/domain/entities/depense.dart';
import 'package:tatacora_flutter/features/depenses/domain/recu_depense.dart';

import '../comptabilite/support/outils_comptabilite.dart';
import 'support/corpus_recus.dart';
import 'support/outils_depenses.dart';

/// Le reçu d'une dépense DANS la base du poste (lot L4, 27/10/2026, schéma v42) :
/// le fichier est rangé hors de Drift (`recus_depenses/` à côté de `poste.json`),
/// la ligne n'en garde que la référence, et son ÉTAT ne se dit que de ce que le
/// serveur a accusé.
void main() {
  late AppDatabase db;
  late Directory dossier;
  late RecusDepensesLocaux recus;
  late DepenseDao dao;

  setUp(() async {
    db = await baseDepenses();
    dossier = await Directory.systemTemp.createTemp('tatacora_recus_');
    recus = RecusDepensesLocaux(() async => Directory('${dossier.path}/r'));
    dao = DepenseDao(
      db,
      maintenant: () => jourDeReference,
      moteur: () async => moteurSur(db, maintenant: () => jourDeReference),
      recus: recus,
    );
  });

  tearDown(() async {
    await db.close();
    if (dossier.existsSync()) await dossier.delete(recursive: true);
  });

  const ligne = SaisieLigneDepense(
    libelle: 'Tomates',
    compteCharge: '6011',
    nature: NatureDepense.tomate,
    montant: 8500,
  );

  Future<Depense> saisir({RecuAJoindre? recu, String compte = '6011'}) async =>
      dao.enregistrer(
        dateTransaction: DateTime(2026, 10, 9),
        tresorerie: TresorerieDepense.caisse,
        libelle: 'Marché',
        auteurId: auteurDepense,
        centreId: await centreDe(db, 'Restaurant'),
        lignes: [
          SaisieLigneDepense(
            libelle: ligne.libelle,
            compteCharge: compte,
            nature: ligne.nature,
            montant: ligne.montant,
          ),
        ],
        recu: recu,
      );

  RecuAJoindre png([String nom = 'ticket.png']) =>
      RecuAJoindre(nom: nom, octets: octetsPng(), type: TypeRecu.png);

  Future<Map<String, Object?>> colonnes(String id) async =>
      (await db
              .customSelect(
                'SELECT recu_nom, recu_sha256, recu_taille, recu_type, '
                'recu_statut, recu_cause FROM depenses_local WHERE id = ?',
                variables: [Variable.withString(id)],
              )
              .getSingle())
          .data;

  group('à la saisie', () {
    test('sans reçu : « sans reçu », aucune colonne n’est fabriquée, aucun '
        'fichier n’est écrit', () async {
      final d = await saisir();
      expect(d.recu, isNull);
      for (final v in (await colonnes(d.id)).values) {
        expect(v, isNull);
      }
      expect(Directory('${dossier.path}/r').existsSync(), isFalse);
    });

    test(
      'avec reçu : le FICHIER est rangé hors de la base, la ligne garde la '
      'référence (nom, empreinte, taille, type), l’état est « en attente »',
      () async {
        final octets = octetsPng();
        final d = await saisir(recu: png());

        final fichier = File('${dossier.path}/r/${d.id}.png');
        expect(fichier.existsSync(), isTrue);
        expect(fichier.readAsBytesSync(), octets);

        final c = await colonnes(d.id);
        expect(c['recu_nom'], '${d.id}.png');
        expect(c['recu_sha256'], RecusDepensesLocaux.empreinte(octets));
        expect(c['recu_taille'], octets.length);
        expect(c['recu_type'], 'image/png');
        expect(c['recu_statut'], 'en_attente');
        expect(c['recu_cause'], isNull);

        expect(d.recu!.statut, StatutRecu.enAttente);
        expect(d.recu!.estLocal, isTrue);
        expect(d.recu!.sha256, RecusDepensesLocaux.empreinte(octets));
      },
    );

    test('le blob n’entre JAMAIS dans la base : aucune colonne ne porte les '
        'octets du fichier', () async {
      final d = await saisir(recu: png());
      final toutes = await db
          .customSelect(
            'SELECT * FROM depenses_local WHERE id = ?',
            variables: [Variable.withString(d.id)],
          )
          .getSingle();
      for (final v in toutes.data.values) {
        expect(v is List<int>, isFalse, reason: 'aucun blob dans la ligne');
      }
    });

    test('un fichier que le web refuserait est refusé AVANT tout : aucune '
        'dépense, aucun fichier', () async {
      await expectLater(
        saisir(
          recu: RecuAJoindre(
            nom: 'note.png',
            octets: octetsPng()..fillRange(0, 4, 0),
            type: TypeRecu.png,
          ),
        ),
        throwsA(
          isA<RefusDepense>().having(
            (r) => r.message,
            'message',
            TextesRecu.nonImage,
          ),
        ),
      );
      expect(await compter(db, 'depenses_local'), 0);
      expect(Directory('${dossier.path}/r').existsSync(), isFalse);
    });

    test('une image de plus de 400 Ko est RÉDUITE avant d’être rangée (PO, '
        '28/10/2026) : le fichier, l’empreinte et la taille sont ceux de '
        'l’image réduite, jamais ceux de l’original', () async {
      final lourde = imageLourdePng(largeur: 900, hauteur: 600);
      expect(lourde.length, greaterThan(tailleMaxRecuOctets));

      final d = await saisir(
        recu: RecuAJoindre(nom: 'gros.png', octets: lourde, type: TypeRecu.png),
      );

      final c = await colonnes(d.id);
      expect(c['recu_nom'], '${d.id}.jpg');
      expect(c['recu_type'], 'image/jpeg');
      expect(c['recu_taille'] as int, lessThanOrEqualTo(tailleMaxRecuOctets));
      final fichier = File('${dossier.path}/r/${d.id}.jpg');
      expect(fichier.existsSync(), isTrue);
      final octets = fichier.readAsBytesSync();
      expect(octets.length, c['recu_taille']);
      expect(c['recu_sha256'], RecusDepensesLocaux.empreinte(octets));
      // Aucun fichier sous l'extension d'origine.
      expect(File('${dossier.path}/r/${d.id}.png').existsSync(), isFalse);
    });

    test('une image lourde ILLISIBLE est refusée avant tout (le seul refus '
        'qui reste pour une image) : aucune dépense, aucun fichier', () async {
      final abimee = Uint8List.fromList(imageLourdePng())
        ..fillRange(100, 450 * 1024, 0);
      await expectLater(
        saisir(
          recu: RecuAJoindre(nom: 'x.png', octets: abimee, type: TypeRecu.png),
        ),
        throwsA(
          isA<RefusDepense>().having(
            (r) => r.message,
            'message',
            TextesRecu.illisible,
          ),
        ),
      );
      expect(await compter(db, 'depenses_local'), 0);
      expect(Directory('${dossier.path}/r').existsSync(), isFalse);
    });

    test('une pièce refusée par le moteur ne laisse AUCUN fichier orphelin '
        '(le fichier est retiré)', () async {
      await expectLater(saisir(recu: png(), compte: '9999'), throwsA(anything));
      expect(await compter(db, 'depenses_local'), 0);
      final restant = Directory('${dossier.path}/r').existsSync()
          ? Directory('${dossier.path}/r').listSync()
          : <FileSystemEntity>[];
      expect(restant, isEmpty);
    });

    test(
      'un refus comptable (centre manquant, RG-12) retire aussi le fichier',
      () async {
        await expectLater(
          dao.enregistrer(
            dateTransaction: DateTime(2026, 10, 9),
            tresorerie: TresorerieDepense.caisse,
            libelle: 'Marché',
            auteurId: auteurDepense,
            lignes: const [ligne],
            recu: png(),
          ),
          throwsA(isA<RefusComptable>()),
        );
        expect(await compter(db, 'depenses_local'), 0);
        final r = Directory('${dossier.path}/r');
        expect(r.existsSync() ? r.listSync() : <Object>[], isEmpty);
      },
    );

    test('sans rangement des reçus, joindre un reçu LÈVE : jamais abandonné en '
        'silence', () async {
      final sans = DepenseDao(
        db,
        maintenant: () => jourDeReference,
        moteur: () async => moteurSur(db, maintenant: () => jourDeReference),
      );
      await expectLater(
        sans.enregistrer(
          dateTransaction: DateTime(2026, 10, 9),
          tresorerie: TresorerieDepense.caisse,
          libelle: 'Marché',
          auteurId: auteurDepense,
          centreId: await centreDe(db, 'Restaurant'),
          lignes: const [ligne],
          recu: png(),
        ),
        throwsStateError,
      );
      expect(await compter(db, 'depenses_local'), 0);
    });

    test('le payload de la dépense qui part ne porte AUCUN octet du reçu (le '
        'fichier a sa propre porte)', () async {
      await saisir(recu: png());
      final op =
          (await db
                      .customSelect('SELECT payload FROM operations_sync_local')
                      .getSingle())
                  .data['payload']!
              as String;
      expect(op, isNot(contains('recu')));
    });
  });

  group('l’état ne se dit que de ce que le serveur a accusé', () {
    test(
      'l’accusé fait « envoyé » ; il ne s’écrit QUE depuis « en attente »',
      () async {
        final d = await saisir(recu: png());
        expect((await dao.recusEnAttente()).map((r) => r.depenseId), [d.id]);

        await dao.accuserRecu(d.id);
        expect((await colonnes(d.id))['recu_statut'], 'envoye');
        expect(await dao.recusEnAttente(), isEmpty);

        // Un refus tardif n’écrase pas un accusé.
        await dao.refuserRecu(d.id, 'trop tard');
        expect((await colonnes(d.id))['recu_statut'], 'envoye');
      },
    );

    test(
      'un refus du serveur fait « refusé » avec sa cause, définitivement',
      () async {
        final d = await saisir(recu: png());
        await dao.refuserRecu(d.id, 'Le champ photo recu doit être une image.');
        final c = await colonnes(d.id);
        expect(c['recu_statut'], 'refuse');
        expect(c['recu_cause'], 'Le champ photo recu doit être une image.');
        expect(await dao.recusEnAttente(), isEmpty);
        await dao.accuserRecu(d.id);
        expect((await colonnes(d.id))['recu_statut'], 'refuse');
      },
    );

    test('accuser une dépense sans reçu ne fabrique rien', () async {
      final d = await saisir();
      await dao.accuserRecu(d.id);
      expect((await colonnes(d.id))['recu_statut'], isNull);
    });

    test('rien n’est « envoyé » à la saisie, quelle que soit la '
        'synchronisation : l’état de départ est « en attente »', () async {
      final d = await saisir(recu: png());
      expect(d.recu!.statut, isNot(StatutRecu.envoye));
    });
  });

  group('la référence descendue du serveur', () {
    final sha = RecusDepensesLocaux.empreinte(octetsPng());

    test('une dépense sans reçu reçoit la référence : « du serveur », sans '
        'fichier', () async {
      final d = await saisir();
      expect(
        await dao.retenirReferenceRecu(
          d.id,
          sha256: sha,
          taille: 70,
          type: 'image/png',
        ),
        isTrue,
      );
      final c = await colonnes(d.id);
      expect(c['recu_statut'], 'du_serveur');
      expect(c['recu_nom'], isNull, reason: 'jamais téléchargé en masse');
      expect(c['recu_sha256'], sha);
    });

    test('le serveur redit la MÊME empreinte qu’un reçu en attente : c’est '
        'l’accusé (réponse perdue) — « envoyé »', () async {
      final d = await saisir(recu: png());
      await dao.retenirReferenceRecu(
        d.id,
        sha256: sha,
        taille: 70,
        type: 'image/png',
      );
      expect((await colonnes(d.id))['recu_statut'], 'envoye');
    });

    test('une AUTRE empreinte pour un reçu en attente : « refusé », le serveur '
        'garde le sien', () async {
      final d = await saisir(recu: png());
      await dao.retenirReferenceRecu(
        d.id,
        sha256: 'a' * 64,
        taille: 70,
        type: 'image/jpeg',
      );
      final c = await colonnes(d.id);
      expect(c['recu_statut'], 'refuse');
      expect(c['recu_cause'], TextesRecuPoste.autreRecuAuServeur);
    });

    test('un reçu web d’avant les empreintes : référence sans empreinte, '
        'toujours « du serveur »', () async {
      final d = await saisir();
      await dao.retenirReferenceRecu(
        d.id,
        sha256: null,
        taille: null,
        type: null,
      );
      final c = await colonnes(d.id);
      expect(c['recu_statut'], 'du_serveur');
      expect(c['recu_sha256'], isNull);
    });

    test('« envoyé » et « refusé » sont des faits : la descente ne les '
        'touche pas', () async {
      final d = await saisir(recu: png());
      await dao.accuserRecu(d.id);
      expect(
        await dao.retenirReferenceRecu(
          d.id,
          sha256: 'b' * 64,
          taille: 1,
          type: 'image/gif',
        ),
        isFalse,
      );
      expect((await colonnes(d.id))['recu_sha256'], sha);
    });

    test('une référence qui change fait oublier le fichier téléchargé '
        '(le nouveau se téléchargera)', () async {
      final d = await saisir();
      await dao.retenirReferenceRecu(
        d.id,
        sha256: sha,
        taille: 70,
        type: 'image/png',
      );
      final range = await recus.ranger(d.id, TypeRecu.png, octetsPng());
      await dao.retenirFichierTelecharge(
        d.id,
        range: range,
        type: TypeRecu.png,
      );
      expect((await colonnes(d.id))['recu_nom'], '${d.id}.png');

      await dao.retenirReferenceRecu(
        d.id,
        sha256: 'c' * 64,
        taille: 9,
        type: 'image/png',
      );
      expect((await colonnes(d.id))['recu_nom'], isNull);
      expect(File('${dossier.path}/r/${d.id}.png').existsSync(), isFalse);
    });

    test('la même référence redite ne change rien', () async {
      final d = await saisir();
      await dao.retenirReferenceRecu(
        d.id,
        sha256: sha,
        taille: 70,
        type: 'image/png',
      );
      expect(
        await dao.retenirReferenceRecu(
          d.id,
          sha256: sha,
          taille: 70,
          type: 'image/png',
        ),
        isFalse,
      );
    });
  });

  group('le rangement des fichiers', () {
    test('un nom ne sort jamais du dossier', () async {
      await recus.ranger('d-1', TypeRecu.png, octetsPng());
      expect(await recus.fichier('../d-1.png'), isNull);
      expect(await recus.fichier('sous/d-1.png'), isNull);
      expect(await recus.fichier('d-1.png'), isNotNull);
      expect(await recus.lire('inconnu.png'), isNull);
      expect(await recus.lire(null), isNull);
    });

    test('l’écriture est atomique : aucun fichier provisoire ne reste, et un '
        'autre type remplace l’ancien', () async {
      await recus.ranger('d-1', TypeRecu.png, octetsPng());
      await recus.ranger('d-1', TypeRecu.jpeg, octetsJpeg());
      final noms = Directory(
        '${dossier.path}/r',
      ).listSync().map((e) => e.uri.pathSegments.last).toList();
      expect(noms, ['d-1.jpg']);
    });
  });
}
