// Vue Blade maîtresse (PA-183) : pwa/pos/historique-ventes.blade.php
import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Typographie — `04_UIUX_DESIGN_SYSTEM.md` §2.2.
///
/// **Deuxième révision du 15/08/2026 appliquée**, et elle seule. Le document
/// porte deux révisions successives à la hausse ; les appliquer en cascade
/// donnerait des tailles doublement majorées. Seule la seconde fait foi.
///
/// Conséquence assumée de cette révision : « Corps de texte » et « Texte
/// secondaire » partagent désormais **la même taille de 15 px**. Leur
/// hiérarchie repose sur le poids et la couleur, plus sur la taille. Ce n'est
/// pas un oubli — le document le documente explicitement comme une convergence
/// voulue.
abstract final class AppTextStyles {
  /// Inter, conservée du prototype approuvé. Revenir à Roboto introduirait une
  /// divergence visuelle avec ce que le client a déjà validé.
  static const String police = 'Inter';

  /// Montants et codes — monospace, pour que les colonnes de chiffres
  /// s'alignent. Une police proportionnelle rend une colonne de montants
  /// illisible dès la troisième ligne.
  static const String policeMonospace = 'JetBrainsMono';

  /// Style dédié aux montants — `04_UIUX_DESIGN_SYSTEM.md` §2.2.
  static const TextStyle montant = TextStyle(
    fontFamily: policeMonospace,
    color: AppColors.gold,
    fontSize: 15,
    fontWeight: FontWeight.w600,
  );

  /// `tracking-wide` de Tailwind — **0.025em**, donc proportionnel à la taille
  /// de police et non un nombre de pixels.
  ///
  /// Le maître le pose sur ses en-têtes de colonne et ses libellés
  /// d'indicateur, toujours avec `uppercase` : `text-[11px] uppercase
  /// tracking-wide` (`carte-module.js` l.51 et l.383). Un interlettrage écrit
  /// en pixels serait juste à 11 px et faux partout ailleurs — c'est une
  /// valeur relative, elle se **multiplie** par la taille.
  static const double suiviLarge = 0.025;

  /// `tracking-wider` de Tailwind — **0.05em** (relu dans le bundle vendorisé
  /// de la vue, `wider:"0.05em"`). Les titres de groupe de la barre latérale
  /// (`text-[10.5px] … tracking-wider`) : 0,525 px à 10,5 px.
  ///
  /// ⚠ La barre latérale écrivait `letterSpacing: 0.8` en dur jusqu'au
  /// 12/10/2026 — ni 0.05em ni 0.1em (`tracking-widest`) : chaque titre de
  /// groupe était plus large que celui de la vue de 0,275 px par caractère,
  /// 6 px sur « RÉSERVATIONS & SÉJOURS » (mesuré au relevé du châssis).
  static const double suiviPlusLarge = 0.05;

  /// `tracking-widest` de Tailwind — **0.1em**. Le sous-titre de marque de
  /// l'écran de connexion (« TATACORA AFRIQUE », `text-[11px] … tracking-widest`).
  /// JETON AJOUTÉ le 29/10/2026.
  static const double suiviTresLarge = 0.1;

  /// `tracking-[0.2em]` — le slogan de l'écran de connexion (valeur entre
  /// crochets de la vue, pas un palier Tailwind). JETON AJOUTÉ le 29/10/2026.
  static const double suiviSlogan = 0.2;

  /// `tracking-tight` de Tailwind — **−0.025em**. La marque de la barre
  /// supérieure (`text-base font-bold tracking-tight`).
  static const double suiviSerre = -0.025;

