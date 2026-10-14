import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../data/stocks_api.dart';
import '../../domain/entities/mouvement_stock.dart';
import '../providers_stocks.dart';

/// Le **journal des mouvements** d'un article — EF-M6-04 et EF-M6-06 (« qui,
/// quoi, quand, pourquoi »).
///
/// ## Où il vit, et pourquoi pas ailleurs
///
/// La vue n'a **pas de page de journal**. Sa seule liste de mouvements est le
/// tableau « Détail des mouvements » de la fiche de stock, déjà porté par
/// `VueFicheStock`. Ce panneau est donc un **ajout à la vue**, placé là où la
/// vue place l'écriture d'un mouvement : dans la modale « Mouvement de stock ».
/// Trois raisons, dont une de terrain :
///
/// 1. **La modale affiche « Stock actuel » sans rien qui l'explique.** Le
///    chiffre est la somme des mouvements ; ce journal est ce qui permet de le
///    vérifier au moment où l'on s'apprête à l'engager.
/// 2. **Un double mouvement ne se corrige que par un mouvement inverse** :
///    `mouvements_stock` est en ajout seul. Un magasinier qui ne sait pas si
///    son mouvement est passé le ressaisit. Voir les dernières lignes est la
///    protection contre le doublon.
/// 3. **Il porte l'AUTEUR** (EF-M6-06) : la colonne « Par » de la fiche le
///    porte aussi, désormais.
///
/// ## Ce que ce panneau NE montre pas : la colonne « Solde »
///
/// Une page du journal ne porte qu'une tranche de l'historique : un cumul
/// partirait d'un point arbitraire. L'absence est nommée à l'écran, avec
/// l'endroit où le solde se lit — la fiche de stock.
class JournalMouvements extends ConsumerWidget {
  const JournalMouvements({super.key, required this.articleId});

  final String articleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resultat = ref.watch(journalArticleProvider(articleId));

    return Container(
      key: const Key('journal-mouvements'),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.neutre0,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.neutre200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            // Le titre du maître (`m6-inventaires.html` l.244).
            'Détail des mouvements',
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.xs),
          resultat.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(AppSpacing.sm),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) =>
                _Note(cle: const Key('journal-erreur'), texte: '$e'),
            data: (r) => switch (r) {
              JournalRecu(:final mouvements, :final total) => _Lignes(
                mouvements: mouvements,
                total: total,
              ),
              JournalRefuse(:final motif) => _Note(
                cle: const Key('journal-refus'),
                texte: motif,
              ),
              // Jamais produit : une base locale n'est pas hors connexion. L'arm
              // reste parce que le type scellé est partagé ; il ne dit rien
              // d'une coupure qui n'existe pas.
              JournalInjoignable() => const _Note(
                cle: Key('journal-hors-ligne'),
                texte: 'Le journal n’a pas pu être lu.',
              ),
            },
          ),
        ],
      ),
    );
  }
}

class _Lignes extends StatelessWidget {
  const _Lignes({required this.mouvements, required this.total});

  final List<MouvementStock> mouvements;
  final int total;

  @override
  Widget build(BuildContext context) {
    if (mouvements.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Text(
          // Le texte du maître (`m6-inventaires.html` l.248), et une
          // information à part entière : aucun mouvement veut dire que le
          // stock n'a jamais bougé, pas que la donnée manque.
          'Aucun mouvement sur cette période.',
          key: const Key('journal-vide'),
          style: Theme.of(context).textTheme.labelMedium,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: AppSpacing.md,
            columns: const [
              // L'ordre du maître (`m6-inventaires.html` l.252-258), moins la
              // colonne « Solde », qu'une page ne peut pas porter, plus la
              // colonne « Point » : le journal traverse les points de stockage,
              // et sans elle on ne saurait pas si la marchandise est au bar ou
              // au magasin — l'erreur ne se verrait qu'à l'inventaire.
              DataColumn(label: Text('Date')),
              DataColumn(label: Text('Type')),
              DataColumn(label: Text('Point')),
              DataColumn(label: Text('Motif')),
              DataColumn(label: Text('Entrée'), numeric: true),
              DataColumn(label: Text('Sortie'), numeric: true),
              DataColumn(label: Text('Par')),
            ],
            rows: [
              for (final m in mouvements)
                // Pas de clé sur la `DataRow` : elle n'atteint pas l'arbre de
                // widgets (piège 10). Elle est posée sur la première cellule.
                DataRow(
                  cells: [
                    DataCell(
                      Text(m.dateCourte, key: Key('journal-ligne-${m.id}')),
                    ),
                    DataCell(Text(m.libelleJournal)),
                    DataCell(
                      Text(m.pointLibelle.isEmpty ? m.pointId : m.pointLibelle),
                    ),
                    DataCell(Text(m.motif)),
                    // La quantité n'apparaît que dans la colonne de son SENS,
                    // que porte chaque mouvement. La porter des deux côtés
                    // inviterait à additionner une colonne qui n'a pas de
                    // contenu.
                    DataCell(Text(m.estEntrante ? m.quantite : '—')),
                    DataCell(Text(m.estEntrante ? '—' : m.quantite)),
                    // Un tiret, jamais un nom de remplacement : « auteur
                    // inconnu » n'est pas « auteur dont le nom est vide ».
                    DataCell(Text(m.utilisateur ?? '—')),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          _pied(),
          key: const Key('journal-pied'),
          style: Theme.of(context).textTheme.labelMedium,
        ),
      ],
    );
  }

  /// Le pied dit **ce qui n'est pas montré**, dans les deux sens.
  ///
  /// Une page pleine sans ce texte se lirait « c'est tout », et un magasinier
  /// conclurait à l'absence d'un mouvement qui se trouve à la page suivante.
  String _pied() {
    final montres = mouvements.length;
    final tranche = montres < total
        ? '$montres mouvement(s) affiché(s) sur $total.'
        : '$montres mouvement(s).';

    return '$tranche La colonne « Solde » n’est pas rendue ici : un cumul sur '
        'une page partirait d’un point arbitraire. Le solde cumulé se lit sur '
        'la fiche de stock.';
  }
}

class _Note extends StatelessWidget {
  const _Note({required Key cle, required this.texte}) : super(key: cle);

  final String texte;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Text(
        texte,
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(color: AppColors.neutre500),
      ),
    );
  }
}
