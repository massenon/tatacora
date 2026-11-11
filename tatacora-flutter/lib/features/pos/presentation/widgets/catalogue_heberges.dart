import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/format/formats.dart';
import '../../../../core/theme/app_breakpoints.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../restaurant/presentation/widgets/corps_carte_commun.dart'
    show styleContenuCarte;
import '../../domain/entities/article_vendable.dart';
import '../providers_pos.dart';

/// La colonne CATALOGUE du point de vente clients hébergés —
/// `heberges.blade.php` l.124-169.
///
/// Trois blocs, dans l'ordre de la vue : le champ de recherche (l.127), la
/// rangée de pastilles de catégorie (l.131-138), la grille des articles
/// (l.141-168).
///
/// ## Le filtre n'est pas la caisse (PA-79)
///
/// Chercher, changer de pastille : rien de cela n'atteint un panier. Le
/// catalogue ne reçoit qu'un rappel [onAjouter] ; c'est l'écran qui décide où
/// la ligne atterrit.
///
/// ## Aucun « Bar / Restaurant » ici, et c'est la vue qui le dit
///
/// Le maître ne pose aucun filtre de famille sur cette page (l.4-7 de
/// l'en-tête de la vue) : « le client a demandé Bar, Restaurant sur le même
/// panier ». Les pastilles sont des catégories, pas des caisses.
///
/// ## Ce que la vue rend et que cette colonne ne rend pas
///
/// - La mention `prestation_refusee` et la carte grisée d'une prestation
///   n'existent plus : depuis le 26/10/2026 (directive du PO), « Tourisme » et
///   « Location » ne sont plus PROPOSÉS à la sélection — le catalogue ne porte
///   que le bar et le restaurant ([modulesProposesAuPos]).
class CatalogueHeberges extends ConsumerStatefulWidget {
  const CatalogueHeberges({
    required this.actif,
    required this.onAjouter,
    super.key,
  });

  /// Vrai quand un séjour est sélectionné ET que le rôle peut vendre. Faux : les
  /// articles restent VISIBLES, simplement inertes (`@disabled(! $ajoutable)`,
  /// l.154) — les masquer laisserait croire qu'il n'y a rien à vendre.
  final bool actif;

  final void Function(ArticleVendable) onAjouter;

  /// `placeholder` du champ de recherche (`pos_pwa.heberges.rechercher`).
  static const String indicationRecherche =
      'Rechercher une consommation ou une prestation…';

  /// `pos_pwa.commun.catalogue_vide`.
  static const String catalogueVide =
      'Aucun article ne correspond à cette recherche.';

  /// `pos_pwa.heberges.tarif_manquant`.
  static const String tarifManquant = 'tarif manquant';

  @override
  ConsumerState<CatalogueHeberges> createState() => _CatalogueHebergesState();
}

class _CatalogueHebergesState extends ConsumerState<CatalogueHeberges> {
  late final TextEditingController _recherche;

  @override
  void initState() {
    super.initState();
    // Le terme garde sa valeur d'un montage à l'autre : le provider est
    // partagé avec le POS au comptant, et un champ vide devant un filtre actif
    // cacherait pourquoi la grille est réduite.
    _recherche = TextEditingController(text: ref.read(rechercheProvider));
  }

