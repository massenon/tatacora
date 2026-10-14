// Vue Blade maîtresse (PA-183) : pwa/livewire/accueil.blade.php
import 'package:flutter/painting.dart';

import '../../../../core/theme/app_colors.dart';

/// Les TRACÉS SVG de la « Vue d'exploitation », copiés de la vue d'accueil
/// caractère pour caractère (12/10/2026, lot 2 de `INSTRUCTION.txt`) et
/// dessinés par `IconeTrace` (`core/navigation/trace_svg.dart`), comme ceux de
/// la coquille (lot 1). Un test relit la vue et exige que chaque chaîne y
/// figure telle quelle (`vue_exploitation_test.dart`) : une icône Material « de
/// même sens » serait un autre dessin.
///
/// ⚠ Le titre « Tableau de bord » N'A PAS d'icône dans la vue : son `<h1>`
/// (l.246) est un texte seul, et le relevé du navigateur le place au même `x`
/// que le sous-titre (296 px). `INSTRUCTION.txt` §2 demande une icône « grille
/// / tableau » avant le titre : la vue gagne — l'icône Material que portait
/// l'écran (`Icons.insights_outlined`) est retirée, pas remplacée.
abstract final class TracesAccueil {
  /// Le bouton « Actualiser » (l.290).
  static const String actualiser =
      '<path stroke-linecap="round" stroke-linejoin="round" d="M23 4v6h-6M1 20v-6h6"/>'
      '<path stroke-linecap="round" stroke-linejoin="round" d="M3.51 9a9 9 0 0114.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0020.49 15"/>';

  /// Le document des boutons « Exporter » (l.301) et « Générer un rapport »
  /// (l.141) : le même tracé.
  static const String document =
      '<path stroke-linecap="round" stroke-linejoin="round" d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8z"/>'
      '<path stroke-linecap="round" stroke-linejoin="round" d="M14 2v6h6"/>';

  /// Le triangle d'alerte — accès rapide « Stocks critiques » (l.140) et
  /// bandeau « Alertes critiques de stock » (l.568) : le même tracé.
  static const String alerte =
      '<path stroke-linecap="round" stroke-linejoin="round" d="M12 9v4m0 4h.01M10.29 3.86L1.82 18a2 2 0 001.71 3h16.94a2 2 0 001.71-3L13.71 3.86a2 2 0 00-3.42 0z"/>';

  /// `$iconesAccesRapide` (l.137-143).
  static const String reservation =
      '<path stroke-linecap="round" d="M12 5v14M5 12h14"/>';
  static const String client =
      '<circle cx="9" cy="7" r="4"/>'
      '<path stroke-linecap="round" stroke-linejoin="round" d="M17 21v-2a4 4 0 00-4-4H5a4 4 0 00-4 4v2M20 8v6M23 11h-6"/>';
  static const String depense =
      '<circle cx="9" cy="21" r="1"/><circle cx="20" cy="21" r="1"/>'
      '<path stroke-linecap="round" stroke-linejoin="round" d="M1 1h4l2.68 13.39a2 2 0 002 1.61h9.72a2 2 0 002-1.61L23 6H6"/>';

  /// `$iconesKpi` (l.150-159), par clé d'indicateur du service.
  static const String chiffreAffaires =
      '<path stroke-linecap="round" stroke-linejoin="round" d="M23 6l-9.5 9.5-5-5L1 18"/>'
      '<path stroke-linecap="round" stroke-linejoin="round" d="M17 6h6v6"/>';
  static const String occupation =
      '<path stroke-linecap="round" stroke-linejoin="round" d="M2 4v16M2 8h18a2 2 0 012 2v10M2 17h20"/>';
  static const String tresorerie =
      '<rect x="2" y="7" width="20" height="14" rx="2"/>'
      '<path stroke-linecap="round" stroke-linejoin="round" d="M16 3H8v4h8V3z"/>';
  static const String depenses =
      '<path stroke-linecap="round" stroke-linejoin="round" d="M12 2v20M17 5H9.5a3.5 3.5 0 000 7h5a3.5 3.5 0 010 7H6"/>';
  static const String attente =
      '<rect x="3" y="4" width="18" height="18" rx="2"/>'
      '<path stroke-linecap="round" stroke-linejoin="round" d="M16 2v4M8 2v4M3 10h18"/>';
  static const String facture =
      '<path stroke-linecap="round" stroke-linejoin="round" d="M6 2h9l5 5v13a2 2 0 01-2 2H6a2 2 0 01-2-2V4a2 2 0 012-2z"/>';
  static const String stock =
      '<path stroke-linecap="round" stroke-linejoin="round" d="M21 8l-9-5-9 5 9 5 9-5zM3 8v8l9 5 9-5V8"/>';
  static const String employes =
      '<rect x="2" y="4" width="20" height="16" rx="2"/>'
      '<circle cx="9" cy="10" r="2"/>'
      '<path stroke-linecap="round" stroke-linejoin="round" d="M15 8h4M15 12h4M6 16h6"/>';

  /// Le repli de la vue pour une clé inconnue (partiel des cartes, l.56) :
  /// un cercle, en ardoise — « la couleur de "je ne sais pas" ».
  static const String inconnu = '<circle cx="12" cy="12" r="9"/>';
}

/// L'icône d'une carte d'indicateur : tracé, couleur du trait, fond de la
/// pastille — `$iconesKpi[$cle]` de la vue, dans l'ordre du service.
typedef IconeIndicateur = ({String trace, Color couleur, Color fond});

/// `$iconesKpi` (l.150-159). Les couleurs sont les jetons de la feuille
/// (`var(--succes)`, `var(--navy)`…) et les fonds les teintes de la vue
/// (`#E8F5E9`, `#E8EEFD`, `#FDF3E0`, `#FDECEC`), déjà nommés au thème.
const Map<String, IconeIndicateur> iconesIndicateurs = {
  'chiffre_affaires_encaisse': (
    trace: TracesAccueil.chiffreAffaires,
    couleur: AppColors.succes,
    fond: AppColors.badgeVertFond,
  ),
  'taux_occupation': (
    trace: TracesAccueil.occupation,
    couleur: AppColors.navy,
    fond: AppColors.badgeBleuFond,
  ),
  'tresorerie_caisse': (
    trace: TracesAccueil.tresorerie,
    couleur: AppColors.gold,
    fond: AppColors.reserveGoldFond,
  ),
  'depenses_cumulees': (
    trace: TracesAccueil.depenses,
    couleur: AppColors.erreur,
    fond: AppColors.badgeRougeFond,
  ),
  'reservations_en_attente': (
    trace: TracesAccueil.attente,
    couleur: AppColors.gold,
    fond: AppColors.reserveGoldFond,
  ),
  'factures_impayees': (
    trace: TracesAccueil.facture,
    couleur: AppColors.erreur,
    fond: AppColors.badgeRougeFond,
  ),
  'valeur_stock': (
    // `#1D4ED8` — le bleu de la feuille (`--info`).
    trace: TracesAccueil.stock,
    couleur: AppColors.info,
    fond: AppColors.badgeBleuFond,
  ),
  'employes_actifs': (
    trace: TracesAccueil.employes,
    couleur: AppColors.succes,
    fond: AppColors.badgeVertFond,
  ),
};

/// Le repli d'une clé inconnue : `['#64748B', '#F1F5F9', cercle]`.
const IconeIndicateur iconeIndicateurInconnu = (
  trace: TracesAccueil.inconnu,
  couleur: Ardoise.c500,
  fond: Ardoise.c100,
);
