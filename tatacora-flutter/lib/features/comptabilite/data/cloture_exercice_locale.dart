import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../synchronisation/data/operations_sync_dao.dart';
import '../../synchronisation/domain/charges_synchronisation.dart';
import '../../synchronisation/domain/operation_sync.dart';
import '../domain/cloture_exercice.dart';
import '../domain/comptes_syscohada.dart';
import '../domain/entities/comptabilite.dart';
import '../domain/etats_financiers.dart';
import '../domain/messages_cloture.dart';
import '../domain/messages_comptables.dart' show PhrasesDuPoste;
import '../domain/refus_comptable.dart';
import 'comptabilite_dao.dart';
import 'moteur_comptable.dart';

/// Les gestes de la CLÔTURE ANNUELLE SYSCOHADA sur le poste — réplique de
/// `ClotureExerciceService` du serveur (26/10/2026, décision du PO : « la
/// clôture annuelle SYSCOHADA DOIT ÊTRE IMPLÉMENTÉE EN POSTE ET WEB »).
///
/// ## Le cycle d'un exercice (le même qu'au serveur)
///
///     ouvert ──démarrer──▶ en_cloture ──clôturer──▶ cloture
///       ▲                     │   ▲                     │
///       └──reprendre saisie───┘   └───────rouvrir───────┘ (comptable, motif)
///
///  - **démarrer** : les modules ne passent plus de pièce dans N (le moteur
///    n'admet que `ouvert`) ; seules les écritures d'inventaire du comptable y
///    entrent ; l'exercice N+1 s'ouvre s'il manque ;
///  - **clôturer**, dans UNE transaction : la liste de contrôle doit être
///    réunie (aucun brouillon, balance et bilan équilibrés, journaux CL et AN,
///    comptes de résultat, centre « Structure ») et N-1 déjà clôturé ; (1) la
///    pièce de clôture au 31/12/N (journal CL) solde les comptes de gestion
///    CENTRE PAR CENTRE, la contrepartie va en 131 (bénéfice) ou 139 (perte) ;
///    (2) la pièce d'à-nouveaux au 01/01/N+1 (journal AN) reporte les soldes de
///    bilan, résultat compris ; (3) le statut passe à `cloture` (verrou RG-11bis,
///    trigger de la base) ; la clôture est consignée (`clotures_exercices_local`) ;
///  - **rouvrir** (LE COMPTABLE seul, motif ≥ 10 caractères) : les deux pièces
///    sont CONTRE-PASSÉES à leur propre date (rien ne s'efface, RG-11) et
///    l'exercice repasse `en_cloture` ; refusé si N+1 est déjà clôturé.
///
/// ## Toutes les pièces passent par le moteur
///
/// Ce service n'écrit AUCUNE ligne d'écriture lui-même : il demande des pièces
/// à [MoteurComptable], seul écrivain de `ecritures_local` (RG-11, RG-12, numéro
/// de pièce, centre obligatoire), et ne fait que changer le statut d'un exercice
/// et consigner la clôture. Un refus du moteur annule TOUT le geste.
///
/// ## Le poste ne clôture que SES pièces ; le serveur reste le seul comptable
///
/// Chaque geste enfile une DEMANDE au serveur (`demandes_cloture_exercice`,
/// dans la MÊME transaction) : il rejoue ses règles sur toutes les pièces de
/// l'établissement et passe SES pièces CL et AN, qui descendent ensuite. Le
/// poste ne lui envoie jamais une pièce (D246). Synchronisation désactivée, la
/// demande reste en file et partira à la réactivation. Écart nommé : le résultat
/// d'une clôture du poste est celui des pièces de CE poste ; si le serveur
/// refuse la demande (un brouillon d'un autre poste, un exercice précédent non
/// clôturé chez lui…), la clôture locale demeure et le refus se lit dans
/// « À traiter » de l'écran de synchronisation.
///
/// ## Les comptes de résultat suivent la correspondance du serveur
///
/// 131 (bénéfice) et 139 (perte) par défaut ; le serveur les rend modifiables
/// (paramètres `compte_resultat_benefice` / `compte_resultat_perte`, groupe
/// « résultat » de la correspondance des comptes) : le poste lit les mêmes
/// paramètres, avec les mêmes défauts.
class ClotureExerciceLocale {
  ClotureExerciceLocale(
    this._db,
    this._moteur, {
    DateTime Function()? maintenant,
    Uuid? uuid,
  }) : _dao = ComptabiliteDao(_db),
       _maintenant = maintenant ?? DateTime.now,
       _uuid = uuid ?? const Uuid();