  @override
  void dispose() {
    _recherche.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<RayonCatalogue> rayons =
        ref.watch(rayonsProvider).value ?? const <RayonCatalogue>[];
    final categorie = ref.watch(categorieHebergesProvider);
    final articles = ref.watch(articlesHebergesProvider);

    // Une pastille par catégorie qui porte un article — OU qui est vide par
    // construction et le dit (leçon PA-90 : un rayon absent ne se distingue pas
    // d'un rayon vide). La vue ne pose que les premières (l.212-221).
    final pastilles = [
      CategorieHeberges.tout,
      for (final c in CategorieHeberges.values.skip(1))
        if (rayons.any(
          (r) =>
              c.accepte(r.module) &&
              (r.articles.isNotEmpty || r.indisponibiliteLocale != null),
        ))
          c,
    ];

    // Le motif d'un rayon vide PAR CONSTRUCTION ne se dit que sur SA pastille :
    // sous « Tout », la phrase de la vue (`catalogue_vide`) reste la bonne.
    final motifIndisponible = categorie == CategorieHeberges.tout
        ? null
        : rayons
              .where(
                (r) =>
                    categorie.accepte(r.module) &&
                    r.indisponibiliteLocale != null,
              )
              .map((r) => r.indisponibiliteLocale)
              .firstOrNull;

    return Container(
      color: Ardoise.c50.withValues(alpha: AppColors.opaciteFondDemi),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // `shrink-0 px-5 pt-4 pb-2 bg-white border-b border-slate-100`.
          Container(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.mdPlus,
              AppSpacing.md,
              AppSpacing.mdPlus,
              AppSpacing.xs,
            ),
            decoration: const BoxDecoration(
              color: AppColors.neutre0,
              border: Border(bottom: BorderSide(color: Ardoise.c100)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ChampRecherche(controleur: _recherche),
                // `mb-3`.
                const SizedBox(height: AppSpacing.sm),
                // `flex gap-1.5 overflow-x-auto pb-2`.
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Row(
                    children: [
                      for (var i = 0; i < pastilles.length; i++) ...[
                        if (i > 0) const SizedBox(width: AppSpacing.xxs),
                        _Pastille(
                          categorie: pastilles[i],
                          active: pastilles[i] == categorie,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          // `flex-1 overflow-y-auto px-5 py-4`.
          Expanded(
            child: articles.isEmpty
                ? SingleChildScrollView(
                    // `px-5 py-4` du conteneur + `py-16 text-center` du
                    // paragraphe (l.141-143) : EN HAUT, pas au milieu.
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.mdPlus,
                      vertical: AppSpacing.md + AppSpacingLarge.p16,
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: Text(
                        key: const Key('pos-catalogue-vide'),
                        // La raison d'un rayon vide PAR CONSTRUCTION passe
                        // avant la phrase générale : « aucun article ne
                        // correspond » dirait que la recherche est en cause.
                        motifIndisponible ?? CatalogueHeberges.catalogueVide,
                        textAlign: TextAlign.center,
                        style: styleContenuCarte(
                          TaillesContenu.t13,
                          couleur: Ardoise.c400,
                        ),
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.mdPlus,
                      vertical: AppSpacing.md,
                    ),
                    child: _Grille(
                      articles: articles,
                      actif: widget.actif,
                      onAjouter: widget.onAjouter,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// `w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2 bg-white
/// focus:border-[var(--gold)]` (l.127-129).
class _ChampRecherche extends ConsumerWidget {
  const _ChampRecherche({required this.controleur});

  final TextEditingController controleur;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    OutlineInputBorder bordure(Color couleur) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      borderSide: BorderSide(color: couleur),
    );

    return TextField(
      key: const Key('pos-recherche'),
      controller: controleur,
      onChanged: ref.read(rechercheProvider.notifier).definir,
      // 13 → 14 : la recherche du comptant (`text-[14px]`), rapport appliqué
      // au corps de cet écran sur consigne du PO (14/10/2026).
      style: styleContenuCarte(TaillesContenu.t14),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: AppColors.neutre0,
        hintText: CatalogueHeberges.indicationRecherche,
        hintStyle: styleContenuCarte(TaillesContenu.t14, couleur: Ardoise.c400),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        border: bordure(Ardoise.c300),
        enabledBorder: bordure(Ardoise.c300),
        focusedBorder: bordure(AppColors.gold),
      ),
    );
  }
}

/// `shrink-0 px-3.5 py-1.5 rounded-full text-[12px] font-semibold` (l.134) :
/// pleine navy quand elle est active, sinon blanche bordée.
class _Pastille extends ConsumerWidget {
  const _Pastille({required this.categorie, required this.active});

  final CategorieHeberges categorie;
  final bool active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      key: Key('pos-categorie-${categorie.name}'),
      borderRadius: BorderRadius.circular(AppRadius.roundedFull),
      onTap: () =>
          ref.read(categorieHebergesProvider.notifier).definir(categorie),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.smPlus,
          vertical: AppSpacing.xxs,
        ),
        decoration: BoxDecoration(
          color: active ? AppColors.navy : AppColors.neutre0,
          border: active ? null : Border.all(color: Ardoise.c300),
          borderRadius: BorderRadius.circular(AppRadius.roundedFull),
        ),
        child: Text(
          categorie.libelle,
          style: styleContenuCarte(
            TaillesContenu.t12,
            poids: FontWeight.w600,
            couleur: active ? AppColors.neutre0 : Ardoise.c600,
          ),
        ),
      ),
    );
  }
}

/// `grid grid-cols-2 md:grid-cols-3 2xl:grid-cols-4 gap-3` (l.145).
///
/// Les colonnes suivent la largeur de la FENÊTRE (`md:` et `2xl:` sont des
/// points de rupture d'écran), pas celle de la colonne : une colonne de 420 px
/// dans une fenêtre de 1 400 px garde trois colonnes, comme au maître.
class _Grille extends StatelessWidget {
  const _Grille({
    required this.articles,
    required this.actif,
    required this.onAjouter,
  });

  final List<ArticleVendable> articles;
  final bool actif;
  final void Function(ArticleVendable) onAjouter;

  /// Nombre de colonnes de la vue pour une largeur de fenêtre.
  static int colonnes(double largeurFenetre) {
    if (largeurFenetre >= AppBreakpoints.xxl) return 4;
    if (largeurFenetre >= AppBreakpoints.md) return 3;
    return 2;
  }

  @override
  Widget build(BuildContext context) {
    final nombre = colonnes(MediaQuery.sizeOf(context).width);

    return LayoutBuilder(
      builder: (context, contraintes) {
        final largeur =
            (contraintes.maxWidth - AppSpacing.sm * (nombre - 1)) / nombre;
        return Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final article in articles)
              SizedBox(
                width: largeur,
                child: _Carte(
                  article: article,
                  actif: actif,
                  onAjouter: onAjouter,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Une carte d'article (l.151-164) : `p-3 rounded-xl border`, nom, tarif,
/// famille. Non ajoutable : fond `slate-50`, opacité réduite, curseur interdit.
class _Carte extends StatelessWidget {
  const _Carte({
    required this.article,
    required this.actif,
    required this.onAjouter,
  });

  final ArticleVendable article;
  final bool actif;
  final void Function(ArticleVendable) onAjouter;

  @override
  Widget build(BuildContext context) {
    final tarifConnu = article.estVendable;
    final ajoutable = actif && tarifConnu;

    final carte = Material(
      color: ajoutable ? AppColors.neutre0 : Ardoise.c50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.roundedXl),
        side: const BorderSide(color: Ardoise.c200),
      ),
      child: InkWell(
        key: Key(
          'pos-article-${article.reference.module.code}:${article.reference.code}',
        ),
        borderRadius: BorderRadius.circular(AppRadius.roundedXl),
        onTap: ajoutable ? () => onAjouter(article) : null,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                article.libelle,
                // `leading-tight`. Nom 12 → 13 et tarif 12 → 15 : les tailles
                // de la carte du comptant (`text-[13px]`, `text-[15px]`),
                // consigne du PO du 14/10/2026 — la vue des hébergés pose
                // 12/12 (l.156-157).
                style: styleContenuCarte(
                  TaillesContenu.t13,
                  poids: FontWeight.w600,
                  couleur: AppColors.navy,
                ).copyWith(height: Tailles.interligneSerre),
              ),
              // `mt-1.5`.
              const SizedBox(height: AppSpacing.xxs),
              Text(
                tarifConnu
                    ? formaterFcfa(article.prix!)
                    : CatalogueHeberges.tarifManquant,
                style: styleContenuCarte(
                  TaillesContenu.t15,
                  poids: FontWeight.bold,
                  couleur: tarifConnu ? AppColors.gold : PaletteMaitre.rouge600,
                ),
              ),
              // `mt-0.5`.
              const SizedBox(height: AppSpacing.demi),
              Text(
                article.module.libelle,
                style: styleContenuCarte(
                  TaillesContenu.t10,
                  couleur: Ardoise.c400,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return ajoutable
        ? carte
        : Opacity(opacity: AppColors.opaciteArticleInactif, child: carte);
  }
}
