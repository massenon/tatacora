/// Les briques communes aux deux écrans de M7.
///
/// Les deux pages du maître partagent leur ossature — en-tête à icône, onglets,
/// barre d'outils, tableau encadré, pastilles de statut. Le maître factorise
/// lui-même sa barre d'outils (`m7-approvisionnement.html` l.118,
/// `barreOutils`) et écrit pourquoi (l.108-111) : *« Trois barres différentes
/// pour quatre listes obligent l'utilisateur à réapprendre l'écran à chaque
/// onglet — et c'est ainsi qu'on cesse de se servir des filtres. »*
///
/// La recopier dans chaque onglet la ferait diverger au premier ajustement,
/// exactement comme l'en-tête d'état recopiée que `RESPECT_TABLEAU_RAPPORT.md`
/// §4 recense en non-conformité n° 1.
library;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';

/// Un onglet de la barre de `pwa/achats/achats.blade.php` (l.75-80), au style
/// UNIQUE de la PWA — `App\Pwa\Support\Onglets::classes()` : `px-3.5 py-2
/// rounded-lg text-[13px] font-semibold`, plein navy avec `shadow-sm` quand il
/// est actif, blanc bordé de gris sinon (directive du Product Owner du
/// 01/09/2026, un seul auteur).
///
/// L'onglet actif n'a PAS de filet : le bouton plein est donc 2 px plus court
/// que les autres, comme dans la vue.
class OngletAchats extends StatelessWidget {
  const OngletAchats({
    required Key cle,
    required this.libelle,
    required this.actif,
    required this.onChoix,
  }) : super(key: cle);

  final String libelle;
  final bool actif;
  final VoidCallback onChoix;

  @override
  Widget build(BuildContext context) {
    final forme = BorderRadius.circular(AppRadius.roundedLg);

    return Container(
      decoration: BoxDecoration(
        borderRadius: forme,
        boxShadow: actif ? AppShadows.tailwindSm : null,
      ),
      child: Material(
        color: actif ? AppColors.navy : AppColors.neutre0,
        borderRadius: forme,
        child: InkWell(
          onTap: onChoix,
          borderRadius: forme,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.smPlus, // px-3.5
              vertical: AppSpacing.xs, // py-2
            ),
            decoration: BoxDecoration(
              borderRadius: forme,
              border: actif ? null : Border.all(color: Ardoise.c200),
            ),
            child: Text(
              libelle,
              style: TextStyle(
                fontFamily: AppTextStyles.police,
                fontSize: TaillesContenu.t13,
                fontWeight: FontWeight.w600,
                height: AppLayout.interligneContenu,
                color: actif ? AppColors.neutre0 : Ardoise.c500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// L'en-tête de page du maître : icône, titre, sous-titre — au mot près.
class EnTeteAchats extends StatelessWidget {
  const EnTeteAchats({
    super.key,
    required this.icone,
    required this.titre,
    required this.sousTitre,
    this.onglets = const [],
    this.action,
  });

  final IconData icone;
  final String titre;

  /// Repris **tel quel**. Un texte reformulé est un écart : le manuel, la
  /// formation et l'habitude s'appuient sur le mot exact.
  final String sousTitre;

  final List<Widget> onglets;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.neutre200)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icone, color: AppColors.navy, size: 22),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  titre,
                  style: textes.titleLarge?.copyWith(color: AppColors.navy),
                ),
              ),
              ?action,
            ],
          ),
          const SizedBox(height: AppSpacing.unit),
          Text(
            sousTitre,
            style: textes.bodySmall?.copyWith(color: AppColors.neutre500),
          ),
          if (onglets.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: onglets,
            ),
          ],
        ],
      ),
    );
  }
}

/// Une carte d'indicateur — `bg-white rounded-xl border border-slate-200
/// p-3.5` : libellé `text-[10px] font-bold uppercase tracking-wider`, valeur
/// `text-lg font-bold mt-0.5`.
///
/// [valeur] est `null` quand la donnée n'a **pas été obtenue** : la carte rend
/// alors « — » et sa raison en infobulle, jamais `0`. Un zéro se lit comme une
/// mesure — « aucune dette », « aucune commande en attente » — sous un écran
/// qui n'a rien consulté. La raison n'est pas écrite DANS la carte : une ligne
/// de plus l'étirerait, et la vue n'en a que deux ; l'écran la redit en note.
class CarteKpiAchats extends StatelessWidget {
  const CarteKpiAchats({
    required Key cle,
    required this.libelle,
    required this.valeur,
    this.raisonAbsence,
    this.accent,
  }) : super(key: cle);

