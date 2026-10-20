/// L'EXERCICE CONSULTÉ du poste — le sélecteur d'exercice global de la barre
/// supérieure (`docs/SPEC_SELECTEUR_EXERCICE.md`, décisions du PO du
/// 20/10/2026). Réplique de `App\Pwa\Support\ExerciceConsulte` : UN choix,
/// gardé en mémoire pour la session (il revient au défaut à la reconnexion),
/// lu par tout écran qui suit le sélecteur.
///
/// ## Il ne déplace AUCUNE écriture (R4)
///
/// Il borne ce qui se LIT. Le moteur comptable range toujours une pièce dans
/// l'exercice de SA date : rien ici n'est lu par un chemin d'écriture.
///
/// ## La date de référence
///
/// « Ce mois », « exercice entier » se calculent à partir d'AUJOURD'HUI quand
/// l'exercice consulté le contient, de son DERNIER JOUR sinon — jamais un mois
/// hors de l'année consultée.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/entities/comptabilite.dart';
import 'providers_comptabilite.dart';

/// Les routes du poste qui SUIVENT le sélecteur — `ExerciceConsulte::ROUTES`.
const List<String> routesQuiSuiventLExercice = [
  '/comptabilite',
  '/tableau-de-bord',
  '/etats',
  '/depenses',
  '/facturation',
  '/fournisseurs',
  '/approvisionnement',
  '/paie',
];

bool routeSuitLExercice(String route) => routesQuiSuiventLExercice.any(
  (r) => route == r || route.startsWith('$r/') || route.startsWith('$r?'),
);

/// L'exercice CHOISI (`null` : le défaut s'applique).
final exerciceChoisiProvider = NotifierProvider<_ExerciceChoisi, String?>(
  _ExerciceChoisi.new,
);

final class _ExerciceChoisi extends Notifier<String?> {
  @override
  String? build() => null;

  void choisir(String? id) => state = id;

  void revenir() => state = null;
}

/// Les exercices du poste, du plus récent au plus ancien.
final exercicesDuPosteProvider = FutureProvider<List<ExerciceComptable>>((
  ref,
) async {
  final liste = await ref.watch(comptabiliteDaoProvider).exercices();
  return [...liste]..sort((a, b) => b.annee.compareTo(a.annee));
});

/// L'exercice OUVERT le plus récent, à défaut le plus récent.
ExerciceComptable? exerciceParDefaut(List<ExerciceComptable> exercices) {
  final tries = [...exercices]..sort((a, b) => b.annee.compareTo(a.annee));
  return tries.where((e) => e.statut == StatutExercice.ouvert).firstOrNull ??
      tries.firstOrNull;
}

/// L'exercice consulté parmi [exercices] : le choisi s'il existe, sinon le
/// défaut.
ExerciceComptable? exerciceConsulteParmi(
  List<ExerciceComptable> exercices,
  String? choisi,
) =>
    exercices.where((e) => e.id == choisi).firstOrNull ??
    exerciceParDefaut(exercices);

final exerciceConsulteProvider = Provider<ExerciceComptable?>((ref) {
  final exercices = ref.watch(exercicesDuPosteProvider).value ?? const [];
  return exerciceConsulteParmi(exercices, ref.watch(exerciceChoisiProvider));
});

/// La date de référence : [maintenant] s'il tombe dans [exercice], son dernier
/// jour (à midi) sinon.
DateTime dateDeReference(ExerciceComptable? exercice, DateTime maintenant) {
  if (exercice == null) return maintenant;
  final debut = DateTime.tryParse(exercice.dateDebut);
  final fin = DateTime.tryParse(exercice.dateFin);
  if (debut == null || fin == null) return maintenant;
  if (maintenant.isBefore(debut)) {
    return DateTime(debut.year, debut.month, debut.day, 12);
  }
  if (!maintenant.isBefore(fin.add(const Duration(days: 1)))) {
    return DateTime(fin.year, fin.month, fin.day, 12);
  }
  return maintenant;
}

/// L'horloge des écrans qui suivent le sélecteur — `DateTime.now` tant que
/// l'exercice consulté contient aujourd'hui.
final horlogeExerciceConsulteProvider = Provider<DateTime Function()>((ref) {
  final exercice = ref.watch(exerciceConsulteProvider);
  return () => dateDeReference(exercice, DateTime.now());
});

/// Les bornes `[début, fin]` (dates ISO, INCLUSES) de l'exercice consulté.
({String debut, String fin})? bornesDeLExercice(ExerciceComptable? e) =>
    e == null ? null : (debut: e.dateDebut, fin: e.dateFin);

/// Une date ISO (`AAAA-MM-JJ…`) tombe-t-elle dans l'exercice ? `true` sans
/// exercice (rien à borner).
bool dansLExercice(ExerciceComptable? e, String dateIso) {
  if (e == null || dateIso.length < 10) return true;
  final jour = dateIso.substring(0, 10);
  return jour.compareTo(e.dateDebut) >= 0 && jour.compareTo(e.dateFin) <= 0;
}
