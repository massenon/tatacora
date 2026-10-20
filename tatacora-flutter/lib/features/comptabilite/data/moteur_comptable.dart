import '../domain/entities/comptabilite.dart';
import '../domain/messages_comptables.dart';
import '../domain/montant_comptable.dart';
import '../domain/refus_comptable.dart';
import '../domain/regles_ecriture.dart';
import 'comptabilite_dao.dart';

/// Une ligne de pièce telle que le module métier la demande : un NUMÉRO de
/// compte (jamais un identifiant), un débit OU un crédit en centimes, un
/// libellé optionnel et un centre optionnel.
final class LigneDemandee {
  const LigneDemandee({
    required this.compte,
    this.debitCentimes = 0,
    this.creditCentimes = 0,
    this.libelle,
    this.centreId,
  });

  /// La conversion EXPLICITE depuis les chaînes décimales du serveur
  /// (`"12500.00"`), tronquée comme `bcadd(.., '0', 2)`. Une chaîne illisible
  /// lève [RefusComptable] (`montantIllisible`).
  factory LigneDemandee.depuisMontants({
    required String compte,
    String? debit,
    String? credit,
    String? libelle,
    String? centreId,
  }) {
    int convertir(String? v) {
      if (v == null) return 0;
      try {
        return centimesDepuisChaine(v);
      } on FormatException {
        throw RefusComptable(
          MotifRefus.montantIllisible,
          PhrasesDuPoste.montantIllisible(v),
        );
      }
    }

    return LigneDemandee(
      compte: compte,
      debitCentimes: convertir(debit),
      creditCentimes: convertir(credit),
      libelle: libelle,
      centreId: centreId,
    );
  }

  final String compte;
  final int debitCentimes;
  final int creditCentimes;
  final String? libelle;
  final String? centreId;
}

/// Une pièce demandée : un CODE de journal, une date `AAAA-MM-JJ`, un libellé
/// et ses lignes.
final class DemandePiece {
  const DemandePiece({
    required this.journal,
    required this.date,
    required this.libelle,
    required this.lignes,
  });

  final String journal;
  final String date;
  final String libelle;
  final List<LigneDemandee> lignes;
}

/// Le moteur comptable du poste — RÉPLIQUE de `PasserEcritureService`,
/// `EcritureComptableService`, `ExerciceComptableService` et des écritures de
/// `PlanComptableService` du serveur.
///
/// ## Ce que ce moteur est, et ce qu'il n'est pas
///
/// C'est l'UNIQUE chemin d'écriture de `ecritures_local` : un module métier
/// (caisse, dépenses, ventes, encaissement — lots suivants) lui passe des CODES
/// (journal, numéro de compte, date) et il résout, vérifie, numérote et écrit.
/// Il ne porte AUCUN mouvement d'argent lui-même : aucun module n'y est branché
/// dans ce lot.
///
/// ## Quatre refus, aucun repli
///
/// Journal inconnu, compte inconnu, exercice absent ou non ouvert, centre
/// introuvable : chacun lève [RefusComptable] avec la phrase du serveur. Aucun
/// n'est remplacé par une valeur plausible : un compte « 601 » (division)
/// substitué au « 6011 » attendu imputerait une charge au mauvais poste sur une
/// pièce validée, donc immuable.
///
/// ## Tout ou rien
///
/// Chaque geste public tient dans UNE transaction. Un refus — y compris celui
/// d'un trigger de RG-11 à la dernière ligne — annule tout ce qui précède,
/// compteur de séquence compris.
///
/// ## Pas de contrôle de droit ici
///
/// Comme le serveur, le moteur ne connaît pas le RBAC : l'appelant a déjà vérifié
/// le droit du module qui déclenche le mouvement. Il exige en revanche un AUTEUR
/// (RG-15) : une pièce sans nom de qui l'a passée n'a pas de sens.
///
/// @see EF-M10-02 Saisie des écritures comptables
/// @see EF-M10-07 Clôture comptable périodique
/// @see RG-11 Immutabilité — portée par les triggers de la base
/// @see RG-12 Centre de coût obligatoire
class MoteurComptable {
  MoteurComptable(this._dao, {DateTime Function()? maintenant})
    : _maintenant = maintenant ?? DateTime.now;