  /// `TextTheme` complet, adossé au mapping web → Flutter du §2.2.
  /// ⚠ `letterSpacing: 0` PARTOUT (Phase 1D, 08/10/2026). Sans lui, le thème
  /// Material 3 injecte son interlettrage par défaut (0,25 px sur le corps de
  /// texte, 0,1 sur les libellés) : chaque texte était plus LARGE que celui du
  /// navigateur de 0,25 px par caractère — 4 px sur « Identité & Légal »,
  /// 2,5 px sur « Paramètres » —, et tous les éléments suivants dans une
  /// ligne glissaient d'autant. Tailwind n'a aucun interlettrage par défaut
  /// (`tracking-normal`) ; seuls les titres de section en posent un, avec
  /// `tracking-wide` / `tracking-wider`, écrit à l'endroit où il sert.
  static const TextTheme theme = TextTheme(
    // H1 — titre de module.
    headlineSmall: TextStyle(
      fontFamily: police,
      letterSpacing: 0,
      fontSize: 22,
      fontWeight: FontWeight.bold,
      color: AppColors.navy,
    ),
    // H2 — section.
    titleLarge: TextStyle(
      fontFamily: police,
      letterSpacing: 0,
      fontSize: 18,
      fontWeight: FontWeight.bold,
      color: AppColors.navy,
    ),
    // H3 — carte.
    titleMedium: TextStyle(
      fontFamily: police,
      letterSpacing: 0,
      fontSize: 15,
      fontWeight: FontWeight.bold,
      color: AppColors.anthracite,
    ),
    // Corps de texte.
    bodyMedium: TextStyle(
      fontFamily: police,
      letterSpacing: 0,
      fontSize: 15,
      color: AppColors.anthracite,
    ),
    // Libellé de formulaire.
    labelLarge: TextStyle(
      fontFamily: police,
      letterSpacing: 0,
      fontSize: 15,
      fontWeight: FontWeight.w500,
      color: AppColors.anthracite,
    ),
    // Texte secondaire — même taille que le corps, distingué par la couleur.
    bodySmall: TextStyle(
      fontFamily: police,
      letterSpacing: 0,
      fontSize: 15,
      color: AppColors.neutre500,
    ),
    // Texte tertiaire, notes de bas de page.
    labelMedium: TextStyle(
      fontFamily: police,
      letterSpacing: 0,
      fontSize: 13,
      color: AppColors.neutre500,
    ),
    // Badges et codes très compacts.
    labelSmall: TextStyle(
      fontFamily: police,
      letterSpacing: 0,
      fontSize: 12,
      fontWeight: FontWeight.w600,
    ),
  );
}

/// L'échelle typographique du maître, telle qu'elle est **réellement employée**.
///
/// Relevée par comptage sur les 49 pages de `prototype_v2/pages/`, et non
/// déduite de l'échelle par défaut de Tailwind — `DOCTRINE_PORTAGE_FIDELE_
/// FLUTTER.md` §3.1 : « mesurer, ne pas supposer ».
///
/// | Taille | Emplois | Classe du maître |
/// |---|---|---|
/// | 13 px | **393** | `text-[13px]` — la plus fréquente de tout le maître |
/// | 15 px | 305 | `text-[15px]` |
/// | 12 px | 198 | `text-[12px]` |
/// | 14 px | 176 | `text-sm` |
/// | 11 px | 81 | `text-[11px]` |
/// | 18 px | 53 | `text-lg` |
/// | 20 px | 48 | `text-xl` |
/// | 16 px | 25 | `text-base` |
/// | 10 px | 23 | `text-[10px]` |
/// | 30 px | 2 | `text-3xl` — le titre de la colonne image de connexion |
///
/// **Ce que ce tableau apprend, et qui ne se devine pas :** le maître n'emploie
/// presque pas l'échelle nommée de Tailwind. Neuf de ses dix tailles les plus
/// courantes sont des valeurs *arbitraires* entre crochets. Un portage qui
/// aurait traduit `text-sm` par « petit » et `text-base` par « normal » se
/// serait trompé sur **plus de 900 occurrences** — parce qu'il aurait supposé
/// une échelle au lieu de lire celle qui est là.
///
/// Aucun widget ne doit écrire `fontSize: 15`. Il écrit [t15].
abstract final class Tailles {
  /// Mentions légales, pieds de tableau, unités.
  static const double t10 = 10;

