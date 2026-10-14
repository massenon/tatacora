// Vue Blade maîtresse (PA-183) : pwa/bar/carte.blade.php
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
// Le maître ne possède qu'UN fichier de carte pour M4 et M5 :
// `prototype_v2/pages/carte-module.js`, qui branche sur `EST_BAR` (l.67) et
// sert les deux pages. Son portage Flutter vit dans `features/restaurant/`
// parce que M4 a été livré le premier ; le réécrire ici en donnerait deux
// copies, et « deux listes décrivant la même chose divergeront — ce n'est
// qu'une question de temps » (Article 10). Les jetons de style, l'échelle
// typographique effective et le gabarit de tableau y sont déjà mesurés sur ce
// même fichier maître.
//
// ⚠ Le NOM de ces briques dit « Restaurant » alors qu'elles portent les deux
// modules. Les renommer touche les sept fichiers de M4 sans changer un pixel :
// l'arbitrage est ouvert, il n'est pas tranché ici en silence.
import '../../../restaurant/presentation/widgets/coquille_restaurant.dart';
import '../../../restaurant/presentation/widgets/tableau_restaurant.dart';
import '../../domain/entities/carte_bar.dart';

/// L'onglet **« Couverture du stock »** de la carte du bar —
/// `pwa/carte/corps.blade.php` l.448-527.
///
/// ## Les sept colonnes sont MESURÉES depuis le 11/09/2026 (PA-200)
///
/// Cinq d'entre elles étaient rendues vides et nommées : « Liés au stock »,
/// « Sans lien » et « Couverture » parce que le lien est obligatoire au bar
/// (donc constant), « Indisponibles » et « Prix provisoires » faute de donnée.
/// La vue les affiche, et le client Flutter suit la vue (PA-182) ; retraits
/// et prix provisoires sont rendus par l'API depuis PA-191 et PA-199. Un
/// chiffre constant reste vrai : « 6 / 6 » dit qu'aucune boisson n'échappe au
/// stock, ce qui est exactement ce que cet onglet sert à vérifier.
///
/// Les couleurs sont celles de la vue (l.480-493) : liens en émeraude, sans
/// lien et indisponibles en ambre, provisoires en rouge semi-gras, zéro en
/// gris ; « Indisponibles » et « Prix provisoires » écrivent « — » pour zéro,
/// comme la vue (`?: TIRET`) ; la ligne TOTAL écrit ses nombres tels quels.
///
/// La carte est comptée SANS FILTRE (vue et maître, l.150), et sans attendre
/// le réseau : la réponse serveur l'enrichit si elle est déjà là.
class VueCouvertureBar extends StatelessWidget {
  const VueCouvertureBar({super.key, required this.couverture});

  final List<CouvertureCategorieBar> couverture;

  /// Les sept colonnes de la vue (l.465-472), dans son ordre et avec ses mots.
  static const colonnes = [
    ColonneRestaurant('Catégorie'),
    ColonneRestaurant('Articles', aDroite: true),
    ColonneRestaurant('Liés au stock', aDroite: true),
    ColonneRestaurant('Sans lien', aDroite: true),
    ColonneRestaurant('Couverture', aDroite: true),
    ColonneRestaurant('Indisponibles', aDroite: true),
    ColonneRestaurant('Prix provisoires', aDroite: true),
  ];