  final ComptabiliteDao _dao;
  final DateTime Function() _maintenant;

  /// `AAAA-MM-JJ` de l'instant courant (`now()->toDateString()`).
  String aujourdhui() => formaterDateIso(_maintenant());

  /* ================================================================== */
  /* Passer une pièce                                                    */
  /* ================================================================== */

  /// Écrit une pièce en BROUILLON, à partir de codes métier.
  ///
  /// Les refus tombent dans l'ordre du serveur : journal, exercice, puis, ligne
  /// par ligne, compte (inconnu, puis division) et centre ; ensuite pièce vide,
  /// équilibre, et enfin les contraintes de ligne au moment d'écrire.
  Future<List<EcritureComptable>> passer(
    DemandePiece demande, {
    required String auteurId,
  }) async {
    _exigerAuteur(auteurId);
    return _dao.enTransaction(() async {
      final journal = await _dao.journalParCode(demande.journal);
      if (journal == null) {
        throw RefusComptable.dit(
          MotifRefus.journalInconnu,
          'depenses.journal_inconnu',
          {'code': demande.journal},
        );
      }
      // Passage d'année (20/10/2026) : un poste laissé allumé la nuit du
      // 31/12 n'attend plus son redémarrage — la première pièce de l'année
      // ouvre l'exercice qui manque, dans SA transaction (refusée, elle
      // n'ouvre rien).
      var exercices = await _dao.exercices();
      // Seulement une date RÉELLE dont l'année n'a aucun exercice ici : une
      // date impossible (« 2031-02-30 ») reste un refus, jamais un doublon.
      final anneePiece = DateTime.tryParse(demande.date)?.year;
      if (exerciceCouvrant(exercices, demande.date) == null &&
          anneePiece != null &&
          formaterDateIso(DateTime.parse(demande.date)) == demande.date &&
          !exercices.any((x) => x.annee == anneePiece) &&
          ouvertureAutomatiquePermise(anneePiece, _maintenant())) {
        await _dao.insererExercice(
          annee: anneePiece,
          dateDebut: '$anneePiece-01-01',
          dateFin: '$anneePiece-12-31',
        );
        exercices = await _dao.exercices();
      }
      final exercice = exerciceOuvertPour(exercices, demande.date);

      final resolues = <_LigneResolue>[];
      for (final ligne in demande.lignes) {
        final compte = await _compteImputable(ligne.compte);
        resolues.add(
          _LigneResolue(
            compte: compte,
            centreId: centrePour(
              centreExplicite: ligne.centreId,
              compte: compte,
            ),
            debitCentimes: ligne.debitCentimes,
            creditCentimes: ligne.creditCentimes,
            libelle: ligne.libelle ?? demande.libelle,
          ),
        );
      }

      verifierPieceNonVide(resolues.length);
      verifierEquilibre([
        for (final l in resolues)
          (debitCentimes: l.debitCentimes, creditCentimes: l.creditCentimes),
      ]);
      for (final l in resolues) {
        verifierContraintesDeLigne((
          debitCentimes: l.debitCentimes,
          creditCentimes: l.creditCentimes,
        ));
      }

      final annee = int.parse(demande.date.substring(0, 4));
      final rang = await _dao.allouerRang(journalId: journal.id, annee: annee);
      final numeroPiece = formaterNumeroPiece(journal.code, annee, rang);
      final creeLe = _maintenant();

      final ecrites = <EcritureComptable>[];
      for (final l in resolues) {
        ecrites.add(
          await _dao.insererEcriture(
            exerciceId: exercice.id,
            journalId: journal.id,
            compteId: l.compte.id,
            centreId: l.centreId,
            dateEcriture: demande.date,
            libelle: l.libelle,
            debitCentimes: l.debitCentimes,
            creditCentimes: l.creditCentimes,
            // Toute pièce naît en brouillon : la validation est un acte
            // distinct, qui rend l'écriture immuable (RG-11).
            statut: StatutEcriture.brouillon,
            ecritureContrepasseeId: null,
            numeroPiece: numeroPiece,
            creeLe: creeLe,
            creePar: auteurId,
          ),
        );
      }
      return ecrites;
    });
  }

