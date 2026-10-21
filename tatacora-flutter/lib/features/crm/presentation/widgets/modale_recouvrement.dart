// Vue Blade maîtresse (PA-183) : pwa/crm/clients-creances.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../caisse/domain/montant_caisse.dart' show formaterCentimesEnFcfa;
import '../../../caisse/presentation/widgets/modale_ouverture_caisse.dart'
    show BoutonActionCaisse, BoutonAnnulerCaisse, ChampMontantCaisse;
import '../../../comptabilite/domain/montant_comptable.dart'
    show chaineDepuisCentimes;
import '../../../comptabilite/domain/refus_comptable.dart';
import '../../../facturation/domain/entities/paiement_facture.dart';
import '../../../facturation/domain/messages_encaissement.dart';
import '../../../facturation/domain/regles_encaissement.dart';
import '../../../facturation/presentation/providers_paiements.dart';
import '../../../restaurant/presentation/widgets/coquille_modale_restaurant.dart';

/// Une facture impayée du client, telle que le sélecteur de la vue la propose :
/// `{id, libelle, reste}` de `ClientsCreances::facturesImpayeesDuClient`.
typedef FactureImpayee = ({String id, String libelle, int resteCentimes});

/// La modale **« Ajouter un recouvrement »** (`pwa/crm/clients-creances.blade.php`
/// l.632-684), posée dans le châssis partagé des modales.
///
/// ## Ce qu'elle rend, dans l'ordre de la vue
///
/// Le nom du client (rappel, non modifiable), « Pièce réglée » (le sélecteur des
/// factures impayées, chacune avec son reste dû), « Montant reçu (FCFA) »
/// (pré-rempli du reste dû de la pièce choisie, et re-rempli quand on en change :
/// `updatedRecouvrementFactureId`), « Mode » (les quatre modes du schéma),
/// l'avertissement, « Annuler » et « Enregistrer le recouvrement ».
///
/// ## Deux champs de la vue NE SONT PAS rendus, et c'est dit
///
/// La vue pose aussi « Référence » et « Commentaire ». L'invite du champ
/// « Référence », dite ici avec les mots de la vue :
/// « N° de transaction Mobile Money, n° de chèque… »
/// Le serveur les LIE à deux propriétés
/// (`recouvrementReference`, `recouvrementCommentaire`) que
/// `enregistrerRecouvrement` ne lit JAMAIS : `paiements` n'a aucune colonne pour
/// elles, et la colonne « Référence » du tableau des recouvrements affiche les
/// huit premiers caractères de l'identifiant du paiement. Rendre ces deux champs
/// ferait taper à l'opérateur une référence de transaction qui serait jetée en
/// silence — un champ dont la saisie disparaît est pire qu'un champ absent
/// (même raisonnement que la fiche de réservation, v7). Incohérence du SERVEUR
/// signalée à l'Architecte (D233), pas reproduite.
///
/// ## Le refus s'affiche SOUS le montant, la saisie reste
///
/// Comme `@error('recouvrementMontant')` (l.653) : au serveur TOUT refus du
/// service y est posé — sur-encaissement, caisse fermée, pièce comptable
/// refusée. Le masquer ferait croire à un encaissement qui n'a pas eu lieu
/// (PA-59/60/61).
class ModaleRecouvrement extends ConsumerStatefulWidget {
  const ModaleRecouvrement({
    required this.clientNom,
    required this.factures,
    super.key,
  });

  final String clientNom;

  /// Les factures impayées du client, de la plus ancienne à la plus récente
  /// (`orderBy('factures.date_emission')`). Jamais vide : l'appelant dit
  /// « Ce client n'a aucune créance en cours. » sinon.
  final List<FactureImpayee> factures;

  @override
  ConsumerState<ModaleRecouvrement> createState() => _EtatModaleRecouvrement();
}

class _EtatModaleRecouvrement extends ConsumerState<ModaleRecouvrement> {
  late String _pieceId;
  late final TextEditingController _montant;
  ModePaiementFacture _mode = ModePaiementFacture.especes;
  String? _refus;
  bool _envoi = false;

  @override
  void initState() {
    super.initState();
    // `$this->recouvrementFactureId = $factures[0]['id']`, le montant du reste
    // dû de cette première pièce, le mode « espèces » : l'état d'ouverture de la
    // vue (l.332-339 de `ClientsCreances`).
    _pieceId = widget.factures.first.id;
    _montant = TextEditingController(
      text: chaineDepuisCentimes(widget.factures.first.resteCentimes),
    );
  }

  @override
  void dispose() {
    _montant.dispose();
    super.dispose();
  }

  void _changerDePiece(String? id) {
    if (id == null) return;
    setState(() {
      _pieceId = id;
      // `updatedRecouvrementFactureId` : le montant suit le reste dû de la pièce.
      final facture = widget.factures.firstWhere((f) => f.id == id);
      _montant.text = chaineDepuisCentimes(facture.resteCentimes);
    });
  }

