import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../restaurant/presentation/widgets/coquille_modale_restaurant.dart';
import '../../../synchronisation/data/telechargement_recu_depense.dart';
import '../../../synchronisation/presentation/providers_synchronisation.dart';
import '../../domain/entities/depense.dart';
import '../../domain/recu_depense.dart';
import '../providers_depenses.dart';

/// Ce que l'écran DIT de l'état d'un reçu (lot L4, 27/10/2026). Une phrase par
/// état, vraie ou rien : « envoyé » ne se dit qu'après l'accusé du serveur.
abstract final class TextesEtatRecu {
  static const String enAttente =
      'En attente d’envoi : le serveur n’a pas encore accusé ce reçu (hors '
      'réseau, synchronisation désactivée, ou dépense pas encore acceptée). Il '
      'est conservé sur ce poste et partira à la prochaine synchronisation.';

  static const String envoye = 'Envoyé : le serveur a accusé ce reçu.';

  static String refuse(String? cause) =>
      'Refusé par le serveur : ${cause ?? 'cause non précisée'}';

  static const String duServeur =
      'Reçu d’une dépense venue d’un autre poste : le fichier se télécharge à '
      'la demande.';
}

/// Ouvre le reçu de [depense] : le fichier de ce poste s'il y est, sinon il est
/// demandé au serveur (à la demande seulement, jamais en masse).
Future<void> ouvrirRecuDepense(BuildContext context, Depense depense) {
  return showDialog<void>(
    context: context,
    barrierColor: AppColors.voileModale,
    builder: (context) => DialogueRecuDepense(depense: depense),
  );
}

class DialogueRecuDepense extends ConsumerStatefulWidget {
  const DialogueRecuDepense({required this.depense, super.key});

  final Depense depense;

  @override
  ConsumerState<DialogueRecuDepense> createState() =>
      _DialogueRecuDepenseState();
}

class _DialogueRecuDepenseState extends ConsumerState<DialogueRecuDepense> {
  late Future<IssueRecuDistant> _issue;

  @override
  void initState() {
    super.initState();
    _issue = _obtenir();
  }

  Future<IssueRecuDistant> _obtenir() async {
    final issue = await ref
        .read(telechargementRecuDepenseProvider)
        .obtenir(widget.depense.id);
    // Un fichier téléchargé change la ligne (nom, empreinte) : la liste la relit.
    if (issue is RecuDisponible) ref.invalidate(depensesProvider);
    return issue;
  }

  @override
  Widget build(BuildContext context) {
    final recu = widget.depense.recu;
    return CoquilleModaleRestaurant(
      cle: const Key('depense-recu-modale'),
      titre: 'Reçu / facture (photo)',
      largeur: AppLayout.modaleDepense,
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.depense.libelle,
            key: const Key('depense-recu-libelle'),
            style: const TextStyle(
              fontFamily: AppTextStyles.police,
              fontSize: Tailles.t15,
              fontWeight: FontWeight.w600,
              color: Ardoise.c700,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          FutureBuilder<IssueRecuDistant>(
            future: _issue,
            builder: (context, instantane) {
              final issue = instantane.data;
              if (issue == null) {
                return const Padding(
                  padding: EdgeInsets.all(AppSpacing.md),
                  child: Center(
                    child: SizedBox(
                      key: Key('depense-recu-chargement'),
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                );
              }
              return switch (issue) {
                RecuDisponible(:final octets) => _Apercu(octets: octets),
                RecuIndisponible(:final phrase) => Container(
                  key: const Key('depense-recu-indisponible'),
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: Ardoise.c50,
                    borderRadius: BorderRadius.circular(AppRadius.roundedLg),
                  ),
                  child: Text(phrase, style: _aide),
                ),
              };
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          if (recu != null)
            Text(
              switch (recu.statut) {
                StatutRecu.enAttente => TextesEtatRecu.enAttente,
                StatutRecu.envoye => TextesEtatRecu.envoye,
                StatutRecu.refuse => TextesEtatRecu.refuse(recu.cause),
                StatutRecu.duServeur => TextesEtatRecu.duServeur,
              },
              key: const Key('depense-recu-etat'),
              style: recu.statut == StatutRecu.refuse
                  ? _aide.copyWith(color: PaletteMaitre.rouge700)
                  : _aide,
            ),
        ],
      ),
      actions: [
        FilledButton(
          key: const Key('depense-recu-fermer'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fermer'),
        ),
      ],
    );
  }

  static const TextStyle _aide = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: Tailles.t13,
    color: Ardoise.c500,
  );
}

class _Apercu extends StatelessWidget {
  const _Apercu({required this.octets});

  final List<int> octets;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 360),
      child: InteractiveViewer(
        child: Image.memory(
          Uint8List.fromList(octets),
          key: const Key('depense-recu-image'),
          fit: BoxFit.contain,
          errorBuilder: (context, erreur, pile) => const Text(
            'Aperçu impossible : le fichier est conservé mais ne peut pas être '
            'affiché ici.',
            key: Key('depense-recu-apercu-impossible'),
          ),
        ),
      ),
    );
  }
}
