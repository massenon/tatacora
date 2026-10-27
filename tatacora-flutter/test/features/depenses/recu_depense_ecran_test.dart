import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/fichiers/selecteur_fichiers.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/depenses/data/depense_dao.dart';
import 'package:tatacora_flutter/features/depenses/data/recus_depenses_locaux.dart';
import 'package:tatacora_flutter/features/depenses/domain/categories_depense.dart';
import 'package:tatacora_flutter/features/depenses/domain/entities/depense.dart';
import 'package:tatacora_flutter/features/depenses/domain/recu_depense.dart';
import 'package:tatacora_flutter/features/depenses/presentation/ecran_depenses.dart';
import 'package:tatacora_flutter/features/depenses/presentation/widgets/dialogue_recu_depense.dart';
import 'package:tatacora_flutter/features/synchronisation/data/telechargement_recu_depense.dart';
import 'package:tatacora_flutter/features/synchronisation/presentation/providers_synchronisation.dart';

import '../../support/selecteur_essai.dart';
import 'support/corpus_recus.dart';
import 'support/outils_depenses.dart';

/// Le reçu en image DANS l'écran Dépenses (lot L4, 27/10/2026) : la modale
/// joint un fichier par la fenêtre native (jugé par la règle du web, mêmes
/// phrases), la colonne « Pièces » rend le lien « reçu » et l'ÉTAT du reçu —
/// qui ne dit « envoyé » qu'après l'accusé du serveur —, et le clic ouvre le
/// fichier (téléchargé à la demande pour un reçu d'un autre poste).
///
/// Le rangement des fichiers est EN MÉMOIRE ici : un fichier réel n'avance pas
/// sous l'horloge simulée d'un `testWidgets` ; le rangement sur disque est
/// éprouvé par `recu_depense_dao_test.dart`.
void main() {
  late AppDatabase db;
  late DepenseDao dao;
  late RecusEnMemoire memoire;

  setUp(() async {
    db = await baseDepenses();
    memoire = RecusEnMemoire();
    dao = DepenseDao(
      db,
      maintenant: () => jourDeReference,
      moteur: depenseDaoSur(db).moteur,
      recus: memoire,
    );
  });
  tearDown(() => db.close());

  Future<Depense> saisir({
    RecuAJoindre? recu,
    String libelle = 'Marché du matin',
  }) async => dao.enregistrer(
    dateTransaction: DateTime(2026, 10, 9),
    tresorerie: TresorerieDepense.caisse,
    libelle: libelle,
    auteurId: auteurDepense,
    centreId: await centreDe(db, 'Restaurant'),
    lignes: const [
      SaisieLigneDepense(
        libelle: 'Tomates',
        compteCharge: '6011',
        nature: NatureDepense.tomate,
        montant: 8500,
      ),
    ],
    recu: recu,
  );

  RecuAJoindre png() =>
      RecuAJoindre(nom: 't.png', octets: octetsPng(), type: TypeRecu.png);

  Future<void> monter(
    WidgetTester tester, {
    SelecteurFichiers? selecteur,
    List<Override> surcharges = const [],
    Map<String, String> droits = const {'M10': 'C'},
  }) async {
    tester.view
      ..physicalSize = const Size(1800, 2600)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...surchargesDepenses(db, droits: droits),
          recusDepensesLocauxProvider.overrideWithValue(memoire),
          if (selecteur != null)
            selecteurFichiersProvider.overrideWithValue(selecteur),
          ...surcharges,
        ],
        child: MaterialApp(
          theme: AppTheme.clair,
          home: const Scaffold(body: EcranDepenses()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> ouvrirModale(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('depenses-nouvelle')));
    await tester.pumpAndSettle();
  }

  Future<void> remplir(WidgetTester tester) async {
    await tester.enterText(find.byKey(const Key('depense-libelle')), 'Marché');
    await tester.enterText(
      find.byKey(const Key('depense-ligne-libelle-0')),
      'Tomates',
    );
    await tester.enterText(
      find.byKey(const Key('depense-ligne-montant-0')),
      '8500',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('depense-ligne-compte-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('6011 — dans la Région').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('depense-ligne-nature-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Marché · Tomate').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('depense-tresorerie')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Caisse').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('depense-centre')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restaurant').last);
    await tester.pumpAndSettle();
  }

  Future<void> choisir(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const Key('depense-recu-choisir')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('depense-recu-choisir')));
    await tester.pumpAndSettle();
  }

  String texte(WidgetTester tester, String cle) =>
      tester.widget<Text>(find.byKey(Key(cle))).data!;

  group('la modale joint un reçu', () {
    testWidgets('un fichier valide : son nom et sa taille s’affichent, la '
        'dépense est enregistrée AVEC son reçu, « en attente d’envoi »', (
      tester,
    ) async {
      await monter(
        tester,
        selecteur: SelecteurEssai(
          lu: FichierLu(nom: 'ticket.png', octets: octetsPng()),
        ),
      );
      await ouvrirModale(tester);
      await remplir(tester);
      await choisir(tester);

      expect(texte(tester, 'depense-recu-nom'), startsWith('ticket.png · '));
      expect(find.byKey(const Key('depense-recu-refus')), findsNothing);
      expect(find.byKey(const Key('depense-recu-retirer')), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('depense-enregistrer')));
      await tester.tap(find.byKey(const Key('depense-enregistrer')));
      await tester.pumpAndSettle();

      final enBase = (await dao.depenses()).single;
      expect(enBase.recu!.statut, StatutRecu.enAttente);
      expect(enBase.recu!.sha256, RecusDepensesLocaux.empreinte(octetsPng()));
      expect(memoire.fichiers['${enBase.id}.png'], octetsPng());

      // La colonne « Pièces » : le lien « reçu » et l'état, JAMAIS « envoyé ».
      expect(find.byKey(Key('depense-recu-${enBase.id}')), findsOneWidget);
      expect(find.text('reçu'), findsOneWidget);
      expect(find.byKey(const Key('depenses-sans-recu')), findsNothing);
      expect(find.text('en attente d’envoi'), findsOneWidget);
      expect(find.text('envoyé'), findsNothing);
    });

    testWidgets('un fichier qui n’est pas une image : la phrase du WEB, en '
        'rouge sous le champ, rien n’est gardé ; la dépense s’enregistre « sans '
        'reçu »', (tester) async {
      await monter(
        tester,
        selecteur: SelecteurEssai(
          lu: FichierLu(
            nom: 'notes.png',
            octets: Uint8List.fromList('pas une image'.codeUnits),
          ),
        ),
      );
      await ouvrirModale(tester);
      await remplir(tester);
      await choisir(tester);

      expect(
        texte(tester, 'depense-recu-refus'),
        'Le champ photo recu doit être une image.',
      );
      expect(texte(tester, 'depense-recu-nom'), 'Aucun fichier choisi');
      expect(find.byKey(const Key('depense-recu-retirer')), findsNothing);

      await tester.ensureVisible(find.byKey(const Key('depense-enregistrer')));
      await tester.tap(find.byKey(const Key('depense-enregistrer')));
      await tester.pumpAndSettle();
      expect((await dao.depenses()).single.recu, isNull);
      expect(memoire.fichiers, isEmpty);
      expect(find.byKey(const Key('depenses-sans-recu')), findsOneWidget);
    });

    testWidgets('un fichier trop lourd : « ne peut pas peser plus de 400 '
        'kilo-octets » ; pile à la borne il passe', (tester) async {
      await monter(
        tester,
        selecteur: SelecteurEssai(
          lu: FichierLu(
            nom: 'gros.png',
            octets: complete(octetsPng(), 400 * 1024 + 1),
          ),
        ),
      );
      await ouvrirModale(tester);
      await choisir(tester);
      expect(
        texte(tester, 'depense-recu-refus'),
        'Le fichier photo recu ne peut pas peser plus de 400 kilo-octets.',
      );
    });

    testWidgets('« Retirer » vide le choix ; annuler la fenêtre ne change '
        'rien ; un second fichier remplace le premier', (tester) async {
      final selecteur = SelecteurEssai(
        lu: FichierLu(nom: 'ticket.png', octets: octetsPng()),
      );
      await monter(tester, selecteur: selecteur);
      await ouvrirModale(tester);
      await choisir(tester);
      expect(texte(tester, 'depense-recu-nom'), startsWith('ticket.png'));

      await tester.tap(find.byKey(const Key('depense-recu-retirer')));
      await tester.pumpAndSettle();
      expect(texte(tester, 'depense-recu-nom'), 'Aucun fichier choisi');

      // « Annuler » dans la fenêtre native : rien ne change.
      await tester.pumpWidget(const SizedBox());
      await monter(tester, selecteur: SelecteurEssai());
      await ouvrirModale(tester);
      await choisir(tester);
      expect(texte(tester, 'depense-recu-nom'), 'Aucun fichier choisi');
      expect(find.byKey(const Key('depense-recu-refus')), findsNothing);
    });

    testWidgets('l’aide du champ est la phrase VRAIE : plus de « douzaine », '
        'plus de réduction promise', (tester) async {
      await monter(tester);
      await ouvrirModale(tester);
      final aide = texte(tester, 'depense-recu-aide');
      expect(aide, contains('400 kilo-octets'));
      expect(aide, isNot(contains('douzaine')));
      expect(aide, isNot(contains('est réduite')));
    });
  });

  group('la colonne « Pièces » dit l’état VRAI du reçu', () {
    Future<Depense> avecStatut(String statut, {String? cause}) async {
      final d = await saisir(recu: png());
      await db.customStatement(
        'UPDATE depenses_local SET recu_statut = ?, recu_cause = ? WHERE id = ?',
        [statut, cause, d.id],
      );
      return d;
    }

    String infobulle(WidgetTester tester, Key cle) => tester
        .widget<Tooltip>(
          find
              .ancestor(of: find.byKey(cle), matching: find.byType(Tooltip))
              .first,
        )
        .message!;

    testWidgets('en attente d’envoi : pastille ambre et infobulle qui dit '
        'POURQUOI (hors réseau, éteinte, dépense pas acceptée)', (
      tester,
    ) async {
      final d = await avecStatut('en_attente');
      await monter(tester);
      expect(find.text('en attente d’envoi'), findsOneWidget);
      expect(
        infobulle(tester, Key('depense-recu-etat-${d.id}')),
        TextesEtatRecu.enAttente,
      );
    });

    testWidgets('envoyé : seulement quand la base le dit (l’accusé)', (
      tester,
    ) async {
      final d = await avecStatut('envoye');
      await monter(tester);
      expect(find.text('envoyé'), findsOneWidget);
      expect(find.text('en attente d’envoi'), findsNothing);
      expect(
        infobulle(tester, Key('depense-recu-etat-${d.id}')),
        TextesEtatRecu.envoye,
      );
    });

    testWidgets('refusé : la CAUSE du serveur est dite', (tester) async {
      final d = await avecStatut(
        'refuse',
        cause: 'Le champ photo recu doit être une image.',
      );
      await monter(tester);
      expect(find.text('refusé'), findsOneWidget);
      expect(
        infobulle(tester, Key('depense-recu-etat-${d.id}')),
        'Refusé par le serveur : Le champ photo recu doit être une image.',
      );
    });

    testWidgets('reçu d’un autre poste : « reçu » seul, aucun état d’envoi', (
      tester,
    ) async {
      final d = await saisir();
      await dao.retenirReferenceRecu(
        d.id,
        sha256: RecusDepensesLocaux.empreinte(octetsPng()),
        taille: 70,
        type: 'image/png',
      );
      await monter(tester);
      expect(find.byKey(Key('depense-recu-${d.id}')), findsOneWidget);
      expect(find.byKey(Key('depense-recu-etat-${d.id}')), findsNothing);
      expect(find.byKey(const Key('depenses-sans-recu')), findsNothing);
    });

    testWidgets('en lecture seule sur M10, le lien « reçu » s’ouvre (lire '
        'n’est pas écrire)', (tester) async {
      final d = await saisir(recu: png());
      await monter(tester, droits: const {'M10': 'L'});
      await tester.tap(find.byKey(Key('depense-recu-${d.id}')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('depense-recu-modale')), findsOneWidget);
      expect(find.byKey(const Key('depense-recu-image')), findsOneWidget);
    });
  });

  group('le clic sur « reçu »', () {
    testWidgets('un reçu de CE poste s’ouvre : image, libellé, état — sans '
        'aucune requête', (tester) async {
      final d = await saisir(recu: png());
      final faux = FauxTelechargement((id) => throw StateError('RÉSEAU'));
      await monter(
        tester,
        surcharges: [telechargementRecuDepenseProvider.overrideWithValue(faux)],
      );
      await tester.tap(find.byKey(Key('depense-recu-${d.id}')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('depense-recu-modale')), findsOneWidget);
      expect(find.byKey(const Key('depense-recu-image')), findsOneWidget);
      expect(texte(tester, 'depense-recu-libelle'), 'Marché du matin');
      expect(texte(tester, 'depense-recu-etat'), TextesEtatRecu.enAttente);
      expect(faux.demandes, [d.id], reason: 'demandé AU CLIC, une fois');

      await tester.tap(find.byKey(const Key('depense-recu-fermer')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('depense-recu-modale')), findsNothing);
    });

    testWidgets('un reçu qui ne peut pas venir : la phrase DIT pourquoi, '
        'jamais une image absente en silence', (tester) async {
      final d = await saisir();
      await dao.retenirReferenceRecu(
        d.id,
        sha256: 'a' * 64,
        taille: 70,
        type: 'image/png',
      );
      final faux = FauxTelechargement(
        (id) async => const RecuIndisponible(TextesRecuDistant.desactivee),
        direct: false,
      );
      await monter(
        tester,
        surcharges: [telechargementRecuDepenseProvider.overrideWithValue(faux)],
      );
      await tester.tap(find.byKey(Key('depense-recu-${d.id}')));
      await tester.pump();
      expect(find.byKey(const Key('depense-recu-chargement')), findsOneWidget);
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(const Key('depense-recu-indisponible')),
                matching: find.byType(Text),
              ),
            )
            .data,
        TextesRecuDistant.desactivee,
      );
      expect(find.byKey(const Key('depense-recu-image')), findsNothing);
      expect(texte(tester, 'depense-recu-etat'), TextesEtatRecu.duServeur);
    });

    testWidgets('un reçu refusé montre la cause dans la fenêtre', (
      tester,
    ) async {
      final d = await saisir(recu: png());
      await db.customStatement(
        'UPDATE depenses_local SET recu_statut = ?, recu_cause = ? WHERE id = ?',
        ['refuse', 'Cette dépense porte déjà un autre reçu.', d.id],
      );
      await monter(
        tester,
        surcharges: [
          telechargementRecuDepenseProvider.overrideWithValue(
            FauxTelechargement((id) => throw StateError('RÉSEAU')),
          ),
        ],
      );
      await tester.tap(find.byKey(Key('depense-recu-${d.id}')));
      await tester.pumpAndSettle();
      expect(
        texte(tester, 'depense-recu-etat'),
        'Refusé par le serveur : Cette dépense porte déjà un autre reçu.',
      );
    });
  });
}

