/// RBAC — **premier niveau sur trois**, `00_MASTER_INSTRUCTIONS.md` §3.2.
///
/// ## Ce que ce fichier protège, et ce qu'il ne protège pas
///
/// Il masque des entrées de menu et des actions. C'est le niveau **le plus
/// faible** du dispositif : il améliore l'ergonomie en évitant de proposer ce
/// qui sera refusé, mais il ne protège **rien**.
///
/// Un utilisateur qui contourne l'interface est arrêté par le middleware et la
/// `Policy` Laravel (niveau 2), puis par le filtrage en base (niveau 3).
///
/// **Conséquence en revue :** constater « le bouton est masqué pour ce rôle »
/// ne vérifie rien. Il faut constater que l'API refuse l'appel.
///
/// ## Aucune règle d'accès n'est réinventée ici
///
/// La matrice 14 modules × 11 rôles est définie côté backend et fait autorité.
/// Ce fichier en est un **miroir de lecture**. Toute divergence se corrige au
/// backend d'abord.
library;

/// Modules du CdCF, plus les deux transverses et les trois droits ouverts à tous.
enum ModuleTatacora {
  m1Hebergement('M1'),
  m2Facturation('M2'),
  m3Crm('M3'),
  m4Restaurant('M4'),
  m5Bar('M5'),
  m6Stocks('M6'),
  m7Achats('M7'),
  m8Vehicules('M8'),
  m9Tourisme('M9'),
  m10Comptabilite('M10'),
  m11TableauxDeBord('M11'),
  m12Notifications('M12'),
  m13Rh('M13'),
  m14Etats('M14'),
  roles('ROLES'),
  parametres('PARAM'),

  /// Trois droits TRANSVERSES, hors écran de la matrice (09/11/2026, décision du
  /// PO : « Synchronisation », « Import & Export » et « Appairage Postes » sont au
  /// menu de TOUS les rôles par défaut). Lecture pour tous, écriture pour les
  /// rôles d'administration — mêmes valeurs que `RolePermissionSeeder::MATRICE`.
  /// Ils ne commandent que la VISIBILITÉ de l'entrée et de l'écran : chaque
  /// action sensible garde sa garde (rôle, ou écriture sur `PARAM`).
  synchro('SYNCHRO'),
  appairage('APPAIRAGE'),
  importExport('IMPORT_EXPORT'),

  /// Le droit d'ANNULER (réservation, vente, facture…), hors écran de la matrice comme les trois
  /// précédents (`RolePermissionSeeder::MATRICE`, `socleRbacCdcf`). Depuis le 09/11/2026 (décision du
  /// PO : « le serveur ne juge plus les droits du compte d'appairage sur les opérations d'un poste »)
  /// c'est CE droit, jugé sur l'utilisateur connecté, qui décide au poste de qui peut annuler une
  /// réservation — y compris celle d'un autre poste ou du serveur.
  annulations('ANNULATIONS');

  const ModuleTatacora(this.code);

  final String code;
}

/// Niveau d'accès à un module.
enum NiveauAcces {
  /// Accès complet — lecture et écriture.
  complet('C'),

  /// Lecture seule.
  lecture('L'),

  /// Aucun accès.
  aucun('-');

  const NiveauAcces(this.code);

  final String code;

  static NiveauAcces depuisCode(String? code) => switch (code) {
    'C' => NiveauAcces.complet,
    'L' => NiveauAcces.lecture,
    _ => NiveauAcces.aucun,
  };

  bool get peutLire => this != NiveauAcces.aucun;

  bool get peutEcrire => this == NiveauAcces.complet;
}

/// Droits de la session active.
///
/// Les droits viennent de la **réponse de connexion**, pas d'une table locale
/// figée : un rôle modifié côté backend doit prendre effet à la reconnexion
/// suivante, sans réinstallation.
final class GardeAcces {
  const GardeAcces(this._droits);

  /// Session sans aucun droit — état par défaut avant connexion.
  const GardeAcces.deconnecte() : _droits = const {};

  final Map<String, String> _droits;

  /// Reconstruit les droits depuis la charge utile de connexion.
  factory GardeAcces.depuisJson(Map<String, dynamic> json) {
    final droits = <String, String>{};
    for (final entree in json.entries) {
      final valeur = entree.value;
      if (valeur is String) droits[entree.key] = valeur;
    }
    return GardeAcces(droits);
  }

  NiveauAcces niveau(ModuleTatacora module) =>
      NiveauAcces.depuisCode(_droits[module.code]);

  bool peutLire(ModuleTatacora module) => niveau(module).peutLire;

  bool peutEcrire(ModuleTatacora module) => niveau(module).peutEcrire;

  /// Modules visibles au menu, dans l'ordre de déclaration.
  ///
  /// Un module sans aucun droit n'apparaît pas — plutôt que d'apparaître grisé.
  /// Un item grisé invite à cliquer et produit un refus ; l'absence n'invite à
  /// rien.
  List<ModuleTatacora> get modulesVisibles =>
      ModuleTatacora.values.where(peutLire).toList(growable: false);

  bool get estVide => _droits.isEmpty;

  /// Les MÊMES droits, clé pour clé (aucune égalité de valeur sur la garde elle-même : une
  /// session relue sans changement ne doit pas reconstruire tout l'écran).
  bool memesDroitsQue(GardeAcces autre) {
    if (_droits.length != autre._droits.length) return false;
    for (final e in _droits.entries) {
      if (autre._droits[e.key] != e.value) return false;
    }
    return true;
  }
}
