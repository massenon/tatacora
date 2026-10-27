// Vue Blade maîtresse (PA-183) : pwa/livewire/verrou-session.blade.php
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/navigation/trace_svg.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/mesures_verrou_session.dart';
import '../domain/verrou_session.dart';
import 'providers_verrou.dart';

/// Le VOILE DE VERROUILLAGE — le composant `VerrouSession` du web et sa vue
/// (`layouts/pwa` le monte UNE fois, pour tout écran).
///
/// ## Où il se pose
///
/// Au-dessus du `Navigator` ([MaterialApp.builder]) : il couvre donc aussi les
/// modales ouvertes, comme le `z-[9999]` de la vue. Rien n'est fermé en dessous
/// — un panier de comptoir, une saisie en cours restent intacts ; la couche du
/// dessous perd seulement le focus clavier ([ExcludeFocus]) et le pointeur (le
/// voile est opaque aux clics, `@click.stop`).
///
/// ## L'activité
///
/// Les six événements de la vue (`mousemove mousedown keydown scroll
/// touchstart wheel`) deviennent : survol, appui et déplacement du pointeur,
/// molette ([PointerSignalEvent]) et toute touche du clavier physique. Un seul
/// chemin les reçoit : [VerrouSessionNotifier.activite].
///
/// ## Ce que le voile rend, au mot de la vue
///
/// Titre, phrase du Product Owner, sous-message, champ « Mot de passe » (avec
/// son œil), bouton « Déverrouiller », message d'erreur sous le champ. Pas de
/// bouton de fermeture ni de déconnexion : la vue n'en pose pas, et Échap est
/// neutralisé (`@keydown.window.escape.prevent.stop`).
class VoileVerrouSession extends ConsumerStatefulWidget {
  const VoileVerrouSession({required this.child, super.key});

  /// L'application (le `Navigator`).
  final Widget child;

  @override
  ConsumerState<VoileVerrouSession> createState() => _EtatVoile();
}

class _EtatVoile extends ConsumerState<VoileVerrouSession> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_surTouche);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_surTouche);
    super.dispose();
  }

  /// `keydown` : jamais consommé (`false`), le clavier continue son chemin.
  bool _surTouche(KeyEvent evenement) {
    if (evenement is KeyDownEvent || evenement is KeyRepeatEvent) _signaler();
    return false;
  }

  void _signaler() => ref.read(verrouSessionProvider.notifier).activite();

  @override
  Widget build(BuildContext context) {
    final avecSession = ref.watch(sessionProvider) != null;
    final verrouille = ref.watch(
      verrouSessionProvider.select((e) => e.verrouille),
    );
    final voile = avecSession && verrouille;

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _signaler(),
      onPointerMove: (_) => _signaler(),
      onPointerHover: (_) => _signaler(),
      onPointerSignal: (_) => _signaler(),
      child: Stack(
        children: [
          Positioned.fill(
            child: ExcludeFocus(excluding: voile, child: widget.child),
          ),
          // Un `Overlay` à lui : le voile est AU-DESSUS du `Navigator`, donc hors
          // de son `Overlay`, et un champ de saisie ne peut pas ouvrir son menu
          // contextuel (ni une infobulle) sans en trouver un.
          if (voile)
            Positioned.fill(child: Overlay.wrap(child: const _ContenuVoile())),
        ],
      ),
    );
  }
}

class _ContenuVoile extends ConsumerStatefulWidget {
  const _ContenuVoile();

  @override
  ConsumerState<_ContenuVoile> createState() => _EtatContenuVoile();
}

class _EtatContenuVoile extends ConsumerState<_ContenuVoile> {
  final _motDePasse = TextEditingController();
  final _focus = FocusNode();
  bool _visible = false;

