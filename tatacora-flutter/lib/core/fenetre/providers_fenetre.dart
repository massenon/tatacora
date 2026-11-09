import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'controle_fenetre.dart';
import 'controle_fenetre_windows.dart';

/// Le contrôle de fenêtre du poste, ou `null` quand la barre supérieure n'a
/// pas à porter les boutons (autre plateforme que Windows, barre native
/// conservée, tests). C'est le SEUL interrupteur des boutons : un test fournit
/// une fausse réalisation par `controleFenetreProvider.overrideWithValue`.
final controleFenetreProvider = Provider<ControleFenetre?>(
  (ref) => ControleFenetreWindows.instance,
);
