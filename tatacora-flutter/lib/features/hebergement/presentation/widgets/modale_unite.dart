/// La modale « Ajouter hébergement » / « Modifier l'hébergement ».
///
/// Vue Blade maîtresse (PA-183) : pwa/hebergement/hebergement.blade.php
/// (formulaire `formulaire-unite`, l.552-611).
///
/// ## `statut` NE SE SAISIT PAS, et c'est la vue qui le dit
///
/// Son commentaire est explicite (l.596-601) : « `statut` ne se SAISIT pas — il
/// est écrit par les gestes » du cycle. Le laisser choisir ferait dire à
/// l'écran qu'une chambre est occupée sans que personne y dorme. Une unité
/// entre donc au parc `libre`, et son état change par les boutons de sa carte.
///
/// ## La catégorie porte le tarif et la capacité
///
/// C'est le modèle du Product Owner (01/09/2026), écrit dans la vue l.567-571.
/// Les catégories « ne se seedent pas — elles se CRÉENT ici, tarif réel en
/// main », d'où la case « + Nouvelle catégorie » et ses trois champs.
///
/// ## Un ÉCART assumé avec la vue : modifier une catégorie existante
///
/// - **Vue** (l.572-593) : la modale ne sait que **créer** une catégorie. Rien
///   n'y permet d'en corriger le tarif ou la capacité.
/// - **Ici** : un bouton « Modifier la catégorie » rouvre les trois mêmes
///   champs, pré-remplis, sur la catégorie retenue.
/// - **Pourquoi** : instruction du Product Owner du 14/09/2026 — le parc se
///   saisit sur le poste, catégories comprises. Le poste est zéro réseau : un
///   tarif fautif saisi ici ne pourrait plus être corrigé nulle part, ni par la
///   PWA, ni par un seeder, ni par une descente serveur. L'écart n'ajoute aucun
///   champ à la vue ; il rend accessibles en modification les trois qu'elle
///   pose déjà en création.
///
/// ⚠ Corriger un tarif ne réécrit **aucun** montant déjà réservé : `tarifNuit`
/// est figé sur la réservation (PA-55). Le catalogue dit ce qu'on vend
/// aujourd'hui, la réservation dit ce qui a été vendu.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/format/formats.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../domain/entities/categorie_hebergement.dart';
import '../../domain/entities/unite_hebergement.dart';
import '../../domain/refus_parc.dart';
import '../providers_hebergement.dart';

/// Ouvre la modale. [unite] nulle = création. Rend `true` si quelque chose a
/// été enregistré.
Future<bool> ouvrirModaleUnite(
  BuildContext context,
  WidgetRef ref, {
  UniteHebergement? unite,
}) async {
  final categories = await ref.read(categoriesParcProvider.future);
  if (!context.mounted) return false;

  final enregistre = await showDialog<bool>(
    context: context,
    builder: (context) => _ModaleUnite(unite: unite, categories: categories),
  );
  return enregistre ?? false;
}

class _ModaleUnite extends ConsumerStatefulWidget {
  const _ModaleUnite({required this.unite, required this.categories});

  final UniteHebergement? unite;
  final List<CategorieHebergement> categories;

  @override
  ConsumerState<_ModaleUnite> createState() => _ModaleUniteState();
}

class _ModaleUniteState extends ConsumerState<_ModaleUnite> {
  final _formulaire = GlobalKey<FormState>();

  late final TextEditingController _numero = TextEditingController(
    text: widget.unite?.numero ?? '',
  );
  final _categorieLibelle = TextEditingController();
  final _categorieTarif = TextEditingController();
  final _categorieCapacite = TextEditingController();

  /// La catégorie retenue. Pré-remplie en modification ; en création, laissée
  /// VIDE plutôt que sur la première de la liste — choisir à la place de
  /// l'utilisateur rattacherait une chambre à une catégorie qu'il n'a pas vue.
  late String? _categorieId = widget.unite?.categorieId;

  /// La case « + Nouvelle catégorie » de la vue.
  bool _nouvelleCategorie = false;

  /// L'écart documenté en tête de fichier.
  bool _editionCategorie = false;

  String? _erreur;

  bool get _saisitCategorie => _nouvelleCategorie || _editionCategorie;

