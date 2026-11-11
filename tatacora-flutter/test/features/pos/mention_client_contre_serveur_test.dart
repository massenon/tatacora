@Timeout(Duration(minutes: 2))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/pos/domain/mention_client.dart';

import '../comptabilite/support/outils_comptabilite.dart';

/// La MENTION client du comptoir, confrontée au VRAI code du serveur : les mêmes
/// saisies passent par `VenteService::normaliserMentionClient` (PHP, via
/// `tool/ventes/rejouer_mention_client.php`) et par `MentionClient.normaliser`
/// (Dart), et le résultat est comparé caractère pour caractère. La longueur
/// maximale est celle de la VRAIE colonne `ventes.client_mention`, lue dans
/// `information_schema`.
///
/// Le chemin complet (charge d'une vente de poste, `GestionnaireVentes`,
/// colonne rangée) est prouvé à part par `charges_contre_serveur_test.dart`.
///
/// MySQL injoignable ou `php` absent : le test ÉCHOUE, il ne saute pas.
void main() {
  // Chaque saisie vise une branche de la règle ; la dernière est la plus hostile.
  final saisies = <String?>[
    null,
    '',
    '   ',
    'Jean',
    '  Jean Dupont  ',
    'Mme Aïssatou N\'DOUR — Société Sahel',
    'Sé́bastien',
    'Ligne un\nligne deux',
    'Tab\tulation',
    'Retour\r\nchariot',
    'Nul\u0000Octet',
    'Echap\u001BCommande',
    'DEL\u007FSupprime',
    'C1\u0085Suivante\u009F',
    '\u0007\u0008  Bord  \u0009',
    '\n\n',
    'Espace  double  conservé',
    'Espace insécable',
    'A' * 255,
    'B' * 256,
    '${'C' * 254} ',
    '${'D' * 254}  E',
    '${' ' * 10}${'F' * 300}',
    // Hors BMP : un point de code compte pour UN caractère (utf8mb4).
    '😀' * 255,
    '😀' * 300,
    'é' * 300,
    '${'G' * 253}\n\nH',
  ];

  late Map<String, dynamic> serveur;

  setUpAll(() async {
    serveur = await executerPhp(
      'rejouer_mention_client.php',
      dossier: 'ventes',
      entree: {'saisies': saisies},
    );
  });

  test('la longueur maximale du poste est celle de la colonne du serveur', () {
    expect(serveur['colonne_max'], MentionClient.longueurMax);
  });

  test('chaque saisie donne, au poste, EXACTEMENT ce que donne le serveur', () {
    final attendu = (serveur['normalisees'] as List).cast<String?>();
    expect(attendu, hasLength(saisies.length));
    for (var i = 0; i < saisies.length; i++) {
      expect(
        MentionClient.normaliser(saisies[i]),
        attendu[i],
        reason: 'saisie n°$i : ${saisies[i]?.runes.take(40).toList()}',
      );
    }
  });

  test(
    'le serveur ne laisse AUCUN caractère de contrôle, le poste non plus',
    () {
      final controle = RegExp(r'[\u0000-\u001F\u007F-\u009F]');
      for (final s in saisies) {
        final r = MentionClient.normaliser(s);
        if (r != null) {
          expect(controle.hasMatch(r), isFalse, reason: r);
          expect(r.runes.length, lessThanOrEqualTo(MentionClient.longueurMax));
        }
      }
      for (final r in (serveur['normalisees'] as List).cast<String?>()) {
        if (r != null) expect(controle.hasMatch(r), isFalse);
      }
    },
  );
}
