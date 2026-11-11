// Vue Blade maîtresse (PA-183) : pwa/tourisme/departs.blade.php
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../restaurant/presentation/widgets/coquille_modale_restaurant.dart';
import '../../../restaurant/presentation/widgets/textes_modale_restaurant.dart';
import '../../domain/departs.dart';
import '../../domain/entities/guide.dart';
import '../providers_tourisme.dart';

/// Ouvre **« Ajouter un guide touristique »** au-dessus de « Réserver des
/// places ». Rend le guide créé (`null` : abandon), que la réservation
/// sélectionne dans la foulée.
///
/// Le guide est écrit par le DAO du poste et enfilé à la synchronisation : sa
/// fiche rejoint le référentiel du serveur.
Future<Guide?> ouvrirModaleAjoutGuide(BuildContext context) =>
    showDialog<Guide>(
      context: context,
      barrierDismissible: true,
      barrierColor: AppColors.voileModale,
      builder: (_) => const _ModaleAjoutGuide(),
    );

class _ModaleAjoutGuide extends ConsumerStatefulWidget {
  const _ModaleAjoutGuide();

  @override
  ConsumerState<_ModaleAjoutGuide> createState() => _ModaleAjoutGuideState();
}

class _ModaleAjoutGuideState extends ConsumerState<_ModaleAjoutGuide> {
  final _nom = TextEditingController();
  final _certification = TextEditingController();
  final _zone = TextEditingController();
  final _tarif = TextEditingController();

  bool _envoi = false;
  String? _refus;

  @override
  void dispose() {
    _nom.dispose();
    _certification.dispose();
    _zone.dispose();
    _tarif.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CoquilleModaleRestaurant(
      cle: const Key('tourisme-modale-ajout-guide'),
      titre: 'Ajouter un guide touristique',
      sousTitre:
          'Le guide rejoint le référentiel et se sélectionne dans la '
          'réservation.',
      largeur: AppLayout.modaleAjoutGuideTourisme,
      refus: _refus,
      cleRefus: const Key('tourisme-modale-ajout-guide-refus'),
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _champ(
            cle: const Key('tourisme-guide-nom'),
            etiquette: 'Nom du guide',
            controleur: _nom,
            obligatoire: true,
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _champ(
                  cle: const Key('tourisme-guide-certification'),
                  etiquette: 'Certification',
                  controleur: _certification,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _champ(
                  cle: const Key('tourisme-guide-zone'),
                  etiquette: 'Zone de compétence',
                  controleur: _zone,
                  invite: 'Ex. Nord Bénin',
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _champ(
            cle: const Key('tourisme-guide-tarif'),
            etiquette: 'Tarif journalier',
            controleur: _tarif,
            obligatoire: true,
            chiffresSeulement: true,
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
          onPressed: _envoi ? null : _enregistrer,
          child: const Text(
            'Ajouter le guide',
            style: TextesModaleRestaurant.bouton,
          ),
        ),
      ],
    );
  }

  Widget _champ({
    required Key cle,
    required String etiquette,
    required TextEditingController controleur,
    bool obligatoire = false,
    bool chiffresSeulement = false,
    String? invite,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        EtiquetteChampRestaurant(texte: etiquette, obligatoire: obligatoire),
        TextField(
          key: cle,
          controller: controleur,
          keyboardType: chiffresSeulement ? TextInputType.number : null,
          inputFormatters: chiffresSeulement
              ? [FilteringTextInputFormatter.digitsOnly]
              : null,
          style: TextesModaleRestaurant.corps,
          decoration: InputDecoration(
            hintText: invite,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  Future<void> _enregistrer() async {
    final tarif = int.tryParse(_tarif.text.trim());

    if (_nom.text.trim().isEmpty || tarif == null) {
      setState(
        () => _refus = 'Le nom et le tarif journalier sont obligatoires.',
      );
      return;
    }

    setState(() {
      _envoi = true;
      _refus = null;
    });

    try {
      final guide = await ref
          .read(tourismeDaoProvider)
          .enregistrerGuide(
            nom: _nom.text,
            certification: _certification.text,
            zoneCompetence: _zone.text,
            tarifJourFrancs: tarif,
          );

      if (!mounted) return;

      rechargerTourisme(ref);
      Navigator.of(context).pop(guide);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const Key('tourisme-guide-cree'),
          content: Text('Guide « ${guide.nom} » ajouté au référentiel.'),
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
