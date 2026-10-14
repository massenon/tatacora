// Vue Blade maîtresse (PA-183) : pwa/vehicules/locations.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../restaurant/presentation/widgets/coquille_modale_restaurant.dart';
import '../../../restaurant/presentation/widgets/textes_modale_restaurant.dart';
import '../../domain/entities/contrat_location.dart';
import '../../domain/entities/vehicule.dart';
import '../../domain/regles_vehicules.dart';
import '../providers_vehicules.dart';

/// La modale **« Immobiliser un véhicule »** — `largeur="520px"`.
///
/// @see EF-M8-05 Entretien et carburation
///
/// ## Ce que l'immobilisation PEUT faire sur ce poste, et rien de plus
///
/// `entretiens_vehicule` **n'a aucune table locale** : ni motif, ni date, ni
/// coût n'ont où s'écrire. Le seul effet réel disponible est le **statut du
/// véhicule**, qui existe, et qui commande tout le reste — un véhicule
/// `entretien` n'est plus louable, et la création de contrat le refuse.
///
/// Trois conduites étaient possibles, deux sont des mensonges :
///
/// 1. **Tout collecter et n'écrire que le statut.** Le motif, la date et le
///    coût disparaîtraient en silence sous un « Immobilisation enregistrée » —
///    « un formulaire dont les champs sont collectés puis ignorés »
///    (Article 6), et personne ne saurait que le journal d'entretien n'existe
///    pas.
/// 2. **Retirer la modale.** Un véhicule au garage resterait proposé à la
///    location : c'est la fonction qui compte, pas le formulaire.
/// 3. **La rendre honnête.** Le véhicule change d'état, et les trois champs
///    sans stockage gardent leur place en disant pourquoi ils ne prennent
///    rien.
///
/// C'est la troisième. Le geste utile — sortir un véhicule du parc louable —
/// est tenu ; ce qui n'existe pas est nommé, à sa place.
///
/// ## La promesse de l'ancien maître sur le chevauchement reste non tenue
///
/// Il écrivait : « l'immobilisation passe par le même contrôle de chevauchement
/// qu'une location ». Aucun contrôle de ce genre n'existe — ici comme au
/// serveur, où le contrôleur écrivait en direct. On PEUT donc immobiliser un
/// véhicule déjà loué : son contrat court toujours, et le statut n'y change
/// rien. La modale le dit plutôt que de recopier la promesse.
Future<bool?> ouvrirModaleImmobilisation(BuildContext context) =>
    showDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierColor: AppColors.voileModale,
      builder: (_) => const _ModaleImmobilisation(),
    );

class _ModaleImmobilisation extends ConsumerStatefulWidget {
  const _ModaleImmobilisation();

  @override
  ConsumerState<_ModaleImmobilisation> createState() =>
      _ModaleImmobilisationState();
}

class _ModaleImmobilisationState extends ConsumerState<_ModaleImmobilisation> {
  String? _vehiculeId;
  TypeEntretien _type = TypeEntretien.entretien;

  bool _envoi = false;
  String? _refus;
  Map<String, String> _parChamp = const {};

