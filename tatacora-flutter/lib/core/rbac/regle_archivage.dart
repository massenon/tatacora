/// QUI PEUT ARCHIVER — la règle, écrite UNE fois. Réplique de
/// `App\Pwa\Support\AutoriseArchivage::peutArchiver()` (directive du Product
/// Owner du 03/09/2026 : « mettre le bouton Supprimer sur chaque table, pour
/// administrateur et super_admin »).
///
/// * `administrateur` et `super_admin` en `C` sur le module : oui, **sans la
///   bascule**. La bascule `activation_suppression` naît FERMÉE ; sans cette
///   exception, l'Administrateur n'aurait ni bouton de ligne, ni case, ni bouton
///   de lot, et rien à l'écran ne lui dirait où l'ouvrir.
/// * Tout autre rôle en `C` sur le module : oui, **seulement** quand la bascule
///   est ouverte en Paramètres. La lever pour tout le monde retirerait une
///   protection que le PO n'a pas demandé de lever.
/// * Un rôle en `L` ou sans accès : jamais.
///
/// ## Un seul auteur, plusieurs lecteurs
///
/// Un écran ne rejoue JAMAIS ce calcul : il le demande ici. Le serveur a plié sa
/// seconde copie le 03/09/2026 (la Paie portait la sienne) ; ce poste ne
/// l'écrit qu'une fois. La valeur de la bascule est lue par
/// `OptionsSysteme.suppressionActive` (un seul lecteur).
///
/// Lecteurs au 27/10/2026 : fournisseurs (M7), clients (M3), articles (M6) et
/// désormais la Paie (M13, `peutArchiverPaieProvider`, D272 levée par la
/// décision du PO « le poste fait comme le web »). Les unités d'hébergement
/// lisent la bascule seule (`vue_plan_hebergement.dart`, décision du
/// 13/10/2026 : tous les rôles qui écrivent). Aucun écran ne porte plus de
/// copie réduite aux deux rôles.
///
/// @see RG-15 traçabilité — un archivage ne détruit rien
library;

import 'garde_acces.dart';

/// `User::ROLES_ADMINISTRATION` : les deux rôles qui archivent sans la bascule.
const Set<String> rolesAdministration = {'administrateur', 'super_admin'};

/// Le libellé d'un rôle tel que la règle le compare : en minuscules, les
/// espaces remplacés par des soulignés (« Super Admin » -> `super_admin`). Le
/// serveur compare le libellé EXACT ; la session locale peut porter la casse
/// saisie à la création du compte.
String roleNormalise(String? role) =>
    (role ?? '').trim().toLowerCase().replaceAll(' ', '_');

/// `peutArchiver()` du serveur : le droit `C` sur [module], PUIS un des deux
/// rôles d'administration OU la bascule ouverte.
bool peutArchiver({
  required GardeAcces droits,
  required ModuleTatacora module,
  required String? role,
  required bool suppressionActive,
}) {
  if (!droits.peutEcrire(module)) return false;
  if (rolesAdministration.contains(roleNormalise(role))) return true;
  return suppressionActive;
}
