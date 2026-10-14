/// Les briques communes aux deux écrans de M4.
///
/// Les deux pages du maître partagent leur ossature — en-tête à icône et
/// sous-titre, cadre blanc à bord `slate-200`, tableau à en-tête compacte en
/// capitales, pavés d'explication colorés. Les recopier dans chaque écran les
/// ferait diverger au premier ajustement, exactement comme l'en-tête d'état
/// recopiée que `RESPECT_TABLEAU_RAPPORT.md` §4 recense en non-conformité n° 1.
///
/// ## Deux échelles typographiques, et il faut savoir de quel côté on tombe
///
/// `app.css` l.166-197 remappe l'échelle **à l'intérieur de `<main>`** : dans
/// une page du maître, `text-[13px]` rend 12,5 px. Le contenu de page emploie
/// donc [TaillesContenu]. Les **conteneurs de modales** sont hors `</main>` au
/// maître — `crud-ui.js` les injecte dans `#crud-modales-zone`, frère de
/// `<main>` — et emploient [Tailles], l'échelle déclarée.
///
/// [TextesRestaurant] tient cette frontière, style par style, chacun avec la
/// classe du maître qui le produit.
library;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';

/// Les styles de texte des deux écrans, **mesurés dans le maître**.
///
/// Chaque entrée cite la classe qui la produit. Une taille déduite d'un nom de
/// classe est une erreur en attente — `DIRECTIVE_CONFORMITE_100.md` Article 2.
abstract final class TextesRestaurant {
  /* -------------------------------------------- Contenu de page (`<main>`) */

