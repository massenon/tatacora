/// Le REGISTRE DES ARCHIVES — onglet « Restaurer » d'Import & Export, réplique
/// de `App\Shared\ImportExport\Services\RegistreArchivesService` (02/09/2026).
///
/// ## Aucune table d'archives, ici comme au serveur
///
/// « Supprimer = archiver » se matérialise par un STATUT réversible du
/// référentiel lui-même ; DEUX familles le portent réellement : les unités
/// d'hébergement (M1) et les véhicules (M8), toutes deux `hors_service`. Ce
/// registre est un AGRÉGAT DÉRIVÉ de ces statuts, jamais une table qu'il
/// faudrait tenir à jour. (L'ancien motif « il faudrait une table d'archives »
/// était inexact : le web n'en a pas.)
///
/// ## D'où viennent « archivé le » et « par »
///
/// Le serveur lit la date du dernier archivage sur la ligne (colonnes d'audit)
/// et l'auteur dans la colonne d'audit. Le poste n'a pas ces colonnes : l'archivage
/// d'une unité (`{'actif': false}`) ou d'un véhicule (`{'statut': 'hors_service'}`)
/// est une OPÉRATION de la file d'envoi, qui porte l'instant de saisie et le
/// login de l'auteur (`operations_sync_local.auteur_login`, v38). Un élément
/// archivé SANS opération locale (archivé par un autre poste, ou avant la v38)
/// rend « — » aux deux colonnes : jamais un nom ni une date devinés.
///
/// ## « Déjà restaurées » vient de l'HISTORIQUE, pas d'un drapeau
///
/// Une fois restauré, l'élément quitte `hors_service` : aucun drapeau ne reste
/// sur sa ligne. Le serveur lit les transitions `hors_service → …` du journal
/// d'audit ; le poste les lit de la même file : une opération de restauration
/// (`{'actif': true}` / un statut autre que `hors_service`) qui suit une
/// opération d'archivage du MÊME élément est une restauration passée. Cent au
/// plus, les plus récentes d'abord (`limit(100)` du serveur).
///
/// ⚠ Strict à dessein : la file ne garde pas l'ANCIEN statut. Un véhicule
/// remis `disponible` depuis l'état `entretien` produit la même opération
/// qu'une restauration depuis `hors_service` ; sans archivage connu juste avant,
/// l'opération n'est PAS comptée (une restauration affirmée sans l'avoir
/// vérifiée serait une fausse trace). Les archivages d'un autre poste n'y sont
/// donc pas : écart nommé plus bas.
///
/// ## Écarts nommés
///
/// * Les restaurations / archivages faits par un AUTRE poste, ou avant la v38,
///   ne sont pas dans la file de CE poste : ils n'y apparaissent pas comme
///   « déjà restaurés » (le serveur, qui journalise toute transition, les
///   liste), et l'archivé correspondant rend « — » aux colonnes « ARCHIVÉ LE »
///   et « PAR » (le serveur y met la date de dernière écriture).
/// * La file garde ses opérations tant que le poste n'est pas réinitialisé.
library;

import '../../../core/rbac/garde_acces.dart';
import 'roles_du_poste.dart' show libellesModulesMatrice;

/// `RegistreArchivesService::TYPES` — le registre FERMÉ des familles archivables.
enum TypeArchive {
  uniteHebergement('unite_hebergement', ModuleTatacora.m1Hebergement),
  vehicule('vehicule', ModuleTatacora.m8Vehicules);

  const TypeArchive(this.code, this.module);

  final String code;
  final ModuleTatacora module;

  /// `'M1'` / `'M8'` — le code du module, tel que le serveur le rend.
  String get codeModule => switch (this) {
    TypeArchive.uniteHebergement => 'M1',
    TypeArchive.vehicule => 'M8',
  };

  /// `RolesPermissions::MODULES['M1']` — la colonne « MODULE ».
  String get libelleModule => libellesModulesMatrice[module] ?? codeModule;
}

/// Une entrée du registre.
final class EntreeArchive {
  const EntreeArchive({
    required this.type,
    required this.id,
    required this.libelle,
    required this.restaure,
    this.archiveLe,
    this.archivePar,
  });

  final TypeArchive type;
  final String id;

  /// Le numéro de l'unité ou l'immatriculation du véhicule.
  final String libelle;

  /// `true` : une restauration PASSÉE (ligne estompée, badge « RESTAURÉ »).
  final bool restaure;

  /// L'instant du geste ; `null` : « — ».
  final DateTime? archiveLe;
  final String? archivePar;
}

/// Une unité ou un véhicule tel que le registre le lit.
typedef ElementParc = ({String id, String libelle, String statut});

/// Une opération de la file, réduite à ce que le registre en lit.
typedef OperationArchive = ({
  TypeArchive type,
  String entiteId,
  Map<String, Object?> charge,
  DateTime instant,
  String? auteur,
});

