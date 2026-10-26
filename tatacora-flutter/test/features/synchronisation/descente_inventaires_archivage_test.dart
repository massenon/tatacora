import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/stocks/data/stocks_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/data/descente_catalogue_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/descente_catalogue.dart';

import 'support/faux_transport.dart';

/// La DESCENTE des deux moitiés du lot « inventaire et archivage des
/// articles » (21/10/2026) : l'état `actif` d'un article (appliqué, plus
/// « l'article archivé reste »), et les inventaires clôturés des autres postes
/// avec leurs lignes. Ce qui descend ne remonte JAMAIS (aucune opération en
/// file), et les dépendances absentes mettent l'inventaire en attente — il ne
/// s'écrit pas à moitié.
void main() {
  late BancSync b;

  setUp(() async {
    b = await BancSync.creer();
    await b.semerAuteur();
  });
  tearDown(() => b.fermer());

  Future<Map<String, Object?>?> ligne(String table, String id) async =>
      (await b.db
              .customSelect(
                'SELECT * FROM $table WHERE id = ?',
                variables: [Variable.withString(id)],
              )
              .getSingleOrNull())
          ?.data;

  Future<int> compte(String table) async =>
      (await b.db.customSelect('SELECT COUNT(*) AS n FROM $table').getSingle())
              .data['n']
          as int;

  Future<BilanDescente> descendre(List<Map<String, Object?>> elements) async {
    // Le faux serveur reprend après le curseur ; le vrai re-sert un document
    // modifié.
    await DescenteCatalogueDao(b.db).effacerCurseur();
    return b
        .descente(
          FauxTransport(
            (r) => r.methode == 'GET'
                ? FauxCatalogue(elements).repondre(r)
                : reponseLot(r),
          ),
        )
        .descendre((await b.lecteur.appairage())!, surRefus: (_) async {});
  }

  Map<String, Object?> article({String libelle = 'Riz local'}) => {
    'libelle': libelle,
    'categorie': 'Denrées',
    'unite_mesure': 'sac',
    'seuil_alerte': '5.00',
    'suivi': 'permanent',
  };

  final point = element('points_stockage', 'ps-1', {
    'libelle': 'Magasin',
    'type': 'magasin',
  });

  Future<bool?> actif(String id) async {
    final v = (await ligne('articles_local', id))!['actif'];
    return v == null ? null : v == 1;
  }

  group('L’état `actif` d’un article est APPLIQUÉ', () {
    test('archivé au serveur → `actif` faux ici, et le bilan ne le compte '
        'plus comme « non porté » ; restauré → vrai', () async {
      var bilan = await descendre([
        element('articles', 'art-1', article(), actif: false),
      ]);
      expect(bilan.appliques, 1);
      expect(bilan.archivesNonPortees, 0);
      expect(await actif('art-1'), isFalse);
      // Rien n'est supprimé : la ligne existe, marquée.
      expect(await compte('articles_local'), 1);

      bilan = await descendre([element('articles', 'art-1', article())]);
      expect(bilan.appliques, 1);
      expect(await actif('art-1'), isTrue);
      expect(await b.total(), 0, reason: 'ce qui descend ne remonte pas');
    });

    test('un article NEUF descendu actif est actif', () async {
      await descendre([element('articles', 'art-2', article())]);
      expect(await actif('art-2'), isTrue);
    });

    test('un archivage du poste encore en file est CONSERVÉ face à l’état '
        'actif du serveur — il part, le serveur tranche', () async {
      await descendre([element('articles', 'art-1', article())]);
      // L'archivage est écrit PAR LE DAO du poste : fiche, file.
      await StocksDao(b.db).archiverArticle('art-1');
      expect(await actif('art-1'), isFalse);

      final bilan = await descendre([element('articles', 'art-1', article())]);
      expect(bilan.conservesLocalement, 1);
      expect(await actif('art-1'), isFalse, reason: 'jamais écrasé');
    });

    test('un archivage REFUSÉ par le serveur (verrou) est repris : l’article '
        'redevient actif ici, la version du serveur est gardée', () async {
      await descendre([element('articles', 'art-1', article())]);
      await StocksDao(b.db).archiverArticle('art-1');
      expect(await actif('art-1'), isFalse);

      // Le serveur a refusé l'opération (par exemple parce que le plat est lié
      // au stock) : elle est rejetée, plus rien n'attend.
      await b.db.customStatement(
        "UPDATE operations_sync_local SET statut = 'rejete' "
        "WHERE entite_id = 'art-1' AND type = 'modification'",
      );
      final bilan = await descendre([element('articles', 'art-1', article())]);
      expect(bilan.appliques, 1, reason: '$bilan');
      expect(await actif('art-1'), isTrue);
    });
  });

  group('Un inventaire clôturé par un autre poste descend avec ses lignes', () {
    Map<String, Object?> inventaire({
      String date = '2026-10-20',
      List<Map<String, Object?>>? lignes,
    }) => {
      'point_id': 'ps-1',
      'date_inventaire': date,
      'lignes':
          lignes ??
          [
            {
              'article_id': 'art-1',
              'quantite_theorique': '10.00',
              'quantite_constatee': '12.00',
              'ecart': '2.00',
            },
            {
              'article_id': 'art-2',
              'quantite_theorique': '4.00',
              'quantite_constatee': '3.00',
              'ecart': '-1.00',
            },
          ],
    };

    List<Map<String, Object?>> catalogue() => [
      point,
      element('articles', 'art-1', article()),
      element('articles', 'art-2', article(libelle: 'Huile')),
    ];

    test('l’en-tête, les lignes en centièmes, l’origine ; RIEN ne part en '
        'file, et aucun mouvement n’est réécrit', () async {
      final bilan = await descendre([
        ...catalogue(),
        {
          ...element('inventaires', 'inv-1', inventaire()),
          'poste_origine': 'POSTE-A',
        },
      ]);
      expect(bilan.refuses, 0, reason: bilan.motifsRefus.join(' ; '));
      expect(bilan.enAttenteDeDependance, 0);

      final entete = await ligne('inventaires_local', 'inv-1');
      expect(entete!['point_id'], 'ps-1');
      expect(entete['date_inventaire'], '2026-10-20');
      expect(entete['utilisateur_id'], isNull, reason: 'comptes non descendus');

      final lignes = await b.db
          .customSelect(
            'SELECT article_id, quantite_theorique_centiemes AS t, '
            'quantite_constatee_centiemes AS c, ecart_centiemes AS e '
            "FROM lignes_inventaire_local WHERE inventaire_id = 'inv-1' "
            'ORDER BY article_id',
          )
          .get();
      expect(
        [
          for (final l in lignes)
            (l.data['article_id'], l.data['t'], l.data['c'], l.data['e']),
        ],
        [('art-1', 1000, 1200, 200), ('art-2', 400, 300, -100)],
      );

      final origine = await b.db
          .customSelect(
            'SELECT poste_origine FROM origines_documents_local '
            "WHERE table_serveur = 'inventaires' AND entite_id = 'inv-1'",
          )
          .getSingle();
      expect(origine.data['poste_origine'], 'POSTE-A');

      // Le constat descend ; la régularisation descend À PART (mouvements).
      expect(await compte('mouvements_stock_local'), 0);
      expect(await b.total(), 0);

      // Il se lit à l'historique, sans auteur : « — ».
      final liste = await StocksDao(b.db).inventairesClos();
      expect(liste.single.id, 'inv-1');
      expect((liste.single.articles, liste.single.regularises), (2, 2));
      expect(liste.single.par, isNull);
      expect(liste.single.pointLibelle, 'Magasin');
    });

    test('déjà détenu (celui de CE poste qui revient par le flux) : rien '
        'n’est réécrit, aucune ligne en double', () async {
      final premier = await descendre([
        ...catalogue(),
        element('inventaires', 'inv-1', inventaire()),
      ]);
      expect(premier.appliques, 4);
      final lignesAvant = await compte('lignes_inventaire_local');

      await descendre([
        ...catalogue(),
        element(
          'inventaires',
          'inv-1',
          inventaire(
            lignes: [
              {
                'article_id': 'art-1',
                'quantite_theorique': '1.00',
                'quantite_constatee': '1.00',
                'ecart': '0.00',
              },
            ],
          ),
        ),
      ]);
      expect(await compte('inventaires_local'), 1);
      expect(await compte('lignes_inventaire_local'), lignesAvant);
      final rien = await b.db
          .customSelect(
            "SELECT quantite_constatee_centiemes AS c FROM lignes_inventaire_local WHERE article_id = 'art-1'",
          )
          .getSingle();
      expect(rien.data['c'], 1200);
    });

    test('un point ou un article pas encore reçu : l’inventaire ATTEND en '
        'entier — jamais une ligne écrite sans son article', () async {
      final bilan = await descendre([
        point,
        element('articles', 'art-1', article()),
        // art-2 n'est pas encore reçu.
        element('inventaires', 'inv-1', inventaire()),
      ]);
      expect(bilan.enAttenteDeDependance, 1, reason: '$bilan');
      expect(await compte('inventaires_local'), 0);
      expect(await compte('lignes_inventaire_local'), 0);

      // Il arrive : repris à la descente suivante.
      final suite = await descendre([
        ...catalogue(),
        element('inventaires', 'inv-1', inventaire()),
      ]);
      expect(suite.refuses, 0);
      expect(await compte('inventaires_local'), 1);
      expect(await compte('lignes_inventaire_local'), 2);
    });

    test('une quantité à trois décimales est REFUSÉE, jamais arrondie — et '
        'rien n’est écrit', () async {
      final bilan = await descendre([
        ...catalogue(),
        element(
          'inventaires',
          'inv-1',
          inventaire(
            lignes: [
              {
                'article_id': 'art-1',
                'quantite_theorique': '10.005',
                'quantite_constatee': '12.00',
                'ecart': '1.995',
              },
            ],
          ),
        ),
      ]);
      expect(bilan.refuses, 1);
      expect(await compte('inventaires_local'), 0);
      expect(await compte('lignes_inventaire_local'), 0);
    });

    test('la table est libellée en français pour l’écran de synchronisation', () {
      expect(libelleTableServeur('inventaires'), 'Inventaires physiques');
      expect(
        TableDescendue.depuisNom('inventaires'),
        TableDescendue.inventaires,
      );
      // Le poste ne pousse pas ce qu'il reçoit, mais il POUSSE ses inventaires.
      expect(
        TableDescendue.inventaires.tableSynchronisee?.nomServeur,
        'inventaires',
      );
    });
  });
}
