/// Flavors — `FLUTTER_DEPLOYMENT.md` §2.
///
/// La valeur vient de `--dart-define=ENV=...` au moment du build, jamais d'un
/// fichier lu à l'exécution ni d'un réglage utilisateur.
///
/// ## La règle stricte, et ce qu'elle empêche
///
/// > Un build `production` ne doit **jamais** pouvoir basculer vers une autre
/// > base URL depuis l'interface.
///
/// Sans elle, un utilisateur peut pointer vers Recette en croyant manipuler
/// des données réelles — ou l'inverse, saisir en production ce qu'il pensait
/// être un essai. `selecteurVisible` porte cette règle dans le code plutôt que
/// dans une consigne d'écran.
enum Flavor { dev, recette, production, demo }

final class Environnement {
  const Environnement._({
    required this.flavor,
    required this.baseUrl,
    required this.libelle,
  });

  final Flavor flavor;

  /// `null` pour le flavor `demo` : il fonctionne **entièrement en local**,
  /// sans backend (`SEEDER_TEST_FLUTTER.md` §4). Un appel réseau y est un
  /// défaut, pas une dégradation.
  final String? baseUrl;

  final String libelle;

  static const String _cle = String.fromEnvironment('ENV', defaultValue: 'dev');

  static const Environnement _dev = Environnement._(
    flavor: Flavor.dev,
    baseUrl: 'http://localhost:8000/api/v1',
    libelle: 'Développement',
  );

  static const Environnement _recette = Environnement._(
    flavor: Flavor.recette,
    baseUrl: 'https://recette-api.tatacora-erp.com/api/v1',
    libelle: 'Recette',
  );

  /// Le serveur de production — décision du PO du 15/10/2026 (lot F2a).
  /// C'est le SEUL serveur auquel un poste de production s'appaire et
  /// pousse sa file : l'appairage enregistre cette adresse dans `poste.json`
  /// (`serveur`), et le moteur d'envoi refuse un appairage fait vers une
  /// autre (`EtatSynchronisation.autreServeur`).
  static const Environnement _production = Environnement._(
    flavor: Flavor.production,
    baseUrl: 'https://logirestock.digitonpro.com/api/v1',
    libelle: 'Production',
  );

  static const Environnement _demo = Environnement._(
    flavor: Flavor.demo,
    baseUrl: null,
    libelle: 'Démonstration',
  );

  /// Environnement actif, résolu au build.
  ///
  /// Une valeur `ENV` inconnue retombe sur `dev`, jamais sur `production` :
  /// une faute de frappe dans un script de build ne doit pas envoyer des
  /// écritures d'essai sur la base réelle.
  static Environnement get actuel => switch (_cle) {
    'recette' => _recette,
    'production' => _production,
    'demo' => _demo,
    _ => _dev,
  };

  bool get estProduction => flavor == Flavor.production;

  /// Mode local intégral : aucune requête réseau ne doit partir.
  bool get estHorsLigneIntegral => flavor == Flavor.demo;

  /// Le sélecteur d'environnement n'existe **jamais** en production.
  bool get selecteurVisible => !estProduction;

  /// Le bandeau d'environnement n'est affiché qu'en dehors de la production :
  /// en production, il n'apporte rien et occupe une ligne d'écran.
  bool get bandeauVisible => !estProduction;
}
