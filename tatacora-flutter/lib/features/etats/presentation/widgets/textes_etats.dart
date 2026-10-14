import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';

/// Les styles de `m14-etats-studio.html`, **mesurés dans le maître**.
///
/// Chaque entrée cite la classe qui la produit et sa ligne. Une taille déduite
/// d'un nom de classe est une erreur en attente
/// (`DIRECTIVE_CONFORMITE_100.md` Article 2).
///
/// ## Échelle EFFECTIVE, sans exception ici
///
/// Toute la page vit dans `<main>` — le studio n'a **aucune modale**, ce que
/// le comparateur confirme (`m14-etats-studio.html` : 0 modale). `app.css`
/// l.175-193 y remappe l'échelle : `text-[13px]` rend 12,5 px. D'où
/// [TaillesContenu] partout dans ce fichier, et le classement de M14 du côté
/// « contenu de page » dans `echelle_contenu_test.dart`.
///
/// Les styles déjà portés par `TextesRestaurant` ne sont pas recopiés : ce
/// fichier ne porte que ceux que le studio est seul à employer.
abstract final class TextesEtats {
  /// `text-[15px] font-bold` sur `var(--navy)` — le titre de la barre d'outils
  /// (l.51) et le titre de l'aperçu (`m14-etats-studio.js` l.190).
  static const TextStyle titreBarre = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: TaillesContenu.t15,
    height: AppLayout.interligneContenu,
    fontWeight: FontWeight.bold,
    color: AppColors.navy,
  );

  /// `text-[15px] font-semibold` sur `var(--navy)` — l'accroche de l'écran
  /// d'accueil de l'aperçu (`m14-etats-studio.js` l.132).
  static const TextStyle accrocheAccueil = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: TaillesContenu.t15,
    height: AppLayout.interligneContenu,
    fontWeight: FontWeight.w600,
    color: AppColors.navy,
  );

  /// `text-[10px] font-bold tracking-wider text-slate-400` — l'en-tête de
  /// groupe du catalogue, `M6 — STOCKS` (`m14-etats-studio.js` l.79-80).
  static const TextStyle enTeteGroupe = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: TaillesContenu.t10,
    height: AppLayout.interligneContenu,
    fontWeight: FontWeight.bold,
    letterSpacing: TaillesContenu.t10 * AppTextStyles.suiviLarge,
    color: Ardoise.c400,
  );

  /// `text-[13px] font-semibold leading-snug` — le libellé d'un état
  /// (`m14-etats-studio.js` l.88). La couleur varie : `text-white` quand
  /// l'entrée est sélectionnée (`aria-selected` — `m14-etats-studio.html`
  /// l.22), sinon l'héritage.
  static const TextStyle libelleEtat = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: TaillesContenu.t13,
    height: Tailles.interligneSnug,
    fontWeight: FontWeight.w600,
    color: Ardoise.c800,
  );

  /// La même entrée **sélectionnée** — `aria-selected="true"` pose
  /// `background: var(--navy); color: #fff` (`m14-etats-studio.html` l.21-23).
  static const TextStyle libelleEtatActif = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: TaillesContenu.t13,
    height: Tailles.interligneSnug,
    fontWeight: FontWeight.w600,
    color: AppColors.neutre0,
  );

  /// `.item-desc` sur une entrée sélectionnée : `rgba(255,255,255,.6)`
  /// (l.24). La mention discrète de `TextesRestaurant` sert au cas non
  /// sélectionné ; celle-ci n'existe que pour l'entrée active.
  static TextStyle get mentionEtatActif => const TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: TaillesContenu.t11,
    height: Tailles.interligneSerre,
  ).copyWith(color: AppColors.neutre0.withValues(alpha: opaciteMentionActive));

  /// `rgba(255,255,255,.6)` — l'opacité exacte du maître (l.24).
  static const double opaciteMentionActive = 0.6;

  /// `text-[9px] px-1.5 py-0.5 rounded bg-slate-100 text-slate-500` — la
  /// pastille du module source, à droite du libellé (l.89).
  static const TextStyle badgeModule = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: TaillesContenu.t9,
    height: AppLayout.interligneContenu,
    color: Ardoise.c500,
  );

  /// `text-[11px] px-2 py-1` — une puce de filtre de module (l.51-55 du JS).
  static const TextStyle puceModule = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: TaillesContenu.t11,
    height: AppLayout.interligneContenu,
    fontWeight: FontWeight.w600,
  );

  /// `text-[12px] text-slate-400` — la note de bas de l'accueil, celle qui
  /// rappelle d'où viennent les droits (`m14-etats-studio.js` l.139).
  static const TextStyle noteAccueil = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: TaillesContenu.t12,
    height: AppLayout.interligneContenu,
    color: Ardoise.c400,
  );

  /// `text-[12px] text-slate-500` — l'étiquette « Période » de la barre
  /// d'outils (l.56) et la sous-ligne de l'en-tête d'aperçu (JS l.192).
  static const TextStyle etiquetteBarre = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: TaillesContenu.t12,
    height: AppLayout.interligneContenu,
    color: Ardoise.c500,
  );

  /// `text-[13px]` — un bouton de la barre d'outils (l.66-68).
  static const TextStyle boutonBarre = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: TaillesContenu.t13,
    height: AppLayout.interligneContenu,
    color: Ardoise.c700,
  );

  /// Le même bouton, en variante pleine : `bg-[var(--navy)] text-white
  /// font-semibold` (l.68).
  static const TextStyle boutonBarrePlein = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: TaillesContenu.t13,
    height: AppLayout.interligneContenu,
    fontWeight: FontWeight.w600,
    color: AppColors.neutre0,
  );

  // ---------------------------------------------------------------------
  // L'aperçu (`studio.blade.php` l.132-203), repris sur la VUE BLADE.
  // ---------------------------------------------------------------------

  /// `text-[10px] uppercase tracking-wide text-slate-400 font-semibold` — le
  /// libellé d'un indicateur de l'en-tête (l.152).
  static const TextStyle indicateurLibelle = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: TaillesContenu.t10,
    height: AppLayout.interligneContenu,
    fontWeight: FontWeight.w600,
    letterSpacing: TaillesContenu.t10 * AppTextStyles.suiviLarge,
    color: Ardoise.c400,
  );

  /// `text-[13px] font-bold` sur `var(--navy)` — la valeur d'un indicateur
  /// (l.153).
  static const TextStyle indicateurValeur = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: TaillesContenu.t13,
    height: AppLayout.interligneContenu,
    fontWeight: FontWeight.bold,
    color: AppColors.navy,
  );

  /// `text-[11px] uppercase tracking-wide text-white/90 font-semibold` — un
  /// `<th>` du tableau d'aperçu (l.171).
  static const TextStyle enteteApercu = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: TaillesContenu.t11,
    height: AppLayout.interligneContenu,
    fontWeight: FontWeight.w600,
    letterSpacing: TaillesContenu.t11 * AppTextStyles.suiviLarge,
    color: AppColors.blanc90,
  );

  /// `text-[12.5px]` — une cellule du tableau d'aperçu (`table ... text-[12.5px]
  /// apercu`, l.169), couleur du corps de page (`var(--texte)`).
  static const TextStyle celluleApercu = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: TaillesContenu.t12_5,
    height: AppLayout.interligneContenu,
    color: AppColors.anthracite,
  );

  /// `text-[13px] text-slate-400` — l'état vide (`p-10 text-center`, l.166).
  static const TextStyle videApercu = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: TaillesContenu.t13,
    height: AppLayout.interligneContenu,
    color: Ardoise.c400,
  );

  /// `text-slate-300` — la puce « · » entre la période, le module et le
  /// nombre de lignes (l.141-143).
  static const TextStyle separateurApercu = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: TaillesContenu.t12,
    height: AppLayout.interligneContenu,
    color: Ardoise.c300,
  );

  /// `bg-slate-50/40` — le fond des lignes impaires du tableau d'aperçu
  /// (`$index % 2`, l.178).
  static const double opaciteRayure = 0.4;

  static Color get fondRayure => Ardoise.c50.withValues(alpha: opaciteRayure);
}
