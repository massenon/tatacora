import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/auth/domain/session.dart';
import 'package:tatacora_flutter/features/parametres/domain/regles_parametres.dart';
import 'package:tatacora_flutter/features/parametres/presentation/ecran_parametres.dart';

/// L'écran Paramètres, monté sur la SOURCE LOCALE réelle : la chaîne entière
/// (écran -> cas d'usage -> dépôt -> SQLite) est empruntée, rien n'est simulé
/// au-dessus de la base.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.enMemoire();
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
            dateCreation: DateTime(2026, 10, 9),
            dateMotDePasse: DateTime(2026, 10, 9),
          ),
        );
  });

  tearDown(() => db.close());

  Future<void> monter(WidgetTester tester, {String niveau = 'C'}) async {
    tester.view
      ..physicalSize = const Size(1600, 1400)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final droits = GardeAcces({'PARAM': niveau});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseLocaleProvider.overrideWithValue(db),
          droitsProvider.overrideWithValue(droits),
          sessionProvider.overrideWithBuild(
            (ref, n) => Session(
              utilisateurId: 'u-essai',
              login: 'essai',
              nom: 'Essai',
              role: 'administrateur',
              droits: droits,
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.clair,
          home: const Scaffold(body: EcranParametres()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Le texte de la pastille de valeur d'une ligne (premier texte du bloc après
  /// le libellé) — on lit la ligne entière et on cherche la valeur attendue.
  Finder ligne(String cle) => find.byKey(Key('param-ligne-$cle'));

  Finder texteDans(String cle, String texte) =>
      find.descendant(of: ligne(cle), matching: find.text(texte));

  Future<void> modifier(WidgetTester tester, String cle) async {
    await tester.ensureVisible(find.byKey(Key('param-modifier-$cle')));
    await tester.tap(find.byKey(Key('param-modifier-$cle')));
    await tester.pumpAndSettle();
  }

  Future<void> enregistrer(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('param-enregistrer')));
    await tester.pumpAndSettle();
  }

  Future<Map<String, String>> enBase() async => {
    for (final l in await db.select(db.parametresSystemeLocal).get())
      l.cle: l.valeur,
  };

  testWidgets('un poste neuf : chaque valeur est « — », les deux badges disent '
      'la vérité, aucun refus d’écran', (tester) async {
    await monter(tester);

    expect(find.byKey(const Key('param-refus')), findsNothing);
    expect(find.byKey(const Key('param-hors-ligne')), findsNothing);

    // Identité & Légal : 6 champs d'identité hors adresse + adresse + 3 légaux
    // + 4 fiscaux. Tous « — ».
    for (final cle in [
      'entreprise_raison_sociale',
      'entreprise_adresse',
      'entreprise_ifu',
      'entreprise_rccm',
      'entreprise_numero_mecef',
      'taux_tva',
      'convention_prix',
    ]) {
      expect(texteDans(cle, '—'), findsOneWidget, reason: cle);
    }

    expect(
      find.descendant(
        of: find.byKey(const Key('param-etat-tva')),
        matching: find.text(
          'TVA inactive — aucune taxe n’est ajoutée aux factures.',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('param-etat-mecef')),
        matching: find.textContaining('MECeF non configurée'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('saisir un IFU : la pastille, la base et la trace (qui) le '
      'montrent', (tester) async {
    await monter(tester);

    await modifier(tester, 'entreprise_ifu');
    await tester.enterText(
      find.byKey(const Key('param-champ-entreprise_ifu')),
      '3202612345678',
    );
    await tester.pump();
    await enregistrer(tester);

    expect(texteDans('entreprise_ifu', '3202612345678'), findsOneWidget);
    expect(find.text('Paramètres enregistrés.'), findsOneWidget);
    expect(await enBase(), {'entreprise_ifu': '3202612345678'});
    final l = await db.select(db.parametresSystemeLocal).getSingle();
    expect(l.modifiePar, 'u-essai');
  });

  testWidgets('vider un IFU erroné est POSSIBLE : la ligne disparaît, le champ '
      'redevient « — »', (tester) async {
    await monter(tester);
    await modifier(tester, 'entreprise_ifu');
    await tester.enterText(
      find.byKey(const Key('param-champ-entreprise_ifu')),
      'FAUX',
    );
    await tester.pump();
    await enregistrer(tester);
    expect(texteDans('entreprise_ifu', 'FAUX'), findsOneWidget);

    await modifier(tester, 'entreprise_ifu');
    await tester.enterText(
      find.byKey(const Key('param-champ-entreprise_ifu')),
      '',
    );
    await tester.pump();
    await enregistrer(tester);

    expect(texteDans('entreprise_ifu', '—'), findsOneWidget);
    expect(await enBase(), isEmpty);
  });

  testWidgets(
    'une valeur refusée reste à l’écran avec son motif, et RIEN n’est '
    'écrit',
    (tester) async {
      await monter(tester);
      await modifier(tester, 'entreprise_telephone');
      await tester.enterText(
        find.byKey(const Key('param-champ-entreprise_telephone')),
        'appelez-moi',
      );
      await tester.pump();
      await enregistrer(tester);

      expect(
        find.text(
          '« Téléphone principal » n’est pas un numéro valide : chiffres, '
          'espaces et indicatif uniquement.',
        ),
        findsOneWidget,
      );
      // La fenêtre est toujours ouverte.
      expect(find.byKey(const Key('param-enregistrer')), findsOneWidget);
      expect(await enBase(), isEmpty);
    },
  );

  testWidgets('la TVA : activer sans taux est refusé à l’écran ; poser le '
      'taux, puis l’activer, change le badge — qui ne dit JAMAIS « TVA '
      'active. »', (tester) async {
    await monter(tester);

    // 1. Activer sans taux.
    await modifier(tester, 'tva_active');
    await tester.tap(find.byKey(const Key('param-champ-tva_active')));
    await tester.pump();
    await enregistrer(tester);
    expect(find.text(refusTvaSansTaux), findsOneWidget);
    expect(await enBase(), isEmpty);
    await tester.tap(find.byKey(const Key('param-annuler')));
    await tester.pumpAndSettle();

    // 2. Le taux d'abord.
    await modifier(tester, 'taux_tva');
    await tester.enterText(find.byKey(const Key('param-champ-taux_tva')), '18');
    await tester.pump();
    await enregistrer(tester);
    expect(await enBase(), {'taux_tva': '18'});

    // 3. Puis l'activation.
    await modifier(tester, 'tva_active');
    await tester.tap(find.byKey(const Key('param-champ-tva_active')));
    await tester.pump();
    await enregistrer(tester);

    expect(await enBase(), {'taux_tva': '18', 'tva_active': 'true'});
    final badge = find.byKey(const Key('param-etat-tva'));
    expect(
      find.descendant(
        of: badge,
        matching: find.text(
          'TVA activée et paramétrée : ce poste ventile HT/TVA dans la pièce '
          'comptable de chaque vente, mais ne l’applique encore à aucune '
          'facture — aucune ventilation HT/TVA n’y est calculée.',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: badge, matching: find.text('TVA active.')),
      findsNothing,
    );

    // 4. Le second sens : vider le taux d'une TVA active.
    await modifier(tester, 'taux_tva');
    await tester.enterText(find.byKey(const Key('param-champ-taux_tva')), '');
    await tester.pump();
    await enregistrer(tester);
    expect(find.text(refusTvaSansTaux), findsOneWidget);
    expect((await enBase())['taux_tva'], '18');
  });

  testWidgets('MECeF : renseigner le numéro contribuable donne « en attente », '
      'jamais « active »', (tester) async {
    await monter(tester);
    await modifier(tester, 'entreprise_numero_mecef');
    await tester.enterText(
      find.byKey(const Key('param-champ-entreprise_numero_mecef')),
      'M-0012345',
    );
    await tester.pump();
    await enregistrer(tester);

    final badge = find.byKey(const Key('param-etat-mecef'));
    expect(
      find.descendant(
        of: badge,
        matching: find.textContaining('le client MECeF réel n’est pas encore'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: badge,
        matching: find.textContaining('Certification MECeF active'),
      ),
      findsNothing,
    );
  });

  testWidgets(
    'une clé sans lecteur le dit : infobulle sur la ligne, texte VISIBLE dans '
    'la fenêtre de modification ; un secret voisin nomme son refus',
    (tester) async {
      await monter(tester);

      String infobulle(String cle) =>
          tester.widget<Tooltip>(find.byKey(Key('param-note-$cle'))).message!;

      expect(
        infobulle('fiscalite_regime'),
        'Aucun module de ce poste ne lit encore cette valeur.',
      );
      // Le taux de TVA a un lecteur depuis le 12/10/2026 (lot 6) : la pièce
      // comptable d'une vente. Il ne porte plus l'infobulle.
      expect(find.byKey(const Key('param-note-taux_tva')), findsNothing);
      // Le numéro contribuable MECeF : le refus du secret, PUIS « aucun module ».
      expect(
        infobulle('entreprise_numero_mecef'),
        'Sur ce poste, aucune clé d’API MECeF n’est enregistrable : un secret '
        'n’entre jamais dans cette base.\n'
        'Aucun module de ce poste ne lit encore cette valeur.',
      );

      // Dans la fenêtre de modification, les notes sont du texte visible.
      await modifier(tester, 'entreprise_numero_mecef');
      expect(
        find.byKey(const Key('param-champ-note-entreprise_numero_mecef-0')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(
                const Key('param-champ-note-entreprise_numero_mecef-0'),
              ),
            )
            .data,
        'Sur ce poste, aucune clé d’API MECeF n’est enregistrable : un secret '
        'n’entre jamais dans cette base.',
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(
                const Key('param-champ-note-entreprise_numero_mecef-1'),
              ),
            )
            .data,
        'Aucun module de ce poste ne lit encore cette valeur.',
      );
    },
  );

  testWidgets(
    'la tolérance de réception A UN LECTEUR depuis M7 : la ligne ne dit plus '
    '« aucun module ne la lit » ; la fenêtre non plus',
    (tester) async {
      await monter(tester);
      await tester.tap(find.byKey(const Key('param-onglet-activation')));
      await tester.pumpAndSettle();

      // Une clé du même onglet qui n'a PAS de lecteur porte l'infobulle
      // (témoin : sans lui, l'absence ci-dessous pourrait venir d'un onglet
      // mal ouvert) ...
      expect(
        find.byKey(const Key('param-note-delai_preavis_conge_jours')),
        findsOneWidget,
      );
      // ... celle que `AchatsDao` lit pour juger une réception n'en porte plus :
      // la dire « sans effet » serait faux, et l'exploitant ne la renseignerait
      // pas — alors que sans elle aucune réception n'est possible.
      expect(
        find.byKey(const Key('param-note-tolerance_reception_pct')),
        findsNothing,
      );

      await modifier(tester, 'tolerance_reception_pct');
      expect(
        find.byKey(const Key('param-champ-note-tolerance_reception_pct-0')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'la correction d’une aide fausse sur ce poste est VISIBLE en ligne, et '
    'une clé sans cette erreur n’en porte pas',
    (tester) async {
      await monter(tester);

      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('param-correction-entreprise_ifu')),
            )
            .data,
        'Sur ce poste, aucun document n’imprime encore cette valeur.',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('param-correction-tva_active')))
            .data,
        'Sur ce poste : HT/TVA ventilés dans la pièce des ventes ; sans taux, '
        'la vente est refusée.',
      );
      // Le taux de TVA n'a pas d'aide fausse : aucune correction.
      expect(find.byKey(const Key('param-correction-taux_tva')), findsNothing);
    },
  );

  testWidgets(
    'lecture seule (L) : les valeurs sont visibles, aucun « Modifier »',
    (tester) async {
      await monter(tester, niveau: 'L');

      expect(texteDans('entreprise_ifu', '—'), findsOneWidget);
      expect(
        find.byKey(const Key('param-modifier-entreprise_ifu')),
        findsNothing,
      );
      expect(find.text('Modifier'), findsNothing);
    },
  );

  testWidgets('sans aucun droit sur PARAM : un refus, aucune valeur', (
    tester,
  ) async {
    await monter(tester, niveau: '-');

    expect(
      find.text(
        'Vous n’avez pas le droit de consulter les paramètres du système.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('param-ligne-entreprise_ifu')), findsNothing);
  });
}
