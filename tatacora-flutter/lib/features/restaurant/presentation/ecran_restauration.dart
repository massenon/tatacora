// Vue Blade maîtresse (PA-183) : pwa/restaurant/restauration.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/format/formats.dart';
import '../../../core/rbac/garde_acces.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared_widgets/bouton_standard.dart';
import '../../achats/presentation/widgets/composants_crud_achats.dart'
    show CaseSelectionAchats;
import '../../achats/presentation/widgets/modale_archivage_achats.dart';
import '../../bar/data/boissons_api.dart' show BarRecu, BarRefuse;
import '../../pos/data/dto/catalogue_dto.dart' show IndisponibiliteDistante;
import '../data/restaurant_api.dart';
import '../domain/entities/plat.dart';
import 'providers_restaurant.dart';
import 'widgets/coquille_restaurant.dart';
import 'widgets/modale_detail_plat.dart';
import 'widgets/modale_fiche.dart';
import 'widgets/modale_menu.dart';
import 'widgets/modale_plat.dart';
import 'widgets/tableau_restaurant.dart';

// ## Les TROIS onglets de la vue sont rendus, et LOCAUX (09/10/2026, schéma v14)
//
// Le catalogue des plats, les fiches techniques et les menus lisent la base de
// ce poste ([RestaurantApi] -> `RestaurantDao`). Sur un poste neuf les trois
// sont VIDES et le disent avec les mots de la vue : « Aucun résultat », puis la
// raison — jamais « donnée non disponible », qui affirmerait une panne là où il
// n'y a qu'une table vide. Les trois gestes d'écriture de la vue existent :
// « Nouveau menu », « Nouvelle fiche technique » (composition comprise) et
// « Nouveau plat ».
//
// Les cases de sélection, « Retirer de la carte » et la colonne « Disponible »
// sont rendues depuis le 21/10/2026 (v31) : la disponibilité du jour est lue de
// `indisponibilites_carte_local`, et « Retirer de la carte » écrit le motif
// `retire` par `RetraitsPlats` (même geste que la vue : le plat reste au
// catalogue, rien n'est effacé). La sélection ne porte aucun geste de groupe —
// la vue non plus : la suppression groupée y est interdite (RG-02), la case
// rend la sélection visible et le compteur « N sélectionné(s) » la dit.
//
// Ce que la vue porte et que cet écran ne rend pas, et pourquoi :
//  - la carte « Compositions provisoires » : « — », aucune source (la marque
//    « provisoire » d'une fiche n'a pas de colonne sur ce poste) ;
//
// Le champ « Catégorie » du formulaire de plat et la colonne / le filtre du
// catalogue sont PORTÉS depuis la v41 (27/10/2026, décision D1 du PO) : la
// catégorie est celle du PLAT (`plats.categorie`, dix valeurs), plus le type du
// menu ; l'arbitrage D100 est tranché.

/// Les trois onglets de la vue (`pwa/restaurant/restauration.blade.php`).
const _onglets = <(String, String)>[
  ('plats', 'Catalogue des plats'),
  ('fiches', 'Fiches techniques'),
  ('menus', 'Menus'),
];

class EcranRestauration extends ConsumerStatefulWidget {
  const EcranRestauration({super.key});

  @override
  ConsumerState<EcranRestauration> createState() => _EtatEcranRestauration();
}

class _EtatEcranRestauration extends ConsumerState<EcranRestauration> {
  String _onglet = 'plats';

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      // `max-w-[1440px] mx-auto p-5 lg:p-8` : 32 px au poste de travail.
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppLayout.maxContentWidth,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _EnTete(),
              Container(
                // `flex flex-wrap gap-1.5 mb-4`
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Wrap(
                  spacing: AppSpacing.xxs,
                  runSpacing: AppSpacing.xxs,
                  children: [
                    for (final (cle, libelle) in _onglets)
                      OngletRestaurant(
                        cle: Key('restauration-onglet-$cle'),
                        libelle: libelle,
                        actif: cle == _onglet,
                        onChoix: () => setState(() => _onglet = cle),
                      ),
                  ],
                ),
              ),
              switch (_onglet) {
                'fiches' => const _OngletFiches(),
                'menus' => const _OngletMenus(),
                _ => const _OngletPlats(),
              },
            ],
          ),
        ),
      ),
    );
  }
}

class _EnTete extends ConsumerWidget {
  const _EnTete();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.mdPlus), // mb-5
      child: EnTeteRestaurant(
        icone: const Icon(
          Icons.restaurant_outlined,
          color: AppColors.navy,
          size: AppLayout.iconeTitrePage,
        ),
        // `carte_pwa.restauration.titre`, au mot — esperluette comprise.
        titre: 'Restaurant & Cuisine',
        // `carte_pwa.restauration.sous_titre`, au mot.
        sousTitre:
            'Gestion des menus, fiches de recette et prise de commande, avec '
            'déduction automatique du stock cuisine',
        actions: [
          _BoutonEntete(
            cle: const Key('restauration-nouveau-menu'),
            libelle: 'Nouveau menu',
            onTap: () => ouvrirModaleMenu(context),
          ),
          _BoutonEntete(
            cle: const Key('restauration-nouvelle-fiche'),
            libelle: 'Nouvelle fiche technique',
            onTap: () => ouvrirModaleFiche(context),
          ),
          _BoutonEntete(
            cle: const Key('restauration-ajouter'),
            libelle: 'Nouveau plat',
            plein: true,
            onTap: () async {
              final enregistre = await ouvrirModalePlat(context);
              if (enregistre == true) ref.invalidate(platsProvider);
            },
          ),
        ],
      ),
    );
  }
}

/// `text-[13px] px-4 py-2 rounded-lg font-semibold`, contour ardoise ou fond
/// marine.
class _BoutonEntete extends StatelessWidget {
  const _BoutonEntete({
    required Key cle,
    required this.libelle,
    required this.onTap,
    this.plein = false,
  }) : super(key: cle);

  final String libelle;
  final VoidCallback onTap;
  final bool plein;

