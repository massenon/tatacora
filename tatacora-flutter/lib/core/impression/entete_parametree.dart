import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/parametres/data/parametres_dao.dart';
import '../di/providers.dart';
import 'entete_etablissement.dart';

/// La lecture de l'en-tête des états depuis `parametres_systeme_local` —
/// **point unique**, exposé comme action injectable (directive du PO du
/// 14/10/2026).
///
/// Relue à CHAQUE édition, jamais mise en cache : un IFU saisi en Paramètres
/// figure sur le document suivant, sans redémarrer le poste. Un test surcharge
/// ce provider pour composer sans base.
///
/// Usage : `final entete = await ref.read(lireEnteteEtablissementProvider)();`
final lireEnteteEtablissementProvider =
    Provider<Future<EnteteEtablissement> Function()>(
      (ref) =>
          () async => EnteteEtablissement.depuisParametres(
            await ParametresDao(ref.read(baseLocaleProvider)).lireTout(),
          ),
    );
