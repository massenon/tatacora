// Vue Blade maîtresse (PA-183) : pwa/restaurant/carte.blade.php
import 'package:flutter/material.dart';

import '../../../../core/donnees_absentes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import 'cadre_ventes_carte.dart';
import 'corps_carte_commun.dart';

/// Ce que l'onglet « Ventes du Restaurant » ne trouve pas sur ce poste.
const String ventesRestaurantAbsentes = 'Les lignes de vente du restaurant';

/// L'onglet **« Ventes du Restaurant »** — `pwa/carte/corps.blade.php`
/// l.563-711 : la barre de filtres du panneau, puis le cadre du tableau.
///
/// ## Un onglet SANS donnée, dont la structure est quand même celle de la vue
///
/// Jusqu'au 09/10/2026 l'onglet se réduisait à une note : le bloc entier était
/// refusé (jeton de refus du bloc « ventes », retiré), au motif que rien ne sert
/// ce relevé sur ce poste. Ce motif reste VRAI et reste vérifié le même jour :
/// `ventes_bar_local` / `lignes_vente_bar_local` ne portent que le bar,
/// `paniers_local` ne porte ni le stock du jour, ni le statut, ni
/// l'utilisateur, et le relevé serveur des ventes M4 est un autre objet que ce
/// poste ne détient pas. Exposer l'un d'eux comme « ventes du restaurant »
/// serait inventer un relevé.
///
/// Mais un refus ne couvre que ce qu'il refuse. Ce qui est refusé, c'est la
/// DONNÉE ; la vue montre toujours son cadre — filtres, titre, colonnes, ligne
/// de total —, et un onglet réduit à une phrase passait pour cassé, alors que
/// le cadre vide DIT la même chose avec la structure de la vue. Le refus de
/// bloc est donc retiré, et remplacé par une présence honnête : tous les
/// éléments de la vue sont là, aucun ne porte un chiffre, et chaque geste dit
/// pourquoi il ne produit rien (Article 3.3).
///
/// Les filtres NE FILTRENT RIEN et ne sont pas désactivés : un contrôle grisé
/// sans explication se lit comme un écran cassé. Chacun répond, au toucher,
/// par la phrase de `core/donnees_absentes.dart`. La valeur de la liste ne
/// change pas non plus — une liste qui afficherait « Annulée » sous un tableau
/// qui ne filtre rien affirmerait un état qu'elle n'a pas vérifié.
class VueVentesRestaurant extends StatelessWidget {
  const VueVentesRestaurant({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _FiltresVentes(),
        CadreVentesSansDonnee(
          cleMessage: const Key('carte-restaurant-ventes-absentes'),
          message: donneeNonDisponible(ventesRestaurantAbsentes),
        ),
      ],
    );
  }
}

/// La barre de filtres du panneau — `bg-white rounded-xl border border-slate-200
/// p-3.5 mb-4`, une rangée `flex flex-wrap gap-2.5 items-center`, puis la note
/// des bornes (`mt-2`) — l.567-596.
class _FiltresVentes extends StatelessWidget {
  const _FiltresVentes();

  /// `gap-2.5` — 10 px.
  static const double _ecart = AppSpacing.xsPlus;