  /// Badges, pastilles de statut, codes courts.
  static const double t11 = 11;

  /// Intitulés de colonne en capitales, libellés de séparateur.
  static const double t12 = 12;

  /// **La taille dominante du maître** — texte courant des tableaux, des
  /// cartes et des pieds de page. 393 emplois de `text-[13px]`.
  ///
  /// ⚠ C'est la taille **déclarée**. Dans un `<main>`, `app.css` la remappe à
  /// 12,5 px — voir [TaillesContenu.t13].
  static const double t13 = 13;

  /// `text-sm` — champs de formulaire, boutons.
  static const double t14 = 14;

  /// Corps de texte des formulaires, étiquettes de champ, accroches.
  static const double t15 = 15;

  /// `text-base`.
  static const double t16 = 16;

  /// La valeur d'une carte d'indicateur du journal des ventes —
  /// `text-[17px]` (`prototype_v2/pages/historique-ventes.html` l.176).
  ///
  /// Valeur **entre crochets**, mesurée : elle ne vient d'aucune échelle
  /// Tailwind, et ce n'est ni `text-base` (16) ni `text-lg` (18). La supposer
  /// aurait décalé toute la bande d'indicateurs de cette page.
  static const double t17 = 17;

  /// `text-lg` — titres de section.
  static const double t18 = 18;

  /// `text-xl` — titres de page et de modale.
  static const double t20 = 20;

  /// `text-[28px]` — la marque « LogiReStock » et le titre « Bienvenue ! » de
  /// l'écran de connexion (sa vue Blade, refonte du
  /// 29/10/2026). JETON AJOUTÉ pour cet écran : aucun palier existant ne
  /// valait 28, et le poste ne doit pas l'écrire en dur.
  static const double t28 = 28;

  /// `text-3xl` — le seul très grand titre du maître, en colonne image.
  static const double t30 = 30;

  /// `leading-tight` de Tailwind, employé sur le titre 30 px.
  static const double interligneSerre = 1.25;

  /// `leading-none` de Tailwind — 1. Les boutons « − » / « + » et la croix de
  /// retrait d'une ligne de panier (`heberges.blade.php` l.210-219).
  static const double interligneAucun = 1;

  /// `leading-snug` de Tailwind — 1,375. Employé sur le libellé d'un état du
  /// catalogue (`m14-etats-studio.js` l.88).
  ///
  /// **Les interlignes ne sont PAS remappés** par `app.css`, qui ne redéfinit
  /// que `font-size` (l.175-186) : ce palier vaut donc la même chose dans un
  /// `<main>` et hors de lui, et il n'a pas de jumeau dans [TaillesContenu].
  /// Lui en donner un ferait croire à une seconde valeur qui n'existe pas.
  static const double interligneSnug = 1.375;

  /// `text-xs` HORS `<main>` — Tailwind lui donne `line-height: 1rem`, soit
  /// 16 px pour 12 : le rapport 4/3. Les boutons de la barre supérieure
  /// (« Caisse fermée », « Vente ») et les lignes du menu de compte. Dans un
  /// `<main>`, c'est [TaillesContenu.interligneXs] qui vaut.
  static const double interligneXsHorsMain = 16 / 12;

  /// `text-sm` HORS `<main>` — Tailwind lui donne `line-height: 1.25rem`, soit
  /// 20 px pour 14. Le titre « Accès rapides » du panneau latéral (partiel
  /// `acces-rapide`, inclus après `</main>`).
  static const double interligneSmHorsMain = 20 / 14;

  // ------------------------------------------------------------------------
  // Les paliers que le remappage de `app.css` nomme et que cette échelle
  // ignorait. Ils sont **déclarés** par le maître, donc atteignables hors
  // `main` (barre supérieure, modales, connexion, démarrage).
  // ------------------------------------------------------------------------

  /// `text-[8px]` — app.css l.176.
  static const double t8 = 8;

  /// `text-[9px]` — app.css l.177.
  static const double t9 = 9;

