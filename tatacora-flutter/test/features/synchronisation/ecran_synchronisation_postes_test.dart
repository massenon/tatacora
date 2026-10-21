import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/auth/domain/session.dart';
import 'package:tatacora_flutter/features/synchronisation/data/transport_synchronisation.dart';
import 'package:tatacora_flutter/features/transverse/data/configuration_poste.dart';
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
  int lectures = 0;
  final List<String> revoques = [];

  @override
  Future<String> revoquer(String posteId) async {
    revoques.add(posteId);
    return ServiceSuiviPostes.revocationFaite(posteId);
  }

  @override
  Future<IssueSuiviPostes> lire() async {
    lectures++;
    return etat;
  }

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
  Future<void> monter(
    WidgetTester tester,
    ServiceSuiviPostes service, {
    String? role,
  }) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final droits = GardeAcces(const {});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          serviceSuiviPostesProvider.overrideWithValue(service),
          if (role != null)
            sessionProvider.overrideWithBuild(
              (ref, n) => Session(
                utilisateurId: 'u-1',
                login: 'essai',
                nom: 'Essai',
                role: role,
                droits: droits,
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

    expect(find.text('Postes & Appairage'), findsOneWidget);
    expect(find.text('Dernière demande : 18/10/2026 10:00:00'), findsOneWidget);
    expect(find.text('COMPTOIR'), findsOneWidget);
    expect(
      find.text('18/10/2026 09:58'),
      findsOneWidget,
      reason: 'dernier envoi',
    );
    expect(find.textContaining('· Reçue'), findsOneWidget);
    expect(find.textContaining('· Pas encore reçue'), findsOneWidget);
  });

  testWidgets('les neuf colonnes de « Postes & Appairage », leurs dates et '
      'l’état de chaque poste', (tester) async {
    await monter(
      tester,
      _ServiceFactice(
        SuiviPostesLu(
          demandeeLe: null,
          postes: [
            EtatPosteServeur(
              posteId: 'COMPTOIR',
              utilisateur: 'caisse1',
              derniereMontee: DateTime(2026, 10, 21, 9, 30),
              derniereDescente: null,
              enAttente: 3,
              demandeSuivie: true,
              appaire: true,
              appaireLe: DateTime(2026, 10, 1, 8),
              jetonUtiliseLe: DateTime(2026, 10, 21, 9, 45),
              expireLe: DateTime(2026, 11, 1, 8),
              dernierControle: DateTime(2026, 10, 20, 17, 5),
              etat: EtatAppairage.actif,
            ),
            EtatPosteServeur(
              posteId: 'ANCIEN',
              utilisateur: null,
              derniereMontee: null,
              derniereDescente: null,
              enAttente: null,
              demandeSuivie: true,
              appaire: true,
              appaireLe: DateTime(2026, 9, 1),
              jetonUtiliseLe: DateTime(2026, 9, 2),
              etat: EtatAppairage.silencieux,
            ),
            const EtatPosteServeur(
              posteId: 'PERDU',
              utilisateur: null,
              derniereMontee: null,
              derniereDescente: null,
              enAttente: null,
              demandeSuivie: true,
            ),
          ],
        ),
      ),
    );

    for (final colonne in [
      'POSTE',
      'UTILISATEUR',
      'APPAIRÉ LE',
      'DERNIER CONTACT',
      'EXPIRATION',
      'DERNIER ENVOI',
      'DERNIER CONTRÔLE',
      'ÉTAT',
      'ACTIONS',
    ]) {
      expect(find.text(colonne), findsOneWidget, reason: colonne);
    }
    expect(find.text('Actualiser'), findsOneWidget);
    expect(find.text('Demander la synchronisation des postes'), findsOneWidget);
    expect(find.text('01/10/2026 08:00'), findsOneWidget, reason: 'appairé le');
    expect(find.text('21/10/2026 09:45'), findsOneWidget, reason: 'contact');
    expect(find.text('01/11/2026 08:00'), findsOneWidget, reason: 'expiration');
    expect(find.text('20/10/2026 17:05'), findsOneWidget, reason: 'contrôle');
    expect(find.text('Sans expiration'), findsOneWidget, reason: 'ANCIEN');

    expect(
      tester.widget<Text>(find.byKey(const Key('etat-COMPTOIR'))).data,
      'Actif',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('etat-ANCIEN'))).data,
      'Sans nouvelles',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('etat-PERDU'))).data,
      'Non appairé',
    );
    expect(find.textContaining('En attente d\'envoi : 3'), findsOneWidget);
  });

  testWidgets('« Actualiser » relit le serveur sans rien demander', (
    tester,
  ) async {
    final service = _ServiceFactice(
      const SuiviPostesLu(demandeeLe: null, postes: []),
    );
    await monter(tester, service);
    final lecturesAvant = service.lectures;

    await tester.tap(find.byKey(const Key('bouton-actualiser-postes')));
    await tester.pumpAndSettle();

    expect(service.lectures, lecturesAvant + 1);
    expect(service.demandes, 0, reason: 'actualiser n’écrit rien');
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

  group('Révoquer l’appairage d’un poste (19/10/2026)', () {
    SuiviPostesLu deuxPostes() => SuiviPostesLu(
      demandeeLe: null,
      cePoste: 'COMPTOIR',
      postes: [
        for (final (id, appaire) in [
          ('COMPTOIR', true),
          ('RECEPTION', true),
          ('ANCIEN', false),
        ])
          EtatPosteServeur(
            posteId: id,
            utilisateur: null,
            derniereMontee: null,
            derniereDescente: null,
            enAttente: null,
            demandeSuivie: true,
            appaire: appaire,
            jetonUtiliseLe: appaire ? DateTime(2026, 10, 19, 8, 30) : null,
          ),
      ],
    );

    testWidgets('un Administrateur révoque un AUTRE poste, après '
        'confirmation ; jamais le sien, jamais un poste non appairé', (
      tester,
    ) async {
      final service = _ServiceFactice(deuxPostes());
      await monter(tester, service, role: 'administrateur');

      expect(find.text('ACTIONS'), findsOneWidget);
      expect(find.text('19/10/2026 08:30'), findsNWidgets(2));
      expect(find.byKey(const Key('revoquer-COMPTOIR')), findsNothing);
      expect(find.byKey(const Key('revoquer-ANCIEN')), findsNothing);

      // Annuler : rien ne part.
      await tester.ensureVisible(find.byKey(const Key('revoquer-RECEPTION')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('revoquer-RECEPTION')));
      await tester.pumpAndSettle();
      expect(
        find.text("Révoquer l'appairage du poste « RECEPTION » ?"),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('annuler-revocation')));
      await tester.pumpAndSettle();
      expect(service.revoques, isEmpty);

      await tester.ensureVisible(find.byKey(const Key('revoquer-RECEPTION')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('revoquer-RECEPTION')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmer-revocation')));
      await tester.pumpAndSettle();
      expect(service.revoques, ['RECEPTION']);
      expect(
        find.text('Appairage du poste « RECEPTION » révoqué.'),
        findsOneWidget,
      );
    });

    testWidgets('hors Administrateur : aucun bouton', (tester) async {
      await monter(tester, _ServiceFactice(deuxPostes()), role: 'gerant');
      expect(find.byKey(const Key('revoquer-RECEPTION')), findsNothing);
    });

    test(
      'le service appelle la révocation du serveur et dit son issue',
      () async {
        final dossier = await Directory.systemTemp.createTemp(
          'tatacora-revoc-',
        );
        addTearDown(() => dossier.delete(recursive: true));
        final chemin = '${dossier.path}/poste.json';
        File(chemin).writeAsStringSync(
          jsonEncode({
            'poste_id': 'COMPTOIR',
            'jeton_api': '7|jeton',
            'serveur': 'https://serveur.essai/api/v1',
          }),
        );
        var statut = 200;
        final transport = FauxTransport(
          (r) => ReponseHttp(
            statut: statut,
            corps: statut == 422
                ? const {
                    'message': 'Le poste « X » n\'a aucun appairage actif.',
                  }
                : const {'data': {}},
          ),
        );
        final service = ServiceSuiviPostes(
          transport: transport,
          urlServeur: 'https://serveur.essai/api/v1',
          lecteur: LecteurConfigurationPoste(chemin: () async => chemin),
        );

        expect(
          await service.revoquer('PC RÉCEPTION'),
          ServiceSuiviPostes.revocationFaite('PC RÉCEPTION'),
        );
        final requete = transport.requetes.single;
        expect(requete.methode, 'POST');
        expect(
          requete.url.toString(),
          'https://serveur.essai/api/v1/sync/postes/PC%20R%C3%89CEPTION/revocation',
        );
        expect(requete.jeton, '7|jeton');

        statut = 403;
        expect(
          await service.revoquer('X'),
          ServiceSuiviPostes.revocationReservee,
        );
        statut = 422;
        expect(
          await service.revoquer('X'),
          "Le poste « X » n'a aucun appairage actif.",
        );
      },
    );
  });
}
