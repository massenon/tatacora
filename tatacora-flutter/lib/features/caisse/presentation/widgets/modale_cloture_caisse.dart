// Vue Blade maîtresse (PA-183) : pwa/pos/comptant.blade.php
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/format/formats.dart' show formaterFcfa;
import '../../../../core/theme/app_colors.dart';
import '../../../comptabilite/domain/montant_comptable.dart'
    show chaineDepuisCentimes;
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../restaurant/presentation/widgets/coquille_modale_restaurant.dart';
import '../../domain/entities/session_caisse.dart';
import '../../domain/messages_caisse.dart';
import '../../domain/montant_caisse.dart';
import '../../domain/regles_caisse.dart';
import '../providers_caisse.dart';
import 'modale_ouverture_caisse.dart'
    show BoutonActionCaisse, BoutonAnnulerCaisse, ChampMontantCaisse;

/// La modale **« Clôturer la caisse bar »** (`pos/comptant.blade.php` l.660-700,
/// « maître `caisse-ui.js` l.130-150 »), posée dans le châssis partagé des
/// modales.
///
/// ## Le récapitulatif : fond, espèces, théorique
///
/// Le serveur écrit trois montants : le fond, les ESPÈCES encaissées de la
/// session, et le théorique (leur somme), puis pré-remplit le champ compté du
/// théorique (`caisse-ui.js` l.146, `value="${theorique}"`). Depuis le lot 5 le
/// poste a la source de ces espèces (`especesDeLaSessionProvider`, le panier
/// porte la session qui l'a encaissé) et fait de même.
///
/// ⚠ Piège de SÉQUENCE (n° 6) : les espèces se lisent en base, donc APRÈS le
/// premier rendu. Tant qu'elles ne sont pas là, « Espèces encaissées » et
/// « Théorique en caisse » valent « — » (jamais 0 : un zéro se lirait comme un
/// tiroir sans vente), et le champ compté reste vide. Il est pré-rempli à
/// l'arrivée des espèces, SEULEMENT s'il est encore vide — jamais par-dessus ce
/// que le caissier a déjà tapé.
///
/// ## Le refus s'affiche SOUS le champ, la saisie reste
///
/// Comme le `@error('montantConstateSaisi')` de la vue (l.697-699) : « Aucune
/// caisse n'est ouverte à ce point de vente… » si la session a été close entre
/// l'ouverture de la modale et le clic.
///
/// Ce fichier PORTE cette modale de la vue : il cite donc la vue en tête (PA-183).
class ModaleClotureCaisse extends ConsumerStatefulWidget {
  const ModaleClotureCaisse({required this.session, super.key});

  final SessionCaisse session;

  @override
  ConsumerState<ModaleClotureCaisse> createState() =>
      _EtatModaleClotureCaisse();
}

class _EtatModaleClotureCaisse extends ConsumerState<ModaleClotureCaisse> {
  final TextEditingController _constate = TextEditingController();
  String? _refus;
  bool _envoi = false;

  /// Les espèces de la session, en centimes ; `null` tant qu'elles se chargent.
  int? _especes;

  /// Les ventes en espèces de la période rattachées à AUCUNE session (réserve
  /// R2) ; `null` tant qu'elles se chargent, `nombre == 0` : rien à dire.
  ({int nombre, int montant})? _sansSession;

  @override
  void initState() {
    super.initState();
    unawaited(_chargerEspeces());
  }

