import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';

/// RBAC premier niveau — masquage d'interface.
///
/// Ces tests vérifient le **confort**, pas la sécurité : le refus qui compte
/// est celui de l'API. Ce qu'ils garantissent, c'est qu'un droit ne s'obtient
/// jamais par omission — un code inconnu, absent ou mal orthographié doit
/// donner « aucun accès », jamais « accès complet ».
void main() {
  group('Niveaux', () {
    test('un code inconnu donne AUCUN accès, jamais un accès', () {
      expect(NiveauAcces.depuisCode('X'), NiveauAcces.aucun);
      expect(NiveauAcces.depuisCode(null), NiveauAcces.aucun);
      expect(NiveauAcces.depuisCode(''), NiveauAcces.aucun);
      // La casse compte : 'c' minuscule n'est pas 'C'.
      expect(NiveauAcces.depuisCode('c'), NiveauAcces.aucun);
    });

    test('lecture seule ne permet pas d’écrire', () {
      expect(NiveauAcces.lecture.peutLire, isTrue);
      expect(NiveauAcces.lecture.peutEcrire, isFalse);
    });

    test('accès complet permet les deux', () {
      expect(NiveauAcces.complet.peutLire, isTrue);
      expect(NiveauAcces.complet.peutEcrire, isTrue);
    });
  });

  group('Session déconnectée', () {
    const garde = GardeAcces.deconnecte();

    test('ne donne accès à rien', () {
      for (final m in ModuleTatacora.values) {
        expect(garde.peutLire(m), isFalse, reason: m.code);
        expect(garde.peutEcrire(m), isFalse, reason: m.code);
      }
    });

    test('ne rend aucun module visible', () {
      expect(garde.modulesVisibles, isEmpty);
      expect(garde.estVide, isTrue);
    });
  });

  group('Droits issus de la réponse de connexion', () {
    final magasinier = GardeAcces.depuisJson(const {
      'M6': 'C',
      'M7': 'C',
      'M4': 'L',
      'M5': 'L',
      'M14': 'L',
      'M13': '-',
    });

    test('les droits accordés sont respectés', () {
      expect(magasinier.peutEcrire(ModuleTatacora.m6Stocks), isTrue);
      expect(magasinier.peutLire(ModuleTatacora.m4Restaurant), isTrue);
      expect(magasinier.peutEcrire(ModuleTatacora.m4Restaurant), isFalse);
    });

    test('un module absent de la réponse est refusé', () {
      // M1 n'est pas cité : il ne doit surtout pas être accordé par défaut.
      expect(magasinier.peutLire(ModuleTatacora.m1Hebergement), isFalse);
    });

    test('un magasinier ne voit pas la paie', () {
      expect(magasinier.peutLire(ModuleTatacora.m13Rh), isFalse);
      expect(magasinier.modulesVisibles, isNot(contains(ModuleTatacora.m13Rh)));
    });

    test('les modules visibles suivent l’ordre de déclaration', () {
      expect(magasinier.modulesVisibles, [
        ModuleTatacora.m4Restaurant,
        ModuleTatacora.m5Bar,
        ModuleTatacora.m6Stocks,
        ModuleTatacora.m7Achats,
        ModuleTatacora.m14Etats,
      ]);
    });

    test('une valeur non textuelle est ignorée, pas convertie', () {
      // Une réponse serveur malformée ne doit pas ouvrir un accès.
      final douteux = GardeAcces.depuisJson(const {
        'M1': 1,
        'M2': true,
        'M3': 'C',
      });
      expect(douteux.peutLire(ModuleTatacora.m1Hebergement), isFalse);
      expect(douteux.peutLire(ModuleTatacora.m2Facturation), isFalse);
      expect(douteux.peutEcrire(ModuleTatacora.m3Crm), isTrue);
    });
  });
}
