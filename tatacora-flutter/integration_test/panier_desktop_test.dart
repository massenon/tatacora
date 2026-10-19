import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/pos/data/panier_dao.dart';
import 'package:tatacora_flutter/features/pos/data/panier_repository_local.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/article_vendable.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/panier.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/reference_catalogue.dart';

/// **D2 — le critère d'acceptation, dans l'application Windows compilée.**
///
/// > *Un panier de séjour survit à la fermeture de l'application*, constaté par
/// > le cycle écrire → fermer → rouvrir → relire, **sur fichier**, comme D0.3.
///
/// ⚠ **Portage d'une PROPOSITION non ratifiée**
/// (`docs/PROPOSITION_MODELE_PANIER_POS.md`, Q1/Q2/Q3).
///
/// ## Pourquoi ce fichier existe alors que `test/features/pos/` couvre déjà le
/// cycle sur fichier
///
/// Parce que ce n'est pas le même risque. Les tests unitaires tournent dans la
/// **VM Dart** ; ici, le code s'exécute **dans l'exécutable**, avec ses plugins
/// natifs et le vrai `%USERPROFILE%\Documents\tatacora.sqlite` — c'est-à-dire
/// l'endroit où la donnée vivra réellement au comptoir. C'est la distinction
/// établie par D0 : la VM Dart ne prouve rien de l'enveloppe.
///
/// **Lancer un fichier à la fois** (limite d'outillage constatée en D1) :
///
/// ```
/// flutter test integration_test/panier_desktop_test.dart -d windows
/// ```
///
/// ## Ce test écrit dans la base RÉELLE de la machine, et fait son ménage
///
/// Il ne peut pas faire autrement : c'est précisément l'emplacement qu'il doit
/// éprouver. Toutes les lignes créées portent le préfixe `d2-` et sont
/// supprimées à la fin, dans l'ordre inverse des clés étrangères.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const marqueur = 'd2-panier';
  const biere = ArticleVendable(
    reference: ReferenceCatalogue(
      module: ModuleVendable.m5Bar,
      code: '$marqueur-bsn',
    ),
    libelle: 'Béninoise 33cl',
    prix: 1000,
    categorie: 'locale',
  );

  Future<void> nettoyer() async {
    final db = AppDatabase();
    for (final ordre in [
      "DELETE FROM lignes_panier_local WHERE code_article LIKE '$marqueur%'",
      "DELETE FROM paniers_local WHERE id LIKE '$marqueur%' "
          "OR reservation_id LIKE '$marqueur%'",
      "DELETE FROM reservations_local WHERE id LIKE '$marqueur%'",
      "DELETE FROM cartes_boisson_local WHERE id LIKE '$marqueur%'",
      "DELETE FROM unites_hebergement_local WHERE id LIKE '$marqueur%'",
      "DELETE FROM categories_hebergement_local WHERE id LIKE '$marqueur%'",
      "DELETE FROM clients_local WHERE id LIKE '$marqueur%'",
    ]) {
      await db.customStatement(ordre);
    }
    await db.close();
  }

  Future<void> semer() async {
    final db = AppDatabase();
    await db.customStatement(
      'INSERT OR REPLACE INTO cartes_boisson_local '
      '(id, article_id, libelle, categorie, prix_vente) '
      "VALUES ('$marqueur-bsn', '$marqueur-art', 'Béninoise 33cl', "
      "'locale', 1000)",
    );
    await db.customStatement(
      'INSERT OR REPLACE INTO categories_hebergement_local '
      '(id, libelle, capacite_max, tarif_base) '
      "VALUES ('$marqueur-cat', 'Bungalow', 2, 28000)",
    );
    await db.customStatement(
      'INSERT OR REPLACE INTO unites_hebergement_local '
      '(id, categorie_id, numero, statut) '
      "VALUES ('$marqueur-u', '$marqueur-cat', 'D2-BNG-01', 'libre')",
    );
    await db.customStatement(
      'INSERT OR REPLACE INTO clients_local '
      '(id, nom, telephone, type_client) '
      "VALUES ('$marqueur-cli', 'KORA', '+229 01 00 00 00 01', 'particulier')",
    );
    await db.customStatement(
      'INSERT OR REPLACE INTO reservations_local '
      '(id, reference, client_id, unite_id, date_arrivee, date_depart, '
      ' statut, tarif_nuit, acompte, statut_sync, date_creation_locale) '
      "VALUES ('$marqueur-res', 'LOC-D2', '$marqueur-cli', '$marqueur-u', "
      "1800000000, 1800432000, 'confirmee', 28000, 0, 'local', 1800000000)",
    );
    await db.close();
  }

  setUpAll(() async {
    await nettoyer();
    await semer();
  });

  tearDownAll(nettoyer);

  testWidgets('on tourne bien sur Windows, pas en VM Dart', (tester) async {
    // Garde-fou du garde-fou : ce fichier passerait sur n'importe quelle
    // plateforme, et ne prouverait alors rien du socle desktop.
    expect(Platform.isWindows, isTrue, reason: 'à lancer avec -d windows');
  });

  testWidgets('la base réelle porte les deux tables de la v3', (tester) async {
    final db = AppDatabase();
    final tables = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type='table' "
          "AND name IN ('paniers_local', 'lignes_panier_local')",
        )
        .get();
    // Si la machine avait déjà une base v2, c'est `onUpgrade` qui vient de
    // s'exécuter — sur un fichier réel portant de vraies données, et non sur
    // une base vide.
    expect(tables, hasLength(2));

    // La version attendue est celle du SCHÉMA COURANT, pas celle de D2 : le
    // registre de facturation (D3) a porté la base en v4, et les tables du
    // panier doivent y survivre — c'est précisément ce que la ligne au-dessus
    // vérifie. Figer 3 ici ferait rougir ce test à chaque migration suivante,
    // pour une raison qui n'a rien à voir avec le panier.
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.data.values.first, db.schemaVersion);
    await db.close();
  });

  testWidgets(
    'CRITÈRE D2 — le panier de séjour survit à la fermeture de l’application',
    (tester) async {
      // Session 1 : le barman porte trois bières sur la note de chambre.
      final premiere = AppDatabase();
      final panier = await PanierRepositoryLocal(PanierDao(premiere)).ouvrir(
        typeVente: TypeVente.surSejour,
        reservationId: '$marqueur-res',
        clientNom: 'KORA',
        pointVente: 'Bar',
        dateDepartPrevue: DateTime(2027, 1, 1),
      );
      await PanierRepositoryLocal(
        PanierDao(premiere),
      ).ajouterLigne(panier.id, biere, quantite: 3);
      await premiere.close();

      // Le fichier existe sur le disque, indépendamment du processus — et à
      // l'emplacement STABLE des documents de l'utilisateur, pas dans un
      // répertoire temporaire que le ménage du système emporterait.
      final dossier = await getApplicationDocumentsDirectory();
      final fichier = File(p.join(dossier.path, 'tatacora.sqlite'));
      expect(fichier.existsSync(), isTrue);
      expect(fichier.lengthSync(), greaterThan(0));

      // Session 2 : l'application est relancée.
      final seconde = AppDatabase();
      final relu = await PanierRepositoryLocal(
        PanierDao(seconde),
      ).panierOuvertPour('$marqueur-res');

      expect(relu, isNotNull, reason: 'le panier du séjour a survécu');
      expect(relu!.id, panier.id);
      expect(relu.statut, StatutPanier.ouvert);
      expect(relu.clientNom, 'KORA');
      expect(relu.lignes, hasLength(1));
      expect(relu.lignes.single.quantite, 3);
      // Le prix FIGÉ a survécu lui aussi : c'est ce qui fait qu'une bière de
      // lundi reste au prix de lundi après plusieurs redémarrages.
      expect(relu.lignes.single.prixUnitaire, 1000);
      expect(relu.total, 3000);
      await seconde.close();
    },
  );

  testWidgets('⚠ Q2 — l’unicité tient d’un démarrage à l’autre', (
    tester,
  ) async {
    // Si la garantie vivait en mémoire, redémarrer l'application suffirait à
    // ouvrir un second panier — et à scinder les consommations du séjour.
    final db = AppDatabase();
    await expectLater(
      PanierRepositoryLocal(PanierDao(db)).ouvrir(
        typeVente: TypeVente.surSejour,
        reservationId: '$marqueur-res',
        dateDepartPrevue: DateTime(2027, 1, 1),
      ),
      throwsA(isA<Exception>()),
    );
    await db.close();
  });

  testWidgets('le panier n’écrit RIEN en file de synchronisation', (
    tester,
  ) async {
    // `paniers` n'est pas au registre `TABLES_SYNCHRONISABLES` du serveur : une
    // opération y serait rejetée à chaque tentative, et le poste afficherait
    // « en attente » sur quelque chose qui ne partira jamais (PA-59/60/61).
    final db = AppDatabase();
    final file = await db
        .customSelect("SELECT * FROM sync_queue WHERE table_cible = 'paniers'")
        .get();
    expect(file, isEmpty);
    await db.close();
  });

  testWidgets('clôture : le montant se fige, et le séjour se libère', (
    tester,
  ) async {
    final db = AppDatabase();
    final depot = PanierRepositoryLocal(PanierDao(db));
    final ouvert = (await depot.panierOuvertPour('$marqueur-res'))!;

    // Clôture ANTICIPÉE : le départ est en 2027. Sans `anticipe`, la règle 5
    // refuse — et c'est ce refus qui est éprouvé juste avant.
    await expectLater(
      depot.cloturer(ouvert.id, auteurId: 'u-integration'),
      throwsA(isA<Exception>()),
      reason: 'règle 5 : jamais silencieuse',
    );

    final cloture = await depot.cloturer(
      ouvert.id,
      anticipe: true,
      modePaiement: 'especes',
      auteurId: 'u-integration',
    );
    expect(cloture.montantCloture, 3000);
    await db.close();

    // Relancée : le montant figé n'a pas bougé, et le séjour n'a plus de
    // panier ouvert — la règle 1 ne bloque que les paniers OUVERTS.
    final apres = AppDatabase();
    final depotApres = PanierRepositoryLocal(PanierDao(apres));
    expect((await depotApres.parId(cloture.id))!.montantCloture, 3000);
    expect(await depotApres.panierOuvertPour('$marqueur-res'), isNull);
    await apres.close();
  });
}