  /// Le bouton standard (PO, 14/10/2026), `px-4 py-2`. Écart nommé : le
  /// contour de la vue écrit son texte en navy semi-gras ; le standard le
  /// rend en ardoise normale, comme toutes les barres d'action.
  @override
  Widget build(BuildContext context) => BoutonStandard(
    libelle: libelle,
    variante: plein ? VarianteBouton.primaire : VarianteBouton.secondaire,
    margeHorizontale: AppSpacing.md,
    onPressed: onTap,
  );
}

/* ====================================================================== */
/* Onglet « Catalogue des plats »                                          */
/* ====================================================================== */

class _OngletPlats extends ConsumerWidget {
  const _OngletPlats();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resultat = ref.watch(platsProvider);
    final compteurs = ref.watch(compteursCatalogueProvider).value;
    final k = compteurs is RestaurantRecu<CompteursCatalogue>
        ? compteurs.donnees
        : null;
    // Les retraits en cours (`$indisponibilites->count()` de la vue). Tant que
    // la lecture n'est pas revenue : « — », jamais « 0 », qui se lirait « aucun
    // plat retiré ».
    final retires = ref.watch(platsRetiresProvider).value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Les quatre cartes de la vue, toutes COMPTÉES (un zéro y est une
        // mesure).
        _GrilleCartes(
          cartes: [
            ('Plats au catalogue', k?.total.toString(), null, null, null),
            (
              'Avec fiche technique',
              k == null ? null : '${k.avecFiche} / ${k.total}',
              PaletteMaitre.emeraude600,
              null,
              null,
            ),
            (
              'Sans fiche technique',
              k?.sansFiche.toString(),
              (k?.sansFiche ?? 0) > 0
                  ? PaletteMaitre.ambre600
                  : PaletteMaitre.emeraude600,
              null,
              null,
            ),
            (
              'Retirés de la carte',
              retires?.length.toString(),
              (retires?.length ?? 0) > 0
                  ? PaletteMaitre.ambre600
                  : Ardoise.c400,
              null,
              null,
            ),
          ],
          colonnes: 4,
          cles: 'restauration-kpi',
        ),
        const _BarreOutils(),
        resultat.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(AppSpacing.xl),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => NoteRestaurant(
            cle: const Key('restauration-erreur'),
            texte: '$e',
            icone: Icons.error_outline,
          ),
          data: (r) => switch (r) {
            RestaurantRecu<PageRestaurant<Plat>>(:final donnees) => _Tableau(
              page: donnees,
            ),
            RestaurantRefuse<PageRestaurant<Plat>>(:final motif) =>
              NoteRestaurant(
                cle: const Key('restauration-refus'),
                texte: motif,
                icone: Icons.lock_outline,
              ),
            // Jamais produite : une base locale n'est pas hors connexion.
            RestaurantInjoignable<PageRestaurant<Plat>>() =>
              const NoteRestaurant(
                cle: Key('restauration-hors-ligne'),
                texte: 'Le catalogue de plats n’a pas pu être lu.',
              ),
          },
        ),
      ],
    );
  }
}

/// `grid grid-cols-N gap-3 mb-5` de cartes `p-3.5`.
///
/// Chaque carte : son libellé, sa valeur (`null` = « — »), la couleur de sa
/// valeur, et — quand elle n'a AUCUNE source — la raison, en infobulle (une
/// ligne de plus déplacerait la mise en page de la vue).
class _GrilleCartes extends StatelessWidget {
  const _GrilleCartes({
    required this.cartes,
    required this.colonnes,
    required this.cles,
  });

