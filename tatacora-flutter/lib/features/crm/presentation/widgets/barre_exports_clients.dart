import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared_widgets/modale_export.dart';
import '../../../../shared_widgets/toast_export.dart';
import '../../domain/entities/registre_clients.dart';
import '../providers_crm.dart';

/// « Exporter » du registre — `m3-clients-creances.html` l.65-66.
///
/// Depuis le 14/10/2026 (PO), le bouton ouvre la modale d'export PARTAGÉE
/// (`shared_widgets/modale_export.dart`) : l'ancien dialogue aux deux boutons
/// « Excel » / « PDF » est retiré. Le sous-titre dit le PÉRIMÈTRE exporté.
///
/// L'export emporte **la liste affichée**, filtres compris (PA-119), et une
/// liste vide se refuse : produire une page blanche laisserait croire qu'il
/// n'y a aucun client, alors que c'est le filtre qui ne rend rien.
abstract final class BarreExportsClients {
  /// Le titre de la modale (PO, 14/10/2026).
  static const String titreModale = 'Exporter — Clients & Créances';

  /// Le périmètre sans filtre actif (PO, 14/10/2026).
  static const String sansFiltre = 'Aucun filtre — tout le registre';

  /// Ouvre la modale, puis enregistre le document choisi.
  static Future<void> exporter(
    BuildContext context,
    WidgetRef ref,
    List<LigneClient> lignes,
  ) async {
    final filtre = _filtreActif(ref);
    final format = await choisirFormatExport(
      context,
      titre: titreModale,
      sousTitre: 'Périmètre : ${filtre ?? sansFiltre}',
    );
    if (format == null || !context.mounted) return;

    if (lignes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Rien à exporter : la liste filtrée est vide.',
            key: Key('clients-export-vide'),
          ),
        ),
      );
      return;
    }

    // Le libellé IMPRIMÉ dans le document reste celui d'avant : « Tous les
    // clients » sans filtre.
    final libelle = filtre ?? 'Tous les clients';
    await executerExport(
      context,
      () => switch (format) {
        FormatExport.pdf => ref.read(exporterRegistreClientsPdfProvider)(
          lignes,
          libelle,
        ),
        FormatExport.excel => ref.read(exporterRegistreClientsProvider)(
          lignes,
          libelle,
        ),
      },
      cleSucces: const Key('clients-export-fait'),
    );
  }

  /// Le filtre actif, composé au moment du clic ; `null` : aucun.
  static String? _filtreActif(WidgetRef ref) {
    final etat = ref.read(etatCreanceProvider);
    final terme = ref.read(rechercheClientProvider).trim();

    final parties = <String>[
      if (etat != EtatCreance.tous) etat.libelle,
      if (terme.isNotEmpty) 'recherche « $terme »',
    ];

    return parties.isEmpty ? null : parties.join(' — ');
  }
}
