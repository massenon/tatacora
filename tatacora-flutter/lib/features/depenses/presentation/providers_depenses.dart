/// Les providers de M10 — Dépense courante.
///
/// ## Tout vient de la base LOCALE, et rien ne part
///
/// Aucun `Dio`, aucun client d'API : cet écran n'a pas de branche « si
/// connecté ». C'est l'inverse de M4, M6, M7, M8, M11 et Paramètres, qui
/// exigent le réseau parce que leurs données ne sont pas répliquées. Ici, la
/// dépense EST sur le poste — et elle y reste : `depenses` n'est à aucun
/// registre synchronisable.
///
/// ## Aucun `autoDispose`
///
/// Là encore, l'inverse de M8. Quitter un écran en ligne doit **oublier** la
/// réponse, faute de copie locale à laquelle retomber. Ici la copie locale est
/// la seule vérité : la relire coûte une requête SQLite, et la garder n'affiche
/// jamais « les chiffres d'hier ».
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/di/providers.dart';
import '../../comptabilite/domain/entities/comptabilite.dart';
import '../../comptabilite/domain/refus_comptable.dart';
import '../../comptabilite/presentation/providers_comptabilite.dart';
import '../data/depense_dao.dart';
import '../domain/categories_depense.dart';
import '../domain/entities/depense.dart';
import '../domain/filtre_depenses.dart';
import '../domain/repositories/depenses_repository.dart';
import '../impression/etat_depenses.dart';

/// Le dépôt des dépenses — **l'interface**, jamais le DAO.
///
/// C'est ce qui permet à un test de widget de monter l'écran sur un dépôt en
/// mémoire, et c'est surtout ce qui garantit qu'aucun écran ne sait qu'une base
/// existe.
///
/// ## Le moteur arrive par un RÉSOLVEUR
///
/// `moteurComptableProvider` attend l'installation du référentiel ; le dépôt le
/// demande à chaque écriture (jamais à la construction), si bien qu'une dépense
/// n'est jamais passée sur un plan vide. Sans lui, une dépense ne
/// s'enregistrerait pas : elle ne s'enregistre jamais sans sa pièce comptable.
final depotDepensesProvider = Provider<DepensesRepository>(
  (ref) => DepenseDao(
    ref.watch(baseLocaleProvider),
    moteur: () => ref.read(moteurComptableProvider.future),
  ),
);

/// Les sept centres de coût, dans l'ORDRE DE LA VUE : alphabétique sans tenir
/// compte de la casse (`orderBy('libelle')` sous MySQL, collation insensible à
/// la casse — « Restaurant » avant « RH »). SQLite trie en binaire (« RH » avant
/// « Restaurant ») : l'ordre est refait ici plutôt que de dépendre du moteur.
final centresDeCoutProvider = FutureProvider<List<CentreDeCout>>((ref) async {
  await ref.watch(moteurComptableProvider.future);
  final centres = await ref.watch(comptabiliteDaoProvider).centres();
  return [
    ...centres,
  ]..sort((a, b) => a.libelle.toLowerCase().compareTo(b.libelle.toLowerCase()));
});

/// Les comptes de charge PROPOSÉS à la saisie : classe 6, quatre chiffres, lus
/// du plan installé (`MoteurComptable.comptesDeCharge`) — jamais une liste
/// écrite dans l'écran.
final comptesDeChargeProvider = FutureProvider<List<CompteDuPlan>>((ref) async {
  final moteur = await ref.watch(moteurComptableProvider.future);
  return moteur.comptesDeCharge();
});

/// Les libellés des comptes pour la colonne « Charge (SYSCOHADA) » et l'export :
/// le plan d'abord, l'ancien registre à six chiffres pour NOMMER une ligne déjà
/// saisie ([LibellesDesComptes]).
final libellesComptesProvider = Provider<LibellesDesComptes>((ref) {
  final comptes = ref.watch(comptesDeChargeProvider).value ?? const [];
  return LibellesDesComptes({for (final c in comptes) c.numero: c.libelle});
});

/// Le registre entier, tel qu'il est en base.
final depensesProvider = FutureProvider<List<Depense>>(
  (ref) => ref.watch(depotDepensesProvider).depenses(),
);

/// Les cinq filtres de la barre du maître.
final filtreDepensesProvider =
    NotifierProvider<FiltreDepensesNotifier, FiltreDepenses>(
      FiltreDepensesNotifier.new,
    );

final class FiltreDepensesNotifier extends Notifier<FiltreDepenses> {
  @override
  FiltreDepenses build() => const FiltreDepenses();

  void definirTerme(String valeur) => state = state.avecTerme(valeur);

  void definirDu(DateTime? valeur) => state = state.avecDu(valeur);

  void definirAu(DateTime? valeur) => state = state.avecAu(valeur);

  void definirTresorerie(TresorerieDepense? valeur) =>
      state = state.avecTresorerie(valeur);

  void definirFamille(FamilleDepense? valeur) =>
      state = state.avecFamille(valeur);

  /// « Réinitialiser » — le maître en fait un LIEN, pas une action protégée :
  /// vider un filtre est une lecture, et l'exiger derrière un droit d'écriture
  /// empêcherait un profil en consultation de revenir à la liste entière.
  void reinitialiser() => state = const FiltreDepenses();
}

/// La liste **telle que l'écran l'affiche**.
///
/// C'est elle que les six indicateurs somment et que l'export emporte : une
/// seconde source pour l'un des trois les ferait diverger (PA-119, PA-121).
final depensesFiltreesProvider = FutureProvider<List<Depense>>((ref) async {
  final toutes = await ref.watch(depensesProvider.future);
  return filtrerDepenses(
    toutes,
    ref.watch(filtreDepensesProvider),
    libelles: ref.watch(libellesComptesProvider),
  );
});

