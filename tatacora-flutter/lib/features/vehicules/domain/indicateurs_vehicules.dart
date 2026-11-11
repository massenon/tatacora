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
/// Rend `null` si la liste est vide ou si **une seule** valeur est illisible OU
/// ABSENTE (`null`, depuis la v41 : le montant d'un contrat d'avant n'est pas
/// connu) : mieux vaut ne rien afficher qu'un total silencieusement incomplet.
String? sommeDecimales(Iterable<String?> montants) {
  var centimes = 0;
  var vus = 0;

  for (final brut in montants) {
    if (brut == null) return null;
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

  /// Les contrats ACTIFS (`statut != annule`) qui chevauchent la période —
  /// `$agregats['contrats_actifs']` de la vue (`ParcVehiculeService::
  /// agregerContratsActifs`).
  final int contratsSurPeriode;

  /// Les contrats ANNULÉS de l'ensemble affiché — `contratsAnnulesCount` de la
  /// vue : `$contrats->count() - $agregats['contrats_actifs']`, où `$contrats`
  /// est déjà FILTRÉ par le statut choisi. Avec le filtre par défaut « Contrats
  /// actifs » la vue dit donc « 0 annulé(s) » ; c'est « Tous » ou « Annulés » qui
  /// les compte. Le poste fait de même — la même phrase, le même chiffre.
  final int contratsAnnules;

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

  /// Somme des restes dus (montant figé − acompte) des contrats ACTIFS de la
  /// période — `agregerContratsActifs()['reste_a_encaisser']` de la vue. `'0.00'`
  /// quand aucun contrat actif ne compte ; `null` si UN SEUL contrat n'a pas de
  /// montant ou d'acompte connu (signé avant la v41 et pas encore reçu du
  /// serveur) : une somme amputée dirait « tout est soldé » sur un écran où l'on
  /// décide de relancer un client.
  final String? resteAEncaisser;

  final int joursLoues;

  /// Ce que chaque indicateur absent doit dire à l'écran. Une seule source :
  /// la carte lit cette table, elle ne réécrit pas la phrase.
  static const Map<String, String> raisons = {
    'reste_a_encaisser':
        'Au moins un contrat de la période n’a ni montant ni acompte connus '
        '(signé avant que ce poste les enregistre, et pas encore reçu du '
        'serveur) : la somme serait amputée, et « 0 FCFA » se lirait « tout '
        'est soldé ».',
    // ⚠ Corrigé le 09/10/2026 : le texte disait « Choisissez une période »
    // alors que le taux est aussi `null` sur un parc VIDE, période choisie —
    // une raison fausse envoie chercher une date qui est déjà posée.
    'taux_occupation':
        'Aucun taux sans période choisie ni véhicule au parc : « 0 % » se '
        'lirait comme un parc inoccupé.',
    'chiffre_affaires':
        'Au moins un contrat de la période n’a pas de montant connu (signé '
        'avant que ce poste le fige, et pas encore reçu du serveur) : une '
        'somme amputée serait plausible et fausse.',
    'immobilises':
        'Compté sur le statut courant des véhicules (« Entretien », « Hors '
        'service »), et non sur les immobilisations de la période, que ce '
        'poste n’enregistre pas.',
  };
}

/// Calcule les six indicateurs. Fonction **pure** : éprouvable sans réseau.
///
/// [debut] et [fin] sont `Y-m-d` ou `null`. [joursPeriode] est le nombre de
/// jours de la période choisie, `null` si elle ne l'est pas. [statut] est le
/// filtre de la vue (`actif` par défaut, `annule`, ou vide pour « Tous ») : la
/// vue calcule ses chiffres sur les contrats DÉJÀ filtrés (`contratsFiltres`),
/// puis n'en compte comme actifs que ceux qui ne sont pas annulés.
IndicateursVehicules calculerIndicateurs({
  required List<Vehicule> parc,
  required List<ContratLocation> contrats,
  required String? debut,
  required String? fin,
  required int? joursPeriode,
  String statut = statutContratActif,
}) {
  final retenus = contrats
      .where((c) => c.chevauche(debut, fin))
      .where(
        (c) => switch (statut) {
          statutContratActif => !c.annule,
          statutContratAnnule => c.annule,
          _ => true,
        },
      )
      .toList(growable: false);
  // `agregerContratsActifs` : « actif » = `statut !== 'annule'`, la seule
  // définition du dépôt.
  final actifs = retenus.where((c) => !c.annule).toList(growable: false);

  final joursLoues = actifs.fold(0, (s, c) => s + c.nombreJours);

  // Le dénominateur du maître : parc × jours de la période. Un parc vide ou
  // une période absente rendent le taux insensé — `null`, jamais 0 %.
  final denominateur = (joursPeriode == null || parc.isEmpty)
      ? null
      : parc.length * joursPeriode;

  return IndicateursVehicules(
    parc: parc.length,
    immobilises: parc.where((v) => v.statut?.estImmobilise ?? false).length,
    contratsSurPeriode: actifs.length,
    contratsAnnules: retenus.length - actifs.length,
    chiffreAffaires: actifs.isEmpty
        ? '0.00'
        : sommeDecimales(actifs.map((c) => c.montant)),
    tauxOccupation: denominateur == null || denominateur == 0
        ? null
        : ((joursLoues * 100) / denominateur).round(),
    resteAEncaisser: actifs.isEmpty
        ? '0.00'
        : sommeDecimales(actifs.map((c) => c.resteDu)),
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
