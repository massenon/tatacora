/// Les règles métier de M8, **écrites une seule fois**.
///
/// @see EF-M8-01 Référentiel véhicules
/// @see EF-M8-03 Contrat de location
/// @see RG-08 Prévention des doubles locations
/// @see RG-09 Pièces justificatives conditionnelles
///
/// ## Pourquoi ce fichier existe — décision du Product Owner, 14/09/2026
///
/// Le poste est **zéro réseau**. RG-08 et RG-09 se tenaient au serveur, dans
/// `ContratLocationService` : c'est lui qui refusait, et l'écran ne faisait que
/// relayer son message. Il n'y a plus de serveur à interroger, et une règle que
/// personne n'applique n'est pas une règle — elle est un commentaire.
///
/// Les deux vivent donc ici, et **ici seulement** : le DAO les applique dans la
/// transaction qui écrit, l'écran les lit pour décider ce qu'il affiche. Deux
/// transcriptions de la même règle finiraient par diverger, et c'est ainsi
/// qu'une règle conditionnelle devient appliquée à un endroit et oubliée à un
/// autre — ce que le PHPDoc de `Vehicule::exigePermis()` dit lui-même.
library;

import '../../../core/format/formats.dart' show formaterDate;
import 'entities/vehicule.dart';

/// Les catégories dispensées de permis — **l'unique auteur local de RG-09**.
///
/// ## Ce n'est PAS une seconde liste, et la distinction est tout
///
/// `Vehicule::CATEGORIES_SANS_PERMIS` (`tatacora-api/app/Domain/Vehicules/
/// Models/Vehicule.php` l.52) reste **le seul endroit qui en décide** : PA-50
/// nomme cette constante comme « le seul endroit à modifier le jour où la
/// décision tombe ». Ce `Set` en est la transcription sur un poste qui ne peut
/// plus lire le serveur, et `regles_vehicules_test.dart` **relit le fichier
/// PHP** pour que les deux ne puissent pas diverger en silence : une liste
/// recopiée côté Dart ne vérifierait qu'elle-même et resterait verte le jour où
/// l'arbitrage tomberait.
///
/// ⚠ La règle du CdCF est littéralement « hors motos » : c'est donc `moto`
/// seul. Le maître écrit, lui, « moto, scooter et vélo en sont dispensés » —
/// l'écart est **ouvert** (PA-50, arbitrage Architecte + Product Owner) et
/// n'est pas tranché ici. Exiger un permis pour louer un vélo est
/// vraisemblablement involontaire ; aucun document ne les dispense.
const Set<String> categoriesSansPermis = {'moto'};

/// RG-09 — cette catégorie exige-t-elle un permis de conduire ?
///
/// [categorieBrute] est la valeur **stockée** (`vehicules.categorie`), jamais
/// le libellé d'affichage : « Berline » est ce que l'écran montre, `voiture`
/// est ce que la règle lit.
///
/// Une catégorie **inconnue** exige un permis. Ce n'est pas un repli
/// arbitraire : un registre qui gagnerait une valeur demain ne doit pas obtenir
/// la dispense par omission — le défaut sûr est d'exiger la pièce, pas de s'en
/// passer.
bool exigePermisPour(String? categorieBrute) =>
    !categoriesSansPermis.contains(categorieBrute);

/// Les statuts sous lesquels un véhicule peut être loué —
/// `Vehicule::STATUTS_LOUABLES`.
///
/// Le statut n'est pas la disponibilité (même distinction qu'en M1, RG-02) :
/// un véhicule `loue` reste louable pour une période future. Les confondre
/// ferait disparaître du parc tout ce qui est en cours de location.
const Set<String> statutsLouables = {'disponible', 'loue'};

/// Deux plages `Y-m-d` se chevauchent-elles ? **Bornes demi-ouvertes.**
///
/// « Un véhicule rendu le 13 est relouable dès le 13 » : une location qui finit
/// là où une autre commence ne chevauche pas. C'est la même convention que le
/// `CHECK (date_fin > date_debut)` du schéma et que `ContratLocation.chevauche`.
bool plagesSeChevauchent({
  required DateTime debutA,
  required DateTime finA,
  required DateTime debutB,
  required DateTime finB,
}) => debutA.isBefore(finB) && finA.isAfter(debutB);

