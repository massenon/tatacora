/// La CLOCHE de la barre supérieure et son panneau — composant
/// `transverse/cloche-notifications` de la vue (chemin sans préfixe, PA-187),
/// porté le 14/10/2026 (lot B du plan du PO).
///
/// Transcription de la vue :
///
/// * le bouton `relative text-white/70 hover:text-white p-2`, tracé 20 px — il
///   occupe 36 px entre « Vente » et le menu de compte (le décalage de ~35 px
///   relevé au châssis depuis le lot 1) ;
/// * le badge des non-lues `absolute top-1 right-1 min-w-[14px] h-3.5 px-1
///   bg-erreur rounded-full text-[8px] font-bold`, MASQUÉ à zéro ;
/// * le panneau `absolute right-0 top-12 w-80 bg-white rounded-xl shadow-2xl
///   border border-slate-100` : en-tête (« Notifications », « Tout marquer
///   comme lu »), les deux filtres, la liste `max-h-80`, le lien de pied vers
///   le Journal d'Audit sous la garde M14.
///
/// Contenu RÉEL : les alertes dérivées (`alertes_ouverture.dart`), relues au
/// montage, à chaque changement de route — la vue rend la cloche à chaque page
/// — et à chaque ouverture du panneau. Aucun bouton muet : une alerte mène à
/// l'écran du module ; le lien de pied, dont l'écran n'existe pas sur ce
/// poste, le DIT au clic.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/providers.dart';
import '../../../core/navigation/acces_rapide.dart';
import '../../../core/navigation/coquille_vue.dart';
import '../../../core/navigation/trace_svg.dart';
import '../../../core/rbac/garde_acces.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../domain/alertes_ouverture.dart';
import 'providers_alertes.dart';

class ClocheNotifications extends ConsumerStatefulWidget {
  const ClocheNotifications({required this.routeActive, super.key});

  /// La route affichée — la cloche se relit quand elle change.
  final String routeActive;

  @override
  ConsumerState<ClocheNotifications> createState() => _EtatCloche();
}

class _EtatCloche extends ConsumerState<ClocheNotifications> {
  final _portail = OverlayPortalController();
  final _lien = LayerLink();
  final _groupe = Object();
  bool _survol = false;

  /// Le filtre de la vue : `toutes` | `non-lues`.
  bool _nonLues = false;

