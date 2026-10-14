/// Livre de paie, déclarations et indicateurs — **lecture seule**.
///
/// Vue Blade maîtresse (PA-183) : pwa/rh/paie.blade.php
///
/// @see EF-M13-07 Calcul de la paie conforme à la réglementation béninoise
library;

import '../entities/bulletin_paie.dart';
import '../entities/employe.dart';
import '../entities/periode_paie.dart';
import 'bulletin_paie_service.dart';
import 'calcul_paie_service.dart';

/// ## Aucune écriture, aucune formule de paie
///
/// Ce service **additionne des colonnes déjà figées** sur les bulletins. Il ne
/// recalcule ni la CNSS ni l'ITS : les reprendre aux taux d'aujourd'hui ferait
/// diverger le livre du bulletin qu'il totalise, et c'est la ligne du livre que
/// le Comptable reporterait sur sa déclaration.
///
/// ## Un bulletin ANNULÉ ne compte nulle part
///
/// Ni au livre, ni aux déclarations, ni à l'effectif payé. Il reste au dossier
/// du salarié : c'est la différence entre annuler et supprimer, et c'est aussi
/// pourquoi le total du livre ne se relit jamais comme un compte de bulletins
/// existants.
///
/// ## Les déclarations portent un ÉTAT, pas une promesse
///
/// - **VPS** : arrêté. Taxe employeur de 4 % sur le brut total, sans plafond,
///   exigible au plus tard le 10 du mois suivant — échéance calculée, jamais
///   saisie.
/// - **ITS** : arrêté. Retenu à la source, reversé à la DGI.
/// - **CNSS** : **incomplet, et il le dit.** Le montant additionne la part
///   salariale, la pension et les prestations familiales — il EXCLUT les
///   risques professionnels (PA-53). Présenter ce montant comme arrêté ferait
///   déclarer une cotisation minorée.
///
/// Aucun état « déclaré » ou « télédéclaré » n'existe : rien ne transmet ces
/// déclarations, et un badge qui l'affirmerait serait PA-59/60/61.
final class LivreDePaieService {
  const LivreDePaieService(this._bulletins);

  final BulletinPaieService _bulletins;

  /// Les bulletins retenus au livre — **annulés exclus**.
  Future<List<BulletinPaie>> bulletinsRetenus(String periode) async {
    final tous = await _bulletins.bulletinsDuMois(periode);
    return tous.where((b) => !b.estAnnule).toList(growable: false);
  }

  /// Les totaux d'une période.
  Future<TotauxLivre> totaux(String periode) async {
    final retenus = await bulletinsRetenus(periode);

    var brut = 0;
    var cnss = 0;
    var its = 0;
    var autres = 0;
    var net = 0;
    var confirmees = 0;
    var sansCnss = 0;

    for (final bulletin in retenus) {
      brut += bulletin.brut;
      cnss += bulletin.cnssSalarie;
      its += bulletin.its;
      autres += bulletin.autresRetenues;
      net += bulletin.netAPayer;
      confirmees += bulletin.chargesPatronalesConfirmees;
      if (bulletin.employe.sansNumeroCnss) sansCnss++;
    }

    // La VENTILATION de la part patronale se recalcule sur le brut total : les
    // trois taux sont confirmés, et le bulletin ne stocke que leur somme. Si un
    // taux venait à changer, l'écart se verrait entre la somme des lignes et le
    // total figé — ce qui est exactement le signal voulu.
    final moteur = await _bulletins.calcul();
    final patronal = moteur.etatReferentiel().patronal;
    final ventilation = patronal
        ? moteur.chargesPatronalesConfirmees(brut)
        : const ChargesPatronalesConfirmees(
            pension: 0,
            prestationsFamiliales: 0,
            vps: 0,
          );

    return TotauxLivre(
      periode: periode,
      effectif: retenus.length,
      sansNumeroCnss: sansCnss,
      brut: brut,
      cnssSalarie: cnss,
      its: its,
      autresRetenues: autres,
      net: net,
      ventilation: ventilation,
      patronalesConfirmees: confirmees,
      fourchette: CalculPaieService.fourchetteRisquesProfessionnels(brut),
    );
  }

