// Vue Blade maîtresse (PA-183) : pwa/bar/carte.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/providers.dart';
import '../../../core/rbac/garde_acces.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared_widgets/liste_paginee.dart';
import '../../restaurant/presentation/widgets/coquille_restaurant.dart';
import '../../restaurant/presentation/widgets/corps_carte_commun.dart';
import '../domain/entities/boisson.dart';
import '../domain/entities/carte_bar.dart';
import 'providers_bar.dart';
import 'widgets/barre_exports_carte.dart';
import '../../../shared_widgets/modale_export.dart';
import 'widgets/modale_historique_prix.dart';
import 'widgets/modale_lien_stock.dart';
import 'widgets/modale_nouvelle_boisson.dart';
import 'widgets/modale_prix_boisson.dart';
import 'widgets/modale_retrait_carte.dart';
import 'widgets/table_carte.dart';
import 'widgets/vue_couverture_bar.dart';
import 'widgets/vue_ventes_bar.dart';

/// L'écran **Carte du bar** — `pwa/bar/carte.blade.php`, dont le corps est le
/// partiel partagé `pwa/carte/corps.blade.php`.
///
/// ## La page, dans l'ordre de la vue (Phase 2, 08/10/2026)
///
/// Une seule colonne qui défile d'un bloc (`p-5 lg:p-8`, `max-w-[1500px]`,
/// corps l.72-73), puis, dans l'ordre : l'en-tête et ses CINQ boutons
/// (l.75-144), l'accordéon des six indicateurs (l.163-209), les onglets
/// (l.212), la barre de filtres (l.230), le bandeau du rayon (l.260) et les
/// avertissements de stock (l.267-283), enfin le panneau de l'onglet courant.
///
/// Trois choses ont changé de place par rapport à la version précédente, qui
/// les posait à côté de leur objet plutôt qu'à l'endroit de la vue :
///
///  - « Exporter » et « Imprimer la fiche des prix » sont dans l'EN-TÊTE
///    (l.101-109), pas au-dessus du tableau ; « Exporter » suit l'onglet
///    courant (carte ou ventes, PO 03/09/2026) ;
///  - le bandeau et les avertissements sont SOUS les filtres (l.258-283), pas
///    au-dessus des onglets ;
///  - le tableau est dans un cadre à en-tête « N article(s) » (l.304-308).
///
/// ## L'ossature est PARTAGÉE avec la carte du restaurant (09/10/2026)
///
/// La page, l'en-tête, l'accordéon, la grille de six cartes, la barre de
/// filtres et les encadrés vivent dans `corps_carte_commun.dart`, comme la vue
/// les tient dans UN corps partagé. Ce fichier ne garde que ce qui distingue
/// le bar : ses textes, ses cinq boutons, ses données.
///
/// ## Les TROIS onglets sont portés
///
/// « Carte du jour », « Couverture du stock » et « Ventes du Bar » (l.212-226),
/// dans l'ordre de la vue et avec le premier actif par défaut. Le deuxième
/// n'est pas une projection de durée mais un simple `lies / total`.
///
/// « Rapprocher automatiquement » n'est pas rendu — et la vue ne le rend pas
/// non plus : l'écran précédent l'affichait dans un panneau « Ce que cet écran
/// ne rend pas » qui nommait un contrôle du maître archivé (`prototype_v2/`),
/// absent de la vue Blade (PA-182). Ce panneau n'existe pas dans la vue : il
/// est retiré (08/10/2026). La raison du refus reste vraie — c'est une
/// **écriture** de stock, et aucune route ne l'accepte — et se lit ici, là où
/// quelqu'un voudrait le rajouter.
///
/// ## L'écran fonctionne hors connexion, sa colonne de stock non
///
/// Prix, libellés et catégories viennent de la base locale (PA-129) : la carte
/// s'affiche au comptoir même sans réseau, ce qui est le sens même de cet
/// écran. Le stock, lui, est calculé par le serveur sur des tables que ce poste
/// ne détient pas ; il est **absent**, et l'écran le dit. Un zéro à la place
/// ferait commander des caisses déjà en réserve.
///
/// ## La carte se modifie ICI, sur ce poste
///
/// « Nouvelle boisson » écrit dans la carte locale (`creerBoissonProvider`,
/// décision du PO du 14/09/2026) : le poste est zéro réseau, il n'y a plus de
/// second état à annoncer. « Lier au stock » reste un arbitrage ouvert, que ce
/// lot ne tranche pas.
///
/// ## Un bouton de l'écran n'est PAS dans la vue
///
/// « Boissons » (catalogue du bar, `ecran_catalogue_boissons.dart`) : la vue
/// du bar n'a pas d'écran de catalogue séparé (`t-blade-flutter.js` le
/// signale comme ajout). Il est conservé, **en fin de rangée** pour ne déplacer
/// aucun des cinq boutons de la vue, parce que c'est le seul chemin vers cet
/// écran : le retirer en ferait un écran inatteignable par un clic
/// (Directive Article 3.3). C'est au Product Owner de dire s'il reste.
///
/// Les blocs de la vue que le bar ne rend JAMAIS (le corps partagé les garde
/// derrière un drapeau que la vue du bar met à faux) se déclarent pour le
/// comparateur, qui n'évalue pas les conditions Blade.
///
/// « Délier » n'est pas un refus : la vue ne la rend jamais au bar
/// (`$page['delier'] = false`, `bar/carte.blade.php` l.62) —
/// `cartes_boisson.article_id` est NOT NULL, le lien se REMPLACE (« Modifier
/// le lien ») et ne se retire pas ; `CarteBoissonService` n'expose aucun
/// `delierDuStock()`.
///
///  - blade-refuse:bar/carte#modale:modal-delier
class EcranCarteBar extends ConsumerWidget {
  const EcranCarteBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final toutes = ref.watch(carteBarProvider);
    final carte = ref.watch(carteFiltreeProvider);
    final onglet = ref.watch(ongletCarteBarProvider);
    // « Prix » par ligne (vue l.434-435) : pour les rôles qui écrivent sur M5.
    final peutEcrire = ref
        .watch(droitsProvider)
        .peutEcrire(ModuleTatacora.m5Bar);

