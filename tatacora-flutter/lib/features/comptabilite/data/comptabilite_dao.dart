import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/declencheurs_comptables.dart';
import '../../tableau_de_bord/domain/indicateurs_locaux.dart' show ChargeDatee;
import '../domain/anciennes_pieces_saisies.dart';
import '../domain/cloture_exercice.dart';
import '../domain/correspondance_comptes.dart';
import '../domain/entities/comptabilite.dart';
import '../domain/etats_financiers.dart' show CompteDeReport;
import 'ecritures_serveur_dao.dart' show EcritureServeur;
import '../domain/messages_comptables.dart';
import '../domain/refus_comptable.dart';
import '../domain/regle_numero_compte.dart';

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

  /// Le centre d'identifiant [id], ou `null` (lot F1 : la dépense relit
  /// celui de sa pièce pour l'envoyer au serveur).
  Future<CentreDeCout?> centreParId(String id) async {
    final r = await (select(
      attachedDatabase.centresCoutLocal,
    )..where((c) => c.id.equals(id))).getSingleOrNull();
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

  /// Le compte d'un RÔLE comptable à l'instant de la lecture : la valeur du
  /// paramètre `compte_<rôle>` (`parametres_systeme_local`), à défaut — clé
  /// absente ou vide — le compte par défaut du rôle. Lecture seule : l'écriture
  /// est celle du seul `EnregistrerParametres`.
  ///
  /// Un rôle hors registre LÈVE : un numéro deviné serait une pièce imputée au
  /// hasard.
  Future<String> compteDuRole(String code) async {
    final role = RolesCorrespondance.parCode(code);
    if (role == null) {
      throw ArgumentError.value(code, 'code', 'Rôle comptable inconnu.');
    }
    final ligne = await (select(
      attachedDatabase.parametresSystemeLocal,
    )..where((p) => p.cle.equals(role.cle))).getSingleOrNull();
    final choisi = ligne?.valeur.trim() ?? '';
    return choisi.isEmpty ? role.defaut : choisi;
  }

  /// Les quatre refus de la correspondance, jugés sur le plan de CE poste
  /// (`verifierCompteDuRole` : format, existence, classe du rôle, compte
  /// imputable) — la phrase du refus, ou `null`.
  Future<String?> verifierCompteDuRole(RoleCompte role, String numero) async {
    final compte = RegleNumeroCompte.format.hasMatch(numero)
        ? await compteParNumero(numero)
        : null;
    final division =
        compte != null && numero.length < 4 && await aDesSousComptes(numero);
    return verifierCompteDuRoleSurPlan(
      role: role,
      numero: numero,
      compte: compte,
      aDesSousComptes: division,
    );
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
  /// Les lignes dont le libellé commence par [prefixe] et finit par
  /// [suffixe] — une pièce retrouvée par l'UUID de son document quand le
  /// numéro cité au libellé a changé depuis (lot F5c). Les deux bornes sont
  /// comparées EXACTEMENT (aucun joker) : un `%` ou un `_` du texte ne
  /// s'interprète pas.
  Future<List<EcritureComptable>> lignesParSuffixeLibelle(
    String suffixe, {
    required String prefixe,
  }) async => [
    for (final r
        in await (select(attachedDatabase.ecrituresLocal)
              ..where(
                (e) =>
                    e.libelle.substr(1, prefixe.length).equals(prefixe) &
                    CustomExpression<String>(
                      'substr(libelle, -${suffixe.length})',
                    ).equals(suffixe),
              )
              ..orderBy([
                (e) => OrderingTerm(
                  expression: const CustomExpression<int>('rowid'),
                ),
              ]))
            .get())
      _ecriture(r),
  ];

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

  /// L'exercice de [annee] tel que le SERVEUR le détient (descente du
  /// catalogue, 20/10/2026) : créé s'il manque ici, sinon ses dates et son
  /// statut sont ceux du serveur — maître de la clôture. L'identifiant
  /// local, que désignent les écritures, ne change jamais.
  Future<void> alignerExerciceDescendu({
    required int annee,
    required String dateDebut,
    required String dateFin,
    required StatutExercice statut,
    DateTime? dateCloture,
  }) async {
    final existant = await exerciceDeLAnnee(annee);
    if (existant == null) {
      await into(attachedDatabase.exercicesLocal).insert(
        ExercicesLocalCompanion.insert(
          id: nouvelId(),
          annee: annee,
          dateDebut: dateDebut,
          dateFin: dateFin,
          statut: Value(statut.valeur),
          dateCloture: Value(dateCloture),
        ),
      );
      return;
    }
    await (update(
      attachedDatabase.exercicesLocal,
    )..where((e) => e.id.equals(existant.id))).write(
      ExercicesLocalCompanion(
        dateDebut: Value(dateDebut),
        dateFin: Value(dateFin),
        statut: Value(statut.valeur),
        dateCloture: Value(dateCloture),
      ),
    );
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

  /// Le statut d'un exercice qui CHANGE — les gestes de la clôture
  /// (démarrer, reprendre la saisie, clôturer, rouvrir). [cloture] pose la date
  /// et l'auteur de la clôture ; sans lui, les deux sont EFFACÉS (un exercice
  /// qui n'est plus clôturé n'a plus de date de clôture).
  Future<void> changerStatutExercice(
    String exerciceId,
    StatutExercice statut, {
    DateTime? clotureLe,
    String? clotureParId,
  }) async {
    await (update(
      attachedDatabase.exercicesLocal,
    )..where((e) => e.id.equals(exerciceId))).write(
      ExercicesLocalCompanion(
        statut: Value(statut.valeur),
        dateCloture: Value(clotureLe),
        utilisateurClotureId: Value(clotureParId),
      ),
    );
  }

  /// L'exercice de [annee], créé s'il MANQUE (`ExerciceComptableService::assurer`) :
  /// jamais réécrit, jamais rouvert — un exercice clôturé reste clôturé. Hors
  /// 2000-2100, rien n'est créé et la valeur rendue est `null`.
  Future<ExerciceComptable?> assurerExercice(int annee) async {
    if (annee < 2000 || annee > 2100) return null;
    return await exerciceDeLAnnee(annee) ??
        await insererExercice(
          annee: annee,
          dateDebut: '$annee-01-01',
          dateFin: '$annee-12-31',
        );
  }

  /* ================================================================== */
  /* Lectures de la clôture                                              */
  /* ================================================================== */

  /// Les soldes des comptes de GESTION (classes 6, 7, 8) d'un exercice, par
  /// compte ET par centre, sur les écritures VALIDÉES — le `GROUP BY` de
  /// `lignesDeCloture` du serveur. Journal de clôture compris : une clôture déjà
  /// contre-passée s'annule dans la somme.
  Future<List<SoldeGestion>> soldesDeGestion(String exerciceId) async {
    final e = attachedDatabase.ecrituresLocal;
    final p = attachedDatabase.planComptableLocal;
    final debit = e.debitCentimes.sum();
    final credit = e.creditCentimes.sum();
    final requete =
        selectOnly(e).join([innerJoin(p, p.id.equalsExp(e.compteId))])
          ..addColumns([p.numeroCompte, e.centreId, debit, credit])
          ..where(
            e.exerciceId.equals(exerciceId) &
                e.statut.equals('validee') &
                p.classe.isIn(classesDeGestion),
          )
          ..groupBy([p.numeroCompte, e.centreId]);
    return [
      for (final r in await requete.get())
        (
          numero: r.read(p.numeroCompte)!,
          centreId: r.read(e.centreId)!,
          debitCentimes: r.read(debit) ?? 0,
          creditCentimes: r.read(credit) ?? 0,
        ),
    ];
  }

  /// Les soldes des comptes de BILAN (classes 1 à 5) d'un exercice, par compte,
  /// sur les écritures VALIDÉES — journaux AN et CL compris (c'est la balance
  /// « après clôture » du serveur, `apresCloture: true`).
  Future<List<SoldeBilan>> soldesDeBilan(String exerciceId) async {
    final e = attachedDatabase.ecrituresLocal;
    final p = attachedDatabase.planComptableLocal;
    final debit = e.debitCentimes.sum();
    final credit = e.creditCentimes.sum();
    final requete =
        selectOnly(e).join([innerJoin(p, p.id.equalsExp(e.compteId))])
          ..addColumns([p.numeroCompte, p.classe, debit, credit])
          ..where(
            e.exerciceId.equals(exerciceId) &
                e.statut.equals('validee') &
                p.classe.isIn(classesDeBilan),
          )
          ..groupBy([p.numeroCompte, p.classe]);
    return [
      for (final r in await requete.get())
        (
          numero: r.read(p.numeroCompte)!,
          classe: r.read(p.classe)!,
          debitCentimes: r.read(debit) ?? 0,
          creditCentimes: r.read(credit) ?? 0,
        ),
    ];
  }

  /// Les écritures VALIDÉES de chaque année d'exercice, AGRÉGÉES par (journal,
  /// compte) — de quoi calculer la balance, le compte de résultat et le bilan
  /// sans charger chaque ligne : une somme ne change pas selon qu'on l'écrit en
  /// une ligne ou en mille. Au format du miroir du serveur, pour que le MÊME
  /// calcul (`etats_financiers.dart`) serve les deux sources.
  ///
  /// [anneeAvecBrouillons] : l'exercice dont les BROUILLONS comptent aussi — la
  /// liste de contrôle d'une clôture juge l'exercice sur ses brouillons ET ses
  /// validées, pendant que le report de l'exercice précédent ne porte que les
  /// validées (`EtatClotureService`, `BalanceGeneraleService`).
  Future<Map<int, List<EcritureServeur>>> ecrituresValideesParAnnee({
    int? anneeAvecBrouillons,
  }) async {
    final e = attachedDatabase.ecrituresLocal;
    final x = attachedDatabase.exercicesLocal;
    final j = attachedDatabase.journauxLocal;
    final p = attachedDatabase.planComptableLocal;
    final debit = e.debitCentimes.sum();
    final credit = e.creditCentimes.sum();
    final requete =
        selectOnly(e).join([
            innerJoin(x, x.id.equalsExp(e.exerciceId)),
            innerJoin(j, j.id.equalsExp(e.journalId)),
            innerJoin(p, p.id.equalsExp(e.compteId)),
          ])
          ..addColumns([
            x.annee,
            j.code,
            p.numeroCompte,
            p.libelle,
            p.classe,
            debit,
            credit,
          ])
          ..where(
            anneeAvecBrouillons == null
                ? e.statut.equals('validee')
                : e.statut.equals('validee') |
                      x.annee.equals(anneeAvecBrouillons),
          )
          ..groupBy([x.annee, j.code, p.numeroCompte, p.libelle, p.classe]);
    final parAnnee = <int, List<EcritureServeur>>{};
    for (final r in await requete.get()) {
      final annee = r.read(x.annee)!;
      (parAnnee[annee] ??= []).add(
        EcritureServeur(
          annee: annee,
          codeJournal: r.read(j.code)!,
          numeroCompte: r.read(p.numeroCompte)!,
          libelleCompte: r.read(p.libelle)!,
          classe: r.read(p.classe)!,
          debitCentimes: r.read(debit) ?? 0,
          creditCentimes: r.read(credit) ?? 0,
        ),
      );
    }
    return parAnnee;
  }

  /// Les années dont la clôture est enregistrée sur ce poste et non rouverte.
  Future<Set<int>> anneesAvecClotureActive() async {
    final c = attachedDatabase.cloturesExercicesLocal;
    final x = attachedDatabase.exercicesLocal;
    final requete =
        selectOnly(c).join([innerJoin(x, x.id.equalsExp(c.exerciceId))])
          ..addColumns([x.annee])
          ..where(c.rouverteLe.isNull());
    return {for (final r in await requete.get()) r.read(x.annee)!};
  }

  /// Les comptes de résultat que le report nomme (131 / 139 ou ceux qu'une
  /// correspondance a choisis), pour libeller les à-nouveaux provisoires.
  Future<Map<String, CompteDeReport>> comptesDeReport(
    Iterable<String> numeros,
  ) async {
    final plan = <String, CompteDeReport>{};
    for (final numero in numeros) {
      final c = await compteParNumero(numero);
      if (c != null) {
        plan[numero] = CompteDeReport(libelle: c.libelle, classe: c.classe);
      }
    }
    return plan;
  }

  /// Les lignes d'une pièce D'UN EXERCICE (le numéro porte l'année de sa date,
  /// donc la pièce d'à-nouveaux de N+1 se retrouve dans N+1), jamais celles
  /// d'une contre-passation (sans numéro).
  Future<List<EcritureComptable>> lignesDeLaPieceDeLExercice(
    String exerciceId,
    String numeroPiece,
  ) async => [
    for (final r
        in await (select(attachedDatabase.ecrituresLocal)
              ..where(
                (e) =>
                    e.exerciceId.equals(exerciceId) &
                    e.numeroPiece.equals(numeroPiece) &
                    e.ecritureContrepasseeId.isNull(),
              )
              ..orderBy([
                (e) => OrderingTerm(
                  expression: const CustomExpression<int>('rowid'),
                ),
              ]))
            .get())
      _ecriture(r),
  ];

  /// Toutes les lignes d'un exercice, validées ou non, dans l'ordre de
  /// l'archive légale (date, journal, pièce, saisie) avec ce que le fichier des
  /// écritures cite : journal, compte, centre, pièce contre-passée, auteur.
  Future<List<LigneDArchive>> lignesPourArchive(String exerciceId) async {
    final e = attachedDatabase.ecrituresLocal;
    final j = attachedDatabase.journauxLocal;
    final p = attachedDatabase.planComptableLocal;
    final c = attachedDatabase.centresCoutLocal;
    final u = attachedDatabase.utilisateursLocal;
    final lignes =
        await (select(e).join([
                innerJoin(j, j.id.equalsExp(e.journalId)),
                innerJoin(p, p.id.equalsExp(e.compteId)),
                innerJoin(c, c.id.equalsExp(e.centreId)),
                leftOuterJoin(u, u.id.equalsExp(e.creePar)),
              ])
              ..where(e.exerciceId.equals(exerciceId))
              ..orderBy([
                OrderingTerm.asc(e.dateEcriture),
                OrderingTerm.asc(j.code),
                OrderingTerm.asc(e.numeroPiece),
                OrderingTerm.asc(e.creeLe),
                OrderingTerm.asc(e.rowId),
              ]))
            .get();
    return [
      for (final r in lignes)
        LigneDArchive(
          codeJournal: r.readTable(j).code,
          libelleJournal: r.readTable(j).libelle,
          numeroPiece: r.readTable(e).numeroPiece,
          dateEcriture: r.readTable(e).dateEcriture,
          numeroCompte: r.readTable(p).numeroCompte,
          libelleCompte: r.readTable(p).libelle,
          libelleCentre: r.readTable(c).libelle,
          libelle: r.readTable(e).libelle,
          debitCentimes: r.readTable(e).debitCentimes,
          creditCentimes: r.readTable(e).creditCentimes,
          statut: r.readTable(e).statut,
          pieceContrepassee: r.readTable(e).ecritureContrepasseeId == null
              ? null
              : await _numeroDePiece(r.readTable(e).ecritureContrepasseeId!),
          saisieLe: r.readTable(e).creeLe,
          saisiePar: r.readTableOrNull(u)?.login,
        ),
    ];
  }

  Future<String?> _numeroDePiece(String ecritureId) async => (await (select(
    attachedDatabase.ecrituresLocal,
  )..where((e) => e.id.equals(ecritureId))).getSingleOrNull())?.numeroPiece;

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

  /// Marque une pièce de SAISIE MANUELLE (v44, D246 rouvert) : son identifiant
  /// d'origine, celui que le poste envoie et que le serveur pose sur sa pièce.
  /// Seul appelant : [MoteurComptable.saisirPiece], dans la transaction de la pièce.
  Future<void> insererPieceSaisie({
    required String id,
    required String numeroPiece,
    required String codeJournal,
    required String datePiece,
    required String libelle,
    required String statut,
    required DateTime creeLe,
  }) async {
    await into(attachedDatabase.piecesSaisieLocal).insert(
      PiecesSaisieLocalCompanion.insert(
        id: id,
        numeroPiece: numeroPiece,
        codeJournal: codeJournal,
        datePiece: datePiece,
        libelle: libelle,
        statut: statut,
        creeLe: creeLe,
      ),
    );
  }

  /// Les pièces de saisie manuelle que le serveur n'a PAS encore reprises : leur
  /// identifiant d'origine ne figure pas dans le miroir `ecritures_serveur_local`
  /// (seules les pièces validées y descendent). Une pièce validée ici, envoyée
  /// puis redescendue, n'y figure plus — c'est la même pièce, jamais deux.
  Future<List<PieceSaisieLigne>> piecesSaisiesNonReprises() =>
      (select(attachedDatabase.piecesSaisieLocal)
            ..where(
              (p) => CustomExpression<bool>(
                'NOT EXISTS (SELECT 1 FROM ecritures_serveur_local e '
                'WHERE e.piece_origine_id = pieces_saisie_local.id)',
              ),
            )
            ..orderBy([(p) => OrderingTerm.asc(p.creeLe)]))
          .get();

  /// Les numéros des ANCIENNES pièces saisies à la main (avant la v44, lot A3) :
  /// ni marquées (`pieces_saisie_local`), ni rattachées à un module, une clôture
  /// ou une contre-passation. Voir `anciennes_pieces_saisies.dart` : EN CAS DE
  /// DOUTE la pièce n'y est pas. Le filtre se fait par PIÈCE (un `NOT IN` sur les
  /// numéros), jamais ligne à ligne : une pièce dont UNE ligne est citée par un
  /// module disparaît entière.
  static final String _sqlAnciennesPieces =
      '''
SELECT e.numero_piece FROM ecritures_local e
  JOIN journaux_local j ON j.id = e.journal_id
  JOIN exercices_local x ON x.id = e.exercice_id
 WHERE e.numero_piece IS NOT NULL
   AND j.code NOT IN (${journauxDesModulesEtDeCloture.map((c) => "'$c'").join(',')})
   AND x.statut <> 'cloture'
   AND NOT EXISTS (SELECT 1 FROM pieces_saisie_local p
                    WHERE p.numero_piece = e.numero_piece)
   AND e.numero_piece NOT IN (
     SELECT e2.numero_piece FROM ecritures_local e2
      WHERE e2.numero_piece IS NOT NULL
        AND (e2.ecriture_contrepassee_id IS NOT NULL
          OR e2.id IN (SELECT ecriture_contrepassee_id FROM ecritures_local
                        WHERE ecriture_contrepassee_id IS NOT NULL)
          OR e2.id IN (SELECT ecriture_id FROM depenses_local
                        WHERE ecriture_id IS NOT NULL)
          OR e2.id IN (SELECT ecriture_remboursement_id FROM reservations_local
                        WHERE ecriture_remboursement_id IS NOT NULL)))
 GROUP BY e.numero_piece
HAVING COUNT(*) >= 2
   AND COUNT(DISTINCT e.journal_id) = 1
   AND COUNT(DISTINCT e.exercice_id) = 1
   AND COUNT(DISTINCT e.statut) = 1
   AND COUNT(DISTINCT e.date_ecriture) = 1
   AND SUM(e.debit_centimes) = SUM(e.credit_centimes)''';

  /// Les pièces saisies à la main que le poste COMPTE en attendant le serveur :
  /// celles qu'il a marquées et que le serveur n'a pas reprises (reconnues par
  /// l'identifiant d'origine) ET les anciennes pièces encore non marquées —
  /// jamais perdues tant que le geste n'est pas fait.
  static final String _sqlPiecesACompter = '''
SELECT p.numero_piece FROM pieces_saisie_local p
 WHERE NOT EXISTS (SELECT 1 FROM ecritures_serveur_local s
                    WHERE s.piece_origine_id = p.id)
UNION
$_sqlAnciennesPieces''';

  /// Les anciennes pièces saisies à la main, proposées à l'envoi (lot A3), les
  /// plus anciennes d'abord. Lecture seule : rien n'est marqué ici.
  Future<List<AnciennePieceSaisie>> anciennesPiecesSaisies() async {
    final numeros = [
      for (final r in await customSelect(_sqlAnciennesPieces).get())
        r.read<String>('numero_piece'),
    ];
    final comptes = <String, String>{};
    final centres = {for (final c in await this.centres()) c.id: c.libelle};
    final journaux = {for (final j in await this.journaux()) j.id: j.code};
    final pieces = <AnciennePieceSaisie>[];
    for (final numero in numeros) {
      final lignes = await lignesDeLaPiece(numero);
      for (final l in lignes) {
        comptes[l.compteId] ??= (await compteParId(l.compteId))!.numero;
      }
      final premiere = lignes.first;
      pieces.add(
        AnciennePieceSaisie(
          numeroPiece: numero,
          journal: journaux[premiere.journalId] ?? '',
          date: premiere.dateEcriture,
          libelle: premiere.libelle,
          statut: premiere.estValidee ? 'validee' : 'brouillon',
          lignes: [
            for (final l in lignes)
              LigneAnciennePiece(
                compte: comptes[l.compteId]!,
                debitCentimes: l.debitCentimes,
                creditCentimes: l.creditCentimes,
                libelle: l.libelle,
                centreLibelle: centres[l.centreId] ?? '',
              ),
          ],
        ),
      );
    }
    pieces.sort((a, b) {
      final d = a.date.compareTo(b.date);
      return d != 0 ? d : a.numeroPiece.compareTo(b.numeroPiece);
    });
    return pieces;
  }

  /// Les écritures VALIDÉES des pièces saisies à la main que le serveur n'a pas
  /// encore reprises, par année d'exercice et agrégées (journal, compte), au
  /// format du miroir : elles s'AJOUTENT au miroir `ecritures_serveur_local`
  /// (lot A1). Sans double compte : la pièce redescendue est reconnue par son
  /// identifiant d'origine et sort d'ici.
  Future<Map<int, List<EcritureServeur>>>
  ecrituresPiecesManuellesNonReprises() async {
    final e = attachedDatabase.ecrituresLocal;
    final x = attachedDatabase.exercicesLocal;
    final j = attachedDatabase.journauxLocal;
    final p = attachedDatabase.planComptableLocal;
    final debit = e.debitCentimes.sum();
    final credit = e.creditCentimes.sum();
    final requete =
        selectOnly(e).join([
            innerJoin(x, x.id.equalsExp(e.exerciceId)),
            innerJoin(j, j.id.equalsExp(e.journalId)),
            innerJoin(p, p.id.equalsExp(e.compteId)),
          ])
          ..addColumns([
            x.annee,
            j.code,
            p.numeroCompte,
            p.libelle,
            p.classe,
            debit,
            credit,
          ])
          ..where(
            e.statut.equals('validee') &
                CustomExpression<bool>(
                  'ecritures_local.numero_piece IN ($_sqlPiecesACompter)',
                ),
          )
          ..groupBy([x.annee, j.code, p.numeroCompte, p.libelle, p.classe]);
    final parAnnee = <int, List<EcritureServeur>>{};
    for (final r in await requete.get()) {
      final annee = r.read(x.annee)!;
      (parAnnee[annee] ??= []).add(
        EcritureServeur(
          annee: annee,
          codeJournal: r.read(j.code)!,
          numeroCompte: r.read(p.numeroCompte)!,
          libelleCompte: r.read(p.libelle)!,
          classe: r.read(p.classe)!,
          debitCentimes: r.read(debit) ?? 0,
          creditCentimes: r.read(credit) ?? 0,
        ),
      );
    }
    return parAnnee;
  }

  /// Les charges (classe 6) VALIDÉES des mêmes pièces, datées — « Dépenses
  /// cumulées » du tableau de bord quand la source est le miroir (lot A1).
  Future<List<ChargeDatee>> chargesPiecesManuellesNonReprises() async {
    final e = attachedDatabase.ecrituresLocal;
    final p = attachedDatabase.planComptableLocal;
    final lignes =
        await (select(e).join([innerJoin(p, p.id.equalsExp(e.compteId))])
              ..where(
                e.statut.equals('validee') &
                    p.classe.equals('6') &
                    CustomExpression<bool>(
                      'ecritures_local.numero_piece IN ($_sqlPiecesACompter)',
                    ),
              ))
            .get();
    return [
      for (final r in lignes)
        ChargeDatee(
          date: r.readTable(e).dateEcriture,
          debitCentimes: r.readTable(e).debitCentimes,
          creditCentimes: r.readTable(e).creditCentimes,
        ),
    ];
  }

  /// Combien de PIÈCES saisies à la main (au moins une ligne validée) le poste
  /// compte en attendant le serveur — pour le bandeau de provenance.
  Future<int> nombrePiecesManuellesCompteesEnAttente() async {
    final r = await customSelect(
      'SELECT COUNT(DISTINCT numero_piece) AS n FROM ecritures_local '
      "WHERE statut = 'validee' AND numero_piece IN ($_sqlPiecesACompter)",
    ).getSingle();
    return r.read<int>('n');
  }

  /// Un compte du plan DESCENDU du serveur (28/10/2026, D246 rouvert) : ajouté
  /// SEULEMENT si son numéro manque ici — jamais réécrit, pas même un compte créé
  /// sur ce poste dont l'envoi attend ou a été refusé. Rend `true` quand il est
  /// neuf. Le numéro est la clé naturelle ; l'identifiant est celui du serveur.
  Future<bool> insererCompteDescendu({
    required String id,
    required String numero,
    required String libelle,
    required String? nature,
  }) async {
    final ajoutes = await into(attachedDatabase.planComptableLocal).insert(
      PlanComptableLocalCompanion.insert(
        id: id,
        numeroCompte: numero,
        libelle: libelle,
        classe: numero.substring(0, 1),
        nature: Value(nature),
      ),
      mode: InsertMode.insertOrIgnore,
    );
    return ajoutes > 0;
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

/// Une ligne du fichier des écritures de l'archive légale — ce que
/// `ArchiveClotureService::fichierEcritures` joint pour chaque ligne passée.
final class LigneDArchive {
  const LigneDArchive({
    required this.codeJournal,
    required this.libelleJournal,
    required this.numeroPiece,
    required this.dateEcriture,
    required this.numeroCompte,
    required this.libelleCompte,
    required this.libelleCentre,
    required this.libelle,
    required this.debitCentimes,
    required this.creditCentimes,
    required this.statut,
    required this.pieceContrepassee,
    required this.saisieLe,
    required this.saisiePar,
  });

  final String codeJournal;
  final String libelleJournal;
  final String? numeroPiece;

  /// `AAAA-MM-JJ`.
  final String dateEcriture;
  final String numeroCompte;
  final String libelleCompte;
  final String libelleCentre;
  final String libelle;
  final int debitCentimes;
  final int creditCentimes;
  final String statut;

  /// Le numéro de la pièce d'ORIGINE quand cette ligne en est la
  /// contre-passation.
  final String? pieceContrepassee;
  final DateTime saisieLe;

  /// Le login de qui l'a passée.
  final String? saisiePar;
}
