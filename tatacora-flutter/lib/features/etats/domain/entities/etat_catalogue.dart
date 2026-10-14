import '../../../../core/rbac/garde_acces.dart';

/// Un état du catalogue — une entrée du registre fermé de M14.
///
/// @see EF-M14-02 Bibliothèque d'états standards par module
/// @see RG-19 Entête normalisée et moteur d'états
///
/// ## Quatre champs, comme le serveur
///
/// `CatalogueEtatsService::pourUtilisateur()` rend exactement quatre champs ;
/// ce poste les compose depuis `EtatLocal` et les droits (`EtatsApi.catalogue`) :
/// `code`, `module`, `libelle`, `niveau`. La vue Blade n'en affiche pas
/// davantage par entrée (`studio.blade.php` l.97-105 : libellé et pastille de
/// module, et le commentaire de la vue dit pourquoi elle n'y met ni
/// description ni décompte). Rien n'est donc fabriqué ici : une description
/// écrite côté client serait un second registre en face du registre fermé du
/// serveur (`DIRECTIVE_CONFORMITE_100.md` Article 10).
final class EtatCatalogue {
  const EtatCatalogue({
    required this.code,
    required this.module,
    required this.libelle,
    required this.niveau,
  });

  /// Le code stable du registre fermé du serveur. **Il fait partie du contrat
  /// d'API** : `CatalogueEtatsService::REGISTRE` interdit de le renommer sans
  /// versionner. C'est lui, jamais le libellé, qui désigne l'état.
  final String code;

  /// Le module **source** de l'état — celui qui porte le droit d'accès.
  ///
  /// Éditer l'état des stocks exige un droit sur M6, pas sur M14 : c'est
  /// pourquoi ce champ est central plutôt que décoratif.
  final String module;

  final String libelle;

  /// Le niveau RBAC de l'utilisateur **sur le module source** — celui de la
  /// session, lu par `GardeAcces` (la même fabrique que la voie serveur).
  final NiveauAcces niveau;
}

/// Les codes de module du catalogue, **dans l'ordre alphabétique** des
/// pastilles de filtre.
///
/// `pwa/etats/studio.blade.php` l.76 rend `$modules` tel que
/// `EtatsStudio::render()` le prépare : `array_unique(array_column(..))` puis
/// `sort($modules)` — un tri de chaînes (M1, M10, M11, M13, M3, M5, M6…). Ce
/// n'est PAS l'ordre du CdCF que suivait l'ancien registre `ModulesCatalogue`
/// (maître `prototype_v2`, archivé, PA-183), retiré le 09/10/2026 : il faisait
/// précéder M6 de M1/M3/M5 alors que la vue sert M10 avant M6. La vue gagne.
List<String> modulesDuCatalogue(List<EtatCatalogue> etats) =>
    <String>{for (final e in etats) e.module}.toList()..sort();

/// Le catalogue **groupé par module**, prêt à rendre.
///
/// Fonction pure : elle ne lit ni réseau ni base, et s'éprouve sans écran.
List<GroupeCatalogue> grouperParModule(List<EtatCatalogue> etats) {
  // `collect($liste)->groupBy('module')` (studio.blade.php l.87) : les groupes
  // gardent l'ORDRE D'APPARITION dans la réponse du serveur, pas un tri.
  // Un `Map` Dart est ordonné par insertion : c'est le même comportement.
  final parModule = <String, List<EtatCatalogue>>{};
  for (final e in etats) {
    (parModule[e.module] ??= <EtatCatalogue>[]).add(e);
  }

  return [
    for (final entree in parModule.entries)
      GroupeCatalogue(
        module: entree.key,
        // `{{ $codeModule }}` (l.89) : le CODE, sans libellé de module.
        enTete: entree.key,
        etats: entree.value,
      ),
  ];
}

final class GroupeCatalogue {
  const GroupeCatalogue({
    required this.module,
    required this.enTete,
    required this.etats,
  });

  final String module;
  final String enTete;
  final List<EtatCatalogue> etats;
}

/// Le filtre du catalogue : recherche libre et filtre de module.
///
/// Le maître cherche sur `libelle + description + module`
/// (`m14-etats-studio.js` l.66). La description n'existant pas ici, la
/// recherche porte sur le libellé et le module — l'écart est nommé à l'écran
/// avec le champ absent, pas dissimulé dans un comportement de recherche.
List<EtatCatalogue> filtrerCatalogue(
  List<EtatCatalogue> etats, {
  required String terme,
  required String? module,
}) {
  final t = terme.trim().toLowerCase();
  return [
    for (final e in etats)
      if ((module == null || e.module == module) &&
          (t.isEmpty || '${e.libelle} ${e.module}'.toLowerCase().contains(t)))
        e,
  ];
}
