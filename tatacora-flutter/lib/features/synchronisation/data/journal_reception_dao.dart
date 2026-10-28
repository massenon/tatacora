import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../domain/descente_catalogue.dart';
import '../domain/journal_reception.dart';

/// Ce que le journal compte, par issue.
final class CompteursReception {
  const CompteursReception({
    this.aligne = 0,
    this.conserve = 0,
    this.enAttente = 0,
    this.refuse = 0,
  });

  final int aligne;
  final int conserve;
  final int enAttente;
  final int refuse;

  /// Tous les éléments reçus que le journal retient.
  int get recus => aligne + conserve + enAttente + refuse;

  /// Ce qui reste à traiter : conservés, en attente, refusés.
  int get aTraiter => conserve + enAttente + refuse;

  int de(IssueReception i) => switch (i) {
    IssueReception.aligne => aligne,
    IssueReception.conserve => conserve,
    IssueReception.enAttente => enAttente,
    IssueReception.refuse => refuse,
  };
}

/// Le SEUL auteur de `journal_reception_local` (schéma v37, 26/10/2026) —
/// appelé par `DescenteCatalogue`, jamais par l'aligneur ni par la file
/// d'envoi. N'enfile RIEN : ce qui descend du serveur n'y remonte jamais.
///
/// ## Une ligne par élément, mise à jour à chaque tentative
///
/// [consigner] écrit l'issue du DERNIER alignement. Une nouvelle version du
/// même élément (autre `modifie_le`) repart à une tentative et à une nouvelle
/// date de réception ; la même version rejouée (reprise, relance) ajoute une
/// tentative. L'élément lui-même n'est gardé que tant qu'il reste à traiter.
///
/// ## Rétention bornée
///
/// [purger] : les éléments alignés de plus de [joursRetention] jours partent,
/// puis, au-delà de [lignesMax] lignes, les alignés les plus anciens d'abord
/// (et, s'il n'y en a plus, les plus anciennes lignes).
class JournalReceptionDao extends DatabaseAccessor<AppDatabase> {
  JournalReceptionDao(super.db, {DateTime Function()? maintenant})
    : _maintenant = maintenant ?? DateTime.now;

  final DateTime Function() _maintenant;

  /// Les éléments alignés se gardent 30 jours.
  static const int joursRetention = 30;

  /// Le journal ne dépasse jamais 5 000 lignes.
  static const int lignesMax = 5000;

  $JournalReceptionLocalTable get _journal =>
      attachedDatabase.journalReceptionLocal;

  /// Consigne l'issue de [element]. [note] remplace le motif d'un élément
  /// aligné qui mérite une précision (archive non portée, version périmée).
  /// [tentative] `false` : cette écriture n'ajoute pas de tentative (le même
  /// élément vient d'être consigné dans la même descente).
  /// [seulementSiChange] : la reprise AUTOMATIQUE d'un élément gardé n'écrit
  /// rien si la même version a la même issue et le même motif (sans cela,
  /// chaque réveil de cinq minutes gonflerait les tentatives).
  Future<void> consigner(
    ElementCatalogue element,
    IssueAlignement issue, {
    String? note,
    bool tentative = true,
    bool seulementSiChange = false,
  }) async {
    final genre = IssueReception.depuis(issue);
    final motif = switch (issue) {
      Aligne(:final archiveNonPortee) =>
        note ??
            (archiveNonPortee
                ? 'Archivé au serveur ; ce poste n’a pas d’archive pour cet '
                      'élément, il reste proposé.'
                : ''),
      ConserveLocalement(:final raison) => raison,
      EnAttenteDeDependance(:final motif) => motif,
      RefuseParLePoste(:final motif) => motif,
    };
    final a = analyserMotif(genre, motif);
    await _ecrire(
      table: element.table.nomServeur,
      id: element.id,
      modifieLe: element.modifieLe,
      issue: genre,
      cause: a.cause,
      motif: motif,
      champ: a.champ,
      dependance: a.dependance,
      etiquette: element.supprime
          ? 'Purge définitive'
          : etiquetteElement(element.donnees),
      posteOrigine: element.posteOrigine,
      elementJson: genre.ouverte ? element.encoder() : null,
      tentative: tentative,
      seulementSiChange: seulementSiChange,
    );
  }