    return PageCarte(
      // `max-w-[1500px] mx-auto` (corps l.73).
      largeurMax: AppLayout.pageCarteBar,
      enfants: [
        const _EnTete(),
        // L'accordéon et le bandeau portent sur la carte ENTIÈRE, comme
        // `socleDeLaCarte()` : le filtre du tableau ne change pas
        // « Couverture actuelle ».
        _Indicateurs(toutes: toutes),
        const _Onglets(),
        const _Filtres(),
        _Bandeaux(toutes: toutes),
        // ⚠ L'onglet « Couverture » ne consomme PAS `lignes` : le maître
        // appelle `C.articles({ module })` sans filtre, et le décompte
        // se fait sur la carte locale, sans réseau.
        switch (onglet) {
          OngletCarteBar.carteDuJour => carte.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('$e'),
            data: (lignes) =>
                _PanneauCarte(lignes: lignes, peutEcrire: peutEcrire, ref: ref),
          ),
          OngletCarteBar.couvertureDuStock => const _Couverture(),
          // « Ventes du Bar » (PA-197) : ses lignes viennent du serveur ;
          // la carte NON filtrée ne sert qu'à y lire le stock du jour de
          // chaque article — les filtres du haut filtrent la carte,
          // jamais les ventes (vue l.564-566).
          OngletCarteBar.ventes => toutes.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('$e'),
            data: (lignes) => VueVentesBar(carte: lignes),
          ),
        },
      ],
    );
  }
}

/* ====================================================================== */
/* En-tête — corps l.75-144                                                */
/* ====================================================================== */