  final AppDatabase _db;
  final MoteurComptable _moteur;
  final ComptabiliteDao _dao;
  final DateTime Function() _maintenant;
  final Uuid _uuid;

  /* ================================================================== */
  /* Lecture                                                             */
  /* ================================================================== */

  /// Les comptes qui reçoivent le résultat : ceux de la correspondance des
  /// comptes (rôles `RESULTAT_BENEFICE` et `RESULTAT_PERTE`, paramètres
  /// `compte_resultat_*`), à défaut 131 et 139 — la même lecture que le moteur,
  /// donc la même règle que `CorrespondanceComptesService` du serveur.
  Future<({String benefice, String perte})> comptesDeResultat() async => (
    benefice: await _dao.compteDuRole('RESULTAT_BENEFICE'),
    perte: await _dao.compteDuRole('RESULTAT_PERTE'),
  );

  /// La clôture ACTIVE de l'exercice (non rouverte), la plus récente, ou `null`.
  Future<ClotureExercice?> clotureActive(String exerciceId) async {
    final ligne =
        await (_db.select(_db.cloturesExercicesLocal)
              ..where(
                (c) => c.exerciceId.equals(exerciceId) & c.rouverteLe.isNull(),
              )
              ..orderBy([(c) => OrderingTerm.desc(c.clotureeLe)])
              ..limit(1))
            .getSingleOrNull();
    return ligne == null ? null : _cloture(ligne);
  }

  /// Toutes les clôtures du poste (actives et rouvertes), la plus récente
  /// d'abord.
  Future<List<ClotureExercice>> clotures() async => [
    for (final l in await (_db.select(
      _db.cloturesExercicesLocal,
    )..orderBy([(c) => OrderingTerm.desc(c.clotureeLe)])).get())
      _cloture(l),
  ];

  /// Les données des états : les pièces VALIDÉES de ce poste, par année.
  /// [anneeAvecBrouillons] : l'exercice jugé sur ses brouillons ET ses validées
  /// (la liste de contrôle de sa clôture).
  Future<DonneesEtats> donneesDesEtats({int? anneeAvecBrouillons}) async {
    final exercices = await _dao.exercices();
    return DonneesEtats(
      ecrituresParAnnee: await _dao.ecrituresValideesParAnnee(
        anneeAvecBrouillons: anneeAvecBrouillons,
      ),
      statutParAnnee: {for (final e in exercices) e.annee: e.statut},
      plan: await _dao.comptesDeReport(const [
        ComptesSyscohada.resultatBenefice,
        ComptesSyscohada.resultatPerte,
      ]),
      anneesAvecClotureActive: await _dao.anneesAvecClotureActive(),
    );
  }

  /// L'état de la procédure de clôture de [exerciceId] — la liste de contrôle,
  /// le résultat à reporter, ses avertissements (`EtatClotureService`).
  Future<EtatClotureLocal> etat(String exerciceId) async {
    final exercice = await _exercice(exerciceId);
    final comptes = await comptesDeResultat();
    final journaux = {for (final j in await _dao.journaux()) j.code};
    return etatDeCloture(
      annee: exercice.annee,
      statut: exercice.statut.valeur,
      donnees: await donneesDesEtats(anneeAvecBrouillons: exercice.annee),
      brouillons: await _dao.nombreDeBrouillons(exercice.id),
      referentiel: (
        journauxPresents:
            journaux.contains(journalDeCloture) &&
            journaux.contains(journalANouveaux),
        comptesDeResultatPresents:
            await _dao.compteParNumero(comptes.benefice) != null &&
            await _dao.compteParNumero(comptes.perte) != null,
        centreDeClotureEtPresent:
            await _dao.centreParLibelle(centreDeCloture) != null,
      ),
      compteBenefice: comptes.benefice,
      comptePerte: comptes.perte,
    );
  }