  /// `text-[10.5px]` — app.css l.179. Valeur **fractionnaire** : ni 10 ni 11.
  static const double t10_5 = 10.5;

  /// `text-[11.5px]` — app.css l.181.
  static const double t11_5 = 11.5;

  /// `text-[12.5px]` — app.css l.183.
  static const double t12_5 = 12.5;

  /// `text-[19px]` — un seul emploi dans tout le maître, et **aucun remappage
  /// ne le couvre** : il rend donc 19 px, y compris dans un `<main>`.
  ///
  /// Relevé le 26/08/2026 par une garde qui confronte l'échelle déclarée aux
  /// classes réellement écrites. Il n'avait aucun jeton : le porter aurait
  /// demandé une valeur en dur, ou l'aurait fait glisser vers `t18` ou `t20`
  /// — un arrondi invisible, sur le seul écran qui l'emploie.
  static const double t19 = 19;

  /// `#shell-sidebar .lien-sidebar { font-size: 14px }` — app.css l.199.
  ///
  /// Le maître le commente lui-même : « le menu revient à 14 px — sa taille
  /// d'origine. Un menu plus gros que le contenu qu'il sert inverse la
  /// hiérarchie de lecture. » La barre latérale est donc **hors** du remappage
  /// de [TaillesContenu], délibérément.
  static const double lienSidebar = 14;
}

/// L'échelle typographique **EFFECTIVE** à l'intérieur de `<main>`.
///
/// ## Le piège que la doctrine annonce, réalisé
///
/// `DOCTRINE_PORTAGE_FIDELE_FLUTTER.md` §3.1 prévient : « `.text-xs` ne vaut
/// pas forcément 12 px : une surcharge locale peut le porter à 13,6 px. On
/// ouvre le HTML, on lit la règle effective, on la reporte. »
///
/// C'est exactement ce que fait `app.css` l.166-197. Le maître y **remappe
/// chaque palier** pour le contenu de page, et son commentaire dit pourquoi :
/// « les pages utilisent des tailles ABSOLUES (`text-[13px]`), qui ne suivent
/// pas le `font-size` d'un parent : réduire le corps par héritage n'aurait eu
/// aucun effet. Chaque palier est donc remappé explicitement. »
///
/// **La conséquence est contre-intuitive et se vérifie dans un navigateur :**
/// dans une page du maître, `class="text-[13px]"` s'affiche à **12,5 px**.
/// La classe dit 13, le pixel vaut 12,5.
///
/// ## Portée : 48 pages sur 50
///
/// Mesuré, pas supposé — `grep -L '<main'` sur `prototype_v2/pages/` ne rend
/// que `login.html` et `splash.html`. Toutes les autres pages, c'est-à-dire
/// tous les écrans de module, sont dans la portée du remappage. La barre
/// supérieure et les modales en sont exclues par le maître lui-même
/// (« la portée reste limitée à `main` »).
///
/// ## L'arbitrage, rendu le 26/08/2026
///
/// Il l'était : « les écrans livrés emploient aujourd'hui [Tailles] ». Ce
/// n'est plus vrai, et laisser la phrase serait la quatrième occurrence du
/// motif de refus périmé de ce dépôt (PA-144). **Le contenu de page emploie
/// désormais [TaillesContenu]** — le maître fait foi sur ce qui *se voit*
/// (Article 0), et ce qui se voit est le pixel rendu, pas le nom de la classe.
///
/// Ce qui reste sur [Tailles], parce que le maître les met **hors** de la
/// portée du remappage, et c'est mesuré et non supposé :
///
/// - le **châssis** — `#shell-topbar`, `#shell-banniere`, `#shell-sidebar`
///   sont des frères de `<main>`, et la barre latérale est en outre ramenée à
///   14 px par une règle propre (`app.css` l.196) ;
/// - la **connexion** et le **démarrage** — seules pages du maître sans
///   `<main>`, vérifié par `grep -L` sur les 50 ;
/// - les **modales** — `app.css` l.172 l'écrit, et le DOM le confirme :
///   les 52 conteneurs de modales des 50 pages sont **tous** hors `</main>`.
///
/// `test/core/theme/echelle_contenu_test.dart` tient cette frontière, et il la
/// tient en relisant le maître, pas en recopiant cette liste.
///
/// ## Ce qui n'est TOUJOURS pas tranché, et qui est plus large
///
/// L'essentiel de la typographie de contenu ne passe par aucune de ces deux
/// échelles : elle vient de [AppTextStyles.theme], dérivé de
/// `04_UIUX_DESIGN_SYSTEM.md` §2.2 — **un document, pas le maître**. La
/// question « déclarée ou effective » ne s'y pose même pas, parce que ses
/// emplacements n'ont jamais été rattachés à une classe du maître. Mesuré :
/// 45 des 50 `<h1>` du maître portent `text-lg lg:text-xl`, soit 18,5 px
/// effectifs ; `headlineSmall` vaut 22. L'écart n'est ni un demi-pixel ni un
/// arbitrage d'échelle : c'est une **ré-extraction** au sens de l'Article 2,
/// et elle est remontée au rapport plutôt que tranchée seule (Article 8).
abstract final class TaillesContenu {
  /// `text-[8px]` → 8 px (inchangé).
  static const double t8 = 8;

