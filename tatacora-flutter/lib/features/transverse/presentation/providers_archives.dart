import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/rbac/garde_acces.dart';
import '../../../core/rbac/regle_archivage.dart' show estSuperAdmin;
import '../../hebergement/presentation/providers_hebergement.dart'
    show parcDaoProvider;
import '../../vehicules/presentation/providers_vehicules.dart'
    show vehiculeDaoProvider;
import '../data/archives_poste.dart';
import '../domain/registre_archives.dart';

/// Le registre des archives et son geste « Restaurer » (`ImportExport::
/// restaurerArchive`).
final archivesPosteProvider = Provider<ArchivesPoste>(
  (ref) => ArchivesPoste(
    ref.watch(baseLocaleProvider),
    parc: ref.watch(parcDaoProvider),
    vehicules: ref.watch(vehiculeDaoProvider),
  ),
);

/// Les deux listes du registre, relues à chaque ouverture de l'onglet (jamais
/// gardées : un registre périmé offrirait de restaurer ce qui l'est déjà).
final registreArchivesProvider = FutureProvider.autoDispose<RegistreArchives>(
  (ref) => ref.watch(archivesPosteProvider).registre(),
);

/// `restaurerArchive` : le niveau `C` du module (Paramètres, `MODULE` du
/// composant) est relu à l'instant du geste, puis l'élément est remis en place
/// par l'écrivain de son module. Rend le libellé de l'élément.
final restaurerArchiveProvider =
    Provider<Future<String> Function(TypeArchive, String)>(
      (ref) => (type, id) async {
        if (!ref.read(droitsProvider).peutEcrire(ModuleTatacora.parametres)) {
          throw const RefusArchive(MessagesArchives.droitManquant);
        }
        final libelle = await ref
            .read(archivesPosteProvider)
            .restaurer(type, id);
        ref.invalidate(registreArchivesProvider);
        return libelle;
      },
    );

/// `purgerArchive` : le rôle `super_admin` (`exigerSuperAdmin`) PUIS le niveau
/// `C` du module Paramètres (`exigerEcriture`) sont relus à l'instant du geste,
/// dans l'ordre de l'écran ; l'élément est alors purgé par l'écrivain de son
/// module, qui enfile la `suppression`. Rend le libellé de l'élément.
final purgerArchiveProvider =
    Provider<Future<String> Function(TypeArchive, String)>(
      (ref) => (type, id) async {
        if (!estSuperAdmin(ref.read(sessionProvider)?.role)) {
          throw const RefusArchive(MessagesArchives.superAdminRequis);
        }
        if (!ref.read(droitsProvider).peutEcrire(ModuleTatacora.parametres)) {
          throw const RefusArchive(MessagesArchives.droitManquant);
        }
        final libelle = await ref.read(archivesPosteProvider).purger(type, id);
        ref.invalidate(registreArchivesProvider);
        return libelle;
      },
    );