  /* ================================================================== */
  /* Les gestes                                                          */
  /* ================================================================== */

  /// ouvert → en_cloture ; ouvre N+1 s'il manque.
  Future<ExerciceComptable> demarrer(
    String exerciceId, {
    required String auteurId,
  }) => _db.transaction(() async {
    final exercice = await _exercice(exerciceId);
    if (exercice.statut != StatutExercice.ouvert) {
      throw _refus(
        MotifRefus.clotureDemarrageImpossible,
        'comptabilite.cloture_demarrage_impossible',
        {'annee': '${exercice.annee}', 'statut': exercice.statut.valeur},
      );
    }
    await _assurerSuivant(exercice);
    await _dao.changerStatutExercice(exercice.id, StatutExercice.enCloture);
    await _demander(exercice.annee, 'demarrer');
    return _exercice(exercice.id);
  });

  /// en_cloture → ouvert, tant que la clôture n'est pas passée.
  Future<ExerciceComptable> reprendreSaisie(
    String exerciceId, {
    required String auteurId,
  }) => _db.transaction(() async {
    final exercice = await _exercice(exerciceId);
    if (exercice.statut != StatutExercice.enCloture) {
      throw _refus(
        MotifRefus.clotureRepriseImpossible,
        'comptabilite.cloture_reprise_impossible',
        {'annee': '${exercice.annee}', 'statut': exercice.statut.valeur},
      );
    }
    await _dao.changerStatutExercice(exercice.id, StatutExercice.ouvert);
    await _demander(exercice.annee, 'reprendre_saisie');
    return _exercice(exercice.id);
  });

  /// La clôture DÉFINITIVE — voir l'en-tête.
  Future<ClotureExercice> cloturer(
    String exerciceId, {
    required String auteurId,
  }) => _db.transaction(() async {
    final exercice = await _exercice(exerciceId);
    if (exercice.statut != StatutExercice.enCloture) {
      throw _refus(
        MotifRefus.clotureExigeEnCloture,
        'comptabilite.cloture_exige_en_cloture',
        {'annee': '${exercice.annee}'},
      );
    }
    final precedent = await _dao.exerciceDeLAnnee(exercice.annee - 1);
    if (precedent != null && precedent.statut != StatutExercice.cloture) {
      throw _refus(MotifRefus.clotureOrdre, 'comptabilite.cloture_ordre', {
        'annee': '${exercice.annee}',
        'precedent': '${precedent.annee}',
      });
    }

    final etat = await this.etat(exercice.id);
    if (!etat.conditionsReunies) {
      throw _refus(
        MotifRefus.clotureConditionsNonReunies,
        'comptabilite.cloture_conditions_non_reunies',
        {
          'annee': '${exercice.annee}',
          'blocages': [
            for (final b in etat.blocages)
              MessagesCloture.dire('pwa.comptabilite.motifs.${b.code}'),
          ].join(', '),
        },
      );
    }

    final suivant = await _assurerSuivant(exercice);
    if (suivant.statut == StatutExercice.cloture) {
      throw _refus(
        MotifRefus.clotureSuivantClos,
        'comptabilite.cloture_suivant_clos',
        {'annee': '${suivant.annee}'},
      );
    }

    final structure = (await _dao.centreParLibelle(centreDeCloture))!.id;
    final comptes = await comptesDeResultat();

    // 1. Le solde des comptes de gestion, centre par centre.
    final cl = lignesDeCloture(
      await _dao.soldesDeGestion(exercice.id),
      centreStructureId: structure,
      compteBenefice: comptes.benefice,
      comptePerte: comptes.perte,
    );
    String? pieceCloture;
    if (cl.lignes.isNotEmpty) {
      final piece = await _moteur.passerEtValider(
        DemandePiece(
          journal: journalDeCloture,
          date: '${exercice.annee}-12-31',
          libelle: MessagesCloture.dire('comptabilite.libelle_piece_cloture', {
            'annee': '${exercice.annee}',
          }),
          lignes: _lignes(cl.lignes),
          statutsExerciceAdmis: const {StatutExercice.enCloture},
        ),
        auteurId: auteurId,
      );
      pieceCloture = piece.first.numeroPiece;
    }

    // 2. Les à-nouveaux : les soldes de bilan APRÈS la clôture.
    final an = lignesANouveaux(
      await _dao.soldesDeBilan(exercice.id),
      centreStructureId: structure,
    );
    String? pieceANouveaux;
    if (an.isNotEmpty) {
      final piece = await _moteur.passerEtValider(
        DemandePiece(
          journal: journalANouveaux,
          date: '${exercice.annee + 1}-01-01',
          libelle: MessagesCloture.dire(
            'comptabilite.libelle_piece_a_nouveaux',
            {'annee': '${exercice.annee}'},
          ),
          lignes: _lignes(an),
          statutsExerciceAdmis: const {
            StatutExercice.ouvert,
            StatutExercice.enCloture,
          },
        ),
        auteurId: auteurId,
      );
      pieceANouveaux = piece.first.numeroPiece;
    }

    // 3. Le verrou définitif, puis la clôture consignée.
    final quand = _maintenant();
    await _dao.changerStatutExercice(
      exercice.id,
      StatutExercice.cloture,
      clotureLe: quand,
      clotureParId: auteurId,
    );
    final id = _uuid.v4();
    await _db
        .into(_db.cloturesExercicesLocal)
        .insert(
          CloturesExercicesLocalCompanion.insert(
            id: id,
            exerciceId: exercice.id,
            pieceCloture: Value(pieceCloture),
            pieceANouveaux: Value(pieceANouveaux),
            resultatCentimes: cl.resultatCentimes,
            clotureePar: auteurId,
            clotureeLe: quand,
          ),
        );
    await _demander(exercice.annee, 'cloturer');
    return (await _cloturePar(id))!;
  });