  /// `text-lg font-bold` sur le titre de page — l'échelle **effective**.
  /// `m4-restaurant-carte.html` l.30, `m4-restauration.html` l.26.
  static const TextStyle titrePage = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: TaillesContenu.lg,
    height: TaillesContenu.interligneLg,
    fontWeight: FontWeight.bold,
    color: AppColors.navy,
  );

  /// La variante `lg:text-xl` du même titre, au-delà du point de rupture
  /// `lg` (1024 px). **Deux tailles, pas une** : le maître écrit
  /// `text-lg lg:text-xl`, et n'en retenir qu'une serait changer un point de
  /// rupture (Article 1, interdit 12).
  static const TextStyle titrePageLarge = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: TaillesContenu.xl,
    height: TaillesContenu.interligneXl,
    fontWeight: FontWeight.bold,
    color: AppColors.navy,
  );

  /// `text-[15px] text-slate-500` — le sous-titre de page.
  /// `m4-restaurant-carte.html` l.32, `m4-restauration.html` l.28.
  static const TextStyle sousTitrePage = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: TaillesContenu.t15,
    color: Ardoise.c500,
  );

  /// `text-[13px]` — la taille la plus employée du maître.
  static const TextStyle corps = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: TaillesContenu.t13,
    color: Ardoise.c700,
  );

  /// `text-[13px] font-semibold text-slate-800` — la première cellule d'une
  /// ligne de carte (`carte-module.js` l.98).
  static const TextStyle corpsFort = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: TaillesContenu.t13,
    fontWeight: FontWeight.w600,
    color: Ardoise.c800,
  );

  /// `text-[12px] text-slate-500` — la seconde ligne d'une cellule.
  static const TextStyle secondaire = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: TaillesContenu.t12,
    color: Ardoise.c500,
  );

  /// `text-[11px] text-slate-400` — mention discrète.
  static const TextStyle mention = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: TaillesContenu.t11,
    color: Ardoise.c400,
  );

  /// `text-[10.5px] text-slate-400` — la conversion sous un article de stock
  /// (`carte-module.js` l.110).
  static const TextStyle mentionFine = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: TaillesContenu.t10_5,
    color: Ardoise.c400,
  );

  /// `text-[11px] uppercase tracking-wide text-slate-500 font-semibold` —
  /// l'en-tête d'une colonne de tableau (`carte-module.js` l.51).
  static const TextStyle enteteColonne = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: TaillesContenu.t11,
    fontWeight: FontWeight.w600,
    letterSpacing: TaillesContenu.t11 * AppTextStyles.suiviLarge,
    color: Ardoise.c500,
  );

  /// La même en-tête, **sur fond navy** — `text-white/90`
  /// (`crud-ui.js` l.69). Le moteur CRUD pose une en-tête pleine, là où la
  /// carte pose une en-tête `bg-slate-50`. Deux écrans, deux en-têtes : les
  /// aligner serait choisir à la place du maître.
  static const TextStyle enteteColonneNavy = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: TaillesContenu.t11,
    fontWeight: FontWeight.w600,
    letterSpacing: TaillesContenu.t11 * AppTextStyles.suiviLarge,
    color: AppColors.neutre0,
  );

  /// `text-[11px] uppercase tracking-wide text-slate-400 font-semibold` — le
  /// libellé d'une carte d'indicateur (`carte-module.js` l.383).
  static const TextStyle libelleIndicateur = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: TaillesContenu.t11,
    fontWeight: FontWeight.w600,
    letterSpacing: TaillesContenu.t11 * AppTextStyles.suiviLarge,
    color: Ardoise.c400,
  );

  /// `text-[17px] font-bold` — la valeur d'une carte d'indicateur (l.384).
  static const TextStyle valeurIndicateur = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: TaillesContenu.t17,
    fontWeight: FontWeight.bold,
    color: AppColors.navy,
  );

  /// `text-[14px] font-bold` — le titre d'un cadre de tableau (l.47).
  static const TextStyle titreCadre = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: TaillesContenu.t14,
    fontWeight: FontWeight.bold,
    color: AppColors.navy,
  );

  /// `text-[13px] font-semibold` — un onglet (l.52-53) et un bouton de la
  /// barre d'en-tête (l.35-45).
  static const TextStyle onglet = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: TaillesContenu.t13,
    fontWeight: FontWeight.w600,
  );

  /// `text-sm` du moteur CRUD — une cellule de son tableau (`crud-engine.js`
  /// l.230) et son champ de recherche (`crud-ui.js` l.21).
  static const TextStyle corpsCrud = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: TaillesContenu.sm,
    height: TaillesContenu.interligneSm,
    color: Ardoise.c700,
  );

  /// `text-xs` du moteur CRUD — ses filtres, ses boutons, sa pagination.
  static const TextStyle petitCrud = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: TaillesContenu.xs,
    height: TaillesContenu.interligneXs,
    color: Ardoise.c500,
  );

  /// `text-xs font-semibold` — le texte d'une pastille de badge
  /// (`crud-engine.js` l.219).
  static const TextStyle pastille = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: TaillesContenu.xs,
    fontWeight: FontWeight.w600,
  );

  /// `text-[11px]` compact — une pastille de la carte (`carte-module.js`
  /// l.94-96) et un bouton d'action de ligne (l.117-122).
  static const TextStyle pastilleCarte = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: TaillesContenu.t11,
    fontWeight: FontWeight.w600,
  );
}

/// L'en-tête de page du maître : icône, titre, sous-titre — au mot près.
///
/// Le titre bascule de `text-lg` à `text-xl` au point de rupture `lg`
/// (1024 px), et la décision se prend sur la largeur de l'**écran**, jamais sur
/// celle du contenu : une barre latérale déployée fausse tout. C'est le défaut
/// de responsive n° 1 de ce dépôt.
class EnTeteRestaurant extends StatelessWidget {
  const EnTeteRestaurant({
    super.key,
    required this.icone,
    required this.titre,
    required this.sousTitre,
    this.actions = const [],
  });

  final Widget icone;
  final String titre;

  /// Repris **tel quel**. Un texte reformulé est un écart : le manuel, la
  /// formation et l'habitude s'appuient sur le mot exact.
  final String sousTitre;

