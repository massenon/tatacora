import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/bar/data/boissons_api.dart';
import 'package:tatacora_flutter/features/bar/domain/entities/ventes_bar.dart';
import 'package:tatacora_flutter/features/pos/data/catalogue_dao.dart';
import 'package:tatacora_flutter/features/pos/data/panier_dao.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/article_vendable.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/panier.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/reference_catalogue.dart';
import 'package:tatacora_flutter/features/synchronisation/data/descente_catalogue_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/descente_catalogue.dart';
import 'package:tatacora_flutter/features/ventes/domain/lignes_vente_du_rayon.dart';

import '../facturation/support/outils_encaissement.dart';
import '../pos/support/outils_ventes.dart';
import 'support/faux_transport.dart';

/// Le NUMÉRO `V-` et l'AUTEUR d'une vente sur le poste — 26/10/2026 (v38).
///
/// Le numéro est une séquence continue du SERVEUR : le poste ne l'invente pas
/// (deux postes hors ligne attribueraient les mêmes). Il le REÇOIT, par deux
/// chemins prouvés ici — l'accusé de l'envoi et la descente de la vente — et ne
/// l'affiche qu'alors ; avant, « — ». L'auteur est le compte connecté à la
/// clôture, ou le `par` que le serveur rend pour la vente d'un autre poste.
void main() {
  late BancSync b;
  late PanierDao paniers;

  const biere = ArticleVendable(
    reference: ReferenceCatalogue(module: ModuleVendable.m5Bar, code: 'bsn-33'),
    libelle: 'Béninoise 33cl',
    prix: 1000,
  );

  setUp(() async {
    b = await BancSync.creer();
    await avecComptabilite(b.db);
    await b.db
        .into(b.db.cartesBoissonLocal)
        .insert(
          CartesBoissonLocalCompanion.insert(
            id: 'bsn-33',
            articleId: 'art-bsn',
            libelle: 'Béninoise 33cl',
            categorie: 'locale',
            prixVente: 1000,
          ),
        );
    await ouvrirCaissePour(b.db);
    paniers = panierDaoSur(b.db);
  });
  tearDown(() => b.fermer());

  Future<Panier> vendre({int quantite = 3}) async {
    var p = await paniers.ouvrir(
      typeVente: TypeVente.comptant,
      pointVente: 'Comptoir',
    );
    p = await paniers.ajouterLigne(p.id, biere, quantite: quantite);
    return paniers.cloturer(
      p.id,
      modePaiement: 'especes',
      auteurId: caissierDeVente,
      anticipe: false,
    );
  }

  Future<Panier> relu(String id) async =>
      (await paniers.paniers()).singleWhere((p) => p.id == id);

  Future<BilanDescente> descendre(List<Map<String, Object?>> elements) async {
    await DescenteCatalogueDao(b.db).effacerCurseur();
    return b
        .descente(FauxTransport((r) => FauxCatalogue(elements).repondre(r)))
        .descendre((await b.lecteur.appairage())!, surRefus: (_) async {});
  }

  Map<String, Object?> venteDuServeur(
    String id, {
    String numero = 'V-2026-00042',
    String? par = 'caissier-b',
    String statut = 'validee',
  }) => element('ventes', id, {
    'numero': numero,
    'session_id': null,
    'point_vente': 'Bar',
    'client_id': null,
    'client_mention': null,
    'table_id': null,
    'montant_total': '1000.00',
    'mode_paiement': 'especes',
    'encaisse': true,
    'statut': statut,
    'motif_annulation': null,
    'annulee_at': null,
    'created_at': '2026-10-26 09:05:00',
    'date_creation': '2026-10-26 09:30:00',
    'par': par,
    'lignes': [
      {
        'code': 'bsn-33',
        'nom': 'Béninoise 33cl',
        'categorie': 'locale',
        'module': 'M5',
        'prix_unitaire': '1000.00',
        'quantite': 1,
        'montant': '1000.00',
      },
    ],
  });

  group('l’AUTEUR de la vente', () {
    test('la clôture écrit le login du compte connecté, et aucun numéro n’est '
        'inventé', () async {
      b.db.auteurEcriture = () => (login: 'awa.caisse', poste: 'CAISSE-1');

      final vente = await vendre();

      final p = await relu(vente.id);
      expect(p.auteurLogin, 'awa.caisse');
      expect(p.numeroVente, isNull, reason: 'le serveur seul numérote');
    });

    test('sans compte connecté : « — », jamais un système', () async {
      final vente = await vendre();
      expect((await relu(vente.id)).auteurLogin, isNull);
    });
  });

  group('le NUMÉRO, par l’accusé de l’envoi', () {
    test(
      'le numéro du serveur est posé sur le panier à l’accusé de la création '
      '— et sur elle seule',
      () async {
        final vente = await vendre();
        expect((await relu(vente.id)).numeroVente, isNull);

        final t = FauxTransport(
          (r) => reponseLot(
            r,
            particulier: (o) => o['table'] == 'ventes'
                ? {
                    'uuid_operation': o['uuid_operation'],
                    'statut': 'synchronise',
                    'entite_id': o['entite_id'],
                    'numero': 'V-2026-00007',
                  }
                : null,
          ),
        );
        await b.manager(t).synchroniserMaintenant();

        expect((await relu(vente.id)).numeroVente, 'V-2026-00007');
      },
    );

    test('une vente REJETÉE n’a pas de numéro', () async {
      final vente = await vendre();
      final t = FauxTransport(
        (r) => reponseLot(
          r,
          particulier: (o) => o['table'] == 'ventes'
              ? {
                  'uuid_operation': o['uuid_operation'],
                  'statut': 'rejete',
                  'entite_id': o['entite_id'],
                  'motif': 'Refus du serveur.',
                  'numero': 'V-2026-99999',
                }
              : null,
        ),
      );
      await b.manager(t).synchroniserMaintenant();

      expect((await relu(vente.id)).numeroVente, isNull);
    });
  });

  group('le NUMÉRO et l’AUTEUR, par la descente', () {
    test(
      'la vente d’un autre poste arrive avec son numéro et son auteur',
      () async {
        final bilan = await descendre([venteDuServeur('srv-v1')]);

        expect(bilan.refuses, 0, reason: bilan.motifsRefus.join(' ; '));
        final p = await relu('srv-v1');
        expect(p.numeroVente, 'V-2026-00042');
        expect(p.auteurLogin, 'caissier-b');
      },
    );

    test('un serveur qui ne dit rien de l’auteur : « — »', () async {
      await descendre([venteDuServeur('srv-v1', par: null)]);
      expect((await relu('srv-v1')).auteurLogin, isNull);
    });

    test('la vente de CE poste dont la réponse s’est perdue reçoit son numéro '
        'à la descente — et garde son auteur local', () async {
      b.db.auteurEcriture = () => (login: 'awa.caisse', poste: 'CAISSE-1');
      final vente = await vendre();
      // Le serveur a bien reçu la vente (l'opération est aboutie) mais le numéro
      // du résultat n'est pas revenu : tant qu'une opération attend, la descente
      // CONSERVE le panier local (règle commune de l'aligneur).
      await b.db.customStatement(
        "UPDATE operations_sync_local SET statut = 'synchronise'",
      );

      await descendre([venteDuServeur(vente.id, numero: 'V-2026-00011')]);

      final p = await relu(vente.id);
      expect(p.numeroVente, 'V-2026-00011');
      expect(
        p.auteurLogin,
        'awa.caisse',
        reason:
            'l’auteur local n’est pas '
            'écrasé',
      );
    });
  });

  group('l’écran « Ventes du Bar » : numéro et utilisateur', () {
    test(
      'le numéro V- et l’utilisateur s’affichent ; avant le numéro : « — »',
      () async {
        b.db.auteurEcriture = () => (login: 'awa.caisse', poste: 'CAISSE-1');
        final envoyee = await vendre();
        final locale = await vendre(quantite: 1);
        await paniers.regulariserNumeroVente(envoyee.id, 'V-2026-00001');

        final source = BoissonsApi(
          CatalogueDao(b.db),
          sourceVentes: paniers.paniers,
        );
        final page =
            (await source.ventes(const FiltreVentesBar())
                    as BarRecu<PageVentesBar>)
                .donnees;

        final parNumero = {for (final l in page.lignes) l.numero: l};
        expect(parNumero.keys.toSet(), {'V-2026-00001', null});
        expect(parNumero['V-2026-00001']!.utilisateur, 'awa.caisse');
        expect(parNumero[null]!.utilisateur, 'awa.caisse');
        expect(locale.id, isNot(envoyee.id));
      },
    );

    test('la recherche de la vue trouve par numéro et par login', () {
      final p = Panier(
        id: 'p',
        typeVente: TypeVente.comptant,
        statut: StatutPanier.cloture,
        ouvertLe: DateTime(2026, 10, 26, 9),
        clotureLe: DateTime(2026, 10, 26, 9),
        numeroVente: 'V-2026-00001',
        auteurLogin: 'awa.caisse',
        lignes: [
          LignePanier(
            id: 'l',
            reference: const ReferenceCatalogue(
              module: ModuleVendable.m5Bar,
              code: 'x',
            ),
            libelle: 'Bière',
            prixUnitaire: 1000,
            quantite: 1,
            ajouteeLe: DateTime(2026, 10, 26, 9),
          ),
        ],
      );
      for (final terme in ['00001', 'awa']) {
        expect(
          lignesDuRayon(
            [p],
            ModuleVendable.m5Bar,
            FiltreVentesBar(recherche: terme),
          ),
          hasLength(1),
          reason: terme,
        );
      }
      expect(
        lignesDuRayon(
          [p],
          ModuleVendable.m5Bar,
          const FiltreVentesBar(recherche: 'zzz'),
        ),
        isEmpty,
      );
    });
  });
}
