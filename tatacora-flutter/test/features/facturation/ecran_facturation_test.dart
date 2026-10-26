import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/impression/texte_ticket.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/facturation/data/facture_dao.dart';
import 'package:tatacora_flutter/features/facturation/data/facture_repository_local.dart';
import 'package:tatacora_flutter/features/facturation/domain/entities/piece_facturation.dart';
import 'package:tatacora_flutter/features/facturation/domain/repositories/facture_repository.dart';
import 'package:tatacora_flutter/features/auth/domain/session.dart';
import 'package:tatacora_flutter/features/facturation/impression/facture_a4.dart';
import 'package:tatacora_flutter/features/facturation/impression/ticket_facture.dart';
import 'package:tatacora_flutter/features/facturation/impression/etat_registre_factures.dart';
import 'package:tatacora_flutter/features/facturation/presentation/ecran_facturation.dart';
import 'package:tatacora_flutter/features/facturation/presentation/providers_facturation.dart';
import 'package:tatacora_flutter/features/facturation/presentation/widgets/vue_ticket.dart';
import 'package:tatacora_flutter/shared_widgets/tableau_tatacora.dart'
    show PastilleStatut;
import 'package:tatacora_flutter/features/hebergement/data/reservation_dao.dart';
import 'package:tatacora_flutter/features/hebergement/data/reservation_repository_local.dart';
import 'package:tatacora_flutter/features/hebergement/presentation/providers_hebergement.dart';
import 'package:tatacora_flutter/features/pos/data/panier_dao.dart';
import 'package:tatacora_flutter/features/pos/data/panier_repository_local.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/article_vendable.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/panier.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/reference_catalogue.dart';
import 'package:tatacora_flutter/features/pos/presentation/ecran_pos_comptant.dart';
import 'package:tatacora_flutter/features/pos/presentation/providers_pos.dart';
import '../comptabilite/support/outils_comptabilite.dart'
    show baseInstalleeSur, moteurSur;
import 'support/outils_encaissement.dart'
    show caissierEssai, ouvrirLaCaisseDuComptoir;

