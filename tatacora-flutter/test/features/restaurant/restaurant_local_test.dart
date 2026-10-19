@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/restaurant/data/restaurant_api.dart';
import 'package:tatacora_flutter/features/restaurant/data/restaurant_dao.dart';
import 'package:tatacora_flutter/features/restaurant/domain/entities/carte_restaurant.dart';
import 'package:tatacora_flutter/features/restaurant/domain/entities/plat.dart';
import 'package:tatacora_flutter/features/restaurant/domain/messages_restaurant.dart';
import 'package:tatacora_flutter/features/stocks/data/stocks_dao.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/etat_stock.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/mouvement_stock.dart';

/// M4 sur sa source LOCALE — par le chemin que l'écran emprunte :
/// `RestaurantApi` -> `RestaurantDao` -> `StocksDao` -> la base. Aucun faux : un
/// test qui simulerait le DAO ne dirait rien de ce que la base reçoit
/// réellement (piège 5).
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late StocksDao stocks;
  late RestaurantApi api;
  var peutLire = true;
  var peutEcrire = true;
  String? auteur = 'u-1';

  setUp(() async {
    db = AppDatabase.enMemoire();
    peutLire = true;
    peutEcrire = true;
    auteur = 'u-1';

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

    stocks = StocksDao(db);
    api = RestaurantApi(
      dao: RestaurantDao(db, stocks: stocks),
      peutLire: () => peutLire,
      peutEcrire: () => peutEcrire,
      auteurId: () => auteur,
    );
  });

  tearDown(() => db.close());

  /* -------------------------------------------------------------------- */
  /* Aides                                                                  */
  /* -------------------------------------------------------------------- */

  Future<int> compte(String table) async {
    final r = await db
        .customSelect('SELECT COUNT(*) AS n FROM $table')
        .getSingle();
    return r.data['n'] as int;
  }

  T recu<T>(ResultatRestaurant<T> r) {
    expect(r, isA<RestaurantRecu<T>>(), reason: '$r');
    return (r as RestaurantRecu<T>).donnees;
  }

  RestaurantRefuse<T> refuse<T>(ResultatRestaurant<T> r) {
    expect(r, isA<RestaurantRefuse<T>>(), reason: '$r');
    return r as RestaurantRefuse<T>;
  }

  Future<void> article(
    String id,
    String libelle, {
    SuiviArticle suivi = SuiviArticle.permanent,
    int seuil = 0,
    String unite = 'kg',
  }) => stocks.creerArticle(
    id: id,
    libelle: libelle,
    categorie: null,
    uniteMesure: unite,
    seuilCentiemes: seuil,
    suivi: suivi,
    pointStockageId: null,
  );

  Future<void> entree(
    String articleId,
    String pointId,
    int centiemes, {
    int? cout,
  }) async {
    await stocks.ajouterMouvement(
      articleId: articleId,
      pointId: pointId,
      type: TypeMouvement.entree,
      centiemes: centiemes,
      motif: 'Réception',
      auteurId: 'u-1',
      coutDixMilliemes: cout,
    );
  }

  Future<String> menu(String libelle, {String type = 'local'}) async => recu(
    await api.enregistrerMenu(SaisieMenu(libelle: libelle, type: type)),
  ).id;

  Future<String> fiche(
    String libelle,
    List<(String, String)> lignes, {
    String? id,
  }) async => recu(
    await api.enregistrerRecette(
      SaisieFiche(
        id: id,
        libelle: libelle,
        lignes: [
          for (final (a, q) in lignes)
            LigneSaisieComposition(articleId: a, quantite: q),
        ],
      ),
    ),
  ).id;

  Future<Plat> plat(
    String libelle,
    String menuId,
    String recetteId, {
    String prix = '4500',
    bool provisoire = false,
  }) async => recu(
    await api.enregistrerPlat(
      SaisiePlat(
        libelle: libelle,
        menuId: menuId,
        recetteId: recetteId,
        prixVente: prix,
        prixProvisoire: provisoire,
      ),
      modification: false,
    ),
  );

  /* -------------------------------------------------------------------- */
  /* Les phrases de refus sont CELLES DU SERVEUR                            */
  /* -------------------------------------------------------------------- */

  group('Les phrases du serveur sont reprises mot pour mot', () {
    Future<Map<String, dynamic>> langue() async {
      final r = await Process.run(
        'php',
        ['tool/restaurant/exporter_langue.php'],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      expect(
        r.exitCode,
        0,
        reason: 'PHP est requis : ÉCHEC, pas saut. ${r.stderr}',
      );
      return jsonDecode(r.stdout as String) as Map<String, dynamic>;
    }

    String remplacer(String modele, Map<String, String> valeurs) {
      var texte = modele;
      valeurs.forEach((cle, v) => texte = texte.replaceAll(':$cle', v));
      return texte;
    }

    test(
      'lang/fr/restaurant.php (validation), relu en exécutant PHP',
      () async {
        final validation =
            ((await langue())['restaurant']
                    as Map<String, dynamic>)['validation']
                as Map<String, dynamic>;

        // Relevé des clés effectivement confrontées : un balayage vide serait
        // vert à vide.
        final attendu = <String, String>{
          'libelle_obligatoire': MessagesRestaurant.libelleObligatoire,
          'categorie_inconnue': MessagesRestaurant.categorieInconnue,
          'menu_obligatoire': MessagesRestaurant.menuObligatoire,
          'menu_inexistant': MessagesRestaurant.menuInexistant,
          'recette_obligatoire': MessagesRestaurant.recetteObligatoire,
          'recette_inexistante': MessagesRestaurant.recetteInexistante,
          'prix_obligatoire': MessagesRestaurant.prixObligatoire,
          'prix_negatif': MessagesRestaurant.prixNegatif,
          'saison_inversee': MessagesRestaurant.saisonInversee,
          'article_obligatoire': MessagesRestaurant.articleObligatoire,
          'article_inexistant': MessagesRestaurant.articleInexistant,
          'ingredient_en_double': MessagesRestaurant.ingredientEnDouble,
          'quantite_recette_obligatoire':
              MessagesRestaurant.quantiteRecetteObligatoire,
          'quantite_recette_positive':
              MessagesRestaurant.quantiteRecettePositive,
        };
        expect(attendu, hasLength(14));
        for (final e in attendu.entries) {
          expect(e.value, validation[e.key], reason: 'validation.${e.key}');
        }
      },
    );

    test(
      'lang/fr/carte_pwa.php (restauration) : les messages de la VUE',
      () async {
        final v =
            ((await langue())['carte_pwa']
                    as Map<String, dynamic>)['restauration']
                as Map<String, dynamic>;

        expect(MessagesRestaurant.aucunMenu, v['aucun_menu']);
        expect(MessagesRestaurant.aucuneFiche, v['aucune_fiche']);
        expect(
          MessagesRestaurant.recetteSansIngredient,
          v['recette_sans_ingredient'],
        );
        expect(
          MessagesRestaurant.recetteAucunArticle,
          v['recette_aucun_article'],
        );

        expect(
          MessagesRestaurant.platEnregistre('Poulet DG', creation: true),
          remplacer(v['cree'] as String, {'plat': 'Poulet DG'}),
        );
        expect(
          MessagesRestaurant.platEnregistre('Poulet DG', creation: false),
          remplacer(v['modifie'] as String, {'plat': 'Poulet DG'}),
        );
        expect(
          MessagesRestaurant.menuEnregistre('Carte', creation: true),
          remplacer(v['menu_cree'] as String, {'libelle': 'Carte'}),
        );
        expect(
          MessagesRestaurant.menuEnregistre('Carte', creation: false),
          remplacer(v['menu_modifie'] as String, {'libelle': 'Carte'}),
        );

        // Les six phrases d'une fiche : le coût est dit dans ses TROIS états.
        for (final creation in [true, false]) {
          final p = creation ? 'creee' : 'modifiee';
          expect(
            MessagesRestaurant.ficheEnregistree(
              libelle: 'Poulet',
              creation: creation,
              vide: false,
              incomplet: false,
              articlesSansCout: const [],
              cout: '750 FCFA',
            ),
            remplacer(v['recette_$p'] as String, {
              'recette': 'Poulet',
              'cout': '750 FCFA',
            }),
            reason: 'recette_$p',
          );
          expect(
            MessagesRestaurant.ficheEnregistree(
              libelle: 'Poulet',
              creation: creation,
              vide: true,
              incomplet: false,
              articlesSansCout: const [],
            ),
            remplacer(v['recette_${p}_sans_ingredient'] as String, {
              'recette': 'Poulet',
            }),
            reason: 'recette_${p}_sans_ingredient',
          );
          expect(
            MessagesRestaurant.ficheEnregistree(
              libelle: 'Poulet',
              creation: creation,
              vide: false,
              incomplet: true,
              articlesSansCout: const ['Riz', 'Oignon'],
            ),
            remplacer(v['recette_${p}_cout_incomplet'] as String, {
              'recette': 'Poulet',
              'articles': 'Riz, Oignon',
            }),
            reason: 'recette_${p}_cout_incomplet',
          );
        }
      },
    );
  });

  /* -------------------------------------------------------------------- */
  /* Menus                                                                  */
  /* -------------------------------------------------------------------- */

  group('Un menu', () {
    test('naît avec ses colonnes, son auteur et rien de plus', () async {
      final m = recu(
        await api.enregistrerMenu(
          const SaisieMenu(
            libelle: ' Carte d’été ',
            type: 'europeen',
            dateDebut: '2026-06-01',
            dateFin: '2026-09-30',
          ),
        ),
      );
      expect(m.libelle, 'Carte d’été');
      expect(m.typeBrut, 'europeen');
      expect(m.typeLibelle, 'Européen');
      expect(m.dateDebut, '2026-06-01');
      expect(m.dateFin, '2026-09-30');
      expect(m.nbPlats, 0);

      final ligne = await db.select(db.menusLocal).getSingle();
      expect(ligne.creePar, 'u-1');
      expect(ligne.modifiePar, isNull);
      expect(ligne.id, m.id);
    });

    test(
      'se modifie : l’identifiant, l’auteur de création et la date de '
      'création sont conservés, la saison peut redevenir permanente',
      () async {
        final id = recu(
          await api.enregistrerMenu(
            const SaisieMenu(
              libelle: 'Saison',
              type: 'local',
              dateDebut: '2026-06-01',
              dateFin: '2026-09-30',
            ),
          ),
        ).id;
        final avant = await db.select(db.menusLocal).getSingle();

        final apres = recu(
          await api.enregistrerMenu(
            SaisieMenu(id: id, libelle: 'Permanent', type: 'special'),
          ),
        );
        expect(apres.id, id);
        expect(apres.libelle, 'Permanent');
        expect(apres.typeBrut, 'special');
        // `null` ÉCRIT : vider une date est un geste, pas un oubli.
        expect(apres.dateDebut, isNull);
        expect(apres.dateFin, isNull);

        final ligne = await db.select(db.menusLocal).getSingle();
        expect(await compte('menus_local'), 1);
        expect(ligne.creeLe, avant.creeLe);
        expect(ligne.creePar, 'u-1');
        expect(ligne.modifiePar, 'u-1');
        expect(ligne.modifieLe, isNotNull);
      },
    );

    test('un refus est dit champ par champ, avec la phrase du serveur, et '
        'n’écrit RIEN', () async {
      final r = refuse(
        await api.enregistrerMenu(
          const SaisieMenu(
            libelle: '',
            type: 'gastronomique',
            dateDebut: '2026-09-30',
            dateFin: '2026-01-01',
          ),
        ),
      );
      expect(r.code, 422);
      expect(r.erreurs['libelle'], MessagesRestaurant.libelleObligatoire);
      expect(r.erreurs['type'], MessagesRestaurant.categorieInconnue);
      expect(r.erreurs['date_fin'], MessagesRestaurant.saisonInversee);
      expect(await compte('menus_local'), 0);
    });

    test('modifier un menu inconnu est refusé, pas créé', () async {
      final r = refuse(
        await api.enregistrerMenu(
          const SaisieMenu(id: 'fantome', libelle: 'x', type: 'local'),
        ),
      );
      expect(r.motif, MessagesRestaurant.menuInexistant);
      expect(await compte('menus_local'), 0);
    });

    test('le nombre de plats est COMPTÉ des plats, pas stocké', () async {
      final m1 = await menu('Carte A');
      await menu('Carte B');
      final f = await fiche('Fiche', []);
      await plat('Riz', m1, f);
      await plat('Pâtes', m1, f);

      final liste = recu(await api.menus()).elements;
      expect(
        {for (final m in liste) m.libelle: m.nbPlats},
        {'Carte A': 2, 'Carte B': 0},
      );
    });

    test('la liste est triée par libellé SANS accent, et se filtre par type '
        'et par recherche', () async {
      await menu('Zeste', type: 'special');
      await menu('Éclat');
      await menu('apéritif', type: 'europeen');

      expect(
        [for (final m in recu(await api.menus()).elements) m.libelle],
        ['apéritif', 'Éclat', 'Zeste'],
      );
      expect(
        [
          for (final m in recu(
            await api.menus(type: CategoriePlat.europeen),
          ).elements)
            m.libelle,
        ],
        ['apéritif'],
      );
      expect(
        [
          for (final m in recu(await api.menus(recherche: 'ECLAT')).elements)
            m.libelle,
        ],
        ['Éclat'],
      );
    });
  });

  /* -------------------------------------------------------------------- */
  /* Fiches techniques                                                      */
  /* -------------------------------------------------------------------- */

  group('Une fiche technique', () {
    setUp(() async {
      await stocks.creerPoint(
        libelle: 'Cuisine',
        type: TypePoint.cuisine,
        id: 'p-cui',
      );
      await article('a-poulet', 'Poulet');
      await article('a-riz', 'Riz');
      await article('a-oignon', 'Oignon', suivi: SuiviArticle.journalier);
    });

    test(
      'se crée avec sa composition, son coût calculé et ses états',
      () async {
        await entree('a-poulet', 'p-cui', 1000, cout: 25000000);
        await entree('a-riz', 'p-cui', 5000, cout: 8000000);
        final r = recu(
          await api.enregistrerRecette(
            const SaisieFiche(
              libelle: 'Poulet DG',
              lignes: [
                LigneSaisieComposition(articleId: 'a-poulet', quantite: '0,3'),
                LigneSaisieComposition(articleId: 'a-riz', quantite: '0,15'),
              ],
            ),
          ),
        );
        // 0,3 × 2 500 = 750,00 ; 0,15 × 800 = 120,00.
        expect(r.coutMatiere, '870.00');
        expect(r.coutMatiereIncomplet, isFalse);
        expect(r.compositionVide, isFalse);
        expect(r.nbIngredients, 2);
        expect(r.etat, EtatFiche.composee);
        expect(await compte('ingredients_recette_local'), 2);
      },
    );

    test('la composition est REMPLACÉE, jamais fusionnée : l’ingrédient '
        'retiré à l’écran disparaît de la fiche', () async {
      final id = await fiche('Poulet DG', [
        ('a-poulet', '0,3'),
        ('a-riz', '0,15'),
      ]);
      await fiche('Poulet DG', [('a-poulet', '0,4')], id: id);

      final lignes = await db.select(db.ingredientsRecetteLocal).get();
      expect(lignes, hasLength(1));
      expect(lignes.single.articleId, 'a-poulet');
      expect(lignes.single.quantiteMilliemes, 400);
      expect(await compte('recettes_local'), 1);
    });

    test('vider une fiche erronée est possible : une composition VIDE est '
        'acceptée', () async {
      final id = await fiche('Erreur', [('a-poulet', '1')]);
      final r = recu(
        await api.enregistrerRecette(
          SaisieFiche(id: id, libelle: 'Erreur', lignes: const []),
        ),
      );
      expect(r.compositionVide, isTrue);
      expect(r.coutMatiere, isNull);
      expect(r.etat, EtatFiche.vide);
      expect(await compte('ingredients_recette_local'), 0);
    });

    test('un article inconnu est refusé AVANT toute écriture, sur la ligne '
        'fautive, avec la phrase du serveur', () async {
      final r = refuse(
        await api.enregistrerRecette(
          const SaisieFiche(
            libelle: 'Fantôme',
            lignes: [
              LigneSaisieComposition(articleId: '', quantite: ''),
              LigneSaisieComposition(articleId: 'a-poulet', quantite: '1'),
              LigneSaisieComposition(articleId: 'a-fantome', quantite: '1'),
            ],
          ),
        ),
      );
      expect(r.code, 422);
      expect(r.erreurs.keys, ['lignes.2.article_id']);
      expect(
        r.erreurs['lignes.2.article_id'],
        MessagesRestaurant.articleInexistant,
      );
      // Ni l'en-tête ni la première ligne n'ont été écrits : pas de fiche
      // orpheline, indiscernable d'une fiche volontairement vide.
      expect(await compte('recettes_local'), 0);
      expect(await compte('ingredients_recette_local'), 0);
    });

    test('ATOMIQUE : une insertion de composition qui échoue défait l’entête '
        'ET les lignes déjà écrites', () async {
      // Un échec RÉEL du moteur, après l'écriture de l'entête et d'une ligne :
      // un déclencheur refuse la quantité 0,777. Les contrôles préalables ne le
      // voient pas (l'article existe, la quantité est valide).
      await db.customStatement(
        'CREATE TRIGGER refus_essai BEFORE INSERT ON ingredients_recette_local '
        "WHEN NEW.quantite_milliemes = 777 BEGIN SELECT RAISE(ABORT, 'refus'); END",
      );

      await expectLater(
        api.enregistrerRecette(
          const SaisieFiche(
            libelle: 'Atomique',
            lignes: [
              LigneSaisieComposition(articleId: 'a-poulet', quantite: '0,3'),
              LigneSaisieComposition(articleId: 'a-riz', quantite: '0,777'),
            ],
          ),
        ),
        throwsA(isA<Exception>()),
      );

      expect(await compte('recettes_local'), 0);
      expect(await compte('ingredients_recette_local'), 0);
    });

    test('un refus de saisie ne touche pas à la fiche existante', () async {
      final id = await fiche('Poulet DG', [('a-poulet', '0,3')]);
      final r = refuse(
        await api.enregistrerRecette(
          SaisieFiche(
            id: id,
            libelle: 'Poulet DG',
            lignes: const [
              LigneSaisieComposition(articleId: 'a-riz', quantite: '0,0001'),
            ],
          ),
        ),
      );
      expect(
        r.erreurs['lignes.0.quantite_unitaire'],
        MessagesRestaurant.quantiteTropFine,
      );
      final lignes = await db.select(db.ingredientsRecetteLocal).get();
      expect([for (final l in lignes) l.articleId], ['a-poulet']);
    });

    test('modifier une fiche inconnue est refusé, pas créé', () async {
      final r = refuse(
        await api.enregistrerRecette(
          const SaisieFiche(id: 'fantome', libelle: 'x', lignes: []),
        ),
      );
      expect(r.motif, MessagesRestaurant.recetteInexistante);
      expect(await compte('recettes_local'), 0);
    });

    test('le coût d’un ingrédient jamais réceptionné est INCONNU, nommé, pas '
        'zéro', () async {
      final id = await fiche('Salade', [('a-oignon', '0,1')]);
      final detail = recu(await api.recette(id));
      expect(detail.recette.coutMatiere, isNull);
      expect(detail.recette.coutMatiereIncomplet, isTrue);
      expect(detail.recette.articlesSansCout, ['Oignon']);
      // Composée d'un seul article journalier : elle ne décrémente rien.
      expect(detail.recette.etat, EtatFiche.sansSuivi);
      final l = detail.composition.single;
      expect(l.articleLibelle, 'Oignon');
      expect(l.uniteMesure, 'kg');
      expect(l.quantiteUnitaire, '0.100');
      expect(l.coutUnitaire, isNull);
      expect(l.coutLigne, isNull);
    });

    test('la fiche détaillée porte le coût de chaque ligne', () async {
      await entree('a-poulet', 'p-cui', 1000, cout: 25000000);
      final id = await fiche('Poulet', [('a-poulet', '0,3')]);
      final l = recu(await api.recette(id)).composition.single;
      expect(l.coutUnitaire, '2500.0000');
      expect(l.coutLigne, '750.00');
    });

    test(
      'la composition se relit à trois décimales, pour être rééditée',
      () async {
        final id = await fiche('Poulet', [('a-poulet', '0,4'), ('a-riz', '2')]);
        final lignes = (await api.compositionEditable(id))!;
        expect(
          [for (final l in lignes) (l.articleId, l.quantite)],
          [('a-poulet', '0.400'), ('a-riz', '2.000')],
        );
      },
    );

    test('la liste : états, plats servis, filtre « vides seulement » et '
        'recherche', () async {
      final vide = await fiche('Fiche à écrire', []);
      await fiche('Bouillon', [('a-poulet', '1')]);
      final m = await menu('Carte');
      await plat('Salade nue', m, vide);
      await plat('Crudités', m, vide);

      final toutes = recu(await api.recettes()).elements;
      expect(
        [for (final f in toutes) f.libelle],
        ['Bouillon', 'Fiche à écrire'],
      );
      final v = toutes.last;
      expect(v.etat, EtatFiche.vide);
      expect(v.platsServis, ['Crudités', 'Salade nue']);
      expect(toutes.first.platsServis, isEmpty);

      expect(
        [
          for (final f in recu(
            await api.recettes(videsSeulement: true),
          ).elements)
            f.libelle,
        ],
        ['Fiche à écrire'],
      );
      expect(
        [
          for (final f in recu(
            await api.recettes(recherche: 'ECRIRE'),
          ).elements)
            f.libelle,
        ],
        ['Fiche à écrire'],
      );

      final k = recu(await api.compteursFiches());
      expect(k.total, 2);
      expect(k.vides, 1);
    });

    test(
      'les articles proposés sont de vrais articles, triés sans accent',
      () async {
        await article('a-eau', 'Éau');
        final choix = (await api.articlesPourFiches())!;
        expect(
          [for (final a in choix) a.libelle],
          ['Éau', 'Oignon', 'Poulet', 'Riz'],
        );
        expect(
          choix.firstWhere((a) => a.id == 'a-oignon').suivi,
          SuiviArticle.journalier,
        );
      },
    );
  });

  /* -------------------------------------------------------------------- */
  /* Plats                                                                  */
  /* -------------------------------------------------------------------- */

  group('Un plat', () {
    late String m;
    late String f;

    setUp(() async {
      m = await menu('Carte', type: 'special');
      f = await fiche('Fiche', []);
    });

    test(
      'naît avec ses colonnes : prix en francs entiers, auteur, menu, fiche',
      () async {
        final p = await plat('Poulet DG', m, f, prix: '4 500');
        expect(p.libelle, 'Poulet DG');
        expect(p.prixVente, '4500.00');
        expect(p.menuId, m);
        expect(p.menuLibelle, 'Carte');
        expect(p.categorieBrute, 'special');
        expect(p.categorieLibelle, 'Spécial');
        expect(p.recetteId, f);
        expect(p.recetteLibelle, 'Fiche');
        expect(p.prixProvisoire, isFalse);
        expect(p.prixCorrigeMain, isFalse);

        final ligne = await db.select(db.platsLocal).getSingle();
        expect(ligne.prixVente, 4500);
        expect(ligne.creePar, 'u-1');
      },
    );

    test('un plat OFFERT (prix zéro) est enregistré', () async {
      final p = await plat('Amuse-bouche', m, f, prix: '0');
      expect(p.prixVente, '0.00');
    });

    test(
      'un prix à fraction de franc est refusé et RIEN n’est écrit',
      () async {
        final r = refuse(
          await api.enregistrerPlat(
            SaisiePlat(
              libelle: 'x',
              menuId: m,
              recetteId: f,
              prixVente: '4500,50',
            ),
            modification: false,
          ),
        );
        expect(r.erreurs['prix_vente'], MessagesRestaurant.prixFractionDeFranc);
        expect(await compte('plats_local'), 0);
      },
    );

    test('un menu ou une fiche inconnus sont refusés avec la phrase du '
        'serveur, par champ', () async {
      final r = refuse(
        await api.enregistrerPlat(
          const SaisiePlat(
            libelle: 'x',
            menuId: 'm-fantome',
            recetteId: 'f-fantome',
            prixVente: '100',
          ),
          modification: false,
        ),
      );
      expect(r.erreurs['menu_id'], MessagesRestaurant.menuInexistant);
      expect(r.erreurs['recette_id'], MessagesRestaurant.recetteInexistante);
      expect(await compte('plats_local'), 0);
    });

    test('« corrigé à la main » se DÉDUIT : un plat provisoire dont le prix '
        'change porte la marque', () async {
      final p = await plat('Brochette', m, f, prix: '1000', provisoire: true);

      // Le prix ne change pas : rien.
      var apres = recu(
        await api.enregistrerPlat(
          SaisiePlat(
            id: p.id,
            libelle: 'Brochette',
            menuId: m,
            recetteId: f,
            prixVente: '1000',
            prixProvisoire: true,
          ),
          modification: true,
        ),
      );
      expect(apres.prixCorrigeMain, isFalse);
      expect(apres.prixProvisoire, isTrue);

      // Le prix change : la marque se pose, sans que personne la coche.
      apres = recu(
        await api.enregistrerPlat(
          SaisiePlat(
            id: p.id,
            libelle: 'Brochette',
            menuId: m,
            recetteId: f,
            prixVente: '1200',
            prixProvisoire: true,
          ),
          modification: true,
        ),
      );
      expect(apres.prixCorrigeMain, isTrue);
      expect(apres.prixVente, '1200.00');

      // Décocher « provisoire » ne LÈVE pas la marque : c'est un fait.
      apres = recu(
        await api.enregistrerPlat(
          SaisiePlat(
            id: p.id,
            libelle: 'Brochette',
            menuId: m,
            recetteId: f,
            prixVente: '1200',
          ),
          modification: true,
        ),
      );
      expect(apres.prixProvisoire, isFalse);
      expect(apres.prixCorrigeMain, isTrue);
    });

    test(
      'un plat jamais provisoire dont le prix change ne porte pas la marque',
      () async {
        final p = await plat('Riz', m, f, prix: '1000');
        final apres = recu(
          await api.enregistrerPlat(
            SaisiePlat(
              id: p.id,
              libelle: 'Riz',
              menuId: m,
              recetteId: f,
              prixVente: '1500',
            ),
            modification: true,
          ),
        );
        expect(apres.prixCorrigeMain, isFalse);
      },
    );

    test('la modification conserve l’identifiant, la création et l’auteur '
        'de création', () async {
      final p = await plat('Riz', m, f);
      final avant = await db.select(db.platsLocal).getSingle();
      await api.enregistrerPlat(
        SaisiePlat(
          id: p.id,
          libelle: 'Riz sauce',
          menuId: m,
          recetteId: f,
          prixVente: '1500',
        ),
        modification: true,
      );
      final apres = await db.select(db.platsLocal).getSingle();
      expect(await compte('plats_local'), 1);
      expect(apres.id, p.id);
      expect(apres.libelle, 'Riz sauce');
      expect(apres.creeLe, avant.creeLe);
      expect(apres.creePar, 'u-1');
      expect(apres.modifiePar, 'u-1');
    });

    test('modifier un plat inconnu est refusé, pas créé', () async {
      final r = refuse(
        await api.enregistrerPlat(
          SaisiePlat(
            id: 'fantome',
            libelle: 'x',
            menuId: m,
            recetteId: f,
            prixVente: '1',
          ),
          modification: true,
        ),
      );
      expect(r.motif, 'Ce plat ne figure pas au catalogue.');
      expect(await compte('plats_local'), 0);
    });

    test('deux plats peuvent porter le même nom dans deux menus : le serveur '
        'l’admet', () async {
      final autre = await menu('Fête');
      await plat('Poulet DG', m, f);
      await plat('Poulet DG', autre, f);
      expect(await compte('plats_local'), 2);
    });
  });

  group('Le catalogue des plats', () {
    late String m;
    late String f;

    setUp(() async {
      m = await menu('Carte');
      f = await fiche('Fiche', []);
      for (var i = 0; i < 25; i++) {
        await plat('Plat ${i.toString().padLeft(2, '0')}', m, f);
      }
    });

    test('dix par page : 10, 10, 5 — le total est celui du filtre', () async {
      final p1 = recu(await api.plats());
      expect(p1.elements, hasLength(10));
      expect(p1.total, 25);
      expect(p1.derniere, 3);
      expect((p1.premier, p1.dernier), (1, 10));

      final p3 = recu(await api.plats(page: 3));
      expect(p3.elements, hasLength(5));
      expect((p3.premier, p3.dernier), (21, 25));
      expect(p3.elements.last.libelle, 'Plat 24');
    });

    test(
      'la recherche porte sur le catalogue ENTIER, pas sur la page',
      () async {
        final r = recu(await api.plats(recherche: 'plat 24'));
        expect(r.total, 1);
        expect(r.elements.single.libelle, 'Plat 24');
      },
    );

    test('une page hors bornes est ramenée à la dernière, pas vide', () async {
      final r = recu(await api.plats(page: 99));
      expect(r.page, 3);
      expect(r.elements, hasLength(5));
    });

    test('un catalogue vide : zéro, page 1 sur 1', () async {
      final r = recu(await api.plats(recherche: 'introuvable'));
      expect((r.total, r.premier, r.dernier, r.derniere), (0, 0, 0, 1));
    });

    test('les compteurs : avec fiche (composée) / sans fiche, sur le '
        'catalogue entier', () async {
      await article('a-1', 'Riz');
      final composee = await fiche('Composée', [('a-1', '1')]);
      await plat('Garni', m, composee);

      final k = recu(await api.compteursCatalogue());
      expect(k.total, 26);
      expect(k.avecFiche, 1);
      expect(k.sansFiche, 25);
    });
  });

  /* -------------------------------------------------------------------- */
  /* La carte, branchée sur le stock réel de M6                             */
  /* -------------------------------------------------------------------- */

  group('La carte lit le stock du point cuisine', () {
    test('33 portions, puis 25 après une sortie de 2,50 kg — et le plat '
        'dit son ingrédient limitant', () async {
      await stocks.creerPoint(
        libelle: 'Cuisine',
        type: TypePoint.cuisine,
        id: 'p-cui',
      );
      await stocks.creerPoint(
        libelle: 'Magasin',
        type: TypePoint.magasin,
        id: 'p-mag',
      );
      await article('a-poulet', 'Poulet');
      await entree('a-poulet', 'p-cui', 1000, cout: 25000000);
      // Du stock au MAGASIN : il ne compte pas, ce qui dort au magasin n'est
      // pas servi en salle.
      await entree('a-poulet', 'p-mag', 99900);
      final f = await fiche('Poulet DG', [('a-poulet', '0,3')]);
      final m = await menu('Carte');
      await plat('Poulet DG', m, f, prix: '4500');

      var l = recu(await api.carte()).lignes.single;
      expect(l.portionsVendables, 33);
      expect(l.coutMatiere, '750.00');
      expect(l.marge, '3750.00');
      expect(l.ingredientLimitant?.libelle, 'Poulet');

      await stocks.ajouterMouvement(
        articleId: 'a-poulet',
        pointId: 'p-cui',
        type: TypeMouvement.sortie,
        centiemes: 250,
        motif: 'Vente',
        auteurId: 'u-1',
      );
      l = recu(await api.carte()).lignes.single;
      expect(l.portionsVendables, 25);
    });

    test(
      'sans point cuisine, la carte le DIT : aucun chiffre, aucune rupture',
      () async {
        await article('a-1', 'Riz');
        final f = await fiche('Riz', [('a-1', '1')]);
        final m = await menu('Carte');
        await plat('Riz', m, f);

        final c = recu(await api.carte());
        expect(c.sansPointCuisine, isTrue);
        expect(c.lignes.single.portionsVendables, isNull);
        expect(c.lignes.single.rupture, isFalse);
        expect(
          c.lignes.single.motifSansStock,
          MotifSansStock.pointCuisineAbsent,
        );
        expect(c.indicateurs.enRupture, 0);
      },
    );

    test('une carte vide : zéro plat, pas de taux, les raisons des deux '
        'indicateurs sans source', () async {
      final c = recu(await api.carte());
      expect(c.lignes, isEmpty);
      expect(c.indicateurs.plats, 0);
      expect(c.indicateurs.tauxCouverture, isNull);
      expect(c.indicateurs.prixProvisoires, 0);
      expect(c.indicateurs.raisonAbsence('disponibles'), isNotNull);
      expect(c.indicateurs.raisonAbsence('indisponibles'), isNotNull);
      expect(c.indicateurs.raisonAbsence('prix_provisoires'), isNull);
    });

    test('un plat se relit seul, ou est introuvable', () async {
      final f = await fiche('Fiche', []);
      final m = await menu('Carte');
      final p = await plat('Riz', m, f);
      expect(recu(await api.plat(p.id)).libelle, 'Riz');
      expect(
        refuse(await api.plat('fantome')).motif,
        MessagesRestaurant.platIntrouvable,
      );
    });
  });

  /* -------------------------------------------------------------------- */
  /* Droits et auteur                                                       */
  /* -------------------------------------------------------------------- */

  group('Droits et auteur', () {
    test('sans droit d’écriture : refus 403 et RIEN n’est écrit', () async {
      peutEcrire = false;
      final r = refuse(
        await api.enregistrerMenu(
          const SaisieMenu(libelle: 'x', type: 'local'),
        ),
      );
      expect(r.code, 403);
      expect(r.motif, MessagesRestaurant.droitEcritureRefuse);
      expect(await compte('menus_local'), 0);

      expect(
        refuse(
          await api.enregistrerRecette(
            const SaisieFiche(libelle: 'x', lignes: []),
          ),
        ).code,
        403,
      );
      expect(await compte('recettes_local'), 0);
      expect(
        refuse(
          await api.enregistrerPlat(
            const SaisiePlat(
              libelle: 'x',
              menuId: 'a',
              recetteId: 'b',
              prixVente: '1',
            ),
            modification: false,
          ),
        ).code,
        403,
      );
    });

    test('sans droit de lecture : tout est refusé, et les sélecteurs rendent '
        'null — pas une liste vide qui dirait « aucun menu »', () async {
      await menu('Carte');
      peutLire = false;
      expect(refuse(await api.carte()).code, 403);
      expect(refuse(await api.plats()).code, 403);
      expect(refuse(await api.menus()).code, 403);
      expect(refuse(await api.recettes()).code, 403);
      expect(refuse(await api.compteursCatalogue()).code, 403);
      expect(refuse(await api.compteursFiches()).code, 403);
      expect(refuse(await api.recette('x')).code, 403);
      expect(await api.tousLesMenus(), isNull);
      expect(await api.toutesLesRecettes(), isNull);
      expect(await api.articlesPourFiches(), isNull);
      expect(await api.compositionEditable('x'), isNull);
    });

    test('sans auteur : aucune écriture (RG-15)', () async {
      auteur = null;
      final r = refuse(
        await api.enregistrerMenu(
          const SaisieMenu(libelle: 'x', type: 'local'),
        ),
      );
      expect(r.motif, MessagesRestaurant.auteurInconnu);
      expect(await compte('menus_local'), 0);
    });
  });

  /* -------------------------------------------------------------------- */
  /* Qui écrit : un seul auteur (pièges 9 et 11)                            */
  /* -------------------------------------------------------------------- */

  group('Un seul auteur pour les quatre tables', () {
    test('aucune écriture sur ces tables hors de RestaurantDao', () {
      final ecritures = RegExp(
        r'(into|update|delete)\(\s*(attachedDatabase\.|db\.|_db\.)?'
        r'(platsLocal|menusLocal|recettesLocal|ingredientsRecetteLocal)\b',
      );
      final insertSql = RegExp(
        r'(INSERT\s+INTO|UPDATE|DELETE\s+FROM)\s+'
        r'(plats_local|menus_local|recettes_local|ingredients_recette_local)\b',
        caseSensitive: false,
      );

      var lus = 0;
      final fautifs = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        if (f.path.endsWith('.g.dart')) continue;
        lus++;
        final chemin = f.path.replaceAll(r'\', '/');
        if (chemin.endsWith('features/restaurant/data/restaurant_dao.dart')) {
          continue;
        }
        // Le SECOND auteur, déclaré (lot F2b, 15/10/2026) : la DESCENTE du
        // catalogue serveur, qui n'enfile jamais (descente_catalogue_test).
        if (chemin.endsWith(
          'features/synchronisation/data/aligneur_catalogue.dart',
        )) {
          continue;
        }
        final texte = f
            .readAsLinesSync()
            .where((l) => !l.trimLeft().startsWith('//'))
            .join('\n');
        if (ecritures.hasMatch(texte) || insertSql.hasMatch(texte)) {
          fautifs.add(chemin);
        }
      }

      // Le balayage n'est pas vert à vide.
      expect(lus, greaterThan(200));
      expect(fautifs, isEmpty);
    });

    test('aucune de ces tables n’a de statut de synchronisation : annoncer '
        '« en attente » serait mentir', () async {
      for (final t in [
        'menus_local',
        'recettes_local',
        'ingredients_recette_local',
        'plats_local',
      ]) {
        final cols = await db.customSelect('PRAGMA table_info($t)').get();
        final noms = [for (final c in cols) c.data['name'] as String];
        expect(noms, isNotEmpty, reason: t);
        expect(noms.any((n) => n.contains('sync')), isFalse, reason: t);
      }
    });
  });
}
