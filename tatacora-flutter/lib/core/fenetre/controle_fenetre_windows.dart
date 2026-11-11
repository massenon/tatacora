import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

import 'controle_fenetre.dart';

/// La réalisation WINDOWS du [ControleFenetre], par le plugin `window_manager`.
///
/// ## La barre de titre native est masquée
///
/// Avant le 09/11/2026 le runner créait la fenêtre sans `WS_SYSMENU`,
/// `WS_MINIMIZEBOX` ni `WS_MAXIMIZEBOX` (décision du PO du 24/08/2026 : ne pas
/// fermer l'application par mégarde) : une barre de titre SANS bouton, avec le
/// seul titre. Le PO demande désormais les trois boutons dans l'interface :
/// [preparer] masque la barre native (`TitleBarStyle.hidden`) et la barre
/// supérieure de la coquille porte les boutons et la zone de déplacement.
///
/// ## Jamais actif sans que la barre native soit masquée
///
/// [instance] reste `null` tant que [preparer] n'a pas réussi : sans plugin
/// (échec de chargement, plateforme autre que Windows), la barre native reste
/// et AUCUN bouton n'est dessiné en double.
final class ControleFenetreWindows
    with WindowListener
    implements ControleFenetre {
  ControleFenetreWindows._();

  static ControleFenetreWindows? _instance;

  /// Le contrôle prêt, ou `null` (voir plus haut).
  static ControleFenetreWindows? get instance => _instance;

  /// À appeler UNE fois, avant `runApp`. Ne lève jamais : un poste dont la
  /// fenêtre ne peut pas être préparée démarre quand même, avec sa barre native.
  static Future<ControleFenetreWindows?> preparer() async {
    if (!Platform.isWindows) return null;
    if (_instance != null) return _instance;
    try {
      await windowManager.ensureInitialized();
      final controle = ControleFenetreWindows._();
      controle._agrandie.value = await windowManager.isMaximized();
      windowManager.addListener(controle);
      // En dernier : si l'un des appels précédents lève, la barre native reste.
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
      _instance = controle;
    } on Object catch (erreur) {
      debugPrint('Fenêtre : barre de titre native conservée ($erreur)');
    }
    return _instance;
  }

  final ValueNotifier<bool> _agrandie = ValueNotifier<bool>(false);

  @override
  ValueListenable<bool> get agrandie => _agrandie;

  @override
  void onWindowMaximize() => _agrandie.value = true;

  @override
  void onWindowUnmaximize() => _agrandie.value = false;

  @override
  Future<void> reduire() => windowManager.minimize();

  @override
  Future<void> basculerAgrandissement() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  Future<void> fermer() => windowManager.close();

  @override
  Future<void> deplacer() => windowManager.startDragging();

  /// `window_manager` ne trace aucune zone de saisie : il envoie seulement
  /// `WM_NCLBUTTONDOWN` au bord demandé (`startResizing`). Les bords GAUCHE,
  /// DROIT et BAS, ainsi que leurs coins, restent redimensionnables par le
  /// cadre natif (`WS_THICKFRAME` ; `WM_NCCALCSIZE` du plugin retire 8 px à
  /// gauche, à droite et en bas de la zone client, JAMAIS en haut) : seuls le
  /// haut et ses deux coins n'ont plus de cadre, d'où ces trois bords.
  @override
  Future<void> redimensionner(BordFenetre bord) =>
      windowManager.startResizing(switch (bord) {
        BordFenetre.haut => ResizeEdge.top,
        BordFenetre.hautGauche => ResizeEdge.topLeft,
        BordFenetre.hautDroite => ResizeEdge.topRight,
      });
}
