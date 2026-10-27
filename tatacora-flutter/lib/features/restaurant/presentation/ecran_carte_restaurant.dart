// Vue Blade maîtresse (PA-183) : pwa/restaurant/carte.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/donnees_absentes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared_widgets/modale_export.dart';
import '../../../shared_widgets/toast_export.dart';
import '../data/restaurant_api.dart';
import '../domain/entities/carte_restaurant.dart';
import 'providers_restaurant.dart';
import 'widgets/coquille_restaurant.dart';
import 'widgets/corps_carte_commun.dart';
import 'widgets/vue_carte_du_jour.dart';
import 'widgets/vue_couverture.dart';
import 'widgets/vue_ventes_restaurant.dart';

/// L'écran **Carte du restaurant** — `pwa/restaurant/carte.blade.php`, dont le
/// corps est le partiel partagé `pwa/carte/corps.blade.php` (le même que la
/// carte du bar).
///
/// @see EF-M4-01 Gestion des menus et cartes
/// @see EF-M4-02 Fiches techniques (coût matière)
///
/// ## La page, dans l'ordre de la vue (Phase 2, 09/10/2026)
///
/// Une seule colonne qui défile d'un bloc (`p-5 lg:p-8`, `max-w-[1500px]`,
/// corps l.72-73), puis : l'en-tête et ses CINQ boutons (l.75-144), l'accordéon
/// des six indicateurs (l.163-209), les TROIS onglets (l.212-227), la barre de
/// filtres (l.230), le bandeau du rayon (l.260), l'avertissement de point de
/// stockage (l.267-275), enfin le panneau de l'onglet courant. L'ossature est
/// celle de la carte du bar : `corps_carte_commun.dart`, UN seul auteur pour
/// les deux rayons, comme la vue.
///
/// Ce qui a changé par rapport à la version précédente, écrite d'après
/// l'ancien prototype : « Excel » et « PDF » sont fusionnés en UN bouton
/// « Exporter » dont la modale choisit le format (dérogation du Product Owner
/// du 01/09/2026, `DerogationsMaquette::export_bouton_unique`) ; le bouton
/// « Plats » devient « Plats, fiches techniques & menus » (l.140-141, ajout du
/// PO du 04/09/2026) ; l'onglet « Ventes du Restaurant » existe (PO
/// 03/09/2026) ; le panneau « Ce que cet écran ne rend pas » est retiré, la
/// vue n'ayant aucun bloc de ce genre — ses raisons sont ICI, datées.
///
/// ## LOCAL depuis le 09/10/2026 (schéma v14)
///
/// La carte est CALCULÉE des plats, des fiches techniques et du stock du point
/// cuisine de ce poste ([RestaurantApi] -> `RestaurantDao` -> `StocksDao`), à
/// chaque lecture : rien n'est stocké, rien ne vieillit. Sur un poste neuf elle
/// est VIDE — « 0 article », pas de taux, l'avertissement du point cuisine —, et
/// c'est la vérité, pas un refus. Trois issues restent distinguées par le type
/// ([RestaurantRecu], [RestaurantRefuse], [RestaurantInjoignable]) ; seule la
/// deuxième existe encore (un droit de lecture manquant).
///
/// ## « Lier au stock » et « Délier » SONT portés (21/10/2026, schéma v36)
///
/// Le lien direct plat -> article de stock existe : `plats_local.article_id` +
/// `unites_vendables` (le conditionnement, « 24 » pour un casier), écrits par
/// `RestaurantDao.lierAuStock` / `delierDuStock` seuls, enfilés en modification du
/// plat (`article_id` + `unites_vendables_par_unite_stock`, `null` des deux pour
/// délier) et redescendus par `AligneurCatalogue`. Le lien l'emporte sur la fiche
/// (comme `DeductionStockCuisineService`) : portions = solde du point cuisine ×
/// conditionnement. Les jetons de refus des modales « Lier au stock » et
/// « Délier » sont retirés : un bloc rendu ne se déclare pas refusé. « Prix » et
/// « Historique des prix » sont portés depuis la v38 (section suivante).
///
/// ## « Prix » et « Historique des prix » SONT portés (26/10/2026, schéma v38)
///
/// Le serveur trace chaque changement de prix (`historique_prix_carte`, par les
/// observateurs des deux cartes) ; ce poste en tient la table miroir
/// (`historique_prix_carte_local`, `HistoriquePrixCarteDao` seul écrivain). Le
/// bouton « Prix » ([ouvrirModalePrixPlat], droit d'écriture M4) change le prix
/// SEUL par `RestaurantDao.modifierPrix` : le changement est tracé dans la même
/// transaction (`_enfilerPlat`) puis enfilé en modification du plat. Le bouton
/// « Historique des prix » (lecture) ouvre la modale partagée du bar, nourrie par
/// `historiquePrixPlatProvider`. Les traces des autres postes et de la PWA
/// redescendent (`AligneurCatalogue._historiquePrix`) ; la trace d'un changement
/// fait ici est ADOPTÉE à celle du serveur plutôt que doublée. Les jetons de
/// refus des deux modales sont retirés : un bloc rendu ne se déclare pas refusé.
///
/// ## Ce que cet écran REFUSE de rendre, et pourquoi (09/10/2026)
///
/// Les modales restantes sont des blocs entiers de la vue que le corps partagé
/// des cartes ne pose pas sur cette page (voir la section suivante). Le retrait
/// de la carte a sa modale (`modale_retrait_carte.dart`, rendue par
/// [VueCarteDuJour] et écrite par `IndisponibilitesCarteDao`) : son jeton de
/// refus est retiré le 27/10/2026, un bloc rendu ne se déclare pas refusé.
///
/// ## L'onglet « Ventes du Restaurant » : CALCULÉ sur ce poste (26/10/2026)
///
/// ⚠ Le texte du 09/10/2026 (« rendu SANS donnée », « rien ne sert ce relevé »)
/// est PÉRIMÉ : les lignes de vente du rayon sont calculées sur les paniers du
/// poste, les siens et ceux des autres postes que la descente lui a rendus
/// (`ventes/domain/lignes_vente_du_rayon.dart`, réplique de
/// `LignesVenteDuRayonService`), avec statut, numéro `V-` et auteur (v38). Les
/// filtres, les neuf colonnes, la ligne de total et les exports lisent ce relevé
/// ([VueVentesRestaurant]).
///
/// ## « Nouvelle boisson » n'est PAS un refus : la vue ne la rend jamais ici
///
/// Le corps partagé garde la modale « Nouvelle boisson » (l.730) et celle de
/// « Modifier la boisson » (l.787, PO 08/10/2026) derrière
/// `$page['creation_boisson']`, que seule la vue du BAR pose. Le restaurant
/// crée ses plats sur « Plats, fiches techniques & menus » (menu et fiche
/// technique obligatoires). Le comparateur, qui n'évalue pas les conditions
/// Blade, les compte pourtant sur cette page ; les jetons le lui disent.
///
///  - blade-refuse:restaurant/carte#modale:commun.modale_boisson_titre
///  - blade-refuse:restaurant/carte#modale:commun.modale_modifier_boisson_titre
///
/// ## Ce que la vue rend et que cet écran ne peut PAS rendre, sans être un bloc
///
///  - la colonne « Réserve » : aucun calcul de réserve n'est écrit sur ce
///    poste, elle rend « — » avec sa raison (voir [VueCarteDuJour]) ; la colonne
///    « Disponible » est servie depuis la v31 (`indisponibilites_carte_local`) ;
///  - l'avertissement « stock non consulté » (l.277-283) : une lecture locale ne
///    « échoue » pas ; un point cuisine absent, lui, est DIT (l.267-275) ;
///  - « Rapprocher automatiquement » : la vue ne le pose que sur le bar ;
///  - l'indicateur « coût matière inconnu », que le calcul produit
///    (`cout_matiere_inconnu`) et que les six cartes de la vue ne comptent pas :
///    en ajouter un serait inventer un indicateur (Article 1, interdit 07). Le
///    coût matière est rendu dans l'onglet des fiches et dans l'export.
///
/// Rendues depuis la v14, parce qu'une source existe maintenant : les marques
/// « provisoire » et « corrigé à la main » sous le prix (l.354-360), le
/// compteur « Prix provisoires », et le libellé de la fiche technique dans
/// « Article de stock ».
///
/// ## Le bandeau reprend le texte de la VUE, au mot
///
/// Jusqu'au 09/10/2026 il remplaçait deux phrases du maître archivé (« Cette
/// fiche n'existe pas… », « rattaché à la main… ») par une formulation propre
/// à ce client, au motif que `plats` n'aurait aucune colonne d'article. La vue
/// Blade fait foi (PA-182) et `restaurant/carte.blade.php` l.11-13 écrit
/// l'inverse : `plats.article_id` est nullable, le lien direct est
/// l'exception. Le motif avait cessé d'être vrai (PA-144) ; le texte de la vue
/// est rétabli. La dernière phrase (« Un plat peut néanmoins être rattaché à la
/// main… ») décrit un geste de la PWA que ce poste n'offre pas : le bouton
/// « Lier au stock » existe depuis la v36 (voir plus haut).
class EcranCarteRestaurant extends ConsumerWidget {
  const EcranCarteRestaurant({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resultat = ref.watch(carteRestaurantProvider);

    return resultat.when(
      // Un filtre qui change relance la lecture : sans cela, la page entière —
      // la barre de filtres comprise, donc le texte en cours de saisie — serait
      // remplacée par une roue pendant la relecture.
      skipLoadingOnReload: true,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _PageSansDonnees(
        cle: const Key('carte-restaurant-erreur'),
        texte: '$e',
        icone: Icons.error_outline,
      ),
      data: (r) => switch (r) {
        RestaurantRecu<CarteRestaurant>(:final donnees) => _PageAvecDonnees(
          carte: donnees,
        ),
        RestaurantRefuse<CarteRestaurant>(:final motif) => _PageSansDonnees(
          cle: const Key('carte-restaurant-refus'),
          texte: motif,
          icone: Icons.lock_outline,
        ),
        // `RestaurantApi` ne produit plus cette issue (zéro réseau, PO
        // 14/09/2026) ; le `switch` scellé l'exige encore. L'ancienne phrase
        // « Serveur injoignable… Réessayez » (09/10/2026 : retirée) enverrait
        // réessayer une liaison qui n'existe plus : elle dit désormais la
        // vérité unique de `donnees_absentes.dart`.
        RestaurantInjoignable<CarteRestaurant>() => _PageSansDonnees(
          cle: const Key('carte-restaurant-hors-ligne'),
          texte: donneeNonDisponible('La carte et les fiches du restaurant'),
          icone: Icons.help_outline,
        ),
      },
    );
  }
}

/// La coquille seule, au-dessus d'un message — un refus ou une coupure ne
/// doivent pas faire disparaître le titre de la page : l'écran passerait pour
/// cassé. Les boutons de document disent pourquoi ils ne produisent rien.
class _PageSansDonnees extends StatelessWidget {
  const _PageSansDonnees({
    required this.cle,
    required this.texte,
    required this.icone,
  });

