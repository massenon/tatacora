import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/theme/app_colors.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/fiche_reservation.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/periode_sejour.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/reservation.dart';
import 'package:tatacora_flutter/features/hebergement/domain/messages_annulation.dart';
import 'package:tatacora_flutter/features/hebergement/presentation/widgets/modale_annulation_reservation.dart';

/// Ce que la modale « Annuler cette réservation » MONTRE, élément par élément
/// (`hebergement/reservations.blade.php`, modale `annulation_titre`).
///
/// Les flux (refus, pièce, atomicité) sont dans `ecrans_test.dart` et
/// `acompte_piece_test.dart` ; ce fichier tient le RENDU, en montant la modale
/// seule à un instant FIXE — le délai avant l'arrivée en dépend, et un test
/// qui lirait l'horloge ne dirait jamais la même chose deux jours de suite.
void main() {
  final arrivee = DateTime(2031, 7, 10);

  Reservation reservation({int acompte = 20000}) => Reservation(
    id: 'res-1',
    reference: 'LOC-1',
    clientId: 'cli-1',
    clientNom: 'KORA Jean',
    uniteId: 'u-1',
    periode: PeriodeSejour(arrivee: arrivee, depart: DateTime(2031, 7, 12)),
    tarifNuit: 28000,
    statut: StatutReservation.confirmee,
    statutSynchronisation: StatutSynchronisation.local,
    creeeLe: DateTime(2031, 6, 1),
    acompte: acompte,
    modePaiement: ModePaiementReservation.especes,
  );

  Future<void> monter(
    WidgetTester tester, {
    required DateTime maintenant,
    int acompte = 20000,
    String? nomClient = 'Jean KORA',
    String taux = '50.00',
  }) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ModaleAnnulationReservation(
              reservation: reservation(acompte: acompte),
              nomClient: nomClient,
              tauxInitial: taux,
              maintenant: maintenant,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  String texte(WidgetTester tester, String cle) =>
      tester.widget<Text>(find.byKey(Key(cle))).data!;

  Color? fond(WidgetTester tester, String cle) {
    final c = tester.widget<Container>(find.byKey(Key(cle)));
    return (c.decoration! as BoxDecoration).color;
  }

  testWidgets('le titre, le sous-titre (prénom puis nom) et les deux montants '
      'de référence', (tester) async {
    await monter(tester, maintenant: DateTime(2031, 7, 1));

    expect(find.text(MessagesAnnulation.titre), findsOneWidget);
    expect(
      find.text('la réservation de Jean KORA du 10/07/2031 au 12/07/2031'),
      findsOneWidget,
    );
    expect(find.text(MessagesAnnulation.montantTotal), findsOneWidget);
    expect(texte(tester, 'annulation-total'), '56 000 FCFA');
    expect(find.text(MessagesAnnulation.acompteVerse), findsOneWidget);
    expect(texte(tester, 'annulation-acompte'), '20 000 FCFA');
  });

  testWidgets('sans client, le sous-titre écrit le tiret de la vue', (
    tester,
  ) async {
    await monter(tester, maintenant: DateTime(2031, 7, 1), nomClient: null);
    expect(
      find.text('la réservation de — du 10/07/2031 au 12/07/2031'),
      findsOneWidget,
    );
  });

  group('Le délai avant l’arrivée — informatif, jamais un automatisme', () {
    testWidgets('loin de l’arrivée : « Prestation dans N heure(s). », fond '
        'ardoise, aucune mention de 24 h', (tester) async {
      await monter(tester, maintenant: DateTime(2031, 7, 1));
      final ligne = find.descendant(
        of: find.byKey(const Key('annulation-delai')),
        matching: find.byType(Text),
      );
      final t = tester.widget<Text>(ligne).data!;
      expect(t, 'Prestation dans 216.0 heure(s).');
      expect(t, isNot(contains('24h')));
      expect(
        fond(tester, 'annulation-delai'),
        isNot(AppColors.reserveGoldFond),
      );
    });

    testWidgets('à moins de 24 h : la mention du taux de référence ET le fond '
        'or', (tester) async {
      await monter(tester, maintenant: DateTime(2031, 7, 9, 10));
      final t = tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(const Key('annulation-delai')),
              matching: find.byType(Text),
            ),
          )
          .data!;
      expect(
        t,
        'Prestation dans 14.0 heure(s). — ${MessagesAnnulation.sousSeuil}',
      );
      expect(fond(tester, 'annulation-delai'), AppColors.reserveGoldFond);
    });

    testWidgets('arrivée dépassée : « La date d’arrivée est déjà passée. » et '
        'toujours sous le seuil', (tester) async {
      await monter(tester, maintenant: DateTime(2031, 7, 10, 10));
      final t = tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(const Key('annulation-delai')),
              matching: find.byType(Text),
            ),
          )
          .data!;
      expect(
        t,
        '${MessagesAnnulation.delaiPasse} — ${MessagesAnnulation.sousSeuil}',
      );
      expect(fond(tester, 'annulation-delai'), AppColors.reserveGoldFond);
    });

    testWidgets('à 24 h pile : pas sous le seuil (la frontière est stricte)', (
      tester,
    ) async {
      await monter(tester, maintenant: DateTime(2031, 7, 9));
      expect(
        fond(tester, 'annulation-delai'),
        isNot(AppColors.reserveGoldFond),
      );
    });
  });

  group('Le taux et le remboursement', () {
    testWidgets('avec un acompte : libellés, aides, sélecteur de mode ET '
        'valeur', (tester) async {
      await monter(tester, maintenant: DateTime(2031, 7, 1));

      // Le libellé est un texte riche (l'astérisque rouge du champ obligatoire).
      expect(
        find.textContaining(MessagesAnnulation.champTaux, findRichText: true),
        findsOneWidget,
      );
      expect(find.textContaining(' *', findRichText: true), findsWidgets);
      expect(find.text(MessagesAnnulation.tauxAide), findsOneWidget);
      expect(
        find.textContaining(
          MessagesAnnulation.champRemboursement,
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(find.text(MessagesAnnulation.remboursementAide), findsOneWidget);
      expect(find.byKey(const Key('annulation-mode')), findsOneWidget);
      // Le mode sélectionné par défaut est lu à l'écran : « % de l'acompte ».
      expect(find.text(MessagesAnnulation.modePourcentage), findsWidgets);
      expect(find.byKey(const Key('annulation-valeur')), findsOneWidget);
      expect(find.byKey(const Key('annulation-aucun-acompte')), findsNothing);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('annulation-taux')))
            .controller!
            .text,
        '50.00',
      );
    });

    testWidgets('le taux pré-rempli est celui qu’on lui donne, pas un 50 en '
        'dur', (tester) async {
      await monter(tester, maintenant: DateTime(2031, 7, 1), taux: '30');
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('annulation-taux')))
            .controller!
            .text,
        '30',
      );
    });

    testWidgets('sans acompte : la phrase « rien à rembourser », ni mode ni '
        'valeur', (tester) async {
      await monter(tester, maintenant: DateTime(2031, 7, 1), acompte: 0);

      expect(find.text(MessagesAnnulation.aucunAcompte), findsOneWidget);
      expect(find.byKey(const Key('annulation-mode')), findsNothing);
      expect(find.byKey(const Key('annulation-valeur')), findsNothing);
      expect(find.text(MessagesAnnulation.remboursementAide), findsNothing);
    });

    testWidgets('le suggéré : 20 000 F d’acompte moins 28 000 F de commission '
        '(50 % de 56 000) est négatif, donc « 0 »', (tester) async {
      await monter(tester, maintenant: DateTime(2031, 7, 1));
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('annulation-valeur')))
            .controller!
            .text,
        '0',
      );
    });

    testWidgets('le suggéré avec un taux bas : 10 % -> 5 600 F de commission, '
        'il reste 14 400 F = 72 % de l’acompte', (tester) async {
      await monter(tester, maintenant: DateTime(2031, 7, 1), taux: '10');
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('annulation-valeur')))
            .controller!
            .text,
        '72.00',
      );
    });
  });

  testWidgets('le rappel de RG-02 : la réservation est CONSERVÉE (en gras), '
      'jamais supprimée', (tester) async {
    await monter(tester, maintenant: DateTime(2031, 7, 1));

    final rappel = tester.widget<Container>(
      find.byKey(const Key('annulation-rappel')),
    );
    expect(
      (rappel.decoration! as BoxDecoration).color,
      AppColors.badgeRougeFond,
    );
    final riche = tester.widget<RichText>(
      find.descendant(
        of: find.byKey(const Key('annulation-rappel')),
        matching: find.byType(RichText),
      ),
    );
    expect(
      riche.text.toPlainText(),
      '${MessagesAnnulation.rappelAvant}${MessagesAnnulation.rappelGras}'
      '${MessagesAnnulation.rappelApres}',
    );
    // Le seul morceau en gras est « conservée ».
    final gras = <String>[];
    riche.text.visitChildren((span) {
      if (span is TextSpan &&
          span.style?.fontWeight == FontWeight.bold &&
          span.text != null) {
        gras.add(span.text!);
      }
      return true;
    });
    expect(gras, [MessagesAnnulation.rappelGras]);
  });

  testWidgets('les deux boutons : « Annuler » renonce, « Annuler la '
      'réservation » confirme', (tester) async {
    await monter(tester, maintenant: DateTime(2031, 7, 1));
    expect(find.byKey(const Key('annulation-renoncer')), findsOneWidget);
    expect(find.text(MessagesAnnulation.renoncer), findsOneWidget);
    expect(find.byKey(const Key('annulation-confirmer')), findsOneWidget);
    expect(find.text(MessagesAnnulation.confirmer), findsOneWidget);
  });
}
