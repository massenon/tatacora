/// Les refus du CRUD de PARC (M1) — **un jeu fermé**.
///
/// Vue Blade maîtresse (PA-183) : pwa/hebergement/hebergement.blade.php
///
/// ## Pourquoi une famille fermée plutôt qu'un `StateError` par endroit
///
/// Le refus d'archiver une unité engagée **est le livrable** du verrou, pas un
/// accident : la vue l'affiche mot pour mot dans sa modale d'archivage
/// (`modale-archivage`, état BLOQUÉ), et le serveur en fait autant
/// (`ParcHebergementService::archiver()`). Le noyer dans une exception
/// générique ferait afficher « une erreur est survenue » là où le logiciel a
/// quelque chose de précis à dire : quelles réservations tiennent la chambre.
///
/// Chaque refus porte donc son [message], en français, et l'écran le rend tel
/// quel — exactement comme le composant Livewire rend le message du service.
///
/// ## Les libellés viennent de `lang/fr`, à l'apostrophe près
///
/// `hebergement_pwa.hebergement.archivage_verrou` et
/// `archivage_detail_reservation` sont recopiés **caractère pour caractère**,
/// apostrophe DROITE comprise : le maître l'écrit 581 fois contre 39
/// typographiques, et c'est aussi la seule que les polices intégrées des PDF
/// couvrent.
library;

import '../../../core/format/formats.dart';

/// Base de tous les refus du parc.
///
/// `implements Exception` et non `Error` : ce sont des situations métier
/// attendues (une chambre déjà engagée, un numéro déjà pris), pas des défauts
/// de programmation. Le lint `only_throw_errors` est satisfait par `Exception`.
abstract base class RefusParc implements Exception {
  const RefusParc();

  /// Ce qui est affiché à l'utilisateur, mot pour mot.
  String get message;

  @override
  String toString() => message;
}

/* ====================================================================== */
/* Le verrou d'archivage — le livrable                                     */
/* ====================================================================== */

/// Une réservation qui ENGAGE l'unité, décrite juste assez pour être nommée.
///
/// Le même prédicat que `ParcHebergementService::engagements()` : réservation
/// non annulée dont le **départ n'est pas passé**. Une réservation terminée
/// n'empêche pas d'archiver — elle reste lisible, puisque rien n'est effacé.
final class EngagementUnite {
  const EngagementUnite({required this.arrivee, required this.depart});

  final DateTime arrivee;
  final DateTime depart;

  /// `hebergement_pwa.hebergement.archivage_detail_reservation`, verbatim.
  String get libelle =>
      'réservation du ${formaterDate(arrivee)} au ${formaterDate(depart)}';
}

/// L'unité est engagée : elle ne s'archive pas.
///
/// ⚠ Le message est celui de `hebergement_pwa.hebergement.archivage_verrou`,
/// recopié à l'identique. Le reformuler ferait diverger les deux canaux, et
/// quiconque compare la PWA et le poste ne retrouverait pas sa phrase.
final class UniteEngagee extends RefusParc {
  const UniteEngagee(this.engagements);

  final List<EngagementUnite> engagements;

  @override
  String get message =>
      'Élément engagé dans ${engagements.length} opération(s) : '
      '${engagements.map((e) => e.libelle).join(', ')}. Il ne peut pas être '
      'archivé — la ligne correspondante deviendrait illisible.';
}

/// La bascule « Suppression d'un enregistrement » est FERMÉE au moment du
/// geste — elle a pu l'être en Paramètres entre l'ouverture de la modale et le
/// clic (13/10/2026, contrôle des lots B et C).
///
/// Le serveur la revérifie au geste (`Hebergement::archiverUnite` →
/// `exigerSuppressionOuverte()`), et y répond par un `abort(403)` NU : la PWA
/// montre sa page d'erreur, sans phrase. ÉCART NOMMÉ : le poste reste dans la
/// modale et dit la phrase que le serveur emploie pour CE refus ailleurs
/// (`pwa.archivage.refus_bascule`, `AutoriseArchivage::exigerArchivage`),
/// mot pour mot — la même que les fournisseurs de M7
/// (`MessagesAchats.refusBascule`, confrontée au PHP). Un test vérifie
/// l'égalité des deux.
final class SuppressionFermee extends RefusParc {
  const SuppressionFermee();

  @override
  String get message =>
      "Archivage refusé : l'option « Suppression d'un enregistrement » est "
      'fermée en Paramètres pour ce profil.';
}

