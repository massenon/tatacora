// Vue Blade maîtresse (PA-183) : pwa/vehicules/locations.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/format/formats.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../restaurant/presentation/widgets/coquille_restaurant.dart';
import '../../domain/entities/contrat_location.dart';
import '../../domain/entities/vehicule.dart';
import '../providers_vehicules.dart';

/// L'onglet **« Planning du parc »** de la vue
/// (`vehicules/locations.blade.php` l.463-526).
///
/// ## La grille est CALCULÉE sur les contrats lus une fois
///
/// Les contrats sont lus **une fois**, et l'occupation se déduit de leurs
/// plages. C'est la même donnée que celle sur laquelle le DAO refuse un
/// chevauchement — `contrats_location_local` — et non une seconde vérité : une
/// grille qui compterait autrement montrerait libre une case que l'écriture
/// refuse, ou l'inverse.
///
/// ## Les trois couches de la légende sont celles de la vue
///
/// | Couche | Source |
/// |---|---|
/// | libre | ni louée ni hors service |
/// | location | `contrats_location_local`, bornes demi-ouvertes |
/// | immobilisé | `statut == hors_service` du véhicule (vue l.507, 513) |
///
/// Sans véhicule, la vue rend quand même le titre, la légende et l'en-tête
/// « Véhicule » (l.474-496) : seule la boucle des lignes est vide.
class VuePlanning extends ConsumerWidget {
  const VuePlanning({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final periode = ref.watch(periodeVehiculesProvider);

    // Le maître refuse la grille sans période (l.146-147), avec son texte.
    if (!periode.complete) {
      return const EncadreRestaurant(
        cle: Key('vehicules-planning-sans-periode'),
        ton: TonEncadre.gris,
        titre: 'Choisissez une période.',
        texte: 'Le planning se construit sur une plage de dates.',
      );
    }

    final parc = ref.watch(parcProvider);
    final contrats = ref.watch(contratsProvider);

    final vehicules = switch (parc) {
      AsyncData(value: final v) => v,
      _ => null,
    };
    final lignes = switch (contrats) {
      AsyncData(value: final c) => c,
      _ => null,
    };

    if (parc.isLoading || contrats.isLoading) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (vehicules == null || lignes == null) {
      return const NoteRestaurant(
        cle: Key('vehicules-planning-indisponible'),
        texte:
            'Le planning demande le parc ET les contrats : l’une des deux '
            'lectures n’a rien rendu. Une grille dessinée sur la moitié de la '
            'donnée montrerait des cases libres qui ne le sont pas.',
      );
    }

    // Le planning ne dessine que les jours de la fenêtre. `periode.complete`
    // garantit `jours > 0` (restitution STRICTEMENT après le départ).
    final jours = _jours(periode.debutDate!, periode.jours!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        CadreTableauRestaurant(
          corps: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // `px-4 py-3 border-b flex flex-wrap items-center
              // justify-between gap-2` (vue l.475) : le titre à gauche, la
              // légende à DROITE sur la même rangée (14/10/2026, demande du
              // PO — elle était posée sous le titre).
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Ardoise.c200)),
                ),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    // `planning_titre` (vue l.476) : « Planning du parc — N
                    // jour(s) ».
                    Text(
                      'Planning du parc — ${jours.length} jour(s)',
                      style: TextesRestaurant.titreCadre,
                    ),
                    const _Legende(),
                  ],
                ),
              ),
              _Grille(vehicules: vehicules, contrats: lignes, jours: jours),
            ],
          ),
        ),
        // ⚠ RETIRÉS le 09/10/2026 : les deux encadrés qui suivaient le tableau.
        //  - « Un seul planning pour deux modules » venait de l'ANCIEN maître
        //    (`prototype_v2/pages/m8-locations.html` l.194-196). La vue Blade
        //    (`vehicules/locations.blade.php` l.463-526) n'en pose aucun, et son
        //    commentaire de fin de fichier (l.589) renvoie le planning des
        //    circuits à M9.
        //  - « Ce planning ne voit que les locations » disait que les couches
        //    « circuit » et « immobilisé » du maître étaient absentes. La vue
        //    n'en dessine que TROIS (l.478-480) : libre, location, immobilisé —
        //    ce dernier pour un véhicule `hors_service` (l.507, 513), donnée que
        //    ce poste possède. Il n'y a plus d'écart à signaler : le motif a
        //    cessé d'être vrai, et le garder transformerait une décision en
        //    oubli (PA-144).
      ],
    );
  }

  /// Les [nombre] jours à partir de [debut] — `$joursListe` de la vue
  /// (l.468-473), sans plafond : la vue n'en pose aucun.
  static List<DateTime> _jours(DateTime debut, int nombre) => [
    for (var i = 0; i < nombre; i++)
      DateTime(debut.year, debut.month, debut.day + i),
  ];
}

