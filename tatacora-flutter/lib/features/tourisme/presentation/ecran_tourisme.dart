// Vue Blade maîtresse (PA-183) : pwa/tourisme/departs.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format/formats.dart';
import '../../../core/theme/app_breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../restaurant/presentation/widgets/coquille_restaurant.dart';
import '../domain/departs.dart';
import 'providers_tourisme.dart';
import 'widgets/barre_filtres_tourisme.dart';
import 'widgets/vue_catalogue.dart';
import 'widgets/vue_departs.dart';
import 'widgets/vue_reservations.dart';

/// L'écran **Tourisme** (M9) — départs, circuits et guides.
///
/// @see EF-M9-01 Catalogue de circuits
/// @see EF-M9-03 Réservation avec affectation de guide
/// @see EF-M9-04 Capacité maximale par circuit
/// @see RG-13 Capacité contrôlée cumulée sur le départ
/// @see UC-39 Réaffecter un guide
///
/// ## Il est LOCAL, entièrement — et c'est le premier écrivain de deux tables
///
/// Les trois tables de M9 (`circuits_local`, `guides_local`,
/// `reservations_tour_local`) existent au schéma depuis la v1. Les deux
/// dernières n'avaient **aucun écrivain dans tout le dépôt** avant ce lot : on
/// les lisait, rien ne les remplissait. Un poste neuf ne pouvait donc prendre
/// aucune réservation de circuit — c'est le piège 11 de ce dépôt, rencontré
/// une quatrième fois (après PA-127, PA-128 et PA-129).
///
/// Rien ne part au serveur, et l'écran le dit plutôt que d'afficher un badge
/// « en attente de synchronisation » sur ce qui n'attend rien (PA-59/60/61).
///
/// ## Trois règles portées, et ce qu'elles coûtent
///
/// | Règle | Où elle vit |
/// |---|---|
/// | **RG-13**, capacité cumulée sur le départ | `domain/departs.dart`, appliquée dans la transaction du DAO |
/// | **`guide_id` NOT NULL** : affecter = RÉaffecter | modale « Réaffecter le guide », UC-39 |
/// | **`duree` est un texte libre** : un circuit de plusieurs jours ne bloque que son jour de départ | `dureeIndeterminee()`, et le contrôle de guide borné à la journée |
///
/// ## Ce que la vue ne rend pas à l'écran, et cet écran non plus (09/10/2026)
///
/// La vue a retiré son bloc « non porté » de l'écran (directive du Product
/// Owner du 02/09/2026, `departs.blade.php` l.624-637 : un écran dit ce qu'il
/// FAIT). Ce client portait un panneau « Ce que cet écran ne rend pas » que la
/// vue n'a pas : il est RETIRÉ, et ses raisons sont écrites ici, datées et
/// revérifiées le 09/10/2026 contre `lib/core/database/tables/` :
///
///  - **« + Départ »** : un départ n'est pas une entité (aucune table
///    `departs`), il naît de sa première réservation. La vue refuse ce bouton
///    pour la même raison (l.28-35) ; le geste qui crée un départ est
///    « + Réservation ».
///  - **Colonnes « N° », « Véhicule », « Acompte », « Reste dû », « Indicatif € »** :
///    aucune n'a de colonne (`reservations_tour_local` ne porte ni numéro, ni
///    véhicule, ni acompte ; `circuits_local` ni indicatif). Elles gardent leur
///    place et portent « — » avec leur raison en infobulle : les retirer
///    masquerait que la vue les pose, les remplir inventerait des montants.
///  - **Liste fermée du champ « Thème »** : la vue lit l'énumération MySQL de
///    `circuits.theme` dans `information_schema`. Ce poste ne détient pas ce
///    schéma, et `circuits_local.theme` est un texte libre.
///  - **Motif d'une réaffectation de guide** : aucune colonne ne le porte. Un
///    motif saisi puis jeté laisserait croire que la décision est tracée.
///  - **Le DOCUMENT imprimable de la vue** (`hidden print:block`, l.363-404,
///    l.485-528 et l.588-621) : un état par onglet, qui ne sort qu'au papier
///    — « Réservations tourisme », « Catalogue tourisme », et des colonnes
///    que l'écran n'a pas : « Téléphone », « Prix FCFA », « Indicatif EUR »,
///    « Page catalogue ». NON PORTÉ : ce poste n'imprime pas l'écran (aucune
///    action d'impression de page, et aucun A4 de M9 n'est classé aux visas,
///    PA-192). Ce n'est PAS le fichier de « Exporter » : celui-ci écrit les
///    colonnes de `TourismeExport` (celles de l'écran), relues par un test.
///    « Indicatif EUR » et « Page catalogue » n'ont de toute façon aucune
///    source au schéma ; le téléphone existe (`clients_local.telephone`) et
///    l'écran le montre déjà sous le nom du client. Libellés nommés ici avec
///    les mots de la vue : le comparateur les compte « nommés comme refusés »,
///    PAS « rendus » — la dette n'a pas été réduite par du portage.
///  - **Suppression** d'une prestation, d'une réservation ou d'un départ :
///    interdite (RG-02), tout s'ANNULE. L'annulation libère la place et
///    conserve la ligne (RG-15).
///  - **Arbitrage de la capacité entre DEUX postes** : RG-13 est vérifiée dans
///    la transaction qui insère, ce qui protège CE poste. `reservations_tour`
///    n'est au registre d'aucune synchronisation : deux postes hors ligne
///    peuvent sur-réserver le même départ (même famille que RG-01). Une
///    prestation créée ici reste sur ce poste (note sous le catalogue).
///
/// ## Le bloc de la vue qui est REFUSÉ, et déclaré comme tel
///
/// La modale d'archivage partagée de la vue (`x-pwa.modale-archivage`) est
/// refusée pour une raison de VOCABULAIRE, pas de place : ses mots sont
/// « Confirmer la suppression », « Archivage impossible », « L'élément part aux
/// archives et reste restaurable », « Supprimer définitivement ». Aucun de ces
/// gestes n'existe en M9 : rien n'y est archivé, restauré ni supprimé — une
/// réservation et un départ s'ANNULENT, et la ligne reste en base pour que la
/// trace de ce qui a été encaissé subsiste (RG-02, RG-15). Rendre « Supprimer
/// définitivement » sur un écran qui ne supprime rien serait affirmer un geste
/// qui n'a pas lieu. La confirmation d'annulation de cet écran porte donc les
/// deux phrases que la vue lui passe réellement (« Voulez-vous annuler la
/// réservation … ? », « Voulez-vous annuler le départ … ? ») et son
/// avertissement sur les places déjà vendues. Motif relu le 09/10/2026 : le DAO
/// n'expose aucune archive ni restauration pour M9.
///
///  - blade-refuse:tourisme/departs#modale:modale-archivage
///
/// La modale d'export, elle, n'est PLUS refusée : le bouton « Exporter » ouvre
/// le partiel partagé (`choisirFormatExport`) et écrit le CSV de l'onglet
/// affiché (`BoutonExporterTourisme`). Le choix PDF y est offert et refusé
/// avec son message — aucun état A4 de M9 n'est classé aux visas (PA-192).
class EcranTourisme extends ConsumerWidget {
  const EcranTourisme({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onglet = ref.watch(ongletTourismeProvider);

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppLayout.pageTourisme),
        child: ListView(
          // `max-w-[1600px] mx-auto p-5 lg:p-8` (vue l.85) : 32 px au poste de
          // travail, 20 px en dessous. Le point de rupture est celui de
          // l'ÉCRAN, jamais de la largeur du contenu (Article 5). Relevé
          // navigateur à 1383 px : le titre est à x = 330 = 264 (barre
          // latérale) + 32 + 34 (icône 24 + écart 10).
          padding: EdgeInsets.all(
            MediaQuery.sizeOf(context).width >= AppBreakpoints.lg
                ? AppSpacing.xl
                : AppSpacing.mdPlus,
          ),
          children: [
            const _EnTete(),
            // `mb-5` — 20 px.
            const SizedBox(height: AppSpacing.mdPlus),
            const _Indicateurs(),
            const SizedBox(height: AppSpacing.mdPlus),
            const _Onglets(),
            // `mb-4` — 16 px.
            const SizedBox(height: AppSpacing.md),
            const BarreFiltresTourisme(),
            const SizedBox(height: AppSpacing.md),
            const _LignesIllisibles(),
            switch (onglet) {
              OngletTourisme.departs => const VueDeparts(),
              OngletTourisme.reservations => const VueReservations(),
              OngletTourisme.catalogue => const VueCatalogue(),
            },
          ],
        ),
      ),
    );
  }
}

