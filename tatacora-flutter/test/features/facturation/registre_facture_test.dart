import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/facturation/data/facture_dao.dart';
import 'package:tatacora_flutter/features/facturation/data/facture_repository_local.dart';
import 'package:tatacora_flutter/features/facturation/domain/certification_mecef.dart';
import 'package:tatacora_flutter/features/facturation/domain/entities/piece_facturation.dart';
import 'package:tatacora_flutter/features/facturation/domain/repositories/facture_repository.dart';
import 'package:tatacora_flutter/features/facturation/domain/usecases/facturer.dart';

/// **Les RÈGLES du registre de facturation, rejouées en Dart — avec leurs
/// raisons, pas seulement leur code.**
///
/// Elles venaient des 36 assertions de la suite `t-facture.js` de l'ancien
/// prototype, archivé depuis PA-183. Elles vivent aujourd'hui dans ce client
/// (`FactureDao`, registre local) et, côté serveur, dans
/// `app/Domain/Facturation/Services/EmissionFactureService.php`.
///
/// Quatre propriétés y sont figées, parce que **chacune se trompe en silence** :
///
///  - la séquence de numéros ne saute pas et ne se répète jamais ;
///  - les lignes copiées ne bougent pas quand la carte change ;
///  - une facture émise est immuable — on l'annule par avoir, on ne l'efface
///    pas ;
///  - aucune facture ne se déclare certifiée MECeF tant qu'elle ne l'est pas.
///
/// La dernière est la plus importante : c'est **PA-61** transposé. Afficher
/// « certifiée » sur une facture de démonstration serait affirmer une
/// certification fiscale qui n'a pas eu lieu.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late FactureDao dao;
  late FactureRepository depot;
  late Facturer facturer;

  /// Horloge figée : l'année fait partie du numéro de pièce, et un test qui
  /// dépend de l'horloge réelle change de résultat le 1er janvier.
  const annee = 2026;
  DateTime maintenant() => DateTime(annee, 8, 20, 14, 30);

  /// Semis minimal, et il n'est **pas décoratif** : `reservationId` et
  /// `panierId` sont de vraies clés étrangères. Une pièce désignant une
  /// réservation qui n'existe pas est refusée par la base — c'est ce qui
  /// distingue une provenance d'un champ libre (le défaut PA-76).
  Future<void> semer() async {
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
        .into(db.reservationsLocal)
        .insert(
          ReservationsLocalCompanion.insert(
            id: 'r1',
            reference: 'LOC-R1',
            clientId: 'cli-1',
            uniteId: 'u-1',
            dateArrivee: DateTime.utc(2026, 8, 18),
            dateDepart: DateTime.utc(2026, 8, 24),
            statut: 'confirmee',
            tarifNuit: 28000,
          ),
        );
    await db
        .into(db.paniersLocal)
        .insert(
          PaniersLocalCompanion.insert(
            id: 'pan1',
            typeVente: 'sur_sejour',
            reservationId: const Value('r1'),
          ),
        );
  }

  setUp(() async {
    db = AppDatabase.enMemoire();
    dao = FactureDao(db, maintenant: maintenant);
    depot = FactureRepositoryLocal(dao);
    facturer = Facturer(depot);
    await semer();
  });

  tearDown(() => db.close());

  BrouillonFacture venteComptant() => const BrouillonFacture(
    origine: OrigineFacture.posComptant,
    modePaiement: 'especes',
    lignes: [
      LigneBrouillon(
        module: ModuleFacturable.m5Bar,
        libelle: 'Béninoise 33cl',
        prixUnitaire: 1000,
        quantite: 2,
        codeArticle: 'bsn-33',
      ),
      LigneBrouillon(
        module: ModuleFacturable.m4Restaurant,
        libelle: 'Poulet braisé',
        prixUnitaire: 4500,
        quantite: 1,
        codeArticle: 'plat-poulet',
      ),
    ],
  );

  BrouillonFacture sejour() => const BrouillonFacture(
    origine: OrigineFacture.posSejour,
    reservationId: 'r1',
    panierId: 'pan1',
    clientNom: 'KORA',
    lignes: [
      LigneBrouillon(
        module: ModuleFacturable.m9Tourisme,
        libelle: 'Circuit Tata',
        prixUnitaire: 5000,
        quantite: 2,
        codeArticle: 'cir-1',
      ),
    ],
  );

  /* ================================================================== */
  group('Un seul registre, trois origines', () {
    test('trois origines déclarées, et le registre est fermé', () {
      // Le prototype vérifie `Object.keys(F.ORIGINES).length === 3`. En Dart
      // l'enum ferme le registre au type ; ce qui reste à éprouver, c'est que
      // la lecture d'un code inconnu LÈVE au lieu de retomber sur une valeur.
      expect(OrigineFacture.values, hasLength(3));
      expect(
        () => OrigineFacture.depuisCode('inconnue'),
        throwsA(isA<ArgumentError>()),
        reason:
            'retomber sur `pos_comptant` rangerait une facture de séjour parmi '
            'les ventes de passage : le chiffre du comptoir serait faux et la '
            'créance du client invisible',
      );
    });

    test('les deux origines vivent dans le MÊME registre', () async {
      await depot.emettre(venteComptant());
      await depot.emettre(sejour());

      expect(await depot.pieces(), hasLength(2));
    });

    test('le filtre est une colonne, pas un entrepôt', () async {
      await depot.emettre(venteComptant());
      await depot.emettre(sejour());

      expect(
        await depot.pieces(origine: OrigineFacture.posComptant),
        hasLength(1),
      );
      expect(
        await depot.pieces(origine: OrigineFacture.posSejour),
        hasLength(1),
      );
    });

    test('une pièce vide est refusée', () async {
      // Le prototype : « une facture sans ligne ne peut pas être émise ».
      await expectLater(
        depot.emettre(
          const BrouillonFacture(
            origine: OrigineFacture.posComptant,
            lignes: [],
          ),
        ),
        throwsA(isA<FactureSansLigne>()),
      );
      expect(await depot.pieces(), isEmpty);
    });
  });

  /* ================================================================== */
  group('Séquence de numéros — unique, toutes origines confondues', () {
    test('deux pièces n’ont jamais le même numéro', () async {
      final a = await depot.emettre(venteComptant());
      final b = await depot.emettre(sejour());

      expect(a.numero, isNot(b.numero));
      expect(a.numero, 'F-$annee-00001');
      expect(
        b.numero,
        'F-$annee-00002',
        reason: 'la séquence est unique MALGRÉ une origine différente',
      );
    });

    test(
      'registre vidé, le compteur ne repart PAS à 1 — le point qui compte',
      () async {
        // Le compteur est persisté **séparément** de la liste. Le déduire du
        // nombre de pièces réattribuerait un numéro déjà utilisé dès qu'une
        // pièce serait archivée ou purgée — et un numéro de pièce ne se
        // réemploie jamais, même si la pièce disparaît.
        //
        // La purge se fait ici en SQL brut, et c'est délibéré : le dépôt
        // n'expose AUCUNE suppression. On simule l'archivage ou la reprise de
        // données qui, un jour, videra la table.
        await depot.emettre(venteComptant());
        await depot.emettre(sejour());

        await db.customStatement('DELETE FROM lignes_piece_facturation_local');
        await db.customStatement('DELETE FROM pieces_facturation_local');
        expect(await depot.pieces(), isEmpty);

        final c = await depot.emettre(venteComptant());
        expect(c.numero, 'F-$annee-00003');
      },
    );

    test('le compteur vit dans une table à part, et il l’a retenu', () async {
      await depot.emettre(venteComptant());
      await depot.emettre(sejour());

      final sequence = await db.select(db.sequencesFactureLocal).getSingle();
      expect(sequence.annee, annee);
      expect(sequence.dernierNumero, 2);
    });

    test('la base REFUSE deux pièces au même numéro', () async {
      // La garantie tient en base, pas seulement dans le code : c'est ce qui
      // rend impossible de désigner deux pièces par le même numéro, ce qu'un
      // contrôle fiscal demande précisément de faire.
      final a = await depot.emettre(venteComptant());

      await expectLater(
        db.customStatement(
          'INSERT INTO pieces_facturation_local '
          '(id, numero, origine, date_emission, client_nom, statut, '
          ' statut_transmission) '
          "VALUES ('doublon', '${a.numero}', 'pos_comptant', 0, 'X', "
          "'emise', 'non_transmissible')",
        ),
        throwsA(anything),
      );
    });
  });

  /* ================================================================== */
  group('Les lignes sont COPIÉES, jamais référencées', () {
    test(
      'la pièce relue porte le nom et le prix du jour de l’émission',
      () async {
        // *Une facture qui change est une facture fausse.* Le prototype mute la
        // source après coup ; en Dart les entités sont immuables, alors on éprouve
        // la propriété là où elle peut réellement être enfreinte : la relecture
        // ne joint AUCUN catalogue.
        final f = await depot.emettre(venteComptant());

        // La carte change : le libellé et le prix de l'article bougent au
        // catalogue du bar. La facture, elle, ne doit pas bouger.
        await db
            .into(db.cartesBoissonLocal)
            .insert(
              CartesBoissonLocalCompanion.insert(
                id: 'bsn-33',
                articleId: 'art-bsn',
                libelle: 'Béninoise 33cl — NOUVEAU NOM',
                categorie: 'locale',
                prixVente: 99999,
              ),
            );

        final relue = (await depot.parId(f.id))!;
        expect(relue.lignes.first.libelle, 'Béninoise 33cl');
        expect(relue.lignes.first.prixUnitaire, 1000);
        expect(
          relue.montantTotal,
          6500,
          reason: 'le total reste celui remis au client',
        );
      },
    );

    test('le montant de ligne est CALCULÉ, jamais stocké', () async {
      final f = await depot.emettre(venteComptant());

      for (final l in f.lignes) {
        expect(l.montant, l.prixUnitaire * l.quantite);
      }
      expect(f.montantTotal, 6500);
    });

    test('l’ordre des lignes ne dépend pas du plan d’exécution', () async {
      // Deux impressions de la même pièce doivent sortir identiques.
      final f = await depot.emettre(venteComptant());
      final relue = (await depot.parId(f.id))!;

      expect(relue.lignes.map((l) => l.libelle).toList(), [
        'Béninoise 33cl',
        'Poulet braisé',
      ]);
      expect(relue.lignes.map((l) => l.ordre).toList(), [0, 1]);
    });
  });

  /* ================================================================== */
  group('Le module voyage avec la ligne', () {
    test('bar et restaurant coexistent, chacun identifié', () async {
      final f = await depot.emettre(venteComptant());

      expect(f.lignes[0].module, ModuleFacturable.m5Bar);
      expect(f.lignes[1].module, ModuleFacturable.m4Restaurant);
      expect(f.ventilation, {
        ModuleFacturable.m5Bar: 2000,
        ModuleFacturable.m4Restaurant: 4500,
      });
    });

    test('le filtre par activité trouve — et ne trouve pas', () async {
      await depot.emettre(venteComptant());

      expect(
        await depot.pieces(module: ModuleFacturable.m4Restaurant),
        hasLength(1),
      );
      expect(
        await depot.pieces(module: ModuleFacturable.m9Tourisme),
        isEmpty,
        reason: 'la facture ne porte aucune ligne de tourisme',
      );
    });

    test('un code de module inconnu en base LÈVE à la lecture', () async {
      // Retomber sur M5 par défaut ferait apparaître une prestation de
      // tourisme dans le chiffre du bar, sans que rien ne le signale.
      final f = await depot.emettre(venteComptant());
      await db.customStatement(
        "UPDATE lignes_piece_facturation_local SET module_source = 'M42' "
        "WHERE piece_id = '${f.id}'",
      );

      await expectLater(depot.parId(f.id), throwsA(isA<ArgumentError>()));
    });
  });

  /* ================================================================== */
  group('Annulation : par AVOIR, jamais par effacement', () {
    test('un motif vide est refusé', () async {
      final g = await depot.emettre(venteComptant());

      await expectLater(
        depot.annuler(g.id, '  '),
        throwsA(isA<MotifAnnulationRequis>()),
      );
      expect((await depot.parId(g.id))!.statut, StatutPiece.emise);
    });

    test(
      'la facture d’origine EXISTE toujours, et son montant aussi',
      () async {
        final g = await depot.emettre(venteComptant());
        await depot.annuler(g.id, 'Erreur de saisie');

        final relue = await depot.parId(g.id);
        expect(relue, isNotNull, reason: 'rien n’a été effacé');
        expect(relue!.statut, StatutPiece.annulee);
        expect(relue.motifAnnulation, 'Erreur de saisie');
        expect(
          relue.montantTotal,
          6500,
          reason: 'son montant n’a pas été effacé',
        );
      },
    );

    test('l’avoir porte le montant inverse, et son PROPRE numéro', () async {
      final g = await depot.emettre(venteComptant());
      final r = await depot.annuler(g.id, 'Erreur de saisie');

      expect(r.avoir.montantTotal, -6500);
      expect(
        r.avoir.avoirDe,
        g.numero,
        reason: 'l’avoir désigne la pièce qu’il neutralise',
      );
      expect(r.avoir.numero, isNot(g.numero));
      expect(r.avoir.numero, 'F-$annee-00002');
      expect(
        r.avoir.statut,
        StatutPiece.emise,
        reason: 'un avoir est une pièce vivante, pas une annotation',
      );
    });

    test(
      'l’invariant montant = prix × quantité tient sur l’avoir aussi',
      () async {
        // Divergence assumée avec le prototype, qui garde une quantité positive
        // à côté d'un montant négatif : sa ligne d'avoir contredit alors le
        // produit de ses deux facteurs.
        final g = await depot.emettre(venteComptant());
        final r = await depot.annuler(g.id, 'Erreur de saisie');

        for (final l in r.avoir.lignes) {
          expect(l.montant, l.prixUnitaire * l.quantite);
          expect(l.quantite, isNegative);
        }
      },
    );

    test('deux pièces au registre : l’originale et l’avoir', () async {
      final g = await depot.emettre(venteComptant());
      await depot.annuler(g.id, 'Erreur de saisie');

      expect(await depot.pieces(), hasLength(2));
    });

    test('une facture déjà annulée ne se réannule pas', () async {
      final g = await depot.emettre(venteComptant());
      await depot.annuler(g.id, 'Erreur de saisie');

      await expectLater(
        depot.annuler(g.id, 'encore'),
        throwsA(isA<FactureDejaAnnulee>()),
      );
      expect(
        await depot.pieces(),
        hasLength(2),
        reason: 'aucun second avoir n’a été émis',
      );
    });

    test('un avoir ne s’annule pas — il est déjà la correction', () async {
      final g = await depot.emettre(venteComptant());
      final r = await depot.annuler(g.id, 'Erreur de saisie');

      await expectLater(
        depot.annuler(r.avoir.id, 'annuler l’avoir'),
        throwsA(isA<AvoirNonAnnulable>()),
      );
    });

    test('une pièce inexistante ne s’annule pas', () async {
      await expectLater(
        depot.annuler('fantome', 'motif'),
        throwsA(isA<PieceIntrouvable>()),
      );
    });

    test('la base REFUSE un avoir désignant une pièce inexistante', () async {
      // La clé étrangère vise `numero`, et `PRAGMA foreign_keys` est actif :
      // un avoir orphelin ne se crée pas, même en SQL brut.
      await expectLater(
        db.customStatement(
          'INSERT INTO pieces_facturation_local '
          '(id, numero, origine, date_emission, client_nom, statut, '
          ' avoir_de, statut_transmission) '
          "VALUES ('orphelin', 'F-$annee-09999', 'pos_comptant', 0, 'X', "
          "'emise', 'F-$annee-00404', 'non_transmissible')",
        ),
        throwsA(anything),
      );
    });
  });

  /* ================================================================== */
  group('MECeF : aucune pièce ne se déclare certifiée (PA-61)', () {
    test('aucun numéro MECeF à l’émission, donc pas certifiée', () async {
      final h = await depot.emettre(venteComptant());

      expect(h.numeroMecef, isNull);
      expect(h.estCertifiee, isFalse);
      expect(h.libelleCertification, 'MECeF — non certifiée, démonstration');
    });

    test('un numéro de DÉMONSTRATION ne compte PAS comme certification', () {
      // Le piège exact : `MecefClientFake` produit `MECEF-DEMO-XXXXXXXX`. Le
      // jour de l'inscription DGI — celui où l'on cesse de se méfier — un
      // prédicat qui se contenterait de « un numéro existe » passerait au vert
      // pendant que toutes les pièces partiraient en démonstration.
      expect(CertificationMecef.estReelle('MECEF-DEMO-A1B2C3D4'), isFalse);
      expect(CertificationMecef.estReelle('mecef-demo-a1b2c3d4'), isFalse);
      expect(
        CertificationMecef.estReelle('DONNEES-NON-CERTIFIEES-DEMO'),
        isFalse,
      );
    });

    test('seul un vrai numéro certifie', () {
      expect(CertificationMecef.estReelle('MECEF-REEL-0000123'), isTrue);
      expect(
        CertificationMecef.libelle('MECEF-REEL-0000123'),
        'MECeF MECEF-REEL-0000123',
      );
    });

    test('ni le vide ni l’espace ne certifient', () {
      expect(CertificationMecef.estReelle(null), isFalse);
      expect(CertificationMecef.estReelle(''), isFalse);
      expect(CertificationMecef.estReelle('   '), isFalse);
    });

    test('une pièce relue depuis la base reste non certifiée', () async {
      final h = await depot.emettre(venteComptant());
      final relue = (await depot.parId(h.id))!;

      expect(relue.estCertifiee, isFalse);
    });
  });

  /* ================================================================== */
  group('Retrouver la facture d’un séjour', () {
    test('aucune facture : rien à proposer au téléchargement', () async {
      expect(await depot.facturePourReservation('r1'), isNull);
    });

    test('une fois émise, elle est retrouvable', () async {
      final i = await depot.emettre(sejour());

      expect((await depot.facturePourReservation('r1'))!.id, i.id);
    });

    test('⚠ annulée, elle ne se propose plus — ET l’AVOIR non plus', () async {
      // **Le piège précis de ce module.** L'avoir porte le MÊME
      // `reservationId` et le statut `emise`. Sans l'exclusion des avoirs, on
      // proposerait au client un document à montant NÉGATIF à la place de sa
      // facture.
      final i = await depot.emettre(sejour());
      final r = await depot.annuler(i.id, 'test');

      expect(
        r.avoir.reservationId,
        'r1',
        reason: 'l’avoir porte bien le même séjour',
      );
      expect(r.avoir.statut, StatutPiece.emise, reason: 'et le même statut');

      final proposee = await depot.facturePourReservation('r1');
      expect(proposee, isNull);
    });

    test('la même garde vaut pour le panier', () async {
      // Elle sert d'idempotence à l'émission : sans elle, un second appui sur
      // « Clôturer et facturer » émettrait une seconde pièce numérotée.
      final i = await depot.emettre(sejour());
      expect((await depot.facturePourPanier('pan1'))!.id, i.id);

      await depot.annuler(i.id, 'test');
      expect(await depot.facturePourPanier('pan1'), isNull);
    });
  });

  /* ================================================================== */
  group('Indicateurs', () {
    test('trois pièces : deux factures et un avoir', () async {
      await depot.emettre(venteComptant());
      final j = await depot.emettre(sejour());
      await depot.annuler(j.id, 'test');

      final k = await KpisFacturation.calculer(depot);
      expect(k.pieces, 3);
      expect(k.annulees, 1);
      expect(k.avoirs, 1);
      expect(k.factures, 1, reason: 'la facture annulée n’en est plus une');
      expect(
        k.certifiees,
        0,
        reason: 'aucune certifiée — c’est la vérité du prototype, et la nôtre',
      );
    });

    test(
      '⚠ le montant net ne déduit l’annulation QU’UNE FOIS — le prototype la '
      'déduit deux fois',
      () async {
        // **Défaut trouvé dans `facture-engine.js` en le portant.** Son KPI
        // `montant` filtre sur `statut === EMISE` : la facture annulée sort du
        // total ET son avoir y entre, donc le montant est retiré deux fois. Sur
        // ce jeu exact, le prototype rend -3 500 F au lieu de 6 500 F. Aucune
        // assertion de `t-facture.js` ne couvre ce champ, ce qui explique qu'il
        // ait tenu.
        //
        // La somme juste porte sur TOUTES les pièces : c'est ce que veut dire
        // « corriger par contre-passation » — l'avoir neutralise l'original
        // arithmétiquement, et le statut `annulee` n'est qu'une étiquette.
        await depot.emettre(venteComptant()); // +6 500
        final j = await depot.emettre(sejour()); // +10 000
        await depot.annuler(j.id, 'test'); // -10 000

        final k = await KpisFacturation.calculer(depot);
        expect(
          k.montantNet,
          6500,
          reason: 'seuls les 6 500 F du comptoir ont réellement été encaissés',
        );
        expect(
          k.montantNet,
          isNot(-3500),
          reason: 'le -3 500 F est exactement le résultat du prototype',
        );
      },
    );

    test('une facture annulée ET son avoir pèsent zéro, ensemble', () async {
      final j = await depot.emettre(sejour());
      await depot.annuler(j.id, 'test');

      final k = await KpisFacturation.calculer(depot);
      expect(k.montantNet, 0);
    });
  });

  /* ================================================================== */
  group('Le cas d’usage refuse ce qu’il ne peut pas justifier', () {
    test('une facture directe s’émet sans panier ni séjour', () async {
      final f = await facturer.emettreDirecte(
        clientNom: 'MAIRIE DE NATITINGOU',
        lignes: const [
          LigneBrouillon(
            module: ModuleFacturable.m9Tourisme,
            libelle: 'Circuit groupe',
            prixUnitaire: 4500,
            quantite: 12,
          ),
        ],
      );

      expect(f.origine, OrigineFacture.factureDirecte);
      expect(f.montantTotal, 54000);
      expect(f.panierId, isNull);
    });
  });
}
