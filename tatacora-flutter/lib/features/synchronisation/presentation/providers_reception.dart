import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../data/coherence_persistee.dart';
import '../data/journal_reception_dao.dart';
import '../domain/journal_reception.dart';
import 'providers_synchronisation.dart';

/// Les providers de la partie « Réception » de l'écran de synchronisation
/// (journal de réception, schéma v37, 26/10/2026).

final journalReceptionDaoProvider = Provider<JournalReceptionDao>(
  (ref) => JournalReceptionDao(ref.watch(baseLocaleProvider)),
);

/// Le filtre de la liste de réception : table, issue, dates de dernière
/// tentative.
final class FiltreReception {
  const FiltreReception({this.table, this.issue, this.du, this.au});

  final String? table;
  final IssueReception? issue;
  final DateTime? du;
  final DateTime? au;

  bool get vide => table == null && issue == null && du == null && au == null;

  FiltreReception avec({
    String? table,
    IssueReception? issue,
    DateTime? du,
    DateTime? au,
    bool effacerTable = false,
    bool effacerIssue = false,
    bool effacerDu = false,
    bool effacerAu = false,
  }) => FiltreReception(
    table: effacerTable ? null : (table ?? this.table),
    issue: effacerIssue ? null : (issue ?? this.issue),
    du: effacerDu ? null : (du ?? this.du),
    au: effacerAu ? null : (au ?? this.au),
  );

  @override
  bool operator ==(Object other) =>
      other is FiltreReception &&
      other.table == table &&
      other.issue == issue &&
      other.du == du &&
      other.au == au;

  @override
  int get hashCode => Object.hash(table, issue, du, au);
}

final filtreReceptionProvider =
    NotifierProvider<FiltreReceptionNotifier, FiltreReception>(
      FiltreReceptionNotifier.new,
    );

final class FiltreReceptionNotifier extends Notifier<FiltreReception> {
  @override
  FiltreReception build() => const FiltreReception();

  void poser(FiltreReception filtre) => state = filtre;
}

/// Abonne le provider [ref] au signal d'écriture du journal : il se relit
/// seul (`invalidateSelf`, comme `comptesFileSynchronisationProvider` — un
/// `Provider<void>` intermédiaire ne notifierait jamais : sa valeur ne change
/// pas). Le signal de tables de Drift, jamais une requête `.watch()` qui
/// laisse un minuteur au banc.
void _relireAChaqueEcriture(Ref ref) {
  final abonnement = ref
      .read(journalReceptionDaoProvider)
      .surveiller()
      .listen((_) => ref.invalidateSelf());
  ref.onDispose(abonnement.cancel);
}

final compteursReceptionProvider =
    FutureProvider.autoDispose<CompteursReception>((ref) {
      _relireAChaqueEcriture(ref);
      return ref.watch(journalReceptionDaoProvider).compter();
    });

final entreesReceptionProvider =
    FutureProvider.autoDispose<List<EntreeJournalReception>>((ref) {
      _relireAChaqueEcriture(ref);
      final f = ref.watch(filtreReceptionProvider);
      return ref
          .watch(journalReceptionDaoProvider)
          .lister(table: f.table, issue: f.issue, du: f.du, au: f.au);
    });

final tablesReceptionProvider = FutureProvider.autoDispose<List<String>>((ref) {
  _relireAChaqueEcriture(ref);
  return ref.watch(journalReceptionDaoProvider).tablesPresentes();
});

/// Ce que le serveur a annoncé et que ce poste a retenu : phase d'essais
/// (`X-Tatacora-Phase-Essais`), génération des données
/// (`X-Tatacora-Generation`), réinitialisation constatée.
final class AnnoncesServeur {
  const AnnoncesServeur({
    required this.phaseEssais,
    required this.generationRetenue,
    required this.reinitialiseLe,
  });

  final bool phaseEssais;
  final bool generationRetenue;
  final DateTime? reinitialiseLe;
}

final annoncesServeurProvider = FutureProvider.autoDispose<AnnoncesServeur>((
  ref,
) async {
  // Relu à chaque bilan (une réponse du serveur vient d'être lue).
  ref.watch(dernierBilanSynchronisationProvider);
  final dao = ref.watch(descenteCatalogueDaoProvider);
  return AnnoncesServeur(
    phaseEssais: await dao.phaseEssaisServeur(),
    generationRetenue: await dao.generation() != null,
    reinitialiseLe: await dao.reinitialisationServeur(),
  );
});

/// Le dernier contrôle de cohérence rangé.
final derniereCoherenceProvider = FutureProvider.autoDispose<CoherenceRangee?>((
  ref,
) async {
  final brut = await ref
      .watch(descenteCatalogueDaoProvider)
      .derniereCoherence();
  return brut == null ? null : coherenceDepuisJson(brut);
});

/// « Relancer » un élément : rejoue l'aligneur MAINTENANT (sans réseau).
final relancerElementProvider =
    Provider<Future<ResultatRelance> Function(String table, String id)>(
      (ref) =>
          (table, id) =>
              ref.read(descenteCatalogueProvider).relancerElement(table, id),
    );

/// « Relancer tout » : rejoue les éléments refusés et gardés (sans réseau),
/// lève le repli de la descente, puis lance un passage complet (envoi puis
/// descente depuis le curseur). Rend ce qui reste à traiter après la relance
/// locale.
final relancerToutProvider = Provider<Future<int> Function()>(
  (ref) => () async {
    final descente = ref.read(descenteCatalogueProvider);
    final restant = await descente.relancerTout();
    await descente.leverRepli();
    try {
      await ref.read(synchroniserDepuisEcranProvider)();
    } on Object {
      // Le moteur ne lève pas ; un moteur impossible à construire ne remonte
      // pas jusqu'à l'écran.
    }
    return restant;
  },
);
