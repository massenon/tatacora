import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/navigation/coquille_vue.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/router/coquille_application.dart';

import '../../support/coquille_montee.dart';

/// Le bandeau « Accès lecture seule » de la coquille (`partials/banniere`,
/// `BanniereEcriture::pour`) : rendu quand le profil n'a pas le niveau `C` sur
/// le module de l'écran, rien sinon.
void main() {
  const complet = {
    'M1': 'C', 'M2': 'C', 'M3': 'C', 'M4': 'C', 'M5': 'C', 'M6': 'C', //
    'M7': 'C', 'M8': 'C', 'M9': 'C', 'M10': 'C', 'M11': 'C', 'M12': 'C',
    'M13': 'C', 'M14': 'C', 'ROLES': 'C', 'PARAM': 'C',
  };

  testWidgets(
    'un profil en lecture sur le module voit le bandeau et son bouton',
    (tester) async {
      await monterCoquille(
        tester,
        role: 'receptionniste',
        droits: {...complet, 'M6': 'L'},
        routeActive: '/stocks',
      );
      expect(find.byKey(const Key('shell-banniere')), findsOneWidget);
      expect(
        find.textContaining(
          LibellesCoquille.banniereLectureTitre,
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          LibellesCoquille.banniereLectureDetail,
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(find.text(LibellesCoquille.banniereChangerProfil), findsOneWidget);
    },
  );

  testWidgets('un profil à accès complet ne voit aucun bandeau', (
    tester,
  ) async {
    await monterCoquille(
      tester,
      role: 'administrateur',
      droits: complet,
      routeActive: '/stocks',
    );
    expect(find.byKey(const Key('shell-banniere')), findsNothing);
  });

  testWidgets('un écran de consultation pure n\'affiche jamais le bandeau', (
    tester,
  ) async {
    await monterCoquille(
      tester,
      role: 'barman',
      droits: {...complet, 'M14': 'L'},
      routeActive: '/journal-audit',
    );
    expect(find.byKey(const Key('shell-banniere')), findsNothing);
  });

  test('le module d\'une route vient du registre du menu', () {
    expect(moduleDeLaRoute('/stocks'), ModuleTatacora.m6Stocks);
    expect(moduleDeLaRoute('/stocks/inventaires'), ModuleTatacora.m6Stocks);
    expect(moduleDeLaRoute('/inconnue'), isNull);
  });
}
