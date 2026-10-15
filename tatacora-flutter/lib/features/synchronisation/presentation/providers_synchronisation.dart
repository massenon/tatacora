import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/environnement.dart';
import '../../../core/di/providers.dart';
import '../../transverse/data/configuration_poste.dart';
import '../data/operations_sync_dao.dart';
import '../data/service_appairage.dart';
import '../data/sync_manager.dart';
import '../data/transport_synchronisation.dart';
import '../domain/bilan_synchronisation.dart';

/// La file d'envoi du poste (lot F1, 15/10/2026).
final operationsSyncDaoProvider = Provider<OperationsSyncDao>(
  (ref) => OperationsSyncDao(ref.watch(baseLocaleProvider)),
);

/// Au DÉMARRAGE du poste : les opérations restées `en_cours` sous un bail
/// échu (le lot d'un processus tué pendant un envoi) redeviennent
/// `en_attente`. Lu par `main.dart` après la première image ; ne bloque rien
/// et n'atteint jamais l'interface — une base fermée pendant l'arrêt, par
/// exemple, sera traitée au démarrage suivant.
final liberationBauxSyncProvider = FutureProvider<int>((ref) async {
  try {
    return await ref.watch(operationsSyncDaoProvider).libererBauxExpires();
  } on Object {
    return 0;
  }
});

/* ==================================================================== */
/* Lot F2a — transport, appairage, moteur d'envoi, déclencheurs         */
/* ==================================================================== */

/// Le transport HTTP — un test le remplace (`MockClient` ou faux).
final transportSynchronisationProvider = Provider<TransportSynchronisation>(
  (ref) => TransportHttp(),
);

/// L'adresse de l'API du BUILD (`--dart-define=ENV=…`) ; `null` en
/// démonstration. Jamais une saisie.
final urlServeurSynchronisationProvider = Provider<String?>(
  (ref) => Environnement.actuel.baseUrl,
);

/// Le chemin de `poste.json` — un test pose le sien.
final cheminConfigurationPosteProvider = Provider<Future<String> Function()>(
  (ref) => cheminConfigurationPoste,
);

/// La démonstration ne se synchronise JAMAIS : flavor `demo`, ou base dont la
/// file est inactive (`AppDatabase.fileSynchronisationActive`).
final synchronisationInterditeProvider = Provider<bool>(
  (ref) =>
      Environnement.actuel.estHorsLigneIntegral ||
      !ref.watch(baseLocaleProvider).fileSynchronisationActive,
);

/// L'appairage du poste (Paramètres → Synchronisation).
final serviceAppairageProvider = Provider<ServiceAppairage>((ref) {
  final chemin = ref.watch(cheminConfigurationPosteProvider);
  return ServiceAppairage(
    transport: ref.watch(transportSynchronisationProvider),
    urlServeur: ref.watch(synchronisationInterditeProvider)
        ? null
        : ref.watch(urlServeurSynchronisationProvider),
    lecteur: LecteurConfigurationPoste(chemin: chemin),
    ecrivain: EcrivainConfigurationPoste(chemin: chemin),
  );
});

/// L'appairage actuel, relu du fichier à chaque lecture.
final appairageActuelProvider = FutureProvider.autoDispose<AppairagePoste?>(
  (ref) => ref.watch(serviceAppairageProvider).appairageActuel(),
);

/// Le DERNIER bilan de synchronisation de cette session du logiciel — `null`
/// tant qu'aucune n'a eu lieu. L'écran de synchronisation (F2b) le lira.
final dernierBilanSynchronisationProvider =
    NotifierProvider<DernierBilanSynchronisation, BilanSynchronisation?>(
      DernierBilanSynchronisation.new,
    );

final class DernierBilanSynchronisation
    extends Notifier<BilanSynchronisation?> {
  @override
  BilanSynchronisation? build() => null;

  void poser(BilanSynchronisation bilan) => state = bilan;
}

/// Le moteur d'envoi — UNE instance : c'est elle qui tient le « un seul
/// envoi à la fois » du processus.
final syncManagerProvider = Provider<SyncManager>((ref) {
  final chemin = ref.watch(cheminConfigurationPosteProvider);
  return SyncManager(
    dao: ref.watch(operationsSyncDaoProvider),
    transport: ref.watch(transportSynchronisationProvider),
    urlServeur: ref.watch(urlServeurSynchronisationProvider),
    demonstration: ref.watch(synchronisationInterditeProvider),
    lecteur: LecteurConfigurationPoste(chemin: chemin),
    ecrivain: EcrivainConfigurationPoste(chemin: chemin),
    surBilan: (bilan) =>
        ref.read(dernierBilanSynchronisationProvider.notifier).poser(bilan),
  );
});

/// La période du réveil automatique.
const Duration periodeSynchronisation = Duration(minutes: 5);

/// Lance une synchronisation SANS l'attendre et sans rien laisser remonter :
/// ni exception synchrone, ni erreur asynchrone. C'est la forme de TOUT
/// déclencheur automatique — un geste (la clôture de caisse d'abord) ne
/// dépend jamais du réseau.
void lancerSynchronisationSansAttendre(SyncManager Function() manager) {
  try {
    unawaited(
      manager().synchroniserMaintenant().then<void>((_) {}, onError: (_) {}),
    );
  } on Object {
    // Un moteur impossible à construire (base fermée) : rien ne remonte.
  }
}

/// Le déclencheur « après un geste » : appelé par `cloturerLaCaisse` une fois
/// la clôture ÉCRITE. Rend immédiatement.
final declencheurSynchronisationProvider = Provider<void Function()>(
  (ref) =>
      () => lancerSynchronisationSansAttendre(
        () => ref.read(syncManagerProvider),
      ),
);

/// Le réveil AUTOMATIQUE : une synchronisation au démarrage, puis toutes les
/// [periodeSynchronisation] tant que l'application tourne — sans requête
/// quand aucune opération n'est échue (le moteur s'arrête sur une file vide
/// ou en repli). Démarré par `main.dart` après la première image, PAS par
/// `main_demo.dart` (et le moteur refuserait la démonstration de toute
/// façon). Aucune sonde de connectivité : la tentative est l'autorité.
final synchronisationAutomatiqueProvider = Provider<void>((ref) {
  final manager = ref.watch(syncManagerProvider);
  lancerSynchronisationSansAttendre(() => manager);
  final minuteur = Timer.periodic(
    periodeSynchronisation,
    (_) => lancerSynchronisationSansAttendre(() => manager),
  );
  ref.onDispose(minuteur.cancel);
});
