import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'support/outils_ventes.dart';
import '../facturation/support/outils_encaissement.dart'
    show ouvrirLaCaisseDuComptoir;
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/pos/data/panier_repository_local.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/article_vendable.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/panier.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/reference_catalogue.dart';
import 'package:tatacora_flutter/features/pos/domain/repositories/panier_repository.dart';
import 'package:tatacora_flutter/features/pos/domain/unicite_panier_ouvert.dart';
import 'package:tatacora_flutter/features/pos/domain/usecases/gerer_panier.dart';

/// Les RÈGLES du panier, rejouées en Dart — **avec leurs raisons**, pas
/// seulement leurs assertions.
///
/// Elles venaient de la suite `t-panier.js` de l'ancien prototype, archivé
/// depuis PA-183 et qui n'est plus une référence. Ces règles vivent
/// aujourd'hui dans le domaine de ce client (`gerer_panier.dart`) et, côté
/// serveur, dans `app/Domain/Ventes/Services/PanierService.php`. Un portage
/// qui ne reprendrait que le code perdrait la raison de chaque garde, et une
/// garde dont plus personne ne connaît la raison finit par être « simplifiée ».
///
/// ⚠ **Portage d'une PROPOSITION, pas d'une décision.** Le modèle vient de
/// `docs/PROPOSITION_MODELE_PANIER_POS.md`, non ratifié : Q1, Q2 et Q3 restent
/// ouvertes auprès de l'Architecte. Le porter dans un second client le rend
/// plus difficile à amender — c'est pourquoi les trois questions sont isolées
/// derrière des points nommés, éprouvés séparément
/// (`place_hebergement_test.dart`, `panier_dao_test.dart`).
///
/// ## Trois des cinq règles peuvent se tromper en silence
///
///  - deux paniers ouverts sur un même séjour : la facture de départ oublie la
///    moitié des consommations, et l'écart n'apparaît qu'à la réclamation ;
///  - un prix référencé au lieu d'être figé : la carte change pendant le
///    séjour, et l'addition de lundi se réécrit toute seule ;
///  - une clôture anticipée acceptée sans un mot : plus aucune consommation ne
///    peut être enregistrée d'ici au départ, sans que personne l'ait voulu.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase base;
  late PanierRepository depot;
  late GererPanier cas;

  /// Le « maintenant » du domaine, pilotable.
  ///
  /// La règle 5 dépend du jour courant : un test qui lirait l'horloge réelle
  /// passerait 364 jours sur 365 et échouerait le jour du départ — c'est-à-dire
  /// exactement le jour où la règle compte.
  late DateTime maintenant;

  const biere = ArticleVendable(
    reference: ReferenceCatalogue(module: ModuleVendable.m5Bar, code: 'bsn-33'),
    libelle: 'Béninoise 33cl',
    prix: 1000,
    categorie: 'Bières',
  );

  /// Un circuit tient le rôle du plat du prototype : c'est le second module au
  /// même panier, et la règle 4 porte sur la **mixité**, pas sur M4 en
  /// particulier. M4 n'est pas répliqué localement — voir `catalogue_dao.dart`.
  const circuit = ArticleVendable(
    reference: ReferenceCatalogue(
      module: ModuleVendable.m9Tourisme,
      code: 'cir-tanougou',
    ),
    libelle: 'Cascades de Tanougou',
    prix: 4500,
    categorie: 'Nature',
  );

  Future<void> semer() async {
    await base
        .into(base.cartesBoissonLocal)
        .insert(
          CartesBoissonLocalCompanion.insert(
            id: 'bsn-33',
            articleId: 'art-bsn',
            libelle: 'Béninoise 33cl',
            categorie: 'locale',
            prixVente: 1000,
          ),
        );
    await base
        .into(base.circuitsLocal)
        .insert(
          CircuitsLocalCompanion.insert(
            id: 'cir-tanougou',
            nom: 'Cascades de Tanougou',
            theme: 'Nature',
            zone: 'Atacora',
            prix: 4500,
            capaciteMax: 12,
          ),
        );
    await base
        .into(base.categoriesHebergementLocal)
        .insert(
          CategoriesHebergementLocalCompanion.insert(
            id: 'cat-1',
            libelle: 'Bungalow',
            capaciteMax: 2,
            tarifBase: 28000,
          ),
        );
    await base
        .into(base.unitesHebergementLocal)
        .insert(
          UnitesHebergementLocalCompanion.insert(
            id: 'u-1',
            categorieId: 'cat-1',
            numero: 'BNG-01',
            statut: 'libre',
          ),
        );
    await base
        .into(base.clientsLocal)
        .insert(
          ClientsLocalCompanion.insert(
            id: 'cli-1',
            nom: 'KORA',
            telephone: '+229 01 00 00 00 01',
            typeClient: 'particulier',
          ),
        );
    for (final ref in ['r1', 'r2', 'r9', 'rA']) {
      await base
          .into(base.reservationsLocal)
          .insert(
            ReservationsLocalCompanion.insert(
              id: ref,
              reference: 'LOC-$ref',
              clientId: 'cli-1',
              uniteId: 'u-1',
              dateArrivee: DateTime.utc(2026, 8, 18),
              dateDepart: DateTime.utc(2026, 8, 24),
              statut: 'confirmee',
              tarifNuit: 28000,
            ),
          );
    }
  }

  setUp(() async {
    maintenant = DateTime(2026, 8, 20, 11);
    base = AppDatabase.enMemoire();
    // Clôturer passe la pièce de la vente : référentiel comptable (l'exercice
    // 2026) et auteur.
    await avecComptabilite(base, maintenant: maintenant);
    await semer();
    await ouvrirLaCaisseDuComptoir(base);
    depot = PanierRepositoryLocal(
      panierDaoSur(base, lireHorloge: () => maintenant),
    );
    cas = GererPanier(depot);
  });

  /// Clôture au nom du caissier d'essai. Le mode par défaut est « espèces » : le
  /// poste REFUSE désormais de deviner un mode (voir `PanierDao.cloturer`), et
  /// un séjour est de toute façon porté sur la note de chambre.
  Future<Panier> cloturer(
    String id, {
    bool anticipe = false,
    String? modePaiement = 'especes',
  }) => cas.cloturer(
    id,
    anticipe: anticipe,
    modePaiement: modePaiement,
    auteurId: caissierDeVente,
  );

  tearDown(() => base.close());

  /// Le départ, exprimé en jours depuis le « maintenant » du test.
  DateTime jour(int decalage) =>
      DateTime(2026, 8, 20).add(Duration(days: decalage));

  /* ================================================================== */
  group('Ouverture — les deux POS, une seule structure', () {
    test('un panier au comptant s’ouvre et n’a aucun séjour', () async {
      final p = await cas.ouvrirAuComptant(pointVente: 'Bar');

      expect(p.statut, StatutPanier.ouvert);
      expect(p.typeVente, TypeVente.comptant);
      expect(p.reservationId, isNull);
      // `pointVente` dit OÙ EST L'ARGENT, jamais ce qui est vendu.
      expect(p.pointVente, 'Bar');
    });

    test('un panier de séjour SANS réservation est refusé', () async {
      // Un panier de séjour orphelin verrait ses consommations n'atteindre
      // jamais la facture de départ.
      await expectLater(
        depot.ouvrir(typeVente: TypeVente.surSejour),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('un panier au comptant AVEC réservation est refusé', () async {
      await expectLater(
        depot.ouvrir(typeVente: TypeVente.comptant, reservationId: 'r1'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('un type de vente inconnu est refusé à la lecture', () {
      // Le prototype refuse une chaîne libre ; ici l'enum rend la valeur
      // inexprimable à l'écriture. Reste la LECTURE d'une base écrite par une
      // autre version : elle doit lever, jamais retomber sur `comptant`.
      expect(
        () => TypeVente.depuisCode('a_credit'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  /* ================================================================== */
  group('Règle 1 — un seul panier ouvert par séjour (⚠ Q2)', () {
    test('le panier du séjour est retrouvable', () async {
      final p = await cas.ouvrirPourSejour(
        reservationId: 'r1',
        clientNom: 'KORA',
        dateDepartPrevue: jour(3),
      );

      expect((await depot.panierOuvertPour('r1'))!.id, p.id);
    });

    test('un SECOND panier sur le même séjour est refusé', () async {
      await cas.ouvrirPourSejour(
        reservationId: 'r1',
        dateDepartPrevue: jour(3),
      );

      await expectLater(
        cas.ouvrirPourSejour(reservationId: 'r1', dateDepartPrevue: jour(3)),
        throwsA(isA<PanierDejaOuvertException>()),
      );
    });

    test(
      'et le message explique la CONSÉQUENCE, pas seulement la règle',
      () async {
        final premier = await cas.ouvrirPourSejour(
          reservationId: 'r1',
          dateDepartPrevue: jour(3),
        );

        // « un seul panier par séjour » n'apprend rien à un réceptionniste.
        // « la facture de départ en oublierait la moitié » lui dit ce qu'il évite.
        try {
          await cas.ouvrirPourSejour(
            reservationId: 'r1',
            dateDepartPrevue: jour(3),
          );
          fail('un second panier aurait dû être refusé');
        } on PanierDejaOuvertException catch (e) {
          expect(e.toString(), contains('scinderait'));
          expect(e.panierExistantId, premier.id);
        }
      },
    );

    test('un autre séjour ouvre évidemment le sien', () async {
      final r1 = await cas.ouvrirPourSejour(
        reservationId: 'r1',
        dateDepartPrevue: jour(3),
      );
      final r2 = await cas.ouvrirPourSejour(
        reservationId: 'r2',
        dateDepartPrevue: jour(3),
      );

      expect(r2.id, isNot(r1.id));
      expect(r2.statut, StatutPanier.ouvert);
    });

    test(
      'la règle ne bloque que les paniers OUVERTS, pas l’historique',
      () async {
        final p = await cas.ouvrirPourSejour(
          reservationId: 'r1',
          dateDepartPrevue: jour(0),
        );
        await cas.ajouter(p.id, biere);
        await cloturer(p.id);

        expect(await depot.panierOuvertPour('r1'), isNull);
        final second = await cas.ouvrirPourSejour(
          reservationId: 'r1',
          dateDepartPrevue: jour(0),
        );
        expect(second.statut, StatutPanier.ouvert);
      },
    );
  });

  /* ================================================================== */
  group('Règle 4 — bar et tourisme dans le MÊME panier', () {
    late Panier p;

    setUp(() async {
      p = await cas.ouvrirPourSejour(
        reservationId: 'r1',
        dateDepartPrevue: jour(3),
      );
      await cas.ajouter(p.id, biere);
      p = await cas.ajouter(p.id, circuit);
    });

    test('deux modules cohabitent sur une seule addition', () async {
      // Exigence explicite du client au compte rendu d'atelier :
      // « pas de panier différent ».
      expect(p.lignes, hasLength(2));
      expect(p.total, 5500);
    });

    test('la ventilation par module reste lisible', () async {
      expect(p.ventilation[ModuleVendable.m5Bar], 1000);
      expect(p.ventilation[ModuleVendable.m9Tourisme], 4500);
    });

    test('réajouter le même article incrémente au lieu de dupliquer', () async {
      // Deux lignes identiques sur une addition font douter le client, et
      // douter d'une addition suffit à gâcher un départ.
      final apres = await cas.ajouter(p.id, biere);

      expect(apres.lignes, hasLength(2));
      expect(
        apres.lignes.firstWhere((l) => l.reference.code == 'bsn-33').quantite,
        2,
      );
      expect(apres.total, 6500);
    });
  });

  /* ================================================================== */
  group('Règle 3 — prix ET libellé figés à l’ajout', () {
    test('le prix est copié sur la ligne', () async {
      final p = await cas.ouvrirAuComptant();
      final apres = await cas.ajouter(p.id, biere);

      expect(apres.lignes.single.prixUnitaire, 1000);
      expect(apres.lignes.single.libelle, 'Béninoise 33cl');
    });

    test(
      'un changement de carte ne réécrit PAS une consommation servie',
      () async {
        // Le point qui compte : un panier de séjour vit plusieurs jours. Si la
        // carte du bar change entre lundi et le départ, la bière de lundi doit
        // rester au prix de lundi.
        final p = await cas.ouvrirPourSejour(
          reservationId: 'r1',
          dateDepartPrevue: jour(3),
        );
        await cas.ajouter(p.id, biere);
        await cas.ajouter(p.id, circuit);

        // La carte augmente : le MÊME article part à 1 200 F.
        const biereApresHausse = ArticleVendable(
          reference: ReferenceCatalogue(
            module: ModuleVendable.m5Bar,
            code: 'bsn-33',
          ),
          libelle: 'Béninoise 33cl',
          prix: 1200,
        );
        await cas.ajouter(p.id, biereApresHausse);
        await cas.ajouter(p.id, biere);

        final apres = (await depot.parId(p.id))!;
        final bieres = apres.lignes.where((l) => l.reference.code == 'bsn-33');

        expect(
          bieres,
          hasLength(2),
          reason: 'un nouveau prix crée une ligne DISTINCTE',
        );
        expect(
          bieres.map((l) => l.prixUnitaire),
          containsAll(const [1000, 1200]),
          reason: 'l’ancien prix est conservé tel quel',
        );
        // 2 × 1 000 + 1 × 1 200 + 4 500
        expect(apres.total, 7700);
      },
    );

    test('la lecture ne joint JAMAIS le catalogue', () async {
      final p = await cas.ouvrirAuComptant();
      await cas.ajouter(p.id, biere);

      // La carte est modifiée EN BASE après l'ajout. Une jointure à la lecture
      // ferait remonter 1 800 F ; la ligne figée en garde 1 000.
      await (base.update(base.cartesBoissonLocal)
            ..where((c) => c.id.equals('bsn-33')))
          .write(const CartesBoissonLocalCompanion(prixVente: Value(1800)));

      final relu = (await depot.parId(p.id))!;
      expect(relu.lignes.single.prixUnitaire, 1000);
      expect(relu.total, 1000);
    });
  });

  /* ================================================================== */
  group('Prix inconnu et quantité — refus, jamais un zéro silencieux', () {
    test('un article sans tarif est refusé', () async {
      final p = await cas.ouvrirAuComptant();
      const sansTarif = ArticleVendable(
        reference: ReferenceCatalogue(
          module: ModuleVendable.m5Bar,
          code: 'bsn-33',
        ),
        libelle: 'Sans tarif',
        prix: null,
      );

      // Un montant deviné est une perte à chaque service.
      await expectLater(
        cas.ajouter(p.id, sansTarif),
        throwsA(isA<PrixInconnu>()),
      );
    });

    test('une quantité explicitement nulle est refusée', () async {
      final p = await cas.ouvrirAuComptant();

      // `Number(quantite) || 1` la facturait à UNE unité (PA-78).
      await expectLater(
        cas.ajouter(p.id, biere, quantite: 0),
        throwsA(isA<ArgumentError>()),
      );
      expect((await depot.parId(p.id))!.lignes, isEmpty);
    });

    test(
      'une quantité ABSENTE vaut 1 — et ce n’est pas la même chose',
      () async {
        final p = await cas.ouvrirAuComptant();
        final apres = await cas.ajouter(p.id, biere);

        expect(apres.lignes.single.quantite, 1);
      },
    );
  });

  /* ================================================================== */
  group('Règle 5 — clôture anticipée possible, jamais silencieuse', () {
    test('clôturer avant le départ est refusé par défaut', () async {
      final p = await cas.ouvrirPourSejour(
        reservationId: 'r1',
        dateDepartPrevue: jour(3),
      );
      await cas.ajouter(p.id, biere);

      await expectLater(
        cloturer(p.id),
        throwsA(isA<ClotureAnticipeeNonConfirmee>()),
      );
      expect((await depot.parId(p.id))!.statut, StatutPanier.ouvert);
    });

    test(
      'le refus dit POURQUOI : aucun second panier ne pourra être ouvert',
      () async {
        final p = await cas.ouvrirPourSejour(
          reservationId: 'r1',
          dateDepartPrevue: jour(3),
        );
        await cas.ajouter(p.id, biere);

        try {
          await cloturer(p.id);
          fail('la clôture anticipée aurait dû être refusée');
        } on ClotureAnticipeeNonConfirmee catch (e) {
          expect(e.toString(), contains('second panier'));
          expect(e.dateLisible, '23/08/2026');
        }
      },
    );

    test('sur confirmation explicite, la clôture reste possible', () async {
      final p = await cas.ouvrirPourSejour(
        reservationId: 'r1',
        dateDepartPrevue: jour(3),
      );
      await cas.ajouter(p.id, biere);

      final cloture = await cloturer(
        p.id,
        anticipe: true,
        modePaiement: 'especes',
      );

      expect(cloture.statut, StatutPanier.cloture);
      // Un séjour est TOUJOURS porté sur la note de chambre (`PosHeberges`) :
      // le mode demandé n'y change rien — l'enregistrer en espèces ferait entrer
      // en caisse un argent que personne n'a remis.
      expect(cloture.modePaiement, 'note_chambre');
      // Le montant est FIGÉ à la clôture : il ne se recalcule plus.
      expect(cloture.montantCloture, 1000);
    });

    test('le jour du départ, aucune confirmation n’est demandée', () async {
      // Demander confirmation le jour même ferait du garde-fou une formalité
      // qu'on apprend à valider sans lire.
      final p = await cas.ouvrirPourSejour(
        reservationId: 'r9',
        dateDepartPrevue: jour(0),
      );
      await cas.ajouter(p.id, biere);

      expect((await cloturer(p.id)).statut, StatutPanier.cloture);
    });

    test('un panier au comptant ne connaît pas la clôture anticipée', () async {
      final p = await cas.ouvrirAuComptant();
      await cas.ajouter(p.id, biere);

      expect((await cloturer(p.id)).statut, StatutPanier.cloture);
    });

    test('un panier vide ne se clôture pas', () async {
      final p = await cas.ouvrirAuComptant();

      await expectLater(cloturer(p.id), throwsA(isA<PanierVide>()));
    });
  });

  /* ================================================================== */
  group('Règle 2 — un panier clôturé est immuable', () {
    late Panier cloture;

    setUp(() async {
      final p = await cas.ouvrirAuComptant();
      await cas.ajouter(p.id, biere);
      cloture = await cloturer(p.id);
    });

    test('aucune ligne ne s’ajoute après clôture', () async {
      // Sinon le panier devient le chemin par lequel on modifie une facture
      // déjà remise.
      await expectLater(
        cas.ajouter(cloture.id, circuit),
        throwsA(isA<PanierNonModifiable>()),
      );
    });

    test('aucune ligne ne se retire après clôture', () async {
      await expectLater(
        cas.retirer(cloture.id, cloture.lignes.single.id),
        throwsA(isA<PanierNonModifiable>()),
      );
    });

    test('aucune quantité ne se modifie après clôture', () async {
      await expectLater(
        cas.changerQuantite(cloture.id, cloture.lignes.single.id, 5),
        throwsA(isA<PanierNonModifiable>()),
      );
    });

    test('un panier déjà clôturé ne se reclôture pas', () async {
      await expectLater(
        cloturer(cloture.id),
        throwsA(isA<PanierNonModifiable>()),
      );
    });

    test('un panier clôturé ne s’annule pas', () async {
      // La correction passe par un avoir sur la facture émise, jamais par le
      // panier.
      await expectLater(
        cas.annuler(cloture.id, 'erreur'),
        throwsA(isA<PanierNonModifiable>()),
      );
    });
  });

  /* ================================================================== */
  group('Lignes — retrait, quantité, gestes du comptoir', () {
    test('retirer une ligne d’un AUTRE panier échoue', () async {
      final a = await cas.ouvrirAuComptant();
      final b = await cas.ouvrirAuComptant();
      final avecLigne = await cas.ajouter(a.id, biere);

      // Sans ce contrôle, `delete().go()` rendrait 0 sans lever, et le retrait
      // passerait pour un succès sur un panier qui n'a rien perdu.
      await expectLater(
        cas.retirer(b.id, avecLigne.lignes.single.id),
        throwsA(isA<LigneIntrouvable>()),
      );
      expect((await depot.parId(a.id))!.lignes, hasLength(1));
    });

    test('« moins » sur une ligne à une unité retire la ligne', () async {
      final p = await cas.ouvrirAuComptant();
      final avec = await cas.ajouter(p.id, biere);

      final apres = await cas.diminuer(p.id, avec.lignes.single);
      // Une ligne à zéro sur l'addition serait un article annoncé au client et
      // facturé à rien.
      expect(apres.lignes, isEmpty);
    });

    test('« moins » sur une ligne à deux unités décrémente', () async {
      final p = await cas.ouvrirAuComptant();
      await cas.ajouter(p.id, biere);
      final avec = await cas.ajouter(p.id, biere);

      final apres = await cas.diminuer(p.id, avec.lignes.single);
      expect(apres.lignes.single.quantite, 1);
      expect(apres.total, 1000);
    });

    test('une quantité modifiée à zéro est refusée', () async {
      final p = await cas.ouvrirAuComptant();
      final avec = await cas.ajouter(p.id, biere);

      await expectLater(
        cas.changerQuantite(p.id, avec.lignes.single.id, 0),
        throwsA(isA<ArgumentError>()),
      );
      expect((await depot.parId(p.id))!.lignes.single.quantite, 1);
    });
  });

  /* ================================================================== */
  group('Annulation — le motif est exigé, les lignes restent', () {
    test('un motif vide est refusé', () async {
      final p = await cas.ouvrirAuComptant();
      await cas.ajouter(p.id, biere);

      // Un panier annulé sans raison est indistinguable d'une erreur de
      // manipulation.
      await expectLater(
        cas.annuler(p.id, '   '),
        throwsA(isA<ArgumentError>()),
      );
      expect((await depot.parId(p.id))!.statut, StatutPanier.ouvert);
    });

    test('les lignes sont CONSERVÉES', () async {
      final p = await cas.ouvrirAuComptant();
      await cas.ajouter(p.id, biere);

      final annule = await cas.annuler(p.id, 'Client parti sans consommer');

      expect(annule.statut, StatutPanier.annule);
      // La question « qu'a-t-il consommé ? » doit rester répondable après coup.
      expect(annule.lignes, hasLength(1));
      expect(annule.motifAnnulation, 'Client parti sans consommer');
    });

    test('un panier annulé libère le séjour', () async {
      final p = await cas.ouvrirPourSejour(
        reservationId: 'r1',
        dateDepartPrevue: jour(3),
      );
      await cas.annuler(p.id, 'Erreur de saisie');

      expect(await depot.panierOuvertPour('r1'), isNull);
    });
  });

  /* ================================================================== */
  group('KPI — dérivés de la base, jamais d’un compteur tenu à part', () {
    test('les paniers de séjour sont isolés du comptant', () async {
      final a = await cas.ouvrirPourSejour(
        reservationId: 'rA',
        dateDepartPrevue: jour(0),
      );
      await cas.ajouter(a.id, circuit);
      final b = await cas.ouvrirAuComptant();
      await cas.ajouter(b.id, biere);

      final k = await KpisPanier.calculer(depot);

      expect(k.ouverts, 2);
      expect(k.paniersSejour, 1);
      // L'un est dans le tiroir, l'autre est une créance réglée au départ.
      expect(k.encoursSejours, 4500);
      expect(k.encours, 5500);
      expect(k.clotures, 0);
    });

    test(
      'une clôture bascule les compteurs, sans les recompter à la main',
      () async {
        final p = await cas.ouvrirAuComptant();
        await cas.ajouter(p.id, biere);
        await cloturer(p.id);

        final k = await KpisPanier.calculer(depot);
        expect(k.ouverts, 0);
        expect(k.encours, 0);
        expect(k.clotures, 1);
      },
    );
  });
}
