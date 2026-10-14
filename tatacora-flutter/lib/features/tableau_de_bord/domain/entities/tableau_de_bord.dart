/// Le **tableau de bord** — M11, EF-M11-01 / 03 / 04.
///
/// ## Depuis le 10/10/2026, M11 se lit sur le poste — indicateur par indicateur
///
/// M11 ne possède aucune table (`TableauDeBordService` : « service de lecture
/// agrégée, jamais de duplication de données »). Il ne peut donc que **relire**
/// les tables des autres modules, et la question n'est pas « le poste a-t-il un
/// serveur ? » (il n'en a plus) mais « le poste détient-il TOUTES les sources
/// de CET indicateur ? ». PA-120 : un indicateur dont une source manque donne un
/// chiffre plus petit que la réalité, sans le dire.
///
/// - **Calculés** (source complète, règle confrontée au serveur par PHP) : taux
///   d'occupation, réservations en attente, valeur du stock, employés actifs,
///   ventilation du chiffre d'affaires facturé par activité — et, depuis le
///   lot 5 (12/10/2026, D234), chiffre d'affaires encaissé, trésorerie de
///   caisse et factures non soldées : `PaiementsFactureDao` écrit les
///   encaissements, le comptoir rattache ses ventes au comptant à la session
///   de caisse, et `data/tableau_de_bord_local.dart` les calcule avec les
///   formules du serveur (incohérences D233 répliquées).
/// - **« — » avec leur raison datée** ([IndicateurTableauDeBord.indisponible]) :
///   dépenses cumulées et séries mensuelles. Elles lisent toutes les écritures
///   de classe 6, et ce poste n'y passe que les pièces des dépenses courantes
///   saisies (ni la réception, ni la paie) : la somme serait un minorant
///   présenté comme le total. Raisons dans `RaisonsTableauDeBord`.
///
/// Le calcul vit dans `domain/indicateurs_locaux.dart` et
/// `domain/periode_locale.dart` ; ce fichier ne porte que les entités.
///
/// ## Les montants restent des CHAÎNES jusqu'à l'affichage
///
/// Le serveur les produit en `bcmath` (`'125000.00'`) et le client garde ce
/// format : aucune arithmétique flottante sur un montant, et une variation
/// calculée en entiers avec la troncature de `bcdiv`.
library;

/// Les périodes du SÉLECTEUR de l'écran — le registre de la vue d'accueil
/// (12/10/2026, D296). **Registre fermé.**
///
/// Codes : `Periode::CODES_CALENDAIRES`, dans leur ordre ; libellés :
/// `lang/fr/accueil_pwa.php` (`periodes`), l'ordre des options du `<select>` ;
/// défaut : `Accueil::$filtrePeriode` = `'mois'`. Les trois sont relus par
/// exécution de PHP (`tool/tableau_de_bord/exporter_indicateurs.php`) : une
/// copie qui divergerait de la vue resterait verte sinon.
///
/// Ce sont des fenêtres CALENDAIRES (`Periode::resoudre`) : « Ce mois » couvre
/// le mois entier, passé ET à venir, comme dans la vue — pas « les 30 derniers
/// jours ». ⚠ Jusqu'au 12/10/2026 ce registre portait les cinq codes « à
/// date » de l'API (`7j`, `30j`…, défaut `30j`) : à l'ouverture, le CA
/// encaissé, la trésorerie et les alertes ne portaient pas sur la même fenêtre
/// que la PWA. Ces codes vivent désormais dans [PeriodeADate], pour M14 seul.
enum PeriodeTableauDeBord {
  // Apostrophe DROITE : celle de `accueil_pwa.periodes.aujourdhui`.
  aujourdHui('aujourdhui', "Aujourd'hui"),
  semaine('semaine', 'Cette semaine'),
  mois('mois', 'Ce mois'),
  trimestre('trimestre', 'Ce trimestre'),
  semestre('semestre', 'Ce semestre'),
  annee('annee', 'Cette année'),

  /// Les bornes viennent des deux champs « Du » / « Au » de la vue. Sans ses
  /// deux dates, la période se résout sur le mois courant, comme
  /// `Periode::resoudre` — le libellé de période affiche alors les dates
  /// RÉELLES du mois : l'écran dit exactement ce qu'il calcule.
  personnalisee('personnalisee', 'Période personnalisée');

