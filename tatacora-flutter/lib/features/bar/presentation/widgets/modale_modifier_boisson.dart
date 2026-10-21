// Vue Blade maîtresse (PA-183) : pwa/bar/carte.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../restaurant/presentation/widgets/coquille_modale_restaurant.dart';
import '../../../restaurant/presentation/widgets/textes_modale_restaurant.dart';
import '../../data/boissons_api.dart';
import '../../domain/entities/boisson.dart';
import '../../domain/entities/carte_bar.dart';
import '../providers_bar.dart';

/// La modale **« Modifier la boisson — »** de la Carte du bar — corps partagé
/// des cartes (`pwa/carte/corps.blade.php` l.784-820), ouverte par le bouton
/// « Modifier » de chaque ligne (l.438-441, ajout du Product Owner du
/// 08/10/2026, propre au bar comme « Nouvelle boisson »).
///
/// @see EF-M5-02 Carte des boissons
///
/// Elle renomme et reclasse : le LIBELLÉ et la CATÉGORIE, rien d'autre. Le prix
/// garde sa modale tracée, le lien au stock la sienne — deux chemins d'écriture
/// pour un même champ divergeraient. `ouvrirModificationBoisson()` pré-remplit
/// les deux champs avec ceux de la ligne ; l'écriture passe par
/// `modifierBoissonProvider`, qui relit le prix au catalogue.
///
/// ÉCART DÉLIBÉRÉ — l.793-799. La vue : le libellé vide ou trop long est refusé
/// par la validation Livewire, au retour. Ici : il est refusé par le catalogue
/// local, sous le champ, et un libellé déjà pris l'est aussi (deux entrées de
/// même nom au comptoir se confondraient).
Future<bool?> ouvrirModaleModifierBoisson(
  BuildContext context,
  LigneCarte ligne,
) => showDialog<bool>(
  context: context,
  barrierDismissible: true,
  barrierColor: AppColors.voileModale,
  builder: (_) => _ModaleModifierBoisson(ligne: ligne),
);

/// Les mots de la modale — `lang/fr/carte_pwa.php`, clés `commun.*`.
abstract final class TextesModifierBoisson {
  static const String bouton = 'Modifier';
  static String titre(String article) => 'Modifier la boisson — $article';
  static const String sousTitre =
      "Le libellé et la catégorie changent ; le prix, le lien au stock et l'historique restent ceux de la boisson.";
  static const String champLibelle = 'Libellé';
  static const String champCategorie = 'Catégorie';
  static const String annuler = 'Annuler';
  static const String confirmer = 'Enregistrer la boisson';

  /// `toast_boisson_modifiee`.
  static String modifiee(String article) => '« $article » est à jour.';
}

class _ModaleModifierBoisson extends ConsumerStatefulWidget {
  const _ModaleModifierBoisson({required this.ligne});

  final LigneCarte ligne;

  @override
  ConsumerState<_ModaleModifierBoisson> createState() =>
      _ModaleModifierBoissonState();
}

class _ModaleModifierBoissonState
    extends ConsumerState<_ModaleModifierBoisson> {
  late final TextEditingController _libelle = TextEditingController(
    text: widget.ligne.libelle,
  );

  // Une catégorie que ce client ne connaît pas ne devient pas « Locale » en
  // silence : le champ part vide et la saisie est refusée tant qu'on n'a pas
  // choisi.
  late CategorieBoisson? _categorie = CategorieBoisson.depuisCode(
    widget.ligne.categorie,
  );

  bool _envoi = false;
  String? _refus;
  Map<String, String> _parChamp = const {};

  @override
  void dispose() {
    _libelle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CoquilleModaleRestaurant(
      cle: const Key('modale-modifier-boisson'),
      titre: TextesModifierBoisson.titre(widget.ligne.libelle),
      sousTitre: TextesModifierBoisson.sousTitre,
      largeur: AppLayout.modaleModifierBoisson,
      refus: _parChamp.isEmpty ? _refus : null,
      cleRefus: const Key('modifier-boisson-refus'),
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const EtiquetteChampRestaurant(
            texte: TextesModifierBoisson.champLibelle,
            obligatoire: true,
          ),
          TextField(
            key: const Key('modifier-boisson-libelle'),
            controller: _libelle,
            style: TextesModaleRestaurant.corps,
            decoration: InputDecoration(
              isDense: true,
              border: const OutlineInputBorder(),
              errorText: _parChamp['libelle'],
              errorMaxLines: 4,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          const EtiquetteChampRestaurant(
            texte: TextesModifierBoisson.champCategorie,
            obligatoire: true,
          ),
          DropdownButtonFormField<CategorieBoisson>(
            key: const Key('modifier-boisson-categorie'),
            initialValue: _categorie,
            isExpanded: true,
            style: TextesModaleRestaurant.corps,
            decoration: InputDecoration(
              isDense: true,
              border: const OutlineInputBorder(),
              errorText: _parChamp['categorie'],
            ),
            items: [
              for (final c in CategorieBoisson.values)
                DropdownMenuItem(value: c, child: Text(c.libelle)),
            ],
            onChanged: (c) => setState(() => _categorie = c),
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('modifier-boisson-annuler'),
          onPressed: _envoi ? null : () => Navigator.of(context).pop(false),
          child: const Text(
            TextesModifierBoisson.annuler,
            style: TextesModaleRestaurant.bouton,
          ),
        ),
        FilledButton(
          key: const Key('modifier-boisson-confirmer'),
          onPressed: _envoi ? null : _enregistrer,
          child: const Text(
            TextesModifierBoisson.confirmer,
            style: TextesModaleRestaurant.bouton,
          ),
        ),
      ],
    );
  }

  Future<void> _enregistrer() async {
    final categorie = _categorie;
    if (categorie == null) {
      // `required|in:` du serveur : sans catégorie du registre, rien ne part.
      setState(
        () => _parChamp = {'categorie': 'La catégorie est obligatoire.'},
      );
      return;
    }

    setState(() {
      _envoi = true;
      _refus = null;
      _parChamp = const {};
    });

    final resultat = await ref.read(modifierBoissonProvider)(
      widget.ligne.id,
      libelle: _libelle.text,
      categorie: categorie,
    );
    if (!mounted) return;

    switch (resultat) {
      case BarRecu<Boisson>(:final donnees):
        final messager = ScaffoldMessenger.of(context);
        Navigator.of(context).pop(true);
        messager.showSnackBar(
          SnackBar(
            content: Text(
              TextesModifierBoisson.modifiee(donnees.libelle),
              key: const Key('modifier-boisson-modifiee'),
            ),
          ),
        );
      case BarRefuse<Boisson>(:final motif, :final erreurs):
        setState(() {
          _envoi = false;
          _refus = motif;
          _parChamp = erreurs;
        });
      case BarInjoignable<Boisson>():
        // Inatteignable : l'écriture est locale. Le cas reste écrit parce que
        // le registre est FERMÉ.
        setState(() => _envoi = false);
    }
  }
}
