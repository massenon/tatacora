/// Les champs de « Mon profil » que leur titulaire modifie SOUS DROIT — réplique de
/// `App\Pwa\Support\ChampsProfil` du serveur (décision du Product Owner du
/// 03/11/2026) : leur droit RBAC, leurs bornes, leur normalisation, leurs phrases.
///
/// La FONCTION n'est pas ici : c'est le rôle RBAC, géré par l'administrateur. L'
/// « intitulé de poste » est un texte libre, informatif, SANS effet sur les droits.
///
/// ## Le droit est un module RBAC transverse, binaire
///
/// `PROFIL_NOM`, `PROFIL_TELEPHONE`, `PROFIL_INTITULE` : `C` autorise, tout le reste
/// (`-`, `L`, absent) refuse — un droit ne s'obtient jamais par omission. Par défaut,
/// le nom et le téléphone sont ouverts à TOUS les rôles, l'intitulé aux deux rôles
/// d'administration. L'administrateur règle le reste à l'écran « Rôles &
/// Permissions ».
library;

/// Un champ modifiable de « Mon profil ».
enum ChampProfil {
  nomComplet('PROFIL_NOM', 'nom_complet', 'Modifier son nom complet'),
  telephone('PROFIL_TELEPHONE', 'telephone', 'Modifier son téléphone'),
  intitule(
    'PROFIL_INTITULE',
    'intitule_poste',
    'Modifier son intitulé de poste',
  );

  const ChampProfil(this.droit, this.cle, this.libelleDroit);

  /// Le code du droit dans la matrice (`roles_local.droits_json`).
  final String droit;

  /// La clé du champ (colonne du serveur), pour le journal d'audit.
  final String cle;

  /// Le libellé du droit à l'écran « Rôles & Permissions » (`pwa.roles.profil_*`).
  final String libelleDroit;

  /// Le champ qui porte ce [droit], `null` si ce n'est pas un droit de profil.
  static ChampProfil? depuisDroit(String droit) {
    for (final c in values) {
      if (c.droit == droit) return c;
    }
    return null;
  }
}

/// Les trois codes de droit, dans l'ordre de l'écran.
final List<String> codesDroitsProfil = [
  for (final c in ChampProfil.values) c.droit,
];

/// Les droits de profil qu'un rôle reçoit PAR DÉFAUT quel qu'il soit (y compris un
/// rôle créé à l'écran) : le nom et le téléphone. L'intitulé est réservé par défaut
/// aux rôles d'administration (le socle).
const Set<String> droitsProfilPourTous = {'PROFIL_NOM', 'PROFIL_TELEPHONE'};

/// Les rôles d'administration — qui reçoivent aussi l'intitulé de poste par défaut
/// (`User::ROLES_ADMINISTRATION` du serveur).
const Set<String> rolesAdministrationProfil = {'administrateur', 'super_admin'};

/// Les valeurs par défaut des trois droits pour un rôle de libellé [role], sous
/// la forme de la matrice (`C`/`-`) — `RolePermissionSeeder::MATRICE` et
/// `completerModulesNouveaux()` du serveur.
Map<String, String> droitsProfilParDefaut(String role) => {
  'PROFIL_NOM': 'C',
  'PROFIL_TELEPHONE': 'C',
  'PROFIL_INTITULE': rolesAdministrationProfil.contains(role) ? 'C' : '-',
};

/// Les trois droits TRANSVERSES des entrées de menu ouvertes à tous (09/11/2026,
/// décision du PO) : `RolePermissionSeeder::DROITS_OUVERTS_A_TOUS`. Lecture (`L`)
/// pour tout rôle, y compris un rôle créé à l'écran ; `C` pour les rôles
/// d'administration. Ils ne commandent que la VISIBILITÉ.
const List<String> droitsOuvertsATous = [
  'SYNCHRO',
  'APPAIRAGE',
  'IMPORT_EXPORT',
];

/// Les valeurs par défaut de ces trois droits pour un rôle de libellé [role].
Map<String, String> droitsOuvertsATousParDefaut(String role) => {
  for (final code in droitsOuvertsATous)
    code: rolesAdministrationProfil.contains(role) ? 'C' : 'L',
};

/// Les règles de saisie — `ChampsProfil` du serveur.
abstract final class ReglesProfil {
  static const int nomMax = 120;
  static const int telephoneMax = 30;
  static const int intituleMax = 120;

  /// Chiffres, plus, espaces, tirets — rien d'autre.
  static final RegExp motifTelephone = RegExp(r'^[0-9+ \t\n\r\f\v-]+$');

  /// Un texte libre ne porte aucun caractère de contrôle.
  static final RegExp motifControle = RegExp(r'[\u0000-\u001F\u007F-\u009F]');

  /// Trim, espaces internes réduits à un seul ; vide → `null`
  /// (`ChampsProfil::normaliser`).
  static String? normaliser(String? valeur) {
    final propre = (valeur ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
    return propre.isEmpty ? null : propre;
  }

  /// La phrase de refus d'une valeur DÉJÀ normalisée, `null` si elle convient. Le
  /// vide est permis (il efface la valeur).
  static String? erreur(ChampProfil champ, String? valeur) {
    if (valeur == null) return null;
    final n = valeur.runes.length;
    switch (champ) {
      case ChampProfil.nomComplet:
        if (n > nomMax || motifControle.hasMatch(valeur)) {
          return MessagesProfil.nomInvalide;
        }
      case ChampProfil.telephone:
        if (n > telephoneMax || !motifTelephone.hasMatch(valeur)) {
          return MessagesProfil.telephoneInvalide;
        }
      case ChampProfil.intitule:
        if (n > intituleMax || motifControle.hasMatch(valeur)) {
          return MessagesProfil.intituleInvalide;
        }
    }
    return null;
  }
}

/// Les phrases (`pwa.profil.*` du serveur), au mot.
abstract final class MessagesProfil {
  static const String nomInvalide =
      'Le nom complet ne peut pas dépasser 120 caractères ni contenir de caractère de contrôle.';
  static const String telephoneInvalide =
      'Le téléphone ne peut contenir que des chiffres, des +, des espaces et des tirets (30 caractères au plus).';
  static const String intituleInvalide =
      "L'intitulé de poste ne peut pas dépasser 120 caractères ni contenir de caractère de contrôle.";
  static const String champRefuse =
      'Votre rôle ne permet pas de modifier ce champ.';
  static const String infosEnregistrees = 'Informations enregistrées.';
  static const String aucunChangement = 'Aucune modification à enregistrer.';
}

/// Un refus d'enregistrement du profil — par CHAMP (`nom_complet`, `telephone`,
/// `intitule_poste`, `email`, `droit`), comme les erreurs de validation du serveur.
final class RefusProfil implements Exception {
  const RefusProfil(this.erreurs);

  RefusProfil.message(String champ, String message)
    : erreurs = {champ: message};

  final Map<String, String> erreurs;

  String get message => erreurs.values.first;

  @override
  String toString() => message;
}

/// Ce que « Mon profil » relit du compte : ses trois champs et SES droits, lus en
/// base au moment de l'ouverture (jamais ceux, éventuellement périmés, de la
/// session).
final class ProfilDuCompte {
  const ProfilDuCompte({
    required this.nomComplet,
    required this.telephone,
    required this.intitule,
    required this.droits,
  });

  final String? nomComplet;
  final String? telephone;
  final String? intitule;

  /// Les champs que ce compte peut modifier.
  final Set<ChampProfil> droits;

  bool peutModifier(ChampProfil champ) => droits.contains(champ);
}
