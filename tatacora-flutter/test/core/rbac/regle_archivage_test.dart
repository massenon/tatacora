import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/rbac/regle_archivage.dart';
import 'package:tatacora_flutter/features/parametres/domain/options_systeme.dart';

/// La règle d'archivage et la lecture de la bascule, SEULES : les cas de bord que
/// la confrontation au serveur (`archivage_contre_serveur_test.dart`) ne joue
/// pas toujours — le libellé d'un rôle saisi avec une autre casse, une valeur de
/// bascule exotique.
void main() {
  GardeAcces droits(String niveau) => GardeAcces.depuisJson({'M7': niveau});

  bool peut({String niveau = 'C', String? role, bool bascule = false}) =>
      peutArchiver(
        droits: droits(niveau),
        module: ModuleTatacora.m7Achats,
        role: role,
        suppressionActive: bascule,
      );

  group('peutArchiver : le droit C d’abord, puis le rôle OU la bascule', () {
    test('les deux rôles d’administration archivent SANS la bascule', () {
      expect(peut(role: 'administrateur'), isTrue);
      expect(peut(role: 'super_admin'), isTrue);
    });

    test('tout autre rôle en C n’archive que bascule ouverte', () {
      for (final role in ['gerant', 'achats', 'magasinier', 'comptable']) {
        expect(peut(role: role), isFalse, reason: role);
        expect(peut(role: role, bascule: true), isTrue, reason: role);
      }
    });

    test('un rôle inconnu ou absent est un rôle ordinaire', () {
      expect(peut(role: null), isFalse);
      expect(peut(role: ''), isFalse);
      expect(peut(role: null, bascule: true), isTrue);
    });

    test('sans le droit C : jamais, ni administrateur ni bascule ouverte', () {
      for (final niveau in ['L', '-']) {
        expect(peut(niveau: niveau, role: 'administrateur'), isFalse);
        expect(
          peut(niveau: niveau, role: 'administrateur', bascule: true),
          isFalse,
        );
        expect(peut(niveau: niveau, role: 'achats', bascule: true), isFalse);
      }
    });

    test('le droit se lit sur LE module demandé, pas sur un autre', () {
      final autreModule = GardeAcces.depuisJson({'M7': '-', 'M6': 'C'});
      expect(
        peutArchiver(
          droits: autreModule,
          module: ModuleTatacora.m7Achats,
          role: 'administrateur',
          suppressionActive: true,
        ),
        isFalse,
      );
      expect(
        peutArchiver(
          droits: autreModule,
          module: ModuleTatacora.m6Stocks,
          role: 'administrateur',
          suppressionActive: false,
        ),
        isTrue,
      );
    });

    test('le libellé d’un rôle est normalisé : casse et espaces', () {
      expect(roleNormalise('Administrateur'), 'administrateur');
      expect(roleNormalise(' Super Admin '), 'super_admin');
      expect(roleNormalise(null), '');
      expect(peut(role: 'Super Admin'), isTrue);
      expect(peut(role: 'Administrateur'), isTrue);
      // Un rôle qui CONTIENT « admin » n'est pas un rôle d'administration.
      expect(peut(role: 'sous_administrateur'), isFalse);
      expect(peut(role: 'admin'), isFalse);
    });

    test('le registre des rôles d’administration est EXACTEMENT les deux', () {
      expect(rolesAdministration, {'administrateur', 'super_admin'});
    });
  });

  group('OptionsSysteme : la lecture d’une bascule (OptionsSystemeService)', () {
    test('une clé absente ou vide vaut son DÉFAUT du maître', () {
      expect(OptionsSysteme.suppressionActive(null), isFalse);
      expect(OptionsSysteme.suppressionActive(''), isFalse);
      expect(OptionsSysteme.suppressionActive('   '), isFalse);
      // Les alertes naissent OUVERTES : « absent = faux » les éteindrait.
      expect(
        OptionsSysteme.actif(OptionsSysteme.cleAlertesOuverture, null),
        isTrue,
      );
      expect(
        OptionsSysteme.actif(OptionsSysteme.cleAlertesOuverture, ''),
        isTrue,
      );
      expect(
        OptionsSysteme.actif(OptionsSysteme.cleAlertesOuverture, 'false'),
        isFalse,
      );
      expect(
        OptionsSysteme.actif(OptionsSysteme.cleReinitialisationSeeders, null),
        isFalse,
      );
    });

    test('une clé hors du registre est FAUSSE, jamais vraie', () {
      expect(OptionsSysteme.actif('inconnue', 'true'), isFalse);
      expect(OptionsSysteme.actif('inconnue', null), isFalse);
    });

    test(
      'filter_var(FILTER_VALIDATE_BOOLEAN) : quatre mots vrais, le reste faux',
      () {
        for (final vrai in [
          '1',
          'true',
          'TRUE',
          'True',
          'on',
          'ON',
          'yes',
          ' true ',
          ' 1 ',
        ]) {
          expect(
            OptionsSysteme.suppressionActive(vrai),
            isTrue,
            reason: '« $vrai »',
          );
        }
        for (final faux in [
          '0',
          'false',
          'FALSE',
          'off',
          'no',
          'oui',
          'non',
          '2',
          'garbage',
          'vrai',
        ]) {
          expect(
            OptionsSysteme.suppressionActive(faux),
            isFalse,
            reason: '« $faux »',
          );
        }
      },
    );

    test(
      'les défauts sont ceux du serveur : suppression fermée, alertes ouvertes',
      () {
        expect(OptionsSysteme.defauts, {
          'activation_suppression': false,
          'reinitialisation_seeders': false,
          'activation_alertes_ouverture': true,
        });
      },
    );
  });
}
