import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/di/providers.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/comptabilite/presentation/providers_comptabilite.dart';
import 'features/transverse/presentation/providers_contact_editeur.dart';

/// Point d'entrée — flavors `dev`, `recette`, `production`.
///
/// L'environnement se choisit au build par `--dart-define=ENV=...`, jamais à
/// l'exécution. Le flavor `demo` a son propre point d'entrée (`main_demo.dart`)
/// parce qu'il ne doit émettre aucun appel réseau : partager ce fichier
/// laisserait la possibilité d'en émettre un par inadvertance.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: ApplicationTatacora()));
}

class ApplicationTatacora extends ConsumerStatefulWidget {
  const ApplicationTatacora({super.key});

  @override
  ConsumerState<ApplicationTatacora> createState() => _EtatApplication();
}

class _EtatApplication extends ConsumerState<ApplicationTatacora> {
  // ⚠ Un `AppLifecycleListener` vivait ici : il réveillait la synchronisation
  // au retour au premier plan (PA-64). Le poste est zéro réseau depuis le
  // 14/09/2026 — il n'y a plus de file à faire partir, donc plus rien à
  // réveiller. Ne rétablissez pas l'écoute « au cas où » : un déclencheur qui
  // n'appelle rien est exactement le défaut de PA-63, à l'envers.

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
      // minutes tant que l'application tourne. C'est la SEULE action réseau
      // du poste ; `main_demo.dart` ne la démarre pas.
      ref.read(relanceMessagesEditeurProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'TATACORA AFRIQUE',
      debugShowCheckedModeBanner: false,
      // Le messager de la garde du routeur (« Accès refusé à ce module. »).
      scaffoldMessengerKey: messagerApplication,
      theme: AppTheme.clair,
      routerConfig: ref.watch(routeurProvider),
    );
  }
}
