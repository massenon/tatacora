import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/features/auth/data/session_repository_local.dart';
import 'package:tatacora_flutter/features/transverse/data/roles_dao.dart';

/// 10/11/2026 (PO : « si l'admin modifie le RBAC, l'application doit prendre en compte le rôle modifié
/// et le synchroniser ») : un rôle DESCENDU du serveur est recopié sur les comptes du poste ET la
/// session déjà ouverte relit ses droits — sans reconnexion, sans redémarrage.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase base;
  late ProviderContainer c;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    base = AppDatabase.enMemoire();
    c = ProviderContainer(
      overrides: [baseLocaleProvider.overrideWithValue(base)],
    );
    await RolesDao(base).installerSocle();
    await SessionRepositoryLocal(base).creerCompte(
      login: 'marie',
      nom: 'MARIE',
      motDePasse: 'Secret-Marie-9',
      role: 'barman',
      droits: const {'M5': 'C', 'M1': '-'},
    );
  });

  tearDown(() async {
    c.dispose();
    await base.close();
  });

  Future<String> idRole(String libelle) async =>
      (await RolesDao(base).parLibelle(libelle))!.id;

  test('un rôle descendu change les droits de la session ouverte, sans '
      'reconnexion', () async {
    await c.read(sessionProvider.notifier).connecter('marie', 'Secret-Marie-9');
    final avant = c.read(sessionProvider)!;
    expect(avant.droits.peutEcrire(ModuleTatacora.m1Hebergement), isFalse);

    await RolesDao(base).inscrireDescendu(
      id: await idRole('barman'),
      libelle: 'barman',
      description: null,
      droits: const {'M1': 'C'},
    );
    // Rien n'a bougé tant que la session n'a pas relu (c'est ce que fait le bilan de synchro).
    expect(
      c.read(sessionProvider)!.droits.peutEcrire(ModuleTatacora.m1Hebergement),
      isFalse,
    );

    await c.read(sessionProvider.notifier).relireDroitsSiChange();

    expect(
      c.read(sessionProvider)!.droits.peutEcrire(ModuleTatacora.m1Hebergement),
      isTrue,
    );
    expect(c.read(sessionProvider)!.login, 'marie');
  });

  test(
    'sans changement de droits, la session n\'est pas reconstruite',
    () async {
      await c
          .read(sessionProvider.notifier)
          .connecter('marie', 'Secret-Marie-9');
      final avant = c.read(sessionProvider);

      await c.read(sessionProvider.notifier).relireDroitsSiChange();

      expect(identical(c.read(sessionProvider), avant), isTrue);
    },
  );

  test('personne de connecté : rien ne se passe, rien ne plante', () async {
    await c.read(sessionProvider.notifier).relireDroitsSiChange();
    expect(c.read(sessionProvider), isNull);
  });
}