  final String libelle;
  final String? valeur;

  /// Obligatoire de fait quand [valeur] est `null` : une absence sans raison
  /// laisse croire à une panne.
  final String? raisonAbsence;

  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final carte = Container(
      padding: const EdgeInsets.all(AppSpacing.smPlus), // p-3.5
      decoration: BoxDecoration(
        color: AppColors.neutre0,
        borderRadius: BorderRadius.circular(AppRadius.roundedXl),
        border: Border.all(color: AppColors.neutre200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            libelle.toUpperCase(),
            style: const TextStyle(
              fontFamily: AppTextStyles.police,
              fontSize: TaillesContenu.t10,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
              height: AppLayout.interligneContenu,
              color: AppColors.neutre400,
            ),
          ),
          const SizedBox(height: AppSpacing.demi), // mt-0.5
          Text(
            valeur ?? '—',
            style: TextStyle(
              fontFamily: AppTextStyles.police,
              fontSize: TaillesContenu.lg,
              fontWeight: FontWeight.bold,
              height: TaillesContenu.interligneLg,
              color: valeur == null
                  ? AppColors.neutre500
                  : (accent ?? AppColors.navy),
            ),
          ),
        ],
      ),
    );
    return raisonAbsence == null
        ? carte
        : Tooltip(message: raisonAbsence!, child: carte);
  }
}

/// Une pastille de statut ou de conformité.
class PastilleAchats extends StatelessWidget {
  const PastilleAchats({
    required Key cle,
    required this.texte,
    required this.couleur,
    required this.fond,
  }) : super(key: cle);

  final String texte;
  final Color couleur;
  final Color fond;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.demi,
      ),
      decoration: BoxDecoration(
        color: fond,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        texte,
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(color: couleur),
      ),
    );
  }
}

/// Un message qui occupe la place d'une liste : refus, coupure, liste vide.
///
/// Un écran qui ne rend jamais rien passe pour cassé (leçon PA-90) : il dit
/// toujours quelque chose, et il dit **quoi faire**.
class NoteAchats extends StatelessWidget {
  const NoteAchats({
    required Key cle,
    required this.texte,
    this.icone = Icons.cloud_off_outlined,
  }) : super(key: cle);

  final String texte;
  final IconData icone;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.neutre100,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, color: AppColors.neutre500),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              texte,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: AppColors.neutre500),
            ),
          ),
        ],
      ),
    );
  }
}

// `BlocNonRendu` (« Ce que cet onglet ne rend pas ») est RETIRÉ le 14/10/2026 :
// directive absolue du PO, aucune note de conception ne s'affiche plus.

/// Le cadre blanc d'un tableau — `bg-white rounded-xl border border-slate-200
/// overflow-hidden`, son en-tête `px-4 py-3 border-b` (titre `text-[13px]
/// font-bold`, sous-titre `text-[11px] text-slate-400 mt-0.5`).
///
/// [outils] est facultatif : dans la vue d'approvisionnement la recherche et
/// l'export sont ceux de la PAGE, au-dessus des sections.
class CadreListeAchats extends StatelessWidget {
  const CadreListeAchats({
    super.key,
    required this.titre,
    this.sousTitre,
    this.outils,
    required this.corps,
  });

  final String titre;
  final String? sousTitre;
  final Widget? outils;
  final Widget corps;

  @override
  Widget build(BuildContext context) {
    TextStyle t(double taille, {FontWeight? poids, Color? couleur}) =>
        TextStyle(
          fontFamily: AppTextStyles.police,
          fontSize: taille,
          fontWeight: poids,
          color: couleur,
          height: AppLayout.interligneContenu,
        );

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.neutre0,
        borderRadius: BorderRadius.circular(AppRadius.roundedXl),
        border: Border.all(color: AppColors.neutre200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.neutre200)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titre,
                  style: t(
                    TaillesContenu.t13,
                    poids: FontWeight.bold,
                    couleur: AppColors.navy,
                  ),
                ),
                if (sousTitre != null) ...[
                  const SizedBox(height: AppSpacing.demi),
                  Text(
                    sousTitre!,
                    style: t(TaillesContenu.t11, couleur: AppColors.neutre400),
                  ),
                ],
                if (outils != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  outils!,
                ],
              ],
            ),
          ),
          corps,
        ],
      ),
    );
  }
}
