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
import '../vocabulaire_pos.dart';

/// Le catalogue — **l'affichage**, jamais la caisse.
///
/// ## Ce que ce widget ne fait pas, et c'est le point
///
/// Il ne touche à aucun panier. Changer de rayon, chercher, effacer la
/// recherche : rien de tout cela n'atteint le panier courant, qui vit en base
/// sous son propre identifiant.
///
/// C'est la correction structurelle du défaut PA-79 : tant que le poste de
/// caisse était choisi par ce même sélecteur, changer de filtre changeait de
/// caisse — donc vidait le panier —, et une addition mêlant bar et restaurant
/// devenait impossible. Le poste dit **où se trouve l'argent** ; le filtre dit
/// **ce qu'on regarde**.
class VueCatalogue extends ConsumerWidget {
  const VueCatalogue({
    required this.onAjouter,
    required this.vocabulaire,
    this.actif = true,
    super.key,
  });

  /// Les mots du point de vente qui affiche ce catalogue.
  ///
  /// **Obligatoire, et sans valeur par défaut** : les deux POS ont deux
  /// maîtres, et un défaut ferait porter au second le vocabulaire du premier
  /// sans que personne ne le voie — c'est exactement le défaut corrigé le
  /// 24/08/2026.
  final VocabulairePos vocabulaire;

  /// Appelé quand un article est choisi.
  final void Function(ArticleVendable) onAjouter;

  /// Faux quand aucun panier n'est ouvert : les articles restent **visibles**,
  /// simplement inertes. Les masquer laisserait croire qu'il n'y a rien à
  /// vendre.
  final bool actif;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rayons = ref.watch(rayonsProvider);
    final categorie = ref.watch(categorieComptantProvider);

    // Présentation alignée sur la vue le 14/10/2026 (NOUVELLE_INSTRUCTION1
    // §4, `pos/comptant.blade.php` l.218-315) : `flex-1 bg-slate-50/50` ; en
    // tête blanche `px-5 pt-4 pb-2 border-b border-slate-100` portant la
    // recherche, le sélecteur de famille (`Tout ▾`) et les pastilles de
    // catégorie ; puis la grille `px-5 py-4`.
    return Container(
      color: Ardoise.c50.withValues(alpha: AppColors.opaciteFondDemi),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
                // `flex flex-wrap gap-2 items-center mb-3`.
                Row(
                  children: [
                    Expanded(
                      child: _ChampRecherche(
                        indication: vocabulaire.indicationRecherche,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    const _SelecteurFamille(),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                // `flex gap-1.5 overflow-x-auto pb-2`.
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Row(
                    children: [
                      for (final (i, c) in categoriesAffichees(
                        ref.watch(articlesAffichesProvider),
                      ).indexed) ...[
                        if (i > 0) const SizedBox(width: AppSpacing.xxs),
                        _Pastille(
                          cle: Key('pos-categorie-${c ?? 'tout'}'),
                          libelle: c ?? 'Tout',
                          active: c == categorie,
                          onTap: () => ref
                              .read(categorieComptantProvider.notifier)
                              .definir(c),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: rayons.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
              data: (_) => _Grille(onAjouter: onAjouter, actif: actif),
            ),
          ),
        ],
      ),
    );
  }
}

/// La pastille « Tout » (`null`) puis les catégories des articles affichés,
/// dans leur ordre d'apparition — `rendreOnglets()` du maître (l.240-247).
List<String?> categoriesAffichees(List<ArticleVendable> articles) => [
  null,
  ...{
    for (final a in articles)
      if (a.categorie != null && a.categorie!.isNotEmpty) a.categorie!,
  },
];

/// La pastille de catégorie active du comptoir — un filtre d'AFFICHAGE, comme
/// [rayonAfficheProvider] : il ne touche à aucun panier (PA-79). `null` =
/// « Tout ».
final categorieComptantProvider =
    NotifierProvider<CategorieComptantNotifier, String?>(
      CategorieComptantNotifier.new,
    );

final class CategorieComptantNotifier extends Notifier<String?> {
  @override
  String? build() {
    // Changer de famille ramène à « Tout » : une catégorie d'une autre famille
    // viderait la grille sans dire pourquoi.
    ref.watch(rayonAfficheProvider);
    return null;
  }

  void definir(String? categorie) => state = categorie;
}

/// `w-full text-[14px] border border-slate-300 rounded-lg pl-9 pr-3 py-2.5
/// focus:border-[var(--gold)] bg-white`, loupe 16 px slate-400 à gauche
/// (l.221-226).
class _ChampRecherche extends ConsumerWidget {
  const _ChampRecherche({required this.indication});

  final String indication;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    OutlineInputBorder bordure(Color couleur) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      borderSide: BorderSide(color: couleur),
    );

    return TextField(
      key: const Key('pos-recherche'),
      onChanged: ref.read(rechercheProvider.notifier).definir,
      style: styleContenuCarte(TaillesContenu.t14),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: AppColors.neutre0,
        prefixIcon: const Icon(
          Icons.search,
          size: AppLayout.iconeChamp,
          color: Ardoise.c400,
        ),
        hintText: indication,
        hintStyle: styleContenuCarte(TaillesContenu.t14, couleur: Ardoise.c400),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xsPlus,
        ),
        border: bordure(Ardoise.c300),
        enabledBorder: bordure(Ardoise.c300),
        focusedBorder: bordure(AppColors.gold),
      ),
    );
  }
}

