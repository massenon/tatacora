/// Les rôles DU POSTE et leur matrice de droits — réplique de la table `roles`
/// du serveur, de sa matrice (`Role::niveauSurModule()`) et du socle du CdCF
/// (`RolePermissionSeeder::MATRICE`), 14/10/2026.
///
/// ## Ce qui a changé le 14/10/2026 (demande du PO : écran complet)
///
/// Jusqu'à ce jour (D418), les colonnes de la matrice étaient DÉRIVÉES des
/// comptes du poste, faute de référentiel des rôles. Le référentiel existe
/// désormais (`roles_local`, schéma v24, seul auteur `RolesDao`) : les cartes et
/// la matrice viennent des rôles, comme au serveur, et le nombre de comptes
/// rattachés se compte sur `utilisateurs_local.role`.
library;

import '../../../core/format/cle_comparaison.dart';
import '../../../core/rbac/garde_acces.dart';

/// Un compte du poste, tel que l'écran des rôles le lit — jamais le dérivé du
/// mot de passe.
final class CompteDuPoste {
  const CompteDuPoste({
    required this.role,
    required this.droits,
    required this.actif,
  });

  final String role;
  final GardeAcces droits;
  final bool actif;
}

/// Une colonne de la matrice et une carte : un rôle, ses droits et ses
/// comptes — `RolesPermissions::render()`.
final class RoleDuPoste {
  const RoleDuPoste({
    required this.id,
    required this.libelle,
    required this.niveaux,
    required this.comptes,
    this.description,
  });

  final String id;

  /// `roles.libelle` — le CODE du rôle (`administrateur`, `barman`…).
  final String libelle;
  final String? description;

  /// La matrice telle qu'elle est stockée : code de module → `C`/`L`/`-`,
  /// modules hors écran compris (`ANNULATIONS`).
  final Map<String, String> niveaux;

  /// `withCount('utilisateurs')` : TOUS les comptes qui portent le rôle,
  /// désactivés compris, comme au serveur.
  final int comptes;

  /// Les droits, relus par la MÊME fabrique que la session.
  GardeAcces get droits => GardeAcces.depuisJson(niveaux);

  /// `RolesPermissions::render()` : le nombre de modules de l'écran à `C`.
  int get complet => [
    for (final m in libellesModulesMatrice.keys)
      if (droits.niveau(m) == NiveauAcces.complet) m,
  ].length;

  /// Le nombre de modules de l'écran à `L`.
  int get lecture => [
    for (final m in libellesModulesMatrice.keys)
      if (droits.niveau(m) == NiveauAcces.lecture) m,
  ].length;

  /// `RolePermissionService::estConformeAuSocle()` : `null` pour un rôle hors
  /// socle (« conforme » n'a pas de sens pour lui), sinon l'égalité EXACTE de
  /// chaque module du socle, `ANNULATIONS` compris.
  bool? get conforme {
    final socle = socleDuRole(libelle);
    if (socle == null) return null;
    for (final e in socle.entries) {
      if ((niveaux[e.key] ?? NiveauAcces.aucun.code) != e.value) return false;
    }
    return true;
  }
}

/// `$matriceConformeAuSocle` de la vue : conforme si AUCUN rôle du socle ne
/// s'en écarte (un rôle ajouté, `conforme == null`, ne rend pas la matrice
/// « amendée » à lui seul).
bool matriceConformeAuSocle(List<RoleDuPoste> roles) =>
    roles.every((r) => r.conforme != false);

/// Le socle du rôle [libelle], comparé comme MySQL compare `roles.libelle`
/// (`utf8mb4_unicode_ci` : sans casse ni accent) — `null` hors socle.
Map<String, String>? socleDuRole(String libelle) {
  final cle = cleDeComparaison(libelle);
  for (final e in socleRbacCdcf.entries) {
    if (cleDeComparaison(e.key) == cle) return e.value;
  }
  return null;
}

