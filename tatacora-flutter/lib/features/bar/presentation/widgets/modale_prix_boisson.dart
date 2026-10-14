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

/// La modale **« Modifier le prix — »** de la Carte du bar — corps partagé des
/// cartes, l.793-819, ouverte par le bouton « Prix » de chaque ligne
/// (l.434-435).
///
/// @see EF-M5-02 Carte des boissons
///
/// Directive du Product Owner du 02/09/2026 côté PWA : la trace des prix
/// existait (`HistoriquePrixCarte`), le geste manquait. Porté ici le
/// 11/09/2026. L'écriture passe par `modifierPrixBoissonProvider` : le prix
/// seul, les autres champs relus au serveur — voir son en-tête.
///
/// ## Ce qui est tenu à l'identique
///
/// Titre avec le libellé de l'article, sous-titre, un seul champ obligatoire
/// pré-rempli avec le prix actuel (`ouvrirModificationPrix()`), l'aide sous le
/// champ, « Annuler » puis « Enregistrer le prix ». Un prix à ZÉRO est refusé
/// (`gt:0`), alors que l'API accepte `min:0` : la règle est celle du GESTE
/// dans la PWA, et elle est reprise ici — suspendre la vente est le rôle de
/// « Retirer de la carte », qui porte son motif.
///
/// ## Un écart, nommé
///
/// ÉCART DÉLIBÉRÉ — corps partagé des cartes, l.797-818.
/// La vue : la validation du prix vient du serveur, au retour.
/// Ici : un champ vide, illisible ou nul est signalé AVANT l'envoi.
/// Raison : un aller-retour pour apprendre qu'un champ est vide fait perdre
/// la saisie quand la liaison tombe entre les deux. Les refus du serveur (422)
/// restent affichés.
Future<bool?> ouvrirModalePrixBoisson(BuildContext context, LigneCarte ligne) =>
    showDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierColor: AppColors.voileModale,
      builder: (_) => _ModalePrix(ligne: ligne),
    );

/// Les messages de la modale — un seul endroit pour l'écran et les essais.
abstract final class TextesPrixBoisson {
  // Les mots de la vue — `lang/fr/carte_pwa.php` l.233-239.
  static const String bouton = 'Prix';
  static String titre(String article) => 'Modifier le prix — $article';
  static const String sousTitre =
      "Le changement est tracé dans l'historique des prix.";
  static const String champ = 'Nouveau prix de vente (FCFA)';
  static const String aide =
      'Un prix à zéro est refusé : pour suspendre la vente, utilisez « Retirer '
      'de la carte », qui porte son motif.';
  static const String annuler = 'Annuler';
  static const String confirmer = 'Enregistrer le prix';
  static String modifie(String article) => 'Prix de « $article » modifié.';

  // Propres à ce poste.
  static const String manquant = 'Le nouveau prix est obligatoire.';
  static const String illisible = 'Le prix doit être un nombre.';
  static const String nul =
      'Un prix à zéro est refusé : pour suspendre la vente, retirez l’article '
      'de la carte.';

  /// ⚠ Le nouveau prix ne vaut que pour les ventes À VENIR.
  ///
  /// Les lignes déjà saisies au panier gardent le leur : prix et libellé y
  /// sont figés à l'ajout (règle 3). Le dire évite la question inverse — un
  /// barman qui croirait avoir corrigé une addition déjà prise.
  static const String aidePortee =
      'Le nouveau prix s’applique aux ventes à venir. Les consommations déjà '
      'saisies au panier gardent le prix auquel elles ont été servies.';
}

class _ModalePrix extends ConsumerStatefulWidget {
  const _ModalePrix({required this.ligne});

  final LigneCarte ligne;

  @override
  ConsumerState<_ModalePrix> createState() => _ModalePrixState();
}

class _ModalePrixState extends ConsumerState<_ModalePrix> {
  // `ouvrirModificationPrix()` : le champ part du prix actuel. Un prix entier
  // s'affiche sans décimale — le franc CFA n'a pas de sous-unité en usage.
  late final TextEditingController _prix = TextEditingController(
    text: widget.ligne.prix == widget.ligne.prix.roundToDouble()
        ? widget.ligne.prix.toStringAsFixed(0)
        : '${widget.ligne.prix}',
  );

