// Vue Blade maîtresse (PA-183) : pwa/vehicules/locations.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../restaurant/presentation/widgets/coquille_modale_restaurant.dart';
import '../../../restaurant/presentation/widgets/textes_modale_restaurant.dart';
import '../../domain/entities/vehicule.dart';
import '../../domain/regles_vehicules.dart';
import '../providers_vehicules.dart';

/// La modale **« Nouveau véhicule au parc »** / **« Éditer le véhicule »** —
/// `largeur="560px"`.
///
/// @see EF-M8-01 Référentiel véhicules
///
/// ## Elle n'existait pas, et son absence était le défaut
///
/// L'ancien maître déclarait son parc « en lecture seule », et cet écran le
/// recopiait : « aucune route de l'API ne crée un véhicule ». C'était vrai
/// tant qu'un serveur alimentait `vehicules_local`. Depuis le 14/09/2026 le
/// poste est zéro réseau : **plus personne n'écrivait cette table**, un poste
/// neuf n'avait aucun véhicule, et aucun contrat ne pouvait donc être établi.
/// C'est la question des deux moitiés (piège 11) — qui l'écrit, qui la
/// descend ? — dont les deux réponses étaient « personne ».
///
/// La vue Blade, elle, porte bien cette modale (« + Véhicule », l.199) : elle
/// fait foi depuis PA-183, et ses libellés sont repris au mot de
/// `tatacora-api/lang/fr/vehicules.php`.
///
/// ## « Places », « Année » et « Transmission » sont saisis (v41, 27/10/2026)
///
/// Ils étaient rendus inertes tant que `vehicules_local` n'avait pas leurs
/// colonnes. Ils ont désormais les leurs (nullables) : la modale les demande comme
/// la vue (Places et Année obligatoires, Transmission facultative), les valide aux
/// bornes et aux phrases du serveur, les écrit et les enfile à la synchronisation.
/// Un véhicule d'avant la v41 s'ouvre avec ces champs VIDES : Places et Année sont
/// obligatoires à l'enregistrement, comme la vue — rien n'est pré-rempli.
Future<bool?> ouvrirModaleVehicule(
  BuildContext context, {
  Vehicule? vehicule,
}) => showDialog<bool>(
  context: context,
  barrierDismissible: true,
  barrierColor: AppColors.voileModale,
  builder: (_) => _ModaleVehicule(vehicule: vehicule),
);

class _ModaleVehicule extends ConsumerStatefulWidget {
  const _ModaleVehicule({this.vehicule});

  /// `null` en création ; la fiche à rééditer sinon.
  final Vehicule? vehicule;

  @override
  ConsumerState<_ModaleVehicule> createState() => _ModaleVehiculeState();
}

class _ModaleVehiculeState extends ConsumerState<_ModaleVehicule> {
  late final _immatriculation = TextEditingController(
    text: widget.vehicule?.immatriculation ?? '',
  );
  late final _tarif = TextEditingController(
    text: _tarifInitial(widget.vehicule),
  );

  late final _capacite = TextEditingController(
    text: widget.vehicule?.capacite?.toString() ?? '',
  );
  late final _annee = TextEditingController(
    text: widget.vehicule?.annee?.toString() ?? '',
  );
  late final _transmission = TextEditingController(
    text: widget.vehicule?.transmission ?? '',
  );

  late CategorieVehicule _categorie =
      widget.vehicule?.categorie ?? CategorieVehicule.voiture;

  bool _envoi = false;
  String? _refus;
  Map<String, String> _parChamp = const {};

