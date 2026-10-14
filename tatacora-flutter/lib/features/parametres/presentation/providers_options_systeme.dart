import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/di/providers.dart';
import '../../../core/rbac/garde_acces.dart';
import '../../../core/rbac/regle_archivage.dart';
import '../data/parametres_dao.dart';
import '../domain/options_systeme.dart';

/// La valeur EFFECTIVE de la bascule « Suppression d'un enregistrement »
/// (`activation_suppression`) : la valeur saisie en Paramètres, ou son défaut
/// FERMÉ quand rien n'est saisi (`OptionsSysteme.suppressionActive`).
///
/// ## Un vrai lecteur, relu à chaque ouverture d'écran
///
/// La bascule se saisit depuis longtemps (Paramètres, v11) ; jusqu'au 12/10/2026
/// RIEN ne la lisait : un Administrateur l'ouvrait, et aucun bouton ne changeait.
/// Elle est lue ici, depuis `parametres_systeme_local`, sans cache durable
/// (`autoDispose`) : refermée en Paramètres, elle l'est à l'ouverture suivante de
/// l'écran qui la lit. Pendant le chargement la valeur est « fermée » — le défaut
/// du serveur —, jamais « ouverte » : un bouton destructeur n'apparaît pas par
/// défaut d'information.
final suppressionActiveProvider = FutureProvider.autoDispose<bool>(
  (ref) => lireSuppressionActive(ref.watch(baseLocaleProvider)),
);

/// LA lecture de la bascule, depuis la base — le lecteur DÉCLARÉ au registre
/// (`SpecParametre.lecteur`). Le provider ci-dessus et la règle d'archivage des
/// fournisseurs relue à chaque geste (`achatsApiProvider`) passent tous deux
/// par elle : jusqu'au 12/10/2026 le second relisait la clé lui-même, et la
/// bascule avait deux lecteurs quand le registre en nommait un (R-C, D284).
Future<bool> lireSuppressionActive(AppDatabase base) async {
  final valeurs = await ParametresDao(base).lireTout();
  return OptionsSysteme.suppressionActive(
    valeurs[OptionsSysteme.cleSuppression],
  );
}

/// La règle d'archivage (`regle_archivage.dart`, UN seul auteur) appliquée à la
/// session courante, pour le module [module]. Les écrans reçoivent ce booléen :
/// ils ne rejouent jamais le calcul.
final peutArchiverProvider = Provider.autoDispose.family<bool, ModuleTatacora>((
  ref,
  module,
) {
  return peutArchiver(
    droits: ref.watch(droitsProvider),
    module: module,
    role: ref.watch(sessionProvider)?.role,
    suppressionActive: ref.watch(suppressionActiveProvider).value ?? false,
  );
});
