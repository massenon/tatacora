import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/verrou_session.dart';

/// Où le verrou range l'instant de la dernière activité — le `localStorage` de
/// la vue (`tatacora_derniere_activite`) : sans lui, fermer puis rouvrir
/// l'application ferait oublier l'inactivité, et le verrou se contournerait en
/// quittant le logiciel.
abstract interface class StockageActiviteVerrou {
  Future<DateTime?> lire();
  Future<void> ecrire(DateTime instant);
}

/// Le coffre sécurisé du poste (déjà employé pour la session courante).
///
/// Ne lève JAMAIS : un coffre illisible vaut « aucune activité connue » (jamais
/// inactif, comme la vue sans horodatage) et une écriture ratée se perd en
/// silence — le verrou fonctionne en mémoire dans tous les cas.
final class StockageActiviteCoffre implements StockageActiviteVerrou {
  StockageActiviteCoffre({FlutterSecureStorage? coffre})
    : _coffre = coffre ?? const FlutterSecureStorage();

  final FlutterSecureStorage _coffre;

  @override
  Future<DateTime?> lire() async {
    try {
      final brut = await _coffre.read(key: cleActiviteVerrou);
      final ms = int.tryParse(brut ?? '');
      if (ms == null) return null;
      return DateTime.fromMillisecondsSinceEpoch(ms);
    } on Object {
      return null;
    }
  }

  @override
  Future<void> ecrire(DateTime instant) async {
    try {
      await _coffre.write(
        key: cleActiviteVerrou,
        value: '${instant.millisecondsSinceEpoch}',
      );
    } on Object {
      // Voir la classe : jamais bloquant.
    }
  }
}