/// Les cinq boutons de la vue, dans son ordre : « Point de vente » (l.86),
/// « Stocks » (l.88), « Exporter » (l.101), « Imprimer la fiche des prix »
/// (l.108), « Nouvelle boisson » (l.117). Les deux liens sont des
/// NAVIGATIONS, rendus à tous comme dans la vue : l'écran visé porte lui-même
/// la garde de son module. « Nouvelle boisson » n'existe que pour un rôle qui
/// ÉCRIT sur M5 : le serveur refuserait les autres en 403 (`exigerEcriture`,
/// `module:M5`), et un bouton qui ne mène qu'à un refus invite à cliquer.
class _EnTete extends ConsumerWidget {
  const _EnTete();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final peutEcrire = ref
        .watch(droitsProvider)
        .peutEcrire(ModuleTatacora.m5Bar);
    final ventes = ref.watch(ongletCarteBarProvider) == OngletCarteBar.ventes;

    return EnTeteCarte(
      // `<svg width="24" height="24">` (`bar/carte.blade.php` l.40).
      icone: Icons.local_bar_outlined,
      titre: 'Carte du bar',
      // `carte_pwa.bar.sous_titre` — la règle de contenance, qui est
      // la raison d'être du lien de stock. `<strong>contenance</strong>`
      // est rendu gras ; chaque fragment est UN littéral, le
      // comparateur coupe la phrase de la vue à ses balises.
      sousTitre: const [
        TextSpan(
          text:
              'Chaque boisson vendue décrémente son casier. Le rapprochement contrôle la ',
        ),
        TextSpan(
          text: 'contenance',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        TextSpan(text: ' : une 33 cl ne sort pas du casier de 66 cl.'),
      ],
      boutons: [
        // `<a href="{{ route('pwa.pos.comptant') }}">` (l.86-87).
        BoutonEnteteCarte(
          key: const Key('carte-lien-pos'),
          libelle: 'Point de vente',
          style: StyleBoutonEntete.lien,
          onPressed: () => context.go('/pos'),
        ),
        // `<a href="{{ route('pwa.stocks.liste') }}">` (l.88-89).
        BoutonEnteteCarte(
          key: const Key('carte-lien-stocks'),
          libelle: 'Stocks',
          style: StyleBoutonEntete.lien,
          onPressed: () => context.go('/stocks'),
        ),
        // « Exporter » (l.101-102) : UN bouton, qui exporte l'onglet
        // COURANT. La clé dit lequel, pour qu'un test sache ce qu'il
        // touche.
        BoutonEnteteCarte(
          key: Key(ventes ? 'ventes-bar-exporter' : 'carte-exporter'),
          libelle: TextesExport.bouton,
          style: StyleBoutonEntete.plein,
          onPressed: () => BarreExportsCarte.exporter(context, ref),
        ),
        // « Imprimer la fiche des prix » (l.108-109) : directement,
        // sans modale. Un document qui se LIT, groupé par catégorie.
        BoutonEnteteCarte(
          key: const Key('carte-fiche-prix'),
          libelle: 'Imprimer la fiche des prix',
          style: StyleBoutonEntete.or,
          onPressed: () => BarreExportsCarte.fichePrix(context, ref),
        ),
        // « Nouvelle boisson » (l.117-120) — propre au bar.
        if (peutEcrire)
          BoutonEnteteCarte(
            key: const Key('carte-nouvelle-boisson'),
            libelle: TextesNouvelleBoisson.bouton,
            style: StyleBoutonEntete.plein,
            onPressed: () => ouvrirModaleNouvelleBoisson(context),
          ),
        // AJOUT, hors vue : voir l'en-tête de l'écran.
        BoutonEnteteCarte(
          key: const Key('carte-vers-boissons'),
          libelle: 'Boissons',
          style: StyleBoutonEntete.lien,
          onPressed: () => context.go('/bar/boissons'),
        ),
      ],
    );
  }
}

/* ====================================================================== */
/* Indicateurs — corps l.146-209                                           */
/* ====================================================================== */

