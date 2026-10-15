import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/features/comptabilite/data/comptabilite_dao.dart';
import 'package:tatacora_flutter/features/comptabilite/data/moteur_comptable.dart';
import 'package:tatacora_flutter/features/tableau_de_bord/presentation/ecran_pilotage_consolide.dart';
import 'package:tatacora_flutter/features/tableau_de_bord/presentation/ecran_tableau_de_bord.dart';
import 'package:tatacora_flutter/features/tableau_de_bord/presentation/widgets/graphique_marge_centres.dart';

import '../../support/coquille_montee.dart';
import '../comptabilite/support/outils_comptabilite.dart';
import '../facturation/support/outils_encaissement.dart' show emettreFacture;

/// La fin du Pilotage consolidé (13/10/2026, décision du PO) : les cartes
/// « Par module » Véhicules, Tourisme, Personnel & paie, Clients & créances et
/// la marge par centre calculée sur le poste, sur une VRAIE base.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  final aujourdhui = DateTime(2026, 10, 10, 14, 30);

  Future<void> semer() async {
    await baseInstalleeSur(db, aujourdhui);
    await db.customStatement(
      'INSERT INTO clients_local (id, nom, prenom, telephone, type_client) '
      "VALUES ('cli-1', 'KORA', 'Jean', '+229 01', 'particulier')",
    );
    // M8 : deux véhicules (un en entretien) et un contrat du 9 au 12.
    await db.customStatement(
      'INSERT INTO vehicules_local (id, categorie, immatriculation, '
      "tarif_jour, statut) VALUES ('v1', 'berline', 'AB-1', 15000, "
      "'disponible'), ('v2', 'berline', 'AB-2', 15000, 'entretien')",
    );
    await db.customStatement(
      'INSERT INTO contrats_location_local (id, vehicule_id, client_id, '
      'date_debut, date_fin) VALUES (?, ?, ?, ?, ?)',
      [
        'c1',
        'v1',
        'cli-1',
        DateTime(2026, 10, 9).millisecondsSinceEpoch ~/ 1000,
        DateTime(2026, 10, 12).millisecondsSinceEpoch ~/ 1000,
      ],
    );
    // M9 : un circuit de 10 places, 4 vendues le 13.
    await db.customStatement(
      'INSERT INTO circuits_local (id, nom, theme, zone, prix, capacite_max, '
      "duree) VALUES ('ci1', 'Cascades', 'Nature', 'Atacora', 5000, 10, "
      "'1 jour')",
    );
    await db.customStatement(
      "INSERT INTO guides_local (id, nom) VALUES ('g1', 'Guide')",
    );
    await db.customStatement(
      'INSERT INTO reservations_tour_local (id, circuit_id, client_id, '
      'guide_id, date_circuit, nb_participants, statut) VALUES '
      '(?, ?, ?, ?, ?, ?, ?)',
      [
        't1',
        'ci1',
        'cli-1',
        'g1',
        DateTime(2026, 10, 13).millisecondsSinceEpoch ~/ 1000,
        4,
        'reservee',
      ],
    );
    // M3 : une facture de plus de 90 jours, jamais réglée (7 000 F).
    await emettreFacture(
      db,
      montant: 7000,
      clientId: 'cli-1',
      horloge: DateTime(2026, 6, 1, 9),
    );
    // Un départ dont TOUTES les lignes sont annulées n'est plus un départ.
    await db.customStatement(
      'INSERT INTO reservations_tour_local (id, circuit_id, client_id, '
      'guide_id, date_circuit, nb_participants, statut) VALUES '
      '(?, ?, ?, ?, ?, ?, ?)',
      [
        't2',
        'ci1',
        'cli-1',
        'g1',
        DateTime(2026, 10, 15).millisecondsSinceEpoch ~/ 1000,
        2,
        'annulee',
      ],
    );
  }

  Future<void> unePieceAuBar() async {
    final bar = await ComptabiliteDao(db).centreParLibelle('Bar');
    await moteurSur(db, maintenant: () => aujourdhui).passerEtValider(
      DemandePiece(
        journal: 'VTE',
        date: '2026-10-10',
        libelle: 'Vente essai',
        lignes: [
          const LigneDemandee(compte: '5711', debitCentimes: 1000000),
          LigneDemandee(
            compte: '7011',
            creditCentimes: 1000000,
            centreId: bar!.id,
          ),
        ],
      ),
      auteurId: auteurEssai,
    );
  }

  setUp(() async {
    db = AppDatabase.enMemoire();
    await db.customStatement('SELECT 1');
    await semerAuteur(db);
    await semer();
  });

  tearDown(() => db.close());

  Future<void> monter(
    WidgetTester tester, {
    String role = 'administrateur',
    Map<String, String> droits = const {
      'M3': 'L',
      'M8': 'L',
      'M9': 'L',
      'M10': 'L',
      'M11': 'C',
      'M13': 'L',
    },
  }) async {
    await monterCoquille(
      tester,
      role: role,
      droits: droits,
      routeActive: '/tableau-de-bord',
      taille: const Size(1600, 3200),
      enfant: const EcranTableauDeBord(),
      surcharges: [
        baseLocaleProvider.overrideWithValue(db),
        horlogeTableauDeBordProvider.overrideWithValue(() => aujourdhui),
      ],
    );
    await tester.tap(find.text('Pilotage consolidé'));
    await tester.pumpAndSettle();
  }

  String carte(WidgetTester tester, String cle) => tester
      .widgetList<Text>(
        find.descendant(of: find.byKey(Key(cle)), matching: find.byType(Text)),
      )
      .map((t) => t.data ?? '')
      .join(' | ');

  testWidgets('les quatre cartes du serveur, à leurs mots et à leurs '
      'valeurs', (tester) async {
    await monter(tester);

    final m8 = carte(tester, 'pilotage-module-m8');
    expect(m8, startsWith('Location de véhicules | M8'));
    // Le contrat du 9 au 12 chevauche la fenêtre [10, 24] : un contrat, 3
    // jours ; deux véhicules au parc, un immobilisé.
    expect(m8, contains('Parc | 2'));
    expect(m8, contains('Contrats actifs | 1'));
    expect(m8, contains('Jours loués | 3'));
    expect(m8, contains('1 véhicule(s) immobilisé(s).'));

    final m9 = carte(tester, 'pilotage-module-m9');
    expect(m9, startsWith('Tourisme & circuits | M9'));
    expect(m9, contains('Départs planifiés | 1'));
    expect(m9, contains('Places vendues | 4 / 10'));
    expect(m9, contains('Remplissage | 40 %'));
    expect(m9, contains('Chiffre d’affaires | 20 000 FCFA'));

    final m13 = carte(tester, 'pilotage-module-m13');
    expect(m13, startsWith('Personnel & paie | M13'));
    expect(m13, contains('Effectif actif | 0'));
    expect(m13, contains('VPS à reverser'));
    expect(
      m13,
      contains(
        'Fourchette : le taux de risques professionnels n’est pas '
        'confirmé.',
      ),
    );

    final m3 = carte(tester, 'pilotage-module-m3');
    expect(m3, startsWith('Clients & créances | M3'));
    expect(m3, contains('Clients débiteurs | 1'));
    expect(m3, contains('Total dû | 7 000 FCFA'));
    // La tranche « plus de 90 jours » du graphique, jamais une seconde lecture.
    expect(m3, contains('Dont + de 90 jours | 7 000 FCFA'));
    expect(m3, contains('Encaissé sur 30 jours | 0 FCFA'));
  });

  testWidgets('l’ordre de la vue : M1, POS, Stocks, M8, M9, M13, M3, M10, '
      'Dépense courante', (tester) async {
    await monter(tester);
    double y(String cle) => tester.getTopLeft(find.byKey(Key(cle))).dy;
    double x(String cle) => tester.getTopLeft(find.byKey(Key(cle))).dx;
    final ordre = [
      'pilotage-module-m8',
      'pilotage-module-m9',
      'pilotage-module-m13',
      'pilotage-module-m3',
    ];
    for (var i = 1; i < ordre.length; i++) {
      final avant = (y(ordre[i - 1]), x(ordre[i - 1]));
      final apres = (y(ordre[i]), x(ordre[i]));
      expect(
        apres.$1 > avant.$1 || (apres.$1 == avant.$1 && apres.$2 > avant.$2),
        isTrue,
        reason: '${ordre[i]} après ${ordre[i - 1]}',
      );
    }
  });

  testWidgets('sans droit sur un module, sa carte n’est pas rendue ; le '
      'gérant ne voit ni Tourisme, ni Véhicules, ni Personnel, ni Clients '
      '(masquage de la barre latérale)', (tester) async {
    await monter(tester, droits: const {'M11': 'C', 'M9': 'L'});
    expect(find.byKey(const Key('pilotage-module-m8')), findsNothing);
    expect(find.byKey(const Key('pilotage-module-m13')), findsNothing);
    expect(find.byKey(const Key('pilotage-module-m3')), findsNothing);
    expect(find.byKey(const Key('pilotage-module-m9')), findsOneWidget);
  });

  testWidgets('le gérant : les quatre cartes masquées comme dans la vue', (
    tester,
  ) async {
    await monter(tester, role: 'gerant');
    for (final m in ['m8', 'm9', 'm13', 'm3']) {
      expect(find.byKey(Key('pilotage-module-$m')), findsNothing, reason: m);
    }
  });

  testWidgets('la marge par centre est CALCULÉE sur le poste : le graphique '
      'quand l’exercice ouvert porte des écritures', (tester) async {
    await unePieceAuBar();
    // Un exercice PLUS ANCIEN encore ouvert, sans écriture : le serveur prend
    // le plus RÉCENT (`orderByDesc('annee')`).
    await db.customStatement(
      'INSERT INTO exercices_local (id, annee, date_debut, date_fin, statut) '
      "VALUES ('ex-2025', 2025, '2025-01-01', '2025-12-31', 'ouvert')",
    );
    await monter(tester);
    final graphique = tester.widget<GraphiqueMargeCentres>(
      find.byType(GraphiqueMargeCentres),
    );
    // La ligne de caisse (5711, classe 5) prend le centre par défaut de son
    // compte : ce centre a une ligne et un résultat NUL — le serveur le rend
    // aussi (un compte de bilan n'est ni un produit ni une charge).
    expect(
      [for (final c in graphique.centres) (c.libelle, c.resultat)],
      [('Bar', '10000.00'), ('Hébergement', '0.00')],
    );
    // La phrase périmée « calculées par le serveur… hors connexion » n'existe
    // plus nulle part à l'écran.
    expect(find.textContaining('hors connexion'), findsNothing);
  });

  testWidgets('sans écriture : la phrase de la vue ; sans droit M10 : « Non '
      'consulté »', (tester) async {
    await monter(tester);
    expect(
      find.text("Aucune écriture analytique sur l'exercice ouvert."),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
    await monter(tester, droits: const {'M11': 'C', 'M3': 'L'});
    expect(
      find.byKey(const Key('pilotage-centres-non-consulte')),
      findsOneWidget,
    );
    expect(find.byType(GraphiqueMargeCentres), findsNothing);
  });

  testWidgets('sans exercice OUVERT : « Non consulté », suivi de la raison', (
    tester,
  ) async {
    await db.customStatement("UPDATE exercices_local SET statut = 'cloture'");
    await monter(tester);
    expect(
      find.descendant(
        of: find.byKey(const Key('pilotage-centres-absent')),
        matching: find.text(
          'Non consulté : aucun exercice comptable n’est ouvert sur ce poste.',
        ),
      ),
      findsOneWidget,
    );
  });
}
