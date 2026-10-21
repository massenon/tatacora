import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../synchronisation/data/operations_sync_dao.dart';
import '../../synchronisation/domain/charges_synchronisation.dart';
import '../../synchronisation/domain/operation_sync.dart';
import '../domain/entities/conge_planning.dart';

/// Les PLANNINGS d'équipe et les CONGÉS (M13, EF-M13-02 / EF-M13-04) — le
/// **seul écrivain de saisie** de `plannings_local` et `conges_local`.
///
/// Vue Blade maîtresse (PA-183) : pwa/rh/conges-plannings.blade.php
///
/// Réplique de `PlanningService` et `CongeService` du serveur, refus dans
/// leur ordre et aux mêmes mots :
///
///  * **RG-13** — un employé n'est pas planifié deux fois sur le même créneau
///    d'un même jour (bornes adjacentes admises : 08-12 puis 12-16), ni pendant
///    un congé validé, ni s'il n'est plus en poste.
///  * **RG-14** — valider une demande exige le préavis et la couverture de
///    service paramétrés ; un paramètre absent REFUSE (jamais de valeur
///    devinée) ; DEMANDER est toujours accepté ; refuser garde la demande.
///
/// Chaque geste s'écrit et s'enfile dans UNE transaction (`OperationsSyncDao`,
/// seul écrivain de la file). Le serveur rejoue les mêmes règles avec SES
/// données : un refus de sa part rend la décision du poste « à traiter ».
///
/// ⚠ Les lectures des paramètres vivent ICI (`cleDelaiPreavis`,
/// `cleCouverture`) : c'est ce fichier que `registre_parametres_local.dart`
/// déclare comme leur lecteur.
///
/// @see EF-M13-02, EF-M13-04, RG-13, RG-14
class CongesPlanningsDao {
  CongesPlanningsDao(this._db, {Uuid? uuid, DateTime Function()? maintenant})
    : _uuid = uuid ?? const Uuid(),
      _maintenant = maintenant ?? DateTime.now;

  final AppDatabase _db;
  final Uuid _uuid;
  final DateTime Function() _maintenant;

  static const String cleDelaiPreavis = 'delai_preavis_conge_jours';
  static const String cleCouverture = 'couverture_minimale_par_service';

  OperationsSyncDao get _file => OperationsSyncDao(_db);

  /* ================================================================== */
  /* Lectures                                                            */
  /* ================================================================== */

  Future<List<ServicesRhLocalData>> _servicesBruts() => (_db.select(
    _db.servicesRhLocal,
  )..orderBy([(s) => OrderingTerm.asc(s.libelle)])).get();

  /// Les services proposés au filtre et au formulaire (par libellé).
  Future<List<({String id, String libelle})>> services() async => [
    for (final s in await _servicesBruts()) (id: s.id, libelle: s.libelle),
  ];

  /// Les employés EN POSTE (`actif` ou `conge`), par nom — ceux qu'on peut
  /// planifier ou à qui on peut poser un congé.
  Future<List<EmployePlanifiable>> employesEnPoste() async {
    final lignes =
        await (_db.select(_db.employesLocal)
              ..where((e) => e.statut.isIn(const ['actif', 'conge']))
              ..orderBy([(e) => OrderingTerm.asc(e.nom)]))
            .get();
    return [
      for (final e in lignes)
        EmployePlanifiable(id: e.id, nomComplet: _nomComplet(e.nom, e.prenom)),
    ];
  }