/// Le sélecteur de famille à droite de la recherche — `text-[13px] border
/// border-slate-300 rounded-lg px-3 py-2.5 bg-white font-medium` (l.230-236),
/// infobulle de la vue comprise. Il pilote [rayonAfficheProvider] : un filtre
/// d'affichage, jamais la caisse (PA-79).
///
/// ÉCART (14/10/2026) : la vue n'offre que « Bar » et « Restaurant » ; ce
/// poste liste ses rayons tels que le catalogue local les porte (y compris
/// Tourisme et Location, que la clôture au comptant refuse avec sa raison).
class _SelecteurFamille extends ConsumerWidget {
  const _SelecteurFamille();

  /// `pos_pwa.comptant.filtre_famille_aide`.
  static const String aide =
      'Filtre d\'affichage du catalogue — il ne change ni la caisse, ni le '
      'panier';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<RayonCatalogue> rayons =
        ref.watch(rayonsProvider).value ?? const <RayonCatalogue>[];
    final actif = ref.watch(rayonAfficheProvider);
    final style = styleContenuCarte(
      TaillesContenu.t13,
      poids: FontWeight.w500,
      couleur: AppColors.anthracite,
    );

    return Tooltip(
      message: aide,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.neutre0,
          border: Border.all(color: Ardoise.c300),
          borderRadius: BorderRadius.circular(AppRadius.roundedLg),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String?>(
            key: const Key('pos-famille'),
            value: actif,
            style: style,
            items: [
              DropdownMenuItem<String?>(
                key: const Key('pos-rayon-tout'),
                child: Text('Tout', style: style),
              ),
              for (final rayon in rayons)
                DropdownMenuItem<String?>(
                  key: Key('pos-rayon-${rayon.module.code}'),
                  value: rayon.module.code,
                  child: Text(rayon.libelle, style: style),
                ),
            ],
            onChanged: (code) =>
                ref.read(rayonAfficheProvider.notifier).definir(code),
          ),
        ),
      ),
    );
  }
}

/// `shrink-0 px-3.5 py-1.5 rounded-full text-[12px] font-semibold` (l.243) :
/// pleine navy quand elle est active, sinon blanche bordée slate-300.
class _Pastille extends StatelessWidget {
  const _Pastille({
    required this.cle,
    required this.libelle,
    required this.active,
    required this.onTap,
  });

  final Key cle;
  final String libelle;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: cle,
      borderRadius: BorderRadius.circular(AppRadius.roundedFull),
      onTap: onTap,
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
          libelle,
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

class _Grille extends ConsumerWidget {
  const _Grille({required this.onAjouter, required this.actif});

  final void Function(ArticleVendable) onAjouter;
  final bool actif;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categorie = ref.watch(categorieComptantProvider);
    final articles = ref
        .watch(articlesAffichesProvider)
        .where((a) => categorie == null || a.categorie == categorie)
        .toList(growable: false);
    final rayonActif = ref.watch(rayonAfficheProvider);
    final List<RayonCatalogue> rayons =
        ref.watch(rayonsProvider).value ?? const <RayonCatalogue>[];

    // Un rayon vide **par construction** dit pourquoi. Un onglet qui ne rend
    // jamais rien passe pour cassé (leçon PA-90) — et ici la raison est réelle :
    // la carte du restaurant n'est pas répliquée sur ce poste.
    final motifIndisponible = rayonActif == null
        ? null
        : rayons
              .where((RayonCatalogue r) => r.module.code == rayonActif)
              .map((RayonCatalogue r) => r.indisponibiliteLocale)
              .firstOrNull;

