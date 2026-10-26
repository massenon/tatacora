// Vue Blade maîtresse (PA-183) : pwa/restaurant/carte.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../bar/presentation/widgets/modale_prix_boisson.dart'
    show TextesPrixBoisson;
import '../../data/restaurant_api.dart';
import '../../domain/entities/carte_restaurant.dart';
import '../../domain/entities/plat.dart';
import '../providers_restaurant.dart';
import 'coquille_modale_restaurant.dart';
import 'textes_modale_restaurant.dart';

/// La modale **« Modifier le prix — »** de la Carte du restaurant — corps
/// partagé des cartes, l.793-819, ouverte par le bouton « Prix » de chaque ligne
/// (l.434-435). Rend `true` si le prix a été enregistré.
///
/// @see EF-M4-01 Gestion des menus et cartes
///
/// Directive du PO du 02/09/2026 côté PWA : la trace des prix existait, le geste
/// manquait. Porté ici le 26/10/2026 (schéma v38, « le poste fait ce que le web
/// fait ») : `RestaurantDao.modifierPrix` écrit le prix SEUL, le TRACE dans
/// l'historique et l'enfile en modification du plat, dans une seule transaction.
///
/// Les mots sont ceux du corps partagé (`lang/fr/carte_pwa.php`, `commun.*`),
/// déjà portés pour la carte du bar : [TextesPrixBoisson] les porte, ce fichier
/// ne les recopie pas.
///
/// ## Un écart, nommé
///
/// ÉCART DÉLIBÉRÉ — corps partagé des cartes, l.797-818.
/// La vue : la validation du prix vient du serveur, au retour.
/// Ici : un champ vide, illisible, nul ou à fraction de franc est refusé par le
/// DAO AVANT toute écriture, avec ses phrases (`MessagesRestaurant`). Raison :
/// le franc CFA n'a pas de sous-unité, et un prix à fraction que le serveur
/// arrondirait ne doit pas être enregistré sur ce poste pour être corrigé plus
/// tard.
Future<bool?> ouvrirModalePrixPlat(
  BuildContext context, {
  required LigneCarteRestaurant ligne,
}) => showDialog<bool>(
  context: context,
  barrierDismissible: true,
  barrierColor: AppColors.voileModale,
  builder: (_) => _ModalePrixPlat(ligne: ligne),
);

class _ModalePrixPlat extends ConsumerStatefulWidget {
  const _ModalePrixPlat({required this.ligne});

  final LigneCarteRestaurant ligne;

  @override
  ConsumerState<_ModalePrixPlat> createState() => _ModalePrixPlatState();
}

class _ModalePrixPlatState extends ConsumerState<_ModalePrixPlat> {
  // `ouvrirModificationPrix()` : le champ part du prix actuel, en francs
  // entiers (le prix du plat est « 1500.00 » au contrat, « 1500 » à l'écran).
  late final TextEditingController _prix = TextEditingController(
    text: widget.ligne.prixVente.split('.').first,
  );

  bool _envoi = false;
  String? _refus;
  String? _erreurChamp;

  @override
  void dispose() {
    _prix.dispose();
    super.dispose();
  }

  Future<void> _enregistrer() async {
    setState(() {
      _envoi = true;
      _refus = null;
      _erreurChamp = null;
    });
    final messager = ScaffoldMessenger.of(context);
    final navigateur = Navigator.of(context);

    final resultat = await ref
        .read(restaurantApiProvider)
        .modifierPrix(platId: widget.ligne.id, prix: _prix.text);
    if (!mounted) return;

    switch (resultat) {
      case RestaurantRecu<Plat>(:final donnees):
        invaliderRestaurant(ref);
        messager
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Text(
                TextesPrixBoisson.modifie(donnees.libelle),
                key: const Key('prix-plat-modifie'),
              ),
            ),
          );
        navigateur.pop(true);
      case RestaurantRefuse<Plat>(:final motif, :final erreurs):
        setState(() {
          _envoi = false;
          _erreurChamp = erreurs['prix_vente'];
          final autres = erreurs.entries
              .where((e) => e.key != 'prix_vente')
              .map((e) => e.value);
          _refus = erreurs.containsKey('prix_vente')
              ? (autres.isEmpty ? null : autres.join('\n'))
              : [motif, ...autres].join('\n');
        });
      case RestaurantInjoignable<Plat>():
        setState(() => _envoi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CoquilleModaleRestaurant(
      cle: const Key('modale-prix-plat'),
      titre: TextesPrixBoisson.titre(widget.ligne.libelle),
      sousTitre: TextesPrixBoisson.sousTitre,
      largeur: AppLayout.modalePrixBoisson,
      refus: _refus,
      cleRefus: const Key('prix-plat-refus'),
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const EtiquetteChampRestaurant(
            texte: TextesPrixBoisson.champ,
            obligatoire: true,
          ),
          TextField(
            key: const Key('prix-plat-champ'),
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
            key: Key('prix-plat-aide'),
            style: TextesModaleRestaurant.aide,
          ),
          const SizedBox(height: AppSpacing.xxs),
          const Text(
            TextesPrixBoisson.aidePortee,
            key: Key('prix-plat-aide-portee'),
            style: TextesModaleRestaurant.aide,
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('prix-plat-annuler'),
          onPressed: _envoi ? null : () => Navigator.of(context).pop(false),
          child: const Text(
            TextesPrixBoisson.annuler,
            style: TextesModaleRestaurant.bouton,
          ),
        ),
        FilledButton(
          key: const Key('prix-plat-confirmer'),
          onPressed: _envoi ? null : _enregistrer,
          child: const Text(
            TextesPrixBoisson.confirmer,
            style: TextesModaleRestaurant.bouton,
          ),
        ),
      ],
    );
  }
}
