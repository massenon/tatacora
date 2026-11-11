import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/rbac/regle_archivage.dart';
import 'package:tatacora_flutter/core/rbac/regles_roles.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/anciennes_pieces_saisies.dart';

/// 11/11/2026 (PO) : (1) les utilisateurs système ont TOUJOURS l'accès complet à Import & Export ;
/// (2) le gérant a les gestes réservés au comptable. Une règle, à un endroit, miroir du serveur.
void main() {
  List<String> constantePhp(String nom) {
    final source = File(
      '../tatacora-api/app/Models/User.php',
    ).readAsStringSync();
    final m = RegExp('const $nom = \\[([^\\]]*)\\];').firstMatch(source);
    expect(m, isNotNull, reason: '$nom absent de User.php');
    return RegExp(
      "'([^']+)'",
    ).allMatches(m!.group(1)!).map((e) => e.group(1)!).toList();
  }

  test('les listes sont celles du serveur (User.php)', () {
    expect(rolesAdministration, constantePhp('ROLES_ADMINISTRATION').toSet());
    expect(
      rolesSystemeImportExport,
      constantePhp('ROLES_SYSTEME_IMPORT_EXPORT').toSet(),
    );
    expect(
      modulesImplicitesSysteme,
      constantePhp('MODULES_IMPLICITES_SYSTEME').toSet(),
    );
    expect(
      rolesComptabiliteSensible,
      constantePhp('ROLES_COMPTABILITE_SENSIBLE').toSet(),
    );
  });

  test('rôles système d\'Import & Export : cinq rôles, les autres bornés', () {
    for (final r in [
      'super_admin',
      'administrateur',
      'comptable',
      'gerant',
      'barman',
      'Super Admin',
    ]) {
      expect(estRoleSystemeImportExport(r), isTrue, reason: r);
    }
    for (final r in [
      'receptionniste',
      'cuisine',
      'magasinier',
      'achats',
      'vehicules',
      'guide',
      'rh',
      '',
      null,
    ]) {
      expect(estRoleSystemeImportExport(r), isFalse, reason: '$r');
    }
  });

  test(
    'droit implicite : C sur Import & Export pour les rôles système, rien ailleurs',
    () {
      for (final r in rolesSystemeImportExport) {
        for (final d in <Map<String, dynamic>>[
          {},
          {'IMPORT_EXPORT': '-'},
          {'IMPORT_EXPORT': 'L'},
        ]) {
          final garde = GardeAcces.depuisJson(droitsAvecImplicites(d, r));
          expect(
            garde.peutEcrire(ModuleTatacora.importExport),
            isTrue,
            reason: r,
          );
          // Le reste suit le RBAC : aucun autre module n'est relevé.
          expect(garde.niveau(ModuleTatacora.m3Crm), NiveauAcces.aucun);
        }
      }
      for (final r in ['receptionniste', 'magasinier']) {
        final l = GardeAcces.depuisJson(
          droitsAvecImplicites({'IMPORT_EXPORT': 'L'}, r),
        );
        expect(l.niveau(ModuleTatacora.importExport), NiveauAcces.lecture);
        final c = GardeAcces.depuisJson(
          droitsAvecImplicites({'IMPORT_EXPORT': 'C'}, r),
        );
        expect(c.peutEcrire(ModuleTatacora.importExport), isTrue);
      }
    },
  );

  test('comptable ou gérant, jamais l\'administration ni un autre rôle', () {
    expect(estComptableOuGerant('comptable'), isTrue);
    expect(estComptableOuGerant('gerant'), isTrue);
    expect(estComptableOuGerant('Gerant'), isTrue);
    for (final r in ['administrateur', 'super_admin', 'barman', null]) {
      expect(estComptableOuGerant(r), isFalse, reason: '$r');
    }
    // L'envoi des anciennes pièces : administration + comptable + gérant.
    for (final r in ['administrateur', 'super_admin', 'comptable', 'gerant']) {
      expect(peutEnvoyerAnciennesPieces(r), isTrue, reason: r);
    }
    expect(peutEnvoyerAnciennesPieces('barman'), isFalse);
  });
}
