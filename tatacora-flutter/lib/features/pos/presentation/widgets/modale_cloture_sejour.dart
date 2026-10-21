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
/// ## La case « Payer séparément » EST rendue (21/10/2026)
///
/// La case (l.309-315) et son rappel (l.316-325) : décochée, la facture porte
/// les nuitées PUIS les consommations (un seul document, RG-04) ; cochée, elle
/// ne porte QUE les consommations — `Facturer.emettreConsommationsDuSejour`,
/// la reprise de `EmissionFactureService::emettrePourConsommations` (amendement
/// de RG-04, directive du PO du 02/09/2026) — et l'hébergement reste dû sur la
/// fiche du client. La modale affiche EXACTEMENT ce que la facture portera : le
/// « Total facturé » suit la case. Jusqu'au 21/10/2026 elle était refusée ici,
/// faute de ce chemin d'émission.
///
/// ## « une vente en note de chambre est enregistrée au journal » est VRAI ici
///
/// (`cloture_detail`, `lang/fr/pos_pwa.php`) Depuis le lot F5 (17/10/2026), la
/// clôture d'un séjour enregistre la vente en note de chambre au journal (le
/// panier clôturé EST la vente, lue par l'Historique des ventes) et la fait
/// partir au serveur : la phrase de la vue est rendue entière.
///
/// ## La remise
///
/// La ligne « Remise » (`- montant`, l.341-346) n'est PAS rendue : le panier de
/// ce poste ne porte aucune remise (`paniers_local` n'a ni type ni valeur de
/// remise — schéma à étendre). Mention de MESURE : « Remise ».
class ModaleClotureSejour extends StatefulWidget {
  const ModaleClotureSejour({
    required this.reservation,
    required this.panier,
    this.payerSeparement,
    super.key,
  });

  final Reservation reservation;
  final Panier panier;

  /// Lu par l'appelant après la confirmation : le choix de la case « Payer
  /// séparément ». Absent, la case existe quand même (état de la modale).
  final ValueNotifier<bool>? payerSeparement;

  /// `pos_pwa.heberges.cloture_titre`.
  static const String titre = 'Clôturer avant le départ ?';

  /// `pos_pwa.heberges.cloture_message`.
  static const String message =
      'Aucune consommation ne pourra plus être enregistrée pour ce séjour.';

  /// `pos_pwa.heberges.cloture_detail`, au mot.
  static const String detail =
      'Le panier est clôturé, une vente en note de chambre est enregistrée au journal, et la facture du séjour est émise : nuitées d’abord, consommations ensuite, un seul document.';

  /// `pos_pwa.heberges.cloture_payer_separement`.
  static const String payerSeparementLibelle =
      "Payer séparément (l'hébergement sera facturé plus tard)";

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
  State<ModaleClotureSejour> createState() => _EtatModaleClotureSejour();
}

class _EtatModaleClotureSejour extends State<ModaleClotureSejour> {
  late final ValueNotifier<bool> _separement =
      widget.payerSeparement ?? ValueNotifier<bool>(false);

  Reservation get reservation => widget.reservation;
  Panier get panier => widget.panier;

  static const TextStyle _petit = ModaleClotureSejour._petit;
  static const TextStyle _etiquette = ModaleClotureSejour._etiquette;
  static const TextStyle _montant = ModaleClotureSejour._montant;
  static const TextStyle _ligne = ModaleClotureSejour._ligne;
  static const TextStyle _bouton = ModaleClotureSejour._bouton;

  @override
  Widget build(BuildContext context) {
    // La MÊME composition que la facture de départ : ce que la modale affiche
    // est ce que `Facturer` portera, jamais une seconde arithmétique de vue.
    final composition = CompositionFactureSejour.composer(
      montantHebergement: reservation.tarifNuit * reservation.nuits,
      totalPanier: panier.total,
    );
    final separement = _separement.value;
    // Le « Total facturé » DÉPEND de la case : la modale affiche exactement ce
    // que la facture portera.
    final totalFacture = separement
        ? composition.consommations
        : composition.total;

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
      titre: ModaleClotureSejour.titre,
      sousTitre: ModaleClotureSejour.message,
      largeur: LargeursPos.modaleCloture,
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(ModaleClotureSejour.detail, style: _petit),
          const SizedBox(height: AppSpacing.md),
          cadre([
            enTete(
              ModaleClotureSejour.blocHebergement,
              composition.hebergement,
            ),
            const SizedBox(height: AppSpacing.unit),
            Text(
              '${reservation.nuits} nuitée(s) × '
              '${formaterFcfa(reservation.tarifNuit)}',
              key: const Key('cloture-nuitees'),
              style: _petit,
            ),
            // `cloture_payer_separement` : COCHÉE = payer séparément, la facture
            // ne porte que les consommations (l.309-315).
            InkWell(
              key: const Key('cloture-payer-separement'),
              onTap: () => setState(() => _separement.value = !separement),
              child: Row(
                children: [
                  Checkbox(
                    value: separement,
                    onChanged: (v) =>
                        setState(() => _separement.value = v ?? false),
                  ),
                  const Expanded(
                    child: Text(
                      ModaleClotureSejour.payerSeparementLibelle,
                      style: _petit,
                    ),
                  ),
                ],
              ),
            ),
            // Le RAPPEL exigé par la directive (l.316-325) : ce qui restera dû,
            // en toutes lettres, avant que le doigt ne clique.
            if (separement)
              Container(
                key: const Key('cloture-rappel-hebergement'),
                margin: const EdgeInsets.only(top: AppSpacing.xxs),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: PaletteMaitre.ambre50,
                  border: Border.all(color: PaletteMaitre.ambre200),
                  borderRadius: BorderRadius.circular(AppRadius.roundedLg),
                ),
                child: Text(
                  // `cloture_rappel_hebergement`, au mot.
                  "L'hébergement n'est pas réglé : ${reservation.nuits} nuitée(s) × ${formaterFcfa(reservation.tarifNuit)} resteront dues sur la fiche du client.",
                  style: _petit.copyWith(color: PaletteMaitre.ambre800),
                ),
              ),
          ]),
          const SizedBox(height: AppSpacing.md),
          cadre([
            enTete(
              ModaleClotureSejour.blocConsommations,
              composition.consommations,
            ),
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
                  ModaleClotureSejour.totalFacture,
                  style: TextStyle(
                    fontFamily: AppTextStyles.police,
                    fontSize: Tailles.t13,
                    fontWeight: FontWeight.w600,
                    color: Ardoise.c600,
                  ),
                ),
                Text(
                  key: const Key('cloture-total-facture'),
                  formaterFcfa(totalFacture),
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
          child: const Text(ModaleClotureSejour.annuler),
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
          child: const Text(ModaleClotureSejour.facture),
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
  final payerSeparement = ValueNotifier<bool>(false);
  final confirme = await showDialog<bool>(
    context: context,
    barrierColor: AppColors.voileModale,
    builder: (_) => ModaleClotureSejour(
      reservation: reservation,
      panier: panier,
      payerSeparement: payerSeparement,
    ),
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
    if (context.mounted) {
      await facturerPanier(
        context,
        ref,
        cloture,
        payerSeparement: payerSeparement.value,
      );
    }
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
