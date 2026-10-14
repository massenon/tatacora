import '../../../core/database/app_database.dart';
import '../../comptabilite/data/comptabilite_dao.dart';
import '../domain/analytique_locale.dart';
import '../domain/entities/pilotage.dart';

/// La source des lectures M10 CONSOLIDÉES de l'onglet « Pilotage consolidé » :
/// l'exercice, les indicateurs comptables (`IndicateursComptablesService` du
/// serveur : balance, compte de résultat, bilan) et l'analytique
/// (`AnalytiqueService`). Rien d'autre — le chiffre d'affaires encaissé et la
/// trésorerie de caisse des cartes 1 et 3 sont des indicateurs M11, lus de la
/// bande (`TableauDeBordLocal`), jamais d'ici (R1 du contrôle du 12/10/2026).
///
/// ## Il ne conserve RIEN
///
/// Aucun cache, aucune écriture locale — même règle que la bande
/// d'indicateurs (PA-120) : garder la dernière réponse ferait afficher des
/// chiffres d'hier sous une page qui ne dit pas qu'ils datent.
///
/// ## ⚠ Ce que disait ce fichier, et qui est PÉRIMÉ (revu le 12/10/2026)
///
/// « Ce module n'a aucune table locale — sa donnée était calculée par le
/// serveur, jamais répliquée » (14/09/2026). Faux depuis D192 (10/10/2026) :
/// M10 a six tables sur ce poste (schéma v15), son moteur comptable
/// (`MoteurComptable`) y passe les pièces des dépenses courantes, des ventes,
/// des acomptes et remboursements de réservation, des encaissements de factures
/// et des règlements fournisseurs. Et le motif rendu à l'écran — la phrase
/// unique de `donneeNonDisponible` : « … calculée par le serveur … aucun chiffre
/// ne peut être affiché à la place » — envoyait l'exploitant vers un serveur qui
/// n'existe plus, pour une donnée dont les pièces sont ici.
///
/// ## Ce qui est vrai : l'issue « absente », avec sa raison datée
///
/// Ce qui manque n'est ni une table ni une liaison : c'est le CALCUL. Aucun
/// équivalent de la balance, du compte de résultat ni du bilan n'est porté sur
/// ce poste (les marges analytiques le sont depuis le 13/10/2026, voir
/// ci-dessous) ; et même porté, il lirait des écritures
/// auxquelles manquent la saisie manuelle des pièces du comptable (opérations
/// diverses, dont la paie — le serveur ne la comptabilise que par cette saisie,
/// `LivreDePaieService` n'en passe aucune) et les pièces antérieures au portage.
/// D'où [SourceAbsente] — « la donnée n'existe pas (encore) » — plutôt qu'un
/// refus, qui ferait chercher un droit manquant.
///
/// Les types de résultat et les entités sont CONSERVÉS : ils portent les
/// signatures que les écrans consomment, et ils redeviendront utiles le jour
/// où ces états seront calculés sur le poste.
///
/// ## Ce qui est calculé sur le poste depuis le 13/10/2026 (fin du Pilotage)
///
/// L'EXERCICE OUVERT (`exercices_local`, le plus récent — `Accueil::
/// margeParActivite` du serveur) et l'ANALYTIQUE par centre
/// (`analytique_locale.dart`, réplique de `AnalytiqueService`), lue sur les
/// écritures de M10 que `MoteurComptable` passe ici. Le compte de résultat, la
/// balance et le bilan (`indicateurs`) restent absents : rien ne les calcule
/// encore sur le poste.
final class PilotageApi {
  const PilotageApi({this.base});

  /// La base locale ; `null` (tests anciens) : tout est absent, comme avant.
  final AppDatabase? base;

  /// La raison unique, DATÉE — rendue sous « Résultat net », dans « À traiter »
  /// (alertes comptables non évaluées) et dans la carte « Comptabilité ». Une
  /// raison non datée vieillit sans que personne la rouvre (PA-107, PA-120,
  /// PA-144). ⚠ Les marges analytiques en sont SORTIES le 13/10/2026 : elles
  /// sont calculées sur le poste.
  static const String raisonAbsence =
      'le compte de résultat, la balance et le bilan ne sont pas calculés sur '
      'ce poste (constaté le 13/10/2026).';

  /// Sans exercice ouvert, rien n'est affirmé : la vue rend « Non consulté ».
  static const String raisonSansExercice =
      'aucun exercice comptable n’est ouvert sur ce poste.';

  /// L'exercice OUVERT le plus récent — `ExerciceComptable::query()->where(
  /// 'statut', 'ouvert')->orderByDesc('annee')->first()`.
  Future<SourcePilotage<ExercicePilotage>> exercice() async {
    final b = base;
    if (b == null) return const SourceAbsente<ExercicePilotage>(raisonAbsence);
    final e = await ComptabiliteDao(b).exerciceOuvertLePlusRecent();
    if (e == null) {
      return const SourceAbsente<ExercicePilotage>(raisonSansExercice);
    }
    return SourceRecue(ExercicePilotage(id: e.id, annee: e.annee));
  }

  Future<SourcePilotage<ComptaPilotage>> indicateurs(String exerciceId) async =>
      const SourceAbsente<ComptaPilotage>(raisonAbsence);

  /// Les marges par centre de l'exercice — `AnalytiqueService::
  /// genererPourExercice($id, ['brouillon', 'validee'])`.
  Future<SourcePilotage<AnalytiquePilotage>> analytique(
    String exerciceId,
  ) async {
    if (base == null) {
      return const SourceAbsente<AnalytiquePilotage>(raisonAbsence);
    }
    return SourceRecue(versAnalytiquePilotage(await marges(exerciceId)));
  }

  /// Les lignes du calcul, produits et charges compris (la confrontation au
  /// serveur les compare toutes). Base absente : aucune ligne.
  Future<List<MargeCentre>> marges(String exerciceId) async {
    final b = base;
    if (b == null) return const [];
    return margesParCentre([
      for (final a in await ComptabiliteDao(b).agregatsAnalytiques(exerciceId))
        AgregatAnalytique(
          centreId: a.centreId,
          centreLibelle: a.centreLibelle,
          classe: a.classe,
          debitCentimes: a.debitCentimes,
          creditCentimes: a.creditCentimes,
          nombreLignes: a.nombreLignes,
        ),
    ]);
  }
}
