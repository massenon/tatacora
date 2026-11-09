import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/format/auteur_compte.dart';
import '../../synchronisation/data/operations_sync_dao.dart';
import '../../synchronisation/domain/charges_synchronisation.dart';
import '../../synchronisation/domain/operation_sync.dart';
import '../domain/affectation_resultat.dart';
import '../domain/cloture_exercice.dart';
import '../domain/entities/comptabilite.dart';
import '../domain/messages_affectation.dart';
import '../domain/refus_comptable.dart';
import 'cloture_exercice_locale.dart';
import 'comptabilite_dao.dart';
import 'moteur_comptable.dart';

/// L'affectation passée, telle que la carte l'affiche : « Affectation passée le …
/// par … (pièce n° …) » et la ventilation relue de la pièce.
final class AffectationPassee {
  const AffectationPassee({
    required this.numeroPiece,
    required this.dateApprobation,
    required this.passeeLe,
    required this.auteur,
    required this.ventilation,
  });

  final String numeroPiece;

  /// `AAAA-MM-JJ`.
  final String dateApprobation;
  final DateTime passeeLe;
  final String auteur;

  /// Centimes par poste de [postesAffectation] (les postes non nuls seulement).
  final Map<String, int> ventilation;
}

/// Ce que la carte « Affectation du résultat de l'exercice N-1 » montre.
final class EtatAffectation {
  const EtatAffectation({
    required this.annee,
    required this.anneeAffectation,
    required this.resultatCentimes,
    required this.compteResultat,
    required this.exerciceAffectation,
    required this.affectable,
    required this.active,
    required this.dateParDefaut,
    required this.proposition,
    required this.reserveLegalePropose,
    required this.plafondReserveLegaleAtteint,
  });

  /// L'exercice clôturé dont le résultat s'affecte (N-1) et celui qui porte la
  /// pièce (N).
  final int annee;
  final int anneeAffectation;
  final int resultatCentimes;
  final String compteResultat;
  final ExerciceComptable? exerciceAffectation;

  /// Aucune affectation active, N ouvert, un résultat non nul.
  final bool affectable;
  final AffectationPassee? active;
  final String dateParDefaut;
  final Map<String, int> proposition;
  final bool reserveLegalePropose;
  final bool plafondReserveLegaleAtteint;

  bool get estBenefice => resultatCentimes >= 0;
  int get resultatAbsoluCentimes =>
      resultatCentimes >= 0 ? resultatCentimes : -resultatCentimes;
  List<String> get postes => estBenefice ? postesBenefice : postesPerte;
}

/// L'AFFECTATION DU RÉSULTAT d'un exercice clôturé, sur le poste — réplique
/// d'`AffectationResultatService` du serveur (09/11/2026, demande du PO :
/// « ajoute l'affectation du résultat », web ET poste).
///
/// ## Ce que le poste fait, et ce que le serveur refait
///
/// Le poste passe la pièce d'affectation (journal OD, datée dans N, validée
/// donc immuable) PAR [MoteurComptable.saisirPiece], seul écrivain de
/// `ecritures_local` : le moteur l'enfile comme une PIÈCE SAISIE À LA MAIN
/// (`pieces_saisie`), jamais avec un numéro définitif. Le serveur la reçoit avec
/// son bloc `affectation` et la passe par `AffectationResultatService` : exercice
/// clôturé, UNE affectation active, somme exacte, comptable seul — ses phrases,
/// lues dans « À traiter » en cas de refus. La contre-passation part comme une
/// demande `annuler_affectation` (`demandes_cloture_exercice`).
///
/// ## Comment le poste reconnaît « son » affectation
///
/// Sans table de plus : la pièce d'affectation porte le libellé
/// `comptabilite.libelle_affectation_resultat` de l'exercice, dans N ; elle est
/// ACTIVE tant qu'aucune de ses lignes n'est contre-passée. Écart nommé : une
/// pièce saisie à la main avec ce libellé exact passerait pour l'affectation ; et
/// l'affectation passée au SERVEUR (web, autre poste) n'est reconnue ici qu'une
/// fois sa pièce descendue ET réconciliée avec une pièce de ce poste — le
/// serveur reste, lui, le juge de l'unicité.
///
/// ## Les comptes suivent la correspondance
///
/// 131/139, 111, 1181, 465, 121, 1291 par défaut (jamais en dur ici : lus par
/// [ComptabiliteDao.compteDuRole]).
class AffectationResultatLocale {
  AffectationResultatLocale(
    this._db,
    this._moteur, {
    DateTime Function()? maintenant,
    Uuid? uuid,
  }) : _dao = ComptabiliteDao(_db),
       _clotures = ClotureExerciceLocale(_db, _moteur),
       _maintenant = maintenant ?? DateTime.now,
       _uuid = uuid ?? const Uuid();