  /// Relecture APRÈS l'image en cours : invalider pendant la construction
  /// marquerait à reconstruire un widget déjà construit (même raison que
  /// l'indicateur de caisse, D316).
  void _relire() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.invalidate(alertesClocheProvider);
    });
  }

  @override
  void initState() {
    super.initState();
    _relire();
  }

  @override
  void didUpdateWidget(covariant ClocheNotifications ancien) {
    super.didUpdateWidget(ancien);
    if (ancien.routeActive != widget.routeActive) {
      // Une nouvelle page referme le panneau (la vue le rend fermé) — après
      // l'image, comme la relecture.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fermer();
      });
      _relire();
    }
  }

  void _fermer() {
    if (_portail.isShowing) _portail.hide();
  }

  void _basculer() {
    if (_portail.isShowing) {
      _portail.hide();
    } else {
      ref.invalidate(alertesClocheProvider);
      _portail.show();
    }
    setState(() {});
  }

  void _dire(String message) {
    ScaffoldMessenger.maybeOf(context)
      ?..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Le clic sur une alerte : marquée vue PUIS l'écran du module — deux
  /// gestes, comme la vue (`wire:click="marquerLu"` + `wire:navigate`).
  Future<void> _ouvrirAlerte(
    AlerteOuverture alerte,
    List<AlerteOuverture> derivees,
  ) async {
    final route = routesFlutterParRoutePwa[alerte.routePwa];
    await marquerAlerteVue(ref, alerte, derivees);
    if (!mounted) return;
    _fermer();
    if (route == null) {
      _dire(LibellesCoquille.ecranNonPorte(alerte.titre));
      return;
    }
    GoRouter.of(context).go(route);
  }

  @override
  Widget build(BuildContext context) {
    final lu = ref.watch(alertesClocheProvider);
    // Le badge ne s'affiche que sur une lecture RÉUSSIE : pendant la lecture
    // ou après un échec, aucun nombre n'est affirmé.
    final alertes = lu.hasValue && !lu.hasError ? lu.value : null;
    final nonLues = alertes?.where((a) => !a.vue).length ?? 0;

    final bouton = MouseRegion(
      onEnter: (_) => setState(() => _survol = true),
      onExit: (_) => setState(() => _survol = false),
      // `aria-label` de la vue : une étiquette d'accessibilité, pas une
      // infobulle visible.
      child: Semantics(
        label: LibellesCloche.notifications,
        button: true,
        child: InkWell(
          key: const Key('bouton-cloche-notifications'),
          onTap: _basculer,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.xs), // p-2
                child: IconeTrace(
                  trace: TracesCoquille.cloche,
                  taille: MesuresBarreSuperieure.iconeCloche,
                  // `text-white/70 hover:text-white`.
                  couleur: AppColors.neutre0.withValues(
                    alpha: _survol ? 1 : OpacitesBarreSuperieure.cloche,
                  ),
                ),
              ),
              // `#badge-notifications-non-lues` : masqué à zéro, comme la vue.
              if (nonLues > 0)
                Positioned(
                  top: MesuresBarreSuperieure.decalageBadgeCloche,
                  right: MesuresBarreSuperieure.decalageBadgeCloche,
                  child: Container(
                    key: const Key('badge-notifications-non-lues'),
                    constraints: const BoxConstraints(
                      minWidth: MesuresBarreSuperieure.badgeCloche,
                    ),
                    height: MesuresBarreSuperieure.badgeCloche,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.unit, // px-1
                    ),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.erreur,
                      borderRadius: BorderRadius.circular(
                        AppRadius.roundedFull,
                      ),
                    ),
                    child: Text(
                      '$nonLues',
                      style: TextStyle(
                        color: AppColors.neutre0,
                        fontFamily: AppTextStyles.police,
                        fontSize: Tailles.t8,
                        height: Tailles.interligneAucun,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    return TapRegion(
      groupId: _groupe,
      onTapOutside: (_) {
        if (_portail.isShowing) setState(_fermer);
      },
      child: CompositedTransformTarget(
        link: _lien,
        child: OverlayPortal(
          controller: _portail,
          overlayChildBuilder: (context) => _panneau(context),
          child: bouton,
        ),
      ),
    );
  }

  Widget _panneau(BuildContext context) {
    return Positioned(
      left: 0,
      top: 0,
      child: CompositedTransformFollower(
        link: _lien,
        showWhenUnlinked: false,
        // `absolute right-0 top-12` : le bord DROIT du panneau sur celui du
        // bouton, 48 px sous son haut.
        targetAnchor: Alignment.topRight,
        followerAnchor: Alignment.topRight,
        offset: const Offset(0, MesuresBarreSuperieure.decalagePanneauCloche),
        child: TapRegion(
          groupId: _groupe,
          child: SizedBox(
            width: MesuresBarreSuperieure.panneauCloche,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.neutre0,
                borderRadius: BorderRadius.circular(AppRadius.roundedXl),
                border: Border.all(color: AppColors.neutre100),
                boxShadow: AppShadows.tailwind2xl,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.roundedXl),
                child: Material(
                  type: MaterialType.transparency,
                  child: Consumer(builder: (context, ref, _) => _contenu(ref)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _contenu(WidgetRef ref) {
    final lu = ref.watch(alertesClocheProvider);
    final droits = ref.watch(droitsProvider);
    final derivees = lu.hasValue && !lu.hasError ? lu.value! : null;
    final affichees = derivees == null
        ? null
        : _nonLues
        ? [
            for (final a in derivees)
              if (!a.vue) a,
          ]
        : derivees;

    final petit = TextStyle(
      fontFamily: AppTextStyles.police,
      fontSize: Tailles.t11,
      height: AppLayout.interligneContenu,
      fontWeight: FontWeight.w600,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // `flex items-center justify-between px-4 py-3 border-b
        // border-slate-100`.
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.neutre100)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  LibellesCloche.notifications,
                  style: TextStyle(
                    fontFamily: AppTextStyles.police,
                    fontSize: Tailles.t14,
                    height: Tailles.interligneSmHorsMain,
                    fontWeight: FontWeight.bold,
                    color: AppColors.neutre700,
                  ),
                ),
              ),
              // Rendu EN PERMANENCE, comme la vue : à zéro non-lue, le clic
              // ne marque rien (un non-geste, pas un contrôle inerte).
              InkWell(
                key: const Key('cloche-tout-marquer-lu'),
                onTap: derivees == null
                    ? null
                    : () => marquerToutesLesAlertesVues(ref, derivees),
                child: Text(
                  LibellesCloche.toutMarquerLu,
                  style: petit.copyWith(color: AppColors.gold),
                ),
              ),
            ],
          ),
        ),
        // Les deux filtres : `flex gap-1 px-3 pt-2.5`.
        Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.sm,
            right: AppSpacing.sm,
            top: AppSpacing.xsPlus,
          ),
          child: Row(
            children: [
              _Filtre(
                cle: 'toutes',
                texte: LibellesCloche.filtreToutes,
                actif: !_nonLues,
                onTap: () => setState(() => _nonLues = false),
              ),
              const SizedBox(width: AppSpacing.unit), // gap-1
              _Filtre(
                cle: 'non-lues',
                texte: LibellesCloche.filtreNonLues,
                actif: _nonLues,
                onTap: () => setState(() => _nonLues = true),
              ),
            ],
          ),
        ),
        // `#liste-notifications` : `max-h-80 overflow-y-auto py-2`.
        ConstrainedBox(
          constraints: const BoxConstraints(
            maxHeight: MesuresBarreSuperieure.hauteurMaxListeCloche,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (lu.hasError)
                  _Vide(LibellesCloche.lectureImpossible)
                else if (affichees == null)
                  // Pendant la lecture, rien n'est affirmé.
                  const SizedBox.shrink()
                else if (affichees.isEmpty)
                  // État vide de la vue, décliné par filtre.
                  _Vide(
                    _nonLues
                        ? LibellesCloche.aucuneNonLue
                        : LibellesCloche.aucuneNotification,
                  )
                else
                  for (final a in affichees)
                    _LigneAlerte(
                      alerte: a,
                      onTap: () => _ouvrirAlerte(a, derivees!),
                    ),
              ],
            ),
          ),
        ),
        // (La ligne « Sur ce poste : les arrivées du jour sans check-in ne
        // sont pas signalées » est RETIRÉE le 14/10/2026, lot C : la famille
        // est dérivée, comme dans la vue.)
        // Le pied : `@if ($liensChassis['journal_audit']['url'] !== null)`,
        // garde M14. `px-4 py-2.5 border-t border-slate-100 text-center`.
        if (droits.peutLire(ModuleTatacora.m14Etats))
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xsPlus,
            ),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.neutre100)),
            ),
            alignment: Alignment.center,
            child: InkWell(
              key: const Key('cloche-voir-notifications'),
              // `$liensChassis['journal_audit']['url']` : le Journal d'Audit,
              // écran porté depuis le 14/10/2026 (lot D, D424).
              onTap: () {
                _fermer();
                setState(() {});
                GoRouter.of(context).go('/journal-audit');
              },
              child: Text(
                LibellesCloche.voirNotifications,
                style: petit.copyWith(color: AppColors.navy),
              ),
            ),
          ),
      ],
    );
  }
}