  const PeriodeTableauDeBord(this.code, this.libelle);

  final String code;
  final String libelle;

  /// Le défaut de la vue (`Accueil::$filtrePeriode`). Deux défauts différents
  /// feraient afficher, à l'ouverture, une période que la PWA n'affiche pas.
  static const PeriodeTableauDeBord parDefaut = PeriodeTableauDeBord.mois;

  static PeriodeTableauDeBord? parCode(String? code) {
    for (final p in values) {
      if (p.code == code) return p;
    }
    return null;
  }
}

/// La période demandée à l'écran : un code du sélecteur et, pour « Période
/// personnalisée », ses deux bornes saisies (jours, bornes INCLUSES côté
/// saisie, comme `Periode::personnalisee`).
///
/// [du] et [au] survivent à un changement de code, comme les propriétés `$du`
/// et `$au` du composant : revenir à « Période personnalisée » retrouve les
/// dates saisies.
final class SelectionPeriode {
  const SelectionPeriode(this.periode, {this.du, this.au});

  static const SelectionPeriode parDefaut = SelectionPeriode(
    PeriodeTableauDeBord.parDefaut,
  );

  final PeriodeTableauDeBord periode;
  final DateTime? du;
  final DateTime? au;

  SelectionPeriode avecPeriode(PeriodeTableauDeBord p) =>
      SelectionPeriode(p, du: du, au: au);

  SelectionPeriode avecDu(DateTime jour) =>
      SelectionPeriode(periode, du: jour, au: au);

  SelectionPeriode avecAu(DateTime jour) =>
      SelectionPeriode(periode, du: du, au: jour);

  /// Le champ « Du » VIDÉ — l'`<input type="date">` de la vue rend alors une
  /// chaîne vide à `$du`, et `Periode::resoudre` retombe sur le mois courant
  /// (`FenetreTableauDeBord.resoudre`, sans ses deux dates = le mois).
  SelectionPeriode sansDu() => SelectionPeriode(periode, au: au);

  /// Le champ « Au » vidé — même effet que [sansDu].
  SelectionPeriode sansAu() => SelectionPeriode(periode, du: du);

  @override
  bool operator ==(Object other) =>
      other is SelectionPeriode &&
      other.periode == periode &&
      other.du == du &&
      other.au == au;

  @override
  int get hashCode => Object.hash(periode, du, au);
}

/// Les cinq fenêtres « à date » de `Periode::CODES` — le contrat de l'API
/// `/tableau-de-bord` et du moteur d'états (`EtatTableauDeBord` :
/// `Periode::depuisCode(Periode::DEFAUT)`). Elles s'arrêtent à la fin de la
/// journée en cours. Plus aucun sélecteur ne les offre : seul l'aperçu de
/// l'état « Tableau de bord » de M14 les emploie, avec le défaut du serveur.
enum PeriodeADate {
  aujourdHui('aujourdhui'),
  septJours('7j'),
  trenteJours('30j'),
  trimestre('trimestre'),
  annee('annee');

  const PeriodeADate(this.code);

  final String code;

  /// `Periode::DEFAUT`.
  static const PeriodeADate parDefaut = PeriodeADate.trenteJours;
}

/// L'unité d'un indicateur, telle que le serveur la déclare.
enum UniteIndicateur {
  montant('montant'),
  pourcentage('pourcentage'),
  nombre('nombre');

  const UniteIndicateur(this.code);

  final String code;

  /// Une unité inconnue **n'est pas devinée** : la lecture échoue.
  ///
  /// La deviner reviendrait à afficher un pourcentage en francs, ou l'inverse
  /// — et un taux d'occupation de « 68 FCFA » ne se remarque pas forcément au
  /// premier coup d'œil sur une bande de six chiffres.
  static UniteIndicateur parCode(String code) => values.firstWhere(
    (u) => u.code == code,
    orElse: () =>
        throw ArgumentError.value(code, 'unite', 'Unité d’indicateur inconnue'),
  );
}