  /// Les créneaux d'un jour, par heure de début ; [serviceId] filtre.
  Future<List<CreneauPlanning>> creneaux({
    required DateTime jour,
    String? serviceId,
  }) async {
    final j = _minuit(jour);
    final requete = _db.select(_db.planningsLocal)
      ..where((p) => p.date.equals(j))
      ..orderBy([
        (p) => OrderingTerm.asc(p.heureDebut),
        (p) => OrderingTerm.asc(p.id),
      ]);
    if (serviceId != null && serviceId.isNotEmpty) {
      requete.where((p) => p.serviceId.equals(serviceId));
    }
    final lignes = await requete.get();
    final noms = await _nomsEmployes();
    final libelles = {for (final s in await _servicesBruts()) s.id: s.libelle};
    return [
      for (final p in lignes)
        CreneauPlanning(
          id: p.id,
          employeId: p.employeId,
          employeNom: noms[p.employeId] ?? '—',
          serviceId: p.serviceId,
          serviceLibelle: libelles[p.serviceId] ?? '—',
          date: _iso(p.date),
          heureDebut: p.heureDebut,
          heureFin: p.heureFin,
        ),
    ];
  }

  /// Les demandes de congé, la plus récente d'abord ; [statut] filtre.
  Future<List<DemandeConge>> conges({StatutConge? statut}) async {
    final requete = _db.select(_db.congesLocal)
      ..orderBy([
        (c) => OrderingTerm.desc(c.dateDebut),
        (c) => OrderingTerm.asc(c.id),
      ]);
    if (statut != null) {
      requete.where((c) => c.statutValidation.equals(statut.code));
    }
    final noms = await _nomsEmployes();
    final lignes = await requete.get();
    return [
      for (final c in lignes)
        if (TypeConge.depuisCode(c.type) case final type?)
          if (StatutConge.depuisCode(c.statutValidation) case final st?)
            DemandeConge(
              id: c.id,
              employeId: c.employeId,
              employeNom: noms[c.employeId] ?? '—',
              type: type,
              dateDebut: _iso(c.dateDebut),
              dateFin: _iso(c.dateFin),
              jours: _jours(c.dateDebut, c.dateFin),
              statut: st,
              validateur: c.validateur,
            ),
    ];
  }

  /// Combien d'employés sont en congé VALIDÉ ce jour (bornes incluses).
  Future<int> enCongeLe(DateTime jour) async {
    final j = _minuit(jour);
    final lignes =
        await (_db.select(_db.congesLocal)..where(
              (c) =>
                  c.statutValidation.equals(StatutConge.valide.code) &
                  c.dateDebut.isSmallerOrEqualValue(j) &
                  c.dateFin.isBiggerOrEqualValue(j),
            ))
            .get();
    return lignes.length;
  }

  /* ================================================================== */
  /* Planifier — RG-13                                                   */
  /* ================================================================== */

