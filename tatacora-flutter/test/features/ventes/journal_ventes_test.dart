import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/caisse/data/sessions_caisse_dao.dart';
import 'package:tatacora_flutter/features/caisse/domain/entities/session_caisse.dart'
    show pointDeCaisseDuComptoir;
import 'package:tatacora_flutter/features/facturation/data/facture_dao.dart';
import 'package:tatacora_flutter/features/facturation/domain/entities/piece_facturation.dart';
import 'package:tatacora_flutter/features/facturation/domain/repositories/facture_repository.dart';
import 'package:tatacora_flutter/features/pos/data/panier_dao.dart';
import 'package:tatacora_flutter/features/pos/data/tables_pos_dao.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/article_vendable.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/espace_pos.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/mode_reglement.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/panier.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/reference_catalogue.dart';
import 'package:tatacora_flutter/features/ventes/domain/entities/vente.dart';
import 'package:tatacora_flutter/features/ventes/domain/journal_ventes.dart';
import 'package:tatacora_flutter/features/ventes/impression/etat_journal_ventes.dart';
import '../comptabilite/support/outils_comptabilite.dart'
    show baseInstalleeSur, moteurSur;
import '../pos/support/outils_ventes.dart' show cloturerSansPiece;
import '../facturation/support/outils_encaissement.dart'
    show caissierEssai, ouvrirLaCaisseDuComptoir;

