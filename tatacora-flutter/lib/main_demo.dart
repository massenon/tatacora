import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/environnement.dart';
import 'core/database/app_database.dart';
import 'core/dev/mode_demo.dart';
import 'core/di/providers.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/comptabilite/data/installateur_referentiel.dart';

/// Point d'entrée du flavor `demo` — `SEEDER_TEST_FLUTTER.md` §4.
///
/// ## Pourquoi un point d'entrée distinct
///
/// Le flavor `demo` fonctionne **entièrement en local**, sans backend. Partager
/// `main.dart` laisserait la possibilité d'émettre un appel réseau par
/// inadvertance — et une démonstration commerciale qui échoue faute de réseau
/// est exactement ce que ce flavor existe pour éviter.
///
/// Lancement :
/// ```
/// flutter run --dart-define=ENV=demo -t lib/main_demo.dart
/// ```
///
/// ## Ce qui reste interdit ici
///
/// L'écran de connexion n'affiche **aucune grille de comptes cliquables**,
/// même en démonstration (`SECURITY_STRICT.md` §12), et **aucun compte n'est
/// semé** : le poste demande la création du premier compte, comme en
/// exploitation. Le flavor change la source des données, jamais les règles de
/// sécurité.
///
/// ## La base est amorcée AVANT le premier écran (PA-201)
///
/// Jusqu'au 12/09/2026, ce point d'entrée n'amorçait rien : le flavor
/// interdisait le réseau — la seule source de données qui existe — sans en
/// fournir aucune autre, et la démonstration s'ouvrait sur des tables vides.
/// [amorcerModeDemo] sème le jeu relevé sur le serveur de démonstration, par
/// les auteurs habituels de chaque référentiel.
///
/// La base amorcée est **celle que les écrans liront** : `baseLocaleProvider`
/// en construirait une seconde, et l'application afficherait alors un poste
/// vide à côté d'un poste semé.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Garde-fou de build : lancer ce point d'entrée sans `ENV=demo` produirait
  // une application qui croit être en démonstration tout en pointant vers un
  // vrai backend. Mieux vaut refuser de démarrer que corrompre des données.
  final env = Environnement.actuel;
  if (!env.estHorsLigneIntegral) {
    throw StateError(
      'main_demo.dart exige --dart-define=ENV=demo. '
      'Environnement détecté : ${env.libelle}.',
    );
  }

  // Lot F1 : la démonstration n'alimente JAMAIS la file d'envoi — ses données
  // sont fictives (`AppDatabase.fileSynchronisationActive`). Le défaut du
  // flavor `demo` le dit déjà ; on l'écrit ici pour qu'aucune régression du
  // défaut ne le défasse.
  final base = AppDatabase(fileSynchronisation: false);
  // Le référentiel comptable (plan du PO, journaux, centres, exercice) est
  // installé EXPLICITEMENT ici, et AVANT l'amorçage : le moteur ne doit jamais
  // être servi sur un plan vide, y compris en démonstration, et les dépenses du
  // jeu de démonstration sont confrontées au plan avant d'être écrites.
  // Idempotent.
  await installerReferentielComptable(
    base,
    contenuPlan: await rootBundle.loadString(cheminAssetPlanComptable),
    maintenant: DateTime.now(),
  );
  await amorcerModeDemo(base);

  runApp(
    ProviderScope(
      overrides: [baseLocaleProvider.overrideWithValue(base)],
      child: const ApplicationDemo(),
    ),
  );
}

class ApplicationDemo extends ConsumerWidget {
  const ApplicationDemo({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'TATACORA AFRIQUE — Démonstration',
      debugShowCheckedModeBanner: false,
      // Le messager de la garde du routeur (« Accès refusé à ce module. »).
      scaffoldMessengerKey: messagerApplication,
      theme: AppTheme.clair,
      routerConfig: ref.watch(routeurProvider),
    );
  }
}
