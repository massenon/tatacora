/// Établissement des bulletins — **le seul point d'écriture de la paie**.
///
/// Vue Blade maîtresse (PA-183) : pwa/rh/paie.blade.php
///
/// @see EF-M13-07 Calcul de la paie conforme à la réglementation béninoise
/// @see RG-15 Journalisation des opérations
library;

import '../../data/employe_dao.dart';
import '../../data/paie_dao.dart';
import '../entities/bulletin_paie.dart';
import '../entities/employe.dart';
import '../entities/periode_paie.dart';
import '../entities/taux_paie.dart';
import '../refus_rh.dart';
import 'calcul_paie_service.dart';

/// Ce service **n'a aucune formule de paie**, et c'est délibéré.
///
/// Tout le calcul appartient à [CalculPaieService] : cotisation CNSS, barème
/// ITS progressif, part confirmée de la charge patronale. Réécrire ici la
/// moindre de ces formules produirait deux vérités sur le même bulletin, et
/// c'est la copie affichée qui tromperait le Comptable. Ce service
/// **orchestre** : il lit le salaire, demande le calcul, et fige le résultat.
///
/// ## Les deux refus de PA-53 le traversent sans être adoucis
///
/// 1. [coutEmployeur] rend une **fourchette**, jamais un chiffre unique.
/// 2. [simuler] et [etablirBulletin] laissent remonter
///    [BaremeItsNonTranche] avec son message, mot pour mot.
///
/// ## Pourquoi [etatReferentiel] existe avant tout calcul
///
/// [CalculPaieService] lève dès qu'un taux manque. L'écran doit pouvoir
/// **dire** que le référentiel est vide sans provoquer une exception au rendu —
/// c'est le geste d'`etatTva()` (PA-62) : nommer l'incohérence avant qu'elle
/// atteigne une opération.
final class BulletinPaieService {
  const BulletinPaieService(this._paie, this._personnel);

  final PaieDao _paie;
  final EmployeDao _personnel;

  /* ================================================================== */
  /* Référentiel — lecture pure, aucun calcul déclenché                  */
  /* ================================================================== */

  /// Le moteur de calcul, chargé du référentiel courant.
  Future<CalculPaieService> calcul() async =>
      CalculPaieService(await _paie.taux());

  Future<EtatReferentiel> etatReferentiel() async =>
      (await calcul()).etatReferentiel();

  /// Le coût employeur d'un brut, **en fourchette**.
  ///
  /// Rend `null` si les trois taux patronaux confirmés ne sont pas paramétrés :
  /// l'écran affiche alors un tiret et dit pourquoi, plutôt que de laisser une
  /// exception traverser le rendu.
  Future<CoutEmployeur?> coutEmployeur(int brut) async {
    final moteur = await calcul();
    if (!moteur.etatReferentiel().patronal) return null;

    return CoutEmployeur.composer(
      brut: brut,
      confirmees: moteur.chargesPatronalesConfirmees(brut),
      fourchette: CalculPaieService.fourchetteRisquesProfessionnels(brut),
    );
  }

  /// Le détail complet d'un brut — le simulateur de l'onglet « Barèmes ».
  ///
  /// ⚠ Le `catch` ici ne masque **rien** : il transporte le message de refus
  /// jusqu'à l'écran, mot pour mot. C'est la seule façon de rendre le refus
  /// tangible plutôt que théorique. Le refus est une **sortie** de cette
  /// méthode, pas une erreur avalée — un `return null` silencieux, lui, serait
  /// le défaut.
  Future<Simulation> simuler(int brut) async {
    final moteur = await calcul();
    final etat = moteur.etatReferentiel();

    if (!etat.salarial || !etat.patronal) {
      return const Simulation(
        refus:
            "Les taux de paie ne sont pas paramétrés : aucun calcul n'est "
            'possible.',
      );
    }

    try {
      return Simulation(
        retenues: moteur.retenuesSalariales(brut),
        cout: CoutEmployeur.composer(
          brut: brut,
          confirmees: moteur.chargesPatronalesConfirmees(brut),
          fourchette: CalculPaieService.fourchetteRisquesProfessionnels(brut),
        ),
      );
    } on RefusRh catch (refus) {
      return Simulation(refus: refus.message);
    }
  }

  /* ================================================================== */
  /* Écritures                                                           */
  /* ================================================================== */

  /// Établit le bulletin d'un salarié pour une période `AAAA-MM`.
  ///
  /// **Idempotent par construction** : `bulletins_paie_local` porte
  /// `unique(employeId, periode)`, et un bulletin déjà établi est rendu tel
  /// quel plutôt que ré-alloué. Un second appel ne brûle donc aucun numéro —
  /// même piège que `FactureDao.numeroSuivant()`, qui ALLOUE et n'est jamais
  /// une lecture (PA-101).
  ///
  /// Le calcul est fait **avant** l'écriture : un refus de barème ne doit pas
  /// laisser derrière lui un numéro alloué.
  Future<BulletinPaie> etablirBulletin(Employe employe, String periode) async {
    final mois = PeriodePaie.depuisTexte(periode);
    if (mois == null) throw PeriodeInvalide(periode);

    final moteur = await calcul();
    final etat = moteur.etatReferentiel();
    final manque = etat.refus;
    if (manque != null) throw manque;

    if (employe.statut == StatutEmploye.parti) {
      throw EmployeParti(employe.nomComplet());
    }

    final retenues = moteur.retenuesSalariales(employe.salaireBase);
    final patronales = moteur.chargesPatronalesConfirmees(employe.salaireBase);

    return _paie.etablir(
      employe: employe,
      periode: mois.code,
      retenues: retenues,
      // ⚠ La part CONFIRMÉE seulement. Le total n'existe pas (PA-53).
      chargesPatronalesConfirmees: patronales.total,
    );
  }

