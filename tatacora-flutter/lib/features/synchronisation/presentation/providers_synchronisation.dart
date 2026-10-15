import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../data/operations_sync_dao.dart';

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
