/// « Réinitialiser comme neuf » sur la base LOCALE du poste — réplique de
/// `ReinitialisationDonneesTestService` du serveur (demande du Product Owner
/// du 14/10/2026, lot E ; règle « le serveur fait foi, répliqué en local »).
///
/// ## Mêmes règles que le serveur
///
/// * **Environnement** : refus en build `production`
///   (`Environnement.actuel.estProduction`), comme `app()->isProduction()` —
///   SAUF quand ce poste a constaté que le SERVEUR a été réinitialisé
///   (19/10/2026, essais en production : génération des données, 409
///   `generation_perimee`). Le poste ne synchronise plus : sa remise à neuf
///   est alors le seul chemin, et la bascule locale n'est pas exigée (le
///   geste a été autorisé au serveur). Le rôle et « VIDER » le restent.
/// * **Bascule** `reinitialisation_seeders` (`parametres_systeme_local`), lue
///   par `OptionsSysteme.actif` : fermée par défaut, relue AU MOMENT D'AGIR.
/// * **Rôle** : administrateur ou super_admin (`rolesAdministration`).
/// * **Confirmation** : la saisie du mot « VIDER » — vérifiée par l'écran.
/// * **Une transaction** : tout est vidé, ou rien.
///
/// ## Ce qui est GARDÉ — liste FERMÉE ; toute table ajoutée demain est VIDÉE
///
/// Correspondance avec le serveur : `utilisateurs_local` (utilisateurs, rôles
/// et droits — `droits_json`), `parametres_systeme_local` et `taux_paie_local`
/// (paramètres), le parc (`categories_hebergement_local`,
/// `unites_hebergement_local`), les articles et leurs lieux
/// (`articles_local`, `points_stockage_local` — SANS mouvements : le stock se
/// rejoue des mouvements, il retombe à zéro), la fiche restaurant
/// (`menus_local`, `recettes_local`, `ingredients_recette_local`,
/// `plats_local`, `tables_local`), la carte du bar (`cartes_boisson_local`),
/// `vehicules_local`, `circuits_local`, le paramétrage comptable
/// (`exercices_local`, `journaux_local`, `centres_cout_local`,
/// `plan_comptable_local`), `services_rh_local`,
/// `modeles_notification_local` et la boîte d'envoi à l'éditeur
/// (`messages_editeur_local`, comme `messages_editeur` au serveur).
///
/// ## Un geste d'ADMINISTRATION, hors des gardes RG-11 — délibérément
///
/// Les quatre triggers de `declencheurs_comptables.dart` refusent toute
/// suppression d'une écriture, et c'est juste pour l'exploitation. Ici l'on
/// remet à neuf une base de démonstration : les triggers sont retirés DANS la
/// transaction, puis recréés par `creerDeclencheursComptables` dans la même
/// transaction (le DDL de SQLite est transactionnel : un échec les rend).
///
/// ## Ordre de vidage : les ENFANTS avant les PARENTS
///
/// `PRAGMA foreign_keys` reste ACTIF (il ne se change pas dans une
/// transaction) : l'ordre est un tri topologique sur `PRAGMA
/// foreign_key_list`. Les auto-références et les colonnes d'une table GARDÉE
/// qui pointent vers une table vidée sont remises à NULL si elles l'admettent
/// — sinon le geste est refusé avant toute écriture.
///
/// Écart avec le serveur, NOMMÉ : le poste ne produit aucune sauvegarde de sa
/// base (onglet « Sauvegardes ») ni aucun journal d'audit local ; la
/// réinitialisation n'a donc ni filet ni trace sur ce poste.
library;

import 'package:drift/drift.dart';

import '../../../core/config/environnement.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/declencheurs_comptables.dart';
import '../../../core/rbac/regle_archivage.dart';
import '../../parametres/data/parametres_dao.dart';
import '../../parametres/data/parametres_depot_local.dart';
import '../../parametres/domain/options_systeme.dart';
import '../../synchronisation/data/descente_catalogue_dao.dart';

/// Les tables que la réinitialisation NE TOUCHE PAS — voir l'entête.
const Set<String> tablesPreserveesLocales = {
  // Identité et réglages.
  'utilisateurs_local',
  // Les rôles et leur matrice (v24, D438) — `roles` / `permission_role`,
  // GARDÉS au serveur avec l'identité. Défaut corrigé en passe finale
  // (14/10/2026) : la table, née après la liste, tombait dans « vidé » par
  // défaut ; les rôles créés et les matrices amendées étaient perdus pendant
  // que les comptes gardaient leurs droits recopiés.
  'roles_local',
  'parametres_systeme_local',
  'taux_paie_local',
  // M1 — le parc (les chambres), sans leurs réservations.
  'categories_hebergement_local',
  'unites_hebergement_local',
  // M6 — les articles et leurs lieux, sans leurs mouvements.
  'articles_local',
  'points_stockage_local',
  // M4 — la fiche restaurant.
  'menus_local',
  'recettes_local',
  'ingredients_recette_local',
  'plats_local',
  'tables_local',
  // M5 — la carte du bar.
  'cartes_boisson_local',
  // M8 / M9 — véhicules et catalogue tourisme.
  'vehicules_local',
  'circuits_local',
  // M10 — le paramétrage comptable.
  'exercices_local',
  'journaux_local',
  'centres_cout_local',
  'plan_comptable_local',
  // M13 / M12 — référentiels sans donnée personnelle.
  'services_rh_local',
  'modeles_notification_local',
  // La boîte d'envoi à l'éditeur (v25) — `messages_editeur` est GARDÉE au
  // serveur (`TABLES_PRESERVEES`) : un message en attente ne se perd pas.
  'messages_editeur_local',
};