  /// `text-[9px]` → 9 px (inchangé).
  static const double t9 = 9;

  /// `text-[10px]` → 10 px (inchangé).
  static const double t10 = 10;

  /// `text-[10.5px]` → 10.5 px (inchangé).
  static const double t10_5 = 10.5;

  /// `text-[11px]` → **10.5 px**.
  static const double t11 = 10.5;

  /// `text-[11.5px]` → **11 px**.
  static const double t11_5 = 11;

  /// `text-[12px]` → **11.5 px**.
  static const double t12 = 11.5;

  /// `text-[12.5px]` → **12 px**.
  static const double t12_5 = 12;

  /// `text-[13px]` → **12.5 px**. La classe la plus employée du maître
  /// (393 emplois) ne rend pas la taille qu'elle nomme.
  static const double t13 = 12.5;

  /// `text-[14px]` → **13.5 px**.
  static const double t14 = 13.5;

  /// `text-[15px]` → **14 px**.
  static const double t15 = 14;

  /// `text-[17px]` → **16 px**.
  static const double t17 = 16;

  /// `text-[18px]` → **18 px (inchangé)** : `app.css` ne remappe pas ce
  /// palier (la liste de `main .text-[…]` s'arrête à `[17px]`). Mesuré sur
  /// la valeur d'un indicateur de la dépense courante : 22 px de boîte, soit
  /// la hauteur de contenu d'Inter à 18 px.
  static const double t18 = 18;

  /// `text-[19px]` → **19 px (inchangé)** : `app.css` ne remappe pas ce
  /// palier non plus. Un seul emploi dans tout le maître : le total du panier
  /// de séjour (`pos/heberges.blade.php` l.238), à l'intérieur de `<main>`.
  static const double t19 = 19;

  // --------------------------------------------- L'échelle nommée, remappée
  //
  // Elle porte en plus un `line-height`, que la variante entre crochets n'a
  // pas. Les deux ne sont donc pas interchangeables même à taille égale.

  /// `text-xs` → 11.5 px, interligne 1.45.
  static const double xs = 11.5;
  static const double interligneXs = 1.45;

  /// `text-sm` → 13.5 px, interligne 1.5.
  static const double sm = 13.5;
  static const double interligneSm = 1.5;

  /// `text-base` → 15 px, interligne 1.5.
  static const double base = 15;
  static const double interligneBase = 1.5;

  /// `text-lg` → 17 px, interligne 1.4.
  static const double lg = 17;
  static const double interligneLg = 1.4;

  /// `text-xl` → 18.5 px, interligne 1.35.
  static const double xl = 18.5;
  static const double interligneXl = 1.35;

  /// `text-2xl` → 22 px, interligne 1.3.
  static const double xxl = 22;
  static const double interligneXxl = 1.3;
}