  /// Les boutons de droite — `flex flex-wrap gap-2`
  /// (`m4-restaurant-carte.html` l.34-46). Vide sur `m4-restauration.html`,
  /// qui n'en pose aucun à cet endroit.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final bloc = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            icone,
            // `gap-2.5` — 10 px, et non les 8 px de `gap-2`. `py-2.5` fait
            // 10 px là où `py-[7px]` en ferait 7 : l'échelle nommée n'est pas
            // la valeur entre crochets.
            const SizedBox(width: AppSpacing.xsPlus),
            Flexible(
              child: Text(
                titre,
                // MESURÉ dans le navigateur (Phase 1D, 08/10/2026) : à 1383 px
                // le titre rend à 17 px (`lg`), pas à 18,5 px (`xl`) — la
                // variante `lg:text-xl` n'est pas celle qui s'applique dans
                // `<main>`. L'échelle supposée était fausse de 8,8 %.
                style: TextesRestaurant.titrePage,
              ),
            ),
          ],
        ),
        // `mt-1.5` — 6 px.
        const SizedBox(height: AppSpacing.xxs),
        Text(sousTitre, style: TextesRestaurant.sousTitrePage),
      ],
    );

    if (actions.isEmpty) return bloc;

    // `flex flex-wrap items-start justify-between gap-3` (l.26).
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.start,
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        bloc,
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: actions,
        ),
      ],
    );
  }
}

/// Un onglet de la carte — `m4-restaurant-carte.html` l.14-15 :
/// `.onglet-actif { background: var(--navy); color: #fff }`,
/// `.onglet-inactif { background: #fff; color: #64748B; border: 1px solid #E2E8F0 }`.
class OngletRestaurant extends StatelessWidget {
  const OngletRestaurant({
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
    return InkWell(
      onTap: onChoix,
      borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      child: Container(
        // `px-3.5 py-2` — 14 px et 8 px. Mesurés, pas déduits.
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.smPlus,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: actif ? AppColors.navy : AppColors.neutre0,
          border: Border.all(color: actif ? AppColors.navy : Ardoise.c200),
          borderRadius: BorderRadius.circular(AppRadius.roundedLg),
        ),
        child: Text(
          libelle,
          style: TextesRestaurant.onglet.copyWith(
            color: actif ? AppColors.neutre0 : Ardoise.c500,
          ),
        ),
      ),
    );
  }
}

/// Une carte de la bande d'indicateurs — `carte-module.js` l.381-386.
///
/// [valeur] est `null` quand la donnée **n'existe pas** : la carte affiche
/// alors « — » et [raison] dit pourquoi. Jamais `0` — « — » et « 0 » ne disent
/// pas la même chose (Article 7), et sur cet écran un zéro inventé se lirait
/// comme « aucun plat retiré, aucun prix provisoire », c'est-à-dire comme une
/// bonne nouvelle que personne n'a vérifiée.
class CarteIndicateurRestaurant extends StatelessWidget {
  const CarteIndicateurRestaurant({
    required Key cle,
    required this.libelle,
    required this.valeur,
    this.detail,
    this.raison,
    this.accent,
  }) : super(key: cle);

  final String libelle;
  final String? valeur;

  /// La seconde ligne du maître — « N disponible(s) », « Rupture ou retrait ».
  final String? detail;

  /// Obligatoire de fait quand [valeur] est `null` : une absence sans raison
  /// laisse croire à une panne.
  final String? raison;

  final Color? accent;

  /// Le tiret de l'Article 7. Un seul endroit dans tout M4 : deux écritures
  /// différentes du même « rien » se liraient comme deux états.
  static const String absent = '—';

