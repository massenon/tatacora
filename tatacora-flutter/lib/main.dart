import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/database/app_database.dart';
import 'core/demarrage/demarrage_resilient.dart';
import 'core/demarrage/journal_demarrage.dart';
import 'core/di/providers.dart';
import 'core/router/app_router.dart';
import 'features/auth/presentation/voile_verrou_session.dart';
import 'core/theme/app_theme.dart';
import 'features/comptabilite/presentation/providers_comptabilite.dart';
import 'features/synchronisation/presentation/providers_synchronisation.dart';
import 'features/transverse/presentation/providers_contact_editeur.dart';
import 'features/notifications/presentation/providers_notifications.dart'
    show relanceBoiteEmailsProvider;

/// Point d'entrée — flavors `dev`, `recette`, `production`.
///
/// L'environnement se choisit au build par `--dart-define=ENV=...`, jamais à
/// l'exécution. Le flavor `demo` a son propre point d'entrée (`main_demo.dart`)
/// parce qu'il ne doit émettre aucun appel réseau : partager ce fichier
/// laisserait la possibilité d'en émettre un par inadvertance.
///
/// Le démarrage est enveloppé (PRD réinstallation R1) : la fenêtre s'ouvre sur
/// « Mise à jour de la base du poste… », la base est ouverte et migrée, puis
/// seulement le premier écran métier ; toute erreur laisse une ligne dans
/// `demarrage.log` et affiche l'écran de panne.
void main() {
  final controleur = ControleurDemarrage();
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    brancherFilets(controleur);
    Directory? dossier;
    try {
      dossier = await dossierDonneesDuPoste();
      controleur.attacherJournal(
        JournalDemarrage(dossier)..nouvelleSession('Démarrage TATACORA'),
      );
    } on Object catch (e, s) {
      controleur.signaler('dossier des données', e, s);
    }
    runApp(
      DemarrageResilient(
        controleur: controleur,
        dossierDonnees: dossier?.path,
        preparer: () => ouvrirBaseDuPoste(controleur.journal),
        construire: (base) => ProviderScope(
          overrides: [baseDemarrageProvider.overrideWithValue(base)],
          child: const ApplicationTatacora(),
        ),
      ),
    );
  }, (erreur, pile) => controleur.signaler('zone', erreur, pile));
}

class ApplicationTatacora extends ConsumerStatefulWidget {
  const ApplicationTatacora({super.key});

  @override
  ConsumerState<ApplicationTatacora> createState() => _EtatApplication();
}

class _EtatApplication extends ConsumerState<ApplicationTatacora> {
  // ⚠ Un `AppLifecycleListener` vivait ici : il réveillait la synchronisation
  // au retour au premier plan (PA-64), retiré avec « zéro réseau » le
  // 14/09/2026. Depuis le lot F2a, la synchronisation revient en tâche de
  // fond par `synchronisationAutomatiqueProvider` (démarrage + toutes les
  // 5 minutes) et après chaque clôture de caisse ; le retour au premier plan
  // n'est PAS un déclencheur.

  @override
  void initState() {
    super.initState();
    // Restauration de session au démarrage : un utilisateur déjà connecté ne
    // doit pas ressaisir son mot de passe à chaque ouverture.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(sessionProvider.notifier).restaurer();
      // Le référentiel comptable (plan du PO, journaux, centres, exercice de
      // l'année) s'installe ICI, au démarrage : la migration v15 crée des
      // tables vides. Idempotent. Un échec reste dans l'état du fournisseur et
      // est relevé par `moteurComptableProvider` (il ne se tait pas).
      ref.read(referentielComptableProvider);
      // La relance des messages à l'éditeur restés en attente (Lot J2 partie
      // 2, 14/10/2026) : une première fois maintenant, puis toutes les cinq
      // minutes tant que l'application tourne. L'une des DEUX actions réseau
      // du poste (avec la synchronisation, ci-dessous) ; `main_demo.dart` ne
      // la démarre pas.
      ref.read(relanceMessagesEditeurProvider);
      // La relance des e-mails de notification en boîte d'envoi (schéma v39,
      // 26/10/2026) : même rythme, même tentative-fait-foi, SMTP direct (pas
      // de la synchronisation : l'interrupteur ne la coupe pas).
      ref.read(relanceBoiteEmailsProvider);
      // Lot F1 : la file d'envoi libère les baux d'un processus tué.
      ref.read(liberationBauxSyncProvider);
      // Lot F2a : la synchronisation en tâche de fond — une première fois
      // maintenant, puis toutes les 5 minutes. Rien ne l'attend ; un poste
      // non appairé ne tente rien. `main_demo.dart` ne la démarre pas.
      ref.read(synchronisationAutomatiqueProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'LogiReStock — TATACORA AFRIQUE',
      debugShowCheckedModeBanner: false,
      // Le messager de la garde du routeur (« Accès refusé à ce module. »).
      scaffoldMessengerKey: messagerApplication,
      theme: AppTheme.clair,
      routerConfig: ref.watch(routeurProvider),
      // Le verrou de session (`layouts/pwa` le monte une fois pour tout écran) :
      // au-dessus du `Navigator`, donc au-dessus des modales ouvertes.
      builder: (context, child) =>
          VoileVerrouSession(child: child ?? const SizedBox.shrink()),
    );
  }
}