/// L'accordéon « Indicateurs de la carte » et ses six cartes (l.163-209).
class _Indicateurs extends StatelessWidget {
  const _Indicateurs({required this.toutes});

  final AsyncValue<List<LigneCarte>> toutes;

  @override
  Widget build(BuildContext context) {
    return AccordeonIndicateurs(
      cleBouton: const Key('carte-kpis-accordeon'),
      contenu: toutes.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Text('$e'),
        data: (lignes) =>
            GrilleIndicateurs(cartes: _cartes(KpisCarte.calculer(lignes))),
      ),
    );
  }

  /// Les six cartes de la vue (l.171-207), dans son ordre.
  List<Widget> _cartes(KpisCarte k) {
    final gris = Ardoise.c400;

    return [
      CarteKpi(
        cle: const Key('carte-kpi-articles'),
        libelle: 'Articles à la carte',
        valeur: '${k.articles}',
        detail: '${k.disponibles} disponible(s)',
      ),
      CarteKpi(
        cle: const Key('carte-kpi-retires'),
        libelle: 'Retirés du jour',
        valeur: '${k.indisponibles}',
        detail: 'Rupture ou retrait',
        accent: k.indisponibles > 0 ? PaletteMaitre.ambre600 : gris,
      ),
      CarteKpi(
        cle: const Key('carte-kpi-lies'),
        libelle: 'Liés au stock',
        valeur: '${k.lies} / ${k.articles}',
        detail: '${k.tauxLisible} % de couverture',
        accent: k.tauxCouverture < 50
            ? PaletteMaitre.ambre600
            : PaletteMaitre.emeraude600,
      ),
      CarteKpi(
        cle: const Key('carte-kpi-sans-lien'),
        libelle: 'Ne décrémentent rien',
        valeur: '${k.sansLien}',
        detail: "Stock surévalué d'autant",
        accent: k.sansLien > 0
            ? PaletteMaitre.rouge600
            : PaletteMaitre.emeraude600,
      ),
      CarteKpi(
        cle: const Key('carte-kpi-rupture'),
        libelle: 'En rupture de stock',
        // Sans aucun chiffre du serveur, « 0 » se lirait comme une bonne
        // nouvelle alors qu'il veut dire « on ne sait pas ».
        valeur: k.stockConnu ? '${k.enRupture}' : '—',
        detail: k.stockConnu
            ? '${k.sousSeuil} sous seuil'
            : TextesStockCarte.nonConsulte,
        accent: k.enRupture > 0 ? PaletteMaitre.rouge600 : gris,
      ),
      CarteKpi(
        cle: const Key('carte-kpi-provisoires'),
        libelle: 'Prix provisoires',
        valeur: '${k.prixProvisoires}',
        detail: 'À confronter à la carte',
        accent: k.prixProvisoires > 0 ? PaletteMaitre.rouge600 : gris,
      ),
    ];
  }
}

/* ====================================================================== */
/* Onglets et filtres — corps l.211-256                                    */
/* ====================================================================== */

/// Les trois onglets — `flex flex-wrap gap-1.5 mb-4` (l.212).
class _Onglets extends ConsumerWidget {
  const _Onglets();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actif = ref.watch(ongletCarteBarProvider);

    return Padding(
      // `mb-4` — 16 px.
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Wrap(
        // `gap-1.5` — 6 px, et non les 8 px de `gap-2`.
        spacing: AppSpacing.xxs,
        runSpacing: AppSpacing.xxs,
        children: [
          for (final o in OngletCarteBar.values)
            OngletRestaurant(
              cle: Key('onglet-carte-bar-${o.cle}'),
              libelle: o.libelle,
              actif: actif == o,
              onChoix: () =>
                  ref.read(ongletCarteBarProvider.notifier).definir(o),
            ),
        ],
      ),
    );
  }
}