  /// Libellé, valeur, couleur de la valeur, raison de l'absence, détail (la
  /// seconde ligne de la carte : `fiches_kpi_provisoires_detail`).
  final List<(String, String?, Color?, String?, String?)> cartes;
  final int colonnes;
  final String cles;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.mdPlus),
      child: LayoutBuilder(
        builder: (context, c) {
          final largeur =
              (c.maxWidth - (colonnes - 1) * AppSpacing.sm) / colonnes;
          return Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (var i = 0; i < cartes.length; i++)
                SizedBox(
                  width: largeur,
                  child: _avecRaison(
                    cartes[i].$4,
                    CarteIndicateurRestaurant(
                      cle: Key('$cles-$i'),
                      libelle: cartes[i].$1,
                      valeur: cartes[i].$2,
                      accent: cartes[i].$3,
                      detail: cartes[i].$5,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  static Widget _avecRaison(String? raison, Widget carte) =>
      raison == null ? carte : Tooltip(message: raison, child: carte);
}

/// La carte des filtres — `bg-white rounded-xl border p-3.5 mb-4`.
class _BarreOutils extends ConsumerStatefulWidget {
  const _BarreOutils();

  @override
  ConsumerState<_BarreOutils> createState() => _BarreOutilsState();
}

class _BarreOutilsState extends ConsumerState<_BarreOutils> {
  final _terme = TextEditingController();

  @override
  void dispose() {
    _terme.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _CarteFiltres(
      enfants: [
        Expanded(
          child: _ChampRecherche(
            cle: const Key('restauration-recherche'),
            controleur: _terme,
            // L'invite du maître — trois points, pas le caractère typographique.
            invite: 'Rechercher un plat...',
            onChanged: (v) {
              ref.read(rechercheRestaurationProvider.notifier).definir(v);
              ref.read(selectionPlatsProvider.notifier).vider();
              // `pageActuelle = 1` du maître : rester en page 4 après un filtre
              // qui n'en rend qu'une afficherait une page vide.
              ref.read(pageRestaurationProvider.notifier).premiere();
            },
          ),
        ),
        const SizedBox(width: AppSpacing.xsPlus), // gap-2.5
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.roundedLg),
            border: Border.all(color: AppColors.neutre300),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<CategorieCarte?>(
                key: const Key('restauration-filtre-categorie'),
                // Sans cela le champ impose 48 px de haut (`kMinInteractiveDimension`)
                // à une liste de 13 px : la carte de filtres grandit de 12 px.
                itemHeight: null,
                value: ref.watch(categorieRestaurationProvider),
                isDense: true,
                style: TextesRestaurant.petitCrud.copyWith(
                  fontSize: TaillesContenu.t13,
                  height: 1.5,
                ),
                items: [
                  // Le libellé de l'option vide EST celui du filtre de la vue.
                  const DropdownMenuItem<CategorieCarte?>(
                    child: Text('Toutes les catégories'),
                  ),
                  for (final c in CategorieCarte.values)
                    DropdownMenuItem<CategorieCarte?>(
                      value: c,
                      child: Text(c.libelle),
                    ),
                ],
                onChanged: (c) {
                  ref.read(categorieRestaurationProvider.notifier).definir(c);
                  ref.read(selectionPlatsProvider.notifier).vider();
                  ref.read(pageRestaurationProvider.notifier).premiere();
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CarteFiltres extends StatelessWidget {
  const _CarteFiltres({required this.enfants});

  final List<Widget> enfants;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md), // mb-4
      padding: const EdgeInsets.all(AppSpacing.smPlus), // p-3.5
      decoration: BoxDecoration(
        color: AppColors.neutre0,
        borderRadius: BorderRadius.circular(AppRadius.roundedXl),
        border: Border.all(color: AppColors.neutre200),
      ),
      child: Row(children: enfants),
    );
  }
}

/// `w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2`
class _ChampRecherche extends StatelessWidget {
  const _ChampRecherche({
    required Key cle,
    this.controleur,
    required this.invite,
    required this.onChanged,
  }) : super(key: cle);

  final TextEditingController? controleur;
  final String invite;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final bordure = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      borderSide: const BorderSide(color: AppColors.neutre300),
    );
    return TextField(
      controller: controleur,
      style: TextesRestaurant.corpsCrud.copyWith(
        fontSize: TaillesContenu.t13,
        height: 1.5,
      ),
      decoration: InputDecoration(
        hintText: invite,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        border: bordure,
        enabledBorder: bordure,
        focusedBorder: bordure.copyWith(
          borderSide: const BorderSide(color: AppColors.gold),
        ),
      ),
      onChanged: onChanged,
    );
  }
}

/* ====================================================================== */
/* Onglet « Fiches techniques »                                            */
/* ====================================================================== */

/// L'onglet des fiches — LOCAL (09/10/2026) : la liste, ses coûts matière dans
/// leurs trois états, ses états (vide, composée, composée SANS suivi) et le
/// filtre qui rend le blocage praticable.
///
/// Une fiche sans ingrédient ne décrémente rien : sur 80 fiches, les repérer à
/// l'œil est impraticable, et « fiches vides seulement » les isole. Le coût d'une
/// fiche n'est JAMAIS « 0 F » : « non calculable » (composition vide) et
/// « incomplet » (un ingrédient jamais réceptionné, nommé en infobulle) sont deux
/// états distincts d'un montant.
class _OngletFiches extends ConsumerStatefulWidget {
  const _OngletFiches();

  @override
  ConsumerState<_OngletFiches> createState() => _OngletFichesState();
}

class _OngletFichesState extends ConsumerState<_OngletFiches> {
  final _terme = TextEditingController();

  @override
  void dispose() {
    _terme.dispose();
    super.dispose();
  }

  static const _colonnes = [
    // `$entete(..., true)` : « Fiche technique » et « Plat servi » à gauche.
    ColonneRestaurant('Fiche technique'),
    ColonneRestaurant('Plat servi'),
    ColonneRestaurant('Ingrédients', aDroite: true),
    ColonneRestaurant('Coût matière', aDroite: true),
    ColonneRestaurant('État', aDroite: true),
    // La dernière colonne de la vue n'a pas de titre (`<th></th>`).
    ColonneRestaurant('', aDroite: true),
  ];

  @override
  Widget build(BuildContext context) {
    final resultat = ref.watch(fichesProvider);
    final compteurs = ref.watch(compteursFichesProvider).value;
    final k = compteurs is RestaurantRecu<CompteursFiches>
        ? compteurs.donnees
        : null;
    final videsSeulement = ref.watch(videsSeulementProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md), // mb-4
          child: Text(
            // `fiches_bandeau`, au mot — en UN littéral : le comparateur ne
            // recolle pas deux morceaux.
            "Une fiche sans ingrédient ne décrémente aucun stock : le plat qui l'utilise se vend quand même, sans sortie de stock. Ouvrez la fiche, posez ses articles de stock et leurs quantités par portion pour que la vente décrémente : le coût matière se calcule tout seul.",
            style: TextesRestaurant.petitCrud.copyWith(
              fontSize: TaillesContenu.t13,
              height: 1.5,
              color: AppColors.neutre500,
            ),
          ),
        ),
        _GrilleCartes(
          cartes: [
            ('Fiches techniques', k?.total.toString(), null, null, null),
            // Décision du PO du 30/10/2026 (« le stock s'ajoute après ») : la vue
            // (`fiches_kpi_vides`) colorait ce compteur en ROUGE dès qu'il restait une
            // fiche vide, parce qu'une fiche vide était une vente refusée au comptoir.
            // Le refus est levé : le compteur reste un repère de saisie, en gris neutre.
            (
              'Fiches vides — sans sortie de stock',
              k?.vides.toString(),
              AppColors.neutre600,
              null,
              null,
            ),
            // `fiches_kpi_provisoires` : les fiches dont la composition a été
            // posée, jamais pesée — comptées de `recettes.composition_provisoire`.
            (
              'Compositions provisoires',
              k?.provisoires.toString(),
              (k?.provisoires ?? 0) > 0
                  ? PaletteMaitre.ambre600
                  : PaletteMaitre.emeraude600,
              null,
              'Quantités posées, jamais pesées',
            ),
          ],
          colonnes: 3,
          cles: 'restauration-fiches-kpi',
        ),
        _CarteFiltres(
          enfants: [
            Expanded(
              child: _ChampRecherche(
                cle: const Key('restauration-fiches-recherche'),
                controleur: _terme,
                invite: 'Rechercher une fiche technique...',
                onChanged: (v) {
                  ref.read(rechercheFichesProvider.notifier).definir(v);
                  ref.read(pageFichesProvider.notifier).premiere();
                },
              ),
            ),
            const SizedBox(width: AppSpacing.xsPlus),
            InkWell(
              key: const Key('restauration-fiches-vides'),
              onTap: () {
                ref
                    .read(videsSeulementProvider.notifier)
                    .definir(!videsSeulement);
                ref.read(pageFichesProvider.notifier).premiere();
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    value: videsSeulement,
                    onChanged: (v) {
                      ref
                          .read(videsSeulementProvider.notifier)
                          .definir(v ?? false);
                      ref.read(pageFichesProvider.notifier).premiere();
                    },
                  ),
                  Text(
                    'Fiches vides seulement',
                    style: TextesRestaurant.petitCrud.copyWith(
                      fontSize: TaillesContenu.t13,
                      height: 1.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.neutre700,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    'Ces plats se vendent au comptoir, sans sortie de stock.',
                    style: TextesRestaurant.mention.copyWith(
                      fontSize: TaillesContenu.t11,
                      color: AppColors.neutre400,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        resultat.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(AppSpacing.xl),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => NoteRestaurant(
            cle: const Key('restauration-fiches-erreur'),
            texte: '$e',
            icone: Icons.error_outline,
          ),
          data: (r) => switch (r) {
            RestaurantRecu<PageRestaurant<Recette>>(:final donnees) =>
              _TableauFiches(page: donnees, colonnes: _colonnes),
            RestaurantRefuse<PageRestaurant<Recette>>(:final motif) =>
              NoteRestaurant(
                cle: const Key('restauration-fiches-refus'),
                texte: motif,
                icone: Icons.lock_outline,
              ),
            RestaurantInjoignable<PageRestaurant<Recette>>() =>
              const NoteRestaurant(
                cle: Key('restauration-fiches-hors-ligne'),
                texte: 'Les fiches techniques n’ont pas pu être lues.',
              ),
          },
        ),
      ],
    );
  }
}

class _TableauFiches extends ConsumerWidget {
  const _TableauFiches({required this.page, required this.colonnes});

  final PageRestaurant<Recette> page;
  final List<ColonneRestaurant> colonnes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CadreTableauRestaurant(
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          TableauRestaurant(
            gabarit: GabaritTableau.carteVue,
            colonnes: colonnes,
            pleineLargeur: true,
            videSousEntete: true,
            vide: const _EtatVide(
              cle: Key('restauration-fiches-vide'),
              detail: 'Aucune fiche technique ne correspond à ces critères.',
            ),
            clesLignes: [
              for (final f in page.elements) Key('restauration-fiche-${f.id}'),
            ],
            lignes: [
              for (final f in page.elements)
                [
                  Text(f.libelle, style: TextesRestaurant.corpsFort),
                  Text(
                    f.platsServis.isEmpty
                        // `fiches_sans_plat`.
                        ? 'Aucun plat'
                        : f.platsServis.join(', '),
                    key: Key('restauration-fiche-plats-${f.id}'),
                    style: TextesRestaurant.secondaire,
                  ),
                  Text(
                    '${f.nbIngredients ?? 0}',
                    key: Key('restauration-fiche-ingredients-${f.id}'),
                    style: TextesRestaurant.corps.copyWith(
                      fontWeight: FontWeight.w600,
                      color: (f.nbIngredients ?? 0) == 0
                          ? PaletteMaitre.rouge600
                          : Ardoise.c700,
                    ),
                  ),
                  _CoutFiche(fiche: f),
                  _EtatFicheBadge(fiche: f),
                  _BoutonLigneCrud(
                    cle: Key('restauration-fiche-modifier-${f.id}'),
                    // `fiches_action_composer`.
                    libelle: 'Modifier',
                    onTap: () => ouvrirModaleFiche(context, fiche: f),
                  ),
                ],
            ],
          ),
          _Pagination(
            cle: 'restauration-fiches',
            page: page,
            onPage: (n) => ref.read(pageFichesProvider.notifier).definir(n),
          ),
        ],
      ),
    );
  }
}

/// Le coût matière d'une fiche — TROIS états, jamais « 0 F ».
class _CoutFiche extends StatelessWidget {
  const _CoutFiche({required this.fiche});

  final Recette fiche;

  @override
  Widget build(BuildContext context) {
    if (fiche.compositionVide || fiche.etat == EtatFiche.vide) {
      return Tooltip(
        // `fiches_cout_vide_infobulle`.
        message:
            "Une composition vide n'a pas de coût : ce n'est pas un plat gratuit.",
        child: Text(
          // `fiches_cout_vide`.
          'Non calculable',
          key: Key('restauration-fiche-cout-${fiche.id}'),
          style: TextesRestaurant.secondaire.copyWith(color: Ardoise.c400),
        ),
      );
    }
    if (fiche.coutMatiereIncomplet) {
      return Tooltip(
        // `fiches_cout_incomplet_infobulle`.
        message:
            'Sans coût moyen pondéré (jamais réceptionnés) : '
            '${fiche.articlesSansCout.join(', ')}',
        child: Text(
          // `fiches_cout_incomplet`.
          'Incomplet',
          key: Key('restauration-fiche-cout-${fiche.id}'),
          style: TextesRestaurant.secondaire.copyWith(
            fontWeight: FontWeight.w600,
            color: PaletteMaitre.ambre600,
          ),
        ),
      );
    }
    return Text(
      formaterMontantDecimal(fiche.coutMatiere, suffixe: 'FCFA') ??
          CarteIndicateurRestaurant.absent,
      key: Key('restauration-fiche-cout-${fiche.id}'),
      style: TextesRestaurant.corps.copyWith(
        fontWeight: FontWeight.w600,
        color: AppColors.gold,
      ),
    );
  }
}

/// L'état d'une fiche — vide (gris), composée SANS suivi (bleu), composée
/// (vert). Le troisième est la vérité d'une salade verte : la fiche est
/// composée et ne décrémente RIEN, parce que tous ses ingrédients s'achètent au
/// jour le jour. Rendue « composée », elle se lirait comme une fiche qui
/// décrémente.
class _EtatFicheBadge extends StatelessWidget {
  const _EtatFicheBadge({required this.fiche});

  final Recette fiche;

  @override
  Widget build(BuildContext context) {
    final (texte, fond, couleur, aide) = switch (fiche.etat) {
      EtatFiche.vide || null => (
        // `fiches_etat_vide` et son infobulle.
        'Vide — ne décrémente rien',
        // Neutre depuis le 30/10/2026 (la vue le rendait en rouge : une fiche vide
        // était une vente refusée). Le plat se vend, sans sortie de stock.
        AppColors.badgeGrisFond,
        AppColors.badgeGrisTexte,
        'Ce plat se vend au point de vente restaurant, sans aucune sortie de '
            'stock tant que la composition est vide. Composez la fiche pour que '
            'la vente décrémente ses ingrédients.',
      ),
      EtatFiche.sansSuivi => (
        // `fiches_etat_sans_suivi` et son infobulle.
        'Aucun stock suivi',
        AppColors.badgeBleuFond,
        AppColors.info,
        // `fiches_etat_sans_suivi_infobulle`, au mot — la vue l'écrit SANS
        // accents (« composee », « decremente ») et avec l'apostrophe
        // typographique de « c’est » : défaut de la vue, repris tel quel
        // parce que la vue est le maître (signalé dans le rapport).
        'Cette fiche est composee, et elle ne decremente aucun stock : tous ses ingredients sont suivis « au jour le jour » (achetes le matin, jamais inventories). La vente passe, rien ne bouge, et c’est correct.',
      ),
      EtatFiche.composee => (
        // `fiches_etat_composee`.
        'Composée',
        AppColors.badgeVertFond,
        AppColors.succes,
        null,
      ),
    };

    final pastille = PastilleRestaurant(
      cle: Key('restauration-fiche-etat-${fiche.id}'),
      texte: texte,
      fond: fond,
      couleur: couleur,
      compacte: true,
    );
    final etat = aide == null
        ? pastille
        : Tooltip(message: aide, child: pastille);
    if (!fiche.compositionProvisoire) return etat;

    // La marque « composition provisoire » (`composition_provisoire`) : À CÔTÉ
    // de l'état, pas à sa place — une fiche provisoire est bel et bien
    // composée, elle décrémente une quantité que personne n'a mesurée.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        etat,
        const SizedBox(width: AppSpacing.unit), // ml-1
        Tooltip(
          // `fiches_etat_provisoire_infobulle`, au mot.
          message:
              "Les quantités de cette fiche ont été POSÉES pour débloquer le service, elles n'ont jamais été pesées. Le stock décrémenté à chaque vente est donc approximatif. Enregistrez la composition relevée en cuisine : la marque tombe d'elle-même.",
          child: PastilleRestaurant(
            cle: Key('restauration-fiche-provisoire-${fiche.id}'),
            // `fiches_etat_provisoire`.
            texte: 'Provisoire',
            fond: AppColors.reserveGoldFond,
            couleur: AppColors.reserveGoldTexte,
            compacte: true,
          ),
        ),
      ],
    );
  }
}

/// `text-[11px] px-2 py-0.5 rounded border border-slate-300` — le petit bouton
/// de ligne des onglets ajoutés (« Modifier »).
class _BoutonLigneCrud extends StatelessWidget {
  const _BoutonLigneCrud({
    required Key cle,
    required this.libelle,
    required this.onTap,
  }) : super(key: cle);

  final String libelle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.rounded),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.demi,
        ),
        decoration: BoxDecoration(
          border: Border.all(color: Ardoise.c300),
          borderRadius: BorderRadius.circular(AppRadius.rounded),
        ),
        child: Text(
          libelle,
          style: TextesRestaurant.mention.copyWith(color: Ardoise.c700),
        ),
      ),
    );
  }
}

