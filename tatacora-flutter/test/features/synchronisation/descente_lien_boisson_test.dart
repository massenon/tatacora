import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/bar/data/boissons_api.dart';
import 'package:tatacora_flutter/features/bar/domain/entities/boisson.dart';
import 'package:tatacora_flutter/features/pos/data/catalogue_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/descente_catalogue.dart';

import 'support/faux_transport.dart';

/// La DESCENTE reprend le LIEN d’une boisson : l’article et son conditionnement
/// (`unites_vendables_par_unite_stock`), quand un autre poste ou le bureau les
/// change — et ne l’écrase pas tant que la modification du poste n’est pas
/// partie.
///
/// Une table répliquée a deux moitiés (piège 11) : « Lier au stock » monte le
/// lien (`lien_stock_poste_test.dart`), ce fichier prouve qu’il redescend.
void main() {
  late BancSync b;

  setUp(() async {
    b = await BancSync.creer();
    await b.semerAuteur();
  });
  tearDown(() => b.fermer());

  Map<String, Object?> article(String libelle) => {
    'libelle': libelle,
    'categorie': 'Boissons',
    'unite_mesure': 'casier',
    'point_stockage_id': null,
    'suivi': 'permanent',
    'seuil_alerte': '2.00',
  };

  Map<String, Object?> boisson(String articleId, String unites) => {
    'libelle': 'Béninoise 33 cl',
    'article_id': articleId,
    'categorie': 'locale',
    'prix_vente': '500.00',
    'unites_vendables_par_unite_stock': unites,
  };

  List<Map<String, Object?>> premierJournal() => [
    element('articles', 'art-a', article('Casier Béninoise')),
    element('articles', 'art-b', article('Fût Flag')),
    element('cartes_boisson', 'b-1', boisson('art-a', '24.0000')),
  ];

  Future<Map<String, Object?>> ligneBoisson() async =>
      (await b.db
              .customSelect(
                'SELECT article_id, unites_vendables FROM cartes_boisson_local '
                "WHERE id = 'b-1'",
              )
              .getSingle())
          .data;

  test('l’article et le conditionnement du serveur sont repris, puis REPRIS '
      'quand le lien change', () async {
    final appairage = (await b.lecteur.appairage())!;
    Future<BilanDescente> descente(List<Map<String, Object?>> elements) async {
      final cat = FauxCatalogue(elements);
      return b
          .descente(FauxTransport((r) => cat.repondre(r)))
          .descendre(appairage, surRefus: (_) async {});
    }

    final premier = await descente(premierJournal());
    expect((premier.appliques, premier.refuses), (3, 0), reason: '$premier');
    expect(await ligneBoisson(), {
      'article_id': 'art-a',
      'unites_vendables': '24.0000',
    });

    // Le bureau (ou un autre poste) change l’article ET le conditionnement.
    // (Le faux serveur est un journal : la page suivante part du curseur `c3`.)
    final second = await descente([
      ...premierJournal(),
      element('cartes_boisson', 'b-1', boisson('art-b', '66.5000')),
    ]);
    expect((second.appliques, second.refuses), (1, 0), reason: '$second');
    expect(await ligneBoisson(), {
      'article_id': 'art-b',
      'unites_vendables': '66.5000',
    });
  });

  test('un lien posé sur le poste et pas encore envoyé n’est PAS écrasé par '
      'la descente', () async {
    final appairage = (await b.lecteur.appairage())!;
    Future<BilanDescente> descente(List<Map<String, Object?>> elements) async {
      final cat = FauxCatalogue(elements);
      return b
          .descente(FauxTransport((r) => cat.repondre(r)))
          .descendre(appairage, surRefus: (_) async {});
    }

    await descente(premierJournal());

    // Le poste change le lien (file : `en_attente`)…
    final api = BoissonsApi(CatalogueDao(b.db));
    final r = await api.lierAuStock(
      id: 'b-1',
      articleId: 'art-b',
      unitesVendablesParUniteStock: '12',
    );
    expect(r, isA<BarRecu<Boisson>>(), reason: r is BarRefuse ? '$r' : null);

    // … et la descente suivante rapporte l’ANCIEN lien du serveur.
    await descente([
      ...premierJournal(),
      element('cartes_boisson', 'b-1', boisson('art-a', '24.0000')),
    ]);

    expect(await ligneBoisson(), {
      'article_id': 'art-b',
      'unites_vendables': '12',
    });
  });
}
