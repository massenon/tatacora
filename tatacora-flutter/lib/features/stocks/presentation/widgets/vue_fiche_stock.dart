import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/format/formats.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/entities/fiche_stock.dart';

/// Le résultat de la fiche — récapitulatif, lignes, et exports.
///
/// ## Le bandeau d'incohérence vient EN PREMIER
///
/// Il est posé avant le récapitulatif, et pas en pied de page : la mention qui
/// borne la portée d'un document doit être lue **avant** les chiffres qu'elle
/// disqualifie. Même raisonnement que « ne vaut pas facture » au corps du
/// document de réservation, et non en pied (PA-113).
class VueFicheStock extends ConsumerWidget {
  const VueFicheStock({
    super.key,
    required this.fiche,
    required this.pointLibelle,
  });

  final FicheStock fiche;
  final String? pointLibelle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!fiche.coherent) _BandeauIncoherent(),
        _Recapitulatif(fiche: fiche, pointLibelle: pointLibelle),
        // La paire « Export Excel » / « Export PDF » qui suivait est RETIRÉE
        // (14/10/2026, demande du PO) : la vue n'a qu'UN bouton « Exporter »,
        // dans la carte des filtres, qui ouvre la modale partagée
        // (`ecran_inventaires.dart`, `_CartePeriode`).
        const SizedBox(height: AppSpacing.sm),
        _Lignes(fiche: fiche),
      ],
    );
  }
}

class _BandeauIncoherent extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('fiche-incoherente'),
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.erreurFondLeger,
        borderRadius: BorderRadius.circular(AppSpacing.xs),
        border: Border.all(color: AppColors.erreurBordure),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: AppColors.erreur),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              'Cette fiche NE VAUT PAS JUSTIFICATIF : le cumul des mouvements '
              'ne correspond pas au stock théorique. Un mouvement a été '
              'écrit hors de l’écriture dédiée, donc sans le contrôle de '
              'disponibilité.',
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: AppColors.erreur),
            ),
          ),
        ],
      ),
    );
  }
}

class _Recapitulatif extends StatelessWidget {
  const _Recapitulatif({required this.fiche, required this.pointLibelle});

  final FicheStock fiche;
  final String? pointLibelle;

  @override
  Widget build(BuildContext context) {
    final u = fiche.article.unite;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.neutre0,
        borderRadius: BorderRadius.circular(AppSpacing.md),
        border: Border.all(color: AppColors.neutre200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            fiche.article.libelle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(
            // La portée est DITE : une fiche restreinte à un point qui ne le
            // dirait pas serait lue comme la fiche complète de l'article, et
            // son solde final passerait pour le stock total (PA-119).
            'Du ${fiche.debut} au ${fiche.fin} — '
            '${pointLibelle ?? 'tous points confondus'}',
            key: const Key('fiche-portee'),
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.unit,
            children: [
              _Poste(
                cle: 'initial',
                libelle: 'Stock initial',
                valeur: '${fiche.stockInitial} $u',
              ),
              _Poste(
                cle: 'entrees',
                libelle: 'Entrées',
                valeur: '${fiche.entrees} $u',
              ),
              _Poste(
                cle: 'sorties',
                libelle: 'Sorties',
                valeur: '${fiche.sorties} $u',
              ),
              _Poste(
                cle: 'pertes',
                libelle: 'Pertes',
                valeur: '${fiche.pertes} $u',
              ),
              // Comptées à part : elles ne viennent pas d'un flux mais d'un
              // constat, et les mélanger ferait passer un écart d'inventaire
              // pour un achat.
              _Poste(
                cle: 'regularisations',
                libelle: 'Régularisations',
                valeur: '${fiche.regularisations} $u',
              ),
              _Poste(
                cle: 'theorique',
                libelle: 'Stock théorique',
                valeur: '${fiche.stockTheorique} $u',
                accent: true,
              ),
              _Poste(
                cle: 'valeur',
                libelle: 'Valeur',
                valeur: formaterFcfa(int.parse(fiche.valeurStockTheorique)),
                accent: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Poste extends StatelessWidget {
  const _Poste({
    required this.cle,
    required this.libelle,
    required this.valeur,
    this.accent = false,
  });

  final String cle;
  final String libelle;
  final String valeur;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          libelle.toUpperCase(),
          style: Theme.of(context).textTheme.labelMedium,
        ),
        Text(
          valeur,
          key: Key('fiche-$cle'),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: accent ? AppColors.navy : AppColors.neutre700,
          ),
        ),
      ],
    );
  }
}

class _Lignes extends StatelessWidget {
  const _Lignes({required this.fiche});

  final FicheStock fiche;

  @override
  Widget build(BuildContext context) {
    if (fiche.estVide) {
      return Container(
        key: const Key('fiche-aucun-mouvement'),
        padding: const EdgeInsets.all(AppSpacing.lg),
        alignment: Alignment.center,
        child: Text(
          // « Aucun mouvement » n'est pas « pas de données » : le stock initial
          // reste le stock théorique, et c'est une information.
          'Aucun mouvement sur cette période — le stock théorique est celui du '
          'début de période.',
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.neutre0,
        borderRadius: BorderRadius.circular(AppSpacing.md),
        border: Border.all(color: AppColors.neutre200),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Date')),
            DataColumn(label: Text('Type')),
            DataColumn(label: Text('Motif')),
            DataColumn(label: Text('Entrée'), numeric: true),
            DataColumn(label: Text('Sortie'), numeric: true),
            DataColumn(label: Text('Solde'), numeric: true),
            // La colonne « Par » de la vue (EF-M6-06) : le « qui » de chaque
            // mouvement. Absente tant que la fiche venait d'une route qui ne
            // le portait pas ; les mouvements locaux l'ont.
            DataColumn(label: Text('Par')),
          ],
          rows: [
            for (final (index, l) in fiche.lignes.indexed)
              // Pas de clé sur la `DataRow` : elle n'atteint pas l'arbre de
              // widgets (piège 10).
              DataRow(
                cells: [
                  DataCell(Text(l.date, key: Key('fiche-ligne-$index'))),
                  DataCell(
                    Text(
                      // La décision de forcer une rupture se lit ICI : la
                      // confirmation promet qu'elle sera « tracée comme
                      // rupture forcée dans la fiche de stock ».
                      l.ruptureForcee ? '${l.type} — rupture forcée' : l.type,
                      key: l.ruptureForcee ? Key('fiche-rupture-$index') : null,
                    ),
                  ),
                  DataCell(Text(l.motif)),
                  // Un tiret plutôt qu'un zéro : une ligne est une entrée OU
                  // une sortie, et « 0.00 » invite à additionner une colonne
                  // qui n'a pas de contenu.
                  DataCell(Text(_ouRien(l.entree))),
                  DataCell(Text(_ouRien(l.sortie))),
                  DataCell(
                    Text(
                      l.solde,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  // Un tiret, jamais un nom de remplacement.
                  DataCell(Text(l.par ?? '—')),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// Les quantités arrivent écrites par `ecrireCentiemes` : « 0.00 » est le seul
  /// zéro possible. Comparer le texte évite de repasser par un flottant.
  static String _ouRien(String quantite) => quantite == '0.00' ? '—' : quantite;
}
