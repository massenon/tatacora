import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../data/lecteur_comptes_poste.dart';
import '../data/roles_dao.dart';
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
