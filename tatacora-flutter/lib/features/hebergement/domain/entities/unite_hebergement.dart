/// État **opérationnel** d'une unité — ce que le personnel constate sur place.
///
/// Ce n'est PAS la disponibilité. Une unité « réservée » pour le 20 août reste
/// réservable pour le 5 septembre : la disponibilité se calcule toujours sur
/// une période (RG-02). Confondre les deux interdirait toute réservation à
/// l'avance, ce qu'un gîte fait toute l'année.
enum StatutUnite {
  libre('libre'),
  occupee('occupee'),
  reservee('reservee'),
  nettoyage('nettoyage'),
  horsService('hors_service');

  const StatutUnite(this.code);

  /// Code stocké en base et échangé avec l'API — jamais l'index de l'enum,
  /// qui changerait au premier réordonnancement.
  final String code;

  /// Un code inconnu donne `horsService`, jamais `libre`.
  ///
  /// Le défaut le plus sûr est celui qui ne vend rien : proposer une unité
  /// dont on ne comprend pas l'état ferait vendre une chambre condamnée.
  static StatutUnite depuisCode(String? code) => values.firstWhere(
    (s) => s.code == code,
    orElse: () => StatutUnite.horsService,
  );

  /// Les états qui n'empêchent pas une réservation **future**.
  ///
  /// « nettoyage » en fait partie : une chambre en cours de ménage aujourd'hui
  /// est parfaitement louable la semaine prochaine.
  bool get estLouable => this != StatutUnite.horsService;
}

/// Une unité d'hébergement : bungalow, chambre ou tente.
///
/// L'entité ne porte **aucun champ de présentation** — pas de libellé
/// d'affichage prémâché, pas de couleur de badge. Une entité modelée sur la
/// maquette devient inutilisable dès le deuxième écran, et c'est la couche
/// présentation qui décide comment un statut se donne à voir.
final class UniteHebergement {
  const UniteHebergement({
    required this.id,
    required this.numero,
    required this.categorieId,
    required this.categorieLibelle,
    required this.statut,
    required this.tarifBase,
    required this.capaciteMax,
  });

  /// UUID v4 généré côté client à la création (offline-first).
  final String id;

  /// Identifiant métier lisible : `BNG-01`, `CH-101`.
  final String numero;

  final String categorieId;
  final String categorieLibelle;
  final StatutUnite statut;

  /// Tarif de base par nuit, en francs CFA.
  ///
  /// Le XOF n'a pas de sous-unité en circulation : un entier suffit, et il
  /// évite les surprises d'arrondi d'un `double` sur une addition de lignes.
  final int tarifBase;

  final int capaciteMax;

  UniteHebergement copyWith({StatutUnite? statut}) => UniteHebergement(
    id: id,
    numero: numero,
    categorieId: categorieId,
    categorieLibelle: categorieLibelle,
    statut: statut ?? this.statut,
    tarifBase: tarifBase,
    capaciteMax: capaciteMax,
  );

  @override
  bool operator ==(Object other) => other is UniteHebergement && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'UniteHebergement($numero, ${statut.code})';
}
