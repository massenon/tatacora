import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/entities/comptabilite.dart';
import 'providers_comptabilite.dart';

/// Ce que le hub Comptabilité lit du moteur du poste — relu à chaque visite,
/// aucun cache (lot D, 14/10/2026, D417). LECTURE seule : `MoteurComptable`
/// reste le seul auteur des écritures.
final class DonneesComptabilite {
  const DonneesComptabilite({
    required this.exercices,
    required this.journaux,
    required this.centres,
    required this.ecritures,
    required this.comptes,
    required this.exerciceOuvert,
  });

  final List<ExerciceComptable> exercices;
  final List<JournalComptable> journaux;
  final List<CentreDeCout> centres;
  final List<EcritureComptable> ecritures;

  /// Les comptes MOUVEMENTÉS, par identifiant — le plan entier (1 332
  /// comptes) n'est pas relu pour afficher quelques lignes.
  final Map<String, CompteDuPlan> comptes;

  /// L'exercice ouvert le plus récent — le choix par défaut du sélecteur.
  final ExerciceComptable? exerciceOuvert;
}

final donneesComptabiliteProvider =
    FutureProvider.autoDispose<DonneesComptabilite>((ref) async {
      final dao = ref.watch(comptabiliteDaoProvider);
      final ecritures = await dao.toutesLesEcritures();
      final comptes = <String, CompteDuPlan>{};
      for (final id in {for (final e in ecritures) e.compteId}) {
        final c = await dao.compteParId(id);
        if (c != null) comptes[id] = c;
      }
      return DonneesComptabilite(
        exercices: await dao.exercices(),
        journaux: await dao.journaux(),
        centres: await dao.centres(),
        ecritures: ecritures,
        comptes: comptes,
        exerciceOuvert: await dao.exerciceOuvertLePlusRecent(),
      );
    });