  Future<void> _chargerEspeces() async {
    final especes = await ref.read(especesDeLaSessionProvider)(widget.session);
    final sansSession = await ref.read(ventesSansSessionProvider)(
      widget.session,
    );
    if (!mounted) return;
    setState(() {
      _especes = especes;
      _sansSession = sansSession;
      // Le champ compté naît du théorique, comme la vue — mais jamais par-dessus
      // une saisie déjà commencée.
      if (_constate.text.isEmpty) {
        _constate.text = chaineDepuisCentimes(
          theoriqueCentimes(
            fondCentimes: widget.session.fondCentimes,
            especesCentimes: especes,
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _constate.dispose();
    super.dispose();
  }

  Future<void> _cloturer() async {
    setState(() {
      _refus = null;
      _envoi = true;
    });
    final navigateur = Navigator.of(context);
    final messages = ScaffoldMessenger.of(context);
    try {
      final issue = await cloturerLaCaisse(ref, _constate.text);
      navigateur.pop();
      messages.showSnackBar(SnackBar(content: Text(issue)));
    } on RefusCaisse catch (e) {
      if (mounted) setState(() => _refus = e.message);
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  static const TextStyle _ligne = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: Tailles.t13,
  );

  // `flex justify-between` : le libellé cède la place au montant, jamais
  // l'inverse. Sans `Flexible`, un montant à sept chiffres fait déborder la
  // rangée de la modale (rencontré dès que le récapitulatif a porté de vraies
  // valeurs au lieu de tirets).
  Widget _recap(String etiquette, String valeur, {Key? cle}) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Flexible(
        child: Text(etiquette, style: _ligne.copyWith(color: Ardoise.c500)),
      ),
      const SizedBox(width: AppSpacing.xs),
      Text(
        valeur,
        key: cle,
        style: _ligne.copyWith(fontWeight: FontWeight.bold),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return CoquilleModaleRestaurant(
      cle: const Key('modale-cloture-caisse'),
      titre: MessagesCaisse.titreCloture(widget.session.point.code),
      sousTitre: MessagesCaisse.sousTitreCloture,
      largeur: LargeursPos.modaleCaisse,
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // `text-[13px] space-y-1.5`.
          _recap(
            MessagesCaisse.recapFond,
            formaterCentimesEnFcfa(widget.session.fondCentimes),
            cle: const Key('cloture-recap-fond'),
          ),
          const SizedBox(height: AppSpacing.xxs),
          _recap(
            MessagesCaisse.recapEspeces,
            _especes == null
                ? MessagesCaisse.tiret
                : formaterCentimesEnFcfa(_especes!),
            cle: const Key('cloture-recap-especes'),
          ),
          const SizedBox(height: AppSpacing.xxs),
          // `pt-1.5 border-t border-slate-100`.
          Container(
            padding: const EdgeInsets.only(top: AppSpacing.xxs),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Ardoise.c100)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    MessagesCaisse.recapTheorique,
                    style: _ligne.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  _especes == null
                      ? MessagesCaisse.tiret
                      : formaterCentimesEnFcfa(
                          theoriqueCentimes(
                            fondCentimes: widget.session.fondCentimes,
                            especesCentimes: _especes!,
                          ),
                        ),
                  key: const Key('cloture-recap-theorique'),
                  style: _ligne.copyWith(
                    fontSize: Tailles.t15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          // ⚠ Réserve R2 : des ventes en espèces que le théorique ne peut pas
          // compter. Le poste le DIT — un théorique présenté comme un fait
          // enverrait compter un tiroir « trop plein ».
          if ((_sansSession?.nombre ?? 0) > 0) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              key: const Key('cloture-avertissement-sans-session'),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xsPlus,
              ),
              decoration: BoxDecoration(
                color: AppColors.reserveGoldFond,
                border: Border.all(color: AppColors.bordureReserveGold),
                borderRadius: BorderRadius.circular(AppRadius.roundedLg),
              ),
              child: Text(
                MessagesCaisse.ventesSansSession(
                  _sansSession!.nombre,
                  formaterFcfa(_sansSession!.montant),
                ),
                style: _ligne.copyWith(
                  fontSize: Tailles.t12,
                  color: AppColors.gold,
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          // `block text-[11px] font-semibold text-slate-500 mb-1`.
          const Padding(
            padding: EdgeInsets.only(bottom: AppSpacing.unit),
            child: Text(
              MessagesCaisse.etiquetteConstate,
              style: TextStyle(
                fontFamily: AppTextStyles.police,
                fontSize: Tailles.t11,
                fontWeight: FontWeight.w600,
                color: Ardoise.c500,
              ),
            ),
          ),
          ChampMontantCaisse(
            cle: const Key('caisse-constate-saisi'),
            controleur: _constate,
          ),
          if (_refus != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                _refus!,
                key: const Key('caisse-refus'),
                style: const TextStyle(
                  fontFamily: AppTextStyles.police,
                  fontSize: Tailles.t12,
                  color: PaletteMaitre.rouge600,
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.xs),
          // `text-[11.5px] text-slate-400 mt-2`.
          const Text(MessagesCaisse.aideRecap, style: TextesModaleCaisse.aide),
        ],
      ),
      actions: [
        BoutonAnnulerCaisse(
          onPressed: _envoi ? null : () => Navigator.of(context).pop(),
        ),
        BoutonActionCaisse(
          cle: const Key('caisse-cloturer-confirmer'),
          libelle: MessagesCaisse.cloturerLaCaisse,
          onPressed: _envoi ? null : _cloturer,
        ),
      ],
    );
  }
}

/// Le style des aides des modales de caisse — `text-[11.5px] text-slate-400`,
/// arrondi à 12 px : l'échelle déclarée ne porte pas de palier 11,5 (écart nommé).
abstract final class TextesModaleCaisse {
  static const TextStyle aide = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: Tailles.t12,
    color: Ardoise.c400,
  );
}
