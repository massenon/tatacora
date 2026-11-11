// Vue Blade maîtresse (PA-183) : pwa/tourisme/departs.blade.php
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
// `app_spacing.dart` réexporte `app_radius.dart`.
import '../../../../core/theme/app_spacing.dart';
import '../../../restaurant/presentation/widgets/coquille_modale_restaurant.dart';
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
  String? _theme;
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
    // Premier thème du registre à la création, comme la vue (l.407 du composant).
    _theme = c?.theme ?? themesCircuit.first;
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
                  etiquette: 'Prix par personne',
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

  /// Le champ « Thème » — vue l.802-808 : une liste FERMÉE.
  ///
  /// Les options sont celles du registre du serveur (`themesCircuit`), « Autre »
  /// comprise. Un thème hérité d'une saisie libre d'avant ce registre reste
  /// offert tant que la fiche le porte, pour ne pas être changé sans que
  /// l'exploitant l'ait choisi.
  Widget _champTheme() {
    final options = [
      ...themesCircuit,
      if (_theme != null && !themesCircuit.contains(_theme)) _theme!,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const EtiquetteChampRestaurant(texte: 'Thème', obligatoire: true),
        DropdownButtonFormField<String>(
          key: const Key('tourisme-prestation-theme'),
          initialValue: _theme,
          isExpanded: true,
          style: TextesModaleRestaurant.corps,
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
          ),
          items: [
            for (final t in options)
              DropdownMenuItem(value: t, child: Text(libelleTheme(t))),
          ],
          onChanged: (v) => setState(() => _theme = v),
        ),
      ],
    );
  }

  Future<void> _enregistrer() async {
    final prix = int.tryParse(_prix.text.trim());
    final capacite = int.tryParse(_capacite.text.trim());

    if (_nom.text.trim().isEmpty ||
        _theme == null ||
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
            theme: _theme!,
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
