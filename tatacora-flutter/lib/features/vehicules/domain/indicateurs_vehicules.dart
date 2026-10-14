/// La bande d'indicateurs de `m8-locations.js` `kpisVehicules()` l.386-405 —
/// **six cartes**, dans l'ordre du maître.
///
/// ## Le serveur ne rend AUCUN indicateur pour M8
///
/// Contrairement à M11, où huit KPI sont calculés côté serveur et où ce client
/// n'additionne rien (PA-120), le groupe `vehicules` n'expose que des listes.
/// Les six cartes du maître doivent donc être calculées ici — ou refusées.
/// Deux le sont, et pour la même cause : le schéma n'a pas la colonne.
///
/// ## Les montants s'additionnent en CENTIMES ENTIERS, jamais en `double`
///
/// « Comparaison de montants : `bccomp()` en PHP, jamais une égalité flottante
/// directe » — la règle projet vaut aussi ici. `montant` arrive en chaîne
/// (`DECIMAL(15,2)`) ; [sommeDecimales] la convertit en centimes entiers,
/// additionne, et recompose. Un `double` accumulerait une erreur sur un
/// registre de plusieurs centaines de contrats, invisible ligne à ligne.
///
/// **Une valeur illisible fait rendre `null`, pas zéro.** Une somme amputée
/// d'un contrat serait plausible et fausse ; « — » se voit.
library;

import 'entities/contrat_location.dart';
import 'entities/vehicule.dart';

/// Additionne des montants décimaux en chaîne, **exactement**.
///
/// Rend `null` si la liste est vide ou si **une seule** valeur est illisible :
/// mieux vaut ne rien afficher qu'un total silencieusement incomplet.
String? sommeDecimales(Iterable<String> montants) {
  var centimes = 0;
  var vus = 0;

  for (final brut in montants) {
    final c = _enCentimes(brut);
    if (c == null) return null;
    centimes += c;
    vus++;
  }

  if (vus == 0) return null;

  final negatif = centimes < 0;
  final absolu = centimes.abs();
  final unites = absolu ~/ 100;
  final reste = absolu % 100;

  return '${negatif ? '-' : ''}$unites.${reste.toString().padLeft(2, '0')}';
}

int? _enCentimes(String brut) {
  final texte = brut.trim().replaceAll(',', '.');
  if (texte.isEmpty) return null;

  final negatif = texte.startsWith('-');
  final absolu = negatif ? texte.substring(1) : texte;
  final point = absolu.indexOf('.');

  final partieEntiere = point < 0 ? absolu : absolu.substring(0, point);
  final partieDecimale = point < 0
      ? '00'
      : absolu.substring(point + 1).padRight(2, '0');

  // Plus de deux décimales : le serveur n'en produit jamais, et deviner
  // l'arrondi serait inventer un centime.
  if (partieDecimale.length > 2) return null;

  final unites = int.tryParse(partieEntiere);
  final centiemes = int.tryParse(partieDecimale);
  if (unites == null || centiemes == null) return null;

  final total = unites * 100 + centiemes;
  return negatif ? -total : total;
}

/// Les six indicateurs du maître, chacun avec sa disponibilité réelle.
///
/// `null` veut dire **« la donnée n'existe pas »**, jamais « zéro » — les deux
/// ne disent pas la même chose (Article 7). Chaque `null` structurel porte sa
/// raison dans [raisons].
final class IndicateursVehicules {
  const IndicateursVehicules({
    required this.parc,
    required this.immobilises,
    required this.contratsSurPeriode,
    required this.contratsAnnules,
    required this.chiffreAffaires,
    required this.tauxOccupation,
    required this.resteAEncaisser,
    required this.joursLoues,
  });

  /// Le nombre de véhicules connus du serveur.
  final int parc;

  /// Les véhicules dont le **statut courant** est `entretien` ou
  /// `hors_service`.
  ///
  /// ⚠ Ce n'est pas tout à fait la mesure du maître, qui compte les
  /// *immobilisations enregistrées* sur la période. `entretiens_vehicule`
  /// n'étant relisible par aucune route, le statut du véhicule est la seule
  /// source — et il décrit **aujourd'hui**, pas la période choisie.
  final int immobilises;

  /// Les contrats qui chevauchent la période.
  ///
  /// Le maître dit « Contrats actifs ». Faute de colonne `statut` (PA-50),
  /// **tout contrat est actif** : le mot est donc exact, mais pour une raison
  /// qui n'est pas celle du maître.
  final int contratsSurPeriode;

  /// **Toujours `null`.** Aucun contrat ne peut être annulé : ni colonne
  /// `statut`, ni route, ni méthode `annuler()` sur le modèle (PA-50).
  /// Afficher « 0 » annoncerait « aucune annulation », c'est-à-dire une bonne
  /// nouvelle vérifiée par personne — alors que la vérité est « l'annulation
  /// n'existe pas ».
  final int? contratsAnnules;