  final Key cle;
  final String texte;
  final IconData icone;

  @override
  Widget build(BuildContext context) {
    return PageCarte(
      largeurMax: AppLayout.pageCarteRestaurant,
      enfants: [
        _EnTete(carte: null, motifAbsence: texte),
        NoteRestaurant(cle: cle, texte: texte, icone: icone),
      ],
    );
  }
}

class _PageAvecDonnees extends ConsumerWidget {
  const _PageAvecDonnees({required this.carte});

  final CarteRestaurant carte;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onglet = ref.watch(ongletCarteRestaurantProvider);

    return PageCarte(
      // `max-w-[1500px] mx-auto` (corps l.73).
      largeurMax: AppLayout.pageCarteRestaurant,
      enfants: [
        _EnTete(carte: carte, motifAbsence: null),
        AccordeonIndicateurs(
          cleBouton: const Key('carte-restaurant-kpis-accordeon'),
          contenu: GrilleIndicateurs(cartes: _cartes(carte.indicateurs)),
        ),
        const _Onglets(),
        const _Filtres(),
        _Bandeau(indicateurs: carte.indicateurs),
        if (carte.sansPointCuisine)
          const AvertissementCarte(
            cle: Key('carte-restaurant-sans-point-cuisine'),
            // `carte_pwa.restaurant.point_absent`, au mot (l.267-275).
            texte:
                "Aucun point de stockage de type « cuisine » n'est encore déclaré : le stock vendable ne peut pas être calculé, et aucun chiffre n'est affiché. Ce qui dort au magasin n'est pas servi en salle.",
          ),
        // Un ÉCHEC de lecture se NOMME (`$stocksNonConsultes > 0`, corps l.278-283) :
        // il ne se replie ni sur zéro ni sur une liste vide, « 0 » se lirait
        // « rupture ». Sur ce poste, la lecture est locale : l'échec n'est
        // possible que pour un plat dont le motif d'absence de stock n'est pas
        // du registre (`MotifSansStock.inconnu`) — on ne sait pas lire son
        // stock, le chiffre est absent, il n'est pas nul.
        if (carte.lignes.any(
          (l) =>
              l.portionsVendables == null &&
              l.motifSansStock == MotifSansStock.inconnu,
        ))
          const AvertissementCarte(
            cle: Key('carte-restaurant-stock-non-consulte'),
            // `carte_pwa.commun.stock_non_consulte_detail`, au mot.
            texte:
                "Le stock de cet article n'a pas pu être lu : le chiffre est absent, il n'est pas nul.",
          ),
        switch (onglet) {
          OngletCarte.carteDuJour =>
            carte.lignes.isEmpty
                ? const EtatVideCarteRestaurant()
                : VueCarteDuJour(
                    lignes: carte.lignes,
                    cleFiltre: (
                      ref.watch(rechercheCarteRestaurantProvider),
                      ref.watch(categorieCarteRestaurantProvider),
                      ref.watch(etatCarteRestaurantProvider),
                    ),
                  ),
          OngletCarte.couvertureDuStock => VueCouverture(
            couverture: carte.couverture,
            indicateurs: carte.indicateurs,
          ),
          OngletCarte.ventes => const VueVentesRestaurant(),
        },
      ],
    );
  }

