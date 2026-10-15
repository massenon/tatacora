import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/impression/texte_ticket.dart';
import 'package:tatacora_flutter/features/facturation/data/facture_dao.dart';
import 'package:tatacora_flutter/features/facturation/data/facture_repository_local.dart';
import 'package:tatacora_flutter/features/facturation/domain/certification_mecef.dart';
import 'package:tatacora_flutter/features/facturation/domain/entities/piece_facturation.dart';
import 'package:tatacora_flutter/features/facturation/domain/usecases/facturer.dart';
import 'package:tatacora_flutter/features/facturation/impression/ticket_facture.dart';
import 'package:tatacora_flutter/features/hebergement/data/reservation_dao.dart';
import 'package:tatacora_flutter/features/hebergement/data/reservation_repository_local.dart';
import 'package:tatacora_flutter/features/pos/data/panier_dao.dart';
import 'package:tatacora_flutter/features/pos/data/panier_repository_local.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/article_vendable.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/panier.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/reference_catalogue.dart';

/// **D3 — le critère d'acceptation, dans l'application Windows compilée.**
///
/// > *Une facture survit à la fermeture de l'application*, constaté par le
/// > cycle écrire → fermer → rouvrir → relire, **sur fichier**, comme D0.3 et
/// > D2 ; et *le ticket composé ne contient aucun caractère non imprimable*.
///
/// ## Pourquoi ce fichier existe alors que `test/features/facturation/` couvre
/// déjà le cycle sur fichier
///
/// Parce que ce n'est pas le même risque. Les tests unitaires tournent dans la
/// **VM Dart** ; ici, le code s'exécute **dans l'exécutable**, avec ses plugins
/// natifs et le vrai `%USERPROFILE%\\Documents\\tatacora.sqlite` — c'est-à-dire
/// l'endroit où la pièce vivra réellement au comptoir. C'est la distinction
/// établie par D0 : la VM Dart ne prouve rien de l'enveloppe.
///
/// **Lancer un fichier à la fois** (limite d'outillage constatée en D1) :
///
/// ```
/// flutter test integration_test/facture_desktop_test.dart -d windows
/// ```
///
/// ## Ce que ce fichier NE prouve PAS, et qu'aucun test ne prouvera
///
/// Que le ticket sorte **lisible d'une thermique réelle** : largeur du papier,
/// jeu de caractères du pilote, contraste. Cela demande la machine du comptoir.
/// Le PDF est écrit sur le disque à la fin, pour qu'un humain puisse l'ouvrir
/// et le regarder — le rendu se juge à l'œil, pas par une assertion.
///
/// ## Ce test écrit dans la base RÉELLE de la machine, et fait son ménage
///
/// Il ne peut pas faire autrement : c'est précisément l'emplacement qu'il doit
/// éprouver. Toutes les lignes créées portent le préfixe `d3-` et sont
/// supprimées à la fin, dans l'ordre inverse des clés étrangères.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const marqueur = 'd3-facture';
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
      'DELETE FROM lignes_piece_facturation_local WHERE piece_id IN '
          "(SELECT id FROM pieces_facturation_local WHERE panier_id LIKE '$marqueur%' "
          " OR reservation_id LIKE '$marqueur%')",
      "DELETE FROM pieces_facturation_local WHERE panier_id LIKE '$marqueur%' "
          "OR reservation_id LIKE '$marqueur%'",
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
      "VALUES ('$marqueur-u', '$marqueur-cat', 'D3-BNG-01', 'libre')",
    );
    await db.customStatement(
      'INSERT OR REPLACE INTO clients_local '
      '(id, nom, telephone, type_client) '
      "VALUES ('$marqueur-cli', 'KORA', '+229 01 00 00 00 03', 'particulier')",
    );
    // Six nuits à 28 000 F : 1 787 011 200 → 1 787 529 600 (UTC).
    await db.customStatement(
      'INSERT OR REPLACE INTO reservations_local '
      '(id, reference, client_id, unite_id, date_arrivee, date_depart, '
      ' statut, tarif_nuit, acompte, statut_sync, date_creation_locale) '
      "VALUES ('$marqueur-res', 'LOC-D3', '$marqueur-cli', '$marqueur-u', "
      "1787011200, 1787529600, 'confirmee', 28000, 0, 'local', 1787011200)",
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

  testWidgets('la base réelle porte les trois tables de la v4', (tester) async {
    final db = AppDatabase();
    final tables = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type='table' "
          "AND name IN ('pieces_facturation_local', "
          "'lignes_piece_facturation_local', 'sequences_facture_local')",
        )
        .get();
    // Si la machine avait déjà une base v3, c'est `onUpgrade` qui vient de
    // s'exécuter — sur un fichier réel portant de vraies données, et non sur
    // une base vide.
    expect(tables, hasLength(3));

    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.data.values.first, 4);
    await db.close();
  });

  late String numeroEmis;
  late String idEmis;

  testWidgets(
    'CRITÈRE D3 — la facture survit à la fermeture de l’application',
    (tester) async {
      // Session 1 : le réceptionniste clôture le séjour et facture.
      final premiere = AppDatabase();
      final depotPanier = PanierRepositoryLocal(PanierDao(premiere));
      final panier = await depotPanier.ouvrir(
        typeVente: TypeVente.surSejour,
        reservationId: '$marqueur-res',
        clientNom: 'KORA',
        pointVente: 'Réception',
        dateDepartPrevue: DateTime.utc(2026, 8, 24),
      );
      await depotPanier.ajouterLigne(panier.id, biere, quantite: 2);
      final cloture = await depotPanier.cloturer(
        panier.id,
        anticipe: true,
        modePaiement: 'especes',
        auteurId: 'u-integration',
      );

      final reservation = (await ReservationRepositoryLocal(
        ReservationDao(premiere),
      ).parId('$marqueur-res'))!;

      final piece = await Facturer(
        FactureRepositoryLocal(FactureDao(premiere)),
      ).emettrePourSejour(panier: cloture, reservation: reservation);

      numeroEmis = piece.numero;
      idEmis = piece.id;
      await premiere.close();

      // Le fichier existe sur le disque, indépendamment du processus — et à
      // l'emplacement STABLE des documents de l'utilisateur.
      final dossier = await getApplicationDocumentsDirectory();
      final fichier = File(p.join(dossier.path, 'tatacora.sqlite'));
      expect(fichier.existsSync(), isTrue);
      expect(fichier.lengthSync(), greaterThan(0));

      // Session 2 : l'application est relancée.
      final seconde = AppDatabase();
      final relue = await FactureRepositoryLocal(
        FactureDao(seconde),
      ).parNumero(numeroEmis);

      expect(relue, isNotNull, reason: 'la pièce a survécu');
      expect(relue!.id, idEmis);
      expect(relue.origine, OrigineFacture.posSejour);
      expect(relue.statut, StatutPiece.emise);

      // ⚠ Q3 — hébergement et consommations restent NOMMÉS séparément.
      expect(relue.lignes, hasLength(2));
      expect(relue.lignes.first.module, ModuleFacturable.m1Hebergement);
      expect(relue.lignes.first.prixUnitaire, 28000);
      expect(relue.lignes.first.quantite, 6);
      expect(relue.lignes.last.prixUnitaire, 1000);
      expect(relue.montantTotal, 170000);

      // Et elle ne se déclare toujours pas certifiée.
      expect(relue.estCertifiee, isFalse);
      await seconde.close();
    },
  );

  testWidgets('le COMPTEUR survit lui aussi, d’un démarrage à l’autre', (
    tester,
  ) async {
    // Si le compteur repartait de zéro au redémarrage, la première pièce du
    // lendemain porterait un numéro déjà remis à un client.
    final db = AppDatabase();
    final sequence = await db
        .customSelect('SELECT * FROM sequences_facture_local')
        .get();
    expect(sequence, isNotEmpty);
    await db.close();

    // Le numéro suivant est strictement postérieur, sur la même année.
    final apres = AppDatabase();
    final suivant = await FactureDao(apres).numeroSuivant();
    expect(suivant.compareTo(numeroEmis), greaterThan(0));
    await apres.close();
  });

  testWidgets('l’annulation par avoir conserve la pièce, et rien n’est effacé', (
    tester,
  ) async {
    final db = AppDatabase();
    final depot = FactureRepositoryLocal(FactureDao(db));
    final r = await depot.annuler(idEmis, 'Essai D3 — chambre déjà réglée');

    expect(r.facture.statut, StatutPiece.annulee);
    expect(r.facture.montantTotal, 170000, reason: 'rien n’a été effacé');
    expect(r.avoir.avoirDe, numeroEmis);
    expect(r.avoir.montantTotal, -170000);
    await db.close();

    // Relancée : l'avoir est là, et surtout il n'est PAS proposé à la place de
    // la facture — ce serait un document à montant négatif remis au client.
    final apres = AppDatabase();
    final depotApres = FactureRepositoryLocal(FactureDao(apres));
    expect((await depotApres.parId(r.avoir.id))!.montantTotal, -170000);
    expect(await depotApres.facturePourReservation('$marqueur-res'), isNull);
    await apres.close();
  });

  testWidgets('le greffon atteint le sous-système d’impression', (
    tester,
  ) async {
    // Si le greffon Windows n'était pas lié, cet appel lèverait — et c'est
    // exactement la panne qu'on cherche ici, pas un défaut de mise en page.
    final imprimantes = await Printing.listPrinters();
    expect(
      imprimantes,
      isNotEmpty,
      reason: 'aucune imprimante vue : le greffon n’atteint pas le système',
    );
  });

  testWidgets(
    'CRITÈRE D3 — le ticket composé ne perd AUCUN caractère, et sort en PDF',
    (tester) async {
      final db = AppDatabase();
      final piece = (await FactureRepositoryLocal(
        FactureDao(db),
      ).parId(idEmis))!;
      await db.close();

      final ticket = TicketFacture.composer(piece);

      // Le garde-fou porte sur le document EFFECTIVEMENT composé.
      for (final texte in ticket.textes) {
        expect(
          caracteresNonImprimables(texte),
          isEmpty,
          reason: 'ces caractères disparaîtraient en silence : « $texte »',
        );
      }

      // Le filigrane est là, et la mention aussi : aucune pièce ne se déclare
      // certifiée (PA-61).
      expect(
        ticket.texteBrut,
        contains(CertificationMecef.filigraneDemonstration),
      );
      expect(
        ticket.texteBrut,
        contains(texteTicket(CertificationMecef.libelleDemonstration)),
      );

      final octets = await ticket.pdf();
      expect(octets.length, greaterThan(500));
      expect(String.fromCharCodes(octets.take(4)), '%PDF');

      // Le fichier est CONSERVÉ : c'est la seule pièce de D3 qu'un humain peut
      // ouvrir, mettre dans l'imprimante, et regarder. La lisibilité sur papier
      // thermique ne se constate que là.
      final dossier = await getApplicationDocumentsDirectory();
      final sortie = File(
        p.join(dossier.path, 'tatacora-ticket-d3-$numeroEmis.pdf'),
      );
      await sortie.writeAsBytes(octets);
      expect(sortie.existsSync(), isTrue);
      // ignore: avoid_print
      print('Ticket D3 écrit pour contrôle humain : ${sortie.path}');
    },
  );

  testWidgets(
    'la migration v3 → v4 s’exécute sur la base RÉELLE du poste, données '
    'comprises',
    (tester) async {
      // ## Pourquoi une COPIE de la vraie base, et pas la vraie
      //
      // La base du poste est déjà en v4 depuis la première ouverture de ce
      // fichier de test : la transition ne peut plus être rejouée en place. La
      // rejouer sur une **copie** garde ce qui compte — le volume et la forme
      // réels des données du poste, pas un fichier reconstitué à la main — sans
      // risquer la base de travail.
      //
      // C'est la leçon PA-59 : `onCreate` s'exécute à chaque test en mémoire,
      // `onUpgrade` jamais, et c'est pourtant lui le chemin de la mise à jour.
      final dossier = await getApplicationDocumentsDirectory();
      final reelle = File(p.join(dossier.path, 'tatacora.sqlite'));
      final copie = File(p.join(dossier.path, 'tatacora-d3-migration.sqlite'));
      if (copie.existsSync()) copie.deleteSync();
      await reelle.copy(copie.path);
      addTearDown(() {
        if (copie.existsSync()) copie.deleteSync();
      });

      // Retour en v3 : les trois tables de la v4 sont retirées.
      final v3 = AppDatabase.surFichier(copie);
      await v3.customStatement('SELECT 1');
      final avant =
          (await v3
                  .customSelect('SELECT COUNT(*) AS n FROM reservations_local')
                  .getSingle())
              .data['n'];
      await v3.customStatement('DROP TABLE lignes_piece_facturation_local');
      await v3.customStatement('DROP TABLE pieces_facturation_local');
      await v3.customStatement('DROP TABLE sequences_facture_local');
      await v3.customStatement('PRAGMA user_version = 3');
      await v3.close();

      // Réouverture : `onUpgrade` s'exécute sur un fichier NON VIDE.
      final v4 = AppDatabase.surFichier(copie);
      final version = await v4.customSelect('PRAGMA user_version').getSingle();
      expect(version.data.values.first, 4);

      final apres =
          (await v4
                  .customSelect('SELECT COUNT(*) AS n FROM reservations_local')
                  .getSingle())
              .data['n'];
      expect(
        apres,
        avant,
        reason: 'les réservations du poste ont survécu à la migration',
      );
      expect(await v4.select(v4.piecesFacturationLocal).get(), isEmpty);
      // ignore: avoid_print
      print(
        'Migration v3 → v4 rejouée sur copie réelle : $avant réservation(s) conservée(s)',
      );
      await v4.close();
    },
  );

  testWidgets('la facture n’écrit RIEN en file de synchronisation', (
    tester,
  ) async {
    // `factures` n'est pas au registre `TABLES_SYNCHRONISABLES` du serveur, et
    // `routes/api.php` n'expose aucune route de facturation : une opération y
    // serait rejetée à chaque tentative, et le poste afficherait « en attente »
    // sur quelque chose qui ne partira jamais (PA-59/60/61).
    final db = AppDatabase();
    final file = await db
        .customSelect("SELECT * FROM sync_queue WHERE table_cible = 'factures'")
        .get();
    expect(file, isEmpty);
    await db.close();
  });
}
