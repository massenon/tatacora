import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/features/pos/data/panier_dao.dart';
import 'package:tatacora_flutter/features/pos/data/panier_repository_local.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/article_vendable.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/panier.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/reference_catalogue.dart';
import 'package:tatacora_flutter/features/pos/presentation/providers_pos.dart';
import 'package:tatacora_flutter/features/ventes/domain/entities/vente.dart';
import 'package:tatacora_flutter/features/ventes/domain/journal_ventes.dart';
import 'package:tatacora_flutter/features/ventes/presentation/providers_ventes.dart';

import '../facturation/support/outils_encaissement.dart'
    show ouvrirLaCaisseDuComptoir;
import '../pos/support/outils_ventes.dart';

/// Une vente CLÔTURÉE au comptoir arrive au journal — par le chemin du POS
/// (`PanierDao.cloturer` -> `rafraichirPaniers` -> `journalVentesProvider`),
/// sans aucun geste manuel sur le journal. Correction du 26/10/2026 : « les
/// ventes faites au poste ne s'affichent pas dans l'Historique des ventes ».
///
/// ## Les autres causes possibles, écartées ici une à une
///
/// Le journal est une lecture de `paniers_local` ; seuls quatre ingrédients
/// pouvaient cacher une vente CLÔTURÉE, et chacun a son cas :
///
///  1. un journal gardé en mémoire (le défaut corrigé) ;
///  2. un filtre posé par défaut (dates, statut, poste) — le filtre initial est
///     vierge, et la veille comme 23 h 59 restent listées ;
///  3. une dépendance au point de vente, à la session de caisse ou au statut
///     du règlement — une vente sans poste, d'une session close, annulée ou en
///     note de chambre reste une ligne ;
///  4. le fuseau : un jour se compare en HEURE LOCALE (`_minuit`), pas en UTC.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late PanierDao dao;
  late ProviderContainer c;

  final jour = DateTime(2026, 10, 26, 10);

  const flag = ArticleVendable(
    reference: ReferenceCatalogue(module: ModuleVendable.m5Bar, code: 'b-lie'),
    libelle: 'Flag 33 cl',
    prix: 600,
  );
  const libre = ArticleVendable(
    reference: ReferenceCatalogue(
      module: ModuleVendable.m5Bar,
      code: 'b-libre',
    ),
    libelle: 'Jus maison',
    prix: 300,
  );
  const platSansFiche = ArticleVendable(
    reference: ReferenceCatalogue(
      module: ModuleVendable.m4Restaurant,
      code: 'p-vide',
    ),
    libelle: 'Riz sauce',
    prix: 2500,
  );
  const platCompose = ArticleVendable(
    reference: ReferenceCatalogue(
      module: ModuleVendable.m4Restaurant,
      code: 'p-compose',
    ),
    libelle: 'Poulet braisé',
    prix: 4000,
  );

  setUp(() async {
    db = AppDatabase.enMemoire();
    await avecComptabilite(db, maintenant: jour);
    await ouvrirLaCaisseDuComptoir(db);
    dao = panierDaoSur(db, horloge: jour);

    await db
        .into(db.articlesLocal)
        .insert(
          ArticlesLocalCompanion.insert(
            id: 'art-flag',
            libelle: 'Casier Flag',
            categorie: 'Boissons',
            uniteMesure: 'casier',
            seuilAlerte: 2,
          ),
        );
    await db
        .into(db.cartesBoissonLocal)
        .insert(
          CartesBoissonLocalCompanion.insert(
            id: 'b-lie',
            articleId: 'art-flag',
            libelle: 'Flag 33 cl',
            categorie: 'locale',
            prixVente: 600,
            unitesVendables: const Value('24'),
          ),
        );
    await db
        .into(db.cartesBoissonLocal)
        .insert(
          CartesBoissonLocalCompanion.insert(
            id: 'b-libre',
            articleId: '',
            libelle: 'Jus maison',
            categorie: 'maison',
            prixVente: 300,
          ),
        );
    await db
        .into(db.menusLocal)
        .insert(
          MenusLocalCompanion.insert(
            id: 'm-1',
            libelle: 'Carte',
            type: 'local',
            creeLe: jour,
            creePar: caissierDeVente,
          ),
        );
    for (final (recette, plat, libelle, prix) in [
      ('r-vide', 'p-vide', 'Riz sauce', 2500),
      ('r-compose', 'p-compose', 'Poulet braisé', 4000),
    ]) {
      await db
          .into(db.recettesLocal)
          .insert(
            RecettesLocalCompanion.insert(
              id: recette,
              libelle: 'Fiche $libelle',
              creeLe: jour,
              creePar: caissierDeVente,
            ),
          );
      await db
          .into(db.platsLocal)
          .insert(
            PlatsLocalCompanion.insert(
              id: plat,
              menuId: 'm-1',
              recetteId: recette,
              libelle: libelle,
              prixVente: prix,
              creeLe: jour,
              creePar: caissierDeVente,
            ),
          );
    }
    await db
        .into(db.ingredientsRecetteLocal)
        .insert(
          IngredientsRecetteLocalCompanion.insert(
            recetteId: 'r-compose',
            articleId: 'art-flag',
            quantiteMilliemes: 500,
          ),
        );

    c = ProviderContainer(
      overrides: [
        baseLocaleProvider.overrideWithValue(db),
        depotPanierProvider.overrideWithValue(PanierRepositoryLocal(dao)),
      ],
    );
  });

  tearDown(() async {
    c.dispose();
    await db.close();
  });

  /// Lit le journal comme un écran : le fournisseur est `autoDispose`, il lui
  /// faut un écouteur le temps de la lecture.
  Future<JournalVentes> journal() async {
    final ecoute = c.listen(journalVentesProvider, (_, _) {});
    try {
      return await c.read(journalVentesProvider.future);
    } finally {
      ecoute.close();
    }
  }

  Future<Panier> encaisser(
    List<ArticleVendable> articles, {
    String? pointVente = 'Bar principal',
    String mode = 'especes',
  }) async {
    var p = await dao.ouvrir(
      typeVente: TypeVente.comptant,
      pointVente: pointVente,
    );
    for (final a in articles) {
      p = await dao.ajouterLigne(p.id, a);
    }
    return dao.cloturer(p.id, modePaiement: mode, auteurId: caissierDeVente);
  }

  test(
    'un journal DÉJÀ lu (et gardé vivant par un écran) se recompose '
    'quand le POS rafraîchit les paniers — sans invalider le journal',
    () async {
      // Le journal est lu AVANT la vente et reste écouté : l'historique, le
      // tableau de bord et le « journal du jour » du POS le tiennent vivant.
      final ecoute = c.listen(journalVentesProvider, (_, _) {});
      addTearDown(ecoute.close);
      expect((await c.read(journalVentesProvider.future)).ventes, isEmpty);

      final vente = await encaisser([flag]);
      // Ce que fait `_cloturer` du POS : rafraîchir les paniers, rien d'autre.
      c
        ..invalidate(paniersProvider)
        ..invalidate(kpisPanierProvider);

      final journal = await c.read(journalVentesProvider.future);
      expect([for (final v in journal.ventes) v.id], [vente.id]);
      expect(journal.ventes.single.montant, 600);
      expect(journal.ventes.single.estValidee, isTrue);
    },
  );

  test(
    'un journal NON écouté se relit à la visite suivante (autoDispose)',
    () async {
      expect((await journal()).ventes, isEmpty);
      // Plus aucun écouteur : le fournisseur est libéré avant la vente.
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final vente = await encaisser([libre]);

      expect([for (final v in (await journal()).ventes) v.id], [vente.id]);
    },
  );

  test('boissons et plats, liés ou non au stock : tous au journal, et chacun '
      'dit s’il a sorti du stock', () async {
    await encaisser([flag, platCompose]);
    await encaisser([libre]);
    await encaisser([platSansFiche]);

    final j = await journal();
    expect(j.ventes, hasLength(3));
    // L'ordre des lignes d'un panier suit leur identifiant (aléatoire) : la
    // vente se retrouve par une de ses lignes, jamais par la première.
    Vente avec(String libelle) =>
        j.ventes.firstWhere((v) => v.lignes.any((l) => l.libelle == libelle));
    // La vente qui mêle une boisson liée et un plat composé ne l'est pas.
    expect(avec('Flag 33 cl').aDesLignesSansImpactStock, isFalse);
    expect(avec('Flag 33 cl').lignesSansImpactStock, isEmpty);
    expect(avec('Poulet braisé'), avec('Flag 33 cl'));
    expect(avec('Jus maison').aDesLignesSansImpactStock, isTrue);
    expect(avec('Riz sauce').aDesLignesSansImpactStock, isTrue);
    expect(avec('Riz sauce').lignesSansImpactStock, ['Riz sauce']);
  });

  test('aucun filtre par défaut ne cache une vente : veille, 23 h 59, sans '
      'poste, session close, annulée, note de chambre', () async {
    final aujourdhui = await encaisser([flag]);
    final sansPoste = await encaisser([libre], pointVente: null);
    final annulee = await dao.annulerVente(
      (await encaisser([platSansFiche])).id,
      'Erreur de saisie',
      auteurId: caissierDeVente,
    );

    // La veille à 23 h 59 (heure LOCALE) et une vente d'une session CLOSE.
    final veille = await encaisser([flag]);
    final tard = DateTime(2026, 10, 25, 23, 59, 30);
    await db.customStatement(
      'UPDATE paniers_local SET cloture_le = ? WHERE id = ?',
      [tard.millisecondsSinceEpoch ~/ 1000, veille.id],
    );
    final close = await encaisser([libre]);
    await db.customStatement(
      'UPDATE sessions_caisse_local SET date_cloture = ? WHERE id = ?',
      [jour.millisecondsSinceEpoch ~/ 1000, close.sessionEncaissementId],
    );

    final j = await journal();
    expect(
      {for (final v in j.ventes) v.id},
      {aujourdhui.id, sansPoste.id, annulee.id, veille.id, close.id},
    );
    // Le filtre initial de l'écran est vierge.
    expect(c.read(filtreVentesProvider).estVierge, isTrue);
    // L'écran affiche `ventesAfficheesProvider`, dérivé du journal ÉCOUTÉ.
    final ecoute = c.listen(journalVentesProvider, (_, _) {});
    addTearDown(ecoute.close);
    await c.read(journalVentesProvider.future);
    expect(c.read(ventesAfficheesProvider), hasLength(5));
  });

  test('le jour d’une vente se compare en heure LOCALE : 23 h 59 et 00 h 00 '
      'tombent chacune dans leur jour', () async {
    final minuit = await encaisser([flag]);
    final tard = await encaisser([flag]);
    await db.customStatement(
      'UPDATE paniers_local SET cloture_le = ? WHERE id = ?',
      [
        DateTime(2026, 10, 26, 0, 0, 5).millisecondsSinceEpoch ~/ 1000,
        minuit.id,
      ],
    );
    await db.customStatement(
      'UPDATE paniers_local SET cloture_le = ? WHERE id = ?',
      [
        DateTime(2026, 10, 26, 23, 59, 55).millisecondsSinceEpoch ~/ 1000,
        tard.id,
      ],
    );
    final j = await journal();

    final ceJour = filtrerVentes(
      j.ventes,
      FiltreVentes(debut: DateTime(2026, 10, 26), fin: DateTime(2026, 10, 26)),
    );
    expect({for (final v in ceJour) v.id}, {minuit.id, tard.id});
    final veille = filtrerVentes(
      j.ventes,
      FiltreVentes(debut: DateTime(2026, 10, 25), fin: DateTime(2026, 10, 25)),
    );
    expect(veille, isEmpty);
  });
}
