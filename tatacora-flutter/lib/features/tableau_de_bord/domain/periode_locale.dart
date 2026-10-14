/// La fenêtre de temps d'un tableau de bord — calculée SUR LE POSTE.
///
/// Vue Blade maîtresse (PA-183) : `pwa/livewire/accueil.blade.php`, libellé de
/// période et bornes de `App\Domain\TableauxDeBord\Data\Periode`.
///
/// ## Pourquoi cette règle existe ici, alors qu'elle « ne se rejouait jamais »
///
/// Jusqu'au 14/09/2026 les bornes descendaient de la réponse du serveur, et le
/// client s'interdisait de les recalculer : un décalage d'un jour entre deux
/// règles ne se verrait qu'en rapprochant deux documents (PA-120). Il n'y a
/// plus de serveur. La règle vit donc ici, **en une seule copie**, et elle est
/// confrontée à la VRAIE classe PHP par exécution
/// (`tool/tableau_de_bord/exporter_indicateurs.php`) : bornes, période
/// précédente, nombre de jours et libellé, sur les deux familles de codes et
/// sur des dates de référence choisies pour casser une règle approximative
/// (fin de mois, fin de trimestre, 1er janvier, 29 février, un dimanche).
///
/// ## Deux familles, comme la classe `Periode` du serveur
///
/// 1. **Calendaires** ([FenetreTableauDeBord.resoudre], `Periode::resoudre`) —
///    le sélecteur de l'écran, celui de la vue d'accueil : la période ENTIÈRE,
///    passée ou à venir (« Ce trimestre » au 10 octobre = du 1er octobre au
///    31 décembre). C'est la fenêtre de TOUT le tableau de bord : bande,
///    pilotage, alertes, graphiques.
/// 2. **« À date »** ([FenetreTableauDeBord.depuis], `Periode::depuisCode`) —
///    le contrat de l'API et du moteur d'états : elles s'arrêtent à la fin de
///    la journée en cours (« ce trimestre » au 10 octobre = dix jours). Seul
///    l'aperçu M14 de l'état « Tableau de bord » les emploie.
///
/// `trimestre` et `annee` existent dans les deux familles avec des bornes
/// différentes — deux questions distinctes, comme au serveur.
///
/// ## Bornes semi-ouvertes, comme RG-01 et comme le serveur
///
/// `[debut, finExclue)` : [finExclue] est le premier instant EXCLU.
///
/// ## Arithmétique de CALENDRIER, jamais de durées
///
/// Retrancher `Duration(days: 30)` d'une date locale traverse un changement
/// d'heure et tombe à 23 h la veille. Toutes les bornes sont construites par
/// `DateTime(année, mois, jour ± n)`, que Dart normalise : minuit reste minuit.
library;

import 'entities/tableau_de_bord.dart';

/// La fenêtre résolue d'une période du registre fermé.
final class FenetreTableauDeBord {
  const FenetreTableauDeBord._({required this.debut, required this.finExclue});

  /// Une fenêtre dont les bornes sont DÉJÀ résolues (celles de la réponse
  /// [TableauDeBord]) — pour les blocs qui reçoivent la période d'en-tête sans
  /// avoir à la recalculer.
  const FenetreTableauDeBord.entre(DateTime debut, DateTime finExclue)
    : this._(debut: debut, finExclue: finExclue);

  /// Résout une fenêtre « À DATE » ([PeriodeADate], `Periode::depuisCode`) à
  /// l'instant [maintenant] — l'horloge est INJECTÉE : un test qui lirait
  /// l'heure réelle serait vert un jour et rouge le lendemain.
  factory FenetreTableauDeBord.depuis(
    PeriodeADate periode,
    DateTime maintenant,
  ) {
    final jour = DateTime(maintenant.year, maintenant.month, maintenant.day);
    // `finJournee` = minuit du lendemain : la fenêtre « à date » l'embrasse.
    final finJournee = DateTime(jour.year, jour.month, jour.day + 1);

    final debut = switch (periode) {
      PeriodeADate.aujourdHui => jour,
      PeriodeADate.septJours => DateTime(
        finJournee.year,
        finJournee.month,
        finJournee.day - 7,
      ),
      PeriodeADate.trenteJours => DateTime(
        finJournee.year,
        finJournee.month,
        finJournee.day - 30,
      ),
      // Premier jour du trimestre civil : mois 1, 4, 7 ou 10.
      PeriodeADate.trimestre => DateTime(
        jour.year,
        _premierMoisDuTrimestre(jour.month),
        1,
      ),
      PeriodeADate.annee => DateTime(jour.year, 1, 1),
    };

    return FenetreTableauDeBord._(debut: debut, finExclue: finJournee);
  }

