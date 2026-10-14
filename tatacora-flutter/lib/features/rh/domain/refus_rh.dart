/// Les refus du module M13 — **un jeu fermé**.
///
/// Vue Blade maîtresse (PA-183) : pwa/rh/paie.blade.php
///
/// ## Pourquoi une famille fermée plutôt qu'un `StateError` par endroit
///
/// Deux de ces refus sont le **livrable** du module (PA-53), pas des
/// accidents : le coût total employeur et le haut du barème ITS ne sont pas
/// calculables, et l'écran doit les dire mot pour mot. Les noyer dans des
/// exceptions génériques ferait afficher « une erreur est survenue » là où le
/// logiciel a quelque chose de précis à expliquer à un Comptable.
///
/// Chaque refus porte donc son [message], en français, et l'écran le rend tel
/// quel — exactement comme le composant PWA rend le message du service.
library;

import '../../../core/format/formats.dart';

/// Base de tous les refus de M13.
///
/// `implements Exception` et non `Error` : ce sont des situations métier
/// attendues (un taux non arbitré, un salarié déjà parti), pas des défauts de
/// programmation. Le lint `only_throw_errors` est satisfait par `Exception`.
abstract base class RefusRh implements Exception {
  const RefusRh();

  /// Ce qui est affiché à l'utilisateur, mot pour mot.
  String get message;

  @override
  String toString() => message;
}

/* ====================================================================== */
/* Les deux refus de PA-53 — le livrable du module                         */
/* ====================================================================== */

/// Un taux n'est pas paramétré : **aucun calcul n'est fait à sa place**.
///
/// C'est ce refus qui interdit tout total de charge patronale, puisque
/// `taux_cnss_risques_professionnels` est délibérément absent du référentiel.
final class TauxNonParametre extends RefusRh {
  const TauxNonParametre(this.cle);

  final String cle;

  @override
  String get message =>
      "Le taux « $cle » n'est pas paramétré. Aucun calcul de paie n'est "
      "effectué tant qu'il n'est pas renseigné — un bulletin faux est une "
      'déclaration sociale erronée.';
}

/// Le revenu imposable dépasse le plafond du barème ITS confirmé.
///
/// Deux sources divergent sur le haut de barème (taux unique de 30 % contre
/// palier supplémentaire à 40 %). Extrapoler la dernière tranche produirait une
/// retenue à la source fausse sur un document conservé sans limitation de
/// durée.
final class BaremeItsNonTranche extends RefusRh {
  const BaremeItsNonTranche({
    required this.revenuImposable,
    required this.plafond,
  });

  final int revenuImposable;
  final int plafond;

  @override
  String get message =>
      'Revenu imposable de ${formaterFcfa(revenuImposable)}, au-delà du '
      'plafond confirmé de ${formaterFcfa(plafond)}. La structure du barème '
      "ITS au-delà de ce seuil n'est pas tranchée : deux sources divergent "
      '(taux unique de 30 % contre palier supplémentaire à 40 %). Le calcul '
      "est refusé plutôt qu'extrapolé — à faire confirmer auprès de la DGI.";
}

/* ====================================================================== */
/* Référentiel et période                                                  */
/* ====================================================================== */

/// Les taux confirmés ne sont pas tous en base : aucun bulletin ne s'établit.
final class ReferentielIncomplet extends RefusRh {
  const ReferentielIncomplet(this.clesAbsentes);

  final List<String> clesAbsentes;

  @override
  String get message =>
      "Les taux de paie ne sont pas paramétrés : ${clesAbsentes.join(', ')}.";
}

/// La période n'est pas au format `AAAA-MM`.
final class PeriodeInvalide extends RefusRh {
  const PeriodeInvalide(this.periode);

  final String periode;

  @override
  String get message => 'Période invalide : $periode. Format attendu AAAA-MM.';
}

/* ====================================================================== */
/* Dossier du personnel                                                    */
/* ====================================================================== */

final class EmployeIntrouvable extends RefusRh {
  const EmployeIntrouvable(this.id);

  final String id;

  @override
  String get message => "Ce salarié n'existe pas sur ce poste ($id).";
}

/// Le service désigné n'est pas au référentiel.
///
/// Le refus existe parce que le champ est une **vraie clé étrangère** : offrir
/// du texte libre à la place ferait des dossiers rattachés à « Restauration »,
/// « restauration » et « Resto » — trois services pour le logiciel.
final class ServiceInconnu extends RefusRh {
  const ServiceInconnu();

  @override
  String get message => "Le service désigné n'existe pas.";
}

final class ContratInconnu extends RefusRh {
  const ContratInconnu(this.code);

  final String code;

  @override
  String get message => 'Type de contrat hors registre : $code.';
}

final class StatutEmployeInconnu extends RefusRh {
  const StatutEmployeInconnu(this.code);

  final String code;

  @override
  String get message => 'Statut hors registre : $code.';
}

/// Un salarié parti ne se réarchive pas.
final class EmployeDejaArchive extends RefusRh {
  const EmployeDejaArchive(this.nom);

  final String nom;

  @override
  String get message => '$nom est déjà archivé (statut « parti »).';
}

/// Un salarié parti n'a plus de bulletin à établir.
final class EmployeParti extends RefusRh {
  const EmployeParti(this.nom);

  final String nom;

  @override
  String get message =>
      "$nom a quitté l'entreprise : aucun bulletin ne peut être établi.";
}

/* ====================================================================== */
/* Bulletins                                                               */
/* ====================================================================== */

final class BulletinIntrouvable extends RefusRh {
  const BulletinIntrouvable(this.id);

  final String id;

  @override
  String get message => "Ce bulletin n'existe pas sur ce poste ($id).";
}

final class BulletinDejaAnnule extends RefusRh {
  const BulletinDejaAnnule();

  @override
  String get message => 'Ce bulletin est déjà annulé.';
}

/// Une annulation sans motif est indistinguable d'une erreur de manipulation,
/// et c'est le seul élément qu'un contrôle pourra lire des années plus tard.
final class MotifAnnulationRequis extends RefusRh {
  const MotifAnnulationRequis();

  @override
  String get message => "Le motif d'annulation est obligatoire.";
}

/// Un salaire de base négatif — jamais ramené silencieusement à zéro.
final class SalaireInvalide extends RefusRh {
  const SalaireInvalide(this.valeur);

  final int valeur;

  @override
  String get message =>
      'Salaire de base invalide : $valeur. Il doit être positif ou nul.';
}
