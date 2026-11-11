/// Rendus du POSTE pour le manuel (chapitres 15 à 19 et annexes), PAR LE MOTEUR
/// FLUTTER lui-même — pas des photos d'écran Windows.
///
///     CAPTURES_POSTE_DIR=../manuel_utilisation/captures \
///       flutter test --dart-define=ENV=production tool/capturer_poste_test.dart
///
/// Sans la variable `CAPTURES_POSTE_DIR`, chaque cas s'ignore (même mécanisme
/// que les tests d'intégration) : `flutter test` seul n'écrit rien. Ce fichier
/// n'est pas dans `test/` pour la même raison.
///
/// ## Ce que c'est
///
/// Les VRAIS écrans du poste (`lib/features/**`), montés avec leurs vrais
/// fournisseurs sur une base Drift en mémoire (ou un fichier jetable) alimentée
/// de données de démonstration FICTIVES, le thème réel et la police Inter
/// réelle (chargée depuis `assets/fonts` : sans elle, un test rend le texte en
/// carrés `Ahem`). Fenêtre de 1 440 px de large, facteur 2 (PNG de 2 880 px),
/// comme les captures de la PWA. Les états (poste appairé, « À traiter »,
/// pièce refusée…) sont produits par les vrais écrivains et les vrais clics ;
/// seuls le réseau et le système de fichiers de Windows sont simulés.
///
/// ## Ce que ce n'est pas
///
/// Ni le cadre de fenêtre Windows, ni la barre de titre, ni le rendu des
/// polices de Windows (ClearType) : l'image vient du moteur Skia/Impeller de
/// l'hôte Linux. Chaque figure reste « à confirmer par le PO sur Windows ».
///
/// ## Jamais
///
/// Aucun secret ni e-mail réel : identifiants, IFU, jetons et mots de passe
/// ci-dessous sont des valeurs d'essai évidentes.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/foundation.dart' show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/demarrage/demarrage_resilient.dart';
import 'package:tatacora_flutter/core/demarrage/journal_demarrage.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/auth/presentation/ecran_code_secours.dart';
import 'package:tatacora_flutter/features/auth/presentation/ecran_connexion.dart';
import 'package:tatacora_flutter/features/auth/presentation/formulaire_premier_compte.dart';

import 'package:tatacora_flutter/features/synchronisation/data/service_suivi_postes.dart';
import 'package:tatacora_flutter/features/synchronisation/presentation/ecran_synchronisation.dart';
import 'package:tatacora_flutter/features/synchronisation/presentation/ecran_synchronisation_postes.dart';
import 'package:tatacora_flutter/features/synchronisation/presentation/providers_synchronisation.dart';
import 'package:tatacora_flutter/features/parametres/presentation/ecran_parametres.dart';
import 'package:tatacora_flutter/features/parametres/presentation/widgets/onglet_synchronisation.dart';
import 'package:tatacora_flutter/features/transverse/data/configuration_poste.dart';

import 'package:tatacora_flutter/features/comptabilite/data/comptabilite_dao.dart';
import 'package:tatacora_flutter/features/comptabilite/data/ecritures_serveur_dao.dart';
import 'package:tatacora_flutter/features/comptabilite/data/moteur_comptable.dart';
import 'package:tatacora_flutter/features/comptabilite/presentation/ecran_comptabilite.dart';
import 'package:tatacora_flutter/features/comptabilite/presentation/providers_comptabilite.dart';
import 'package:tatacora_flutter/features/stocks/data/stocks_api.dart';
import 'package:tatacora_flutter/features/stocks/data/stocks_dao.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/etat_stock.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/mouvement_stock.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';
import 'package:tatacora_flutter/features/stocks/presentation/ecran_inventaires.dart';
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';
import 'package:tatacora_flutter/features/transverse/presentation/ecran_import_export.dart';
import 'package:tatacora_flutter/core/impression/entete_etablissement.dart';
import 'package:tatacora_flutter/core/theme/app_assets.dart';
import 'package:tatacora_flutter/features/facturation/impression/proforma_a4.dart';
import '../test/outils/echantillons_presentation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:tatacora_flutter/features/auth/data/session_repository_local.dart';
import 'package:tatacora_flutter/features/facturation/data/proforma_dao.dart';
import 'package:tatacora_flutter/features/facturation/domain/mode_facturation.dart';
import 'package:tatacora_flutter/features/facturation/domain/reglages_documents.dart';
import 'package:tatacora_flutter/features/facturation/presentation/ecran_proformas.dart';
import 'package:tatacora_flutter/features/facturation/presentation/providers_facturation.dart';
import 'package:tatacora_flutter/features/facturation/presentation/providers_proformas.dart';
import 'package:tatacora_flutter/features/facturation/presentation/widgets/champs_acheteur_facture.dart';
import 'package:tatacora_flutter/features/hebergement/data/reservation_dao.dart';
import 'package:tatacora_flutter/features/hebergement/data/reservation_repository_local.dart';
import 'package:tatacora_flutter/features/hebergement/presentation/providers_hebergement.dart';
import 'package:tatacora_flutter/features/parametres/data/parametres_depot_local.dart';
import 'package:tatacora_flutter/features/pos/data/catalogue_dao.dart';
import 'package:tatacora_flutter/features/pos/data/panier_repository_local.dart';
import 'package:tatacora_flutter/features/pos/presentation/ecran_pos_heberges.dart';
import 'package:tatacora_flutter/features/pos/presentation/providers_pos.dart';
import 'package:tatacora_flutter/features/transverse/data/comptes_utilisateurs_dao.dart';
import 'package:tatacora_flutter/features/transverse/data/roles_dao.dart';
import 'package:tatacora_flutter/features/transverse/domain/roles_du_poste.dart';
import 'package:tatacora_flutter/features/transverse/presentation/ecran_comptes_utilisateurs.dart';
import 'package:tatacora_flutter/features/transverse/presentation/ecran_mon_profil.dart';
import 'package:tatacora_flutter/features/auth/data/code_secours_local.dart';
import 'package:tatacora_flutter/features/auth/impression/feuille_code_secours.dart';
import 'package:drift/drift.dart' show Value;

