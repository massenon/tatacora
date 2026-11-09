@Timeout(Duration(minutes: 3))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/parametres/domain/aide_echec_email.dart';

import '../comptabilite/support/outils_comptabilite.dart';

/// L'AIDE sous l'échec de « Envoyer un email de test » (09/11/2026), CONTRE le vrai
/// `AideEchecEmail` du serveur : `tool/parametres/rejouer_aide_email.php` classe chaque
/// message de transport ; le même message passe par `AideEchecEmail` de Dart. Ce qui se
/// compare : le cas reconnu, la phrase, les fragments et l'ordre d'examen — jamais une
/// liste recopiée. Une chaîne par cas.
void main() {
  const messages = <String>[
    // Le message EXACT obtenu par le PO.
    "Serveur SMTP injoignable (connexion absente ?) : Failed host lookup: 'mail.logirestock.digitonpro.com'",
    'Connection could not be established with host "mail.exemple.bj:587": stream_socket_client(): php_network_getaddresses: getaddrinfo for mail.exemple.bj failed: Name or service not known',
    'Temporary failure in name resolution',
    'Serveur SMTP injoignable (connexion absente ?) : No address associated with hostname',
    'Connection could not be established with host "mail.exemple.bj:465": stream_socket_client(): Unable to connect to ssl://mail.exemple.bj:465 (Connection refused)',
    'Serveur SMTP injoignable (connexion absente ?) : Connection refused, errno = 111',
    'Le serveur SMTP n’a pas répondu à temps (connexion absente ?).',
    'Connection to "mail.exemple.bj:587" timed out.',
    'HandshakeException: Handshake error in client (OS Error: WRONG_VERSION_NUMBER)',
    'Failed to authenticate on SMTP server with username "contact@exemple.bj"',
    'Le serveur SMTP a refusé les identifiants (utilisateur ou mot de passe SMTP).',
    'Envoi refusé par le serveur SMTP : 550 Mailbox full',
    'Exception: relais indisponible',
    '',
  ];

  late Map<String, dynamic> serveur;

  setUpAll(() async {
    serveur = await executerPhp(
      'rejouer_aide_email.php',
      dossier: 'parametres',
      entree: {'messages': messages},
    );
  });

  test('chaque message : même cas, même phrase que le serveur', () {
    final cas = serveur['cas'] as Map<String, dynamic>;
    final aide = serveur['aide'] as Map<String, dynamic>;
    var reconnus = 0;
    var inconnus = 0;
    for (final m in messages) {
      expect(AideEchecEmail.cas(m)?.code, cas[m], reason: m);
      expect(AideEchecEmail.pour(m), aide[m], reason: m);
      cas[m] == null ? inconnus++ : reconnus++;
    }
    // Le serveur a RÉELLEMENT reconnu des cas et RÉELLEMENT laissé des inconnus.
    expect(reconnus, 11);
    expect(inconnus, 3);
  });

  test('les trois phrases sont celles du fichier de langue, au mot', () {
    final phrases = serveur['phrases'] as Map<String, dynamic>;
    expect(AideEchecEmail.hote, phrases['hote']);
    expect(AideEchecEmail.connexion, phrases['connexion']);
    expect(AideEchecEmail.authentification, phrases['authentification']);
    expect(phrases.length, 3);
  });

  test('les fragments et leur ORDRE d’examen sont ceux du serveur', () {
    final fragments = serveur['fragments'] as Map<String, dynamic>;
    expect(
      [for (final c in AideEchecEmail.fragments.keys) c.code],
      [for (final c in fragments.keys) c],
      reason: 'l’ordre : hôte, authentification, connexion',
    );
    for (final e in AideEchecEmail.fragments.entries) {
      expect(e.value, (fragments[e.key.code] as List).cast<String>());
    }
  });

  test('un nom introuvable passe avant « connexion impossible » (ordre)', () {
    const symfony =
        'Connection could not be established with host "x:587": getaddrinfo failed';
    expect(AideEchecEmail.cas(symfony), CasEchecEmail.hote);
  });

  test('l’aide est une phrase fixe : ni secret, ni compte, ni message', () {
    const secret = 'M0t-de-passe-S3cret';
    for (final m in [
      "Failed host lookup 'mail.exemple.bj' $secret",
      'Connection refused $secret contact@exemple.bj',
      'authentication $secret',
    ]) {
      final aide = AideEchecEmail.pour(m)!;
      expect(aide, isNot(contains(secret)));
      expect(aide, isNot(contains('contact@exemple.bj')));
      expect(aide, isNot(contains('mail.exemple.bj')));
    }
  });
}
