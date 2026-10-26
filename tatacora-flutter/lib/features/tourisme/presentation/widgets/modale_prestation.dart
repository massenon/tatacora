// Vue Blade maîtresse (PA-183) : pwa/tourisme/departs.blade.php
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
// `app_spacing.dart` réexporte `app_radius.dart`.
import '../../../../core/theme/app_spacing.dart';
import '../../../restaurant/presentation/widgets/coquille_modale_restaurant.dart';
import '../../../restaurant/presentation/widgets/coquille_restaurant.dart';
import '../../../restaurant/presentation/widgets/textes_modale_restaurant.dart';
import '../../domain/departs.dart';
import '../../domain/entities/circuit.dart';
import '../providers_tourisme.dart';

/// Ouvre la modale **« Prestation »** — vue l.787-843 (EF-M9-01).
///
/// Création quand [circuit] est `null`, édition sinon : ce sont les deux titres
/// de la vue, et un seul formulaire.
Future<bool?> ouvrirModalePrestation(
  BuildContext context, {
  Circuit? circuit,
}) => showDialog<bool>(
  context: context,
  barrierDismissible: true,
  barrierColor: AppColors.voileModale,
  builder: (_) => _ModalePrestation(circuit: circuit),
);

class _ModalePrestation extends ConsumerStatefulWidget {
  const _ModalePrestation({this.circuit});

  final Circuit? circuit;

  @override
  ConsumerState<_ModalePrestation> createState() => _ModalePrestationState();
}

class _ModalePrestationState extends ConsumerState<_ModalePrestation> {
  late final TextEditingController _nom;
  late final TextEditingController _theme;
  late final TextEditingController _zone;
  late final TextEditingController _duree;
  late final TextEditingController _prix;
  late final TextEditingController _capacite;

  bool _envoi = false;
  String? _refus;

  @override
  void initState() {
    super.initState();
    final c = widget.circuit;
    _nom = TextEditingController(text: c?.nom ?? '');
    _theme = TextEditingController(text: c?.theme ?? '');
    _zone = TextEditingController(text: c?.zone ?? '');
    _duree = TextEditingController(text: c?.duree ?? '');
    _prix = TextEditingController(text: c == null ? '' : c.prix.toString());
    _capacite = TextEditingController(
      text: c == null ? '' : c.capaciteMax.toString(),
    );
  }

