@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/hebergement/domain/messages_canaux.dart';

/// Les phrases des canaux sont CELLES du serveur : `lang/fr/parametres.php`,
/// EXÉCUTÉ par PHP (les chaînes y sont concaténées), paramètres remplacés
/// comme le fait `__()`.
void main() {
  Map<String, dynamic> langue(String nom) {
    final r = Process.runSync('php', [
      '-r',
      'echo json_encode(require "lang/fr/$nom.php");',
    ], workingDirectory: '../tatacora-api');
    if (r.exitCode != 0) fail('PHP n’a pas pu lire lang/fr/$nom.php');
    return jsonDecode(r.stdout as String) as Map<String, dynamic>;
  }

  test('les refus et succès des canaux sont repris au mot', () {
    final p = langue('parametres');
    expect(p['canal_nom_requis'], isNotNull, reason: 'extraction non vide');
    expect(MessagesCanaux.nomRequis, p['canal_nom_requis']);
    expect(
      MessagesCanaux.nomDejaUtilise('Booking.com'),
      (p['canal_nom_deja_utilise'] as String).replaceAll(':nom', 'Booking.com'),
    );
    expect(MessagesCanaux.introuvable, p['canal_introuvable']);
    expect(MessagesCanaux.enregistre, p['canal_enregistre']);
    expect(MessagesCanaux.bascule, p['canal_bascule']);
  });

  test(
    'les mots de l’onglet sont ceux de la vue (pwa.parametres.canaux_*)',
    () {
      final pwa = langue('pwa')['parametres'] as Map<String, dynamic>;
      expect(pwa['canaux_modale_titre_ajout'], 'Nouveau canal de réservation');
      expect(pwa['canaux_bouton_desactiver'], 'Désactiver');
      expect(
        (pwa['canaux_confirmation_desactivation'] as String)
            .replaceAll(':nom', 'X')
            .replaceAll(':n', '3'),
        contains('Désactiver « X » ? 3 réservation(s)'),
      );
    },
  );
}