/// Le journal des ventes, monté sur une **vraie base locale**.
///
/// ## Ce que ces cas éprouvent en priorité
///
/// Le piège de ce lot n'est pas un calcul, c'est une **confusion de
/// registres** : le journal lit les paniers, la Facturation lit les pièces.
/// Les cas les plus importants sont donc ceux qui vérifient que les deux ne
/// disent pas la même chose — une vente sans facture entre au journal, une
/// facture annulée par avoir ne fait pas disparaître sa vente, et le numéro
/// annoncé sur une ligne n'est jamais celui d'un avoir.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late PanierDao paniers;
  late FactureDao factures;
  late TablesPosDao tables;

  DateTime maintenant() => DateTime(2026, 8, 26, 18);

  const biere = ArticleVendable(
    reference: ReferenceCatalogue(module: ModuleVendable.m5Bar, code: 'bsn-33'),
    libelle: 'Béninoise 33cl',
    prix: 1000,
    categorie: 'locale',
  );
  const circuit = ArticleVendable(
    reference: ReferenceCatalogue(
      module: ModuleVendable.m9Tourisme,
      code: 'cir-taneka',
    ),
    libelle: 'Circuit Taneka',
    prix: 15000,
  );

  setUp(() async {
    db = AppDatabase.enMemoire();
    await ouvrirLaCaisseDuComptoir(db);
    // Une vente passe sa pièce comptable (l'exercice 2026) à la clôture.
    await baseInstalleeSur(db, maintenant());
    paniers = PanierDao(
      db,
      maintenant: maintenant,
      moteur: () async => moteurSur(db, maintenant: maintenant),
    );
    factures = FactureDao(db, maintenant: maintenant);
    tables = TablesPosDao(db);

    await db
        .into(db.cartesBoissonLocal)
        .insert(
          CartesBoissonLocalCompanion.insert(
            id: 'bsn-33',
            articleId: 'art-bsn',
            libelle: 'Béninoise 33cl',
            categorie: 'locale',
            prixVente: 1000,
          ),
        );
    await db
        .into(db.circuitsLocal)
        .insert(
          CircuitsLocalCompanion.insert(
            id: 'cir-taneka',
            nom: 'Circuit Taneka',
            theme: 'Culture',
            zone: 'Atacora',
            prix: 15000,
            capaciteMax: 12,
          ),
        );
  });

  tearDown(() => db.close());

  /// Un panier au comptoir, alimenté puis clôturé.
  Future<Panier> venteComptant({
    String? modePaiement = 'especes',
    String pointVente = 'Bar principal',
    List<ArticleVendable> articles = const [biere],
  }) async {
    var p = await paniers.ouvrir(
      typeVente: TypeVente.comptant,
      pointVente: pointVente,
    );
    for (final a in articles) {
      p = await paniers.ajouterLigne(p.id, a);
    }
    // Une vente HISTORIQUE — un mode « non renseigné », une note de chambre au
    // comptoir, un circuit ou une location au panier — la clôture d'aujourd'hui
    // la REFUSE (voir `PanierDao.cloturer`) : le journal doit pourtant pouvoir
    // la montrer, c'est un poste qui a vécu avant. Elle est donc écrite comme
    // l'ancienne clôture le faisait, sans pièce.
    final historique =
        modePaiement == null ||
        modePaiement == ModeReglement.noteChambre.code ||
        articles.any(
          (a) =>
              a.reference.module != ModuleVendable.m5Bar &&
              a.reference.module != ModuleVendable.m4Restaurant,
        );
    if (historique) {
      final session = await SessionsCaisseDao(
        db,
      ).sessionOuverte(pointDeCaisseDuComptoir);
      await cloturerSansPiece(
        db,
        p.id,
        mode: modePaiement,
        quand: maintenant(),
        sessionId: session?.id,
      );
      return (await paniers.parId(p.id))!;
    }
    return paniers.cloturer(
      p.id,
      modePaiement: modePaiement,
      auteurId: caissierEssai,
    );
  }

  Future<JournalVentes> journal() async => composerJournal(
    paniers: await paniers.paniers(),
    libellesTables: await tables.libelles(),
    numeroFactureParPanier: await factures.numerosFactureParPanier(),
  );

  /* ================================================================== */
  group('Ce qui est une vente, et ce qui n’en est pas', () {
    test(
      'un panier ENCORE OUVERT n’entre pas au journal, et il est compté',
      () async {
        // Rien n'y est encaissé, et le mode de règlement se fige à la clôture :
        // le compter annoncerait un chiffre d'affaires que personne n'a réalisé.
        // Mais il n'est pas avalé pour autant — l'écran dit combien il y en a,
        // sans quoi un barman conclurait que l'écran a perdu sa vente.
        final ouvert = await paniers.ouvrir(
          typeVente: TypeVente.comptant,
          pointVente: 'Bar principal',
        );
        await paniers.ajouterLigne(ouvert.id, biere);

        final j = await journal();

        expect(j.ventes, isEmpty);
        expect(j.paniersOuverts, 1);
      },
    );

    test('un panier CLÔTURÉ est une vente validée, au montant FIGÉ', () async {
      final panier = await venteComptant();
      final j = await journal();

      expect(j.ventes, hasLength(1));
      final v = j.ventes.single;
      expect(v.id, panier.id);
      expect(v.statut, StatutVente.validee);
      expect(v.montant, 1000);
      expect(
        v.montantFige,
        isTrue,
        reason:
            'le montant doit venir de `montantCloture` : c’est celui qui a été '
            'annoncé au client, pas une somme recalculée après coup',
      );
      expect(v.encaisse, isTrue);
      expect(v.date, maintenant());
    });

    test(
      'un panier ANNULÉ reste une vente, sans montant figé et hors du CA',
      () async {
        // ⚠ Divergence de fond avec le maître : ici une vente annulée n'a
        // JAMAIS été encaissée — `PanierDao.annuler` n'accepte qu'un panier
        // ouvert. Il n'y a donc aucun montant arrêté, et rien à contre-passer.
        var p = await paniers.ouvrir(
          typeVente: TypeVente.comptant,
          pointVente: 'Bar principal',
        );
        p = await paniers.ajouterLigne(p.id, biere, quantite: 3);
        await paniers.annuler(p.id, 'Client parti sans consommer');

        final j = await journal();
        final v = j.ventes.single;

        expect(v.statut, StatutVente.annulee);
        expect(v.motifAnnulation, 'Client parti sans consommer');
        expect(v.montant, 3000, reason: 'la somme des lignes, pas un zéro');
        expect(
          v.montantFige,
          isFalse,
          reason:
              'aucun montant n’a été arrêté : le présenter comme figé ferait '
              'croire qu’il a été encaissé puis rendu',
        );

        final kpis = KpisJournalVentes.calculer(j.ventes);
        expect(kpis.ventes, 0);
        expect(kpis.annulees, 1);
        expect(kpis.chiffreAffaires, 0);
      },
    );

    test(
      'les ventes sont rendues de la plus récente à la plus ancienne',
      () async {
        final vieux = PanierDao(
          db,
          maintenant: () => DateTime(2026, 8, 20),
          moteur: () async =>
              moteurSur(db, maintenant: () => DateTime(2026, 8, 20)),
        );
        var a = await vieux.ouvrir(
          typeVente: TypeVente.comptant,
          pointVente: 'Bar principal',
        );
        a = await vieux.ajouterLigne(a.id, biere);
        await vieux.cloturer(
          a.id,
          modePaiement: 'especes',
          auteurId: caissierEssai,
        );

        final recent = await venteComptant();

        final j = await journal();
        expect(j.ventes.map((v) => v.id).toList(), [recent.id, a.id]);
      },
    );
  });

  /* ================================================================== */
  group('`encaisse` n’est pas `montant` — et il a TROIS réponses', () {
    test('une note de chambre n’est PAS dans le tiroir', () async {
      await venteComptant(modePaiement: ModeReglement.noteChambre.code);

      final j = await journal();
      final kpis = KpisJournalVentes.calculer(j.ventes);

      expect(j.ventes.single.encaisse, isFalse);
      expect(kpis.chiffreAffaires, 1000);
      expect(
        kpis.encaisse,
        0,
        reason:
            'annoncer 1000 F encaissés ferait tomber faux le comptage de fin '
            'de service, et ferait disparaître la créance du client',
      );
      expect(kpis.enNote, 1000);
    });

    test(
      'un règlement NON RENSEIGNÉ ne vaut ni encaissé ni porté en note',
      () async {
        // `PanierDao.cloturer` accepte un `modePaiement` nul, et le maître n'a
        // pas ce cas : chez lui `encaisse` est toujours un booléen. Le ranger
        // dans l'un des deux paquets ferait entrer en caisse — ou en créance —
        // un argent dont personne n'a dit ce qu'il était devenu.
        await venteComptant(modePaiement: null);

        final j = await journal();
        final v = j.ventes.single;
        final kpis = KpisJournalVentes.calculer(j.ventes);

        expect(v.mode, isNull);
        expect(v.encaisse, isNull);
        expect(kpis.chiffreAffaires, 1000);
        expect(kpis.encaisse, 0);
        expect(kpis.enNote, 0);
        expect(
          kpis.ventesSansReglement,
          1,
          reason:
              'sans ce compteur, l’écart entre le chiffre d’affaires et la '
              'somme des deux autres cartes ne se verrait nulle part',
        );
        expect(kpis.montantSansReglement, 1000);
      },
    );

    test('les trois paquets se recomposent en chiffre d’affaires', () async {
      await venteComptant();
      await venteComptant(modePaiement: ModeReglement.noteChambre.code);
      await venteComptant(modePaiement: null);

      final kpis = KpisJournalVentes.calculer((await journal()).ventes);

      expect(kpis.ventes, 3);
      expect(
        kpis.encaisse + kpis.enNote + kpis.montantSansReglement,
        kpis.chiffreAffaires,
        reason:
            'un quatrième cas non compté ferait disparaître de l’argent entre '
            'le total et ses parts, sans qu’aucune carte ne le signale',
      );
    });
  });

  /* ================================================================== */
  group('La vente et la facture ne sont PAS la même pièce', () {
    test(
      'une vente SANS facture entre au journal, et n’affirme rien',
      () async {
        await venteComptant();
        final j = await journal();

        expect(j.ventes.single.aUneFacture, isFalse);
        expect(j.ventes.single.numeroFacture, isNull);
        expect(
          mentionPiecesFiscales(ventes: 1, avecFacture: 0),
          'Aucune facture émise pour ces ventes',
          reason:
              'ni « certifiée » ni « non certifiée » : écrire la seconde '
              'laisserait croire qu’une pièce existe et attend son cachet',
        );
      },
    );

    test('une vente FACTURÉE annonce le numéro de sa pièce', () async {
      final panier = await venteComptant();
      final piece = await factures.emettre(
        BrouillonFacture(
          origine: OrigineFacture.posComptant,
          clientNom: 'Client de passage',
          panierId: panier.id,
          lignes: const [
            LigneBrouillon(
              module: ModuleFacturable.m5Bar,
              libelle: 'Béninoise 33cl',
              prixUnitaire: 1000,
              quantite: 1,
            ),
          ],
        ),
      );

      final j = await journal();
      expect(j.ventes.single.numeroFacture, piece.numero);
      expect(
        mentionPiecesFiscales(ventes: 1, avecFacture: 1),
        contains('1 vente(s) sur 1 avec facture'),
      );
    });

    test(
      '⚠ une facture annulée par AVOIR ne laisse plus aucun numéro sur la vente',
      () async {
        // Le piège de ce module, porté du registre des factures : l'avoir
        // porte le MÊME `panierId` et le statut `emise`. Sans l'exclusion des
        // avoirs, le journal annoncerait sur la ligne de vente le numéro d'un
        // document à montant NÉGATIF — et la vente, elle, resterait au journal
        // exactement comme avant, ce qui est précisément la différence entre
        // les deux registres.
        final panier = await venteComptant();
        final piece = await factures.emettre(
          BrouillonFacture(
            origine: OrigineFacture.posComptant,
            clientNom: 'Client de passage',
            panierId: panier.id,
            lignes: const [
              LigneBrouillon(
                module: ModuleFacturable.m5Bar,
                libelle: 'Béninoise 33cl',
                prixUnitaire: 1000,
                quantite: 1,
              ),
            ],
          ),
        );
        await factures.annuler(piece.id, 'Erreur de saisie');

        final j = await journal();
        final v = j.ventes.single;

        expect(
          v.aUneFacture,
          isFalse,
          reason:
              'la facture est annulée et l’avoir n’est pas une facture : '
              'l’annoncer proposerait au client un montant négatif à la place '
              'de sa pièce',
        );
        expect(
          v.statut,
          StatutVente.validee,
          reason:
              'annuler une FACTURE n’annule pas la VENTE : elle a bien eu '
              'lieu, et c’est tout l’objet de ce journal',
        );
      },
    );
  });

  /* ================================================================== */
  group('Les filtres portent sur ce qui identifie une VENTE', () {
    test('l’activité retient toute vente qui CONTIENT la ligne', () async {
      // `any` et non `every` : une vente qui mêle bar et tourisme appartient
      // aux deux. L'inverse ferait disparaître du filtre les ventes les plus
      // fournies — celles qui portent le plus d'argent.
      await venteComptant(articles: const [biere, circuit]);
      await venteComptant();

      final ventes = (await journal()).ventes;

      expect(
        filtrerVentes(
          ventes,
          const FiltreVentes(activite: ModuleVendable.m9Tourisme),
        ),
        hasLength(1),
      );
      expect(
        filtrerVentes(
          ventes,
          const FiltreVentes(activite: ModuleVendable.m5Bar),
        ),
        hasLength(2),
      );
      expect(
        filtrerVentes(
          ventes,
          const FiltreVentes(activite: ModuleVendable.m8Vehicules),
        ),
        isEmpty,
      );
    });

    test('la recherche trouve par référence, table, client et poste', () async {
      final panier = await venteComptant(pointVente: 'Restaurant');
      final ventes = (await journal()).ventes;
      final v = ventes.single;

      for (final terme in [
        v.referenceLocale.toLowerCase(),
        panier.id,
        'restaur',
      ]) {
        expect(
          filtrerVentes(ventes, FiltreVentes(terme: terme)),
          hasLength(1),
          reason: 'terme « $terme »',
        );
      }
      expect(filtrerVentes(ventes, const FiltreVentes(terme: 'zzz')), isEmpty);
    });

    test(
      '⚠ la recherche NE trouve PAS par numéro de facture, délibérément',
      () async {
        // C'est le registre des factures qui répond à cette question. L'offrir
        // ici ferait converger les deux écrans — exactement ce que l'entrée de
        // menu du maître demande d'éviter.
        final panier = await venteComptant();
        final piece = await factures.emettre(
          BrouillonFacture(
            origine: OrigineFacture.posComptant,
            clientNom: 'Client de passage',
            panierId: panier.id,
            lignes: const [
              LigneBrouillon(
                module: ModuleFacturable.m5Bar,
                libelle: 'Béninoise 33cl',
                prixUnitaire: 1000,
                quantite: 1,
              ),
            ],
          ),
        );

        final ventes = (await journal()).ventes;
        expect(ventes.single.numeroFacture, piece.numero);
        expect(
          filtrerVentes(ventes, FiltreVentes(terme: piece.numero)),
          isEmpty,
        );
      },
    );

    test('les bornes de date sont INCLUSES aux deux extrémités', () async {
      // Exclure la borne de fin ferait disparaître les ventes du dernier jour
      // d'un mois — celles qu'on cherche justement quand on arrête une période.
      await venteComptant();
      final ventes = (await journal()).ventes;
      final jour = DateTime(2026, 8, 26);

      expect(
        filtrerVentes(ventes, FiltreVentes(debut: jour, fin: jour)),
        hasLength(1),
      );
      expect(
        filtrerVentes(
          ventes,
          FiltreVentes(debut: jour.add(const Duration(days: 1))),
        ),
        isEmpty,
      );
      expect(
        filtrerVentes(
          ventes,
          FiltreVentes(fin: jour.subtract(const Duration(days: 1))),
        ),
        isEmpty,
      );
    });

    test('le statut et le règlement filtrent le journal', () async {
      await venteComptant();
      await venteComptant(modePaiement: ModeReglement.noteChambre.code);
      var abandonne = await paniers.ouvrir(
        typeVente: TypeVente.comptant,
        pointVente: 'Bar principal',
      );
      abandonne = await paniers.ajouterLigne(abandonne.id, biere);
      await paniers.annuler(abandonne.id, 'Erreur');

      final ventes = (await journal()).ventes;

      expect(
        filtrerVentes(ventes, const FiltreVentes(statut: StatutVente.annulee)),
        hasLength(1),
      );
      expect(
        filtrerVentes(ventes, const FiltreVentes(statut: StatutVente.validee)),
        hasLength(2),
      );
      expect(
        filtrerVentes(
          ventes,
          const FiltreVentes(mode: ModeReglement.noteChambre),
        ),
        hasLength(1),
      );
    });

    test(
      'les postes offerts viennent des ventes, et excluent les séjours',
      () async {
        // `filter(Boolean)` du maître : une vente de séjour n'a aucun poste
        // (`ecran_pos_heberges.dart` n'en passe pas). Offrir une entrée vide
        // donnerait un filtre qu'on ne saurait pas nommer.
        await venteComptant(pointVente: 'Bar principal');
        await venteComptant(pointVente: 'Restaurant');

        final sansPoste = await paniers.ouvrir(typeVente: TypeVente.comptant);
        await paniers.ajouterLigne(sansPoste.id, biere);
        await paniers.cloturer(
          sansPoste.id,
          modePaiement: 'especes',
          auteurId: caissierEssai,
        );

        // ⚠ Et un poste réduit à des espaces n'est PAS un poste. `pointVente`
        // est une chaîne libre du panier : rien n'empêche d'y écrire « ␣␣ ».
        // Le maître l'écarte par son `filter(Boolean)` ; sans ce cas, la garde
        // `trim().isNotEmpty` pourrait disparaître sans qu'aucun test ne
        // rougisse — et le filtre offrirait une entrée vide, impossible à
        // nommer et impossible à défaire.
        await venteComptant(pointVente: '   ');

        final ventes = (await journal()).ventes;
        expect(ventes, hasLength(4));
        expect(postesDuJournal(ventes), ['Bar principal', 'Restaurant']);
      },
    );
  });

  /* ================================================================== */
  group('La table et sa vente', () {
    test('le libellé de la table est joint au référentiel', () async {
      final salle = await tables.toutes();
      final table = salle.firstWhere((t) => t.espace == EspacePos.restaurant);

      var p = await paniers.ouvrir(
        typeVente: TypeVente.comptant,
        pointVente: 'Restaurant',
        tableId: table.id,
        espace: table.espace.code,
      );
      p = await paniers.ajouterLigne(p.id, biere);
      await paniers.cloturer(
        p.id,
        modePaiement: 'especes',
        auteurId: caissierEssai,
      );

      final j = await journal();
      expect(j.ventes.single.tableLibelle, table.libelle);
      expect(j.ventes.single.espace, EspacePos.restaurant.code);
    });

    test('`libelles()` ne SÈME jamais le référentiel', () async {
      // `toutes()` sème treize tables quand le référentiel est vide, et c'est
      // ce qu'il faut au point de vente. Une LECTURE ne doit rien écrire :
      // ouvrir un journal vide ne doit pas créer de salle.
      expect(await tables.libelles(), isEmpty);
      expect(await db.select(db.tablesLocal).get(), isEmpty);
    });
  });

  /* ================================================================== */
  group('L’export porte sur ce qui est affiché, et il DIT son filtre', () {
    test('une liste vide est REFUSÉE, pas exportée', () {
      final etat = EtatJournalVentes.composer(
        ventes: const [],
        filtre: const FiltreVentes(),
      );
      expect(etat.estVide, isTrue);
      expect(
        messageExportVentesVide,
        'Rien à exporter : la liste filtrée est vide.',
      );
    });

    test('le filtre est écrit en clair sur le document', () async {
      await venteComptant();
      final ventes = (await journal()).ventes;

      final sansFiltre = EtatJournalVentes.composer(
        ventes: ventes,
        filtre: const FiltreVentes(),
      );
      expect(
        sansFiltre.filtre,
        'Aucun filtre',
        reason:
            'le dire est une information : sans elle, un extrait se lirait '
            'comme un journal complet',
      );

      final filtre = FiltreVentes(
        statut: StatutVente.validee,
        pointVente: 'Bar principal',
        activite: ModuleVendable.m5Bar,
        mode: ModeReglement.especes,
        terme: 'bsn',
        debut: DateTime(2026, 8, 1),
        fin: DateTime(2026, 8, 31),
      );
      final etat = EtatJournalVentes.composer(ventes: ventes, filtre: filtre);

      expect(etat.filtre, contains('Du 01/08/2026 au 31/08/2026'));
      expect(etat.filtre, contains('Statut : Validées'));
      expect(etat.filtre, contains('Poste : Bar principal'));
      expect(etat.filtre, contains('Activité : Bar'));
      expect(etat.filtre, contains('Règlement : Espèces'));
      expect(etat.filtre, contains('Recherche : bsn'));
    });

    test(
      'le CSV porte le BOM, le point-virgule et des montants BRUTS',
      () async {
        await venteComptant();
        final etat = EtatJournalVentes.composer(
          ventes: (await journal()).ventes,
          filtre: const FiltreVentes(),
        );
        final csv = etat.csv();

        expect(
          csv.codeUnitAt(0),
          0xFEFF,
          reason: 'sans BOM, Excel casse les accents',
        );
        expect(csv, contains('";"'));
        expect(
          csv,
          contains('"1000"'),
          reason: 'un tableur ne sait pas additionner « 1 000 FCFA »',
        );
        expect(csv, contains('"oui"'));
        expect(csv, contains(EtatJournalVentes.titre));
      },
    );

    test(
      'un règlement inconnu s’écrit « inconnu », jamais « non (note) »',
      () async {
        await venteComptant(modePaiement: null);
        final etat = EtatJournalVentes.composer(
          ventes: (await journal()).ventes,
          filtre: const FiltreVentes(),
        );

        expect(
          etat.cellules(etat.ventes.single).last,
          StatutVente.validee.code,
        );
        expect(etat.cellules(etat.ventes.single)[6], 'inconnu');
        expect(etat.csv(), isNot(contains('"non (note)"')));
      },
    );

    test('le PDF du journal se compose réellement', () async {
      await venteComptant();
      final etat = EtatJournalVentes.composer(
        ventes: (await journal()).ventes,
        filtre: const FiltreVentes(statut: StatutVente.validee),
      );
      // Un document qui ne se compose pas n'existe pas : le seul moyen de le
      // savoir est de l'écrire réellement.
      expect((await etat.pdf()).length, greaterThan(1000));
    });
  });

  /* ================================================================== */
  group('Le document d’une vente n’affirme aucun statut fiscal', () {
    test('sans facture, il le dit', () async {
      await venteComptant();
      final etat = EtatVente(vente: (await journal()).ventes.single);

      expect(EtatVente.titre, 'Détail de la vente');
      expect(EtatVente.titre, isNot(contains('Facture')));
      expect(etat.mentionPortee, contains('ne vaut pas facture'));
      expect(etat.mentionPortee, contains('aucune facture'));
      expect((await etat.pdf()).length, greaterThan(1000));
    });

    test(
      'avec facture, il RAPPELLE le numéro sans prétendre en être une',
      () async {
        final panier = await venteComptant();
        final piece = await factures.emettre(
          BrouillonFacture(
            origine: OrigineFacture.posComptant,
            clientNom: 'Client de passage',
            panierId: panier.id,
            lignes: const [
              LigneBrouillon(
                module: ModuleFacturable.m5Bar,
                libelle: 'Béninoise 33cl',
                prixUnitaire: 1000,
                quantite: 1,
              ),
            ],
          ),
        );

        final etat = EtatVente(vente: (await journal()).ventes.single);
        expect(etat.mentionPortee, contains('ne vaut pas facture'));
        expect(etat.mentionPortee, contains(piece.numero));
      },
    );
  });

  /* ================================================================== */
  group('La référence affichée n’est pas un numéro de vente', () {
    test('elle ne prend jamais la forme « V-AAAA-NNNNN »', () async {
      await venteComptant();
      final v = (await journal()).ventes.single;

      expect(v.referenceLocale, isNot(startsWith('V-')));
      expect(v.referenceLocale, hasLength(8));
      expect(
        RegExp(r'^[0-9A-F]{8}$').hasMatch(v.referenceLocale),
        isTrue,
        reason:
            'la référence est l’identifiant réel de la vente, abrégé — pas un '
            'numéro fabriqué à l’affichage, que deux postes hors ligne '
            'attribueraient en double',
      );
    });
  });
}
