import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../domain/descente_catalogue.dart';
import '../domain/operation_sync.dart';
import 'operations_sync_dao.dart';

/// L'état de la DESCENTE du catalogue (lot F2b, schéma v27) : curseur,
/// repli, éléments gardés pour une reprise, bilan, et correspondances
/// d'identifiants.
///
/// Seul auteur de `correspondances_sync_local` et des clés `descente.*` et
/// `element_differe:*` de `etat_synchronisation_local` (les clés
/// `operation_remplacee:*` appartiennent à `OperationsSyncDao.renvoyer`).
/// N'écrit RIEN dans la file d'envoi : ce qui descend du serveur n'y
/// remonte jamais.
class DescenteCatalogueDao extends DatabaseAccessor<AppDatabase> {
  DescenteCatalogueDao(super.db, {DateTime Function()? maintenant})
    : _maintenant = maintenant ?? DateTime.now;

  final DateTime Function() _maintenant;

  static const cleCurseur = 'descente.curseur';
  static const cleDerniere = 'descente.derniere';
  static const cleEchecs = 'descente.echecs';
  static const cleProchaineTentative = 'descente.prochaine_tentative';
  static const prefixeDiffere = 'element_differe:';

  $EtatSynchronisationLocalTable get _etat =>
      attachedDatabase.etatSynchronisationLocal;
  $CorrespondancesSyncLocalTable get _correspondances =>
      attachedDatabase.correspondancesSyncLocal;

  /* ================================================================== */
  /* Clé / valeur                                                        */
  /* ================================================================== */

  Future<String?> _lire(String cle) async => (await (select(
    _etat,
  )..where((e) => e.cle.equals(cle))).getSingleOrNull())?.valeur;

  Future<void> _ecrire(String cle, String valeur) =>
      into(_etat).insertOnConflictUpdate(
        EtatSynchronisationLocalCompanion.insert(
          cle: cle,
          valeur: valeur,
          modifieLe: _maintenant(),
        ),
      );

  Future<void> _effacer(String cle) =>
      (delete(_etat)..where((e) => e.cle.equals(cle))).go();

  /// Le curseur OPAQUE du serveur, ou `null` (depuis le début).
  Future<String?> curseur() => _lire(cleCurseur);

  /// Pose le curseur. Appelé DANS la transaction de la page, après
  /// l'application de ses éléments : un arrêt au milieu d'une page la
  /// rejoue entière, sans rien perdre ni doubler (écritures idempotentes).
  Future<void> poserCurseur(String curseur) => _ecrire(cleCurseur, curseur);

  /// Oublie le curseur (le serveur l'a déclaré illisible) : la descente
  /// suivante repart du début, sans dommage — chaque écriture est un
  /// alignement idempotent.
  Future<void> effacerCurseur() => _effacer(cleCurseur);

  /// Le repli PROPRE à la descente : nombre d'échecs consécutifs et
  /// prochaine tentative. Distinct de celui de la file : une descente en
  /// échec ne retarde jamais un envoi.
  Future<({int echecs, DateTime? prochaine})> repli() async {
    final echecs = int.tryParse(await _lire(cleEchecs) ?? '') ?? 0;
    final brut = await _lire(cleProchaineTentative);
    return (
      echecs: echecs,
      prochaine: brut == null ? null : DateTime.tryParse(brut)?.toLocal(),
    );
  }

  Future<void> poserRepli({required int echecs, DateTime? prochaine}) async {
    await _ecrire(cleEchecs, '$echecs');
    if (prochaine == null) {
      await _effacer(cleProchaineTentative);
    } else {
      await _ecrire(cleProchaineTentative, prochaine.toUtc().toIso8601String());
    }
  }

  /// Retient le bilan de la dernière descente TENTÉE — l'écran le relit
  /// après un redémarrage.
  Future<void> consignerBilan(BilanDescente bilan) =>
      _ecrire(cleDerniere, jsonEncode(bilan.versJson()));

  Future<BilanDescente?> derniereDescente() async {
    final brut = await _lire(cleDerniere);
    if (brut == null) return null;
    try {
      return BilanDescente.depuisJson(jsonDecode(brut));
    } on FormatException {
      return null;
    }
  }

  /* ================================================================== */
  /* Éléments gardés pour une reprise                                    */
  /* ================================================================== */

  /// Garde [element] pour la reprise : [nature] `dependance` (un élément
  /// qu'il cite manque) ou `conserve` (modification locale non poussée).
  /// Une version plus récente du même élément remplace la précédente.
  Future<void> garder(
    ElementCatalogue element, {
    required String nature,
    required String motif,
  }) => _ecrire(
    '$prefixeDiffere${element.table.nomServeur}:${element.id}',
    jsonEncode({
      'nature': nature,
      'motif': motif,
      'element': element.versJson(),
    }),
  );