  /// La RÉOUVERTURE contrôlée — le comptable seul, motif obligatoire.
  Future<ExerciceComptable> rouvrir(
    String exerciceId, {
    required String auteurId,
    required String motif,
  }) async {
    final role =
        await (_db.select(_db.utilisateursLocal)
              ..where((u) => u.id.equals(auteurId)))
            .map((u) => u.role)
            .getSingleOrNull();
    if (role != roleReouverture) {
      throw _refus(
        MotifRefus.reouvertureReservee,
        'comptabilite.reouverture_reservee',
      );
    }
    return _db.transaction(() async {
      final exercice = await _exercice(exerciceId);
      if (exercice.statut != StatutExercice.cloture) {
        throw _refus(
          MotifRefus.reouvertureNonCloture,
          'comptabilite.reouverture_non_cloture',
          {'annee': '${exercice.annee}'},
        );
      }
      final propre = motif.trim();
      if (!motifReouvertureValide(propre)) {
        throw _refus(
          MotifRefus.reouvertureMotif,
          'comptabilite.reouverture_motif',
          {'min': '$longueurMinMotifReouverture'},
        );
      }
      final suivant = await _dao.exerciceDeLAnnee(exercice.annee + 1);
      if (suivant != null && suivant.statut == StatutExercice.cloture) {
        throw _refus(
          MotifRefus.reouvertureSuivantClos,
          'comptabilite.reouverture_suivant_clos',
          {'annee': '${exercice.annee}', 'suivant': '${suivant.annee}'},
        );
      }

      // D'ABORD le statut : une contre-passation ne s'écrit pas dans un
      // exercice clôturé (RG-11bis, trigger de la base).
      await _dao.changerStatutExercice(exercice.id, StatutExercice.enCloture);

      final cloture = await clotureActive(exercice.id);
      if (cloture != null) {
        final libelle = MessagesCloture.dire(
          'comptabilite.libelle_reouverture',
          {'annee': '${exercice.annee}', 'motif': propre},
        );
        await _moteur.contrepasserPieceADateDOrigine(
          exercice.id,
          cloture.pieceCloture,
          libelle: libelle,
          auteurId: auteurId,
        );
        if (suivant != null) {
          await _moteur.contrepasserPieceADateDOrigine(
            suivant.id,
            cloture.pieceANouveaux,
            libelle: libelle,
            auteurId: auteurId,
          );
        }
        await (_db.update(
          _db.cloturesExercicesLocal,
        )..where((c) => c.id.equals(cloture.id))).write(
          CloturesExercicesLocalCompanion(
            rouvertePar: Value(auteurId),
            rouverteLe: Value(_maintenant()),
            motifReouverture: Value(propre),
          ),
        );
      }
      await _demander(exercice.annee, 'rouvrir', motif: propre);
      return _exercice(exercice.id);
    });
  }