  @override
  void dispose() {
    _motDePasse.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// `wire:submit="deverrouiller"` : le champ est vidé après CHAQUE essai, échec
  /// compris (`$this->reset('motDePasse')`) — le mot de passe ne reste pas en
  /// mémoire plus longtemps que l'essai.
  Future<void> _soumettre() async {
    final saisi = _motDePasse.text;
    if (saisi.isEmpty) return; // `x-bind:required="verrouille"`.
    _motDePasse.clear();
    await ref.read(verrouSessionProvider.notifier).deverrouiller(saisi);
    if (mounted) _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final etat = ref.watch(verrouSessionProvider);

    return Shortcuts(
      // `@keydown.window.escape.prevent.stop` : Échap ne ferme rien.
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.escape):
            DoNothingAndStopPropagationIntent(),
      },
      child: Semantics(
        // `role="dialog" aria-modal="true" aria-labelledby`.
        scopesRoute: true,
        explicitChildNodes: true,
        namesRoute: true,
        label: TextesVerrou.titre,
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: MesuresVerrouSession.flou,
            sigmaY: MesuresVerrouSession.flou,
          ),
          child: GestureDetector(
            key: const Key('verrou-voile'),
            behavior: HitTestBehavior.opaque,
            // Le voile avale les clics : rien ne passe à la page dessous.
            onTap: () {},
            child: ColoredBox(
              color: MesuresVerrouSession.voile,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md), // p-4
                  child: _carte(etat),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _carte(EtatVerrou etat) {
    return ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: MesuresVerrouSession.largeurCarte,
      ),
      child: Material(
        key: const Key('verrou-carte'),
        color: AppColors.neutre0,
        borderRadius: BorderRadius.circular(AppRadius.rounded2xl),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.rounded2xl),
            boxShadow: AppShadows.tailwind2xl,
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg), // p-6
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _entete(),
                const SizedBox(height: AppSpacing.mdPlus), // mb-5
                _formulaire(etat),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _entete() {
    return Column(
      children: [
        Container(
          width: MesuresVerrouSession.disqueIcone,
          height: MesuresVerrouSession.disqueIcone,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: AppColors.fondClair,
            shape: BoxShape.circle,
          ),
          child: const IconeTrace(
            trace: MesuresVerrouSession.traceCadenas,
            taille: MesuresVerrouSession.cadenas,
            couleur: AppColors.navy,
          ),
        ),
        const SizedBox(height: AppSpacing.sm), // mb-3
        Text(
          TextesVerrou.titre,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: Tailles.t16,
            fontWeight: FontWeight.bold,
            color: AppColors.navy,
          ),
        ),
        const SizedBox(height: AppSpacing.unit), // mt-1
        Text(
          TextesVerrou.message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: Tailles.t13,
            fontWeight: FontWeight.w600,
            color: Ardoise.c700,
          ),
        ),
        const SizedBox(height: AppSpacing.unit),
        Text(
          TextesVerrou.sousMessage,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: Tailles.t12, color: Ardoise.c400),
        ),
      ],
    );
  }

  Widget _formulaire(EtatVerrou etat) {
    const bordure = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(AppRadius.roundedLg)),
      borderSide: BorderSide(color: Ardoise.c300),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: AppSpacing.xxs), // mb-1.5
          child: Text(
            TextesVerrou.motDePasse,
            style: TextStyle(
              fontSize: Tailles.t12,
              fontWeight: FontWeight.w600,
              color: Ardoise.c600,
            ),
          ),
        ),
        Stack(
          alignment: Alignment.centerRight,
          children: [
            TextField(
              key: const Key('verrou-mot-de-passe'),
              controller: _motDePasse,
              focusNode: _focus,
              autofocus: true,
              obscureText: !_visible,
              autofillHints: const [AutofillHints.password],
              enabled: !etat.enCours,
              onSubmitted: (_) => _soumettre(),
              style: const TextStyle(fontSize: Tailles.t14),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.fromLTRB(
                  AppSpacing.sm, // px-3
                  AppSpacing.xsPlus, // py-2.5
                  MesuresVerrouSession.retraitChamp, // pr-11
                  AppSpacing.xsPlus,
                ),
                enabledBorder: bordure,
                disabledBorder: bordure,
                focusedBorder: bordure.copyWith(
                  borderSide: const BorderSide(color: AppColors.gold),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm), // right-3
              child: Tooltip(
                message: _visible
                    ? TextesVerrou.masquerMotDePasse
                    : TextesVerrou.afficherMotDePasse,
                child: GestureDetector(
                  key: const Key('verrou-oeil'),
                  onTap: () => setState(() => _visible = !_visible),
                  child: IconeTrace(
                    trace: _visible
                        ? MesuresVerrouSession.traceOeilBarre
                        : MesuresVerrouSession.traceOeilOuvert,
                    taille: MesuresVerrouSession.oeil,
                    couleur: Ardoise.c400,
                  ),
                ),
              ),
            ),
          ],
        ),
        if (etat.erreur != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xxs), // mt-1.5
            child: Text(
              etat.erreur!,
              key: const Key('verrou-erreur'),
              style: const TextStyle(
                fontSize: Tailles.t12,
                color: PaletteMaitre.rouge600,
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.md), // mt-4
        FilledButton(
          key: const Key('verrou-deverrouiller'),
          // `wire:loading.attr="disabled"`.
          onPressed: etat.enCours ? null : _soumettre,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.navy,
            foregroundColor: AppColors.neutre0,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, // px-4
              vertical: AppSpacing.xsPlus, // py-2.5
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.roundedLg),
            ),
            textStyle: const TextStyle(
              fontSize: Tailles.t14,
              fontWeight: FontWeight.w600,
            ),
          ),
          child: const Text(TextesVerrou.deverrouiller),
        ),
      ],
    );
  }
}
