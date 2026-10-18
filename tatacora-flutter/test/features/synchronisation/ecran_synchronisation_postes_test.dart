import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/synchronisation/data/service_suivi_postes.dart';
import 'package:tatacora_flutter/features/synchronisation/presentation/ecran_synchronisation_postes.dart';

import 'support/faux_transport.dart';

/// L'écran « Synchroniser les postes » du poste (décision PO du 18/10/2026) :
/// l'état de chaque poste tel que le serveur le connaît, le bouton qui
/// enregistre la demande, et la raison dite quand le serveur ne répond pas.
final class _ServiceFactice extends ServiceSuiviPostes {
  _ServiceFactice(this.etat, {this.demande})
    : super(transport: FauxTransport(reponseLot), urlServeur: null);

  IssueSuiviPostes etat;
  final DateTime? demande;
  int demandes = 0;

  @override
  Future<IssueSuiviPostes> lire() async => etat;

  @override
  Future<DateTime?> demander() async {
    demandes++;
    if (demande != null) {
      etat = SuiviPostesLu(demandeeLe: demande, postes: const []);
    }
    return demande;
  }
}

void main() {
  Future<void> monter(WidgetTester tester, ServiceSuiviPostes service) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [serviceSuiviPostesProvider.overrideWithValue(service)],
        child: MaterialApp(
          theme: AppTheme.clair,
          home: const Scaffold(body: EcranSynchronisationPostes()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('les postes tels que le serveur les connaît', (tester) async {
    await monter(
      tester,
      _ServiceFactice(
        SuiviPostesLu(
          demandeeLe: DateTime(2026, 10, 18, 10),
          postes: [
            EtatPosteServeur(
              posteId: 'COMPTOIR',
              utilisateur: 'caisse1',
              derniereMontee: DateTime(2026, 10, 18, 9, 58),
              derniereDescente: DateTime(2026, 10, 18, 10, 0, 20),
              enAttente: 0,
              demandeSuivie: true,
            ),
            const EtatPosteServeur(
              posteId: 'RECEPTION',
              utilisateur: null,
              derniereMontee: null,
              derniereDescente: null,
              enAttente: null,
              demandeSuivie: false,
            ),
          ],
        ),
      ),
    );

    expect(find.text('Synchroniser les postes'), findsOneWidget);
    expect(find.text('Dernière demande : 18/10/2026 10:00:00'), findsOneWidget);
    expect(find.text('COMPTOIR'), findsOneWidget);
    expect(find.text('18/10/2026 10:00'), findsOneWidget);
    expect(find.text('Reçue'), findsOneWidget);
    expect(find.text('Pas encore reçue'), findsOneWidget);
  });

  testWidgets('le bouton enregistre la demande et la confirme', (tester) async {
    final service = _ServiceFactice(
      const SuiviPostesLu(demandeeLe: null, postes: []),
      demande: DateTime(2026, 10, 18, 10, 5, 7),
    );
    await monter(tester, service);
    expect(
      find.text(
        "Aucune demande de synchronisation n'a encore été faite depuis le serveur.",
      ),
      findsOneWidget,
    );
    expect(
      find.text("Aucun poste ne s'est encore synchronisé avec ce serveur."),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('bouton-synchroniser-postes')));
    await tester.pumpAndSettle();

    expect(service.demandes, 1);
    expect(
      find.text(
        'Demande envoyée le 18/10/2026 10:05:07. Les postes allumés et connectés la suivent dans la minute.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('hors réseau : l’écran le dit, la demande aussi', (tester) async {
    final service = _ServiceFactice(
      const SuiviPostesIndisponible(ServiceSuiviPostes.horsReseau),
    );
    await monter(tester, service);
    expect(find.text(ServiceSuiviPostes.horsReseau), findsOneWidget);

    await tester.tap(find.byKey(const Key('bouton-synchroniser-postes')));
    await tester.pumpAndSettle();
    expect(find.text(ServiceSuiviPostes.horsReseau), findsNWidgets(2));
  });
}