  final AppDatabase _db;
  final MoteurComptable _moteur;
  final ComptabiliteDao _dao;
  final ClotureExerciceLocale _clotures;
  final DateTime Function() _maintenant;
  final Uuid _uuid;

  /* ================================================================== */
  /* Lecture                                                             */
  /* ================================================================== */

  Future<ComptesAffectation> _comptes() async => (
    benefice: await _dao.compteDuRole('RESULTAT_BENEFICE'),
    perte: await _dao.compteDuRole('RESULTAT_PERTE'),
    reserveLegale: await _dao.compteDuRole('RESERVE_LEGALE'),
    autresReserves: await _dao.compteDuRole('AUTRES_RESERVES'),
    dividendes: await _dao.compteDuRole('DIVIDENDES_A_PAYER'),
    reportCrediteur: await _dao.compteDuRole('REPORT_A_NOUVEAU_CREDITEUR'),
    reportDebiteur: await _dao.compteDuRole('REPORT_A_NOUVEAU_DEBITEUR'),
  );

  /// L'affectation ACTIVE de l'exercice [exerciceId] (N-1), ou `null`.
  Future<AffectationPassee?> active(String exerciceId) async {
    final exercice = await _dao.exercice(exerciceId);
    if (exercice == null) return null;
    final suivant = await _dao.exerciceDeLAnnee(exercice.annee + 1);
    if (suivant == null) return null;
    final lignes = await _lignesActives(exercice.annee, suivant);
    if (lignes.isEmpty) return null;

    final premiere = lignes.first;
    final comptes = await _comptes();
    final parCompte = <String, String>{
      comptes.reserveLegale: 'reserve_legale',
      comptes.autresReserves: 'autres_reserves',
      comptes.dividendes: 'dividendes',
      comptes.reportCrediteur: 'report_a_nouveau',
    };
    final ventilation = <String, int>{};
    var resultat = 0;
    for (final l in lignes) {
      final compte = await _dao.compteParId(l.compteId);
      final numero = compte?.numero ?? '';
      if (numero == comptes.benefice) {
        resultat = l.debitCentimes;
        continue;
      }
      if (numero == comptes.perte) {
        resultat = -l.creditCentimes;
        continue;
      }
      final beneficiaire = resultat >= 0;
      final poste = numero == comptes.reportDebiteur
          ? 'report_a_nouveau'
          : (!beneficiaire && numero == comptes.reportCrediteur)
          ? 'imputation_report_crediteur'
          : parCompte[numero];
      if (poste == null) continue;
      final montant = beneficiaire ? l.creditCentimes : l.debitCentimes;
      if (montant > 0) ventilation[poste] = (ventilation[poste] ?? 0) + montant;
    }
    final auteur = await (_db.select(
      _db.utilisateursLocal,
    )..where((u) => u.id.equals(premiere.creePar))).getSingleOrNull();
    return AffectationPassee(
      numeroPiece: premiere.numeroPiece ?? '—',
      dateApprobation: premiere.dateEcriture,
      passeeLe: premiere.creeLe,
      auteur: auteur == null
          ? '—'
          : libelleAuteurCompte(auteur.login, supprimeLe: auteur.supprimeLe),
      ventilation: ventilation,
    );
  }

  /// Les lignes d'origine de la pièce d'affectation de [annee] dans [suivant],
  /// SANS contre-passation : vide quand aucune affectation n'est active.
  Future<List<EcritureComptable>> _lignesActives(
    int annee,
    ExerciceComptable suivant,
  ) async {
    final candidates = await _dao.lignesParLibelle(
      libellePieceAffectation(annee),
    );
    return [
      for (final l in candidates)
        if (l.exerciceId == suivant.id &&
            l.ecritureContrepasseeId == null &&
            l.statut == StatutEcriture.validee &&
            !await _dao.dejaContrepassee(l.id))
          l,
    ];
  }

