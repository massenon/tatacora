import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/features/bar/presentation/widgets/modale_export_carte.dart'
    show TextesExport;
import 'package:tatacora_flutter/features/pos/data/panier_dao.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/article_vendable.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/panier.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/reference_catalogue.dart';
import 'package:tatacora_flutter/features/tableau_de_bord/domain/croise_local.dart';
import 'package:tatacora_flutter/features/tableau_de_bord/presentation/ecran_pilotage_consolide.dart';
import 'package:tatacora_flutter/features/tableau_de_bord/presentation/ecran_tableau_croise.dart';
import 'package:tatacora_flutter/features/tableau_de_bord/presentation/ecran_tableau_de_bord.dart';

import '../../support/coquille_montee.dart';
import '../pos/support/outils_ventes.dart' show cloturerSansPiece;

/// Le panneau « Tableau croisé dynamique », sur une VRAIE base du poste : les
/// trois registres sont lus par `SourcesCroise` (ventes clôturées, dépenses,
/// réservations), la fenêtre est celle de la bande (« Ce mois » au 10/10/2026),
/// et ce qui s'affiche est ce que `croiser` rend. Le calcul lui-même est
/// confronté au serveur ailleurs (`croise_contre_serveur_test.dart`).
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  final aujourdhui = DateTime(2026, 10, 10, 14, 30);

  const biere = ArticleVendable(
    reference: ReferenceCatalogue(module: ModuleVendable.m5Bar, code: 'bsn'),
    libelle: 'Béninoise 33cl',
    prix: 1000,
    categorie: 'locale',
  );

  Future<void> uneVente({
    required DateTime quand,
    String mode = 'especes',
    int quantite = 2,
    TypeVente type = TypeVente.comptant,
  }) async {
    final dao = PanierDao(db);
    var p = await dao.ouvrir(typeVente: type, pointVente: 'Comptoir');
    p = await dao.ajouterLigne(p.id, biere, quantite: quantite);
    await cloturerSansPiece(db, p.id, mode: mode, quand: quand);
  }

  Future<void> uneDepense({
    required String id,
    required DateTime quand,
    required int montant,
  }) async {
    await db
        .into(db.depensesLocal)
        .insert(
          DepensesLocalCompanion.insert(
            id: id,
            dateTransaction: quand,
            tresorerie: 'caisse',
            libelle: 'Marché',
            saisieLe: Value(quand),
          ),
        );
    await db
        .into(db.lignesDepenseLocal)
        .insert(
          LignesDepenseLocalCompanion.insert(
            id: '$id-l1',
            depenseId: id,
            libelle: 'Riz',
            compteCharge: '6021',
            nature: 'Riz',
            famille: 'Achats',
            montant: montant,
          ),
        );
  }

  Future<void> uneReservation({
    required String id,
    required DateTime arrivee,
    required int acompte,
    String statut = 'confirmee',
  }) async {
    await db.customStatement(
      'INSERT INTO reservations_local (id, reference, client_id, unite_id, '
      'date_arrivee, date_depart, statut, tarif_nuit, acompte) VALUES '
      '(?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        id,
        'LOC-$id',
        'cli-1',
        'u-1',
        arrivee.millisecondsSinceEpoch ~/ 1000,
        arrivee.add(const Duration(days: 2)).millisecondsSinceEpoch ~/ 1000,
        statut,
        28000,
        acompte,
      ],
    );
  }

  setUp(() async {
    db = AppDatabase.enMemoire();
    await db.customStatement('SELECT 1');
    await db
        .into(db.cartesBoissonLocal)
        .insert(
          CartesBoissonLocalCompanion.insert(
            id: 'bsn',
            articleId: 'art-bsn',
            libelle: 'Béninoise 33cl',
            categorie: 'locale',
            prixVente: 1000,
          ),
        );
    await db.customStatement(
      'INSERT INTO categories_hebergement_local (id, libelle, capacite_max, '
      "tarif_base) VALUES ('cat-1', 'Bungalow', 2, 28000)",
    );
    await db.customStatement(
      'INSERT INTO unites_hebergement_local (id, categorie_id, numero, statut) '
      "VALUES ('u-1', 'cat-1', 'BNG-01', 'libre')",
    );
    await db.customStatement(
      'INSERT INTO clients_local (id, nom, prenom, telephone, type_client) '
      "VALUES ('cli-1', 'KORA', 'Jean', '+229 01', 'particulier')",
    );
  });

  tearDown(() => db.close());

  Future<void> monter(
    WidgetTester tester, {
    Map<String, String> droits = const {'M11': 'C'},
  }) async {
    await monterCoquille(
      tester,
      role: 'administrateur',
      droits: droits,
      routeActive: '/tableau-de-bord',
      taille: const Size(1600, 1600),
      enfant: const EcranTableauDeBord(),
      surcharges: [
        baseLocaleProvider.overrideWithValue(db),
        horlogeTableauDeBordProvider.overrideWithValue(() => aujourdhui),
      ],
    );
    await tester.tap(find.byKey(const Key('tdb-onglet-croise')));
    await tester.pumpAndSettle();
  }

  String texteDe(WidgetTester tester, String cle) =>
      tester.widget<Text>(find.byKey(Key(cle))).data!;

  Future<void> choisir(WidgetTester tester, String liste, String option) async {
    await tester.ensureVisible(find.byKey(Key(liste)));
    await tester.tap(find.byKey(Key(liste)));
    await tester.pumpAndSettle();
    await tester.tap(find.text(option).last);
    await tester.pumpAndSettle();
  }

  testWidgets('l’onglet n’est plus inerte : il ouvre le panneau, ses mots et '
      'ses quatre sélecteurs aux défauts du composant', (tester) async {
    await monter(tester);

    expect(find.byKey(const Key('croise-intro')), findsOneWidget);
    expect(texteDe(tester, 'croise-intro'), MotsCroise.intro);
    for (final mot in ['LIGNES', 'COLONNES', 'MESURE', 'SOURCES']) {
      expect(find.text(mot), findsOneWidget, reason: mot);
    }
    final valeurs = {
      for (final cle in ['croise-lignes', 'croise-colonnes', 'croise-mesure'])
        cle: tester.widget<DropdownButton<Object>>(find.byKey(Key(cle))).value,
    };
    expect(valeurs, {
      'croise-lignes': AxeCroise.activite,
      'croise-colonnes': AxeCroise.mois,
      'croise-mesure': MesureCroise.montant,
    });
    for (final s in SourceCroise.values) {
      expect(
        tester
            .widget<Checkbox>(find.byKey(Key('croise-source-${s.name}')))
            .value,
        isTrue,
      );
      expect(find.text(s.libelle), findsOneWidget);
    }
    expect(find.byKey(const Key('croise-exporter')), findsOneWidget);
  });

  testWidgets('sans aucun mouvement : « Aucun mouvement sur cette période… », '
      'la note « 0 mouvement(s) » et l’en-tête « ACTIVITÉ » / « TOTAL »', (
    tester,
  ) async {
    await monter(tester);

    expect(texteDe(tester, 'croise-message'), MotsCroise.vide);
    expect(
      texteDe(tester, 'croise-note'),
      '${MotsCroise.note(0)} ${MotsCroise.noteReservations}',
    );
    expect(texteDe(tester, 'croise-entete-axe'), 'ACTIVITÉ');
    expect(find.text('TOTAL'), findsOneWidget);
    expect(find.byKey(const Key('croise-total-general')), findsNothing);
  });

  testWidgets('les trois registres du poste, croisés par activité et par mois '
      ': ventes, dépense en NÉGATIF (rouge), acompte de réservation — et rien '
      'hors de la fenêtre', (tester) async {
    await uneVente(quand: DateTime(2026, 10, 3, 10)); // 2 000
    await uneVente(quand: DateTime(2026, 9, 30, 10)); // hors période
    await uneDepense(id: 'd1', quand: DateTime(2026, 10, 4), montant: 5000);
    await uneReservation(
      id: 'r1',
      arrivee: DateTime(2026, 10, 5),
      acompte: 10000,
    );
    await uneReservation(
      id: 'r2',
      arrivee: DateTime(2026, 10, 6),
      acompte: 3000,
      statut: 'annulee',
    );
    await monter(tester);

    // Lignes triées comme `asort` : « Achats » < « Hébergement » < « locale ».
    expect(
      [for (var i = 0; i < 3; i++) texteDe(tester, 'croise-ligne-$i')],
      ['Achats', 'Hébergement', 'locale'],
    );
    expect(find.byKey(const Key('croise-ligne-3')), findsNothing);
    expect(find.text('OCTOBRE 2026'), findsOneWidget);
    expect(texteDe(tester, 'croise-cellule-0-0'), '-5 000 FCFA');
    expect(texteDe(tester, 'croise-cellule-1-0'), '10 000 FCFA');
    expect(texteDe(tester, 'croise-cellule-2-0'), '2 000 FCFA');
    // Le solde : 2 000 + 10 000 − 5 000.
    expect(texteDe(tester, 'croise-total-general'), '7 000 FCFA');
    expect(
      tester
          .widget<Text>(find.byKey(const Key('croise-cellule-0-0')))
          .style!
          .color,
      CouleursCroise.negatif,
    );
    expect(
      texteDe(tester, 'croise-note'),
      '${MotsCroise.note(3)} ${MotsCroise.noteReservations}',
    );
  });

  testWidgets('changer la mesure et la colonne recalcule : « Nombre de lignes '
      '» par « Source », un zéro PÂLE, des comptes sans « FCFA »', (
    tester,
  ) async {
    await uneVente(quand: DateTime(2026, 10, 3, 10), quantite: 4);
    await uneDepense(id: 'd1', quand: DateTime(2026, 10, 4), montant: 5000);
    await monter(tester);

    await choisir(tester, 'croise-colonnes', 'Source');
    await choisir(tester, 'croise-mesure', 'Nombre de lignes');

    expect(find.text('VENTES'), findsOneWidget);
    expect(find.text('DÉPENSES'), findsOneWidget);
    // Achats × Dépenses = 1 ; Achats × Ventes = 0, en pâle.
    final colonnes = [find.text('DÉPENSES'), find.text('VENTES')];
    expect(colonnes.every((f) => f.evaluate().isNotEmpty), isTrue);
    expect(texteDe(tester, 'croise-total-general'), '2');
    final zero = tester.widget<Text>(
      find.byKey(const Key('croise-cellule-0-1')),
    );
    expect(zero.data, '0');
    expect(zero.style!.color, CouleursCroise.zero);

    await choisir(tester, 'croise-mesure', 'Quantité');
    // 4 bières + 1 ligne de dépense (quantité 1).
    expect(texteDe(tester, 'croise-total-general'), '5');
  });

  testWidgets('décocher les trois sources : « Aucune source sélectionnée… », '
      'jamais une grille vide', (tester) async {
    await uneVente(quand: DateTime(2026, 10, 3, 10));
    await monter(tester);

    for (final s in SourceCroise.values) {
      await tester.tap(find.byKey(Key('croise-source-${s.name}')));
      await tester.pumpAndSettle();
    }
    expect(texteDe(tester, 'croise-message'), MotsCroise.aucuneSource);

    // Recocher les ventes seules : la vente revient, rien d'autre.
    await tester.tap(find.byKey(const Key('croise-source-ventes')));
    await tester.pumpAndSettle();
    expect(texteDe(tester, 'croise-total-general'), '2 000 FCFA');
  });

  testWidgets('une vente d’AVANT sans mode de règlement : mode « — », et pas '
      'un franc « encaissé » (écart nommé du poste)', (tester) async {
    final dao = PanierDao(db);
    var p = await dao.ouvrir(typeVente: TypeVente.comptant, pointVente: 'Bar');
    p = await dao.ajouterLigne(p.id, biere, quantite: 3);
    await cloturerSansPiece(db, p.id, quand: DateTime(2026, 10, 2, 9));
    await monter(tester);

    await choisir(tester, 'croise-lignes', 'Mode de paiement');
    await choisir(tester, 'croise-mesure', 'Encaissé (FCFA)');

    expect(texteDe(tester, 'croise-ligne-0'), '—');
    expect(texteDe(tester, 'croise-total-general'), '0 FCFA');
    await choisir(tester, 'croise-mesure', 'Montant (FCFA)');
    expect(texteDe(tester, 'croise-total-general'), '3 000 FCFA');
  });

  testWidgets('« Exporter » ouvre la MÊME modale que l’en-tête', (
    tester,
  ) async {
    await monter(tester);
    await tester.tap(find.byKey(const Key('croise-exporter')));
    await tester.pumpAndSettle();

    expect(find.text(titreExportPilotage), findsOneWidget);
    expect(find.text(TextesExport.generer), findsOneWidget);
  });
}
