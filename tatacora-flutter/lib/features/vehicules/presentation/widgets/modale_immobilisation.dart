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
import '../../../../core/di/providers.dart';
import '../providers_vehicules.dart';

/// La modale **« Immobiliser un véhicule »** — `largeur="520px"`.
///
/// @see EF-M8-05 Entretien et carburation
///
/// ## Elle écrit un ENTRETIEN daté (v32, 21/10/2026)
///
/// Comme `Locations::enregistrerImmobilisation` : une ligne
/// `entretiens_vehicule_local` (véhicule, motif du registre fermé, jour, coût en
/// francs) qui part au serveur et s'affiche dans l'onglet « Immobilisations ».
/// **Le statut du véhicule n'est PAS touché** — la PWA non plus (statut ≠
/// disponibilité, RG-02) : pour sortir un véhicule du parc louable, on change
/// son statut depuis sa ligne du parc.
///
/// Jusqu'au 21/10/2026 cette modale ne pouvait que changer le statut, faute de
/// table, et disait que le motif, la date et le coût « disparaîtraient ». Ils
/// sont maintenant écrits.
///
/// ## Un champ reste inerte, et la vue aussi
///
/// « Au » : aucune colonne de fin au schéma du serveur. Le champ garde sa place
/// et le dit.
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
  static String _aujourdhui() {
    final n = DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}-'
        '${n.month.toString().padLeft(2, '0')}-'
        '${n.day.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _cout.dispose();
    super.dispose();
  }

  String? _vehiculeId;
  TypeEntretien _type = TypeEntretien.entretien;
  String? _date = _aujourdhui();
  final _cout = TextEditingController(text: '0');

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
      sousTitre: 'Entretien ou carburation.',
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
          const SizedBox(height: AppSpacing.md),

          // ------------------------- 3, 4 et 5. Du / Au / Coût (l.750-760)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _ChampDate(
                  valeur: _date,
                  erreur: _parChamp['date'],
                  onChoix: (d) => setState(() => _date = d),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              const Expanded(
                child: _ChampInerte(
                  cle: Key('modale-immobilisation-fin'),
                  etiquette: 'Au',
                  raison:
                      'Aucune date de fin n’existe au schéma : une '
                      'immobilisation est un fait daté, enregistré à sa date.',
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const EtiquetteChampRestaurant(
            texte: 'Coût (FCFA)',
            obligatoire: true,
          ),
          TextField(
            key: const Key('modale-immobilisation-cout'),
            controller: _cout,
            keyboardType: TextInputType.number,
            style: TextesModaleRestaurant.corps,
            decoration: InputDecoration(
              isDense: true,
              border: const OutlineInputBorder(),
              errorText: _parChamp['cout'],
              errorMaxLines: 3,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
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

    final date = _date == null ? null : DateTime.tryParse(_date!);
    final cout = int.tryParse(_cout.text.trim().replaceAll(' ', ''));
    final manques = <String, String>{
      if (date == null) 'date': MessagesVehicules.dateEntretienManquante,
      if (cout == null || cout < 0)
        'cout': MessagesVehicules.coutEntretienInvalide,
    };
    if (manques.isNotEmpty) {
      setState(() {
        _envoi = false;
        _parChamp = manques;
      });
      return;
    }

    try {
      await ref
          .read(vehiculeDaoProvider)
          .enregistrerEntretien(
            vehiculeId: vehiculeId,
            type: _type,
            date: date!,
            coutFrancs: cout!,
            auteur: ref.read(sessionProvider)?.login,
          );

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

/// « Du » — le jour de l'immobilisation (sélecteur de date).
class _ChampDate extends StatelessWidget {
  const _ChampDate({
    required this.valeur,
    required this.erreur,
    required this.onChoix,
  });

  final String? valeur;
  final String? erreur;
  final ValueChanged<String?> onChoix;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const EtiquetteChampRestaurant(texte: 'Du', obligatoire: true),
        OutlinedButton(
          key: const Key('modale-immobilisation-date'),
          onPressed: () async {
            final courant = valeur == null ? null : DateTime.tryParse(valeur!);
            final choisi = await showDatePicker(
              context: context,
              initialDate: courant ?? DateTime.now(),
              firstDate: DateTime(DateTime.now().year - 5),
              lastDate: DateTime(DateTime.now().year + 2),
            );
            if (choisi == null) return;
            onChoix(
              '${choisi.year.toString().padLeft(4, '0')}-'
              '${choisi.month.toString().padLeft(2, '0')}-'
              '${choisi.day.toString().padLeft(2, '0')}',
            );
          },
          child: Text(
            valeur ?? 'jj/mm/aaaa',
            style: TextesModaleRestaurant.corps,
          ),
        ),
        if (erreur != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.demi),
            child: Text(
              erreur!,
              style: TextesModaleRestaurant.aide.copyWith(
                color: AppColors.erreur,
              ),
            ),
          ),
      ],
    );
  }
}
