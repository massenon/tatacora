/// « Actualiser » l'écran courant — clic droit, F5 et Ctrl+R (demande du PO).
///
/// Le poste est offline-first : toute lecture vient de la base locale Drift.
/// Actualiser veut donc dire RELIRE LA BASE, jamais joindre un serveur.
///
/// ## Mécanisme (un seul endroit)
///
/// [ActualisationEcran.actualiser] fait deux choses :
///
/// 1. invalide les providers de LECTURE ([invaliderLesLectures]) : ils
///    relisent la base au prochain `watch` ;
/// 2. incrémente un compteur que [ZoneActualisation] utilise comme clé de
///    l'écran (`KeyedSubtree`) : l'écran est reconstruit.
///
/// ## Critère des providers invalidés
///
/// Tout `FutureProvider` / `StreamProvider` VIVANT dans le conteneur (famille et
/// `autoDispose` compris), sauf [lecturesConservees]. Ce sont les seuls
/// providers qui portent une lecture mise en cache ; ce critère couvre donc
/// aussi ceux qu'on ajoutera plus tard, sans liste à tenir à jour. Ne sont
/// JAMAIS touchés, par construction : la session, la base, le droit, le thème
/// (des `Provider` / `Notifier`, pas des lectures asynchrones), les filtres et
/// onglets (des `Notifier`), donc l'utilisateur reste connecté et garde ses
/// filtres.
///
/// Ce qui est EN BASE reste intact. Ce qui n'est qu'en mémoire dans un
/// formulaire de la page est perdu à la reconstruction ; une modale ouverte
/// n'est pas fermée, et le menu n'agit pas tant qu'elle est ouverte.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Seul accès au parcours des providers vivants (`getAllProviderElements`,
// extension non exportée par l'API publique) : épinglé par
// `actualisation_ecran_test.dart`, qui rougit si une montée de version le retire.
// ignore: depend_on_referenced_packages, implementation_imports, invalid_use_of_internal_member
import 'package:riverpod/src/internals.dart' show InternalProviderContainer;

import '../../features/auth/presentation/formulaire_premier_compte.dart'
    show aucunCompteProvider;
import '../../features/synchronisation/presentation/providers_synchronisation.dart'
    show liberationBauxSyncProvider;
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';

/// Le libellé du menu contextuel.
abstract final class LibellesActualisation {
  static const String actualiser = 'Actualiser';
}

/// Les lectures asynchrones qu'on ne relit PAS : l'une décide de l'écran de
/// démarrage (premier compte), l'autre est une tâche (libération des baux de
/// la file), pas une lecture d'écran.
final List<Object> lecturesConservees = <Object>[
  aucunCompteProvider,
  liberationBauxSyncProvider,
];

/// Invalide chaque `FutureProvider` / `StreamProvider` vivant du conteneur,
/// hors [lecturesConservees]. Rend le nombre de providers invalidés.
int invaliderLesLectures(
  ProviderContainer conteneur, {
  List<Object> conservees = const <Object>[],
}) {
  final aInvalider = [
    // ignore: invalid_use_of_internal_member
    for (final element in conteneur.getAllProviderElements())
      if ((element.provider is FutureProvider ||
              element.provider is StreamProvider) &&
          !lecturesConservees.contains(element.provider) &&
          !conservees.contains(element.provider))
        element.provider,
  ];
  for (final p in aInvalider) {
    conteneur.invalidate(p);
  }
  return aInvalider.length;
}

/// Le compteur d'actualisations : la clé de l'écran courant.
final actualisationEcranProvider = NotifierProvider<ActualisationEcran, int>(
  ActualisationEcran.new,
);

final class ActualisationEcran extends Notifier<int> {
  @override
  int build() => 0;

  /// Relit les lectures puis reconstruit l'écran.
  void actualiser() {
    invaliderLesLectures(ref.container);
    state = state + 1;
  }
}

/// Enveloppe l'écran courant : reconstruit sur le compteur, ouvre le menu
/// « Actualiser » au clic droit (hors champ de saisie), écoute F5 et Ctrl+R.
class ZoneActualisation extends ConsumerStatefulWidget {
  const ZoneActualisation({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<ZoneActualisation> createState() => _EtatZoneActualisation();
}

class _EtatZoneActualisation extends ConsumerState<ZoneActualisation> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_toucheAppuyee);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_toucheAppuyee);
    super.dispose();
  }

  /// Une modale (ou toute route au-dessus de la page) ouverte : le menu
  /// n'agit que sur la page.
  bool get _pageAuPremierPlan => ModalRoute.of(context)?.isCurrent ?? true;

  bool _toucheAppuyee(KeyEvent evenement) {
    if (evenement is! KeyDownEvent || !mounted || !_pageAuPremierPlan) {
      return false;
    }
    final touche = evenement.logicalKey;
    final raccourci =
        touche == LogicalKeyboardKey.f5 ||
        (touche == LogicalKeyboardKey.keyR &&
            HardwareKeyboard.instance.isControlPressed);
    if (!raccourci) return false;
    ref.read(actualisationEcranProvider.notifier).actualiser();
    return true;
  }

  /// Le clic est-il sur un champ de saisie ? Il garde alors son menu natif
  /// (copier / coller).
  bool _surChampDeSaisie(PointerDownEvent e) {
    final resultat = HitTestResult();
    WidgetsBinding.instance.hitTestInView(resultat, e.position, e.viewId);
    return resultat.path.any((h) => h.target is RenderEditable);
  }

  Future<void> _ouvrirMenu(PointerDownEvent e) async {
    final navigateur = Navigator.of(context);
    final recouvrement =
        navigateur.overlay!.context.findRenderObject()! as RenderBox;
    final choix = await showMenu<bool>(
      context: context,
      color: AppColors.neutre0,
      elevation: 0,
      menuPadding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: const BorderSide(color: AppColors.neutre100),
      ),
      position: RelativeRect.fromRect(
        e.position & Size.zero,
        Offset.zero & recouvrement.size,
      ),
      items: [
        PopupMenuItem<bool>(
          key: const Key('menu-actualiser'),
          value: true,
          child: Text(
            LibellesActualisation.actualiser,
            style: TextStyle(
              fontFamily: AppTextStyles.police,
              fontSize: Tailles.t13,
              color: AppColors.neutre700,
            ),
          ),
        ),
      ],
    );
    if (choix == true && mounted) {
      ref.read(actualisationEcranProvider.notifier).actualiser();
    }
  }

  @override
  Widget build(BuildContext context) {
    final compteur = ref.watch(actualisationEcranProvider);
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) {
        if (e.kind != PointerDeviceKind.mouse ||
            e.buttons != kSecondaryMouseButton ||
            !_pageAuPremierPlan ||
            _surChampDeSaisie(e)) {
          return;
        }
        _ouvrirMenu(e);
      },
      child: KeyedSubtree(key: ValueKey(compteur), child: widget.child),
    );
  }
}