  /// Les trois déclarations de la période.
  Future<List<Declaration>> declarations(String periode) async {
    final t = await totaux(periode);
    final mois = PeriodePaie.depuisTexte(periode);

    return [
      Declaration(
        code: 'CNSS',
        libelle: 'Cotisations CNSS (salariales + patronales)',
        note: 'Hors risques professionnels — taux non confirmé.',
        montant:
            t.cnssSalarie +
            t.ventilation.pension +
            t.ventilation.prestationsFamiliales,
        // Hors risques professionnels : le montant est un MINIMUM.
        complet: false,
      ),
      Declaration(
        code: 'VPS',
        libelle: 'Versement Patronal sur Salaires (4 %)',
        note:
            'Base brute sans plafond. Déclaration et paiement au plus tard le '
            '10 du mois suivant.',
        montant: t.ventilation.vps,
        echeance: mois?.echeanceVps,
        complet: true,
      ),
      Declaration(
        code: 'ITS',
        libelle: 'Impôt sur les Traitements et Salaires retenu à la source',
        note: 'Reversé à la DGI.',
        montant: t.its,
        complet: true,
      ),
    ];
  }
}

/// Les totaux du livre de paie.
final class TotauxLivre {
  const TotauxLivre({
    required this.periode,
    required this.effectif,
    required this.sansNumeroCnss,
    required this.brut,
    required this.cnssSalarie,
    required this.its,
    required this.autresRetenues,
    required this.net,
    required this.ventilation,
    required this.patronalesConfirmees,
    required this.fourchette,
  });

  final String periode;

  /// Le nombre de bulletins **retenus**, pas l'effectif de l'entreprise.
  final int effectif;

  final int sansNumeroCnss;
  final int brut;
  final int cnssSalarie;
  final int its;
  final int autresRetenues;
  final int net;

  final ChargesPatronalesConfirmees ventilation;

  /// La somme des parts **figées** sur les bulletins.
  final int patronalesConfirmees;

  final FourchetteRisquesProfessionnels fourchette;

  /// ⚠ Le coût total est une **fourchette**, aux deux bouts du livre comme
  /// ailleurs. Aucun accesseur ne rend un montant unique.
  int get coutMin => brut + patronalesConfirmees + fourchette.minimum;

  int get coutMax => brut + patronalesConfirmees + fourchette.maximum;
}

/// Une déclaration sociale ou fiscale de la période.
final class Declaration {
  const Declaration({
    required this.code,
    required this.libelle,
    required this.note,
    required this.montant,
    required this.complet,
    this.echeance,
  });

  final String code;
  final String libelle;
  final String note;
  final int montant;

  /// Calculée, jamais saisie. `null` quand la déclaration n'en porte pas.
  final DateTime? echeance;

  /// `false` = « Incomplet » : le montant est un minimum. C'est le cas de la
  /// CNSS, amputée des risques professionnels.
  final bool complet;
}

/// Les six indicateurs de tête de l'écran.
///
/// Assemblés ici et non dans un widget : trois d'entre eux croisent l'effectif
/// affiché et les bulletins du mois, et un écran qui les recomposerait à la
/// volée finirait par compter « effectif » et « bulletins » sur deux périmètres
/// différents.
final class IndicateursPaie {
  const IndicateursPaie({
    required this.effectifAffiche,
    required this.effectifTotal,
    required this.masseSalariale,
    required this.coutMasse,
    required this.totaux,
    required this.bulletinsManquants,
    required this.sansNumeroCnss,
  });

  factory IndicateursPaie.composer({
    required List<Employe> affiches,
    required int effectifTotal,
    required TotauxLivre totaux,
    required int bulletinsManquants,
    required CoutEmployeur? coutMasse,
  }) {
    var masse = 0;
    var sansCnss = 0;
    for (final employe in affiches) {
      masse += employe.salaireBase;
      if (employe.sansNumeroCnss) sansCnss++;
    }

    return IndicateursPaie(
      effectifAffiche: affiches.length,
      effectifTotal: effectifTotal,
      masseSalariale: masse,
      coutMasse: coutMasse,
      totaux: totaux,
      bulletinsManquants: bulletinsManquants,
      sansNumeroCnss: sansCnss,
    );
  }

  final int effectifAffiche;
  final int effectifTotal;
  final int masseSalariale;

  /// `null` quand le référentiel patronal est incomplet : l'écran rend un
  /// tiret et le bandeau dit pourquoi, plutôt qu'un zéro plausible.
  final CoutEmployeur? coutMasse;

  final TotauxLivre totaux;
  final int bulletinsManquants;
  final int sansNumeroCnss;
}