/// Le libellé affiché d'un rôle — `RolesPermissions::libelleRole()` : celui de
/// la table du composant, sinon `mb_convert_case(str_replace('_', ' ', $code),
/// MB_CASE_TITLE)` (« super_admin » → « Super Admin »).
String libelleRole(String code) {
  final connu = libellesRolesMatrice[code];
  if (connu != null) return connu;
  return code
      .replaceAll('_', ' ')
      .split(' ')
      .map(
        (mot) => mot.isEmpty
            ? mot
            : mot.substring(0, 1).toUpperCase() +
                  mot.substring(1).toLowerCase(),
      )
      .join(' ');
}

/// `mb_strtoupper(mb_substr($role->libelle, 0, 2))` — deux CARACTÈRES, pas
/// deux octets (« éric » → « ÉR »).
String initialesRole(String code) {
  final points = code.runes.take(2).toList();
  return String.fromCharCodes(points).toUpperCase();
}

/// `RolesPermissions::ROLES`, au mot.
const Map<String, String> libellesRolesMatrice = {
  'administrateur': 'Administrateur système',
  'gerant': 'Gérant / Direction',
  'receptionniste': 'Réceptionniste',
  'cuisine': 'Resp. Restaurant/Cuisine',
  'barman': 'Barman',
  'magasinier': 'Magasinier',
  'achats': 'Resp. Achats',
  'vehicules': 'Resp. Véhicules',
  'guide': 'Guide Touristique',
  'rh': 'Resp. RH',
  'comptable': 'Comptable',
};

/// Les libellés des modules de la matrice — `RolesPermissions::MODULES`, dans
/// son ordre et à ses mots.
const Map<ModuleTatacora, String> libellesModulesMatrice = {
  ModuleTatacora.m1Hebergement: 'Hébergement',
  ModuleTatacora.m2Facturation: 'Facturation',
  ModuleTatacora.m3Crm: 'CRM',
  ModuleTatacora.m4Restaurant: 'Restaurant',
  ModuleTatacora.m5Bar: 'Bar',
  ModuleTatacora.m6Stocks: 'Stocks',
  ModuleTatacora.m7Achats: 'Achats',
  ModuleTatacora.m8Vehicules: 'Véhicules',
  ModuleTatacora.m9Tourisme: 'Tourisme',
  ModuleTatacora.m10Comptabilite: 'Comptabilité',
  ModuleTatacora.m11TableauxDeBord: 'Tab. de Bord',
  ModuleTatacora.m12Notifications: 'Notifications',
  ModuleTatacora.m13Rh: 'RH',
  ModuleTatacora.m14Etats: 'États',
  ModuleTatacora.roles: 'Rôles',
  ModuleTatacora.parametres: 'Paramètres',
};

