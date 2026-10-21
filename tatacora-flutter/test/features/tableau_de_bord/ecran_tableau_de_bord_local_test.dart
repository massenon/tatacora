import 'dart:async';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/format/formats.dart';
import 'package:tatacora_flutter/core/impression/texte_ticket.dart';
import 'package:tatacora_flutter/core/navigation/trace_svg.dart';
import 'package:tatacora_flutter/core/theme/app_colors.dart';
import 'package:tatacora_flutter/core/theme/app_spacing.dart';
import 'package:tatacora_flutter/features/depenses/domain/categories_depense.dart';
import 'package:tatacora_flutter/features/depenses/domain/entities/depense.dart';
import 'package:tatacora_flutter/features/facturation/data/facture_dao.dart';
import 'package:tatacora_flutter/features/facturation/domain/entities/piece_facturation.dart';
import 'package:tatacora_flutter/features/facturation/domain/repositories/facture_repository.dart';
import 'package:tatacora_flutter/features/hebergement/data/reservation_dao.dart';
import 'package:tatacora_flutter/features/hebergement/data/reservation_repository_local.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/periode_sejour.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/reservation.dart';
import 'package:tatacora_flutter/features/pos/data/panier_dao.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/article_vendable.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/panier.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/reference_catalogue.dart';
import 'package:tatacora_flutter/features/rh/data/employe_dao.dart';
import 'package:tatacora_flutter/features/rh/data/paie_dao.dart';
import 'package:tatacora_flutter/features/rh/domain/entities/employe.dart';
import 'package:tatacora_flutter/features/rh/domain/services/bulletin_paie_service.dart';
import 'package:tatacora_flutter/features/stocks/data/stocks_dao.dart';
import 'package:tatacora_flutter/features/stocks/data/stocks_api.dart'
    show StockRecu;
import 'package:tatacora_flutter/features/stocks/domain/entities/etat_stock.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/mouvement_stock.dart';
import 'package:tatacora_flutter/features/tableau_de_bord/data/tableau_de_bord_local.dart';
import 'package:tatacora_flutter/features/tableau_de_bord/domain/entities/pilotage.dart';
import 'package:tatacora_flutter/features/tableau_de_bord/domain/entities/tableau_de_bord.dart';
import 'package:tatacora_flutter/features/tableau_de_bord/domain/rapports_accueil.dart'
    show TypeRapportAccueil;
import 'package:tatacora_flutter/features/tableau_de_bord/impression/etat_pilotage.dart';
import 'package:tatacora_flutter/features/tableau_de_bord/impression/etat_rapport_accueil.dart'
    show EtatRapportAccueil;
import 'package:tatacora_flutter/features/tableau_de_bord/presentation/widgets/modale_rapport_accueil.dart'
    show exporterRapportAccueilProvider;
import 'package:tatacora_flutter/features/tableau_de_bord/presentation/ecran_pilotage_consolide.dart';
import 'package:tatacora_flutter/features/tableau_de_bord/presentation/ecran_tableau_de_bord.dart';
import 'package:tatacora_flutter/features/tableau_de_bord/presentation/onglets_tableau_de_bord.dart';
import 'package:tatacora_flutter/shared_widgets/modale_export.dart'
    show FormatExport;

import '../../support/coquille_montee.dart';
import '../../support/vue_blade.dart';
import '../comptabilite/support/outils_comptabilite.dart'
    show baseInstalleeSur, moteurSur;
import '../depenses/support/outils_depenses.dart';
import '../facturation/support/outils_encaissement.dart'
    show
        caissierEssai,
        creerClient,
        emettreFacture,
        ouvrirLaCaisseDuComptoir,
        paiementsDaoSur;