/* ====================================================================== */
/* Onglet « Menus »                                                        */
/* ====================================================================== */

/// L'onglet des menus — LOCAL (09/10/2026). La saison est celle que les dates
/// ENCADRENT : un menu permanent n'en a pas, et « Permanent » se lit autrement
/// qu'un tiret (qui voudrait dire « donnée manquante »).
class _OngletMenus extends ConsumerWidget {
  const _OngletMenus();

  static const _colonnes = [
    ColonneRestaurant('Menu'),
    ColonneRestaurant('Type de carte', aDroite: true),
    ColonneRestaurant('Saison', aDroite: true),
    ColonneRestaurant('Plats rattachés', aDroite: true),
    ColonneRestaurant('', aDroite: true),
  ];

  /// « 2026-06-01 » -> « 01/06/2026 » (`format('d/m/Y')`).
  static String _jour(String iso) {
    final p = iso.split('-');
    return p.length == 3 ? '${p[2]}/${p[1]}/${p[0]}' : iso;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resultat = ref.watch(menusListeProvider);

    return resultat.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => NoteRestaurant(
        cle: const Key('restauration-menus-erreur'),
        texte: '$e',
        icone: Icons.error_outline,
      ),
      data: (r) => switch (r) {
        RestaurantRecu<PageRestaurant<MenuRestaurant>>(:final donnees) =>
          CadreTableauRestaurant(
            corps: TableauRestaurant(
              gabarit: GabaritTableau.carteVue,
              colonnes: _colonnes,
              pleineLargeur: true,
              videSousEntete: true,
              vide: const _EtatVide(
                cle: Key('restauration-menus-vide'),
                // `menus_aucun`, au mot.
                detail:
                    "Aucun menu n'existe encore. Le bouton « Nouveau menu » en crée un : sans lui, aucun plat ne peut être enregistré.",
              ),
              clesLignes: [
                for (final m in donnees.elements)
                  Key('restauration-menu-${m.id}'),
              ],
              lignes: [
                for (final m in donnees.elements)
                  [
                    Text(m.libelle, style: TextesRestaurant.corpsFort),
                    Text(
                      libellesTypesMenu[m.typeBrut] ?? m.typeBrut,
                      style: TextesRestaurant.secondaire,
                    ),
                    Text(
                      m.dateDebut == null && m.dateFin == null
                          // `menus_saison_permanente`.
                          ? 'Permanent'
                          : '${m.dateDebut == null ? CarteIndicateurRestaurant.absent : _jour(m.dateDebut!)}'
                                ' → '
                                '${m.dateFin == null ? CarteIndicateurRestaurant.absent : _jour(m.dateFin!)}',
                      key: Key('restauration-menu-saison-${m.id}'),
                      style: TextesRestaurant.secondaire,
                    ),
                    Text(
                      '${m.nbPlats ?? CarteIndicateurRestaurant.absent}',
                      key: Key('restauration-menu-plats-${m.id}'),
                      style: TextesRestaurant.corps.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    _BoutonLigneCrud(
                      cle: Key('restauration-menu-modifier-${m.id}'),
                      // `menus_action_editer`.
                      libelle: 'Modifier',
                      onTap: () => ouvrirModaleMenu(context, menu: m),
                    ),
                  ],
              ],
            ),
          ),
        RestaurantRefuse<PageRestaurant<MenuRestaurant>>(:final motif) =>
          NoteRestaurant(
            cle: const Key('restauration-menus-refus'),
            texte: motif,
            icone: Icons.lock_outline,
          ),
        RestaurantInjoignable<PageRestaurant<MenuRestaurant>>() =>
          const NoteRestaurant(
            cle: Key('restauration-menus-hors-ligne'),
            texte: 'Les menus n’ont pas pu être lus.',
          ),
      },
    );
  }
}

