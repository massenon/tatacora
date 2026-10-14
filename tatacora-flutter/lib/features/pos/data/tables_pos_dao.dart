import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/tables/panier_tables.dart';
import '../../../core/database/tables/tables_pos_table.dart';
import '../domain/entities/espace_pos.dart';
import '../domain/entities/table_pos.dart';

part 'tables_pos_dao.g.dart';

/// Le référentiel des tables de salle — porté de `tables-engine.js`.
///
/// ## L'occupation se DÉDUIT, elle ne se stocke pas
///
/// Aucune colonne `occupee` n'existe, et il ne faut jamais en ajouter. Un
/// drapeau posé à la main se désynchroniserait au premier panier clôturé
/// depuis un autre écran, et la salle afficherait des tables occupées qui sont
/// libres depuis une heure — un indicateur qui affirme un état qu'il n'a pas
/// vérifié (PA-59/60/61).
///
/// Ici, une table est occupée **si et seulement si** un panier ouvert la
/// désigne. Clôturer suffit donc à la libérer : aucun drapeau à remettre à
/// zéro, donc aucun à oublier.
@DriftAccessor(tables: [TablesLocal, PaniersLocal])
class TablesPosDao extends DatabaseAccessor<AppDatabase>
    with _$TablesPosDaoMixin {
  TablesPosDao(super.db);

  static const _uuid = Uuid();

  /// Le jeu initial : six tables au restaurant, quatre au jardin, trois à la
  /// plage.
  ///
  /// Ce sont des valeurs de **démarrage**, pas une vérité : l'exploitant les
  /// ajuste depuis Paramètres au premier jour. Les poser évite un poste livré
  /// sans aucune table, où il faudrait en créer treize avant la première
  /// vente.
  ///
  /// **Semé ici et non dans la migration**, délibérément : une migration ne se
  /// rejoue pas, et un poste dont l'exploitant a supprimé des tables les
  /// verrait revenir à la mise à jour suivante.
  static const jeuInitial = {
    EspacePos.restaurant: 6,
    EspacePos.jardin: 4,
    EspacePos.plage: 3,
  };

  /// Toutes les tables, en semant le jeu initial **si et seulement si** la
  /// table est vide.
  ///
  /// Le contrôle porte sur le vide total et non sur un espace : un exploitant
  /// qui ferme la plage pour la saison ne doit pas la voir repeuplée au
  /// prochain démarrage.
  Future<List<TablePos>> toutes() async {
    final lignes = await select(tablesLocal).get();
    if (lignes.isEmpty) return semerJeuInitial();
    return lignes.map(_versDomaine).toList()..sort(_ordre);
  }

  Future<List<TablePos>> semerJeuInitial() async {
    await batch((b) {
      for (final entree in jeuInitial.entries) {
        for (var i = 1; i <= entree.value; i++) {
          b.insert(
            tablesLocal,
            TablesLocalCompanion.insert(
              id: _uuid.v4(),
              espace: entree.key.code,
              numero: i,
              libelle: '${entree.key.prefixe}$i',
            ),
          );
        }
      }
    });
    return (await select(tablesLocal).get()).map(_versDomaine).toList()
      ..sort(_ordre);
  }

  /// Les libellés des tables, par identifiant — **sans jamais semer**.
  ///
  /// [toutes] sème le jeu initial quand le référentiel est vide, et c'est ce
  /// qu'il faut au point de vente. Une **lecture** ne doit rien écrire : le
  /// journal des ventes appelle ceci pour afficher la table d'une vente
  /// passée, et créer treize tables au premier affichage d'un journal vide
  /// serait un effet de bord que personne n'attend.
  ///
  /// Une table inconnue rend simplement une entrée absente : la vente
  /// s'affiche alors sans table plutôt que de disparaître.
  Future<Map<String, String>> libelles() async => {
    for (final t in await select(tablesLocal).get()) t.id: t.libelle,
  };

  /// L'état de la salle, espace par espace — ce que le panneau affiche.
  ///
  /// [inclureFermees] montre aussi les tables désactivées. Le point de vente
  /// les affiche **barrées plutôt que masquées** : une table absente de
  /// l'écran laisse croire qu'elle n'existe pas, et un serveur la cherche.
  Future<List<RayonSalle>> salle({bool inclureFermees = false}) async {
    final tables = await toutes();

    // Un seul passage sur les paniers ouverts, plutôt qu'une requête par
    // table : la salle se redessine à chaque ajout au panier.
    final ouverts = await (select(
      paniersLocal,
    )..where((p) => p.statut.equals('ouvert') & p.tableId.isNotNull())).get();
    final parTable = {for (final p in ouverts) p.tableId!: p.id};

    return [
      for (final espace in EspacePos.avecTablesSeulement)
        RayonSalle(
          espace: espace,
          cases: [
            for (final t in tables.where(
              (t) => t.espace == espace && (inclureFermees || t.actif),
            ))
              CaseSalle(table: t, panierOuvertId: parTable[t.id]),
          ],
        ),
    ];
  }

  Future<bool> estOccupee(String tableId) async {
    final n =
        await (select(paniersLocal)..where(
              (p) => p.statut.equals('ouvert') & p.tableId.equals(tableId),
            ))
            .get();
    return n.isNotEmpty;
  }

  /// Le panier ouvert d'une table, s'il y en a un.
  ///
  /// C'est ce qui fait que rouvrir une table **retrouve son panier** au lieu
  /// d'en créer un second : deux paniers sur une table scinderaient l'addition,
  /// et la moitié manquerait au départ du client.
  Future<String?> panierOuvertDe(String tableId) async {
    final p =
        await (select(paniersLocal)..where(
              (p) => p.statut.equals('ouvert') & p.tableId.equals(tableId),
            ))
            .getSingleOrNull();
    return p?.id;
  }

  Future<TablePos> creer({
    required EspacePos espace,
    required int numero,
    int places = 4,
  }) async {
    if (!espace.avecTables) {
      throw ArgumentError.value(
        espace.code,
        'espace',
        'Le comptoir ne comporte pas de table.',
      );
    }
    if (numero < 1) {
      throw ArgumentError.value(
        numero,
        'numero',
        'Le numéro de table doit être un entier positif.',
      );
    }

    final ligne = TablesLocalCompanion.insert(
      id: _uuid.v4(),
      espace: espace.code,
      numero: numero,
      // Le libellé SUIT le numéro, il ne se saisit pas.
      libelle: '${espace.prefixe}$numero',
      places: Value(places),
    );
    await into(tablesLocal).insert(ligne);
    return _versDomaine(
      await (select(
        tablesLocal,
      )..where((t) => t.id.equals(ligne.id.value))).getSingle(),
    );
  }

  /// Renumérote une table — « Renuméroter » de Paramètres › Espaces & tables.
  /// Le libellé SUIT le numéro (`table_aide_renumerotation`). Un numéro déjà
  /// porté par une autre table du même espace est refusé : la contrainte
  /// d'unicité (espace, numéro) lèverait de toute façon, avec un message
  /// technique.
  Future<TablePos> renumeroter(String id, int numero) async {
    if (numero < 1) {
      throw ArgumentError.value(
        numero,
        'numero',
        'Le numéro de table doit être un entier positif.',
      );
    }
    return transaction(() async {
      final ligne = await (select(
        tablesLocal,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (ligne == null) {
        throw ArgumentError.value(id, 'id', 'Table introuvable.');
      }
      final espace = EspacePos.parCode(ligne.espace);
      final homonyme =
          await (select(tablesLocal)..where(
                (t) =>
                    t.espace.equals(ligne.espace) &
                    t.numero.equals(numero) &
                    t.id.equals(id).not(),
              ))
              .getSingleOrNull();
      if (homonyme != null) {
        throw ArgumentError.value(
          numero,
          'numero',
          'La table ${espace.prefixe}$numero existe déjà dans cet espace.',
        );
      }
      await (update(tablesLocal)..where((t) => t.id.equals(id))).write(
        TablesLocalCompanion(
          numero: Value(numero),
          libelle: Value('${espace.prefixe}$numero'),
        ),
      );
      return _versDomaine(
        await (select(tablesLocal)..where((t) => t.id.equals(id))).getSingle(),
      );
    });
  }

  /// Active ou désactive. **Jamais de suppression.**
  ///
  /// Et une table dont le panier est **ouvert** ne se désactive pas : les
  /// consommations servies n'auraient plus de table pour les porter jusqu'à
  /// l'addition.
  Future<TablePos> basculer(String id) async {
    final ligne = await (select(
      tablesLocal,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (ligne == null) {
      throw ArgumentError.value(id, 'id', 'Table introuvable.');
    }

    if (ligne.actif && await estOccupee(id)) {
      throw TableOccupee(ligne.libelle);
    }

    await (update(tablesLocal)..where((t) => t.id.equals(id))).write(
      TablesLocalCompanion(actif: Value(!ligne.actif)),
    );

    return _versDomaine(
      await (select(tablesLocal)..where((t) => t.id.equals(id))).getSingle(),
    );
  }

  TablePos _versDomaine(TablesLocalData d) => TablePos(
    id: d.id,
    espace: EspacePos.parCode(d.espace),
    numero: d.numero,
    libelle: d.libelle,
    places: d.places,
    actif: d.actif,
  );

  static int _ordre(TablePos a, TablePos b) {
    final e = a.espace.index.compareTo(b.espace.index);
    return e != 0 ? e : a.numero.compareTo(b.numero);
  }
}

/// Refus de désactiver une table servie.
final class TableOccupee implements Exception {
  const TableOccupee(this.libelle);

  final String libelle;

  @override
  String toString() =>
      'La table $libelle porte un panier ouvert. '
      'Encaissez l’addition avant de la désactiver.';
}
