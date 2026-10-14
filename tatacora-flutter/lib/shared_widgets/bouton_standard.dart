/// Le BOUTON D'ACTION standard des écrans de contenu — demande du Product
/// Owner du 14/10/2026 : un seul bouton, aux mesures de la vue, pour toutes
/// les barres d'action (« + Véhicule », « Immobiliser », « + Contrat »,
/// « Exporter », « Importer », « Modèle »…).
///
/// ## Les mesures sont celles de la vue, pas de la consigne
///
/// La consigne du PO donnait « ~38-40 px / 16 / 13-14 medium / 6 » et disait
/// « la vue tranche ». La vue (barre d'actions des locations, des stocks et
/// des inventaires) écrit :
///
/// | Variante | Classes de la vue |
/// |---|---|
/// | [VarianteBouton.secondaire] | `text-[13px] px-3.5 py-2 rounded-lg border border-slate-300 bg-white` |
/// | [VarianteBouton.primaire] | `text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold` |
/// | [VarianteBouton.or] | `text-[13px] px-4 py-2 rounded-lg border border-[var(--gold)] text-[var(--gold)] font-semibold` |
/// | [VarianteBouton.contourRouge] | `text-[13px] px-4 py-2 rounded-lg border border-red-200 text-red-700` (« Tout retirer », Rôles & Permissions) |
/// | [VarianteBouton.erreur] | `text-[13px] px-4 py-2 rounded-lg text-white font-semibold` sur `var(--erreur)` (confirmation destructive) |
/// | [VarianteBouton.fantome] | sans fond ni bordure visibles, texte ardoise — « Annuler » d'une modale (ajout du PO, 14/10/2026, absent de la vue) |
///
/// Soit, dans `<main>` : police 12,5 px (`text-[13px]` remappé), interligne
/// 1,5, 8 px de marge verticale, rayon 8 px (`rounded-lg`), 14 ou 16 px de
/// marge horizontale — environ 37 px de haut, bordure comprise. Le texte du
/// bouton secondaire est de graisse NORMALE (la vue ne pose pas
/// `font-medium`).
///
/// ## Écart assumé : 40 px de haut, rayon 6 px (PO, 14/10/2026)
///
/// Décision du Product Owner du 14/10/2026 : TOUS les boutons standard
/// (« + Véhicule », « + Contrat », « Exporter »…) font **40 px** de haut,
/// bordure comprise ([AppLayout.hauteurBoutonStandard]), et ont un rayon de
/// **6 px** ([AppRadius.roundedMd]) — au lieu des ~37 px et 8 px
/// (`rounded-lg`) de la vue. La hauteur est FIXE : [compact] et
/// [margeVerticale] ne la changent plus, ils ne règlent que la police et le
/// remplissage intérieur ; le libellé est centré verticalement.
///
/// ## Une bordure sur TOUTES les variantes
///
/// Le bouton plein porte une bordure de sa propre couleur, invisible, pour
/// garder le même dessin que les variantes bordées — même raisonnement que
/// `BoutonEnteteCarte`.
///
/// Brique commune (`shared_widgets/`) : aucune valeur n'y est écrite en dur.
library;

import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_text_styles.dart';

/// Les habits d'un bouton d'action de la vue.
enum VarianteBouton { secondaire, primaire, or, contourRouge, erreur, fantome }

/// Le bouton d'action standard. [onPressed] nul = désactivé (grisé), jamais
/// inerte en silence : l'appelant qui n'a pas de geste à offrir le DIT.
class BoutonStandard extends StatelessWidget {
  const BoutonStandard({
    super.key,
    required this.libelle,
    required this.onPressed,
    this.variante = VarianteBouton.secondaire,
    this.cleLibelle,
    this.taillePolice = TaillesContenu.t13,
    this.compact = false,
    this.margeVerticale = AppSpacing.xs,
    this.margeHorizontale,
  });

  /// La marge horizontale quand la vue s'écarte de celle de la variante —
  /// « Annuler » d'un pied de modale est `px-4` (16 px) là où le secondaire
  /// des barres d'action est `px-3.5` (14 px). `null` : celle de la variante.
  final double? margeHorizontale;

