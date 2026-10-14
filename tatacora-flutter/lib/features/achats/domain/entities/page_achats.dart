/// Une page d'une liste de M7, avec le total que le FILTRE retient.
///
/// Sans [total], une page pleine se lirait comme « c'est tout », et un acheteur
/// conclurait à l'absence d'une commande qui se trouve à la page suivante. Les
/// compteurs de la bande d'indicateurs se lisent d'ailleurs **ailleurs** (un
/// décompte par statut) — jamais en additionnant ce qu'une page montre.
library;

final class PageAchats<T> {
  const PageAchats({
    required this.elements,
    required this.total,
    required this.derniere,
  });

  final List<T> elements;
  final int total;

  /// Le numéro de la dernière page, pour que l'écran puisse dire ce qu'il ne
  /// montre pas.
  final int derniere;

  bool get estPartielle => elements.length < total;
}