  @override
  Widget build(BuildContext context) {
    final total = CouvertureCategorieBar.total(couverture);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        CadreTableauRestaurant(
          // `couverture_titre`, au mot.
          titre: 'Couverture du lien au stock, catégorie par catégorie',
          corps: TableauRestaurant(
            gabarit: GabaritTableau.carte,
            colonnes: colonnes,
            clesLignes: [
              for (final c in couverture)
                Key(
                  'couverture-bar-${c.categorie.isEmpty ? 'sans' : c.categorie}',
                ),
            ],
            lignes: [
              for (final c in couverture)
                [
                  Text(c.libelle, style: TextesRestaurant.corpsFort),
                  Text('${c.articles}', style: TextesRestaurant.corps),
                  _Compte(
                    '${c.lies}',
                    couleur: c.lies > 0 ? PaletteMaitre.emeraude700 : null,
                    fort: true,
                  ),
                  _Compte(
                    '${c.sansLien}',
                    couleur: c.sansLien > 0 ? PaletteMaitre.ambre600 : null,
                  ),
                  _Taux(taux: c.taux, lisible: c.tauxLisible),
                  _Compte(
                    c.indisponibles > 0 ? '${c.indisponibles}' : '—',
                    couleur: c.indisponibles > 0
                        ? PaletteMaitre.ambre600
                        : null,
                  ),
                  _Compte(
                    c.provisoires > 0 ? '${c.provisoires}' : '—',
                    couleur: c.provisoires > 0 ? PaletteMaitre.rouge600 : null,
                    fort: c.provisoires > 0,
                  ),
                ],
            ],
            // La ligne TOTAL de la vue (l.499-507) — ses nombres tels quels.
            ligneTotal: couverture.isEmpty
                ? null
                : [
                    const Text('TOTAL', style: TextesRestaurant.titreCadre),
                    _Total('${total.articles}'),
                    _Total('${total.lies}'),
                    _Total('${total.sansLien}'),
                    _Total('${total.tauxLisible} %'),
                    _Total('${total.indisponibles}'),
                    _Total('${total.provisoires}'),
                  ],
            // Un tableau vide DIT pourquoi (Article 7). Ici la cause est
            // connue et actionnable : le catalogue vendable descend du serveur
            // (PA-129), et sans lui le comptoir n'a rien à vendre non plus.
            vide: const NoteRestaurant(
              cle: Key('couverture-bar-catalogue-vide'),
              texte:
                  'Aucune boisson n’est enregistrée sur ce poste. La carte '
                  'descend du serveur : lancez une synchronisation dès que la '
                  'liaison revient. Tant qu’elle est vide, le point de vente '
                  'n’a rien à vendre non plus.',
              icone: Icons.help_outline,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _Conclusion(sansLien: total.sansLien),
      ],
    );
  }
}

/// Le pavé de conclusion — la vue, l.513-527 : un avertissement ambre quand
/// des articles ne décrémentent rien, sinon « Couverture complète. »
/// « Chaque vente décrémente le stock correspondant » est vrai du système —
/// le décrément a lieu au SERVEUR, à la vente.
class _Conclusion extends StatelessWidget {
  const _Conclusion({required this.sansLien});

  final int sansLien;

  @override
  Widget build(BuildContext context) {
    if (sansLien > 0) {
      return EncadreRestaurant(
        cle: const Key('couverture-bar-dette'),
        ton: TonEncadre.ambre,
        // `couverture_dette_titre` / `couverture_dette_texte`.
        titre: '$sansLien article(s) ne décrémentent rien à la vente.',
        texte:
            "Chaque vente de ces articles laisse le stock inchangé. La valeur du stock affichée est surévaluée d'autant, et l'écart n'apparaîtra qu'à l'inventaire physique — au moment où il est le plus coûteux à expliquer.",
      );
    }
    return const EncadreRestaurant(
      cle: Key('couverture-bar-complete'),
      ton: TonEncadre.gris,
      // `couverture_complete_titre` / `couverture_complete_texte`.
      titre: 'Couverture complète.',
      texte: 'Chaque vente décrémente le stock correspondant.',
      // Phrase d'une ligne : titre et texte sont deux éléments de la vue
      // (voir `EncadreRestaurant.titreSepare`, 09/10/2026).
      titreSepare: true,
    );
  }
}

/// Un décompte de ligne — coloré s'il compte, gris (`text-slate-300`) sinon.
class _Compte extends StatelessWidget {
  const _Compte(this.texte, {this.couleur, this.fort = false});

  final String texte;
  final Color? couleur;
  final bool fort;

  @override
  Widget build(BuildContext context) => Text(
    texte,
    style: TextesRestaurant.corps.copyWith(
      color: couleur ?? Ardoise.c300,
      fontWeight: fort ? FontWeight.w600 : null,
    ),
  );
}

/// La colonne « Couverture » : la barre de la vue (l.482-489) — `w-24 h-2
/// rounded-full bg-slate-200`, remplie au taux, colorée par palier (≥ 80
/// émeraude, ≥ 40 or, sinon rouge), suivie du pourcentage.
class _Taux extends StatelessWidget {
  const _Taux({required this.taux, required this.lisible});

  final double taux;
  final String lisible;

  @override
  Widget build(BuildContext context) {
    final couleur = taux >= 80
        ? PaletteMaitre.emeraude600
        : taux >= 40
        ? AppColors.gold
        : PaletteMaitre.rouge600;

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.roundedFull),
          child: Container(
            // `w-24` — 96 px ; `h-2` — 8 px.
            width: AppLayout.barreCouverture,
            height: AppSpacing.xs,
            color: Ardoise.c200,
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: (taux / 100).clamp(0, 1),
              heightFactor: 1,
              child: ColoredBox(color: couleur),
            ),
          ),
        ),
        // `gap-2` — 8 px.
        const SizedBox(width: AppSpacing.xs),
        SizedBox(
          // `w-11` — 44 px.
          width: AppLayout.tauxCouverture,
          child: Text(
            '$lisible %',
            textAlign: TextAlign.right,
            style: TextesRestaurant.corps.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

/// Une cellule de la ligne TOTAL — `font-bold` (l.499).
class _Total extends StatelessWidget {
  const _Total(this.texte);

  final String texte;

  @override
  Widget build(BuildContext context) => Text(
    texte,
    style: TextesRestaurant.corps.copyWith(fontWeight: FontWeight.bold),
  );
}