/// `RolePermissionSeeder::MATRICE`, recopiée À L'IDENTIQUE (14/10/2026) :
/// DOUZE rôles (dont `super_admin`, directive du PO du 03/09/2026) et DIX-SEPT
/// colonnes (dont `ANNULATIONS`, droit transverse que l'écran n'affiche pas,
/// mais que le socle pose et que « Rétablir » rétablit). Une divergence avec
/// le seeder se corrige ICI, jamais acceptée comme « presque pareil ».
const Map<String, Map<String, String>> socleRbacCdcf = {
  'super_admin': {
    'M1': 'C',
    'M2': 'C',
    'M3': 'C',
    'M4': 'C',
    'M5': 'C',
    'M6': 'C',
    'M7': 'C',
    'M8': 'C',
    'M9': 'C',
    'M10': 'C',
    'M11': 'C',
    'M12': 'C',
    'M13': 'C',
    'M14': 'C',
    'ROLES': 'C',
    'PARAM': 'C',
    'ANNULATIONS': 'C',
  },
  'administrateur': {
    'M1': 'C',
    'M2': 'C',
    'M3': 'C',
    'M4': 'C',
    'M5': 'C',
    'M6': 'C',
    'M7': 'C',
    'M8': 'C',
    'M9': 'C',
    'M10': 'C',
    'M11': 'C',
    'M12': 'C',
    'M13': 'C',
    'M14': 'C',
    'ROLES': 'C',
    'PARAM': 'C',
    'ANNULATIONS': 'C',
  },
  'gerant': {
    'M1': 'C',
    'M2': 'C',
    'M3': 'C',
    'M4': 'C',
    'M5': 'C',
    'M6': 'C',
    'M7': 'C',
    'M8': 'C',
    'M9': 'C',
    'M10': 'C',
    'M11': 'C',
    'M12': 'C',
    'M13': 'C',
    'M14': 'C',
    'ROLES': 'L',
    'PARAM': 'L',
    'ANNULATIONS': 'C',
  },
  'receptionniste': {
    'M1': 'C',
    'M2': 'C',
    'M3': 'C',
    'M4': 'L',
    'M5': 'L',
    'M6': 'L',
    'M7': '-',
    'M8': 'L',
    'M9': 'L',
    'M10': '-',
    'M11': 'L',
    'M12': 'L',
    'M13': '-',
    'M14': 'L',
    'ROLES': '-',
    'PARAM': '-',
    'ANNULATIONS': 'L',
  },
  'cuisine': {
    'M1': '-',
    'M2': '-',
    'M3': 'L',
    'M4': 'C',
    'M5': '-',
    'M6': 'C',
    'M7': '-',
    'M8': '-',
    'M9': '-',
    'M10': '-',
    'M11': 'L',
    'M12': '-',
    'M13': '-',
    'M14': 'L',
    'ROLES': '-',
    'PARAM': '-',
    'ANNULATIONS': '-',
  },
  'barman': {
    'M1': '-',
    'M2': '-',
    'M3': 'L',
    'M4': '-',
    'M5': 'C',
    'M6': 'C',
    'M7': '-',
    'M8': '-',
    'M9': '-',
    'M10': '-',
    'M11': 'L',
    'M12': '-',
    'M13': '-',
    'M14': 'L',
    'ROLES': '-',
    'PARAM': '-',
    'ANNULATIONS': '-',
  },
  'magasinier': {
    'M1': '-',
    'M2': '-',
    'M3': '-',
    'M4': 'L',
    'M5': 'L',
    'M6': 'C',
    'M7': 'C',
    'M8': '-',
    'M9': '-',
    'M10': '-',
    'M11': 'L',
    'M12': '-',
    'M13': '-',
    'M14': 'L',
    'ROLES': '-',
    'PARAM': '-',
    'ANNULATIONS': '-',
  },
  'achats': {
    'M1': '-',
    'M2': '-',
    'M3': '-',
    'M4': '-',
    'M5': '-',
    'M6': 'L',
    'M7': 'C',
    'M8': '-',
    'M9': '-',
    'M10': '-',
    'M11': 'L',
    'M12': '-',
    'M13': '-',
    'M14': 'L',
    'ROLES': '-',
    'PARAM': '-',
    'ANNULATIONS': '-',
  },
  'vehicules': {
    'M1': '-',
    'M2': '-',
    'M3': 'L',
    'M4': '-',
    'M5': '-',
    'M6': '-',
    'M7': '-',
    'M8': 'C',
    'M9': 'L',
    'M10': '-',
    'M11': 'L',
    'M12': '-',
    'M13': '-',
    'M14': 'L',
    'ROLES': '-',
    'PARAM': '-',
    'ANNULATIONS': '-',
  },
  'guide': {
    'M1': '-',
    'M2': '-',
    'M3': 'L',
    'M4': '-',
    'M5': '-',
    'M6': '-',
    'M7': '-',
    'M8': 'L',
    'M9': 'C',
    'M10': '-',
    'M11': '-',
    'M12': '-',
    'M13': '-',
    'M14': '-',
    'ROLES': '-',
    'PARAM': '-',
    'ANNULATIONS': '-',
  },
  'rh': {
    'M1': '-',
    'M2': '-',
    'M3': '-',
    'M4': '-',
    'M5': '-',
    'M6': '-',
    'M7': '-',
    'M8': '-',
    'M9': '-',
    'M10': 'L',
    'M11': 'L',
    'M12': '-',
    'M13': 'C',
    'M14': 'L',
    'ROLES': '-',
    'PARAM': '-',
    'ANNULATIONS': '-',
  },
  'comptable': {
    'M1': 'L',
    'M2': 'L',
    'M3': 'L',
    'M4': 'L',
    'M5': 'L',
    'M6': 'L',
    'M7': 'L',
    'M8': 'L',
    'M9': 'L',
    'M10': 'C',
    'M11': 'L',
    'M12': '-',
    'M13': 'L',
    'M14': 'C',
    'ROLES': '-',
    'PARAM': '-',
    'ANNULATIONS': 'L',
  },
};

