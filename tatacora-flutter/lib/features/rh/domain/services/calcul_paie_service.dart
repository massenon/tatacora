/// Calcul de paie — **et refus de calculer**.
///
/// Vue Blade maîtresse (PA-183) : pwa/rh/paie.blade.php
///
/// @see EF-M13-07 Calcul de la paie conforme à la réglementation béninoise
library;

import '../entities/taux_paie.dart';
import '../refus_rh.dart';

/// Ce qui est calculable, et ce qui ne l'est pas.
///
/// `ATELIER_PLAN_COMPTABLE.md` §5 distingue les taux **confirmés à la source**
/// de ceux qui ne le sont pas. Cette distinction est reproduite telle quelle :
///
/// | Élément | Statut | Conséquence ici |
/// |---|---|---|
/// | CNSS salarié 3,6 % | Confirmé sur cnss.bj | Calculé |
/// | CNSS employeur pension 6,4 % + familiales 9 % | Confirmé | Calculé |
/// | VPS — Versement Patronal sur Salaires 4 % | Confirmé | Calculé |
/// | CNSS employeur **risques professionnels** | **1 % à 4 %, non confirmé** | **Refus de calculer** |
/// | Barème ITS jusqu'à 500 000 F | Confirmé, 4 tranches | Calculé |
/// | Barème ITS **au-delà de 500 000 F** | **Deux sources divergent** | **Refus de calculer** |
///
/// ## Le refus est le livrable, pas une lacune (PA-53)
///
/// [chargesPatronalesAvecRisquesProfessionnels] refuse **toujours** tant que le
/// taux de risques professionnels n'est pas renseigné, et il ne l'est pas : la
/// CNSS n'a pas confirmé la catégorie de risque de l'hôtellerie-restauration.
/// `ATELIER_PLAN_COMPTABLE.md` §5.1 propose « une valeur de 2 % [comme]
/// hypothèse raisonnable en attendant confirmation » — une hypothèse n'est pas
/// une source, et sur une masse salariale annuelle l'écart entre 1 % et 4 %
/// est un redressement.
///
/// Mais 19,4 % du brut sont établis : les laisser inaccessibles bloquerait la
/// paie mensuelle entière pour un seul taux manquant.
/// [chargesPatronalesConfirmees] expose donc la part certaine, et
/// [fourchetteRisquesProfessionnels] **chiffre l'incertitude au lieu de la
/// masquer**. Retenir 2,5 % « au milieu » serait exactement l'hypothèse
/// refusée.
///
/// ## Le VPS n'est pas une retenue
///
/// C'est une taxe directe à la charge de l'employeur, assise sur le total des
/// salaires bruts **sans plafond**, à payer au plus tard le 10 du mois suivant.
/// Il ne figure jamais au débit du salarié : l'inscrire en retenue produirait
/// un bulletin faux et un net minoré de 4 %. Il est donc absent de
/// [retenuesSalariales] **par construction**.
final class CalculPaieService {
  /// [taux] est une photographie du référentiel, lue une fois.
  ///
  /// Le service est **synchrone et pur** : il ne touche pas la base. C'est ce
  /// qui permet de l'éprouver sur des cas chiffrés sans monter une base, et
  /// d'être certain que le refus ne dépend d'aucun état.
  const CalculPaieService(this._taux);

  final Map<String, String> _taux;

  /// Plafond au-delà duquel le barème ITS n'est pas tranché.
  static const int plafondItsConfirme = 500000;

  /// Bornes **réglementaires** du taux de risques professionnels.
  ///
  /// Elles servent à chiffrer l'incertitude, jamais à en déduire une valeur :
  /// prendre la moyenne serait exactement l'hypothèse que le projet refuse.
  static const int tauxRisquesMin = 1;
  static const int tauxRisquesMax = 4;

  /// Barème ITS confirmé — `ATELIER_PLAN_COMPTABLE.md` §5.3.
  ///
  /// Le haut de barème (au-delà de 500 000 F) est **absent volontairement** :
  /// deux sources divergent, et inventer la tranche produirait un bulletin
  /// faux.
  static const List<TrancheIts> baremeIts = [
    TrancheIts(plancher: 0, plafond: 60000, taux: 0),
    TrancheIts(plancher: 60000, plafond: 150000, taux: 10),
    TrancheIts(plancher: 150000, plafond: 250000, taux: 15),
    TrancheIts(plancher: 250000, plafond: plafondItsConfirme, taux: 19),
  ];

  /* ================================================================== */
  /* Référentiel                                                         */
  /* ================================================================== */

  bool tauxEstParametre(String cle) => Taux.depuisTexte(_taux[cle]) != null;

  EtatReferentiel etatReferentiel() => EtatReferentiel(
    clesAbsentes: ClesTaux.confirmees
        .where((cle) => !tauxEstParametre(cle))
        .toList(growable: false),
    risquesProfessionnels: tauxEstParametre(ClesTaux.cnssRisquesProfessionnels),
  );