  /// Les six cartes de la vue (l.171-207), dans son ordre — dont deux sans
  /// chiffre.
  ///
  /// **Deux des six chiffres de la vue N'ONT AUCUNE SOURCE ici** (la
  /// disponibilité du jour n'est portée par aucune table) : les retirer serait
  /// supprimer un élément visible, les remplir de zéros affirmerait « aucun plat
  /// retiré » sous un écran qui n'a rien consulté. Elles portent « — » et leur
  /// raison. Les « prix provisoires », eux, sont comptés depuis la v14.
  List<Widget> _cartes(IndicateursCarte k) {
    final taux = double.tryParse(k.tauxCouverture ?? '');

    return [
      CarteKpi(
        cle: const Key('carte-restaurant-kpi-articles'),
        libelle: 'Articles à la carte',
        valeur: '${k.plats}',
        detail: k.disponibles == null ? null : '${k.disponibles} disponible(s)',
        raison: k.raisonAbsence('disponibles'),
      ),
      CarteKpi(
        cle: const Key('carte-restaurant-kpi-retires'),
        libelle: 'Retirés du jour',
        valeur: k.indisponibles == null
            ? CarteIndicateurRestaurant.absent
            : '${k.indisponibles}',
        // `$k['indisponibles'] > 0 ? 'text-amber-600' : 'text-slate-400'`.
        accent: (k.indisponibles ?? 0) > 0
            ? PaletteMaitre.ambre600
            : Ardoise.c400,
        detail: 'Rupture ou retrait',
        raison: k.raisonAbsence('indisponibles'),
      ),
      CarteKpi(
        cle: const Key('carte-restaurant-kpi-lies'),
        libelle: 'Liés au stock',
        valeur: '${k.lies} / ${k.plats}',
        // « — % de couverture » sur une carte vide : le serveur rend `null`,
        // et « 0 % » s'y lirait comme un défaut à corriger.
        detail:
            '${k.tauxCouverture ?? CarteIndicateurRestaurant.absent} % de couverture',
        // `$k['taux_couverture'] < 50` (l.185).
        accent: taux != null && taux < _seuilCouverture
            ? PaletteMaitre.ambre600
            : PaletteMaitre.emeraude600,
      ),
      CarteKpi(
        cle: const Key('carte-restaurant-kpi-sans-lien'),
        libelle: 'Ne décrémentent rien',
        valeur: '${k.sansLien}',
        detail: "Stock surévalué d'autant",
        accent: k.sansLien > 0
            ? PaletteMaitre.rouge600
            : PaletteMaitre.emeraude600,
      ),
      CarteKpi(
        cle: const Key('carte-restaurant-kpi-rupture'),
        libelle: 'En rupture de stock',
        valeur: '${k.enRupture}',
        detail: '${k.sousSeuil} sous seuil',
        accent: k.enRupture > 0 ? PaletteMaitre.rouge600 : Ardoise.c400,
      ),
      CarteKpi(
        cle: const Key('carte-restaurant-kpi-provisoires'),
        libelle: 'Prix provisoires',
        // COMPTÉ des plats depuis la v14 (`plats_local.prix_provisoire`) : un
        // zéro y est une mesure. `null` (un client qui ne compte pas) garde
        // « — » et sa raison.
        valeur:
            k.prixProvisoires?.toString() ?? CarteIndicateurRestaurant.absent,
        // `$k['prix_provisoires'] > 0` : rouge dès qu'il en reste un, gris
        // quand il n'y en a plus (corps l.195).
        accent: (k.prixProvisoires ?? 0) > 0
            ? PaletteMaitre.rouge600
            : Ardoise.c400,
        detail: 'À confronter à la carte',
        raison: k.prixProvisoires == null
            ? k.raisonAbsence('prix_provisoires')
            : null,
      ),
    ];
  }

