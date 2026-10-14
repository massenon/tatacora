// Vue Blade maîtresse (PA-183) : pwa/tourisme/departs.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/format/formats.dart';
import '../../../../core/theme/app_colors.dart';
// `app_spacing.dart` réexporte `app_radius.dart`.
import '../../../../core/theme/app_spacing.dart';
import '../../../restaurant/presentation/widgets/coquille_modale_restaurant.dart';
import '../../../restaurant/presentation/widgets/coquille_restaurant.dart';
import '../../../restaurant/presentation/widgets/textes_modale_restaurant.dart';
import '../../domain/departs.dart';
import '../../domain/entities/circuit.dart';
import '../../domain/entities/guide.dart';
import '../providers_tourisme.dart';

/// Ouvre **« Réaffecter le guide »** — vue l.747-785. C'est UC-39.
///
/// ## Pourquoi « RÉaffecter », et pas « affecter »
///
/// `reservations_tour.guide_id` est **NOT NULL** (PA-51) : une prestation ne
/// peut pas exister sans guide, donc un départ en a forcément déjà un. Le champ
/// ne peut jamais être vidé — seulement remplacé. Le vocabulaire de tout le
/// module suit le schéma, et ce n'est pas un détail de formulation : un bouton
/// « Affecter » laisserait croire qu'un départ peut partir sans guide.
///
/// ## Elle porte sur le DÉPART entier
///
/// Toutes les lignes actives du couple (circuit, date) changent de guide dans
/// la même transaction. Réaffecter ligne par ligne laisserait deux groupes du
/// même départ partir avec deux guides différents.
Future<bool?> ouvrirModaleGuide(
  BuildContext context, {
  required String circuitId,
  required DateTime date,
}) => showDialog<bool>(
  context: context,
  barrierDismissible: true,
  barrierColor: AppColors.voileModale,
  builder: (_) => _ModaleGuide(circuitId: circuitId, date: date),
);

class _ModaleGuide extends ConsumerStatefulWidget {
  const _ModaleGuide({required this.circuitId, required this.date});

  final String circuitId;
  final DateTime date;

  @override
  ConsumerState<_ModaleGuide> createState() => _ModaleGuideState();
}

class _ModaleGuideState extends ConsumerState<_ModaleGuide> {
  String? _nouveauGuideId;
  bool _envoi = false;
  String? _refus;

  @override
  Widget build(BuildContext context) {
    final guides =
        donneeOuNull(ref.watch(guidesTourismeProvider)) ?? const <Guide>[];
    final circuits =
        donneeOuNull(ref.watch(circuitsProvider)) ?? const <Circuit>[];
    final circuit = circuits.where((c) => c.id == widget.circuitId).firstOrNull;

    final cle = (widget.circuitId, cleDeJour(widget.date));
    final guideActuel = donneeOuNull(ref.watch(guideDuDepartProvider(cle)));

    _nouveauGuideId ??= guides.isEmpty ? null : guides.first.id;

    return CoquilleModaleRestaurant(
      cle: const Key('tourisme-modale-guide'),
      // Le titre de la vue (l.750), au mot.
      titre: 'Réaffecter le guide',
      // Le sous-titre de la vue (l.751) : « :circuit — :date ».
      sousTitre:
          '${circuit?.nom ?? CarteIndicateurRestaurant.absent} — '
          '${formaterDate(widget.date)}',
      largeur: AppLayout.modaleReservationTourisme,
      refus: _refus,
      cleRefus: const Key('tourisme-modale-guide-refus'),
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            // `bg-slate-50 border border-slate-200 rounded-lg p-3`.
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: Ardoise.c50,
              border: Border.all(color: Ardoise.c200),
              borderRadius: BorderRadius.circular(AppRadius.roundedLg),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Le libellé de la vue (l.757), deux-points compris.
                //
                // ⚠ Les deux textes sont FLEXIBLES, et ce n'est pas une
                // précaution de principe : la modale fait 520 px, et le
                // libellé suivi d'un nom de guide un peu long débordait de
                // 51 px — le nom sortait de la boîte, donc l'information que
                // ce bloc existe pour donner. Un `Row` de deux textes nus
                // prend leur largeur naturelle et ne rend jamais la place.
                const Flexible(
                  child: Text(
                    'Guide actuellement affecté :',
                    style: TextesRestaurant.corps,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  child: Text(
                    guideActuel?.nom ?? CarteIndicateurRestaurant.absent,
                    key: const Key('tourisme-guide-actuel'),
                    style: TextesRestaurant.corpsFort,
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          if (guides.isEmpty)
            Text(
              // Le message de la vue (l.763), au mot.
              'Aucun guide au référentiel — une réservation ne peut pas être '
              'prise sans lui (`reservations_tour.guide_id` est NOT NULL).',
              key: const Key('tourisme-guide-aucun-reaffectation'),
              style: TextesRestaurant.secondaire.copyWith(
                color: PaletteMaitre.ambre700,
              ),
            )
          else ...[
            const EtiquetteChampRestaurant(
              texte: 'Nouveau guide',
              obligatoire: true,
            ),
            DropdownButtonFormField<String>(
              key: const Key('tourisme-nouveau-guide'),
              initialValue: _nouveauGuideId,
              isExpanded: true,
              style: TextesModaleRestaurant.corps,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: [
                for (final g in guides)
                  DropdownMenuItem(value: g.id, child: Text(g.nom)),
              ],
              onChanged: (v) => setState(() => _nouveauGuideId = v),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),

          Container(
            padding: const EdgeInsets.all(AppSpacing.xsPlus),
            decoration: BoxDecoration(
              color: Ardoise.c50,
              border: Border.all(color: Ardoise.c200),
              borderRadius: BorderRadius.circular(AppRadius.roundedLg),
            ),
            child: const Text(
              // La note de la vue (l.774), au mot.
              'Il s\'agit d\'une réaffectation : un départ ne peut pas exister '
              'sans guide, celui-ci a donc forcément déjà le sien.',
              key: Key('tourisme-note-reaffectation'),
              style: TextesRestaurant.mention,
            ),
          ),
        ],
      ),
      actions: [
        OutlinedButton(
          key: const Key('tourisme-guide-annuler'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler', style: TextesModaleRestaurant.bouton),
        ),
        FilledButton(
          key: const Key('tourisme-guide-valider'),
          onPressed: _envoi || guides.isEmpty ? null : _reaffecter,
          // Le libellé de la vue (l.782), au mot.
          child: const Text('Réaffecter', style: TextesModaleRestaurant.bouton),
        ),
      ],
    );
  }

  Future<void> _reaffecter() async {
    final nouveau = _nouveauGuideId;
    if (nouveau == null) return;

    setState(() {
      _envoi = true;
      _refus = null;
    });

    try {
      final nombre = await ref
          .read(tourismeDaoProvider)
          .reaffecterGuide(
            circuitId: widget.circuitId,
            date: widget.date,
            nouveauGuideId: nouveau,
          );

      if (!mounted) return;

      rechargerTourisme(ref);
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const Key('tourisme-guide-reaffecte'),
          // Le message de la vue (`tourisme.pwa.guide_reaffecte`), au mot.
          content: Text('Guide réaffecté à $nombre réservation(s) du départ.'),
        ),
      );
    } on RefusTourisme catch (e) {
      if (!mounted) return;
      setState(() {
        _envoi = false;
        _refus = e.message;
      });
    }
  }
}
