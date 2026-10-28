import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart' show driftRuntimeOptions;

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/restaurant/data/restaurant_api.dart';
import 'package:tatacora_flutter/features/restaurant/data/restaurant_dao.dart';
import 'package:tatacora_flutter/features/restaurant/domain/calcul_restaurant.dart';
import 'package:tatacora_flutter/features/restaurant/domain/entities/carte_restaurant.dart';
import 'package:tatacora_flutter/features/restaurant/domain/entities/plat.dart';
import 'package:tatacora_flutter/features/stocks/data/stocks_dao.dart';
import 'package:tatacora_flutter/features/stocks/domain/calcul_stock.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/etat_stock.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/mouvement_stock.dart';

/// La CARTE du restaurant, CONFRONTÉE au serveur en exécutant PHP.
///
/// `tool/restaurant/exporter_carte.php` charge le VRAI `CarteRestaurantService`
/// (et, derrière lui, `CompositionRecetteService::coutMatiere`) sur une base
/// SQLite en mémoire qui porte le MÊME scénario que la base Drift de ce test :
/// mêmes points, mêmes articles, mêmes mouvements, mêmes fiches, mêmes plats.
/// Les deux calculs sont comparés champ à champ. Une formule recopiée à la main
/// dans un test ne vérifierait qu'elle-même, et resterait verte le jour où le
/// serveur changerait (piège 12).
///
/// PHP absent, ou `vendor/` absent : le test ÉCHOUE, il ne saute pas.
///
/// ## Ce que le scénario ne contient PAS, et pourquoi
///
/// Aucun article en achat journalier dans la comparaison EXACTE : le serveur y
/// rend « rupture » en permanence (un solde de `0.00` lu pour un article qui
/// n'a aucun mouvement), et ce poste dit « non suivi » — c'est l'écart n° 1 de
/// `calcul_restaurant.dart`, éprouvé À PART, par PHP aussi, dans le dernier
/// groupe de ce fichier.
Future<List<Map<String, dynamic>>> _executer(Map<String, dynamic> cas) async {
  final php = await Process.start('php', [
    'tool/restaurant/exporter_carte.php',
  ]);
  php.stdin.write(jsonEncode(cas));
  await php.stdin.close();

  final sortie = utf8.decodeStream(php.stdout);
  final erreur = utf8.decodeStream(php.stderr);
  final code = await php.exitCode;

  if (code != 0) {
    fail(
      'Le serveur n’a pas pu rejouer la carte (php, code $code) : '
      '${await erreur}. C’est un ÉCHEC, pas un saut.',
    );
  }
  return (jsonDecode(await sortie) as List<dynamic>)
      .cast<Map<String, dynamic>>();
}

final class _Monde {
  _Monde(this.db)
    : stocks = StocksDao(db),
      dao = RestaurantDao(db, stocks: StocksDao(db)),
      api = RestaurantApi(
        dao: RestaurantDao(db, stocks: StocksDao(db)),
        peutLire: () => true,
        peutEcrire: () => true,
        auteurId: () => 'u-1',
      );

  final AppDatabase db;
  final StocksDao stocks;
  final RestaurantDao dao;
  final RestaurantApi api;

  final menus = <String>[];
  final menuTypes = <String, String>{};
  final fiches = <String>[];
  final plats = <String>[];
}