  /// Écrit une pièce ET la valide, en une transaction.
  ///
  /// C'est le choix des mouvements d'argent : le geste métier est déjà
  /// irréversible quand on arrive ici (l'argent est sorti du tiroir), et toutes
  /// les lectures comptables filtrent `statut = 'validee'` — une pièce laissée
  /// en brouillon resterait invisible au grand livre, à la balance et au compte
  /// de résultat.
  Future<List<EcritureComptable>> passerEtValider(
    DemandePiece demande, {
    required String auteurId,
  }) async {
    _exigerAuteur(auteurId);
    return _dao.enTransaction(() async {
      final piece = await passer(demande, auteurId: auteurId);
      return valider(piece, auteurId: auteurId);
    });
  }

  /* ================================================================== */
  /* Valider                                                             */
  /* ================================================================== */

  /// Validation d'une pièce — le point de non-retour de RG-11.
  ///
  /// Refuse (`ecritureDejaValidee`) dès qu'UNE ligne est déjà validée, et annule
  /// alors les validations précédentes de la même pièce. L'état de chaque ligne
  /// est relu de la base : une ligne périmée en mémoire ne trompe pas le refus.
  Future<List<EcritureComptable>> valider(
    List<EcritureComptable> piece, {
    required String auteurId,
  }) async {
    _exigerAuteur(auteurId);
    return _dao.enTransaction(() async {
      final quand = _maintenant();
      for (final ligne in piece) {
        final fraiche = await _relire(ligne.id);
        if (fraiche.estValidee) {
          throw RefusComptable.dit(
            MotifRefus.ecritureDejaValidee,
            'comptabilite.ecriture_deja_validee',
          );
        }
        await _dao.marquerValidee(ligne.id, auteurId: auteurId, quand: quand);
      }
      return [for (final l in piece) await _relire(l.id)];
    });
  }

  /* ================================================================== */
  /* Contre-passer                                                       */
  /* ================================================================== */

  /// Contre-passe TOUTES les lignes d'une pièce déjà validée.
  ///
  /// La pièce entière, jamais une seule ligne : n'inverser que la contrepartie
  /// d'une vente rendrait la trésorerie juste et laisserait le compte de
  /// produits crédité. Le motif est repris à l'identique sur chaque ligne, ce
  /// qui rend les inverses reconnaissables comme un seul geste au journal.
  Future<List<EcritureComptable>> contrepasserPiece(
    List<EcritureComptable> piece, {
    required String auteurId,
    String? motif,
  }) async {
    _exigerAuteur(auteurId);
    // Une contre-passation qui ne trouve rien à inverser ne doit pas se taire :
    // elle laisserait croire que l'annulation a atteint la comptabilité.
    verifierPieceNonVide(piece.length);
    return _dao.enTransaction(() async {
      final inverses = <EcritureComptable>[];
      for (final ligne in piece) {
        inverses.add(
          await contrepasserLigne(ligne, auteurId: auteurId, motif: motif),
        );
      }
      return inverses;
    });
  }