  /// La carte de l'exercice [exerciceId] — `null` tant qu'il n'est pas clôturé
  /// avec une clôture active (rien à affecter).
  Future<EtatAffectation?> etat(String exerciceId) async {
    final exercice = await _dao.exercice(exerciceId);
    if (exercice == null || exercice.statut != StatutExercice.cloture) {
      return null;
    }
    final cloture = await _clotures.clotureActive(exercice.id);
    if (cloture == null) return null;

    final resultat = cloture.resultatCentimes;
    final suivant = await _dao.exerciceDeLAnnee(exercice.annee + 1);
    final active = await this.active(exercice.id);
    final comptes = await _comptes();
    final proposition = suivant == null
        ? proposerVentilation(
            resultatCentimes: resultat,
            capitalCentimes: 0,
            reserveLegaleCentimes: 0,
          )
        : proposerVentilation(
            resultatCentimes: resultat,
            capitalCentimes: await _soldeCrediteur(
              suivant.id,
              prefixes: prefixesCapital,
            ),
            reserveLegaleCentimes: await _soldeCrediteur(
              suivant.id,
              exact: comptes.reserveLegale,
            ),
          );
    return EtatAffectation(
      annee: exercice.annee,
      anneeAffectation: exercice.annee + 1,
      resultatCentimes: resultat,
      compteResultat: resultat >= 0 ? comptes.benefice : comptes.perte,
      exerciceAffectation: suivant,
      affectable:
          active == null &&
          suivant != null &&
          suivant.statut == StatutExercice.ouvert &&
          resultat != 0,
      active: active,
      dateParDefaut: _dateParDefaut(exercice.annee + 1),
      proposition: proposition.ventilation,
      reserveLegalePropose: proposition.reserveLegalePropose,
      plafondReserveLegaleAtteint: proposition.plafondAtteint,
    );
  }

  /// Aujourd'hui s'il est dans N, sinon la borne de N la plus proche.
  String _dateParDefaut(int annee) {
    final aujourdhui = _maintenant();
    if (aujourdhui.year == annee) return formaterDateIso(aujourdhui);
    return aujourdhui.year > annee ? '$annee-12-31' : '$annee-01-01';
  }

  /// Solde créditeur d'un compte (ou des comptes d'un préfixe) dans l'exercice,
  /// écritures validées, contre-passations comprises.
  Future<int> _soldeCrediteur(
    String exerciceId, {
    List<String> prefixes = const [],
    String? exact,
  }) async {
    var total = 0;
    for (final s in await _dao.soldesDeBilan(exerciceId)) {
      final retenu = exact != null
          ? s.numero == exact
          : prefixes.any(s.numero.startsWith);
      if (retenu) total += s.creditCentimes - s.debitCentimes;
    }
    return total;
  }

  /* ================================================================== */
  /* Les gestes                                                          */
  /* ================================================================== */

  RefusComptable _refus(
    MotifRefus motif,
    String cle, [
    Map<String, String> variables = const {},
  ]) => RefusComptable(
    motif,
    MessagesAffectation.dire('comptabilite.$cle', variables),
  );

  Future<void> _exigerComptable(String auteurId) async {
    final role =
        await (_db.select(_db.utilisateursLocal)
              ..where((u) => u.id.equals(auteurId)))
            .map((u) => u.role)
            .getSingleOrNull();
    if (role != roleAffectation) {
      throw _refus(MotifRefus.affectationReservee, 'affectation_reservee');
    }
  }

  /// Passe l'affectation du résultat de [exerciceId] (N-1) : le comptable seul,
  /// exercice clôturé, une seule affectation active, date dans N ouvert,
  /// ventilation à la somme exacte. Rend le numéro de la pièce (celui de ce
  /// poste : le serveur passe la sienne, sous son numéro).
  Future<String> affecter(
    String exerciceId, {
    required Map<String, int> ventilation,
    required String date,
    required String auteurId,
  }) async {
    await _exigerComptable(auteurId);
    return _db.transaction(() async {
      final exercice = await _dao.exercice(exerciceId);
      final annee = exercice?.annee ?? 0;
      final cloture =
          exercice == null || exercice.statut != StatutExercice.cloture
          ? null
          : await _clotures.clotureActive(exercice.id);
      if (exercice == null || cloture == null) {
        throw _refus(
          MotifRefus.affectationExigeCloture,
          'affectation_exige_cloture',
          {'annee': '$annee'},
        );
      }
      final resultat = cloture.resultatCentimes;
      if (resultat == 0) {
        throw _refus(
          MotifRefus.affectationResultatNul,
          'affectation_resultat_nul',
          {'annee': '$annee'},
        );
      }
      final existante = await active(exercice.id);
      if (existante != null) {
        throw _refus(
          MotifRefus.affectationDejaPassee,
          'affectation_deja_passee',
          {'annee': '$annee', 'piece': existante.numeroPiece},
        );
      }

      final suivant = await _exerciceDeLaDate(exercice, date);
      final comptes = await _comptes();
      final montants = controlerVentilation(
        ventilation: ventilation,
        resultatCentimes: resultat,
        soldesImputables: {
          'autres_reserves': await _soldeCrediteur(
            suivant.id,
            exact: comptes.autresReserves,
          ),
          'imputation_report_crediteur': await _soldeCrediteur(
            suivant.id,
            exact: comptes.reportCrediteur,
          ),
        },
      );

      final structure = await _dao.centreParLibelle(centreDeCloture);
      if (structure == null) {
        throw _refus(
          MotifRefus.affectationCentreAbsent,
          'affectation_centre_absent',
          {'centre': centreDeCloture},
        );
      }
      final lignes = lignesAffectation(
        resultatCentimes: resultat,
        montants: montants,
        comptes: comptes,
      );
      final piece = await _moteur.saisirPiece(
        DemandePiece(
          journal: journalAffectation,
          date: date,
          libelle: libellePieceAffectation(annee),
          lignes: [
            for (final l in lignes)
              LigneDemandee(
                compte: l.compte,
                debitCentimes: l.debit,
                creditCentimes: l.credit,
                centreId: structure.id,
              ),
          ],
          statutsExerciceAdmis: const {StatutExercice.ouvert},
        ),
        auteurId: auteurId,
        valider: true,
        affectation: (annee: annee, ventilation: montants),
      );
      return piece.first.numeroPiece!;
    });
  }