/// L'en-tête — vue l.88-119 : icône, titre, sous-titre, et le groupe de droite
/// (les deux champs de période, puis « Exporter »).
class _EnTete extends StatelessWidget {
  const _EnTete();

  @override
  Widget build(BuildContext context) {
    return const EnTeteRestaurant(
      // Le repère cartographique de la vue (l.91) : une épingle sur un cercle.
      icone: Icon(
        Icons.place_outlined,
        color: AppColors.navy,
        size: AppLayout.iconeTitrePage,
      ),
      // Le `<h1>` de la vue (l.92), au mot.
      titre: 'Tourisme',
      // Le sous-titre de la vue (l.94), au mot — ses `<strong>` deviennent du
      // texte, la phrase ne change pas.
      sousTitre:
          'Circuits, départs, guides et capacités. La capacité est contrôlée '
          'cumulée sur le départ — jamais réservation par réservation. Un '
          'départ ne peut pas exister sans guide.',
      // `flex flex-wrap gap-2 items-center` (vue l.97) : un seul groupe, aligné
      // au centre — chaque contrôle a sa propre hauteur.
      actions: [_ActionsEnTete()],
    );
  }
}

/// Le groupe de droite de l'en-tête : « du », champ, « au », champ, puis
/// « Exporter » — vue l.97-118.
class _ActionsEnTete extends StatelessWidget {
  const _ActionsEnTete();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      // `gap-2` — 8 px.
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [ChampsPeriodeTourisme(), BoutonExporterTourisme()],
    );
  }
}

