@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/fichiers/lecture_tableur.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/restaurant/domain/entities/plat.dart';
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';
import 'package:tatacora_flutter/features/transverse/data/importeurs_locaux.dart';
import 'package:tatacora_flutter/features/transverse/domain/import_referentiels.dart';
import 'package:tatacora_flutter/features/transverse/presentation/providers_import_export.dart';

import '../comptabilite/support/outils_comptabilite.dart';
import 'support/outils_import.dart';

/// L'import du M4 « Carte du restaurant » et sa colonne « Catégorie » (v41,
/// 27/10/2026) : liste FERMÉE des dix clés de la carte, obligatoire, jugée par le
/// VRAI `ControleImportService` du serveur (`tool/transverse/rejouer_import_m4.php`),
/// puis écrite par le DAO de la carte et enfilée à la synchronisation.
///
/// Base d'essai privée : `TATACORA_BASE_ESSAI=tatacora_<nom>_test`.
void main() {
  late AppDatabase db;
  late ProviderContainer conteneur;
  late MoteurImportLocal moteur;

  setUp(() async {
    db = await baseImport();
    conteneur = conteneurImport(db);
    moteur = conteneur.read(moteurImportProvider);
  });
  tearDown(() async {
    conteneur.dispose();
    await db.close();
  });

  ImporteurLocal importeur() => conteneur
      .read(importeursLocauxProvider)
      .singleWhere((i) => i.cle == 'm4-restaurant');

  const entete = [
    'Nom du plat',
    'Catégorie',
    'Prix de vente (FCFA)',
    'Menu',
    'Fiche recette',
  ];

  List<String> ligne(String nom, String categorie) => [
    nom,
    categorie,
    '4500',
    'Menu local',
    'Poulet DG',
  ];

  List<int> csv(List<List<String>> lignes) =>
      utf8.encode('${lignes.map((l) => l.join(';')).join('\r\n')}\r\n');

  /// Les dix clés de la carte, dans l'ordre du serveur.
  const dixCles = [
    'entrees',
    'plats',
    'sauces',
    'garnitures',
    'accompagnements',
    'sandwicherie',
    'pizzas',
    'desserts',
    'boissons_maison',
    'formules',
  ];

  group('Contre le VRAI serveur', () {
    late Map<String, dynamic> serveur;

    // Les fichiers soumis aux deux contrôles (en-tête + lignes).
    final tableaux = <List<List<String>>>[
      // 0. une ligne par clé : tout passe.
      [entete, for (final (i, c) in dixCles.indexed) ligne('Plat $i', c)],
      // 1. la graphie : libellé, pluriel manquant, majuscule, espaces, accent.
      [
        entete,
        ligne('A', 'Plats complets'),
        ligne('B', 'dessert'),
        ligne('C', 'Plats'),
        ligne('D', '  plats  '),
        ligne('E', 'entrées'),
        ligne('F', 'boissons'),
      ],
      // 2. obligatoire : vide.
      [entete, ligne('G', '')],
      // 3. la colonne n'est pas dans le fichier.
      [
        ['Nom du plat', 'Prix de vente (FCFA)', 'Menu', 'Fiche recette'],
        ['H', '4500', 'Menu local', 'Poulet DG'],
      ],
      // 4. la colonne n'est pas à sa place : l'en-tête commande, pas le rang.
      [
        [
          'Catégorie',
          'Nom du plat',
          'Fiche recette',
          'Menu',
          'Prix de vente (FCFA)',
        ],
        ['pizzas', 'I', 'Poulet DG', 'Menu local', '3000'],
      ],
    ];

    setUpAll(() async {
      serveur = await executerPhp(
        'rejouer_import_m4.php',
        dossier: 'transverse',
        entree: {'tableaux': tableaux},
      );
    });

    List<Map<String, dynamic>> rapports() => [
      for (final r in serveur['rapports'] as List) r as Map<String, dynamic>,
    ];

    test('la colonne « Catégorie » est déclarée comme au serveur : libellé, '
        'obligatoire, liste fermée des dix clés, exemple', () {
      final c = (serveur['colonnes'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere((x) => x['champ'] == 'categorie');
      final poste = importeur().colonnes.singleWhere(
        (x) => x.champ == 'categorie',
      );
      expect(poste.libelle, c['libelle']);
      expect(poste.requis, c['requis']);
      expect(poste.type, TypeColonneImport.liste);
      expect(c['type'], 'liste');
      expect(poste.valeurs, (c['valeurs'] as List).cast<String>());
      expect(poste.valeurs, dixCles);
      expect(poste.exemple, c['exemple']);
    });

    test('toutes les colonnes du modèle, dans l’ordre du serveur', () {
      final srv = (serveur['colonnes'] as List).cast<Map<String, dynamic>>();
      expect(
        [
          for (final c in importeur().colonnes)
            (c.champ, c.libelle, c.requis, c.exemple),
        ],
        [
          for (final c in srv)
            (c['champ'], c['libelle'], c['requis'], c['exemple']),
        ],
      );
      expect((serveur['colonnes'] as List).map((c) => (c as Map)['type']), [
        'texte',
        'liste',
        'montant',
        'reference',
        'reference',
      ]);
    });

    test('CHAQUE fichier : le MÊME verdict, les MÊMES lignes et phrases en '
        'erreur', () async {
      final ecarts = <String>[];
      for (final (i, srv) in rapports().indexed) {
        final poste = await moteur.controler(importeur(), csv(tableaux[i]));
        final lesErreurs = [
          for (final e in poste.erreurs) (e.ligne, e.colonne, e.message),
        ];
        final lesErreursServeur = [
          for (final e in (srv['erreurs'] as List).cast<Map<String, dynamic>>())
            (e['ligne'], e['colonne'], e['message']),
        ];
        if (poste.ok != srv['ok'] ||
            '$lesErreurs' != '$lesErreursServeur' ||
            poste.avertissements.length !=
                (srv['avertissements'] as List).length) {
          ecarts.add(
            'fichier $i\n  serveur : ${srv['ok']} $lesErreursServeur\n'
            '  poste   : ${poste.ok} $lesErreurs',
          );
        }
      }
      expect(ecarts, isEmpty, reason: ecarts.join('\n'));
    });

    test('le scénario est assez large pour que la comparaison compte', () {
      final r = rapports();
      expect(r[0]['ok'], isTrue);
      expect(
        (r[0]['categories'] as List).cast<String>(),
        dixCles,
        reason: 'les dix clés passent telles quelles',
      );
      expect(r[1]['ok'], isFalse);
      expect((r[1]['erreurs'] as List).length, greaterThanOrEqualTo(2));
      expect(r[2]['ok'], isFalse);
      expect(r[3]['ok'], isFalse, reason: 'colonne manquante');
      expect(r[4]['ok'], isTrue, reason: 'colonnes dans le désordre');
    });
  });

  group('Ce que le poste en fait', () {
    test('les dix clés s’importent : chaque plat porte SA catégorie en base '
        'et dans la création enfilée', () async {
      await db.customStatement('DELETE FROM operations_sync_local');
      final issue = await moteur.appliquer(
        importeur(),
        csv([
          entete,
          for (final (i, c) in dixCles.indexed) ligne('Plat $i', c),
        ]),
      );
      expect(issue, isA<ImportFait>(), reason: '$issue');
      expect((issue as ImportFait).importees, 10);

      final lignes = await db
          .customSelect('SELECT libelle, categorie FROM plats_local')
          .get();
      expect(
        {for (final l in lignes) l.data['libelle']: l.data['categorie']},
        {for (final (i, c) in dixCles.indexed) 'Plat $i': c},
      );
      final file = await OperationsSyncDao(
        db,
      ).operations(table: TableSynchronisee.plats);
      expect(file, hasLength(10));
      expect(file.map((o) => o.type).toSet(), {TypeOperationSync.creation});
      for (final (i, c) in dixCles.indexed) {
        final charge = jsonDecode(file[i].payload) as Map<String, dynamic>;
        expect(charge['categorie'], c, reason: 'Plat $i');
      }
    });

    test('une catégorie hors liste est DITE (ligne, colonne, valeur) et le '
        'fichier n’écrit RIEN — pas même ses lignes valides', () async {
      final avant = await compterLignes(db, 'plats_local');
      final contenu = csv([
        entete,
        ligne('Bon plat', 'plats'),
        ligne('Mauvais plat', 'Plats complets'),
        ligne('Autre bon plat', 'desserts'),
      ]);

      final rapport = await moteur.controler(importeur(), contenu);
      expect(rapport.ok, isFalse);
      expect(rapport.lignes, isEmpty, reason: 'aucun import partiel');
      expect((rapport.total, rapport.enErreur, rapport.valides), (3, 1, 2));
      final e = rapport.erreurs.single;
      expect((e.ligne, e.colonne), (3, 'Catégorie'));
      expect(e.message, startsWith('valeur « Plats complets » hors liste'));

      expect(
        await moteur.appliquer(importeur(), contenu),
        isA<ImportNonConforme>(),
      );
      expect(await compterLignes(db, 'plats_local'), avant);
    });

    test('la colonne peut changer de place : l’en-tête commande', () async {
      final issue = await moteur.appliquer(
        importeur(),
        csv([
          [
            'Catégorie',
            'Nom du plat',
            'Fiche recette',
            'Menu',
            'Prix de vente (FCFA)',
          ],
          ['pizzas', 'Margherita', 'Poulet DG', 'Menu local', '3000'],
        ]),
      );
      expect(issue, isA<ImportFait>(), reason: '$issue');
      final p = await db
          .customSelect(
            "SELECT categorie, prix_vente FROM plats_local WHERE libelle = 'Margherita'",
          )
          .getSingle();
      expect(p.data['categorie'], 'pizzas');
    });

    test(
      'le registre du poste (CategorieCarte) porte les mêmes dix clés que la '
      'colonne',
      () {
        expect([for (final c in CategorieCarte.values) c.code], dixCles);
      },
    );

    test('le modèle téléchargeable porte la colonne « Catégorie » à sa place, '
        'avec son exemple', () {
      expect(lireTableur(importeur().modeleOctets()).first, entete);
    });
  });
}
