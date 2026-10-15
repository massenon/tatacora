import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/hebergement/data/reservation_dao.dart';
import 'package:tatacora_flutter/features/hebergement/data/reservation_repository_local.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/periode_sejour.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/reservation.dart';
import 'retour_arriere_schema.dart';

/// Cycle de vie de la base **sur fichier** — les deux chemins que la base en
/// mémoire ne peut pas éprouver.
///
/// ## Pourquoi ces tests existent
///
/// Le rapport du Sprint 1 portait le critère 2 — « la réservation survit à la
/// fermeture de l'application » — comme **non vérifié**, et la migration
/// `v1 → v2` n'avait **jamais été exécutée** : `onCreate` s'exécute à chaque
/// test en mémoire, `onUpgrade` jamais.
///
/// Or c'est le chemin de la **mise à jour d'application**. S'il est faux, un
/// utilisateur qui met à jour perd ses saisies hors ligne — la seule donnée qui
/// n'existe nulle part ailleurs — et personne ne s'en aperçoit avant que le
/// client ne se présente avec une confirmation introuvable.
///
/// Ce que ces tests ne couvrent toujours pas : l'arrêt **brutal** du processus
/// par le système d'exploitation. Cela demande un appareil.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory dossier;
  late File fichier;

  setUp(() async {
    dossier = await Directory.systemTemp.createTemp('tatacora_cycle_');
    fichier = File('${dossier.path}/tatacora.sqlite');
  });

  tearDown(() async {
    // Sous Windows, le fichier reste verrouillé un court instant après la
    // fermeture. Un échec de ménage ne doit pas faire rougir un test dont
    // l'assertion a réussi — le dossier est temporaire, le système le reprendra.
    try {
      if (dossier.existsSync()) await dossier.delete(recursive: true);
    } on FileSystemException {
      // sans conséquence
    }
  });

  Future<void> semer(AppDatabase db) async {
    await db
        .into(db.categoriesHebergementLocal)
        .insert(
          CategoriesHebergementLocalCompanion.insert(
            id: 'cat-1',
            libelle: 'Bungalow',
            capaciteMax: 2,
            tarifBase: 28000,
          ),
        );
    await db
        .into(db.unitesHebergementLocal)
        .insert(
          UnitesHebergementLocalCompanion.insert(
            id: 'u-1',
            categorieId: 'cat-1',
            numero: 'BNG-01',
            statut: 'libre',
          ),
        );
    await db
        .into(db.clientsLocal)
        .insert(
          ClientsLocalCompanion.insert(
            id: 'cli-1',
            nom: 'KORA',
            telephone: '+229 01 00 00 00 01',
            typeClient: 'particulier',
          ),
        );
  }

  Reservation reservation(String id) => Reservation(
    id: id,
    reference: 'LOC-$id',
    clientId: 'cli-1',
    clientNom: 'KORA',
    uniteId: 'u-1',
    periode: PeriodeSejour(
      arrivee: DateTime.now().add(const Duration(days: 10)),
      depart: DateTime.now().add(const Duration(days: 12)),
    ),
    tarifNuit: 28000,
    statut: StatutReservation.enAttente,
    statutSynchronisation: StatutSynchronisation.local,
    creeeLe: DateTime.now(),
  );

  /* ================================================================== */
  group('Critère 2 — la saisie survit à la fermeture', () {
    test('une réservation écrite puis relue après réouverture', () async {
      // Session 1 : l'application tourne, le réceptionniste saisit hors ligne.
      final premiere = AppDatabase.surFichier(fichier);
      await semer(premiere);
      final depot = ReservationRepositoryLocal(ReservationDao(premiere));
      await depot.enregistrer(reservation('res-1'));
      await premiere.close();

      // Le fichier existe sur le disque, indépendamment du processus.
      expect(fichier.existsSync(), isTrue);
      expect(fichier.lengthSync(), greaterThan(0));

      // Session 2 : l'application est relancée.
      final seconde = AppDatabase.surFichier(fichier);
      final relue = await ReservationRepositoryLocal(
        ReservationDao(seconde),
      ).parId('res-1');

      expect(relue, isNotNull, reason: 'la saisie hors ligne a survécu');
      expect(relue!.montantTotal, 56000);
      expect(relue.statutSynchronisation, StatutSynchronisation.local);
      await seconde.close();
    });

    test('l’opération de synchronisation survit elle aussi', () async {
      // Sans elle, la réservation existerait localement sans que rien ne la
      // pousse jamais au serveur : perdue sans erreur.
      final premiere = AppDatabase.surFichier(fichier);
      await semer(premiere);
      await ReservationRepositoryLocal(
        ReservationDao(premiere),
      ).enregistrer(reservation('res-2'));
      await premiere.close();

      // ⚠ Ce cas relisait la FILE après réouverture du fichier : l'entrée
      // devait y être, en attente, sans quoi la réservation n'aurait jamais
      // été poussée — perdue sans erreur. La file a disparu le 14/09/2026
      // (zéro réseau), mais la garantie qu'elle servait à prouver demeure, et
      // c'est la plus importante du poste : **ce qui a été saisi est encore là
      // quand on rouvre le fichier**.
      final seconde = AppDatabase.surFichier(fichier);
      final apres = await seconde.select(seconde.reservationsLocal).get();
      expect(apres.map((r) => r.id), contains('res-2'));
      expect(
        apres.firstWhere((r) => r.id == 'res-2').statutSync,
        StatutSynchronisation.local.code,
      );
      await seconde.close();
    });

    test('le fichier est réutilisé, pas recréé', () async {
      final premiere = AppDatabase.surFichier(fichier);
      await semer(premiere);
      await premiere.close();
      final tailleApresSemis = fichier.lengthSync();

      final seconde = AppDatabase.surFichier(fichier);
      // Une lecture suffit à déclencher l'ouverture réelle.
      expect(
        await seconde.select(seconde.unitesHebergementLocal).get(),
        hasLength(1),
      );
      await seconde.close();

      // Un `createAll` sur une base existante viderait ou dupliquerait : la
      // taille effondrée serait le signe d'un fichier repris à zéro.
      expect(fichier.lengthSync(), greaterThanOrEqualTo(tailleApresSemis));
    });
  });

  /* ================================================================== */
  group('Migration v1 → v2 — le chemin de la mise à jour', () {
    /// Ramène un fichier v2 à l'état v1 : les quatre colonnes du schéma v2
    /// sont retirées et `user_version` remis à 1.
    ///
    /// C'est plus fidèle que de recréer une v1 à la main — le reste du schéma
    /// est celui que Drift produit réellement, pas une transcription.
    /// [avecLigne] insère une réservation au format v1 **après** le retrait des
    /// colonnes. L'ordre compte : rouvrir `AppDatabase` déclenche `onUpgrade`
    /// aussitôt, on ne peut donc pas insérer une ligne v1 depuis une seconde
    /// ouverture. C'est ce détail de mise en scène qui rend le test fidèle —
    /// et c'est en le corrigeant que le défaut de la migration est apparu.
    Future<void> ramenerEnV1(File f, {bool avecLigne = false}) async {
      final db = AppDatabase.surFichier(f);
      await ramenerSchemaA(db, 1);

      if (avecLigne) {
        await db.customStatement(
          'INSERT INTO reservations_local '
          '(id, client_id, unite_id, date_arrivee, date_depart, statut, '
          ' acompte, statut_sync, date_creation_locale) '
          "VALUES ('res-v1', 'cli-1', 'u-1', 1800000000, 1800172800, "
          "'confirmee', 0, 'synchronise', 1800000000)",
        );
      }

      await db.close();
    }

    test('les quatre colonnes sont ajoutées à l’ouverture', () async {
      await ramenerEnV1(fichier);

      final db = AppDatabase.surFichier(fichier);
      final colonnes = await db
          .customSelect('PRAGMA table_info(reservations_local)')
          .get();
      final noms = colonnes.map((l) => l.data['name'] as String).toSet();

      expect(
        noms,
        containsAll(const [
          'reference',
          'tarif_nuit',
          'motif_rejet',
          'motif_annulation',
        ]),
      );
      await db.close();
    });

    test('les données existantes SURVIVENT à la migration', () async {
      // Le point qui compte. Recréer la table aurait été plus court à écrire et
      // aurait effacé les saisies hors ligne — la seule donnée qui n'existe
      // nulle part ailleurs.
      final prepare = AppDatabase.surFichier(fichier);
      await semer(prepare);
      await prepare.close();
      await ramenerEnV1(fichier, avecLigne: true);

      // Ouverture en v2 : `onUpgrade` s'exécute sur une table NON VIDE — le
      // seul cas qui compte, et celui qui plantait.
      final v2 = AppDatabase.surFichier(fichier);
      final lignes = await v2.select(v2.reservationsLocal).get();

      expect(lignes, hasLength(1), reason: 'la ligne v1 n’a pas été perdue');
      expect(lignes.single.id, 'res-v1');
      expect(lignes.single.statut, 'confirmee');
      await v2.close();
    });

    test('les lignes v1 ne sont PAS requalifiées en « local »', () async {
      final prepare = AppDatabase.surFichier(fichier);
      await semer(prepare);
      await prepare.close();
      await ramenerEnV1(fichier, avecLigne: true);

      final v2 = AppDatabase.surFichier(fichier);
      final ligne = await v2.select(v2.reservationsLocal).getSingle();

      // Elles viennent d'une version où `synchronise` signifiait « état
      // inconnu ». Les rejouer toutes créerait des doublons que rien ne
      // rattrape : le nouveau défaut ne vaut que pour les lignes à venir.
      expect(ligne.statutSync, 'synchronise');
      await v2.close();
    });

    // ⚠ UN CAS A ÉTÉ RETIRÉ ICI le 14/09/2026 : « la migration ne met RIEN en
    // file de synchronisation ». Il protégeait un vrai risque — une migration
    // qui aurait poussé les anciennes lignes au serveur aurait fait repartir
    // TOUT l'historique du poste à la première mise à jour. La décision
    // « zéro réseau » a supprimé la file (v10) : le risque n'existe plus,
    // faute de destination, et aucune autre table ne porte ce qu'il vérifiait.
  });

  /* ================================================================== */
  test('les clés étrangères sont actives sur fichier aussi', () async {
    // `PRAGMA foreign_keys = ON` est posé dans `beforeOpen`. Sous SQLite les
    // clés étrangères ne sont PAS actives par défaut, et sans cette ligne une
    // ligne de facture survit à sa facture.
    final db = AppDatabase.surFichier(fichier);
    final r = await db.customSelect('PRAGMA foreign_keys').getSingle();
    expect(r.data.values.first, 1);
    await db.close();
  });

  /* ================================================================== */
  group('Migration v8 → v9 — le préfixe des tables du restaurant', () {
    /// Le libellé d'une table est **stocké** à sa création. Changer le préfixe
    /// dans le code ne renomme donc rien : sans cette migration, un poste déjà
    /// en service afficherait « T1 » à côté d'un « R9 » créé après la mise à
    /// jour, et un serveur croirait à deux salles.
    test('les tables « T » deviennent « R », les autres espaces intacts', () async {
      // Une base v8 réelle, portant des tables au format d'avant.
      final avant = AppDatabase.surFichier(fichier);
      await avant.customStatement(
        'INSERT INTO tables_local (id, espace, numero, libelle, places, actif) '
        "VALUES ('t-1', 'restaurant', 1, 'T1', 4, 1), "
        "       ('t-12', 'restaurant', 12, 'T12', 4, 1), "
        "       ('j-1', 'jardin', 1, 'J1', 4, 1)",
      );
      await avant.customStatement('PRAGMA user_version = 8');
      await avant.close();

      // Rouvrir déclenche `onUpgrade` — le chemin qu'aucun test en mémoire
      // n'emprunte jamais (piège 2 du guide).
      final apres = AppDatabase.surFichier(fichier);
      final lignes = await apres
          .customSelect('SELECT id, libelle FROM tables_local ORDER BY id')
          .get();
      final parId = {
        for (final l in lignes) l.data['id'] as String: l.data['libelle'],
      };
      await apres.close();

      expect(parId['t-1'], 'R1');
      // Recomposé depuis `numero`, jamais obtenu en coupant l'ancienne chaîne :
      // un remplacement de caractère marcherait ici et casserait une table
      // renumérotée hors convention.
      expect(parId['t-12'], 'R12');
      // Les autres espaces ne sont pas touchés.
      expect(parId['j-1'], 'J1');
    });
  });
}
