import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/restaurant/domain/calcul_restaurant.dart';
import 'package:tatacora_flutter/features/restaurant/domain/entities/carte_restaurant.dart';
import 'package:tatacora_flutter/features/restaurant/domain/entities/plat.dart';
import 'package:tatacora_flutter/features/restaurant/domain/messages_restaurant.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/etat_stock.dart';

/// Les fonctions pures de M4, AVEC LEURS VALEURS EXACTES, calculées à la main.
///
/// La confrontation au serveur (PHP) est dans `carte_contre_serveur_test.dart` ;
/// ces cas-ci disent ce que chaque borne vaut, pour qu'une mutation d'une
/// constante ou d'un opérateur fasse rougir un cas NOMMÉ.
IngredientCalcule ing(
  String id, {
  required int quantite,
  int stock = 0,
  int seuil = 0,
  int cmp = 0,
  SuiviArticle suivi = SuiviArticle.permanent,
  String? libelle,
}) => IngredientCalcule(
  articleId: id,
  libelle: libelle ?? 'Article $id',
  uniteMesure: 'kg',
  quantiteMilliemes: quantite,
  suivi: suivi,
  seuilCentiemes: seuil,
  stockCentiemes: stock,
  cmpDixMilliemes: cmp,
);

PlatCalcule plat(
  String id,
  String libelle, {
  List<IngredientCalcule> composition = const [],
  String type = 'local',
  int prix = 1000,
  bool provisoire = false,
}) => PlatCalcule(
  id: id,
  libelle: libelle,
  menuId: 'm-$type',
  menuType: type,
  recetteId: 'r-$id',
  prixFrancs: prix,
  prixProvisoire: provisoire,
  composition: composition,
);