  @override
  void dispose() {
    _numero.dispose();
    _categorieLibelle.dispose();
    _categorieTarif.dispose();
    _categorieCapacite.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.unite == null
                ? 'Ajouter hébergement'
                : "Modifier l'hébergement",
            key: const Key('modale-unite-titre'),
          ),
          const SizedBox(height: AppSpacing.demi),
          const Text(
            'Parc du Gîte Chez Noël — bungalows, chambres et tentes.',
            style: TextStyle(
              color: Ardoise.c500,
              fontFamily: AppTextStyles.police,
              fontSize: Tailles.t13,
              fontWeight: FontWeight.normal,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: AppLayout.modaleUniteHebergement,
        child: SingleChildScrollView(
          child: Form(
            key: _formulaire,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _etiquette('Code unité', obligatoire: true),
                TextFormField(
                  key: const Key('modale-unite-code'),
                  controller: _numero,
                  decoration: const InputDecoration(hintText: 'Ex. BNG-03'),
                  validator: (valeur) => (valeur ?? '').trim().isEmpty
                      ? "Le code de l'unité est obligatoire."
                      : null,
                ),
                const SizedBox(height: AppSpacing.sm),
                _etiquette('Catégorie', obligatoire: true),
                _choixCategorie(),
                if (_saisitCategorie) _champsCategorie(),
                if (_erreur != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      _erreur!,
                      key: const Key('modale-unite-erreur'),
                      style: const TextStyle(
                        color: PaletteMaitre.rouge600,
                        fontFamily: AppTextStyles.police,
                        fontSize: Tailles.t12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('modale-unite-annuler'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const Key('modale-unite-enregistrer'),
          onPressed: _enregistrer,
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }

  Widget _etiquette(String texte, {bool obligatoire = false}) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
    child: Row(
      children: [
        Text(
          texte,
          style: const TextStyle(
            color: Ardoise.c700,
            fontFamily: AppTextStyles.police,
            fontSize: Tailles.t15,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (obligatoire)
          const Text(
            ' *',
            style: TextStyle(
              color: PaletteMaitre.rouge500,
              fontFamily: AppTextStyles.police,
              fontSize: Tailles.t15,
            ),
          ),
      ],
    ),
  );

  Widget _choixCategorie() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // La case de la vue, avec son libellé exact.
        CheckboxListTile(
          key: const Key('modale-unite-nouvelle-categorie'),
          value: _nouvelleCategorie,
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text(
            '+ Nouvelle catégorie',
            style: TextStyle(
              color: Ardoise.c500,
              fontFamily: AppTextStyles.police,
              fontSize: Tailles.t12,
              fontWeight: FontWeight.w600,
            ),
          ),
          onChanged: (valeur) => setState(() {
            _nouvelleCategorie = valeur ?? false;
            // Les deux modes s'excluent : saisir une nouvelle catégorie tout
            // en corrigeant une autre écrirait deux fois, et l'unité
            // n'atterrirait que sur l'une des deux.
            if (_nouvelleCategorie) _editionCategorie = false;
            _viderChampsCategorie();
          }),
        ),
        if (!_nouvelleCategorie)
          DropdownButtonFormField<String>(
            key: const Key('modale-unite-categorie'),
            initialValue: _categorieId,
            isExpanded: true,
            decoration: const InputDecoration(
              hintText: 'Choisir une catégorie…',
            ),
            items: [
              for (final categorie in widget.categories)
                DropdownMenuItem(
                  value: categorie.id,
                  // La vue affiche « libellé — tarif » : sans le tarif, deux
                  // catégories voisines ne se distinguent pas au comptoir.
                  child: Text(
                    '${categorie.libelle} — ${formaterFcfa(categorie.tarifBase)}',
                  ),
                ),
            ],
            onChanged: (valeur) => setState(() {
              _categorieId = valeur;
              if (_editionCategorie) _prendreCategorie(valeur);
            }),
            validator: (valeur) => _nouvelleCategorie || valeur != null
                ? null
                : 'La catégorie est obligatoire.',
          ),
        // ÉCART assumé — voir l'en-tête de fichier. Le bouton n'apparaît que
        // sur une catégorie réellement retenue : « modifier » sans cible
        // n'ouvrirait rien, et un bouton qui n'ouvre rien empêche de savoir si
        // la fonction manque ou si l'écran est cassé.
        if (!_nouvelleCategorie && _categorieId != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const Key('modale-unite-modifier-categorie'),
              onPressed: () => setState(() {
                _editionCategorie = !_editionCategorie;
                if (_editionCategorie) {
                  _prendreCategorie(_categorieId);
                } else {
                  _viderChampsCategorie();
                }
              }),
              child: Text(
                _editionCategorie
                    ? 'Ne plus modifier la catégorie'
                    : 'Modifier la catégorie',
              ),
            ),
          ),
      ],
    );
  }

  /// Les trois champs de la vue, dans son ordre : libellé, tarif, capacité.
  Widget _champsCategorie() {
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.xs),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: Ardoise.c50,
        borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            key: const Key('modale-unite-categorie-libelle'),
            controller: _categorieLibelle,
            decoration: const InputDecoration(
              hintText:
                  'Libellé de la catégorie (Bungalow, Chambre simple, '
                  'Suite…)',
            ),
            validator: (valeur) => !_saisitCategorie
                ? null
                : ((valeur ?? '').trim().isEmpty
                      ? 'Le libellé de la catégorie est obligatoire.'
                      : null),
          ),
          TextFormField(
            key: const Key('modale-unite-categorie-tarif'),
            controller: _categorieTarif,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              hintText: 'Tarif par nuit (FCFA)',
            ),
            validator: (valeur) => !_saisitCategorie
                ? null
                : (_entier(valeur) == null || _entier(valeur)! <= 0
                      ? 'Un tarif par nuit strictement positif est requis.'
                      : null),
          ),
          TextFormField(
            key: const Key('modale-unite-categorie-capacite'),
            controller: _categorieCapacite,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(hintText: 'Capacité (personnes)'),
            validator: (valeur) => !_saisitCategorie
                ? null
                : (_entier(valeur) == null || _entier(valeur)! < 1
                      ? 'Une capacité d’au moins une personne est requise.'
                      : null),
          ),
        ],
      ),
    );
  }

  void _prendreCategorie(String? id) {
    final categorie = widget.categories
        .where((c) => c.id == id)
        .cast<CategorieHebergement?>()
        .firstWhere((c) => true, orElse: () => null);
    if (categorie == null) return;

    _categorieLibelle.text = categorie.libelle;
    _categorieTarif.text = categorie.tarifBase.toString();
    _categorieCapacite.text = categorie.capaciteMax.toString();
  }

  void _viderChampsCategorie() {
    _categorieLibelle.clear();
    _categorieTarif.clear();
    _categorieCapacite.clear();
  }

  static int? _entier(String? valeur) => int.tryParse((valeur ?? '').trim());

  Future<void> _enregistrer() async {
    if (!_formulaire.currentState!.validate()) return;

    final dao = ref.read(parcDaoProvider);

    try {
      var categorieId = _categorieId;

      if (_nouvelleCategorie) {
        // La catégorie naît AVEC son tarif réel et sa capacité — jamais un
        // zéro d'attente qui se lirait comme une nuit gratuite.
        categorieId = (await dao.creerCategorie(
          libelle: _categorieLibelle.text,
          capaciteMax: _entier(_categorieCapacite.text)!,
          tarifBase: _entier(_categorieTarif.text)!,
        )).id;
      } else if (_editionCategorie && categorieId != null) {
        await dao.modifierCategorie(
          categorieId,
          libelle: _categorieLibelle.text,
          capaciteMax: _entier(_categorieCapacite.text)!,
          tarifBase: _entier(_categorieTarif.text)!,
        );
      }

      if (categorieId == null) {
        setState(() => _erreur = 'La catégorie est obligatoire.');
        return;
      }

      if (widget.unite == null) {
        await dao.creerUnite(numero: _numero.text, categorieId: categorieId);
      } else {
        await dao.modifierUnite(
          widget.unite!.id,
          numero: _numero.text,
          categorieId: categorieId,
        );
      }
    } on RefusParc catch (refus) {
      // Le message du domaine, tel quel : c'est lui qui dit quoi corriger.
      if (mounted) setState(() => _erreur = refus.message);
      return;
    }

    if (!mounted) return;
    rafraichirListes(ref);
    Navigator.of(context).pop(true);
  }
}
