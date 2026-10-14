/// Les briques communes des écrans transverses du lot D (14/10/2026) : la page
/// (`max-w-[…] mx-auto p-5 lg:p-8`), l'en-tête (icône 24 px, `<h1>`,
/// sous-titre), la carte blanche (`bg-white rounded-xl border
/// border-slate-200`), l'onglet (`Onglets::classes`), le tableau à en-tête
/// navy et le bouton.
///
/// Ce fichier ne porte AUCUNE vue (PA-187) : il ne cite aucun chemin de vue,
/// et aucun libellé de vue n'y est écrit — chaque écran passe les siens.
library;

import 'package:flutter/material.dart';

import '../../../../core/navigation/trace_svg.dart';
import '../../../../core/theme/app_breakpoints.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/mesures_transverses.dart';

/// Un style de texte DANS `<main>` : la police de la vue, `height: 1.5`,
/// `letterSpacing: 0` — `app.css` remappe les tailles (`TaillesContenu`).
TextStyle styleTransverse(
  double taille, {
  FontWeight? poids,
  Color couleur = AppColors.anthracite,
  double interligne = AppLayout.interligneContenu,
  String? police,
}) => TextStyle(
  fontFamily: police ?? AppTextStyles.police,
  fontSize: taille,
  fontWeight: poids,
  color: couleur,
  height: interligne,
  letterSpacing: 0,
);

/// Le message d'un geste : un clic n'est jamais muet (Article 3.3).
void direTransverse(BuildContext context, String message, {Key? cle}) {
  ScaffoldMessenger.maybeOf(context)
    ?..removeCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message, key: cle)));
}

/// `<div class="max-w-[…] mx-auto p-5 lg:p-8">` dans un `<main>` qui défile.
class PageTransverse extends StatelessWidget {
  const PageTransverse({
    required this.largeurMax,
    required this.enfants,
    this.controleur,
    super.key,
  });

  final double largeurMax;
  final List<Widget> enfants;

  /// Pour remonter en haut de page après un geste posé en bas (une tuile qui
  /// change d'onglet).
  final ScrollController? controleur;

  @override
  Widget build(BuildContext context) {
    final large = MediaQuery.sizeOf(context).width >= AppBreakpoints.lg;
    return SingleChildScrollView(
      controller: controleur,
      padding: EdgeInsets.all(large ? AppSpacing.xl : AppSpacing.mdPlus),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: largeurMax),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: enfants,
          ),
        ),
      ),
    );
  }
}

/// L'en-tête de page : `flex items-center gap-2.5`, l'icône de 24 px navy, le
/// `<h1 class="text-lg lg:text-xl font-bold">`, puis le sous-titre
/// `text-[15px] text-slate-500 mt-1.5`.
class EnTeteTransverse extends StatelessWidget {
  const EnTeteTransverse({
    required this.trace,
    required this.titre,
    required this.sousTitre,
    this.margeBas = AppSpacing.lg,
    this.sousTitreRiche,
    super.key,
  });

  final String trace;
  final String titre;
  final String sousTitre;

  /// `mb-6` par défaut, `mb-5` pour le journal et le hub.
  final double margeBas;

  /// Un sous-titre composé (un mot en gras) — remplace [sousTitre] au rendu.
  final InlineSpan? sousTitreRiche;

  @override
  Widget build(BuildContext context) {
    final large = MediaQuery.sizeOf(context).width >= AppBreakpoints.lg;
    final styleSous = styleTransverse(
      TaillesContenu.t15,
      couleur: Ardoise.c500,
    );
    return Padding(
      padding: EdgeInsets.only(bottom: margeBas),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            // `flex items-center` sans `w-full` : le bloc de titre garde sa
            // largeur de contenu (le hub pose le sélecteur d'exercice à côté).
            mainAxisSize: MainAxisSize.min,
            children: [
              IconeTrace(
                trace: trace,
                taille: AppLayout.iconeTitrePage,
                couleur: AppColors.navy,
              ),
              const SizedBox(width: AppSpacing.xsPlus), // gap-2.5
              Flexible(
                child: Text(
                  titre,
                  style: styleTransverse(
                    large ? TaillesContenu.xl : TaillesContenu.lg,
                    poids: FontWeight.bold,
                    couleur: AppColors.navy,
                    interligne: large
                        ? TaillesContenu.interligneXl
                        : TaillesContenu.interligneLg,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs), // mt-1.5
          if (sousTitreRiche != null)
            Text.rich(sousTitreRiche!, style: styleSous)
          else
            Text(sousTitre, style: styleSous),
        ],
      ),
    );
  }
}

/// `bg-white rounded-xl border border-slate-200` (+ `overflow-hidden`).
class CarteTransverse extends StatelessWidget {
  const CarteTransverse({
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.mdPlus), // p-5
    this.fond = AppColors.neutre0,
    this.bordure = Ardoise.c200,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color fond;
  final Color bordure;

  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    padding: padding,
    decoration: BoxDecoration(
      color: fond,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      border: Border.all(color: bordure),
    ),
    child: child,
  );
}

/// Un encadré coloré (`rounded-xl border p-4` sur un fond de couleur).
class EncadreTransverse extends StatelessWidget {
  const EncadreTransverse({
    required this.fond,
    required this.bordure,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md), // p-4
    super.key,
  });