/// La bande d'indicateurs — vue l.122-166, **six cartes**, dans son ordre.
class _Indicateurs extends ConsumerWidget {
  const _Indicateurs();

  /// Le seuil d'alerte de la vue (l.139) : en dessous de 50 %, le taux passe
  /// en ambre.
  static const int seuilTauxFaible = 50;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = donneeOuNull(ref.watch(agregatsTourismeProvider));

    final taux = a?.tauxRemplissage;
    final cartes = <Widget>[
      _CarteKpi(
        id: 'departs',
        libelle: 'Départs planifiés',
        valeur: a?.departs.toString(),
        detail: a == null ? null : '${a.complets} complet(s)',
        raison: a == null ? _raisonAbsence : null,
      ),
      _CarteKpi(
        id: 'places',
        libelle: 'Places vendues',
        valeur: a == null ? null : '${a.placesVendues} / ${a.capaciteOfferte}',
        detail: 'Capacité offerte',
        raison: a == null ? _raisonAbsence : null,
      ),
      _CarteKpi(
        id: 'remplissage',
        libelle: 'Taux de remplissage',
        // `null` quand aucune capacité n'est offerte : « 0 % » se lirait comme
        // un départ désert, alors qu'il n'y a rien à remplir (vue l.137-138).
        valeur: taux == null ? null : '${formaterTaux(taux)} %',
        detail: 'Sur la période',
        raison: a == null
            ? _raisonAbsence
            : taux == null
            ? 'Aucune capacité offerte sur la période : il n\'y a rien à '
                  'remplir. « 0 % » se lirait comme un départ désert.'
            : null,
        accent: taux != null && taux < seuilTauxFaible
            ? PaletteMaitre.ambre600
            : null,
      ),
      _CarteKpi(
        id: 'ca',
        // L'apostrophe DROITE de la vue (`kpi_ca`).
        libelle: 'Chiffre d\'affaires',
        valeur: a == null ? null : formaterFcfa(a.chiffreAffaires),
        detail: 'Réservations confirmées',
        raison: a == null ? _raisonAbsence : null,
      ),
      const _CarteKpi(
        id: 'reste',
        libelle: 'Reste à encaisser',
        // Structurellement absent — jamais « 0 FCFA ».
        valeur: null,
        detail: 'Soldes clients',
        raison:
            'Aucun acompte n\'est enregistré sur une réservation de circuit : '
            'le reste à encaisser n\'est pas calculable. Afficher le montant '
            'entier le '
            'présenterait comme impayé.',
      ),
      _CarteKpi(
        id: 'duree',
        libelle: 'Durée indéterminée',
        // VRAI chiffre depuis la v10 (14/09/2026) : `circuits_local.duree`
        // existe et le DAO la lit. `null` ne subsiste que tant qu'aucun départ
        // n'a été lu. Ambre dès qu'il y en a un, ardoise à zéro (vue l.163) :
        // « 0 » y est une MESURE (tous les circuits affichés ont une durée
        // chiffrée), pas une donnée absente.
        valeur: a?.dureeIndeterminee.toString(),
        detail: 'Véhicule sous-bloqué',
        raison: a == null ? _raisonAbsence : null,
        accent: a == null
            ? null
            : a.dureeIndeterminee > 0
            ? PaletteMaitre.ambre600
            : Ardoise.c400,
      ),
    ];