  /// Planifie un créneau. Refus dans l'ordre du serveur : employé inconnu ou
  /// hors effectif, congé validé ce jour-là, chevauchement.
  Future<CreneauPlanning> planifier({
    required String? employeId,
    required String? serviceId,
    required DateTime? date,
    required String heureDebut,
    required String heureFin,
  }) async {
    if (employeId == null || employeId.isEmpty) {
      throw const RefusCongesPlannings(MessagesCongesPlannings.employeRequis);
    }
    if (serviceId == null || serviceId.isEmpty) {
      throw const RefusCongesPlannings(MessagesCongesPlannings.serviceRequis);
    }
    if (date == null) {
      throw const RefusCongesPlannings(MessagesCongesPlannings.dateIllisible);
    }
    final debut = _heureNormalisee(heureDebut);
    final fin = _heureNormalisee(heureFin);
    if (debut == null || fin == null) {
      throw const RefusCongesPlannings(MessagesCongesPlannings.heureIllisible);
    }
    if (fin.compareTo(debut) <= 0) {
      throw const RefusCongesPlannings(
        MessagesCongesPlannings.heureFinAvantDebut,
      );
    }
    final jour = _minuit(date);

    return _db.transaction(() async {
      final employe = await (_db.select(
        _db.employesLocal,
      )..where((e) => e.id.equals(employeId))).getSingleOrNull();
      if (employe == null) {
        throw const RefusCongesPlannings(
          MessagesCongesPlannings.employeInconnu,
        );
      }
      final service = await (_db.select(
        _db.servicesRhLocal,
      )..where((s) => s.id.equals(serviceId))).getSingleOrNull();
      if (service == null) {
        throw const RefusCongesPlannings(
          MessagesCongesPlannings.serviceInconnu,
        );
      }
      if (employe.statut != 'actif' && employe.statut != 'conge') {
        throw RefusCongesPlannings(
          MessagesCongesPlannings.horsEffectif(employe.statut),
        );
      }

      // Un congé VALIDÉ couvre la date visée (bornes incluses).
      final enConge =
          await (_db.select(_db.congesLocal)..where(
                (c) =>
                    c.employeId.equals(employeId) &
                    c.statutValidation.equals(StatutConge.valide.code) &
                    c.dateDebut.isSmallerOrEqualValue(jour) &
                    c.dateFin.isBiggerOrEqualValue(jour),
              ))
              .get();
      if (enConge.isNotEmpty) {
        throw RefusCongesPlannings(MessagesCongesPlannings.enConge(_iso(jour)));
      }

      // RG-13 : même employé, même jour, plages qui se recouvrent. Une borne
      // commune n'est pas un recouvrement (08-12 puis 12-16).
      final memeJour =
          await (_db.select(_db.planningsLocal)..where(
                (p) => p.employeId.equals(employeId) & p.date.equals(jour),
              ))
              .get();
      final conflit = memeJour.any(
        (p) =>
            p.heureDebut.compareTo(fin) < 0 && p.heureFin.compareTo(debut) > 0,
      );
      if (conflit) {
        throw const RefusCongesPlannings(MessagesCongesPlannings.chevauchement);
      }

      final id = _uuid.v4();
      await _db
          .into(_db.planningsLocal)
          .insert(
            PlanningsLocalCompanion.insert(
              id: id,
              employeId: employeId,
              serviceId: serviceId,
              date: jour,
              heureDebut: debut,
              heureFin: fin,
            ),
          );
      await _file.enfiler(
        table: TableSynchronisee.plannings,
        entiteId: id,
        type: TypeOperationSync.creation,
        payload: chargePlanning(
          employeId: employeId,
          serviceId: await _serviceCoteServeur(serviceId),
          serviceLibelle: service.libelle,
          date: jour,
          heureDebut: debut,
          heureFin: fin,
        ),
      );

      return CreneauPlanning(
        id: id,
        employeId: employeId,
        employeNom: _nomComplet(employe.nom, employe.prenom),
        serviceId: serviceId,
        serviceLibelle: service.libelle,
        date: _iso(jour),
        heureDebut: debut,
        heureFin: fin,
      );
    });
  }

  /* ================================================================== */
  /* Congés — RG-14                                                      */
  /* ================================================================== */

  /// Dépose une demande — **toujours acceptée** (RG-14 porte sur la
  /// validation) pourvu que l'employé soit en poste.
  Future<DemandeConge> demander({
    required String? employeId,
    required TypeConge? type,
    required DateTime? dateDebut,
    required DateTime? dateFin,
  }) async {
    if (employeId == null || employeId.isEmpty) {
      throw const RefusCongesPlannings(MessagesCongesPlannings.employeRequis);
    }
    if (type == null) {
      throw const RefusCongesPlannings(MessagesCongesPlannings.typeInconnu);
    }
    if (dateDebut == null || dateFin == null) {
      throw const RefusCongesPlannings(MessagesCongesPlannings.dateIllisible);
    }
    final debut = _minuit(dateDebut);
    final fin = _minuit(dateFin);
    if (fin.isBefore(debut)) {
      throw const RefusCongesPlannings(MessagesCongesPlannings.finAvantDebut);
    }

    return _db.transaction(() async {
      final employe = await (_db.select(
        _db.employesLocal,
      )..where((e) => e.id.equals(employeId))).getSingleOrNull();
      if (employe == null) {
        throw const RefusCongesPlannings(
          MessagesCongesPlannings.employeInconnu,
        );
      }
      if (employe.statut != 'actif' && employe.statut != 'conge') {
        throw RefusCongesPlannings(
          MessagesCongesPlannings.horsEffectif(employe.statut),
        );
      }

      final id = _uuid.v4();
      await _db
          .into(_db.congesLocal)
          .insert(
            CongesLocalCompanion.insert(
              id: id,
              employeId: employeId,
              type: type.code,
              dateDebut: debut,
              dateFin: fin,
            ),
          );
      await _file.enfiler(
        table: TableSynchronisee.conges,
        entiteId: id,
        type: TypeOperationSync.creation,
        payload: chargeConge(
          employeId: employeId,
          type: type.code,
          dateDebut: debut,
          dateFin: fin,
        ),
      );

      return DemandeConge(
        id: id,
        employeId: employeId,
        employeNom: _nomComplet(employe.nom, employe.prenom),
        type: type,
        dateDebut: _iso(debut),
        dateFin: _iso(fin),
        jours: _jours(debut, fin),
        statut: StatutConge.enAttente,
      );
    });
  }