/// `<thead class="bg-[var(--navy)]">` — `px-3 py-2.5`, 11 px en majuscules.
class _EnteteMarine extends StatelessWidget {
  const _EnteteMarine({
    required this.colonnes,
    required this.aDroite,
    this.parts,
    this.debut = 0,
  });

  final List<String> colonnes;
  final Set<String> aDroite;

  /// Les parts de largeur relevées sur la vue rendue (`<table class="w-full">`
  /// : la largeur de colonne vient de son contenu, que l'état vide réduit à
  /// l'en-tête). À défaut, parts égales.
  final List<int>? parts;

  /// La largeur de la case de sélection que la vue place avant la première
  /// colonne (`th w-10`) : réservée, pour que les colonnes tombent où elles
  /// tombent dans la vue. La case elle-même n'est pas rendue (voir l'en-tête).
  final double debut;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.navy,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xsPlus),
      child: Row(
        children: [
          if (debut > 0) SizedBox(width: debut),
          for (var i = 0; i < colonnes.length; i++)
            Expanded(
              flex: parts?[i] ?? 1,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: Text(
                  colonnes[i].toUpperCase(),
                  textAlign: aDroite.contains(colonnes[i])
                      ? TextAlign.right
                      : TextAlign.left,
                  style: TextesRestaurant.enteteColonneNavy,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// L'état vide de la vue (`p-10 text-center text-[13px] text-slate-400`) :
/// titre en gras, détail, puis le message propre à l'écran.
class _EtatVide extends StatelessWidget {
  const _EtatVide({
    this.cle,
    this.detail = 'Aucun plat ne correspond à ces critères.',
  });

  final Key? cle;

  /// Le message propre à l'écran (`vide`, `fiches_aucune`, `menus_aucun`).
  final String detail;

  @override
  Widget build(BuildContext context) {
    final base = TextesRestaurant.petitCrud.copyWith(
      fontSize: TaillesContenu.t13,
      height: 1.5,
      color: AppColors.neutre400,
    );
    return Padding(
      key: cle,
      padding: const EdgeInsets.all(AppSpacingLarge.p10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Aucun résultat',
            style: base.copyWith(
              fontWeight: FontWeight.w600,
              color: AppColors.neutre500,
            ),
          ),
          Text(
            'Essayez de modifier votre recherche ou vos filtres.',
            style: base,
          ),
          Text(detail, style: base, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

/// Le tableau et sa pagination — `crud-ui.js` l.62-82.
///
/// La première colonne est la case de sélection du maître (`#crud-case-tout`) :
/// « Tout sélectionner » coche TOUS les plats que le filtre retient — pas
/// seulement la page affichée, comme `requetePlats()->pluck('id')` de la vue —
/// et chaque ligne porte « Sélectionner cette ligne ».
class _Tableau extends ConsumerWidget {
  const _Tableau({required this.page});

  final PageRestaurant<Plat> page;

  /// Les colonnes du maître (`m4-restauration.html` l.77-121), dans son ordre.
  ///
  /// La colonne d'actions n'a pas d'en-tête (`<th></th>`) ; la première est la
  /// case de sélection, dont l'en-tête est une case et non un texte.
  static const _libelleActions = 'Actions';

  /// `th w-10` : la colonne de la case ne reçoit aucune part du surplus.
  static const _largeursFixes = {0: AppLayout.colonneSelection};

  static const colonnes = [
    ColonneRestaurant('Plat'),
    ColonneRestaurant('Catégorie', aDroite: true),
    ColonneRestaurant('Prix de vente', aDroite: true),
    ColonneRestaurant('Disponible', aDroite: true),
    ColonneRestaurant(_libelleActions, aDroite: true),
  ];

  /// Les ids de TOUS les plats que le filtre retient (`toutSelectionne`).
  Future<Set<String>> _tousLesPlatsFiltres(WidgetRef ref) async {
    final r = await ref
        .read(restaurantApiProvider)
        .plats(
          recherche: _terme(ref),
          categorie: ref.read(categorieRestaurationProvider),
          page: 1,
          parPage: 1 << 30,
        );
    return switch (r) {
      RestaurantRecu<PageRestaurant<Plat>>(:final donnees) => {
        for (final p in donnees.elements) p.id,
      },
      _ => const <String>{},
    };
  }

  static String? _terme(WidgetRef ref) {
    final t = ref.read(rechercheRestaurationProvider).trim();
    return t.isEmpty ? null : t;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(selectionPlatsProvider);
    final retires = ref.watch(platsRetiresProvider).value ?? const {};
    final toutCoche =
        page.total > 0 &&
        selection.length >= page.total &&
        page.elements.every((p) => selection.contains(p.id));

    final caseTout = CaseSelectionAchats(
      cle: const Key('restauration-tout'),
      valeur: toutCoche,
      // `aria-label` de la vue (`selection_tout`).
      etiquette: 'Tout sélectionner',
      surMarine: true,
      onChanged: (coche) async {
        if (!coche) {
          ref.read(selectionPlatsProvider.notifier).vider();
          return;
        }
        final tous = await _tousLesPlatsFiltres(ref);
        ref.read(selectionPlatsProvider.notifier).definir(tous);
      },
    );

    return CadreTableauRestaurant(
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (page.elements.isEmpty) ...[
            _EnteteMarine(
              // La dernière colonne de la vue n'a pas de titre (`<th></th>`).
              colonnes: [
                for (final c in colonnes)
                  c.titre == _libelleActions ? '' : c.titre,
              ],
              aDroite: {
                for (final c in colonnes)
                  if (c.aDroite) c.titre,
              },
              parts: const [2000, 1915, 3017, 2529, 689],
              debut: AppSpacingLarge.p10,
            ),
            const _EtatVide(),
          ] else
            TableauRestaurant(
              gabarit: GabaritTableau.crud,
              colonnes: [
                ColonneRestaurant('', enteteSpecial: caseTout),
                ...colonnes,
              ],
              largeursFixes: _largeursFixes,
              vide: const EtatVideCrud(),
              clesLignes: [
                for (final p in page.elements)
                  Key('restauration-ligne-${p.id}'),
              ],
              lignes: [
                for (final p in page.elements)
                  [
                    CaseSelectionAchats(
                      cle: Key('restauration-case-${p.id}'),
                      valeur: selection.contains(p.id),
                      // `aria-label` de la vue (`selection_ligne`).
                      etiquette: 'Sélectionner cette ligne',
                      onChanged: (coche) => ref
                          .read(selectionPlatsProvider.notifier)
                          .basculer(p.id, coche: coche),
                    ),
                    _NomPlat(plat: p, retrait: retires[p.id]),
                    _BadgeCategorie(plat: p),
                    Text(
                      // « FCFA » partout, PWA comprise — décision du Product
                      // Owner du 11/09/2026 (PA-186).
                      formaterMontantDecimal(p.prixVente, suffixe: 'FCFA') ??
                          CarteIndicateurRestaurant.absent,
                      style: TextesRestaurant.corpsCrud.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.gold,
                      ),
                    ),
                    _BadgeDisponible(plat: p, retrait: retires[p.id]),
                    _Actions(plat: p),
                  ],
              ],
            ),
          _Pagination(
            cle: 'restauration',
            page: page,
            selectionnes: selection.length,
            onPage: (n) {
              ref.read(selectionPlatsProvider.notifier).vider();
              ref.read(pageRestaurationProvider.notifier).definir(n);
            },
          ),
        ],
      ),
    );
  }
}

/// Le nom du plat — et, quand il est retiré de la carte, le motif en ambre en
/// dessous (`{{ $indisponibilite->libelleMotif() }}`, la ligne ajoutée par la
/// vue : `opacity-55` sur la ligne entière).
class _NomPlat extends StatelessWidget {
  const _NomPlat({required this.plat, required this.retrait});

  final Plat plat;
  final IndisponibiliteDistante? retrait;

  @override
  Widget build(BuildContext context) {
    final nom = Text(plat.libelle, style: TextesRestaurant.corpsCrud);
    final description = plat.description;
    // La description FACULTATIVE (30/10/2026, décision du PO) : une ligne secondaire
    // discrète sous le nom, rendue seulement quand elle existe.
    final texte = description == null
        ? nom
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              nom,
              Text(
                description,
                key: Key('restauration-description-${plat.id}'),
                style: TextesRestaurant.mention.copyWith(
                  color: AppColors.neutre400,
                ),
              ),
            ],
          );
    if (retrait == null) return texte;
    return Opacity(
      opacity: AppLayout.opaciteLigneRetiree,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          texte,
          Text(
            retrait!.commentaire == null
                ? retrait!.libelle
                : '${retrait!.libelle} — ${retrait!.commentaire}',
            key: Key('restauration-retrait-${plat.id}'),
            style: TextesRestaurant.mention.copyWith(
              color: PaletteMaitre.ambre700,
            ),
          ),
        ],
      ),
    );
  }
}

/// La colonne « Catégorie » — la vue la rend en TEXTE (`text-right text-slate-500
/// text-[12px]`) : `$categories[$plat->categorie] ?? $plat->categorie ?? —`, c'est-à-dire
/// le libellé de la catégorie du PLAT (dix valeurs, `plats.categorie`, v41), la clé
/// brute si le registre ne la connaît pas, « — » sans catégorie. Ce n'est plus le
/// type du menu, ni une pastille aux trois couleurs de l'ancien maître.
class _BadgeCategorie extends StatelessWidget {
  const _BadgeCategorie({required this.plat});

  final Plat plat;

  @override
  Widget build(BuildContext context) {
    return Text(
      plat.categorieCarteLibelle ?? CarteIndicateurRestaurant.absent,
      key: Key('restauration-categorie-${plat.id}'),
      style: TextesRestaurant.mention.copyWith(color: Ardoise.c500),
    );
  }
}

/// La pastille « Disponible » — « Oui » (vert) ou « Non » (rouge, le motif en
/// infobulle), lue de `indisponibilites_carte_local` comme la vue lit
/// `indisponibilites_carte` (`disponible_oui`, `disponible_non`).
class _BadgeDisponible extends StatelessWidget {
  const _BadgeDisponible({required this.plat, required this.retrait});

  final Plat plat;
  final IndisponibiliteDistante? retrait;

  @override
  Widget build(BuildContext context) {
    final r = retrait;
    if (r == null) {
      return PastilleRestaurant(
        cle: Key('restauration-disponible-${plat.id}'),
        texte: 'Oui',
        fond: AppColors.badgeVertFond,
        couleur: AppColors.succes,
      );
    }
    return Tooltip(
      message: r.libelle,
      child: PastilleRestaurant(
        cle: Key('restauration-disponible-${plat.id}'),
        texte: 'Non',
        fond: AppColors.badgeRougeFond,
        couleur: AppColors.erreur,
      ),
    );
  }
}

/// Les actions de ligne — `restauration.blade.php` : « Modifier » et « Retirer
/// de la carte » (`action_editer`, `action_archiver`), plus le détail du maître.
///
/// « Retirer de la carte » ouvre la modale d'archivage partagée : ses verrous
/// sont calculés AVANT (plat déjà retiré, addition ouverte qui le porte), le
/// bouton de confirmation disparaît quand ils bloquent, et la confirmation
/// écrit le motif `retire` — rien n'est effacé. Le droit d'écriture M4 est
/// relu à chaque geste (`exigerEcriture`).
class _Actions extends ConsumerWidget {
  const _Actions({required this.plat});

  final Plat plat;

  Future<void> _retirer(BuildContext context, WidgetRef ref) async {
    final messager = ScaffoldMessenger.of(context);
    final retraits = ref.read(retraitsPlatsProvider);
    final verrous = await retraits.verrous(plat.id);
    if (!context.mounted) return;

    final confirme = await ouvrirArchivageAchats(
      context,
      element: plat.libelle,
      // `archiver_titre` — la vue passe son propre titre au composant.
      titre: 'Retirer « ${plat.libelle} » de la carte ?',
      // `archiver_message`, au mot.
      message:
          "Le plat quitte la carte du jour et reste au catalogue — rien n'est effacé. Il revient depuis la carte du restaurant, bouton « Remettre ».",
      messagesVerrou: verrous,
      bloque: verrous.isNotEmpty,
      // `archiver_confirmer`.
      libelleConfirmer: 'Retirer de la carte',
    );
    if (confirme != true) return;

    // Les verrous sont RECALCULÉS : ceux affichés datent de l'ouverture de la
    // modale, une addition a pu naître depuis (`confirmerRetraitDuPlat`).
    if ((await retraits.verrous(plat.id)).isNotEmpty) return;
    final r = await retraits.retirer(platId: plat.id, motif: 'retire');
    final texte = switch (r) {
      BarRecu<String>(:final donnees) =>
        // `archive`, de la vue.
        'Le plat « $donnees » est retiré de la carte.',
      BarRefuse<String>(:final motif) => motif,
      _ => 'Le plat n’a pas pu être retiré de la carte.',
    };
    messager.showSnackBar(
      SnackBar(
        content: Text(texte, key: const Key('restauration-retrait-issue')),
      ),
    );
    invaliderRestaurant(ref);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final peutEcrire = ref
        .watch(droitsProvider)
        .peutEcrire(ModuleTatacora.m4Restaurant);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: Key('restauration-voir-${plat.id}'),
          // Le `title` du maître (l.234), au mot.
          tooltip: 'Voir le détail',
          onPressed: () => ouvrirModaleDetailPlat(context, plat: plat),
          icon: const Icon(
            Icons.visibility_outlined,
            size: AppLayout.iconeChamp,
            color: Ardoise.c500,
          ),
        ),
        IconButton(
          key: Key('restauration-modifier-${plat.id}'),
          tooltip: 'Modifier',
          onPressed: () async {
            final enregistre = await ouvrirModalePlat(context, plat: plat);
            if (enregistre == true) ref.invalidate(platsProvider);
          },
          icon: const Icon(
            Icons.edit_outlined,
            size: AppLayout.iconeChamp,
            color: Ardoise.c500,
          ),
        ),
        if (peutEcrire)
          IconButton(
            key: Key('restauration-retirer-${plat.id}'),
            tooltip: 'Retirer de la carte',
            onPressed: () => _retirer(context, ref),
            icon: const Icon(
              Icons.archive_outlined,
              size: AppLayout.iconeChamp,
              color: Ardoise.c500,
            ),
          ),
      ],
    );
  }
}

