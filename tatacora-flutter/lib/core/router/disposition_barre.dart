import '../theme/mesures_fenetre.dart';

/// Ce que la barre supérieure montre, pour une LARGEUR de fenêtre donnée.
///
/// La barre ne déborde jamais (de 320 à 2560 px) : elle replie ses éléments
/// par priorité, selon les seuils de [MesuresFenetre]. Une fonction pure de la
/// largeur, pour que le repli se prouve sans monter la coquille.
///
/// Jamais repliés : les trois boutons de fenêtre, le menu de compte et le
/// bouton de menu (ou la bascule du menu latéral).
final class DispositionBarre {
  const DispositionBarre({
    required this.compacte,
    required this.rechercheIcone,
    required this.caisseIcone,
    required this.exerciceReduit,
    required this.exerciceMasque,
    required this.venteIcone,
    required this.logoMasque,
    required this.synchroMasquee,
  });

  /// [avecBoutonsFenetre] : le poste porte ses boutons de fenêtre. La barre
  /// compacte (boutons de 32 px, identité du compte masquée) ne se conçoit
  /// qu'avec eux ; les autres replis ne dépendent que de la largeur.
  factory DispositionBarre.pour(
    double largeur, {
    required bool avecBoutonsFenetre,
  }) => DispositionBarre(
    compacte: avecBoutonsFenetre && largeur < MesuresFenetre.seuilBarreCompacte,
    rechercheIcone: largeur < MesuresFenetre.seuilRechercheIcone,
    caisseIcone: largeur < MesuresFenetre.seuilCaisseIcone,
    exerciceReduit: largeur < MesuresFenetre.seuilExerciceReduit,
    exerciceMasque: largeur < MesuresFenetre.seuilExerciceMasque,
    venteIcone: largeur < MesuresFenetre.seuilVenteIcone,
    logoMasque: largeur < MesuresFenetre.seuilLogoMasque,
    synchroMasquee: largeur < MesuresFenetre.seuilSynchroMasquee,
  );

  /// Boutons de 32 px et identité (login, rôle) masquée.
  final bool compacte;

  /// La recherche globale n'est qu'une icône.
  final bool rechercheIcone;

  /// L'indicateur de caisse n'est que sa pastille.
  final bool caisseIcone;

  /// Le sélecteur d'exercice n'a que sa liste.
  final bool exerciceReduit;

  /// Le sélecteur d'exercice est masqué (sous le minimum du poste).
  final bool exerciceMasque;

  /// « Vente » n'est que son icône.
  final bool venteIcone;

  /// Le logo est masqué.
  final bool logoMasque;

  /// Le bouton de synchronisation est masqué.
  final bool synchroMasquee;
}