  /* ================================================================== */
  /* Retenues salariales                                                 */
  /* ================================================================== */

  /// Retenues salariales et net à payer.
  ///
  /// Le net est une valeur **calculée**, jamais un champ de formulaire soumis.
  ///
  /// Lève [TauxNonParametre] si la CNSS salariale n'est pas au référentiel, et
  /// [BaremeItsNonTranche] si le revenu imposable dépasse le plafond confirmé.
  RetenuesSalariales retenuesSalariales(int brut) {
    if (brut < 0) throw SalaireInvalide(brut);

    final cnss = _taux3(ClesTaux.cnssSalarie).pourcentDe(brut);

    // Le revenu imposable est le brut MOINS la cotisation salariale :
    // appliquer le barème au brut surtaxerait chaque bulletin.
    final imposable = brut - cnss;
    final impot = impotSurTraitements(imposable);

    return RetenuesSalariales(
      brut: brut,
      cnssSalarie: cnss,
      revenuImposable: imposable,
      its: impot,
      totalRetenues: cnss + impot,
      netAPayer: brut - cnss - impot,
    );
  }

  /// Impôt sur les Traitements et Salaires — barème progressif par tranches.
  ///
  /// ⚠ **Refuse au-delà du plafond confirmé**, plutôt que d'extrapoler la
  /// dernière tranche : deux sources divergent (taux unique de 30 % contre
  /// palier à 40 %). `ATELIER_PLAN_COMPTABLE.md` note qu'aucun employé actuel
  /// n'approche 500 000 F ; le refus ne bloque donc personne aujourd'hui, et il
  /// se déclenchera au premier recrutement de cadre — exactement au moment où
  /// la question doit être tranchée.
  int impotSurTraitements(int revenuImposable) {
    if (revenuImposable > plafondItsConfirme) {
      throw BaremeItsNonTranche(
        revenuImposable: revenuImposable,
        plafond: plafondItsConfirme,
      );
    }

    // Les parts se cumulent en numérateur de centièmes, et l'arrondi n'a lieu
    // qu'une fois, à la fin : arrondir tranche par tranche décalerait le total
    // d'un franc sur certains bruts.
    var centiemes = 0;

    for (final tranche in baremeIts) {
      if (revenuImposable <= tranche.plancher) break;

      final borneHaute = revenuImposable < tranche.plafond
          ? revenuImposable
          : tranche.plafond;
      centiemes += (borneHaute - tranche.plancher) * tranche.taux;
    }

    return arrondiCommercial(centiemes, 100);
  }

  /* ================================================================== */
  /* Charges patronales                                                  */
  /* ================================================================== */

  /// Part **certaine** de la charge patronale : CNSS pension 6,4 %,
  /// prestations familiales 9 %, VPS 4 % — soit 19,4 % du brut.
  ///
  /// Calculable sans le taux de risques professionnels. C'est ce qui permet
  /// d'établir une paie mensuelle plutôt que de tout suspendre à un seul taux
  /// manquant.
  ChargesPatronalesConfirmees chargesPatronalesConfirmees(int brut) {
    final pension = _taux3(ClesTaux.cnssPensionEmployeur).pourcentDe(brut);
    final familiales = _taux3(
      ClesTaux.cnssPrestationsFamiliales,
    ).pourcentDe(brut);
    final vps = _taux3(ClesTaux.vps).pourcentDe(brut);

    return ChargesPatronalesConfirmees(
      pension: pension,
      prestationsFamiliales: familiales,
      vps: vps,
    );
  }

  /// ⚠ **Ce calcul est REFUSÉ, et c'est le livrable du module (PA-53).**
  ///
  /// Il n'existe que pour porter le refus jusqu'à l'appelant : tant que
  /// `taux_cnss_risques_professionnels` n'est pas au référentiel — et il ne
  /// doit pas y entrer sans confirmation de la CNSS —, il lève
  /// [TauxNonParametre].
  ///
  /// **Ne jamais lui donner de repli.** Un total de charge patronale est
  /// exactement ce que le module refuse de produire : la fourchette de
  /// [fourchetteRisquesProfessionnels] est la réponse, et elle publie l'écart
  /// au lieu de le moyenner.
  ChargesPatronalesCompletes chargesPatronalesAvecRisquesProfessionnels(
    int brut,
  ) {
    final confirmees = chargesPatronalesConfirmees(brut);
    // ⚠ AUCUN REPLI. Une mutation posant « 2 % en attendant confirmation » a
    // été éprouvée le 14/09/2026 : elle fait rougir les deux cas de refus de
    // `calcul_paie_test.dart`. Ces assertions ne sont donc pas vides — c'est
    // la seule preuve qu'elles protègent réellement quelque chose.
    final risques = _taux3(ClesTaux.cnssRisquesProfessionnels).pourcentDe(brut);

    return ChargesPatronalesCompletes(
      confirmees: confirmees,
      risquesProfessionnels: risques,
    );
  }