Future<_Monde> _monde() async {
  final db = AppDatabase.enMemoire();
  await db
      .into(db.utilisateursLocal)
      .insert(
        UtilisateursLocalCompanion.insert(
          id: 'u-1',
          login: 'cuisinier',
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
  return _Monde(db);
}

/// Le scénario de PHP, relu de la base Drift — jamais construit à part : c'est
/// ce que la base contient qui est confronté, pas ce que le test croit y avoir
/// mis.
Future<Map<String, dynamic>> _versPhp(
  _Monde m,
  List<Map<String, String?>> requetes,
) async {
  final mouvements = await m.stocks.mouvementsCalcul();
  final parArticle = <String, List<MouvementCalcul>>{};
  for (final mv in mouvements) {
    parArticle.putIfAbsent(mv.articleId, () => []).add(mv);
  }

  final db = m.db;
  final categoriesDesPlats = {
    for (final r in await db.select(db.platsLocal).get()) r.categorie ?? '',
  };
  return {
    'points': [
      for (final p in await m.stocks.points())
        {'id': p.id, 'libelle': p.libelle, 'type': p.type},
    ],
    'articles': [
      for (final a in await m.stocks.articles())
        {
          'id': a.id,
          'libelle': a.libelle,
          'unite': a.uniteMesure,
          'seuil': ecrireCentiemes(a.seuilCentiemes),
          'suivi': a.suivi.code,
          'cmp': ecrireCout(coutMoyenPondereDe(parArticle[a.id] ?? const [])),
        },
    ],
    'mouvements': [
      for (final mv in mouvements)
        {
          'article_id': mv.articleId,
          'point_id': mv.pointId,
          'type': mv.type.code,
          'quantite': ecrireCentiemes(mv.centiemes),
        },
    ],
    // C1 : l'API du serveur classe par `menus.type`, la vue web par la catégorie
    // du PLAT. Pour confronter le CLASSEMENT au vrai `CarteRestaurantService`, on
    // lui donne un menu par catégorie de plat (`type` = `plats.categorie`, vide
    // pour un plat sans catégorie) : ce qu'il range sous « type » EST alors la
    // catégorie du plat. Les menus réels du poste ne servent plus au classement.
    'menus': [
      for (final c in categoriesDesPlats)
        {'id': 'cat-$c', 'libelle': 'Catégorie $c', 'type': c},
    ],
    'recettes': [
      for (final r in await db.select(db.recettesLocal).get())
        {'id': r.id, 'libelle': r.libelle},
    ],
    'ingredients': [
      for (final r in await db.select(db.ingredientsRecetteLocal).get())
        {
          'recette_id': r.recetteId,
          'article_id': r.articleId,
          'quantite': ecrireMilliemes(r.quantiteMilliemes),
        },
    ],
    'plats': [
      for (final r in await db.select(db.platsLocal).get())
        {
          'id': r.id,
          'libelle': r.libelle,
          'menu_id': 'cat-${r.categorie ?? ''}',
          'recette_id': r.recetteId,
          'prix_vente': ecrirePrix(r.prixVente),
          'prix_provisoire': r.prixProvisoire,
        },
    ],
    'requetes': requetes,
  };
}

/// Compare une carte locale à la réponse du serveur, champ à champ.
void _comparer(
  CarteRestaurant locale,
  Map<String, dynamic> serveur, {
  required Map<String, dynamic> sansFiltre,
  required String contexte,
}) {
  final lignes = (serveur['lignes'] as List<dynamic>)
      .cast<Map<String, dynamic>>();

  expect(
    [for (final l in locale.lignes) l.id],
    [for (final l in lignes) l['id']],
    reason: '$contexte : les plats retenus, dans l’ordre',
  );

  for (var i = 0; i < lignes.length; i++) {
    final s = lignes[i];
    final l = locale.lignes[i];
    final c = '$contexte / ${l.libelle}';

    expect(l.categorieBrute, s['categorie'], reason: '$c : catégorie');
    expect(l.nbIngredients, s['nb_ingredients'], reason: '$c : ingrédients');
    expect(l.lieAuStock, s['lie'], reason: '$c : lié');
    expect(l.motifSansStock?.code, s['motif'], reason: '$c : motif');
    expect(l.portionsVendables, s['portions'], reason: '$c : portions');
    expect(l.ingredientLimitant?.id, s['limitant'], reason: '$c : limitant');
    expect(l.rupture, s['rupture'], reason: '$c : rupture');
    expect(l.sousSeuil, s['sous_seuil'], reason: '$c : sous seuil');
    expect(l.coutMatiere, s['cout'], reason: '$c : coût matière');
    expect(
      l.coutMatiereIncomplet,
      s['cout_incomplet'],
      reason: '$c : incomplet',
    );
    expect(
      l.articlesSansCout,
      s['sans_cout'],
      reason: '$c : articles sans coût',
    );
    expect(l.marge, s['marge'], reason: '$c : marge');
  }

  // Les indicateurs et la couverture sont ceux de la carte ENTIÈRE (la vue) :
  // on les confronte à ceux de la requête SANS filtre, jamais à ceux d'une
  // requête que l'API du serveur filtre avant de compter (écart nommé).
  final k = sansFiltre['indicateurs'] as Map<String, dynamic>;
  final i = locale.indicateurs;
  expect(i.plats, k['plats'], reason: '$contexte : plats');
  expect(i.lies, k['lies'], reason: '$contexte : liés');
  expect(i.sansLien, k['sans_lien'], reason: '$contexte : sans lien');
  expect(i.tauxCouverture, k['taux_couverture'], reason: '$contexte : taux');
  expect(i.enRupture, k['en_rupture'], reason: '$contexte : en rupture');
  expect(i.sousSeuil, k['sous_seuil'], reason: '$contexte : sous seuil');
  expect(
    i.coutMatiereInconnu,
    k['cout_matiere_inconnu'],
    reason: '$contexte : coût inconnu',
  );
  expect(
    i.prixProvisoires,
    k['prix_provisoires'],
    reason: '$contexte : prix provisoires',
  );

  final couverture = (sansFiltre['couverture'] as List<dynamic>)
      .cast<Map<String, dynamic>>();
  // Le serveur ne rend que les catégories PRÉSENTES, par ordre d'octets ; la vue
  // web (et le poste) rendent les dix du registre, dans SON ordre, même vides,
  // puis les clés hors registre. Mêmes comptes sur les catégories présentes :
  expect(
    [
      for (final c in locale.couverture)
        if (c.plats > 0)
          [c.categorieBrute, c.plats, c.lies, c.sansLien, c.taux],
    ]..sort((a, b) => (a[0]! as String).compareTo(b[0]! as String)),
    [
      for (final c in couverture)
        [c['categorie'], c['plats'], c['lies'], c['sans_lien'], c['taux']],
    ],
    reason: '$contexte : couverture',
  );
  // … et l'ORDRE est celui de la vue : le registre d'abord, intégral.
  expect(
    [for (final c in locale.couverture) c.categorieBrute].take(10).toList(),
    [for (final c in CategorieCarte.values) c.code],
    reason: '$contexte : ordre du registre',
  );
  expect(
    [for (final c in locale.couverture) c.plats].fold<int>(0, (a, b) => a + b),
    i.plats,
    reason: '$contexte : la somme des groupes est le total',
  );

  expect(
    locale.pointCuisineId,
    serveur['point_cuisine'],
    reason: '$contexte : point cuisine',
  );
}

void main() {
  driftRuntimeOptionsSansAvertissement();

  group('La carte locale est celle du serveur — scénarios aléatoires', () {
    test(
      '48 scénarios, 5 requêtes chacun : lignes, indicateurs, couverture '
      'identiques champ à champ',
      () async {
        final hasard = Random(20261009);

        // Ce que les scénarios ont réellement atteint : sans ce relevé, un
        // générateur qui ne produirait que des cartes sans rupture ferait un
        // test vert à vide.
        var plats = 0;
        var ruptures = 0;
        var sousSeuil = 0;
        var vides = 0;
        var coutsConnus = 0;
        var coutsIncomplets = 0;
        var sansPoint = 0;
        var provisoires = 0;
        var multiIngredients = 0;
        var partiels = 0;

        for (var k = 0; k < 48; k++) {
          final m = await _monde();
          try {
            await _peupler(m, hasard, avecPointCuisine: k % 8 != 7);

            final requetes = <Map<String, String?>>[
              {'recherche': null, 'categorie': null, 'etat': null},
              {'recherche': 'plat-0', 'categorie': null, 'etat': null},
              {'recherche': null, 'categorie': 'plats', 'etat': null},
              {'recherche': null, 'categorie': null, 'etat': 'lie'},
              {'recherche': null, 'categorie': null, 'etat': 'rupture_stock'},
            ];
            final reponses = await _executer(await _versPhp(m, requetes));

            final filtres = <(String?, String?, EtatArticleCarte)>[
              (null, null, EtatArticleCarte.tous),
              ('plat-0', null, EtatArticleCarte.tous),
              (null, 'plats', EtatArticleCarte.tous),
              (null, null, EtatArticleCarte.liesAuStock),
              (null, null, EtatArticleCarte.enRuptureDeStock),
            ];

            for (var r = 0; r < filtres.length; r++) {
              final (recherche, categorie, etat) = filtres[r];
              final carte =
                  ((await m.api.carte(
                            recherche: recherche,
                            categorie: CategorieCarte.depuisCode(categorie),
                            etat: etat,
                          ))
                          as RestaurantRecu<CarteRestaurant>)
                      .donnees;
              _comparer(
                carte,
                reponses[r],
                sansFiltre: reponses[0],
                contexte: 'scénario $k requête $r',
              );
            }

            // Le relevé porte sur la requête sans filtre.
            final tout =
                ((await m.api.carte()) as RestaurantRecu<CarteRestaurant>)
                    .donnees;
            plats += tout.lignes.length;
            sansPoint += tout.pointCuisineId == null ? 1 : 0;
            for (final l in tout.lignes) {
              ruptures += l.rupture ? 1 : 0;
              sousSeuil += l.sousSeuil ? 1 : 0;
              vides += l.lieAuStock ? 0 : 1;
              coutsConnus += l.coutMatiere != null ? 1 : 0;
              coutsIncomplets += l.coutMatiereIncomplet ? 1 : 0;
              provisoires += l.prixProvisoire ? 1 : 0;
              multiIngredients += l.nbIngredients > 1 ? 1 : 0;
              partiels += (l.portionsVendables ?? 0) > 0 ? 1 : 0;
            }
          } finally {
            await m.db.close();
          }
        }

        // Le balayage n'est pas vert à vide : chaque état a été atteint.
        expect(plats, greaterThan(300), reason: 'assez de plats');
        expect(ruptures, greaterThan(10), reason: 'des ruptures');
        expect(sousSeuil, greaterThan(10), reason: 'des sous seuil');
        expect(vides, greaterThan(10), reason: 'des fiches vides');
        expect(coutsConnus, greaterThan(20), reason: 'des coûts connus');
        expect(
          coutsIncomplets,
          greaterThan(10),
          reason: 'des coûts incomplets',
        );
        expect(
          sansPoint,
          greaterThanOrEqualTo(4),
          reason: 'sans point cuisine',
        );
        expect(provisoires, greaterThan(10), reason: 'des prix provisoires');
        expect(multiIngredients, greaterThan(20), reason: 'plusieurs lignes');
        expect(partiels, greaterThan(40), reason: 'des portions positives');
      },
      // Quarante-huit bases, cinq exécutions de PHP : plus que les 30 s par défaut.
      timeout: const Timeout(Duration(minutes: 4)),
    );
  });

  group('Un article en achat JOURNALIER : l’écart avec le serveur est '
      'NOMMÉ, et mesuré par PHP', () {
    test('le serveur rend « rupture » ; ce poste rend « non suivi »', () async {
      final m = await _monde();
      try {
        await m.stocks.creerPoint(libelle: 'Cuisine', type: TypePoint.cuisine);
        await m.stocks.creerArticle(
          id: 'a-oignon',
          libelle: 'Oignon',
          categorie: null,
          uniteMesure: 'kg',
          seuilCentiemes: 0,
          suivi: SuiviArticle.journalier,
          pointStockageId: null,
        );
        final menu = (await m.dao.enregistrerMenu(
          const SaisieMenu(libelle: 'Carte', type: 'local'),
          auteurId: 'u-1',
        )).id;
        final fiche = (await m.dao.enregistrerRecette(
          const SaisieFiche(
            libelle: 'Salade',
            lignes: [
              LigneSaisieComposition(articleId: 'a-oignon', quantite: '0,1'),
            ],
          ),
          auteurId: 'u-1',
        )).id;
        await m.dao.enregistrerPlat(
          SaisiePlat(
            libelle: 'Salade nue',
            menuId: menu,
            recetteId: fiche,
            prixVente: '1500',
          ),
          modification: false,
          auteurId: 'u-1',
        );

        final serveur = (await _executer(await _versPhp(m, [{}]))).single;
        final ligneServeur =
            (serveur['lignes'] as List<dynamic>).single as Map<String, dynamic>;
        // Le SERVEUR : zéro portion, rupture, sous seuil — pour un article dont
        // personne ne tient le stock.
        expect(ligneServeur['portions'], 0);
        expect(ligneServeur['rupture'], isTrue);
        expect(ligneServeur['sous_seuil'], isTrue);

        // CE POSTE : aucun chiffre, et la raison.
        final locale =
            ((await m.api.carte()) as RestaurantRecu<CarteRestaurant>)
                .donnees
                .lignes
                .single;
        expect(locale.portionsVendables, isNull);
        expect(locale.rupture, isFalse);
        expect(locale.sousSeuil, isFalse);
        expect(locale.motifSansStock, MotifSansStock.compositionSansSuivi);
        // Le coût, lui, est le même des deux côtés : l'oignon n'a jamais été
        // réceptionné, son coût est INCONNU (pas gratuit).
        expect(locale.coutMatiere, isNull);
        expect(locale.coutMatiere, ligneServeur['cout']);
        expect(locale.articlesSansCout, ['Oignon']);
      } finally {
        await m.db.close();
      }
    });

    test('un oignon dans une fiche de poulet : le serveur met TOUT le plat en '
        'rupture, ce poste compte le poulet', () async {
      final m = await _monde();
      try {
        await m.stocks.creerPoint(
          libelle: 'Cuisine',
          type: TypePoint.cuisine,
          id: 'p-cui',
        );
        await m.stocks.creerArticle(
          id: 'a-poulet',
          libelle: 'Poulet',
          categorie: null,
          uniteMesure: 'kg',
          seuilCentiemes: 0,
          suivi: SuiviArticle.permanent,
          pointStockageId: 'p-cui',
        );
        await m.stocks.creerArticle(
          id: 'a-oignon',
          libelle: 'Oignon',
          categorie: null,
          uniteMesure: 'kg',
          seuilCentiemes: 0,
          suivi: SuiviArticle.journalier,
          pointStockageId: null,
        );
        await m.stocks.ajouterMouvement(
          articleId: 'a-poulet',
          pointId: 'p-cui',
          type: TypeMouvement.entree,
          centiemes: 1000,
          motif: 'Réception',
          auteurId: 'u-1',
          coutDixMilliemes: 25000000,
        );
        final menu = (await m.dao.enregistrerMenu(
          const SaisieMenu(libelle: 'Carte', type: 'local'),
          auteurId: 'u-1',
        )).id;
        final fiche = (await m.dao.enregistrerRecette(
          const SaisieFiche(
            libelle: 'Poulet DG',
            lignes: [
              LigneSaisieComposition(articleId: 'a-poulet', quantite: '0,3'),
              LigneSaisieComposition(articleId: 'a-oignon', quantite: '0,05'),
            ],
          ),
          auteurId: 'u-1',
        )).id;
        await m.dao.enregistrerPlat(
          SaisiePlat(
            libelle: 'Poulet DG',
            menuId: menu,
            recetteId: fiche,
            prixVente: '4500',
          ),
          modification: false,
          auteurId: 'u-1',
        );

        final serveur = (await _executer(await _versPhp(m, [{}]))).single;
        final ligneServeur =
            (serveur['lignes'] as List<dynamic>).single as Map<String, dynamic>;
        // 10 kg de poulet à 0,3 kg la portion = 33 portions. Le serveur dit 0.
        expect(ligneServeur['portions'], 0);
        expect(ligneServeur['rupture'], isTrue);

        final locale =
            ((await m.api.carte()) as RestaurantRecu<CarteRestaurant>)
                .donnees
                .lignes
                .single;
        expect(locale.portionsVendables, 33);
        expect(locale.ingredientLimitant?.id, 'a-poulet');
        expect(locale.rupture, isFalse);
      } finally {
        await m.db.close();
      }
    });
  });
}

void driftRuntimeOptionsSansAvertissement() {
  // Plusieurs bases en mémoire dans un même test : le message de Drift n'a
  // d'intérêt que pour un oubli de fermeture, et chaque scénario ferme la sienne.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
}

/// Peuple une base avec un monde aléatoire mais SANS article journalier.
Future<void> _peupler(
  _Monde m,
  Random hasard, {
  required bool avecPointCuisine,
}) async {
  await m.stocks.creerPoint(
    libelle: 'Magasin',
    type: TypePoint.magasin,
    id: 'p-mag',
  );
  if (avecPointCuisine) {
    await m.stocks.creerPoint(
      libelle: 'Cuisine',
      type: TypePoint.cuisine,
      id: 'p-cui',
    );
  }

  // Les articles : 8 au plus, un seuil tiré, du stock au magasin comme en
  // cuisine, des coûts d'achat (ou aucun : un article jamais réceptionné).
  final articles = <String>[];
  for (var a = 0; a < 8; a++) {
    final id = 'a-${a.toString().padLeft(2, '0')}';
    articles.add(id);
    await m.stocks.creerArticle(
      id: id,
      libelle: 'Article $a',
      categorie: null,
      uniteMesure: a.isEven ? 'kg' : 'l',
      seuilCentiemes: hasard.nextInt(4) == 0 ? 0 : hasard.nextInt(1500),
      suivi: SuiviArticle.permanent,
      pointStockageId: 'p-mag',
    );

    final points = ['p-mag', if (avecPointCuisine) 'p-cui'];
    for (final point in points) {
      final entrees = hasard.nextInt(3);
      for (var e = 0; e < entrees; e++) {
        await m.stocks.ajouterMouvement(
          articleId: id,
          pointId: point,
          type: TypeMouvement.entree,
          centiemes: 1 + hasard.nextInt(hasard.nextInt(5) == 0 ? 40 : 6000),
          motif: 'Entrée',
          auteurId: 'u-1',
          coutDixMilliemes: hasard.nextInt(3) == 0
              ? null
              : 1000 + hasard.nextInt(40000000),
        );
      }
      if (hasard.nextInt(3) == 0) {
        // Une sortie ou une perte — forcée : la rupture est un état à atteindre.
        await m.stocks.ajouterMouvement(
          articleId: id,
          pointId: point,
          type: hasard.nextBool() ? TypeMouvement.sortie : TypeMouvement.perte,
          centiemes: 1 + hasard.nextInt(3000),
          motif: 'Sortie',
          auteurId: 'u-1',
          forcage: true,
        );
      }
    }
  }

  // Les menus.
  for (var i = 0; i < 3; i++) {
    final type = typesDeMenu[i];
    final menu = await m.dao.enregistrerMenu(
      SaisieMenu(libelle: 'Menu $type', type: type),
      auteurId: 'u-1',
    );
    m.menus.add(menu.id);
    m.menuTypes[menu.id] = type;
  }

  // Les fiches : de zéro à quatre ingrédients distincts.
  final nbFiches = 4 + hasard.nextInt(5);
  for (var f = 0; f < nbFiches; f++) {
    final nb = hasard.nextInt(5) == 0 ? 0 : 1 + hasard.nextInt(4);
    final choisis = [...articles]..shuffle(hasard);
    final fiche = await m.dao.enregistrerRecette(
      SaisieFiche(
        libelle: 'Fiche $f',
        lignes: [
          for (final article in choisis.take(nb))
            LigneSaisieComposition(
              articleId: article,
              quantite:
                  '${hasard.nextInt(4)},${(1 + hasard.nextInt(998)).toString().padLeft(3, '0')}',
            ),
        ],
      ),
      auteurId: 'u-1',
    );
    m.fiches.add(fiche.id);
  }

  // Les plats : 6 à 14, deux plats peuvent partager une fiche.
  final nbPlats = 6 + hasard.nextInt(9);
  for (var p = 0; p < nbPlats; p++) {
    final plat = await m.dao.enregistrerPlat(
      SaisiePlat(
        libelle: 'plat-${p.toString().padLeft(3, '0')}',
        menuId: m.menus[hasard.nextInt(m.menus.length)],
        recetteId: m.fiches[hasard.nextInt(m.fiches.length)],
        prixVente: '${hasard.nextInt(20000)}',
        prixProvisoire: hasard.nextInt(4) == 0,
        // Une catégorie sur cinq manque (plat d'avant la v41).
        categorie: hasard.nextInt(5) == 0
            ? null
            : CategorieCarte.values[hasard.nextInt(3)].code,
      ),
      modification: false,
      auteurId: 'u-1',
    );
    m.plats.add(plat.id);
  }
}