  /// Établit tous les bulletins manquants de la période.
  ///
  /// Un salarié **refusé** (barème ITS dépassé) n'interrompt pas les autres :
  /// son motif est collecté et rendu, nommé. Échouer le lot entier ferait
  /// perdre neuf bulletins corrects pour un cas non tranché — c'est le refus
  /// par opération de PA-65, appliqué à la paie.
  Future<BilanGeneration> etablirBulletinsManquants(String periode) async {
    var etablis = 0;
    final refus = <RefusBulletin>[];

    for (final employe in await employesSansBulletin(periode)) {
      try {
        await etablirBulletin(employe, periode);
        etablis++;
      } on RefusRh catch (erreur) {
        // Le motif est RENDU, jamais avalé : c'est ce qui distingue un salarié
        // hors barème d'un salarié oublié.
        refus.add(
          RefusBulletin(employe: employe.nomComplet(), motif: erreur.message),
        );
      }
    }

    return BilanGeneration(etablis: etablis, refus: refus);
  }

  /// Annule un bulletin, avec motif obligatoire — **jamais une suppression**.
  ///
  /// Le bulletin sort du livre de paie et des déclarations, et reste au dossier
  /// du salarié : « il est conservé et reste traçable : rien n'est effacé »
  /// (mot du maître). Même geste métier que RG-02 en M1.
  Future<BulletinPaie> annulerBulletin(String bulletinId, String motif) =>
      _paie.annuler(bulletinId, motif);

  /* ================================================================== */
  /* Lectures                                                            */
  /* ================================================================== */

  Future<List<BulletinPaie>> bulletinsDuMois(String periode) =>
      _paie.bulletinsDuMois(periode);

  /// Les salariés **en poste** qui n'ont pas encore de bulletin sur la période.
  ///
  /// Un bulletin ANNULÉ ne rend pas le salarié « manquant » : le réétablir
  /// buterait sur `unique(employeId, periode)`, et l'écran afficherait une
  /// erreur de base pour une raison qui n'a rien à voir avec le geste demandé.
  Future<List<Employe>> employesSansBulletin(String periode) async {
    final deja = await _paie.employeIdsAvecBulletin(periode);
    final employes = await _personnel.employes();

    return employes
        .where((e) => e.estEnPoste && !deja.contains(e.id))
        .toList(growable: false);
  }

  /// Le récapitulatif d'un bulletin, tel que le maître l'imprime.
  ///
  /// Tous les montants viennent des colonnes **figées** à l'établissement.
  /// Seule la fourchette de risques professionnels est recalculée : elle ne
  /// dépend d'aucun taux paramétré — les bornes 1 % et 4 % sont réglementaires
  /// — et ne peut donc pas dériver.
  RecapitulatifBulletin recapitulatif(BulletinPaie bulletin) {
    final fourchette = CalculPaieService.fourchetteRisquesProfessionnels(
      bulletin.brut,
    );

    return RecapitulatifBulletin(
      bulletin: bulletin,
      cout: CoutEmployeur.composer(
        brut: bulletin.brut,
        confirmees: null,
        totalConfirmees: bulletin.chargesPatronalesConfirmees,
        fourchette: fourchette,
      ),
    );
  }
}

/// Le coût employeur — **une fourchette, jamais un chiffre unique** (PA-53).
///
/// Aucun accesseur ne rend « le » coût : le type lui-même interdit la question.
/// C'est délibéré — un `int get total` ici serait le seul endroit du module où
/// l'hypothèse refusée pourrait rentrer.
final class CoutEmployeur {
  const CoutEmployeur._({
    required this.brut,
    required this.confirmees,
    required this.rpMin,
    required this.rpMax,
  });

  /// [confirmees] pour un calcul frais, [totalConfirmees] pour un bulletin dont
  /// la part patronale est **figée** — les deux ne doivent jamais être mêlées.
  factory CoutEmployeur.composer({
    required int brut,
    required ChargesPatronalesConfirmees? confirmees,
    required FourchetteRisquesProfessionnels fourchette,
    int? totalConfirmees,
  }) => CoutEmployeur._(
    brut: brut,
    confirmees: totalConfirmees ?? confirmees!.total,
    rpMin: fourchette.minimum,
    rpMax: fourchette.maximum,
  );

  final int brut;

  /// 19,4 % du brut.
  final int confirmees;

  final int rpMin;
  final int rpMax;

  int get coutMin => brut + confirmees + rpMin;

  int get coutMax => brut + confirmees + rpMax;

  int get ecart => rpMax - rpMin;

  int get ecartAnnuel => ecart * 12;
}

/// Le résultat du simulateur — un refus **ou** un calcul, jamais les deux.
final class Simulation {
  const Simulation({this.refus, this.retenues, this.cout});

  /// Le message de refus, rendu mot pour mot par l'écran.
  final String? refus;

  final RetenuesSalariales? retenues;
  final CoutEmployeur? cout;

  bool get estRefusee => refus != null;
}

/// Le récapitulatif imprimé d'un bulletin.
final class RecapitulatifBulletin {
  const RecapitulatifBulletin({required this.bulletin, required this.cout});

  final BulletinPaie bulletin;
  final CoutEmployeur cout;
}

/// Ce qu'une génération de lot a réellement fait.
final class BilanGeneration {
  const BilanGeneration({required this.etablis, required this.refus});

  final int etablis;
  final List<RefusBulletin> refus;

  bool get sansEffet => etablis == 0 && refus.isEmpty;
}

/// Un salarié dont le bulletin a été refusé, et pourquoi.
final class RefusBulletin {
  const RefusBulletin({required this.employe, required this.motif});

  final String employe;
  final String motif;
}
