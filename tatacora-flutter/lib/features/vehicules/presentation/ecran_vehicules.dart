// Vue Blade maîtresse (PA-183) : pwa/vehicules/locations.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format/formats.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_breakpoints.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared_widgets/bouton_standard.dart';
// Le gabarit de tableau, la carte d'indicateur, l'onglet, l'encadré et le bloc
// « ce qui n'est pas rendu » de la vue vivent dans `features/restaurant/`
// parce que M4 a été livré le premier. Les réécrire ici en donnerait deux
// copies, et « deux listes décrivant la même chose divergeront — ce n'est
// qu'une question de temps » (Article 10).
//
// ⚠ Le NOM de ces briques dit « Restaurant » alors qu'elles portent le gabarit
// commun. L'arbitrage du renommage est ouvert, il n'est pas tranché ici en
// silence.
import '../../restaurant/presentation/widgets/coquille_restaurant.dart';
import '../domain/indicateurs_vehicules.dart';
import 'providers_vehicules.dart';
import 'widgets/barre_filtres_vehicules.dart';
import 'widgets/modale_contrat.dart';
import 'widgets/modale_immobilisation.dart';
import 'widgets/modale_vehicule.dart';
import 'widgets/vue_contrats.dart';
import 'widgets/vue_immobilisations.dart';
import 'widgets/vue_parc.dart';
import 'widgets/vue_planning.dart';

/// L'écran **Véhicules & Locations**.
///
/// @see EF-M8-01 Référentiel véhicules
/// @see EF-M8-02 Disponibilité et planning
/// @see EF-M8-03 Contrat de location
/// @see EF-M8-05 Entretien et carburation
/// @see RG-08 Chevauchement de location
/// @see RG-09 Pièce d'identité et permis de conduire
///
/// ## TOUT EST LOCAL — décision du Product Owner, 14/09/2026
///
/// ⚠ Cet en-tête portait « EN LIGNE SEULEMENT, sans cache » et « le parc est en
/// lecture seule par l'API ». Les deux sont **faux** depuis le passage zéro
/// réseau : il n'y a plus d'API, et `vehicules_local` n'avait plus aucun
/// écrivain — un poste neuf n'avait pas un seul véhicule, donc pas un seul
/// contrat possible. Le parc **se saisit sur ce poste**, et les deux tables de
/// M8 sont lues et écrites par `VehiculeDao`.
///
/// Ne rétablissez pas la mention « lecture seule » : c'est exactement la
/// phrase périmée que PA-144 décrit — un motif de refus qui a cessé d'être vrai
/// transforme une décision en oubli, et personne ne rouvre la question puisque
/// le code dit que c'est impossible.
///
/// ## RG-08 et RG-09 se tiennent désormais ICI
///
/// Elles vivaient dans `ContratLocationService`, sous verrou pessimiste. Le
/// DAO les applique dans la transaction qui insère. Un seul poste utilise le
/// logiciel : c'est le seul arbitre du double-booking, et il n'a plus d'arbitre
/// au-dessus de lui.
///
/// ## Ce qui n'est pas rendu, en un coup d'œil
///
/// Le détail vit au code de chaque onglet (le bloc affiché « Ce que cet écran
/// ne rend pas » est retiré le 14/10/2026, directive du PO). En résumé :
///
/// | Élément de la vue | État |
/// |---|---|
/// | Parc & disponibilité | rendu, avec création, édition et archivage |
/// | Contrats | rendu — 4 colonnes sur 10 sans source, nommées |
/// | Planning du parc | rendu — les 3 couches de la vue (libre, location, immobilisé = hors service) |
/// | Immobilisations | **vide** — en-têtes et message de la vue, aucune table locale, et un encadré le dit |
/// | Annulation d'un contrat | **refusée** — PA-50, aucune colonne de statut |
class EcranVehicules extends ConsumerWidget {
  const EcranVehicules({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onglet = ref.watch(ongletVehiculesProvider);

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        // `max-w-[1600px] mx-auto p-5 lg:p-8` (vue l.84) : 32 px au poste de
        // travail, 20 px en dessous. Le point de rupture est celui de l'ÉCRAN,
        // jamais de la largeur du contenu (Article 5). Relevé navigateur à
        // 1383 px : le titre est à x = 330 = 264 (barre latérale) + 32 + 34
        // (icône 24 + gap 10).
        constraints: const BoxConstraints(maxWidth: AppLayout.pageVehicules),
        child: ListView(
          padding: EdgeInsets.all(
            MediaQuery.sizeOf(context).width >= AppBreakpoints.lg
                ? AppSpacing.xl
                : AppSpacing.mdPlus,
          ),
          children: [
            const EnTeteVehicules(),
            // `mb-5` — 20 px.
            const SizedBox(height: AppSpacing.mdPlus),
            const _Indicateurs(),
            const SizedBox(height: AppSpacing.mdPlus),
            const _Onglets(),
            // `mb-4` — 16 px.
            const SizedBox(height: AppSpacing.md),
            const BarreFiltresVehicules(),
            const SizedBox(height: AppSpacing.md),
            switch (onglet) {
              OngletVehicules.parc => const VueParc(),
              OngletVehicules.contrats => const VueContrats(),
              OngletVehicules.planning => const VuePlanning(),
              OngletVehicules.immobilisations => const VueImmobilisations(),
            },
            // Le bloc « Ce que cet écran ne rend pas » qui suivait est RETIRÉ
            // (directive absolue du PO, 14/10/2026) : la page se termine après
            // le tableau ou l'état vide, comme la vue. Les écarts restent
            // nommés au code, dans les widgets qui les portent.
          ],
        ),
      ),
    );
  }
}

