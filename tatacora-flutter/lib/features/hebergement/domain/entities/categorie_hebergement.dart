/// Une catégorie du parc : Bungalow, Chambre simple, Suite, Tente…
///
/// Vue Blade maîtresse (PA-183) : pwa/hebergement/hebergement.blade.php
///
/// ## Le modèle est celui du Product Owner (01/09/2026)
///
/// La vue l'écrit en toutes lettres dans le commentaire de sa modale
/// (`formulaire-unite`, l.567-571) : « la catégorie porte le type (Bungalow,
/// Chambre simple, Suite…), le tarif et la capacité ; l'hébergement porte son
/// libellé ». C'est pour cela que le tarif ne vit pas sur l'unité — deux
/// bungalows identiques ne se vendent pas à deux prix — et c'est aussi
/// pourquoi une unité sans catégorie n'a pas de tarif du tout : le composant
/// Livewire rend alors un tiret plutôt qu'un montant (l.238).
///
/// ## Le tarif est un ENTIER ici, un `REAL` au schéma
///
/// Le XOF n'a pas de sous-unité en circulation. La conversion est faite **au
/// DAO**, une fois, comme pour [UniteHebergement.tarifBase] : imposer un
/// `double` au domaine finirait par produire un arrondi sur une addition de
/// lignes.
library;

final class CategorieHebergement {
  const CategorieHebergement({
    required this.id,
    required this.libelle,
    required this.capaciteMax,
    required this.tarifBase,
  });

  /// UUID v4 posé côté client à la création — jamais un auto-incrément.
  final String id;

  /// Le type, tel qu'il est saisi : « Bungalow », « Chambre simple »…
  final String libelle;

  /// Nombre de personnes que l'unité peut recevoir.
  final int capaciteMax;

  /// Tarif de base par nuit, en francs CFA.
  final int tarifBase;

  CategorieHebergement copyWith({
    String? libelle,
    int? capaciteMax,
    int? tarifBase,
  }) => CategorieHebergement(
    id: id,
    libelle: libelle ?? this.libelle,
    capaciteMax: capaciteMax ?? this.capaciteMax,
    tarifBase: tarifBase ?? this.tarifBase,
  );

  @override
  bool operator ==(Object other) =>
      other is CategorieHebergement && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'CategorieHebergement($libelle, $tarifBase F)';
}
