import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../data/immobilisations_dao.dart';
import '../domain/immobilisations.dart';

/// Le seul écrivain de saisie des immobilisations, au nom du compte connecté.
final immobilisationsDaoProvider = Provider<ImmobilisationsDao>(
  (ref) => ImmobilisationsDao(
    ref.watch(baseLocaleProvider),
    auteur: ref.watch(sessionProvider)?.login,
  ),
);

/// Les immobilisations du poste, par code — relues après chaque création et à
/// chaque visite de l'onglet. Le plan et le tableau en sont CALCULÉS
/// (`tableauPourExercice`), jamais lus.
final immobilisationsProvider =
    FutureProvider.autoDispose<List<Immobilisation>>(
      (ref) => ref.watch(immobilisationsDaoProvider).toutes(),
    );