/// L'en-tête de la vue : titre, sous-titre, et les contrôles de droite.
class EnTeteVehicules extends ConsumerWidget {
  const EnTeteVehicules({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return EnTeteRestaurant(
      // Le bus de la vue.
      icone: const Icon(
        Icons.directions_bus_outlined,
        color: AppColors.navy,
        size: AppLayout.iconeTitrePage,
      ),
      // Le titre de la vue, au mot — esperluette comprise.
      titre: 'Véhicules & Locations',
      // Le sous-titre de `vehicules.pwa.sous_titre`, au mot.
      sousTitre:
          'Parc, contrats de location, planning et immobilisations. Un '
          'véhicule loué ou immobilisé pour entretien n\'est proposé nulle part '
          'ailleurs.',
      // `flex flex-wrap gap-2 items-center` (vue l.96) : un seul groupe, aligné
      // au centre — chaque contrôle a sa propre hauteur.
      actions: [_ActionsEnTete()],
    );
  }
}

/// Le groupe de droite de l'en-tête : « du », champ, « au », champ, puis
/// « Exporter » — vue l.96-117.
class _ActionsEnTete extends StatelessWidget {
  const _ActionsEnTete();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      // `gap-2` — 8 px.
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [ChampsPeriodeVehicules(), BoutonExporterVehicules()],
    );
  }
}

/// La bande d'indicateurs — **six cartes**, dans l'ordre de la vue.
class _Indicateurs extends ConsumerWidget {
  const _Indicateurs();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final k = ref.watch(indicateursVehiculesProvider);
    final indicateurs = switch (k) {
      AsyncData(value: final v) => v,
      _ => null,
    };

    // `grid grid-cols-2 lg:grid-cols-6 gap-3`. La décision se prend sur
    // `MediaQuery`, jamais sur `constraints.maxWidth` d'un `LayoutBuilder`
    // local — la largeur du contenu n'est pas celle de la fenêtre (Article 5).
    final large = MediaQuery.sizeOf(context).width >= AppBreakpoints.lg;