/// La pagination du maître — `crud-engine.js` l.252-260, formulation comprise.
///
/// Partagée par le catalogue et les fiches : [cle] préfixe les clés (`-decompte`,
/// `-page-precedente`, `-page-courante`, `-page-suivante`), et [onPage] pose la
/// page voulue. Deux copies écrites à deux endroits finiraient par diverger.
class _Pagination<T> extends StatelessWidget {
  const _Pagination({
    required this.cle,
    required this.page,
    required this.onPage,
    this.selectionnes = 0,
  });

  /// Le compteur de sélection que la vue ajoute au décompte (`selectionnes`) :
  /// 0 = rien n'est coché, rien ne s'affiche.
  final int selectionnes;

  final String cle;
  final PageRestaurant<T> page;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) {
    final courante = page.page;

    return Container(
      // `flex items-center justify-between px-4 py-3 border-t border-slate-100`.
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Ardoise.c100)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        children: [
          Text.rich(
            // La formulation du maître (l.254), au mot — et, quand des cases
            // sont cochées, « N sélectionné(s) » en gras marine (`selectionnes`).
            TextSpan(
              children: [
                TextSpan(
                  text:
                      'Affichage de ${page.premier}-${page.dernier} sur ${page.total}',
                ),
                if (selectionnes > 0)
                  TextSpan(
                    text: '  $selectionnes sélectionné(s)',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.navy,
                    ),
                  ),
              ],
            ),
            key: Key('$cle-decompte'),
            style: TextesRestaurant.petitCrud,
          ),
          // `flex items-center gap-2` — rendu en `Wrap` : les trois contrôles
          // débordent de 161 px sur un écran de 390 px, et « Suivant → »
          // devient inatteignable. Trouvé par le test de rendu (Article 9.3).
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton(
                key: Key('$cle-page-precedente'),
                onPressed: courante <= 1 ? null : () => onPage(courante - 1),
                // Le libellé du maître, flèche comprise.
                child: const Text(
                  '← Précédent',
                  style: TextesRestaurant.petitCrud,
                ),
              ),
              Padding(
                // `px-2` sur le compteur de page, en plus du `gap-2` du
                // conteneur : le maître pose les deux.
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                child: Text(
                  'Page $courante / ${page.derniere}',
                  key: Key('$cle-page-courante'),
                  style: TextesRestaurant.petitCrud,
                ),
              ),
              OutlinedButton(
                key: Key('$cle-page-suivante'),
                onPressed: courante >= page.derniere
                    ? null
                    : () => onPage(courante + 1),
                child: const Text(
                  'Suivant →',
                  style: TextesRestaurant.petitCrud,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