    if (articles.isEmpty) {
      // `py-16 text-center text-[13px] text-slate-400` (l.252), EN HAUT de la
      // zone (`px-5 py-4`), comme le bloc de flux de la vue.
      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.mdPlus,
          vertical: AppSpacing.md + AppSpacingLarge.p16,
        ),
        child: SizedBox(
          width: double.infinity,
          child: Text(
            key: const Key('pos-catalogue-vide'),
            motifIndisponible ??
                'Aucun article ne correspond à cette recherche.',
            textAlign: TextAlign.center,
            style: styleContenuCarte(TaillesContenu.t13, couleur: Ardoise.c400),
          ),
        ),
      );
    }

    // `grid grid-cols-2 md:grid-cols-3 xl:grid-cols-4 gap-2.5` (l.254) : les
    // colonnes suivent la largeur de la FENÊTRE (points de rupture d'écran),
    // les cartes leur hauteur naturelle — plus de cellule figée à 124 px.
    final largeurFenetre = MediaQuery.sizeOf(context).width;
    final nombre = largeurFenetre >= AppBreakpoints.xl
        ? 4
        : largeurFenetre >= AppBreakpoints.md
        ? 3
        : 2;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.mdPlus,
        vertical: AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, contraintes) {
              final largeur =
                  (contraintes.maxWidth - AppSpacing.xsPlus * (nombre - 1)) /
                  nombre;
              return Wrap(
                spacing: AppSpacing.xsPlus,
                runSpacing: AppSpacing.xsPlus,
                children: [
                  for (final article in articles)
                    SizedBox(
                      width: largeur,
                      child: _Carte(
                        article: article,
                        onAjouter: onAjouter,
                        actif: actif,
                      ),
                    ),
                ],
              );
            },
          ),
          const _LegendesCatalogue(),
        ],
      ),
    );
  }
}

class _Carte extends StatelessWidget {
  const _Carte({
    required this.article,
    required this.onAjouter,
    required this.actif,
  });

  final ArticleVendable article;
  final void Function(ArticleVendable) onAjouter;
  final bool actif;

  @override
  Widget build(BuildContext context) {
    // Un article invendable reste VISIBLE, grisé. Le masquer laisserait croire
    // qu'il n'est pas à la carte, alors que c'est son tarif qui manque — et
    // c'est cela qu'il faut corriger.
    final cliquable = actif && article.estVendable;

    // La ligne discrète de la vue : `famille · catégorie` (l.285-293). Le
    // stock de la vue n'est pas porté (aucun stock vendable lu ici) ; la
    // précision du catalogue local (« par jour », zone) prend sa place.
    final sousTexte = [
      article.module.libelle,
      if (article.categorie != null && article.categorie!.isNotEmpty)
        article.categorie!,
      // Le point orange dit déjà « fiche technique absente » : ne pas le doubler
      // d'une phrase que la vue n'écrit pas.
      if (!article.sansLienStock &&
          article.detail != null &&
          article.detail!.isNotEmpty)
        article.detail!,
    ].join(' · ');

    // `text-left p-3 rounded-xl border` (l.263) : blanche bordée slate-200,
    // ou `bg-slate-50 opacity-60` quand elle n'est pas cliquable.
    final carte = Material(
      color: cliquable ? AppColors.neutre0 : Ardoise.c50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.roundedXl),
        side: const BorderSide(color: Ardoise.c200),
      ),
      child: InkWell(
        key: Key('pos-article-${article.reference}'),
        borderRadius: BorderRadius.circular(AppRadius.roundedXl),
        onTap: cliquable ? () => onAjouter(article) : null,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // `flex items-start justify-between gap-1.5` : le libellé, puis —
              // à droite — le point orange OU la marque « P » (jamais les deux).
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    // `text-[13px] font-semibold leading-snug` navy.
                    child: Text(
                      article.libelle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: styleContenuCarte(
                        TaillesContenu.t13,
                        poids: FontWeight.w600,
                        couleur: AppColors.navy,
                      ).copyWith(height: Tailles.interligneSnug),
                    ),
                  ),
                  if (article.estVendable && article.sansLienStock) ...[
                    const SizedBox(width: AppSpacing.xxs),
                    const Tooltip(
                      // `point_orange_infobulle`.
                      message:
                          'Vendable, mais ne décrémente aucun stock — fiche technique absente',
                      child: PointOrangeCatalogue(
                        key: Key('pos-point-orange'),
                        decalage: true,
                      ),
                    ),
                  ] else if (article.estVendable &&
                      article.compositionProvisoire) ...[
                    const SizedBox(width: AppSpacing.xxs),
                    const Tooltip(
                      // `composition_provisoire_infobulle`.
                      message:
                          'Fiche technique provisoire : le stock décrémenté par ce plat est approximatif — ses quantités ont été posées, jamais pesées.',
                      child: MarqueProvisoireCatalogue(
                        key: Key('pos-marque-provisoire'),
                      ),
                    ),
                  ],
                ],
              ),
              // `mt-2 text-[15px] font-bold` or — « Prix à définir » sans
              // tarif (`pos_pwa.commun.prix_a_definir`).
              const SizedBox(height: AppSpacing.xs),
              Text(
                article.estVendable
                    ? formaterFcfa(article.prix!)
                    : 'Prix à définir',
                style: styleContenuCarte(
                  TaillesContenu.t15,
                  poids: FontWeight.bold,
                  couleur: article.estVendable
                      ? AppColors.gold
                      : PaletteMaitre.rouge600,
                ),
              ),
              // `text-[10px] text-slate-400 mt-0.5`.
              const SizedBox(height: AppSpacing.demi),
              Text(
                sousTexte,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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

    return cliquable
        ? carte
        : Opacity(opacity: AppColors.opaciteArticleInactif, child: carte);
  }
}

