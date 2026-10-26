import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/features/pos/data/panier_dao.dart';
import 'package:tatacora_flutter/features/pos/data/panier_repository_local.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/article_vendable.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/panier.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/reference_catalogue.dart';
import 'package:tatacora_flutter/features/pos/presentation/providers_pos.dart';
import 'package:tatacora_flutter/features/ventes/domain/journal_ventes.dart';
import 'package:tatacora_flutter/features/ventes/presentation/providers_ventes.dart';

import '../facturation/support/outils_encaissement.dart'
    show ouvrirLaCaisseDuComptoir;
import 'support/outils_ventes.dart';

/// Tourisme et location s'encaissent au comptoir (22/10/2026) : la vente
/// CLÔTURÉE arrive à l'historique des ventes et au journal du jour, avec ses
/// bons modules, et ne se dit jamais « sans impact sur le stock » (une
/// prestation n'a aucun stock à sortir : ce n'est pas une fiche vide).
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late PanierDao dao;
  late ProviderContainer c;

  final jour = DateTime(2026, 10, 26, 10);

  const circuit = ArticleVendable(
    reference: ReferenceCatalogue(
      module: ModuleVendable.m9Tourisme,
      code: 'cir-1',
    ),
    libelle: 'Cascades de Tanougou',
    prix: 4500,
  );
  const location = ArticleVendable(
    reference: ReferenceCatalogue(
      module: ModuleVendable.m8Vehicules,
      code: 'veh-1',
    ),
    libelle: '4x4 AB-123-CD',
    prix: 65000,
  );

  setUp(() async {
    db = AppDatabase.enMemoire();
    await avecComptabilite(db, maintenant: jour);
    await ouvrirLaCaisseDuComptoir(db);
    dao = panierDaoSur(db, horloge: jour);
    await db
        .into(db.circuitsLocal)
        .insert(
          CircuitsLocalCompanion.insert(
            id: 'cir-1',
            nom: 'Cascades de Tanougou',
            theme: 'Nature',
            zone: 'Atacora',
            prix: 4500,
            capaciteMax: 12,
          ),
        );
    await db
        .into(db.vehiculesLocal)
        .insert(
          VehiculesLocalCompanion.insert(
            id: 'veh-1',
            categorie: '4x4',
            immatriculation: 'AB-123-CD',
            tarifJour: 65000,
            statut: 'disponible',
          ),
        );
    c = ProviderContainer(
      overrides: [
        baseLocaleProvider.overrideWithValue(db),
        depotPanierProvider.overrideWithValue(PanierRepositoryLocal(dao)),
      ],
    );
  });

  tearDown(() async {
    c.dispose();
    await db.close();
  });

  Future<JournalVentes> journal() async {
    final ecoute = c.listen(journalVentesProvider, (_, _) {});
    try {
      return await c.read(journalVentesProvider.future);
    } finally {
      ecoute.close();
    }
  }

  test('une vente de circuit et de véhicule est au journal, ventilée par '
      'activité, sans « impact stock » à signaler', () async {
    var p = await dao.ouvrir(
      typeVente: TypeVente.comptant,
      pointVente: 'Comptoir',
    );
    p = await dao.ajouterLigne(p.id, circuit, quantite: 2);
    p = await dao.ajouterLigne(p.id, location, quantite: 3);
    await dao.cloturer(
      p.id,
      modePaiement: 'especes',
      auteurId: caissierDeVente,
    );

    final vente = (await journal()).ventes.single;
    expect(vente.id, p.id);
    expect(vente.estValidee, isTrue);
    expect(vente.montant, 2 * 4500 + 3 * 65000);
    expect(vente.activites, [
      ModuleVendable.m8Vehicules,
      ModuleVendable.m9Tourisme,
    ]);
    expect(vente.ventilation, {
      ModuleVendable.m8Vehicules: 195000,
      ModuleVendable.m9Tourisme: 9000,
    });
    expect(vente.aDesLignesSansImpactStock, isFalse);
  });
}