  /// Résout la période CALENDAIRE du sélecteur — `Periode::resoudre($cle,
  /// $du, $au)`, appelée par `Accueil::periode()` — à l'instant [maintenant].
  ///
  /// - « Cette semaine » commence le LUNDI (`startOfWeek()` de Carbon, vérifié
  ///   par exécution un dimanche) ;
  /// - « Ce semestre » : 1er janvier ou 1er juillet ;
  /// - « Période personnalisée » : `[du, au + 1 jour)` — « du 1er au 31 »
  ///   comprend le 31 entier. Sans ses DEUX dates, le mois courant (le code
  ///   reste « personnalisée », le libellé dit les dates du mois).
  ///
  /// ⚠ Un intervalle INVERSÉ (« du 20 au 5 ») n'est pas refusé : le serveur ne
  /// le refuse pas (`Periode::personnalisee` ne compare pas les bornes, et
  /// `Accueil` ne valide ni `$du` ni `$au`). Sa durée est alors NÉGATIVE
  /// (`nombreJours()` vaut -14), et chaque indicateur se calcule comme au
  /// serveur sur cette fenêtre vide. Incohérence du SERVEUR, répliquée et notée
  /// (D297), jamais corrigée ici seul.
  factory FenetreTableauDeBord.resoudre(
    SelectionPeriode selection,
    DateTime maintenant,
  ) {
    final jour = DateTime(maintenant.year, maintenant.month, maintenant.day);
    final debutMois = DateTime(jour.year, jour.month, 1);
    final mois = FenetreTableauDeBord._(
      debut: debutMois,
      finExclue: DateTime(jour.year, jour.month + 1, 1),
    );

    switch (selection.periode) {
      case PeriodeTableauDeBord.aujourdHui:
        return FenetreTableauDeBord._(
          debut: jour,
          finExclue: DateTime(jour.year, jour.month, jour.day + 1),
        );
      case PeriodeTableauDeBord.semaine:
        // `DateTime.weekday` : lundi = 1, dimanche = 7.
        final lundi = DateTime(
          jour.year,
          jour.month,
          jour.day - (jour.weekday - DateTime.monday),
        );
        return FenetreTableauDeBord._(
          debut: lundi,
          finExclue: DateTime(lundi.year, lundi.month, lundi.day + 7),
        );
      case PeriodeTableauDeBord.mois:
        return mois;
      case PeriodeTableauDeBord.trimestre:
        final debut = DateTime(jour.year, _premierMoisDuTrimestre(jour.month));
        return FenetreTableauDeBord._(
          debut: debut,
          finExclue: DateTime(debut.year, debut.month + 3),
        );
      case PeriodeTableauDeBord.semestre:
        final debut = DateTime(jour.year, jour.month <= 6 ? 1 : 7);
        return FenetreTableauDeBord._(
          debut: debut,
          finExclue: DateTime(debut.year, debut.month + 6),
        );
      case PeriodeTableauDeBord.annee:
        return FenetreTableauDeBord._(
          debut: DateTime(jour.year),
          finExclue: DateTime(jour.year + 1),
        );
      case PeriodeTableauDeBord.personnalisee:
        final du = selection.du;
        final au = selection.au;
        if (du == null || au == null) return mois;
        return FenetreTableauDeBord._(
          debut: DateTime(du.year, du.month, du.day),
          finExclue: DateTime(au.year, au.month, au.day + 1),
        );
    }
  }

  static int _premierMoisDuTrimestre(int mois) => ((mois - 1) ~/ 3) * 3 + 1;

  final DateTime debut;

  /// Le premier instant EXCLU.
  final DateTime finExclue;

  /// Nombre de jours entiers couverts — base du calcul de nuitées.
  int get nombreJours => DateTime.utc(
    finExclue.year,
    finExclue.month,
    finExclue.day,
  ).difference(DateTime.utc(debut.year, debut.month, debut.day)).inDays;

  /// La période immédiatement antérieure, de MÊME durée (EF-M11-03) :
  /// « ce trimestre » précédent n'a pas la durée d'un autre trimestre, et le
  /// décalage garde deux fenêtres strictement comparables.
  FenetreTableauDeBord get precedente {
    final jours = nombreJours;
    return FenetreTableauDeBord._(
      debut: DateTime(debut.year, debut.month, debut.day - jours),
      finExclue: debut,
    );
  }

  /// « Du 11/09/2026 au 10/10/2026 » — le dernier jour INCLUS, car « du 1er au
  /// 31 exclu » ne se dit pas sur un document. Même gabarit que
  /// `lang/fr/tableaux_de_bord.php` (`periode.du_au`).
  String get libelle {
    final dernier = DateTime(
      finExclue.year,
      finExclue.month,
      finExclue.day - 1,
    );
    return 'Du ${_jour(debut)} au ${_jour(dernier)}';
  }

  /// `whereBetween(debut, fin)` du serveur : les DEUX bornes sont incluses,
  /// alors que la fenêtre est semi-ouverte. L'instant exactement égal à
  /// [finExclue] est donc compté ici ET dans la période suivante — une
  /// particularité du serveur, reproduite pour que les deux postes disent la
  /// même chose (elle ne mord que sur un horodatage à la seconde près de
  /// minuit).
  bool contientComme(DateTime instant) =>
      !instant.isBefore(debut) && !instant.isAfter(finExclue);

  /// Égalité PAR VALEUR : la fenêtre sert de clé à un fournisseur `family`.
  /// Sans elle, chaque lecture d'écran créerait une clé neuve — donc un
  /// fournisseur neuf, jamais chargé, et une lecture au clic qui rendrait
  /// toujours « pas encore de valeur ».
  @override
  bool operator ==(Object other) =>
      other is FenetreTableauDeBord &&
      other.debut == debut &&
      other.finExclue == finExclue;

  @override
  int get hashCode => Object.hash(debut, finExclue);

  static String _jour(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';
}