  @override
  Widget build(BuildContext context) {
    return Container(
      // `p-3.5` — 14 px.
      padding: const EdgeInsets.all(AppSpacing.smPlus),
      decoration: BoxDecoration(
        color: AppColors.neutre0,
        borderRadius: BorderRadius.circular(AppRadius.roundedXl),
        border: Border.all(color: Ardoise.c200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            libelle.toUpperCase(),
            style: TextesRestaurant.libelleIndicateur,
          ),
          // `mt-1` — 4 px.
          const SizedBox(height: AppSpacing.unit),
          Text(
            valeur ?? absent,
            style: TextesRestaurant.valeurIndicateur.copyWith(
              color: valeur == null ? Ardoise.c400 : (accent ?? AppColors.navy),
            ),
          ),
          // `mt-0.5` — 2 px.
          const SizedBox(height: AppSpacing.demi),
          if (detail != null) Text(detail!, style: TextesRestaurant.mention),
          if (raison != null)
            Text(raison!, style: TextesRestaurant.mention, maxLines: 6),
        ],
      ),
    );
  }
}

/// Le ton d'un pavé d'explication — `carte-module.js` l.55-56.
enum TonEncadre {
  /// `#FFFBEB` / `#FDE68A` / `#78350F`.
  ambre(PaletteMaitre.ambre50, PaletteMaitre.ambre200, PaletteMaitre.ambre900),

  /// `#F8FAFC` / `#E2E8F0` / `#334155`.
  gris(Ardoise.c50, Ardoise.c200, Ardoise.c700);

  const TonEncadre(this.fond, this.bordure, this.texte);

  final Color fond;
  final Color bordure;
  final Color texte;
}

/// Un pavé d'explication — `encadre()` de `carte-module.js` l.54-60.
///
/// Ce n'est pas une décoration : le bandeau de M4 porte la raison pour laquelle
/// des plats ne décrémentent rien. Le retirer laisserait le chiffre sans son
/// explication.
class EncadreRestaurant extends StatelessWidget {
  const EncadreRestaurant({
    required Key cle,
    required this.ton,
    required this.titre,
    required this.texte,
    this.titreSepare = false,
  }) : super(key: cle);

  final TonEncadre ton;

  /// Vrai quand le `<strong>` et le texte sont deux ÉLÉMENTS de la vue
  /// (`vehicules/locations.blade.php` l.234-236 : le relevé les mesure à part,
  /// x = 310,8 et 474,6) et non une seule phrase : deux `Text` côte à côte, qui
  /// passent à la ligne ensemble. Faux par défaut : aucun autre écran ne change
  /// (09/10/2026).
  final bool titreSepare;

  /// Rendu en gras et suivi du texte, sur la même ligne — `<strong>` du maître.
  final String titre;

  final String texte;

  @override
  Widget build(BuildContext context) {
    return Container(
      // `rounded-xl p-3.5` — 14 px.
      padding: const EdgeInsets.all(AppSpacing.smPlus),
      decoration: BoxDecoration(
        color: ton.fond,
        borderRadius: BorderRadius.circular(AppRadius.roundedXl),
        border: Border.all(color: ton.bordure),
      ),
      child: titreSepare
          ? Wrap(
              // L'espace entre `</strong>` et le texte : ~4 px à 13 px.
              spacing: AppSpacing.unit,
              children: [
                Text(
                  titre,
                  style: TextesRestaurant.corps.copyWith(
                    fontWeight: FontWeight.bold,
                    color: ton.texte,
                  ),
                ),
                Text(
                  texte,
                  style: TextesRestaurant.corps.copyWith(color: ton.texte),
                ),
              ],
            )
          : Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$titre ',
                    style: TextesRestaurant.corps.copyWith(
                      fontWeight: FontWeight.bold,
                      color: ton.texte,
                    ),
                  ),
                  TextSpan(
                    text: texte,
                    style: TextesRestaurant.corps.copyWith(color: ton.texte),
                  ),
                ],
              ),
            ),
    );
  }
}

/// Le cadre blanc d'un tableau — `bg-white rounded-xl border border-slate-200
/// overflow-hidden` (`carte-module.js` l.44).
class CadreTableauRestaurant extends StatelessWidget {
  const CadreTableauRestaurant({
    super.key,
    this.titre,
    this.aside,
    required this.corps,
  });

  /// L'en-tête du cadre — « 6 article(s) », « Couverture du lien au stock,
  /// catégorie par catégorie ». Absent sur le tableau du moteur CRUD.
  final String? titre;