  /// Valide une demande — RG-14 : préavis PUIS couverture, paramétrés.
  ///
  /// Ordre du serveur : demande déjà décidée, paramètre de préavis (absent =
  /// refus), préavis réel, paramètre de couverture (absent = refus),
  /// couverture. [validateur] : le login de qui décide.
  Future<void> valider(String congeId, {required String? validateur}) =>
      _db.transaction(() async {
        final conge = await _demandeEnAttente(congeId);

        final exige = await _parametreObligatoire(cleDelaiPreavis);
        final reel = _joursEntre(_minuit(_maintenant()), conge.dateDebut);
        if (reel < exige.$1) {
          throw RefusCongesPlannings(
            MessagesCongesPlannings.preavisInsuffisant(
              reel: reel < 0 ? 0 : reel,
              exige: exige.$2,
            ),
          );
        }

        final minimum = await _parametreObligatoire(cleCouverture);
        final employe = await (_db.select(
          _db.employesLocal,
        )..where((e) => e.id.equals(conge.employeId))).getSingleOrNull();
        if (employe == null) {
          throw const RefusCongesPlannings(
            MessagesCongesPlannings.employeInconnu,
          );
        }
        final effectif =
            await (_db.select(_db.employesLocal)..where(
                  (e) =>
                      e.serviceId.equals(employe.serviceId) &
                      e.statut.equals('actif'),
                ))
                .get();
        // +1 : la demande en cours de validation compte parmi les absents.
        final absents =
            await _absentsSurPeriode(
              employe.serviceId,
              conge.dateDebut,
              conge.dateFin,
              exclureId: conge.id,
            ) +
            1;
        final restants = effectif.length - absents;
        if (restants < minimum.$1) {
          throw RefusCongesPlannings(
            MessagesCongesPlannings.couvertureInsuffisante(
              restants: restants < 0 ? 0 : restants,
              minimum: minimum.$2,
            ),
          );
        }

        await _decider(conge, StatutConge.valide, validateur);
      });

  /// Refuse une demande — elle est CONSERVÉE avec sa trace.
  Future<void> refuser(String congeId, {required String? validateur}) =>
      _db.transaction(() async {
        final conge = await _demandeEnAttente(congeId);
        await _decider(conge, StatutConge.refuse, validateur);
      });

  /* ================================================================== */
  /* Privé                                                               */
  /* ================================================================== */

  Future<CongeLigne> _demandeEnAttente(String id) async {
    final conge = await (_db.select(
      _db.congesLocal,
    )..where((c) => c.id.equals(id))).getSingleOrNull();
    if (conge == null) {
      throw const RefusCongesPlannings(MessagesCongesPlannings.demandeInconnue);
    }
    if (conge.statutValidation != StatutConge.enAttente.code) {
      throw const RefusCongesPlannings(MessagesCongesPlannings.dejaTraite);
    }
    return conge;
  }

  Future<void> _decider(
    CongeLigne conge,
    StatutConge decision,
    String? validateur,
  ) async {
    await (_db.update(
      _db.congesLocal,
    )..where((c) => c.id.equals(conge.id))).write(
      CongesLocalCompanion(
        statutValidation: Value(decision.code),
        validateur: Value(validateur),
      ),
    );
    await _file.enfiler(
      table: TableSynchronisee.conges,
      entiteId: conge.id,
      type: TypeOperationSync.modification,
      payload: chargeDecisionConge(valide: decision == StatutConge.valide),
    );
  }