/// Ramène un horodatage au JOUR — les plages de M8 sont des dates, pas des
/// instants.
///
/// Sans cette normalisation, un contrat saisi à 16 h 45 et un autre saisi à
/// 9 h 00 le jour de la restitution ne se compareraient pas comme le fait le
/// schéma, dont les colonnes sont des `date`.
DateTime jourDe(DateTime d) => DateTime(d.year, d.month, d.day);

/// Le refus d'une écriture de M8 — porté à l'écran tel quel.
///
/// Un registre **fermé** de messages, comme les refus de la connexion
/// (PA-103) : ils sont écrits pour l'exploitant du Gîte, en français, et ne
/// nomment ni table ni colonne dans leur texte.
final class RefusVehicule implements Exception {
  const RefusVehicule(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Les messages de refus, **repris au mot de `tatacora-api/lang/fr/
/// vehicules.php`**.
///
/// Ils sont recopiés à l'identique — apostrophe DROITE comprise, comme le
/// fichier de langue l'écrit — pour qu'un même refus se dise de la même façon
/// sur les deux canaux. L'exploitant qui a vu la phrase sur la PWA doit la
/// reconnaître ici.
abstract final class MessagesVehicules {
  /// Les refus d'une immobilisation (entretien ou carburation).
  static const String dateEntretienManquante = 'La date est obligatoire.';
  static const String coutEntretienInvalide =
      'Le coût est un nombre entier de francs, zéro ou plus.';
  static const String typeEntretienInconnu =
      'Le motif doit être « Entretien » ou « Carburation ».';

  /// `vehicules.chevauchement` — RG-08.
  static const String chevauchement =
      'Ce véhicule est déjà loué sur cette période.';

  /// `vehicules.piece_identite_requise` — RG-09.
  static const String pieceIdentiteRequise =
      "Une pièce d'identité est obligatoire pour toute location.";

  /// `vehicules.permis_requis` — RG-09, avec sa catégorie.
  static String permisRequis(String categorie) =>
      'Un permis de conduire est obligatoire pour la catégorie '
      '« $categorie ».';

  /// `vehicules.non_louable`.
  static String nonLouable(String statut) =>
      'Ce véhicule est indisponible ($statut) : il ne peut pas être loué.';

  /// `vehicules.pwa.verrou_contrat_annule` — la phrase de la vue quand le
  /// contrat est DÉJÀ annulé (le service du serveur la lève aussi :
  /// `ContratLocationService::annuler`).
  static const String contratDejaAnnule =
      "Ce contrat est déjà annulé — il n'y a plus rien à archiver.";

  /// Le contrat à annuler ne figure pas au registre de ce poste (la vue
  /// répond 404 : `findOrFail`).
  static const String contratInexistant =
      "Ce contrat n'existe pas dans le registre.";

  /// `vehicules.pwa.archiver_contrat` — la question de la modale d'archivage.
  static String questionAnnulerContrat(String element) =>
      'Voulez-vous annuler le contrat $element ?';

  /// `vehicules.pwa.archivage_contrat_fait` — le message de succès.
  static String contratAnnule(String element) =>
      'Contrat $element annulé — le véhicule redevient disponible.';

  /// `vehicules.validation.vehicule_inexistant`.
  static const String vehiculeInexistant =
      "Ce véhicule n'existe pas dans le parc.";

  /// `vehicules.validation.client_inexistant`.
  static const String clientInexistant =
      "Ce client n'existe pas dans le référentiel.";

  /// `vehicules.validation.fin_apres_debut` — le `CHECK` du schéma.
  static const String finApresDebut =
      'La date de fin doit être postérieure à la date de début.';

  /// L'immatriculation est le SEUL identifiant lisible d'un véhicule : la table
  /// n'a aucune colonne de nom. Sans elle, la ligne serait introuvable au
  /// comptoir.
  static const String immatriculationRequise =
      "L'immatriculation est obligatoire : c'est le seul identifiant d'un "
      'véhicule au parc.';

  /// Une immatriculation est unique au schéma serveur (`->unique()`).
  static String immatriculationDejaPrise(String immatriculation) =>
      'Le véhicule $immatriculation existe déjà au parc.';

  /// Un tarif à zéro facturerait une location gratuite sans que rien ne le
  /// signale — c'est lui qui produit le montant du contrat.
  static const String tarifInvalide =
      'Le tarif journalier doit être supérieur à zéro : c\'est lui qui donne '
      'son montant au contrat.';

  /// Le registre fermé des catégories (`vehicules.categorie`).
  static String categorieInconnue(String categorie) =>
      'La catégorie « $categorie » n\'existe pas au registre du parc.';

  /// Les libellés de la vue (`vehicules.pwa.champ_*`) que les phrases du serveur
  /// nomment : `GestionnaireVehicules` et `GestionnaireContratsLocation` les
  /// passent à la validation comme noms de champ.
  static const String libelleAnnee = 'Année';
  static const String libellePlaces = 'Places';
  static const String libelleTransmission = 'Transmission';
  static const String libelleRemise = 'Remise (FCFA)';
  static const String libelleAcompte = 'Acompte reçu (FCFA)';

  /// `validation.required` — « Le champ :attribute est obligatoire. »
  static String champObligatoire(String champ) =>
      'Le champ $champ est obligatoire.';

  /// `validation.integer` — la phrase du serveur, accent compris.
  static String champEntier(String champ) =>
      'Le champ $champ doit être un entier.';

  /// `validation.min.numeric` — ⚠ le fichier de langue du serveur n'a PAS
  /// d'accent ici (« etre ») : la phrase est recopiée telle qu'il la rend.
  static String champMinimum(String champ, int minimum) =>
      'Le champ $champ doit etre au minimum de $minimum.';

  /// `validation.max.numeric` — sans accent non plus (« etre superieur a »).
  static String champMaximum(String champ, int maximum) =>
      'Le champ $champ ne peut pas etre superieur a $maximum.';

  /// `validation.max.string` — la transmission tient en 255 caractères.
  static const String transmissionTropLongue =
      'Le champ Transmission ne peut pas contenir plus de 255 caracteres.';

  /// `validation.lte.numeric` — la phrase de la vue quand la remise dépasse le
  /// montant brut ([brut] : « 75000.00 »).
  static String remiseSuperieureAuBrut(String brut) =>
      'Le champ $libelleRemise doit être inférieur ou égal à $brut.';

  /// `validation.lte.numeric` — l'acompte dépasse le montant net ([net]).
  static String acompteSuperieurAuNet(String net) =>
      'Le champ $libelleAcompte doit être inférieur ou égal à $net.';

  /// `vehicules.verrou` — un élément engagé ne s'archive pas.
  ///
  /// La vue nomme le NOMBRE d'opérations : « 1 contrat » et « 6 contrats » ne
  /// se corrigent pas de la même façon, et un refus qui ne compte pas laisse
  /// chercher lequel.
  static String archivageVerrouille(int contrats) =>
      'Ce véhicule est engagé dans $contrats contrat(s) de location en cours '
      'ou à venir : il ne peut pas être archivé. La ligne correspondante '
      'deviendrait illisible, et le client a un véhicule réservé.';

  /// `pwa.import_export.purge_refusee_non_archive` — seul un élément archivé se purge.
  static const String purgeRefuseeNonArchive =
      'Purge refusée : seul un élément archivé se purge.';

  /// `pwa.import_export.purge_refusee_referencee` — un contrat ou un entretien,
  /// même passé, cite encore le véhicule.
  static const String purgeRefuseeReferencee =
      'Purge refusée : des enregistrements passés référencent encore cet '
      "élément, et l'effacer les rendrait illisibles.";

  /// `vehicules.verrou` tel que `ParcVehiculeService::messageVerrou` le rend à la
  /// PURGE : le nombre de contrats engagés puis trois d'entre eux (« Contrat
  /// :numero du :debut au :fin », séparés par « · », suivis de « … » au-delà).
  static String purgeVerrouille(
    List<({String numero, DateTime debut, DateTime fin})> contrats,
  ) {
    final apercu = contrats
        .take(3)
        .map(
          (c) =>
              'Contrat ${c.numero} du ${formaterDate(c.debut)} au '
              '${formaterDate(c.fin)}',
        )
        .join(' · ');
    return 'Élément engagé dans ${contrats.length} opération(s) : '
        '$apercu${contrats.length > 3 ? ' …' : ''}. Il ne peut pas être '
        'archivé — la ligne correspondante deviendrait illisible.';
  }
}

/// L'ANNULATION D'UN CONTRAT existe depuis la v38 (26/10/2026) — PA-50 levé.
///
/// `contrats_location_local.statut` (nullable : `null` se lit « actif ») est
/// écrit par `VehiculeDao.annulerContrat`, seul écrivain de saisie, qui enfile
/// la modification `{statut: annule}` dans sa transaction. Le serveur la rejoue
/// par `ContratLocationService::annuler` (le même chemin que la PWA) et
/// l'annulation d'un autre poste ou de la PWA redescend. Un contrat annulé reste
/// lisible, ne compte plus dans les chiffres et ne bloque plus son véhicule
/// (RG-08) : `_contratsEnConflit` l'écarte, comme `ContratLocationService`
/// depuis la même date.

/// L'année maximale d'un véhicule : l'an prochain (`max:` de
/// `Locations::enregistrerVehicule`, `(int) date('Y') + 1`).
int anneeMaximaleVehicule([DateTime? maintenant]) =>
    (maintenant ?? DateTime.now()).year + 1;

/// L'année minimale d'un véhicule (`min:1950`).
const int anneeMinimaleVehicule = 1950;

/// Le contrôle d'une « Année » saisie, aux phrases du serveur ; `null` = valide.
/// Obligatoire, entière, de 1950 à l'an prochain — comme la vue.
String? refusAnnee(String? saisie, {DateTime? maintenant}) {
  final texte = (saisie ?? '').trim();
  if (texte.isEmpty) {
    return MessagesVehicules.champObligatoire(MessagesVehicules.libelleAnnee);
  }
  final valeur = int.tryParse(texte);
  if (valeur == null) {
    return MessagesVehicules.champEntier(MessagesVehicules.libelleAnnee);
  }
  return refusAnneeEntiere(valeur, maintenant: maintenant);
}

/// Les bornes seules, pour un entier déjà lu.
String? refusAnneeEntiere(int valeur, {DateTime? maintenant}) {
  if (valeur < anneeMinimaleVehicule) {
    return MessagesVehicules.champMinimum(
      MessagesVehicules.libelleAnnee,
      anneeMinimaleVehicule,
    );
  }
  final maximum = anneeMaximaleVehicule(maintenant);
  if (valeur > maximum) {
    return MessagesVehicules.champMaximum(
      MessagesVehicules.libelleAnnee,
      maximum,
    );
  }
  return null;
}

/// Le contrôle des « Places » saisies : obligatoires, entières, de 1 à 99.
String? refusPlaces(String? saisie) {
  final texte = (saisie ?? '').trim();
  if (texte.isEmpty) {
    return MessagesVehicules.champObligatoire(MessagesVehicules.libellePlaces);
  }
  final valeur = int.tryParse(texte);
  if (valeur == null) {
    return MessagesVehicules.champEntier(MessagesVehicules.libellePlaces);
  }
  return refusPlacesEntieres(valeur);
}

/// Les bornes seules (1 à 99), pour un entier déjà lu.
String? refusPlacesEntieres(int valeur) {
  if (valeur < 1) {
    return MessagesVehicules.champMinimum(MessagesVehicules.libellePlaces, 1);
  }
  if (valeur > 99) {
    return MessagesVehicules.champMaximum(MessagesVehicules.libellePlaces, 99);
  }
  return null;
}

/// La transmission : texte libre, 255 caractères au plus ; `null` = valide.
String? refusTransmission(String? saisie) =>
    (saisie ?? '').trim().runes.length > 255
    ? MessagesVehicules.transmissionTropLongue
    : null;

/// Le nombre de jours d'une location — bornes demi-ouvertes, `null` si la
/// plage est vide ou inversée.
///
/// Rendre 0 ferait afficher « 0 FCFA » sur un tarif réel, au lieu de dire que
/// la période est fausse.
int? nombreDeJoursEntre(DateTime debut, DateTime fin) {
  final jours = jourDe(fin).difference(jourDe(debut)).inDays;
  return jours <= 0 ? null : jours;
}

/// La catégorie du registre fermé, ou `null` si la valeur stockée n'en est pas.
///
/// Une valeur hors registre n'est **jamais** rangée par défaut dans
/// « voiture » : elle doit se voir.
CategorieVehicule? categorieDepuisCode(String? code) =>
    CategorieVehicule.depuisCode(code);