    final cartes = <Widget>[
      _CarteKpi(
        id: 'parc',
        libelle: 'Parc',
        valeur: indicateurs?.parc.toString(),
        detail: indicateurs == null
            ? null
            : indicateurs.immobilises > 0
            ? '${indicateurs.immobilises} immobilisé(s)'
            // Le second libellé de la vue, au mot.
            : 'Aucune immobilisation',
        raison: indicateurs == null ? _raisonAbsence : null,
      ),
      _CarteKpi(
        id: 'contrats',
        libelle: 'Contrats actifs',
        valeur: indicateurs?.contratsSurPeriode.toString(),
        // La vue écrit « N annulé(s) » (`kpi_contrats_detail`). L'annulation
        // n'existe pas : écrire « 0 annulé(s) » annoncerait une bonne nouvelle
        // que personne n'a vérifiée. Le N devient « — », la phrase garde sa
        // forme, et la raison est dans l'infobulle de la carte.
        detail: indicateurs == null ? null : '— annulé(s)',
        raison: indicateurs == null
            ? _raisonAbsence
            : IndicateursVehicules.raisons['contrats_annules'],
      ),
      _CarteKpi(
        id: 'ca',
        // L'apostrophe DROITE de `vehicules.pwa.kpi_ca`.
        libelle: "Chiffre d'affaires",
        valeur: formaterMontantDecimal(
          indicateurs?.chiffreAffaires,
          suffixe: 'FCFA',
        ),
        detail: indicateurs == null
            ? null
            : '${indicateurs.joursLoues} jour(s) loué(s)',
        raison: indicateurs?.chiffreAffaires == null
            ? IndicateursVehicules.raisons['chiffre_affaires']
            : null,
      ),
      _CarteKpi(
        id: 'occupation',
        // L'apostrophe DROITE de `vehicules.pwa.kpi_occupation`.
        libelle: "Taux d'occupation",
        valeur: indicateurs?.tauxOccupation == null
            ? null
            : '${indicateurs!.tauxOccupation} %',
        // Le détail de la vue est posé même quand le taux est « — » (l.148-149).
        detail: 'Sur la période',
        raison: indicateurs?.tauxOccupation == null
            ? IndicateursVehicules.raisons['taux_occupation']
            : null,
      ),
      _CarteKpi(
        id: 'reste',
        libelle: 'Reste à encaisser',
        // Structurellement absent — jamais « 0 FCFA ».
        valeur: null,
        detail: 'Soldes de location',
        raison: IndicateursVehicules.raisons['reste_a_encaisser'],
      ),
      _CarteKpi(
        id: 'jours',
        libelle: 'Jours loués',
        valeur: indicateurs?.joursLoues.toString(),
        detail: 'Toutes catégories',
        raison: indicateurs == null ? _raisonAbsence : null,
      ),
    ];

    // `grid-cols-2 lg:grid-cols-6` — les deux valeurs de la vue.
    final colonnes = large ? 6 : 2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var debut = 0; debut < cartes.length; debut += colonnes)
          Padding(
            // `gap-3` — 12 px ENTRE les rangées, pas après la dernière : la
            // grille de la vue n'a pas d'écart final (l.121), seulement `mb-5`.
            padding: EdgeInsets.only(
              bottom: debut + colonnes < cartes.length ? AppSpacing.sm : 0,
            ),
            // `IntrinsicHeight` et non `CrossAxisAlignment.stretch` seul : une
            // `Row` étirée dans une liste défilante reçoit une hauteur INFINIE
            // et fait exploser la contrainte (doctrine §3.3, rencontré deux
            // fois dans ce dépôt).
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

  /// ⚠ Ce texte disait « le serveur n'a pas rendu le parc ou les contrats ».
  /// Il n'y a plus de serveur : ce qui reste possible est une lecture locale
  /// encore en cours, ou une base illisible — deux situations qui ne
  /// s'attendent pas de la même façon.
  static const String _raisonAbsence =
      'Les six chiffres se calculent sur le parc et les contrats de ce poste, '
      'qui ne sont pas encore lus. « — » plutôt qu’un zéro qui aurait l’air '
      'd’une mesure.';
}

/// Une carte de la bande — la carte du gabarit commun, dont la RAISON d'une
/// absence passe en infobulle.
///
/// Le gabarit commun l'écrit sous le détail, sur jusqu'à six lignes : sur six
/// cartes côte à côte, la plus bavarde fixe la hauteur de la rangée et pousse
/// tout le reste de la page de ~96 px (relevé géométrique du 09/10/2026 : les
/// onglets 96,6 px trop bas). La vue ne pose que deux lignes (libellé, valeur,
/// détail — `locations.blade.php` l.122-163). La raison n'est pas perdue : elle
/// est lue au survol, et « — » reste la valeur affichée (jamais un zéro).
class _CarteKpi extends StatelessWidget {
  const _CarteKpi({
    required this.id,
    required this.libelle,
    required this.valeur,
    required this.detail,
    this.raison,
  });

