import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../data/achats_api.dart';
import '../../domain/entities/bon_reception.dart';
import '../../domain/entities/commande_achat.dart';
import '../providers_achats.dart';
import 'coquille_achats.dart';

/// Le **rapprochement** d'une commande — EF-M7-04,
/// `GET /achats/commandes/{id}/rapprochement`.
///
/// ## Cet écran n'annonce JAMAIS un contrôle à trois voies
///
/// C'est le point de tout ce fichier. Le sous-titre de `m7-achats.html` (l.28)
/// promet « rapprochement à trois voies ». Le contrôle n'en porte que **deux** :
/// aucune table du schéma ne reçoit de facture fournisseur — `factures` est la
/// facturation CLIENT (M2), de nature opposée.
///
/// `ControleTroisVoiesService` accepte bien un tableau de montants facturés,
/// mais **ne le compare à rien** : il le teste contre `null`, bascule
/// `facture_verifiable` à `true` et retire l'avertissement qui disait que la
/// troisième voie n'avait pas été vérifiée. La route ne l'expose donc pas, et
/// cet écran **affiche ce que la route rend, et rien de plus**.
///
/// C'est la forme exacte de PA-59/60/61, posée sur la pièce qui autorise le
/// paiement d'un fournisseur : un rapprochement présenté comme complet alors
/// qu'il ne porte que sur deux voies est pire que pas de rapprochement du tout —
/// il donne une assurance qu'il n'a pas.
///
/// Les [Rapprochement.avertissements] du serveur sont affichés **tels quels**,
/// et ils ne sont pas décoratifs.
Future<void> ouvrirRapprochement(
  BuildContext context, {
  required CommandeAchat commande,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _ModaleRapprochement(commande: commande),
  );
}

class _ModaleRapprochement extends ConsumerWidget {
  const _ModaleRapprochement({required this.commande});

  final CommandeAchat commande;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resultat = ref.watch(rapprochementProvider(commande.id));

    return AlertDialog(
      key: const Key('modale-rapprochement'),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Rapprochement', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.unit),
          Text(
            '${commande.fournisseurRaisonSociale} — commandé le '
            '${commande.dateCommande}',
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ],
      ),
      content: SizedBox(
        width: AppLayout.modaleAchats,
        child: SingleChildScrollView(
          child: resultat.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('$e', key: const Key('rapprochement-erreur')),
            data: (r) => switch (r) {
              AchatsRecu(:final donnees) => _Corps(rapprochement: donnees),
              AchatsRefuse(:final motif) => Text(
                motif,
                key: const Key('rapprochement-refus'),
              ),
              // Jamais produite (la base est locale) ; le type la garde.
              AchatsInjoignable() => const Text(
                'La base du poste n’a pas répondu : aucun verdict n’est '
                'affiché, plutôt qu’un verdict d’hier qui autoriserait un '
                'paiement sur une situation dépassée.',
                key: Key('rapprochement-hors-ligne'),
              ),
            },
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('rapprochement-fermer'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fermer'),
        ),
      ],
    );
  }
}

class _Corps extends StatelessWidget {
  const _Corps({required this.rapprochement});

  final Rapprochement rapprochement;

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Les voies RÉELLEMENT confrontées, telles que le serveur les nomme —
        // jamais une mention « trois voies » écrite en dur.
        Container(
          key: const Key('rapprochement-voies'),
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.reserveGoldFond,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Voies confrontées : '
                '${rapprochement.voiesVerifiees.join(', ')}',
                style: textes.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (!rapprochement.factureVerifiable)
                Text(
                  'La facture fournisseur n’est PAS confrontée. Aucune table '
                  'n’en porte, et aucun montant facturé n’est comparé à quoi '
                  'que ce soit. Ce contrôle ne vaut donc pas autorisation de '
                  'paiement.',
                  style: textes.labelMedium?.copyWith(color: AppColors.erreur),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Text('Concordance globale', style: textes.labelMedium),
            const SizedBox(width: AppSpacing.xs),
            PastilleAchats(
              cle: const Key('rapprochement-concordance'),
              texte: rapprochement.estConforme ? 'Conforme' : 'Écart constaté',
              couleur: rapprochement.estConforme
                  ? AppColors.succes
                  : AppColors.erreur,
              fond: rapprochement.estConforme
                  ? AppColors.succesFond
                  : AppColors.erreurFondLeger,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (rapprochement.lignes.isEmpty)
          Text(
            'Cette commande ne porte aucune ligne : il n’y a rien à '
            'rapprocher.',
            key: const Key('rapprochement-vide'),
            style: textes.bodySmall,
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Article')),
                DataColumn(label: Text('Commandé'), numeric: true),
                DataColumn(label: Text('Reçu'), numeric: true),
                DataColumn(label: Text('Écart'), numeric: true),
                DataColumn(label: Text('Concordance')),
              ],
              rows: [
                for (final l in rapprochement.lignes)
                  DataRow(
                    cells: [
                      DataCell(
                        Text(
                          // Le libellé FIGÉ à la commande quand la source le
                          // porte (ce poste) ; sinon l'identifiant tel quel,
                          // jamais un nom inventé (le serveur ne le joint pas
                          // sur cette route).
                          l.libelle ?? l.articleId,
                          key: Key('rapprochement-ligne-${l.articleId}'),
                        ),
                      ),
                      DataCell(Text(l.commandee)),
                      DataCell(Text(l.recue)),
                      DataCell(Text(l.ecart)),
                      DataCell(Text(l.concordance)),
                    ],
                  ),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        for (final a in rapprochement.avertissements)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Container(
              key: Key('rapprochement-avertissement-${a.hashCode}'),
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.erreurFondLeger,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppColors.erreurBordure),
              ),
              // Le texte du serveur, tel quel. Le reformuler ferait deux
              // vérités à tenir, et la seconde vieillirait.
              child: Text(a, style: textes.labelMedium),
            ),
          ),
      ],
    );
  }
}
