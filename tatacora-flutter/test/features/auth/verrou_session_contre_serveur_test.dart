@Timeout(Duration(minutes: 3))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/auth/domain/verrou_session.dart';

import '../comptabilite/support/outils_comptabilite.dart';

/// Le verrou de session du poste CONTRE le vrai composant du serveur.
///
/// `tool/session/rejouer_verrou.php` rejoue `VerrouSession::deverrouiller()`
/// (Livewire, vrai `RateLimiter`, vrai `Auth::validate`) sur une base d'essai ;
/// le même scénario passe par [DeverrouillageSession]. Ce qui se compare : le
/// message sous le champ et l'événement `session-deverrouillee`, essai par
/// essai. Une règle recopiée côté Dart ne vérifierait qu'elle-même.
///
/// La base d'essai privée se donne par `TATACORA_BASE_ESSAI=tatacora_<nom>_test`
/// (sinon `tatacora_test`, sérialisée par le verrou de fichier).
void main() {
  const correct = 'CORRECT';
  const faux = 'pas-le-bon';

  // Le scénario : trois utilisateurs INDÉPENDANTS (la clé est par utilisateur).
  final ops = <Map<String, Object?>>[
    {'op': 'utilisateur', 'ref': 'a'},
    {'op': 'utilisateur', 'ref': 'b'},
    {'op': 'utilisateur', 'ref': 'c'},
    {'op': 'libelles'},
    // a : deux échecs, un succès qui remet le compteur à zéro, puis QUATRE
    // échecs (la limite n'est pas atteinte) et un succès.
    for (final mdp in [faux, faux, correct, faux, faux, faux, faux, correct])
      {'op': 'deverrouiller', 'user': 'a', 'mot_de_passe': mdp},
    // b : cinq échecs, puis le sixième essai est refusé même avec le BON mot de
    // passe — c'est la limite, pas la vérification.
    for (final mdp in [faux, faux, faux, faux, faux, faux, correct, correct])
      {'op': 'deverrouiller', 'user': 'b', 'mot_de_passe': mdp},
    // c : n'est pas affecté par le compteur de b.
    {'op': 'deverrouiller', 'user': 'c', 'mot_de_passe': correct},
  ];

  late List<dynamic> serveur;

  setUpAll(() async {
    final reponse = await executerPhp(
      'rejouer_verrou.php',
      dossier: 'session',
      entree: {'ops': ops},
    );
    serveur = reponse['resultats'] as List<dynamic>;
  });

  /// « Réessayez dans 60 seconde(s) » -> `:n`, et le nombre à part.
  (String?, int?) separer(String? message) {
    if (message == null) return (null, null);
    final m = RegExp(r'(\d+) seconde\(s\)').firstMatch(message);
    if (m == null) return (message, null);
    return (message.replaceFirst(m.group(1)!, ':n'), int.parse(m.group(1)!));
  }

  test('le scénario est assez large pour que la comparaison compte', () {
    expect(serveur, hasLength(ops.length));
    final deverrouillages = [
      for (var i = 0; i < ops.length; i++)
        if (ops[i]['op'] == 'deverrouiller')
          (serveur[i] as Map)['deverrouille'] as bool,
    ];
    // Le serveur a RÉELLEMENT refusé et RÉELLEMENT accepté.
    expect(deverrouillages.where((d) => d), isNotEmpty);
    expect(deverrouillages.where((d) => !d), isNotEmpty);
    final messages = [
      for (var i = 0; i < ops.length; i++)
        if (ops[i]['op'] == 'deverrouiller')
          (serveur[i] as Map)['erreur'] as String?,
    ];
    expect(
      messages.whereType<String>().where((m) => m.contains('Trop')),
      isNotEmpty,
    );
    expect(
      messages.whereType<String>().where((m) => m.contains('incorrect')),
      isNotEmpty,
    );
  });

  test('chaque essai rend le MÊME résultat des deux côtés', () async {
    var maintenant = DateTime(2026, 10, 27, 10);
    final local = DeverrouillageSession(
      verifier: (login, mdp) async => mdp == correct,
      limiteur: LimiteurTentatives(horloge: () => maintenant),
    );
    final ecarts = <String>[];
    for (var i = 0; i < ops.length; i++) {
      final op = ops[i];
      if (op['op'] != 'deverrouiller') continue;
      final issue = await local.deverrouiller(
        utilisateurId: 'id-${op['user']}',
        login: '${op['user']}',
        motDePasse: op['mot_de_passe']! as String,
      );
      final (messageLocal, secondesLocal) = separer(switch (issue) {
        MotDePasseRefuse(:final message) => message,
        TropDeTentatives(:final message) => message,
        _ => null,
      });
      final s = serveur[i] as Map<String, dynamic>;
      final (messageServeur, secondesServeur) = separer(s['erreur'] as String?);
      final deverrouilleLocal = issue is Deverrouille;
      if (messageLocal != messageServeur ||
          deverrouilleLocal != s['deverrouille']) {
        ecarts.add(
          'op #$i $op\n  serveur : $messageServeur / ${s['deverrouille']}'
          '\n  poste   : $messageLocal / $deverrouilleLocal',
        );
      }
      // Le décompte : dans la fenêtre de 60 s des deux côtés (le serveur compte
      // en secondes entières, quelques secondes ont pu s'écouler).
      if (secondesLocal != null || secondesServeur != null) {
        expect(secondesLocal, inInclusiveRange(1, 60));
        expect(secondesServeur, inInclusiveRange(1, 60));
      }
      maintenant = maintenant.add(const Duration(milliseconds: 10));
    }
    expect(ecarts, isEmpty, reason: ecarts.join('\n'));
  });

  test('les mots, le seuil et le délai sont ceux du serveur', () {
    final lib =
        (serveur[3] as Map<String, dynamic>)['libelles']
            as Map<String, dynamic>;
    expect(TextesVerrou.titre, lib['titre']);
    expect(TextesVerrou.message, lib['message']);
    expect(TextesVerrou.sousMessage, lib['sous_message']);
    expect(TextesVerrou.motDePasse, lib['mot_de_passe']);
    expect(TextesVerrou.deverrouiller, lib['deverrouiller']);
    expect(TextesVerrou.erreur, lib['erreur']);
    expect(
      TextesVerrou.tropDeTentatives(0).replaceFirst('0', ':secondes'),
      lib['trop_de_tentatives'],
    );
    expect(TextesVerrou.afficherMotDePasse, lib['afficher_mot_de_passe']);
    expect(TextesVerrou.masquerMotDePasse, lib['masquer_mot_de_passe']);
    expect(inactiviteVerrou.inSeconds, lib['inactivite_secondes']);
    // Prouvé NON VIDE : une extraction vide serait verte à vide.
    expect(lib['inactivite_secondes'], 900);
  });
}
