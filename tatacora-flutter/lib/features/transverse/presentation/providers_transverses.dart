import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../synchronisation/presentation/providers_synchronisation.dart';
import '../data/comptes_utilisateurs_dao.dart';
import '../data/lecteur_comptes_poste.dart';
import '../data/roles_dao.dart';
import '../domain/comptes_utilisateurs.dart';
import '../domain/journal_poste.dart';
import '../domain/roles_du_poste.dart';

/// Le lecteur des comptes du poste (lot D, 14/10/2026).
final lecteurComptesPosteProvider = Provider<LecteurComptesPoste>(
  (ref) => LecteurComptesPoste(ref.watch(baseLocaleProvider)),
);

/// Les comptes du poste — relus à chaque visite (aucun cache).
final comptesDuPosteProvider = FutureProvider.autoDispose<List<CompteDuPoste>>(
  (ref) => ref.watch(lecteurComptesPosteProvider).comptes(),
);

/// Le seul écrivain du référentiel des rôles (schéma v24, 14/10/2026).
final rolesDaoProvider = Provider<RolesDao>(
  (ref) => RolesDao(ref.watch(baseLocaleProvider)),
);

/// Ce que l'écran Rôles & Permissions affiche : les rôles et le total des
/// comptes.
typedef MatriceDuPoste = ({List<RoleDuPoste> roles, int totalComptes});

/// Les rôles du poste — relus à chaque visite (aucun cache). Pose d'abord les
/// rôles du socle qui MANQUENT (`RolesDao.installerSocle`, idempotent, ne
/// réécrit jamais un rôle présent) : c'est l'appelant de l'installation, comme
/// `referentielComptableProvider` l'est du plan comptable (piège 1).
final matriceDuPosteProvider = FutureProvider.autoDispose<MatriceDuPoste>((
  ref,
) async {
  final dao = ref.watch(rolesDaoProvider);
  await dao.installerSocle();
  return (roles: await dao.roles(), totalComptes: await dao.totalComptes());
});

/// L'état du compte de la session — `null` : inconnu.
final compteSessionActifProvider = FutureProvider.autoDispose<bool?>((ref) {
  final session = ref.watch(sessionProvider);
  if (session == null) return Future.value();
  return ref.watch(lecteurComptesPosteProvider).estActif(session.utilisateurId);
});

/// L'écrivain des comptes du poste (Lot J2, 14/10/2026).
final comptesUtilisateursDaoProvider = Provider<ComptesUtilisateursDao>(
  (ref) => ComptesUtilisateursDao(ref.watch(baseLocaleProvider)),
);

/// Ce que l'écran « Comptes utilisateurs » affiche : les comptes et les rôles
/// proposés à la création.
typedef ComptesEtRoles = ({
  List<CompteUtilisateur> comptes,
  List<RoleDuPoste> roles,
});

/// Les comptes et les rôles — relus à chaque visite (aucun cache). Pose
/// d'abord les rôles du socle qui MANQUENT (`RolesDao.installerSocle`) : sur
/// un poste où « Rôles & Permissions » n'a jamais été ouvert, `roles_local`
/// est vide, et la liste des rôles le serait aussi.
final comptesEtRolesProvider = FutureProvider.autoDispose<ComptesEtRoles>((
  ref,
) async {
  final roles = ref.watch(rolesDaoProvider);
  await roles.installerSocle();
  return (
    comptes: await ref.watch(comptesUtilisateursDaoProvider).comptes(),
    roles: await roles.roles(),
  );
});

/// Le Journal d'Audit de ce poste : la file d'envoi, relue à chaque visite
/// (aucun cache). Lecture seule, par `OperationsSyncDao` — le seul qui lise la
/// file.
final journalDuPosteProvider =
    FutureProvider.autoDispose<List<EntreeJournalPoste>>((ref) async {
      final operations = await ref
          .watch(operationsSyncDaoProvider)
          .operations();
      return [
        for (final o in operations) EntreeJournalPoste.depuisOperation(o),
      ];
    });