  @override
  void dispose() {
    _nom.dispose();
    _theme.dispose();
    _zone.dispose();
    _duree.dispose();
    _prix.dispose();
    _capacite.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CoquilleModaleRestaurant(
      cle: const Key('tourisme-modale-prestation'),
      // Les deux titres de la vue (l.789-791), au mot.
      titre: widget.circuit == null
          ? 'Nouvelle prestation au catalogue'
          : 'Éditer la prestation',
      // Le sous-titre de la vue (l.792), au mot — référence EF comprise.
      sousTitre: 'Catalogue des circuits.',
      largeur: AppLayout.modalePrestationTourisme,
      refus: _refus,
      cleRefus: const Key('tourisme-modale-prestation-refus'),
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _champ(
            cle: const Key('tourisme-prestation-nom'),
            etiquette: 'Intitulé',
            controleur: _nom,
          ),
          const SizedBox(height: AppSpacing.sm),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _champTheme()),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _champ(
                  cle: const Key('tourisme-prestation-zone'),
                  etiquette: 'Zone',
                  controleur: _zone,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          // La rangée de TROIS champs de la vue (l.817-834).
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _champ(
                  cle: const Key('tourisme-prestation-duree'),
                  // Le libellé de la vue (l.818). Texte LIBRE : « Plusieurs
                  // jours » est une valeur légitime, et la règle la compte
                  // comme indéterminée plutôt que de la refuser.
                  etiquette: 'Durée',
                  controleur: _duree,
                  // PAS obligatoire : la colonne est nullable des deux côtés.
                  obligatoire: false,
                  // L'invite de la vue (l.818-823), au mot.
                  invite: 'Ex. 3 jours / 2 nuits',
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _champ(
                  cle: const Key('tourisme-prestation-prix'),
                  // Le libellé de la vue (l.825), au mot.
                  etiquette: 'Prix par personne (FCFA)',
                  controleur: _prix,
                  chiffresSeulement: true,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _champ(
                  cle: const Key('tourisme-prestation-capacite'),
                  etiquette: 'Capacité maximale',
                  controleur: _capacite,
                  chiffresSeulement: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          // La capacité saisie ici est celle que RG-13 opposera aux
          // réservations : le dire à l'endroit où on la saisit évite de
          // chercher plus tard d'où vient un refus.
          Container(
            padding: const EdgeInsets.all(AppSpacing.xsPlus),
            decoration: BoxDecoration(
              color: Ardoise.c50,
              border: Border.all(color: Ardoise.c200),
              borderRadius: BorderRadius.circular(AppRadius.roundedLg),
            ),
            child: const Text(
              'La capacité maximale est celle qui sera opposée aux '
              'réservations, cumulée sur chaque départ. La prestation est '
              'enregistrée sur ce poste et n\'est proposée sur aucun autre.',
              key: Key('tourisme-note-prestation-locale'),
              style: TextesRestaurant.mention,
            ),
          ),
        ],
      ),
      actions: [
        OutlinedButton(
          key: const Key('tourisme-prestation-annuler'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler', style: TextesModaleRestaurant.bouton),
        ),
        FilledButton(
          key: const Key('tourisme-prestation-valider'),
          onPressed: _envoi ? null : _enregistrer,
          // Le libellé de la vue (l.840), au mot.
          child: const Text(
            'Enregistrer',
            style: TextesModaleRestaurant.bouton,
          ),
        ),
      ],
    );
  }

  /// [obligatoire] était CODÉ EN DUR à `true` jusqu'au 14/09/2026, ce qui
  /// convenait aux quatre champs d'alors. Le cinquième — « Durée » — ne l'est
  /// pas : `circuits.duree` est nullable au serveur, la vue n'en exige rien et
  /// le DAO accepte le vide. L'astérisque rouge aurait affirmé une contrainte
  /// qui n'existe nulle part.
  ///
  /// [invite] porte le `placeholder` de la vue, quand elle en pose un.
  Widget _champ({
    required Key cle,
    required String etiquette,
    required TextEditingController controleur,
    bool chiffresSeulement = false,
    bool obligatoire = true,
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

  /// Le champ « Thème ».
  ///
  /// ÉCART DÉLIBÉRÉ — vue l.803-807.
  /// La vue : une **liste fermée**, dont les options sont lues dans
  /// l'énumération MySQL de `circuits.theme` (`themesDuCatalogue()` interroge
  /// `information_schema`).
  /// Ici : un champ texte.
  /// Raison : `circuits_local.theme` est une colonne TEXTE libre, et
  /// l'énumération vit dans un schéma MySQL que ce poste ne détient pas.
  /// Fabriquer une liste à partir des thèmes déjà présents au catalogue
  /// interdirait d'en créer le premier ; en recopier une en dur ici figerait
  /// une énumération serveur que personne ne relirait le jour où elle
  /// changerait. Le champ dit ce qu'il est.
  Widget _champTheme() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const EtiquetteChampRestaurant(texte: 'Thème', obligatoire: true),
        TextField(
          key: const Key('tourisme-prestation-theme'),
          controller: _theme,
          style: TextesModaleRestaurant.corps,
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
            helperText: 'Texte libre sur ce poste',
            helperStyle: TextesModaleRestaurant.aide,
          ),
        ),
      ],
    );
  }

  Future<void> _enregistrer() async {
    final prix = int.tryParse(_prix.text.trim());
    final capacite = int.tryParse(_capacite.text.trim());

    if (_nom.text.trim().isEmpty ||
        _theme.text.trim().isEmpty ||
        _zone.text.trim().isEmpty ||
        prix == null ||
        capacite == null) {
      setState(
        () => _refus =
            'Intitulé, thème, zone, prix par personne et capacité maximale '
            'sont tous obligatoires.',
      );
      return;
    }

    setState(() {
      _envoi = true;
      _refus = null;
    });

    try {
      final circuit = await ref
          .read(tourismeDaoProvider)
          .enregistrerCircuit(
            id: widget.circuit?.id,
            nom: _nom.text,
            theme: _theme.text.trim(),
            zone: _zone.text,
            prix: prix,
            capaciteMax: capacite,
            duree: _duree.text,
          );

      if (!mounted) return;

      rechargerTourisme(ref);
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const Key('tourisme-prestation-enregistree'),
          // Le message de la vue (`tourisme.pwa.circuit_enregistre`), au mot —
          // guillemets français compris.
          content: Text(
            'Prestation « ${circuit.nom} » enregistrée au catalogue.',
          ),
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

// ⚠ `_ChampDureeInerte` est RETIRÉ le 14/09/2026. Il tenait la place du champ
// « Durée » de la vue (l.818-823) en disant qu'une saisie « serait acceptée
// puis perdue » — vrai tant que `circuits_local` n'avait pas la colonne, faux
// dès la v10, livrée le matin même. Le champ enregistre désormais réellement.
