import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/declencheurs_comptables.dart';
import '../domain/entities/comptabilite.dart';
import '../domain/messages_comptables.dart';
import '../domain/refus_comptable.dart';

/// Accès Drift au moteur comptable — **local pur**. Il ne rend que des entités
/// du domaine, jamais une ligne Drift.
///
/// ## Qui l'appelle
///
/// `MoteurComptable` (écritures, exercices, comptes), `installerReferentielComptable`
/// (référentiel) et les états à venir (lecture). Aucun module métier n'écrit
/// une écriture par ce DAO : il passe par le moteur, qui porte les règles.
///
/// ## Aucun mixin généré
///
/// Comme `StocksDao` et `RestaurantDao` : on passe par `attachedDatabase.<table>`.
///
/// ## Les gardes de la base sont traduites ici
///
/// Les triggers de RG-11 (`declencheurs_comptables.dart`) lèvent un CODE ; ce
/// DAO le relit et rend la phrase EXACTE du serveur ([traduireRefusBase]).
class ComptabiliteDao extends DatabaseAccessor<AppDatabase> {
  ComptabiliteDao(super.db, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final Uuid _uuid;

  /// Une identité neuve (v4), pour les lignes que le moteur écrit.
  String nouvelId() => _uuid.v4();

  /* ================================================================== */
  /* Transaction                                                         */
  /* ================================================================== */

  /// Exécute [action] dans une transaction ; imbriquée, elle devient un point
  /// de sauvegarde. Un refus (toute exception) annule TOUT ce que l'action a
  /// écrit — compteur de séquence compris.
  Future<T> enTransaction<T>(Future<T> Function() action) =>
      attachedDatabase.transaction(action);

  /* ================================================================== */
  /* Lecture du référentiel                                              */
  /* ================================================================== */

  Future<JournalComptable?> journalParCode(String code) async {
    final r = await (select(
      attachedDatabase.journauxLocal,
    )..where((j) => j.code.equals(code))).getSingleOrNull();
    return r == null ? null : _journal(r);
  }

  Future<List<JournalComptable>> journaux() async => [
    for (final r in await (select(
      attachedDatabase.journauxLocal,
    )..orderBy([(j) => OrderingTerm.asc(j.code)])).get())
      _journal(r),
  ];

  Future<List<CentreDeCout>> centres() async => [
    for (final r in await (select(
      attachedDatabase.centresCoutLocal,
    )..orderBy([(c) => OrderingTerm.asc(c.libelle)])).get())
      CentreDeCout(id: r.id, libelle: r.libelle, type: r.type),
  ];

  Future<CentreDeCout?> centreParLibelle(String libelle) async {
    final r = await (select(
      attachedDatabase.centresCoutLocal,
    )..where((c) => c.libelle.equals(libelle))).getSingleOrNull();
    return r == null
        ? null
        : CentreDeCout(id: r.id, libelle: r.libelle, type: r.type);
  }

  Future<CompteDuPlan?> compteParNumero(String numero) async {
    final r = await (select(
      attachedDatabase.planComptableLocal,
    )..where((c) => c.numeroCompte.equals(numero))).getSingleOrNull();
    return r == null ? null : _compte(r);
  }

  Future<CompteDuPlan?> compteParId(String id) async {
    final r = await (select(
      attachedDatabase.planComptableLocal,
    )..where((c) => c.id.equals(id))).getSingleOrNull();
    return r == null ? null : _compte(r);
  }

  /// Vrai si le plan porte au moins un sous-compte de [numero] : un numéro
  /// différent qui commence par lui.
  Future<bool> aDesSousComptes(String numero) async {
    final t = attachedDatabase.planComptableLocal;
    // `substr` plutôt que `LIKE` : un numéro n'a aucun caractère générique à
    // échapper, et la comparaison reste exacte.
    final n =
        await (selectOnly(t)
              ..addColumns([t.id])
              ..where(
                t.numeroCompte.substr(1, numero.length).equals(numero) &
                    t.numeroCompte.equals(numero).not(),
              )
              ..limit(1))
            .get();
    return n.isNotEmpty;
  }

  /// Les comptes d'une classe, triés par numéro — pour remplir un sélecteur.
  /// Non paginé : une page manquante ferait imputer une écriture au mauvais
  /// compte.
  Future<List<CompteDuPlan>> comptesDeClasse(String classe) async => [
    for (final r
        in await (select(attachedDatabase.planComptableLocal)
              ..where((c) => c.classe.equals(classe))
              ..orderBy([(c) => OrderingTerm.asc(c.numeroCompte)]))
            .get())
      _compte(r),
  ];

  Future<int> nombreDeComptes() async {
    final t = attachedDatabase.planComptableLocal;
    final n = t.id.count();
    final r = await (selectOnly(t)..addColumns([n])).getSingle();
    return r.read(n) ?? 0;
  }

  Future<List<ExerciceComptable>> exercices() async => [
    for (final r in await (select(
      attachedDatabase.exercicesLocal,
    )..orderBy([(e) => OrderingTerm.asc(e.annee)])).get())
      _exercice(r),
  ];

  Future<ExerciceComptable?> exercice(String id) async {
    final r = await (select(
      attachedDatabase.exercicesLocal,
    )..where((e) => e.id.equals(id))).getSingleOrNull();
    return r == null ? null : _exercice(r);
  }

  Future<ExerciceComptable?> exerciceDeLAnnee(int annee) async {
    final r = await (select(
      attachedDatabase.exercicesLocal,
    )..where((e) => e.annee.equals(annee))).getSingleOrNull();
    return r == null ? null : _exercice(r);
  }

  /// L'exercice OUVERT le plus récent — `ExerciceComptable::query()->where(
  /// 'statut', 'ouvert')->orderByDesc('annee')->first()` (le Pilotage).
  Future<ExerciceComptable?> exerciceOuvertLePlusRecent() async {
    final r =
        await (select(attachedDatabase.exercicesLocal)
              ..where((e) => e.statut.equals('ouvert'))
              ..orderBy([(e) => OrderingTerm.desc(e.annee)])
              ..limit(1))
            .getSingleOrNull();
    return r == null ? null : _exercice(r);
  }

  /* ================================================================== */
  /* Lecture des écritures                                               */
  /* ================================================================== */

  Future<EcritureComptable?> ecriture(String id) async {
    final r = await (select(
      attachedDatabase.ecrituresLocal,
    )..where((e) => e.id.equals(id))).getSingleOrNull();
    return r == null ? null : _ecriture(r);
  }

  /// Le numéro de pièce de chaque écriture demandée : `identifiant -> numéro`.
  ///
  /// UNE requête pour toutes (un module qui affiche une liste n'en fait pas une
  /// par ligne). Une écriture sans numéro (une contre-passation) ou inconnue est
  /// ABSENTE de la réponse — jamais une chaîne vide, que l'appelant afficherait.
  Future<Map<String, String>> numerosDePiece(Iterable<String> ids) async {
    final demandes = ids.toSet();
    if (demandes.isEmpty) return const {};
    final lignes = await (select(
      attachedDatabase.ecrituresLocal,
    )..where((e) => e.id.isIn(demandes))).get();
    return {
      for (final l in lignes)
        if (l.numeroPiece != null) l.id: l.numeroPiece!,
    };
  }

  /// Les lignes d'une pièce, dans l'ordre où elles ont été écrites.
  Future<List<EcritureComptable>> lignesDeLaPiece(String numeroPiece) async => [
    for (final r
        in await (select(attachedDatabase.ecrituresLocal)
              ..where((e) => e.numeroPiece.equals(numeroPiece))
              ..orderBy([
                (e) => OrderingTerm(
                  expression: const CustomExpression<int>('rowid'),
                ),
              ]))
            .get())
      _ecriture(r),
  ];

  /// Les lignes dont le libellé est EXACTEMENT [libelle], dans l'ordre
  /// d'écriture.
  ///
  /// C'est le lien du serveur entre un encaissement et sa pièce : `paiements`
  /// n'a pas de colonne `ecriture_id` et `ecritures_comptables` aucune colonne de
  /// pièce (PA-52), donc `EncaissementFactureService::annuler` retrouve la pièce
  /// par son libellé « Encaissement `n°` — `id du paiement` », unique par
  /// l'identifiant du paiement. Répliqué tel quel.
  Future<List<EcritureComptable>> lignesParLibelle(String libelle) async => [
    for (final r
        in await (select(attachedDatabase.ecrituresLocal)
              ..where((e) => e.libelle.equals(libelle))
              ..orderBy([
                (e) => OrderingTerm(
                  expression: const CustomExpression<int>('rowid'),
                ),
              ]))
            .get())
      _ecriture(r),
  ];

  /// Toutes les écritures, dans l'ordre d'écriture.
  Future<List<EcritureComptable>> toutesLesEcritures() async => [
    for (final r
        in await (select(attachedDatabase.ecrituresLocal)..orderBy([
              (e) => OrderingTerm(
                expression: const CustomExpression<int>('rowid'),
              ),
            ]))
            .get())
      _ecriture(r),
  ];

  /// Les agrégats de l'ANALYTIQUE d'un exercice — le `GROUP BY` de
  /// `AnalytiqueService::genererPourExercice` : par (centre, classe du compte),
  /// les deux statuts (`brouillon`, `validee`), sommes des débits et crédits
  /// en centimes, nombre de lignes. Une LECTURE : le calcul de la marge vit
  /// dans `tableau_de_bord/domain/analytique_locale.dart`.
  Future<
    List<
      ({
        String centreId,
        String centreLibelle,
        String classe,
        int debitCentimes,
        int creditCentimes,
        int nombreLignes,
      })
    >
  >
  agregatsAnalytiques(String exerciceId) async {
    final e = attachedDatabase.ecrituresLocal;
    final p = attachedDatabase.planComptableLocal;
    final c = attachedDatabase.centresCoutLocal;
    final debit = e.debitCentimes.sum();
    final credit = e.creditCentimes.sum();
    final lignes = e.id.count();
    final requete =
        selectOnly(e).join([
            innerJoin(p, p.id.equalsExp(e.compteId)),
            innerJoin(c, c.id.equalsExp(e.centreId)),
          ])
          ..addColumns([e.centreId, c.libelle, p.classe, debit, credit, lignes])
          ..where(
            e.exerciceId.equals(exerciceId) &
                e.statut.isIn(const ['brouillon', 'validee']),
          )
          ..groupBy([e.centreId, c.libelle, c.type, p.classe]);
    return [
      for (final r in await requete.get())
        (
          centreId: r.read(e.centreId)!,
          centreLibelle: r.read(c.libelle)!,
          classe: r.read(p.classe)!,
          debitCentimes: r.read(debit) ?? 0,
          creditCentimes: r.read(credit) ?? 0,
          nombreLignes: r.read(lignes) ?? 0,
        ),
    ];
  }

  /// Une ligne est contre-passée dès qu'une autre l'a pour origine.
  Future<bool> dejaContrepassee(String ecritureId) async {
    final t = attachedDatabase.ecrituresLocal;
    final r =
        await (selectOnly(t)
              ..addColumns([t.id])
              ..where(t.ecritureContrepasseeId.equals(ecritureId))
              ..limit(1))
            .get();
    return r.isNotEmpty;
  }

  Future<int> nombreDeBrouillons(String exerciceId) async {
    final t = attachedDatabase.ecrituresLocal;
    final n = t.id.count();
    final r =
        await (selectOnly(t)
              ..addColumns([n])
              ..where(
                t.exerciceId.equals(exerciceId) & t.statut.equals('brouillon'),
              ))
            .getSingle();
    return r.read(n) ?? 0;
  }

  /* ================================================================== */
  /* Écriture                                                            */
  /* ================================================================== */

  /// ALLOUE le prochain rang de pièce de ce journal pour cette année.
  ///
  /// ## Compteur PERSISTÉ, jamais recalculé
  ///
  /// La ligne `(journal, année)` porte le dernier rang alloué ; il est
  /// incrémenté ici et nulle part ailleurs. À APPELER dans la transaction qui
  /// écrit la pièce : le rollback d'un refus rend alors le rang (aucun trou).
  /// Comme `SequenceDocumentService::suivant()`, chaque appel ALLOUE : ne
  /// jamais l'appeler pour « voir » le prochain numéro (`dernierRang` lit).
  Future<int> allouerRang({
    required String journalId,
    required int annee,
  }) async {
    final rang = (await dernierRang(journalId, annee)) + 1;
    await into(attachedDatabase.sequencesPieceLocal).insertOnConflictUpdate(
      SequencesPieceLocalCompanion.insert(
        journalId: journalId,
        annee: annee,
        dernierRang: Value(rang),
      ),
    );
    return rang;
  }

  /// Le dernier rang alloué pour (journal, année), `0` sans pièce. Une LECTURE
  /// du compteur persisté — pas une allocation.
  Future<int> dernierRang(String journalId, int annee) async {
    final r =
        await (select(attachedDatabase.sequencesPieceLocal)..where(
              (s) => s.journalId.equals(journalId) & s.annee.equals(annee),
            ))
            .getSingleOrNull();
    return r?.dernierRang ?? 0;
  }

  Future<EcritureComptable> insererEcriture({
    required String exerciceId,
    required String journalId,
    required String compteId,
    required String centreId,
    required String dateEcriture,
    required String libelle,
    required int debitCentimes,
    required int creditCentimes,
    required StatutEcriture statut,
    required String? ecritureContrepasseeId,
    required String? numeroPiece,
    required DateTime creeLe,
    required String creePar,
  }) async {
    final id = nouvelId();
    try {
      await into(attachedDatabase.ecrituresLocal).insert(
        EcrituresLocalCompanion.insert(
          id: id,
          exerciceId: exerciceId,
          journalId: journalId,
          compteId: compteId,
          centreId: centreId,
          dateEcriture: dateEcriture,
          libelle: libelle,
          debitCentimes: Value(debitCentimes),
          creditCentimes: Value(creditCentimes),
          statut: Value(statut.valeur),
          ecritureContrepasseeId: Value(ecritureContrepasseeId),
          numeroPiece: Value(numeroPiece),
          creeLe: creeLe,
          creePar: creePar,
        ),
      );
    } catch (e) {
      final refus = traduireRefusBase(e);
      if (refus != null) throw refus;
      rethrow;
    }
    return (await ecriture(id))!;
  }

  /// Passe une ligne de `brouillon` à `validee` — le point de non-retour de
  /// RG-11. L'UPDATE est le seul chemin légitime ; les triggers refusent tout
  /// autre.
  Future<void> marquerValidee(
    String ecritureId, {
    required String auteurId,
    required DateTime quand,
  }) async {
    try {
      await (update(
        attachedDatabase.ecrituresLocal,
      )..where((e) => e.id.equals(ecritureId))).write(
        EcrituresLocalCompanion(
          statut: Value(StatutEcriture.validee.valeur),
          modifieLe: Value(quand),
          modifiePar: Value(auteurId),
        ),
      );
    } catch (e) {
      final refus = traduireRefusBase(e);
      if (refus != null) throw refus;
      rethrow;
    }
  }

  Future<ExerciceComptable> insererExercice({
    required int annee,
    required String dateDebut,
    required String dateFin,
  }) async {
    final id = nouvelId();
    try {
      await into(attachedDatabase.exercicesLocal).insert(
        ExercicesLocalCompanion.insert(
          id: id,
          annee: annee,
          dateDebut: dateDebut,
          dateFin: dateFin,
        ),
      );
    } catch (e) {
      final refus = traduireRefusBase(e);
      if (refus != null) throw refus;
      rethrow;
    }
    return (await exercice(id))!;
  }

  Future<void> marquerCloture(
    String exerciceId, {
    required DateTime quand,
    required String auteurId,
  }) async {
    await (update(
      attachedDatabase.exercicesLocal,
    )..where((e) => e.id.equals(exerciceId))).write(
      ExercicesLocalCompanion(
        statut: Value(StatutExercice.cloture.valeur),
        dateCloture: Value(quand),
        utilisateurClotureId: Value(auteurId),
      ),
    );
  }

  Future<CompteDuPlan> insererCompte({
    required String numero,
    required String libelle,
    required String nature,
  }) async {
    final id = nouvelId();
    await into(attachedDatabase.planComptableLocal).insert(
      PlanComptableLocalCompanion.insert(
        id: id,
        numeroCompte: numero,
        libelle: libelle,
        classe: numero.substring(0, 1),
        nature: Value(nature),
      ),
    );
    return (await compteParId(id))!;
  }

  /* ================================================================== */
  /* Traduction des gardes de la base                                    */
  /* ================================================================== */

  /// Rend le refus du domaine qui correspond à une exception de la base.
  ///
  /// * un trigger de RG-11 -> la phrase EXACTE du serveur (l'équivalent de
  ///   `EcritureImmuableException`) ;
  /// * une contrainte `CHECK`, une clé étrangère ou un `NOT NULL` -> le refus
  ///   `contrainteBase` (le serveur répond par une erreur SQL, sans phrase) ;
  /// * toute autre exception rend `null` : une panne de disque n'est pas un
  ///   refus comptable, et la déguiser le cacherait. L'appelant la relève.
  static RefusComptable? traduireRefusBase(Object erreur) {
    if (erreur is RefusComptable) return erreur;
    final texte = erreur.toString();
    if (texte.contains(CodesRefusBase.ecritureImmuable)) {
      return RefusComptable.dit(
        MotifRefus.ecritureImmuable,
        CodesRefusBase.ecritureImmuable,
      );
    }
    if (texte.contains(CodesRefusBase.suppressionInterdite)) {
      return RefusComptable.dit(
        MotifRefus.suppressionInterdite,
        CodesRefusBase.suppressionInterdite,
      );
    }
    if (texte.contains(CodesRefusBase.exerciceClos)) {
      return RefusComptable.dit(
        MotifRefus.exerciceClos,
        CodesRefusBase.exerciceClos,
      );
    }
    if (texte.contains('CHECK constraint failed') ||
        texte.contains('FOREIGN KEY constraint failed') ||
        texte.contains('NOT NULL constraint failed')) {
      return const RefusComptable(
        MotifRefus.contrainteBase,
        PhrasesDuPoste.referenceRefusee,
      );
    }
    return null;
  }

  /* ================================================================== */
  /* Conversions                                                         */
  /* ================================================================== */

  JournalComptable _journal(JournauxLocalData r) =>
      JournalComptable(id: r.id, code: r.code, libelle: r.libelle);

  CompteDuPlan _compte(PlanComptableLocalData r) => CompteDuPlan(
    id: r.id,
    numero: r.numeroCompte,
    libelle: r.libelle,
    classe: r.classe,
    nature: r.nature,
    centreCoutDefautId: r.centreCoutDefautId,
  );

  ExerciceComptable _exercice(ExercicesLocalData r) => ExerciceComptable(
    id: r.id,
    annee: r.annee,
    dateDebut: r.dateDebut,
    dateFin: r.dateFin,
    statut: StatutExercice.depuis(r.statut),
    dateCloture: r.dateCloture,
    utilisateurClotureId: r.utilisateurClotureId,
  );

  EcritureComptable _ecriture(EcrituresLocalData r) => EcritureComptable(
    id: r.id,
    exerciceId: r.exerciceId,
    journalId: r.journalId,
    compteId: r.compteId,
    centreId: r.centreId,
    dateEcriture: r.dateEcriture,
    libelle: r.libelle,
    debitCentimes: r.debitCentimes,
    creditCentimes: r.creditCentimes,
    statut: StatutEcriture.depuis(r.statut),
    ecritureContrepasseeId: r.ecritureContrepasseeId,
    numeroPiece: r.numeroPiece,
    creeLe: r.creeLe,
    creePar: r.creePar,
    modifieLe: r.modifieLe,
    modifiePar: r.modifiePar,
  );
}