    // `grid grid-cols-2 lg:grid-cols-6 gap-3` (vue l.122). La décision se prend
    // sur `MediaQuery`, jamais sur les contraintes d'un `LayoutBuilder` local :
    // la largeur du contenu n'est pas celle de la fenêtre (Article 5).
    final colonnes = MediaQuery.sizeOf(context).width >= AppBreakpoints.lg
        ? 6
        : 2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var debut = 0; debut < cartes.length; debut += colonnes)
          Padding(
            // `gap-3` — 12 px ENTRE les rangées, pas après la dernière : la
            // grille de la vue n'a pas d'écart final (l.122), seulement `mb-5`.
            padding: EdgeInsets.only(
              bottom: debut + colonnes < cartes.length ? AppSpacing.sm : 0,
            ),
            // `IntrinsicHeight` plutôt qu'un simple `stretch` : une `Row`
            // étirée dans une liste défilante reçoit une hauteur INFINIE et
            // fait exploser la contrainte (rencontré deux fois ici).
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < colonnes; i++) ...[
                    if (i > 0) const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: debut + i < cartes.length
                          ? cartes[debut + i]
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// Aucun départ n'a encore été lu : la lecture locale est en cours, ou la
  /// base est illisible. « — » plutôt qu'un zéro qui aurait l'air d'une mesure.
  static const String _raisonAbsence =
      'Les six chiffres se calculent sur les départs de ce poste, qui ne sont '
      'pas encore lus. « — » plutôt qu\'un zéro qui aurait l\'air d\'une '
      'mesure.';
}

/// Une carte de la bande — la carte du gabarit commun, dont la RAISON d'une
/// absence passe en infobulle.
///
/// Le gabarit commun l'écrit sous le détail, sur jusqu'à six lignes : sur six
/// cartes côte à côte, la plus bavarde fixe la hauteur de la rangée et pousse
/// tout le reste de la page de ~96 px (relevé géométrique du 09/10/2026 : les
/// onglets 95,6 px trop bas). La vue ne pose que trois lignes (libellé, valeur,
/// détail — `departs.blade.php` l.122-166). La raison n'est pas perdue : elle
/// est lue au survol, et « — » reste la valeur affichée (jamais un zéro). Même
/// décision que Véhicules (09/10/2026).
class _CarteKpi extends StatelessWidget {
  const _CarteKpi({
    required this.id,
    required this.libelle,
    required this.valeur,
    required this.detail,
    this.raison,
    this.accent,
  });

  /// `departs`, `places`, `remplissage`, `ca`, `reste`, `duree` : les clés
  /// `tourisme-kpi-<id>` (la carte) et `tourisme-kpi-<id>-raison`
  /// (l'infobulle) en dérivent.
  final String id;
  final String libelle;
  final String? valeur;
  final String? detail;
  final String? raison;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final carte = CarteIndicateurRestaurant(
      cle: Key('tourisme-kpi-$id'),
      libelle: libelle,
      valeur: valeur,
      detail: detail,
      accent: accent,
    );

    return raison == null
        ? carte
        : Tooltip(
            key: Key('tourisme-kpi-$id-raison'),
            message: raison,
            child: carte,
          );
  }
}

/// Les trois onglets — vue l.169-173, dans son ordre, « Départs planifiés »
/// actif par défaut.
class _Onglets extends ConsumerWidget {
  const _Onglets();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actif = ref.watch(ongletTourismeProvider);

    // `flex flex-wrap gap-1.5` — 6 px.
    return Wrap(
      spacing: AppSpacing.xxs,
      runSpacing: AppSpacing.xxs,
      children: [
        for (final o in OngletTourisme.values)
          OngletRestaurant(
            cle: Key('tourisme-onglet-${o.cle}'),
            libelle: o.libelle,
            actif: o == actif,
            onChoix: () => ref.read(ongletTourismeProvider.notifier).definir(o),
          ),
      ],
    );
  }
}

/// Le compte des lignes ILLISIBLES — ce qui n'a pas pu être lu est dit.
///
/// Une ligne dont le statut n'appartient pas au registre fermé est écartée du
/// calcul : la compter comme « réservée » fausserait la capacité d'un départ.
/// La jeter en silence ferait disparaître une réservation payée. Le compte
/// s'affiche donc, et il ne s'affiche **que** s'il y en a.
class _LignesIllisibles extends ConsumerWidget {
  const _LignesIllisibles();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registre = donneeOuNull(ref.watch(registreTourismeProvider));
    final illisibles = registre?.illisibles ?? 0;
    if (illisibles == 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: NoteRestaurant(
        cle: const Key('tourisme-lignes-illisibles'),
        icone: Icons.warning_amber_outlined,
        texte:
            '$illisibles ligne(s) de réservation n\'ont pas pu être lues : '
            'statut inconnu, ou circuit, client ou guide introuvable. Elles '
            'sont exclues des places vendues et du chiffre d\'affaires — leur '
            'prêter un statut fausserait la capacité des départs concernés.',
      ),
    );
  }
}