/// La bande d'indicateurs est-elle dépliée ?
///
/// **Dépliée par défaut** : un écran qui s'ouvre vide se lit comme un écran
/// cassé — c'est le motif de la vue, repris tel quel.
///
/// ⚠ L'état n'est PAS retenu d'une session à l'autre, là où la vue le garde en
/// `localStorage`. Aucun magasin de préférences n'est embarqué sur ce client,
/// et en ajouter un pour cette seule bascule est un choix de dépendance qui
/// n'est pas de ce lot. L'écart est nommé, pas masqué.
final kpisDepliesProvider = NotifierProvider<KpisDepliesNotifier, bool>(
  KpisDepliesNotifier.new,
);

final class KpisDepliesNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void basculer() => state = !state;
}

/// Le bandeau vert qui suit un enregistrement — « Dépense de X enregistrée. ».
final messageSuccesDepenseProvider =
    NotifierProvider<MessageSuccesNotifier, String?>(MessageSuccesNotifier.new);

final class MessageSuccesNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void definir(String message) => state = message;

  void effacer() => state = null;
}

/// L'export tableur — rend le **chemin** du fichier écrit.
///
/// Exposé comme action injectable, jamais appelé depuis un widget : un test de
/// widget n'a pas de greffon natif, et il doit exister un seul endroit où un
/// fichier est écrit. Un export silencieux est un export que personne ne
/// retrouve — l'écran affiche le chemin rendu ici.
final exporterDepensesProvider =
    Provider<Future<String> Function(EtatDepenses)>(
      (ref) => (etat) async {
        final dossier = await getApplicationDocumentsDirectory();
        final m = DateTime.now();
        final horodatage =
            '${m.year}'
            '${m.month.toString().padLeft(2, '0')}'
            '${m.day.toString().padLeft(2, '0')}-'
            '${m.hour.toString().padLeft(2, '0')}'
            '${m.minute.toString().padLeft(2, '0')}'
            '${m.second.toString().padLeft(2, '0')}';
        final fichier = File(
          p.join(
            dossier.path,
            '${EtatDepenses.prefixeFichier}-$horodatage.csv',
          ),
        );
        await fichier.writeAsBytes(etat.csvOctets());
        return fichier.path;
      },
    );

/// La raison du dernier rattrapage refusé, affichée en bandeau rouge au-dessus
/// du tableau (le `@error('rattrapage')` de la vue, l.107-111). Effacée au
/// prochain geste.
final refusRattrapageDepenseProvider =
    NotifierProvider<RefusRattrapageNotifier, String?>(
      RefusRattrapageNotifier.new,
    );

final class RefusRattrapageNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void definir(String message) => state = message;

  void effacer() => state = null;
}

/// Le centre de coût choisi au bandeau de rattrapage (`$centreRattrapage` du
/// composant, `wire:model` du `<select>`, vue l.126-131).
///
/// **Chaîne vide = « Choisir un centre »**, qui est l'état de départ : la
/// dépense ne mémorise aucun centre, donc rien ne pré-remplit le choix. Le geste
/// « Comptabiliser » le passe TEL QUEL au dépôt, vide compris — c'est le moteur
/// qui refuse (RG-12), pas l'écran, qui ne fabrique donc aucune phrase de refus.
///
/// `autoDispose`, parce que la vie du composant Livewire est celle de la page :
/// quitter l'écran remet le choix à « Choisir un centre ». `EcranDepenses` y
/// reste abonné tant qu'il est monté, si bien que le rechargement de la liste
/// (le bandeau disparaît un instant) n'efface pas le choix de l'opérateur.
final centreRattrapageProvider =
    NotifierProvider.autoDispose<CentreRattrapageNotifier, String>(
      CentreRattrapageNotifier.new,
    );

final class CentreRattrapageNotifier extends Notifier<String> {
  @override
  String build() => '';

  void choisir(String centreId) => state = centreId;
}

/// Le geste « Comptabiliser » d'une dépense sans pièce (`comptabiliserDepense`
/// de la vue, `DepenseService::comptabiliser`).
///
/// Explicite : il n'est atteint que par le bouton de la ligne. Succès, le
/// bandeau vert dit « Dépense {numéro de pièce} comptabilisée. » — la vue écrit
/// le numéro `DEP-…` de la dépense, que ce poste n'alloue pas (voir
/// `tables/depenses_tables.dart`) ; c'est le numéro de PIÈCE qui le remplace.
/// Refus, le bandeau rouge dit la phrase du moteur (celle du serveur), la raison
/// est consignée sur la dépense, et RIEN n'est écrit.
Future<void> comptabiliserLaDepense(WidgetRef ref, Depense depense) async {
  final refus = ref.read(refusRattrapageDepenseProvider.notifier)..effacer();
  final succes = ref.read(messageSuccesDepenseProvider.notifier)..effacer();
  try {
    final faite = await ref
        .read(depotDepensesProvider)
        .comptabiliser(
          depense.id,
          auteurId: ref.read(sessionProvider)?.utilisateurId ?? '',
          // Le centre du bandeau, obligatoire (10/10/2026) : lu AU CLIC, jamais
          // mémorisé sur la dépense.
          centreId: ref.read(centreRattrapageProvider),
        );
    succes.definir('Dépense ${faite.numeroPiece ?? ''} comptabilisée.');
  } on RefusComptable catch (e) {
    refus.definir(e.message);
  } on RefusDepense catch (e) {
    refus.definir(e.message);
  } finally {
    // La liste lit la base : la pastille, l'indicateur et la raison consignée
    // doivent refléter ce qui vient d'être écrit — ou refusé.
    ref.invalidate(depensesProvider);
  }
}
