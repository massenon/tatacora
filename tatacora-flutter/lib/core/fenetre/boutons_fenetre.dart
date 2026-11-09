import 'package:flutter/gestures.dart' show kPrimaryButton;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../navigation/trace_svg.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/mesures_fenetre.dart';
import 'controle_fenetre.dart';
import 'libelles_fenetre.dart';
import 'providers_fenetre.dart';

/// Les TROIS boutons de fenêtre — réduire, agrandir / restaurer, fermer — à
/// l'extrême droite de la barre supérieure, après le menu de compte (demande
/// du PO du 09/11/2026, capture « — ❐ ✕ »).
///
/// ÉCART À LA VUE, nommé : « poste Windows seulement ». La vue
/// (`partials/barre-superieure` l.112, le `<header>`, qui s'achève l.299 par le
/// menu de compte) n'a PAS ces boutons — c'est une page, le navigateur porte
/// les siens. Ils n'existent que si [controleFenetreProvider] fournit un
/// contrôle, c'est-à-dire sur Windows une fois la barre de titre native
/// masquée ; ailleurs, et dans tous les tests qui ne fournissent pas de
/// contrôle, la barre est exactement celle de la vue.
///
/// Même style que les autres boutons de la barre : tracés `IconeTrace`, blanc
/// atténué (`OpacitesCoquille.texteAttenue`), survol `bg-white/10` comme
/// `#bouton-menu-profil` ; seule la croix survole en rouge, comme Windows.
class BoutonsFenetre extends ConsumerWidget {
  const BoutonsFenetre({this.compacte = false, super.key});

  /// Fenêtre étroite : boutons de [MesuresFenetre.largeurBoutonCompact].
  final bool compacte;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controle = ref.watch(controleFenetreProvider);
    if (controle == null) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _BoutonFenetre(
          cle: const Key('bouton-fenetre-reduire'),
          libelle: LibellesFenetre.reduire,
          trace: TracesFenetre.reduire,
          onTap: controle.reduire,
          compact: compacte,
        ),
        ValueListenableBuilder<bool>(
          valueListenable: controle.agrandie,
          builder: (context, agrandie, _) => _BoutonFenetre(
            cle: const Key('bouton-fenetre-agrandir'),
            libelle: agrandie
                ? LibellesFenetre.restaurer
                : LibellesFenetre.agrandir,
            trace: agrandie ? TracesFenetre.restaurer : TracesFenetre.agrandir,
            onTap: controle.basculerAgrandissement,
            compact: compacte,
          ),
        ),
        _BoutonFenetre(
          cle: const Key('bouton-fenetre-fermer'),
          libelle: LibellesFenetre.fermer,
          trace: TracesFenetre.fermer,
          onTap: controle.fermer,
          compact: compacte,
          survol: AppColors.erreur,
        ),
      ],
    );
  }
}

class _BoutonFenetre extends StatelessWidget {
  const _BoutonFenetre({
    required this.cle,
    required this.libelle,
    required this.trace,
    required this.onTap,
    required this.compact,
    this.survol,
  });

  final Key cle;
  final String libelle;
  final String trace;
  final Future<void> Function() onTap;
  final bool compact;