  /// Chiffre l'incertitude portée par le taux de risques professionnels.
  ///
  /// Ne rend **aucune valeur centrale** : l'écart entre les deux bornes est
  /// exactement ce qu'un redressement viendrait réclamer, et le publier est
  /// plus utile que de le dissimuler derrière une moyenne.
  ///
  /// `static` : les deux bornes sont réglementaires et ne dépendent d'aucun
  /// paramètre, donc d'aucun référentiel. C'est ce qui permet de rendre le
  /// coût d'un bulletin même quand le référentiel a été vidé depuis.
  static FourchetteRisquesProfessionnels fourchetteRisquesProfessionnels(
    int brut,
  ) => FourchetteRisquesProfessionnels(
    minimum: arrondiCommercial(brut * tauxRisquesMin, 100),
    maximum: arrondiCommercial(brut * tauxRisquesMax, 100),
  );

  /* ================================================================== */
  /* Le barème, tel que l'onglet « Barèmes & taux » l'affiche             */
  /* ================================================================== */

  /// Les tranches, avec l'impôt maximal de chacune et le cumul.
  ///
  /// Elles viennent de [baremeIts], jamais recopiées : deux barèmes écrits à
  /// deux endroits finiraient par diverger, et c'est celui qui est **affiché**
  /// qui tromperait.
  List<LigneBareme> baremeAffiche() {
    final lignes = <LigneBareme>[];
    var cumul = 0;

    for (final tranche in baremeIts) {
      final maximum = arrondiCommercial(
        (tranche.plafond - tranche.plancher) * tranche.taux,
        100,
      );
      cumul += maximum;
      lignes.add(LigneBareme(tranche: tranche, maximum: maximum, cumul: cumul));
    }

    return List.unmodifiable(lignes);
  }

  /* ================================================================== */
  /* Interne                                                             */
  /* ================================================================== */

  /// Le taux, ou le refus qui le nomme. **Aucun repli.**
  Taux _taux3(String cle) {
    final taux = Taux.depuisTexte(_taux[cle]);
    if (taux == null) throw TauxNonParametre(cle);
    return taux;
  }
}

/// Une tranche du barème ITS.
final class TrancheIts {
  const TrancheIts({
    required this.plancher,
    required this.plafond,
    required this.taux,
  });

  final int plancher;
  final int plafond;

  /// En pourcentage entier — le barème confirmé n'a pas de décimale.
  final int taux;
}

/// Une ligne du tableau « Barème ITS / IR-PTS ».
final class LigneBareme {
  const LigneBareme({
    required this.tranche,
    required this.maximum,
    required this.cumul,
  });

  final TrancheIts tranche;

  /// Impôt maximal de la tranche.
  final int maximum;

  /// Impôt cumulé jusqu'au plafond de la tranche.
  final int cumul;
}

/// Les retenues d'un bulletin, et le net qui s'en déduit.
final class RetenuesSalariales {
  const RetenuesSalariales({
    required this.brut,
    required this.cnssSalarie,
    required this.revenuImposable,
    required this.its,
    required this.totalRetenues,
    required this.netAPayer,
  });

  final int brut;
  final int cnssSalarie;
  final int revenuImposable;
  final int its;
  final int totalRetenues;

  /// **Calculé**, jamais saisi.
  final int netAPayer;
}

/// La part certaine de la charge patronale — 19,4 % du brut.
final class ChargesPatronalesConfirmees {
  const ChargesPatronalesConfirmees({
    required this.pension,
    required this.prestationsFamiliales,
    required this.vps,
  });

  final int pension;
  final int prestationsFamiliales;

  /// ⚠ Compris ici, et **jamais** dans les retenues du salarié.
  final int vps;

  int get total => pension + prestationsFamiliales + vps;
}

/// Le total de charge patronale — **inatteignable tant que PA-53 est ouverte**.
///
/// Ce type n'existe que comme sortie de
/// [CalculPaieService.chargesPatronalesAvecRisquesProfessionnels], qui lève
/// toujours. Il est conservé pour que le jour de l'arbitrage, il y ait un seul
/// endroit à ouvrir — et pour qu'aucun appelant ne soit tenté d'additionner
/// lui-même une borne de la fourchette au total confirmé.
final class ChargesPatronalesCompletes {
  const ChargesPatronalesCompletes({
    required this.confirmees,
    required this.risquesProfessionnels,
  });

  final ChargesPatronalesConfirmees confirmees;
  final int risquesProfessionnels;

  int get total => confirmees.total + risquesProfessionnels;
}

/// L'incertitude chiffrée — **jamais une valeur centrale**.
final class FourchetteRisquesProfessionnels {
  const FourchetteRisquesProfessionnels({
    required this.minimum,
    required this.maximum,
  });

  final int minimum;
  final int maximum;

  /// Ce qu'un redressement viendrait réclamer, au pire.
  int get ecart => maximum - minimum;

  /// Douze fois l'écart mensuel — la mesure qui rend le refus tangible.
  int get ecartAnnuel => ecart * 12;
}
