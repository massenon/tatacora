import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/achats/data/achats_api.dart';
import 'package:tatacora_flutter/features/achats/data/achats_dao.dart';
import 'package:tatacora_flutter/features/achats/domain/entities/archivage_fournisseur.dart';
import 'package:tatacora_flutter/features/achats/domain/entities/bon_reception.dart';
import 'package:tatacora_flutter/features/achats/domain/entities/commande_achat.dart';
import 'package:tatacora_flutter/features/achats/domain/entities/fournisseur.dart';
import 'package:tatacora_flutter/features/achats/domain/messages_achats.dart';
import 'package:tatacora_flutter/features/stocks/data/stocks_dao.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/etat_stock.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/mouvement_stock.dart';
import 'package:tatacora_flutter/features/stocks/domain/messages_stock.dart';

/// M7 sur sa source LOCALE — par le chemin que l'écran emprunte :
/// `AchatsApi` -> `AchatsDao` -> `StocksDao` -> la base. Aucun faux : un test
/// qui simulerait le DAO ne dirait rien de ce que la base reçoit réellement
/// (piège 5).
void main() {
  late AppDatabase db;
  late StocksDao stocks;
  late AchatsApi api;
  var peutLire = true;
  var peutEcrire = true;
  // La règle d'archivage (`regle_archivage.dart`) est injectée : ce fichier
  // éprouve l'API, pas la règle (qui a son propre test).
  var peutArchiver = true;
  String? auteur = 'u-1';
  late DateTime horloge;

  setUp(() async {
    db = AppDatabase.enMemoire();
    peutLire = true;
    peutEcrire = true;
    peutArchiver = true;
    auteur = 'u-1';
    horloge = DateTime(2026, 10, 9, 8);

    await db
        .into(db.utilisateursLocal)
        .insert(
          UtilisateursLocalCompanion.insert(
            id: 'u-1',
            login: 'acheteur',
            nom: 'Aïcha',
            role: 'achats',
            droitsJson: '{}',
            sel: 's',
            empreinte: 'e',
            iterations: 1,
            dateCreation: DateTime(2026, 10, 1),
            dateMotDePasse: DateTime(2026, 10, 1),
          ),
        );

    // Chaque appel avance d'une minute : deux écritures n'ont jamais le même
    // instant, et l'ordre d'écriture est observable. Le jour reste le 9/10.
    DateTime tic() => horloge = horloge.add(const Duration(minutes: 1));
    stocks = StocksDao(db, maintenant: tic);
    api = AchatsApi(
      dao: AchatsDao(db, stocks: stocks, maintenant: tic),
      peutLire: () => peutLire,
      peutEcrire: () => peutEcrire,
      auteurId: () => auteur,
      peutArchiver: () async => peutArchiver,
    );
  });

  tearDown(() => db.close());

  /* -------------------------------------------------------------------- */
  /* Aides                                                                  */
  /* -------------------------------------------------------------------- */

  Future<void> tolerance(String? valeur) async {
    if (valeur == null) return;
    await db
        .into(db.parametresSystemeLocal)
        .insertOnConflictUpdate(
          ParametresSystemeLocalCompanion.insert(
            cle: 'tolerance_reception_pct',
            valeur: valeur,
            modifieLe: DateTime(2026, 10, 2),
          ),
        );
  }

  Future<String> point(String id, String libelle) async {
    await stocks.creerPoint(libelle: libelle, id: id);
    return id;
  }

  Future<void> article(
    String id,
    String libelle, {
    String unite = 'sac',
    SuiviArticle suivi = SuiviArticle.permanent,
  }) => stocks.creerArticle(
    id: id,
    libelle: libelle,
    categorie: 'Denrées',
    uniteMesure: unite,
    seuilCentiemes: 500,
    suivi: suivi,
    pointStockageId: null,
  );

  SaisieFournisseur saisieF(
    String id,
    String nom, {
    String? contact,
    String? evaluation,
  }) => SaisieFournisseur(
    id: id,
    raisonSociale: nom,
    contact: contact,
    categorie: null,
    conditionsPaiement: null,
    evaluationCode: evaluation,
  );

  Future<Fournisseur> fournisseur(
    String id,
    String nom, {
    String? contact,
    String? evaluation,
  }) async {
    final r = await api.enregistrerFournisseur(
      saisieF(id, nom, contact: contact, evaluation: evaluation),
      modification: false,
    );
    return (r as AchatsRecu<Fournisseur>).donnees;
  }

  LigneSaisieCommande ligne(
    String articleId,
    String quantite,
    String prix, {
    String libelle = 'ignoré',
  }) => LigneSaisieCommande(
    articleId: articleId,
    libelle: libelle,
    uniteMesure: 'ignorée',
    quantite: quantite,
    prixUnitaire: prix,
  );

  SaisieCommande saisieC(
    String fournisseurId,
    List<LigneSaisieCommande> lignes, {
    StatutCommande statut = StatutCommande.envoyee,
    String date = '2026-10-09',
  }) => SaisieCommande(
    fournisseurId: fournisseurId,
    dateCommande: date,
    statut: statut,
    lignes: lignes,
  );

  Future<CommandeAchatDetail> commande(
    String fournisseurId,
    List<LigneSaisieCommande> lignes, {
    StatutCommande statut = StatutCommande.envoyee,
    String date = '2026-10-09',
  }) async {
    final r = await api.creerCommande(
      saisieC(fournisseurId, lignes, statut: statut, date: date),
    );
    expect(r, isA<AchatsRecu<CommandeAchatDetail>>(), reason: '$r');
    return (r as AchatsRecu<CommandeAchatDetail>).donnees;
  }

  SaisieReception reception(
    CommandeAchatDetail c,
    String pointId,
    Map<String, String> quantites,
  ) => SaisieReception(
    commandeId: c.commande.id,
    pointStockageId: pointId,
    dateReception: null,
    lignes: [
      for (final l in c.lignes)
        LigneSaisieReception(
          articleId: l.articleId,
          libelle: l.libelleArticle,
          uniteMesure: l.uniteMesure ?? '',
          quantiteCommandee: l.quantiteCommandee,
          quantiteDejaRecue: l.quantiteRecue,
          quantiteRecue: quantites[l.articleId] ?? '',
        ),
    ],
  );

  Future<ReceptionEnregistree> receptionner(
    CommandeAchatDetail c,
    String pointId,
    Map<String, String> quantites,
  ) async {
    final r = await api.receptionner(reception(c, pointId, quantites));
    expect(r, isA<ReceptionEnregistree>(), reason: '$r');
    return r as ReceptionEnregistree;
  }

  Future<CommandeAchatDetail> detail(String id) async =>
      ((await api.commande(id)) as AchatsRecu<CommandeAchatDetail>).donnees;

  Future<int> compte(TableInfo<Table, dynamic> t) async =>
      (await db.select(t).get()).length;

  Future<int> nombreBons() => compte(db.bonsReceptionLocal);
  Future<int> nombreMouvements() => compte(db.mouvementsStockLocal);

  LigneStock ligneStock(EtatStock e, String id) =>
      e.lignes.firstWhere((l) => l.id == id);

  /* ==================================================================== */
  /* Fournisseurs                                                          */
  /* ==================================================================== */

  group('Les fournisseurs', () {
    test(
      'un fournisseur se crée et se relit, ses champs vides sont NULS',
      () async {
        final f = await fournisseur('f-1', 'SODIS SARL', contact: '  ');

        expect(f.raisonSociale, 'SODIS SARL');
        // « pas de contact » n'est pas « un contact dont le nom est vide ».
        expect(f.contact, isNull);
        expect(f.categorie, isNull);
        expect(f.evaluationCode, isNull);

        final ligne = await db.select(db.fournisseursLocal).getSingle();
        expect(ligne.creePar, 'u-1');
        expect(ligne.modifieLe, isNull);
      },
    );

    test(
      'la liste est triée sans égard à la casse, puis par identifiant',
      () async {
        await fournisseur('f-3', 'zebre');
        await fournisseur('f-1', 'Alpha');
        await fournisseur('f-2', 'alpha');
        await fournisseur('f-4', 'Marché Central');

        final page =
            ((await api.fournisseurs()) as AchatsRecu<PageAchats<Fournisseur>>)
                .donnees;
        expect(
          [for (final f in page.elements) f.id],
          ['f-1', 'f-2', 'f-4', 'f-3'],
        );

        // « Éts » se range avec « Ets », comme la collation du serveur : entre
        // « Dupont » et « Fabre », pas après « zebre » (point de code de É).
        await fournisseur('f-5', 'Dupont');
        await fournisseur('f-6', 'Éts Kora');
        await fournisseur('f-7', 'Fabre');
        final avecAccent =
            ((await api.fournisseurs()) as AchatsRecu<PageAchats<Fournisseur>>)
                .donnees;
        expect(
          [for (final f in avecAccent.elements) f.raisonSociale],
          [
            'Alpha',
            'alpha',
            'Dupont',
            'Éts Kora',
            'Fabre',
            'Marché Central',
            'zebre',
          ],
        );
      },
    );

    test(
      'la recherche porte sur la raison sociale ET le contact, casse et accents',
      () async {
        await fournisseur('f-1', 'Éts Kora', contact: '97 00 00 00');
        await fournisseur('f-2', 'SODIS', contact: 'Mme Aïcha');
        await fournisseur('f-3', 'Marché Central');

        Future<List<String>> cherche(String t) async {
          final p =
              ((await api.fournisseurs(recherche: t))
                      as AchatsRecu<PageAchats<Fournisseur>>)
                  .donnees;
          return [for (final f in p.elements) f.id];
        }

        expect(await cherche('éts'), ['f-1']);
        expect(await cherche('ÉTS'), ['f-1']);
        // Sans accent : « ets » retrouve « Éts », « aicha » retrouve « Aïcha ».
        expect(await cherche('ets'), ['f-1']);
        expect(await cherche('aicha'), ['f-2']);
        expect(await cherche('marche'), ['f-3']);
        expect(await cherche('97 00'), ['f-1']);
        expect(await cherche('aïcha'), ['f-2']);
        expect(await cherche('central'), ['f-3']);
        expect(await cherche('introuvable'), isEmpty);
      },
    );

    test(
      'le filtre d’évaluation distingue « pas évalué » de « À revoir »',
      () async {
        await fournisseur('f-1', 'A', evaluation: 'a_revoir');
        await fournisseur('f-2', 'B');
        await fournisseur('f-3', 'C', evaluation: 'excellent');

        final p =
            ((await api.fournisseurs(evaluation: EvaluationFournisseur.aRevoir))
                    as AchatsRecu<PageAchats<Fournisseur>>)
                .donnees;
        // Le fournisseur jamais noté n'est PAS retenu : lui reprocher une
        // mauvaise note que personne ne lui a donnée serait faux.
        expect([for (final f in p.elements) f.id], ['f-1']);
      },
    );

    test('25 par page, avec le total que le filtre retient', () async {
      for (var i = 0; i < 30; i++) {
        await fournisseur(
          'f-${i.toString().padLeft(2, '0')}',
          'F${i.toString().padLeft(2, '0')}',
        );
      }
      final p1 =
          ((await api.fournisseurs()) as AchatsRecu<PageAchats<Fournisseur>>)
              .donnees;
      final p2 =
          ((await api.fournisseurs(page: 2))
                  as AchatsRecu<PageAchats<Fournisseur>>)
              .donnees;
      expect(p1.elements, hasLength(25));
      expect(p2.elements, hasLength(5));
      expect(p1.total, 30);
      expect(p1.derniere, 2);
      expect(p1.estPartielle, isTrue);
      expect(p2.elements.first.raisonSociale, 'F25');
    });

    test(
      'la modification écrit l’auteur et l’instant, pas la création',
      () async {
        await fournisseur('f-1', 'SODIS', evaluation: 'bon');
        final avant = await db.select(db.fournisseursLocal).getSingle();

        final r = await api.enregistrerFournisseur(
          saisieF(
            'f-1',
            'SODIS SARL',
            contact: '01 90',
            evaluation: 'excellent',
          ),
          modification: true,
        );
        expect(
          (r as AchatsRecu<Fournisseur>).donnees.raisonSociale,
          'SODIS SARL',
        );

        final apres = await db.select(db.fournisseursLocal).getSingle();
        expect(apres.contact, '01 90');
        expect(apres.evaluation, 'excellent');
        expect(apres.creeLe, avant.creeLe);
        expect(apres.creePar, 'u-1');
        expect(apres.modifiePar, 'u-1');
        expect(apres.modifieLe, isNotNull);
      },
    );

    test(
      'modifier un fournisseur inconnu est refusé, rien n’est créé',
      () async {
        final r = await api.enregistrerFournisseur(
          saisieF('f-fantome', 'X'),
          modification: true,
        );
        expect(
          r,
          isA<AchatsRefuse<Fournisseur>>().having(
            (x) => x.motif,
            'motif',
            MessagesAchats.fournisseurIntrouvable,
          ),
        );
        expect(await compte(db.fournisseursLocal), 0);
      },
    );

    test(
      'la raison sociale est obligatoire — la phrase du serveur, par champ',
      () async {
        final r = await api.enregistrerFournisseur(
          saisieF('f-1', '   '),
          modification: false,
        );
        final refus = r as AchatsRefuse<Fournisseur>;
        expect(refus.motif, MessagesAchats.raisonSocialeObligatoire);
        expect(
          refus.erreurs['raison_sociale'],
          MessagesAchats.raisonSocialeObligatoire,
        );
        expect(await compte(db.fournisseursLocal), 0);
      },
    );

    test('une évaluation hors registre est refusée', () async {
      final r = await api.enregistrerFournisseur(
        saisieF('f-1', 'X', evaluation: 'super'),
        modification: false,
      );
      expect((r as AchatsRefuse).motif, MessagesAchats.evaluationInconnue);
      expect(await compte(db.fournisseursLocal), 0);
    });

    test(
      'un second envoi du même identifiant est refusé, pas un doublon',
      () async {
        await fournisseur('f-1', 'SODIS');
        final r = await api.enregistrerFournisseur(
          saisieF('f-1', 'SODIS bis'),
          modification: false,
        );
        expect(r, isA<AchatsRefuse<Fournisseur>>());
        expect(await compte(db.fournisseursLocal), 1);
        expect(
          (await db.select(db.fournisseursLocal).getSingle()).raisonSociale,
          'SODIS',
        );
      },
    );

    test(
      'sans session, rien ne s’écrit (RG-15) ; sans droit, rien non plus',
      () async {
        auteur = null;
        var r = await api.enregistrerFournisseur(
          saisieF('f-1', 'X'),
          modification: false,
        );
        expect((r as AchatsRefuse).motif, MessagesAchats.auteurInconnu);

        auteur = 'u-1';
        peutEcrire = false;
        r = await api.enregistrerFournisseur(
          saisieF('f-1', 'X'),
          modification: false,
        );
        final refus = r as AchatsRefuse<Fournisseur>;
        expect(refus.motif, MessagesAchats.droitEcritureRefuse);
        expect(refus.code, 403);
        expect(await compte(db.fournisseursLocal), 0);
      },
    );

    test(
      'sans droit de lecture : « on ne sait pas », jamais une liste vide',
      () async {
        await fournisseur('f-1', 'SODIS');
        peutLire = false;

        expect(await api.tousLesFournisseurs(), isNull);
        final r = await api.fournisseurs();
        expect((r as AchatsRefuse).motif, MessagesAchats.droitLectureRefuse);

        peutLire = true;
        expect(await api.tousLesFournisseurs(), hasLength(1));
      },
    );

    test(
      'archiver ÉCRIT `actif = false`, restaurer le remet — rien n’est effacé',
      () async {
        await fournisseur('f-1', 'SODIS');
        await fournisseur('f-2', 'Marché');

        final archive = await api.archiverFournisseurs(['f-1']);
        final resultat = (archive as AchatsRecu<ResultatArchivage>).donnees;
        expect(resultat.archives, 1);
        expect(resultat.refus, isNull);

        // La fiche reste au registre, marquée ; l'auteur et l'instant suivent.
        final ligne = await (db.select(
          db.fournisseursLocal,
        )..where((f) => f.id.equals('f-1'))).getSingle();
        expect(ligne.actif, isFalse);
        expect(ligne.modifiePar, 'u-1');
        expect(ligne.modifieLe, isNotNull);
        expect(await db.select(db.fournisseursLocal).get(), hasLength(2));

        // La LISTE montre les deux (l'archivé marqué) ; le SÉLECTEUR de la
        // commande n'offre que l'actif.
        final liste =
            ((await api.fournisseurs()) as AchatsRecu<PageAchats<Fournisseur>>)
                .donnees
                .elements;
        expect(liste.map((f) => (f.id, f.actif)).toSet(), {
          ('f-1', false),
          ('f-2', true),
        });
        expect(
          [for (final f in (await api.tousLesFournisseurs())!) f.id],
          ['f-2'],
        );

        final restaure = await api.restaurerFournisseur('f-1');
        expect((restaure as AchatsRecu<Fournisseur>).donnees.actif, isTrue);
        // Trié par raison sociale : « Marché » avant « SODIS ».
        expect(
          [for (final f in (await api.tousLesFournisseurs())!) f.id],
          ['f-2', 'f-1'],
        );
      },
    );

    test('restaurer une fiche DÉJÀ active ne touche à rien', () async {
      await fournisseur('f-1', 'SODIS');
      final avant = await db.select(db.fournisseursLocal).getSingle();

      final r = await api.restaurerFournisseur('f-1');
      expect((r as AchatsRecu<Fournisseur>).donnees.actif, isTrue);

      final apres = await db.select(db.fournisseursLocal).getSingle();
      expect(apres.modifieLe, avant.modifieLe);
      expect(apres.modifiePar, avant.modifiePar);
    });

    test('un fournisseur ENGAGÉ ne s’archive pas : le verrou porte sur les '
        'commandes qui restent à faire', () async {
      final f = await fournisseur('f-1', 'SODIS');
      await article('a-riz', 'Riz');

      Future<int> engagees() async =>
          (await AchatsDao(db, stocks: stocks).engagements(f.id)).length;

      expect(await engagees(), 0);

      // Un brouillon, une envoyée : engagent.
      final brouillon = await commande(f.id, [
        ligne('a-riz', '1', '100'),
      ], statut: StatutCommande.brouillon);
      await commande(f.id, [ligne('a-riz', '1', '100')]);
      expect(await engagees(), 2);

      // Réceptionnée et clôturée : n'engagent plus rien (posées par SQL — ce sont
      // des états que PRODUIT une réception, cf. la création).
      for (final statut in ['receptionnee', 'cloturee']) {
        await commande(f.id, [ligne('a-riz', '1', '100')]);
        final derniere = (await db.select(db.commandesAchatLocal).get()).last;
        await (db.update(db.commandesAchatLocal)
              ..where((c) => c.id.equals(derniere.id)))
            .write(CommandesAchatLocalCompanion(statut: Value(statut)));
      }
      expect(await engagees(), 2);

      // Un statut INCONNU engage : on ne devine pas qu'une commande est derrière.
      await db.customStatement(
        'UPDATE commandes_achat_local SET statut = ? WHERE id = ?',
        ['statut_inconnu', brouillon.commande.id],
      );
      expect(await engagees(), 2);

      final r = await api.archiverFournisseurs([f.id]);
      final resultat = (r as AchatsRecu<ResultatArchivage>).donnees;
      expect(resultat.archives, 0);
      expect(resultat.refus, MessagesAchats.verrouArchivage(2));
      expect((await db.select(db.fournisseursLocal).getSingle()).actif, isTrue);
    });

    test('le lot : les actifs seulement, triés, un motif par fiche engagée, '
        'bloqué quand rien ne part', () async {
      final b = await fournisseur('f-b', 'Bravo');
      final a = await fournisseur('f-a', 'Alpha');
      final c = await fournisseur('f-c', 'Charlie');
      await article('a-riz', 'Riz');
      await commande(b.id, [ligne('a-riz', '1', '100')]);
      await api.archiverFournisseurs([c.id]);

      Future<LotArchivage> lot(List<String> ids) async =>
          ((await api.preparerArchivage(ids)) as AchatsRecu<LotArchivage>)
              .donnees;

      // Alpha part, Bravo est engagé, Charlie est DÉJÀ archivé (écarté).
      final trois = await lot([c.id, b.id, a.id]);
      expect(trois.ids, [a.id]);
      expect(trois.conserves, 1);
      expect(trois.bloque, isFalse);
      expect(trois.motifs, ['Bravo — ${MessagesAchats.verrouArchivage(1)}']);
      // Deux fiches ACTIVES retenues : pas de nom, le nombre qui PART.
      expect(trois.libelle, '');
      expect(trois.element, isNull);
      expect(trois.nombre, 1);

      // Une seule fiche active visée : son nom.
      final seule = await lot([a.id]);
      expect(seule.libelle, 'Alpha');
      expect(seule.element, 'Alpha');
      expect(seule.nombre, isNull);

      // Tout est engagé : BLOQUÉ, avec son motif.
      final bloque = await lot([b.id]);
      expect(bloque.bloque, isTrue);
      expect(bloque.ids, isEmpty);
      expect(bloque.motifs, hasLength(1));

      // Que des archivés : BLOQUÉ, sans motif, sans nom (D271).
      final archives = await lot([c.id]);
      expect(archives.bloque, isTrue);
      expect(archives.motifs, isEmpty);
      expect(archives.libelle, '');
      expect(archives.conserves, 0);
    });

    test('un engagement né ENTRE l’ouverture et le clic : le verrou est '
        'recontrôlé, les autres fiches partent quand même', () async {
      final a = await fournisseur('f-a', 'Alpha');
      final b = await fournisseur('f-b', 'Bravo');
      await article('a-riz', 'Riz');

      final lot =
          ((await api.preparerArchivage([a.id, b.id]))
                  as AchatsRecu<LotArchivage>)
              .donnees;
      expect(lot.ids, hasLength(2));
      expect(lot.conserves, 0);

      // Entre l'ouverture de la modale et le clic : une commande naît chez Bravo.
      await commande(b.id, [ligne('a-riz', '1', '100')]);

      final resultat =
          ((await api.archiverFournisseurs(lot.ids))
                  as AchatsRecu<ResultatArchivage>)
              .donnees;
      expect(resultat.archives, 1, reason: 'Alpha part');
      expect(resultat.refus, MessagesAchats.verrouArchivage(1));
      final etats = {
        for (final f in await db.select(db.fournisseursLocal).get())
          f.id: f.actif,
      };
      expect(etats, {'f-a': false, 'f-b': true});
    });

    test('les droits : l’ÉCRITURE d’abord, puis la règle d’archivage — et '
        'restaurer n’exige que l’écriture', () async {
      await fournisseur('f-1', 'SODIS');

      // Sans le droit d'écrire : c'est le droit qui est dit, à l'ouverture comme
      // à l'exécution.
      peutEcrire = false;
      for (final r in [
        await api.preparerArchivage(['f-1']),
        await api.archiverFournisseurs(['f-1']),
      ]) {
        final refus = r as AchatsRefuse;
        expect(refus.motif, MessagesAchats.droitEcritureRefuse);
        expect(refus.code, 403);
      }
      expect(
        (await api.restaurerFournisseur('f-1') as AchatsRefuse).motif,
        MessagesAchats.droitEcritureRefuse,
      );
      peutEcrire = true;

      // Écrire sans pouvoir archiver (bascule fermée, rôle ordinaire) : la phrase
      // du serveur, et rien n'est écrit.
      peutArchiver = false;
      for (final r in [
        await api.preparerArchivage(['f-1']),
        await api.archiverFournisseurs(['f-1']),
      ]) {
        final refus = r as AchatsRefuse;
        expect(refus.motif, MessagesAchats.refusBascule);
        expect(refus.code, 403);
      }
      expect((await db.select(db.fournisseursLocal).getSingle()).actif, isTrue);

      // Restaurer, lui, passe sans la règle : fermer la bascule ne doit jamais
      // enfermer une fiche aux archives.
      peutArchiver = true;
      await api.archiverFournisseurs(['f-1']);
      peutArchiver = false;
      final r = await api.restaurerFournisseur('f-1');
      expect((r as AchatsRecu<Fournisseur>).donnees.actif, isTrue);
    });

    test('sans auteur, rien n’est archivé ni restauré', () async {
      await fournisseur('f-1', 'SODIS');
      auteur = null;

      expect(
        ((await api.archiverFournisseurs(['f-1'])) as AchatsRefuse).motif,
        MessagesAchats.auteurInconnu,
      );
      expect(
        ((await api.restaurerFournisseur('f-1')) as AchatsRefuse).motif,
        MessagesAchats.auteurInconnu,
      );
      expect((await db.select(db.fournisseursLocal).getSingle()).actif, isTrue);
    });

    test('une fiche inconnue est refusée avec la phrase de M7', () async {
      expect(
        ((await api.restaurerFournisseur('fantome')) as AchatsRefuse).motif,
        MessagesAchats.fournisseurIntrouvable,
      );
    });
  });

  /* ==================================================================== */
  /* Commandes                                                             */
  /* ==================================================================== */

  group('Les commandes', () {
    late Fournisseur sodis;

    setUp(() async {
      sodis = await fournisseur('f-1', 'SODIS');
      await article('a-riz', 'Riz local (sac 50 kg)');
      await article('a-huile', 'Huile', unite: 'bidon');
    });

    test(
      'une commande naît avec ses lignes : libellé et unité FIGÉS à l’ajout',
      () async {
        final c = await commande(sodis.id, [
          // Le libellé et l'unité de la saisie sont ignorés : ils viennent du
          // référentiel, jamais de l'écran.
          ligne('a-riz', '10', '1200', libelle: 'FAUX LIBELLÉ'),
          ligne('a-huile', '2,5', '8500'),
        ]);

        expect(
          [for (final l in c.lignes) l.libelleArticle],
          ['Riz local (sac 50 kg)', 'Huile'],
        );
        expect([for (final l in c.lignes) l.uniteMesure], ['sac', 'bidon']);
        expect(c.lignes[0].quantiteCommandee, '10.00');
        expect(c.lignes[0].prixUnitaire, '1200.00');
        expect(c.lignes[1].quantiteCommandee, '2.50');

        // Renommer l'article n'écrit pas un bon déjà remis au fournisseur.
        await stocks.modifierArticle(
          id: 'a-riz',
          libelle: 'Riz parfumé',
          categorie: 'Denrées',
          uniteMesure: 'sac',
          seuilCentiemes: 500,
          suivi: SuiviArticle.permanent,
          pointStockageId: null,
        );
        final relue = await detail(c.commande.id);
        expect(relue.lignes.first.libelleArticle, 'Riz local (sac 50 kg)');
      },
    );

    test(
      'le montant est CALCULÉ des lignes, tronqué, et n’est jamais une colonne',
      () async {
        // 10 × 1 200 = 12 000 ; 2,50 × 8 500 = 21 250 ; 1,50 × 0,33 = 0,495 -> 0,49.
        await article('a-sel', 'Sel');
        final c = await commande(sodis.id, [
          ligne('a-riz', '10', '1200'),
          ligne('a-huile', '2,5', '8500'),
          ligne('a-sel', '1,5', '0,33'),
        ]);

        expect(c.lignes.map((l) => l.montant), [
          '12000.00',
          '21250.00',
          '0.49',
        ]);
        expect(c.commande.montantTotal, '33250.49');
        expect(c.commande.nombreLignes, 3);

        final registre =
            ((await api.commandes()) as AchatsRecu<PageAchats<CommandeAchat>>)
                .donnees;
        expect(registre.elements.single.montantTotal, '33250.49');
      },
    );

    test(
      'un statut qui ne se saisit pas est refusé, rien n’est écrit',
      () async {
        for (final s in StatutCommande.refusesALaCreation) {
          final r = await api.creerCommande(
            saisieC(sodis.id, [ligne('a-riz', '1', '10')], statut: s),
          );
          expect(r, isA<AchatsRefuse<CommandeAchatDetail>>(), reason: s.code);
        }
        expect(await compte(db.commandesAchatLocal), 0);
        expect(await compte(db.lignesCommandeAchatLocal), 0);
      },
    );

    test(
      'une saisie fausse n’écrit RIEN : commande et lignes naissent ensemble',
      () async {
        // La seconde ligne est invalide : la première ne doit pas survivre.
        final r = await api.creerCommande(
          saisieC(sodis.id, [
            ligne('a-riz', '10', '1200'),
            ligne('a-huile', '0', '8500'),
          ]),
        );
        expect(
          (r as AchatsRefuse).motif,
          contains(MessagesAchats.quantitePositive),
        );
        expect(await compte(db.commandesAchatLocal), 0);
        expect(await compte(db.lignesCommandeAchatLocal), 0);
      },
    );

    test('les refus de saisie, un par un, avec la phrase du serveur', () async {
      Future<String> motif(SaisieCommande s) async =>
          ((await api.creerCommande(s)) as AchatsRefuse).motif;

      expect(
        await motif(saisieC('f-fantome', [ligne('a-riz', '1', '10')])),
        MessagesAchats.fournisseurInexistant,
      );
      expect(
        await motif(saisieC(sodis.id, [])),
        MessagesAchats.lignesObligatoires,
      );
      expect(
        await motif(saisieC(sodis.id, [ligne('a-fantome', '1', '10')])),
        MessagesAchats.articleInexistant,
      );
      expect(
        await motif(saisieC(sodis.id, [ligne('a-riz', '1', '0')])),
        contains(MessagesAchats.prixObligatoire),
      );
      expect(
        await motif(saisieC(sodis.id, [ligne('a-riz', '1', '')])),
        contains(MessagesAchats.prixObligatoire),
      );
      expect(
        await motif(saisieC(sodis.id, [ligne('a-riz', '-3', '10')])),
        contains(MessagesAchats.quantitePositive),
      );
      expect(
        await motif(saisieC(sodis.id, [ligne('a-riz', '1,555', '10')])),
        contains(MessagesAchats.quantitePositive),
      );
      expect(
        await motif(
          saisieC(sodis.id, [ligne('a-riz', '1', '10')], date: '2026-13-45'),
        ),
        MessagesAchats.dateIllisible,
      );
      expect(await compte(db.commandesAchatLocal), 0);
    });

    test(
      'un même article sur deux lignes est refusé : la seconde écraserait la première',
      () async {
        final r = await api.creerCommande(
          saisieC(sodis.id, [
            ligne('a-riz', '30', '10'),
            ligne('a-riz', '20', '10'),
          ]),
        );
        expect((r as AchatsRefuse).motif, contains('figure deux fois'));
        expect(await compte(db.commandesAchatLocal), 0);
      },
    );

    test(
      'un article en suivi journalier ne se commande pas : la réception ne pourrait jamais l’écrire en stock',
      () async {
        await article('a-pain', 'Pain', suivi: SuiviArticle.journalier);
        final r = await api.creerCommande(
          saisieC(sodis.id, [ligne('a-pain', '10', '100')]),
        );
        expect(
          (r as AchatsRefuse).motif,
          MessagesStock.refusJournalier('Pain'),
        );
        expect(await compte(db.commandesAchatLocal), 0);
      },
    );

    test(
      'le registre : date décroissante, recherche par fournisseur, filtre de statut',
      () async {
        final kora = await fournisseur('f-2', 'Éts Kora');
        final c1 = await commande(sodis.id, [
          ligne('a-riz', '1', '10'),
        ], date: '2026-10-01');
        final c2 = await commande(kora.id, [
          ligne('a-riz', '1', '10'),
        ], date: '2026-10-05');
        final c3 = await commande(
          sodis.id,
          [ligne('a-riz', '1', '10')],
          statut: StatutCommande.brouillon,
          date: '2026-10-03',
        );

        Future<List<String>> ids({
          String? recherche,
          StatutCommande? statut,
          String? fournisseurId,
        }) async {
          final p =
              ((await api.commandes(
                        recherche: recherche,
                        statut: statut,
                        fournisseurId: fournisseurId,
                      ))
                      as AchatsRecu<PageAchats<CommandeAchat>>)
                  .donnees;
          return [for (final c in p.elements) c.id];
        }

        expect(await ids(), [c2, c3, c1].map((c) => c.commande.id).toList());
        expect(await ids(recherche: 'éts'), [c2.commande.id]);
        expect(await ids(recherche: 'ets'), [c2.commande.id]);
        expect(await ids(statut: StatutCommande.brouillon), [c3.commande.id]);
        expect(
          await ids(fournisseurId: sodis.id),
          [c3, c1].map((c) => c.commande.id).toList(),
        );
      },
    );

    test(
      'les compteurs de la bande : « en attente » = brouillon + envoyée',
      () async {
        await commande(sodis.id, [ligne('a-riz', '1', '10')]);
        await commande(sodis.id, [
          ligne('a-riz', '1', '10'),
        ], statut: StatutCommande.brouillon);

        expect(
          ((await api.compterCommandesEnAttente()) as AchatsRecu<int>).donnees,
          2,
        );
        expect(
          ((await api.compterCommandes(StatutCommande.envoyee))
                  as AchatsRecu<int>)
              .donnees,
          1,
        );
        expect(
          ((await api.compterCommandes(
                    StatutCommande.receptionneePartiellement,
                  ))
                  as AchatsRecu<int>)
              .donnees,
          0,
        );
      },
    );

    test(
      'émettre : brouillon -> envoyée, une seule fois ; clôturer exige « réceptionnée »',
      () async {
        final c = await commande(sodis.id, [
          ligne('a-riz', '1', '10'),
        ], statut: StatutCommande.brouillon);
        expect(c.commande.envoyable, isTrue);

        final envoyee = await api.envoyerCommande(c.commande.id);
        expect(
          (envoyee as AchatsRecu<CommandeAchatDetail>)
              .donnees
              .commande
              .statutCode,
          'envoyee',
        );

        final encore = await api.envoyerCommande(c.commande.id);
        expect((encore as AchatsRefuse).motif, MessagesAchats.envoiImpossible);

        final cloture = await api.cloturerCommande(c.commande.id);
        expect(
          (cloture as AchatsRefuse).motif,
          MessagesAchats.clotureImpossible,
        );
        expect((await detail(c.commande.id)).commande.statutCode, 'envoyee');
      },
    );

    test(
      'sans droit : ni lecture ni écriture, et l’écriture dit le droit',
      () async {
        peutEcrire = false;
        final r = await api.creerCommande(
          saisieC(sodis.id, [ligne('a-riz', '1', '10')]),
        );
        expect((r as AchatsRefuse).motif, MessagesAchats.droitEcritureRefuse);
        expect(await compte(db.commandesAchatLocal), 0);

        peutLire = false;
        expect(
          await api.commandes(),
          isA<AchatsRefuse<PageAchats<CommandeAchat>>>(),
        );
        expect(await api.compterCommandesEnAttente(), isA<AchatsRefuse<int>>());
      },
    );
  });

  /* ==================================================================== */
  /* Réceptions — RG-10, l'entrée de stock NON valorisée, l'atomicité     */
  /* ==================================================================== */

  group('Les réceptions', () {
    late Fournisseur sodis;
    late String magasin;

    setUp(() async {
      sodis = await fournisseur('f-1', 'SODIS');
      magasin = await point('p-mag', 'Magasin');
      await article('a-riz', 'Riz local (sac 50 kg)');
      await article('a-huile', 'Huile', unite: 'bidon');
      await tolerance('5');
    });

    Future<CommandeAchatDetail> deuxLignes() => commande(sodis.id, [
      ligne('a-riz', '100', '1200'),
      ligne('a-huile', '20', '8500'),
    ]);

    test(
      'une réception conforme : bon, lignes, entrées de stock NON valorisées (comme le serveur), statut posé',
      () async {
        final c = await deuxLignes();
        final r = await receptionner(c, magasin, {
          'a-riz': '100',
          'a-huile': '20',
        });

        expect(r.bon.conformiteCode, 'totale');
        expect(r.bon.dateReception, '2026-10-09');
        expect(r.bon.pointLibelle, 'Magasin');
        expect(r.bon.nombreArticles, 2);
        expect(r.bon.lignesNonStockees, isFalse);
        expect(r.bon.fournisseurRaisonSociale, 'SODIS');

        // Le stock a bougé, mais l'entrée n'est PAS valorisée : le serveur
        // appelle `entree()` sans coût (D132). Aucun coût, aucun dernier prix —
        // « inconnu », jamais zéro —, et la valeur du stock ne compte pas ces
        // deux articles (M11 dit « hors 2 article(s) sans coût »).
        final etat = (await stocks.etat());
        expect(ligneStock(etat, 'a-riz').stock, '100.00');
        expect(ligneStock(etat, 'a-riz').prixAchat, isNull);
        expect(ligneStock(etat, 'a-riz').cmpInconnu, isTrue);
        expect(ligneStock(etat, 'a-riz').valeurInconnue, isTrue);
        expect(ligneStock(etat, 'a-huile').stock, '20.00');
        expect(ligneStock(etat, 'a-huile').prixAchat, isNull);
        expect(ligneStock(etat, 'a-huile').valeurInconnue, isTrue);
        expect(etat.kpis.valeurStock, '0');
        expect(etat.kpis.sansValorisation, 2);

        // Le mouvement porte la phrase du serveur, l'auteur, le coût en
        // dix-millièmes et l'état LOCAL — jamais « en attente ».
        final m = (await (db.select(
          db.mouvementsStockLocal,
        )..where((x) => x.articleId.equals('a-riz'))).getSingle());
        expect(m.typeMouvement, 'entree');
        expect(m.quantite, 100.0);
        expect(m.coutUnitaireDixMilliemes, isNull);
        expect(m.utilisateurId, 'u-1');
        expect(m.statutSync, 'local');
        expect(
          m.motif,
          MessagesAchats.motifReception(commande: c.commande.id, bon: r.bon.id),
        );

        // Le statut de la commande est PRODUIT par la réception.
        final apres = await detail(c.commande.id);
        expect(apres.commande.statutCode, 'receptionnee');
        expect(apres.commande.receptionnable, isFalse);
        expect(apres.commande.cloturable, isTrue);
      },
    );

    test(
      'la quantité « déjà reçue » est la SOMME des bons, le reste est planché à zéro',
      () async {
        final c = await deuxLignes();
        await receptionner(c, magasin, {'a-riz': '60'});

        final milieu = await detail(c.commande.id);
        final riz = milieu.lignes.firstWhere((l) => l.articleId == 'a-riz');
        expect(riz.quantiteRecue, '60.00');
        expect(riz.resteARecevoir, '40.00');
        final huile = milieu.lignes.firstWhere((l) => l.articleId == 'a-huile');
        expect(huile.quantiteRecue, '0.00');
        expect(huile.resteARecevoir, '20.00');
        expect(milieu.recuReconstitue, isFalse);
        expect(milieu.receptions, hasLength(1));

        // Une seconde réception ajoute, un excédent ne devient pas un reste négatif.
        await receptionner(milieu, magasin, {'a-riz': '50'});
        final fin = await detail(c.commande.id);
        final riz2 = fin.lignes.firstWhere((l) => l.articleId == 'a-riz');
        expect(riz2.quantiteRecue, '110.00');
        expect(riz2.resteARecevoir, '0.00');
        expect(fin.receptions, hasLength(2));
      },
    );

    test(
      'le « déjà reçu » et le rapprochement sont ceux de CETTE commande, pas du même article ailleurs',
      () async {
        final a = await commande(sodis.id, [ligne('a-riz', '100', '1200')]);
        final b = await commande(sodis.id, [ligne('a-riz', '100', '1300')]);
        await receptionner(a, magasin, {'a-riz': '100'});

        // La commande B n'a rien reçu, bien que le MÊME article ait été reçu
        // pour A : une somme par article sans filtre de commande lui en
        // attribuerait 100.
        final detailB = await detail(b.commande.id);
        expect(detailB.lignes.single.quantiteRecue, '0.00');
        expect(detailB.lignes.single.resteARecevoir, '100.00');
        expect(detailB.receptions, isEmpty);

        final rapB =
            ((await api.rapprocher(b.commande.id)) as AchatsRecu<Rapprochement>)
                .donnees;
        expect(rapB.lignes.single.recue, '0.00');
        expect(rapB.lignes.single.concordance, 'manquant');
      },
    );

    test(
      'le seuil de tolérance, PILE : 95 sur 100 à 5 % est conforme, 94 ne l’est pas',
      () async {
        final a = await commande(sodis.id, [ligne('a-riz', '100', '1200')]);
        final r95 = await receptionner(a, magasin, {'a-riz': '95'});
        expect(r95.bon.conformiteCode, 'totale');
        expect(
          (await detail(a.commande.id)).commande.statutCode,
          'receptionnee',
        );

        final b = await commande(sodis.id, [ligne('a-riz', '100', '1200')]);
        final r94 = await receptionner(b, magasin, {'a-riz': '94'});
        expect(r94.bon.conformiteCode, 'partielle');
        expect(
          (await detail(b.commande.id)).commande.statutCode,
          'receptionnee_partiellement',
        );

        // Au-dessus : 105 est pile sur la tolérance, 105,01 ne l'est pas.
        final c = await commande(sodis.id, [ligne('a-riz', '100', '1200')]);
        expect(
          (await receptionner(c, magasin, {'a-riz': '105'})).bon.conformiteCode,
          'totale',
        );
        final d = await commande(sodis.id, [ligne('a-riz', '100', '1200')]);
        expect(
          (await receptionner(d, magasin, {
            'a-riz': '105,01',
          })).bon.conformiteCode,
          'non_conforme',
        );
      },
    );

    test(
      'une tolérance NULLE est une tolérance : le moindre écart décide',
      () async {
        await tolerance('0');
        final c = await commande(sodis.id, [ligne('a-riz', '100', '1200')]);
        final r = await receptionner(c, magasin, {'a-riz': '99,99'});
        expect(r.bon.conformiteCode, 'partielle');
      },
    );

    test(
      'un article reçu HORS commande : non conforme, et son entrée n’est PAS valorisée',
      () async {
        final c = await commande(sodis.id, [ligne('a-riz', '10', '1200')]);
        // L'écran n'envoie que les lignes de la commande ; le DAO, lui, ne se
        // fie pas à l'écran.
        final r = await api.receptionner(
          SaisieReception(
            commandeId: c.commande.id,
            pointStockageId: magasin,
            dateReception: null,
            lignes: const [
              LigneSaisieReception(
                articleId: 'a-huile',
                libelle: 'Huile',
                uniteMesure: 'bidon',
                quantiteCommandee: '0.00',
                quantiteDejaRecue: '0.00',
                quantiteRecue: '3',
              ),
            ],
          ),
        );
        expect((r as ReceptionEnregistree).bon.conformiteCode, 'non_conforme');

        // Du stock sans prix : sa valeur est INCONNUE, jamais valorisée à zéro.
        final huile = ligneStock(await stocks.etat(), 'a-huile');
        expect(huile.stock, '3.00');
        expect(huile.cmpInconnu, isTrue);
        expect(huile.prixAchat, isNull);
      },
    );

    test(
      'la tolérance absente : un refus qui NE se corrige PAS dans le formulaire, et RIEN d’écrit',
      () async {
        await db.delete(db.parametresSystemeLocal).go();
        final c = await deuxLignes();
        final avantMouvements = await nombreMouvements();

        final r = await api.receptionner(
          reception(c, magasin, {'a-riz': '100'}),
        );

        expect(r, isA<ToleranceNonConfiguree>());
        expect(
          (r as ToleranceNonConfiguree).message,
          MessagesAchats.toleranceAbsente,
        );
        expect(await nombreBons(), 0);
        expect(await compte(db.lignesBonReceptionLocal), 0);
        expect(await nombreMouvements(), avantMouvements);
        expect((await detail(c.commande.id)).commande.statutCode, 'envoyee');
      },
    );

    test(
      'une tolérance illisible est refusée, jamais tronquée en silence',
      () async {
        await tolerance('2.555');
        final c = await deuxLignes();
        final r = await api.receptionner(
          reception(c, magasin, {'a-riz': '100'}),
        );
        expect(
          (r as ReceptionRefusee).motif,
          MessagesAchats.toleranceIllisible,
        );
        expect(await nombreBons(), 0);
      },
    );

    test(
      'ATOMIQUE : si l’entrée de stock d’une ligne est refusée, aucune autre n’est écrite',
      () async {
        final c = await deuxLignes();
        // Entre la commande et la réception, la seconde ligne passe en suivi
        // journalier : le DAO du stock refuse son entrée. La première ligne,
        // déjà écrite quand le refus tombe, doit être défaite.
        await stocks.modifierArticle(
          id: 'a-huile',
          libelle: 'Huile',
          categorie: 'Denrées',
          uniteMesure: 'bidon',
          seuilCentiemes: 0,
          suivi: SuiviArticle.journalier,
          pointStockageId: null,
        );
        final avantMouvements = await nombreMouvements();

        final r = await api.receptionner(
          reception(c, magasin, {'a-riz': '100', 'a-huile': '20'}),
        );

        expect(
          (r as ReceptionRefusee).motif,
          MessagesStock.refusJournalier('Huile'),
        );
        // Le riz n'est pas entré en stock, il n'y a ni bon ni ligne de bon, et la
        // commande n'a pas changé de statut.
        expect(await nombreMouvements(), avantMouvements);
        expect(await nombreBons(), 0);
        expect(await compte(db.lignesBonReceptionLocal), 0);
        expect(ligneStock(await stocks.etat(), 'a-riz').stock, '0.00');
        expect((await detail(c.commande.id)).commande.statutCode, 'envoyee');
      },
    );

    test(
      'une commande « réceptionnée » ou « clôturée » ne se réceptionne plus',
      () async {
        final c = await commande(sodis.id, [ligne('a-riz', '10', '1200')]);
        await receptionner(c, magasin, {'a-riz': '10'});

        var r = await api.receptionner(reception(c, magasin, {'a-riz': '1'}));
        expect((r as ReceptionRefusee).motif, MessagesAchats.commandeCloturee);

        final cloture = await api.cloturerCommande(c.commande.id);
        expect(
          (cloture as AchatsRecu<CommandeAchatDetail>)
              .donnees
              .commande
              .statutCode,
          'cloturee',
        );
        r = await api.receptionner(reception(c, magasin, {'a-riz': '1'}));
        expect((r as ReceptionRefusee).motif, MessagesAchats.commandeCloturee);

        // Une seule réception a eu lieu, un seul bon, une seule entrée de stock.
        expect(await nombreBons(), 1);
        expect(ligneStock(await stocks.etat(), 'a-riz').stock, '10.00');
      },
    );

    test(
      'comportement du serveur reproduit : le verdict porte sur CETTE réception, pas sur le cumul',
      () async {
        // 60 puis 40 : le total est 100 (conforme), mais chaque réception, prise
        // seule, est jugée contre les 100 commandés. Le serveur fait de même
        // (`evaluerConformite` ne lit pas les réceptions précédentes) — signalé
        // à l'Architecte (D133), NON corrigé ici : deux verdicts pour une même
        // livraison seraient pire.
        final c = await commande(sodis.id, [ligne('a-riz', '100', '1200')]);
        final premiere = await receptionner(c, magasin, {'a-riz': '60'});
        final seconde = await receptionner(
          await detail(c.commande.id),
          magasin,
          {'a-riz': '40'},
        );
        expect(premiere.bon.conformiteCode, 'partielle');
        expect(seconde.bon.conformiteCode, 'partielle');
        expect(
          (await detail(c.commande.id)).commande.statutCode,
          'receptionnee_partiellement',
        );
        // Et pourtant le stock est juste : 100 sacs entrés, valorisés à 1 200.
        expect(ligneStock(await stocks.etat(), 'a-riz').stock, '100.00');
      },
    );

    test(
      'les refus de saisie : vide, doublon, quantité fausse, point inconnu, commande inconnue',
      () async {
        final c = await deuxLignes();

        Future<String> motif(SaisieReception s) async =>
            ((await api.receptionner(s)) as ReceptionRefusee).motif;

        expect(
          await motif(reception(c, magasin, {})),
          MessagesAchats.receptionVide,
        );
        expect(
          await motif(reception(c, magasin, {'a-riz': '0'})),
          MessagesAchats.receptionVide,
        );
        expect(
          await motif(reception(c, 'p-fantome', {'a-riz': '5'})),
          MessagesAchats.pointInexistant,
        );
        expect(
          await motif(
            SaisieReception(
              commandeId: 'c-fantome',
              pointStockageId: magasin,
              dateReception: null,
              lignes: reception(c, magasin, {'a-riz': '5'}).lignes,
            ),
          ),
          MessagesAchats.commandeIntrouvable,
        );
        // Un doublon d'article dans la réception.
        final doublon = reception(c, magasin, {'a-riz': '5'});
        expect(
          await motif(
            SaisieReception(
              commandeId: doublon.commandeId,
              pointStockageId: magasin,
              dateReception: null,
              lignes: [...doublon.lignes, doublon.lignes.first],
            ),
          ),
          MessagesAchats.articleEnDoubleReception,
        );
        expect(await nombreBons(), 0);
      },
    );

    test('sans droit ou sans session : rien n’est écrit', () async {
      final c = await deuxLignes();
      peutEcrire = false;
      var r = await api.receptionner(reception(c, magasin, {'a-riz': '100'}));
      expect((r as ReceptionRefusee).motif, MessagesAchats.droitEcritureRefuse);
      expect(r.code, 403);

      peutEcrire = true;
      auteur = null;
      r = await api.receptionner(reception(c, magasin, {'a-riz': '100'}));
      expect((r as ReceptionRefusee).motif, MessagesAchats.auteurInconnu);
      expect(await nombreBons(), 0);
      expect(await nombreMouvements(), 0);
    });

    test(
      'l’onglet Réceptions : point et nombre d’articles réels, plus récent d’abord',
      () async {
        final haut = await point('p-bar', 'Bar');
        final c1 = await commande(sodis.id, [ligne('a-riz', '10', '1200')]);
        final c2 = await commande(sodis.id, [
          ligne('a-riz', '10', '1200'),
          ligne('a-huile', '5', '8500'),
        ]);
        final b1 = await receptionner(c1, magasin, {'a-riz': '10'});
        final b2 = await receptionner(c2, haut, {
          'a-riz': '10',
          'a-huile': '5',
        });

        final page =
            ((await api.receptions()) as AchatsRecu<PageAchats<BonReception>>)
                .donnees;
        expect([for (final b in page.elements) b.id], [b2.bon.id, b1.bon.id]);
        expect(page.elements[0].pointLibelle, 'Bar');
        expect(page.elements[0].nombreArticles, 2);
        expect(page.elements[1].pointLibelle, 'Magasin');
        expect(page.elements[1].nombreArticles, 1);

        // Le filtre de conformité reste servi.
        final filtre =
            ((await api.receptions(conformite: ConformiteReception.partielle))
                    as AchatsRecu<PageAchats<BonReception>>)
                .donnees;
        expect(filtre.elements, isEmpty);
        expect(filtre.total, 0);
      },
    );

    test(
      'le rapprochement : deux voies sur trois, l’écart signé, jamais « trois voies »',
      () async {
        final c = await deuxLignes();
        await receptionner(c, magasin, {'a-riz': '80', 'a-huile': '20'});

        final r =
            ((await api.rapprocher(c.commande.id)) as AchatsRecu<Rapprochement>)
                .donnees;

        expect(r.factureVerifiable, isFalse);
        expect(r.voiesVerifiees, ['commande', 'reception']);
        expect(r.estConforme, isFalse);
        expect(r.concordanceGlobale, 'ecart_constate');

        final riz = r.lignes.firstWhere((l) => l.articleId == 'a-riz');
        expect(riz.libelle, 'Riz local (sac 50 kg)');
        expect(riz.commandee, '100.00');
        expect(riz.recue, '80.00');
        expect(riz.ecart, '-20.00');
        expect(riz.concordance, 'manquant');
        final huile = r.lignes.firstWhere((l) => l.articleId == 'a-huile');
        expect(huile.ecart, '0.00');
        expect(huile.concordance, 'conforme');

        // La seule mise en garde est la facture absente : la phrase sur la
        // « reconstitution depuis les mouvements de stock » serait FAUSSE ici.
        expect(r.avertissements, [MessagesAchats.factureAbsente]);
      },
    );

    test(
      'rapprochement d’une commande intacte : tout est « manquant » avec un reçu à 0.00, jamais conforme',
      () async {
        final c = await deuxLignes();
        final r =
            ((await api.rapprocher(c.commande.id)) as AchatsRecu<Rapprochement>)
                .donnees;
        expect(r.lignes.every((l) => l.recue == '0.00'), isTrue);
        expect(r.lignes.every((l) => l.concordance == 'manquant'), isTrue);
        expect(r.estConforme, isFalse);
      },
    );

    test('un rapprochement conforme l’est vraiment', () async {
      final c = await commande(sodis.id, [ligne('a-riz', '10', '1200')]);
      await receptionner(c, magasin, {'a-riz': '10'});
      final r =
          ((await api.rapprocher(c.commande.id)) as AchatsRecu<Rapprochement>)
              .donnees;
      expect(r.estConforme, isTrue);
      expect(r.concordanceGlobale, 'conforme');
    });

    test(
      'une commande inconnue : détail et rapprochement disent « introuvable »',
      () async {
        expect(
          ((await api.commande('c-fantome')) as AchatsRefuse).motif,
          MessagesAchats.commandeIntrouvable,
        );
        expect(
          ((await api.rapprocher('c-fantome')) as AchatsRefuse).motif,
          MessagesAchats.commandeIntrouvable,
        );
      },
    );

    test(
      'la réception d’achat ne touche NI le coût moyen pondéré NI le dernier prix : ceux de l’entrée valorisée d’avant restent',
      () async {
        // 10 sacs déjà en stock à 1 000 F, puis 30 reçus (commandés à 1 400 F) :
        // la réception ne porte aucun coût, donc le CMP reste 1 000 — il aurait
        // valu (10 × 1 000 + 30 × 1 400) / 40 = 1 300 si elle valorisait.
        await stocks.ajouterMouvement(
          articleId: 'a-riz',
          pointId: magasin,
          type: TypeMouvement.entree,
          centiemes: 1000,
          motif: 'Reprise',
          auteurId: 'u-1',
          coutDixMilliemes: 10000000,
        );
        final c = await commande(sodis.id, [ligne('a-riz', '30', '1400')]);
        await receptionner(c, magasin, {'a-riz': '30'});

        final riz = ligneStock(await stocks.etat(), 'a-riz');
        expect(riz.stock, '40.00');
        expect(riz.coutMoyenPondere, '1000.0000');
        expect(riz.prixAchat, '1000.0000');
        // 40 sacs au coût connu de 1 000 F : le stock reçu est valorisé AU COÛT
        // D'AVANT, pas à celui de la commande.
        expect(riz.valeurStock, '40000');
      },
    );
  });
}
