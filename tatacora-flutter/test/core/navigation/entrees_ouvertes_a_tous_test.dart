import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/navigation/navigation_tatacora.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/auth/domain/session.dart';
import 'package:tatacora_flutter/features/synchronisation/data/service_suivi_postes.dart';
import 'package:tatacora_flutter/features/synchronisation/presentation/ecran_synchronisation_postes.dart';
import 'package:tatacora_flutter/features/transverse/domain/roles_du_poste.dart';

import '../../features/synchronisation/support/faux_transport.dart';

/// « Synchronisation », « Import & Export » et « Appairage Postes » sont au menu de TOUS
/// les rôles RBAC par défaut (décision du PO du 09/11/2026), poste ET web : trois droits
/// transverses (`SYNCHRO`, `IMPORT_EXPORT`, `APPAIRAGE`), lecture pour tous, qui ne
/// commandent que la VISIBILITÉ. Chaque geste sensible garde sa garde (rôle
/// d'administration, ou écriture sur `Paramètres`).
///
/// Chaque cas est prouvé par MUTATION : retirer le droit par défaut d'un rôle de la
/// matrice (ici : la clé retirée) fait disparaître l'entrée ET refuse la route.
const _entrees = {
  'Synchronisation': ('/synchronisation', 'SYNCHRO'),
  'Import & Export': ('/import-export', 'IMPORT_EXPORT'),
  'Appairage Postes': ('/synchronisation-postes', 'APPAIRAGE'),
};

final class _Faux extends ServiceSuiviPostes {
  _Faux() : super(transport: FauxTransport(reponseLot), urlServeur: null);

  @override
  Future<IssueSuiviPostes> lire() async => SuiviPostesLu(
    demandeeLe: null,
    cePoste: 'CE-POSTE',
    postes: const [
      EtatPosteServeur(
        posteId: 'AUTRE-POSTE',
        utilisateur: 'caisse',
        appaire: true,
        derniereMontee: null,
        derniereDescente: null,
        enAttente: 0,
        demandeSuivie: false,
      ),
    ],
  );
}

void main() {
  test('la matrice du socle donne la lecture à CHAQUE rôle, l’écriture à '
      'l’administration — et le menu les montre à tous, gérant compris', () {
    expect(socleRbacCdcf.keys, hasLength(12));
    for (final role in socleRbacCdcf.keys) {
      final droits = GardeAcces.depuisJson(socleRbacCdcf[role]!);
      for (final e in _entrees.entries) {
        final (route, code) = e.value;
        final attendu = {'administrateur', 'super_admin'}.contains(role)
            ? NiveauAcces.complet
            : NiveauAcces.lecture;
        expect(
          NiveauAcces.depuisCode(socleRbacCdcf[role]![code]),
          attendu,
          reason: '$role / $code',
        );
        final d = toutesLesDestinations.singleWhere((x) => x.nom == e.key);
        expect(d.route, route);
        expect(
          destinationVisible(d, droits: droits, role: role),
          isTrue,
          reason: '${e.key} doit être au menu de $role',
        );
        expect(
          accesRoute(route, droits: droits, role: role),
          AccesRoute.autorise,
          reason: '$route doit s’ouvrir à $role',
        );
      }
    }
    // Le gérant n'est plus privé de ces trois entrées (les autres masquages restent).
    for (final nom in _entrees.keys) {
      expect(nomsMasquesParRole['gerant'], isNot(contains(nom)));
    }
    expect(nomsMasquesParRole['gerant'], contains('Paramètres'));
  });

  test('MUTATION : retirer le droit par défaut d’un rôle lui retire l’entrée '
      'ET la route', () {
    for (final role in socleRbacCdcf.keys) {
      for (final e in _entrees.entries) {
        final (route, code) = e.value;
        final sans = {...socleRbacCdcf[role]!}..remove(code);
        final droits = GardeAcces.depuisJson(sans);
        final d = toutesLesDestinations.singleWhere((x) => x.nom == e.key);
        expect(
          destinationVisible(d, droits: droits, role: role),
          isFalse,
          reason: '$role sans $code : ${e.key} reste au menu',
        );
        expect(
          accesRoute(route, droits: droits, role: role),
          AccesRoute.refuse,
          reason: '$role sans $code : $route reste ouverte',
        );
      }
    }
  });

  test('le droit retiré à un rôle ne retire QUE son entrée', () {
    final sans = {...socleRbacCdcf['barman']!}..remove('SYNCHRO');
    final droits = GardeAcces.depuisJson(sans);
    for (final e in _entrees.entries) {
      final d = toutesLesDestinations.singleWhere((x) => x.nom == e.key);
      expect(
        destinationVisible(d, droits: droits, role: 'barman'),
        e.key != 'Synchronisation',
        reason: e.key,
      );
    }
  });

  Future<void> monterPostes(WidgetTester tester, String role) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          serviceSuiviPostesProvider.overrideWithValue(_Faux()),
          sessionProvider.overrideWithBuild(
            (ref, n) => Session(
              utilisateurId: 'u-1',
              login: 'essai',
              nom: 'Essai',
              role: role,
              droits: GardeAcces.depuisJson(socleRbacCdcf[role]!),
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.clair,
          home: const Scaffold(body: EcranSynchronisationPostes()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'un rôle non-administrateur voit « Appairage Postes » en lecture : '
    'ni « Révoquer », ni appairage, ni dissociation',
    (tester) async {
      for (final role in socleRbacCdcf.keys.where(
        (r) => !{'administrateur', 'super_admin'}.contains(r),
      )) {
        await monterPostes(tester, role);
        expect(find.text('AUTRE-POSTE'), findsOneWidget, reason: role);
        expect(find.text('Révoquer'), findsNothing, reason: role);
        expect(find.text('Appairer le poste'), findsNothing, reason: role);
        expect(find.text('Réappairer le poste'), findsNothing, reason: role);
        expect(find.text('Dissocier'), findsNothing, reason: role);
        expect(find.text('Tester la connexion'), findsNothing, reason: role);
        expect(
          find.text('L’appairage du poste est réservé aux Administrateurs.'),
          findsOneWidget,
          reason: role,
        );
      }
    },
  );

  testWidgets('un administrateur, lui, a les gestes d’appairage', (
    tester,
  ) async {
    await monterPostes(tester, 'administrateur');
    expect(find.text('Révoquer'), findsOneWidget);
    expect(find.byKey(const Key('appairage-de-ce-poste')), findsOneWidget);
  });
}