/// Les quatre triggers RG-11, retirés puis recréés dans la transaction.
const List<String> _declencheursRg11 = [
  'rg11_ecriture_validee_immuable',
  'rg11_brouillon_exercice_clos_maj',
  'rg11_exercice_clos_ajout',
  'rg11_ecriture_jamais_supprimee',
];

/// Les refus du geste, au mot près des clés serveur
/// (`pwa.import_export.reset_*`).
abstract final class RefusReinitialisation {
  static const String production =
      "Réinitialisation refusée : cet environnement est la Production. Cette action n'existe délibérément que pour développement et recette.";
  static const String bascule =
      'Réinitialisation refusée : la fonction est désactivée dans Paramètres › Activation & Sécurité.';
  static const String role =
      "Réinitialisation refusée : ce geste est réservé à l'Administrateur.";
  static String cycle(String tables) =>
      'Réinitialisation refusée : les tables $tables se référencent en boucle, aucun ordre de vidage ne respecte leurs clés étrangères.';
  static String referenceBloquante(String reference) =>
      'Réinitialisation refusée : la référence $reference relie une table conservée à une table vidée et ne peut pas être détachée.';
}

/// Un refus du geste — rien n'a été écrit.
final class ReinitialisationRefusee implements Exception {
  const ReinitialisationRefusee(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Le bilan d'une réinitialisation réussie.
typedef BilanReinitialisation = ({int tablesVidees, int lignesSupprimees});

typedef _Reference = ({
  String source,
  String colonne,
  String cible,
  bool nullable,
});

/// Le moteur de la réinitialisation locale.
class ReinitialisationLocale {
  ReinitialisationLocale(this._base, {Environnement? environnement})
    : _environnement = environnement ?? Environnement.actuel;

  final AppDatabase _base;
  final Environnement _environnement;

  /// `estAutorisee()` du serveur.
  bool get estAutorisee => !_environnement.estProduction;

  /// Le serveur a été réinitialisé depuis la dernière synchronisation de ce
  /// poste (19/10/2026) — la date, ou `null`.
  Future<DateTime?> reinitialisationServeur() =>
      DescenteCatalogueDao(_base).reinitialisationServeur();

  /// Le serveur annonce la phase d'essais en production (19/10/2026).
  Future<bool> phaseEssaisServeur() =>
      DescenteCatalogueDao(_base).phaseEssaisServeur();

  /// La bascule d'activation, relue depuis la base — le LECTEUR de la clé
  /// `reinitialisation_seeders` sur ce poste.
  Future<bool> estOuverte() async {
    final valeurs = await ParametresDao(_base).lireTout();
    return OptionsSysteme.actif(
      OptionsSysteme.cleReinitialisationSeeders,
      valeurs[OptionsSysteme.cleReinitialisationSeeders],
    );
  }

  /// `estPermisA()` du serveur.
  static bool estPermisA(String? role) =>
      rolesAdministration.contains(roleNormalise(role));

  /// Les tables de la base réelle, hors tables internes de SQLite.
  Future<List<String>> _tablesReelles() async {
    final lignes = await _base
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name NOT LIKE 'sqlite_%' ORDER BY name",
        )
        .get();
    return [for (final l in lignes) l.read<String>('name')];
  }

  /// « Ce qui sera vidé » — mesuré sur la base, jamais recopié.
  Future<List<String>> tablesEffacables() async => [
    for (final t in await _tablesReelles())
      if (!tablesPreserveesLocales.contains(t)) t,
  ];

  /// « Ce qui sera conservé » — les tables gardées EXISTANTES.
  Future<List<String>> tablesPreservees() async => [
    for (final t in await _tablesReelles())
      if (tablesPreserveesLocales.contains(t)) t,
  ];

  Future<List<_Reference>> _references(List<String> tables) async {
    final references = <_Reference>[];
    for (final table in tables) {
      final colonnesNonNulles = {
        for (final c
            in await _base.customSelect('PRAGMA table_info("$table")').get())
          if (c.read<int>('notnull') == 1) c.read<String>('name'),
      };
      final cles = await _base
          .customSelect('PRAGMA foreign_key_list("$table")')
          .get();
      for (final cle in cles) {
        final colonne = cle.read<String>('from');
        references.add((
          source: table,
          colonne: colonne,
          cible: cle.read<String>('table'),
          nullable: !colonnesNonNulles.contains(colonne),
        ));
      }
    }
    return references;
  }

  /// L'ordre de vidage — enfants avant parents.
  Future<List<String>> ordreDeVidage() async {
    final effacables = await tablesEffacables();
    return _trier(effacables, await _references(effacables));
  }

  static List<String> _trier(List<String> effacables, List<_Reference> refs) {
    final index = effacables.toSet();
    final referencesPar = {for (final t in effacables) t: <String>{}};
    for (final r in refs) {
      if (r.source != r.cible &&
          index.contains(r.source) &&
          index.contains(r.cible)) {
        referencesPar[r.source]!.add(r.cible);
      }
    }
    var restantes = [...effacables];
    final ordre = <String>[];
    while (restantes.isNotEmpty) {
      final retirees = [
        for (final t in restantes)
          if (!restantes.any((a) => a != t && referencesPar[a]!.contains(t))) t,
      ];
      if (retirees.isEmpty) {
        throw ReinitialisationRefusee(
          RefusReinitialisation.cycle(restantes.join(', ')),
        );
      }
      ordre.addAll(retirees);
      restantes = [
        for (final t in restantes)
          if (!retirees.contains(t)) t,
      ];
    }
    return ordre;
  }

  /// Vide la base comme neuve. Lève [ReinitialisationRefusee] — et n'écrit
  /// rien — sur tout refus.
  Future<BilanReinitialisation> executer({required String? role}) async {
    final serveurReinitialise = await reinitialisationServeur() != null;
    if (!estAutorisee && !serveurReinitialise) {
      throw const ReinitialisationRefusee(RefusReinitialisation.production);
    }
    if (!serveurReinitialise && !await estOuverte()) {
      throw const ReinitialisationRefusee(RefusReinitialisation.bascule);
    }
    if (!estPermisA(role)) {
      throw const ReinitialisationRefusee(RefusReinitialisation.role);
    }

    final toutes = await _tablesReelles();
    final effacables = await tablesEffacables();
    final references = await _references(toutes);
    final ordre = _trier(effacables, references);
    final aVider = ordre.toSet();

    final aDetacher = <_Reference>[];
    for (final r in references) {
      final gardeVersVidee =
          tablesPreserveesLocales.contains(r.source) &&
          aVider.contains(r.cible);
      final autoReference = r.source == r.cible && aVider.contains(r.source);
      if (!gardeVersVidee && !autoReference) continue;
      if (!r.nullable) {
        throw ReinitialisationRefusee(
          RefusReinitialisation.referenceBloquante(
            '${r.source}.${r.colonne} -> ${r.cible}',
          ),
        );
      }
      aDetacher.add(r);
    }

    final lignes = await _base.transaction(() async {
      for (final nom in _declencheursRg11) {
        await _base.customStatement('DROP TRIGGER IF EXISTS $nom');
      }
      for (final r in aDetacher) {
        await _base.customStatement(
          'UPDATE "${r.source}" SET "${r.colonne}" = NULL '
          'WHERE "${r.colonne}" IS NOT NULL',
        );
      }
      var total = 0;
      for (final table in ordre) {
        total += await _base.customUpdate(
          'DELETE FROM "$table"',
          updateKind: UpdateKind.delete,
        );
      }
      // Les statuts OPÉRATIONNELS des référentiels gardés : une chambre
      // « occupée » sans séjour, un véhicule « loué » sans contrat
      // affirmeraient un état que plus rien ne porte. `hors_service` et
      // `entretien` restent, comme au serveur.
      await _base.customStatement(
        "UPDATE unites_hebergement_local SET statut = 'libre' "
        "WHERE statut IN ('occupee', 'reservee', 'nettoyage')",
      );
      await _base.customStatement(
        "UPDATE vehicules_local SET statut = 'disponible' "
        "WHERE statut = 'loue'",
      );
      await creerDeclencheursComptables(_base);
      // Les vingt paramètres d'établissement (Lot J2) : leurs tables sont
      // GARDÉES, mais un poste « comme neuf » doit les avoir tous — une clé
      // vidée depuis est reposée, une valeur saisie n'est jamais réécrite.
      // ÉCART nommé avec le serveur, qui garde `parametres_systeme` sans
      // rejouer son seeder.
      await ParametresDepotLocal(_base).installerParametresInitiaux();
      return total;
    });

    // Les écrans à l'écoute des tables vidées ou remises à jour se relisent.
    _base.notifyUpdates({
      for (final t in [
        ...ordre,
        'unites_hebergement_local',
        'vehicules_local',
        'parametres_systeme_local',
        'taux_paie_local',
      ])
        TableUpdate(t),
    });

    return (tablesVidees: ordre.length, lignesSupprimees: lignes);
  }
}