void main() {
  group('Lire ce qui est frappé', () {
    test('une quantité de recette : millièmes exacts, virgule acceptée', () {
      expect(lireMilliemes('0,25').milliemes, 250);
      expect(lireMilliemes('1.5').milliemes, 1500);
      expect(lireMilliemes('12').milliemes, 12000);
      expect(lireMilliemes(' 0,001 ').milliemes, 1);
      expect(lireMilliemes('0').milliemes, 0);
    });

    test('des zéros de fin ne sont pas une précision ; une 4e décimale '
        'non nulle est REFUSÉE, jamais tronquée', () {
      expect(lireMilliemes('0,2500').milliemes, 250);
      final trop = lireMilliemes('0,2501');
      expect(trop.milliemes, isNull);
      expect(trop.trop, isTrue);
    });

    test('ce qui n’est pas un nombre positif est illisible, sans être « trop '
        'fin »', () {
      for (final s in ['', 'abc', '-1', '1,2,3', '1 2', '0,']) {
        final r = lireMilliemes(s);
        expect(r.milliemes, isNull, reason: s);
        expect(r.trop, isFalse, reason: s);
      }
    });

    test('ecrireMilliemes : trois décimales toujours, comme le serveur', () {
      expect(ecrireMilliemes(300), '0.300');
      expect(ecrireMilliemes(1500), '1.500');
      expect(ecrireMilliemes(12000), '12.000');
      expect(ecrireMilliemes(1), '0.001');
    });

    test('un prix : des francs entiers, espaces et virgule tolérés', () {
      expect(lirePrix('4500').francs, 4500);
      expect(lirePrix(' 4 500 ').francs, 4500);
      expect(lirePrix('4500,00').francs, 4500);
      expect(lirePrix('4500.0').francs, 4500);
      expect(lirePrix('0').francs, 0);
      expect(lirePrix('-0').francs, 0);
    });

    test('un prix à fraction de franc est REFUSÉ, pas arrondi', () {
      final r = lirePrix('4500,50');
      expect(r.francs, isNull);
      expect(r.erreur, MessagesRestaurant.prixFractionDeFranc);
    });

    test('les refus de prix disent chacun leur raison', () {
      expect(lirePrix('').erreur, MessagesRestaurant.prixObligatoire);
      expect(lirePrix('   ').erreur, MessagesRestaurant.prixObligatoire);
      expect(lirePrix('-5').erreur, MessagesRestaurant.prixNegatif);
      expect(lirePrix('abc').erreur, MessagesRestaurant.prixIllisible);
      expect(lirePrix('12 34 ab').erreur, MessagesRestaurant.prixIllisible);
      expect(
        lirePrix('1234567890123').erreur,
        MessagesRestaurant.prixIllisible,
      );
    });

    test('ecrirePrix : la forme DECIMAL(15,2) du serveur', () {
      expect(ecrirePrix(4500), '4500.00');
      expect(ecrirePrix(0), '0.00');
      expect(ecrireCentimes(75000), '750.00');
      expect(ecrireCentimes(-5000), '-50.00');
    });

    test('une date doit exister au calendrier', () {
      expect(estDateValide('2026-02-28'), isTrue);
      expect(estDateValide('2024-02-29'), isTrue);
      expect(estDateValide('2025-02-29'), isFalse);
      expect(estDateValide('2026-02-30'), isFalse);
      expect(estDateValide('2026-13-01'), isFalse);
      expect(estDateValide('26-02-01'), isFalse);
      expect(estDateValide(''), isFalse);
    });
  });

  group('Vérifier un menu', () {
    test('un menu complet est normalisé', () {
      final lu = verifierMenu(
        const SaisieMenu(
          libelle: '  Carte d’été  ',
          type: 'europeen',
          dateDebut: '2026-06-01',
          dateFin: '2026-09-30',
        ),
      );
      expect(lu.erreurs, isEmpty);
      expect(lu.libelle, 'Carte d’été');
      expect(lu.type, 'europeen');
      expect(lu.dateDebut, '2026-06-01');
      expect(lu.dateFin, '2026-09-30');
    });

    test('un menu permanent n’a pas de saison : des dates vides sont null', () {
      final lu = verifierMenu(
        const SaisieMenu(libelle: 'Permanent', type: 'local'),
      );
      expect(lu.dateDebut, isNull);
      expect(lu.dateFin, isNull);
    });

    test('la fin peut précéder rien quand il n’y a pas de début', () {
      expect(
        verifierMenu(
          const SaisieMenu(libelle: 'x', type: 'local', dateFin: '2026-01-01'),
        ).erreurs,
        isEmpty,
      );
    });

    test('la fin ne peut pas précéder le début', () {
      final lu = verifierMenu(
        const SaisieMenu(
          libelle: 'x',
          type: 'local',
          dateDebut: '2026-09-30',
          dateFin: '2026-09-29',
        ),
      );
      expect(lu.erreurs['date_fin'], MessagesRestaurant.saisonInversee);
      // Le même jour : `after_or_equal`.
      expect(
        verifierMenu(
          const SaisieMenu(
            libelle: 'x',
            type: 'local',
            dateDebut: '2026-09-30',
            dateFin: '2026-09-30',
          ),
        ).erreurs,
        isEmpty,
      );
    });

    test(
      'libellé, type du registre fermé, dates : chaque refus a son champ',
      () {
        final lu = verifierMenu(
          const SaisieMenu(
            libelle: ' ',
            type: 'gastronomique',
            dateDebut: '2026-02-30',
            dateFin: 'demain',
          ),
        );
        expect(lu.erreurs['libelle'], MessagesRestaurant.libelleObligatoire);
        expect(lu.erreurs['type'], MessagesRestaurant.categorieInconnue);
        expect(lu.erreurs['date_debut'], MessagesRestaurant.dateIllisible);
        expect(lu.erreurs['date_fin'], MessagesRestaurant.dateIllisible);
      },
    );

    test('255 caractères passent, 256 non', () {
      expect(
        verifierMenu(SaisieMenu(libelle: 'x' * 255, type: 'local')).erreurs,
        isEmpty,
      );
      expect(
        verifierMenu(
          SaisieMenu(libelle: 'x' * 256, type: 'local'),
        ).erreurs['libelle'],
        MessagesRestaurant.libelleTropLong,
      );
    });

    test('le registre des types est celui du serveur : local, europeen, '
        'special', () {
      expect(typesDeMenu, ['local', 'europeen', 'special']);
    });
  });

  group('Vérifier une fiche technique', () {
    test('les lignes ENTIÈREMENT vides sont retirées avant validation', () {
      final lu = verifierFiche(
        const SaisieFiche(
          libelle: 'Poulet DG',
          lignes: [
            LigneSaisieComposition(articleId: '', quantite: ''),
            LigneSaisieComposition(articleId: 'a-1', quantite: '0,3'),
            LigneSaisieComposition(articleId: '  ', quantite: ' '),
          ],
        ),
      );
      expect(lu.erreurs, isEmpty);
      expect(lu.lignes, hasLength(1));
      expect(lu.lignes.single.articleId, 'a-1');
      expect(lu.lignes.single.milliemes, 300);
    });

    test('une composition VIDE est acceptée : c’est le seul moyen de vider une '
        'fiche erronée', () {
      final lu = verifierFiche(const SaisieFiche(libelle: 'Vide', lignes: []));
      expect(lu.erreurs, isEmpty);
      expect(lu.lignes, isEmpty);
    });

    test(
      'le rang d’une erreur est celui de la ligne SAISIE, vides comprises',
      () {
        final lu = verifierFiche(
          const SaisieFiche(
            libelle: 'x',
            lignes: [
              LigneSaisieComposition(articleId: '', quantite: ''),
              LigneSaisieComposition(articleId: 'a-1', quantite: '0'),
            ],
          ),
        );
        expect(
          lu.erreurs['lignes.1.quantite_unitaire'],
          MessagesRestaurant.quantiteRecettePositive,
        );
        expect(lu.erreurs.containsKey('lignes.0.quantite_unitaire'), isFalse);
      },
    );

    test('un article deux fois : la SECONDE ligne est désignée', () {
      final lu = verifierFiche(
        const SaisieFiche(
          libelle: 'x',
          lignes: [
            LigneSaisieComposition(articleId: 'a-1', quantite: '1'),
            LigneSaisieComposition(articleId: 'a-1', quantite: '2'),
          ],
        ),
      );
      expect(
        lu.erreurs['lignes.1.article_id'],
        MessagesRestaurant.ingredientEnDouble,
      );
      expect(lu.erreurs.containsKey('lignes.0.article_id'), isFalse);
    });

    test('une ligne à moitié remplie dit ce qui manque', () {
      final lu = verifierFiche(
        const SaisieFiche(
          libelle: 'x',
          lignes: [
            LigneSaisieComposition(articleId: 'a-1', quantite: ''),
            LigneSaisieComposition(articleId: '', quantite: '2'),
          ],
        ),
      );
      expect(
        lu.erreurs['lignes.0.quantite_unitaire'],
        MessagesRestaurant.quantiteRecetteObligatoire,
      );
      expect(
        lu.erreurs['lignes.1.article_id'],
        MessagesRestaurant.articleObligatoire,
      );
    });

    test('une 4e décimale est REFUSÉE avec sa raison, un mot n’est pas un '
        'nombre', () {
      final lu = verifierFiche(
        const SaisieFiche(
          libelle: 'x',
          lignes: [
            LigneSaisieComposition(articleId: 'a-1', quantite: '0,0001'),
            LigneSaisieComposition(articleId: 'a-2', quantite: 'beaucoup'),
          ],
        ),
      );
      expect(
        lu.erreurs['lignes.0.quantite_unitaire'],
        MessagesRestaurant.quantiteTropFine,
      );
      expect(
        lu.erreurs['lignes.1.quantite_unitaire'],
        MessagesRestaurant.quantiteIllisible,
      );
    });

    test('le libellé est obligatoire', () {
      expect(
        verifierFiche(
          const SaisieFiche(libelle: ' ', lignes: []),
        ).erreurs['libelle'],
        MessagesRestaurant.libelleObligatoire,
      );
    });
  });

  group('Vérifier un plat', () {
    SaisiePlat saisie({
      String libelle = 'Poulet DG',
      String menu = 'm-1',
      String recette = 'r-1',
      String prix = '4500',
    }) => SaisiePlat(
      libelle: libelle,
      menuId: menu,
      recetteId: recette,
      prixVente: prix,
    );

    test('un plat complet est lu en francs entiers', () {
      final lu = verifierPlat(saisie(libelle: '  Poulet DG '));
      expect(lu.erreurs, isEmpty);
      expect(lu.libelle, 'Poulet DG');
      expect(lu.prixFrancs, 4500);
    });

    test('un plat OFFERT existe : zéro est un prix', () {
      expect(verifierPlat(saisie(prix: '0')).erreurs, isEmpty);
    });

    test('menu et fiche sont obligatoires, avec les phrases du serveur', () {
      final lu = verifierPlat(saisie(menu: '', recette: ''));
      expect(lu.erreurs['menu_id'], MessagesRestaurant.menuObligatoire);
      expect(lu.erreurs['recette_id'], MessagesRestaurant.recetteObligatoire);
    });

    test('un prix refusé est désigné par son champ', () {
      expect(
        verifierPlat(saisie(prix: '4500,50')).erreurs['prix_vente'],
        MessagesRestaurant.prixFractionDeFranc,
      );
    });
  });

  group('PA-161 (b) — « corrigé à la main » est un fait déduit', () {
    bool apres({
      bool corrige = false,
      bool provisoire = false,
      int actuel = 1000,
      int soumis = 1000,
    }) => prixCorrigeMainApres(
      corrigeActuel: corrige,
      provisoireActuel: provisoire,
      prixActuelFrancs: actuel,
      prixSoumisFrancs: soumis,
    );

    test('provisoire ET prix changé : la marque se pose', () {
      expect(apres(provisoire: true, actuel: 1000, soumis: 1200), isTrue);
    });

    test('provisoire mais prix inchangé : rien', () {
      expect(apres(provisoire: true), isFalse);
    });

    test('prix changé mais jamais provisoire : rien', () {
      expect(apres(provisoire: false, actuel: 1000, soumis: 1200), isFalse);
    });

    test('la marque ne se lève jamais d’elle-même', () {
      expect(apres(corrige: true), isTrue);
      expect(apres(corrige: true, provisoire: false, soumis: 5), isTrue);
    });
  });

  group('Les portions vendables — le maillon faible commande', () {
    test('33 portions : 10 kg de poulet à 0,3 kg, et le riz ne borne pas', () {
      final r = calculerPortions([
        ing('a-poulet', quantite: 300, stock: 1000),
        ing('a-riz', quantite: 150, stock: 2500),
      ], pointCuisine: true);
      // 1000 c × 10 / 300 = 33,33 -> 33 ; 2500 × 10 / 150 = 166,6 -> 166.
      expect(r.portions, 33);
      expect(r.limitant?.articleId, 'a-poulet');
      expect(r.motif, isNull);
    });

    test('la troncature : 99 centièmes pour 0,1 kg = 9 portions, pas 10', () {
      final r = calculerPortions([
        ing('a-1', quantite: 100, stock: 99),
      ], pointCuisine: true);
      expect(r.portions, 9);
    });

    test('à égalité, le premier ingrédient garde la place', () {
      final r = calculerPortions([
        ing('a-1', quantite: 100, stock: 200),
        ing('a-2', quantite: 200, stock: 400),
      ], pointCuisine: true);
      expect(r.portions, 20);
      expect(r.limitant?.articleId, 'a-1');
    });

    test('un stock NÉGATIF (rupture forcée) donne zéro, jamais un nombre '
        'négatif', () {
      final r = calculerPortions([
        ing('a-1', quantite: 100, stock: -500),
      ], pointCuisine: true);
      expect(r.portions, 0);
    });

    test('sous seuil : PILE sur le seuil compte (<=), un centième au-dessus '
        'non', () {
      expect(
        calculerPortions([
          ing('a-1', quantite: 100, stock: 500, seuil: 500),
        ], pointCuisine: true).sousSeuil,
        isTrue,
      );
      expect(
        calculerPortions([
          ing('a-1', quantite: 100, stock: 501, seuil: 500),
        ], pointCuisine: true).sousSeuil,
        isFalse,
      );
    });

    test('une quantité nulle ne borne aucune portion', () {
      final r = calculerPortions([
        ing('a-0', quantite: 0, stock: 0),
        ing('a-1', quantite: 100, stock: 300),
      ], pointCuisine: true);
      expect(r.portions, 30);
      expect(r.limitant?.articleId, 'a-1');
    });

    test('fiche vide : aucun chiffre, la raison est la fiche', () {
      final r = calculerPortions(const [], pointCuisine: true);
      expect(r.portions, isNull);
      expect(r.motif, MotifSansStock.recetteSansIngredient);
    });

    test('sans point cuisine : aucun chiffre, la raison est le point', () {
      final r = calculerPortions([
        ing('a-1', quantite: 100, stock: 300),
      ], pointCuisine: false);
      expect(r.portions, isNull);
      expect(r.motif, MotifSansStock.pointCuisineAbsent);
    });

    test(
      'la fiche vide l’emporte sur le point absent (l’ordre du serveur)',
      () {
        expect(
          calculerPortions(const [], pointCuisine: false).motif,
          MotifSansStock.recetteSansIngredient,
        );
      },
    );

    test(
      'un article JOURNALIER ne borne rien et ne passe pas « sous seuil »',
      () {
        final r = calculerPortions([
          ing('a-1', quantite: 100, stock: 300),
          ing(
            'a-oignon',
            quantite: 50,
            stock: 0,
            seuil: 0,
            suivi: SuiviArticle.journalier,
          ),
        ], pointCuisine: true);
        expect(r.portions, 30);
        expect(r.sousSeuil, isFalse);
      },
    );

    test('que des journaliers : « non suivi », ni zéro ni rupture', () {
      final r = calculerPortions([
        ing('a-1', quantite: 100, suivi: SuiviArticle.journalier),
      ], pointCuisine: true);
      expect(r.portions, isNull);
      expect(r.motif, MotifSansStock.compositionSansSuivi);
    });
  });

  group('Le coût matière — trois états, jamais « 0 F »', () {
    test('750.00 : 0,3 kg à 2 500 F le kilo', () {
      final c = calculerCoutMatiere([ing('a-1', quantite: 300, cmp: 25000000)]);
      expect(c.centimes, 75000);
      expect(c.montant, '750.00');
      expect(c.incomplet, isFalse);
      expect(c.vide, isFalse);
    });

    test('la troncature se fait LIGNE PAR LIGNE : deux fois 0,99 = 1,98', () {
      // 0,001 × 999,9999 = 0,9999999 -> 0,99 (tronqué) ; deux lignes : 1,98.
      final c = calculerCoutMatiere([
        ing('a-1', quantite: 1, cmp: 9999999),
        ing('a-2', quantite: 1, cmp: 9999999),
      ]);
      expect(c.montant, '1.98');
    });

    test(
      'un coût connu mais inférieur au centime vaut 0.00, pas « inconnu »',
      () {
        final c = calculerCoutMatiere([ing('a-1', quantite: 3, cmp: 12345)]);
        expect(c.montant, '0.00');
        expect(c.incomplet, isFalse);
      },
    );

    test(
      'un ingrédient jamais réceptionné rend le coût INCOMPLET et le nomme',
      () {
        final c = calculerCoutMatiere([
          ing('a-1', quantite: 300, cmp: 25000000, libelle: 'Poulet'),
          ing('a-2', quantite: 100, cmp: 0, libelle: 'Oignon'),
          ing('a-3', quantite: 100, cmp: 0, libelle: 'Oignon'),
        ]);
        expect(c.montant, isNull);
        expect(c.incomplet, isTrue);
        expect(c.articlesSansCout, ['Oignon']);
      },
    );

    test('une fiche vide : ni 0 ni incomplet, VIDE', () {
      final c = calculerCoutMatiere(const []);
      expect(c.montant, isNull);
      expect(c.vide, isTrue);
      expect(c.incomplet, isFalse);
    });

    test('la marge : prix moins coût, inconnue si le coût l’est, négative à '
        'perte', () {
      final connu = calculerCoutMatiere([
        ing('a-1', quantite: 300, cmp: 25000000),
      ]);
      expect(connu.marge(4500), '3750.00');
      expect(connu.marge(100), '-650.00');
      expect(calculerCoutMatiere(const []).marge(4500), isNull);
    });
  });

  group('Le taux de couverture — tronqué au dixième', () {
    test('valeurs exactes', () {
      expect(tauxCouverture(2, 3), '66.6');
      expect(tauxCouverture(3, 3), '100.0');
      expect(tauxCouverture(0, 3), '0.0');
      expect(tauxCouverture(1, 7), '14.2');
      expect(tauxCouverture(1, 1), '100.0');
    });

    test('une carte vide n’a pas de taux : pas « 0 % »', () {
      expect(tauxCouverture(0, 0), isNull);
    });
  });

  group('Le point cuisine est un choix DÉTERMINISTE', () {
    test('le premier par libellé sans accent, puis par identifiant', () {
      expect(
        choisirPointCuisine([
          (id: 'p-3', libelle: 'Cuisine froide', type: 'cuisine'),
          (id: 'p-2', libelle: 'Âtre', type: 'cuisine'),
          (id: 'p-1', libelle: 'Bar', type: 'bar'),
        ]),
        'p-2',
      );
      expect(
        choisirPointCuisine([
          (id: 'p-9', libelle: 'Cuisine', type: 'cuisine'),
          (id: 'p-4', libelle: 'cuisine', type: 'cuisine'),
        ]),
        'p-4',
      );
    });

    test('sans point de ce type : null, et le type « restaurant » n’en est pas '
        'un sur ce poste', () {
      expect(
        choisirPointCuisine([
          (id: 'p-1', libelle: 'Salle', type: 'restaurant'),
          (id: 'p-2', libelle: 'Magasin', type: null),
        ]),
        isNull,
      );
    });
  });

  group('La carte entière', () {
    final poulet = ing('a-poulet', quantite: 300, stock: 1000, cmp: 25000000);
    final plats = [
      plat('p-1', 'Poulet DG', composition: [poulet], prix: 4500),
      plat('p-2', 'Épinards', type: 'special', provisoire: true),
      plat(
        'p-3',
        'abricot',
        type: 'europeen',
        composition: [ing('a-x', quantite: 100, stock: 0)],
      ),
      plat('p-4', 'Zèbre', composition: [poulet], provisoire: true),
    ];

    CarteRestaurant carte({
      String? recherche,
      String? categorie,
      EtatArticleCarte etat = EtatArticleCarte.tous,
      String? point = 'p-cui',
    }) => calculerCarte(
      plats: plats,
      pointCuisineId: point,
      arreteAu: '2026-10-09T08:00:00',
      recherche: recherche,
      categorie: categorie,
      etat: etat,
    );

    test('l’ordre est celui du libellé SANS accent (a, e, p, z)', () {
      expect(
        [for (final l in carte().lignes) l.libelle],
        ['abricot', 'Épinards', 'Poulet DG', 'Zèbre'],
      );
    });

    test('la recherche ignore casse et accents', () {
      expect(
        [for (final l in carte(recherche: 'EPINARD').lignes) l.id],
        ['p-2'],
      );
      expect([for (final l in carte(recherche: 'zebre').lignes) l.id], ['p-4']);
      expect(carte(recherche: 'introuvable').lignes, isEmpty);
    });

    test('les indicateurs portent sur la carte ENTIÈRE, les lignes sur le '
        'filtre', () {
      final c = carte(categorie: 'special');
      expect([for (final l in c.lignes) l.id], ['p-2']);
      expect(c.indicateurs.plats, 4);
      expect(c.indicateurs.lies, 3);
      expect(c.indicateurs.sansLien, 1);
      expect(c.indicateurs.tauxCouverture, '75.0');
    });

    test('les valeurs exactes de la bande', () {
      final k = carte().indicateurs;
      expect(k.plats, 4);
      expect(k.lies, 3);
      expect(k.sansLien, 1);
      // p-3 : stock 0 de a-x -> 0 portion, rupture ; sous seuil (0 <= 0).
      expect(k.enRupture, 1);
      expect(k.sousSeuil, 1);
      // Coût inconnu : p-2 (fiche vide), p-3 (a-x jamais réceptionné).
      expect(k.coutMatiereInconnu, 2);
      expect(k.prixProvisoires, 2);
      expect(k.absents.keys, containsAll(['disponibles', 'indisponibles']));
      expect(k.absents.containsKey('prix_provisoires'), isFalse);
    });

    test('chaque filtre d’état retient ses plats', () {
      List<String> ids(EtatArticleCarte e) => [
        for (final l in carte(etat: e).lignes) l.id,
      ];
      expect(ids(EtatArticleCarte.liesAuStock), ['p-3', 'p-1', 'p-4']);
      expect(ids(EtatArticleCarte.sansLienDeStock), ['p-2']);
      expect(ids(EtatArticleCarte.enRuptureDeStock), ['p-3']);
      expect(ids(EtatArticleCarte.prixProvisoire), ['p-2', 'p-4']);
      expect(ids(EtatArticleCarte.tous), hasLength(4));
    });

    test('la couverture : par type de menu, dans l’ordre des clés', () {
      final cou = carte().couverture;
      expect(
        [for (final c in cou) c.categorieBrute],
        ['europeen', 'local', 'special'],
      );
      expect([for (final c in cou) c.taux], ['100.0', '100.0', '0.0']);
      expect(cou.last.plats, 1);
      expect(cou.last.sansLien, 1);
    });

    test('sans point cuisine : aucune portion, aucune rupture déclarée', () {
      final c = carte(point: null);
      expect(c.sansPointCuisine, isTrue);
      for (final l in c.lignes.where((l) => l.lieAuStock)) {
        expect(l.portionsVendables, isNull, reason: l.libelle);
        expect(l.rupture, isFalse, reason: l.libelle);
        expect(l.motifSansStock, MotifSansStock.pointCuisineAbsent);
      }
      expect(c.indicateurs.enRupture, 0);
    });

    test('les filtres appliqués sont nommés (l’export les cite)', () {
      expect(carte().filtresAppliques, isEmpty);
      expect(
        carte(
          recherche: 'po',
          categorie: 'local',
          etat: EtatArticleCarte.liesAuStock,
        ).filtresAppliques,
        {'recherche': 'po', 'categorie': 'local', 'etat': 'lie'},
      );
    });

    test('une ligne porte ses valeurs exactes : portions, coût, marge', () {
      final l = carte().lignes.firstWhere((l) => l.id == 'p-1');
      expect(l.portionsVendables, 33);
      expect(l.coutMatiere, '750.00');
      expect(l.marge, '3750.00');
      expect(l.prixVente, '4500.00');
      expect(l.ingredientLimitant?.id, 'a-poulet');
      expect(l.nbIngredients, 1);
      expect(l.rupture, isFalse);
    });
  });

  group('La fiche et ses lignes', () {
    test('trois états : vide, composée, composée SANS suivi', () {
      Recette r(List<IngredientCalcule> c) => versRecette(
        FicheCalculee(
          id: 'r',
          libelle: 'Fiche',
          composition: c,
          platsServis: const [],
        ),
      );
      expect(r(const []).etat, EtatFiche.vide);
      expect(r([ing('a', quantite: 100)]).etat, EtatFiche.composee);
      expect(
        r([ing('a', quantite: 100, suivi: SuiviArticle.journalier)]).etat,
        EtatFiche.sansSuivi,
      );
      // Un seul ingrédient suivi suffit : la vente fait bouger un stock.
      expect(
        r([
          ing('a', quantite: 100, suivi: SuiviArticle.journalier),
          ing('b', quantite: 100),
        ]).etat,
        EtatFiche.composee,
      );
    });

    test('les lignes : quantité, unité, coût de l’unité et de la ligne', () {
      final l = versLignes([
        ing('a-1', quantite: 300, cmp: 25000000, libelle: 'Poulet'),
        ing('a-2', quantite: 100, cmp: 0, libelle: 'Oignon'),
      ]);
      expect(l[0].quantiteUnitaire, '0.300');
      expect(l[0].coutUnitaire, '2500.0000');
      expect(l[0].coutLigne, '750.00');
      expect(l[0].uniteMesure, 'kg');
      // Jamais « 0.0000 » : un article jamais reçu n'est pas gratuit.
      expect(l[1].coutUnitaire, isNull);
      expect(l[1].coutLigne, isNull);
      expect(l[1].coutInconnu, isTrue);
    });
  });
}