  /// Employés distincts du service déjà absents (congé VALIDÉ) sur au moins un
  /// jour de la période — bornes incluses : un congé 10-12 et un autre 12-15
  /// se recoupent le 12.
  Future<int> _absentsSurPeriode(
    String serviceId,
    DateTime debut,
    DateTime fin, {
    required String exclureId,
  }) async {
    final membres = {
      for (final e in await (_db.select(
        _db.employesLocal,
      )..where((e) => e.serviceId.equals(serviceId))).get())
        e.id,
    };
    final lignes =
        await (_db.select(_db.congesLocal)..where(
              (c) =>
                  c.statutValidation.equals(StatutConge.valide.code) &
                  c.id.equals(exclureId).not() &
                  c.dateDebut.isSmallerOrEqualValue(fin) &
                  c.dateFin.isBiggerOrEqualValue(debut),
            ))
            .get();
    return {
      for (final c in lignes)
        if (membres.contains(c.employeId)) c.employeId,
    }.length;
  }

  /// Un paramètre ENTIER obligatoire : (valeur, texte tel que saisi). Absent ou
  /// illisible = refus, jamais une valeur devinée.
  Future<(int, String)> _parametreObligatoire(String cle) async {
    final ligne = await (_db.select(
      _db.parametresSystemeLocal,
    )..where((p) => p.cle.equals(cle))).getSingleOrNull();
    final brut = ligne?.valeur.trim() ?? '';
    final valeur = int.tryParse(brut);
    if (valeur == null) {
      throw RefusCongesPlannings(MessagesCongesPlannings.parametreAbsent(cle));
    }
    return (valeur, brut);
  }

  /// L'identifiant du service que le SERVEUR connaît : celui du poste s'il est
  /// semé des deux côtés (même id), sinon sa correspondance retenue par
  /// libellé à la descente ; à défaut, l'identifiant local (le serveur le
  /// reprend tel quel).
  Future<String> _serviceCoteServeur(String serviceLocal) async {
    final ligne = await _db
        .customSelect(
          'SELECT id_serveur FROM correspondances_sync_local '
          "WHERE table_serveur = 'services' AND id_local = ? LIMIT 1",
          variables: [Variable.withString(serviceLocal)],
          readsFrom: {_db.correspondancesSyncLocal},
        )
        .getSingleOrNull();
    return (ligne?.data['id_serveur'] as String?) ?? serviceLocal;
  }

  Future<Map<String, String>> _nomsEmployes() async => {
    for (final e in await _db.select(_db.employesLocal).get())
      e.id: _nomComplet(e.nom, e.prenom),
  };

  /// `nom` puis prénoms, comme `Employe::nomComplet()`.
  static String _nomComplet(String nom, String prenom) => '$nom $prenom'.trim();

  static DateTime _minuit(DateTime d) => DateTime(d.year, d.month, d.day);

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Jours entre deux minuits, SANS dérive d'heure d'été.
  static int _joursEntre(DateTime de, DateTime a) => DateTime.utc(
    a.year,
    a.month,
    a.day,
  ).difference(DateTime.utc(de.year, de.month, de.day)).inDays;

  /// Bornes incluses, comme `Conge::nombreJours()`.
  static int _jours(DateTime debut, DateTime fin) =>
      _joursEntre(debut, fin) + 1;

  static final RegExp _heure = RegExp(r'^([01]?\d|2[0-3]):([0-5]\d)$');

  /// `HH:MM` à deux chiffres, ou `null` si la saisie n'est pas une heure.
  static String? _heureNormalisee(String saisie) {
    final m = _heure.firstMatch(saisie.trim());
    if (m == null) return null;
    return '${m.group(1)!.padLeft(2, '0')}:${m.group(2)}';
  }
}