  /// `parc`, `contrats`, `ca`, `occupation`, `reste`, `jours` : les clés
  /// `vehicules-kpi-<id>` (la carte) et `vehicules-kpi-<id>-raison`
  /// (l'infobulle) en dérivent.
  final String id;
  final String libelle;
  final String? valeur;
  final String? detail;
  final String? raison;

  @override
  Widget build(BuildContext context) {
    final carte = CarteIndicateurRestaurant(
      cle: Key('vehicules-kpi-$id'),
      libelle: libelle,
      valeur: valeur,
      detail: detail,
    );

    return raison == null
        ? carte
        : Tooltip(
            key: Key('vehicules-kpi-$id-raison'),
            message: raison,
            child: carte,
          );
  }
}

/// Les quatre onglets, dans l'ordre de la vue, « Parc & disponibilité » actif
/// par défaut.
class _Onglets extends ConsumerWidget {
  const _Onglets();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actif = ref.watch(ongletVehiculesProvider);

    // `flex flex-wrap gap-1.5` — 6 px.
    return Wrap(
      spacing: AppSpacing.xxs,
      runSpacing: AppSpacing.xxs,
      children: [
        for (final o in OngletVehicules.values)
          OngletRestaurant(
            cle: Key('vehicules-onglet-${o.cle}'),
            libelle: o.libelle,
            actif: o == actif,
            onChoix: () =>
                ref.read(ongletVehiculesProvider.notifier).definir(o),
          ),
      ],
    );
  }
}

/// Les trois boutons d'action de la barre de filtres — l'ordre de la vue
/// (l.199-204) : « + Véhicule », « Immobiliser », « + Contrat ».
///
/// Ils vivent ici parce que la barre de filtres n'a pas à connaître les
/// modales : elle porte des filtres, ces trois-là ouvrent des formulaires.
class ActionsVehicules extends ConsumerWidget {
  const ActionsVehicules({super.key});

  /// Le bouton d'action standard (`shared_widgets/bouton_standard.dart`,
  /// demande du PO du 14/10/2026) : `px-3.5 py-2 rounded-lg border` pour les
  /// deux secondaires (vue l.200-202), `px-4 py-2 bg-[var(--navy)]
  /// font-semibold` pour « + Contrat » (l.204). Les secondaires étaient en
  /// `font-semibold` ici, la vue ne le pose pas : corrigé.
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Wrap(
      // `gap-2.5` (vue l.176) — 10 px entre les boutons d'action.
      spacing: AppSpacing.xsPlus,
      runSpacing: AppSpacing.xsPlus,
      children: [
        BoutonStandard(
          key: const Key('vehicules-nouveau-vehicule'),
          onPressed: () => _nouveauVehicule(context, ref),
          // Le libellé de la vue, signe « + » compris.
          libelle: '+ Véhicule',
        ),
        BoutonStandard(
          key: const Key('vehicules-immobiliser'),
          onPressed: () => _immobiliser(context, ref),
          // Le libellé de la vue, au mot.
          libelle: 'Immobiliser',
        ),
        BoutonStandard(
          key: const Key('vehicules-nouveau-contrat'),
          variante: VarianteBouton.primaire,
          onPressed: () => _nouveauContrat(context, ref),
          // Le libellé de la vue, signe « + » compris.
          libelle: '+ Contrat',
        ),
      ],
    );
  }

  static Future<void> _nouveauVehicule(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final ecrit = await ouvrirModaleVehicule(context);
    if (ecrit == true) rechargerVehicules(ref);
  }

  static Future<void> _immobiliser(BuildContext context, WidgetRef ref) async {
    final ecrit = await ouvrirModaleImmobilisation(context);
    if (ecrit == true) rechargerVehicules(ref);
  }

  static Future<void> _nouveauContrat(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final cree = await ouvrirModaleContrat(context);
    if (cree == true) rechargerVehicules(ref);
  }
}