  /// `$k['taux_couverture'] < 50` — le seuil de la vue (corps l.185).
  static const double _seuilCouverture = 50;
}

/* ====================================================================== */
/* En-tête — corps l.75-144                                                */
/* ====================================================================== */

/// Les cinq boutons de la vue, dans son ordre : « Point de vente » (l.86),
/// « Stocks » (l.88), « Exporter » (l.101), « Imprimer la fiche des prix »
/// (l.108), « Plats, fiches techniques & menus » (l.140).
///
/// Les deux liens et le dernier sont des NAVIGATIONS, rendus à tous comme dans
/// la vue : l'écran visé porte lui-même la garde de son module. Les deux
/// documents sont toujours cliquables, comme dans la vue : sans donnée, ils
/// le DISENT au lieu de rester grisés (un bouton grisé sans explication se lit
/// comme un écran cassé).
class _EnTete extends ConsumerWidget {
  const _EnTete({required this.carte, required this.motifAbsence});

  /// `null` : le serveur n'a rien rendu — [motifAbsence] dit pourquoi.
  final CarteRestaurant? carte;
  final String? motifAbsence;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return EnTeteCarte(
      // `<svg width="24" height="24">` — la fourchette et le couteau
      // (`restaurant/carte.blade.php` l.41).
      icone: Icons.restaurant_outlined,
      titre: 'Carte du restaurant',
      // `carte_pwa.restaurant.sous_titre` : `<strong>calculé</strong>` est
      // rendu gras ; chaque fragment est UN littéral, le comparateur coupe la
      // phrase de la vue à ses balises.
      sousTitre: const [
        TextSpan(
          text:
              'Composition, disponibilité du jour et lien au stock. Le stock affiché est ',
        ),
        TextSpan(
          text: 'calculé',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        TextSpan(text: ', jamais saisi.'),
      ],
      boutons: [
        // `<a href="{{ route('pwa.pos.comptant') }}">` (corps l.86-87).
        BoutonEnteteCarte(
          key: const Key('carte-restaurant-vers-pos'),
          libelle: 'Point de vente',
          style: StyleBoutonEntete.lien,
          onPressed: () => context.go('/pos'),
        ),
        // `<a href="{{ route('pwa.stocks.liste') }}">` (corps l.88-89).
        BoutonEnteteCarte(
          key: const Key('carte-restaurant-vers-stocks'),
          libelle: 'Stocks',
          style: StyleBoutonEntete.lien,
          onPressed: () => context.go('/stocks'),
        ),
        // « Exporter » (l.101-102) : UN bouton, qui exporte l'onglet COURANT.
        BoutonEnteteCarte(
          key: const Key('carte-restaurant-exporter'),
          libelle: TextesExport.bouton,
          style: StyleBoutonEntete.plein,
          onPressed: () => _exporter(context, ref),
        ),
        // « Imprimer la fiche des prix » (l.108-109) : directement, sans
        // modale. Un document qui se LIT, groupé par catégorie.
        BoutonEnteteCarte(
          key: const Key('carte-restaurant-fiche-prix'),
          libelle: 'Imprimer la fiche des prix',
          style: StyleBoutonEntete.or,
          onPressed: () => _fichePrix(context, ref),
        ),
        // L'accès à l'écran du catalogue (restaurant/carte.blade.php l.59 et
        // corps l.139-142, ajout du PO du 04/09/2026) : sans lui, l'écran des
        // plats, des fiches techniques et des menus n'est atteignable par
        // aucun clic (Article 3.3). Une NAVIGATION, pas une action.
        BoutonEnteteCarte(
          key: const Key('carte-restaurant-vers-plats'),
          libelle: TextesCorpsCarte.lienCatalogue,
          style: StyleBoutonEntete.plein,
          onPressed: () => context.go('/restaurant/plats'),
        ),
      ],
    );
  }