  /// Consigne un élément du serveur que le poste ne sait même pas lire.
  Future<void> consignerIllisible(Object? brut, int rang) async {
    final d = diagnosticIllisible(brut, rang);
    final a = analyserMotif(IssueReception.refuse, d.motif);
    await _ecrire(
      table: d.table,
      id: d.id,
      modifieLe: '',
      issue: IssueReception.refuse,
      cause: a.cause,
      motif: d.motif,
      champ: a.champ,
      dependance: null,
      etiquette: null,
      posteOrigine: null,
      elementJson: null,
      tentative: true,
      seulementSiChange: false,
    );
  }

  Future<void> _ecrire({
    required String table,
    required String id,
    required String modifieLe,
    required IssueReception issue,
    required CauseReception cause,
    required String motif,
    required String? champ,
    required String? dependance,
    required String? etiquette,
    required String? posteOrigine,
    required String? elementJson,
    required bool tentative,
    required bool seulementSiChange,
  }) async {
    final maintenant = _maintenant();
    final existant =
        await (select(_journal)..where(
              (j) => j.tableServeur.equals(table) & j.elementId.equals(id),
            ))
            .getSingleOrNull();
    final memeVersion =
        existant != null && existant.modifieLeServeur == modifieLe;
    if (seulementSiChange &&
        memeVersion &&
        existant.issue == issue.code &&
        existant.motif == motif) {
      return;
    }
    await into(_journal).insertOnConflictUpdate(
      JournalReceptionLocalCompanion.insert(
        tableServeur: table,
        elementId: id,
        issue: issue.code,
        cause: cause.code,
        motif: Value(motif),
        champ: Value(champ),
        dependance: Value(dependance),
        etiquette: Value(etiquette ?? existant?.etiquette),
        posteOrigine: Value(posteOrigine),
        modifieLeServeur: Value(modifieLe),
        tentatives: Value(
          memeVersion ? existant.tentatives + (tentative ? 1 : 0) : 1,
        ),
        recuLe: memeVersion ? existant.recuLe : maintenant,
        derniereTentativeLe: maintenant,
        elementJson: Value(elementJson),
      ),
    );
  }

  /// Applique la rétention (voir l'en-tête). Rend le nombre de lignes retirées.
  Future<int> purger() async {
    final limite = _maintenant().subtract(const Duration(days: joursRetention));
    var retirees =
        await (delete(_journal)..where(
              (j) =>
                  j.issue.equals(IssueReception.aligne.code) &
                  j.derniereTentativeLe.isSmallerThanValue(limite),
            ))
            .go();
    final total = await _total();
    if (total > lignesMax) {
      retirees += await customUpdate(
        'DELETE FROM journal_reception_local WHERE rowid IN ('
        'SELECT rowid FROM journal_reception_local '
        "ORDER BY (issue = 'aligne') DESC, derniere_tentative_le ASC "
        'LIMIT ?)',
        variables: [Variable.withInt(total - lignesMax)],
        updates: {_journal},
      );
    }
    return retirees;
  }

  Future<int> _total() async {
    final r = await customSelect(
      'SELECT COUNT(*) AS n FROM journal_reception_local',
      readsFrom: {_journal},
    ).getSingle();
    return r.data['n'] as int;
  }

  /// Les comptes par issue.
  Future<CompteursReception> compter() async {
    final lignes = await customSelect(
      'SELECT issue, COUNT(*) AS n FROM journal_reception_local '
      'GROUP BY issue',
      readsFrom: {_journal},
    ).get();
    int n(IssueReception i) {
      for (final l in lignes) {
        if (l.data['issue'] == i.code) return l.data['n'] as int;
      }
      return 0;
    }

    return CompteursReception(
      aligne: n(IssueReception.aligne),
      conserve: n(IssueReception.conserve),
      enAttente: n(IssueReception.enAttente),
      refuse: n(IssueReception.refuse),
    );
  }

