@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/restaurant/data/restaurant_api.dart';
import 'package:tatacora_flutter/features/restaurant/data/restaurant_dao.dart';
import 'package:tatacora_flutter/features/restaurant/domain/calcul_restaurant.dart';
import 'package:tatacora_flutter/features/restaurant/domain/entities/plat.dart';
import 'package:tatacora_flutter/features/restaurant/domain/messages_restaurant.dart';
import 'package:tatacora_flutter/features/stocks/data/stocks_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';

import '../comptabilite/support/outils_comptabilite.dart';

/// La description FACULTATIVE d'un plat (v47, 30/10/2026, décision du PO) :
/// normalisée (trim, vide = `NULL`), 500 caractères au plus, rejouée de
/// `DescriptionPlat` du serveur (`tool/restaurant/rejouer_description_plat.php`),
/// écrite par le DAO et enfilée à la synchronisation (création complète,
/// modification par différence, effacement en `null` EXPLICITE).
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late RestaurantApi api;
  late String menuId;
  late String ficheId;

  setUp(() async {
    db = AppDatabase.enMemoire();
    await db
        .into(db.utilisateursLocal)
        .insert(
          UtilisateursLocalCompanion.insert(
            id: 'u-1',
            login: 'chef',
            nom: 'Aïcha',
            role: 'cuisinier',
            droitsJson: '{}',
            sel: 's',
            empreinte: 'e',
            iterations: 1,
            dateCreation: DateTime(2026, 10, 1),
            dateMotDePasse: DateTime(2026, 10, 1),
          ),
        );
    api = RestaurantApi(
      dao: RestaurantDao(db, stocks: StocksDao(db)),
      peutLire: () => true,
      peutEcrire: () => true,
      auteurId: () => 'u-1',
    );
    menuId = _recu(
      await api.enregistrerMenu(
        const SaisieMenu(libelle: 'Carte', type: 'local'),
      ),
    ).id;
    ficheId = _recu(
      await api.enregistrerRecette(
        const SaisieFiche(libelle: 'Fiche vide', lignes: []),
      ),
    ).id;
  });

  tearDown(() => db.close());

  Future<ResultatRestaurant<Plat>> creer(
    String libelle, {
    String? description,
  }) => api.enregistrerPlat(
    SaisiePlat(
      libelle: libelle,
      menuId: menuId,
      recetteId: ficheId,
      prixVente: '2500',
      description: description,
    ),
    modification: false,
  );

  Future<ResultatRestaurant<Plat>> modifier(Plat p, {String? description}) =>
      api.enregistrerPlat(
        SaisiePlat(
          id: p.id,
          libelle: p.libelle,
          menuId: menuId,
          recetteId: ficheId,
          prixVente: '2500',
          description: description,
        ),
        modification: true,
      );

  Future<List<Map<String, dynamic>>> charges() async => [
    for (final o in await OperationsSyncDao(
      db,
    ).operations(table: TableSynchronisee.plats))
      {'type': o.type.name, ...jsonDecode(o.payload) as Map<String, dynamic>},
  ];

  group('Contre la VRAIE règle du serveur', () {
    // Tout ce qui sépare une description valide d'une invalide, et la façon de
    // normaliser : espaces de bord, vide, multiligne, 500 / 501 caractères,
    // 500 + espaces de bord (jugé NORMALISÉ).
    final saisies = <String?>[
      null,
      '',
      '   ',
      '\n\t',
      'Poulet, plantain mûr',
      '  Poulet\nsauce tomate  ',
      'x' * 500,
      'x' * 501,
      ' ${'x' * 500} ',
      ' ${'x' * 501} ',
      'é' * 500,
      'é' * 501,
    ];
    late Map<String, dynamic> serveur;

    setUpAll(() async {
      serveur = await executerPhp(
        'rejouer_description_plat.php',
        dossier: 'restaurant',
        entree: {'descriptions': saisies},
      );
    });

    test('la borne et la phrase sont celles du serveur', () {
      expect(descriptionPlatMax, serveur['maximum']);
      expect(MessagesRestaurant.descriptionTropLongue, serveur['phrase']);
    });

    test('CHAQUE saisie : la même valeur normalisée et le même verdict', () {
      final resultats = (serveur['resultats'] as List)
          .cast<Map<String, dynamic>>();
      expect(resultats, hasLength(saisies.length));

      final ecarts = <String>[];
      for (final (i, saisie) in saisies.indexed) {
        final srv = resultats[i];
        final lue = verifierPlat(
          SaisiePlat(
            libelle: 'Poulet DG',
            menuId: 'm',
            recetteId: 'r',
            prixVente: '1000',
            description: saisie,
          ),
        );
        final valide = !lue.erreurs.containsKey('description');
        if (normaliserDescriptionPlat(saisie) != srv['normalisee'] ||
            valide != srv['valide'] ||
            (!valide && lue.erreurs['description'] != srv['message'])) {
          ecarts.add(
            '#$i ${jsonEncode(saisie)}\n  serveur : ${srv['normalisee']} '
            '${srv['valide']} ${srv['message']}\n  poste   : '
            '${normaliserDescriptionPlat(saisie)} $valide '
            '${lue.erreurs['description']}',
          );
        }
      }
      expect(ecarts, isEmpty, reason: ecarts.join('\n'));
    });

    test('le scénario est assez large pour que la comparaison compte', () {
      final r = (serveur['resultats'] as List).cast<Map<String, dynamic>>();
      expect(r.where((x) => x['valide'] == false), hasLength(3));
      expect(r.where((x) => x['normalisee'] == null), hasLength(4));
      expect(r[5]['normalisee'], 'Poulet\nsauce tomate');
    });
  });

  group('Ce que le poste en fait', () {
    test('absente, vide ou d’espaces : le plat naît SANS description et la '
        'création enfilée ne la porte pas', () async {
      for (final (i, d) in <String?>[null, '', '  \n '].indexed) {
        final p = _recu(await creer('Plat $i', description: d));
        expect(p.description, isNull, reason: 'saisie ${jsonEncode(d)}');
      }
      final tous = await charges();
      expect(tous, hasLength(3));
      for (final c in tous) {
        expect(c['type'], TypeOperationSync.creation.name);
        expect(c.containsKey('description'), isFalse);
      }
    });

    test('saisie : rognée, multiligne conservée, relue, et portée par la '
        'création enfilée', () async {
      final p = _recu(
        await creer('Pizza royale', description: '  Jambon,\nmozza  '),
      );
      expect(p.description, 'Jambon,\nmozza');
      final relue = _recu(await api.plat(p.id));
      expect(relue.description, 'Jambon,\nmozza');
      final c = (await charges()).single;
      expect(c['description'], 'Jambon,\nmozza');
    });

    test('501 caractères : refusé avec la phrase du serveur, sur le champ, '
        'rien n’est écrit ni enfilé', () async {
      final r = await creer('Trop long', description: 'x' * 501);
      expect(r, isA<RestaurantRefuse<Plat>>());
      r as RestaurantRefuse<Plat>;
      expect(
        r.erreurs['description'],
        MessagesRestaurant.descriptionTropLongue,
      );
      expect(
        (await db
                .customSelect('SELECT COUNT(*) AS n FROM plats_local')
                .getSingle())
            .data['n'],
        0,
      );
      expect(await charges(), isEmpty);
    });

    test('modification : `null` laisse la description, du texte la change, '
        'le vide l’EFFACE — repartie en `null` explicite', () async {
      final p = _recu(await creer('Pizza', description: 'Jambon'));
      await db.customStatement('DELETE FROM operations_sync_local');

      // Non soumise : inchangée, et rien ne part pour elle.
      final inchange = _recu(await modifier(p));
      expect(inchange.description, 'Jambon');
      var file = await charges();
      expect(
        file.where((c) => c.containsKey('description')),
        isEmpty,
        reason: 'une modification qui ne la nomme pas ne la renvoie pas',
      );

      await db.customStatement('DELETE FROM operations_sync_local');
      final change = _recu(await modifier(p, description: 'Jambon, mozza'));
      expect(change.description, 'Jambon, mozza');
      file = await charges();
      expect(file.single['type'], TypeOperationSync.modification.name);
      expect(file.single['description'], 'Jambon, mozza');

      await db.customStatement('DELETE FROM operations_sync_local');
      final efface = _recu(await modifier(p, description: '   '));
      expect(efface.description, isNull);
      file = await charges();
      expect(file.single.containsKey('description'), isTrue);
      expect(file.single['description'], isNull);
    });
  });
}

T _recu<T>(ResultatRestaurant<T> r) {
  expect(r, isA<RestaurantRecu<T>>(), reason: '$r');
  return (r as RestaurantRecu<T>).donnees;
}