  void _dire(BuildContext context, String texte, String cle) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(texte, key: Key(cle))));
  }

  /// Le filtre appliqué, **repris du serveur** et jamais reconstruit ici : un
  /// export DIT son filtre (PA-119), et deux formulations du même filtre
  /// finiraient par diverger.
  String _filtreLisible(CarteRestaurant carte) {
    if (carte.filtresAppliques.isEmpty) return 'Carte complète, aucun filtre';

    return carte.filtresAppliques.entries
        .map((e) => '${e.key} : ${e.value}')
        .join(' · ');
  }

  /// « Exporter » → la modale de format → le tableau AFFICHÉ → le document.
  ///
  /// Une liste vide se **refuse** (PA-119), APRÈS le choix du format, avec la
  /// phrase de la vue : une page blanche remise au Gérant se lit comme « aucun
  /// plat », alors que c'est le filtre qui n'a rien retenu.
  Future<void> _exporter(BuildContext context, WidgetRef ref) async {
    final donnees = carte;
    if (donnees == null) {
      return _dire(
        context,
        motifAbsence ?? '',
        'carte-restaurant-export-indisponible',
      );
    }

    // L'export suit l'ONGLET COURANT (PO 03/09/2026) et la modale NOMME ce
    // qu'elle produira : `carte_pwa.restaurant.export_titre_ventes` sur
    // l'onglet des ventes (`restaurant/carte.blade.php` l.64), le titre de la
    // carte ailleurs.
    //
    // 10/10/2026 : l'onglet « Ventes » OUVRE la modale, comme la vue et comme
    // la carte du bar (`vue_ventes_bar.dart`). Il ne la refusait avant le choix
    // du format que parce que le document ne peut pas exister sur ce poste
    // (aucune table de ventes de plats) ; le refus est conservé, mais il tombe
    // APRÈS le choix, comme celui d'une liste vide plus bas : le titre de la
    // vue (« Exporter — Ventes du Restaurant ») est un élément visible de la
    // vue que ce poste n'avait pas à retirer. Aucun fichier n'est produit.
    final surVentes =
        ref.read(ongletCarteRestaurantProvider) == OngletCarte.ventes;
    // L'onglet des ventes s'exporte lui-même (calculé sur ce poste).
    if (surVentes) return exporterVentesRestaurant(context, ref);
    final format = await choisirFormatExport(
      context,
      titre: 'Exporter — Carte du restaurant',
    );
    if (format == null || !context.mounted) return;

    if (donnees.lignes.isEmpty) {
      return _dire(context, TextesExport.vide, 'carte-restaurant-export-vide');
    }

    final filtres = _filtreLisible(donnees);
    await executerExport(
      context,
      () => switch (format) {
        FormatExport.pdf => ref.read(exporterCarteRestaurantPdfProvider)(
          donnees.lignes,
          filtres,
        ),
        FormatExport.excel => ref.read(exporterCarteRestaurantProvider)(
          donnees.lignes,
          filtres,
        ),
      },
      cleSucces: const Key('carte-restaurant-export-fait'),
    );
  }

  Future<void> _fichePrix(BuildContext context, WidgetRef ref) async {
    final donnees = carte;
    if (donnees == null) {
      return _dire(
        context,
        motifAbsence ?? '',
        'carte-restaurant-fiche-indisponible',
      );
    }
    if (donnees.lignes.isEmpty) {
      return _dire(context, TextesExport.vide, 'carte-restaurant-fiche-vide');
    }

    final ecartes = await ref.read(imprimerFichePrixRestaurantProvider)(
      donnees.lignes,
    );
    if (!context.mounted || ecartes == 0) return;

    // On ne masque pas : un tarif absent devient négociable au comptoir.
    _dire(
      context,
      '$ecartes article(s) sans tarif ont été écartés de la fiche.',
      'carte-restaurant-fiche-ecartes',
    );
  }
}