  @override
  void dispose() {
    _immatriculation.dispose();
    _tarif.dispose();
    _capacite.dispose();
    _annee.dispose();
    _transmission.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final edition = widget.vehicule != null;

    return CoquilleModaleRestaurant(
      cle: const Key('modale-vehicule'),
      // Les deux titres de la vue, au mot.
      titre: edition ? 'Éditer le véhicule' : 'Nouveau véhicule au parc',
      sousTitre: 'Référentiel du parc.',
      largeur: AppLayout.modaleVehicule,
      refus: _refus,
      cleRefus: const Key('modale-vehicule-refus'),
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ------------------- 1 et 2. Immatriculation / Catégorie (l.783)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const EtiquetteChampRestaurant(
                      texte: 'Immatriculation',
                      obligatoire: true,
                    ),
                    TextField(
                      key: const Key('modale-vehicule-immatriculation'),
                      controller: _immatriculation,
                      style: TextesModaleRestaurant.corps,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        // L'invite de la vue, au mot.
                        hintText: 'Ex. AB 1234 RB',
                        isDense: true,
                        border: const OutlineInputBorder(),
                        errorText: _parChamp['immatriculation'],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const EtiquetteChampRestaurant(
                      texte: 'Catégorie',
                      obligatoire: true,
                    ),
                    DropdownButtonFormField<CategorieVehicule>(
                      key: const Key('modale-vehicule-categorie'),
                      initialValue: _categorie,
                      isExpanded: true,
                      style: TextesModaleRestaurant.corps,
                      decoration: const InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final c in CategorieVehicule.values)
                          DropdownMenuItem(value: c, child: Text(c.libelle)),
                      ],
                      onChanged: (c) =>
                          setState(() => _categorie = c ?? _categorie),
                    ),
                    // RG-09 se voit AVANT la première location : c'est la
                    // catégorie qui décide, et l'exploitant doit savoir ce
                    // qu'il s'engage à réclamer au comptoir.
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.unit),
                      child: Text(
                        exigePermisPour(_categorie.code)
                            ? 'permis exigé'
                            : 'dispensé de permis',
                        key: const Key('modale-vehicule-permis'),
                        style: TextesModaleRestaurant.aide.copyWith(
                          color: exigePermisPour(_categorie.code)
                              ? PaletteMaitre.ambre700
                              : PaletteMaitre.emeraude700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // ------------- 3, 4 et 5. Places / Année / Transmission (l.801)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _ChampSaisi(
                  cle: const Key('modale-vehicule-capacite'),
                  etiquette: 'Places',
                  obligatoire: true,
                  controleur: _capacite,
                  chiffres: true,
                  erreur: _parChamp['capacite'],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _ChampSaisi(
                  cle: const Key('modale-vehicule-annee'),
                  etiquette: 'Année',
                  obligatoire: true,
                  controleur: _annee,
                  chiffres: true,
                  erreur: _parChamp['annee'],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _ChampSaisi(
                  cle: const Key('modale-vehicule-transmission'),
                  etiquette: 'Transmission',
                  controleur: _transmission,
                  erreur: _parChamp['transmission'],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // --------------------------------- 6. Tarif / jour (FCFA) (l.819)
          const EtiquetteChampRestaurant(
            texte: 'Tarif / jour (FCFA)',
            obligatoire: true,
          ),
          TextField(
            key: const Key('modale-vehicule-tarif'),
            controller: _tarif,
            keyboardType: TextInputType.number,
            style: TextesModaleRestaurant.corps,
            decoration: InputDecoration(
              isDense: true,
              border: const OutlineInputBorder(),
              errorText: _parChamp['tarif_jour'],
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          const Text(
            // Le montant d'un contrat est FIGÉ à sa signature (v41) : modifier le
            // tarif ne réécrit plus les contrats déjà signés.
            'En francs ENTIERS : le XOF n’a pas de sous-unité en circulation. '
            'C’est ce tarif qui donne son montant à chaque NOUVEAU contrat ; '
            'celui d’un contrat déjà signé ne change pas.',
            key: Key('modale-vehicule-aide-tarif'),
            style: TextesModaleRestaurant.aide,
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('modale-vehicule-annuler'),
          onPressed: _envoi ? null : () => Navigator.of(context).pop(false),
          child: const Text('Annuler', style: TextesModaleRestaurant.bouton),
        ),
        FilledButton(
          key: const Key('modale-vehicule-enregistrer'),
          onPressed: _envoi ? null : _enregistrer,
          // Le libellé de la vue, au mot.
          child: const Text(
            'Enregistrer',
            style: TextesModaleRestaurant.bouton,
          ),
        ),
      ],
    );
  }

  Future<void> _enregistrer() async {
    final plaque = _immatriculation.text.trim();
    final tarif = int.tryParse(_tarif.text.trim().replaceAll(' ', ''));

    // Aux phrases du serveur (`GestionnaireVehicules`), champ par champ : le DAO
    // refait ces contrôles dans sa transaction, ceux-ci posent l'erreur sous le
    // bon champ.
    final refusPlacesSaisies = refusPlaces(_capacite.text);
    final refusAnneeSaisie = refusAnnee(_annee.text);
    final refusTransmissionSaisie = refusTransmission(_transmission.text);
    final manquants = <String, String>{
      if (plaque.isEmpty)
        'immatriculation': MessagesVehicules.immatriculationRequise,
      'capacite': ?refusPlacesSaisies,
      'annee': ?refusAnneeSaisie,
      'transmission': ?refusTransmissionSaisie,
      if (tarif == null || tarif <= 0)
        'tarif_jour': MessagesVehicules.tarifInvalide,
    };

    if (manquants.isNotEmpty) {
      setState(() => _parChamp = manquants);
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
          .enregistrerVehicule(
            id: widget.vehicule?.id,
            immatriculation: plaque,
            categorie: _categorie,
            tarifJour: tarif!,
            // Une réédition ne remet pas un véhicule en service : le statut se
            // change par son propre geste, sur la ligne du parc. Le confondre
            // avec l'édition rendrait louable un véhicule au garage.
            statut: widget.vehicule?.statut ?? StatutVehicule.disponible,
            annee: int.parse(_annee.text.trim()),
            capacite: int.parse(_capacite.text.trim()),
            // Vide : la transmission est effacée (chaîne vide), jamais « inchangée ».
            transmission: _transmission.text.trim(),
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

  /// Le tarif d'une fiche existante, ramené en francs entiers pour le champ.
  static String _tarifInitial(Vehicule? v) {
    if (v == null) return '';
    final point = v.tarifJour.indexOf('.');
    return point < 0 ? v.tarifJour : v.tarifJour.substring(0, point);
  }
}

/// Un champ de saisie de la modale — étiquette de la vue, `*` si obligatoire.
class _ChampSaisi extends StatelessWidget {
  const _ChampSaisi({
    required this.cle,
    required this.etiquette,
    required this.controleur,
    this.obligatoire = false,
    this.chiffres = false,
    this.erreur,
  });

  /// La clé du CHAMP de saisie (celle que les essais et les gardes ciblent).
  final Key cle;
  final String etiquette;
  final TextEditingController controleur;
  final bool obligatoire;
  final bool chiffres;
  final String? erreur;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        EtiquetteChampRestaurant(texte: etiquette, obligatoire: obligatoire),
        TextField(
          key: cle,
          controller: controleur,
          keyboardType: chiffres ? TextInputType.number : null,
          style: TextesModaleRestaurant.corps,
          decoration: InputDecoration(
            isDense: true,
            border: const OutlineInputBorder(),
            errorText: erreur,
            errorMaxLines: 3,
          ),
        ),
      ],
    );
  }
}
