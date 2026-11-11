import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../synchronisation/data/operations_sync_dao.dart';
import '../../synchronisation/domain/charges_synchronisation.dart';
import '../../synchronisation/domain/operation_sync.dart';
import '../domain/immobilisations.dart';
import 'comptabilite_dao.dart';

/// Les IMMOBILISATIONS (M10) — le **seul écrivain de saisie** de
/// `immobilisations_local`.
///
/// Vue Blade maîtresse (PA-183) : pwa/comptabilite/hub.blade.php
///
/// Réplique de `ImmobilisationService::creer()` du serveur, refus dans son
/// ordre et aux mêmes mots : libellé obligatoire, valeur d'origine strictement
/// positive, durée d'utilité obligatoire (jamais un défaut), date de mise en
/// service valide, compte connu du plan. Un test relit les phrases dans
/// `lang/fr/comptabilite.php`, exécuté par PHP.
///
/// La création s'écrit et s'enfile dans UNE transaction (`OperationsSyncDao`,
/// seul écrivain de la file). Le CODE `IMMO-AAAA-NNNNN` est alloué ici (l'année
/// de la mise en service, comme la séquence du serveur) ; celui du serveur le
/// remplace à l'accusé ([regulariserCode]).
///
/// Écarts, nommés : la date doit être un jour RÉEL du calendrier (le serveur
/// n'en vérifie que la forme, et MySQL refuserait `2026-02-31` par une erreur
/// SQL sans phrase) ; la PWA borne la durée à 60 ans et le libellé à 255
/// caractères dans son formulaire (pas dans son service) — le poste les borne
/// au champ de saisie.
class ImmobilisationsDao {
  ImmobilisationsDao(this._db, {Uuid? uuid, this.auteur})
    : _uuid = uuid ?? const Uuid();

  final AppDatabase _db;
  final Uuid _uuid;

  /// Le login de qui saisit (`cree_par`), ou `null`.
  final String? auteur;

  OperationsSyncDao get _file => OperationsSyncDao(_db);

  /// Toutes les immobilisations, par code. Une ligne sans durée (qu'aucun
  /// écrivain n'écrit) est ignorée : son plan ne se calculerait pas.
  Future<List<Immobilisation>> toutes() async {
    final lignes = await (_db.select(
      _db.immobilisationsLocal,
    )..orderBy([(i) => OrderingTerm.asc(i.code)])).get();
    return [
      for (final l in lignes)
        if (l.dureeAnnees != null && l.dureeAnnees! > 0)
          Immobilisation(
            id: l.id,
            code: l.code,
            libelle: l.libelle,
            compteImmobilisation: l.compteImmobilisation,
            valeurOrigineCentimes: l.valeurOrigineCentimes,
            dateMiseService: l.dateMiseService,
            dureeAnnees: l.dureeAnnees!,
          ),
    ];
  }

  /// Crée une immobilisation. [valeurOrigineCentimes] `null` ou non positive,
  /// [dureeAnnees] `null` ou non positive, date illisible : refus aux phrases
  /// du serveur. Rien n'est écrit sur un refus.
  Future<Immobilisation> creer({
    required String libelle,
    required int? valeurOrigineCentimes,
    required int? dureeAnnees,
    required String dateMiseService,
    String? compteImmobilisation,
  }) async {
    final propre = libelle.trim();
    if (propre.isEmpty) {
      throw const RefusImmobilisation(MessagesImmobilisations.libelleRequis);
    }
    if (valeurOrigineCentimes == null || valeurOrigineCentimes <= 0) {
      throw const RefusImmobilisation(MessagesImmobilisations.valeurInvalide);
    }
    if (dureeAnnees == null || dureeAnnees <= 0) {
      throw const RefusImmobilisation(MessagesImmobilisations.dureeRequise);
    }
    final jour = dateMiseService.trim();
    if (!_jourReel(jour)) {
      throw const RefusImmobilisation(MessagesImmobilisations.dateInvalide);
    }
    final compte = (compteImmobilisation ?? '').isEmpty
        ? null
        : compteImmobilisation;

    final id = _uuid.v4();
    await _db.transaction(() async {
      if (compte != null) {
        final connu = await ComptabiliteDao(_db).compteParNumero(compte);
        if (connu == null) {
          throw RefusImmobilisation(
            MessagesImmobilisations.compteInconnu(compte),
          );
        }
      }
      await _db
          .into(_db.immobilisationsLocal)
          .insert(
            ImmobilisationsLocalCompanion.insert(
              id: id,
              code: await _codeSuivant(int.parse(jour.substring(0, 4))),
              libelle: propre,
              compteImmobilisation: Value(compte),
              valeurOrigineCentimes: valeurOrigineCentimes,
              dateMiseService: jour,
              dureeAnnees: Value(dureeAnnees),
              creePar: Value(auteur),
            ),
          );
      await _file.enfiler(
        table: TableSynchronisee.immobilisations,
        entiteId: id,
        type: TypeOperationSync.creation,
        payload: chargeImmobilisation(
          libelle: propre,
          compteImmobilisation: compte,
          valeurOrigineCentimes: valeurOrigineCentimes,
          dateMiseService: jour,
          dureeAnnees: dureeAnnees,
        ),
      );
    });

    return (await toutes()).firstWhere((i) => i.id == id);
  }

  /// Le CODE attribué par le serveur remplace celui du poste (réponse de
  /// l'envoi, ou descente).
  Future<void> regulariserCode(String id, String code) async {
    await (_db.update(_db.immobilisationsLocal)..where((i) => i.id.equals(id)))
        .write(ImmobilisationsLocalCompanion(code: Value(code)));
  }

  /// `IMMO-AAAA-NNNNN`, dans la transaction. Le rang est le SUFFIXE du plus
  /// grand code de l'année (`IMMO-2026-00042` lu en entier vaudrait 2026).
  Future<String> _codeSuivant(int annee) async {
    final motif = 'IMMO-$annee-';
    final dernier =
        await (_db.select(_db.immobilisationsLocal)
              ..where((i) => i.code.like('$motif%'))
              ..orderBy([(i) => OrderingTerm.desc(i.code)])
              ..limit(1))
            .getSingleOrNull();
    final rang = dernier == null
        ? 0
        : int.tryParse(dernier.code.substring(motif.length)) ?? 0;
    return '$motif${(rang + 1).toString().padLeft(5, '0')}';
  }

  static final RegExp _forme = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  /// Un `AAAA-MM-JJ` qui existe au calendrier.
  static bool _jourReel(String jour) {
    if (!_forme.hasMatch(jour)) return false;
    final a = int.parse(jour.substring(0, 4));
    final m = int.parse(jour.substring(5, 7));
    final j = int.parse(jour.substring(8, 10));
    final d = DateTime.utc(a, m, j);
    return d.year == a && d.month == m && d.day == j;
  }
}