/* ====================================================================== */
/* Onglets, filtres, bandeau — corps l.211-265                             */
/* ====================================================================== */

/// Les trois onglets — `flex flex-wrap gap-1.5 mb-4` (l.212).
class _Onglets extends ConsumerWidget {
  const _Onglets();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actif = ref.watch(ongletCarteRestaurantProvider);

    return Padding(
      // `mb-4` — 16 px.
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Wrap(
        // `gap-1.5` — 6 px, et non les 8 px de `gap-2`.
        spacing: AppSpacing.xxs,
        runSpacing: AppSpacing.xxs,
        children: [
          for (final o in OngletCarte.values)
            OngletRestaurant(
              cle: Key('onglet-carte-restaurant-${o.cle}'),
              libelle: o.libelle,
              actif: actif == o,
              onChoix: () =>
                  ref.read(ongletCarteRestaurantProvider.notifier).definir(o),
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
      cleRecherche: const Key('carte-restaurant-recherche'),
      onRecherche: (v) =>
          ref.read(rechercheCarteRestaurantProvider.notifier).definir(v),
      categorie: ListeFiltre<CategoriePlat?>(
        cleListe: const Key('carte-restaurant-filtre-categorie'),
        largeur: AppLayout.filtreCategorieCarteRestaurant,
        valeur: ref.watch(categorieCarteRestaurantProvider),
        options: [
          // L'option vide de la vue (`toutes_categories`, l.240).
          const (null, 'Toutes les catégories'),
          for (final c in CategoriePlat.values) (c, c.libelle),
        ],
        onChange: (c) =>
            ref.read(categorieCarteRestaurantProvider.notifier).definir(c),
      ),
      etat: ListeFiltre<EtatArticleCarte>(
        cleListe: const Key('carte-restaurant-filtre-etat'),
        largeur: AppLayout.filtreEtatCarteRestaurant,
        valeur: ref.watch(etatCarteRestaurantProvider),
        options: [for (final e in EtatArticleCarte.values) (e, e.libelle)],
        // Les états sans colonne au schéma restent VISIBLES et ne se
        // sélectionnent pas : les retirer supprimerait un élément de la vue,
        // les laisser actifs ferait échouer l'écran en 422. Une option grisée
        // dit la troisième chose, qui est la vraie — la fonction manque.
        selectionnable: (e) => e.servi,
        onChange: (e) {
          if (e != null) {
            ref.read(etatCarteRestaurantProvider.notifier).definir(e);
          }
        },
      ),
    );
  }
}

/// Le bandeau du rayon — `carte-module.js` archivé l.76-85, vue
/// `restaurant/carte.blade.php` l.43-52 : encadré « amber » (`#FFFBEB` /
/// `#FDE68A` / `#78350F`), `rounded-xl p-3.5 mb-4`.
///
/// Le texte est celui de la vue, au mot (voir l'en-tête de l'écran).
/// Chaque fragment est UN littéral : le comparateur coupe la phrase de la vue à
/// ses balises `<strong>`, et cherche chaque morceau.
class _Bandeau extends StatelessWidget {
  const _Bandeau({required this.indicateurs});

  final IndicateursCarte indicateurs;

  @override
  Widget build(BuildContext context) {
    final fort = styleContenuCarte(
      TaillesContenu.t13,
      poids: FontWeight.bold,
      couleur: PaletteMaitre.ambre900,
    );

    return KeyedSubtree(
      key: const Key('carte-restaurant-bandeau'),
      child: EncadreCarte(
        fond: PaletteMaitre.ambre50,
        bordure: PaletteMaitre.ambre200,
        enfant: Text.rich(
          TextSpan(
            style: styleContenuCarte(
              TaillesContenu.t13,
              couleur: PaletteMaitre.ambre900,
            ),
            children: [
              // `carte_pwa.restaurant.bandeau_titre`.
              TextSpan(
                text:
                    "Un plat n'est pas un article de stock : c'est une recette. ",
                style: fort,
              ),
              // `carte_pwa.restaurant.bandeau_texte`.
              const TextSpan(text: 'Décrémenter un « Poulet DG » suppose une '),
              TextSpan(text: 'fiche technique', style: fort),
              const TextSpan(
                text:
                    " indiquant combien de grammes de poulet, d'huile et d'oignon partent à chaque assiette. ",
              ),
              TextSpan(text: 'Attention :', style: fort),
              TextSpan(
                text:
                    " ${indicateurs.sansLien} article(s) sur ${indicateurs.plats} ne décrémentent rien à la vente. La valeur du stock affichée est donc surévaluée, et l'écart apparaîtra à l'inventaire. Un plat peut néanmoins être rattaché à la main lorsqu'il correspond à un article unique — une bouteille d'eau servie à table, par exemple.",
              ),
            ],
          ),
        ),
      ),
    );
  }
}
