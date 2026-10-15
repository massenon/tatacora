import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';

/// Socle desktop — Sprint D0, éprouvé **sur la cible Windows réelle**.
///
/// ## Pourquoi ces tests ne sont pas des tests unitaires
///
/// Tout ce qui suit passe dans la VM Dart d'un test ordinaire. Ce n'est pas ce
/// qu'on veut prouver : le risque du socle desktop ne vit pas dans le code
/// Dart, il vit dans **l'enveloppe** — la bibliothèque native SQLite, le
/// stockage sécurisé du système, le chemin des documents utilisateur.
///
/// Lancer ces cas avec `flutter test` les ferait passer sans rien prouver.
/// Il faut `flutter test integration_test -d windows`, qui les exécute **dans
/// l'application compilée**, avec ses plugins natifs.
///
/// C'est la même distinction que celle du Sprint 1 mobile : un test sur base
/// **en mémoire** passait toujours par `onCreate` et n'a jamais emprunté
/// `onUpgrade` — le chemin était faux et personne ne le voyait (PA-59).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('D0 — la base vit sur le disque', () {
    testWidgets('SQLite est disponible et le schéma se crée', (tester) async {
      final db = AppDatabase();

      // Une requête triviale suffit : si le moteur natif manquait, elle
      // lèverait ici, avant toute considération de schéma.
      final version = await db
          .customSelect('SELECT sqlite_version() AS v')
          .getSingle();
      expect(version.data['v'], isA<String>());

      final tables = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' "
            "AND name NOT LIKE 'sqlite_%'",
          )
          .get();
      expect(
        tables.length,
        greaterThanOrEqualTo(20),
        reason: 'le schéma Drift complet doit exister sur Windows',
      );

      await db.close();
    });

    testWidgets('le fichier est écrit dans les documents de l’utilisateur', (
      tester,
    ) async {
      // Un emplacement STABLE compte autant que l'écriture elle-même : une
      // base posée dans un répertoire temporaire disparaîtrait au ménage du
      // système, et l'utilisateur perdrait ses saisies hors ligne sans qu'un
      // seul message ne l'annonce.
      final dossier = await getApplicationDocumentsDirectory();
      final fichier = File(p.join(dossier.path, 'tatacora.sqlite'));

      final db = AppDatabase();
      await db.customSelect('SELECT 1').getSingle();
      await db.close();

      expect(fichier.existsSync(), isTrue);
      expect(fichier.lengthSync(), greaterThan(0));
    });

    testWidgets('une écriture survit à la fermeture de la base', (
      tester,
    ) async {
      final temoin = 'd0-${DateTime.now().microsecondsSinceEpoch}';

      final premiere = AppDatabase();
      await premiere.customStatement(
        'INSERT OR REPLACE INTO clients_local '
        '(id, nom, telephone, type_client) '
        "VALUES ('$temoin', 'TEMOIN D0', '+229 00 00 00 00', 'particulier')",
      );
      await premiere.close();

      // Réouverture : c'est le cycle que seul le disque peut passer. Une base
      // ouverte en mémoire par défaut de configuration donnerait une
      // application parfaitement fonctionnelle qui perd tout à la fermeture,
      // sans erreur ni test rouge.
      final seconde = AppDatabase();
      final relu = await seconde
          .customSelect("SELECT nom FROM clients_local WHERE id = '$temoin'")
          .get();
      expect(relu, hasLength(1));
      expect(relu.single.data['nom'], 'TEMOIN D0');

      await seconde.customStatement(
        "DELETE FROM clients_local WHERE id = '$temoin'",
      );
      await seconde.close();
    });
  });

  group('D0 — le stockage sécurisé', () {
    // Il ne porte pas qu'un jeton : il porte le **nom du poste**, dont dépend
    // la vérification `poste_id` du lot de synchronisation (PA-66) et, à
    // travers elle, la classification des conflits (RG-17). Un poste qui
    // perdrait son nom à chaque démarrage ferait passer ses écritures pour
    // celles d'un tiers.
    const stockage = FlutterSecureStorage();
    const cle = 'tatacora_d0_temoin';

    testWidgets('une valeur écrite se relit', (tester) async {
      await stockage.write(key: cle, value: 'poste-reception');
      expect(await stockage.read(key: cle), 'poste-reception');
    });

    testWidgets('elle survit à une nouvelle instance du client', (
      tester,
    ) async {
      // Une seconde instance simule ce que fait l'application au démarrage :
      // elle ne conserve rien en mémoire, elle relit le magasin du système.
      const autre = FlutterSecureStorage();
      expect(await autre.read(key: cle), 'poste-reception');
    });

    testWidgets('elle se supprime', (tester) async {
      await stockage.delete(key: cle);
      expect(await stockage.read(key: cle), isNull);
    });
  });

  group('D0 — la plateforme est bien celle attendue', () {
    testWidgets('on tourne sur Windows', (tester) async {
      // Garde-fou du garde-fou : ces tests passeraient sur n'importe quelle
      // plateforme. S'ils tournaient par mégarde en VM Dart, ils ne
      // prouveraient rien du socle desktop.
      expect(Platform.isWindows, isTrue, reason: 'à lancer avec -d windows');
    });
  });
}