const String statutHorsService = 'hors_service';

/// Vrai quand [o] est un ARCHIVAGE (`{'actif': false}` ; `{'statut':
/// 'hors_service'}`).
bool _estArchivage(OperationArchive o) => switch (o.type) {
  TypeArchive.uniteHebergement => o.charge['actif'] == false,
  TypeArchive.vehicule => o.charge['statut'] == statutHorsService,
};

/// Vrai quand [o] est une RESTAURATION (`{'actif': true}` ; un statut autre que
/// `hors_service`).
bool _estRestauration(OperationArchive o) => switch (o.type) {
  TypeArchive.uniteHebergement => o.charge['actif'] == true,
  TypeArchive.vehicule =>
    o.charge['statut'] is String && o.charge['statut'] != statutHorsService,
};

/// `RegistreArchivesService::restaurees()` : au plus cent restaurations.
const int plafondRestaurees = 100;

/// Les deux listes du registre.
typedef RegistreArchives = ({
  List<EntreeArchive> archivees,
  List<EntreeArchive> restaurees,
});

/// `archives()` + `restaurees()` : [unites] et [vehicules] sont TOUS ceux du
/// parc ; [operations] est la file, dans l'ordre d'écriture.
RegistreArchives composerRegistreArchives({
  required List<ElementParc> unites,
  required List<ElementParc> vehicules,
  required List<OperationArchive> operations,
}) {
  final parCle = <(TypeArchive, String), List<OperationArchive>>{};
  for (final o in operations) {
    parCle.putIfAbsent((o.type, o.entiteId), () => []).add(o);
  }

  final archivees = <EntreeArchive>[];
  void archives(TypeArchive type, List<ElementParc> elements) {
    for (final e in elements) {
      if (e.statut != statutHorsService) continue;
      final dernier = (parCle[(type, e.id)] ?? const <OperationArchive>[])
          .where(_estArchivage)
          .lastOrNull;
      archivees.add(
        EntreeArchive(
          type: type,
          id: e.id,
          libelle: e.libelle,
          restaure: false,
          archiveLe: dernier?.instant,
          archivePar: dernier?.auteur,
        ),
      );
    }
  }

  archives(TypeArchive.uniteHebergement, unites);
  archives(TypeArchive.vehicule, vehicules);
  // `usort` du serveur, stable : la plus récente d'abord, « — » (sans date) à la fin.
  archivees.sort(
    (a, b) => (b.archiveLe?.millisecondsSinceEpoch ?? 0).compareTo(
      a.archiveLe?.millisecondsSinceEpoch ?? 0,
    ),
  );

  final libelles = {
    for (final u in unites) (TypeArchive.uniteHebergement, u.id): u.libelle,
    for (final v in vehicules) (TypeArchive.vehicule, v.id): v.libelle,
  };
  final restaurees = <EntreeArchive>[];
  parCle.forEach((cle, ops) {
    final libelle = libelles[cle];
    // Purgé depuis : plus rien à montrer (le poste ne purge pas encore).
    if (libelle == null) return;
    var archive = false;
    for (final o in ops) {
      if (_estArchivage(o)) {
        archive = true;
      } else if (archive && _estRestauration(o)) {
        archive = false;
        restaurees.add(
          EntreeArchive(
            type: cle.$1,
            id: cle.$2,
            libelle: libelle,
            restaure: true,
            archiveLe: o.instant,
            archivePar: o.auteur,
          ),
        );
      }
    }
  });
  restaurees.sort(
    (a, b) => b.archiveLe!.millisecondsSinceEpoch.compareTo(
      a.archiveLe!.millisecondsSinceEpoch,
    ),
  );

  return (
    archivees: archivees,
    restaurees: restaurees.take(plafondRestaurees).toList(),
  );
}

/// Le filtre de l'onglet — `$filtreArchives` du composant.
enum FiltreArchives { restaurables, toutes, restaurees }

/// `archivesFiltrees()` : le filtre puis la recherche (libellé OU code du
/// module, sans casse), tel que le composant les applique.
List<EntreeArchive> filtrerArchives(
  RegistreArchives registre, {
  FiltreArchives filtre = FiltreArchives.restaurables,
  String recherche = '',
}) {
  final liste = switch (filtre) {
    FiltreArchives.toutes => [...registre.archivees, ...registre.restaurees],
    FiltreArchives.restaurees => registre.restaurees,
    FiltreArchives.restaurables => registre.archivees,
  };
  final terme = recherche.trim().toLowerCase();
  if (terme.isEmpty) return liste;
  return [
    for (final e in liste)
      if (e.libelle.toLowerCase().contains(terme) ||
          e.type.codeModule.toLowerCase().contains(terme))
        e,
  ];
}