/// Un indicateur et sa comparaison avec la période précédente.
final class IndicateurTableauDeBord {
  const IndicateurTableauDeBord({
    required this.cle,
    required this.valeur,
    required this.precedent,
    required this.unite,
    this.variationPct,
    this.mention,
  }) : raisonAbsence = null;

  /// Un indicateur dont une source MANQUE sur ce poste : il n'a pas de valeur,
  /// et il dit pourquoi. Ce n'est ni un zéro (« 0 FCFA encaissés » se lit comme
  /// une journée sans recette) ni une panne : rien n'est à réessayer.
  const IndicateurTableauDeBord.indisponible({
    required this.cle,
    required this.unite,
    required String raison,
  }) : valeur = '',
       precedent = '',
       variationPct = null,
       mention = null,
       raisonAbsence = raison;

  /// Ce que la valeur NE comprend PAS, quand elle est une somme partielle :
  /// « 2 article(s) sans coût ». Un chiffre minoré qui ne le dit pas se lit
  /// comme exact (PA-120).
  final String? mention;

  /// La raison datée de l'absence, ou `null` quand l'indicateur est calculé.
  final String? raisonAbsence;

  bool get estDisponible => raisonAbsence == null;

  /// La clé du serveur (`chiffre_affaires_encaisse`…), conservée telle quelle :
  /// c'est elle qui relie l'écran au contrat, pas le libellé affiché.
  final String cle;

  /// **Chaîne**, jamais un nombre — voir l'en-tête de bibliothèque.
  final String valeur;
  final String precedent;

  /// `null` quand la période précédente vaut zéro : il n'y a alors **aucune
  /// comparaison possible**, et le serveur le dit en n'envoyant rien.
  ///
  /// L'écran doit rendre « — », jamais « 0 % » ni « +100 % » : les deux
  /// affirmeraient une comparaison qui n'a pas eu lieu.
  final String? variationPct;

  final UniteIndicateur unite;

  bool get aUneComparaison => estDisponible && variationPct != null;

  /// Vrai quand la variation est positive. `null` sans comparaison.
  bool? get enHausse {
    final v = variationPct;
    if (v == null) return null;
    final nombre = double.tryParse(v);
    if (nombre == null) return null;
    return nombre > 0;
  }
}

/// Le tableau de bord d'une période.
final class TableauDeBord {
  const TableauDeBord({
    required this.libellePeriode,
    required this.indicateurs,
    this.debut,
    this.finExclue,
  });

  /// « Du 01/10/2026 au 31/10/2026 », composé par [FenetreTableauDeBord] —
  /// le dernier jour INCLUS, pas la borne exclue. Confronté au vrai `Periode`
  /// PHP : un décalage d'un jour ne se verrait qu'en rapprochant deux
  /// documents.
  final String libellePeriode;

  /// Les bornes de la période, telles que [FenetreTableauDeBord] les calcule.
  ///
  /// Transmises aux blocs de l'onglet « Pilotage consolidé » (occupation,
  /// meilleures ventes, dépense courante) : UN seul calcul de fenêtre par
  /// affichage, partagé par la bande et ces blocs. `null` sur une réponse qui
  /// ne les porte pas : les blocs disent alors que la période n'est pas
  /// connue, ils ne la devinent pas.
  final DateTime? debut;

  /// Borne de fin **exclue** (`fin_exclue` au serveur).
  final DateTime? finExclue;

  final List<IndicateurTableauDeBord> indicateurs;

  IndicateurTableauDeBord? parCle(String cle) {
    for (final i in indicateurs) {
      if (i.cle == cle) return i;
    }
    return null;
  }
}

/// Un point de la **série mensuelle** — `GET /tableau-de-bord/series`.
///
/// Chaque point est calculé côté serveur **par le même code que le KPI**
/// (`Periode::mois()` + `chiffreAffairesEncaisse()`). Le client ne recalcule
/// rien : la courbe et la bande d'indicateurs ne peuvent donc pas se
/// contredire.
final class PointMensuel {
  const PointMensuel({
    required this.mois,
    required this.chiffreAffaires,
    required this.depenses,
  });

  /// `2026-09` — l'identifiant du mois, tel que le serveur le rend.
  final String mois;

  /// Chaînes, comme partout ailleurs sur ce module : jamais d'arithmétique
  /// côté client.
  final String chiffreAffaires;
  final String depenses;