/// M11 sur la CHAÎNE RÉELLE : écran -> fournisseurs -> `TableauDeBordLocal` ->
/// DAO -> base. Aucun fournisseur de données n'est surchargé (piège 5) : seule
/// l'horloge est injectée, parce que la période par défaut — « Ce mois », celle
/// de la vue — dépend du jour (au 10/10/2026 : du 1er au 31 octobre).
///
/// Le jeu : un parc de 3 unités dont 1 hors service, des réservations de tous
/// statuts, des salariés de tous statuts, un stock partiellement valorisé, des
/// pièces dont un avoir, des dépenses dans et hors de la fenêtre, un bulletin.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  final aujourdhui = DateTime(2026, 10, 10, 14, 30);

  setUp(() async {
    db = AppDatabase.enMemoire();
    await ouvrirLaCaisseDuComptoir(db);

    await db
        .into(db.utilisateursLocal)
        .insert(
          UtilisateursLocalCompanion.insert(
            id: 'u-essai',
            login: 'essai',
            nom: 'Essai',
            role: 'administrateur',
            droitsJson: '{}',
            sel: 's',
            empreinte: 'e',
            iterations: 1,
            dateCreation: DateTime(2026, 10, 1),
            dateMotDePasse: DateTime(2026, 10, 1),
          ),
        );

    // --- Parc : 2 unités louables + 1 hors service ---------------------
    await db
        .into(db.categoriesHebergementLocal)
        .insert(
          CategoriesHebergementLocalCompanion.insert(
            id: 'cat-1',
            libelle: 'Bungalow',
            capaciteMax: 2,
            tarifBase: 28000,
          ),
        );
    for (final (id, numero, statut) in const [
      ('u-1', 'BNG-01', 'libre'),
      ('u-2', 'BNG-02', 'libre'),
      ('u-3', 'BNG-03', 'hors_service'),
    ]) {
      await db
          .into(db.unitesHebergementLocal)
          .insert(
            UnitesHebergementLocalCompanion.insert(
              id: id,
              categorieId: 'cat-1',
              numero: numero,
              statut: statut,
            ),
          );
    }
    await db
        .into(db.clientsLocal)
        .insert(
          ClientsLocalCompanion.insert(
            id: 'cli-1',
            nom: 'KORA',
            prenom: const Value('Jean'),
            telephone: '+229 01 00 00 00 01',
            typeClient: 'particulier',
          ),
        );

    final depot = ReservationRepositoryLocal(ReservationDao(db));
    Future<void> reserver(
      String id,
      String unite,
      StatutReservation statut,
      DateTime arrivee,
      DateTime depart,
      DateTime creeeLe,
    ) => depot.enregistrer(
      Reservation(
        id: id,
        reference: 'LOC-$id',
        clientId: 'cli-1',
        clientNom: 'KORA Jean',
        uniteId: unite,
        periode: PeriodeSejour(arrivee: arrivee, depart: depart),
        tarifNuit: 28000,
        statut: statut,
        statutSynchronisation: StatutSynchronisation.local,
        creeeLe: creeeLe,
      ),
    );
    // Dans « Ce mois » (01/10 -> 01/11) : 4 nuits + 4 nuits = 8 ; la
    // réservation en attente et l'annulée ne comptent pas comme nuitées
    // vendues.
    await reserver(
      'r1',
      'u-1',
      StatutReservation.confirmee,
      DateTime(2026, 10, 1),
      DateTime(2026, 10, 5),
      DateTime(2026, 9, 25),
    );
    await reserver(
      'r2',
      'u-1',
      StatutReservation.enAttente,
      DateTime(2026, 10, 10),
      DateTime(2026, 10, 13),
      DateTime(2026, 10, 8),
    );
    await reserver(
      'r3',
      'u-1',
      StatutReservation.annulee,
      DateTime(2026, 10, 6),
      DateTime(2026, 10, 8),
      DateTime(2026, 10, 1),
    );
    await reserver(
      'r4',
      'u-2',
      StatutReservation.confirmee,
      DateTime(2026, 10, 8),
      DateTime(2026, 10, 12),
      DateTime(2026, 10, 2),
    );

    // --- Personnel : 2 actifs, 1 en congé, 1 parti ---------------------
    final employes = EmployeDao(db, maintenant: () => aujourdhui);
    await employes.installerServices();
    await PaieDao(
      db,
      maintenant: () => aujourdhui,
    ).installerReferentielConfirme();
    final service = (await employes.services()).first;
    Future<Employe> embaucher(String nom, StatutEmploye statut) =>
        employes.creer(
          nom: nom,
          prenom: 'X',
          poste: 'Poste',
          serviceId: service.id,
          dateEmbauche: DateTime(2024, 1, 1),
          salaireBase: 150000,
          numeroCnss: 'BJ-$nom',
          typeContrat: TypeContrat.cdi,
          statut: statut,
        );
    final kora = await embaucher('KORA', StatutEmploye.actif);
    await embaucher('DOSSOU', StatutEmploye.actif);
    await embaucher('AGBO', StatutEmploye.conge);
    await embaucher('ZINSOU', StatutEmploye.parti);
    await BulletinPaieService(
      PaieDao(db, maintenant: () => aujourdhui),
      employes,
    ).etablirBulletin(kora, '2026-10');

    // --- Stock : un article valorisé, un SANS coût ---------------------
    final stocks = StocksDao(db);
    final point = await stocks.creerPoint(libelle: 'Magasin');
    await stocks.creerArticle(
      id: 'riz',
      libelle: 'Riz',
      categorie: null,
      uniteMesure: 'sac',
      seuilCentiemes: 500,
      suivi: SuiviArticle.permanent,
      pointStockageId: point.id,
      auteurId: 'u-essai',
      ouverture: (centiemes: 1000, coutDixMilliemes: 12505000),
    );
    await stocks.creerArticle(
      id: 'sel',
      libelle: 'Sel',
      categorie: null,
      uniteMesure: 'sac',
      seuilCentiemes: 100,
      suivi: SuiviArticle.permanent,
      pointStockageId: point.id,
      auteurId: 'u-essai',
      ouverture: (centiemes: 400, coutDixMilliemes: null),
    );

    // --- Registre : 50 000 F d'hébergement (dont 20 000 annulés par avoir)
    // et 4 500 F de bar ----------------------------------------------------
    final factures = FactureDao(db, maintenant: () => DateTime(2026, 10, 5, 9));
    await factures.emettre(
      const BrouillonFacture(
        origine: OrigineFacture.factureDirecte,
        lignes: [
          LigneBrouillon(
            module: ModuleFacturable.m1Hebergement,
            libelle: 'Nuitée',
            prixUnitaire: 25000,
            quantite: 2,
          ),
          LigneBrouillon(
            module: ModuleFacturable.m5Bar,
            libelle: 'Boisson',
            prixUnitaire: 1500,
            quantite: 3,
          ),
        ],
      ),
    );
    final aAnnuler = await factures.emettre(
      const BrouillonFacture(
        origine: OrigineFacture.factureDirecte,
        lignes: [
          LigneBrouillon(
            module: ModuleFacturable.m1Hebergement,
            libelle: 'Nuitée annulée',
            prixUnitaire: 20000,
            quantite: 1,
          ),
        ],
      ),
    );
    await factures.annuler(aAnnuler.id, 'Erreur de saisie');

    // --- Ventes du bar : 3 bières en deux tickets le 05/10, 5 en août -----
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
    const biere = ArticleVendable(
      reference: ReferenceCatalogue(
        module: ModuleVendable.m5Bar,
        code: 'bsn-33',
      ),
      libelle: 'Béninoise 33cl',
      prix: 1000,
      categorie: 'locale',
    );
    // Le référentiel comptable : une vente passe sa pièce (l'exercice 2026).
    await baseInstalleeSur(db, aujourdhui);
    Future<void> vendre(DateTime quand, int bouteilles) async {
      final paniers = PanierDao(
        db,
        maintenant: () => quand,
        // Une vente passe sa pièce comptable dans la même transaction.
        moteur: () async => moteurSur(db, maintenant: () => quand),
      );
      var p = await paniers.ouvrir(
        typeVente: TypeVente.comptant,
        pointVente: 'Bar principal',
      );
      for (var i = 0; i < bouteilles; i++) {
        p = await paniers.ajouterLigne(p.id, biere);
      }
      await paniers.cloturer(
        p.id,
        modePaiement: 'especes',
        auteurId: caissierEssai,
      );
    }

    await vendre(DateTime(2026, 10, 5, 19), 2);
    await vendre(DateTime(2026, 10, 6, 20), 1);
    await vendre(DateTime(2026, 8, 3, 20), 5);

    // --- Dépenses : 2 dans la fenêtre, 1 en août ------------------------
    final depenses = await depenseDaoPrepare(db, aujourdhui);
    final centreDepenses = await centreDe(db, 'Restaurant');
    Future<void> depenser(DateTime jour, NatureDepense nature, int montant) =>
        depenses.enregistrer(
          dateTransaction: jour,
          tresorerie: TresorerieDepense.caisse,
          libelle: nature.libelle,
          auteurId: auteurDepense,
          centreId: centreDepenses,
          lignes: [
            SaisieLigneDepense(
              libelle: nature.libelle,
              compteCharge: '6011',
              nature: nature,
              montant: montant,
            ),
          ],
        );
    await depenser(DateTime(2026, 10, 9), NatureDepense.riz, 5000);
    await depenser(DateTime(2026, 10, 10), NatureDepense.transport, 3000);
    await depenser(DateTime(2026, 8, 1), NatureDepense.riz, 99000);
  });

  tearDown(() => db.close());

  Future<void> monter(
    WidgetTester tester, {
    Map<String, String> droits = const {
      'M1': 'C',
      'M6': 'C',
      'M10': 'C',
      'M11': 'C',
      'M13': 'C',
    },
    List<dynamic> surcharges = const [],
    DateTime? maintenant,
    AppDatabase? base,
    Widget? ecran,
    Size? taille,
  }) async {
    await monterCoquille(
      tester,
      role: 'administrateur',
      droits: droits,
      routeActive: '/tableau-de-bord',
      taille: taille ?? const Size(1600, 1400),
      enfant: ecran ?? const EcranTableauDeBord(),
      surcharges: [
        baseLocaleProvider.overrideWithValue(base ?? db),
        horlogeTableauDeBordProvider.overrideWithValue(
          () => maintenant ?? aujourdhui,
        ),
        ...surcharges.cast(),
      ],
    );
  }

  String texte(WidgetTester tester, Key cle) => tester
      .widgetList<Text>(
        find.descendant(of: find.byKey(cle), matching: find.byType(Text)),
      )
      .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
      .join(' | ');

  String valeur(WidgetTester tester, String cle) =>
      tester.widget<Text>(find.byKey(Key('tdb-valeur-$cle'))).data!;

  String note(WidgetTester tester, String cle) =>
      tester.widget<Text>(find.byKey(Key('tdb-note-$cle'))).data!;

  /// Ouvre le calendrier du champ [cle], retient le [jour] d'octobre 2026 (le
  /// mois de l'horloge, proposé à l'ouverture d'un champ vide) et valide.
  Future<void> choisirJour(WidgetTester tester, Key cle, int jour) async {
    await tester.ensureVisible(find.byKey(cle));
    await tester.tap(find.byKey(cle));
    await tester.pumpAndSettle();
    await tester.tap(find.text('$jour').last);
    await tester.pump();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  }

  group('La bande : les indicateurs établis, et des « — » jamais des zéros '
      'sous la note de la vue', () {
    testWidgets('les valeurs sont celles des tables du poste', (tester) async {
      await monter(tester);

      // 8 nuitées vendues / (2 unités louables x 31 jours) = 12,90 % tronqué
      // (12,903…). L'unité hors service n'entre pas au dénominateur : avec
      // elle, 8/93. Sur l'ancienne fenêtre « 30 derniers jours », 7/60.
      expect(valeur(tester, 'taux_occupation'), '12.90 %');
      // Une seule réservation en attente CRÉÉE dans la fenêtre (r2).
      expect(valeur(tester, 'reservations_en_attente'), '1');
      // « actif » seul : le salarié en congé et celui qui est parti en sont.
      expect(valeur(tester, 'employes_actifs'), '2');
      expect(note(tester, 'employes_actifs'), 'Sur 3 au total');
      // 10 sacs à 1 250,50 F = 12 505 F ; le sel n'a aucun coût.
      expect(valeur(tester, 'valeur_stock'), '12 505 FCFA');
    });

    testWidgets('la valeur du stock DIT ce qu’elle ne comprend pas', (
      tester,
    ) async {
      await monter(tester);

      expect(
        note(tester, 'valeur_stock'),
        "Au coût moyen pondéré, à l'instant — jamais au prix de vente"
        ' · hors 1 article(s) sans coût',
      );
    });

    // Décision du PO du 13/10/2026 (« regarde ce qui est fait dans tatacora
    // laravel vue ») : la carte sans source garde son « — », mais sous lui la
    // NOTE DE LA VUE, pas la raison datée — qui grandissait la carte et
    // descendait la seconde rangée de 173 px (géométrie `livewire/accueil`).
    testWidgets(
      'une seule carte reste sans source : les dépenses cumulées, '
      '« — » jamais un zéro, la note de la vue et la HAUTEUR de ses voisines',
      (tester) async {
        await monter(tester);

        const cle = 'depenses_cumulees';
        expect(valeur(tester, cle), '—');
        // La note de la vue, relue par PHP — ni la raison, ni rien d'inventé.
        expect(
          note(tester, cle),
          VueBlade.libelle('accueil_pwa.kpi.$cle.note'),
        );
        // (La série mensuelle, plus bas, garde la sienne : elle n'est pas une
        // carte de la bande.)
        expect(
          find.descendant(
            of: find.byKey(const Key('tdb-$cle')),
            matching: find.textContaining('constaté le 10/10/2026'),
          ),
          findsNothing,
        );
        // Aucun montant dans la carte : ni « 0 FCFA » ni autre.
        expect(texte(tester, Key('tdb-$cle')), isNot(contains('FCFA')));
        // Pas de ligne de variation sur un chiffre qui n'existe pas.
        expect(find.byKey(Key('tdb-variation-$cle')), findsNothing);

        // La hauteur. Les cartes d'une rangée s'étirent à la plus haute
        // (`GrilleAccueil`) : comparer deux cartes de la même rangée ne
        // prouverait rien. On compare donc les NOTES : celle de la carte sans
        // source tient dans l'ordre de grandeur de la note courte d'une carte
        // établie (« Somme des paiements reçus sur la période ») — la raison
        // datée, une dizaine de fois plus longue, la ferait exploser.
        final hauteurNote = tester
            .getSize(find.byKey(const Key('tdb-note-$cle')))
            .height;
        final hauteurNoteEtablie = tester
            .getSize(
              find.byKey(const Key('tdb-note-chiffre_affaires_encaisse')),
            )
            .height;
        expect(hauteurNote, lessThanOrEqualTo(2 * hauteurNoteEtablie));
      },
    );

    testWidgets('sans source, `:total` s’écrit « — » et la raison ne remplace '
        'pas la note (13/10/2026)', (tester) async {
      const absent = IndicateurTableauDeBord.indisponible(
        cle: 'employes_actifs',
        unite: UniteIndicateur.nombre,
        raison:
            'Raison longue, sur plusieurs lignes, qui ne doit pas paraître.',
      );
      expect(noteCarteIndicateur(absent), 'Sur — au total');
      // Le pilotage, lui, garde la raison (cartes Trésorerie / Valeur du stock).
      expect(noteIndicateurAffichee(absent), startsWith('Raison longue'));
    });

    testWidgets('CA encaissé, trésorerie de caisse et factures non soldées '
        'sont CALCULÉS depuis le lot 5 (12/10/2026) : plus de raison périmée', (
      tester,
    ) async {
      await monter(tester);

      for (final cle in const [
        'chiffre_affaires_encaisse',
        'tresorerie_caisse',
        'factures_impayees',
      ]) {
        expect(valeur(tester, cle), isNot('—'), reason: cle);
        // Ni la raison du 10/10 (« aucun paiement n'est enregistré »), ni celle du
        // 12/10 : leur prémisse est tombée.
        expect(find.textContaining('constaté le 12/10/2026'), findsNothing);
        expect(find.textContaining('aucun paiement'), findsNothing);
      }
      // Rien n'est encaissé : un ZÉRO VRAI (source complète et vide), pas un
      // tiret. La trésorerie est le fond de la caisse ouverte par le montage.
      // Le registre du montage porte UNE facture directe de 54 500 F, jamais
      // réglée (l'autre est annulée par son avoir : elle ne doit plus rien).
      expect(valeur(tester, 'chiffre_affaires_encaisse'), '0 FCFA');
      expect(valeur(tester, 'factures_impayees'), '1');
      expect(valeur(tester, 'tresorerie_caisse'), '1 000 FCFA');
    });

    testWidgets(
      'avec des encaissements, les trois cartes suivent LES RÈGLES DU '
      'SERVEUR (annulés comptés, fond des seules caisses ouvertes)',
      (tester) async {
        final client = await creerClient(db);
        final f1 = await emettreFacture(
          db,
          montant: 50000,
          clientId: client.id,
          horloge: DateTime(2026, 10, 5, 9),
        );
        await emettreFacture(
          db,
          montant: 12000,
          clientId: client.id,
          horloge: DateTime(2026, 8, 1, 9), // avant la fenêtre
        );
        final dao = paiementsDaoSur(db, horloge: DateTime(2026, 10, 6, 10));
        await dao.encaisser(
          pieceId: f1.id,
          montant: '20000',
          mode: 'especes',
          auteurId: caissierEssai,
        );
        final annule = await dao.encaisser(
          pieceId: f1.id,
          montant: '5000',
          mode: 'carte',
          auteurId: caissierEssai,
        );
        await dao.annuler(annule.id, 'Doublon', auteurId: caissierEssai);

        await monter(tester);

        // 20 000 + 5 000 : le serveur ne filtre PAS le statut (défaut répliqué).
        expect(valeur(tester, 'chiffre_affaires_encaisse'), '25 000 FCFA');
        // Fond 1 000 (caisse ouverte) + 25 000 rattachés à cette caisse.
        expect(valeur(tester, 'tresorerie_caisse'), '26 000 FCFA');
        // La facture du montage (54 500 F, jamais réglée) + f1 (reste 30 000 F :
        // seuls les 20 000 F ACTIFS sont déduits, l'encaissement annulé non) ; la
        // facture d'août est hors fenêtre, bien qu'impayée.
        expect(valeur(tester, 'factures_impayees'), '2');
      },
    );

    testWidgets('la carte a les QUATRE blocs du partiel de la vue (pastille, '
        'valeur, libellé, note) : aucune ligne « vs période précédente », '
        'libellé en casse normale (12/10/2026)', (tester) async {
      await monter(tester);

      for (final cle in EcranTableauDeBord.libelles.keys) {
        // La ligne de variation est retirée par la vue (arbitrage du PO du
        // 02/09/2026) : la carte ne la porte plus, sous aucune forme.
        expect(find.byKey(Key('tdb-variation-$cle')), findsNothing);
        expect(
          find.descendant(
            of: find.byKey(Key('tdb-$cle')),
            matching: find.textContaining('pas de comparaison'),
          ),
          findsNothing,
        );
        // Le libellé de la vue, AU MOT et dans sa casse (plus de capitales).
        expect(
          tester.widget<Text>(find.byKey(Key('tdb-libelle-$cle'))).data,
          EcranTableauDeBord.libelles[cle],
        );
        // Ordre vertical des blocs : pastille, valeur, libellé, note.
        final ys = [
          tester.getTopLeft(find.byKey(Key('tdb-pastille-$cle'))).dy,
          tester.getTopLeft(find.byKey(Key('tdb-valeur-$cle'))).dy,
          tester.getTopLeft(find.byKey(Key('tdb-libelle-$cle'))).dy,
          tester.getTopLeft(find.byKey(Key('tdb-note-$cle'))).dy,
        ];
        expect(ys, orderedEquals([...ys]..sort()), reason: cle);
      }
    });

    testWidgets('une période DEMANDÉE que le sélecteur ne connaît pas retombe '
        'sur « Ce mois » ET le nomme', (tester) async {
      await monter(
        tester,
        ecran: const EcranTableauDeBord(periodeDemandee: 'siecle'),
      );
      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(const Key('tdb-periode-inconnue')),
                matching: find.byType(Text),
              ),
            )
            .data,
        "La période demandée (« siecle ») n'existe pas. Les chiffres ci-dessous sont ceux de la période par défaut, « Ce mois » — ils ne répondent pas à la demande qui a été faite.",
      );
      expect(
        tester
            .state<FormFieldState<PeriodeTableauDeBord>>(
              find.byKey(const Key('tdb-periode')),
            )
            .value,
        PeriodeTableauDeBord.mois,
      );
    });

    testWidgets('une période demandée CONNUE est appliquée UNE fois, sans '
        'bandeau ; le sélecteur reste libre ensuite', (tester) async {
      await monter(
        tester,
        ecran: const EcranTableauDeBord(periodeDemandee: 'trimestre'),
      );
      expect(find.byKey(const Key('tdb-periode-inconnue')), findsNothing);
      PeriodeTableauDeBord? choisie() => tester
          .state<FormFieldState<PeriodeTableauDeBord>>(
            find.byKey(const Key('tdb-periode')),
          )
          .value;
      expect(choisie(), PeriodeTableauDeBord.trimestre);

      await tester.tap(find.byKey(const Key('tdb-periode')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ce mois').last);
      await tester.pumpAndSettle();
      expect(choisie(), PeriodeTableauDeBord.mois, reason: 'jamais réécrasé');
    });

    testWidgets('sous `lg`, les huit cartes sont repliées derrière « '
        'Indicateurs clés (8) » ; à partir de `lg`, la grille', (tester) async {
      // La barre supérieure déborde sous ~1 100 px (poste de bureau, décision
      // du PO du 08/10/2026) : ce débordement-là n'est pas l'objet du cas.
      final ancien = FlutterError.onError;
      FlutterError.onError = (d) {
        if (!d.toString().contains('overflowed')) ancien?.call(d);
      };
      addTearDown(() => FlutterError.onError = ancien);
      await monter(tester, taille: const Size(1020, 1800));
      expect(find.byKey(const Key('tdb-kpis-accordeon')), findsOneWidget);
      expect(find.text('Indicateurs clés (8)'), findsOneWidget);
      expect(find.byKey(const Key('tdb-valeur-taux_occupation')), findsNothing);
      await tester.tap(find.byKey(const Key('tdb-kpis-accordeon-bouton')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('tdb-valeur-taux_occupation')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('tdb-kpis-accordeon-bouton')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('tdb-valeur-taux_occupation')), findsNothing);
    });

    testWidgets(
      'à partir de `lg`, aucun accordéon : la grille des huit cartes',
      (tester) async {
        await monter(tester);
        expect(find.byKey(const Key('tdb-kpis-accordeon')), findsNothing);
        expect(
          find.byKey(const Key('tdb-valeur-taux_occupation')),
          findsOneWidget,
        );
      },
    );

    testWidgets('à l’ouverture, la période est celle de la VUE : « Ce mois », '
        'le mois civil ENTIER', (tester) async {
      await monter(tester);

      // Le sélecteur porte « Ce mois » (lu dans l'état du champ : le menu
      // garde tous ses libellés dans sa pile, `find.text` y trouverait tout).
      expect(
        tester
            .state<FormFieldState<PeriodeTableauDeBord>>(
              find.byKey(const Key('tdb-periode')),
            )
            .value,
        PeriodeTableauDeBord.mois,
      );
      // Du 1er au 31 octobre — pas « les 30 derniers jours » (11/09 -> 10/10)
      // ni « jusqu'à ce soir ».
      expect(
        tester.widget<Text>(find.byKey(const Key('tdb-libelle-periode'))).data,
        'Du 01/10/2026 au 31/10/2026',
      );
      // Hors « Période personnalisée », aucun champ de date dans l'en-tête.
      expect(find.byKey(const Key('tdb-periode-du')), findsNothing);
      expect(find.byKey(const Key('tdb-periode-au')), findsNothing);
    });

    testWidgets('« Période personnalisée » : sans ses deux dates, le MOIS (et '
        'le libellé le dit) ; avec elles, la fenêtre « du … au … » INCLUSE', (
      tester,
    ) async {
      await monter(tester);

      await tester.tap(find.byKey(const Key('tdb-periode')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Période personnalisée').last);
      await tester.pumpAndSettle();

      // Les deux champs de la vue apparaissent, vides.
      expect(find.byKey(const Key('tdb-periode-du')), findsOneWidget);
      expect(find.byKey(const Key('tdb-periode-au')), findsOneWidget);
      expect(texte(tester, const Key('tdb-periode-du')), 'jj/mm/aaaa');
      // `Periode::resoudre('personnalisee', '', '')` : le mois, dates réelles.
      expect(
        tester.widget<Text>(find.byKey(const Key('tdb-libelle-periode'))).data,
        'Du 01/10/2026 au 31/10/2026',
      );

      await choisirJour(tester, const Key('tdb-periode-du'), 4);
      // Une seule borne : toujours le mois.
      expect(
        tester.widget<Text>(find.byKey(const Key('tdb-libelle-periode'))).data,
        'Du 01/10/2026 au 31/10/2026',
      );
      await choisirJour(tester, const Key('tdb-periode-au'), 8);

      expect(texte(tester, const Key('tdb-periode-du')), '04/10/2026');
      expect(texte(tester, const Key('tdb-periode-au')), '08/10/2026');
      expect(
        tester.widget<Text>(find.byKey(const Key('tdb-libelle-periode'))).data,
        'Du 04/10/2026 au 08/10/2026',
      );
      // Le 8 est INCLUS (fin exclue = 9) : r1 y dort 1 nuit (le 4), r4 aussi
      // (le 8) — 2 nuitées / (2 unités x 5 jours) = 20,00 %. Fin exclue au 8 :
      // 1 / 8 = 12,50 %.
      expect(valeur(tester, 'taux_occupation'), '20.00 %');
      // r2 (en attente) a été créée le 08/10 : DANS la période, borne incluse.
      expect(valeur(tester, 'reservations_en_attente'), '1');
    });

    testWidgets('changer la période RECALCULE : « Aujourd’hui » -> 50,00 %, '
        'et plus aucune réservation en attente', (tester) async {
      await monter(tester);

      await tester.tap(find.byKey(const Key('tdb-periode')));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Aujourd'hui").last);
      await tester.pumpAndSettle();

      expect(
        tester.widget<Text>(find.byKey(const Key('tdb-libelle-periode'))).data,
        'Du 10/10/2026 au 10/10/2026',
      );
      // r4 dort la nuit du 10 ; r2 (en attente) n'est pas une nuit vendue.
      // 1 nuitée / (2 unités x 1 jour) = 50,00 %.
      expect(valeur(tester, 'taux_occupation'), '50.00 %');
      // r2 a été créée le 08/10 : hors de « aujourd'hui ».
      expect(valeur(tester, 'reservations_en_attente'), '0');
    });

    testWidgets('un poste VIDE : « 0 » seulement là où la source est complète '
        'et vide ; le taux, lui, reste « — » (un parc vide n’est pas un hôtel '
        'vide)', (tester) async {
      final vide = AppDatabase.enMemoire();
      addTearDown(vide.close);
      await monter(tester, base: vide);

      expect(valeur(tester, 'taux_occupation'), '—');
      // Sous le « — », la note de la vue (13/10/2026) : la raison (« Aucune
      // unité louable au parc… ») n'est plus rendue par la bande.
      expect(
        note(tester, 'taux_occupation'),
        VueBlade.libelle('accueil_pwa.kpi.taux_occupation.note'),
      );
      expect(find.textContaining('Aucune unité louable au parc'), findsNothing);
      expect(
        find.byKey(const Key('tdb-variation-taux_occupation')),
        findsNothing,
      );
      // Sources complètes et vides : zéro est la vérité.
      expect(valeur(tester, 'reservations_en_attente'), '0');
      expect(valeur(tester, 'employes_actifs'), '0');
      expect(note(tester, 'employes_actifs'), 'Sur 0 au total');
      expect(valeur(tester, 'valeur_stock'), '0 FCFA');
    });

    testWidgets('sans le droit de lecture de M11 : la page « Consultation de '
        'secours » de la vue, AUCUN chiffre consolidé', (tester) async {
      await monter(tester, droits: const {'M1': 'C'});

      // Le titre et le sous-titre de `pwa.accueil` (la vue, l.246-247).
      expect(
        tester.widget<Text>(find.byKey(const Key('tdb-titre'))).data,
        'Consultation de secours',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('tdb-sous-titre'))).data,
        'Consultation de secours — les écrans auxquels votre rôle donne '
        'accès.',
      );
      // Ni bande, ni onglets, ni période, ni récapitulatif, ni graphiques.
      for (final cle in EcranTableauDeBord.libelles.keys) {
        expect(find.byKey(Key('tdb-valeur-$cle')), findsNothing);
      }
      expect(find.byKey(const Key('tdb-onglet-exploitation')), findsNothing);
      expect(find.byKey(const Key('tdb-libelle-periode')), findsNothing);
      expect(find.byKey(const Key('tdb-periode')), findsNothing);
      expect(find.byKey(const Key('tdb-recap')), findsNothing);
      expect(find.byKey(const Key('tdb-carte-ca')), findsNothing);
      // Les chambres (lecture M1) restent. L'accès « Nouvelle réservation »,
      // lui, exige l'écriture sur M1 ET sur l'écran (M11) depuis le lot C
      // (`Accueil::peutEcrire()`) : sans M11, il n'est pas offert.
      expect(find.byKey(const Key('tdb-acces-reservation')), findsNothing);
      expect(find.byKey(const Key('tdb-chambres')), findsOneWidget);
    });

    testWidgets('sans le droit de lecture de M6 : « — » et la phrase de '
        'refus, jamais la valeur du stock', (tester) async {
      await monter(tester, droits: const {'M1': 'C', 'M11': 'C', 'M13': 'C'});

      expect(valeur(tester, 'valeur_stock'), '—');
      expect(note(tester, 'valeur_stock'), isNot(contains('12 505')));
    });
  });

  group('Les graphiques', () {
    testWidgets('la ventilation vient du registre : avoir en diminution, '
        'code de module reconnu', (tester) async {
      await monter(tester);

      // M1 : 50 000 + 20 000 - 20 000 (l'avoir annule la facture annulée).
      expect(
        tester.widget<Text>(find.byKey(const Key('tdb-montant-M1'))).data,
        '50 000 FCFA',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('tdb-montant-M5'))).data,
        '4 500 FCFA',
      );
      // Le code de module est traduit en nom d'activité : ni « M1 » ni « M5 »
      // affichés bruts, ni gris « inconnu ».
      expect(find.text('Hébergement'), findsWidgets);
      expect(find.text('Bar'), findsWidgets);
    });

    testWidgets('la série mensuelle est « non calculable » et le dit, sans '
        'boutons d’étendue inertes', (tester) async {
      await monter(tester);

      final raison = tester
          .widget<Text>(find.byKey(const Key('tdb-ca-indisponible')))
          .data!;
      expect(raison, contains('constaté le 10/10/2026'));
      // La raison RENDUE est la raison revue (D282, puis D414 le 14/10/2026) :
      // la courbe des dépenses serait un minorant tracé comme le total.
      expect(raison, contains('revu le 14/10/2026'));
      expect(raison, contains('Celle des dépenses lit la comptabilité'));
      expect(raison, contains('minorant'));
      expect(raison, isNot(contains('paiements')));
      expect(find.byKey(const Key('tdb-ca-vide')), findsNothing);
      for (final mois in [3, 6, 12]) {
        expect(find.byKey(Key('tdb-mois-$mois')), findsNothing);
      }
    });
  });

  group('Pilotage consolidé', () {
    Future<void> ouvrirPilotage(WidgetTester tester) async {
      await monter(tester);
      await tester.tap(find.text('Pilotage consolidé'));
      await tester.pumpAndSettle();
    }

    testWidgets('le taux du bloc d’occupation est CELUI de la bande (une '
        'seule règle) — ce n’était pas le cas avant', (tester) async {
      await ouvrirPilotage(tester);

      expect(
        tester
            .widget<Text>(find.byKey(const Key('pilotage-occupation-taux')))
            .data,
        '12.90 %',
      );
      // Sous le taux, la phrase de la VUE (`accueil_pwa.occupation.sous_titre`),
      // plus la phrase des nuitées de l'ancien maître (13/10/2026).
      expect(
        tester
            .widget<Text>(find.byKey(const Key('pilotage-occupation-detail')))
            .data,
        'Taux calculé en nuitées vendues, rapportées à la capacité de la '
        'période.',
      );
    });

    testWidgets('« Occupées à l’instant » n’est plus rendu : la vue ne porte '
        'que le taux et sa phrase (13/10/2026)', (tester) async {
      await ouvrirPilotage(tester);
      expect(
        find.byKey(const Key('pilotage-occupation-instant')),
        findsNothing,
      );
      expect(find.text('OCCUPÉES À L’INSTANT'), findsNothing);
    });

    testWidgets('un mois SANS bulletin dit « Aucun bulletin établi ce mois-ci »'
        ' — une paie non établie n’est pas une masse nulle', (tester) async {
      await monter(tester, maintenant: DateTime(2026, 11, 15, 9));
      await tester.tap(find.text('Pilotage consolidé'));
      await tester.pumpAndSettle();

      final carte = texte(tester, const Key('pilotage-kpi-masse-salariale'));
      expect(carte, contains('Aucun bulletin établi ce mois-ci'));
      expect(carte, contains('0 salarié(s) · coût réel non arrêté'));
      expect(carte, isNot(contains('FCFA')));
    });

    testWidgets('sans le droit de lecture de M10, la carte « Dépense '
        'courante » n’est pas rendue (jamais calculée puis masquée)', (
      tester,
    ) async {
      await monter(
        tester,
        droits: const {'M1': 'C', 'M6': 'C', 'M11': 'C', 'M13': 'C'},
      );
      await tester.tap(find.text('Pilotage consolidé'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('pilotage-module-depenses')), findsNothing);
    });

    testWidgets('la masse salariale est le BRUT du bulletin du mois, avec '
        'la mention du coût non arrêté', (tester) async {
      await ouvrirPilotage(tester);

      final carte = texte(tester, const Key('pilotage-kpi-masse-salariale'));
      expect(carte, contains('150 000 FCFA'));
      expect(carte, contains('1 salarié(s) · coût réel non arrêté'));
    });

    testWidgets('sans droit sur M13 : « Non consulté », pas zéro', (
      tester,
    ) async {
      await monter(
        tester,
        droits: const {'M1': 'C', 'M6': 'C', 'M10': 'C', 'M11': 'C'},
      );
      await tester.tap(find.text('Pilotage consolidé'));
      await tester.pumpAndSettle();

      final carte = texte(tester, const Key('pilotage-kpi-masse-salariale'));
      // Rendu exact : libellé, « Non consulté », puis « — » — jamais
      // « 0 salarié(s) » sous une source non lue (D174).
      expect(carte, 'MASSE SALARIALE | Non consulté | —');
    });

    testWidgets('la carte « Dépense courante » est rendue sur la FENÊTRE : '
        'la dépense d’août n’y est pas', (tester) async {
      await ouvrirPilotage(tester);

      final carte = texte(tester, const Key('pilotage-module-depenses'));
      expect(carte, contains('Dépense courante'));
      expect(carte, contains('8 000 FCFA'));
      expect(carte, contains('Nombre'));
      expect(carte, contains('5 000 FCFA'));
      expect(carte, contains('3 000 FCFA'));
      expect(carte, isNot(contains('99 000')));
    });

    testWidgets('les meilleures ventes suivent la période : 3 bières, pas 8 — '
        'celles d’août sont hors fenêtre', (tester) async {
      await ouvrirPilotage(tester);

      final bar = texte(
        tester,
        const Key('pilotage-classement-Bar — boissons'),
      );
      expect(bar, contains('Béninoise 33cl'));
      expect(bar, contains('3'));
      expect(bar, isNot(contains('8')));
      expect(bar, contains('vendu(s)'));
      // Un classement sans vente le DIT (restaurant : aucun plat vendu).
      expect(
        texte(tester, const Key('pilotage-classement-Restaurant — plats')),
        contains('Aucune vente sur cette période.'),
      );
      expect(
        find.byKey(const Key('pilotage-top-ventes-sans-periode')),
        findsNothing,
      );
    });

    /// Deux encaissements : 20 000 F en espèces le 06/10 (dans « Ce mois ») et
    /// 12 000 F le 02/08 (hors du mois, dans l'année). Les
    /// deux sont rattachés à la caisse ouverte du montage. Sans le second, une
    /// carte calculée sur une AUTRE fenêtre (l'année, la période précédente)
    /// pourrait dire la même chose que la bande — la mutation ne mordrait pas
    /// (piège 7).
    Future<void> deuxEncaissements() async {
      final client = await creerClient(db);
      final octobre = await emettreFacture(
        db,
        montant: 50000,
        clientId: client.id,
        horloge: DateTime(2026, 10, 5, 9),
      );
      final aout = await emettreFacture(
        db,
        montant: 12000,
        clientId: client.id,
        horloge: DateTime(2026, 8, 1, 9),
      );
      await paiementsDaoSur(db, horloge: DateTime(2026, 10, 6, 10)).encaisser(
        pieceId: octobre.id,
        montant: '20000',
        mode: 'especes',
        auteurId: caissierEssai,
      );
      await paiementsDaoSur(db, horloge: DateTime(2026, 8, 2, 10)).encaisser(
        pieceId: aout.id,
        montant: '12000',
        mode: 'especes',
        auteurId: caissierEssai,
      );
    }

    testWidgets('R1 — « Chiffre d’affaires encaissé » et « Trésorerie '
        '(caisse) » DISENT LA VALEUR DE LA BANDE, sur la même fenêtre, aux '
        'libellés de la vue', (tester) async {
      await deuxEncaissements();
      await monter(tester);

      // La bande d'abord (onglet d'exploitation), telle qu'elle est rendue.
      final caBande = valeur(tester, 'chiffre_affaires_encaisse');
      final tresorerieBande = valeur(tester, 'tresorerie_caisse');
      // Ancrage EXTÉRIEUR (piège 12) : les montants attendus, pas seulement
      // l'égalité des deux rendus — une carte et une bande fausses ensemble
      // seraient égales entre elles.
      expect(caBande, formaterFcfa(20000));
      expect(tresorerieBande, formaterFcfa(1000 + 20000));

      await tester.tap(find.text('Pilotage consolidé'));
      await tester.pumpAndSettle();

      expect(
        texte(tester, const Key('pilotage-kpi-ca')),
        "CHIFFRE D'AFFAIRES ENCAISSÉ | $caBande | Du 01/10/2026 au 31/10/2026",
      );
      expect(
        texte(tester, const Key('pilotage-kpi-tresorerie')),
        'TRÉSORERIE (CAISSE) | $tresorerieBande | '
        'Sessions de caisse ouvertes et leurs encaissements',
      );
      // Plus aucune trace du motif faux (« calculée par le serveur … aucun
      // chiffre ne peut être affiché à la place ») nulle part dans l'onglet.
      expect(find.textContaining('calculée par le serveur'), findsNothing);
      expect(find.textContaining('indisponible'), findsNothing);
    });

    /// Un article SOUS son seuil et valorisé (1 bidon à 10 000 F, seuil 5) :
    /// l'ancienne carte, lue en M6, peignait alors la valeur en AMBRE et
    /// écrivait « N référence(s) · N sous seuil » — deux choses que la vue ne
    /// porte pas (accueil.blade.php l.928-933 : accent '', note seule). Sans
    /// lui, la mutation « ambre rétabli » ne mordrait pas (piège 7).
    Future<void> huileSousSeuil() async {
      final stocks = StocksDao(db);
      final reserve = await stocks.creerPoint(libelle: 'Réserve');
      await stocks.creerArticle(
        id: 'huile',
        libelle: 'Huile',
        categorie: null,
        uniteMesure: 'bidon',
        seuilCentiemes: 500,
        suivi: SuiviArticle.permanent,
        pointStockageId: reserve.id,
        auteurId: 'u-essai',
        ouverture: (centiemes: 100, coutDixMilliemes: 100000000),
      );
    }

    testWidgets('« Valeur du stock » DIT LA VALEUR DE LA BANDE et sa note — '
        'libellé et détail de la vue, navy, plus « N référence(s) · N sous '
        'seuil » ni l’ambre', (tester) async {
      await huileSousSeuil();
      await monter(tester);

      // La bande d'abord, telle qu'elle est rendue.
      final valeurBande = valeur(tester, 'valeur_stock');
      final noteBande = note(tester, 'valeur_stock');
      // Ancrage EXTÉRIEUR (piège 12) : 12 505 (riz) + 10 000 (huile) ; le sel
      // n'a aucun coût, et la note le dit.
      expect(valeurBande, formaterFcfa(22505));
      expect(
        noteBande,
        "Au coût moyen pondéré, à l'instant — jamais au prix de vente"
        ' · hors 1 article(s) sans coût',
      );

      await tester.tap(find.text('Pilotage consolidé'));
      await tester.pumpAndSettle();

      expect(
        texte(tester, const Key('pilotage-kpi-stock')),
        'VALEUR DU STOCK | $valeurBande | $noteBande',
      );
      expect(
        texte(tester, const Key('pilotage-kpi-stock')),
        isNot(contains('référence(s)')),
      );
      // Un article sous son seuil n'y change rien : la vue écrit `accent ''`.
      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(const Key('pilotage-kpi-stock')),
                matching: find.text(valeurBande),
              ),
            )
            .style
            ?.color,
        AppColors.navy,
      );
    });

    testWidgets('« Valeur du stock » sans article sans coût : le détail est la '
        'note de la vue, AU MOT, et la valeur celle de la bande', (
      tester,
    ) async {
      // Le sel reçoit une entrée VALORISÉE : plus aucun article sans coût.
      final point = (await db.select(db.pointsStockageLocal).get()).single;
      await StocksDao(db).ajouterMouvement(
        articleId: 'sel',
        pointId: point.id,
        type: TypeMouvement.entree,
        centiemes: 100,
        motif: 'Achat',
        auteurId: 'u-essai',
        coutDixMilliemes: 2000000,
      );
      await monter(tester);
      final valeurBande = valeur(tester, 'valeur_stock');
      expect(
        note(tester, 'valeur_stock'),
        isNot(contains('sans coût')),
        reason: 'le cas doit être SANS article sans coût',
      );
      await tester.tap(find.text('Pilotage consolidé'));
      await tester.pumpAndSettle();

      expect(
        texte(tester, const Key('pilotage-kpi-stock')),
        'VALEUR DU STOCK | $valeurBande | '
        "Au coût moyen pondéré, à l'instant — jamais au prix de vente",
      );
    });

    testWidgets('« Valeur du stock » pendant le calcul de la bande : '
        '« Chargement… », comme les cartes 1 et 3', (tester) async {
      final jamais = Completer<ResultatTableauDeBord>();
      await monter(
        tester,
        surcharges: [
          tableauDeBordProvider.overrideWith((ref) => jamais.future),
          ongletTableauDeBordProvider.overrideWithBuild(
            (ref, notifier) => OngletTableauDeBord.pilotage,
          ),
        ],
      );

      expect(
        texte(tester, const Key('pilotage-kpi-stock')),
        'VALEUR DU STOCK | Chargement… | ',
      );
    });

    testWidgets('R1 — « Résultat net » reste sur sa voie M10 : « Non '
        'consulté », les mots de la vue, et la raison DATÉE — jamais un zéro', (
      tester,
    ) async {
      await ouvrirPilotage(tester);

      final carte = texte(tester, const Key('pilotage-kpi-resultat'));
      expect(carte, startsWith('RÉSULTAT NET | Non consulté | '));
      expect(carte, contains('Comptabilité non consultée'));
      expect(carte, contains('constaté le 13/10/2026'));
      expect(carte, isNot(contains('FCFA')));
      // La raison VRAIE : un calcul non porté, pas un serveur disparu.
      expect(carte, contains('ne sont pas calculés sur ce poste'));
    });

    PeriodeTableauDeBord selecteur(WidgetTester tester) => tester
        .state<FormFieldState<PeriodeTableauDeBord>>(
          find.byKey(const Key('tdb-periode')),
        )
        .value!;

    String libellePeriode(WidgetTester tester) =>
        tester.widget<Text>(find.byKey(const Key('tdb-libelle-periode'))).data!;

    testWidgets('R2 — « Exercice entier » règle la période de TOUT le tableau '
        'de bord sur « Cette année », l’année civile ENTIÈRE (`Periode::'
        'annee()`), sans infobulle fausse', (tester) async {
      await deuxEncaissements();
      await ouvrirPilotage(tester);

      // Avant : « Ce mois », l'encaissement d'août n'y est pas.
      expect(
        texte(tester, const Key('pilotage-kpi-ca')),
        contains(formaterFcfa(20000)),
      );
      // Aucune infobulle (« ces bornes ne commandaient que M10 » était faux).
      expect(
        find.descendant(
          of: find.byKey(const Key('pilotage-btn-reset')),
          matching: find.byType(Tooltip),
        ),
        findsNothing,
      );
      // La phrase « Période personnalisée : non portée » a disparu : les
      // champs sont portés (D296).
      expect(find.textContaining('non portée sur ce poste'), findsNothing);

      await tester.tap(find.byKey(const Key('pilotage-btn-reset')));
      await tester.pumpAndSettle();

      // Le sélecteur d'en-tête PORTE la nouvelle période. Lue dans l'ÉTAT du
      // champ, pas par `find.text('Cette année')` : le bouton de menu garde
      // TOUS ses libellés dans sa pile, si bien que ce texte s'y trouve quelle
      // que soit la période retenue (assertion vide, prouvée par mutation le
      // 12/10/2026 — piège 5).
      expect(selecteur(tester), PeriodeTableauDeBord.annee);
      // L'année civile ENTIÈRE, jusqu'au 31/12 — comme la vue ; plus « jusqu'à
      // ce soir » (l'écart nommé le 12/10/2026 matin a disparu).
      expect(libellePeriode(tester), 'Du 01/01/2026 au 31/12/2026');
      // Et les cartes suivent : l'encaissement d'août entre dans l'année.
      expect(
        texte(tester, const Key('pilotage-kpi-ca')),
        "CHIFFRE D'AFFAIRES ENCAISSÉ | ${formaterFcfa(32000)} | "
        'Du 01/01/2026 au 31/12/2026',
      );
      expect(
        texte(tester, const Key('pilotage-kpi-tresorerie')),
        contains(formaterFcfa(1000 + 32000)),
      );

      // La bande dit la même chose sur la même période.
      await tester.tap(find.text("Vue d'exploitation").first);
      await tester.pumpAndSettle();
      expect(valeur(tester, 'chiffre_affaires_encaisse'), formaterFcfa(32000));
    });

    testWidgets('R2 — « Du » / « Au » du pilotage écrivent la borne ET '
        'basculent TOUT l’écran sur « Période personnalisée », fin INCLUSE', (
      tester,
    ) async {
      await deuxEncaissements();
      await ouvrirPilotage(tester);

      // Les deux champs de la vue, vides au départ — jamais inertes.
      expect(texte(tester, const Key('pilotage-f-debut')), 'jj/mm/aaaa');
      expect(texte(tester, const Key('pilotage-f-fin')), 'jj/mm/aaaa');

      // « Du » seul : la période bascule, mais sans « Au » elle reste le mois
      // (`Periode::resoudre`) — et le libellé le dit.
      await choisirJour(tester, const Key('pilotage-f-debut'), 1);
      expect(selecteur(tester), PeriodeTableauDeBord.personnalisee);
      expect(libellePeriode(tester), 'Du 01/10/2026 au 31/10/2026');

      // « Au » le 5 : l'encaissement du 6 sort de la fenêtre.
      await choisirJour(tester, const Key('pilotage-f-fin'), 5);
      expect(libellePeriode(tester), 'Du 01/10/2026 au 05/10/2026');
      expect(
        texte(tester, const Key('pilotage-kpi-ca')),
        "CHIFFRE D'AFFAIRES ENCAISSÉ | ${formaterFcfa(0)} | "
        'Du 01/10/2026 au 05/10/2026',
      );
      // Les deux champs de l'en-tête — les MÊMES propriétés — portent les
      // dates saisies au pilotage.
      expect(texte(tester, const Key('tdb-periode-du')), '01/10/2026');
      expect(texte(tester, const Key('tdb-periode-au')), '05/10/2026');

      // « Au » le 6 : le 6 est INCLUS, son encaissement entre.
      await choisirJour(tester, const Key('pilotage-f-fin'), 6);
      expect(
        texte(tester, const Key('pilotage-kpi-ca')),
        "CHIFFRE D'AFFAIRES ENCAISSÉ | ${formaterFcfa(20000)} | "
        'Du 01/10/2026 au 06/10/2026',
      );

      // « Exercice entier » GARDE les dates saisies (`$du`/`$au` du
      // composant) : revenir à « Période personnalisée » les retrouve.
      await tester.tap(find.byKey(const Key('pilotage-btn-reset')));
      await tester.pumpAndSettle();
      expect(selecteur(tester), PeriodeTableauDeBord.annee);
      expect(find.byKey(const Key('tdb-periode-du')), findsNothing);
      expect(texte(tester, const Key('pilotage-f-debut')), '01/10/2026');
    });

    testWidgets('« Du » du pilotage se VIDE comme le contrôle natif : borne '
        'retirée, bascule sur « personnalisée », période ramenée au MOIS', (
      tester,
    ) async {
      await deuxEncaissements();
      await ouvrirPilotage(tester);

      // Vide : aucune croix — elle n'aurait rien à effacer (Article 3.3).
      expect(find.byKey(const Key('pilotage-f-debut-effacer')), findsNothing);

      await choisirJour(tester, const Key('pilotage-f-debut'), 1);
      await choisirJour(tester, const Key('pilotage-f-fin'), 5);
      expect(libellePeriode(tester), 'Du 01/10/2026 au 05/10/2026');

      // « Exercice entier » d'abord : vider « Du » doit REBASCULER sur
      // « personnalisée » (`x-on:change` part aussi quand le champ se vide) —
      // sans ce détour, la bascule ne serait pas éprouvée.
      await tester.tap(find.byKey(const Key('pilotage-btn-reset')));
      await tester.pumpAndSettle();
      expect(selecteur(tester), PeriodeTableauDeBord.annee);

      await tester.ensureVisible(
        find.byKey(const Key('pilotage-f-debut-effacer')),
      );
      await tester.tap(find.byKey(const Key('pilotage-f-debut-effacer')));
      await tester.pumpAndSettle();

      expect(selecteur(tester), PeriodeTableauDeBord.personnalisee);
      expect(texte(tester, const Key('pilotage-f-debut')), 'jj/mm/aaaa');
      // « Au » est gardé (`$au` n'est pas touché) ; sans ses deux dates,
      // `Periode::resoudre` rend le mois — et toutes les cartes le suivent.
      expect(texte(tester, const Key('pilotage-f-fin')), '05/10/2026');
      expect(libellePeriode(tester), 'Du 01/10/2026 au 31/10/2026');
      expect(
        texte(tester, const Key('pilotage-kpi-ca')),
        "CHIFFRE D'AFFAIRES ENCAISSÉ | ${formaterFcfa(20000)} | "
        'Du 01/10/2026 au 31/10/2026',
      );
      expect(find.byKey(const Key('pilotage-f-debut-effacer')), findsNothing);
    });

    testWidgets('« Au » de l’en-tête se vide aussi : la période reste '
        '« personnalisée » et retombe sur le mois', (tester) async {
      await ouvrirPilotage(tester);
      await tester.tap(find.byKey(const Key('tdb-periode')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Période personnalisée').last);
      await tester.pumpAndSettle();

      await choisirJour(tester, const Key('tdb-periode-du'), 4);
      await choisirJour(tester, const Key('tdb-periode-au'), 8);
      expect(libellePeriode(tester), 'Du 04/10/2026 au 08/10/2026');

      await tester.tap(find.byKey(const Key('tdb-periode-au-effacer')));
      await tester.pumpAndSettle();

      expect(selecteur(tester), PeriodeTableauDeBord.personnalisee);
      expect(texte(tester, const Key('tdb-periode-au')), 'jj/mm/aaaa');
      expect(texte(tester, const Key('tdb-periode-du')), '04/10/2026');
      expect(libellePeriode(tester), 'Du 01/10/2026 au 31/10/2026');
    });

    String alerte(WidgetTester tester, int i) =>
        texte(tester, Key('pilotage-alerte-$i'));

    testWidgets('R3 — « À traiter » : créances (M3), factures non soldées et '
        'réservations en attente (M11), dans l’ORDRE du serveur, aux mots du '
        'serveur, avec le compte des sources', (tester) async {
      // Un article SOUS son seuil : l'alerte de stock (ambre) doit venir APRÈS
      // celle des réservations en attente (info) — l'ordre d'insertion du
      // serveur, qui ne trie pas. Sans elle, un tri par gravité réintroduit
      // dirait la même chose (piège 7).
      final stocks = StocksDao(db);
      final cave = await stocks.creerPoint(libelle: 'Cave');
      await stocks.creerArticle(
        id: 'huile',
        libelle: 'Huile',
        categorie: null,
        uniteMesure: 'bidon',
        seuilCentiemes: 1000,
        suivi: SuiviArticle.permanent,
        pointStockageId: cave.id,
        auteurId: 'u-essai',
        ouverture: (centiemes: 200, coutDixMilliemes: 15000000),
      );
      await monter(
        tester,
        droits: const {
          'M1': 'C',
          'M3': 'L',
          'M6': 'C',
          'M10': 'C',
          'M11': 'C',
          'M13': 'C',
        },
      );
      // Les nombres de la BANDE, relus tels qu'elle les rend.
      final factures = valeur(tester, 'factures_impayees');
      final enAttente = valeur(tester, 'reservations_en_attente');
      expect(factures, '1');
      expect(enAttente, '1');

      await tester.tap(find.text('Pilotage consolidé'));
      await tester.pumpAndSettle();

      // Le montage : UNE facture directe de 54 500 F, jamais réglée, sans
      // client — la même que la carte « Créances clients ».
      expect(
        alerte(tester, 0),
        '${formaterFcfa(54500)} de créances clients | '
        '1 pièce(s) non soldée(s) chez 0 client(s)',
      );
      expect(
        alerte(tester, 1),
        '$factures facture(s) non soldée(s) | '
        'Certifiées dont le règlement reste incomplet',
      );
      expect(
        alerte(tester, 2),
        '$enAttente réservation(s) en attente | À confirmer',
      );
      expect(
        alerte(tester, 3),
        '1 article(s) sous le seuil de réapprovisionnement | '
        'Réapprovisionnement à déclencher.',
      );
      expect(find.byKey(const Key('pilotage-alerte-4')), findsNothing);
      // M3, M11 et M6 lus ; M10 non évalué sur ce poste, et la ligne le dit.
      expect(
        tester
            .widget<Text>(find.byKey(const Key('pilotage-alertes-sources')))
            .data,
        '3 source(s) consultée(s) sur 4 — celles que votre rôle vous donne le '
        'droit de lire.',
      );
      expect(
        texte(tester, const Key('pilotage-alertes-indisponible-0')),
        startsWith(
          'Comptabilité — alertes non évaluées : le compte de '
          'résultat',
        ),
      );
      expect(find.byKey(const Key('pilotage-alertes-aucune')), findsNothing);
    });

    testWidgets('R3 — sans droit de lecture sur M3, l’alerte de créances n’est '
        'ni calculée ni comptée', (tester) async {
      await ouvrirPilotage(tester); // M1, M6, M10, M11, M13 : pas M3

      expect(find.textContaining('de créances clients'), findsNothing);
      expect(alerte(tester, 0), startsWith('1 facture(s) non soldée(s)'));
      expect(
        tester
            .widget<Text>(find.byKey(const Key('pilotage-alertes-sources')))
            .data,
        startsWith('2 source(s) consultée(s) sur 4'),
      );
    });

    testWidgets('R3 — un poste sans créance ni facture : AUCUNE alerte (la '
        'règle est « > 0 »), et le message QUALIFIÉ de la vue, jamais « tout '
        'est au vert »', (tester) async {
      final vide = AppDatabase.enMemoire();
      addTearDown(vide.close);
      await monter(
        tester,
        base: vide,
        droits: const {'M1': 'C', 'M3': 'L', 'M6': 'C', 'M11': 'C'},
      );
      await tester.tap(find.text('Pilotage consolidé'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('pilotage-alerte-0')), findsNothing);
      expect(find.textContaining('de créances clients'), findsNothing);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('pilotage-alertes-aucune')))
            .data,
        'Aucune alerte opérationnelle sur les sources consultées.',
      );
      expect(find.textContaining('au vert'), findsNothing);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('pilotage-alertes-sources')))
            .data,
        startsWith('3 source(s) consultée(s) sur 4'),
      );
    });

    testWidgets('« Créances clients » est ÉTABLIE depuis le lot 5 (D282) : le '
        'reste dû des factures, jamais « indisponible »', (tester) async {
      await ouvrirPilotage(tester);

      // Le registre du montage : UNE facture directe de 54 500 F, jamais
      // réglée, sans client (l'autre est annulée par son avoir).
      expect(
        texte(tester, const Key('pilotage-kpi-creances')),
        'CRÉANCES CLIENTS | 54 500 FCFA | '
        '1 pièce(s) non soldée(s) chez 0 client(s)',
      );
      // La raison du 10/10 (« aucun paiement de facture n'est enregistré »)
      // a disparu de l'écran.
      expect(find.textContaining('Aucun paiement de facture'), findsNothing);
      // Le graphique est PORTÉ depuis le 13/10/2026 (fin du Pilotage) : plus
      // de phrase « non rendu ». SANS droit de lecture sur M3 (ce montage), la
      // vue dit « Non consulté » — le graphique n'est pas calculé.
      expect(find.byKey(const Key('pilotage-creances-refuse')), findsNothing);
      expect(
        find.byKey(const Key('pilotage-creances-non-consulte')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('pilotage-creances-graphique')),
        findsNothing,
      );
    });

    testWidgets('« Créances par ancienneté » AVEC le droit M3 : le tracé, ses '
        'quatre tranches aux mots de la vue, et la note de la vue', (
      tester,
    ) async {
      await monter(
        tester,
        droits: const {
          'M1': 'C',
          'M3': 'L',
          'M6': 'C',
          'M10': 'C',
          'M11': 'C',
          'M13': 'C',
        },
      );
      await tester.tap(find.text('Pilotage consolidé'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('pilotage-creances-graphique')),
        findsOneWidget,
      );
      expect(
        [
          for (var i = 0; i < 4; i++)
            tester
                .widget<Text>(find.byKey(Key('pilotage-creances-tranche-$i')))
                .data,
        ],
        ['0 à 30 jours', '31 à 60 jours', '61 à 90 jours', 'Plus de 90 jours'],
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('pilotage-creances-age')))
            .data,
        "Âge compté depuis la date d'émission de la facture.",
      );
    });

    testWidgets('« Créances clients » déduit les encaissements ACTIFS : reste '
        'dû, toutes périodes, clients distincts', (tester) async {
      final client = await creerClient(db);
      final f1 = await emettreFacture(
        db,
        montant: 50000,
        clientId: client.id,
        horloge: DateTime(2026, 10, 5, 9),
      );
      await emettreFacture(
        db,
        montant: 12000,
        clientId: client.id,
        horloge: DateTime(2026, 8, 1, 9),
      );
      final dao = paiementsDaoSur(db, horloge: DateTime(2026, 10, 6, 10));
      await dao.encaisser(
        pieceId: f1.id,
        montant: '20000',
        mode: 'especes',
        auteurId: caissierEssai,
      );
      final annule = await dao.encaisser(
        pieceId: f1.id,
        montant: '5000',
        mode: 'carte',
        auteurId: caissierEssai,
      );
      await dao.annuler(annule.id, 'Doublon', auteurId: caissierEssai);

      await ouvrirPilotage(tester);

      // 54 500 (montage) + 30 000 (f1 : 50 000 - 20 000 actifs ; l'annulé ne
      // déduit rien) + 12 000 (août : la carte n'est pas fenêtrée, comme
      // `SoldeClientService::totaux()`).
      expect(
        texte(tester, const Key('pilotage-kpi-creances')),
        'CRÉANCES CLIENTS | 96 500 FCFA | '
        '3 pièce(s) non soldée(s) chez 1 client(s)',
      );
    });

    testWidgets('« À traiter » compte les articles critiques COMME LE SERVEUR '
        '(`Accueil::articlesCritiques`) : un journalier au seuil zéro y est, '
        'quand l’écran Stocks ne le compte pas sous seuil', (tester) async {
      final stocks = StocksDao(db);
      // Un achat journalier : seuil ramené à zéro, solde zéro — critique pour
      // le serveur (0 <= 0), jamais « sous seuil » pour l'écran Stocks.
      await stocks.creerArticle(
        id: 'pain',
        libelle: 'Pain',
        categorie: null,
        uniteMesure: 'pièce',
        seuilCentiemes: 0,
        suivi: SuiviArticle.journalier,
        pointStockageId: null,
        auteurId: 'u-essai',
      );
      await ouvrirPilotage(tester);

      // L'écran Stocks (`kpis.sousSeuil`) n'en voit AUCUN — la carte « Stocks »
      // par module le dit (la carte KPI « Valeur du stock » ne porte plus ce
      // décompte depuis le 12/10/2026 : la vue ne l'y met pas).
      expect(
        texte(tester, const Key('pilotage-module-m6')),
        contains('Sous seuil | 0'),
      );
      // « À traiter » en voit UN, comme le serveur.
      final lignes = [
        for (var i = 0; i < 5; i++)
          if (find.byKey(Key('pilotage-alerte-$i')).evaluate().isNotEmpty)
            texte(tester, Key('pilotage-alerte-$i')),
      ];
      expect(
        lignes,
        contains(
          '1 article(s) sous le seuil de réapprovisionnement | '
          'Réapprovisionnement à déclencher.',
        ),
      );
    });

    testWidgets('« Voir les articles » (INSTRUCTION1.txt §2.C) : rendu sous '
        '« À traiter » quand un article est critique, il ouvre la modale des '
        'articles sous le seuil', (tester) async {
      await StocksDao(db).creerArticle(
        id: 'pain',
        libelle: 'Pain',
        categorie: null,
        uniteMesure: 'pièce',
        seuilCentiemes: 0,
        suivi: SuiviArticle.journalier,
        pointStockageId: null,
        auteurId: 'u-essai',
      );
      await ouvrirPilotage(tester);

      final bouton = find.byKey(const Key('pilotage-voir-articles'));
      expect(bouton, findsOneWidget);
      expect(
        find.descendant(of: bouton, matching: find.text('Voir les articles')),
        findsOneWidget,
      );
      await tester.ensureVisible(bouton);
      await tester.tap(bouton);
      await tester.pumpAndSettle();
      expect(find.text('Pain'), findsWidgets);
      expect(find.text('Gérer les stocks'), findsOneWidget);
    });

    testWidgets('sans article critique, pas de « Voir les articles »', (
      tester,
    ) async {
      await ouvrirPilotage(tester);
      expect(find.byKey(const Key('pilotage-voir-articles')), findsNothing);
    });

    testWidgets('« Ce que ces chiffres ne disent pas » : les QUATRE réserves '
        'de la vue, toujours, à ses mots — sauf la phrase FAUSSE sur les '
        'recouvrements, remplacée par la vraie (piège 13)', (tester) async {
      await ouvrirPilotage(tester);

      String lu(String cle) => VueBlade.libelle('accueil_pwa.reserves.$cle')!;
      String texte(int i) => tester
          .widgetList<Text>(
            find.descendant(
              of: find.byKey(Key('pilotage-reserve-$i')),
              matching: find.byType(Text),
            ),
          )
          .map((t) => t.data)
          .join(' | ');

      expect(find.text(lu('titre')), findsOneWidget);
      expect(find.text(lu('sous_titre')), findsOneWidget);
      expect(
        texte(0),
        '${lu('is_titre')} | ${lu('module_comptabilite')} | ${lu('is')}',
      );
      expect(
        texte(1),
        '${lu('structure_titre')} | ${lu('module_analytique')} | '
        '${lu('structure')}',
      );
      expect(
        texte(3),
        '${lu('stock_titre')} | ${lu('module_stocks')} | ${lu('stock')}',
      );
      expect(find.byKey(const Key('pilotage-reserve-4')), findsNothing);

      // La troisième : la vue dit « ne sont pas enregistrés » — FAUX sur ce
      // poste depuis le lot 5 (`PaiementsFactureDao`). Ce test épingle la
      // phrase de la vue À LA SOURCE : il rougira le jour où elle sera
      // corrigée, et l'écart devra être retiré.
      expect(lu('recouvrements'), contains('ne sont pas enregistrés'));
      expect(texte(2), contains(lu('module_creances')));
      expect(texte(2), isNot(contains('ne sont pas enregistrés')));
      expect(texte(2), isNot(contains(lu('recouvrements_titre'))));
      expect(texte(2), contains('Les encaissements partiels sont enregistrés'));
    });

    testWidgets('« À traiter » sans droit de lecture sur M6 : la source n’est '
        'ni lue, ni comptée, ni NOMMÉE — comme le serveur', (tester) async {
      await monter(
        tester,
        droits: const {'M1': 'C', 'M10': 'C', 'M11': 'C', 'M13': 'C'},
      );
      await tester.tap(find.text('Pilotage consolidé'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Stocks — '), findsNothing);
      expect(find.textContaining('sous le seuil de'), findsNothing);
      // M11 seule (M3 et M6 non lisibles ; M10 non évaluée, ligne grise).
      expect(
        tester
            .widget<Text>(find.byKey(const Key('pilotage-alertes-sources')))
            .data,
        startsWith('1 source(s) consultée(s) sur 4'),
      );
    });

    Color? couleurValeur(WidgetTester tester, Key carte, String valeurCarte) =>
        tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(carte),
                matching: find.text(valeurCarte),
              ),
            )
            .style
            ?.color;

    testWidgets('« Trésorerie (caisse) » NÉGATIVE s’écrit en ROUGE (la vue : '
        '`MontantFcfa::estNegatif` -> text-red-600), positive en navy', (
      tester,
    ) async {
      await ouvrirPilotage(tester);
      // Positive d'abord : le fond de la caisse ouverte, 1 000 F.
      expect(
        couleurValeur(
          tester,
          const Key('pilotage-kpi-tresorerie'),
          formaterFcfa(1000),
        ),
        AppColors.navy,
      );
    });

    testWidgets('« Trésorerie (caisse) » NÉGATIVE : rouge', (tester) async {
      // Un fond NÉGATIF n'est pas saisissable par `SessionsCaisseDao` : l'état
      // est forcé en base pour éprouver la branche de la vue, que rien
      // d'autre n'atteint sur ce poste.
      await db
          .update(db.sessionsCaisseLocal)
          .write(
            const SessionsCaisseLocalCompanion(
              montantFondCentimes: Value(-500000),
            ),
          );
      await ouvrirPilotage(tester);

      // -5 000 F de fond, aucun encaissement : la bande et la carte le disent.
      final montant = texte(
        tester,
        const Key('pilotage-kpi-tresorerie'),
      ).split(' | ')[1];
      expect(montant, formaterFcfa(-5000));
      expect(
        couleurValeur(tester, const Key('pilotage-kpi-tresorerie'), montant),
        PaletteMaitre.rouge600,
      );
    });

    testWidgets('pendant le calcul de la bande, les cartes « Chiffre '
        'd’affaires encaissé » et « Trésorerie (caisse) » disent '
        '« Chargement… », jamais « Non consulté »', (tester) async {
      final jamais = Completer<ResultatTableauDeBord>();
      await monter(
        tester,
        surcharges: [
          tableauDeBordProvider.overrideWith((ref) => jamais.future),
          ongletTableauDeBordProvider.overrideWithBuild(
            (ref, notifier) => OngletTableauDeBord.pilotage,
          ),
        ],
      );

      expect(
        texte(tester, const Key('pilotage-kpi-ca')),
        "CHIFFRE D'AFFAIRES ENCAISSÉ | Chargement… | ",
      );
      expect(
        texte(tester, const Key('pilotage-kpi-tresorerie')),
        'TRÉSORERIE (CAISSE) | Chargement… | ',
      );
    });

    testWidgets('la comptabilité consolidée, quand elle répond : alerte '
        '« Comptabilité déséquilibrée » aux mots de la vue, brouillons, et '
        '« · avant impôt » sous « Résultat net »', (tester) async {
      // Aucune comptabilité consolidée n'est calculée sur ce poste
      // (`PilotageApi` -> `SourceAbsente`) : la branche ne s'éprouve qu'en
      // substituant la source — le rendu, lui, est celui de l'écran.
      await monter(
        tester,
        surcharges: [
          comptaPilotageProvider.overrideWith(
            (ref) async => const SourceRecue(
              ComptaPilotage(
                annee: 2026,
                chiffreAffaires: '100000.00',
                valeurAjoutee: '50000.00',
                excedentBrut: '20000.00',
                resultatNet: '15000.00',
                tresorerie: '30000.00',
                totalBilan: '200000.00',
                equilibre: false,
                impotNonComptabilise: true,
                brouillons: 2,
                validees: 5,
              ),
            ),
          ),
        ],
      );
      await tester.tap(find.text('Pilotage consolidé'));
      await tester.pumpAndSettle();

      expect(
        texte(tester, const Key('pilotage-alerte-0')),
        'Comptabilité déséquilibrée | '
        "Aucun état financier n'est exploitable tant que l'écart subsiste. "
        'Vérifiez la balance générale.',
      );
      expect(
        texte(tester, const Key('pilotage-alerte-1')),
        '2 écriture(s) en brouillon | '
        "Elles n'entrent dans aucun état et bloqueront la clôture.",
      );
      expect(
        texte(tester, const Key('pilotage-kpi-resultat')),
        'RÉSULTAT NET | 15 000 FCFA | Exercice 2026 · avant impôt',
      );
    });

    /// Le PDF « Pilotage consolidé » (`exporterTableauDeBord`) ne sert plus
    /// que l'onglet du TABLEAU CROISÉ depuis D415 (14/10/2026) : « Exporter »
    /// de la barre du pilotage produit la synthèse de l'accueil. Les gardes du
    /// PDF du pilotage (masse salariale non consultée, aucun bulletin, ce qui
    /// est affiché) passent donc par « Exporter » du tableau croisé, puis la
    /// modale partagée, PDF présélectionné, « Générer & Télécharger ».
    Future<void> exporterEnPdf(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('tdb-onglet-croise')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('croise-exporter')));
      await tester.tap(find.byKey(const Key('croise-exporter')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('export-generer')));
      await tester.pumpAndSettle();
    }

    testWidgets('« Exporter » de la barre du pilotage produit la SYNTHÈSE de '
        'l’accueil (D415) par la modale partagée ; « Annuler » ne produit '
        'rien', (tester) async {
      final syntheses = <EtatRapportAccueil>[];
      await monter(
        tester,
        surcharges: [
          exporterRapportAccueilProvider.overrideWithValue((
            etat,
            format,
          ) async {
            syntheses.add(etat);
            // Le PDF est présélectionné dans la modale partagée.
            expect(format, FormatExport.pdf);
            return 'C:/Documents/synthese.pdf';
          }),
        ],
      );
      await tester.tap(find.text('Pilotage consolidé'));
      await tester.pumpAndSettle();

      expect(texte(tester, const Key('pilotage-btn-exporter')), 'Exporter');
      await tester.ensureVisible(
        find.byKey(const Key('pilotage-btn-exporter')),
      );
      await tester.tap(find.byKey(const Key('pilotage-btn-exporter')));
      await tester.pumpAndSettle();
      final modale = find.byKey(const Key('modale-export-carte'));
      expect(
        find.descendant(of: modale, matching: find.text(titreExportPilotage)),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('export-annuler')));
      await tester.pumpAndSettle();
      expect(syntheses, isEmpty);

      await tester.tap(find.byKey(const Key('pilotage-btn-exporter')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('export-generer')));
      await tester.pumpAndSettle();
      expect(syntheses, hasLength(1));
      expect(syntheses.single.code, TypeRapportAccueil.synthese.code);
    });

    testWidgets('« Exporter » du TABLEAU CROISÉ ouvre la modale PARTAGÉE de la '
        'vue : titre, sous-titre et deux formats ; PDF produit, tableur '
        'refusé avec sa raison, « Annuler » ne produit rien', (tester) async {
      final imprimes = <EtatPilotage>[];
      await monter(
        tester,
        surcharges: [
          exporterEtatPilotagePdfProvider.overrideWithValue((etat) async {
            imprimes.add(etat);
            return 'C:/Documents/pilotage_consolide.pdf';
          }),
        ],
      );
      await tester.tap(find.byKey(const Key('tdb-onglet-croise')));
      await tester.pumpAndSettle();

      Future<void> ouvrir() async {
        await tester.ensureVisible(find.byKey(const Key('croise-exporter')));
        await tester.tap(find.byKey(const Key('croise-exporter')));
        await tester.pumpAndSettle();
      }

      // 1. « Annuler » : la modale se ferme, rien n'est produit.
      await ouvrir();
      final modale = find.byKey(const Key('modale-export-carte'));
      expect(modale, findsOneWidget);
      expect(
        find.descendant(of: modale, matching: find.text(titreExportPilotage)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: modale, matching: find.text(noteExportPilotage)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: modale,
          matching: find.text(tableurPilotageNonProduit),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('export-annuler')));
      await tester.pumpAndSettle();
      expect(imprimes, isEmpty);

      // 2. Tableur : refusé, DIT, rien n'est produit.
      await ouvrir();
      await tester.tap(find.byKey(const Key('export-format-excel')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('export-generer')));
      await tester.pumpAndSettle();
      expect(imprimes, isEmpty);
      expect(
        find.byKey(const Key('pilotage-export-tableur-absent')),
        findsOneWidget,
      );

      // 3. PDF (présélectionné, comme `$formatExport = 'pdf'`) : le document.
      await ouvrir();
      await tester.tap(find.byKey(const Key('export-generer')));
      await tester.pumpAndSettle();
      expect(imprimes, hasLength(1));
      expect(imprimes.single.periode, 'Du 01/10/2026 au 31/10/2026');
      // L'issue est DITE par le toast commun (14/10/2026).
      expect(
        tester.widget<Text>(find.byKey(const Key('pilotage-export-fait'))).data,
        'Export enregistré : pilotage_consolide.pdf',
      );
    });

    Future<EtatPilotage> imprimer(
      WidgetTester tester, {
      Map<String, String>? droits,
      DateTime? maintenant,
    }) async {
      EtatPilotage? imprime;
      await monter(
        tester,
        droits:
            droits ??
            const {'M1': 'C', 'M6': 'C', 'M10': 'C', 'M11': 'C', 'M13': 'C'},
        maintenant: maintenant,
        surcharges: [
          exporterEtatPilotagePdfProvider.overrideWithValue((etat) async {
            imprime = etat;
            return 'C:/Documents/pilotage_consolide.pdf';
          }),
        ],
      );
      await tester.tap(find.text('Pilotage consolidé'));
      await tester.pumpAndSettle();
      await exporterEnPdf(tester);
      return imprime!;
    }

    testWidgets('PDF, droit M13 absent : « Masse salariale non consultée à '
        'l’édition » et « — », jamais un montant', (tester) async {
      final etat = await imprimer(
        tester,
        droits: const {'M1': 'C', 'M6': 'C', 'M10': 'C', 'M11': 'C'},
      );

      expect(
        etat.lignes,
        contains(
          equals(['RÉSERVE', 'Masse salariale non consultée à l’édition', '—']),
        ),
      );
      expect(
        etat.lignes.where((l) => l[1].startsWith('Masse salariale (')),
        isEmpty,
      );
      expect(
        etat.lignes.where(
          (l) => l[1].startsWith('Masse salariale') && l[2] == '0 FCFA',
        ),
        isEmpty,
      );
    });

    testWidgets('PDF, aucun bulletin ce mois-ci : « Aucun bulletin établi ce '
        'mois-ci », pas « 0 FCFA »', (tester) async {
      final etat = await imprimer(
        tester,
        maintenant: DateTime(2026, 11, 15, 9),
      );

      expect(
        etat.lignes,
        contains(
          equals([
            'Personnel & paie',
            'Masse salariale',
            'Aucun bulletin établi ce mois-ci',
          ]),
        ),
      );
      expect(
        etat.lignes.where(
          (l) => l[1].startsWith('Masse salariale') && l[2] == '0 FCFA',
        ),
        isEmpty,
      );
    });

    testWidgets('le PDF porte ce qui est AFFICHÉ : masse salariale, dépense '
        'courante, la fenêtre — et PAS « toutes périodes »', (tester) async {
      EtatPilotage? imprime;
      await monter(
        tester,
        surcharges: [
          exporterEtatPilotagePdfProvider.overrideWithValue((etat) async {
            imprime = etat;
            return 'C:/Documents/pilotage_consolide.pdf';
          }),
        ],
      );
      await tester.tap(find.text('Pilotage consolidé'));
      await tester.pumpAndSettle();

      // Les cartes sont relues À L'ÉCRAN du pilotage AVANT l'export : le PDF
      // part de l'onglet du tableau croisé depuis D415.
      final affichees = {
        for (final cle in const [
          'pilotage-kpi-ca',
          'pilotage-kpi-tresorerie',
          'pilotage-kpi-stock',
        ])
          cle: texte(tester, Key(cle)).split(' | ')[1],
      };
      String carte(String cle) => affichees[cle]!;

      await exporterEnPdf(tester);

      final etat = imprime!;
      expect(etat.periode, 'Du 01/10/2026 au 31/10/2026');
      // La carte affichée, au mot près (D282) — plus le « — » du 10/10.
      expect(etat.kpis['Créances clients'], '54 500 FCFA');
      // R1 : le papier dit la valeur des cartes « Chiffre d'affaires
      // encaissé » et « Trésorerie (caisse) », au caractère près — relue À
      // L'ÉCRAN, et ancrée sur le montant attendu (fond de la caisse ouverte).
      expect(
        etat.kpis["Chiffre d'affaires encaissé"],
        carte('pilotage-kpi-ca'),
      );
      expect(etat.kpis["Chiffre d'affaires encaissé"], formaterFcfa(0));
      expect(
        etat.kpis['Trésorerie (caisse)'],
        carte('pilotage-kpi-tresorerie'),
      );
      expect(etat.kpis['Trésorerie (caisse)'], formaterFcfa(1000));
      // Les anciennes clés M10 ne sont plus au document.
      expect(etat.kpis.containsKey('Chiffre d’affaires'), isFalse);
      expect(etat.kpis.containsKey('Trésorerie'), isFalse);
      expect(etat.kpis['Résultat net'], '—');
      // « Valeur du stock » : la carte affichée, lue de la BANDE comme elle,
      // ancrée sur le montant (riz 12 505 F ; le sel n'a aucun coût) — et ce
      // qu'elle ne comprend pas part avec le papier, en réserve.
      expect(etat.kpis['Valeur du stock'], carte('pilotage-kpi-stock'));
      expect(etat.kpis['Valeur du stock'], formaterFcfa(12505));
      expect(
        etat.lignes,
        contains(
          equals([
            'RÉSERVE',
            'Valeur du stock hors 1 article(s) sans coût',
            '',
          ]),
        ),
      );
      // L'ancienne ligne lue en M6 a disparu : un seul montant pour la même
      // grandeur sur le document.
      expect(
        etat.lignes.where((l) => l[1] == 'Valeur au coût moyen pondéré'),
        isEmpty,
      );
      // La réserve du document porte la raison datée de la carte.
      expect(
        etat.lignes.where(
          (l) =>
              l[0] == 'RÉSERVE' &&
              l[1].startsWith('Comptabilité non consultée à l’édition : ') &&
              l[1].contains('constaté le 13/10/2026'),
        ),
        hasLength(1),
      );
      expect(
        etat.lignes,
        containsAll([
          [
            'Personnel & paie',
            'Masse salariale (brut, 1 salarié(s))',
            '150 000 FCFA',
          ],
          ['Dépense courante', 'Total décaissé', '8 000 FCFA'],
          ['Dépense courante', 'Marché', '5 000 FCFA'],
          ['Dépense courante', 'Services', '3 000 FCFA'],
        ]),
      );
      // Chaque cellule ajoutée tient dans Latin-1 : les polices intégrées du
      // format n'ont rien au-delà, et un caractère perdu disparaît du papier
      // sans erreur (« Chiffre d'affaires », PA-111).
      for (final cellule in [
        ...etat.lignes.expand((l) => l),
        ...etat.kpis.values,
      ]) {
        expect(
          caracteresNonImprimables(texteTicket(cellule)),
          isEmpty,
          reason: cellule,
        );
      }
      // Et le document est réellement composé (octets PDF, pas une promesse).
      final octets = await etat.pdf();
      expect(String.fromCharCodes(octets.take(5)), '%PDF-');
      // La rubrique des cartes de la bande, en tête du document
      // (`accueil_pwa.etat_consolide.rubrique_indicateurs`), imprimable.
      expect(EtatPilotage.rubriqueIndicateurs, 'Indicateurs consolidés');
      expect(
        caracteresNonImprimables(texteTicket(EtatPilotage.rubriqueIndicateurs)),
        isEmpty,
      );
    });
  });

  // =========================================================================
  // LOT 2 de `INSTRUCTION.txt` (12/10/2026) — la « Vue d'exploitation » suit
  // la vue d'accueil, bloc par bloc. Chaîne réelle : base -> DAO -> écran.
  group('La vue d’exploitation : les blocs de la vue, dans son ordre', () {
    /// Deux articles AU SEUIL OU DESSOUS, créés dans le désordre alphabétique
    /// (le serveur trie par libellé), à côté du riz et du sel du montage.
    Future<void> ajouterCritiques() async {
      final stocks = StocksDao(db);
      final point = (await stocks.points()).first;
      for (final (id, libelle) in const [
        ('huile', 'Huile'),
        ('allumettes', 'Allumettes'),
      ]) {
        await stocks.creerArticle(
          id: id,
          libelle: libelle,
          categorie: null,
          uniteMesure: 'bidon',
          seuilCentiemes: 300,
          suivi: SuiviArticle.permanent,
          pointStockageId: point.id,
          auteurId: 'u-essai',
          ouverture: (centiemes: 200, coutDixMilliemes: 10000000),
        );
      }
    }

    String route(WidgetTester tester) => GoRouter.of(
      tester.element(find.byType(EcranTableauDeBord).first),
    ).routeInformationProvider.value.uri.path;

    Text texteDe(WidgetTester tester, Key cle) =>
        tester.widget<Text>(find.byKey(cle));

    testWidgets('l’en-tête est celui de la vue : titre SANS icône (même x que '
        'le sous-titre), sous-titre, trois onglets, période À DROITE des '
        'onglets et alignée en bas, « Actualiser » et « Exporter »', (
      tester,
    ) async {
      await monter(tester);

      final titre = find.byKey(const Key('tdb-titre'));
      expect(texteDe(tester, const Key('tdb-titre')).data, 'Tableau de bord');
      expect(
        texteDe(tester, const Key('tdb-sous-titre')).data,
        'Vision consolidée et en temps réel de la performance de chaque '
        'activité',
      );
      // Aucune icône devant le titre : la vue écrit un `<h1>` nu, et son
      // relevé place titre et sous-titre au même x.
      expect(
        tester.getTopLeft(titre).dx,
        tester.getTopLeft(find.byKey(const Key('tdb-sous-titre'))).dx,
      );
      expect(find.byIcon(Icons.insights_outlined), findsNothing);
      // Les trois onglets, sous le sous-titre, dans l'ordre de la vue.
      final onglets = [
        for (final o in OngletTableauDeBord.values)
          tester.getTopLeft(find.byKey(Key('tdb-onglet-${o.name}'))),
      ];
      expect(onglets[0].dy, greaterThan(tester.getTopLeft(titre).dy));
      // Ordre de LECTURE (la police de test, plus large qu'Inter, peut faire
      // passer un onglet à la ligne : `flex` de la vue rétrécit de même).
      bool avant(Offset a, Offset b) =>
          a.dy < b.dy || (a.dy == b.dy && a.dx < b.dx);
      expect(avant(onglets[0], onglets[1]), isTrue);
      expect(avant(onglets[1], onglets[2]), isTrue);
      // `lg:self-end` : la période est À DROITE du dernier onglet et son bas
      // est celui de la rangée d'onglets.
      final periode = find.byKey(const Key('tdb-libelle-periode'));
      expect(
        tester.getTopLeft(periode).dx,
        greaterThan(
          tester.getTopRight(find.byKey(const Key('tdb-onglet-croise'))).dx,
        ),
      );
      expect(
        tester.getBottomLeft(periode).dy,
        moreOrLessEquals(
          tester.getBottomLeft(find.byKey(const Key('tdb-onglet-croise'))).dy,
          epsilon: 1,
        ),
      );
      // `lg:ml-auto` : « Exporter » est le dernier élément, au bord droit.
      final exporter = find.byKey(const Key('tdb-exporter'));
      expect(
        tester.getTopLeft(exporter).dx,
        greaterThan(
          tester.getTopRight(find.byKey(const Key('tdb-actualiser'))).dx,
        ),
      );
      expect(
        find.descendant(of: exporter, matching: find.text('Exporter')),
        findsOneWidget,
      );
      // Le style de l'onglet actif : fond navy, texte blanc, `rounded-lg`.
      final actif = tester.widget<Container>(
        find
            .descendant(
              of: find.byKey(const Key('tdb-onglet-exploitation')),
              matching: find.byType(Container),
            )
            .first,
      );
      final deco = actif.decoration! as BoxDecoration;
      expect(deco.color, AppColors.navy);
      expect(deco.borderRadius, BorderRadius.circular(AppRadius.roundedLg));
    });

    testWidgets('les blocs sont dans l’ORDRE de la vue : accès rapides, '
        'bande, alertes, récapitulatif, graphiques (CA et anneau sur la même '
        'rangée), ventes par activité, chambres, consultation', (tester) async {
      await ajouterCritiques();
      await monter(tester);

      double y(String cle) => tester.getTopLeft(find.byKey(Key(cle))).dy;
      final ordre = [
        'tdb-acces-reservation',
        'tdb-chiffre_affaires_encaisse',
        'tdb-alertes-stock',
        'tdb-recap',
        'tdb-carte-ca',
        'tdb-carte-ventes-activite',
        'tdb-chambres',
        'tdb-secours',
      ];
      final ys = [for (final c in ordre) y(c)];
      expect(ys, orderedEquals([...ys]..sort()));
      expect(ys.toSet(), hasLength(ordre.length), reason: 'aucun ex aequo');
      // `xl:grid-cols-3` (fenêtre de 1 600 px) : l'anneau est à DROITE du
      // chiffre d'affaires, sur la même rangée, et deux fois moins large.
      expect(y('tdb-carte-repartition'), y('tdb-carte-ca'));
      final ca = tester.getSize(find.byKey(const Key('tdb-carte-ca'))).width;
      final anneau = tester
          .getSize(find.byKey(const Key('tdb-carte-repartition')))
          .width;
      // 2 colonnes + 1 gouttière contre 1 colonne : (2c + 20) / c.
      expect(ca, moreOrLessEquals(2 * anneau + AppSpacing.mdPlus, epsilon: 1));
    });

    testWidgets('les cinq accès rapides : libellés AU MOT, ordre, tracés et '
        'couleurs de la vue (fond = couleur à l’alpha hexadécimal 15)', (
      tester,
    ) async {
      await monter(
        tester,
        droits: const {
          'M1': 'C',
          'M3': 'C',
          'M6': 'L',
          'M10': 'L',
          'M11': 'C',
          'M14': 'L',
        },
      );

      const attendus = [
        ('reservation', 'Nouvelle réservation', AppColors.navy),
        ('client', 'Ajouter un client', AppColors.info),
        ('stocks', 'Stocks critiques', AppColors.alerte),
        ('rapport', 'Générer un rapport', AppColors.gris),
        ('depense', 'Nouvelle dépense', AppColors.gold),
      ];
      double? xPrecedent;
      for (final (cle, libelle, couleur) in attendus) {
        final bouton = find.byKey(Key('tdb-acces-$cle'));
        expect(
          find.descendant(of: bouton, matching: find.text(libelle)),
          findsOneWidget,
        );
        final x = tester.getTopLeft(bouton).dx;
        if (xPrecedent != null) expect(x, greaterThan(xPrecedent));
        xPrecedent = x;
        final pastille = tester.widget<Container>(
          find.byKey(Key('tdb-acces-pastille-$cle')),
        );
        expect(
          (pastille.decoration! as BoxDecoration).color,
          couleur.withValues(alpha: 0x15 / 0xFF),
        );
        final icone = tester.widget<IconeTrace>(
          find.descendant(
            of: find.byKey(Key('tdb-acces-pastille-$cle')),
            matching: find.byType(IconeTrace),
          ),
        );
        expect(icone.couleur, couleur);
        expect(icone.taille, 16);
      }
    });

    testWidgets('chaque accès rapide suit le droit RÉEL de son module : '
        'masqué, jamais grisé (M1 et M3 en écriture, M6, M14 et M10 en '
        'lecture)', (tester) async {
      await monter(
        tester,
        droits: const {
          'M1': 'L',
          'M3': 'L',
          'M6': '-',
          'M10': '-',
          'M11': 'C',
          'M14': '-',
        },
      );
      for (final cle in ['reservation', 'client', 'stocks', 'rapport']) {
        expect(find.byKey(Key('tdb-acces-$cle')), findsNothing, reason: cle);
      }
      expect(find.byKey(const Key('tdb-acces-depense')), findsNothing);
    });

    testWidgets('les gestes : « Stocks critiques » ouvre la modale de la vue '
        '(articles triés, stock en rouge) et « Gérer les stocks » mène à '
        '/stocks ; « Nouvelle dépense » mène à /depenses ; « Générer un '
        'rapport » DIT qu’il n’est pas porté', (tester) async {
      await ajouterCritiques();
      await monter(
        tester,
        droits: const {
          'M1': 'C',
          'M6': 'L',
          'M10': 'L',
          'M11': 'C',
          'M14': 'L',
        },
      );

      await tester.tap(find.byKey(const Key('tdb-acces-stocks')));
      await tester.pumpAndSettle();
      final modale = find.byKey(const Key('tdb-modale-stocks-critiques'));
      expect(
        find.descendant(
          of: modale,
          matching: find.text("Articles sous le seuil d'alerte"),
        ),
        findsOneWidget,
      );
      // En-têtes rendus en CAPITALES, dans l'ordre de la vue.
      for (final t in ['ARTICLE', 'STOCK THÉORIQUE', "SEUIL D'ALERTE"]) {
        expect(
          find.descendant(of: modale, matching: find.text(t)),
          findsOneWidget,
        );
      }
      // Triés par libellé, comme `orderBy('articles.libelle')`.
      final allumettes = tester.getTopLeft(
        find.descendant(of: modale, matching: find.text('Allumettes')),
      );
      final huile = tester.getTopLeft(
        find.descendant(of: modale, matching: find.text('Huile')),
      );
      expect(allumettes.dy, lessThan(huile.dy));
      // `{{ $article->stock }} {{ $article->unite_mesure }}`, en rouge.
      final stock = tester.widget<Text>(
        find.descendant(of: modale, matching: find.text('2.00 bidon')).first,
      );
      expect(stock.style?.color, PaletteMaitre.rouge600);
      expect(
        find.descendant(of: modale, matching: find.text('3.00 bidon')),
        findsNWidgets(2),
      );
      await tester.tap(find.byKey(const Key('tdb-stocks-critiques-gerer')));
      await tester.pumpAndSettle();
      expect(route(tester), '/stocks');
    });

    testWidgets('« Nouvelle dépense » mène à /depenses, « Générer un rapport » '
        'ouvre la modale des six rapports, « Nouvelle réservation » la modale '
        'RAPIDE de la vue (lot C, 14/10/2026)', (tester) async {
      await monter(
        tester,
        droits: const {'M1': 'C', 'M10': 'L', 'M11': 'C', 'M14': 'L'},
      );

      await tester.tap(find.byKey(const Key('tdb-acces-rapport')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('tdb-modale-rapport')), findsOneWidget);
      expect(
        find.textContaining('ne sont pas encore produits sur ce poste'),
        findsNothing,
      );
      await tester.tap(find.byKey(const Key('tdb-rapport-annuler')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('tdb-acces-reservation')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('tdb-modale-reservation-rapide')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('tdb-resa-annuler')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('tdb-acces-depense')));
      await tester.pumpAndSettle();
      expect(route(tester), '/depenses');
    });

    testWidgets('« Ajouter un client » ÉCRIT le client (registre M3) et le '
        'dit avec la phrase de la vue', (tester) async {
      await monter(tester, droits: const {'M1': 'C', 'M3': 'C', 'M11': 'C'});

      await tester.tap(find.byKey(const Key('tdb-acces-client')));
      await tester.pumpAndSettle();
      // La modale « Ajouter un client » de la VUE (lot C, 14/10/2026).
      expect(find.byKey(const Key('tdb-modale-client')), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('tdb-client-nom')),
        'SOSSOU Paul',
      );
      await tester.enterText(
        find.byKey(const Key('tdb-client-telephone')),
        '+229 01 97 00 00 02',
      );
      await tester.tap(find.byKey(const Key('tdb-client-valider')));
      await tester.pumpAndSettle();

      final clients = await db.select(db.clientsLocal).get();
      expect(clients.map((c) => c.nom), contains('SOSSOU Paul'));
      expect(
        texteDe(tester, const Key('tdb-client-ajoute')).data,
        'Client « SOSSOU Paul » ajouté.',
      );
    });

    testWidgets('le bandeau rouge : titre et liste de la vue (le compte de la '
        'MÊME liste, triée), couleurs red-50 / red-200 ; rien sans article au '
        'seuil, rien sans droit M6', (tester) async {
      await ajouterCritiques();
      await monter(tester);
      expect(
        texteDe(tester, const Key('tdb-alertes-stock-titre')).data,
        '⚠ Alertes critiques de stock (2)',
      );
      expect(
        texteDe(tester, const Key('tdb-alertes-stock-liste')).data,
        'Allumettes, Huile',
      );
      final bandeau = tester.widget<Container>(
        find.byKey(const Key('tdb-alertes-stock')),
      );
      final deco = bandeau.decoration! as BoxDecoration;
      expect(deco.color, PaletteMaitre.rouge50);
      expect((deco.border! as Border).top.color, PaletteMaitre.rouge200);
      expect(
        texteDe(tester, const Key('tdb-alertes-stock-titre')).style?.color,
        PaletteMaitre.rouge800,
      );
      // « Voir » ouvre la même modale.
      await tester.tap(find.byKey(const Key('tdb-alertes-stock-voir')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('tdb-modale-stocks-critiques')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('tdb-stocks-critiques-annuler')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('tdb-modale-stocks-critiques')),
        findsNothing,
      );
    });

    testWidgets('le bandeau rouge exige le droit de lecture sur M6 : sans '
        'lui, rien (la vue : `peutLireStocks && …`)', (tester) async {
      await ajouterCritiques();
      await monter(
        tester,
        droits: const {'M1': 'C', 'M10': 'C', 'M11': 'C', 'M13': 'C'},
      );
      expect(find.byKey(const Key('tdb-alertes-stock')), findsNothing);
      expect(find.byKey(const Key('tdb-acces-stocks')), findsNothing);
    });

    testWidgets('le bandeau vérifie LUI-MÊME le droit M6, avant de lire : '
        'une source qui rendrait des articles sans le vérifier ne passe pas '
        '(la vue : « le droit se vérifie avant le calcul »)', (tester) async {
      const critique = LigneStock(
        id: 'x',
        libelle: 'Huile',
        categorie: null,
        uniteMesure: 'bidon',
        seuilAlerte: '3.00',
        coutMoyenPondere: '0',
        stock: '1.00',
        valeurStock: '0',
        portee: 'tous',
        suivi: SuiviArticle.permanent,
        pointStockageId: null,
        pointLibelle: null,
        prixAchat: null,
        deriveCmp: null,
      );
      await monter(
        tester,
        droits: const {'M1': 'C', 'M11': 'C'},
        surcharges: [
          stockPilotageProvider.overrideWith(
            (ref) async => const StockRecu(
              EtatStock(
                kpis: KpisStock(
                  references: 1,
                  sousSeuil: 1,
                  rupture: 0,
                  valeurStock: '0',
                  mouvements30Jours: 0,
                  permanents: 1,
                  journaliers: 0,
                  sansValorisation: 0,
                ),
                lignes: [critique],
                arreteAu: '2026-10-10',
              ),
            ),
          ),
        ],
      );
      expect(find.byKey(const Key('tdb-alertes-stock')), findsNothing);
    });

    testWidgets('« Actualiser » relit les sources : un article passé au seuil '
        'APRÈS l’ouverture apparaît au clic (avant : aucun bandeau, et pas de '
        'bande verte « stock sain »)', (tester) async {
      await monter(tester);
      expect(find.byKey(const Key('tdb-alertes-stock')), findsNothing);

      await tester.runAsync(ajouterCritiques);
      await tester.tap(find.byKey(const Key('tdb-actualiser')));
      await tester.pumpAndSettle();
      expect(
        texteDe(tester, const Key('tdb-alertes-stock-titre')).data,
        '⚠ Alertes critiques de stock (2)',
      );
    });

    testWidgets('le récapitulatif de la journée (05/10) : arrivées, départs, '
        'nouvelles réservations et encaissé du jour, comme '
        'Accueil::recapDuJour — titre « lundi 5 octobre » ; une vente '
        'validée SANS MODE ce jour-là n’est pas encaissée', (tester) async {
      // Un panier clôturé le 05/10 SANS mode de règlement — une ligne écrite
      // par une version antérieure du poste (`PanierDao.cloturer` refuse
      // désormais le mode absent). Rien ne dit que l'argent est entré :
      // « Encaissé aujourd'hui » ne le compte pas (13/10/2026).
      await db
          .into(db.paniersLocal)
          .insert(
            PaniersLocalCompanion.insert(
              id: 'p-sans-mode',
              typeVente: 'comptant',
              pointVente: const Value('Bar principal'),
              statut: const Value('cloture'),
              ouvertLe: Value(DateTime(2026, 10, 5, 17)),
              clotureLe: Value(DateTime(2026, 10, 5, 18)),
              montantCloture: const Value(7000),
            ),
          );
      await monter(tester, maintenant: DateTime(2026, 10, 5, 21));

      expect(
        texteDe(tester, const Key('tdb-recap-titre')).data,
        '📋 Récapitulatif de la journée — lundi 5 octobre',
      );
      // r1 part le 05/10 ; personne n'arrive ; rien n'a été créé ce jour-là.
      expect(texteDe(tester, const Key('tdb-recap-arrivees-valeur')).data, '0');
      expect(texteDe(tester, const Key('tdb-recap-departs-valeur')).data, '1');
      expect(
        texteDe(tester, const Key('tdb-recap-nouvelles-valeur')).data,
        '0',
      );
      // Deux bières en espèces le 05/10 à 19 h : 2 000 F, en or. Les
      // 7 000 F de la vente sans mode n'y sont pas.
      final encaisse = texteDe(tester, const Key('tdb-recap-encaisse-valeur'));
      expect(encaisse.data, '2 000 FCFA');
      expect(encaisse.style?.color, AppColors.gold);
      // Les quatre libellés de la vue, AU MOT, chacun sous SON compteur.
      for (final (cle, libelle) in const [
        ('arrivees', 'Arrivées prévues'),
        ('departs', 'Départs prévus'),
        ('nouvelles', 'Nouvelles réservations'),
        ('encaisse', "Encaissé aujourd'hui"),
      ]) {
        expect(
          find.descendant(
            of: find.byKey(Key('tdb-recap-$cle')),
            matching: find.text(libelle),
          ),
          findsOneWidget,
          reason: libelle,
        );
      }
      final fond = tester.widget<Container>(find.byKey(const Key('tdb-recap')));
      expect((fond.decoration! as BoxDecoration).color, AppColors.navy);
      expect(
        find.descendant(
          of: find.byKey(const Key('tdb-recap')),
          matching: find.text(
            'Ventes encaissées du jour — les acomptes de réservation ne '
            'portent aucune date de règlement au schéma.',
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('le récapitulatif exige M11 ET M1 (la vue), et ne dit rien '
        'avant d’avoir lu', (tester) async {
      await monter(tester, droits: const {'M6': 'C', 'M11': 'C'});
      expect(find.byKey(const Key('tdb-recap')), findsNothing);
    });

    testWidgets('« Chambres disponibles » : les unités libres CETTE NUIT, '
        'commercialisables, triées par numéro ; cinq en-têtes en CAPITALES ; '
        '« Effectuer Check-in » DIT que le geste n’existe pas sur ce poste', (
      tester,
    ) async {
      // Le 05/10 : r1 part ce jour-là (la nuit est libre), r4 arrive le 08.
      await monter(tester, maintenant: DateTime(2026, 10, 5, 10));

      final table = find.byKey(const Key('tdb-chambres'));
      // L'en-tête de la carte : titre et lien de la vue, au mot.
      expect(
        find.descendant(of: table, matching: find.text('Chambres disponibles')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('tdb-chambres-voir-tout')),
          matching: find.text('Voir tout →'),
        ),
        findsOneWidget,
      );
      for (final t in [
        'CODE',
        'UNITÉ',
        'CATÉGORIE',
        'TARIF / NUIT',
        'ACTIONS',
      ]) {
        expect(
          find.descendant(of: table, matching: find.text(t)),
          findsOneWidget,
        );
      }
      expect(find.byKey(const Key('tdb-chambre-u-1')), findsOneWidget);
      expect(find.byKey(const Key('tdb-chambre-u-2')), findsOneWidget);
      // Hors service : jamais proposée.
      expect(find.byKey(const Key('tdb-chambre-u-3')), findsNothing);
      expect(
        tester.getTopLeft(find.byKey(const Key('tdb-chambre-u-1'))).dy,
        lessThan(
          tester.getTopLeft(find.byKey(const Key('tdb-chambre-u-2'))).dy,
        ),
      );
      final tarif = texteDe(tester, const Key('tdb-chambre-tarif-u-1'));
      expect(tarif.data, '28 000 FCFA');
      expect(tarif.style?.color, AppColors.gold);

      await tester.ensureVisible(find.byKey(const Key('tdb-checkin-u-1')));
      await tester.tap(find.byKey(const Key('tdb-checkin-u-1')));
      await tester.pumpAndSettle();
      // Le check-in d'une chambre est PORTÉ depuis le lot C (14/10/2026,
      // `SejourDao`) : la modale de la vue s'ouvre, plus aucun « ne peut pas
      // être enregistré sur ce poste ».
      expect(
        find.byKey(const Key('tdb-modale-checkin-chambre')),
        findsOneWidget,
      );
      expect(
        find.textContaining('ne peut pas être enregistré sur ce poste'),
        findsNothing,
      );
    });

    testWidgets('« Chambres disponibles » le 10/10 : toutes prises ou hors '
        'service — la phrase de la vue ; en lecture seule, un tiret à la '
        'place du bouton', (tester) async {
      await monter(tester);
      expect(
        texteDe(tester, const Key('tdb-chambres-vide')).data,
        'Aucune chambre disponible actuellement.',
      );
      expect(find.byKey(const Key('tdb-chambres-illisible')), findsNothing);
    });

    testWidgets('« Chambres disponibles » quand la lecture du PARC échoue : le '
        'tableau le DIT (la phrase de la vue pour une donnée non lue) — ni '
        'un blanc, ni « aucune chambre », ni l’exception', (tester) async {
      await monter(
        tester,
        maintenant: DateTime(2026, 10, 5, 10),
        surcharges: [
          parcPilotageProvider.overrideWith(
            (ref) async => throw StateError('SQLITE_IOERR interne'),
          ),
        ],
      );
      final table = find.byKey(const Key('tdb-chambres'));
      expect(
        find.descendant(
          of: table,
          matching: find.text(
            "Cette donnée n'a pas pu être lue. Ce n'est pas un zéro : rien "
            "n'a été mesuré.",
          ),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('tdb-chambres-illisible')), findsOneWidget);
      expect(find.byKey(const Key('tdb-chambres-vide')), findsNothing);
      expect(find.byKey(const Key('tdb-chambre-u-1')), findsNothing);
      expect(find.textContaining('SQLITE_IOERR'), findsNothing);
    });

    // L'autre moitié de la condition (recontrôle de l'accueil, 13/10/2026) :
    // le PARC est lu, ce sont les RÉSERVATIONS qui échouent. Sans elles, une
    // chambre déjà prise se présenterait libre — la phrase doit le dire, pas
    // la liste. Mutation éprouvée : retirer `|| lecturesReservations.hasError`
    // de `TableChambresDisponibles` fait rougir ce cas, et lui seul des six
    // cas « Chambres disponibles » (mesuré le 13/10/2026 : la phrase n'est
    // plus rendue).
    testWidgets('« Chambres disponibles » quand la lecture des RÉSERVATIONS '
        'échoue et que le parc est lu : la même phrase de la vue — jamais une '
        'liste qui croirait libres des chambres prises', (tester) async {
      await monter(
        tester,
        maintenant: DateTime(2026, 10, 5, 10),
        surcharges: [
          reservationsPilotageProvider.overrideWith(
            (ref) async => throw StateError('SQLITE_IOERR interne'),
          ),
        ],
      );
      final table = find.byKey(const Key('tdb-chambres'));
      expect(
        find.descendant(
          of: table,
          matching: find.text(
            "Cette donnée n'a pas pu être lue. Ce n'est pas un zéro : rien "
            "n'a été mesuré.",
          ),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('tdb-chambres-illisible')), findsOneWidget);
      expect(find.byKey(const Key('tdb-chambres-vide')), findsNothing);
      // Le 05/10, u-1 et u-2 seraient listées si le parc seul décidait.
      expect(find.byKey(const Key('tdb-chambre-u-1')), findsNothing);
      expect(find.byKey(const Key('tdb-chambre-u-2')), findsNothing);
      expect(find.textContaining('SQLITE_IOERR'), findsNothing);
    });

    testWidgets('« Chambres disponibles » : le tri par numéro suit la '
        'collation du serveur, INSENSIBLE à la casse (« bng-015 » entre '
        '« BNG-01 » et « BNG-02 »)', (tester) async {
      await db
          .into(db.unitesHebergementLocal)
          .insert(
            UnitesHebergementLocalCompanion.insert(
              id: 'u-4',
              categorieId: 'cat-1',
              numero: 'bng-015',
              statut: 'libre',
            ),
          );
      await monter(tester, maintenant: DateTime(2026, 10, 5, 10));
      double y(String id) =>
          tester.getTopLeft(find.byKey(Key('tdb-chambre-$id'))).dy;
      // Ordre binaire : BNG-01, BNG-02, bng-015 (minuscules après). Ordre
      // MySQL (`utf8mb4_unicode_ci`) : BNG-01, bng-015, BNG-02.
      expect(y('u-1'), lessThan(y('u-4')));
      expect(y('u-4'), lessThan(y('u-2')));
    });

    testWidgets('« Chambres disponibles » en lecture seule (M1 = L) : un '
        'tiret à la place du bouton, comme la vue', (tester) async {
      await monter(
        tester,
        droits: const {'M1': 'L', 'M11': 'C'},
        maintenant: DateTime(2026, 10, 5, 10),
      );
      expect(find.byKey(const Key('tdb-checkin-u-1')), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const Key('tdb-chambre-u-1')),
          matching: find.text('—'),
        ),
        findsNWidgets(2),
      );
    });

    testWidgets('« Consultation de secours » : les écrans du rôle, dans '
        'l’ordre de la vue, niveau dit ; Comptabilité DIT qu’elle est à '
        'venir ; « Ouvrir l’écran → » navigue', (tester) async {
      await monter(
        tester,
        droits: const {'M1': 'C', 'M6': 'L', 'M10': 'C', 'M11': 'C'},
      );

      // Le titre et le sous-titre de la carte, au mot.
      final secours = find.byKey(const Key('tdb-secours'));
      for (final t in [
        'Consultation de secours',
        'Les écrans auxquels votre rôle donne accès.',
      ]) {
        expect(
          find.descendant(of: secours, matching: find.text(t)),
          findsOneWidget,
          reason: t,
        );
      }
      // M11, M1, M6, M2, M3, M14, M10 : seuls ceux qu'ouvrent les droits.
      final cartes = ['M11', 'M1', 'M6', 'M10'];
      double? yPrecedent;
      double? xPrecedent;
      for (final m in cartes) {
        final carte = find.byKey(Key('tdb-secours-$m'));
        expect(carte, findsOneWidget, reason: m);
        final p = tester.getTopLeft(carte);
        if (yPrecedent != null) {
          expect(
            p.dy > yPrecedent || (p.dy == yPrecedent && p.dx > xPrecedent!),
            isTrue,
            reason: m,
          );
        }
        yPrecedent = p.dy;
        xPrecedent = p.dx;
      }
      for (final m in ['M2', 'M3', 'M14']) {
        expect(find.byKey(Key('tdb-secours-$m')), findsNothing, reason: m);
      }
      expect(
        texteDe(tester, const Key('tdb-secours-niveau-M6')).data,
        'Lecture seule',
      );
      expect(
        texteDe(tester, const Key('tdb-secours-niveau-M1')).data,
        "Accès complet dans l'application",
      );
      // Comptabilité a son écran depuis le 14/10/2026 (D417, D424) : « Ouvrir
      // l'écran → », plus « Écran de consultation à venir ».
      expect(find.byKey(const Key('tdb-secours-a-venir-M10')), findsNothing);
      expect(find.byKey(const Key('tdb-secours-ouvrir-M10')), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const Key('tdb-secours-ouvrir-M6')),
      );
      await tester.tap(find.byKey(const Key('tdb-secours-ouvrir-M6')));
      await tester.pumpAndSettle();
      expect(route(tester), '/stocks');
    });

    testWidgets('les graphiques portent les mots de la vue : titres, '
        'sous-titres et ligne de mesure réelle ; les anciens titres '
        '« Répartition par activité » et « Montant par activité » ont '
        'disparu', (tester) async {
      await monter(tester);

      for (final t in [
        "Chiffre d'affaires vs Dépenses",
        'Basé sur les encaissements et dépenses enregistrés',
        'Réservations par activité',
        'Sur la période sélectionnée',
        'Ventilation des montants facturés par activité.',
        '📊 Statistiques de ventes par activité',
        'Nombre de réservations incluant chaque service, période '
            'sélectionnée',
        "Montants facturés par activité, même mesure que l'anneau "
            'ci-dessus.',
      ]) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      expect(find.text('Répartition par activité'), findsNothing);
      expect(find.text('Montant par activité'), findsNothing);
    });

    testWidgets('une lecture qui ÉCHOUE : l’encadré « Non consulté » de la vue '
        'à la place de la bande, la phrase « Ce n’est pas un zéro » dans '
        'chaque graphique — jamais l’exception technique, jamais un zéro', (
      tester,
    ) async {
      await monter(
        tester,
        surcharges: [
          tableauDeBordProvider.overrideWith(
            (ref) async => throw StateError('SQLITE_BUSY interne'),
          ),
          seriesTableauDeBordProvider.overrideWith(
            (ref) async => throw StateError('SQLITE_BUSY interne'),
          ),
        ],
      );

      final encadre = find.byKey(const Key('tdb-bande-non-consultee'));
      expect(encadre, findsOneWidget);
      expect(
        find.descendant(of: encadre, matching: find.text('Non consulté')),
        findsOneWidget,
      );
      final deco =
          tester.widget<Container>(encadre).decoration! as BoxDecoration;
      expect(deco.color, AppColors.badgeRougeFond);
      expect(
        (deco.border! as Border).top.color,
        OpacitesAccueil.bordureNonConsulte,
      );
      for (final cle in EcranTableauDeBord.libelles.keys) {
        expect(find.byKey(Key('tdb-valeur-$cle')), findsNothing);
      }
      expect(find.textContaining('SQLITE_BUSY'), findsNothing);
      const phrase =
          "Cette donnée n'a pas pu être lue. Ce n'est pas un zéro : rien n'a "
          'été mesuré.';
      // L'encadré, puis les trois cartes de graphique.
      expect(find.text(phrase), findsNWidgets(4));
      expect(find.byKey(const Key('tdb-ca-indisponible')), findsOneWidget);
      expect(
        find.byKey(const Key('tdb-repartition-illisible')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('tdb-activites-illisible')), findsOneWidget);
      // Aucun bouton d'étendue sur une série qui n'a pas été lue.
      expect(find.byKey(const Key('tdb-mois-3')), findsNothing);
      // Le reste de la page est là : la vue ne tombe pas avec la bande.
      expect(find.byKey(const Key('tdb-acces-reservation')), findsOneWidget);
      expect(find.byKey(const Key('tdb-chambres')), findsOneWidget);
    });

    testWidgets('« Exporter » de l’en-tête ouvre la MÊME modale que celui du '
        'pilotage et produit la MÊME synthèse (la vue : un seul `export`, '
        '`genererExport`, D413/D415)', (tester) async {
      final syntheses = <EtatRapportAccueil>[];
      await monter(
        tester,
        surcharges: [
          exporterRapportAccueilProvider.overrideWithValue((
            etat,
            format,
          ) async {
            syntheses.add(etat);
            // Le PDF est présélectionné dans la modale partagée.
            expect(format, FormatExport.pdf);
            return 'C:/Documents/synthese.pdf';
          }),
        ],
      );
      await tester.tap(find.byKey(const Key('tdb-exporter')));
      await tester.pumpAndSettle();
      final modale = find.byKey(const Key('modale-export-carte'));
      expect(
        find.descendant(of: modale, matching: find.text(titreExportPilotage)),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('export-generer')));
      await tester.pumpAndSettle();
      expect(syntheses, hasLength(1));
      expect(syntheses.single.code, TypeRapportAccueil.synthese.code);
      // L'issue est DITE par le toast commun (14/10/2026).
      expect(
        tester.widget<Text>(find.byKey(const Key('tdb-exporter-csv'))).data,
        'Export enregistré : synthese.pdf',
      );
    });
  });
}
