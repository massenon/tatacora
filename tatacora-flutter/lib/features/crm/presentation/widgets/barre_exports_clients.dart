import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../shared_widgets/bouton_standard.dart';
import '../../domain/entities/registre_clients.dart';
import '../providers_crm.dart';

/// Les deux boutons d'export du maître — `m3-clients-creances.html` l.65-66.
///
/// Ils emportent **la liste affichée**, filtres compris (PA-119), et une liste
/// vide se refuse : produire une page blanche laisserait croire qu'il n'y a
/// aucun client, alors que c'est le filtre qui ne rend rien.
class BarreExportsClients extends ConsumerWidget {
  const BarreExportsClients({super.key, required this.lignes});

  final List<LigneClient> lignes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // Bouton standard (PO, 14/10/2026) ; dans une modale, `text-[13px]`
        // vaut 13 px (hors `<main>`).
        BoutonStandard(
          key: const Key('clients-export-excel'),
          libelle: 'Excel',
          taillePolice: Tailles.t13,
          onPressed: () => _exporter(context, ref),
        ),
        const SizedBox(width: AppSpacing.xs),
        BoutonStandard(
          key: const Key('clients-export-pdf'),
          libelle: 'PDF',
          variante: VarianteBouton.primaire,
          taillePolice: Tailles.t13,
          onPressed: () => _imprimer(context, ref),
        ),
      ],
    );
  }

  bool _verifier(BuildContext context) {
    if (lignes.isNotEmpty) return true;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Rien à exporter : la liste filtrée est vide.',
          key: Key('clients-export-vide'),
        ),
      ),
    );
    return false;
  }

  Future<void> _imprimer(BuildContext context, WidgetRef ref) async {
    if (!_verifier(context)) return;
    await ref.read(imprimerRegistreClientsProvider)(
      lignes,
      _libelleFiltre(ref),
    );
  }

  Future<void> _exporter(BuildContext context, WidgetRef ref) async {
    if (!_verifier(context)) return;

    final chemin = await ref.read(exporterRegistreClientsProvider)(
      lignes,
      _libelleFiltre(ref),
    );
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Registre exporté : $chemin',
          key: const Key('clients-export-fait'),
        ),
      ),
    );
  }

  /// Composé au moment du clic, depuis l'état réel des filtres.
  String _libelleFiltre(WidgetRef ref) {
    final etat = ref.read(etatCreanceProvider);
    final terme = ref.read(rechercheClientProvider).trim();

    final parties = <String>[
      if (etat != EtatCreance.tous) etat.libelle,
      if (terme.isNotEmpty) 'recherche « $terme »',
    ];

    return parties.isEmpty ? 'Tous les clients' : parties.join(' — ');
  }
}
