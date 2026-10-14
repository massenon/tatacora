import 'package:drift/drift.dart';

/// Le référentiel des tables de salle — porté de `tables-engine.js`.
///
/// ## Le défaut que cette table corrige
///
/// La table était un **champ de texte libre** au point de vente. Trois
/// conséquences, et la troisième est celle qui coûte :
///
///   1. « T3 », « t3 », « Table 3 » et « table3 » désignaient quatre tables
///      différentes pour le logiciel. Aucun regroupement n'était fiable ;
///   2. rien ne permettait de savoir quelles tables **existent**, donc rien ne
///      pouvait dire lesquelles sont **occupées** ;
///   3. le CdCF interdit le texte libre là où une clé étrangère est due —
///      c'est l'anti-patron n° 2 relevé sur le prototype d'origine.
///
/// ## L'occupation n'est PAS une colonne, et ne doit jamais le devenir
///
/// Elle se **déduit** des paniers ouverts. Un drapeau `occupee` posé à la main
/// se désynchroniserait au premier panier clôturé depuis un autre écran, et la
/// salle afficherait des tables occupées qui sont libres depuis une heure.
/// C'est exactement la famille de défauts de PA-59/60/61 : un indicateur qui
/// affirme un état qu'il n'a pas vérifié.
class TablesLocal extends Table {
  /// UUID posé côté client, comme partout ailleurs.
  TextColumn get id => text()();

  /// Le code d'un [EspacePos] — `restaurant`, `jardin`, `plage`.
  ///
  /// Jamais `comptoir` : le comptoir ne comporte pas de table. La garde vit
  /// dans le DAO, qui refuse la création.
  TextColumn get espace => text()();

  IntColumn get numero => integer()();

  /// `T3`, `J2`, `P1`. **Dérivé** du préfixe et du numéro à l'écriture, jamais
  /// saisi : un libellé figé donnerait une table « T3 » portant le numéro 5.
  TextColumn get libelle => text()();

  IntColumn get places => integer().withDefault(const Constant(4))();

  /// Désactivée, **jamais supprimée**.
  ///
  /// Une table supprimée laisserait les ventes passées pointer vers un
  /// identifiant inexistant, et l'analyse par table perdrait son historique.
  /// C'est la règle du dépôt : supprimer, c'est archiver.
  BoolColumn get actif => boolean().withDefault(const Constant(true))();

  DateTimeColumn get creeLe => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};

  /// Deux tables ne portent pas le même numéro dans le même espace — sans quoi
  /// « T3 » désignerait deux endroits, et l'addition partirait au mauvais.
  @override
  List<Set<Column>> get uniqueKeys => [
    {espace, numero},
  ];
}