/// La légende de la vue (l.477-481) — TROIS entrées, dans son ordre.
class _Legende extends StatelessWidget {
  const _Legende();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      // `flex gap-3 text-[11px]`.
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: const [
        _EntreeLegende(
          cle: Key('planning-legende-libre'),
          libelle: 'libre',
          couleur: PaletteMaitre.emeraude50,
          bordure: PaletteMaitre.emeraude200,
        ),
        _EntreeLegende(
          cle: Key('planning-legende-location'),
          libelle: 'location',
          couleur: PaletteMaitre.bleu700,
        ),
        _EntreeLegende(
          cle: Key('planning-legende-immobilise'),
          libelle: 'immobilisé',
          couleur: PaletteMaitre.rouge600,
        ),
      ],
    );
  }
}

class _EntreeLegende extends StatelessWidget {
  const _EntreeLegende({
    required Key cle,
    required this.libelle,
    required this.couleur,
    this.bordure,
  }) : super(key: cle);

  final String libelle;
  final Color couleur;
  final Color? bordure;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          // `w-3 h-3 rounded`.
          width: AppSpacing.sm,
          height: AppSpacing.sm,
          decoration: BoxDecoration(
            color: couleur,
            border: bordure == null ? null : Border.all(color: bordure!),
            borderRadius: BorderRadius.circular(AppRadius.rounded),
          ),
        ),
        const SizedBox(width: AppSpacing.unit),
        Text(libelle, style: TextesRestaurant.mention),
      ],
    );
  }
}

/// La grille — une ligne par véhicule, une colonne par jour.
class _Grille extends StatelessWidget {
  const _Grille({
    required this.vehicules,
    required this.contrats,
    required this.jours,
  });

  final List<Vehicule> vehicules;
  final List<ContratLocation> contrats;
  final List<DateTime> jours;

  /// La colonne « Véhicule » est FIGÉE à gauche (`sticky left-0`, vue l.491 et
  /// l.500) et seuls les jours défilent (`overflow-x-auto`) — demande du PO du
  /// 14/10/2026 : la colonne défilait avec les jours et le nom sortait de
  /// l'écran. Deux blocs côte à côte, rangées de hauteur fixe pour rester
  /// alignées ([AppLayout.hauteurLignePlanning]). La table de la vue est
  /// `w-full` : quand les jours tiennent, leurs cases s'élargissent jusqu'au
  /// bord ; sinon elles gardent leur plancher et défilent.
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, contraintes) {
        final disponible =
            contraintes.maxWidth - AppLayout.colonnePlanningVehicule;
        final largeurCase = jours.isEmpty
            ? AppLayout.caseJourPlanning
            : (disponible / jours.length).clamp(
                AppLayout.caseJourPlanning,
                double.infinity,
              );
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: AppLayout.colonnePlanningVehicule,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _EnteteVehicule(),
                  for (final v in vehicules) _CelluleVehicule(vehicule: v),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                key: const Key('planning-jours-defilement'),
                scrollDirection: Axis.horizontal,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _LigneEntete(jours: jours, largeurCase: largeurCase),
                    for (final v in vehicules)
                      _LigneVehicule(
                        vehicule: v,
                        contrats: contrats,
                        jours: jours,
                        largeurCase: largeurCase,
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// La cellule d'en-tête figée — `px-2 py-2 text-left text-[11px] uppercase
/// tracking-wide text-white/90 font-semibold sticky left-0
/// bg-[var(--navy)]` (vue l.491).
class _EnteteVehicule extends StatelessWidget {
  const _EnteteVehicule();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppLayout.hauteurEntetePlanning,
      color: AppColors.navy,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: const Text('VÉHICULE', style: TextesRestaurant.enteteColonneNavy),
    );
  }
}

/// La cellule figée d'un véhicule — `px-2 py-1.5 text-left sticky left-0
/// bg-white` (vue l.500-503) : le nom, puis « 5 000 FCFA/j ».
class _CelluleVehicule extends StatelessWidget {
  const _CelluleVehicule({required this.vehicule});

