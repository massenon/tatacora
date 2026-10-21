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
const Map<String, AjoutMenuPoste> ajoutsMenuPoste = {
  'Comptes utilisateurs': (
    groupe: 'Pilotage & administration',
    apres: 'Rôles & Permissions',
    date: '14/10/2026',
    raison:
        'Lot J2, directive du PO : la PWA n’a AUCUN écran de gestion des '
        'comptes (ni composant `app/Pwa`, ni vue, ni route `pwa.*`) ; sur ce '
        'poste sans serveur, c’est le seul endroit où un administrateur crée, '
        'désactive ou réinitialise un compte. Réservée aux rôles '
        'd’administration (`rolesExiges`).',
  ),
  'Synchronisation': (
    groupe: 'Pilotage & administration',
    apres: 'Paramètres',
    date: '21/10/2026',
    raison:
        'Demande du PO : un lien direct vers l’écran de synchronisation de '
        'ce poste (file d’envoi, « À traiter », dernière descente). La PWA '
        'n’a pas cet écran : c’est un instrument du poste hors ligne. Il '
        'reste gardé par le module Paramètres.',
  ),
};

/// La page d'origine que porte un ajout du poste dans
/// `navigation_tatacora.dart` — il n'a pas de page de la vue.
const String pageAjoutDuPoste = '(ajout du poste, sans page de la vue)';