/// Recherche, catégorie et état — corps l.229-256.
class _Filtres extends ConsumerWidget {
  const _Filtres();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return BarreFiltresCarte(
      cleRecherche: const Key('carte-recherche'),
      onRecherche: (v) => ref.read(rechercheCarteProvider.notifier).definir(v),
      categorie: ListeFiltre<String?>(
        cleListe: const Key('carte-filtre-categorie'),
        largeur: AppLayout.filtreCategorieCarteBar,
        valeur: ref.watch(categorieCarteProvider),
        // Le REGISTRE fermé de la vue (`CarteBoisson::CATEGORIES`, corps l.241),
        // jamais les catégories qu'on rencontre : une liste dérivée des lignes
        // se vide avec la carte, là où la vue offre toujours ses trois choix.
        options: [
          const (null, 'Toutes les catégories'),
          for (final c in CategorieBoisson.values) (c.code, c.libelle),
        ],
        onChange: (c) => ref.read(categorieCarteProvider.notifier).definir(c),
      ),
      etat: ListeFiltre<EtatCarte>(
        cleListe: const Key('carte-filtre-etat'),
        largeur: AppLayout.filtreEtatCarteBar,
        valeur: ref.watch(etatCarteProvider),
        options: [for (final e in EtatCarte.values) (e, e.libelle)],
        onChange: (e) {
          if (e != null) ref.read(etatCarteProvider.notifier).definir(e);
        },
      ),
    );
  }
}

/* ====================================================================== */
/* Bandeaux — corps l.258-289                                              */
/* ====================================================================== */

/// Le bandeau du rayon et les deux avertissements de stock, SOUS les filtres
/// (l.258-283) : jusqu'au 08/10/2026 ils étaient posés au-dessus des
/// onglets, à côté des indicateurs.
class _Bandeaux extends StatelessWidget {
  const _Bandeaux({required this.toutes});

  final AsyncValue<List<LigneCarte>> toutes;

  @override
  Widget build(BuildContext context) {
    final lignes = toutes.value;
    if (lignes == null) return const SizedBox.shrink();

    final kpis = KpisCarte.calculer(lignes);
    final pointAbsent = lignes.any((l) => l.pointDeVenteAbsent);
    // Un ÉCHEC de lecture, distinct d'un point de vente absent — la vue les
    // dit par deux bandeaux différents (l.267-283).
    final nonConsultes = lignes.any(
      (l) => l.stockNonConsulte && !l.pointDeVenteAbsent,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _Bandeau(kpis: kpis),
        if (pointAbsent)
          const AvertissementCarte(
            cle: Key('carte-point-absent'),
            // `carte_pwa.bar.point_absent`.
            texte:
                "Aucun point de stockage de type « bar » n'est encore déclaré : le stock vendable ne peut pas être calculé, et aucun chiffre n'est affiché. Ce qui dort au magasin n'est pas vendable au comptoir — replier sur le stock tous points confondus annoncerait des bouteilles que le barman n'a pas.",
          ),
        if (nonConsultes)
          const AvertissementCarte(
            cle: Key('carte-stock-non-consulte'),
            texte: TextesStockCarte.nonConsulteDetail,
          ),
      ],
    );
  }
}

/// Le bandeau du module (vue l.258-265, `carte_pwa.bar.bandeau_*`), encadré
/// « gris » de la vue du bar : la couverture actuelle y est DITE en clair.
/// `rounded-xl p-3.5 mb-4`, couleurs posées en `style` (`#F8FAFC` / `#E2E8F0`
/// / `#334155`).
class _Bandeau extends StatelessWidget {
  const _Bandeau({required this.kpis});

  final KpisCarte kpis;