  Future<void> _enregistrer() async {
    setState(() {
      _refus = null;
      _envoi = true;
    });
    final navigateur = Navigator.of(context);
    final messages = ScaffoldMessenger.of(context);
    try {
      final succes = await recouvrerLaFacture(
        ref,
        pieceId: _pieceId,
        montantSaisi: _montant.text,
        modeSaisi: _mode.code,
        clientNom: widget.clientNom,
      );
      navigateur.pop();
      messages.showSnackBar(SnackBar(content: Text(succes)));
    } on RefusEncaissement catch (e) {
      if (mounted) setState(() => _refus = e.message);
    } on RefusComptable catch (e) {
      // `catch (RuntimeException $refus)` du serveur : la pièce refusée (exercice,
      // compte, journal…) est dite sous le montant, et RIEN n'est écrit.
      if (mounted) setState(() => _refus = e.message);
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  static const TextStyle _etiquette = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: Tailles.t13,
    fontWeight: FontWeight.w600,
    color: Ardoise.c700,
  );

  /// `block text-[13px] font-semibold text-slate-700 mb-1.5` + l'astérisque rouge.
  Widget _libelle(String texte) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
    child: Text.rich(
      TextSpan(
        style: _etiquette,
        children: [
          TextSpan(text: texte),
          const TextSpan(
            text: ' *',
            style: TextStyle(color: PaletteMaitre.rouge500),
          ),
        ],
      ),
    ),
  );

  InputDecoration _decoration() {
    final bordure = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      borderSide: const BorderSide(color: Ardoise.c300),
    );
    return InputDecoration(
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xsPlus,
      ),
      enabledBorder: bordure,
      border: bordure,
      focusedBorder: bordure.copyWith(
        borderSide: const BorderSide(color: AppColors.gold),
      ),
    );
  }

  static const TextStyle _valeur = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: Tailles.t13,
    color: AppColors.anthracite,
  );

  @override
  Widget build(BuildContext context) {
    return CoquilleModaleRestaurant(
      cle: const Key('modale-recouvrement'),
      titre: 'Ajouter un recouvrement',
      largeur: AppLayout.modaleRecouvrementCrm,
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // `bg-slate-50 border border-slate-200 rounded-lg p-3`.
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: Ardoise.c50,
              borderRadius: BorderRadius.circular(AppRadius.roundedLg),
              border: Border.all(color: Ardoise.c200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'CLIENT',
                  style: TextStyle(
                    fontFamily: AppTextStyles.police,
                    fontSize: Tailles.t11,
                    fontWeight: FontWeight.w600,
                    color: Ardoise.c400,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  widget.clientNom,
                  key: const Key('recouvrement-client'),
                  style: const TextStyle(
                    fontFamily: AppTextStyles.police,
                    fontSize: Tailles.t15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.navy,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _libelle('Pièce réglée'),
          DropdownButtonFormField<String>(
            key: const Key('recouvrement-piece'),
            initialValue: _pieceId,
            isDense: true,
            isExpanded: true,
            decoration: _decoration(),
            style: _valeur,
            items: [
              for (final f in widget.factures)
                DropdownMenuItem(
                  value: f.id,
                  // `{{ libelle }} — dû {{ MontantFcfa::format(reste) }}`.
                  child: Text(
                    '${f.libelle} — dû ${formaterCentimesEnFcfa(f.resteCentimes)}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: _envoi ? null : _changerDePiece,
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _libelle('Montant reçu (FCFA)'),
                    ChampMontantCaisse(
                      cle: const Key('recouvrement-montant'),
                      controleur: _montant,
                    ),
                    if (_refus != null)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.unit),
                        child: Text(
                          _refus!,
                          key: const Key('recouvrement-refus'),
                          style: const TextStyle(
                            fontFamily: AppTextStyles.police,
                            fontSize: Tailles.t12,
                            color: AppColors.erreur,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _libelle('Mode'),
                    DropdownButtonFormField<ModePaiementFacture>(
                      key: const Key('recouvrement-mode'),
                      initialValue: _mode,
                      isDense: true,
                      isExpanded: true,
                      decoration: _decoration(),
                      style: _valeur,
                      items: [
                        for (final m in ModePaiementFacture.values)
                          DropdownMenuItem(value: m, child: Text(m.libelle)),
                      ],
                      onChanged: _envoi
                          ? null
                          : (m) {
                              if (m != null) setState(() => _mode = m);
                            },
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          // `text-[11px] text-slate-500 bg-amber-50 border border-amber-200
          // rounded-lg p-2.5`.
          Container(
            padding: const EdgeInsets.all(AppSpacing.xsPlus),
            decoration: BoxDecoration(
              color: PaletteMaitre.ambre50,
              borderRadius: BorderRadius.circular(AppRadius.roundedLg),
              border: Border.all(color: PaletteMaitre.ambre200),
            ),
            child: const Text(
              MessagesEncaissement.avertissement,
              key: Key('recouvrement-avertissement'),
              style: TextStyle(
                fontFamily: AppTextStyles.police,
                fontSize: Tailles.t11,
                color: Ardoise.c500,
              ),
            ),
          ),
        ],
      ),
      actions: [
        BoutonAnnulerCaisse(
          onPressed: _envoi ? null : () => Navigator.of(context).pop(),
        ),
        BoutonActionCaisse(
          cle: const Key('recouvrement-enregistrer'),
          libelle: 'Enregistrer le recouvrement',
          onPressed: _envoi ? null : _enregistrer,
        ),
      ],
    );
  }
}