/// L'écran Facturation et le parcours qui l'alimente, montés sur une **vraie
/// base locale**.
///
/// ## Le cas qui compte le plus ici
///
/// **Le registre est branché.** Un moteur de facturation dont aucun écran
/// n'appelle l'émission serait exactement PA-63 : une méthode publique
/// appelée uniquement par ses tests. Le parcours « clôturer et facturer »
/// est donc éprouvé de bout en bout, depuis le bouton du point de vente.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late FactureRepository depotFacture;
  late PanierRepositoryLocal depotPanier;

  const annee = 2026;
  DateTime maintenant() => DateTime(annee, 8, 20, 14, 30);

  const biere = ArticleVendable(
    reference: ReferenceCatalogue(module: ModuleVendable.m5Bar, code: 'bsn-33'),
    libelle: 'Béninoise 33cl',
    prix: 1000,
    categorie: 'locale',
  );

  setUp(() async {
    db = AppDatabase.enMemoire();
    await ouvrirLaCaisseDuComptoir(db);
    // La clôture d'une vente passe sa pièce comptable : le référentiel est
    // installé (l'exercice de l'année du test) et le moteur branché.
    await baseInstalleeSur(db, maintenant());
    depotFacture = FactureRepositoryLocal(
      FactureDao(db, maintenant: maintenant),
    );
    depotPanier = PanierRepositoryLocal(
      PanierDao(
        db,
        maintenant: maintenant,
        moteur: () async => moteurSur(db, maintenant: maintenant),
      ),
    );

    await db
        .into(db.cartesBoissonLocal)
        .insert(
          CartesBoissonLocalCompanion.insert(
            id: 'bsn-33',
            articleId: 'art-bsn',
            libelle: 'Béninoise 33cl',
            categorie: 'locale',
            prixVente: 1000,
          ),
        );
  });

  tearDown(() => db.close());

  /// Les tickets « imprimés » pendant le test — l'impression réelle n'existe
  /// pas ici, mais **l'appel** doit être éprouvé : c'est lui qui manquerait si
  /// le bouton n'était branché sur rien.
  late List<TicketCompose> imprimes;

  /// Les factures A4 « éditées » — même raison, sur l'autre papier.
  late List<FactureA4Composee> editees;
  late List<EtatRegistreFactures> registresImprimes;
  late List<EtatRegistreFactures> registresExportes;

  Future<void> monter(
    WidgetTester tester,
    Widget ecran, {
    GardeAcces? droits,
    AuteurEdition? auteur = const AuteurEdition(
      nom: 'Céline AGBODJAN',
      role: 'Comptable',
    ),
  }) async {
    imprimes = [];
    editees = [];
    registresImprimes = [];
    registresExportes = [];
    tester.view
      ..physicalSize = const Size(1600, 1000)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseLocaleProvider.overrideWithValue(db),
          // Celui qui encaisse : la clôture nomme son auteur (RG-15).
          sessionProvider.overrideWithBuild(
            (ref, notifier) => Session(
              utilisateurId: caissierEssai,
              login: 'caissier',
              nom: 'Caissier',
              role: 'gerant',
              droits:
                  droits ??
                  GardeAcces.depuisJson(const {
                    'M2': 'C',
                    'M5': 'C',
                    'M1': 'C',
                  }),
            ),
          ),
          depotFactureProvider.overrideWithValue(depotFacture),
          depotPanierProvider.overrideWithValue(depotPanier),
          depotReservationProvider.overrideWithValue(
            ReservationRepositoryLocal(ReservationDao(db)),
          ),
          imprimerTicketProvider.overrideWithValue((ticket) async {
            imprimes.add(ticket);
          }),
          imprimerFactureA4Provider.overrideWithValue((facture) async {
            editees.add(facture);
          }),
          // Les deux exports du registre sont des ACTIONS injectées : un test
          // de widget n'a pas de fenêtre « Enregistrer sous » (14/10/2026).
          exporterRegistrePdfProvider.overrideWithValue((etat) async {
            registresImprimes.add(etat);
            return 'C:/Documents/registre_factures.pdf';
          }),
          exporterRegistreProvider.overrideWithValue((etat) async {
            registresExportes.add(etat);
            return 'C:/Documents/registre_factures.csv';
          }),
          auteurEditionProvider.overrideWithValue(auteur),
          // Le paquet d'essai ne porte pas forcément l'asset : le logo n'est
          // pas ce qu'on éprouve ici, et son absence ne doit rien bloquer.
          logoEtablissementProvider.overrideWith((ref) async => null),
          droitsProvider.overrideWithValue(
            droits ??
                GardeAcces.depuisJson(const {'M2': 'C', 'M5': 'C', 'M1': 'C'}),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.clair,
          home: Scaffold(body: ecran),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<PieceFacturation> emettreComptant({String? clientNom}) async {
    final p = await depotPanier.ouvrir(
      typeVente: TypeVente.comptant,
      pointVente: 'Bar',
      clientNom: clientNom,
    );
    await depotPanier.ajouterLigne(p.id, biere, quantite: 2);
    final cloture = await depotPanier.cloturer(
      p.id,
      modePaiement: 'especes',
      auteurId: caissierEssai,
    );
    return depotFacture.emettre(
      BrouillonFacture(
        origine: OrigineFacture.posComptant,
        clientNom: clientNom ?? 'Client de passage',
        panierId: cloture.id,
        pointVente: 'Bar',
        modePaiement: 'especes',
        lignes: const [
          LigneBrouillon(
            module: ModuleFacturable.m5Bar,
            libelle: 'Béninoise 33cl',
            prixUnitaire: 1000,
            quantite: 2,
            codeArticle: 'bsn-33',
          ),
        ],
      ),
    );
  }

  /// Une pièce de **séjour**, qui recouvre une chambre ET des consommations.
  ///
  /// C'est la forme ordinaire d'une facture au Gîte, et c'est elle qui
  /// distingue `any` de `every` dans le filtre d'activité.
  Future<PieceFacturation> emettreSejour({String clientNom = 'ADJOVI Paul'}) {
    return depotFacture.emettre(
      BrouillonFacture(
        origine: OrigineFacture.factureDirecte,
        clientNom: clientNom,
        lignes: const [
          LigneBrouillon(
            module: ModuleFacturable.m1Hebergement,
            libelle: 'Chambre 12 — 3 nuits',
            prixUnitaire: 25000,
            quantite: 3,
          ),
          LigneBrouillon(
            module: ModuleFacturable.m5Bar,
            libelle: 'Béninoise 33cl',
            prixUnitaire: 1000,
            quantite: 4,
          ),
        ],
      ),
    );
  }

  /// Le filtre d'origine est une liste déroulante, posée après « Exporter ».
  Future<void> choisirOrigine(WidgetTester tester, String code) async {
    await tester.tap(find.byKey(const Key('facturation-filtre-origine')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('facturation-origine-$code')).last);
    await tester.pumpAndSettle();
  }

  /* ================================================================== */
  group('Écran Facturation', () {
    testWidgets('un registre vide le DIT, et dit d’où viendra la première', (
      tester,
    ) async {
      // Un écran qui ne rend jamais rien passe pour cassé (leçon PA-90).
      await monter(tester, const EcranFacturation());

      expect(
        find.byKey(const Key('facturation-registre-vide')),
        findsOneWidget,
      );
    });

    testWidgets('⚠ PA-61 — le bandeau annonce la démonstration', (
      tester,
    ) async {
      await monter(tester, const EcranFacturation());

      final bandeau = tester.widget<Text>(
        find.byKey(const Key('facturation-bandeau-mecef')),
      );
      expect(bandeau.data, contains('non certifiées, démonstration'));
      expect(bandeau.data, isNot(contains('certifiée MECeF')));
    });

    testWidgets('⚠ PA-61 — aucune pièce n’est annoncée certifiée', (
      tester,
    ) async {
      await emettreComptant();
      await monter(tester, const EcranFacturation());

      // La mention est DÉRIVÉE des pièces : tant qu'aucune ne porte un vrai
      // numéro MECeF, elle dit « démonstration », pas « N pièce(s)
      // certifiée(s) ».
      final mention = tester.widget<Text>(
        find.byKey(const Key('facturation-bandeau-mecef')),
      );
      expect(mention.data, contains('démonstration'));
      expect(mention.data, isNot(contains('pièce(s) certifiée(s)')));
    });

    testWidgets('le filtre d’origine est une COLONNE, pas un entrepôt', (
      tester,
    ) async {
      final f = await emettreComptant();
      await depotFacture.emettre(
        const BrouillonFacture(
          origine: OrigineFacture.factureDirecte,
          clientNom: 'MAIRIE',
          lignes: [
            LigneBrouillon(
              module: ModuleFacturable.m9Tourisme,
              libelle: 'Circuit groupe',
              prixUnitaire: 4500,
              quantite: 4,
            ),
          ],
        ),
      );

      await monter(tester, const EcranFacturation());
      expect(find.byKey(Key('facturation-piece-${f.id}')), findsOneWidget);

      await choisirOrigine(tester, 'facture_directe');
      await tester.pumpAndSettle();

      // La pièce du comptoir disparaît de la VUE, pas du registre.
      expect(find.byKey(Key('facturation-piece-${f.id}')), findsNothing);
      expect(await depotFacture.pieces(), hasLength(2));
    });

    testWidgets('l’annulation par avoir conserve la facture', (tester) async {
      final f = await emettreComptant();
      await monter(tester, const EcranFacturation());

      // Le geste a change de place le 21/08/2026 : le tableau du maitre ne
      // porte aucune colonne d'action, donc la ligne ouvre le ticket et le
      // ticket porte les gestes — comme l'impression et la facture A4.
      await tester.tap(find.byKey(Key('facturation-piece-${f.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('facturation-annuler-avoir')));
      await tester.pumpAndSettle();
      // Le montant n'est PAS pré-rempli (la vue : `avoirMontant = ''`).
      await tester.enterText(
        find.byKey(const Key('facturation-montant-avoir')),
        '2000',
      );
      await tester.enterText(
        find.byKey(const Key('facturation-motif-avoir')),
        'Erreur de saisie',
      );
      await tester.tap(find.byKey(const Key('facturation-confirmer-avoir')));
      await tester.pumpAndSettle();

      final registre = await depotFacture.pieces();
      expect(registre, hasLength(2), reason: 'l’originale ET l’avoir');
      expect((await depotFacture.parId(f.id))!.statut, StatutPiece.annulee);
      expect(registre.firstWhere((p) => p.estAvoir).montantTotal, -2000);
    });

    testWidgets('sans droit d’écriture sur M2, aucune annulation possible', (
      tester,
    ) async {
      final f = await emettreComptant();
      await monter(
        tester,
        const EcranFacturation(),
        droits: GardeAcces.depuisJson(const {'M2': 'L'}),
      );

      // La garde a suivi le bouton. Elle avait ete PERDUE au deplacement, et
      // c'est ce cas qui l'a rattrapee : un compte en lecture seule aurait pu
      // contre-passer une facture. Une violation RBAC est bloquante, sans
      // exception ni dette differee.
      await tester.tap(find.byKey(Key('facturation-piece-${f.id}')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('facturation-annuler-avoir')), findsNothing);

      // Et le ticket, lui, reste consultable : lire n'est pas ecrire.
      expect(find.byKey(const Key('facturation-ticket')), findsOneWidget);
    });

    testWidgets('le ticket s’ouvre et s’imprime', (tester) async {
      final f = await emettreComptant();
      await monter(tester, const EcranFacturation());

      await tester.tap(find.byKey(Key('facturation-piece-${f.id}')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('facturation-ticket')), findsOneWidget);

      await tester.tap(find.byKey(const Key('facturation-imprimer')));
      await tester.pumpAndSettle();

      // L'appel est ce qui compte : un bouton branché sur rien serait PA-63.
      expect(imprimes, hasLength(1));
      expect(imprimes.single.piece.id, f.id);

      // Et le document réellement composé ne perdra aucun caractère.
      for (final texte in imprimes.single.textes) {
        expect(caracteresNonImprimables(texte), isEmpty, reason: texte);
      }
    });

    testWidgets('le ticket affiché contient le filigrane de démonstration', (
      tester,
    ) async {
      final f = await emettreComptant(clientNom: 'KORA — l’addition');
      await monter(tester, const EcranFacturation());

      await tester.tap(find.byKey(Key('facturation-piece-${f.id}')));
      await tester.pumpAndSettle();

      final texte = tester.widget<Text>(
        find.byKey(const Key('facturation-ticket-texte')),
      );
      expect(texte.data, contains('DOCUMENT DE DÉMONSTRATION'));
      // Et l'apostrophe typographique du nom a bien été normalisée.
      expect(texte.data, contains("KORA - l'addition"));
    });
  });

  /* ================================================================== */
  group('Le registre est BRANCHÉ — parcours depuis le point de vente', () {
    testWidgets('CRITÈRE — « Clôturer et facturer » émet réellement la pièce', (
      tester,
    ) async {
      // Sans ce parcours, `Facturer.emettreAuComptant` serait une méthode
      // publique appelée uniquement par ses tests : le défaut PA-63.
      await monter(tester, const EcranPosComptant());

      await tester.tap(find.byKey(const Key('pos-comptant-ouvrir')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pos-article-M5:bsn-33')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pos-cloturer')));
      await tester.pumpAndSettle();

      final registre = await depotFacture.pieces();
      expect(registre, hasLength(1));
      expect(registre.single.numero, 'PROV-$annee-00001');
      expect(registre.single.origine, OrigineFacture.posComptant);
      expect(registre.single.montantTotal, 1000);
      expect(registre.single.panierId, (await depotPanier.paniers()).single.id);

      // « Vente encaissée » s'ouvre dans la foulée (21/10/2026, vue
      // `comptant.ticket_titre`) et offre le ticket 80 mm ET la facture A4 de
      // la pièce émise : c'est ce que le client attend au comptoir. (Le ticket
      // de facture à l'écran n'est plus présenté d'office ; il reste celui du
      // bouton « Émettre la facture » d'un panier clôturé sans pièce.)
      expect(find.byKey(const Key('modale-vente-encaissee')), findsOneWidget);
      expect(
        find.byKey(const Key('vente-encaissee-ticket-80')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('vente-encaissee-facture')), findsOneWidget);
    });

    testWidgets(
      'un panier clôturé SANS facture propose de l’émettre — pas de vente '
      'bloquée',
      (tester) async {
        // L'état existe réellement : l'émission peut échouer après une clôture
        // réussie. Sans ce bouton, la vente resterait dans un état que rien ne
        // rattrape.
        final p = await depotPanier.ouvrir(
          typeVente: TypeVente.comptant,
          pointVente: 'Bar',
        );
        await depotPanier.ajouterLigne(p.id, biere, quantite: 2);
        final cloture = await depotPanier.cloturer(
          p.id,
          modePaiement: 'especes',
          auteurId: caissierEssai,
        );

        await monter(tester, const EcranPosComptant());
        // On replace l'écran sur ce panier clôturé.
        final element = tester.element(find.byType(EcranPosComptant));
        ProviderScope.containerOf(
          element,
        ).read(panierActifProvider.notifier).definir(cloture.id);
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('pos-emettre-facture')), findsOneWidget);

        await tester.tap(find.byKey(const Key('pos-emettre-facture')));
        await tester.pumpAndSettle();

        expect(await depotFacture.pieces(), hasLength(1));
      },
    );
  });

  /* ================================================================== */
  group('L’édition A4 — le second papier, branché sur quelque chose', () {
    testWidgets('le bouton « Facture A4 » ÉDITE réellement la même pièce', (
      tester,
    ) async {
      // Un bouton « Imprimer la facture » qui n'appellerait rien serait
      // PA-63 : un commentaire qui décrit un déclencheur n'est pas un
      // déclencheur. Ce qui est éprouvé ici est l'APPEL, et l'identité de la
      // pièce éditée.
      final f = await emettreComptant(clientNom: 'KORA — l’addition');
      await monter(tester, const EcranFacturation());

      await tester.tap(find.byKey(Key('facturation-piece-${f.id}')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('facturation-facture-a4')));
      await tester.pumpAndSettle();

      expect(editees, hasLength(1));
      expect(editees.single.piece.id, f.id);
      expect(editees.single.piece.numero, f.numero);

      // Le document A4 est bien un AUTRE document, de la MÊME pièce : même
      // numéro, autre papier. Une séquence par papier serait le défaut n°1
      // du registre.
      expect(editees.single.titre, contains(f.numero));
      for (final texte in editees.single.textes) {
        expect(caracteresNonImprimables(texte), isEmpty, reason: texte);
      }
    });

    testWidgets(
      'l’auteur du document est celui de la SESSION, pas une valeur en dur',
      (tester) async {
        final f = await emettreComptant();
        await monter(
          tester,
          const EcranFacturation(),
          auteur: const AuteurEdition(nom: 'Noël NABOGOU', role: 'Gérant'),
        );

        await tester.tap(find.byKey(Key('facturation-piece-${f.id}')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('facturation-facture-a4')));
        await tester.pumpAndSettle();

        expect(editees.single.texteBrut, contains('Noël NABOGOU - Gérant'));
        expect(editees.single.texteBrut, isNot(contains('Administrateur')));
      },
    );

    testWidgets(
      'sans session, le bouton est DÉSACTIVÉ — jamais un auteur de repli',
      (tester) async {
        // La branche que personne n'emprunte est celle qui se trompe (PA-61).
        // Ici elle se trompe dans un sens précis : un document signé par
        // « Administrateur » alors que personne n'est connecté.
        final f = await emettreComptant();
        await monter(tester, const EcranFacturation(), auteur: null);

        await tester.tap(find.byKey(Key('facturation-piece-${f.id}')));
        await tester.pumpAndSettle();

        final bouton = tester.widget<OutlinedButton>(
          find.byKey(const Key('facturation-facture-a4')),
        );
        expect(bouton.onPressed, isNull);

        await tester.tap(
          find.byKey(const Key('facturation-facture-a4')),
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();
        expect(editees, isEmpty);
      },
    );

    testWidgets(
      'les deux papiers cohabitent : le ticket reste éditable lui aussi',
      (tester) async {
        // Livrer l'A4 ne doit pas retirer le rouleau : le comptoir encaisse au
        // ticket et n'édite la facture que sur demande.
        final f = await emettreComptant();
        await monter(tester, const EcranFacturation());

        await tester.tap(find.byKey(Key('facturation-piece-${f.id}')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('facturation-imprimer')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('facturation-facture-a4')));
        await tester.pumpAndSettle();

        expect(imprimes, hasLength(1));
        expect(editees, hasLength(1));
        // Même pièce, même numéro, deux formats.
        expect(imprimes.single.piece.numero, editees.single.piece.numero);
      },
    );
  });

  /* ================================================================== */
  group('L’auteur se DÉRIVE de la session, il n’est pas fourni à la main', () {
    test('une session connectée donne son nom et son rôle', () {
      // Les tests d'écran ci-dessus surchargent `auteurEditionProvider` : sans
      // ce test-ci, la dérivation elle-même ne serait exécutée nulle part —
      // exactement le défaut « déclaré, jamais branché » (PA-63).
      final auteur = auteurDepuisSession(
        const Session(
          utilisateurId: 'u1',
          login: 'celine',
          nom: 'Céline AGBODJAN',
          role: 'Comptable',
          droits: GardeAcces.deconnecte(),
        ),
      );

      expect(auteur, isNotNull);
      expect(auteur!.nom, 'Céline AGBODJAN');
      expect(auteur.role, 'Comptable');
      expect(auteur.libelle, 'Céline AGBODJAN — Comptable');
    });

    test('sans session, il n’y a PAS d’auteur — et pas de repli', () {
      expect(auteurDepuisSession(null), isNull);

      // Et le CÂBLAGE aussi : un conteneur sans session ne doit produire
      // aucun auteur, sans quoi le bouton d'édition resterait actif.
      final conteneur = ProviderContainer();
      addTearDown(conteneur.dispose);
      expect(conteneur.read(auteurEditionProvider), isNull);
    });
  });

  /* ================================================================== */
  group('Les deux exports du registre', () {
    testWidgets('« Export PDF » envoie CE QUI EST AFFICHÉ', (tester) async {
      await emettreComptant(clientNom: 'KORA Jean');
      await emettreComptant(clientNom: 'DOSSOU Marie');
      await monter(tester, const EcranFacturation());

      await tester.tap(find.byKey(const Key('facturation-exporter')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('export-format-pdf')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('export-generer')));
      await tester.pumpAndSettle();

      expect(registresImprimes, hasLength(1));
      expect(registresImprimes.single.pieces, hasLength(2));
      // Le filtre est DIT sur le document : sans cette mention, un extrait se
      // lirait comme un registre complet.
      expect(
        registresImprimes.single.filtre,
        'Aucun filtre — tout le registre',
      );
    });

    testWidgets('le FILTRE s’applique au document, pas seulement à l’écran', (
      tester,
    ) async {
      // La règle que le maître écrit au-dessus de sa fonction d'export :
      // « porte sur CE QUI EST AFFICHÉ, jamais sur la liste complète ».
      // Quelqu'un qui filtre et exporte attend son filtre — lui rendre le
      // registre entier lui ferait envoyer au comptable un document qu'il
      // croit avoir vérifié.
      await emettreComptant(clientNom: 'KORA Jean');
      await monter(tester, const EcranFacturation());

      await choisirOrigine(tester, OrigineFacture.posSejour.code);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('facturation-exporter')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('export-format-pdf')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('export-generer')));
      await tester.pumpAndSettle();

      // Aucune pièce de séjour : le refus s'affiche, et RIEN n'est envoyé.
      expect(registresImprimes, isEmpty);
      expect(find.byKey(const Key('facturation-export-vide')), findsOneWidget);
    });

    testWidgets('une liste vide se REFUSE, avec le message du maître', (
      tester,
    ) async {
      await monter(tester, const EcranFacturation());

      await tester.tap(find.byKey(const Key('facturation-exporter')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('export-format-excel')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('export-generer')));
      await tester.pumpAndSettle();

      expect(registresExportes, isEmpty);
      expect(
        find.text(
          'Rien à exporter : aucune facture ne correspond aux filtres '
          'affichés.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('« Export Excel » écrit un fichier et DIT où il est', (
      tester,
    ) async {
      await emettreComptant(clientNom: 'KORA Jean');
      await monter(tester, const EcranFacturation());

      await tester.tap(find.byKey(const Key('facturation-exporter')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('export-format-excel')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('export-generer')));
      await tester.pumpAndSettle();

      expect(registresExportes, hasLength(1));
      // Un export silencieux est un export que personne ne retrouve : le
      // toast commun dit le NOM du fichier enregistré.
      expect(
        tester
            .widget<Text>(find.byKey(const Key('facturation-export-chemin')))
            .data,
        'Export enregistré : registre_factures.csv',
      );
    });

    testWidgets('le document n’affirme AUCUNE certification', (tester) async {
      // MECeF est factice sur ce dépôt : écrire « certifiées : 1 » sur un
      // document remis au comptable affirmerait une certification qui n'a pas
      // eu lieu (PA-61).
      await emettreComptant(clientNom: 'KORA Jean');
      await monter(tester, const EcranFacturation());

      await tester.tap(find.byKey(const Key('facturation-exporter')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('export-format-pdf')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('export-generer')));
      await tester.pumpAndSettle();

      final etat = registresImprimes.single;
      expect(etat.nombreCertifiees, 0);
      expect(
        etat.indicateurs['Certification MECeF']!.toLowerCase(),
        contains('démonstration'),
      );
    });
  });

  /* ================================================================== */
  group('La recherche et le filtre d’activité', () {
    Future<void> chercher(WidgetTester tester, String terme) async {
      await tester.enterText(
        find.byKey(const Key('facturation-recherche')),
        terme,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('la recherche porte sur le NUMÉRO et sur le CLIENT', (
      tester,
    ) async {
      final kora = await emettreComptant(clientNom: 'KORA Jean');
      await emettreComptant(clientNom: 'DOSSOU Marie');
      await monter(tester, const EcranFacturation());

      expect(find.byKey(Key('facturation-piece-${kora.id}')), findsOneWidget);

      await chercher(tester, 'dossou');
      expect(find.byKey(Key('facturation-piece-${kora.id}')), findsNothing);
      expect(find.text('DOSSOU Marie'), findsOneWidget);

      // Le numéro : c'est lui qu'un client cite au téléphone.
      await chercher(tester, kora.numero);
      expect(find.byKey(Key('facturation-piece-${kora.id}')), findsOneWidget);
      expect(find.text('DOSSOU Marie'), findsNothing);
    });

    testWidgets(
      'une recherche sans résultat laisse le registre VIDE, pas faux',
      (tester) async {
        await emettreComptant(clientNom: 'KORA Jean');
        await monter(tester, const EcranFacturation());

        await chercher(tester, 'introuvable');

        expect(
          find.byKey(const Key('facturation-registre-vide')),
          findsOneWidget,
        );
      },
    );

    Future<void> filtrer(WidgetTester tester, ModuleFacturable m) async {
      await tester.tap(find.byKey(const Key('facturation-filtre-module')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(m.libelle).last);
      await tester.pumpAndSettle();
    }

    testWidgets('le filtre retient une facture qui CONTIENT l’activité', (
      tester,
    ) async {
      // Le point du filtre : une pièce recouvre souvent plusieurs activités.
      // Ne retenir que celles qui n'en portent QU'UNE ferait disparaître les
      // factures les plus fournies — celles qui portent le plus d'argent.
      final sejour = await emettreSejour();
      final bar = await emettreComptant(clientNom: 'KORA Jean');
      await monter(tester, const EcranFacturation());

      // Le séjour ne porte qu'une ligne de bar sur deux : il doit rester.
      await filtrer(tester, ModuleFacturable.m5Bar);
      expect(find.byKey(Key('facturation-piece-${sejour.id}')), findsOneWidget);
      expect(find.byKey(Key('facturation-piece-${bar.id}')), findsOneWidget);

      // Et sur l'hébergement, le comptant du bar sort.
      await filtrer(tester, ModuleFacturable.m1Hebergement);
      expect(find.byKey(Key('facturation-piece-${sejour.id}')), findsOneWidget);
      expect(find.byKey(Key('facturation-piece-${bar.id}')), findsNothing);
    });

    testWidgets('la recherche et l’activité se CUMULENT', (tester) async {
      await emettreSejour(clientNom: 'ADJOVI Paul');
      await emettreSejour(clientNom: 'KORA Jean');
      await monter(tester, const EcranFacturation());

      await filtrer(tester, ModuleFacturable.m1Hebergement);
      await chercher(tester, 'kora');

      expect(find.text('KORA Jean'), findsOneWidget);
      expect(find.text('ADJOVI Paul'), findsNothing);
    });

    testWidgets('une activité absente vide le registre', (tester) async {
      final piece = await emettreSejour();
      await monter(tester, const EcranFacturation());

      final absente = ModuleFacturable.values.firstWhere(
        (m) => piece.lignes.every((l) => l.module != m),
      );
      await filtrer(tester, absente);

      expect(
        find.byKey(const Key('facturation-registre-vide')),
        findsOneWidget,
      );
    });

    testWidgets('l’export SUIT la recherche, comme il suit l’origine', (
      tester,
    ) async {
      // « L'export porte sur ce qui est affiché » (PA-119) : la règle vaut
      // pour les trois filtres, pas seulement pour celui d'origine.
      await emettreComptant(clientNom: 'KORA Jean');
      await emettreComptant(clientNom: 'DOSSOU Marie');
      await monter(tester, const EcranFacturation());

      await chercher(tester, 'kora');
      await tester.tap(find.byKey(const Key('facturation-exporter')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('export-format-pdf')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('export-generer')));
      await tester.pumpAndSettle();

      expect(registresImprimes, hasLength(1));
      expect(registresImprimes.single.pieces, hasLength(1));
      expect(registresImprimes.single.pieces.single.clientNom, 'KORA Jean');
    });
  });

  /* ================================================================== */
  group('La modale « Émettre un avoir » (vue : facturation.blade.php)', () {
    Future<PieceFacturation> ouvrirAvoir(WidgetTester tester) async {
      final f = await emettreComptant();
      await monter(tester, const EcranFacturation());
      await tester.tap(find.byKey(Key('facturation-ligne-avoir-${f.id}')));
      await tester.pumpAndSettle();
      return f;
    }

    Future<void> saisir(
      WidgetTester tester, {
      String? montant,
      String? motif,
    }) async {
      if (montant != null) {
        await tester.enterText(
          find.byKey(const Key('facturation-montant-avoir')),
          montant,
        );
      }
      if (motif != null) {
        await tester.enterText(
          find.byKey(const Key('facturation-motif-avoir')),
          motif,
        );
      }
      await tester.tap(find.byKey(const Key('facturation-confirmer-avoir')));
      await tester.pumpAndSettle();
    }

    testWidgets(
      'le bouton « Avoir » de la LIGNE ouvre la modale, aux mots de la vue',
      (tester) async {
        await ouvrirAvoir(tester);

        expect(find.text('Émettre un avoir'), findsOneWidget);
        expect(
          find.textContaining('La facture d\'origine reste inchangée'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Montant de l\'avoir (FCFA)'),
          findsOneWidget,
        );
        expect(find.textContaining('Motif de l\'avoir'), findsOneWidget);
        expect(find.text('Émettre l\'avoir'), findsOneWidget);
        // L'aide donne le plafond : le TTC de la facture (2 × 1 000).
        expect(
          tester
              .widget<Text>(find.byKey(const Key('facturation-avoir-aide')))
              .data,
          startsWith('Au plus le montant TTC de la facture — '),
        );
        expect(
          tester
              .widget<Text>(find.byKey(const Key('facturation-avoir-aide')))
              .data,
          contains('2'),
        );
      },
    );

    testWidgets('le montant et le motif sont OBLIGATOIRES, la saisie reste', (
      tester,
    ) async {
      final f = await ouvrirAvoir(tester);

      await saisir(tester);

      expect(
        find.byKey(const Key('facturation-avoir-erreur-montant')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('facturation-avoir-erreur-motif')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('facturation-modale-avoir')), findsOneWidget);
      expect(await depotFacture.pieces(), hasLength(1));
      expect((await depotFacture.parId(f.id))!.statut, StatutPiece.emise);
    });

    testWidgets('un montant au-delà du TTC est refusé aux mots du serveur', (
      tester,
    ) async {
      await ouvrirAvoir(tester);

      await saisir(tester, montant: '2001', motif: 'Erreur');

      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('facturation-avoir-erreur-montant')),
            )
            .data,
        'Le montant de l\'avoir ne peut pas dépasser celui de la facture.',
      );
      expect(await depotFacture.pieces(), hasLength(1));
    });

    testWidgets(
      'un avoir PARTIEL est ÉMIS : la facture reste émise, l\'avoir est une '
      'pièce à lui',
      (tester) async {
        // `emettreAvoir($facture, $montant, $motif)` accepte tout montant jusqu'au
        // TTC ; depuis le 21/10/2026 le poste l'écrit (et l'envoie au serveur).
        final f = await ouvrirAvoir(tester);

        await saisir(tester, montant: '500', motif: 'Geste commercial');

        expect(
          find.byKey(const Key('facturation-avoir-erreur-montant')),
          findsNothing,
        );
        expect(find.byKey(const Key('facturation-modale-avoir')), findsNothing);
        final registre = await depotFacture.pieces();
        expect(registre, hasLength(2));
        // La facture d'origine est INCHANGÉE (RG-03) : ni annulée, ni modifiée.
        final origine = (await depotFacture.parId(f.id))!;
        expect(origine.statut, StatutPiece.emise);
        expect(origine.montantTotal, 2000);
        final avoir = registre.singleWhere((p) => p.estAvoir);
        expect(avoir.avoirDe, f.numero);
        expect(avoir.montantTotal, -500);
        expect(find.textContaining('Avoir de 500 FCFA'), findsOneWidget);
        expect(
          find.textContaining('émis sur la facture ${f.numero}'),
          findsOneWidget,
        );
      },
    );

    testWidgets('le TTC entier émet l\'avoir et le DIT', (tester) async {
      final f = await ouvrirAvoir(tester);

      await saisir(tester, montant: '2000', motif: 'Prestation non fournie');

      final registre = await depotFacture.pieces();
      expect(registre, hasLength(2));
      expect((await depotFacture.parId(f.id))!.statut, StatutPiece.annulee);
      expect(find.byKey(const Key('facturation-modale-avoir')), findsNothing);
      expect(find.textContaining('Avoir de '), findsOneWidget);
      expect(
        find.textContaining('émis sur la facture ${f.numero}'),
        findsOneWidget,
      );
    });

    testWidgets(
      'renoncer depuis le TICKET laisse le ticket ouvert et la facture '
      'intacte',
      (tester) async {
        final f = await emettreComptant();
        await monter(tester, const EcranFacturation());
        await tester.tap(find.byKey(Key('facturation-piece-${f.id}')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('facturation-annuler-avoir')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('facturation-modale-avoir')),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const Key('caisse-annuler')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('facturation-modale-avoir')), findsNothing);
        expect(find.byKey(const Key('facturation-ticket')), findsOneWidget);
        expect((await depotFacture.parId(f.id))!.statut, StatutPiece.emise);
        expect(await depotFacture.pieces(), hasLength(1));
      },
    );

    testWidgets(
      'sans droit d\'écriture sur M2, la ligne n\'offre pas « Avoir »',
      (tester) async {
        final f = await emettreComptant();
        await monter(
          tester,
          const EcranFacturation(),
          droits: GardeAcces.depuisJson(const {'M2': 'L'}),
        );

        expect(
          find.byKey(Key('facturation-ligne-avoir-${f.id}')),
          findsNothing,
        );
        // « Facture A4 », elle, est une lecture.
        expect(find.byKey(Key('facturation-ligne-a4-${f.id}')), findsOneWidget);
      },
    );
  });

  /* ================================================================== */
  group('Sélection, « N avoir(s) » et périmètre de l\'export', () {
    Future<void> exporterPdf(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('facturation-exporter')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('export-format-pdf')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('export-generer')));
      await tester.pumpAndSettle();
    }

    testWidgets('l\'export est RESTREINT aux pièces cochées, et le dit', (
      tester,
    ) async {
      final kora = await emettreComptant(clientNom: 'KORA Jean');
      await emettreComptant(clientNom: 'DOSSOU Marie');
      await monter(tester, const EcranFacturation());

      await tester.tap(find.byKey(Key('facturation-coche-${kora.id}')));
      await tester.pumpAndSettle();
      await exporterPdf(tester);

      expect(registresImprimes, hasLength(1));
      expect(registresImprimes.single.pieces.single.id, kora.id);
      expect(registresImprimes.single.filtre, '1 pièce(s) sélectionnée(s)');
    });

    testWidgets('la modale d\'export dit « Périmètre : … » sous son titre', (
      tester,
    ) async {
      await emettreComptant(clientNom: 'KORA Jean');
      await monter(tester, const EcranFacturation());

      await tester.tap(find.byKey(const Key('facturation-exporter')));
      await tester.pumpAndSettle();

      expect(
        find.text('Périmètre : Aucun filtre — tout le registre'),
        findsOneWidget,
      );
    });

    testWidgets('« Tout sélectionner » coche la page, et une 2e fois la vide', (
      tester,
    ) async {
      await emettreComptant(clientNom: 'KORA Jean');
      await emettreComptant(clientNom: 'DOSSOU Marie');
      await monter(tester, const EcranFacturation());

      await tester.tap(find.byKey(const Key('facturation-tout-selectionner')));
      await tester.pumpAndSettle();
      await exporterPdf(tester);
      expect(registresImprimes.single.pieces, hasLength(2));
      expect(registresImprimes.single.filtre, '2 pièce(s) sélectionnée(s)');

      await tester.tap(find.byKey(const Key('facturation-tout-selectionner')));
      await tester.pumpAndSettle();
      await exporterPdf(tester);
      expect(registresImprimes.last.filtre, 'Aucun filtre — tout le registre');
    });

    testWidgets('un filtre qui change VIDE la sélection (PA-119)', (
      tester,
    ) async {
      final kora = await emettreComptant(clientNom: 'KORA Jean');
      await emettreComptant(clientNom: 'DOSSOU Marie');
      await monter(tester, const EcranFacturation());

      await tester.tap(find.byKey(Key('facturation-coche-${kora.id}')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('facturation-recherche')),
        'dossou',
      );
      await tester.pumpAndSettle();

      // La pièce cochée n'est plus affichée : elle ne doit plus compter.
      await exporterPdf(tester);
      expect(registresImprimes.single.pieces.single.clientNom, 'DOSSOU Marie');
      expect(registresImprimes.single.filtre, 'recherche « dossou »');
    });

    testWidgets(
      '« N avoir(s) » se lit à côté du statut de la facture annulée',
      (tester) async {
        final f = await emettreComptant();
        await depotFacture.annuler(f.id, 'Erreur', auteurId: caissierEssai);
        await monter(tester, const EcranFacturation());

        final badge = tester.widget<PastilleStatut>(
          find.byKey(Key('facturation-avoirs-${f.id}')),
        );
        expect(badge.libelle, '1 avoir(s)');
      },
    );

    testWidgets(
      '« Facture A4 » de la LIGNE édite le même papier que le ticket',
      (tester) async {
        final f = await emettreComptant();
        await monter(tester, const EcranFacturation());

        await tester.tap(find.byKey(Key('facturation-ligne-a4-${f.id}')));
        await tester.pumpAndSettle();

        // Le geste atteint l'édition (PA-63 : un bouton branché sur rien), sans
        // ouvrir le ticket — c'est un bouton de la ligne, pas un clic de ligne.
        expect(editees, hasLength(1));
        expect(editees.single.piece.id, f.id);
        expect(find.byKey(const Key('facturation-ticket')), findsNothing);
      },
    );

    testWidgets('sans session, « Facture A4 » le DIT et n\'édite rien', (
      tester,
    ) async {
      final f = await emettreComptant();
      await monter(tester, const EcranFacturation(), auteur: null);

      await tester.tap(find.byKey(Key('facturation-ligne-a4-${f.id}')));
      await tester.pumpAndSettle();

      expect(editees, isEmpty);
      expect(
        find.textContaining('une facture ne s\'édite pas sans auteur'),
        findsOneWidget,
      );
    });

    testWidgets('une facture sans avoir ne porte aucun badge', (tester) async {
      final f = await emettreComptant();
      await monter(tester, const EcranFacturation());

      expect(find.byKey(Key('facturation-avoirs-${f.id}')), findsNothing);
    });
  });
}
