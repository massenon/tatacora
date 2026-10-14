// Vue Blade maîtresse (PA-183) : pwa/pos/heberges.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart' show sessionProvider;
import '../../../../core/format/formats.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../comptabilite/domain/calcul_tva.dart' show RefusTva;
import '../../../comptabilite/domain/refus_comptable.dart' show RefusComptable;
import '../../../hebergement/domain/entities/reservation.dart';
import '../../../restaurant/presentation/widgets/coquille_modale_restaurant.dart';
import '../../domain/entities/panier.dart';
import '../../domain/messages_ventes.dart' show RefusVente;
import '../../domain/place_hebergement.dart';
import '../../domain/repositories/panier_repository.dart';
import '../providers_pos.dart';
import 'vue_panier.dart' show facturerPanier;

/// La modale **« Clôturer avant le départ ? »** de la vue
/// (`heberges.blade.php` l.291-369), posée dans le châssis partagé des modales
/// ([CoquilleModaleRestaurant], l'équivalent de `x-pwa.modale`).
///
/// ## Elle s'ouvre TOUJOURS, et c'est elle la question de la règle 5
///
/// La vue ouvre ce récapitulatif à chaque clic sur « Clôturer et facturer »
/// (`ouvrirClotureSejour`, l.270) ; « Facture » exécute (l.365). L'ancien écran
/// posait la question seulement quand `cloturer()` levait
/// `ClotureAnticipeeNonConfirmee`, puis une seconde fois. Désormais UNE seule
/// question, celle de la vue, dont le texte nomme la conséquence : « Aucune
/// consommation ne pourra plus être enregistrée pour ce séjour. » Confirmer
/// appelle donc `cloturer(anticipe: true)` — la garde du dépôt, elle, n'a pas
/// bougé : sans cette confirmation explicite, la clôture anticipée reste
/// refusée. La clôture n'est jamais silencieuse (règle 5).
///
/// ## Ce que la modale ne rend pas (09/10/2026)
///
/// - **La case « Payer séparément (l'hébergement sera facturé plus tard) »**
///   (l.309-315) et **son rappel** (l.316-325). Elle ferait émettre une facture
///   qui ne porte que les consommations, l'hébergement restant dû sur la fiche
///   du client : c'est un changement de la règle de facturation du séjour
///   (`Facturer.emettrePourSejour` compose TOUJOURS nuitées + consommations,
///   Q3 `PlaceHebergement.horsPanier`). La directive qui l'a introduite
///   (02/09/2026) a amendé RG-04 côté serveur ; l'arbitrage côté poste n'est
///   pas rendu, et une case sans effet sur la facture serait le défaut que ce
///   dépôt a rencontré dix fois. À remonter au Product Owner.
/// - **« une vente en note de chambre est enregistrée au journal »**
///   (`cloture_detail`, `lang/fr/pos_pwa.php`). Ce poste n'écrit aucune vente
///   en note de chambre au clôturer : il fige le panier et émet la pièce du
///   registre de facturation. La phrase est donc rendue SANS cette proposition.
class ModaleClotureSejour extends StatelessWidget {
  const ModaleClotureSejour({
    required this.reservation,
    required this.panier,
    super.key,
  });

  final Reservation reservation;
  final Panier panier;

  /// `pos_pwa.heberges.cloture_titre`.
  static const String titre = 'Clôturer avant le départ ?';

  /// `pos_pwa.heberges.cloture_message`.
  static const String message =
      'Aucune consommation ne pourra plus être enregistrée pour ce séjour.';

  /// `pos_pwa.heberges.cloture_detail`, sans la vente en note de chambre.
  static const String detail =
      'Le panier est clôturé et la facture du séjour est émise : nuitées '
      'd’abord, consommations ensuite, un seul document.';

  /// `pos_pwa.heberges.cloture_bloc_hebergement`.
  static const String blocHebergement = 'Hébergement';

  /// `pos_pwa.heberges.cloture_bloc_consommations`.
  static const String blocConsommations = 'Consommations';

  /// `pos_pwa.heberges.cloture_total_facture`.
  static const String totalFacture = 'Total facturé';

  /// `pwa.modale.annuler`.
  static const String annuler = 'Annuler';

  /// `pos_pwa.heberges.cloture_facture`.
  static const String facture = 'Facture';

