/// Providers de l'écran « Congés & Plannings » (M13) — Riverpod exclusivement.
///
/// Vue Blade maîtresse (PA-183) : pwa/rh/conges-plannings.blade.php
///
/// Les écrans ne voient ni DAO ni table : ils lisent des entités. Le jour, le
/// service et le statut filtrés sont des providers, un par contrôle de la vue.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/rbac/garde_acces.dart';
import '../data/conges_plannings_dao.dart';
import '../domain/entities/conge_planning.dart';

final congesPlanningsDaoProvider = Provider<CongesPlanningsDao>(
  (ref) => CongesPlanningsDao(ref.watch(baseLocaleProvider)),
);

/// Écrire sur M13 : planifier, demander, décider. Premier niveau du RBAC
/// seulement — il évite de proposer ce qui serait refusé.
final peutEcrireCongesPlanningsProvider = Provider<bool>(
  (ref) => ref.watch(droitsProvider).peutEcrire(ModuleTatacora.m13Rh),
);

/// Les deux onglets, dans l'ordre de la vue — « Plannings » par défaut.
enum OngletCongesPlannings {
  plannings('plannings', 'Plannings'),
  conges('conges', 'Congés');

  const OngletCongesPlannings(this.cle, this.libelle);

  final String cle;
  final String libelle;
}

final ongletCongesPlanningsProvider =
    NotifierProvider<_OngletNotifier, OngletCongesPlannings>(
      _OngletNotifier.new,
    );

/// Le jour des plannings affichés — aujourd'hui par défaut (`jour` vide à la
/// vue).
final jourPlanningsProvider = NotifierProvider<_JourNotifier, DateTime>(
  _JourNotifier.new,
);

/// Le service filtré ; `null` = « Tous les services ».
final servicePlanningsProvider = NotifierProvider<_ServiceNotifier, String?>(
  _ServiceNotifier.new,
);

/// Le statut filtré ; `null` = « Tous les statuts ».
final statutCongesProvider = NotifierProvider<_StatutNotifier, StatutConge?>(
  _StatutNotifier.new,
);

/// Le refus affiché SOUS la ligne d'une demande (`@error('conge-<id>')`).
final refusCongeProvider =
    NotifierProvider<_RefusNotifier, Map<String, String>>(_RefusNotifier.new);

final creneauxProvider = FutureProvider<List<CreneauPlanning>>(
  (ref) => ref
      .watch(congesPlanningsDaoProvider)
      .creneaux(
        jour: ref.watch(jourPlanningsProvider),
        serviceId: ref.watch(servicePlanningsProvider),
      ),
);

final demandesCongeProvider = FutureProvider<List<DemandeConge>>(
  (ref) => ref
      .watch(congesPlanningsDaoProvider)
      .conges(statut: ref.watch(statutCongesProvider)),
);

/// Combien d'employés sont en congé VALIDÉ aujourd'hui.
final enCongeAujourdhuiProvider = FutureProvider<int>((ref) {
  final n = DateTime.now();
  return ref
      .watch(congesPlanningsDaoProvider)
      .enCongeLe(DateTime(n.year, n.month, n.day));
});

final employesEnPosteProvider = FutureProvider<List<EmployePlanifiable>>(
  (ref) => ref.watch(congesPlanningsDaoProvider).employesEnPoste(),
);

final servicesRhProvider = FutureProvider<List<({String id, String libelle})>>(
  (ref) => ref.watch(congesPlanningsDaoProvider).services(),
);

/// Recharge les listes après une écriture.
void rechargerCongesPlannings(WidgetRef ref) {
  ref
    ..invalidate(creneauxProvider)
    ..invalidate(demandesCongeProvider)
    ..invalidate(enCongeAujourdhuiProvider)
    ..invalidate(employesEnPosteProvider);
}

final class _OngletNotifier extends Notifier<OngletCongesPlannings> {
  @override
  OngletCongesPlannings build() => OngletCongesPlannings.plannings;

  void definir(OngletCongesPlannings valeur) => state = valeur;
}

final class _JourNotifier extends Notifier<DateTime> {
  @override
  DateTime build() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  void definir(DateTime valeur) =>
      state = DateTime(valeur.year, valeur.month, valeur.day);
}

final class _ServiceNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void definir(String? valeur) => state = valeur;
}

final class _StatutNotifier extends Notifier<StatutConge?> {
  @override
  StatutConge? build() => null;

  void definir(StatutConge? valeur) => state = valeur;
}

final class _RefusNotifier extends Notifier<Map<String, String>> {
  @override
  Map<String, String> build() => const {};

  void poser(String congeId, String message) =>
      state = {...state, congeId: message};

  void effacer(String congeId) => state = {...state}..remove(congeId);
}
