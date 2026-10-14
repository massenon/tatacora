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

  /// `vehicules.verrou` — un élément engagé ne s'archive pas.
  ///
  /// La vue nomme le NOMBRE d'opérations : « 1 contrat » et « 6 contrats » ne
  /// se corrigent pas de la même façon, et un refus qui ne compte pas laisse
  /// chercher lequel.
  static String archivageVerrouille(int contrats) =>
      'Ce véhicule est engagé dans $contrats contrat(s) de location en cours '
      'ou à venir : il ne peut pas être archivé. La ligne correspondante '
      'deviendrait illisible, et le client a un véhicule réservé.';
}

/// ⚠ **L'ANNULATION D'UN CONTRAT N'EXISTE PAS — PA-50, lacune assumée.**
///
/// Ce n'est pas un oubli de ce lot, et ce n'est pas rattrapable ici :
/// `contrats_location_local` **n'a aucune colonne de statut**, pas plus que la
/// table `contrats_location` du serveur. Il n'y a donc rien à écrire pour
/// marquer un contrat annulé, et rien à lire pour le distinguer d'un contrat
/// actif.
///
/// Aucune méthode `annuler()` n'est exposée, **délibérément** : « une méthode
/// qui ne libère rien laisserait croire que le cas est traité ». Un contrat
/// saisi par erreur bloque son véhicule **définitivement** — c'est la limite
/// connue, et l'écran la dit à la place du bouton que le maître propose.
///
/// La conséquence à ne pas perdre de vue : supprimer la ligne serait la seule
/// façon de libérer le véhicule, et la suppression est interdite sur une table
/// transactionnelle. Le jour de l'arbitrage (Architecte + Product Owner), c'est
/// une **colonne** qu'il faudra ajouter aux deux schémas, pas une méthode ici.
const String refusAnnulationContrat =
    // Texte visible : le code PA-50 est retiré (directive du PO, 14/10/2026).
    'Un contrat de location ne peut pas être annulé sur ce poste. Le véhicule '
    'reste engagé jusqu\'à la fin de la période saisie. Corriger une erreur '
    'de saisie suppose une décision qui n\'est pas encore prise.';

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
