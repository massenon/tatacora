import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/impression/entete_etablissement.dart';
import 'package:tatacora_flutter/core/impression/texte_ticket.dart';
import 'package:tatacora_flutter/core/theme/app_assets.dart';
import 'package:tatacora_flutter/features/facturation/data/facture_dao.dart';
import 'package:tatacora_flutter/features/facturation/data/facture_repository_local.dart';
import 'package:tatacora_flutter/features/facturation/domain/certification_mecef.dart';
import 'package:tatacora_flutter/features/facturation/domain/entities/piece_facturation.dart';
import 'package:tatacora_flutter/features/facturation/domain/usecases/facturer.dart';
import 'package:tatacora_flutter/features/facturation/impression/essai_qr_thermique.dart';
import 'package:tatacora_flutter/features/facturation/impression/facture_a4.dart';
import 'package:tatacora_flutter/features/hebergement/data/reservation_dao.dart';
import 'package:tatacora_flutter/features/hebergement/data/reservation_repository_local.dart';
import 'package:tatacora_flutter/features/pos/data/panier_dao.dart';
import 'package:tatacora_flutter/features/pos/data/panier_repository_local.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/article_vendable.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/panier.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/reference_catalogue.dart';

/// **D4 — la facture A4 et la planche d'essai QR, dans l'exécutable Windows.**
///
/// ## Pourquoi ce fichier existe alors que `test/features/facturation/` couvre
/// déjà la composition
///
/// Pour deux choses qu'aucun test en VM Dart ne peut donner :
///
///  1. **le logo est-il réellement embarqué dans l'application ?** Il est
///     déclaré au `pubspec.yaml` et lu par `rootBundle` : seule l'application
///     compilée le dit. Un asset oublié produirait une facture sans logo — ce
///     qui ne lève pas, ne se voit pas en test, et se découvre sur le papier ;
///  2. **les deux PDF, écrits sur le disque**, pour qu'un humain les ouvre, les
///     imprime, et les regarde. La lisibilité d'un QR sur papier thermique et
///     la tenue d'une page A4 ne se constatent que là.
///
/// **Lancer un fichier à la fois** (limite d'outillage constatée en D1) :
///
/// ```
/// flutter test integration_test/facture_a4_desktop_test.dart -d windows
/// ```
///
/// ## Ce test écrit dans la base RÉELLE de la machine, et fait son ménage
///
/// Toutes les lignes créées portent le préfixe `d4-` et sont supprimées à la
/// fin, dans l'ordre inverse des clés étrangères. Les deux PDF, eux, sont
/// **conservés** : ce sont les livrables de contrôle humain.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const marqueur = 'd4-facture';
  const auteur = AuteurEdition(nom: 'Céline AGBODJAN', role: 'Comptable');
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
      "VALUES ('$marqueur-u', '$marqueur-cat', 'D4-BNG-01', 'libre')",
    );
    await db.customStatement(
      'INSERT OR REPLACE INTO clients_local '
      '(id, nom, telephone, type_client) '
      "VALUES ('$marqueur-cli', 'KORA', '+229 01 00 00 00 04', 'particulier')",
    );
    // Six nuits à 28 000 F.
    await db.customStatement(
      'INSERT OR REPLACE INTO reservations_local '
      '(id, reference, client_id, unite_id, date_arrivee, date_depart, '
      ' statut, tarif_nuit, acompte, statut_sync, date_creation_locale) '
      "VALUES ('$marqueur-res', 'LOC-D4', '$marqueur-cli', '$marqueur-u', "
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
    expect(Platform.isWindows, isTrue, reason: 'à lancer avec -d windows');
  });

  late PieceFacturation piece;

  testWidgets('une facture de séjour est émise dans la base réelle', (
    tester,
  ) async {
    final db = AppDatabase();
    final depotPanier = PanierRepositoryLocal(PanierDao(db));
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
      ReservationDao(db),
    ).parId('$marqueur-res'))!;

    piece = await Facturer(
      FactureRepositoryLocal(FactureDao(db)),
    ).emettrePourSejour(panier: cloture, reservation: reservation);
    await db.close();

    expect(piece.montantTotal, 170000);
    expect(piece.estCertifiee, isFalse);
  });

  testWidgets(
    'CRITÈRE D4 — le logo est réellement EMBARQUÉ dans l’application',
    (tester) async {
      // Un asset déclaré au `pubspec.yaml` mais absent du paquet ne lève pas :
      // il rend une facture sans logo, ce qu'aucun test de composition ne
      // verrait. Seule l'application compilée peut répondre.
      final donnees = await rootBundle.load(AppAssets.logo);

      expect(donnees.lengthInBytes, greaterThan(1000));
      // Un PNG commence par 89 50 4E 47 (« .PNG ») — le logo du PO depuis le
      // 14/10/2026 (D392). Le vérifier évite de valider un fichier vide qui
      // aurait l'air d'un succès.
      final octets = donnees.buffer.asUint8List();
      expect(octets.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    },
  );

  testWidgets(
    'CRITÈRE D4 — la facture A4 composée ne perd AUCUN caractère, et sort en '
    'PDF',
    (tester) async {
      final logo = (await rootBundle.load(AppAssets.logo)).buffer.asUint8List();

      final a4 = FactureA4.composer(
        piece,
        auteur: auteur,
        dateEdition: DateTime.now(),
        entete: const EnteteEtablissement().avecLogo(logo),
      );

      // Le garde-fou porte sur le document EFFECTIVEMENT composé.
      for (final texte in a4.textes) {
        expect(
          caracteresNonImprimables(texte),
          isEmpty,
          reason: 'ces caractères disparaîtraient en silence : « $texte »',
        );
      }

      // ⚠ Q3 — hébergement et consommations restent nommés séparément.
      expect(a4.recapitulatif.map((r) => r.$1), [
        'Hébergement',
        'Consommations',
      ]);
      expect(a4.recapitulatif[0].$2, '168 000 F');
      expect(a4.recapitulatif[1].$2, '2 000 F');

      // ⚠ Aucun cachet fiscal n'est fabriqué, et le filigrane est dérivé.
      expect(a4.texteBrut, contains('Emplacement réservé'));
      expect(a4.filigrane, CertificationMecef.filigraneDemonstration);
      // ⚠ Aucun identifiant fiscal d'exemple n'atteint le papier.
      expect(a4.texteBrut, isNot(contains('IFU')));
      expect(a4.texteBrut, isNot(contains('Ex.')));

      final octets = await a4.pdf();
      expect(String.fromCharCodes(octets.take(4)), '%PDF');
      expect(octets.length, greaterThan(8000), reason: 'le logo doit y être');

      // Le fichier est CONSERVÉ : c'est la pièce de D4 qu'un humain peut
      // ouvrir, imprimer et regarder. La mise en page ne se juge que là.
      final dossier = await getApplicationDocumentsDirectory();
      final sortie = File(
        p.join(dossier.path, 'tatacora-facture-a4-d4-${piece.numero}.pdf'),
      );
      await sortie.writeAsBytes(octets);
      expect(sortie.existsSync(), isTrue);
      // ignore: avoid_print
      print('Facture A4 D4 écrite pour contrôle humain : ${sortie.path}');
    },
  );

  testWidgets(
    'LIVRABLE D4 — la planche d’essai QR est écrite pour la thermique',
    (tester) async {
      // La question est physique : un QR sort-il lisible d'une thermique
      // 80 mm ? Ce test ne peut pas y répondre — il fabrique l'objet qui
      // permettra d'y répondre, et il vérifie que son contenu ne peut être
      // confondu avec aucun cachet fiscal.
      final planche = EssaiQrThermique.composer();

      for (final contenu in planche.contenus) {
        expect(contenu, startsWith('TATACORA-ESSAI-QR-'));
      }
      for (final texte in planche.textes) {
        expect(caracteresNonImprimables(texte), isEmpty, reason: texte);
      }

      final octets = await planche.pdf();
      expect(String.fromCharCodes(octets.take(4)), '%PDF');

      final dossier = await getApplicationDocumentsDirectory();
      final sortie = File(
        p.join(dossier.path, 'tatacora-essai-qr-thermique-d4.pdf'),
      );
      await sortie.writeAsBytes(octets);
      expect(sortie.existsSync(), isTrue);
      // ignore: avoid_print
      print(
        'Planche d’essai QR écrite pour contrôle humain : ${sortie.path} — '
        'à imprimer sur le rouleau du comptoir, puis à scanner carré par '
        'carré, du plus petit au plus grand.',
      );
    },
  );

  testWidgets('l’édition A4 n’écrit RIEN en base, et ne consomme aucun numéro', (
    tester,
  ) async {
    // Une facture A4 est un RENDU : le registre et la séquence sont uniques et
    // appartiennent à la pièce. Si l'édition avait touché la séquence, le
    // ticket et la facture porteraient deux numéros pour une seule vente.
    final db = AppDatabase();
    final depot = FactureRepositoryLocal(FactureDao(db));

    // On LIT le compteur, on ne l'appelle pas. `numeroSuivant()` alloue et
    // persiste — c'est un consommateur, pas une lecture. L'appeler pour
    // « constater » l'état brûlait deux numéros à chaque exécution, sur la base
    // réelle du poste, dans le test même qui affirme qu'aucun numéro n'est
    // consommé. L'assertion ne pouvait alors JAMAIS passer, et sa seule façon
    // d'échouer était la bonne raison pour un mauvais motif.
    Future<int> compteur() async {
      final ligne = await db
          .customSelect(
            'SELECT COALESCE(MAX(dernier_numero), 0) AS n '
            'FROM sequences_facture_local',
          )
          .getSingle();
      return ligne.data['n'] as int;
    }

    final avant = await compteur();

    // Sans cette garde, `avant == apres == 0` passerait au vert sur une base
    // où aucune facture n'aurait jamais été émise — l'assertion comparerait
    // deux zéros et ne prouverait rien. Une facture a été émise plus haut dans
    // ce fichier : le compteur DOIT avoir avancé.
    expect(
      avant,
      greaterThan(0),
      reason: 'compteur à zéro : la comparaison qui suit ne vérifierait rien',
    );

    await FactureA4.composer(
      piece,
      auteur: auteur,
      dateEdition: DateTime.now(),
    ).pdf();
    final apres = await compteur();

    expect(apres, avant, reason: 'aucun numéro n’a été consommé par un rendu');
    expect((await depot.parId(piece.id))!.numero, piece.numero);
    await db.close();
  });
}
