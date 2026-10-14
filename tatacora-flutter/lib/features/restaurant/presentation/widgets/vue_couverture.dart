import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/entities/carte_restaurant.dart';
import '../../../../core/theme/app_text_styles.dart';
import 'coquille_restaurant.dart';
import 'corps_carte_commun.dart';
import 'tableau_restaurant.dart';

/// L'onglet **« Couverture du stock »** — `carte-module.js` l.139-188.
///
/// ## Pourquoi cet onglet est rendu ici, et ce qu'il en est du bar
///
/// L'écran jumeau du bar le refusait au motif que « M6 est le seul des quatorze
/// modules sans aucune route API ». **Ce motif avait cessé d'être vrai** : M6
/// en compte neuf depuis le 26/08/2026, et surtout `GET /restaurant/carte` rend
/// `couverture` catégorie par catégorie, du même parcours que les lignes — il
/// n'y a rien à inventer.
///
/// Un motif de refus périmé transforme une décision en oubli (PA-144) : la
/// raison a donc été **vérifiée** avant d'être écartée, pas recopiée. Le bar a
/// été rouvert et son onglet porté le même jour (`VueCouvertureBar`), mais ses
/// colonnes de lien restent vides pour une raison **structurelle** :
/// `cartes_boisson.article_id` est NOT NULL, là où un plat peut réellement
/// n'avoir aucune recette chiffrée. Les deux écrans ne mesurent donc pas la
/// même chose, et c'est le schéma qui les sépare — pas l'état d'avancement.
///
/// ## Deux colonnes du maître restent sans chiffre
///
/// « Indisponibles » et « Prix provisoires » ne sont portées par aucune colonne
/// du schéma. La vue écrit elle-même `$cat['indisponibles'] ?: TIRET`
/// (l.498) — elle rend déjà un tiret sur zéro. Ici le tiret dit autre chose :
/// non pas « aucun », mais « on ne sait pas ». Les colonnes restent en place.
/// Le panneau « Ce que cet écran ne rend pas », qui portait la distinction,
/// est retiré le 09/10/2026 : la vue n'a aucun bloc de ce genre.
class VueCouverture extends StatelessWidget {
  const VueCouverture({
    super.key,
    required this.couverture,
    required this.indicateurs,
  });

  final List<CouvertureCategorie> couverture;
  final IndicateursCarte indicateurs;

  /// Les colonnes du maître (l.176), dans son ordre.
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CadreTableauRestaurant(
          // Le titre de la vue (`couverture_titre`, l.466), au mot.
          titre: 'Couverture du lien au stock, catégorie par catégorie',
          corps: TableauRestaurant(
            gabarit: GabaritTableau.carteVue,
            pleineLargeur: true,
            colonnes: colonnes,
            clesLignes: [
              for (final c in couverture)
                Key('couverture-restaurant-${c.categorieBrute}'),
            ],
            lignes: [
              for (final c in couverture)
                [
                  Text(c.categorieLibelle, style: TextesRestaurant.corpsFort),
                  Text('${c.plats}', style: TextesRestaurant.corps),
                  Text(
                    '${c.lies}',
                    style: TextesRestaurant.corps.copyWith(
                      fontWeight: FontWeight.w600,
                      color: c.lies > 0
                          ? PaletteMaitre.emeraude700
                          : Ardoise.c300,
                    ),
                  ),
                  Text(
                    '${c.sansLien}',
                    style: TextesRestaurant.corps.copyWith(
                      color: c.sansLien > 0
                          ? PaletteMaitre.ambre600
                          : Ardoise.c300,
                    ),
                  ),
                  _BarreCouverture(taux: c.tauxNumerique, texte: c.taux),
                  const _SansChiffre(),
                  const _SansChiffre(),
                ],
            ],
            // La ligne TOTAL du maître (l.181-186), sur la carte ENTIÈRE.
            ligneTotal: [
              // `px-3 py-2.5` + `style="color:var(--navy)"` sous un `<tr
              // font-bold>` (l.507-508) : 13 px gras, et non les 14 px d'un
              // titre de cadre.
              Text(
                'TOTAL',
                style: TextesRestaurant.corps.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.navy,
                ),
              ),
              _Total('${indicateurs.plats}'),
              _Total('${indicateurs.lies}'),
              _Total('${indicateurs.sansLien}'),
              _Total(
                '${indicateurs.tauxCouverture ?? CarteIndicateurRestaurant.absent} %',
              ),
              const _SansChiffre(),
              const _SansChiffre(),
            ],
          ),
        ),
        // `mb-3` du cadre (l.464).
        const SizedBox(height: AppSpacing.sm),
        // Le pavé de conclusion de la vue (l.521-535), au mot, dans ses deux
        // variantes — `rounded-xl p-3.5 mb-4`. Les apostrophes sont DROITES,
        // comme dans la vue : une apostrophe typographique ne s'y retrouve pas.
        if (indicateurs.sansLien > 0)
          _Conclusion(
            cle: const Key('couverture-restaurant-avertissement'),
            ton: TonEncadre.ambre,
            titre:
                '${indicateurs.sansLien} article(s) ne décrémentent rien à la vente.',
            texte:
                "Chaque vente de ces articles laisse le stock inchangé. La valeur du stock affichée est surévaluée d'autant, et l'écart n'apparaîtra qu'à l'inventaire physique — au moment où il est le plus coûteux à expliquer.",
          )
        else
          const _Conclusion(
            cle: Key('couverture-restaurant-complete'),
            ton: TonEncadre.gris,
            titre: 'Couverture complète.',
            texte: 'Chaque vente décrémente le stock correspondant.',
            // Une phrase d'une ligne : le titre et le texte sont deux
            // éléments de la vue, mesurés à part (voir [_Conclusion]).
            titreSepare: true,
          ),
      ],
    );
  }
}