import '../test/features/comptabilite/support/outils_comptabilite.dart';
import '../test/features/pos/support/outils_ventes.dart';
import '../test/features/synchronisation/support/faux_transport.dart';
import '../test/features/synchronisation/support/scenario_file.dart';
import '../test/support/coquille_montee.dart';
import '../test/support/horloge_reference.dart';

/// Dossier de sortie ; `null` : tout s'ignore.
final String? _sortie = Platform.environment['CAPTURES_POSTE_DIR'];

// La clé de `monterCoquille` : une seule frontière pour tous les cas.
const Key _cleCapture = Key('capture-flutter');

/// Largeur de fenêtre (px logiques) ; le facteur 2 est appliqué à l'export.
const double _largeur = 1440;
const double _facteur = 2;

/// Un cas : s'ignore sans `CAPTURES_POSTE_DIR`.
void _cas(
  String nom,
  Future<void> Function(WidgetTester tester) corps,
) {
  testWidgets(nom, (tester) async {
    // Rendu « bureau Windows » : curseur et sélection de texte de bureau, pas
    // les poignées tactiles d'Android (plate-forme par défaut des tests).
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await _chargerPolices();
      await corps(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }, skip: _sortie == null);
}

bool _policesChargees = false;

Future<void> _chargerPolices() async {
  if (_policesChargees) return;
  final f = File('assets/fonts/Inter.ttf');
  if (!f.existsSync()) fail('Police Inter introuvable : ${f.path}');
  final octets = f.readAsBytesSync();
  // La police du poste : Inter, la seule que le pubspec livre.
  final inter = FontLoader('Inter')
    ..addFont(Future.value(ByteData.view(octets.buffer)));
  await inter.load();
  // Les pictogrammes Material (flèches, croix, calendrier) : sans leur police,
  // un test les rend en carrés. Elle vient du SDK Flutter, pas du dépôt.
  final racine = Platform.environment['FLUTTER_ROOT'] ?? '/home/user/flutter';
  final icones = File(
    '$racine/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (!icones.existsSync()) fail('MaterialIcons introuvable : ${icones.path}');
  final o = icones.readAsBytesSync();
  final mat = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.view(o.buffer)));
  await mat.load();
  // `AppTextStyles.policeMonospace` (« JetBrainsMono ») n'est PAS livrée avec le
  // poste (pubspec : Inter seule) : sur Windows le système en choisit une.
  // Ici, à défaut, DejaVu Sans Mono (identifiants, dates, mots de passe).
  final mono = File('/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf');
  if (mono.existsSync()) {
    final m = mono.readAsBytesSync();
    final charge = FontLoader('JetBrainsMono')
      ..addFont(Future.value(ByteData.view(m.buffer)));
    await charge.load();
  }
  _policesChargees = true;
}

/// Fenêtre de [hauteur] px logiques sur [_largeur], facteur 1 (l'export double).
void _fenetre(WidgetTester tester, double hauteur) {
  tester.view
    ..physicalSize = Size(_largeur, hauteur)
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Enveloppe [app] dans la frontière de capture.
Widget _cadre(Widget app) => RepaintBoundary(key: _cleCapture, child: app);

/// Écrit `<CAPTURES_POSTE_DIR>/<nom>.png` (2 880 px de large).
Future<void> _photographier(WidgetTester tester, String nom) async {
  await tester.runAsync(() async {
    final frontiere = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_cleCapture),
    );
    final image = await frontiere.toImage(pixelRatio: _facteur);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final dossier = Directory(_sortie!)..createSync(recursive: true);
    File('${dossier.path}/$nom.png').writeAsBytesSync(
      png!.buffer.asUint8List(),
    );
  });
}

