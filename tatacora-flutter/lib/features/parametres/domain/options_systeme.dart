/// Les bascules d'activation du maître — réplique de `OptionsSystemeService`.
///
/// ## Un seul lecteur, et il vit ICI
///
/// Le serveur porte trois bascules (`activation_suppression`,
/// `reinitialisation_seeders`, `activation_alertes_ouverture`) et les lit par UN
/// seul auteur, `OptionsSystemeService::actif()`. Une clé absente de
/// `parametres_systeme` vaut son DÉFAUT du maître, pas `false` : chaque lecteur
/// qui réimplémenterait « absent = faux » éteindrait les alertes d'ouverture de
/// tout poste jamais paramétré. Le poste fait de même : un écran qui lirait la
/// valeur brute ferait diverger sa règle de celle du serveur au premier
/// changement de défaut.
///
/// ## Ce qui est confronté au serveur
///
/// `options_systeme_contre_serveur_test.dart` (et `archivage_contre_serveur_test`)
/// posent la MÊME valeur brute dans `parametres_systeme` du serveur et dans
/// `parametres_systeme_local`, puis comparent `suppressionActive()` : le défaut
/// de chaque clé, la lecture d'une valeur absente, vide, blanche, `true`, `1`,
/// `on`, `oui`… Les valeurs que l'écran Paramètres de CE poste écrit sont
/// `true` / `false` seulement.
///
/// @see RG-10 paramétrage sans déploiement
library;

abstract final class OptionsSysteme {
  /// « Suppression d'un enregistrement » : ouvre le geste « Supprimer » (qui
  /// ARCHIVE) aux profils autres que les deux rôles d'administration.
  static const String cleSuppression = 'activation_suppression';

  static const String cleReinitialisationSeeders = 'reinitialisation_seeders';
  static const String cleAlertesOuverture = 'activation_alertes_ouverture';

  /// Les défauts du maître (`OptionsSystemeService::DEFAUTS`) : la suppression
  /// naît FERMÉE — sur un ERP d'exploitation, l'action destructrice n'est pas à
  /// portée de clic tant qu'un Administrateur ne l'a pas ouverte.
  static const Map<String, bool> defauts = {
    cleSuppression: false,
    cleReinitialisationSeeders: false,
    cleAlertesOuverture: true,
  };

  /// `OptionsSystemeService::actif($cle)` sur la valeur [stockee] de la clé
  /// (`null` si absente) : hors registre = faux, jamais vrai ; vide ou blanche =
  /// le défaut ; sinon `filter_var($valeur, FILTER_VALIDATE_BOOLEAN)`.
  static bool actif(String cle, String? stockee) {
    final defaut = defauts[cle];
    if (defaut == null) return false;
    if (_estBlancheAuSensDeLaravel(stockee)) return defaut;
    return filterVarBooleen(stockee!);
  }

  /// `OptionsSystemeService::suppressionActive()`.
  static bool suppressionActive(String? stockee) =>
      actif(cleSuppression, stockee);
}

/// `blank($valeur)` de Laravel pour une chaîne : `null`, ou vide APRÈS `trim()`.
bool _estBlancheAuSensDeLaravel(String? valeur) =>
    valeur == null || valeur.trim().isEmpty;

/// `filter_var($valeur, FILTER_VALIDATE_BOOLEAN)` sans `FILTER_NULL_ON_FAILURE` :
/// « 1 », « true », « on », « yes » (casse ignorée, espaces de bord retirés) sont
/// vrais ; TOUT le reste — « 0 », « false », « non », « oui », « garbage » — est
/// faux. « oui » n'est pas un booléen pour PHP.
bool filterVarBooleen(String valeur) =>
    const {'1', 'true', 'on', 'yes'}.contains(valeur.trim().toLowerCase());