/// Un filtre : `px-3 py-1.5 rounded-md text-[11px] font-semibold`, actif
/// `bg-navy text-white`, sinon `text-slate-500`.
class _Filtre extends StatelessWidget {
  const _Filtre({
    required this.cle,
    required this.texte,
    required this.actif,
    required this.onTap,
  });

  final String cle;
  final String texte;
  final bool actif;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: actif ? AppColors.navy : Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.roundedMd),
      child: InkWell(
        key: Key('cloche-filtre-$cle'),
        borderRadius: BorderRadius.circular(AppRadius.roundedMd),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xxs,
          ),
          child: Text(
            texte,
            style: TextStyle(
              fontFamily: AppTextStyles.police,
              fontSize: Tailles.t11,
              height: AppLayout.interligneContenu,
              fontWeight: FontWeight.w600,
              color: actif ? AppColors.neutre0 : AppColors.neutre500,
            ),
          ),
        ),
      ),
    );
  }
}

/// `text-center text-xs text-slate-400 py-8`.
class _Vide extends StatelessWidget {
  const _Vide(this.texte);

  final String texte;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Text(
        texte,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: AppTextStyles.police,
          fontSize: Tailles.t12,
          height: Tailles.interligneXsHorsMain,
          color: AppColors.neutre400,
        ),
      ),
    );
  }
}

/// Une alerte : `flex items-start gap-2.5 px-4 py-2.5 hover:bg-slate-50`,
/// `bg-amber-50/40` tant qu'elle n'est pas vue ; la pastille dorée `w-1.5
/// h-1.5 rounded-full mt-1.5` (transparente une fois vue) ; le titre `text-xs
/// font-semibold text-slate-700 truncate`, le détail `text-[11px]
/// text-slate-500 leading-snug`.
class _LigneAlerte extends StatelessWidget {
  const _LigneAlerte({required this.alerte, required this.onTap});

  final AlerteOuverture alerte;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: alerte.vue
          ? Colors.transparent
          : PaletteMaitre.ambre50.withValues(
              alpha: OpacitesBarreSuperieure.fondNonLue,
            ),
      child: InkWell(
        key: Key('alerte-${alerte.cle}'),
        hoverColor: AppColors.neutre50,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xsPlus,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(
                  top: MesuresBarreSuperieure.margeHautPastilleNonLue,
                ),
                child: Container(
                  width: MesuresBarreSuperieure.pastilleNonLue,
                  height: MesuresBarreSuperieure.pastilleNonLue,
                  decoration: BoxDecoration(
                    color: alerte.vue ? Colors.transparent : AppColors.gold,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xsPlus), // gap-2.5
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      alerte.titre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppTextStyles.police,
                        fontSize: Tailles.t12,
                        height: Tailles.interligneXsHorsMain,
                        fontWeight: FontWeight.w600,
                        color: AppColors.neutre700,
                      ),
                    ),
                    Text(
                      alerte.detail,
                      style: TextStyle(
                        fontFamily: AppTextStyles.police,
                        fontSize: Tailles.t11,
                        height: Tailles.interligneSnug,
                        color: AppColors.neutre500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