/// Le rangement des reçus EN MÉMOIRE (voir l'en-tête du fichier).
final class RecusEnMemoire extends RecusDepensesLocaux {
  RecusEnMemoire() : super(() async => throw StateError('disque'));

  final Map<String, List<int>> fichiers = {};

  @override
  Future<RecuRange> ranger(
    String depenseId,
    TypeRecu type,
    List<int> octets,
  ) async {
    final nom = RecusDepensesLocaux.nomDe(depenseId, type);
    fichiers[nom] = List<int>.of(octets);
    return RecuRange(
      nom: nom,
      sha256: RecusDepensesLocaux.empreinte(octets),
      taille: octets.length,
    );
  }

  @override
  Future<Uint8List?> lire(String? nom) async {
    final f = fichiers[nom];
    return f == null ? null : Uint8List.fromList(f);
  }

  @override
  Future<void> retirer(String? nom) async => fichiers.remove(nom);
}

/// Le téléchargement remplacé : ce que l'écran en fait, sans réseau. Par défaut
/// il rend le fichier du poste (le reçu de CE poste, déjà là).
final class FauxTelechargement implements TelechargementRecuDepense {
  FauxTelechargement(this._repondre, {this.direct = true});

  final Object? Function(String id) _repondre;

  /// Vrai : le fichier est celui du poste (aucune requête, [_repondre] n'est
  /// jamais appelé) ; faux : [_repondre] décide.
  final bool direct;
  final List<String> demandes = [];

  @override
  int get tailleMaxOctets => 5 * 1024 * 1024;

  @override
  Future<IssueRecuDistant> obtenir(String depenseId) async {
    demandes.add(depenseId);
    if (direct) {
      return RecuDisponible(octets: octetsPng(), type: TypeRecu.png);
    }
    return await Future<Object?>.value(_repondre(depenseId))
        as IssueRecuDistant;
  }
}