  /// Le libellé court de l'axe — « sept. ».
  ///
  /// Composé ici et non au serveur : c'est de l'affichage, et il dépend de la
  /// langue de l'écran. Le **mois**, lui, vient du serveur.
  String get libelleCourt {
    final parties = mois.split('-');
    if (parties.length != 2) return mois;
    final index = int.tryParse(parties[1]);
    if (index == null || index < 1 || index > 12) return mois;
    return _moisCourts[index - 1];
  }

  static const _moisCourts = [
    'janv.',
    'févr.',
    'mars',
    'avr.',
    'mai',
    'juin',
    'juil.',
    'août',
    'sept.',
    'oct.',
    'nov.',
    'déc.',
  ];
}

/// La part d'une activité dans le chiffre d'affaires facturé.
///
/// ⚠ **Ce n'est pas la mesure du prototype**, qui compte les réservations
/// contenant chaque service. Le schéma serveur ne porte aucun service sur
/// `reservations` : on ventile des **montants facturés**
/// (`lignes_facture.source_module`, RG-04). Voir PA-121.
final class PartActivite {
  const PartActivite({required this.module, required this.montant});

  /// `hebergement` | `restaurant` | `bar` | `tourisme` | `vehicule`, ou le CODE
  /// de module du registre (`M1` | `M4` | `M5` | `M8` | `M9`, PA-170).
  final String module;

  final String montant;

  /// Le nom d'activité, que [module] soit un nom ou un code de module. Une
  /// valeur inconnue reste telle quelle plutôt que d'être masquée.
  String get activite => _parCode[module] ?? module;

  /// Le libellé affiché. Une activité inconnue garde **son code** plutôt que
  /// d'être masquée : une part invisible fausserait la lecture du camembert.
  String get libelle => _libelles[activite] ?? module;

  /// Le registre RÉEL de `lignes_facture.source_module` est le CODE de module
  /// (PA-170) : le nom de domaine n'est qu'un alias historique de l'écran.
  static const _parCode = {
    'M1': 'hebergement',
    'M4': 'restaurant',
    'M5': 'bar',
    'M9': 'tourisme',
    'M8': 'vehicule',
  };

  // Les libellés de la légende de la vue : `noms-activites` (accueil.blade.php
  // l.686-692) rend M4 par `accueil_pwa.services.restauration`, soit
  // « Restauration » — jamais « Restaurant » (corrigé le 14/10/2026).
  static const _libelles = {
    'hebergement': 'Hébergement',
    'restaurant': 'Restauration',
    'bar': 'Bar',
    'tourisme': 'Tourisme',
    'vehicule': 'Véhicule',
  };
}

/// Les séries des graphiques.
final class SeriesTableauDeBord {
  const SeriesTableauDeBord({
    required this.mensuelle,
    required this.ventilation,
    this.raisonMensuelle,
  });

  /// Pourquoi la série mensuelle est absente — `null` quand elle est calculée.
  /// « Aucune donnée » et « non calculable sur ce poste » ne se disent pas
  /// pareil : la première rassure, la seconde est vraie.
  final String? raisonMensuelle;

  /// Du plus ANCIEN au plus récent — l'ordre du serveur, et celui de l'axe.
  ///
  /// Un axe des temps inversé se lit à l'envers : une hausse y ressemble à une
  /// baisse, et personne ne relit l'ordre des étiquettes avant de conclure.
  final List<PointMensuel> mensuelle;

  /// Par montant décroissant — l'ordre du serveur.
  final List<PartActivite> ventilation;

  bool get estVide => mensuelle.isEmpty && ventilation.isEmpty;

  /// Le plus grand montant de la série, pour borner l'axe des ordonnées.
  ///
  /// Zéro quand tout est à zéro : l'écran doit alors afficher une échelle
  /// plate, pas une division par zéro.
  double get maximumMensuel {
    var max = 0.0;
    for (final p in mensuelle) {
      final ca = double.tryParse(p.chiffreAffaires) ?? 0;
      final dep = double.tryParse(p.depenses) ?? 0;
      if (ca > max) max = ca;
      if (dep > max) max = dep;
    }
    return max;
  }
}