  /// Contre-passation d'UNE ligne — **la seule correction admise** par RG-11.
  ///
  /// L'écriture d'origine n'est jamais touchée : une ligne inverse est ajoutée,
  /// et le lien `ecritureContrepasseeId` conserve la traçabilité exigée par
  /// SYSCOHADA. Elle est validée d'emblée (une contre-passation en brouillon
  /// laisserait le grand livre faux jusqu'à sa validation), datée du JOUR, sans
  /// numéro de pièce — comme le serveur.
  Future<EcritureComptable> contrepasserLigne(
    EcritureComptable ecriture, {
    required String auteurId,
    String? motif,
  }) async {
    _exigerAuteur(auteurId);
    return _dao.enTransaction(() async {
      final origine = await _relire(ecriture.id);
      if (!origine.estValidee) {
        // Une écriture en brouillon se corrige directement : la contre-passer
        // produirait deux lignes inutiles au grand livre.
        throw RefusComptable.dit(
          MotifRefus.contrepassationSurBrouillon,
          'comptabilite.contrepassation_sur_brouillon',
        );
      }
      if (await _dao.dejaContrepassee(origine.id)) {
        // Une double contre-passation rétablirait l'écriture d'origine tout en
        // laissant croire à une annulation.
        throw RefusComptable.dit(
          MotifRefus.dejaContrepassee,
          'comptabilite.deja_contrepassee',
        );
      }
      final quand = _maintenant();
      return _dao.insererEcriture(
        exerciceId: origine.exerciceId,
        journalId: origine.journalId,
        compteId: origine.compteId,
        centreId: origine.centreId,
        dateEcriture: formaterDateIso(quand),
        libelle: motif ?? libelleContrepassation(origine.libelle),
        // Débit et crédit inversés : c'est toute la contre-passation.
        debitCentimes: origine.creditCentimes,
        creditCentimes: origine.debitCentimes,
        statut: StatutEcriture.validee,
        ecritureContrepasseeId: origine.id,
        numeroPiece: null,
        creeLe: quand,
        creePar: auteurId,
      );
    });
  }

  /* ================================================================== */
  /* Exercices                                                           */
  /* ================================================================== */

  /// Ouvre un nouvel exercice — l'année entière, du 1er janvier au 31 décembre.
  /// Créer la ligne, rien d'autre : aucune écriture d'à-nouveaux, aucune reprise
  /// de solde (périmètre minimal du serveur, Vague E).
  ///
  /// ⚠ **Sans exercice ouvert couvrant la date, tout mouvement est refusé**
  /// (`exerciceAbsent`). Le serveur n'ouvre jamais l'exercice suivant tout seul
  /// (« les exercices suivants sont ouverts par le geste de clôture, jamais par
  /// un seeder ») ; le POSTE, lui, ouvre celui de l'année courante à chaque
  /// démarrage (`installerReferentielComptable`, ticket D197 option (b)) — c'est
  /// l'écart assumé qui évite qu'il cesse de comptabiliser le 01/01/2027. Cette
  /// méthode reste le geste explicite pour toute AUTRE année.
  Future<ExerciceComptable> ouvrirExercice(int annee) async {
    if (annee < 2000 || annee > 2100) {
      throw RefusComptable.dit(
        MotifRefus.exerciceAnneeInvalide,
        'comptabilite.exercice_annee_invalide',
      );
    }
    return _dao.enTransaction(() async {
      if (await _dao.exerciceDeLAnnee(annee) != null) {
        throw RefusComptable.dit(
          MotifRefus.exerciceDejaExistant,
          'comptabilite.exercice_deja_existant',
          {'annee': '$annee'},
        );
      }
      return _dao.insererExercice(
        annee: annee,
        dateDebut: '$annee-01-01',
        dateFin: '$annee-12-31',
      );
    });
  }

  /// Clôture un exercice — REFUSE tant qu'une écriture y reste en brouillon.
  ///
  /// Le refus est délibéré et n'a pas de contournement automatique : une pièce
  /// en brouillon n'est pas opposable, et la clôturer verrouillerait l'exercice
  /// sur un état que personne n'a validé. Aucun solde des comptes de gestion,
  /// aucune écriture de résultat : la clôture COMPLÈTE reste à faire, sous
  /// l'arbitrage du Comptable (comme au serveur).
  Future<ExerciceComptable> cloturerExercice(
    String exerciceId, {
    required String auteurId,
  }) async {
    _exigerAuteur(auteurId);
    return _dao.enTransaction(() async {
      final exercice = await _dao.exercice(exerciceId);
      if (exercice == null) {
        throw RefusComptable(
          MotifRefus.ecritureIntrouvable,
          PhrasesDuPoste.ecritureIntrouvable(exerciceId),
        );
      }
      if (exercice.statut == StatutExercice.cloture) {
        throw RefusComptable.dit(
          MotifRefus.exerciceDejaCloture,
          'comptabilite.exercice_deja_cloture',
          {'annee': '${exercice.annee}'},
        );
      }
      final brouillons = await _dao.nombreDeBrouillons(exercice.id);
      if (brouillons > 0) {
        throw RefusComptable.dit(
          MotifRefus.clotureBrouillonsRestants,
          'comptabilite.cloture_brouillons_restants',
          {'nombre': '$brouillons', 'annee': '${exercice.annee}'},
        );
      }
      await _dao.marquerCloture(
        exercice.id,
        quand: _maintenant(),
        auteurId: auteurId,
      );
      return (await _dao.exercice(exercice.id))!;
    });
  }