  /// L'élément n'est plus à reprendre (appliqué, refusé, ou remplacé).
  Future<void> oublier(TableDescendue table, String id) =>
      _effacer('$prefixeDiffere${table.nomServeur}:$id');

  /// Les éléments gardés, dans l'ordre des tables du serveur (un élément
  /// cité avant celui qui le cite).
  Future<List<({ElementCatalogue element, String nature, String motif})>>
  elementsGardes() async {
    final lignes =
        await (select(_etat)
              ..where((e) => e.cle.like('$prefixeDiffere%'))
              ..orderBy([(e) => OrderingTerm.asc(e.modifieLe)]))
            .get();
    final gardes =
        <({ElementCatalogue element, String nature, String motif})>[];
    for (final l in lignes) {
      Object? brut;
      try {
        brut = jsonDecode(l.valeur);
      } on FormatException {
        continue;
      }
      if (brut is! Map) continue;
      final e = ElementCatalogue.depuisJson(brut['element']);
      if (e == null) continue;
      gardes.add((
        element: e,
        nature: brut['nature'] is String ? brut['nature']! as String : '',
        motif: brut['motif'] is String ? brut['motif']! as String : '',
      ));
    }
    gardes.sort(
      (a, b) => a.element.table.index.compareTo(b.element.table.index),
    );
    return gardes;
  }

  /* ================================================================== */
  /* Correspondances                                                     */
  /* ================================================================== */

  /// Retient que l'élément serveur [idServeur] de [table] est, ici, la
  /// ligne [idLocal]. Une correspondance identique est sans effet ; une
  /// correspondance contraire est REMPLACÉE (la plus récente fait foi).
  Future<void> retenirCorrespondance({
    required String table,
    required String idServeur,
    required String idLocal,
    required String origine,
  }) async {
    if (idServeur == idLocal) return;
    await into(_correspondances).insertOnConflictUpdate(
      CorrespondancesSyncLocalCompanion.insert(
        tableServeur: table,
        idServeur: idServeur,
        idLocal: idLocal,
        origine: origine,
        creeLe: _maintenant(),
      ),
    );
  }

  /// L'identifiant LOCAL de l'élément serveur [idServeur] : sa
  /// correspondance, sinon lui-même (cas nominal : l'élément porte le même
  /// identifiant partout).
  Future<String> idLocal(String table, String idServeur) async {
    final ligne =
        await (select(_correspondances)..where(
              (c) =>
                  c.tableServeur.equals(table) & c.idServeur.equals(idServeur),
            ))
            .getSingleOrNull();
    return ligne?.idLocal ?? idServeur;
  }

  /// Les correspondances retenues (lecture des tests et de l'écran).
  Future<List<CorrespondanceSyncLigne>> correspondances() =>
      select(_correspondances).get();

  /// Le compte local qui porte une création descendue (`cree_par`) quand
  /// aucune session n'est ouverte : le plus ancien ADMINISTRATEUR actif, à
  /// défaut le plus ancien compte actif ; `null` sur un poste sans compte.
  /// Voir `AligneurCatalogue` (écart nommé : l'auteur de l'écriture sur ce
  /// poste, pas celui de la fiche au serveur).
  Future<String?> auteurParDefaut() async {
    final r = await customSelect(
      'SELECT id FROM utilisateurs_local WHERE actif = 1 '
      "ORDER BY CASE WHEN lower(role) IN ('administrateur', 'super_admin') "
      'THEN 0 ELSE 1 END, date_creation ASC LIMIT 1',
      readsFrom: {attachedDatabase.utilisateursLocal},
    ).getSingleOrNull();
    return r?.data['id'] as String?;
  }

  /// Retient les FUSIONS déjà rendues par le serveur à l'envoi
  /// (`fusionne_avec`, consigné par `OperationsSyncDao.marquerResultat`) :
  /// un élément du poste fusionné sur un élément serveur ne doit pas
  /// redescendre en DOUBLON sous l'identifiant serveur, même quand le flux
  /// des correspondances n'est pas encore arrivé (il vient en fin de
  /// catalogue). Rend le nombre de correspondances lues.
  Future<int> retenirFusionsDeLaFile() async {
    final ops = await OperationsSyncDao(
      attachedDatabase,
    ).operations(statut: StatutOperationSync.synchronise);
    var n = 0;
    for (final o in ops) {
      final idServeur = o.idServeur;
      if (idServeur == null || idServeur == o.entiteId) continue;
      if (TableDescendue.depuisNom(o.table.nomServeur) == null) continue;
      await retenirCorrespondance(
        table: o.table.nomServeur,
        idServeur: idServeur,
        idLocal: o.entiteId,
        origine: 'file',
      );
      n++;
    }
    return n;
  }
}
