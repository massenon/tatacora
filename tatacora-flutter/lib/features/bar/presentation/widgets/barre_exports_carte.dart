// Vue Blade maîtresse (PA-183) : pwa/bar/carte.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/boisson.dart';
import '../../domain/entities/carte_bar.dart';
import '../providers_bar.dart';
import '../../../../shared_widgets/modale_export.dart';
import '../../../../shared_widgets/toast_export.dart';
import 'vue_ventes_bar.dart';

/// Les documents de la carte — la vue, corps partagé des cartes l.101-109.
///
/// « Exporter » ouvre la modale de format (PDF ou tableur) et emporte **le
/// tableau affiché**, filtres compris (PA-119) ; « Imprimer la fiche des
/// prix » rend un **autre document**, groupé par catégorie, celui qu'on pose
/// au comptoir, et s'imprime directement, sans modale — comme la vue.
///
/// Ces deux gestes vivent dans l'EN-TÊTE de la vue (l.101-109), pas au-dessus
/// du tableau : jusqu'au 08/10/2026 une barre propre à l'onglet les portait,
/// ce qui les plaçait à 500 px de leur emplacement. L'en-tête de l'écran les
/// déclenche par [BarreExportsCarte], qui ne rend plus rien par elle-même.
///
/// « Exporter » exporte l'**onglet courant** (PO 03/09/2026, vue l.65-67) :
/// la carte, ou les ventes du rayon quand l'onglet « Ventes » est ouvert.
///
/// Une liste vide se refuse : produire une page blanche laisserait croire que
/// la carte est vide, alors que c'est le filtre qui ne rend rien.
abstract final class BarreExportsCarte {
  /// « Exporter » — le document de l'onglet courant.
  static Future<void> exporter(BuildContext context, WidgetRef ref) async {
    if (ref.read(ongletCarteBarProvider) == OngletCarteBar.ventes) {
      return exporterVentesBar(context, ref);
    }
    final lignes = await ref.read(carteFiltreeProvider.future);
    if (!context.mounted) return;

    // UN bouton « Exporter » (vue l.101-102) — dérogation du Product
    // Owner du 01/09/2026 (`DerogationsMaquette`, `export_bouton_unique`) :
    // la paire « Excel » / « PDF » du maître ouvrait déjà la même modale
    // de format, et deux entrées pour un seul formulaire laissaient croire
    // à deux documents. Le format se choisit DANS la modale.
    final format = await choisirFormatExport(
      context,
      // `carte_pwa.bar.export_titre` — la modale NOMME ce qu'elle produira.
      titre: 'Exporter — Carte du bar',
    );
    if (format == null || !context.mounted) return;
    if (!_verifier(context, lignes)) return;

    final filtre = _libelleFiltre(ref);
    await executerExport(
      context,
      () => switch (format) {
        FormatExport.pdf => ref.read(exporterCartePdfProvider)(lignes, filtre),
        FormatExport.excel => ref.read(exporterCarteProvider)(lignes, filtre),
      },
      cleSucces: const Key('carte-export-fait'),
    );
  }

  /// « Imprimer la fiche des prix » — directement, sans modale.
  static Future<void> fichePrix(BuildContext context, WidgetRef ref) async {
    final lignes = await ref.read(carteFiltreeProvider.future);
    if (!context.mounted) return;
    if (!_verifier(context, lignes)) return;

    final ecartes = await ref.read(imprimerFichePrixProvider)(lignes);
    if (!context.mounted || ecartes == 0) return;

    // On ne masque pas : un tarif absent devient négociable au comptoir.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$ecartes article(s) sans tarif ont été écartés de la fiche.',
          key: const Key('carte-fiche-ecartes'),
        ),
      ),
    );
  }

  static bool _verifier(BuildContext context, List<LigneCarte> lignes) {
    if (lignes.isNotEmpty) return true;

    // `carte_pwa.export_vide`, que la vue affiche en toast (l.891-893).
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(TextesExport.vide, key: Key('carte-export-vide')),
      ),
    );
    return false;
  }

  static String _libelleFiltre(WidgetRef ref) {
    final categorie = ref.read(categorieCarteProvider);
    final etat = ref.read(etatCarteProvider);
    final terme = ref.read(rechercheCarteProvider).trim();

    final parties = <String>[
      if (categorie != null)
        CategorieBoisson.depuisCode(categorie)?.libelle ?? categorie,
      if (etat != EtatCarte.tous) etat.libelle,
      if (terme.isNotEmpty) 'recherche « $terme »',
    ];

    return parties.isEmpty ? 'Carte complète' : parties.join(' — ');
  }
}
