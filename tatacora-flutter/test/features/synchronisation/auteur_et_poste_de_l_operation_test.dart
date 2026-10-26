import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/features/auth/domain/session.dart';
import 'package:tatacora_flutter/core/database/auteur_ecriture.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';
import 'package:tatacora_flutter/features/transverse/domain/journal_poste.dart';

import 'support/faux_transport.dart';

/// QUI a écrit, et depuis quel poste — schéma v38 (26/10/2026). Chaque opération
/// de la file garde le login du compte connecté et le nom du poste à
/// l'instant de l'enfilement : c'est ce que le Journal d'Audit affiche dans ses
/// colonnes « Utilisateur » et « Poste », jusque-là « — ».
void main() {
  late BancSync b;

  setUp(() async => b = await BancSync.creer());
  tearDown(() => b.fermer());

  Future<String?> enfiler(String id) => b.db.transaction(
    () => b.dao.enfiler(
      table: TableSynchronisee.clients,
      entiteId: id,
      type: TypeOperationSync.creation,
      payload: {'nom': 'N$id', 'telephone': '97000000'},
    ),
  );

  test('l’opération porte le compte CONNECTÉ et le poste, relus à chaque '
      'écriture', () async {
    b.db.auteurEcriture = () => (login: 'awa', poste: 'CAISSE-1');
    await enfiler('c-1');
    // Une autre session entre deux gestes : l'écriture suivante n'est PAS
    // signée du compte précédent (RG-15).
    b.db.auteurEcriture = () => (login: 'koffi', poste: 'CAISSE-1');
    await enfiler('c-2');

    final ops = await b.dao.operations();
    expect(ops.map((o) => (o.entiteId, o.auteurLogin, o.posteNom)), [
      ('c-1', 'awa', 'CAISSE-1'),
      ('c-2', 'koffi', 'CAISSE-1'),
    ]);
  });

  test('personne n’est connu : « — », jamais un compte inventé', () async {
    await enfiler('c-1');
    final o = (await b.dao.operations()).single;
    expect((o.auteurLogin, o.posteNom), (null, null));
    expect(aucunAuteurEcriture, (login: null, poste: null));
  });

  test(
    '« Renvoyer » garde l’auteur et le poste de l’écriture d’origine',
    () async {
      b.db.auteurEcriture = () => (login: 'awa', poste: 'CAISSE-1');
      await enfiler('c-1');
      final origine = (await b.dao.operations()).single;
      await b.db.customStatement(
        "UPDATE operations_sync_local SET statut = 'rejete' "
        "WHERE uuid_operation = '${origine.uuidOperation}'",
      );
      // Un autre compte relance : il n'a pas SAISI le document.
      b.db.auteurEcriture = () => (login: 'admin', poste: 'CAISSE-1');

      final nouvelle = await b.dao.renvoyer(origine.uuidOperation);

      final copie = (await b.dao.operations()).firstWhere(
        (o) => o.uuidOperation == nouvelle,
      );
      expect((copie.auteurLogin, copie.posteNom), ('awa', 'CAISSE-1'));
    },
  );

  test(
    'le journal du poste lit l’utilisateur et le poste de la file',
    () async {
      b.db.auteurEcriture = () => (login: 'awa', poste: 'CAISSE-1');
      await enfiler('c-1');
      final op = (await b.dao.operations()).single;

      final entree = EntreeJournalPoste.depuisOperation(op);

      expect((entree.utilisateur, entree.poste), ('awa', 'CAISSE-1'));
      expect(entree.libelleTable, 'Client');
    },
  );

  test('le nom du poste est celui de la machine, jamais une chaîne vide', () {
    final nom = nomDuPosteLocal();
    expect(nom == null || nom.trim().isNotEmpty, isTrue);
  });

  test('la base de l’application est CÂBLÉE sur la session : le login du compte '
      'connecté, relu à chaque appel', () async {
    var session = false;
    final conteneur = ProviderContainer(
      overrides: [
        sessionProvider.overrideWithBuild(
          (ref, notifier) => session
              ? Session(
                  utilisateurId: 'u-1',
                  login: 'awa',
                  nom: 'Awa',
                  role: 'caissier',
                  droits: const GardeAcces({}),
                )
              : null,
        ),
      ],
    );
    addTearDown(conteneur.dispose);

    // `AppDatabase()` ouvre son fichier PARESSEUSEMENT : lire le contexte ne le
    // touche pas.
    final base = conteneur.read(baseLocaleProvider);
    expect(base.auteurEcriture().login, isNull, reason: 'personne connecté');

    session = true;
    conteneur.invalidate(sessionProvider);
    expect(base.auteurEcriture().login, 'awa');
    expect(base.auteurEcriture().poste, nomDuPosteLocal());
  });
}
