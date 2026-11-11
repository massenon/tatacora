/// Règles d'ÉQUIVALENCE de rôles, à UN seul endroit (11/11/2026, directives du PO).
///
/// Miroir de `User::ROLES_ADMINISTRATION`, `User::ROLES_SYSTEME_IMPORT_EXPORT`, `User::MODULES_IMPLICITES_SYSTEME` et
/// `User::ROLES_COMPTABILITE_SENSIBLE` du serveur ; un test (`regles_roles_test`) relit le PHP
/// et échoue si les deux côtés divergent. Aucune vue ne recopie ces listes.
library;

import 'garde_acces.dart';
import 'regle_archivage.dart';

/// Les rôles « SYSTÈME » d'Import & Export (PO, 11/11/2026), miroir de
/// `User::ROLES_SYSTEME_IMPORT_EXPORT` : accès COMPLET à l'écran quelle que soit la ligne
/// `IMPORT_EXPORT`. Les autres rôles du socle restent pilotés par leur droit. La sauvegarde est la
/// copie intégrale de la base : le barman y accède par décision du PO.
const Set<String> rolesSystemeImportExport = {
  'super_admin',
  'administrateur',
  'comptable',
  'gerant',
  'barman',
};

bool estRoleSystemeImportExport(String? role) =>
    rolesSystemeImportExport.contains(roleNormalise(role));

/// Les droits que les rôles système ont TOUJOURS en écriture, même sans RBAC (ligne absente,
/// `-` ou `L`) : « Import & Export, avec ses trois onglets » (PO). Droit implicite documenté,
/// pas un masquage : il est appliqué à la construction de la session
/// ([droitsAvecImplicites]), donc vu par le menu, la garde du routeur et chaque geste.
const Set<String> modulesImplicitesSysteme = {'IMPORT_EXPORT'};

/// Les droits [droits] d'un compte de rôle [role], complétés des droits implicites des
/// utilisateurs système. Un autre rôle voit ses droits rendus tels quels.
Map<String, dynamic> droitsAvecImplicites(
  Map<String, dynamic> droits,
  String? role,
) {
  if (!estRoleSystemeImportExport(role)) return droits;
  return {...droits, for (final m in modulesImplicitesSysteme) m: 'C'};
}

/// Les rôles qui passent les gestes comptables réservés (réouverture d'exercice, affectation du
/// résultat et contre-passation) : le comptable ET le gérant (PO). L'administrateur n'y figure
/// pas : ce n'est pas un droit de plus.
const Set<String> rolesComptabiliteSensible = {'comptable', 'gerant'};

/// Le comptable OU le gérant.
bool estComptableOuGerant(String? role) =>
    rolesComptabiliteSensible.contains(roleNormalise(role));

/// Pour les gardes qui ne portent que le nom d'un module.
bool estModuleImplicite(ModuleTatacora module) =>
    modulesImplicitesSysteme.contains(module.code);
