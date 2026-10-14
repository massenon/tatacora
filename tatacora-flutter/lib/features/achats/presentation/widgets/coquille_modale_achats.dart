import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';

/// La coquille commune aux trois modales de M7 —
/// `m7-approvisionnement.html` l.561-595 (commande) et l.624-666 (réception),
/// `m7-achats.html` (formulaire fournisseur du moteur CRUD).
///
/// Le maître pose la même structure aux deux : en-tête (titre + sous-titre),
/// corps défilant borné, pied à deux boutons — « Annuler », puis le libellé de
/// validation.
///
/// ## Les deux bornes du maître sont portées, et l'une est indispensable
///
/// `max-w-2xl` (672 px) et `max-h-[85vh]`. Sans la seconde, la modale de
/// commande — qui porte autant de lignes que d'articles sélectionnés, et il
/// peut y en avoir vingt — déborde de l'écran et **son pied disparaît avec le
/// bouton de validation** : la commande devient impossible à créer sans
/// qu'aucune erreur ne s'affiche. C'est le défaut déjà rencontré sur la modale
/// de mouvement de M6, et le piège 7 en dit la leçon : une borne ne se teste
/// que sur un contenu plus grand qu'elle.
class CoquilleModaleAchats extends StatelessWidget {
  const CoquilleModaleAchats({
    required Key cle,
    required this.titre,
    required this.sousTitre,
    required this.corps,
    required this.libelleValidation,
    required this.cleValidation,
    required this.onValider,
    required this.envoiEnCours,
    this.refus,
    this.cleRefus,
    this.avertissement,
    this.largeur,
  }) : super(key: cle);

  final String titre;
  final String sousTitre;
  final Widget corps;
  final String libelleValidation;
  final Key cleValidation;
  final Future<void> Function() onValider;

  /// Pendant l'envoi, le bouton est **désactivé**, pas seulement occupé : un
  /// second clic créerait une seconde commande — ou pire, un second bon de
  /// réception, donc une seconde entrée de stock pour la même marchandise. Rien
  /// ne rend cette écriture idempotente : `CreerCommandeAchatRequest` pose
  /// `prohibited` sur `id`, faute de mécanisme de rejeu.
  final bool envoiEnCours;

  /// Le refus du serveur, affiché **dans la modale** et non en `SnackBar` : la
  /// saisie est encore là, et le message doit rester lisible pendant qu'on la
  /// corrige.
  final String? refus;

  final Key? cleRefus;

  /// Un avertissement qui n'est pas un refus — la tolérance de réception non
  /// configurée, par exemple : la saisie est juste, c'est ailleurs qu'il faut
  /// agir.
  final Widget? avertissement;

  /// La colonne de la modale, quand elle n'est pas `max-w-2xl` : la modale
  /// « Régler » porte `largeur="420px"` (D66). `null` : celle des deux autres.
  final double? largeur;

  @override
  Widget build(BuildContext context) {
    final hauteurMax =
        MediaQuery.of(context).size.height *
        AppLayout.fractionHauteurModaleAchats;

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        0,
      ),
      // Le titre est BORNÉ à la colonne de la modale : sans borne, la boîte de
      // dialogue prend la largeur INTRINSÈQUE de son titre le plus long — le
      // sous-titre « Commande [UUID] — reste dû … » de la modale « Régler » faisait
      // 855 px de large là où la vue en donne 420 (`largeur="420px"`), et
      // l'étirement emportait la colonne du corps. Il passe désormais à la ligne,
      // comme dans la vue.
      title: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: largeur ?? AppLayout.modaleAchats,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(titre, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.unit),
            Text(sousTitre, style: Theme.of(context).textTheme.labelMedium),
          ],
        ),
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: hauteurMax),
        child: SizedBox(
          width: largeur ?? AppLayout.modaleAchats,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (refus != null) ...[
                  Container(
                    key: cleRefus,
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: AppColors.erreurFond,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(color: AppColors.erreurBordure),
                    ),
                    child: Text(
                      refus!,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: AppColors.erreur,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                if (avertissement != null) ...[
                  avertissement!,
                  const SizedBox(height: AppSpacing.sm),
                ],
                corps,
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('modale-achats-annuler'),
          onPressed: envoiEnCours ? null : () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: cleValidation,
          onPressed: envoiEnCours ? null : onValider,
          child: Text(libelleValidation),
        ),
      ],
    );
  }
}

/// Le pavé doré des écarts et des refus, dans une modale.
class PaveAvertissementAchats extends StatelessWidget {
  const PaveAvertissementAchats({
    required Key cle,
    required this.titre,
    required this.corps,
  }) : super(key: cle);

  final String titre;
  final String corps;

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.reserveGoldFond,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titre,
            style: textes.labelMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          Text(corps, style: textes.labelMedium),
        ],
      ),
    );
  }
}