  // L'échelle des MODALES : hors `<main>`, `app.css` l.172 ne les remappe pas.
  static const TextStyle _petit = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: Tailles.t12,
    color: Ardoise.c500,
  );

  static const TextStyle _etiquette = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: Tailles.t12,
    fontWeight: FontWeight.bold,
    color: Ardoise.c500,
    letterSpacing: Tailles.t12 * AppTextStyles.suiviLarge,
  );

  static const TextStyle _montant = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: Tailles.t13,
    fontWeight: FontWeight.bold,
    color: AppColors.navy,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const TextStyle _ligne = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: Tailles.t12,
    color: Ardoise.c600,
  );

  static const TextStyle _bouton = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: Tailles.t13,
    fontWeight: FontWeight.w600,
  );

  @override
  Widget build(BuildContext context) {
    // La MÊME composition que la facture de départ : ce que la modale affiche
    // est ce que `Facturer` portera, jamais une seconde arithmétique de vue.
    final composition = CompositionFactureSejour.composer(
      montantHebergement: reservation.tarifNuit * reservation.nuits,
      totalPanier: panier.total,
    );

    Widget cadre(List<Widget> enfants) => Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        border: Border.all(color: Ardoise.c200),
        borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: enfants,
      ),
    );

    Widget enTete(String libelle, int montant) => Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(libelle.toUpperCase(), style: _etiquette),
        Text(formaterFcfa(montant), style: _montant),
      ],
    );

    return CoquilleModaleRestaurant(
      cle: const Key('modale-cloture-sejour'),
      titre: titre,
      sousTitre: message,
      largeur: LargeursPos.modaleCloture,
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(detail, style: _petit),
          const SizedBox(height: AppSpacing.md),
          cadre([
            enTete(blocHebergement, composition.hebergement),
            const SizedBox(height: AppSpacing.unit),
            Text(
              '${reservation.nuits} nuitée(s) × '
              '${formaterFcfa(reservation.tarifNuit)}',
              key: const Key('cloture-nuitees'),
              style: _petit,
            ),
          ]),
          const SizedBox(height: AppSpacing.md),
          cadre([
            enTete(blocConsommations, composition.consommations),
            const SizedBox(height: AppSpacing.xxs),
            for (final ligne in panier.lignes)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      '${ligne.libelle} × ${ligne.quantite}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _ligne,
                    ),
                  ),
                  Text(formaterFcfa(ligne.montant), style: _ligne),
                ],
              ),
          ]),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Ardoise.c100)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                const Text(
                  totalFacture,
                  style: TextStyle(
                    fontFamily: AppTextStyles.police,
                    fontSize: Tailles.t13,
                    fontWeight: FontWeight.w600,
                    color: Ardoise.c600,
                  ),
                ),
                Text(
                  key: const Key('cloture-total-facture'),
                  formaterFcfa(composition.total),
                  style: const TextStyle(
                    fontFamily: AppTextStyles.police,
                    fontSize: Tailles.t17,
                    fontWeight: FontWeight.bold,
                    color: AppColors.navy,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        OutlinedButton(
          key: const Key('cloture-annuler'),
          onPressed: () => Navigator.of(context).pop(false),
          style: OutlinedButton.styleFrom(
            foregroundColor: Ardoise.c700,
            side: const BorderSide(color: Ardoise.c300),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.roundedLg),
            ),
            textStyle: _bouton,
          ),
          child: const Text(annuler),
        ),
        // « Facture » — le bouton qui exécute (l.365).
        FilledButton(
          key: const Key('pos-confirmer-cloture-anticipee'),
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.navy,
            foregroundColor: AppColors.neutre0,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.roundedLg),
            ),
            textStyle: _bouton,
          ),
          child: const Text(facture),
        ),
      ],
    );
  }
}

/// Ouvre la modale, puis — si l'opérateur confirme — clôture et facture.
///
/// Les appels sont ceux de l'ancien panneau (`cloturer`, puis
/// `facturerPanier`) : le mode de règlement est lu au même endroit, remis à
/// l'état neutre au même moment.
///
/// ⚠ ÉCART — AUCUN RATTRAPAGE d'émission sur cet écran (09/10/2026, relu
/// contre `ecran_pos_comptant.dart` l.183 et `heberges.blade.php`).
/// La vue clôture et facture dans UNE transaction (`cloturerEtFacturer`,
/// l.365) : si la facturation échoue, rien n'est enregistré et le panier reste
/// intact (`refus_facturation`). Ici, `cloturer` puis `facturerPanier` sont
/// deux écritures : une émission qui échoue laisse le panier CLÔTURÉ, le
/// séjour affiche « AUCUN PANIER », et `ActionFacture` (seul chemin de
/// rattrapage, branché sur le POS au comptant) n'est atteint depuis aucun
/// écran du séjour. La vue n'a aucun bouton de rattrapage et en ajouter un
/// serait une structure absente de la vue. Risque porté au Product Owner.
Future<void> ouvrirModaleClotureSejour(
  BuildContext context,
  WidgetRef ref, {
  required Reservation reservation,
  required Panier panier,
}) async {
  final confirme = await showDialog<bool>(
    context: context,
    barrierColor: AppColors.voileModale,
    builder: (_) =>
        ModaleClotureSejour(reservation: reservation, panier: panier),
  );
  if (confirme != true || !context.mounted) return;

  try {
    final mode = ref.read(modeReglementProvider);
    // Le mode passé n'est PAS celui qui sera écrit : un séjour est toujours
    // porté sur la note de chambre (`PanierDao.cloturer`, comme `PosHeberges`).
    final cloture = await ref
        .read(gererPanierProvider)
        .cloturer(
          panier.id,
          anticipe: true,
          modePaiement: mode.code,
          auteurId: ref.read(sessionProvider)?.utilisateurId ?? '',
        );
    ref.read(modeReglementProvider.notifier).reinitialiser();
    rafraichirPaniers(ref);
    if (context.mounted) await facturerPanier(context, ref, cloture);
  } on PanierVide catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  } on RefusVente catch (e) {
    // Un module sans catalogue encaissable, un article retiré du catalogue :
    // la phrase est celle du serveur, le panier reste OUVERT et intact.
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  } on RefusTva catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  } on RefusComptable catch (e) {
    // La pièce est refusée : RIEN n'a été écrit, le panier reste OUVERT.
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}