/// Le pavé de conclusion : un titre en gras puis son texte, sur le fond du ton.
class _Conclusion extends StatelessWidget {
  const _Conclusion({
    required this.cle,
    required this.ton,
    required this.titre,
    required this.texte,
    this.titreSepare = false,
  });

  final Key cle;
  final TonEncadre ton;
  final String titre;
  final String texte;

  /// Vrai pour la variante COURTE, « Couverture complète. » : la vue l'écrit
  /// `<strong>…</strong> texte` dans un seul `<p>`, mais l'extraction de sa
  /// structure (et le relevé de géométrie du navigateur) la mesurent en deux
  /// éléments — le titre, puis le texte seul. Deux `Text` côte à côte, qui
  /// passent à la ligne ensemble, rendent la même image sur une ligne ET la
  /// même structure (09/10/2026, comme `EncadreRestaurant.titreSepare`).
  ///
  /// Faux pour la variante longue, l'avertissement ambre : ses 200 caractères
  /// tombent à la ligne, et un `Wrap` y rejetterait tout le texte sous le
  /// titre au lieu de l'enchaîner — l'image ne serait plus celle de la vue.
  final bool titreSepare;

  @override
  Widget build(BuildContext context) {
    final gras = styleContenuCarte(
      TaillesContenu.t13,
      poids: FontWeight.bold,
      couleur: ton.texte,
    );
    final normal = styleContenuCarte(TaillesContenu.t13, couleur: ton.texte);

    return KeyedSubtree(
      key: cle,
      child: EncadreCarte(
        fond: ton.fond,
        bordure: ton.bordure,
        enfant: titreSepare
            ? Wrap(
                // L'espace entre `</strong>` et le texte : ~4 px à 13 px.
                spacing: AppSpacing.unit,
                children: [
                  Text(titre, style: gras),
                  Text(texte, style: normal),
                ],
              )
            : Text.rich(
                TextSpan(
                  style: normal,
                  children: [
                    TextSpan(
                      text: '$titre ',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    TextSpan(text: texte),
                  ],
                ),
              ),
      ),
    );
  }
}

/// La barre de progression du maître — `w-24 h-2 rounded-full bg-slate-200`
/// avec un remplissage coloré par palier (l.168-173).
///
/// `null` = aucun taux : la barre est **vide et grise**, jamais à zéro. Une
/// barre à zéro affirmerait une couverture nulle qui n'a pas été mesurée.
class _BarreCouverture extends StatelessWidget {
  const _BarreCouverture({required this.taux, required this.texte});

  final double? taux;
  final String? texte;

  /// Les deux paliers du maître (l.170) : `>= 80` vert, `>= 40` doré, sinon
  /// rouge.
  static const double _vert = 80;
  static const double _dore = 40;

  @override
  Widget build(BuildContext context) {
    final t = taux;

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          width: AppLayout.barreCouverture,
          // `h-2` — 8 px.
          height: AppSpacing.xs,
          decoration: BoxDecoration(
            color: Ardoise.c200,
            borderRadius: BorderRadius.circular(AppRadius.roundedFull),
          ),
          child: t == null
              ? null
              : FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: (t / _cent).clamp(0, 1),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: t >= _vert
                          ? PaletteMaitre.emeraude600
                          : t >= _dore
                          ? AppColors.gold
                          : PaletteMaitre.rouge600,
                      borderRadius: BorderRadius.circular(
                        AppRadius.roundedFull,
                      ),
                    ),
                  ),
                ),
        ),
        const SizedBox(width: AppSpacing.xs),
        SizedBox(
          width: AppLayout.tauxCouverture,
          child: Text(
            '${texte ?? CarteIndicateurRestaurant.absent} %',
            textAlign: TextAlign.right,
            style: TextesRestaurant.secondaire.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  static const double _cent = 100;
}

/// Une cellule de la ligne TOTAL — `font-bold`.
class _Total extends StatelessWidget {
  const _Total(this.texte);

  final String texte;

  @override
  Widget build(BuildContext context) => Text(
    texte,
    style: TextesRestaurant.corps.copyWith(fontWeight: FontWeight.bold),
  );
}

/// Une colonne du maître qu'aucune donnée ne remplit.
///
/// « — » et non « 0 » : le maître rend déjà un tiret sur zéro
/// (`${c.indispo || '—'}`), mais ici il veut dire « on ne sait pas ». La
/// nuance est portée par le bloc « Ce que cet écran ne rend pas », pas par un
/// second glyphe qui n'existe nulle part au maître.
class _SansChiffre extends StatelessWidget {
  const _SansChiffre();

  @override
  Widget build(BuildContext context) => const Text(
    CarteIndicateurRestaurant.absent,
    style: TextesRestaurant.mention,
  );
}
