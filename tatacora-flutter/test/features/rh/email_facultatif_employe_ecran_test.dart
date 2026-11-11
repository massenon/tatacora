import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/format/adresse_email_facultative.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/auth/domain/session.dart';
import 'package:tatacora_flutter/features/rh/data/employe_dao.dart';
import 'package:tatacora_flutter/features/rh/domain/entities/employe.dart';
import 'package:tatacora_flutter/features/rh/presentation/ecran_paie.dart';

/// Le champ « Email » de la fiche employé (28/10/2026), sous Poste / Service
/// comme la vue : FACULTATIF (pas d'astérisque), format refusé avec la phrase du
/// serveur, normalisé à l'enregistrement. La règle elle-même est confrontée au
/// vrai PHP par `email_facultatif_contre_serveur_test`.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late EmployeDao employes;

  setUp(() async {
    db = AppDatabase.enMemoire();
    employes = EmployeDao(db, maintenant: () => DateTime(2026, 9, 14, 10));
    await employes.installerServices();
  });
  tearDown(() => db.close());

  Future<Employe> semer({String? email}) async => employes.creer(
    nom: 'KORA',
    prenom: 'Jean',
    poste: 'Réceptionniste',
    serviceId: (await employes.services()).first.id,
    dateEmbauche: DateTime(2023, 3, 15),
    salaireBase: 150000,
    typeContrat: TypeContrat.cdi,
    email: email,
  );

  Future<void> monter(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1600, 1800)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final droits = GardeAcces({'M13': 'C'});
    final session = Session(
      utilisateurId: 'u-essai',
      login: 'essai',
      nom: 'essai',
      role: 'Administrateur',
      droits: droits,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseLocaleProvider.overrideWithValue(db),
          droitsProvider.overrideWithValue(droits),
          sessionProvider.overrideWithBuild((ref, notifier) => session),
        ],
        child: MaterialApp(
          theme: AppTheme.clair,
          home: const Scaffold(body: EcranPaie()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder cle(String k) => find.byKey(Key(k));

  Future<void> ouvrirFiche(WidgetTester tester, String id) async {
    final bouton = cle('paie-modifier-$id');
    await tester.ensureVisible(bouton);
    await tester.pumpAndSettle();
    await tester.tap(bouton);
    await tester.pumpAndSettle();
  }

  testWidgets('la fiche relit l’adresse, la refuse mal formée (phrase du '
      'serveur, rien d’écrit), l’enregistre normalisée, et la vide', (
    tester,
  ) async {
    final e = await semer(email: 'ancien@exemple.bj');
    await monter(tester);
    await ouvrirFiche(tester, e.id);

    expect(
      tester.widget<TextFormField>(cle('paie-champ-email')).controller!.text,
      'ancien@exemple.bj',
    );
    // Facultatif : l'étiquette « Email » n'a pas d'astérisque, « Nom » l'a.
    Finder etiquette(String texte) => find.byWidgetPredicate(
      (w) => w is Text && w.textSpan?.toPlainText() == texte,
    );
    expect(etiquette('Email'), findsOneWidget);
    expect(etiquette('Email *'), findsNothing);
    expect(etiquette('Nom *'), findsOneWidget);

    Future<void> enregistrer(String texte) async {
      await tester.enterText(cle('paie-champ-email'), texte);
      await tester.tap(cle('paie-fiche-enregistrer'));
      await tester.pumpAndSettle();
    }

    await enregistrer('pas-une-adresse');
    expect(find.text(AdresseEmailFacultative.messageInvalide), findsOneWidget);
    expect(cle('paie-modale-employe'), findsOneWidget);
    expect((await employes.parId(e.id))!.email, 'ancien@exemple.bj');

    await enregistrer('  Jean.KORA@Exemple.BJ ');
    expect(cle('paie-modale-employe'), findsNothing);
    expect((await employes.parId(e.id))!.email, 'jean.kora@exemple.bj');

    await ouvrirFiche(tester, e.id);
    await enregistrer('');
    expect(cle('paie-modale-employe'), findsNothing);
    expect((await employes.parId(e.id))!.email, isNull);
  });
}