  /// Somme des `montant` des contrats de la période, en chaîne décimale.
  ///
  /// `'0.00'` quand la période n'en retient AUCUN : la somme porte sur les
  /// contrats de ce poste, tous lus, et il n'y en a pas — c'est la mesure, non
  /// une absence de source (la vue écrit « 0 FCFA », `locations.blade.php`
  /// l.140). `null` seulement si un montant est illisible : une somme amputée
  /// serait plausible et fausse. ⚠ Corrigé le 09/10/2026 : cette valeur était
  /// `null` pour une période sans contrat, ce qui affichait « — » sur un
  /// chiffre qui existe.
  final String? chiffreAffaires;

  /// Jours loués ÷ (parc × jours de la période), en pourcentage entier.
  ///
  /// `null` sans période choisie — le maître affiche alors « — » et
  /// « Choisissez une période », jamais « 0 % ».
  final int? tauxOccupation;

  /// **Toujours `null`.** `contrats_location` n'a **aucune colonne d'acompte**,
  /// et `CreerContratLocationRequest` n'en accepte aucun. Sans acompte, aucun
  /// reste à encaisser ne se calcule. Afficher « 0 F » dirait « tout est
  /// soldé » sur un écran où l'on décide de relancer un client.
  final String? resteAEncaisser;

  final int joursLoues;

  /// Ce que chaque indicateur absent doit dire à l'écran. Une seule source :
  /// la carte lit cette table, elle ne réécrit pas la phrase.
  static const Map<String, String> raisons = {
    'contrats_annules':
        // Texte visible : sans code interne ni nom de table (directive du
        // PO, 14/10/2026). Raison technique : aucune colonne de statut sur
        // les contrats de ce poste (PA-50).
        'Un contrat ne peut pas être annulé sur ce poste : le nombre '
        'd’annulations n’existe pas. « 0 » se lirait « aucune annulation » ; '
        'la vérité est « aucune annulation n’est possible ».',
    'reste_a_encaisser':
        // Raison technique : aucune colonne d'acompte sur les contrats.
        'Ce poste n’enregistre aucun acompte sur un contrat de location : '
        'le reste à encaisser n’est pas connu. « 0 FCFA » se lirait « tout '
        'est soldé ».',
    // ⚠ Corrigé le 09/10/2026 : le texte disait « Choisissez une période »
    // alors que le taux est aussi `null` sur un parc VIDE, période choisie —
    // une raison fausse envoie chercher une date qui est déjà posée.
    'taux_occupation':
        'Aucun taux sans période choisie ni véhicule au parc : « 0 % » se '
        'lirait comme un parc inoccupé.',
    'chiffre_affaires':
        'Un montant de contrat que ce client n’a pas su lire — une somme '
        'amputée serait plausible et fausse.',
    'immobilises':
        'Compté sur le statut courant des véhicules (« Entretien », « Hors '
        'service »), et non sur les immobilisations de la période, que ce '
        'poste n’enregistre pas.',
  };
}

/// Calcule les six indicateurs. Fonction **pure** : éprouvable sans réseau.
///
/// [debut] et [fin] sont `Y-m-d` ou `null`. [joursPeriode] est le nombre de
/// jours de la période choisie, `null` si elle ne l'est pas.
IndicateursVehicules calculerIndicateurs({
  required List<Vehicule> parc,
  required List<ContratLocation> contrats,
  required String? debut,
  required String? fin,
  required int? joursPeriode,
}) {
  final retenus = contrats
      .where((c) => c.chevauche(debut, fin))
      .toList(growable: false);

  final joursLoues = retenus.fold(0, (s, c) => s + c.nombreJours);

  // Le dénominateur du maître : parc × jours de la période. Un parc vide ou
  // une période absente rendent le taux insensé — `null`, jamais 0 %.
  final denominateur = (joursPeriode == null || parc.isEmpty)
      ? null
      : parc.length * joursPeriode;

  return IndicateursVehicules(
    parc: parc.length,
    immobilises: parc.where((v) => v.statut?.estImmobilise ?? false).length,
    contratsSurPeriode: retenus.length,
    // Structurellement absent — voir le champ.
    contratsAnnules: null,
    chiffreAffaires: retenus.isEmpty
        ? '0.00'
        : sommeDecimales(retenus.map((c) => c.montant)),
    tauxOccupation: denominateur == null || denominateur == 0
        ? null
        : ((joursLoues * 100) / denominateur).round(),
    // Structurellement absent — voir le champ.
    resteAEncaisser: null,
    joursLoues: joursLoues,
  );
}

/// Le nombre de jours entre deux dates `Y-m-d`, bornes demi-ouvertes.
///
/// `null` si l'une des deux manque ou n'est pas lisible. Le maître écrit
/// `nbJours(d, f)` et s'en sert pour le montant d'une période : rendre 0 sur
/// une date illisible ferait afficher « 0 F » sur un tarif réel.
int? nombreDeJours(String? debut, String? fin) {
  if (debut == null || fin == null) return null;
  final d = DateTime.tryParse(debut);
  final f = DateTime.tryParse(fin);
  if (d == null || f == null) return null;
  final jours = f.difference(d).inDays;
  return jours <= 0 ? null : jours;
}
