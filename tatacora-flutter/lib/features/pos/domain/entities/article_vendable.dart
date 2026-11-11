import 'reference_catalogue.dart';

/// Un article proposé au catalogue du point de vente.
///
/// ## Le prix est **nullable**, et ce n'est pas une commodité
///
/// Un article dont le tarif manque existe réellement au Gîte — le prototype en
/// affichait plusieurs, et l'écran les montre grisés plutôt que de les masquer :
/// les cacher laisserait croire qu'ils ne sont pas à la carte, alors que c'est
/// leur tarif qui manque, et c'est cela qu'il faut corriger.
///
/// Modéliser [prix] en `int?` fait exister le cas dans le type, donc dans les
/// tests. Un `int` non nullable l'aurait rendu inexprimable — et le garde-fou
/// « un montant deviné est une perte à chaque service » n'aurait plus jamais
/// été éprouvé.
final class ArticleVendable {
  const ArticleVendable({
    required this.reference,
    required this.libelle,
    required this.prix,
    this.categorie,
    this.detail,
    this.sansLienStock = false,
    this.compositionProvisoire = false,
  });

  /// Le point orange de la vue (`pos.html` l.488) : l'article est vendable
  /// mais ne décrémente aucun stock — un plat dont la fiche technique n'a aucun
  /// ingrédient. Les autres rayons ne le portent jamais (`lien_stock`).
  final bool sansLienStock;

  /// La marque « P » de la vue (`composition_provisoire`) : la fiche du plat est
  /// provisoire, le stock décrémenté est approximatif. Lue de
  /// `recettes_local.composition_provisoire` (v35, 21/10/2026) par le
  /// catalogue ; elle se lève depuis Restaurant & Cuisine, onglet « Fiches
  /// techniques » (réenregistrer la composition).
  final bool compositionProvisoire;

  /// ⚠ Q1 — voir `reference_catalogue.dart`.
  final ReferenceCatalogue reference;

  final String libelle;

  /// Prix de vente en francs CFA, `null` si le tarif n'est pas renseigné.
  final int? prix;

  /// Libellé de rayon, pour l'affichage.
  final String? categorie;

  /// Précision affichée sous le libellé (« Berline — par jour », « 2 jours »).
  final String? detail;

  bool get estVendable => prix != null;

  ModuleVendable get module => reference.module;

  @override
  bool operator ==(Object other) =>
      other is ArticleVendable && other.reference == reference;

  @override
  int get hashCode => reference.hashCode;
}

/// Un rayon du catalogue, tel que l'écran l'affiche.
///
/// Un rayon **vide reste visible** quand son catalogue n'est pas répliqué
/// localement, avec la raison. Un onglet qui ne rend jamais rien passe pour
/// cassé — c'est la leçon PA-90, et elle vaut ici pour le Restaurant, dont la
/// table `plats` est hors du périmètre offline.
final class RayonCatalogue {
  const RayonCatalogue({
    required this.module,
    required this.articles,
    this.indisponibiliteLocale,
  });

  final ModuleVendable module;
  final List<ArticleVendable> articles;

  /// Renseigné quand le rayon est vide **par construction**, pas par hasard.
  /// Affiché tel quel à l'utilisateur.
  final String? indisponibiliteLocale;

  String get libelle => module.libelle;
}
