import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/auth/domain/session.dart';
import 'package:tatacora_flutter/features/comptabilite/data/comptabilite_dao.dart';
import 'package:tatacora_flutter/features/crm/data/client_dao.dart';
import 'package:tatacora_flutter/features/hebergement/data/reservation_dao.dart';
import 'package:tatacora_flutter/features/hebergement/data/reservation_repository_local.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/periode_sejour.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/fiche_reservation.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/reservation.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/service_reservation.dart';
import 'package:tatacora_flutter/features/hebergement/domain/messages_annulation.dart';
import 'package:tatacora_flutter/features/hebergement/impression/confirmation_reservation.dart';
import 'package:tatacora_flutter/features/hebergement/presentation/fiche_reservation.dart';
import 'package:tatacora_flutter/features/hebergement/presentation/ecran_reservations.dart';
import 'package:tatacora_flutter/features/hebergement/presentation/providers_hebergement.dart';

import '../../comptabilite/support/outils_comptabilite.dart';

/// Écrans M1 — montés sur une **vraie base locale**, sans réseau.
///
/// Le dépôt injecté est le dépôt **local** : ces tests portent sur ce que
/// l'écran affiche et refuse, pas sur le protocole HTTP, déjà couvert
/// ailleurs. Monter le composite ici mêlerait deux questions et rendrait
/// chaque échec ambigu.
void main() {
  late AppDatabase db;
  late ReservationRepositoryLocal depot;

  const uniteId = 'u-bng-01';

  /// Périodes exprimées en **jours à partir d'aujourd'hui**.
  ///
  /// `CreerReservation` refuse une arrivée dans le passé — elle fausserait la
  /// disponibilité de toutes les périodes antérieures. Des dates fixes
  /// deviendraient donc invalides au fil du temps, et la suite se mettrait à
  /// échouer un matin sans qu'aucun code n'ait changé.
  PeriodeSejour periode(int dansNJours, int puisNJours) => PeriodeSejour(
    arrivee: DateTime.now().add(Duration(days: dansNJours)),
    depart: DateTime.now().add(Duration(days: puisNJours)),
  );

  setUp(() async {
    db = AppDatabase.enMemoire();
    // Un acompte encaissé et un remboursement passent leur PIÈCE comptable dans
    // la même transaction : le référentiel est installé (l'exercice de l'année
    // courante — ces tests datent leurs séjours d'aujourd'hui) et le moteur
    // branché, comme en production.
    await db.customStatement('SELECT 1');
    await semerAuteur(db);
    await baseInstalleeSur(db, DateTime.now());
    depot = ReservationRepositoryLocal(
      ReservationDao(
        db,
        moteur: () async => moteurSur(db, maintenant: DateTime.now),
      ),
    );

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
    await db
        .into(db.unitesHebergementLocal)
        .insert(
          UnitesHebergementLocalCompanion.insert(
            id: uniteId,
            categorieId: 'cat-1',
            numero: 'BNG-01',
            statut: 'libre',
          ),
        );
    await db
        .into(db.unitesHebergementLocal)
        .insert(
          UnitesHebergementLocalCompanion.insert(
            id: 'u-hs',
            categorieId: 'cat-1',
            numero: 'CH-999',
            statut: 'hors_service',
          ),
        );
    await db
        .into(db.clientsLocal)
        .insert(
          ClientsLocalCompanion.insert(
            id: 'cli-comptoir',
            nom: 'Comptoir',
            telephone: '+229 01 00 00 00 00',
            typeClient: 'particulier',
          ),
        );
    // Le nom affiché vient de la JOINTURE sur `clients`, jamais du champ passé
    // à la création : la fiche client fait autorité. Il faut donc un vrai
    // second client pour éprouver l'affichage d'un conflit.
    await db
        .into(db.clientsLocal)
        .insert(
          ClientsLocalCompanion.insert(
            id: 'cli-dossou',
            nom: 'DOSSOU',
            prenom: const Value('Marie'),
            telephone: '+229 01 00 00 00 02',
            typeClient: 'particulier',
          ),
        );
  });

  tearDown(() async => db.close());

  /// Monte un écran avec le dépôt local et des droits d'écriture sur M1.
  Future<void> monter(
    WidgetTester tester,
    Widget ecran, {
    GardeAcces? droits,
    PeriodeSejour? periodeInitiale,
    Future<void> Function(ConfirmationReservation)? imprimer,
  }) async {
    // La fenêtre de test vaut 800 × 600 par défaut, et le formulaire du maître
    // est plus haut que cela : le bouton d'enregistrement tomberait hors champ,
    // le `tap` ne toucherait rien, et l'échec se lirait sur l'assertion
    // suivante — qui désignerait la mauvaise cause. La LARGEUR reste à 800 :
    // c'est elle qui commande les points de rupture responsives, et l'élargir
    // ferait basculer les écrans dans une mise en page que ces tests
    // n'observent pas.
    tester.view.physicalSize = const Size(800, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Le conteneur est construit AVANT le montage, et la période y est posée
    // avant que l'écran n'existe.
    //
    // C'est l'ordre réel : le réceptionniste choisit ses dates à l'écran
    // Disponibilités, puis ouvre la fiche. La poser après le premier rendu —
    // ce que faisait ce helper — inversait cet ordre, et l'écran de
    // réservation lisait la période PAR DÉFAUT (cette nuit) avant de recevoir
    // celle qu'on croyait lui donner. Le test passait quand même tant que rien
    // ne dépendait des dates ; il a cessé de passer le jour où le nombre de
    // nuits est entré dans le calcul, ce qui est exactement son rôle.
    final conteneur = ProviderContainer(
      overrides: [
        depotReservationProvider.overrideWithValue(depot),
        // La base de test, et non une base de fichier réelle : le bandeau
        // d'opérations en attente interroge la file, donc il lui faut une
        // base. Sans cette surcharge le bandeau resterait muet par erreur —
        // exactement le silence que PA-63 a coûté.
        baseLocaleProvider.overrideWithValue(db),
        // Celui qui encaisse l'acompte et qui annule (RG-15) : la pièce le nomme.
        sessionProvider.overrideWithBuild(
          (ref, notifier) => Session(
            utilisateurId: auteurEssai,
            login: 'caissier',
            nom: 'Caissier',
            role: 'gerant',
            droits: GardeAcces.depuisJson(const {'M1': 'C', 'M3': 'C'}),
          ),
        ),
        droitsProvider.overrideWithValue(
          // M3 en plus de M1 : la fiche de réservation retient un client du
          // référentiel, et l'ajouter est une écriture sur M3.
          droits ?? GardeAcces.depuisJson(const {'M1': 'C', 'M3': 'C'}),
        ),
        // L'impression est une ACTION injectée : un test de widget n'a pas de
        // greffon natif, et `Printing` y lèverait. C'est aussi ce qui permet
        // d'observer ce qui part réellement au papier.
        if (imprimer != null)
          imprimerConfirmationReservationProvider.overrideWithValue(imprimer),
      ],
    );
    addTearDown(conteneur.dispose);

    if (periodeInitiale != null) {
      conteneur
          .read(periodeConsulteeProvider.notifier)
          .definir(
            arrivee: periodeInitiale.arrivee,
            depart: periodeInitiale.depart,
          );
    }

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: conteneur,
        child: MaterialApp(
          theme: AppTheme.clair,
          home: Scaffold(body: ecran),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<Reservation> creerEnBase({
    required PeriodeSejour p,
    String clientId = 'cli-comptoir',
    String client = 'Comptoir',
    StatutSynchronisation sync = StatutSynchronisation.local,
    String? motifRejet,
  }) async {
    final r = Reservation(
      id: 'res-${p.arrivee.millisecondsSinceEpoch}',
      reference: 'LOC-TEST${p.arrivee.day}',
      clientId: clientId,
      clientNom: client,
      uniteId: uniteId,
      periode: p,
      tarifNuit: 28000,
      statut: StatutReservation.enAttente,
      statutSynchronisation: sync,
      creeeLe: DateTime(2026, 8, 1),
      motifRejet: motifRejet,
    );
    return depot.enregistrer(r);
  }

  /* ================================================================== */
  group('Écran Nouvelle réservation', () {
    /// Fait défiler jusqu'au bouton avant de cliquer.
    ///
    /// Le formulaire du maître tient sur plus d'une hauteur d'écran. Un `tap`
    /// direct viserait un point hors de la fenêtre, ne toucherait rien, et le
    /// test échouerait sur l'assertion suivante — en désignant la mauvaise
    /// cause. C'est aussi le geste réel du réceptionniste : il fait défiler.
    Future<void> enregistrer(WidgetTester tester) async {
      final bouton = find.byKey(const Key('bouton-enregistrer'));
      await tester.ensureVisible(bouton);
      await tester.pumpAndSettle();
      await tester.tap(bouton);
      await tester.pumpAndSettle();
    }

    /// Retient un client dans la liste du référentiel.
    ///
    /// Le champ n'est plus un `TextField` : c'est une **clé étrangère**. Y
    /// taper un nom ne rattacherait la réservation à personne, ce qui était
    /// précisément le défaut jusqu'au 25/08/2026.
    Future<void> choisirClient(WidgetTester tester, String nom) async {
      await tester.ensureVisible(find.byKey(const Key('champ-client')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('champ-client')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining(nom).last);
      await tester.pumpAndSettle();
    }

    /// Coche un service et choisit sa première option proposée.
    Future<void> choisirDans(
      WidgetTester tester,
      String cleService,
      String libelleOption,
    ) async {
      await tester.ensureVisible(find.byKey(Key('ajouter-$cleService')));
      await tester.tap(find.byKey(Key('ajouter-$cleService')));
      await tester.pumpAndSettle();

      // Recherche par PRÉFIXE de clé, jamais par type : le champ est un
      // `DropdownButtonFormField<OptionService>`, et un `is
      // DropdownButtonFormField` sans argument de type ne le reconnaît pas —
      // il vaut `<dynamic>`, ce qui ne correspond à rien et rend un « Bad
      // state: No element » qui ne dit pas pourquoi.
      final choix = find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('choix-'),
      );
      await tester.ensureVisible(choix.last);
      await tester.pumpAndSettle();
      await tester.tap(choix.last);
      await tester.pumpAndSettle();
      await tester.tap(find.text(libelleOption).last);
      await tester.pumpAndSettle();
    }

    testWidgets('la page porte les champs du maître, dans son ordre', (
      tester,
    ) async {
      await monter(
        tester,
        const FicheReservation(uniteId: uniteId),
        periodeInitiale: periode(10, 12),
      );

      // Identité et dates — `reservations.html` l.123-141.
      for (final cle in const [
        'champ-client',
        'champ-type-client',
        'champ-canal',
        'champ-date-arrivee',
        'champ-date-depart',
      ]) {
        expect(find.byKey(Key(cle)), findsOneWidget, reason: cle);
      }

      // Les cinq services combinables — l.144-147. C'est la phrase que le
      // maître met en sous-titre de sa page : une réservation combine
      // Hébergement, Restauration, Bar, Tourisme et Véhicule.
      for (final service in ServiceReservation.values) {
        expect(
          find.byKey(Key('service-${service.cle}')),
          findsOneWidget,
          reason: service.cle,
        );
      }

      // Récapitulatif — l.152-181 : Remise, Acompte, Mode de paiement, puis le
      // bloc à CINQ lignes, ni plus ni moins.
      for (final cle in const [
        'champ-remise-type',
        'champ-remise-valeur',
        'champ-acompte',
        'champ-mode-paiement',
        'recap-sous-total',
        'recap-remise',
        'recap-total',
        'recap-acompte',
        'recap-reste',
      ]) {
        expect(find.byKey(Key(cle)), findsOneWidget, reason: cle);
      }

      // Pied — l.184-187.
      expect(find.byKey(const Key('bouton-annuler')), findsOneWidget);
      expect(find.byKey(const Key('bouton-enregistrer')), findsOneWidget);
    });

    testWidgets('arriver depuis Disponibilités pré-coche l’hébergement', (
      tester,
    ) async {
      await monter(
        tester,
        const FicheReservation(uniteId: uniteId),
        periodeInitiale: periode(10, 12),
      );

      // Le bloc de lignes du service est ouvert, avec sa chambre déjà retenue.
      expect(find.byKey(const Key('bloc-hebergement')), findsOneWidget);
      // 28 000 × 2 nuits, sur la ligne comme au sous-total du service.
      expect(find.textContaining('56 000 FCFA'), findsWidgets);
    });

    testWidgets('les nuits sont calculées, jamais saisies', (tester) async {
      await monter(
        tester,
        const FicheReservation(uniteId: uniteId),
        periodeInitiale: periode(10, 12),
      );

      // Le bandeau du maître dit d'où vient le nombre, et que le champ ne se
      // saisit pas : sans lui, un réceptionniste cherche où corriger 2 nuits.
      expect(find.byKey(const Key('bandeau-nuits')), findsOneWidget);
      expect(find.textContaining('2 nuit(s)'), findsOneWidget);

      // La quantité d'une chambre est en lecture seule — c'est le séjour qui
      // la commande.
      final quantite = tester.widget<TextFormField>(
        find.byWidgetPredicate(
          (w) =>
              w is TextFormField &&
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('quantite-'),
        ),
      );
      expect(quantite.enabled, isTrue);
      // `readOnly` n'est pas exposé par TextFormField : on vérifie par le
      // geste, seule preuve qui vaille — la saisie ne prend pas.
      final champ = find.byWidgetPredicate(
        (w) =>
            w is TextFormField &&
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('quantite-'),
      );
      await tester.enterText(champ, '99');
      await tester.pumpAndSettle();
      expect(find.textContaining('56 000 FCFA'), findsWidgets);
    });

    testWidgets('le sous-total est la SOMME des services, pas la chambre', (
      tester,
    ) async {
      // Une boisson au catalogue : le point de vente et la réservation lisent
      // la même table, c'est tout l'intérêt de la source unique.
      await db
          .into(db.cartesBoissonLocal)
          .insert(
            CartesBoissonLocalCompanion.insert(
              id: 'b-1',
              articleId: 'art-biere',
              libelle: 'Bière Béninoise',
              categorie: 'Bière',
              prixVente: 1200,
            ),
          );

      await monter(
        tester,
        const FicheReservation(uniteId: uniteId),
        periodeInitiale: periode(10, 12),
      );

      await tester.tap(find.byKey(const Key('service-bar')));
      await tester.pumpAndSettle();
      await choisirDans(tester, 'bar', 'Bière Béninoise — 1 200 FCFA');

      // 56 000 (chambre) + 1 200 (boisson). Avec l'ancienne formule
      // `tarif × nuits`, la boisson n'aurait jamais atteint le total.
      expect(find.textContaining('57 200 FCFA'), findsWidgets);
    });

    testWidgets('un rayon sans catalogue local reste visible, avec sa raison', (
      tester,
    ) async {
      await monter(
        tester,
        const FicheReservation(uniteId: uniteId),
        periodeInitiale: periode(10, 12),
      );

      await tester.tap(find.byKey(const Key('service-restauration')));
      await tester.pumpAndSettle();

      // Le catalogue du restaurant de CE poste est vide (M4 est local depuis le
      // 09/10/2026). Un bloc absent laisserait croire que le restaurant n'est
      // pas vendable ; un bloc vide sans explication passerait pour cassé
      // (PA-90). La raison n'accuse plus une panne : elle dit quoi faire.
      expect(find.byKey(const Key('vide-restauration')), findsOneWidget);
      expect(
        find.textContaining('Aucun plat n\'est encore au catalogue'),
        findsOneWidget,
      );
      expect(find.textContaining('non répliquée'), findsNothing);
    });

    testWidgets('le rayon Restauration offre les plats du catalogue local — '
        'et ne dit plus qu\'il est vide', (tester) async {
      final utilisateur = UtilisateursLocalCompanion.insert(
        id: 'u-chef',
        login: 'chef',
        nom: 'Chef',
        role: 'cuisinier',
        droitsJson: '{}',
        sel: 's',
        empreinte: 'e',
        iterations: 1,
        dateCreation: DateTime(2026, 10, 1),
        dateMotDePasse: DateTime(2026, 10, 1),
      );
      await db.into(db.utilisateursLocal).insert(utilisateur);
      await db
          .into(db.menusLocal)
          .insert(
            MenusLocalCompanion.insert(
              id: 'm-1',
              libelle: 'Carte',
              type: 'local',
              creeLe: DateTime(2026, 10, 1),
              creePar: 'u-chef',
            ),
          );
      await db
          .into(db.recettesLocal)
          .insert(
            RecettesLocalCompanion.insert(
              id: 'r-1',
              libelle: 'Fiche',
              creeLe: DateTime(2026, 10, 1),
              creePar: 'u-chef',
            ),
          );
      await db
          .into(db.platsLocal)
          .insert(
            PlatsLocalCompanion.insert(
              id: 'p-1',
              menuId: 'm-1',
              recetteId: 'r-1',
              libelle: 'Poulet DG',
              prixVente: 4500,
              creeLe: DateTime(2026, 10, 1),
              creePar: 'u-chef',
            ),
          );

      await monter(
        tester,
        const FicheReservation(uniteId: uniteId),
        periodeInitiale: periode(10, 12),
      );

      await tester.tap(find.byKey(const Key('service-restauration')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('vide-restauration')), findsNothing);
    });

    testWidgets('le reste à payer suit l’acompte saisi', (tester) async {
      await monter(
        tester,
        const FicheReservation(uniteId: uniteId),
        periodeInitiale: periode(10, 12),
      );

      await tester.enterText(find.byKey(const Key('champ-acompte')), '20000');
      await tester.pumpAndSettle();

      expect(find.textContaining('36 000 FCFA'), findsOneWidget);
    });

    testWidgets('une remise en pourcentage se déduit du total', (tester) async {
      await monter(
        tester,
        const FicheReservation(uniteId: uniteId),
        periodeInitiale: periode(10, 12),
      );

      // Le champ de valeur DORT tant que le type vaut « Aucune » : le maître
      // le grise plutôt que de le masquer.
      final valeur = tester.widget<TextFormField>(
        find.byKey(const Key('champ-remise-valeur')),
      );
      expect(valeur.enabled, isFalse);

      await tester.tap(find.byKey(const Key('champ-remise-type')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('%').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('champ-remise-valeur')),
        '10',
      );
      await tester.pumpAndSettle();

      // 10 % de 56 000 = 5 600 retirés, total 50 400.
      expect(find.textContaining('- 5 600 FCFA'), findsOneWidget);
      expect(find.textContaining('50 400 FCFA'), findsWidgets);
    });

    testWidgets('un acompte supérieur au total est refusé', (tester) async {
      await monter(
        tester,
        const FicheReservation(uniteId: uniteId),
        periodeInitiale: periode(10, 12),
      );

      await choisirClient(tester, 'Comptoir');
      await tester.enterText(find.byKey(const Key('champ-acompte')), '100000');
      await enregistrer(tester);

      // Un acompte supérieur au dû transformerait la créance en dette envers
      // le client, sans qu'aucun écran ne le montre.
      expect(find.textContaining('dépasse le total à payer'), findsOneWidget);
      expect(await depot.reservations(), isEmpty);
    });

    testWidgets('sans client retenu, l’enregistrement est refusé', (
      tester,
    ) async {
      // Le refus a changé de NATURE le 25/08/2026 : ce n'était qu'un
      // validateur de champ texte, c'est maintenant l'absence d'une clé
      // étrangère. Sans client, la réservation n'a rien à écrire dans
      // `client_id`, et le serveur la rejetterait.
      await monter(
        tester,
        const FicheReservation(uniteId: uniteId),
        periodeInitiale: periode(10, 12),
      );

      await enregistrer(tester);

      expect(find.textContaining('Choisissez un client'), findsOneWidget);
      expect(await depot.reservations(), isEmpty);
    });

    testWidgets('« Ajouter client » crée une VRAIE fiche, et la retient', (
      tester,
    ) async {
      await monter(
        tester,
        const FicheReservation(uniteId: uniteId),
        periodeInitiale: periode(10, 12),
      );

      await tester.ensureVisible(
        find.byKey(const Key('bouton-nouveau-client')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('bouton-nouveau-client')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('nouveau-client-nom')),
        'ADJOVI Paul',
      );
      await tester.enterText(
        find.byKey(const Key('nouveau-client-telephone')),
        '+229 01 55 44 33 22',
      );
      await tester.tap(find.byKey(const Key('nouveau-client-enregistrer')));
      await tester.pumpAndSettle();

      // Le client existe en base — et c'est tout ce qu'il y a à garantir
      // depuis le 14/09/2026.
      //
      // ⚠ Ce cas vérifiait aussi son ENTRÉE DE FILE : `clients` était au
      // registre synchronisable, et devait partir AVANT la réservation qui le
      // référence, sans quoi le serveur rejetait celle-ci sur une clé
      // étrangère (PA-116/PA-127). Zéro réseau : il n'y a plus d'ordre à
      // garantir, donc plus rien à compter dans une file.
      final enBase = await ClientDao(db).clients();
      expect(enBase.map((c) => c.nom), contains('ADJOVI Paul'));

      // Et il est RETENU : le créer sans le sélectionner obligerait à le
      // rechercher dans une liste où il vient d'apparaître.
      await enregistrer(tester);
      await tester.tap(find.byKey(const Key('bouton-plus-tard')));
      await tester.pumpAndSettle();

      final reservations = await depot.reservations();
      expect(reservations.single.clientNom, 'ADJOVI Paul');
    });

    testWidgets(
      'sans droit d’écriture sur M3, aucun bouton « Ajouter client »',
      (tester) async {
        // Créer un client, c'est écrire dans M3. La synchronisation vérifie les
        // droits PAR OPÉRATION (PA-65) : sans `C` sur M3, le client serait
        // refusé au serveur et la réservation partirait vers un client
        // inexistant. Le bouton est retiré, pas grisé.
        await monter(
          tester,
          const FicheReservation(uniteId: uniteId),
          periodeInitiale: periode(10, 12),
          droits: GardeAcces.depuisJson(const {'M1': 'C', 'M3': 'L'}),
        );

        expect(find.byKey(const Key('bouton-nouveau-client')), findsNothing);
        // La liste, elle, reste : on peut réserver pour un client existant.
        expect(find.byKey(const Key('champ-client')), findsOneWidget);
      },
    );

    testWidgets('aucun service choisi : le refus s’affiche sous le libellé', (
      tester,
    ) async {
      // Sans `uniteId`, rien n'est pré-coché — c'est le cas du maître, qui
      // n'a pas d'écran Disponibilités.
      await monter(
        tester,
        const FicheReservation(),
        periodeInitiale: periode(10, 12),
      );

      await choisirClient(tester, 'Comptoir');
      await enregistrer(tester);

      expect(find.byKey(const Key('erreur-services')), findsOneWidget);
      expect(await depot.reservations(), isEmpty);
    });

    testWidgets('deux chambres sur une fiche sont REFUSÉES, et nommées', (
      tester,
    ) async {
      // Écart assumé avec le maître, qui les accepte : `reservations.unite_id`
      // est une colonne unique et NOT NULL. Deux chambres partiraient au
      // serveur comme une seule, et la seconde serait perdue en silence —
      // elle resterait libre au planning, et le double-booking que M1 existe
      // pour empêcher se produirait à la réception suivante.
      await db
          .into(db.unitesHebergementLocal)
          .insert(
            UnitesHebergementLocalCompanion.insert(
              id: 'u-bng-02',
              categorieId: 'cat-1',
              numero: 'BNG-02',
              statut: 'libre',
            ),
          );

      await monter(
        tester,
        const FicheReservation(uniteId: uniteId),
        periodeInitiale: periode(10, 12),
      );

      await choisirClient(tester, 'Comptoir');
      await choisirDans(
        tester,
        'hebergement',
        'Bungalow (BNG-02) — 28 000 FCFA',
      );
      await enregistrer(tester);

      expect(find.byKey(const Key('message-erreur')), findsOneWidget);
      expect(find.textContaining('une seule chambre'), findsOneWidget);
      expect(await depot.reservations(), isEmpty);
    });

    testWidgets('un chevauchement est refusé et NOMME le conflit', (
      tester,
    ) async {
      await creerEnBase(p: periode(10, 13), clientId: 'cli-dossou');

      await monter(
        tester,
        const FicheReservation(uniteId: uniteId),
        periodeInitiale: periode(12, 15),
      );

      await choisirClient(tester, 'Comptoir');
      await enregistrer(tester);

      expect(find.byKey(const Key('message-erreur')), findsOneWidget);
      // Un refus opaque enverrait chercher ailleurs, devant le client.
      expect(find.textContaining('DOSSOU Marie'), findsOneWidget);
      // Seule la réservation en conflit subsiste : la seconde n'a pas été
      // écrite. Un refus qui laisserait une trace serait pire qu'inutile.
      expect(await depot.reservations(), hasLength(1));
    });

    testWidgets('la modale du maître s’ouvre APRÈS l’enregistrement', (
      tester,
    ) async {
      await monter(
        tester,
        const FicheReservation(uniteId: uniteId),
        periodeInitiale: periode(10, 12),
      );

      // Avant l'enregistrement, aucune modale : la proposer plus tôt ferait
      // croire que l'impression conditionne l'enregistrement.
      expect(find.byKey(const Key('modale-impression-facture')), findsNothing);

      await choisirClient(tester, 'Comptoir');
      await enregistrer(tester);

      expect(
        find.byKey(const Key('modale-impression-facture')),
        findsOneWidget,
      );
      // Les mots du maître, sans reformulation.
      expect(find.text('Réservation enregistrée'), findsOneWidget);
      expect(
        find.text('Voulez-vous imprimer la facture de cette réservation ?'),
        findsOneWidget,
      );
      expect(find.text('Plus tard'), findsOneWidget);
      expect(find.text('Imprimer la facture'), findsOneWidget);
    });

    testWidgets('« Plus tard » n’imprime RIEN, et la réservation reste', (
      tester,
    ) async {
      var impressions = 0;
      await monter(
        tester,
        const FicheReservation(uniteId: uniteId),
        periodeInitiale: periode(10, 12),
        imprimer: (_) async => impressions++,
      );

      await choisirClient(tester, 'Comptoir');
      await enregistrer(tester);
      await tester.tap(find.byKey(const Key('bouton-plus-tard')));
      await tester.pumpAndSettle();

      expect(impressions, 0);
      // Refuser le papier ne défait pas la saisie : c'est le point de l'ordre
      // choisi par le maître.
      expect(await depot.reservations(), hasLength(1));
    });

    testWidgets('« Imprimer la facture » envoie la RÉSERVATION enregistrée', (
      tester,
    ) async {
      ConfirmationReservation? envoye;
      await monter(
        tester,
        const FicheReservation(uniteId: uniteId),
        periodeInitiale: periode(10, 12),
        imprimer: (document) async => envoye = document,
      );

      await choisirClient(tester, 'Comptoir');
      await tester.enterText(find.byKey(const Key('champ-acompte')), '20000');
      await enregistrer(tester);
      await tester.tap(find.byKey(const Key('bouton-imprimer-facture')));
      await tester.pumpAndSettle();

      expect(envoye, isNotNull);
      // La réservation telle qu'elle est EN BASE, avec son acompte et sa
      // ligne de service — pas un objet reconstruit depuis le formulaire, qui
      // pourrait diverger de ce qui a réellement été écrit.
      expect(envoye!.reservation.acompte, 20000);
      expect(envoye!.reservation.lignes, hasLength(1));
      expect(envoye!.recapitulatif.last.$2, contains('36 000'));

      // ⚠ Le document imprimé ne s'appelle PAS « facture », quel que soit le
      // mot du bouton : sans numéro ni cachet fiscal, ce serait un faux
      // document fiscal remis à un client.
      expect(ConfirmationReservation.titre, isNot(contains('FACTURE')));
    });

    testWidgets('une saisie valide crée la réservation ET ses lignes', (
      tester,
    ) async {
      await monter(
        tester,
        const FicheReservation(uniteId: uniteId),
        periodeInitiale: periode(10, 12),
      );

      await choisirClient(tester, 'Comptoir');
      await tester.enterText(find.byKey(const Key('champ-acompte')), '20000');
      await enregistrer(tester);

      // La modale du maître s'ouvre APRÈS l'écriture : on la referme par
      // « Plus tard » avant de constater la base.
      await tester.tap(find.byKey(const Key('bouton-plus-tard')));
      await tester.pumpAndSettle();

      final liste = await depot.reservations();
      expect(liste, hasLength(1));
      final r = liste.first;
      // Le nom vient de la fiche client RETENUE — une vraie clé étrangère.
      expect(r.clientNom, 'Comptoir');
      expect(r.clientId, 'cli-comptoir');
      expect(r.acompte, 20000);
      expect(r.statutSynchronisation, StatutSynchronisation.local);

      // La ligne de service, relue depuis la base — pas depuis l'objet rendu
      // par l'écriture, qui prouverait seulement que l'objet existe en
      // mémoire.
      expect(r.lignes, hasLength(1));
      final ligne = r.lignes.single;
      expect(ligne.service, ServiceReservation.hebergement);
      expect(ligne.itemId, uniteId);
      // Libellé ET prix FIGÉS à l'ajout : un changement de grille ne doit pas
      // réécrire le montant d'une réservation déjà prise.
      expect(ligne.prixUnitaire, 28000);
      expect(ligne.quantite, 2);
      expect(r.montantTotal, 56000);

      // La fiche du maître est enregistrée, pas seulement recueillie.
      expect(r.typeClient, TypeClient.particulier);
      expect(r.canal, CanalReservation.physique);
      expect(r.modePaiement, ModePaiementReservation.mobileMoney);
    });
  });

  /* ================================================================== */
  group('Écran Modifier une réservation', () {
    Future<void> enregistrer(WidgetTester tester) async {
      final bouton = find.byKey(const Key('bouton-enregistrer'));
      await tester.ensureVisible(bouton);
      await tester.pumpAndSettle();
      await tester.tap(bouton);
      await tester.pumpAndSettle();
    }

    /// Une réservation en base, avec sa fiche et sa ligne de service.
    Future<Reservation> aModifier({int acompte = 0}) => depot.enregistrer(
      Reservation(
        id: 'res-mod',
        reference: 'LOC-MOD',
        clientId: 'cli-comptoir',
        clientNom: 'Comptoir',
        uniteId: uniteId,
        periode: periode(10, 12),
        tarifNuit: 28000,
        statut: StatutReservation.confirmee,
        statutSynchronisation: StatutSynchronisation.synchronise,
        creeeLe: DateTime(2026, 8, 1),
        acompte: acompte,
        typeClient: TypeClient.entreprise,
        canal: CanalReservation.whatsapp,
        modePaiement: ModePaiementReservation.cheque,
        lignes: [
          LigneService(
            id: 'l-mod',
            service: ServiceReservation.hebergement,
            itemId: uniteId,
            libelle: 'Bungalow (BNG-01)',
            prixUnitaire: 28000,
            quantite: 2,
          ),
        ],
      ),
    );

    testWidgets('le formulaire arrive REMPLI, et le titre nomme le client', (
      tester,
    ) async {
      await aModifier(acompte: 10000);
      await monter(
        tester,
        const FicheReservation(reservationId: 'res-mod'),
        periodeInitiale: periode(1, 2),
      );

      expect(
        tester
            .widget<Text>(find.byKey(const Key('titre-modale-reservation')))
            .data,
        'Modifier — Comptoir',
      );

      // La fiche entière est reprise : un champ oublié au pré-remplissage se
      // viderait à l'enregistrement, et l'utilisateur ne verrait rien.
      // La liste des clients affiche « nom — téléphone » : c'est ce qui
      // distingue deux homonymes, et c'est le seul moyen de choisir juste au
      // comptoir.
      expect(find.textContaining('Comptoir'), findsWidgets);
      // « Structure », le mot de la vue (PA-185) — le code stocké reste
      // `entreprise`, et c'est lui qui a été relu pour remplir ce champ.
      expect(find.text('Structure'), findsWidgets);
      expect(find.text('WhatsApp'), findsWidgets);
      expect(find.text('Chèque'), findsWidgets);

      // Les dates viennent de la RÉSERVATION, pas de la période consultée :
      // l'écran a été monté sur une tout autre période.
      expect(find.byKey(const Key('bloc-hebergement')), findsOneWidget);
      expect(find.textContaining('56 000 FCFA'), findsWidgets);
    });

    testWidgets(
      'sa propre chambre reste retenue, sans conflit avec elle-même',
      (tester) async {
        // LE cas qui commande tout : sans exclusion, la chambre apparaîtrait
        // occupée — par la réservation qu'on est en train de modifier — et
        // l'enregistrement serait refusé pour un chevauchement avec soi.
        final r = await aModifier();
        await monter(
          tester,
          const FicheReservation(reservationId: 'res-mod'),
          periodeInitiale: periode(1, 2),
        );

        // Le CATALOGUE la propose toujours, et sans la marquer indisponible.
        //
        // Ce cas a d'abord été écrit sans cette assertion : retirer
        // l'exclusion du catalogue ne le faisait pas rougir, parce que le
        // pré-remplissage reprend la ligne DÉJÀ EN BASE et n'interroge pas la
        // liste. Le défaut serait pourtant bien visible — « Bungalow (BNG-01)
        // — indisponible, déjà retenu » sur sa propre chambre, à chaque
        // réouverture de fiche.
        expect(
          find.textContaining('indisponible'),
          findsNothing,
          reason:
              'la réservation modifiée s’occupe elle-même dans le catalogue',
        );

        await tester.enterText(find.byKey(const Key('champ-acompte')), '20000');
        await enregistrer(tester);
        await tester.tap(find.byKey(const Key('bouton-plus-tard')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('message-erreur')), findsNothing);

        final relue = await depot.parId(r.id);
        expect(relue!.acompte, 20000);
        // La même réservation, pas une seconde.
        expect(await depot.reservations(), hasLength(1));
      },
    );

    testWidgets('la modification repart au serveur', (tester) async {
      final r = await aModifier();
      await monter(
        tester,
        const FicheReservation(reservationId: 'res-mod'),
        periodeInitiale: periode(1, 2),
      );

      await tester.enterText(find.byKey(const Key('champ-acompte')), '5000');
      await enregistrer(tester);
      await tester.tap(find.byKey(const Key('bouton-plus-tard')));
      await tester.pumpAndSettle();

      // Elle était « synchronisée » : la correction doit la faire repartir,
      // sinon l'écran affiche un état que le serveur ne porte pas.
      final relue = await depot.parId(r.id);
      expect(relue!.statutSynchronisation, StatutSynchronisation.local);
    });

    testWidgets('une réservation introuvable le DIT', (tester) async {
      // Elle a pu être supprimée d'un autre poste entre l'affichage de la
      // grille et le clic : un formulaire vide se remplirait pour rien.
      await monter(
        tester,
        const FicheReservation(reservationId: 'res-inexistante'),
        periodeInitiale: periode(1, 2),
      );

      expect(find.textContaining('introuvable'), findsOneWidget);
    });
  });

  group('Écran Liste des réservations', () {
    testWidgets('chaque ligne porte son statut de synchronisation', (
      tester,
    ) async {
      await creerEnBase(p: periode(10, 12));
      await monter(tester, const EcranReservations());

      // Exigence centrale du sprint : sans ce badge, le réceptionniste
      // ressaisit une réservation déjà en base.
      expect(find.text('En attente d’envoi'), findsOneWidget);
    });

    testWidgets('une réservation refusée reste, avec le motif du serveur', (
      tester,
    ) async {
      final r = await creerEnBase(p: periode(10, 12));
      await ReservationDao(db).majStatutSync(
        r.id,
        StatutSynchronisation.rejete,
        motifRejet: 'Unité déjà réservée par un autre poste (RG-01).',
      );

      await monter(tester, const EcranReservations());

      expect(find.text('Refusée par le serveur'), findsOneWidget);
      expect(find.byKey(Key('motif-rejet-${r.id}')), findsOneWidget);
      // Le message est affiché TEL QUEL : c'est lui qui dit quoi faire.
      expect(find.textContaining('RG-01'), findsOneWidget);
    });

    testWidgets('le mode « en suspens » ne liste plus rien, et DIT pourquoi', (
      tester,
    ) async {
      // Deux réservations en base, dont une jadis « synchronisée » : sous
      // l'ancien mode, la première aurait été listée comme « pas encore
      // partie au serveur ». Le poste est zéro réseau depuis le 14/09/2026 —
      // rien ne part plus, et `statut_sync` naît à `local` : les lister
      // TOUTES sous ce titre serait l'indicateur qui affirme un état qu'il
      // n'a pas vérifié (PA-59/60/61), appliqué au planning entier.
      final a = await creerEnBase(p: periode(10, 12));
      await creerEnBase(p: periode(20, 22), clientId: 'cli-dossou');
      await ReservationDao(
        db,
      ).majStatutSync(a.id, StatutSynchronisation.synchronise);

      await monter(tester, const EcranReservations(seulementEnSuspens: true));

      // La route existe toujours (`app_router.dart`) : l'écran doit y
      // répondre, et il répond par la raison — jamais par une liste, jamais
      // par « Tout est synchronisé », qui affirmerait une synchronisation.
      expect(
        find.byKey(const Key('reservations-sans-synchronisation')),
        findsOneWidget,
      );
      expect(find.text('DOSSOU Marie'), findsNothing);
      expect(find.text('Comptoir'), findsNothing);
    });

    testWidgets('sans droit d’écriture, aucun bouton Annuler', (tester) async {
      final r = await creerEnBase(p: periode(10, 12));
      await monter(
        tester,
        const EcranReservations(),
        droits: GardeAcces.depuisJson(const {'M1': 'L'}),
      );

      expect(find.byKey(Key('annuler-${r.id}')), findsNothing);
    });

    testWidgets('« Annuler » ouvre la modale du serveur : taux pré-rempli, '
        'refus aux mots du serveur, commission sur le montant GLOBAL', (
      tester,
    ) async {
      // 2 nuits à 28 000 F = 56 000 F ; aucun acompte.
      final r = await creerEnBase(p: periode(10, 12));
      await monter(tester, const EcranReservations());

      await tester.tap(find.byKey(Key('annuler-${r.id}')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('modale-annulation-reservation')),
        findsOneWidget,
      );
      // Le taux de référence du client, jamais imposé.
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('annulation-taux')))
            .controller!
            .text,
        '50.00',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('annulation-total'))).data,
        '56 000 FCFA',
      );
      // Aucun acompte : la section du remboursement n'a pas de sens.
      expect(find.byKey(const Key('annulation-aucun-acompte')), findsOneWidget);
      expect(find.byKey(const Key('annulation-mode')), findsNothing);

      // Un taux vide, puis hors bornes : les phrases du serveur, rien d'écrit.
      await tester.enterText(find.byKey(const Key('annulation-taux')), '');
      await tester.tap(find.byKey(const Key('annulation-confirmer')));
      await tester.pumpAndSettle();
      expect(
        find.text(MessagesAnnulation.obligatoire('a taux')),
        findsOneWidget,
      );
      expect((await depot.parId(r.id))!.statut, StatutReservation.enAttente);

      await tester.enterText(find.byKey(const Key('annulation-taux')), '120');
      await tester.tap(find.byKey(const Key('annulation-confirmer')));
      await tester.pumpAndSettle();
      expect(
        find.text(MessagesAnnulation.maximum('a taux', '100')),
        findsOneWidget,
      );
      expect((await depot.parId(r.id))!.statut, StatutReservation.enAttente);

      await tester.enterText(find.byKey(const Key('annulation-taux')), '25');
      await tester.tap(find.byKey(const Key('annulation-confirmer')));
      await tester.pumpAndSettle();

      final apres = await depot.parId(r.id);
      expect(apres, isNotNull, reason: 'annuler n’est pas supprimer');
      expect(apres!.statut, StatutReservation.annulee);
      final a = apres.annulation!;
      expect(a.tauxCentiemes, 2500);
      expect(a.totalCentimes, 5600000);
      expect(a.commissionCentimes, 1400000, reason: '25 % de 56 000 F');
      expect(a.rembourseCentimes, 0);
      // La modale est fermée, le succès est dit.
      expect(
        find.byKey(const Key('modale-annulation-reservation')),
        findsNothing,
      );
      expect(find.byKey(const Key('annulation-succes')), findsOneWidget);
    });

    testWidgets('un acompte remboursé produit sa PIÈCE (Dr 4191 / Cr 5711) '
        'dans la même transaction que l’annulation', (tester) async {
      final jour = DateTime.now();
      await depot.enregistrer(
        Reservation(
          id: 'res-acompte',
          reference: 'LOC-AC',
          clientId: 'cli-dossou',
          clientNom: 'DOSSOU Marie',
          uniteId: uniteId,
          periode: periode(10, 12),
          tarifNuit: 28000,
          statut: StatutReservation.confirmee,
          statutSynchronisation: StatutSynchronisation.local,
          creeeLe: jour,
          acompte: 20000,
          modePaiement: ModePaiementReservation.especes,
        ),
      );
      await monter(tester, const EcranReservations());

      await tester.tap(find.byKey(const Key('annuler-res-acompte')));
      await tester.pumpAndSettle();
      // Le remboursement suggéré : 20 000 F d'acompte - 28 000 F de commission
      // (50 % de 56 000) < 0, donc « 0 », jamais négatif.
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('annulation-valeur')))
            .controller!
            .text,
        '0',
      );
      // Rembourser plus que l'acompte est refusé, aux mots du serveur.
      await tester.enterText(find.byKey(const Key('annulation-taux')), '10');
      await tester.enterText(find.byKey(const Key('annulation-valeur')), '150');
      await tester.tap(find.byKey(const Key('annulation-confirmer')));
      await tester.pumpAndSettle();
      expect(
        find.text(MessagesAnnulation.remboursementSuperieurAcompte),
        findsOneWidget,
      );
      expect(await ComptabiliteDao(db).toutesLesEcritures(), isEmpty);

      await tester.enterText(find.byKey(const Key('annulation-valeur')), '60');
      await tester.tap(find.byKey(const Key('annulation-confirmer')));
      await tester.pumpAndSettle();

      final apres = (await depot.parId('res-acompte'))!;
      expect(apres.statut, StatutReservation.annulee);
      expect(apres.annulation!.rembourseCentimes, 1200000);
      expect(apres.annulation!.commissionCentimes, 560000);
      expect(apres.annulation!.ecritureRemboursementId, isNotNull);

      final lignes = await ComptabiliteDao(db).toutesLesEcritures();
      expect(lignes, hasLength(2));
      expect(lignes.map((e) => e.debit), containsAll(['12000.00', '0.00']));
    });

    testWidgets('liste vide : un message, pas un écran blanc', (tester) async {
      await monter(tester, const EcranReservations());
      expect(find.textContaining('Aucune réservation'), findsOneWidget);
    });

    testWidgets('une annulation entre dans l’onglet Annulations avec ses VRAIS '
        'montants : total, taux, commission, remboursé, date, auteur', (
      tester,
    ) async {
      final r = await creerEnBase(p: periode(10, 12));
      await monter(tester, const EcranReservations());

      await tester.tap(find.byKey(Key('annuler-${r.id}')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('annulation-taux')), '25');
      await tester.tap(find.byKey(const Key('annulation-confirmer')));
      await tester.pumpAndSettle();

      // Plus dans la grille des actives…
      expect(find.byKey(Key('annuler-${r.id}')), findsNothing);
      expect(find.byKey(const Key('grille-vide')), findsOneWidget);

      // …mais dans l'onglet Annulations, avec ce que l'annulation a FIXÉ.
      await tester.tap(
        find.byKey(const Key('reservations-onglet-annulations')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('annulations-vide')), findsNothing);
      expect(find.text('COMMISSION RETENUE'), findsOneWidget);
      expect(find.text('56 000 FCFA'), findsOneWidget);
      expect(find.text('25 %'), findsOneWidget);
      expect(find.text('14 000 FCFA'), findsOneWidget);
      expect(find.text('0 FCFA'), findsOneWidget);
      expect(find.text('compta-$auteurEssai'), findsOneWidget);
      // Aucun tiret : tout est renseigné.
      expect(find.text('—'), findsNothing);
    });

    testWidgets('une annulation d’AVANT la v19 garde ses tirets — jamais un '
        '« 0 FCFA » de commission que personne n’a fixé', (tester) async {
      final r = await creerEnBase(p: periode(10, 12));
      // Une ligne annulée telle que l'ancienne version l'écrivait : le statut et
      // un motif, aucun taux, aucun montant.
      await db.customStatement(
        "UPDATE reservations_local SET statut = 'annulee', "
        "motif_annulation = 'Désistement' WHERE id = ?",
        [r.id],
      );
      await monter(tester, const EcranReservations());

      await tester.tap(
        find.byKey(const Key('reservations-onglet-annulations')),
      );
      await tester.pumpAndSettle();
      expect(find.text('—'), findsNWidgets(6));
      expect(find.textContaining('FCFA'), findsNothing);
    });

    testWidgets('l’onglet Annulations vide le dit', (tester) async {
      await monter(tester, const EcranReservations());
      await tester.tap(
        find.byKey(const Key('reservations-onglet-annulations')),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Aucune réservation annulée pour le moment.'),
        findsOneWidget,
      );
    });
  });
}
