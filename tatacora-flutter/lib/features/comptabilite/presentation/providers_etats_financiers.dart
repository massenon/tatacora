import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../synchronisation/domain/operation_sync.dart';
import '../../synchronisation/presentation/providers_synchronisation.dart';
import '../../../core/di/providers.dart';
import '../data/ecritures_serveur_dao.dart';
import '../domain/etats_financiers.dart';
import 'providers_comptabilite.dart';

/// Ce que lisent le compte de résultat et le bilan du poste : les écritures
/// VALIDÉES reçues du serveur, par année, et le statut de chaque exercice.
/// Relu à chaque visite, aucun cache (LECTURE seule).
final donneesEtatsFinanciersProvider = FutureProvider.autoDispose<DonneesEtats>(
  (ref) async {
    final dao = ref.watch(comptabiliteDaoProvider);
    final miroir = EcrituresServeurDao(ref.watch(baseLocaleProvider));
    final exercices = await dao.exercices();
    final plan = <String, CompteDeReport>{};
    for (final numero in const ['131', '139']) {
      final c = await dao.compteParNumero(numero);
      if (c != null) {
        plan[numero] = CompteDeReport(libelle: c.libelle, classe: c.classe);
      }
    }
    return DonneesEtats(
      ecrituresParAnnee: {
        for (final e in exercices) e.annee: await miroir.deLAnnee(e.annee),
      },
      statutParAnnee: {for (final e in exercices) e.annee: e.statut},
      plan: plan,
    );
  },
);

/// D'où viennent les chiffres, pour le dire sous les états : ce que ce poste
/// a reçu du serveur, et ce qu'il n'a pas encore envoyé (ces opérations n'ont
/// pas encore leur pièce au serveur, donc pas leur écriture ici).
final class ProvenanceEtatsFinanciers {
  const ProvenanceEtatsFinanciers({
    required this.reception,
    required this.enAttenteDEnvoi,
  });

  final ReceptionEcrituresServeur reception;
  final int enAttenteDEnvoi;
}

final provenanceEtatsFinanciersProvider =
    FutureProvider.autoDispose<ProvenanceEtatsFinanciers>((ref) async {
      final comptes = await ref
          .watch(operationsSyncDaoProvider)
          .compteParStatut();
      return ProvenanceEtatsFinanciers(
        reception: await EcrituresServeurDao(
          ref.watch(baseLocaleProvider),
        ).reception(),
        enAttenteDEnvoi:
            (comptes[StatutOperationSync.enAttente] ?? 0) +
            (comptes[StatutOperationSync.enCours] ?? 0),
      );
    });
