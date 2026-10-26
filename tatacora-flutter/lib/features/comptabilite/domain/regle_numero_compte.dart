/// LA règle du numéro d'un compte créé au plan : DEUX À QUATRE chiffres, le
/// premier de 1 à 9. Source unique du poste — le moteur
/// (`MoteurComptable.creerCompte`), la modale « Créer un compte » du hub, son
/// invite et sa longueur maximale la relisent ; un test la confronte à celle du
/// serveur (`PlanComptableService::NUMERO_COMPTE_FORMAT`), que le hub de la PWA
/// relit aussi.
///
/// Le plan du PO (SYSCOHADA révisé, 1 332 comptes) ne compte aucun numéro de
/// plus de quatre chiffres : un compte de mouvement en porte de 2 à 4 (le
/// chiffre unique est la classe).
library;

abstract final class RegleNumeroCompte {
  /// `^[1-9][0-9]{1,3}$`.
  static final RegExp format = RegExp(r'^[1-9][0-9]{1,3}$');

  /// Le plus long numéro du plan du PO.
  static const int chiffresMax = 4;

  /// Un numéro valide, en invite du champ.
  static const String exemple = '6056';
}