/// Laisse tourner les entrées-sorties réelles (base, fichiers) puis redessine.
Future<void> _laisserTourner(WidgetTester tester, [int tours = 20]) async {
  for (var i = 0; i < tours; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  // ---------------------------------------------------------------- Chap. 15
  _cas('c15-premier-demarrage', (tester) async {
    _fenetre(tester, 900);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [aucunCompteProvider.overrideWith((ref) async => true)],
        child: _cadre(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.clair,
            home: const EcranConnexion(),
          ),
        ),
      ),
    );
    await _laisserTourner(tester);
    expect(find.byType(FormulairePremierCompte), findsOneWidget);
    await _photographier(tester, 'c15-premier-demarrage');
  });

  _cas('c15-ecran-panne', (tester) async {
    _fenetre(tester, 900);
    final dossier = Directory.systemTemp.createTempSync('capt_panne_');
    addTearDown(() => dossier.deleteSync(recursive: true));
    // Le VRAI chemin de panne : un fichier qui n'est pas une base SQLite.
    final fichier = File('${dossier.path}/tatacora.sqlite')
      ..writeAsBytesSync(List.filled(4096, 7));
    final c = ControleurDemarrage()
      ..attacherJournal(JournalDemarrage(dossier)..nouvelleSession('capture'));
    await tester.runAsync(() async {
      await tester.pumpWidget(
        _cadre(
          DemarrageResilient(
            controleur: c,
            preparer: () async {
              final base = AppDatabase.surFichier(fichier);
              base.journalDemarrage = c.journal!.ecrire;
              await base.customSelect('SELECT 1').get();
              return base;
            },
            delai: const Duration(seconds: 45),
            dossierDonnees: dossier.path,
            construire: (_) => const MaterialApp(home: Text('ECRAN METIER')),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pump();
    expect(find.byType(EcranPanneDemarrage), findsOneWidget);
    await _photographier(tester, 'c15-ecran-panne');
  });

  // ---------------------------------------------------------------- Chap. 19
  _cas('c19-code-secours-connexion', (tester) async {
    _fenetre(tester, 900);
    final routeur = GoRouter(
      initialLocation: '/mot-de-passe-administrateur-perdu',
      routes: [
        GoRoute(path: '/connexion', builder: (_, _) => const EcranConnexion()),
        GoRoute(
          path: '/mot-de-passe-administrateur-perdu',
          builder: (_, _) => const EcranCodeSecours(),
        ),
      ],
    );
    addTearDown(routeur.dispose);
    final base = AppDatabase.enMemoire();
    addTearDown(base.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseLocaleProvider.overrideWithValue(base),
          aucunCompteProvider.overrideWith((ref) async => false),
        ],
        child: _cadre(
          MaterialApp.router(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.clair,
            routerConfig: routeur,
          ),
        ),
      ),
    );
    await _laisserTourner(tester);
    await _photographier(tester, 'c19-code-secours-connexion');
  });

  // ---------------------------------------------------------------- Chap. 16
  // Un poste APPAIRÉ au serveur de production (adresse publique du produit,
  // compte « gerant » fictif, jeton d'essai jamais affiché), sa file remplie
  // par les VRAIS écrivains (`jouerJourneeComplete`), puis rangée : tout est
  // « synchronisé » sauf trois opérations en attente et une réservation
  // REFUSÉE pour chevauchement.
  const urlServeur = 'https://logirestock.digitonpro.com/api/v1';

  Future<BancSync> bancAppaire({bool journee = false}) async {
    final b = await BancSync.creer(appaire: false);
    await b.ecrivain.enregistrerAppairage(
      AppairagePoste(
        posteId: 'COMPTOIR-1',
        jetonApi: '0|jeton-essai-non-affiche',
        serveur: urlServeur,
        appaireLe: DateTime(2026, 10, 12, 8),
        compte: 'gerant',
      ),
    );
    if (journee) {
      await jouerJourneeComplete(b.db);
      await b.db.customStatement(
        "UPDATE operations_sync_local SET statut = 'synchronise'",
      );
    }
    return b;
  }

  Future<void> monterEnCoquille(
    WidgetTester tester,
    BancSync b, {
    required String route,
    required Widget ecran,
    double hauteur = 900,
    List<Override> plus = const [],
  }) async {
    await monterCoquille(
      tester,
      role: 'administrateur',
      login: 'admin',
      droits: _droitsAdmin,
      routeActive: route,
      taille: Size(_largeur, hauteur),
      enfant: ecran,
      surcharges: [
        baseLocaleProvider.overrideWithValue(b.db),
        transportSynchronisationProvider.overrideWithValue(
          FauxTransport(reponseLot),
        ),
        urlServeurSynchronisationProvider.overrideWithValue(urlServeur),
        cheminConfigurationPosteProvider.overrideWithValue(b.chemin),
        nomPosteParDefautProvider.overrideWithValue('COMPTOIR-1'),
        ...surchargesHorlogeDeReference(),
        ...plus,
      ],
    );
    await _laisserTourner(tester);
  }

  _cas('c16-parametres-synchronisation', (tester) async {
    final b = await tester.runAsync(bancAppaire);
    addTearDown(() => b!.fermer());
    await monterEnCoquille(
      tester,
      b!,
      route: '/parametres',
      ecran: const EcranParametres(),
      hauteur: 1400,
    );
    await tester.tap(find.byKey(const Key('param-onglet-synchronisation')));
    await _laisserTourner(tester, 40);
    await _photographier(tester, 'c16-parametres-synchronisation');
  });

  _cas('c16-ecran-synchronisation-envoi', (tester) async {
    final b = await tester.runAsync(() => bancAppaire(journee: true));
    addTearDown(() => b!.fermer());
    await tester.runAsync(() async {
      final dao = b!.db;
      // Trois opérations restent à envoyer ; la création de la réservation
      // du 20 au 22/10 est REFUSÉE (chevauchement) : la ligne « À traiter ».
      await dao.customStatement(
        "UPDATE operations_sync_local SET statut = 'en_attente' WHERE seq IN "
        "(SELECT seq FROM operations_sync_local ORDER BY seq DESC LIMIT 3)",
      );
      await dao.customStatement(
        "UPDATE operations_sync_local SET statut = 'rejete', "
        "derniere_erreur = ?, resultat_json = ? WHERE seq = (SELECT MIN(seq) "
        "FROM operations_sync_local WHERE table_serveur = 'reservations' "
        "AND type = 'creation')",
        [
          'Refusée par le serveur (422) : l’unité est déjà réservée sur '
              'cette période.',
          '{"code_motif":"chevauchement"}',
        ],
      );
    });
    await monterEnCoquille(
      tester,
      b!,
      route: '/synchronisation',
      ecran: const EcranSynchronisation(),
      hauteur: 1400,
    );
    await _photographier(tester, 'c16-ecran-synchronisation-envoi');
  });

  _cas('c16-bouton-barre', (tester) async {
    final b = await tester.runAsync(() => bancAppaire(journee: true));
    addTearDown(() => b!.fermer());
    await tester.runAsync(
      () => b!.db.customStatement(
        "UPDATE operations_sync_local SET statut = 'en_attente' WHERE seq IN "
        "(SELECT seq FROM operations_sync_local ORDER BY seq DESC LIMIT 3)",
      ),
    );
    await monterEnCoquille(
      tester,
      b!,
      route: '/tableau-de-bord',
      ecran: const SizedBox.expand(),
    );
    await tester.tap(find.byKey(const Key('bouton-synchronisation')));
    await _laisserTourner(tester, 30);
    expect(find.byKey(const Key('modale-synchronisation')), findsOneWidget);
    await _photographier(tester, 'c16-bouton-barre');
  });

  _cas('c16-postes-appairage', (tester) async {
    final b = await tester.runAsync(bancAppaire);
    addTearDown(() => b!.fermer());
    await monterEnCoquille(
      tester,
      b!,
      route: '/synchronisation-postes',
      ecran: const EcranSynchronisationPostes(),
      plus: [
        serviceSuiviPostesProvider.overrideWithValue(
          _SuiviEssai(
            SuiviPostesLu(
              demandeeLe: DateTime(2026, 10, 26, 9, 40),
              cePoste: 'COMPTOIR-1',
              postes: [
                EtatPosteServeur(
                  posteId: 'COMPTOIR-1',
                  utilisateur: 'gerant',
                  derniereMontee: DateTime(2026, 10, 26, 11, 58),
                  derniereDescente: DateTime(2026, 10, 26, 11, 58, 20),
                  enAttente: 0,
                  demandeSuivie: true,
                  appaire: true,
                  appaireLe: DateTime(2026, 10, 12, 8),
                  jetonUtiliseLe: DateTime(2026, 10, 26, 11, 58),
                  dernierControle: DateTime(2026, 10, 25, 17, 5),
                  etat: EtatAppairage.actif,
                ),
                EtatPosteServeur(
                  posteId: 'RECEPTION-2',
                  utilisateur: 'reception',
                  derniereMontee: DateTime(2026, 10, 26, 10, 12),
                  derniereDescente: DateTime(2026, 10, 26, 10, 12, 30),
                  enAttente: 3,
                  demandeSuivie: false,
                  appaire: true,
                  appaireLe: DateTime(2026, 10, 14, 9),
                  jetonUtiliseLe: DateTime(2026, 10, 26, 10, 12),
                  dernierControle: DateTime(2026, 10, 24, 16, 30),
                  etat: EtatAppairage.silencieux,
                ),
              ],
            ),
          ),
        ),
      ],
    );
    await _photographier(tester, 'c16-postes-appairage');
  });

  // ---------------------------------------------------------------- Chap. 17
  _cas('c17-parametres-facturation-normalisee', (tester) async {
    final b = await tester.runAsync(bancAppaire);
    addTearDown(() => b!.fermer());
    // Le mode DESCEND du serveur (ici « boîtier ») ; le jeton, lui, ne descend
    // jamais : aucune valeur de jeton n'existe dans cette base.
    await tester.runAsync(() async {
      await ParametresDepotLocal(
        b!.db,
      ).inscrireDescendue('facturation_mode', 'boitier');
      // Une adresse de pilote CHOISIE (sinon « Adresse par défaut » n'est pas
      // offert) : celle du poste lui-même, enregistrée dans poste.json.
      await b.ecrivain.enregistrerAdresseBoitier('http://127.0.0.1:38917');
    });
    await monterEnCoquille(
      tester,
      b!,
      route: '/parametres',
      ecran: const EcranParametres(),
    );
    // Le défilement de la PAGE (le plus large) — le premier est celui du menu.
    final defiles = find.byType(Scrollable).evaluate().toList();
    var index = 0;
    var large = 0.0;
    for (var i = 0; i < defiles.length; i++) {
      final w = (defiles[i].renderObject! as RenderBox).size.width;
      if (w > large) {
        large = w;
        index = i;
      }
    }
    final defile = find.byType(Scrollable).at(index);
    await tester.scrollUntilVisible(
      find.byKey(const Key('param-mecef-tester')),
      200,
      scrollable: defile,
    );
    await _laisserTourner(tester);
    await tester.drag(defile, const Offset(0, -140));
    await _laisserTourner(tester);
    await _photographier(tester, 'c17-parametres-facturation-normalisee');
  });

  Future<AppDatabase> baseDeVente() async {
    final db = AppDatabase.enMemoire();
    await avecComptabilite(db, maintenant: DateTime(2026, 10, 10, 9));
    await db.into(db.cartesBoissonLocal).insert(
      CartesBoissonLocalCompanion.insert(
        id: 'bsn-33',
        articleId: 'art-bsn',
        libelle: 'Béninoise 33cl',
        categorie: 'locale',
        prixVente: 1000,
      ),
    );
    await db.into(db.categoriesHebergementLocal).insert(
      CategoriesHebergementLocalCompanion.insert(
        id: 'cat-1',
        libelle: 'Bungalow',
        capaciteMax: 2,
        tarifBase: 28000,
      ),
    );
    await db.into(db.unitesHebergementLocal).insert(
      UnitesHebergementLocalCompanion.insert(
        id: 'u-1',
        categorieId: 'cat-1',
        numero: 'BNG-01',
        statut: 'libre',
      ),
    );
    await db.into(db.clientsLocal).insert(
      ClientsLocalCompanion.insert(
        id: 'cli-1',
        nom: 'EXEMPLE',
        prenom: const Value('Client'),
        telephone: '+229 01 00 00 00 01',
        typeClient: 'particulier',
      ),
    );
    await db.into(db.reservationsLocal).insert(
      ReservationsLocalCompanion.insert(
        id: 'res-1',
        reference: 'LOC-RES1',
        clientId: 'cli-1',
        uniteId: 'u-1',
        dateArrivee: DateTime(2026, 10, 9),
        dateDepart: DateTime(2026, 10, 12),
        statut: 'confirmee',
        tarifNuit: 28000,
      ),
    );
    return db;
  }

  _cas('c17-modale-ifu-client', (tester) async {
    final db = await tester.runAsync(baseDeVente);
    addTearDown(() => db!.close());
    final depotPanier = PanierRepositoryLocal(
      panierDaoSur(db!, horloge: DateTime(2026, 10, 10, 9)),
    );
    final b = await tester.runAsync(bancAppaire);
    addTearDown(() => b!.fermer());
    await monterCoquille(
      tester,
      role: 'administrateur',
      login: 'admin',
      droits: _droitsAdmin,
      routeActive: '/pos-heberges',
      taille: const Size(_largeur, 1000),
      enfant: const EcranPosHeberges(),
      surcharges: [
        baseLocaleProvider.overrideWithValue(db),
        // Ce poste certifie par le boîtier : « Normaliser maintenant » est offert.
        certifieParProvider.overrideWith((ref) async => CertifiePar.boitier),
        depotPanierProvider.overrideWithValue(depotPanier),
        catalogueProvider.overrideWithValue(CatalogueDao(db)),
        depotReservationProvider.overrideWithValue(
          ReservationRepositoryLocal(ReservationDao(db)),
        ),
        cheminConfigurationPosteProvider.overrideWithValue(b!.chemin),
        ...surchargesHorlogeDeReference(),
      ],
    );
    await tester.tap(find.byKey(const Key('pos-sejour-res-1')));
    await _laisserTourner(tester);
    await tester.tap(find.byKey(const Key('pos-article-M5:bsn-33')));
    await _laisserTourner(tester);
    await tester.tap(find.byKey(const Key('pos-cloturer')));
    await _laisserTourner(tester, 30);
    await tester.enterText(
      find.byKey(ChampsAcheteurFacture.cleIfu),
      '1234567890123',
    );
    await tester.enterText(
      find.byKey(ChampsAcheteurFacture.cleNom),
      'Client Exemple',
    );
    await _laisserTourner(tester);
    await _photographier(tester, 'c17-modale-ifu-client');
  });

  // ---------------------------------------------------------------- Chap. 18
  _cas('c18-proformas-liste', (tester) async {
    final b = await tester.runAsync(bancAppaire);
    addTearDown(() => b!.fermer());
    await tester.runAsync(() async {
      final dao = ProformaDao(b!.db);
      await dao.creer(
        clientNom: 'SARL Horizon Voyages',
        objet: 'Séminaire de deux jours',
        lignes: const [
          (designation: 'Salle de réunion', quantite: 2, prixUnitaire: 50000),
          (designation: 'Pause-café', quantite: 20, prixUnitaire: 2500),
        ],
        emettre: true,
      );
      await dao.creer(
        clientNom: 'Association Les Amis du Parc',
        objet: 'Week-end découverte',
        lignes: const [
          (designation: 'Bungalow, 2 nuits', quantite: 2, prixUnitaire: 28000),
        ],
      );
      final annulee = await dao.creer(
        clientNom: 'Client Exemple',
        objet: 'Essai',
        lignes: const [
          (designation: 'Repas de groupe', quantite: 10, prixUnitaire: 5000),
        ],
        emettre: true,
      );
      await dao.annuler(annulee.id, 'Essai');
    });
    await monterEnCoquille(
      tester,
      b!,
      route: '/facturation/proformas',
      ecran: const EcranProformas(flux: ''),
      plus: [
        imprimerProformaProvider.overrideWithValue((id) async {}),
        reglagesDocumentsProvider.overrideWith(
          (ref) async => ReglagesDocuments.parDefaut,
        ),
      ],
    );
    await _photographier(tester, 'c18-proformas-liste');
  });

  _cas('c18-proforma-formulaire', (tester) async {
    final b = await tester.runAsync(bancAppaire);
    addTearDown(() => b!.fermer());
    await monterEnCoquille(
      tester,
      b!,
      route: '/facturation/proformas',
      ecran: const EcranProformas(flux: ''),
      hauteur: 1100,
      plus: [
        imprimerProformaProvider.overrideWithValue((id) async {}),
        reglagesDocumentsProvider.overrideWith(
          (ref) async => ReglagesDocuments.parDefaut,
        ),
      ],
    );
    Future<void> saisir(String cle, String texte) async {
      await tester.enterText(find.byKey(Key(cle)), texte);
      await tester.pump();
    }

    await tester.tap(find.byKey(const Key('proformas-nouvelle')));
    await _laisserTourner(tester);
    await saisir('proforma-client', 'SARL Horizon Voyages');
    await saisir('proforma-objet', 'Séminaire de deux jours');
    await saisir('proforma-ligne-0-designation', 'Salle de réunion');
    await saisir('proforma-ligne-0-quantite', '2');
    await saisir('proforma-ligne-0-prix', '50000');
    await _laisserTourner(tester);
    await _photographier(tester, 'c18-proforma-formulaire');
  });

  // ---------------------------------------------------------------- Chap. 19
  Future<({AppDatabase db, String adminId})> baseDeComptes() async {
    // ignore: invalid_use_of_visible_for_testing_member
    FlutterSecureStorage.setMockInitialValues({});
    final db = AppDatabase.enMemoire();
    await RolesDao(db).installerSocle();
    final depot = SessionRepositoryLocal(db);
    await depot.creerCompte(
      login: 'admin',
      nom: 'ADMINISTRATEUR Essai',
      motDePasse: 'Essai-Admin-9',
      role: 'administrateur',
      droits: socleRbacCdcf['administrateur']!,
    );
    // `monterCoquille` ouvre la session de l'identifiant « u-<rôle> » : le
    // compte porte le même, pour que la liste le marque « Vous ».
    const adminId = 'u-administrateur';
    await db.customStatement(
      "UPDATE utilisateurs_local SET id = '$adminId' WHERE login = 'admin'",
    );
    final dao = ComptesUtilisateursDao(db);
    for (final (login, nom, role) in const [
      ('caisse1', 'CAISSIER Un', 'gerant'),
      ('reception1', 'RECEPTION Un', 'receptionniste'),
      ('bar1', 'BARMAN Un', 'barman'),
    ]) {
      await dao.creerCompte(
        auteurId: adminId,
        nom: nom,
        identifiant: login,
        role: role,
        motDePasse: 'Essai-Compte-9',
        confirmation: 'Essai-Compte-9',
      );
    }
    final ids = {
      for (final u in await db.select(db.utilisateursLocal).get()) u.login: u.id,
    };
    // Un compte dont le mot de passe vient d'être réinitialisé (« Changement
    // requis ») et un compte désactivé.
    await dao.reinitialiserParAdministrateur(
      auteurId: adminId,
      compteId: ids['reception1']!,
    );
    await dao.definirActif(
      auteurId: adminId,
      compteId: ids['bar1']!,
      actif: false,
    );
    return (db: db, adminId: adminId);
  }

  Future<void> monterComptes(
    WidgetTester tester,
    ({AppDatabase db, String adminId}) c,
    Widget ecran,
    String route, {
    double hauteur = 1000,
  }) async {
    await monterCoquille(
      tester,
      role: 'administrateur',
      login: 'admin',
      droits: _droitsAdmin,
      routeActive: route,
      taille: Size(_largeur, hauteur),
      enfant: ecran,
      surcharges: [
        baseLocaleProvider.overrideWithValue(c.db),
        imprimerCodeSecoursProvider.overrideWithValue((code, compte) async {}),
        ...surchargesHorlogeDeReference(),
      ],
    );
    await _laisserTourner(tester, 30);
  }

  _cas('c19-comptes-utilisateurs', (tester) async {
    final c = await tester.runAsync(baseDeComptes);
    addTearDown(() => c!.db.close());
    await monterComptes(
      tester,
      c!,
      const EcranComptesUtilisateurs(),
      '/comptes-utilisateurs',
    );
    await _photographier(tester, 'c19-comptes-utilisateurs');
  });

  _cas('c19-temporaire-affiche', (tester) async {
    final c = await tester.runAsync(baseDeComptes);
    addTearDown(() => c!.db.close());
    await monterComptes(
      tester,
      c!,
      const EcranComptesUtilisateurs(),
      '/comptes-utilisateurs',
    );
    await tester.tap(find.byKey(const Key('comptes-reinitialiser-caisse1')));
    await _laisserTourner(tester);
    await tester.tap(find.byKey(const Key('comptes-mot-de-passe-enregistrer')));
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1500)),
    );
    await _laisserTourner(tester, 30);
    expect(find.byKey(const Key('comptes-temporaire-valeur')), findsOneWidget);
    await _photographier(tester, 'c19-temporaire-affiche');
  });

  _cas('c19-mon-profil-poste', (tester) async {
    final c = await tester.runAsync(baseDeComptes);
    addTearDown(() => c!.db.close());
    // Le code de secours, posé comme au premier démarrage : seul son dérivé est
    // stocké, la valeur n'est jamais affichée ici.
    await tester.runAsync(
      () => CodeSecoursLocal(c!.db).poser(login: 'admin'),
    );
    await monterComptes(
      tester,
      c!,
      const EcranMonProfil(),
      '/mon-profil',
      hauteur: 1500,
    );
    await _photographier(tester, 'c19-mon-profil-poste');
  });


  // ---------------------------------------------------------------- Chap. 15
  _cas('c15-sauvegardes-poste', (tester) async {
    final b = await tester.runAsync(() => bancAppaire(journee: true));
    addTearDown(() => b!.fermer());
    await monterEnCoquille(
      tester,
      b!,
      route: '/import-export',
      ecran: const EcranImportExport(),
    );
    await tester.tap(find.byKey(const Key('ie-onglet-sauvegardes')));
    await _laisserTourner(tester);
    await tester.tap(find.byKey(const Key('ie-generer-sauvegarde')));
    await _laisserTourner(tester, 60);
    expect(find.byKey(const Key('ie-sauvegarde-generee')), findsOneWidget);
    // Le message éphémère (toast) s'efface avant la prise de vue.
    await tester.pump(const Duration(seconds: 8));
    await _laisserTourner(tester);
    await _photographier(tester, 'c15-sauvegardes-poste');
  });

  // ---------------------------------------------------------------- Annexes
  _cas('x-poste-comptage-inventaire', (tester) async {
    final db = AppDatabase.enMemoire();
    addTearDown(db.close);
    await tester.runAsync(() async {
      await db.into(db.utilisateursLocal).insert(
        UtilisateursLocalCompanion.insert(
          id: 'u-administrateur',
          login: 'admin',
          nom: 'ADMINISTRATEUR Essai',
          role: 'administrateur',
          droitsJson: '{}',
          sel: 's',
          empreinte: 'e',
          iterations: 1,
          dateCreation: DateTime(2026, 10, 1),
          dateMotDePasse: DateTime(2026, 10, 1),
        ),
      );
    });
    final api = StocksApi(
      dao: StocksDao(db),
      peutLire: () => true,
      peutEcrire: () => true,
      auteurId: () => 'u-administrateur',
    );
    final magasin = await tester.runAsync(() async {
      final point =
          ((await api.creerPoint(libelle: 'Magasin')) as PointEnregistre)
              .point
              .id;
      for (final (id, nom, qte, cout, unite) in const [
        ('riz', 'Riz local', '10', '1250', 'sac'),
        ('huile', 'Huile de palme', '4', '2200', 'bidon'),
        ('sucre', 'Sucre', '6', '900', 'sac'),
        ('farine', 'Farine de maïs', '8', '1100', 'sac'),
      ]) {
        await api.enregistrerArticle(
          SaisieArticle(
            id: id,
            libelle: nom,
            categorie: 'Denrées',
            uniteMesure: unite,
            seuilAlerte: '5',
            suivi: SuiviArticle.permanent,
            pointStockageId: point,
            stockOuverture: qte,
            valeurAchat: cout,
          ),
        );
      }
      return point;
    });
    await monterCoquille(
      tester,
      role: 'administrateur',
      login: 'admin',
      droits: _droitsAdmin,
      routeActive: '/stocks/inventaires',
      taille: const Size(_largeur, 900),
      enfant: const EcranInventaires(),
      surcharges: [
        baseLocaleProvider.overrideWithValue(db),
        ...surchargesHorlogeDeReference(),
      ],
    );
    await tester.tap(find.byKey(const Key('inventaires-onglet-inventaire')));
    await _laisserTourner(tester);
    await tester.tap(find.byKey(Key('inventaire-cycle-$magasin-lancer')));
    await _laisserTourner(tester);
    for (final (article, quantite) in const [('riz', '12'), ('huile', '3')]) {
      await tester.tap(find.byKey(Key('inventaire-compter-$article')));
      await _laisserTourner(tester);
      await tester.enterText(
        find.byKey(const Key('comptage-quantite')),
        quantite,
      );
      await tester.tap(find.byKey(const Key('comptage-enregistrer')));
      await _laisserTourner(tester);
    }
    expect(find.byKey(const Key('inventaire-en-memoire')), findsOneWidget);
    await _photographier(tester, 'x-poste-comptage-inventaire');
  });

  _cas('x-poste-compta-bandeaux', (tester) async {
    const annee = 2026;
    final instant = DateTime(2026, 10, 12, 9);
    final db = await tester.runAsync(
      () => baseInstallee(maintenant: instant),
    );
    addTearDown(() => db!.close());
    final dossier = Directory.systemTemp.createTempSync('capt_compta_');
    addTearDown(() => dossier.deleteSync(recursive: true));
    final dao = ComptabiliteDao(db!);
    final moteur = moteurSur(db, maintenant: () => instant);
    final restaurant = await tester.runAsync(
      () async => (await dao.centreParLibelle('Restaurant'))!.id,
    );
    DemandePiece demande(String libelle, int centimes, String date) =>
        DemandePiece(
          journal: 'OD',
          date: date,
          libelle: libelle,
          lignes: [
            LigneDemandee(compte: '5711', debitCentimes: centimes),
            LigneDemandee(
              compte: '7061',
              creditCentimes: centimes,
              centreId: restaurant,
            ),
          ],
        );
    await tester.runAsync(() async {
      // Deux pièces saisies à la main, validées : le serveur ne les a pas
      // reprises ; la seconde est REFUSÉE par le serveur (« À traiter »).
      await moteur.saisirPiece(
        demande('Régularisation de caisse', 300000, '$annee-10-05'),
        auteurId: auteurEssai,
        valider: true,
      );
      await moteur.saisirPiece(
        demande('Recette de banquet', 120000, '$annee-10-08'),
        auteurId: auteurEssai,
        valider: true,
      );
      final ops = await OperationsSyncDao(
        db,
      ).operations(table: TableSynchronisee.piecesSaisie);
      await db.customStatement(
        "UPDATE operations_sync_local SET statut = 'rejete', "
        "derniere_erreur = 'Le compte 7061 est introuvable.' "
        "WHERE uuid_operation = '${ops.last.uuidOperation}'",
      );
      // Le miroir du serveur : sa propre pièce (ventes du mois).
      final miroir = EcrituresServeurDao(db);
      Future<void> ligne(String id, String compte, {int d = 0, int c = 0}) =>
          miroir.ajouterSiAbsente(
            id: id,
            annee: annee,
            codeJournal: 'VTE',
            numeroCompte: compte,
            libelleCompte: 'Compte $compte',
            classe: compte.substring(0, 1),
            dateEcriture: '$annee-10-06',
            libelle: 'Ventes du jour',
            debitCentimes: d,
            creditCentimes: c,
          );
      await ligne('s1', '5711', d: 1850000);
      await ligne('s2', '7061', c: 1850000);
    });
    final dossierPoste = '${dossier.path}/poste.json';
    await monterCoquille(
      tester,
      role: 'administrateur',
      login: 'admin',
      droits: _droitsAdmin,
      routeActive: '/comptabilite',
      taille: const Size(_largeur, 1100),
      enfant: const EcranComptabilite(ongletInitial: 'resultat'),
      surcharges: [
        baseLocaleProvider.overrideWithValue(db),
        cheminConfigurationPosteProvider.overrideWithValue(
          () async => dossierPoste,
        ),
        moteurComptableProvider.overrideWith(
          (ref) async => moteurSur(db, maintenant: () => instant),
        ),
        ...surchargesHorlogeDeReference(),
      ],
    );
    await _laisserTourner(tester, 40);
    expect(
      find.byKey(const Key('compta-etats-pieces-manuelles')),
      findsOneWidget,
    );
    await _photographier(tester, 'x-poste-compta-bandeaux');
  });


  // ----------------------------------------------- Documents imprimés (PDF)
  // Le PDF est produit par le VRAI générateur du poste, puis sa première page
  // est rastérisée avec `pdftoppm` (poppler) : ce n'est pas une capture d'un
  // lecteur PDF, mais la page elle-même.
  Future<void> rasteriser(
    WidgetTester tester,
    List<int> pdf,
    String nom,
  ) async {
    await tester.runAsync(() async {
      final dossier = Directory.systemTemp.createTempSync('capt_pdf_');
      try {
        final f = File('${dossier.path}/doc.pdf')..writeAsBytesSync(pdf);
        final sortie = Directory(_sortie!)..createSync(recursive: true);
        final r = await Process.run('pdftoppm', [
          '-r',
          '192',
          '-png',
          '-singlefile',
          '-f',
          '1',
          '-l',
          '1',
          f.path,
          '${sortie.path}/$nom',
        ]);
        if (r.exitCode != 0) fail('pdftoppm : ${r.stderr}');
      } finally {
        dossier.deleteSync(recursive: true);
      }
    });
  }

  _cas('c17-facture-normalisee-a4', (tester) async {
    // L'ÉCHANTILLON fictif du poste (filigrane « ÉCHANTILLON — SANS VALEUR
    // FISCALE »), jamais une vraie facture normalisée.
    final logo = File(AppAssets.logo).readAsBytesSync();
    final echantillons = await tester.runAsync(
      () => genererEchantillonsPoste(logo: logo),
    );
    final e = echantillons!.firstWhere(
      (x) => x.nom == '04_facture_A4_poste_normalisee.pdf',
    );
    await rasteriser(tester, e.pdf, 'c17-facture-normalisee-a4');
  });

  _cas('c18-proforma-a4', (tester) async {
    final db = AppDatabase.enMemoire();
    addTearDown(db.close);
    final dao = ProformaDao(db, maintenant: () => DateTime(2026, 10, 26, 9));
    // Identité de l'établissement FICTIVE : ni vrai téléphone, ni vrai e-mail.
    const entete = EnteteEtablissement(
      adresse: 'Quartier Exemple, Natitingou, Bénin',
      telephone: '+229 01 00 00 00 00',
      email: 'contact@exemple.bj',
      siteWeb: 'www.exemple.bj',
      ifu: '1234567890123',
      rccm: 'RB/NAT/00 B 000',
    );
    final reglages = ReglagesDocuments.depuis({
      ClesReglagesDocuments.activites: 'Hébergement, Restauration, Tourisme',
      ClesReglagesDocuments.villeEmission: 'Natitingou',
      ClesReglagesDocuments.signatureAffichee: 'true',
      ClesReglagesDocuments.signataireNom: 'DIRECTEUR Exemple',
      ClesReglagesDocuments.signataireFonction: 'Directeur Général',
      ClesReglagesDocuments.validiteAffichee: 'false',
    });
    final pdf = await tester.runAsync(() async {
      final p = await dao.creer(
        clientNom: 'SARL Horizon Voyages',
        clientTelephone: '0100000000',
        objet: 'Séminaire de deux jours',
        lignes: const [
          (designation: 'Salle de réunion', quantite: 2, prixUnitaire: 50000),
          (designation: 'Pause-café', quantite: 20, prixUnitaire: 2500),
        ],
        emettre: true,
        reglages: reglages,
      );
      final composee = ProformaA4.composer(
        proforma: (await dao.parId(p.id))!,
        lignes: await dao.lignes(p.id),
        entete: entete,
        reglages: reglages,
        maintenant: DateTime(2026, 10, 26),
      );
      return composee.pdf();
    });
    await rasteriser(tester, pdf!, 'c18-proforma-a4');
  });

}

/// Le serveur tel que le poste le lit : deux postes appairés (données fictives).
final class _SuiviEssai extends ServiceSuiviPostes {
  _SuiviEssai(this.etat)
    : super(transport: FauxTransport(reponseLot), urlServeur: null);

  final IssueSuiviPostes etat;

  @override
  Future<IssueSuiviPostes> lire() async => etat;
}

/// La matrice d'un administrateur : tous les modules en création.
const _droitsAdmin = <String, dynamic>{
  'M1': 'C', 'M2': 'C', 'M3': 'C', 'M4': 'C', 'M5': 'C', 'M6': 'C', //
  'M7': 'C', 'M8': 'C', 'M9': 'C', 'M10': 'C', 'M11': 'C', 'M12': 'C',
  'M13': 'C', 'M14': 'C', 'ROLES': 'C', 'PARAM': 'C',
};