/// Le point orange de la vue — `w-1.5 h-1.5 rounded-full bg-amber-400`
/// (`mt-1.5` sur la carte, aucun décalage dans la légende).
class PointOrangeCatalogue extends StatelessWidget {
  const PointOrangeCatalogue({super.key, this.decalage = false});

  final bool decalage;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(top: decalage ? AppSpacing.xxs : 0),
    child: Container(
      width: LargeursPos.pointOrange,
      height: LargeursPos.pointOrange,
      decoration: const BoxDecoration(
        color: PaletteMaitre.ambre400,
        shape: BoxShape.circle,
      ),
    ),
  );
}

/// La marque « P » des compositions posées — `text-[9px] leading-none font-bold
/// px-1 py-0.5 rounded`, fond `#FDF3E0`, texte `#B8891E`. Une LETTRE, pas un
/// point : deux points de couleurs voisines à la même place seraient
/// indiscernables au comptoir.
class MarqueProvisoireCatalogue extends StatelessWidget {
  const MarqueProvisoireCatalogue({super.key});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.unit,
      vertical: AppSpacing.demi,
    ),
    decoration: BoxDecoration(
      color: AppColors.reserveGoldFond,
      borderRadius: BorderRadius.circular(AppRadius.rounded),
    ),
    child: Text(
      // `composition_provisoire_marque`.
      'P',
      style: styleContenuCarte(
        TaillesContenu.t9,
        poids: FontWeight.bold,
        couleur: AppColors.reserveGoldTexte,
      ).copyWith(height: Tailles.interligneAucun),
    ),
  );
}

/// Les trois lignes sous la grille (l.281-312) : la légende du point orange,
/// celle de la marque « P », puis l'écart daté sur le prix provisoire.
class _LegendesCatalogue extends StatelessWidget {
  const _LegendesCatalogue();

  @override
  Widget build(BuildContext context) {
    final style = styleContenuCarte(TaillesContenu.t11, couleur: Ardoise.c400);
    return Padding(
      // `mt-4`.
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            key: const Key('pos-legende-point-orange'),
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const PointOrangeCatalogue(),
              const SizedBox(width: AppSpacing.xxs),
              Expanded(
                child: Text(
                  // `point_orange_legende`.
                  'Point orange : article vendable qui ne décrémente aucun stock, faute de fiche technique.',
                  style: style,
                ),
              ),
            ],
          ),
          // `mt-1.5`.
          const SizedBox(height: AppSpacing.xxs),
          Row(
            key: const Key('pos-legende-marque-p'),
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const MarqueProvisoireCatalogue(),
              const SizedBox(width: AppSpacing.xxs),
              Expanded(
                child: Text(
                  // `composition_provisoire_legende`.
                  'Marque P : la fiche technique du plat est provisoire, le stock décrémenté est approximatif. Elle se lève depuis Restaurant & Cuisine, onglet « Fiches techniques ».',
                  style: style,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            key: const Key('pos-legende-sans-prix-provisoire'),
            // ÉCART NOMMÉ — la vue d'encaissement écrit, sous ses légendes
            // (`sans_prix_provisoire`, « écart déclaré et daté » du 31/08/2026) :
            // « Aucun prix n’est signalé comme provisoire : le schéma ne porte pas cette information (31/08/2026). »
            // C'est FAUSSE depuis PA-161 (b) : `plats.prix_provisoire` existe au
            // serveur comme dans `plats_local`, et la carte du restaurant rend
            // la marque. Phrase VRAIE affichée, au plus près des mots de la
            // vue ; vue à faire corriger (ticket au Lead). Cette citation est un
            // gain de MESURE, pas un rendu.
            'Aucun prix n’est signalé comme provisoire à la caisse : la marque « prix provisoire » se lit sur la carte du restaurant et sur la fiche des prix.',
            style: style,
          ),
        ],
      ),
    );
  }
}
