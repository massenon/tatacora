import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../data/comptabilite_dao.dart';
import '../data/installateur_referentiel.dart';
import '../data/moteur_comptable.dart';

/// Installe le référentiel comptable (plan du PO, journaux, centres, exercice
/// de l'année) — **lu au démarrage de l'application** (`main.dart`), et par
/// tout ce qui a besoin du moteur.
///
/// ## Pourquoi un fournisseur, et pas la migration
///
/// La migration v15 crée les six tables VIDES : une migration ne lit pas un
/// asset, et un référentiel recopié à la main divergerait du fichier du PO.
/// Cette installation est idempotente (une seconde exécution ne change rien) et
/// additive (elle ne supprime jamais un compte) : l'exécuter à CHAQUE démarrage
/// couvre ensemble l'installation neuve, la mise à jour depuis la v14 et le
/// poste qui a sauté une livraison.
///
/// Piège 1 : un commentaire qui décrit un déclencheur n'est pas un déclencheur.
/// L'appelant est `ApplicationTatacora` (`main.dart`) ; un test relit ce
/// fichier source pour que ce soit vrai demain encore.
final referentielComptableProvider = FutureProvider<BilanInstallation>((
  ref,
) async {
  final contenu = await rootBundle.loadString(cheminAssetPlanComptable);
  return installerReferentielComptable(
    ref.watch(baseLocaleProvider),
    contenuPlan: contenu,
    maintenant: DateTime.now(),
  );
});

final comptabiliteDaoProvider = Provider<ComptabiliteDao>(
  (ref) => ComptabiliteDao(ref.watch(baseLocaleProvider)),
);

/// Le moteur comptable — **jamais servi avant l'installation du référentiel** :
/// un moteur sur un plan vide répondrait « compte inconnu » à toute pièce.
///
/// Aucun mouvement d'argent n'y est branché dans ce lot (caisse, dépenses,
/// ventes, encaissement : lots suivants).
final moteurComptableProvider = FutureProvider<MoteurComptable>((ref) async {
  await ref.watch(referentielComptableProvider.future);
  return MoteurComptable(ref.watch(comptabiliteDaoProvider));
});