/// Les colonnes de la matrice du serveur (`array_keys(MATRICE['administrateur'])`) :
/// un rôle neuf les reçoit toutes à `-` (`RolePermissionService::creerRole`
/// ne lui attache aucune permission).
List<String> get codesModulesSocle =>
    socleRbacCdcf['administrateur']!.keys.toList(growable: false);

/// Les refus et confirmations de l'écran, aux mots du serveur
/// (`lang/fr/pwa.php` `roles.*`, `lang/fr/validation.php`, `auth.php`).
abstract final class MessagesRoles {
  /// `auth.module_refuse` — `exigerEcriture('ROLES')`.
  static const String refusDroit = 'Vous n avez pas acces a ce module.';

  /// `validation.required` sur `libelleRoleSaisi` : Laravel n'a pas de nom
  /// d'attribut pour ce champ et affiche le nom technique (« libelle role
  /// saisi »). Défaut du serveur RÉPLIQUÉ, pas corrigé (14/10/2026) : c'est
  /// ce message, et non `pwa.roles.libelle_requis`, que la vue affiche.
  static const String libelleObligatoire =
      'Le champ libelle role saisi est obligatoire.';

  /// `validation.max.string` (`max:100`) sur `libelleRoleSaisi`.
  static const String libelleTropLong =
      'Le champ libelle role saisi ne peut pas contenir plus de 100 caracteres.';

  /// `validation.max.string` (`max:255`) sur `descriptionRoleSaisi`.
  static const String descriptionTropLongue =
      'Le champ description role saisi ne peut pas contenir plus de 255 caracteres.';

  /// `pwa.roles.libelle_requis` — le refus du Service (libellé vide après
  /// `trim`), que la validation rend inatteignable par l'écran.
  static const String libelleRequis = 'Le libellé du rôle est obligatoire.';

  /// `pwa.roles.role_deja_existant`.
  static String roleDejaExistant(String libelle) =>
      'Un rôle « $libelle » existe déjà.';

  /// `pwa.roles.verrouillage_administrateur`.
  static const String verrouillageAdministrateur =
      "Un administrateur ne peut pas se retirer l'accès à Rôles & "
      'Permissions : cela le verrouillerait hors de cet écran, y compris pour '
      'se corriger lui-même.';

  /// AJOUT du poste : `Role::findOrFail()` rend une page 404 au serveur ; le
  /// poste n'a pas de page d'erreur. Inatteignable par l'écran (le rôle vient
  /// de la liste affichée).
  static const String roleIntrouvable = 'Ce rôle est introuvable.';

  /// `pwa.roles.nouveau_role_cree`.
  static const String roleCree =
      "Rôle créé — tous les modules sont fermés (« — ») jusqu'à ce que vous lui "
      'accordiez des droits.';

  /// `pwa.roles.modifier_droits_enregistre`.
  static const String droitsEnregistres = 'Droits mis à jour.';

  /// `pwa.roles.retablir_socle_fait`.
  static String socleRetabli(int nombre) =>
      '$nombre rôle(s) du socle rétabli(s).';
}
