/// Une prestation du catalogue — `circuits_local`.
///
/// Le maître nomme la ligne « Prestation » et la colonne « Type » y vaut
/// toujours « Circuit » : le schéma ne porte **aucun discriminant** entre un
/// circuit et une excursion (`pwa/tourisme/departs.blade.php` l.557, vérifié
/// le 14/09/2026 contre `CircuitsLocal` et contre `Circuit::$fillable`).
final class Circuit {
  const Circuit({
    required this.id,
    required this.nom,
    required this.theme,
    required this.zone,
    required this.prix,
    required this.capaciteMax,
    this.duree,
  });

  final String id;
  final String nom;
  final String theme;
  final String zone;

  /// Prix par personne, en **francs CFA entiers**.
  ///
  /// La table locale le porte en `REAL` ; la conversion a lieu au DAO, une
  /// fois, plutôt que de laisser un `double` remonter jusqu'aux additions de
  /// l'écran où il produirait un arrondi par ligne.
  final int prix;

  /// `circuits.capacite_max` — la capacité d'un départ. **Jamais saisie sur
  /// un départ** : elle vient de la fiche du circuit (EF-M9-04).
  final int capaciteMax;

  /// `circuits.duree` — un `varchar` **LIBRE** au serveur (PA-51) :
  /// « 3 heures », « 2 jours », « la journée ».
  ///
  /// **Lue depuis la v10 (14/09/2026).** `null` veut désormais dire ce qu'il
  /// dit au serveur : aucune durée n'est renseignée — et `dureeIndeterminee`
  /// la traite comme indéterminée. ⚠ Jusqu'à la v10, `null` signifiait
  /// « colonne absente » et aucun écran ne devait en conclure quoi que ce
  /// soit : ne rétablissez pas cette lecture.
  final String? duree;

  /// Le libellé de la colonne « Type » du maître — valeur unique et assumée.
  static const String type = 'Circuit';
}
