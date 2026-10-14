import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../data/stocks_api.dart';
import '../../domain/entities/etat_stock.dart';
import '../providers_stocks.dart';
import 'coquille_modale_stock.dart';

/// La modale **« Nouveau point de stockage »**.
///
/// ## Un AJOUT à la vue, et la raison de son existence
///
/// La vue Blade n'a aucun écran de points : le serveur les reçoit de son
/// seeder. Ce poste n'a ni serveur ni seeder — et aucune ligne n'est semée
/// (un « Magasin général » ou un « Garage » d'usine serait plausible, donc
/// invisible). Sans un geste pour en créer, `points_stockage_local` serait la
/// quatrième table lue partout et écrite par personne (PA-128 : « le parc
/// n'était écrit par PERSONNE »), et aucun mouvement ne pourrait jamais être
/// saisi. Le geste est donc offert là où l'on en a besoin — les deux modales
/// qui choisissent un point —, et nulle part ailleurs.
///
/// Le type est le registre fermé du Gîte (magasin, cuisine, bar, garage) :
/// c'est par lui que la sortie automatique des ventes retrouvera un point
/// (RG-05). Il reste facultatif, comme au serveur.
Future<PointStockage?> ouvrirModalePoint(BuildContext context) {
  return showDialog<PointStockage>(
    context: context,
    builder: (_) => const _ModalePoint(),
  );
}

class _ModalePoint extends ConsumerStatefulWidget {
  const _ModalePoint();

  @override
  ConsumerState<_ModalePoint> createState() => _ModalePointState();
}

class _ModalePointState extends ConsumerState<_ModalePoint> {
  final _formulaire = GlobalKey<FormState>();
  final _libelle = TextEditingController();

  TypePoint? _type;
  bool _envoiEnCours = false;
  String? _refus;

  @override
  void dispose() {
    _libelle.dispose();
    super.dispose();
  }

  Future<void> _creer() async {
    if (!(_formulaire.currentState?.validate() ?? false)) return;

    setState(() {
      _envoiEnCours = true;
      _refus = null;
    });

    final r = await ref
        .read(stocksApiProvider)
        .creerPoint(libelle: _libelle.text, type: _type);
    if (!mounted) return;

    switch (r) {
      case PointEnregistre(:final point):
        // Le sélecteur de la modale appelante doit proposer le nouveau point.
        ref.invalidate(pointsStockProvider);
        Navigator.of(context).pop(point);
      case PointRefuse(:final motif):
        setState(() {
          _envoiEnCours = false;
          _refus = motif;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    return CoquilleModaleStock(
      cle: const Key('modale-point'),
      titre: 'Nouveau point de stockage',
      sousTitre:
          'Un lieu où la marchandise est tenue : le stock se raisonne par '
          'couple (article, point).',
      libelleValidation: 'Créer le point',
      cleValidation: const Key('point-creer'),
      envoiEnCours: _envoiEnCours,
      onValider: _creer,
      refus: _refus,
      cleRefus: const Key('point-refus'),
      corps: Form(
        key: _formulaire,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: const Key('point-libelle'),
              controller: _libelle,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nom du point',
                hintText: 'Ex. Magasin général',
                border: OutlineInputBorder(),
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Le nom du point de stockage est obligatoire.'
                  : null,
            ),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<TypePoint?>(
              key: const Key('point-type'),
              initialValue: _type,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Type',
                border: OutlineInputBorder(),
              ),
              items: [
                // `null` reste offert : un point sans type est valide, et en
                // imposer un en inventerait un.
                const DropdownMenuItem<TypePoint?>(child: Text('Sans type')),
                for (final t in TypePoint.values)
                  DropdownMenuItem<TypePoint?>(
                    value: t,
                    child: Text(t.libelle),
                  ),
              ],
              onChanged: (t) => setState(() => _type = t),
            ),
          ],
        ),
      ),
    );
  }
}