  final Vehicule vehicule;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppLayout.hauteurLignePlanning,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      alignment: Alignment.centerLeft,
      decoration: const BoxDecoration(
        color: AppColors.neutre0,
        border: Border(top: BorderSide(color: Ardoise.c100)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            vehicule.immatriculation,
            key: Key('planning-vehicule-${vehicule.id}'),
            style: TextesRestaurant.corpsFort,
            overflow: TextOverflow.ellipsis,
          ),
          // `MontantFcfa::format(tarif_jour)/j` (vue l.502). Un tarif
          // illisible reste « — », jamais « 0 FCFA/j ».
          Text(
            '${formaterMontantDecimal(vehicule.tarifJour, suffixe: 'FCFA') ?? CarteIndicateurRestaurant.absent}/j',
            style: TextesRestaurant.mentionFine,
          ),
        ],
      ),
    );
  }
}

class _LigneEntete extends StatelessWidget {
  const _LigneEntete({required this.jours, required this.largeurCase});

  final List<DateTime> jours;
  final double largeurCase;

  @override
  Widget build(BuildContext context) {
    // `thead class="bg-[var(--navy)]"` (vue l.489) — l'en-tête était posé sur
    // `slate-50` : la vue le peint en navy depuis le 01/09/2026.
    return Container(
      height: AppLayout.hauteurEntetePlanning,
      color: AppColors.navy,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final j in jours)
            SizedBox(
              width: largeurCase,
              child: Text(
                '${j.day}',
                textAlign: TextAlign.center,
                style: TextesRestaurant.mentionFine.copyWith(
                  // `text-[var(--gold)]` le week-end, `text-white/70` sinon
                  // (vue l.493).
                  color: _weekEnd(j)
                      ? AppColors.gold
                      : AppColors.neutre0.withValues(
                          alpha: OpacitesPlanning.jourOuvre,
                        ),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  static bool _weekEnd(DateTime j) =>
      j.weekday == DateTime.saturday || j.weekday == DateTime.sunday;
}

class _LigneVehicule extends StatelessWidget {
  const _LigneVehicule({
    required this.vehicule,
    required this.contrats,
    required this.jours,
    required this.largeurCase,
  });

  final Vehicule vehicule;
  final List<ContratLocation> contrats;
  final List<DateTime> jours;
  final double largeurCase;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppLayout.hauteurLignePlanning,
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Ardoise.c100)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final j in jours)
            _Case(
              largeur: largeurCase,
              vehiculeId: vehicule.id,
              etat: vehicule.statut == StatutVehicule.horsService
                  ? _EtatCase.immobilise
                  : _occupe(j)
                  ? _EtatCase.loue
                  : _EtatCase.libre,
            ),
        ],
      ),
    );
  }

  /// Bornes demi-ouvertes, comme le maître : le jour de restitution est libre.
  bool _occupe(DateTime jour) {
    final iso = _iso(jour);
    // `$c->statut !== 'annule'` (l.510) : un contrat ANNULÉ ne colore plus la
    // case, quel que soit le filtre de statut choisi.
    return contrats.any(
      (c) =>
          !c.annule &&
          c.immatriculation == vehicule.immatriculation &&
          c.debut.compareTo(iso) <= 0 &&
          c.fin.compareTo(iso) > 0,
    );
  }

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// L'état d'une case — `$couleur` de la vue (l.513) : un véhicule hors service
/// est rouge TOUS les jours (l.507), même un jour loué ; sinon bleu si loué,
/// sinon vert.
enum _EtatCase {
  libre(PaletteMaitre.emeraude50, PaletteMaitre.emeraude200),
  loue(PaletteMaitre.bleu700, null),
  immobilise(PaletteMaitre.rouge600, null);

  const _EtatCase(this.fond, this.bordure);

  final Color fond;
  final Color? bordure;
}

class _Case extends StatelessWidget {
  const _Case({
    required this.etat,
    required this.vehiculeId,
    required this.largeur,
  });

  final _EtatCase etat;

  /// La largeur de la colonne du jour — commune à l'en-tête et aux rangées,
  /// pour que les pastilles restent alignées sous leur numéro.
  final double largeur;

  /// Le véhicule de la ligne : la clé de la case le nomme, pour qu'un test
  /// puisse dire QUEL véhicule est rouge (et non seulement combien le sont).
  final String vehiculeId;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: largeur,
      child: Padding(
        // `px-1 py-1.5`.
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.unit,
          vertical: AppSpacing.xxs,
        ),
        child: Container(
          key: Key('planning-case-${etat.name}-$vehiculeId'),
          // `h-4 rounded`.
          height: AppLayout.pastilleJourPlanning,
          decoration: BoxDecoration(
            color: etat.fond,
            // La case « libre » porte la bordure de la vue (l.516).
            border: etat.bordure == null
                ? null
                : Border.all(color: etat.bordure!),
            borderRadius: BorderRadius.circular(AppRadius.rounded),
          ),
        ),
      ),
    );
  }
}