  @override
  Widget build(BuildContext context) {
    final parc = ref.watch(parcProvider);
    final vehicules = switch (parc) {
      AsyncData(value: final v) => v,
      _ => const <Vehicule>[],
    };

    return CoquilleModaleRestaurant(
      cle: const Key('modale-immobilisation'),
      // Le titre de la vue, au mot.
      titre: 'Immobiliser un véhicule',
      sousTitre: 'Entretien ou carburation — EF-M8-05.',
      largeur: AppLayout.modaleImmobilisation,
      refus: _refus,
      cleRefus: const Key('modale-immobilisation-refus'),
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ----------------------------------------- 1. Véhicule (l.731-737)
          const EtiquetteChampRestaurant(texte: 'Véhicule', obligatoire: true),
          DropdownButtonFormField<String>(
            key: const Key('modale-immobilisation-vehicule'),
            initialValue: vehicules.any((v) => v.id == _vehiculeId)
                ? _vehiculeId
                : null,
            isExpanded: true,
            style: TextesModaleRestaurant.corps,
            decoration: InputDecoration(
              isDense: true,
              border: const OutlineInputBorder(),
              errorText: _parChamp['vehicule_id'],
            ),
            items: [
              for (final v in vehicules)
                DropdownMenuItem(
                  value: v.id,
                  child: Text(
                    v.immatriculation,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (v) => setState(() => _vehiculeId = v),
          ),
          const SizedBox(height: AppSpacing.md),

          // -------------------------------------------- 2. Motif (l.740-748)
          const EtiquetteChampRestaurant(texte: 'Motif', obligatoire: true),
          DropdownButtonFormField<TypeEntretien>(
            key: const Key('modale-immobilisation-motif'),
            initialValue: _type,
            isExpanded: true,
            style: TextesModaleRestaurant.corps,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
            ),
            items: [
              for (final t in TypeEntretien.values)
                DropdownMenuItem(value: t, child: Text(t.libelle)),
            ],
            onChanged: (t) => setState(() => _type = t ?? _type),
          ),
          const SizedBox(height: AppSpacing.xxs),
          const Text(
            // Réécrit le 14/10/2026 (directive du PO) : la liste reste le
            // registre fermé du schéma de référence (`entretien`,
            // `carburation`), aucune table locale ne porte les entretiens.
            'Le motif n’est pas enregistré sur ce poste.',
            key: Key('modale-immobilisation-aide-motif'),
            style: TextesModaleRestaurant.aide,
          ),
          const SizedBox(height: AppSpacing.md),

          // ------------------------- 3, 4 et 5. Du / Au / Coût (l.750-760)
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _ChampInerte(
                  cle: Key('modale-immobilisation-date'),
                  etiquette: 'Du',
                  raison:
                      'Ce poste n’enregistre pas la date d’une '
                      'immobilisation. Le véhicule est immobilisé À PARTIR DE '
                      'MAINTENANT, et il le reste jusqu’à sa remise en service.',
                ),
              ),
              SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _ChampInerte(
                  cle: Key('modale-immobilisation-fin'),
                  etiquette: 'Au',
                  raison:
                      'Aucune date de fin : la remise en service se fait '
                      'depuis la ligne du véhicule, dans le parc.',
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const _ChampInerte(
            cle: Key('modale-immobilisation-cout'),
            etiquette: 'Coût (FCFA)',
            raison:
                'Aucune colonne de coût sur ce poste. Le saisir ici le ferait '
                'disparaître, et la dépense d’entretien ne serait comptabilisée '
                'nulle part — elle relève d’une dépense (M10), pas de cet '
                'écran.',
          ),
          const SizedBox(height: AppSpacing.md),

          // Ce que le geste fait RÉELLEMENT, dit avant de le faire.
          Container(
            key: const Key('modale-immobilisation-note'),
            padding: const EdgeInsets.all(AppSpacing.xsPlus),
            decoration: BoxDecoration(
              color: PaletteMaitre.ambre50,
              border: Border.all(color: PaletteMaitre.ambre200),
              borderRadius: BorderRadius.circular(AppRadius.roundedLg),
            ),
            child: Text(
              'Ce que ce geste fait : le véhicule passe en « Entretien » et '
              'cesse d’être louable — toute nouvelle location le refusera. Ce '
              'qu’il ne fait pas : il n’ouvre aucun journal d’entretien, et '
              'l’onglet « Immobilisations » restera vide. ⚠ Un contrat DÉJÀ '
              'signé sur ce véhicule n’est pas annulé pour autant : il court '
              'toujours, et rien ici ne le libère.',
              style: TextesModaleRestaurant.corps.copyWith(
                color: PaletteMaitre.ambre900,
              ),
            ),
          ),
          if (vehicules.isEmpty && !parc.isLoading) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              'Aucun véhicule n’est enregistré au parc : rien à immobiliser. '
              'Le parc se saisit sur ce poste, par « + Véhicule ».',
              key: const Key('modale-immobilisation-parc-absent'),
              style: TextesModaleRestaurant.corps.copyWith(
                color: PaletteMaitre.ambre900,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          key: const Key('modale-immobilisation-annuler'),
          onPressed: _envoi ? null : () => Navigator.of(context).pop(false),
          child: const Text('Annuler', style: TextesModaleRestaurant.bouton),
        ),
        if (vehicules.isNotEmpty)
          FilledButton(
            key: const Key('modale-immobilisation-valider'),
            onPressed: _envoi ? null : _immobiliser,
            // Le libellé de la vue (l.771), au mot.
            child: const Text(
              'Immobiliser',
              style: TextesModaleRestaurant.bouton,
            ),
          ),
      ],
    );
  }

  Future<void> _immobiliser() async {
    final vehiculeId = _vehiculeId;

    if (vehiculeId == null) {
      setState(
        () => _parChamp = {'vehicule_id': 'Le véhicule est obligatoire.'},
      );
      return;
    }

    setState(() {
      _envoi = true;
      _refus = null;
      _parChamp = const {};
    });

    try {
      await ref
          .read(vehiculeDaoProvider)
          .changerStatut(vehiculeId, StatutVehicule.entretien);

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on RefusVehicule catch (refus) {
      if (!mounted) return;
      setState(() {
        _envoi = false;
        _refus = refus.message;
      });
    }
  }
}

/// Un champ de la vue que rien ne stocke — rendu **à sa place**, inerte, avec
/// sa raison.
class _ChampInerte extends StatelessWidget {
  const _ChampInerte({
    required Key cle,
    required this.etiquette,
    required this.raison,
  }) : super(key: cle);

  final String etiquette;
  final String raison;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        EtiquetteChampRestaurant(texte: etiquette),
        Container(
          padding: const EdgeInsets.all(AppSpacing.xs),
          decoration: BoxDecoration(
            color: Ardoise.c50,
            border: Border.all(color: Ardoise.c200),
            borderRadius: BorderRadius.circular(AppRadius.roundedLg),
          ),
          child: Text(raison, style: TextesModaleRestaurant.aide),
        ),
      ],
    );
  }
}
