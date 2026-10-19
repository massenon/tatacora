@Timeout(Duration(minutes: 2))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/messages_comptables.dart';

import 'support/outils_comptabilite.dart';

/// Les phrases de refus du poste sont celles du serveur, mot pour mot : relues
/// par EXÉCUTION de PHP dans `lang/fr/comptabilite.php` et `lang/fr/depenses.php`
/// (`tool/comptabilite/exporter_referentiel.php`).
void main() {
  late Map<String, String> serveur;

  setUpAll(() async {
    final r = await executerPhp('exporter_referentiel.php');
    serveur = (r['messages'] as Map<String, dynamic>).cast<String, String>();
  });

  test('26 clés relues du serveur — un export tronqué échouerait', () {
    expect(serveur, hasLength(26));
    // Non vide : chaque phrase du serveur est une vraie phrase.
    for (final e in serveur.entries) {
      expect(e.value.length, greaterThan(20), reason: e.key);
    }
  });

  test('chaque gabarit du poste est EXACTEMENT celui du serveur', () {
    expect(MessagesComptables.gabarits.keys.toSet(), serveur.keys.toSet());
    for (final e in serveur.entries) {
      expect(MessagesComptables.gabarits[e.key], e.value, reason: e.key);
    }
  });

  test(
    'les phrases propres au poste ne se confondent avec aucune du serveur',
    () {
      final locales = [
        PhrasesDuPoste.ligneNegative,
        PhrasesDuPoste.debitEtCredit,
        PhrasesDuPoste.referenceRefusee,
        PhrasesDuPoste.auteurAbsent,
        PhrasesDuPoste.montantIllisible('x'),
        PhrasesDuPoste.ecritureIntrouvable('x'),
      ];
      for (final l in locales) {
        expect(serveur.values, isNot(contains(l)));
      }
    },
  );

  group('Le remplacement des variables est celui de Laravel', () {
    test('une variable, plusieurs occurrences, plusieurs variables', () {
      expect(
        MessagesComptables.dire('comptabilite.piece_desequilibree', {
          'debit': '10.00',
          'credit': '7.00',
          'ecart': '3.00',
        }),
        startsWith(
          'Pièce déséquilibrée : 10.00 au débit contre 7.00 au crédit '
          '(écart de 3.00).',
        ),
      );
      expect(
        MessagesComptables.dire('depenses.exercice_clos', {
          'annee': '2031',
          'statut': 'en_cloture',
        }),
        startsWith('L\'exercice 2031 est en_cloture : aucune écriture'),
      );
    });

    test('une clé inconnue LÈVE : jamais la clé brute à l’écran', () {
      expect(
        () => MessagesComptables.dire('comptabilite.inconnue'),
        throwsArgumentError,
      );
    });

    test('une variable absente laisse le jeton visible (comme Laravel)', () {
      expect(
        MessagesComptables.dire('comptabilite.compte_division'),
        contains(':numero'),
      );
    });
  });
}
