import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/fichiers/selecteur_fichiers.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/theme/app_spacing.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/vehicules/data/vehicule_dao.dart';
import 'package:tatacora_flutter/features/vehicules/domain/entities/contrat_location.dart';
import 'package:tatacora_flutter/features/vehicules/domain/entities/vehicule.dart';
import 'package:tatacora_flutter/features/vehicules/domain/indicateurs_vehicules.dart';
import 'package:tatacora_flutter/features/vehicules/domain/regles_vehicules.dart';
import 'package:tatacora_flutter/features/vehicules/impression/etat_vehicules.dart';
import 'package:tatacora_flutter/features/vehicules/presentation/ecran_vehicules.dart';
import 'package:tatacora_flutter/features/vehicules/presentation/providers_vehicules.dart';
import 'package:tatacora_flutter/features/vehicules/presentation/widgets/barre_filtres_vehicules.dart';

import '../../support/selecteur_essai.dart';

/// L'écran M8 monté pour de vrai, contre une vraie base Drift en mémoire.
///
/// ## Ce que ces cas protègent
///
/// Le 09/10/2026, l'écran a été recalé sur la vue Blade
/// (`vehicules/locations.blade.php`). Chaque cas ci-dessous éprouve UN
/// comportement de ce recalage, avec des valeurs et des messages EXACTS — un
/// `findsWidgets` ne voit pas un chiffre faux.
///
/// ## Horloge
///
/// `periodeVehiculesProvider` démarre sur `DateTime.now()`. Chaque cas pose la
/// période explicitement (14 au 28 septembre 2026, soit 14 jours) : sans cela,
/// le planning compterait un nombre de jours qui dépend du jour d'exécution. La
/// seule lecture d'horloge restante est celle de `archiverVehicule`, qui juge
/// un contrat « en cours » sur `DateTime.now()` ; le cas qui en dépend pose un
/// contrat en 2099.
void main() {
  late AppDatabase db;
  late VehiculeDao dao;

  /// Le véhicule loué du jeu ; les deux autres (entretien, hors service) ne
  /// sont pas relus individuellement. Rempli par [semer].
  late Vehicule libre;
  late Vehicule horsService;
  late Vehicule entretien;

  setUp(() {
    db = AppDatabase.enMemoire();
    dao = VehiculeDao(db);
  });

  tearDown(() => db.close());

  Future<void> semerClient() => db
      .into(db.clientsLocal)
      .insert(
        ClientsLocalCompanion.insert(
          id: 'cli-1',
          nom: 'KORA',
          telephone: '+229 01 00 00 00 01',
          typeClient: 'particulier',
        ),
      );

  /// Trois véhicules et UN contrat : `AB 1234 RB` loué du 14 au 16 septembre
  /// (2 jours x 25 000 = 50 000 FCFA).
  Future<void> semer() async {
    await semerClient();
    libre = await dao.enregistrerVehicule(
      immatriculation: 'AB 1234 RB',
      categorie: CategorieVehicule.voiture,
      tarifJour: 25000,
    );
    entretien = await dao.enregistrerVehicule(
      immatriculation: 'CD 5678 RB',
      categorie: CategorieVehicule.quatreQuatre,
      tarifJour: 40000,
      statut: StatutVehicule.entretien,
    );
    horsService = await dao.enregistrerVehicule(
      immatriculation: 'EF 9012 RB',
      categorie: CategorieVehicule.moto,
      tarifJour: 15000,
      statut: StatutVehicule.horsService,
    );
    await dao.creerContrat(
      SaisieContrat(
        vehiculeId: libre.id,
        clientId: 'cli-1',
        debut: DateTime(2026, 9, 14),
        fin: DateTime(2026, 9, 16),
        pieceIdentite: 'CNI-123',
        permisConduire: 'PC-456',
      ),
    );
  }

  Future<void> monter(
    WidgetTester tester, {
    List<Override> surcharges = const [],
    double largeur = 1600,
  }) async {
    tester.view
      ..physicalSize = Size(largeur, 2400)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseLocaleProvider.overrideWithValue(db),
          droitsProvider.overrideWithValue(
            GardeAcces.depuisJson(const {'M8': 'C', 'M3': 'C'}),
          ),
          ...surcharges,
        ],
        child: MaterialApp(
          theme: AppTheme.clair,
          home: const Scaffold(body: EcranVehicules()),
        ),
      ),
    );
    await tester.pump();

    // L'horloge est posée, pas lue.
    ProviderScope.containerOf(
        tester.element(find.byType(EcranVehicules)),
      ).read(periodeVehiculesProvider.notifier)
      ..definirDebut('2026-09-14')
      ..definirFin('2026-09-28');
    await tester.pumpAndSettle();
  }

  Future<void> ouvrirOnglet(WidgetTester tester, String cle) async {
    await tester.tap(find.byKey(Key('vehicules-onglet-$cle')));
    await tester.pumpAndSettle();
  }

  String texteDe(WidgetTester tester, Finder f) =>
      tester.widget<Text>(f).data ?? '';

  /// Le texte d'une carte de la bande : valeur et détail, dans l'ordre.
  List<String> carte(WidgetTester tester, String id) {
    final textes = find.descendant(
      of: find.byKey(Key('vehicules-kpi-$id')),
      matching: find.byType(Text),
    );
    return [
      for (var i = 0; i < textes.evaluate().length; i++)
        texteDe(tester, textes.at(i)),
    ];
  }

  /* ================================================================== */
  group('La bande d’indicateurs — valeurs réelles, jamais un zéro plausible', () {
    testWidgets('avec des données : six cartes, chiffres exacts', (
      tester,
    ) async {
      await semer();
      await monter(tester);

      // Libellés en MAJUSCULES (rendu CSS `uppercase`), puis valeur, détail.
      expect(carte(tester, 'parc'), ['PARC', '3', '2 immobilisé(s)']);
      expect(carte(tester, 'contrats'), [
        'CONTRATS ACTIFS',
        '1',
        '— annulé(s)',
      ]);
      expect(carte(tester, 'ca'), [
        "CHIFFRE D'AFFAIRES",
        '50 000 FCFA',
        '2 jour(s) loué(s)',
      ]);
      // 2 jours loués / (3 véhicules x 14 jours) = 4,76 % -> 5 %.
      expect(carte(tester, 'occupation'), [
        "TAUX D'OCCUPATION",
        '5 %',
        'Sur la période',
      ]);
      expect(carte(tester, 'reste'), [
        'RESTE À ENCAISSER',
        '—',
        'Soldes de location',
      ]);
      expect(carte(tester, 'jours'), ['JOURS LOUÉS', '2', 'Toutes catégories']);
    });

    testWidgets(
      'sans aucune donnée : « 0 FCFA » est la MESURE, le taux est « — » '
      'et garde son détail',
      (tester) async {
        await monter(tester);

        expect(carte(tester, 'parc'), ['PARC', '0', 'Aucune immobilisation']);
        // La somme porte sur les contrats de ce poste, tous lus : zéro contrat,
        // zéro franc. Ce n'est pas une absence de source.
        expect(carte(tester, 'ca'), [
          "CHIFFRE D'AFFAIRES",
          '0 FCFA',
          '0 jour(s) loué(s)',
        ]);
        // Aucun véhicule : le taux n'a pas de sens, « 0 % » se lirait comme un
        // parc inoccupé. Le détail de la vue reste posé (l.148-149).
        expect(carte(tester, 'occupation'), [
          "TAUX D'OCCUPATION",
          '—',
          'Sur la période',
        ]);
      },
    );

    testWidgets('la raison d’une absence est dans l’infobulle, pas dans la '
        'carte', (tester) async {
      await monter(tester);

      final infobulle = tester.widget<Tooltip>(
        find.byKey(const Key('vehicules-kpi-reste-raison')),
      );
      expect(
        infobulle.message,
        IndicateursVehicules.raisons['reste_a_encaisser'],
      );
      // Elle n'est PAS écrite sous le détail : sur six cartes côte à côte, la
      // plus bavarde poussait toute la page de ~96 px.
      expect(
        find.text(IndicateursVehicules.raisons['reste_a_encaisser']!),
        findsNothing,
      );
      // Et la raison du taux ne ment plus sur une période pourtant choisie.
      final taux = tester.widget<Tooltip>(
        find.byKey(const Key('vehicules-kpi-occupation-raison')),
      );
      expect(
        taux.message,
        'Aucun taux sans période choisie ni véhicule au parc : « 0 % » se '
        'lirait comme un parc inoccupé.',
      );
    });
  });

  /* ================================================================== */
  group('« Exporter » : un seul bouton, la modale de format', () {
    testWidgets('la paire « Excel » / « PDF » n’existe plus', (tester) async {
      await monter(tester);

      expect(find.byKey(const Key('vehicules-exporter')), findsOneWidget);
      expect(find.text('Exporter'), findsOneWidget);
      expect(find.text('Excel'), findsNothing);
      expect(find.text('PDF'), findsNothing);
      expect(find.byKey(const Key('vehicules-excel')), findsNothing);
      expect(find.byKey(const Key('vehicules-pdf')), findsNothing);
    });

    testWidgets('la modale porte le titre de la vue, ses deux formats et '
        'la note du CSV — plus d’aide qui annonce un PDF refusé', (
      tester,
    ) async {
      await monter(tester);
      await tester.tap(find.byKey(const Key('vehicules-exporter')));
      await tester.pumpAndSettle();

      expect(
        find.text('Exporter le rapport Véhicules & Locations'),
        findsOneWidget,
      );
      expect(find.text('Format du document'), findsOneWidget);
      expect(find.text('PDF Officiel A4 Imprimable'), findsOneWidget);
      expect(find.text('Tableur Excel (.xlsx / .csv)'), findsOneWidget);
      expect(find.text('Générer & Télécharger'), findsOneWidget);
      // Le PDF est produit depuis le 14/10/2026 : la modale dit ce que le
      // tableur produit (un CSV), et plus aucune aide propre à l'écran.
      expect(find.byKey(const Key('export-note-csv')), findsOneWidget);
      expect(find.byKey(const Key('export-aide')), findsNothing);
    });

    testWidgets('le tableur écrit le CSV de l’onglet AFFICHÉ et montre le '
        'chemin', (tester) async {
      await semer();
      final recus = <EtatVehicules>[];
      await monter(
        tester,
        surcharges: [
          exporterVehiculesProvider.overrideWithValue((etat) async {
            recus.add(etat);
            return 'C:/export/vehicules.csv';
          }),
        ],
      );
      await tester.tap(find.byKey(const Key('vehicules-exporter')));
      await tester.pumpAndSettle();
      // D434 : le PDF est présélectionné partout ; le tableur se choisit.
      await tester.tap(find.byKey(const Key('export-format-excel')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Générer & Télécharger'));
      await tester.pumpAndSettle();

      expect(recus, hasLength(1));
      expect(recus.single.titre, 'Disponibilité du parc');
      expect(recus.single.periode, 'Du 2026-09-14 au 2026-09-28');
      // Les trois véhicules du parc, ni plus ni moins.
      expect(recus.single.lignes, hasLength(3));
      expect(
        {for (final l in recus.single.lignes) l.first},
        {'AB 1234 RB', 'CD 5678 RB', 'EF 9012 RB'},
      );
      // Le toast commun dit le NOM du fichier enregistré.
      expect(
        tester
            .widget<Text>(find.byKey(const Key('vehicules-export-fait')))
            .data,
        'Export enregistré : vehicules.csv',
      );
    });

    testWidgets('l’export suit l’onglet : Contrats exporte les contrats', (
      tester,
    ) async {
      await semer();
      final recus = <EtatVehicules>[];
      await monter(
        tester,
        surcharges: [
          exporterVehiculesProvider.overrideWithValue((etat) async {
            recus.add(etat);
            return 'C:/export/contrats.csv';
          }),
        ],
      );
      await ouvrirOnglet(tester, 'contrats');
      await tester.tap(find.byKey(const Key('vehicules-exporter')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('export-format-excel')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Générer & Télécharger'));
      await tester.pumpAndSettle();

      expect(recus.single.titre, 'Contrats de location');
      expect(recus.single.lignes, hasLength(1));
      // Colonnes « Du » et « Au » : les dates du contrat.
      expect(recus.single.lignes.single[5], '2026-09-14');
      expect(recus.single.lignes.single[6], '2026-09-16');
    });

    testWidgets('choisir le PDF PRODUIT l’état A4, enregistré en .pdf par '
        '« Enregistrer sous », et le toast le dit', (tester) async {
      await semer();
      final selecteur = SelecteurEssai();
      var appelsCsv = 0;
      await monter(
        tester,
        surcharges: [
          ...selecteur.surcharges,
          exporterVehiculesProvider.overrideWithValue((etat) async {
            appelsCsv++;
            return 'jamais.csv';
          }),
        ],
      );
      await tester.tap(find.byKey(const Key('vehicules-exporter')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('PDF Officiel A4 Imprimable'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Générer & Télécharger'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('vehicules-pdf-refuse')), findsNothing);
      expect(appelsCsv, 0, reason: 'le PDF ne passe pas par le tableur');
      expect(selecteur.ecrits, hasLength(1));
      final pdf = selecteur.ecrits.single;
      expect(pdf.type, TypeFichierEnregistre.pdf);
      expect(pdf.nom, matches(RegExp(r'^vehicules_\d{4}-\d{2}-\d{2}\.pdf$')));
      expect(pdf.estUnPdf, isTrue);
      expect(pdf.dossierInitial, SelecteurEssai.dossierDocuments);
      expect(find.byKey(const Key('vehicules-export-fait')), findsOneWidget);
    });

    testWidgets('une liste vide est REFUSÉE, rien n’est écrit', (tester) async {
      var appels = 0;
      await monter(
        tester,
        surcharges: [
          exporterVehiculesProvider.overrideWithValue((etat) async {
            appels++;
            return 'jamais.csv';
          }),
        ],
      );
      await tester.tap(find.byKey(const Key('vehicules-exporter')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('export-format-excel')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Générer & Télécharger'));
      await tester.pumpAndSettle();

      expect(find.text(BoutonExporterVehicules.exportVide), findsOneWidget);
      expect(appels, 0);
    });

    test('l’enregistrement du CSV : par « Enregistrer sous », BOM et octets '
        'inchangés', () async {
      final selecteur = SelecteurEssai();
      final conteneur = ProviderContainer(overrides: selecteur.surcharges);
      addTearDown(conteneur.dispose);
      const etat = EtatVehicules(
        titre: 'Disponibilité du parc',
        periode: 'Du 2026-09-14 au 2026-09-28',
        entetes: ['Véhicule'],
        lignes: [
          ['AB 1234 RB'],
        ],
      );

      final chemin = await conteneur.read(exporterVehiculesProvider)(etat);

      final ecrit = selecteur.ecrits.single;
      expect(chemin, 'C:/essai/${ecrit.nom}');
      expect(ecrit.type, TypeFichierEnregistre.csv);
      expect(ecrit.nom, matches(RegExp(r'^vehicules_\d{4}-\d{2}-\d{2}\.csv$')));
      expect(ecrit.dossierInitial, SelecteurEssai.dossierDocuments);
      final relus = ecrit.octets;
      expect(relus, etat.csvOctets());
      expect(relus.take(3), [0xEF, 0xBB, 0xBF]);
      expect(utf8.decode(relus), contains('AB 1234 RB'));
    });

    test('le CSV est de l’UTF-8 réel, BOM compris', () {
      const etat = EtatVehicules(
        titre: 'Disponibilité du parc',
        periode: 'Du 2026-09-14 au 2026-09-28',
        entetes: ['Véhicule'],
        lignes: [
          ['Pick-up é'],
        ],
      );
      final octets = etat.csvOctets();

      // Le BOM, puis « é » sur DEUX octets (0xC3 0xA9), jamais l'unité de code
      // UTF-16 0xE9 écrite telle quelle.
      expect(octets.take(3), [0xEF, 0xBB, 0xBF]);
      expect(utf8.decode(octets).contains('Véhicule'), isTrue);
      final i = octets.indexOf(0xC3);
      expect(octets[i + 1], 0xA9);
      expect(octets.contains(0xE9), isFalse);
    });
  });

  /* ================================================================== */
  group('Onglet « Parc & disponibilité »', () {
    testWidgets('le bandeau est DEUX textes de la vue, et la divergence '
        'd’un ancien prototype n’y est plus', (tester) async {
      await semer();
      await monter(tester);

      expect(find.text('Tarifs « chauffeur inclus ».'), findsOneWidget);
      expect(
        find.text(
          "C'est une caractéristique du tarif catalogue, pas une option "
          "facturée en plus. Le permis n'est exigé que pour les catégories "
          'qui le requièrent.',
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('vehicules-parc-divergence-permis')),
        findsNothing,
      );
      expect(find.textContaining('Divergence de règle'), findsNothing);
    });

    testWidgets('le titre porte les dates au format d/m/Y et les lignes '
        'leurs montants exacts', (tester) async {
      await semer();
      await monter(tester);

      expect(find.text('Parc — du 14/09/2026 au 28/09/2026'), findsOneWidget);
      // Tarif / jour, puis Montant période = 14 jours x tarif.
      expect(find.text('25 000 FCFA'), findsOneWidget);
      expect(find.text('350 000 FCFA'), findsOneWidget);
      expect(find.text('40 000 FCFA'), findsOneWidget);
      expect(find.text('560 000 FCFA'), findsOneWidget);
      // Disponibilité : le loué est « Engagé » (contrat du 14 au 16), le hors
      // service le dit — deux pastilles distinctes, jamais confondues.
      expect(find.byKey(Key('vehicules-engage-${libre.id}')), findsOneWidget);
      expect(
        find.byKey(Key('vehicules-hors-service-${horsService.id}')),
        findsOneWidget,
      );
      expect(find.byKey(Key('vehicules-dispo-${libre.id}')), findsNothing);
    });

    testWidgets('sans véhicule : le message de la vue, seul, dans sa carte', (
      tester,
    ) async {
      await monter(tester);

      expect(find.text('Aucun véhicule ne correspond.'), findsOneWidget);
      expect(
        find.text('Le parc se saisit sur ce poste : « + Véhicule ».'),
        findsOneWidget,
      );
      // Ni titre « Parc — du … », ni en-têtes : la vue ne rend QUE la carte.
      expect(find.textContaining('Parc — du'), findsNothing);
      expect(find.text('CATÉGORIE'), findsNothing);
    });
  });

  /* ================================================================== */
  group('Onglet « Contrats »', () {
    testWidgets('dates d/m/Y, ligne TOTAL exacte', (tester) async {
      await semer();
      await monter(tester);
      await ouvrirOnglet(tester, 'contrats');

      expect(find.text('Contrats de location'), findsOneWidget);
      expect(find.text('14/09/2026'), findsOneWidget);
      expect(find.text('16/09/2026'), findsOneWidget);
      expect(find.text('TOTAL — 1 contrat(s) actif(s)'), findsOneWidget);
      expect(
        find.byKey(const Key('vehicules-contrats-total-montant')),
        findsOneWidget,
      );
      expect(
        texteDe(
          tester,
          find.byKey(const Key('vehicules-contrats-total-montant')),
        ),
        '50 000 FCFA',
      );
    });

    testWidgets('sans contrat : le message de la vue, seul', (tester) async {
      await monter(tester);
      await ouvrirOnglet(tester, 'contrats');

      expect(
        find.text('Aucun contrat ne correspond à ces critères.'),
        findsOneWidget,
      );
      expect(find.text('Contrats de location'), findsNothing);
      expect(find.byKey(const Key('vehicules-contrats-total')), findsNothing);
    });
  });

  /* ================================================================== */
  group('Onglet « Planning du parc »', () {
    testWidgets('14 jours comme la vue, trois couches, cases exactes', (
      tester,
    ) async {
      await semer();
      await monter(tester);
      await ouvrirOnglet(tester, 'planning');

      // 14 jours, pas 15 : la restitution n'est pas un jour de la grille.
      expect(find.text('Planning du parc — 14 jour(s)'), findsOneWidget);
      expect(find.text('libre'), findsOneWidget);
      expect(find.text('location'), findsOneWidget);
      expect(find.text('immobilisé'), findsOneWidget);
      // La couche « circuit » est celle de l'ancien prototype : la vue n'en
      // dessine que trois.
      expect(find.byKey(const Key('planning-legende-circuit')), findsNothing);
      expect(find.textContaining('non rendue'), findsNothing);

      // 3 véhicules x 14 jours = 42 cases : 2 louées (14 et 15 sept.), 14 d'un
      // véhicule hors service (rouge tous les jours), 26 libres. L'« entretien »
      // n'est PAS rouge : la vue ne colore que `hors_service` (l.507).
      Finder cases(String etat, [String? vehiculeId]) => find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith(
              'planning-case-$etat-${vehiculeId ?? ''}',
            ),
      );

      expect(cases('loue'), findsNWidgets(2));
      expect(cases('loue', libre.id), findsNWidgets(2));
      // Rouge : le véhicule HORS SERVICE, 14 jours — et lui seul. Le véhicule
      // en entretien n'a AUCUNE case rouge (la vue ne colore que `hors_service`).
      expect(cases('immobilise'), findsNWidgets(14));
      expect(cases('immobilise', horsService.id), findsNWidgets(14));
      expect(cases('immobilise', entretien.id), findsNothing);
      expect(cases('libre', entretien.id), findsNWidgets(14));
      expect(cases('libre'), findsNWidgets(26));
      // Tarif de la sous-ligne, formaté comme la vue.
      expect(find.text('25 000 FCFA/j'), findsOneWidget);
      expect(find.text('15 000 FCFA/j'), findsOneWidget);
    });

    testWidgets('les deux encadrés de l’ancien prototype ont disparu', (
      tester,
    ) async {
      await semer();
      await monter(tester);
      await ouvrirOnglet(tester, 'planning');

      expect(
        find.byKey(const Key('vehicules-planning-deux-modules')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('vehicules-planning-couches-absentes')),
        findsNothing,
      );
    });

    testWidgets('sans véhicule : titre, légende et en-tête restent, aucune '
        'case', (tester) async {
      await monter(tester);
      await ouvrirOnglet(tester, 'planning');

      expect(find.text('Planning du parc — 14 jour(s)'), findsOneWidget);
      expect(find.text('libre'), findsOneWidget);
      expect(find.text('VÉHICULE'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('planning-case-'),
        ),
        findsNothing,
      );
      expect(find.text('Aucun véhicule au parc.'), findsNothing);
    });

    // D433 (14/10/2026) : colonne Véhicule FIGÉE, jours seuls à défiler,
    // rangées de hauteur fixe, cases élargies jusqu'au bord quand elles
    // tiennent.
    Finder casesDe(String vehiculeId) => find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('planning-case-') &&
          (w.key! as ValueKey<String>).value.contains(vehiculeId),
    );

    testWidgets('fenêtre étroite : les jours défilent, la colonne Véhicule '
        'reste FIGÉE et alignée sur sa rangée', (tester) async {
      await semer();
      await monter(tester, largeur: 900);
      // 61 jours : plus que la fenêtre n'en montre au plancher de la case.
      ProviderScope.containerOf(
        tester.element(find.byType(EcranVehicules)),
      ).read(periodeVehiculesProvider.notifier).definirFin('2026-11-14');
      await tester.pumpAndSettle();
      await ouvrirOnglet(tester, 'planning');
      expect(tester.takeException(), isNull);

      final tarif = find.text('25 000 FCFA/j');
      final premiere = casesDe(libre.id).first;
      final avantTarif = tester.getTopLeft(tarif);
      final avantCase = tester.getTopLeft(premiere);
      // La pastille porte le `px-1` de la case : plancher moins 2 × 4 px.
      expect(
        tester.getSize(premiere).width,
        greaterThanOrEqualTo(AppLayout.caseJourPlanning - 2 * AppSpacing.unit),
      );
      expect(
        tester.getSize(premiere).height,
        lessThanOrEqualTo(AppLayout.hauteurLignePlanning),
      );
      // Même rangée : la cellule du véhicule et ses cases ont le même haut.
      final rangee = find.ancestor(
        of: tarif,
        matching: find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.constraints?.maxHeight == AppLayout.hauteurLignePlanning,
        ),
      );
      expect(
        tester.getTopLeft(rangee.first).dy,
        closeTo(
          tester.getCenter(premiere).dy - AppLayout.hauteurLignePlanning / 2,
          AppLayout.hauteurLignePlanning / 2,
        ),
      );

      await tester.drag(
        find.byKey(const Key('planning-jours-defilement')),
        const Offset(-300, 0),
      );
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(tarif), avantTarif);
      expect(tester.getTopLeft(premiere).dx, lessThan(avantCase.dx));
    });

    testWidgets('fenêtre large : les cases s’élargissent jusqu’au bord, rien '
        'ne défile', (tester) async {
      await semer();
      await monter(tester);
      await ouvrirOnglet(tester, 'planning');

      final cases = casesDe(libre.id);
      expect(
        tester.getSize(cases.first).width + 2 * AppSpacing.unit,
        greaterThan(AppLayout.caseJourPlanning),
      );
      final defilement = find.byKey(const Key('planning-jours-defilement'));
      expect(
        tester.getTopRight(cases.last).dx,
        // Le `px-1` de la dernière case, pas un vide de colonne.
        closeTo(tester.getTopRight(defilement).dx - AppSpacing.unit, 0.5),
      );
    });
  });

  /* ================================================================== */
  group('Onglet « Immobilisations »', () {
    testWidgets('les sept en-têtes restent AU-DESSUS du message vide', (
      tester,
    ) async {
      await monter(tester);
      await ouvrirOnglet(tester, 'immo');

      expect(find.text('Immobilisations du parc'), findsOneWidget);
      for (final entete in [
        'VÉHICULE',
        'MOTIF',
        'DU',
        'AU',
        'JOURS',
        'COMMENTAIRE',
        'ENREGISTRÉ PAR',
      ]) {
        expect(find.text(entete), findsOneWidget, reason: entete);
      }
      // Le message de la vue, au mot, dans son propre texte.
      expect(find.text('Aucune immobilisation enregistrée.'), findsOneWidget);
      // La précision et l'encadré ambre sont RETIRÉS (directive du PO,
      // 14/10/2026) : l'onglet se termine sur l'état vide de la vue, au mot.
      expect(find.textContaining('Aucune table ne les porte'), findsNothing);
      expect(
        find.byKey(const Key('vehicules-immo-sans-lecture')),
        findsNothing,
      );
      final enteteY = tester.getTopLeft(find.text('VÉHICULE')).dy;
      final videY = tester
          .getTopLeft(find.text('Aucune immobilisation enregistrée.'))
          .dy;
      expect(enteteY, lessThan(videY));
    });
  });

  /* ================================================================== */
  group('Immobiliser — un entretien daté, écrit et affiché', () {
    testWidgets('le bouton écrit la ligne, le statut ne bouge pas, l’onglet '
        'la montre', (tester) async {
      await semer();
      final avant = (await dao.vehicule(libre.id))?.statut;
      await monter(tester);

      await tester.ensureVisible(
        find.byKey(const Key('vehicules-immobiliser')),
      );
      await tester.tap(find.byKey(const Key('vehicules-immobiliser')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('modale-immobilisation')), findsOneWidget);

      await tester.tap(find.byKey(const Key('modale-immobilisation-vehicule')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('AB 1234 RB').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('modale-immobilisation-cout')),
        '15000',
      );
      await tester.tap(find.byKey(const Key('modale-immobilisation-valider')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('modale-immobilisation')), findsNothing);
      final lignes = await dao.entretiens();
      expect(lignes, hasLength(1));
      expect(lignes.single.coutFrancs, 15000);
      expect(
        (await dao.vehicule(libre.id))?.statut,
        avant,
        reason: 'statut ≠ disponibilité : la PWA ne le touche pas',
      );

      await ouvrirOnglet(tester, 'immo');
      expect(find.text('AB 1234 RB'), findsWidgets);
      expect(find.text('Entretien'), findsWidgets);
      expect(find.text('Aucune immobilisation enregistrée.'), findsNothing);
    });

    testWidgets('un coût illisible est refusé sous son champ, rien n’est '
        'écrit', (tester) async {
      await semer();
      await monter(tester);

      await tester.ensureVisible(
        find.byKey(const Key('vehicules-immobiliser')),
      );
      await tester.tap(find.byKey(const Key('vehicules-immobiliser')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('modale-immobilisation-vehicule')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('AB 1234 RB').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('modale-immobilisation-cout')),
        'beaucoup',
      );
      await tester.tap(find.byKey(const Key('modale-immobilisation-valider')));
      await tester.pumpAndSettle();

      expect(
        find.text(MessagesVehicules.coutEntretienInvalide),
        findsOneWidget,
      );
      expect(await dao.entretiens(), isEmpty);
    });
  });

  /* ================================================================== */
  group('La barre de filtres', () {
    testWidgets('large : la recherche est basse, les trois boutons finissent '
        'À DROITE', (tester) async {
      await monter(tester);

      // 36 px comme au relevé, pas les 48 px du gabarit Material.
      final recherche = tester.getSize(
        find.byKey(const Key('vehicules-recherche')),
      );
      expect(recherche.height, inInclusiveRange(34, 40));

      // Bord droit de la carte = 1600 - 32 (p-8) ; le dernier bouton s'arrête
      // 14 (p-3.5) + 1 (bordure de la carte) en deçà.
      final bouton = tester.getTopRight(
        find.byKey(const Key('vehicules-nouveau-contrat')),
      );
      const droiteCarte = 1600 - AppSpacing.xl;
      expect(
        bouton.dx,
        closeTo(
          droiteCarte - AppSpacing.smPlus - AppLayout.bordureControle,
          0.5,
        ),
      );
    });

    testWidgets('large : la recherche et l’espace `flex-1` se partagent le '
        'reste à égalité', (tester) async {
      await monter(tester);

      final recherche = tester.getSize(
        find.byKey(const Key('vehicules-recherche')),
      );
      final droiteStatut = tester
          .getTopRight(find.byKey(const Key('vehicules-filtre-statut')))
          .dx;
      final gaucheBoutons = tester
          .getTopLeft(find.byKey(const Key('vehicules-nouveau-vehicule')))
          .dx;

      // Entre la liste de statut et le premier bouton : un écart de 10, le
      // `<div class="flex-1">` de la vue (l.196), un écart de 10. Il vaut la
      // recherche, qui est l'autre `flex-1` : sans cet espace, la recherche
      // avalerait tout le reste.
      expect(
        gaucheBoutons - droiteStatut,
        closeTo(recherche.width + 2 * AppSpacing.xsPlus, 1),
      );
    });

    testWidgets('étroit : la barre passe à la ligne sans déborder', (
      tester,
    ) async {
      await monter(tester, largeur: 700);

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('vehicules-nouveau-contrat')), findsOne);
    });
  });

  /* ================================================================== */
  group('La page', () {
    testWidgets('32 px de marge au poste de travail, 20 px en dessous', (
      tester,
    ) async {
      await monter(tester, largeur: 1600);
      expect(
        tester.getTopLeft(find.text('Véhicules & Locations')).dx,
        // 32 de marge + 24 d'icône + 10 d'écart.
        closeTo(
          AppSpacing.xl + AppLayout.iconeTitrePage + AppSpacing.xsPlus,
          0.5,
        ),
      );

      await monter(tester, largeur: 900);
      expect(
        tester.getTopLeft(find.text('Véhicules & Locations')).dx,
        closeTo(
          AppSpacing.mdPlus + AppLayout.iconeTitrePage + AppSpacing.xsPlus,
          0.5,
        ),
      );
    });
  });

  /* ================================================================== */
  group('« Archiver » passe par la modale PARTAGÉE de la vue', () {
    testWidgets('la question de la vue, puis le véhicule quitte le parc '
        'actif', (tester) async {
      await semer();
      await monter(tester);

      // `AB 1234 RB` est engagé le 14-16 septembre 2026 : passé pour l'horloge
      // réelle, donc archivable.
      await tester.tap(find.byKey(Key('vehicules-archiver-${libre.id}')));
      await tester.pumpAndSettle();

      expect(find.text('Confirmer la suppression'), findsOneWidget);
      expect(
        find.text('Voulez-vous archiver le véhicule AB 1234 RB ?'),
        findsOneWidget,
      );
      expect(find.text('Supprimer définitivement'), findsOneWidget);

      await tester.tap(find.text('Supprimer définitivement'));
      await tester.pumpAndSettle();

      expect(
        (await dao.vehicule(libre.id))!.statut,
        StatutVehicule.horsService,
      );
      expect(
        find.text(
          'Véhicule AB 1234 RB retiré du parc actif — il reste consultable.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('annuler ne change rien', (tester) async {
      await semer();
      await monter(tester);

      await tester.tap(find.byKey(Key('vehicules-archiver-${libre.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();

      // Inchangé : `loue`, posé par le contrat du jeu — ni `hors_service`, ni
      // un retour à `disponible`.
      expect((await dao.vehicule(libre.id))!.statut, StatutVehicule.loue);
    });

    testWidgets('un véhicule engagé : le refus du DAO est affiché tel quel', (
      tester,
    ) async {
      await semerClient();
      final v = await dao.enregistrerVehicule(
        immatriculation: 'GH 3456 RB',
        categorie: CategorieVehicule.voiture,
        tarifJour: 25000,
      );
      // 2099 : « à venir » pour toute horloge réelle.
      await dao.creerContrat(
        SaisieContrat(
          vehiculeId: v.id,
          clientId: 'cli-1',
          debut: DateTime(2099, 1, 1),
          fin: DateTime(2099, 1, 5),
          pieceIdentite: 'CNI-123',
          permisConduire: 'PC-456',
        ),
      );
      await monter(tester);

      await tester.tap(find.byKey(Key('vehicules-archiver-${v.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Supprimer définitivement'));
      await tester.pumpAndSettle();

      expect(
        find.text(MessagesVehicules.archivageVerrouille(1)),
        findsOneWidget,
      );
      expect((await dao.vehicule(v.id))!.statut, StatutVehicule.loue);
    });
  });

  /* ================================================================== */
  group('Le bloc « Ce que cet écran ne rend pas » est RETIRÉ (PO, 14/10)', () {
    testWidgets('la page se termine sur le tableau, sans bloc d’écarts ; le '
        'refus d’annuler un contrat reste une phrase du DAO', (tester) async {
      await monter(tester);

      expect(
        find.textContaining('Bouton « Annuler » d’un contrat'),
        findsNothing,
      );
      expect(find.textContaining('Ce que cet écran ne rend pas'), findsNothing);
      // Le refus, lui, existe toujours (testé par `vehicule_dao_test`).
      expect(refusAnnulationContrat, contains('ne peut pas être annulé'));
      // Les trois motifs périmés ne sont plus affichés.
      expect(find.textContaining('Le NOM d’un véhicule'), findsNothing);
      expect(find.textContaining('Le permis « dispensé »'), findsNothing);
      expect(find.textContaining('Couches « circuit »'), findsNothing);
    });
  });
}
