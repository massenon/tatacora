import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/parametres/domain/regles_parametres.dart';
import 'package:tatacora_flutter/features/parametres/domain/registre_parametres_local.dart';

/// Les règles PURES des paramètres : forme d'une valeur, cohérence de l'état
/// résultant, états dérivés. Tout est testé à valeur et message EXACTS.
void main() {
  SpecParametre spec(String cle) => RegistreParametresLocal.parCle(cle)!;

  String valeur(Normalisation n) => switch (n) {
    ValeurNormalisee(:final valeur) => valeur ?? '<vidé>',
    ValeurRefusee(:final motif) => 'REFUS: $motif',
  };

  group('normaliser — la forme stockée, une seule par type', () {
    test('un booléen devient « true » / « false », sous toutes ses formes', () {
      final s = spec('tva_active');
      expect(valeur(normaliser(s, true)), 'true');
      expect(valeur(normaliser(s, 'true')), 'true');
      expect(valeur(normaliser(s, '1')), 'true');
      expect(valeur(normaliser(s, false)), 'false');
      expect(valeur(normaliser(s, 'false')), 'false');
      expect(valeur(normaliser(s, '0')), 'false');
    });

    test('un booléen ne se vide pas, et ne se devine pas', () {
      final s = spec('tva_active');
      const attendu =
          'REFUS: « Assujettissement à la TVA » est un interrupteur : '
          'choisissez Oui ou Non, il ne se vide pas.';
      expect(valeur(normaliser(s, null)), attendu);
      expect(valeur(normaliser(s, '')), attendu);
      expect(valeur(normaliser(s, 'peut-être')), attendu);
    });

    test('un décimal : virgule française ramenée au point, borne incluse', () {
      final s = spec('taux_tva');
      expect(valeur(normaliser(s, '18')), '18');
      expect(valeur(normaliser(s, ' 3,6 ')), '3.6');
      expect(valeur(normaliser(s, '0')), '0');
      expect(valeur(normaliser(s, '100')), '100');
    });

    test(
      'un décimal hors de ses bornes ou illisible est refusé, message exact',
      () {
        final s = spec('taux_tva');
        expect(
          valeur(normaliser(s, '100,01')),
          'REFUS: « Taux de TVA (%) » doit être compris entre 0 et 100.',
        );
        expect(
          valeur(normaliser(s, '-1')),
          'REFUS: « Taux de TVA (%) » doit être un nombre décimal positif '
          '(exemple : 18 ou 3,6).',
        );
        expect(
          valeur(normaliser(s, 'dix-huit')),
          'REFUS: « Taux de TVA (%) » doit être un nombre décimal positif '
          '(exemple : 18 ou 3,6).',
        );
      },
    );

    test('les bornes du taux de risques professionnels sont celles du serveur '
        '(1 à 4), comparées sans flottant', () {
      final s = spec('taux_cnss_risques_professionnels');
      expect(valeur(normaliser(s, '1')), '1');
      expect(valeur(normaliser(s, '4')), '4');
      expect(valeur(normaliser(s, '2,5')), '2.5');
      const refus =
          'REFUS: « CNSS risques professionnels (%) » doit être compris '
          'entre 1 et 4.';
      expect(valeur(normaliser(s, '0,99')), refus);
      // Le cas où un flottant se tromperait : 4.0000000000000001 lu en IEEE 754
      // vaut exactement 4.0 et passerait la borne.
      expect(valeur(normaliser(s, '4,0000000000000001')), refus);
      expect(valeur(normaliser(s, '5')), refus);
    });

    test('un entier : chiffres seuls, borne incluse', () {
      final s = spec('delai_preavis_conge_jours');
      expect(valeur(normaliser(s, '365')), '365');
      expect(valeur(normaliser(s, '0')), '0');
      expect(
        valeur(normaliser(s, '366')),
        'REFUS: « Préavis de congé (jours) » doit être compris entre 0 et 365.',
      );
      expect(
        valeur(normaliser(s, '3,5')),
        'REFUS: « Préavis de congé (jours) » doit être un nombre entier, sans '
        'signe ni décimale.',
      );
      expect(
        valeur(normaliser(spec('email_smtp_port'), '0')),
        'REFUS: « Port » doit être compris entre 1 et 65535.',
      );
    });

    test('un choix hors registre est refusé, un choix admis est mis en '
        'minuscules', () {
      final s = spec('convention_prix');
      expect(valeur(normaliser(s, 'TTC')), 'ttc');
      expect(
        valeur(normaliser(s, 'xyz')),
        'REFUS: « Convention des prix du catalogue » : la valeur « xyz » '
        'n’est pas admise.',
      );
    });

    test('un téléphone : la regex du serveur, à l’identique', () {
      final s = spec('entreprise_telephone');
      expect(
        valeur(normaliser(s, '+229 01 97 35 59 74')),
        '+229 01 97 35 59 74',
      );
      expect(
        valeur(normaliser(s, 'appelez-moi')),
        'REFUS: « Téléphone principal » n’est pas un numéro valide : '
        'chiffres, espaces et indicatif uniquement.',
      );
      expect(
        valeur(normaliser(s, '12345')),
        'REFUS: « Téléphone principal » n’est pas un numéro valide : '
        'chiffres, espaces et indicatif uniquement.',
      );
    });

    test('un courriel, et la longueur maximale d’un texte', () {
      expect(
        valeur(normaliser(spec('entreprise_email'), 'pas-une-adresse')),
        'REFUS: « Email de contact » n’est pas une adresse électronique '
        'valide.',
      );
      expect(
        valeur(normaliser(spec('entreprise_email'), 'gite@exemple.bj')),
        'gite@exemple.bj',
      );
      expect(valeur(normaliser(spec('entreprise_ifu'), 'A' * 30)), 'A' * 30);
      expect(
        valeur(normaliser(spec('entreprise_ifu'), 'A' * 31)),
        'REFUS: « IFU (Identifiant Fiscal Unique) » ne peut pas dépasser 30 '
        'caractères.',
      );
    });

    test('vider : « non renseigné », jamais une chaîne vide ni un défaut', () {
      expect(valeur(normaliser(spec('entreprise_ifu'), null)), '<vidé>');
      expect(valeur(normaliser(spec('entreprise_ifu'), '   ')), '<vidé>');
      expect(valeur(normaliser(spec('taux_tva'), '')), '<vidé>');
    });

    test(
      'quatre taux confirmés de la paie ne se vident pas, le cinquième si',
      () {
        for (final cle in [
          'taux_cnss_salarie',
          'taux_cnss_pension_employeur',
          'taux_cnss_prestations_familiales',
          'taux_vps',
        ]) {
          expect(
            valeur(normaliser(spec(cle), '')),
            'REFUS: $raisonTauxConfirmeNonVidable',
            reason: cle,
          );
        }
        expect(
          valeur(normaliser(spec('taux_cnss_risques_professionnels'), '')),
          '<vidé>',
        );
      },
    );
  });

  group('cohérence de l’état RÉSULTANT — les deux sens (PA-62, PA-124)', () {
    test('activer la TVA sans taux est refusé', () {
      final resultat = etatResultant({}, {'tva_active': 'true'});
      expect(verifierCoherence(resultat), refusTvaSansTaux);
    });

    test('activer la TVA ET poser le taux du même geste est accepté', () {
      final resultat = etatResultant({}, {
        'tva_active': 'true',
        'taux_tva': '18',
      });
      expect(verifierCoherence(resultat), isNull);
    });

    test('vider le taux pendant que la TVA reste active est refusé — le second '
        'sens, que PA-62 avait laissé ouvert', () {
      final stocke = {'tva_active': 'true', 'taux_tva': '18'};
      final resultat = etatResultant(stocke, {'taux_tva': null});
      expect(resultat.containsKey('taux_tva'), isFalse);
      expect(verifierCoherence(resultat), refusTvaSansTaux);
    });

    test('désactiver la TVA et vider son taux du même geste est accepté', () {
      final stocke = {'tva_active': 'true', 'taux_tva': '18'};
      final resultat = etatResultant(stocke, {
        'tva_active': 'false',
        'taux_tva': null,
      });
      expect(verifierCoherence(resultat), isNull);
    });

    test('un taux seul, TVA inactive ou absente, est cohérent', () {
      expect(verifierCoherence({'taux_tva': '18'}), isNull);
      expect(verifierCoherence({}), isNull);
    });

    test('une convention illisible sous TVA active est refusée', () {
      expect(
        verifierCoherence({
          'tva_active': 'true',
          'taux_tva': '18',
          'convention_prix': 'xyz',
        }),
        refusConventionInvalide('xyz'),
      );
      expect(
        verifierCoherence({
          'tva_active': 'true',
          'taux_tva': '18',
          'convention_prix': 'ttc',
        }),
        isNull,
      );
    });

    test(
      'etatResultant : le soumis recouvre le stocké, null retire la clé',
      () {
        expect(
          etatResultant({'a': '1', 'b': '2'}, {'a': '9', 'b': null, 'c': '3'}),
          {'a': '9', 'c': '3'},
        );
      },
    );

    test('le message cite les LIBELLÉS que l’exploitant voit, dans les deux '
        'sens', () {
      expect(
        refusTvaSansTaux,
        'La TVA ne peut pas être active sans taux. Renseignez « Taux de TVA '
        '(%) » avant d’activer « Assujettissement à la TVA », et désactivez-la '
        'avant de vider son taux : une TVA activée sans taux est un état '
        'incohérent que ce poste refuse d’enregistrer.',
      );
    });
  });

  group('états DÉRIVÉS — les badges (PA-61)', () {
    test(
      'TVA : cinq états (quatre du serveur plus le propre à ce poste), jamais lus du seul champ tva_active',
      () {
        expect(etatTva({}).code, 'inactive');
        expect(
          etatTva({'tva_active': 'false', 'taux_tva': '18'}).code,
          'inactive',
        );
        expect(etatTva({'taux_tva': '18'}).code, 'inactive');
        expect(etatTva({'tva_active': 'true'}).code, 'activee_sans_taux');
        expect(
          etatTva({
            'tva_active': 'true',
            'taux_tva': '18',
            'convention_prix': 'x',
          }).code,
          'activee_convention_invalide',
        );
        expect(
          etatTva({'tva_active': 'true', 'taux_tva': '18'}).code,
          'parametree_non_appliquee',
        );
      },
    );

    test(
      'TVA active ET paramétrée ne dit JAMAIS « TVA active. » : aucun module '
      'de ce poste ne l’applique',
      () {
        final e = etatTva({'tva_active': 'true', 'taux_tva': '18'});
        expect(e.libelle, isNot(contains('TVA active.')));
        expect(
          e.libelle,
          'TVA activée et paramétrée : ce poste ventile HT/TVA dans la pièce '
          'comptable de chaque vente, mais ne l’applique encore à aucune '
          'facture — aucune ventilation HT/TVA n’y est calculée.',
        );
      },
    );

    test('MECeF : « non configurée » sans numéro, « en attente » avec — et '
        'JAMAIS « active » (PA-17)', () {
      expect(etatMecef({}).code, 'non_configuree');
      expect(
        etatMecef({'entreprise_numero_mecef': '  '}).code,
        'non_configuree',
      );

      final avec = etatMecef({'entreprise_numero_mecef': 'M-123456'});
      expect(avec.code, 'en_attente_implementation');
      expect(
        avec.libelle,
        'Configuration complète, mais le client MECeF réel n’est pas encore '
        'implémenté : les factures mentionnent l’attente d’inscription auprès '
        'de la DGI.',
      );

      // Balayage : quelle que soit la combinaison des clés fiscales et le
      // numéro saisi, l'état n'est jamais « active ».
      final numeros = ['', 'M-1', 'ABC 999', 'actif', 'active', 'true'];
      var balayes = 0;
      for (final n in numeros) {
        for (final tva in ['true', 'false', null]) {
          final e = etatMecef({
            'entreprise_numero_mecef': n,
            'tva_active': ?tva,
          });
          expect(e.code, isNot('active'));
          expect(e.libelle, isNot(contains('Certification MECeF active')));
          balayes++;
        }
      }
      expect(balayes, 18);
    });

    test('l’état d’une base incohérente reste NOMMÉ, il ne se lit pas « TVA '
        'active »', () {
      // Une ligne posée hors de l’écran (restauration, base d’un autre poste).
      expect(
        etatTva({'tva_active': 'true'}).libelle,
        'TVA activée SANS TAUX — la clôture d’une vente est refusée.',
      );
    });
  });
}