  /// `py-2` (8 px) par défaut ; `py-1.5` (6 px, [AppSpacing.xxs]) pour les
  /// boutons de la carte des filtres des inventaires.
  final double margeVerticale;

  /// `text-[12px] px-3 py-2` sans `font-semibold` — les boutons de la barre de
  /// filtres des stocks et des inventaires (« Importer », « Modèle »,
  /// « Exporter »), plus petits que ceux d'en-tête dans la vue.
  final bool compact;

  /// `text-[13px]` : 12,5 px DANS `<main>` (remappé par `app.css`, défaut),
  /// 13 px HORS de `<main>` — une modale passe le palier 13 de `Tailles`.
  final double taillePolice;

  final String libelle;
  final VoidCallback? onPressed;
  final VarianteBouton variante;

  /// Une clé posée sur le TEXTE (les tests qui cherchent le libellé par clé).
  final Key? cleLibelle;

  @override
  Widget build(BuildContext context) {
    final (fond, bord, texte, poids, horizontal) = switch (variante) {
      VarianteBouton.secondaire => (
        AppColors.neutre0,
        Ardoise.c300,
        Ardoise.c800,
        FontWeight.w400,
        AppSpacing.smPlus,
      ),
      VarianteBouton.primaire => (
        AppColors.navy,
        AppColors.navy,
        AppColors.neutre0,
        FontWeight.w600,
        AppSpacing.md,
      ),
      VarianteBouton.or => (
        AppColors.neutre0,
        AppColors.gold,
        AppColors.gold,
        FontWeight.w600,
        AppSpacing.md,
      ),
      VarianteBouton.contourRouge => (
        AppColors.neutre0,
        PaletteMaitre.rouge200,
        PaletteMaitre.rouge700,
        FontWeight.w400,
        AppSpacing.md,
      ),
      VarianteBouton.erreur => (
        AppColors.erreur,
        AppColors.erreur,
        AppColors.neutre0,
        FontWeight.w600,
        AppSpacing.md,
      ),
      // Le bouton « fantôme » : ni fond ni bordure visibles, sur n'importe
      // quel fond — la même hauteur que les autres (bordure transparente).
      VarianteBouton.fantome => (
        Colors.transparent,
        Colors.transparent,
        Ardoise.c600,
        FontWeight.w400,
        AppSpacing.md,
      ),
    };
    final actif = onPressed != null;
    // PO, 14/10/2026 : rayon 6 px (`rounded-md`), pas le `rounded-lg` de la vue.
    final rayon = BorderRadius.circular(AppRadius.roundedMd);

    return Opacity(
      // `disabled:opacity-50` des boutons de la vue.
      opacity: actif ? 1 : OpacitesBouton.desactive,
      child: Material(
        color: fond,
        borderRadius: rayon,
        child: InkWell(
          onTap: onPressed,
          borderRadius: rayon,
          // `hover:bg-slate-50` / `hover:opacity-90` : un voile léger.
          hoverColor: Ardoise.c50.withValues(alpha: OpacitesBouton.survol),
          child: Container(
            // Hauteur FIXE de 40 px, bordure comprise (PO, 14/10/2026).
            height: AppLayout.hauteurBoutonStandard,
            padding: EdgeInsets.symmetric(
              horizontal:
                  margeHorizontale ?? (compact ? AppSpacing.sm : horizontal),
              vertical: margeVerticale,
            ),
            decoration: BoxDecoration(
              border: Border.all(color: bord, width: AppLayout.bordureControle),
              borderRadius: rayon,
            ),
            // `widthFactor: 1` : centré verticalement, sans s'étirer en largeur.
            child: Center(
              widthFactor: 1,
              child: Text(
                libelle,
                key: cleLibelle,
                maxLines: 1,
                style: TextStyle(
                  fontFamily: AppTextStyles.police,
                  fontSize: compact ? TaillesContenu.t12 : taillePolice,
                  height: AppLayout.interligneContenu,
                  letterSpacing: 0,
                  fontWeight: compact ? FontWeight.w400 : poids,
                  color: texte,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