  /// La couleur de survol ; `bg-white/10` à défaut.
  final Color? survol;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: libelle,
      excludeSemantics: true,
      onTap: () => onTap(),
      child: Tooltip(
        message: libelle,
        excludeFromSemantics: true,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: cle,
            onTap: () => onTap(),
            hoverColor:
                survol ??
                AppColors.neutre0.withValues(alpha: OpacitesCoquille.filet),
            child: SizedBox(
              width: compact
                  ? MesuresFenetre.largeurBoutonCompact
                  : MesuresFenetre.largeurBouton,
              height: AppLayout.hauteurBarreSuperieure,
              child: Center(
                child: IconeTrace(
                  trace: trace,
                  taille: MesuresFenetre.icone,
                  epaisseur: MesuresFenetre.epaisseurTrace,
                  couleur: AppColors.neutre0.withValues(
                    alpha: OpacitesCoquille.texteAttenue,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// La zone LIBRE de la barre supérieure, qui déplace la fenêtre : on la
/// saisit et on la glisse ; un double-clic agrandit ou restaure. Sans contrôle
/// de fenêtre, elle ne rend que son enfant.
///
/// Elle ne couvre que l'espace libre (identité, `flex-1`) : jamais la
/// recherche, ni un bouton, dont les gestes ne doivent pas déplacer la fenêtre.
class ZoneDeplacementFenetre extends ConsumerWidget {
  const ZoneDeplacementFenetre({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ControleFenetre? controle = ref.watch(controleFenetreProvider);
    if (controle == null) return child;
    return GestureDetector(
      key: const Key('zone-deplacement-fenetre'),
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => controle.deplacer(),
      onDoubleTap: () => controle.basculerAgrandissement(),
      child: child,
    );
  }
}

/// Les zones de saisie INVISIBLES du bord HAUT de la fenêtre et de ses deux
/// coins (haut-gauche, haut-droit) : sans barre de titre native, le haut n'a
/// plus de cadre à saisir (`WM_NCCALCSIZE` du plugin ne retire rien en haut).
/// Les bords gauche, droit et bas, avec leurs coins, gardent le cadre natif.
///
/// À poser en dernier dans la pile de la coquille, en haut de la fenêtre. Trois
/// zones de [MesuresFenetre.epaisseurBordRedimensionnement] px (les coins de
/// [MesuresFenetre.tailleCoinRedimensionnement] px) ; le curseur annonce le
/// redimensionnement, le contact commence le geste dans le système.
///
/// Le bord haut s'arrête à gauche des trois boutons de fenêtre : ils restent
/// cliquables jusqu'au pixel du haut ; seul l'angle de la croix (le coin
/// haut-droit) redimensionne. Rien n'est posé hors du poste Windows (aucun
/// contrôle), ni quand la fenêtre est agrandie (rien à redimensionner).
class ZonesRedimensionnementFenetre extends ConsumerWidget {
  const ZonesRedimensionnementFenetre({this.compacte = false, super.key});

  /// Barre compacte : les boutons de fenêtre sont plus étroits.
  final bool compacte;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controle = ref.watch(controleFenetreProvider);
    if (controle == null) return const SizedBox.shrink();
    return ValueListenableBuilder<bool>(
      valueListenable: controle.agrandie,
      builder: (context, agrandie, _) {
        if (agrandie) return const SizedBox.shrink();
        const epaisseur = MesuresFenetre.epaisseurBordRedimensionnement;
        const coin = MesuresFenetre.tailleCoinRedimensionnement;
        final boutons =
            3 *
            (compacte
                ? MesuresFenetre.largeurBoutonCompact
                : MesuresFenetre.largeurBouton);
        return Stack(
          children: [
            Positioned(
              top: 0,
              left: coin,
              right: boutons,
              height: epaisseur,
              child: _Zone(
                cle: const Key('zone-redimensionnement-haut'),
                bord: BordFenetre.haut,
                curseur: SystemMouseCursors.resizeUpDown,
                controle: controle,
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              width: coin,
              height: coin,
              child: _Zone(
                cle: const Key('zone-redimensionnement-haut-gauche'),
                bord: BordFenetre.hautGauche,
                curseur: SystemMouseCursors.resizeUpLeftDownRight,
                controle: controle,
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              width: coin,
              height: coin,
              child: _Zone(
                cle: const Key('zone-redimensionnement-haut-droit'),
                bord: BordFenetre.hautDroite,
                curseur: SystemMouseCursors.resizeUpRightDownLeft,
                controle: controle,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Zone extends StatelessWidget {
  const _Zone({
    required this.cle,
    required this.bord,
    required this.curseur,
    required this.controle,
  });

  final Key cle;
  final BordFenetre bord;
  final MouseCursor curseur;
  final ControleFenetre controle;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: curseur,
      opaque: true,
      child: Listener(
        key: cle,
        behavior: HitTestBehavior.opaque,
        // Dès l'appui, comme le cadre natif : le système prend le geste.
        onPointerDown: (e) {
          if (e.buttons == kPrimaryButton) controle.redimensionner(bord);
        },
        child: const SizedBox.expand(),
      ),
    );
  }
}
