/// Les AJOUTS du poste au menu de la vue — chacun DÉCIDÉ par le Product Owner,
/// daté et motivé, déclaré ici UN PAR UN.
///
/// Le menu Flutter se confronte au registre `MenuLateral::NAVIGATION` de la
/// PWA (`coquille_conformite_test.dart`, `coquille_rendu_test.dart`) : mêmes
/// groupes, mêmes entrées, même ordre, au caractère près. Une entrée que la
/// PWA n'a pas n'y est admise QUE déclarée ici, à sa place exacte (groupe, et
/// l'entrée de la vue qui la précède). Tout le reste reste confronté strictement
/// — les vingt-quatre destinations de la PWA comprises.
///
/// Une déclaration est PÉRIMÉE, et fait échouer les gardes, le jour où la PWA
/// porte elle-même l'entrée, ou le jour où le poste la retire.
library;

/// Une entrée de menu propre au poste.
typedef AjoutMenuPoste = ({
  /// Le groupe de la vue qui la reçoit.
  String groupe,

  /// L'entrée de la VUE qu'elle suit immédiatement.
  String apres,

  /// La décision du Product Owner, `jj/mm/aaaa`.
  String date,

  /// Pourquoi la PWA ne l'a pas et le poste, si.
  String raison,
});

/// Le registre. La clé est le libellé de l'entrée.
///
/// VIDE depuis le 29/10/2026 : « Comptes utilisateurs » (Lot J2, 14/10/2026) était
/// le seul ajout du poste ; la PWA l'a portée elle-même (option A du PO, mot de
/// passe perdu SANS e-mail : `pwa.comptes-utilisateurs`, entrée du menu juste
/// après « Rôles & Permissions »). La déclaration était périmée, comme ce fichier
/// le prévoit, et a été retirée. Le registre reste, prêt pour le prochain ajout.
const Map<String, AjoutMenuPoste> ajoutsMenuPoste = {};

/// La page d'origine que porte un ajout du poste dans
/// `navigation_tatacora.dart` — il n'a pas de page de la vue.
const String pageAjoutDuPoste = '(ajout du poste, sans page de la vue)';
