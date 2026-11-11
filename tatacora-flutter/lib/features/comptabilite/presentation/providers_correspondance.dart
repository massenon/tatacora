import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/correspondance_comptes.dart';
import 'providers_comptabilite.dart';

/// Une ligne de l'écran « Correspondance des comptes » : le rôle, le compte
/// ACTUEL (le choisi, sinon le défaut), son intitulé au plan, et s'il a été
/// changé.
typedef LigneCorrespondance = ({
  RoleCompte role,
  String actuel,
  String? libelleActuel,
  bool personnalise,
});

/// La correspondance telle qu'elle est lue sur CE poste, à l'instant : les
/// quinze rôles, dans l'ordre du serveur. `autoDispose` : revenir sur l'écran
/// relit la base, il ne réaffiche pas ce qu'on avait vu.
///
/// Le référentiel comptable est installé au DÉMARRAGE (`main.dart`,
/// `referentielComptableProvider`), comme pour le plan du hub : cet écran ne
/// l'attend pas, il lit la base telle qu'elle est.
final correspondanceComptesProvider =
    FutureProvider.autoDispose<List<LigneCorrespondance>>((ref) async {
      final dao = ref.watch(comptabiliteDaoProvider);
      final lignes = <LigneCorrespondance>[];
      for (final role in RolesCorrespondance.roles) {
        final actuel = await dao.compteDuRole(role.code);
        final compte = await dao.compteParNumero(actuel);
        lignes.add((
          role: role,
          actuel: actuel,
          libelleActuel: compte?.libelle,
          personnalise: actuel != role.defaut,
        ));
      }
      return lignes;
    });
