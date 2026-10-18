import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/achats/data/reglements_fournisseur_dao.dart';
import 'package:tatacora_flutter/features/achats/domain/entities/reglement_fournisseur.dart';
import 'package:tatacora_flutter/features/comptabilite/data/comptabilite_dao.dart';
import 'package:tatacora_flutter/features/facturation/data/paiements_facture_dao.dart';
import 'package:tatacora_flutter/features/facturation/domain/entities/paiement_facture.dart';
import 'package:tatacora_flutter/features/pos/data/panier_dao.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/panier.dart';
import 'package:tatacora_flutter/features/synchronisation/data/aligneur_catalogue.dart';
import 'package:tatacora_flutter/features/synchronisation/data/descente_catalogue_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/descente_catalogue.dart';

import '../comptabilite/support/outils_comptabilite.dart' show moteurSur;
import '../facturation/support/outils_encaissement.dart';
import 'support/scenario_file.dart';

/// Lot F6 (décision du PO du 18/10/2026 : « le serveur doit aussi envoyer en
/// local ce qu'il a enregistré ») : quand le serveur ANNULE un document de CE
/// poste (une vente à la PWA, un encaissement), le poste suit — et contre-passe
/// SA pièce locale en entier, pour que son journal ne garde pas un argent que
/// le serveur a rendu. Un document d'un autre poste n'a pas de pièce ici :
/// seul l'état suit.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = await baseEncaissement();
    await semerBoisson(db);
    await ouvrirLaCaisseDuComptoir(db);
  });
  tearDown(() => db.close());

  /// Le serveur n'annule qu'un document qu'il a REÇU : la file est envoyée.
  Future<IssueAlignement> descendre(
    String table,
    String id,
    Map<String, Object?> donnees,
  ) async {
    await db.customStatement(
      "UPDATE operations_sync_local SET statut = 'synchronise'",
    );
    return db.transaction(
      () =>
          AligneurCatalogue(
            db,
            DescenteCatalogueDao(db),
            auteur: () async => caissierEssai,
            maintenant: () => jourEncaissement,
            moteur: () async =>
                moteurSur(db, maintenant: () => jourEncaissement),
          ).aligner(
            ElementCatalogue(
              table: TableDescendue.depuisNom(table)!,
              id: id,
              actif: true,
              modifieLe: '2026-10-12 12:00:00',
              donnees: donnees,
            ),
          ),
    );
  }

  /// Le solde net de chaque compte mouvementé : tout à zéro quand chaque
  /// pièce est contre-passée en entier.
  Future<Map<String, int>> soldes() async {
    final m = <String, int>{};
    for (final e in await ComptabiliteDao(db).toutesLesEcritures()) {
      m[e.compteId] = (m[e.compteId] ?? 0) + e.debitCentimes - e.creditCentimes;
    }
    return m;
  }

  Future<int> lignes() async =>
      (await ComptabiliteDao(db).toutesLesEcritures()).length;

  test('une vente de CE poste annulée au serveur : annulée ici, sa pièce '
      'contre-passée, une seule fois', () async {
    final vente = await vendreAuComptant(db, prix: 2000);
    final avant = await lignes();
    expect((await soldes()).values.any((v) => v != 0), isTrue);

    Map<String, Object?> annulee() => {
      'statut': 'annulee',
      'motif_annulation': 'Erreur de table',
      'mode_paiement': 'especes',
      'montant_total': '2000.00',
    };
    expect(await descendre('ventes', vente.id, annulee()), isA<Aligne>());
    expect(await descendre('ventes', vente.id, annulee()), isA<Aligne>());

    final p = (await PanierDao(db).parId(vente.id))!;
    expect(p.statut, StatutPanier.annule);
    expect((await soldes()).values.every((v) => v == 0), isTrue);
    expect(await lignes(), avant * 2, reason: 'contre-passée, une fois');
  });

  test('un encaissement de CE poste annulé au serveur : sa pièce est '
      'contre-passée ; le reste dû remonte', () async {
    final f = await emettreFacture(db, montant: 30000);
    final dao = paiementsDaoSur(db);
    final p = await dao.encaisser(
      pieceId: f.id,
      montant: '10000',
      mode: 'especes',
      auteurId: caissierEssai,
    );
    final avant = await lignes();

    final issue = await descendre('paiements', p.id, {
      'facture_id': f.id,
      'session_id': 'peu-importe',
      'mode_paiement': 'especes',
      'montant': '10000.00',
      'date_paiement': '2026-10-12 10:00:00',
      'statut': 'annule',
      'motif_annulation': 'Doublon',
      'date_annulation': '2026-10-12 11:00:00',
    });
    expect(issue, isA<Aligne>());

    expect(
      (await PaiementsFactureDao(db).parId(p.id))!.statut,
      StatutPaiementFacture.annule,
    );
    expect(await lignes(), avant + 2, reason: 'les deux lignes inverses');
    expect((await dao.creanceDe(f)).resteDuCentimes, 3000000);
  });

  test('un règlement fournisseur de CE poste annulé au serveur : sa pièce '
      'est contre-passée (journée complète du scénario)', () async {
    await db.close();
    db = AppDatabase.enMemoire();
    final journee = await jouerJourneeComplete(db);
    final avant = await lignes();

    final issue = await descendre('reglements_fournisseur', journee.reglement, {
      'commande_id': journee.commande,
      'montant': '5000.00',
      'tresorerie': 'caisse',
      'date_reglement': '2026-10-12',
      'statut': 'annule',
      'motif_annulation': 'Erreur de fournisseur',
      'date_annulation': '2026-10-12 15:00:00',
    });
    expect(issue, isA<Aligne>());
    expect(
      (await ReglementsFournisseurDao(db).parId(journee.reglement))!.statut,
      StatutReglement.annule,
    );
    expect(await lignes(), avant + 2);
  });
}