  @override
  Widget build(BuildContext context) {
    final fort = styleContenuCarte(
      TaillesContenu.t13,
      poids: FontWeight.bold,
      couleur: Ardoise.c700,
    );

    return KeyedSubtree(
      key: const Key('carte-bandeau'),
      child: EncadreCarte(
        fond: Ardoise.c50,
        bordure: Ardoise.c200,
        enfant: Text.rich(
          TextSpan(
            style: styleContenuCarte(TaillesContenu.t13, couleur: Ardoise.c700),
            children: [
              TextSpan(
                text:
                    'Au bar, vendre et sortir du stock désignent la même chose. ',
                style: fort,
              ),
              // Chaque fragment est UN littéral : le comparateur coupe la phrase
              // de la vue à ses balises `<strong>`, et cherche chaque morceau.
              const TextSpan(
                text:
                    'Une Béninoise 66 cl vendue, c\'est une bouteille en moins. Le lien est direct et automatisable par rapprochement de libellé — à condition que la ',
              ),
              TextSpan(text: 'contenance', style: fort),
              const TextSpan(
                text:
                    " corresponde : une 33 cl ne sort pas du casier de 66 cl, et l'écart ne se verrait qu'à l'inventaire. Couverture actuelle : ",
              ),
              TextSpan(text: '${kpis.lies} / ${kpis.articles}', style: fort),
              const TextSpan(text: ' articles rattachés.'),
            ],
          ),
        ),
      ),
    );
  }
}

/* ====================================================================== */
/* Panneaux des onglets                                                    */
/* ====================================================================== */

/// L'onglet « Carte du jour » : le tableau dans son cadre, ou l'état vide de
/// la vue (l.298-301, `py-14 text-center text-slate-400 text-[13px]`).
class _PanneauCarte extends StatelessWidget {
  const _PanneauCarte({
    required this.lignes,
    required this.peutEcrire,
    required this.ref,
  });

  final List<LigneCarte> lignes;
  final bool peutEcrire;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    if (lignes.isEmpty) {
      return Container(
        key: const Key('carte-vide'),
        padding: const EdgeInsets.symmetric(vertical: AppSpacingLarge.p14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.neutre0,
          borderRadius: BorderRadius.circular(AppRadius.roundedXl),
          border: Border.all(color: Ardoise.c200),
        ),
        child: Text(
          'Aucun article ne correspond à ces critères.',
          style: styleContenuCarte(TaillesContenu.t13, couleur: Ardoise.c400),
        ),
      );
    }

    return Padding(
      // `mb-3` — 12 px.
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: CadreTableauRestaurant(
        // `carte_pwa.commun.tableau_titre` / `tableau_aside` (l.306-307).
        titre: '${lignes.length} article(s)',
        aside: 'Le stock vendable est calculé, jamais saisi.',
        // Dix articles par page (PO, 14/10/2026) ; les exports lisent
        // `carteFiltreeProvider`, la liste ENTIÈRE.
        corps: ListePaginee<LigneCarte>(
          elements: lignes,
          prefixeCle: 'carte-bar-pagination',
          cleRemiseAZero: (
            ref.watch(rechercheCarteProvider),
            ref.watch(categorieCarteProvider),
            ref.watch(etatCarteProvider),
          ),
          constructeur: (_, page) => TableCarte(
            lignes: page,
            onModifierPrix: peutEcrire
                ? (l) => ouvrirModalePrixBoisson(context, l)
                : null,
            onLierAuStock: peutEcrire
                ? (l) => ouvrirModaleLienStock(context, l)
                : null,
            onRetirer: peutEcrire
                ? (l) => ouvrirModaleRetraitCarte(context, l)
                : null,
            onRemettre: peutEcrire
                ? (l) => remettreALaCarte(context, ref, l)
                : null,
            // Une LECTURE : offerte à tout rôle qui voit l'écran, comme
            // `ouvrirHistoriquePrix()`.
            onHistorique: (l) => ouvrirModaleHistoriquePrix(context, l),
          ),
        ),
      ),
    );
  }
}

/// L'onglet « Couverture du stock », sur la carte **locale** et non filtrée.
class _Couverture extends ConsumerWidget {
  const _Couverture();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(couvertureBarProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('$e'),
          data: (couverture) => VueCouvertureBar(couverture: couverture),
        );
  }
}
