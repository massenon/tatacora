import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/format/auteur_compte.dart';
import '../../../core/rbac/regles_roles.dart';
import '../../synchronisation/data/operations_sync_dao.dart';
import '../../synchronisation/domain/charges_synchronisation.dart';
import '../../synchronisation/domain/operation_sync.dart';
import '../domain/affectation_resultat.dart';
import '../domain/cloture_exercice.dart';
import '../domain/entities/comptabilite.dart';
import '../domain/forme_juridique.dart';
import '../domain/messages_affectation.dart';
import '../domain/refus_comptable.dart';
import 'affectations_recues_dao.dart';
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
    this.parAilleurs = false,
  });

  final String numeroPiece;

  /// `AAAA-MM-JJ`.
  final String dateApprobation;
  final DateTime passeeLe;
  final String auteur;

  /// Centimes par poste de [postesAffectation] (les postes non nuls seulement).
  final Map<String, int> ventilation;

  /// `true` : l'affectation a été passée AILLEURS (le web, un autre poste) et ce poste
  /// la connaît par la descente — il n'en détient pas la pièce, il ne sait donc pas la
  /// contre-passer ; elle se contre-passe là où elle a été passée, et redescend.
  final bool parAilleurs;
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
    required this.forme,
    this.alertes = const [],
    this.avertissements = const [],
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

  /// La forme juridique de l'établissement, lue du paramètre descendu du serveur.
  final FormeJuridique forme;

  /// L'alerte de l'article 664 (non bloquante) et les avertissements : à lire sur la carte.
  final List<String> alertes;
  final List<String> avertissements;

  bool get estBenefice => resultatCentimes >= 0;
  int get resultatAbsoluCentimes =>
      resultatCentimes >= 0 ? resultatCentimes : -resultatCentimes;

  /// Les postes OFFERTS : une entreprise individuelle n'offre ni réserve légale ni dividendes.
  List<String> get postes => postesOfferts(forme, benefice: estBenefice);

  /// Le poste qui reçoit LE RESTE (compte de l'exploitant, ou report à nouveau).
  String get posteDuReste => posteDuResteDe(forme);
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
/// ## Comment le poste reconnaît les affectations (v53, 09/11/2026)
///
/// DEUX sources, jamais deux affichages d'une même affectation :
///
///  1. celles que CE poste a passées : leur pièce porte le libellé
///     `comptabilite.libelle_affectation_resultat` de l'exercice, dans N ; elle
///     est ACTIVE tant qu'aucune de ses lignes n'est contre-passée ;
///  2. celles que le serveur connaît — passées au web, par un autre poste, ou par
///     celui-ci une fois reprises — descendues dans `affectations_resultat_local`
///     ([AffectationsRecuesDao]) avec leur statut (active / contre-passée), leur
///     auteur, leur date et leur ventilation.
///
/// Le lien est l'IDENTIFIANT D'ORIGINE de la pièce (`piece_origine_id` du serveur =
/// `pieces_saisie_local.id`, comme pour toute pièce saisie à la main) : une
/// affectation reçue qui porte l'identifiant d'une pièce de ce poste EST cette pièce,
/// elle ne s'affiche pas deux fois ; si le serveur la dit contre-passée (au web),
/// elle n'est plus active ici, même si les lignes du journal du poste n'ont pas bougé.
/// Une affectation reçue sans pièce de ce poste (identifiant absent ou inconnu) vient
/// d'ailleurs : active tant que `contrepassee_le` est vide. Le serveur reste le juge de
/// l'unicité ; le poste la connaît aussi, et ne propose plus « Passer l'affectation ».
///
/// Écart nommé : une pièce saisie à la main avec le libellé exact de l'affectation,
/// dans N, passerait encore pour la pièce du poste tant que le serveur ne l'a pas
/// reprise comme affectation (il la refuserait).
///
/// ## Le résultat, quand la clôture a été faite ailleurs
///
/// Le poste lit le résultat sur SA clôture. Un exercice clôturé au serveur (ou par un
/// autre poste) n'a pas de clôture ici : la ligne d'affectation reçue porte alors le
/// résultat (`resultat`, signé) — celle qui est ACTIVE (une réouverture est refusée
/// tant qu'elle l'est), ou, contre-passée, seulement si elle a été passée APRÈS la
/// clôture que l'exercice porte (une réouverture puis une nouvelle clôture changerait
/// le résultat). Sinon la carte n'existe pas, comme avant.
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
    exploitant: await _dao.compteDuRole('COMPTE_EXPLOITANT'),
  );

  /// La forme juridique, lue du paramètre DESCENDU du serveur
  /// (`parametres_systeme_local`) ; absente ou illisible : l'entreprise individuelle,
  /// le défaut du Gîte (`FormeJuridique::courante`).
  Future<FormeJuridique> forme() async {
    final ligne = await (_db.select(
      _db.parametresSystemeLocal,
    )..where((p) => p.cle.equals(cleFormeJuridique))).getSingleOrNull();
    return FormeJuridique.depuisCode(ligne?.valeur);
  }

  /// La SITUATION de N lue sur ses écritures validées (à-nouveaux compris) — voir
  /// [SituationCapitaux] (`AffectationResultatService::situation`).
  Future<SituationCapitaux> _situation(String exerciceId) async {
    final comptes = await _comptes();
    final solde = await _dao.soldesDeBilan(exerciceId);
    int somme(bool Function(String numero) retenu) => solde
        .where((s) => retenu(s.numero))
        .fold<int>(0, (t, s) => t + s.creditCentimes - s.debitCentimes);
    bool prefixe(String numero, List<String> prefixes) =>
        prefixes.any(numero.startsWith);
    final debitNet = somme((n) => prefixe(n, prefixesPertesAnterieures));
    return (
      capital: somme((n) => prefixe(n, prefixesCapital)),
      reserveLegale: somme((n) => n == comptes.reserveLegale),
      reservesNonDistribuables: somme(
        (n) => prefixe(n, prefixesReservesNonDistribuables),
      ),
      pertesAnterieures: debitNet < 0 ? -debitNet : 0,
      capitauxPropres: somme((n) => prefixe(n, prefixesCapitauxPropres)),
    );
  }

  /// L'affectation ACTIVE de l'exercice [exerciceId] (N-1), ou `null` : celle de ce
  /// poste (sa pièce, encore entière) ou celle que le serveur a descendue — voir
  /// l'en-tête de la classe pour le lien entre les deux.
  Future<AffectationPassee?> active(String exerciceId) async {
    final exercice = await _dao.exercice(exerciceId);
    if (exercice == null) return null;
    final suivant = await _dao.exerciceDeLAnnee(exercice.annee + 1);
    final lignes = suivant == null
        ? <EcritureComptable>[]
        : await _lignesActives(exercice.annee, suivant);
    final recues = await AffectationsRecuesDao(_db).deLAnnee(exercice.annee);

    // Les pièces de CE poste que le serveur a reprises : identifiant d'origine -> numéro.
    final origines = {
      for (final r in recues)
        if (r.pieceOrigineId != null) r.pieceOrigineId!,
    };
    final numeroDeLOrigine = <String, String>{};
    if (origines.isNotEmpty) {
      for (final p in await (_db.select(
        _db.piecesSaisieLocal,
      )..where((p) => p.id.isIn(origines))).get()) {
        numeroDeLOrigine[p.id] = p.numeroPiece;
      }
    }
    final parNumero = <String, List<EcritureComptable>>{};
    for (final l in lignes) {
      parNumero.putIfAbsent(l.numeroPiece ?? '', () => []).add(l);
    }

    // 1. Une ligne reçue ACTIVE : celle d'ici (sa pièce encore entière) ou d'ailleurs.
    for (final r in recues) {
      if (r.contrepassee) continue;
      final numero = numeroDeLOrigine[r.pieceOrigineId];
      if (numero == null) return _passeeAilleurs(r);
      final siennes = parNumero[numero];
      if (siennes != null) return _passeeIci(siennes);
      // Sa pièce est contre-passée ICI, la demande n'est pas encore acceptée : elle
      // n'est plus active pour ce poste.
    }

    // 2. Les pièces d'ici que le serveur n'a pas encore reprises (ou jamais acceptées) ;
    // une pièce que le serveur dit contre-passée n'en fait pas partie.
    final contrepassees = {
      for (final r in recues)
        if (r.contrepassee && numeroDeLOrigine[r.pieceOrigineId] != null)
          numeroDeLOrigine[r.pieceOrigineId]!,
    };
    final reprises = {
      for (final r in recues)
        if (numeroDeLOrigine[r.pieceOrigineId] != null)
          numeroDeLOrigine[r.pieceOrigineId]!,
    };
    for (final e in parNumero.entries) {
      if (contrepassees.contains(e.key) || reprises.contains(e.key)) continue;
      return _passeeIci(e.value);
    }
    return null;
  }

  /// L'affectation que le serveur a descendue et dont ce poste n'a pas la pièce.
  AffectationPassee _passeeAilleurs(AffectationRecueDuServeur r) {
    final benefice = r.resultatCentimes >= 0;
    final ventilation = <String, int>{
      if (r.reserveLegaleCentimes > 0)
        'reserve_legale': r.reserveLegaleCentimes,
      if (r.autresReservesCentimes > 0)
        'autres_reserves': r.autresReservesCentimes,
      if (r.dividendesCentimes > 0) 'dividendes': r.dividendesCentimes,
      // Bénéfice : report créditeur ; perte : imputation sur le report créditeur,
      // et report débiteur (`AffectationResultatService::affecter`).
      if (r.reportCrediteurCentimes > 0)
        (benefice ? 'report_a_nouveau' : 'imputation_report_crediteur'):
            r.reportCrediteurCentimes,
      if (r.reportDebiteurCentimes > 0)
        'report_a_nouveau': r.reportDebiteurCentimes,
    };
    // Le COMPTE DE L'EXPLOITANT (entreprise individuelle) : la descente ne porte pas
    // cette colonne (aucun changement de schéma) ; la ventilation égalant le résultat
    // EXACTEMENT, il est ce qui reste une fois les autres postes retirés.
    final absolu = benefice ? r.resultatCentimes : -r.resultatCentimes;
    final reste = absolu - ventilation.values.fold<int>(0, (t, m) => t + m);
    if (reste > 0) ventilation['compte_exploitant'] = reste;
    return AffectationPassee(
      numeroPiece: r.numeroPiece,
      dateApprobation: r.dateApprobation,
      passeeLe: r.affecteeLe,
      auteur: r.auteurLogin ?? '—',
      ventilation: ventilation,
      parAilleurs: true,
    );
  }

  /// L'affectation passée par CE poste, relue des lignes de sa pièce.
  Future<AffectationPassee> _passeeIci(List<EcritureComptable> lignes) async {
    final premiere = lignes.first;
    final comptes = await _comptes();
    final parCompte = <String, String>{
      comptes.reserveLegale: 'reserve_legale',
      comptes.autresReserves: 'autres_reserves',
      comptes.dividendes: 'dividendes',
      comptes.reportCrediteur: 'report_a_nouveau',
      comptes.exploitant: 'compte_exploitant',
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

  /// Le résultat à affecter de l'exercice clôturé [exercice] : celui de SA clôture
  /// (la clôture de ce poste), à défaut celui de l'affectation que le serveur a
  /// descendue quand la clôture a été faite ailleurs (voir l'en-tête de la classe) ;
  /// `null` si aucun des deux ne dit le résultat de la clôture en cours.
  Future<int?> _resultatDe(ExerciceComptable exercice) async {
    final cloture = await _clotures.clotureActive(exercice.id);
    if (cloture != null) return cloture.resultatCentimes;
    final recues = await AffectationsRecuesDao(_db).deLAnnee(exercice.annee);
    if (recues.isEmpty) return null;
    final derniere = recues.first;
    if (!derniere.contrepassee) return derniere.resultatCentimes;
    // Contre-passée : valable seulement si elle date de la clôture que l'exercice
    // porte (horloge du serveur des deux côtés, lue sans conversion).
    final cloturee = exercice.dateCloture;
    if (cloturee == null) return null;
    return cloturee.isAfter(derniere.affecteeLe)
        ? null
        : derniere.resultatCentimes;
  }

  /// La carte de l'exercice [exerciceId] — `null` tant qu'il n'est pas clôturé
  /// avec une clôture active (rien à affecter).
  Future<EtatAffectation?> etat(String exerciceId) async {
    final exercice = await _dao.exercice(exerciceId);
    if (exercice == null || exercice.statut != StatutExercice.cloture) {
      return null;
    }
    final resultat = await _resultatDe(exercice);
    if (resultat == null) return null;

    final suivant = await _dao.exerciceDeLAnnee(exercice.annee + 1);
    final active = await this.active(exercice.id);
    final comptes = await _comptes();
    final forme = await this.forme();
    final situation = suivant == null ? null : await _situation(suivant.id);
    final proposition = proposerVentilation(
      forme: forme,
      resultatCentimes: resultat,
      situation: situation,
      soldeReportCrediteur: suivant == null
          ? 0
          : await _soldeCrediteur(suivant.id, exact: comptes.reportCrediteur),
      soldeAutresReserves: suivant == null
          ? 0
          : await _soldeCrediteur(suivant.id, exact: comptes.autresReserves),
    );
    final alertes = <String>[];
    final avertissements = <String>[];
    if (situation != null && forme.estSociete) {
      final alerte = alerteMoitieCapital(situation, resultat);
      if (alerte != null) alertes.add(alerte);
      if (resultat >= 0 && situation.capital <= 0) {
        avertissements.add(
          MessagesAffectation.dire(
            'comptabilite.affectation_avertissement_capital_indetermine',
          ),
        );
      }
    }
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
      forme: forme,
      alertes: alertes,
      avertissements: avertissements,
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
    if (!estComptableOuGerant(role)) {
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
      final resultatDeLaCloture =
          exercice == null || exercice.statut != StatutExercice.cloture
          ? null
          : await _resultatDe(exercice);
      if (exercice == null || resultatDeLaCloture == null) {
        throw _refus(
          MotifRefus.affectationExigeCloture,
          'affectation_exige_cloture',
          {'annee': '$annee'},
        );
      }
      final resultat = resultatDeLaCloture;
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

      final forme = await this.forme();
      final suivant = await _exerciceDeLaDate(exercice, date);
      final comptes = await _comptes();
      final controle = controlerVentilation(
        forme: forme,
        ventilation: ventilation,
        resultatCentimes: resultat,
        situation: await _situation(suivant.id),
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
      final montants = controle.montants;

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
  /// comptable seul, motif de dix caractères au moins, référence de la décision
  /// ([reference] : PV d'assemblée / décision de l'exploitant) FACULTATIVE, transmise
  /// au serveur pour son journal d'audit.
  ///
  /// La pièce d'affectation est inversée ligne à ligne (rien ne s'efface, RG-11) :
  ///  - à la date du JOUR de la correction, qui doit tomber dans l'exercice N, OUVERT,
  ///    et n'est jamais antérieure à la pièce d'origine ;
  ///  - REFUSÉE si un dividende de l'affectation est déjà réglé en tout ou partie (le
  ///    compte des dividendes à payer n'est plus au montant affecté) : « annulez
  ///    d'abord le règlement ».
  ///
  /// L'exercice peut ensuite être affecté de nouveau. Enfile la demande
  /// `annuler_affectation`.
  Future<void> contrepasser(
    String exerciceId, {
    required String auteurId,
    required String motif,
    String? reference,
  }) async {
    await _exigerComptable(auteurId);
    final propre = motif.trim();
    if (propre.runes.length < longueurMinMotifAffectation) {
      throw _refus(MotifRefus.affectationMotif, 'affectation_motif', {
        'min': '$longueurMinMotifAffectation',
      });
    }
    final reponse = reference?.trim();
    final referenceDecision = reponse == null || reponse.isEmpty
        ? null
        : reponse;
    if (referenceDecision != null &&
        referenceDecision.runes.length > longueurMaxReferenceDecision) {
      throw _refus(
        MotifRefus.affectationReference,
        'affectation_reference_trop_longue',
        {'max': '$longueurMaxReferenceDecision'},
      );
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
      if (suivant.statut != StatutExercice.ouvert) {
        throw _refus(
          MotifRefus.affectationExerciceClos,
          'affectation_contrepassation_exercice_non_ouvert',
          {
            'annee': '${exercice.annee}',
            'suivant': '${suivant.annee}',
            'statut': suivant.statut.valeur,
          },
        );
      }

      // La date de la correction : AUJOURD'HUI, dans N, jamais avant la pièce d'origine.
      final maintenant = _maintenant();
      final jour = formaterDateIso(maintenant);
      if (maintenant.year != suivant.annee) {
        throw _refus(
          MotifRefus.affectationDate,
          'affectation_contrepassation_date_hors_exercice',
          {'date': jour, 'suivant': '${suivant.annee}'},
        );
      }
      final origine = lignes.first.dateEcriture;
      if (jour.compareTo(origine) < 0) {
        throw _refus(
          MotifRefus.affectationDate,
          'affectation_contrepassation_anterieure',
          {'date': jour, 'origine': origine},
        );
      }

      // Un dividende réglé (le compte des dividendes à payer a été débité) : on
      // annule d'abord le règlement.
      final dividendes = (await _passeeIci(lignes)).ventilation['dividendes'];
      if (dividendes != null && dividendes > 0) {
        final comptes = await _comptes();
        final reste = await _soldeCrediteur(
          suivant.id,
          exact: comptes.dividendes,
        );
        final regle = dividendes - reste;
        if (regle > 0) {
          throw _refus(
            MotifRefus.affectationDividendeRegle,
            'affectation_dividende_regle',
            {
              'annee': '${exercice.annee}',
              'regle': _decimal(regle),
              'dividendes': _decimal(dividendes),
            },
          );
        }
      }

      await _moteur.contrepasserPiece(
        lignes,
        auteurId: auteurId,
        date: jour,
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
          referenceDecision: referenceDecision,
        ),
      );
    });
  }

  /// Les centimes en décimal à deux chiffres, comme `bcadd(.., '0', 2)`.
  static String _decimal(int centimes) {
    final negatif = centimes < 0;
    final abs = negatif ? -centimes : centimes;
    return '${negatif ? '-' : ''}${abs ~/ 100}.${(abs % 100).toString().padLeft(2, '0')}';
  }

  /// Une affectation est-elle ACTIVE, tous exercices confondus ? C'est la garde du
  /// serveur sur la forme juridique (`AffectationResultat::whereNull('contrepassee_le')
  /// ->exists()`), lue ici par le changement de forme (`EnregistrerParametres`) : la
  /// forme ne se change pas sous une pièce passée sous l'ancienne.
  Future<bool> existeUneActive() async {
    for (final e in await _dao.exercices()) {
      if (await active(e.id) != null) return true;
    }
    return false;
  }

  /// L'affectation active de l'exercice [annee] ou `null` — lue par la
  /// RÉOUVERTURE (`ClotureExerciceLocale.rouvrir`).
  Future<AffectationPassee?> activePourAnnee(int annee) async {
    final exercice = await _dao.exerciceDeLAnnee(annee);
    return exercice == null ? null : active(exercice.id);
  }
}