  bool _envoi = false;
  String? _refus;
  String? _erreurChamp;

  @override
  void dispose() {
    _prix.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CoquilleModaleRestaurant(
      cle: const Key('modale-prix-boisson'),
      titre: TextesPrixBoisson.titre(widget.ligne.libelle),
      sousTitre: TextesPrixBoisson.sousTitre,
      largeur: AppLayout.modalePrixBoisson,
      refus: _refus,
      cleRefus: const Key('prix-boisson-refus'),
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const EtiquetteChampRestaurant(
            texte: TextesPrixBoisson.champ,
            obligatoire: true,
          ),
          TextField(
            key: const Key('prix-boisson-champ'),
            controller: _prix,
            // `type="number" step="1" min="1"` (l.806).
            keyboardType: TextInputType.number,
            autofocus: true,
            style: TextesModaleRestaurant.corps,
            decoration: InputDecoration(
              isDense: true,
              border: const OutlineInputBorder(),
              errorText: _erreurChamp,
              errorMaxLines: 3,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            TextesPrixBoisson.aide,
            key: Key('prix-boisson-aide'),
            style: TextesModaleRestaurant.aide,
          ),
          const SizedBox(height: AppSpacing.xxs),
          const Text(
            TextesPrixBoisson.aidePortee,
            key: Key('prix-boisson-aide-portee'),
            style: TextesModaleRestaurant.aide,
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('prix-boisson-annuler'),
          onPressed: _envoi ? null : () => Navigator.of(context).pop(false),
          child: const Text(
            TextesPrixBoisson.annuler,
            style: TextesModaleRestaurant.bouton,
          ),
        ),
        FilledButton(
          key: const Key('prix-boisson-confirmer'),
          onPressed: _envoi ? null : _enregistrer,
          child: const Text(
            TextesPrixBoisson.confirmer,
            style: TextesModaleRestaurant.bouton,
          ),
        ),
      ],
    );
  }

  Future<void> _enregistrer() async {
    final saisie = _prix.text.trim().replaceAll(',', '.');
    final lu = double.tryParse(saisie);

    // `required|numeric|gt:0` — `enregistrerModificationPrix()`.
    final erreur = saisie.isEmpty
        ? TextesPrixBoisson.manquant
        : (lu == null || !lu.isFinite)
        ? TextesPrixBoisson.illisible
        : lu <= 0
        ? TextesPrixBoisson.nul
        : null;
    if (erreur != null) {
      setState(() => _erreurChamp = erreur);
      return;
    }

    setState(() {
      _envoi = true;
      _refus = null;
      _erreurChamp = null;
    });

    final resultat = await ref.read(modifierPrixBoissonProvider)(
      widget.ligne.id,
      saisie,
    );
    if (!mounted) return;

    switch (resultat) {
      case BarRecu<Boisson>(:final donnees):
        final messager = ScaffoldMessenger.of(context);
        Navigator.of(context).pop(true);
        messager.showSnackBar(
          SnackBar(
            content: Text(
              TextesPrixBoisson.modifie(donnees.libelle),
              key: const Key('prix-boisson-modifie'),
            ),
          ),
        );
      case BarRefuse<Boisson>(:final motif, :final erreurs):
        setState(() {
          _envoi = false;
          _erreurChamp = erreurs['prix_vente'];
          // Un refus sur un AUTRE champ n'a pas de champ où s'afficher : il
          // rejoint le motif, plutôt que de disparaître.
          final autres = erreurs.entries
              .where((e) => e.key != 'prix_vente')
              .map((e) => e.value);
          _refus = [motif, ...autres].join('\n');
        });
      case BarInjoignable<Boisson>():
        // Inatteignable : l'écriture est locale. Le cas reste écrit parce que
        // le registre est FERMÉ.
        setState(() => _envoi = false);
    }
  }
}