  /// L'archive légale d'une clôture : son dossier et son empreinte, écrits UNE
  /// fois (une archive n'est jamais réécrite). Appelée par
  /// `ArchiveClotureLocale`, seule.
  Future<void> consignerArchive(
    String clotureId, {
    required String chemin,
    required String empreinte,
  }) async {
    final cloture = await _cloturePar(clotureId);
    if (cloture == null || cloture.archiveEmpreinte != null) return;
    await (_db.update(
      _db.cloturesExercicesLocal,
    )..where((c) => c.id.equals(clotureId))).write(
      CloturesExercicesLocalCompanion(
        archiveChemin: Value(chemin),
        archiveEmpreinte: Value(empreinte),
      ),
    );
  }

  /* ================================================================== */
  /* Interne                                                             */
  /* ================================================================== */

  RefusComptable _refus(
    MotifRefus motif,
    String cle, [
    Map<String, String> variables = const {},
  ]) => RefusComptable(motif, MessagesCloture.dire(cle, variables));

  Future<ExerciceComptable> _exercice(String id) async {
    final e = await _dao.exercice(id);
    if (e == null) {
      throw RefusComptable(
        MotifRefus.ecritureIntrouvable,
        PhrasesDuPoste.ecritureIntrouvable(id),
      );
    }
    return e;
  }

  /// L'exercice N+1, créé s'il manque (`assurer`). Hors de 2000-2100 : le
  /// refus du serveur (`exercice_annee_invalide`).
  Future<ExerciceComptable> _assurerSuivant(ExerciceComptable exercice) async {
    final suivant = await _dao.assurerExercice(exercice.annee + 1);
    if (suivant == null) {
      throw RefusComptable.dit(
        MotifRefus.exerciceAnneeInvalide,
        'comptabilite.exercice_annee_invalide',
      );
    }
    return suivant;
  }

  List<LigneDemandee> _lignes(List<LignePieceCloture> lignes) => [
    for (final l in lignes)
      LigneDemandee(
        compte: l.compte,
        centreId: l.centreId,
        debitCentimes: l.debitCentimes,
        creditCentimes: l.creditCentimes,
      ),
  ];

  /// Enfile la DEMANDE au serveur, dans la transaction du geste.
  Future<void> _demander(int annee, String action, {String? motif}) =>
      OperationsSyncDao(_db).enfiler(
        table: TableSynchronisee.demandesClotureExercice,
        entiteId: _uuid.v4(),
        type: TypeOperationSync.creation,
        payload: chargeDemandeCloture(
          annee: annee,
          action: action,
          motif: motif,
        ),
      );

  Future<ClotureExercice?> _cloturePar(String id) async {
    final ligne = await (_db.select(
      _db.cloturesExercicesLocal,
    )..where((c) => c.id.equals(id))).getSingleOrNull();
    return ligne == null ? null : _cloture(ligne);
  }

  ClotureExercice _cloture(ClotureExerciceLigne l) => ClotureExercice(
    id: l.id,
    exerciceId: l.exerciceId,
    pieceCloture: l.pieceCloture,
    pieceANouveaux: l.pieceANouveaux,
    resultatCentimes: l.resultatCentimes,
    clotureePar: l.clotureePar,
    clotureeLe: l.clotureeLe,
    archiveChemin: l.archiveChemin,
    archiveEmpreinte: l.archiveEmpreinte,
    rouvertePar: l.rouvertePar,
    rouverteLe: l.rouverteLe,
    motifReouverture: l.motifReouverture,
  );
}
