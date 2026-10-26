import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/bar/data/boissons_api.dart';
import 'package:tatacora_flutter/features/bar/domain/entities/boisson.dart';
import 'package:tatacora_flutter/features/bar/domain/entities/carte_bar.dart';
import 'package:tatacora_flutter/features/bar/domain/entities/trace_prix.dart';
import 'package:tatacora_flutter/features/bar/domain/motif_indisponibilite.dart';
import 'package:tatacora_flutter/features/pos/data/indisponibilites_carte_dao.dart';
import 'package:tatacora_flutter/features/pos/data/catalogue_dao.dart';
import 'package:tatacora_flutter/features/pos/data/panier_dao.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/article_vendable.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/panier.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/reference_catalogue.dart';

/// Le CRUD **local** du catalogue des boissons — décision du PO du 14/09/2026.
///
/// ## Pourquoi ces cas existent
///
/// La carte du bar DESCENDAIT du serveur (PA-129). Le poste étant passé zéro
/// réseau, elle n'avait plus aucun auteur : sur une installation neuve, le
/// point de vente **n'avait rien à vendre**. Ces cas protègent les quatre
/// choses que le portage local ne doit jamais perdre :
///
///  1. **La saisie atteint réellement Drift.** Une écriture gardée en mémoire
///     disparaîtrait à la fermeture de la fenêtre, et le catalogue serait à
///     refaire chaque matin. Chaque cas relit donc par une instance NEUVE.
///  2. **Ce qui est créé est vendable.** Le catalogue du bar est celui du
///     point de vente : une boisson qui n'atteint pas `rayons()` n'existe pas
///     pour le comptoir.
///  3. **Aucun stock n'est inventé.** Il se calcule des mouvements, et ce
///     poste n'en a aucun. « 0 » se lirait « rupture » sur l'écran qui sert à
///     commander — l'absence doit rester une absence (PA-129, PA-134).
///  4. **Ce que le schéma ne porte pas est REFUSÉ, pas simulé.** L'historique
///     des prix n'a ni colonne ni table ici (retrait de la carte : v31, lien au
///     stock : v30 et `lien_stock_poste_test.dart`). Le tenir en session le
///     ferait revenir seul au redémarrage — la famille PA-59/60/61, sur
///     l'écran du barman.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase base;
  late CatalogueDao catalogue;
  late BoissonsApi source;

  setUp(() {
    base = AppDatabase.enMemoire();
    catalogue = CatalogueDao(base);
    source = BoissonsApi(catalogue);
  });

  tearDown(() => base.close());

  /// Une source NEUVE sur la même base : ce qu'elle relit a réellement été
  /// écrit, et n'est pas resté dans un champ de l'instance précédente.
  BoissonsApi relire() => BoissonsApi(CatalogueDao(base));

  Future<Boisson> creer({
    String libelle = 'Béninoise 33 cl',
    String prix = '500',
    CategorieBoisson categorie = CategorieBoisson.locale,
  }) async {
    final r = await source.enregistrer(
      SaisieBoisson(libelle: libelle, categorie: categorie, prixVente: prix),
    );
    expect(
      r,
      isA<BarRecu<Boisson>>(),
      reason: r is BarRefuse<Boisson> ? r.motif : null,
    );
    return (r as BarRecu<Boisson>).donnees;
  }

  Future<List<Boisson>> catalogueRelu() async {
    final r = await relire().boissons();
    return (r as BarRecu<PageBar<Boisson>>).donnees.elements;
  }

  /// La carte telle que l'écran la compose hors de toute réponse distante —
  /// le chemin exact de `carteLocaleProvider`.
  ///
  /// ⚠ Déclarée ICI, au-dessus de ses appels : Dart ne remonte pas les
  /// fonctions locales, et l'appeler plus haut que sa déclaration est une
  /// erreur de compilation, pas un avertissement.
  Future<List<LigneCarte>> carteLocale() async {
    final dao = CatalogueDao(base);
    final rayons = await dao.rayons();
    final liens = await dao.liensDeStockDesBoissons();
    final retraits = await IndisponibilitesCarteDao(base).boissonsRetirees();

    return composerCarte(
      local: rayons
          .where((r) => r.module == ModuleVendable.m5Bar)
          .expand((r) => r.articles)
          .map(
            (a) => LigneCarte(
              id: a.reference.code,
              libelle: a.libelle,
              categorie: a.categorie ?? '',
              prix: a.prix ?? 0,
              articleId: liens[a.reference.code],
              stock: null,
              indisponibilite: retraits[a.reference.code],
              disponibiliteConnue: true,
            ),
          )
          .toList(growable: false),
      // Aucune réponse distante : c'est l'état permanent de ce poste.
      distantes: null,
    );
  }

  /* ================================================================== */
  group('Créer une boisson SUR LE POSTE', () {
    test('elle est écrite en base, et relue par une instance neuve', () async {
      final creee = await creer(libelle: 'Sodabi', prix: '1000');

      final relues = await catalogueRelu();
      expect(relues, hasLength(1));
      expect(relues.single.id, creee.id);
      expect(relues.single.libelle, 'Sodabi');
      // Des francs ENTIERS : le XOF n'a pas de sous-unité en circulation.
      expect(relues.single.prixVente, '1000');
      expect(relues.single.categorie, CategorieBoisson.locale);
    });

    test('elle est VENDABLE tout de suite au point de vente', () async {
      // Le catalogue du bar est celui du POS : c'est toute la raison d'être du
      // lot. Une boisson créée qui n'atteint pas `rayons()` laisse le comptoir
      // sans rien à vendre — le défaut que PA-129 a nommé trois fois.
      await creer(libelle: 'Tchoukoutou', prix: '300');

      final rayons = await CatalogueDao(base).rayons();
      final bar = rayons.firstWhere((r) => r.module == ModuleVendable.m5Bar);

      expect(bar.articles, hasLength(1));
      expect(bar.articles.single.libelle, 'Tchoukoutou');
      expect(bar.articles.single.prix, 300);
      expect(bar.articles.single.estVendable, isTrue);
    });

    test(
      'l’identifiant naît CÔTÉ CLIENT, et deux créations en font deux',
      () async {
        final a = await creer(libelle: 'Béninoise 33 cl');
        final b = await creer(libelle: 'Béninoise 66 cl');

        expect(a.id, isNotEmpty);
        expect(a.id, isNot(b.id));
        expect(await catalogueRelu(), hasLength(2));
      },
    );

    test(
      'réenregistrer le même identifiant REMPLACE, il ne duplique pas',
      () async {
        final creee = await creer(libelle: 'Sodabi', prix: '1000');

        final r = await source.enregistrer(
          SaisieBoisson(
            id: creee.id,
            libelle: 'Sodabi artisanal',
            categorie: CategorieBoisson.maison,
            prixVente: '1200',
          ),
        );

        expect(r, isA<BarRecu<Boisson>>());
        final relues = await catalogueRelu();
        expect(relues, hasLength(1));
        expect(relues.single.id, creee.id);
        expect(relues.single.libelle, 'Sodabi artisanal');
        expect(relues.single.categorie, CategorieBoisson.maison);
      },
    );

    test('un libellé DÉJÀ à la carte est refusé, sur son champ', () async {
      // Deux articles de même nom mettent deux entrées au point de vente, et
      // le barman ne peut plus savoir laquelle il vend.
      await creer(libelle: 'Béninoise 33 cl');

      final r = await source.enregistrer(
        // La casse et les espaces de bord ne font pas une autre bouteille.
        const SaisieBoisson(
          libelle: '  béninoise 33 CL ',
          categorie: CategorieBoisson.locale,
          prixVente: '500',
        ),
      );

      expect(r, isA<BarRefuse<Boisson>>());
      expect((r as BarRefuse<Boisson>).erreurs, contains('libelle'));
      expect(await catalogueRelu(), hasLength(1));
    });

    test(
      'un libellé vide et un prix illisible sont refusés CHAMP PAR CHAMP',
      () async {
        final r = await source.enregistrer(
          const SaisieBoisson(
            libelle: '   ',
            categorie: CategorieBoisson.locale,
            prixVente: 'gratuit',
          ),
        );

        final refus = r as BarRefuse<Boisson>;
        // Un refus global obligerait à deviner lequel des champs est en cause.
        expect(refus.erreurs.keys, containsAll(['libelle', 'prix_vente']));
        expect(await catalogueRelu(), isEmpty);
      },
    );
  });

  /* ================================================================== */
  group('Modifier le prix', () {
    test(
      'le prix change, l’identifiant et le libellé sont CONSERVÉS',
      () async {
        final creee = await creer(libelle: 'Béninoise 66 cl', prix: '800');

        final r = await source.modifierPrix(creee.id, '1000');

        expect(r, isA<BarRecu<Boisson>>());
        final relues = await catalogueRelu();
        expect(relues.single.id, creee.id);
        expect(relues.single.libelle, 'Béninoise 66 cl');
        expect(relues.single.prixVente, '1000');
      },
    );

    test('une ligne de panier DÉJÀ SAISIE garde son prix (règle 3)', () async {
      // Le catalogue dit ce qu'on vend aujourd'hui ; la ligne dit ce qui a été
      // servi. Réécrire la seconde depuis le premier changerait le montant
      // d'une consommation déjà apportée au client.
      final creee = await creer(libelle: 'Béninoise 66 cl', prix: '800');
      final paniers = PanierDao(base);
      final panier = await paniers.ouvrir(typeVente: TypeVente.comptant);

      await paniers.ajouterLigne(
        panier.id,
        ArticleVendable(
          reference: ReferenceCatalogue(
            module: ModuleVendable.m5Bar,
            code: creee.id,
          ),
          libelle: creee.libelle,
          prix: 800,
        ),
      );

      await source.modifierPrix(creee.id, '1000');

      final relu = await PanierDao(base).parId(panier.id);
      expect(relu!.lignes.single.prixUnitaire, 800);
      expect(relu.lignes.single.libelle, 'Béninoise 66 cl');
      // Et le catalogue, lui, a bien changé : les deux valeurs DIFFÈRENT, ce
      // qui est le fait que ce cas protège.
      expect((await catalogueRelu()).single.prixVente, '1000');
    });

    test(
      'un prix à ZÉRO est refusé — retirer de la carte est un autre geste',
      () async {
        final creee = await creer(prix: '500');

        final r = await source.modifierPrix(creee.id, '0');

        expect(r, isA<BarRefuse<Boisson>>());
        expect((r as BarRefuse<Boisson>).erreurs, contains('prix_vente'));
        expect((await catalogueRelu()).single.prixVente, '500');
      },
    );

    test('une boisson inconnue est refusée SANS lever', () async {
      // Le chemin « introuvable » n'est emprunté par aucun écran au
      // quotidien : c'est exactement celui qu'un transtypage générique fautif
      // ferait planter en production sans qu'aucun test ne le voie.
      final r = await source.modifierPrix('bsn-fantome', '1000');

      expect(r, isA<BarRefuse<Boisson>>());
      expect(await catalogueRelu(), isEmpty);
    });
  });

  /* ================================================================== */
  group('Retrait et remise à la carte — ÉCRITS en base (v31)', () {
    test('« Rendre indispo. » est écrit, relu par une instance neuve, et la '
        'boisson est INTACTE', () async {
      final creee = await creer(libelle: 'Béninoise 33 cl', prix: '500');

      final r = await source.retirer(
        id: creee.id,
        motif: MotifIndisponibilite.rupture.code,
        commentaire: '  livraison attendue jeudi ',
      );
      expect(r, isA<BarRecu<Boisson>>());

      // Une carte composée depuis la base : l'état est SU, donc les gestes
      // sont offerts, et le retrait porte son motif et son commentaire.
      final ligne = (await carteLocale()).single;
      expect(ligne.disponibiliteConnue, isTrue);
      expect(ligne.estRetiree, isTrue);
      expect(ligne.indisponibilite?.motif, 'rupture');
      expect(ligne.indisponibilite?.libelle, 'Rupture du jour');
      expect(ligne.indisponibilite?.commentaire, 'livraison attendue jeudi');

      // Aucun état de retrait n'a été bricolé dans le catalogue.
      final relue = (await catalogueRelu()).single;
      expect(relue.libelle, 'Béninoise 33 cl');
      expect(relue.prixVente, '500');
      expect(relue.categorie, CategorieBoisson.locale);
    });

    test('un motif hors registre et une boisson inconnue sont refusés SANS '
        'écrire', () async {
      final creee = await creer();

      final motif = await source.retirer(id: creee.id, motif: 'hors_saison');
      expect(motif, isA<BarRefuse<Boisson>>());
      expect((motif as BarRefuse<Boisson>).erreurs, contains('motif'));
      expect(
        await source.retirer(id: 'bsn-fantome', motif: 'rupture'),
        isA<BarRefuse<Boisson>>(),
      );
      expect((await carteLocale()).single.estRetiree, isFalse);
    });

    test('retirer deux fois ne double rien, et le refus le DIT', () async {
      final creee = await creer();
      await source.retirer(id: creee.id, motif: 'rupture');

      final encore = await source.retirer(id: creee.id, motif: 'saison');
      expect(encore, isA<BarRefuse<Boisson>>());
      expect((encore as BarRefuse<Boisson>).motif, contains('déjà retirée'));
      expect(
        (await carteLocale()).single.indisponibilite?.motif,
        'rupture',
        reason: 'le retrait en cours est celui du premier geste',
      );
    });

    test('« Remettre » ferme le retrait ; sur une boisson à la carte, il est '
        'refusé en le disant', () async {
      final creee = await creer();

      final rien = await source.remettre(creee.id);
      expect(rien, isA<BarRefuse<Boisson>>());
      expect((rien as BarRefuse<Boisson>).motif, contains('n’est pas retirée'));

      await source.retirer(id: creee.id, motif: 'retire');
      expect(await source.remettre(creee.id), isA<BarRecu<Boisson>>());
      final ligne = (await carteLocale()).single;
      expect(ligne.estRetiree, isFalse);
      expect(ligne.disponibiliteConnue, isTrue);

      // Et la boisson peut être retirée de nouveau : un nouveau retrait.
      expect(
        await source.retirer(id: creee.id, motif: 'rupture'),
        isA<BarRecu<Boisson>>(),
      );
    });
  });

  /* ================================================================== */
  group('Lien au stock (refus d’un article absent) et historique — REFUSÉ '
      'avec sa raison', () {
    // Le lien lui-même s’écrit depuis le 26/10/2026 : voir
    // `lien_stock_poste_test.dart`. Ici, l’article « art-1 » n’existe pas sur
    // ce poste — le refus est celui de l’article, pas d’une colonne absente.
    test('« Lier au stock » sur un article ABSENT du poste est refusé, et la '
        'boisson reste sans lien', () async {
      final creee = await creer();

      final r = await source.lierAuStock(
        id: creee.id,
        articleId: 'art-1',
        unitesVendablesParUniteStock: '24',
      );

      expect(r, isA<BarRefuse<Boisson>>());
      // Un lien écrit à moitié — l'article sans son conditionnement — ferait
      // croire à un rattachement qui ne décrémente rien de juste.
      expect((await catalogueRelu()).single.articleId, isEmpty);
    });

    test(
      'l’historique dit que la TRACE n’existe pas, pas qu’elle est vide',
      () async {
        final creee = await creer(prix: '500');
        await source.modifierPrix(creee.id, '1000');

        final r = await source.historiquePrix(creee.id);

        final refus = r as BarRefuse<List<TracePrix>>;
        // « Aucun changement de prix » serait un FAIT, et il serait faux : le
        // prix vient précisément d'être modifié ci-dessus.
        expect(refus.motif, isNot(contains('Aucun changement')));
        expect(refus.motif, contains('n’existe pas'));
      },
    );
  });

  /* ================================================================== */
  group('Aucun stock n’est inventé', () {
    test('une boisson saisie n’a AUCUN stock — jamais « 0 »', () async {
      await creer();

      final relue = (await catalogueRelu()).single;
      // `null` veut dire « aucun chiffre n'existe ». Un zéro se lirait
      // « rupture » sur l'écran où l'on décide de commander.
      expect(relue.stockDisponible, isNull);
      expect(relue.stockDisponible, isNot('0'));
      // Le stock ne se saisit jamais (PA-24).
      expect(relue.stockLectureSeule, isTrue);
      // Aucune colonne ne porte le conditionnement.
      expect(relue.unitesVendablesParUniteStock, isNull);
    });

    test('la carte dit « non suivi », et n’est PAS en rupture', () async {
      await creer();
      final ligne = (await carteLocale()).single;

      expect(ligne.estLieAuStock, isFalse);
      expect(ligne.stock, isNull);
      // Le point du cas : un stock ABSENT n'est pas une rupture. Si `stock`
      // valait 0, `enRupture` passerait à `true` et la carte annoncerait une
      // rupture générale sur un catalogue qu'on vient de saisir.
      expect(ligne.enRupture, isFalse);
    });

    test('modifier le prix n’introduit aucun chiffre de stock', () async {
      final creee = await creer(prix: '500');
      await source.modifierPrix(creee.id, '1000');

      expect((await catalogueRelu()).single.stockDisponible, isNull);
      expect((await carteLocale()).single.stock, isNull);
    });
  });
}