  /// La mention de droite — « Le stock vendable est calculé, jamais saisi. »
  final String? aside;

  final Widget corps;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.neutre0,
        borderRadius: BorderRadius.circular(AppRadius.roundedXl),
        border: Border.all(color: Ardoise.c200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (titre != null)
            Container(
              // `px-4 py-3`.
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Ardoise.c200)),
              ),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  Text(titre!, style: TextesRestaurant.titreCadre),
                  if (aside != null)
                    Text(aside!, style: TextesRestaurant.mention),
                ],
              ),
            ),
          corps,
        ],
      ),
    );
  }
}

/// Une pastille — `<span class="inline-block px-2.5 py-1 rounded text-xs
/// font-semibold">` (`crud-engine.js` l.219) et les pastilles compactes de la
/// carte (`carte-module.js` l.95).
class PastilleRestaurant extends StatelessWidget {
  const PastilleRestaurant({
    required Key cle,
    required this.texte,
    required this.fond,
    required this.couleur,
    this.compacte = false,
  }) : super(key: cle);

  final String texte;
  final Color fond;
  final Color couleur;

  /// La variante `px-1.5 py-0.5 rounded` de la carte, plus petite que celle du
  /// moteur CRUD. Deux tailles au maître : les aligner serait choisir à sa
  /// place.
  final bool compacte;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: compacte
          // `px-1.5 py-0.5` — 6 px et 2 px.
          ? const EdgeInsets.symmetric(
              horizontal: AppSpacing.xxs,
              vertical: AppSpacing.demi,
            )
          // `px-2.5 py-1` — 10 px et 4 px.
          : const EdgeInsets.symmetric(
              horizontal: AppSpacing.xsPlus,
              vertical: AppSpacing.unit,
            ),
      decoration: BoxDecoration(
        color: fond,
        borderRadius: BorderRadius.circular(AppRadius.rounded),
      ),
      child: Text(
        texte,
        style:
            (compacte
                    ? TextesRestaurant.pastilleCarte
                    : TextesRestaurant.pastille)
                .copyWith(color: couleur),
      ),
    );
  }
}

// `BlocNonRenduRestaurant` (le bloc « Ce que cet écran ne rend pas ») est
// RETIRÉ le 14/10/2026 : directive absolue du PO, aucune note de conception
// ne s'affiche plus à l'écran. Les écarts se nomment au code.

/// Un message qui occupe la place d'une liste : refus, coupure, liste vide.
///
/// Un écran qui ne rend jamais rien passe pour cassé : il dit toujours quelque
/// chose, et il dit **quoi faire** (Article 7).
class NoteRestaurant extends StatelessWidget {
  const NoteRestaurant({
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
        color: Ardoise.c100,
        borderRadius: BorderRadius.circular(AppRadius.roundedXl),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, color: Ardoise.c500),
          const SizedBox(width: AppSpacing.xs),
          Expanded(child: Text(texte, style: TextesRestaurant.corps)),
        ],
      ),
    );
  }
}

/// L'état vide du moteur CRUD — `crud-ui.js` l.75-79, au mot près.
class EtatVideCrud extends StatelessWidget {
  const EtatVideCrud({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      // `py-16` — 64 px.
      padding: const EdgeInsets.symmetric(vertical: AppSpacingLarge.p16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // `<svg width="40" height="40" stroke="#CBD5E1">` — la loupe.
          const Icon(
            Icons.search,
            size: AppLayout.iconeEtatVide,
            color: Ardoise.c300,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Aucun résultat',
            style: TextesRestaurant.corpsCrud.copyWith(
              fontWeight: FontWeight.w600,
              color: Ardoise.c500,
            ),
          ),
          const SizedBox(height: AppSpacing.unit),
          Text(
            'Essayez de modifier votre recherche ou vos filtres.',
            style: TextesRestaurant.petitCrud.copyWith(color: Ardoise.c400),
          ),
        ],
      ),
    );
  }
}