  /// Un signal à chaque écriture du journal (l'écran relit).
  Stream<void> surveiller() => attachedDatabase.tableUpdates(
    TableUpdateQuery.onTableName('journal_reception_local'),
  );

  /// Les tables présentes dans le journal (nom serveur), pour le filtre.
  Future<List<String>> tablesPresentes() async {
    final lignes = await customSelect(
      'SELECT DISTINCT table_serveur AS t FROM journal_reception_local',
      readsFrom: {_journal},
    ).get();
    return [for (final l in lignes) l.data['t'] as String]..sort();
  }

  /// Les lignes, les plus récemment tentées d'abord, filtrées au besoin —
  /// SANS l'élément gardé (lourd) : [lire] le rend pour un détail.
  /// [du] et [au] bornent la date de dernière tentative (jours inclus).
  Future<List<EntreeJournalReception>> lister({
    String? table,
    IssueReception? issue,
    DateTime? du,
    DateTime? au,
    bool? aTraiter,
    int limite = 2000,
  }) async {
    final q = select(_journal)
      ..orderBy([
        (j) => OrderingTerm.desc(j.derniereTentativeLe),
        (j) => OrderingTerm.asc(j.tableServeur),
        (j) => OrderingTerm.asc(j.elementId),
      ])
      ..limit(limite);
    if (table != null) q.where((j) => j.tableServeur.equals(table));
    if (issue != null) q.where((j) => j.issue.equals(issue.code));
    if (aTraiter ?? false) {
      q.where((j) => j.issue.equals(IssueReception.aligne.code).not());
    }
    if (du != null) {
      final debut = DateTime(du.year, du.month, du.day);
      q.where((j) => j.derniereTentativeLe.isBiggerOrEqualValue(debut));
    }
    if (au != null) {
      final fin = DateTime(
        au.year,
        au.month,
        au.day,
      ).add(const Duration(days: 1));
      q.where((j) => j.derniereTentativeLe.isSmallerThanValue(fin));
    }
    return [for (final l in await q.get()) _vers(l, avecElement: false)];
  }

  /// Une ligne, avec l'élément gardé.
  Future<EntreeJournalReception?> lire(String table, String id) async {
    final l =
        await (select(_journal)..where(
              (j) => j.tableServeur.equals(table) & j.elementId.equals(id),
            ))
            .getSingleOrNull();
    return l == null ? null : _vers(l, avecElement: true);
  }

  /// Les lignes encore à traiter qui portent leur élément (la relance de
  /// tout), dans l'ordre des tables du serveur.
  Future<List<EntreeJournalReception>> aRelancer() async {
    final lignes =
        await (select(_journal)..where(
              (j) =>
                  j.issue.equals(IssueReception.aligne.code).not() &
                  j.elementJson.isNotNull(),
            ))
            .get();
    final entrees = [for (final l in lignes) _vers(l, avecElement: true)];
    int rang(EntreeJournalReception e) =>
        TableDescendue.depuisNom(e.tableServeur)?.index ?? 1 << 20;
    entrees.sort((a, b) => rang(a).compareTo(rang(b)));
    return entrees;
  }

  EntreeJournalReception _vers(
    JournalReceptionLigne l, {
    required bool avecElement,
  }) => EntreeJournalReception(
    tableServeur: l.tableServeur,
    elementId: l.elementId,
    issue: IssueReception.depuisCode(l.issue) ?? IssueReception.refuse,
    cause: CauseReception.depuisCode(l.cause),
    motif: l.motif,
    champ: l.champ,
    dependance: l.dependance,
    etiquette: l.etiquette,
    posteOrigine: l.posteOrigine,
    modifieLeServeur: l.modifieLeServeur,
    tentatives: l.tentatives,
    recuLe: l.recuLe,
    derniereTentativeLe: l.derniereTentativeLe,
    elementJson: avecElement ? l.elementJson : null,
  );
}