  /// L'exercice N qui reçoit la pièce : celui qui suit [exercice], OUVERT, et
  /// qui couvre la date d'approbation.
  Future<ExerciceComptable> _exerciceDeLaDate(
    ExerciceComptable exercice,
    String date,
  ) async {
    final forme = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(date);
    DateTime? jour;
    if (forme != null) {
      final y = int.parse(forme.group(1)!);
      final m = int.parse(forme.group(2)!);
      final d = int.parse(forme.group(3)!);
      final candidat = DateTime.utc(y, m, d);
      if (candidat.year == y && candidat.month == m && candidat.day == d) {
        jour = candidat;
      }
    }
    if (jour == null) {
      throw _refus(MotifRefus.affectationDate, 'affectation_date_invalide', {
        'date': date,
      });
    }
    final suivant = await _dao.exerciceDeLAnnee(exercice.annee + 1);
    if (suivant == null || jour.year != suivant.annee) {
      throw _refus(
        MotifRefus.affectationDate,
        'affectation_date_hors_exercice',
        {'date': date, 'annee': '${exercice.annee + 1}'},
      );
    }
    if (suivant.statut != StatutExercice.ouvert) {
      throw _refus(
        MotifRefus.affectationDate,
        'affectation_exercice_non_ouvert',
        {'annee': '${suivant.annee}', 'statut': suivant.statut.valeur},
      );
    }
    return suivant;
  }

  /// La CONTRE-PASSATION de l'affectation active de [exerciceId] (N-1) : le
  /// comptable seul, motif de dix caractères au moins. La pièce d'affectation
  /// est inversée ligne à ligne (rien ne s'efface, RG-11) ; l'exercice peut
  /// ensuite être affecté de nouveau. Enfile la demande `annuler_affectation`.
  Future<void> contrepasser(
    String exerciceId, {
    required String auteurId,
    required String motif,
  }) async {
    await _exigerComptable(auteurId);
    final propre = motif.trim();
    if (propre.runes.length < longueurMinMotifAffectation) {
      throw _refus(MotifRefus.affectationMotif, 'affectation_motif', {
        'min': '$longueurMinMotifAffectation',
      });
    }
    await _db.transaction(() async {
      final exercice = await _dao.exercice(exerciceId);
      final suivant = exercice == null
          ? null
          : await _dao.exerciceDeLAnnee(exercice.annee + 1);
      final lignes = exercice == null || suivant == null
          ? <EcritureComptable>[]
          : await _lignesActives(exercice.annee, suivant);
      if (exercice == null || suivant == null || lignes.isEmpty) {
        throw _refus(MotifRefus.affectationAucune, 'affectation_aucune', {
          'annee': '${exercice?.annee ?? 0}',
        });
      }
      if (suivant.statut == StatutExercice.cloture) {
        throw _refus(
          MotifRefus.affectationExerciceClos,
          'affectation_contrepassation_exercice_clos',
          {'annee': '${exercice.annee}', 'suivant': '${suivant.annee}'},
        );
      }
      await _moteur.contrepasserPiece(
        lignes,
        auteurId: auteurId,
        motif: MessagesAffectation.dire(
          'comptabilite.libelle_contrepassation_affectation',
          {'annee': '${exercice.annee}', 'motif': propre},
        ),
      );
      await OperationsSyncDao(_db).enfiler(
        table: TableSynchronisee.demandesClotureExercice,
        entiteId: _uuid.v4(),
        type: TypeOperationSync.creation,
        payload: chargeDemandeCloture(
          annee: exercice.annee,
          action: 'annuler_affectation',
          motif: propre,
        ),
      );
    });
  }

  /// L'affectation active de l'exercice [annee] ou `null` — lue par la
  /// RÉOUVERTURE (`ClotureExerciceLocale.rouvrir`).
  Future<AffectationPassee?> activePourAnnee(int annee) async {
    final exercice = await _dao.exerciceDeLAnnee(annee);
    return exercice == null ? null : active(exercice.id);
  }
}