  /* ================================================================== */
  /* Plan comptable                                                      */
  /* ================================================================== */

  /// Crée un compte au plan — DEUX à QUATRE chiffres, le premier de 1 à 9. La
  /// classe est DÉRIVÉE du numéro, jamais saisie. Le plan du PO compte des
  /// numéros de 1 à 4 chiffres ; un compte créé ici est un compte de mouvement.
  Future<CompteDuPlan> creerCompte(
    String numero,
    String libelle,
    String nature,
  ) async {
    if (!RegExp(r'^[1-9][0-9]{1,3}$').hasMatch(numero)) {
      throw RefusComptable.dit(
        MotifRefus.compteNumeroInvalide,
        'comptabilite.compte_numero_invalide',
        {'numero': numero},
      );
    }
    final propre = libelle.trim();
    if (propre.isEmpty) {
      throw RefusComptable.dit(
        MotifRefus.compteLibelleRequis,
        'comptabilite.compte_libelle_requis',
      );
    }
    if (!_naturesAdmises.contains(nature)) {
      throw RefusComptable.dit(
        MotifRefus.compteNatureInvalide,
        'comptabilite.compte_nature_invalide',
        {'nature': nature},
      );
    }
    return _dao.enTransaction(() async {
      if (await _dao.compteParNumero(numero) != null) {
        throw RefusComptable.dit(
          MotifRefus.compteDejaExistant,
          'comptabilite.compte_deja_existant',
          {'numero': numero},
        );
      }
      return _dao.insererCompte(
        numero: numero,
        libelle: propre,
        nature: nature,
      );
    });
  }

  /// Les comptes de charge (classe 6) qu'une dépense peut imputer : les
  /// comptes IMPUTABLES uniquement, une division (60, 601…) n'est pas proposée.
  Future<List<CompteDuPlan>> comptesDeCharge() async => [
    for (final c in await _dao.comptesDeClasse('6'))
      if (c.numero.length >= 4) c,
  ];

  /* ================================================================== */
  /* Interne                                                             */
  /* ================================================================== */

  static const _naturesAdmises = ['actif', 'passif', 'charge', 'produit'];

  void _exigerAuteur(String auteurId) {
    if (auteurId.trim().isEmpty) {
      throw const RefusComptable(
        MotifRefus.auteurAbsent,
        PhrasesDuPoste.auteurAbsent,
      );
    }
  }

  Future<EcritureComptable> _relire(String id) async {
    final e = await _dao.ecriture(id);
    if (e == null) {
      throw RefusComptable(
        MotifRefus.ecritureIntrouvable,
        PhrasesDuPoste.ecritureIntrouvable(id),
      );
    }
    return e;
  }

  Future<CompteDuPlan> _compteImputable(String numero) async {
    final compte = await _dao.compteParNumero(numero);
    if (compte == null) {
      throw RefusComptable.dit(
        MotifRefus.compteInconnu,
        'depenses.compte_inconnu',
        {'numero': numero},
      );
    }
    if (numero.length < 4 && await _dao.aDesSousComptes(numero)) {
      throw RefusComptable.dit(
        MotifRefus.compteDivision,
        'comptabilite.compte_division',
        {'numero': numero},
      );
    }
    return compte;
  }
}

/// `AAAA-MM-JJ`, sur la date LOCALE de l'instant (le serveur : `toDateString()`
/// dans le fuseau de l'application).
String formaterDateIso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

final class _LigneResolue {
  const _LigneResolue({
    required this.compte,
    required this.centreId,
    required this.debitCentimes,
    required this.creditCentimes,
    required this.libelle,
  });

  final CompteDuPlan compte;
  final String centreId;
  final int debitCentimes;
  final int creditCentimes;
  final String libelle;
}
