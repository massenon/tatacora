/// Table de correspondance UNIQUE : fonction métier -> compte du plan comptable
/// du Product Owner. RÉPLIQUE de `App\Domain\Comptabilite\Support\ComptesSyscohada`
/// du serveur (décision du PO du 10/10/2026 : le serveur est la référence).
///
/// ⚠ **À VALIDER PAR LE COMPTABLE** — comme au serveur : la correspondance a été
/// établie par le lead à partir de sources secondaires, le texte officiel de
/// l'AUDCIF n'a pas été consulté. Le fichier du PO fait foi. Elle n'est pas
/// recopiée ici « à peu près » : `comptes_syscohada_contre_serveur_test.dart`
/// EXÉCUTE PHP, relit la classe du serveur par réflexion et exige l'égalité
/// exacte, dans les deux sens (aucun rôle en trop, aucun manquant, aucun
/// numéro différent).
///
/// ## Aucun compte inventé
///
/// Tout numéro de ce fichier existe dans le plan comptable embarqué
/// (`assets/data/plan-comptable-syscohada-revise.csv`) : un test le prouve, et
/// un autre balaie `lib/` pour qu'aucun numéro de compte en dur n'échappe au
/// plan. Un compte absent du plan n'est JAMAIS créé ici : le flux concerné se
/// refuse en nommant le compte.
///
/// ## Centres de coût
///
/// Le fichier du PO ne porte aucun centre. Le CENTRE DE COÛT porte la
/// distinction que les anciens numéros portaient (caisse Réception / Restaurant
/// / Bar, produit hébergement / restaurant) : une ligne sur 5711 ou 7061 doit
/// nommer son centre. [centreParDefaut] ne couvre que les comptes que le code
/// mouvemente en dur ; tout autre compte naît SANS centre, et l'écriture doit
/// alors porter le sien (RG-12) — rien n'est deviné.
///
/// @see RG-12 Centre de coût obligatoire
library;

abstract final class ComptesSyscohada {
  static const clients = '4111';
  static const fournisseurs = '4011';
  static const avancesClients = '4191';
  static const tvaFactureeBiens = '4431';
  static const tvaFactureePrestations = '4432';
  static const tvaRecuperableAchats = '4452';
  static const caisse = '5711';
  static const banque = '5211';
  static const mobileMoney = '552';
  static const produitPrestations = '7061';
  static const produitMarchandises = '7011';
  static const produitLocations = '7073';
  static const achatsMarchandises = '6011';
  static const electricite = '6052';
  static const eau = '6051';
  static const locationMaterielTransport = '6223';
  static const telephoneInternet = '6281';
  static const resultatBenefice = '131';
  static const resultatPerte = '139';

  /// Les rôles, sous le NOM DE LA CONSTANTE DU SERVEUR (`CLIENTS`,
  /// `AVANCES_CLIENTS`…) : c'est ce nom que le test confronte à la réflexion
  /// PHP, jamais une traduction.
  static const tous = <String, String>{
    'CLIENTS': clients,
    'FOURNISSEURS': fournisseurs,
    'AVANCES_CLIENTS': avancesClients,
    'TVA_FACTUREE_BIENS': tvaFactureeBiens,
    'TVA_FACTUREE_PRESTATIONS': tvaFactureePrestations,
    'TVA_RECUPERABLE_ACHATS': tvaRecuperableAchats,
    'CAISSE': caisse,
    'BANQUE': banque,
    'MOBILE_MONEY': mobileMoney,
    'PRODUIT_PRESTATIONS': produitPrestations,
    'PRODUIT_MARCHANDISES': produitMarchandises,
    'PRODUIT_LOCATIONS': produitLocations,
    'ACHATS_MARCHANDISES': achatsMarchandises,
    'ELECTRICITE': electricite,
    'EAU': eau,
    'LOCATION_MATERIEL_TRANSPORT': locationMaterielTransport,
    'TELEPHONE_INTERNET': telephoneInternet,
    'RESULTAT_BENEFICE': resultatBenefice,
    'RESULTAT_PERTE': resultatPerte,
  };

  /// Les sept centres de coût actés au CdCF : libellé -> type
  /// (`ComptabiliteReferentielSeeder::CENTRES`).
  static const centres = <String, String>{
    'Hébergement': 'exploitation',
    'Restaurant': 'exploitation',
    'Bar': 'exploitation',
    'Tourisme': 'exploitation',
    'Véhicules': 'exploitation',
    'RH': 'support',
    'Structure': 'support',
  };

  /// Les cinq journaux de `MODULE_COMPTABILITE_COMPLET.md` §2 : code -> libellé
  /// (`ComptabiliteReferentielSeeder::JOURNAUX`).
  static const journaux = <String, String>{
    'VTE': 'Journal des ventes',
    'ACH': 'Journal des achats',
    'BQ': 'Journal de banque',
    'CAI': 'Journal de caisse',
    'OD': 'Journal des opérations diverses',
  };

  /// Numéro de compte -> libellé du centre par défaut
  /// (`ComptabiliteReferentielSeeder::CENTRE_PAR_DEFAUT`). Suggestion de saisie
  /// uniquement.
  static const centreParDefaut = <String, String>{
    '131': 'Structure',
    '139': 'Structure',
    '4011': 'Structure',
    '4111': 'Structure',
    '4191': 'Hébergement',
    '4431': 'Structure',
    '4432': 'Structure',
    '4452': 'Structure',
    '5211': 'Structure',
    '552': 'Structure',
    '5711': 'Hébergement',
  };

  /// Registre fermé des natures d'un compte (`PlanComptableService::NATURES`).
  static const natures = <String>['actif', 'passif', 'charge', 'produit'];
}