/* ====================================================================== */
/* Parc — unités                                                       */
/* ====================================================================== */

final class UniteIntrouvableAuParc extends RefusParc {
  const UniteIntrouvableAuParc(this.id);

  final String id;

  @override
  String get message => "Cette unité n'existe pas sur ce poste ($id).";
}

/// Deux unités ne portent jamais le même code.
///
/// Le numéro est l'identifiant que le personnel prononce (« la BNG-03 ») : deux
/// chambres homonymes rendraient toute conversation ambiguë, et le planning
/// illisible.
final class NumeroUniteDejaPris extends RefusParc {
  const NumeroUniteDejaPris(this.numero);

  final String numero;

  @override
  String get message =>
      'Le code « $numero » est déjà porté par une autre unité du parc.';
}

final class NumeroUniteRequis extends RefusParc {
  const NumeroUniteRequis();

  @override
  String get message => "Le code de l'unité est obligatoire.";
}

/// Une unité déjà hors service ne se réarchive pas.
final class UniteDejaArchivee extends RefusParc {
  const UniteDejaArchivee(this.numero);

  @override
  String get message => "L'unité $numero est déjà retirée du parc.";

  final String numero;
}

/// La purge d'une unité qui n'est pas archivée
/// (`pwa.import_export.purge_refusee_non_archive`).
final class PurgeRefuseeNonArchive extends RefusParc {
  const PurgeRefuseeNonArchive();

  @override
  String get message => 'Purge refusée : seul un élément archivé se purge.';
}

/// La purge d'une unité que des réservations PASSÉES citent encore
/// (`pwa.import_export.purge_refusee_referencee`) : l'effacer les rendrait
/// illisibles. Le verrou d'engagement (réservation à venir) est [UniteEngagee].
final class PurgeRefuseeReferencee extends RefusParc {
  const PurgeRefuseeReferencee();

  @override
  String get message =>
      'Purge refusée : des enregistrements passés référencent encore cet '
      "élément, et l'effacer les rendrait illisibles.";
}

/* ====================================================================== */
/* Parc — catégories                                                       */
/* ====================================================================== */

/// La catégorie désignée n'est pas au référentiel.
///
/// Le refus existe parce que le champ est une **vraie clé étrangère** : offrir
/// du texte libre à la place ferait des unités rattachées à « Bungalow »,
/// « bungalow » et « Bung. » — trois catégories pour le logiciel, donc trois
/// tarifs.
final class CategorieIntrouvable extends RefusParc {
  const CategorieIntrouvable();

  @override
  String get message => "La catégorie désignée n'existe pas.";
}

final class LibelleCategorieRequis extends RefusParc {
  const LibelleCategorieRequis();

  @override
  String get message => 'Le libellé de la catégorie est obligatoire.';
}

/// Deux catégories ne portent jamais le même libellé.
///
/// C'est la contrainte du serveur (`unique:categories_hebergement,libelle`), et
/// elle a une raison mesurée : deux référentiels semés avec des libellés
/// différents se croyaient chacun idempotent et ne se voyaient pas
/// (PA-160/161). Ici, deux « Bungalow » porteraient deux tarifs, et la
/// réservation prendrait celui que la base rendrait en premier.
final class LibelleCategorieDejaPris extends RefusParc {
  const LibelleCategorieDejaPris(this.libelle);

  final String libelle;

  @override
  String get message => 'Une catégorie « $libelle » existe déjà au parc.';
}

/// Un tarif nul ou négatif — jamais accepté en silence.
///
/// La vue l'exige elle-même (`required|numeric|gt:0`), et son commentaire dit
/// pourquoi : « la catégorie naît AVEC son tarif réel et sa capacité — jamais
/// un zéro d'attente qui se lirait comme une nuit gratuite ».
final class TarifCategorieInvalide extends RefusParc {
  const TarifCategorieInvalide(this.valeur);

  final int valeur;

  @override
  String get message =>
      'Tarif par nuit invalide : ${formaterFcfa(valeur)}. Il doit être '
      'strictement positif — un tarif à zéro se lirait comme une nuit '
      'offerte.';
}

/// La capacité doit être d'au moins une personne.
final class CapaciteCategorieInvalide extends RefusParc {
  const CapaciteCategorieInvalide(this.valeur);

  final int valeur;

  @override
  String get message =>
      'Capacité invalide : $valeur. Une catégorie reçoit au moins une '
      'personne.';
}