  void _dire(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          donneeNonDisponible(ventesRestaurantAbsentes),
          key: const Key('carte-restaurant-ventes-filtre-indisponible'),
        ),
      ),
    );
  }

  /// La largeur d'un texte, pour décider si la rangée tient sur une ligne.
  double _largeur(String texte, TextStyle style) {
    final mesure = TextPainter(
      text: TextSpan(text: texte, style: style),
      textDirection: TextDirection.ltr,
    )..layout();

    return mesure.width;
  }

  @override
  Widget build(BuildContext context) {
    final styleBorne = styleContenuCarte(
      TaillesContenu.t12,
      couleur: Ardoise.c500,
    );

    final recherche = TextField(
      key: const Key('carte-restaurant-ventes-recherche'),
      // Lecture seule : taper ici ne filtrerait aucune vente. Le toucher le
      // dit, au lieu de laisser croire que la frappe a été prise en compte.
      readOnly: true,
      style: styleContenuCarte(TaillesContenu.t13),
      decoration: decorationRechercheCarte(TextesVentesCarte.recherche),
      onTap: () => _dire(context),
    );

    final statut = ListeFiltre<String>(
      cleListe: const Key('carte-restaurant-ventes-statut'),
      largeur: AppLayout.filtreStatutVentesCarte,
      valeur: '',
      options: const [
        ('', TextesVentesCarte.tousStatuts),
        ('validee', TextesVentesCarte.validee),
        ('annulee', TextesVentesCarte.annulee),
      ],
      // Le choix n'est PAS retenu : `valeur` reste « Tous les statuts ».
      onChange: (_) => _dire(context),
    );

    Widget borne(String libelle, Key cle) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(libelle, style: styleBorne),
        // `gap-1.5` — 6 px.
        const SizedBox(width: AppSpacing.xxs),
        _ChampDate(cle: cle, onTap: () => _dire(context)),
      ],
    );

    final du = borne(
      TextesVentesCarte.du,
      const Key('carte-restaurant-ventes-du'),
    );
    final au = borne(
      TextesVentesCarte.au,
      const Key('carte-restaurant-ventes-au'),
    );

    return Container(
      // `mb-4`, `p-3.5`.
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.smPlus),
      decoration: BoxDecoration(
        color: AppColors.neutre0,
        borderRadius: BorderRadius.circular(AppRadius.roundedXl),
        border: Border.all(color: Ardoise.c200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, contraintes) {
              // Ce que prennent les contrôles qui ne s'étirent pas : la liste
              // et les deux bornes (libellé, 6 px, champ).
              final controles =
                  AppLayout.filtreStatutVentesCarte +
                  2 * (AppLayout.champDateVentesCarte + AppSpacing.xxs) +
                  _largeur(TextesVentesCarte.du, styleBorne) +
                  _largeur(TextesVentesCarte.au, styleBorne);
              final minimum =
                  AppLayout.rechercheMinCarteRestaurant +
                  controles +
                  _ecart * 3;

              if (contraintes.maxWidth >= minimum) {
                return Row(
                  children: [
                    Expanded(child: recherche),
                    const SizedBox(width: _ecart),
                    statut,
                    const SizedBox(width: _ecart),
                    du,
                    const SizedBox(width: _ecart),
                    au,
                  ],
                );
              }

              // Trop étroit : `flex-wrap` — la recherche prend sa ligne.
              return Wrap(
                spacing: _ecart,
                runSpacing: _ecart,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(width: contraintes.maxWidth, child: recherche),
                  statut,
                  du,
                  au,
                ],
              );
            },
          ),
          // `mt-2` — 8 px (l.595).
          const SizedBox(height: AppSpacing.xs),
          Text(
            TextesVentesCarte.bornesAide,
            style: styleContenuCarte(TaillesContenu.t11, couleur: Ardoise.c400),
          ),
        ],
      ),
    );
  }
}

/// Un `<input type="date">` — `text-[13px] border border-slate-300 rounded-lg
/// px-3 py-2` (l.584-585) : « jj/mm/aaaa » et l'icône du calendrier. Il ne
/// choisit aucune date : le toucher dit pourquoi.
class _ChampDate extends StatelessWidget {
  const _ChampDate({required this.cle, required this.onTap});

  final Key cle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: cle,
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      child: Container(
        width: AppLayout.champDateVentesCarte,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: AppColors.neutre0,
          borderRadius: BorderRadius.circular(AppRadius.roundedLg),
          border: Border.all(color: Ardoise.c300),
        ),
        child: SizedBox(
          // Une ligne de texte, comme la liste voisine.
          height: TaillesContenu.t13 * 1.5,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'jj/mm/aaaa',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: styleContenuCarte(
                    TaillesContenu.t13,
                    couleur: Ardoise.c700,
                  ),
                ),
              ),
              const Icon(
                Icons.calendar_today_outlined,
                size: AppLayout.iconeChamp,
                color: Ardoise.c500,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