  final Color fond;
  final Color bordure;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: fond,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      border: Border.all(color: bordure),
    ),
    child: child,
  );
}

/// `Onglets::classes($actif)` — `px-3.5 py-2 rounded-lg text-[13px]
/// font-semibold`, actif `bg-navy text-white shadow-sm`, inactif `bg-white
/// text-slate-500 border border-slate-200`.
class OngletTransverse extends StatelessWidget {
  const OngletTransverse({
    required Key cle,
    required this.libelle,
    required this.actif,
    required this.onChoix,
    this.pastille,
  }) : super(key: cle);

  final String libelle;
  final bool actif;
  final VoidCallback onChoix;

  /// Un compteur doré après le libellé (onglet « Restaurer »).
  final String? pastille;

  @override
  Widget build(BuildContext context) {
    final forme = BorderRadius.circular(AppRadius.md);
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
              horizontal: AppSpacing.smPlus,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              borderRadius: forme,
              border: actif ? null : Border.all(color: Ardoise.c200),
            ),
            child: Text(
              libelle,
              style: styleTransverse(
                TaillesContenu.t13,
                poids: FontWeight.w600,
                couleur: actif ? AppColors.neutre0 : Ardoise.c500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Un bouton de la vue : fond plein (`text-white`) ou contour (`border
/// border-slate-300 bg-white`). Il a toujours un geste (Article 3.3).
class BoutonTransverse extends StatelessWidget {
  const BoutonTransverse({
    required Key cle,
    required this.libelle,
    required this.onTap,
    this.fond,
    this.trace,
    this.taille = TaillesContenu.t13,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.xs,
    ),
    this.couleurContour = Ardoise.c300,
    this.couleurTexteContour = Ardoise.c700,
    this.pleineLargeur = false,
  }) : super(key: cle);

  final String libelle;
  final VoidCallback onTap;

  /// `null` : bouton à contour, fond blanc.
  final Color? fond;
  final String? trace;
  final double taille;
  final EdgeInsetsGeometry padding;
  final Color couleurContour;
  final Color couleurTexteContour;
  final bool pleineLargeur;

  @override
  Widget build(BuildContext context) {
    final plein = fond != null;
    final couleurTexte = plein ? AppColors.neutre0 : couleurTexteContour;
    final forme = BorderRadius.circular(AppRadius.md);
    return Material(
      color: fond ?? AppColors.neutre0,
      borderRadius: forme,
      child: InkWell(
        onTap: onTap,
        borderRadius: forme,
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: forme,
            border: plein ? null : Border.all(color: couleurContour),
          ),
          child: Row(
            mainAxisSize: pleineLargeur ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (trace != null) ...[
                IconeTrace(
                  trace: trace!,
                  taille: MesuresTransverses.iconeBouton,
                  couleur: couleurTexte,
                ),
                const SizedBox(width: AppSpacing.xs),
              ],
              Flexible(
                child: Text(
                  libelle,
                  textAlign: TextAlign.center,
                  style: styleTransverse(
                    taille,
                    poids: FontWeight.w600,
                    couleur: couleurTexte,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Une colonne d'un tableau : son en-tête et son alignement.
typedef ColonneTransverse = ({String titre, TextAlign alignement});

/// Un tableau à en-tête navy (`thead class="bg-[var(--navy)]"`, `text-[11px]
/// font-semibold text-white/90 uppercase tracking-wide`), qui défile en
/// largeur (`overflow-x-auto`). Sans ligne, [vide] occupe une rangée centrée
/// (`colspan`), jamais un tableau blanc.
class TableauTransverse extends StatelessWidget {
  const TableauTransverse({
    required this.colonnes,
    required this.lignes,
    required this.vide,
    this.pied,
    this.majuscules = true,
    this.largeurs = const {},
    this.cleVide,
    super.key,
  });

  final List<ColonneTransverse> colonnes;
  final List<List<Widget>> lignes;

  /// Le texte de la rangée vide — celui de la vue, ou ce qui le dit.
  final String vide;
  final Key? cleVide;

  /// Une rangée de totaux (`tfoot`), rendue sur fond navy.
  final List<Widget>? pied;

  /// `uppercase` : la plupart des en-têtes de la vue le sont.
  final bool majuscules;

  /// Les largeurs FIXES, par rang de colonne ; les autres prennent
  /// [MesuresTransverses.colonneTableauMin] au moins.
  final Map<int, double> largeurs;

  static EdgeInsets get _cellule => const EdgeInsets.symmetric(
    horizontal: AppSpacing.sm,
    vertical: AppSpacing.xsPlus,
  );

  @override
  Widget build(BuildContext context) {
    final enTete = styleTransverse(
      TaillesContenu.t11,
      poids: FontWeight.w600,
      couleur: AppColors.neutre0.withValues(
        alpha: OpacitesAccueil.enTeteTableau,
      ),
    ).copyWith(letterSpacing: AppTextStyles.suiviLarge * TaillesContenu.t11);

    // Une cellule : largeur FIXE si la colonne en a une, sinon `Expanded` au
    // moins large de [MesuresTransverses.colonneTableauMin].
    Widget cellule(Widget enfant, int rang) {
      final colonne = colonnes[rang];
      final fixe = largeurs[rang];
      final boite = Container(
        constraints: BoxConstraints(
          minWidth: fixe ?? MesuresTransverses.colonneTableauMin,
        ),
        width: fixe,
        padding: _cellule,
        alignment: switch (colonne.alignement) {
          TextAlign.right || TextAlign.end => Alignment.centerRight,
          TextAlign.center => Alignment.center,
          _ => Alignment.centerLeft,
        },
        child: enfant,
      );
      return fixe != null ? boite : Expanded(child: boite);
    }

    return LayoutBuilder(
      builder: (context, contraintes) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: contraintes.maxWidth),
          child: IntrinsicWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  color: AppColors.navy,
                  child: Row(
                    children: [
                      for (final (i, c) in colonnes.indexed)
                        cellule(
                          Text(
                            majuscules ? c.titre.toUpperCase() : c.titre,
                            textAlign: c.alignement,
                            style: enTete,
                          ),
                          i,
                        ),
                    ],
                  ),
                ),
                if (lignes.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.xlPlus, // py-10
                      horizontal: AppSpacing.mdPlus,
                    ),
                    child: Text(
                      vide,
                      key: cleVide,
                      textAlign: TextAlign.center,
                      style: styleTransverse(
                        TaillesContenu.t13,
                        couleur: Ardoise.c400,
                      ),
                    ),
                  ),
                for (final ligne in lignes)
                  DecoratedBox(
                    decoration: const BoxDecoration(
                      border: Border(top: BorderSide(color: Ardoise.c100)),
                    ),
                    child: Row(
                      children: [
                        for (final (i, enfant) in ligne.indexed)
                          cellule(enfant, i),
                      ],
                    ),
                  ),
                if (pied != null && lignes.isNotEmpty)
                  Container(
                    color: AppColors.navy,
                    child: Row(
                      children: [
                        for (final (i, enfant) in pied!.indexed)
                          cellule(enfant, i),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Le texte d'une cellule — `text-[13px]` (12,5 px dans `<main>`).
Text celluleTexte(
  String texte, {
  Color couleur = Ardoise.c600,
  FontWeight? poids,
  bool mono = false,
  double taille = TaillesContenu.t13,
  TextAlign? alignement,
}) => Text(
  texte,
  textAlign: alignement,
  style: styleTransverse(
    taille,
    poids: poids,
    couleur: couleur,
    police: mono ? AppTextStyles.policeMonospace : null,
  ),
);

/// Le refus d'un écran entier quand le droit manque — la vue répond 403 à la
/// route (`module:…,L`) ; ce poste DIT le refus au lieu d'un écran blanc.
class RefusDroitTransverse extends StatelessWidget {
  const RefusDroitTransverse({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Text(
        message,
        key: const Key('transverse-refus-droit'),
        textAlign: TextAlign.center,
        style: styleTransverse(TaillesContenu.t15, couleur: Ardoise.c500),
      ),
    ),
  );
}

/// Une grille de cartes (`grid grid-cols-N gap-…`) dont les rangées prennent
/// la hauteur de leur plus haute carte.
class GrilleTransverse extends StatelessWidget {
  const GrilleTransverse({
    required this.colonnes,
    required this.ecart,
    required this.enfants,
    super.key,
  });

  final int colonnes;
  final double ecart;
  final List<Widget> enfants;

  @override
  Widget build(BuildContext context) {
    final rangees = <Widget>[];
    for (var i = 0; i < enfants.length; i += colonnes) {
      final tranche = enfants.sublist(
        i,
        i + colonnes > enfants.length ? enfants.length : i + colonnes,
      );
      rangees.add(
        Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : ecart),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var j = 0; j < colonnes; j++) ...[
                  if (j > 0) SizedBox(width: ecart),
                  Expanded(
                    child: j < tranche.length
                        ? tranche[j]
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rangees,
    );
  }
}
