import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/caisse/data/sessions_caisse_dao.dart';
import 'package:tatacora_flutter/features/caisse/domain/entities/session_caisse.dart';
import 'package:tatacora_flutter/features/depenses/domain/categories_depense.dart';
import 'package:tatacora_flutter/features/depenses/domain/entities/depense.dart';
import 'package:tatacora_flutter/features/pos/data/catalogue_dao.dart';
import 'package:tatacora_flutter/features/pos/data/dto/catalogue_dto.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/article_vendable.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/panier.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/reference_catalogue.dart';
import 'package:tatacora_flutter/features/stocks/data/stocks_dao.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/etat_stock.dart';
import 'package:uuid/uuid.dart';

import '../../comptabilite/support/outils_comptabilite.dart';
import '../../depenses/support/outils_depenses.dart';
import '../../pos/support/outils_ventes.dart';

/// Les identifiants posés par [jouerJourneeDeCaisse].
final class JourneeDeCaisse {
  late String point;
  late String article;
  late String boisson;
  late String session;
  late String vente1;
  late String vente2;
  late String depense;
}

/// Une journée de comptoir RÉALISTE, par les VRAIS écrivains du poste (lot
/// F2a) : un article et sa carte créés HORS CONNEXION, la caisse ouverte,
/// deux ventes au comptant, une dépense de caisse, la caisse clôturée. Chaque
/// geste dépose son opération dans la file ; rien n'est écrit à la main dans
/// la file.
///
/// [jour] : 10 h du jour de la journée ; les gestes s'étalent jusqu'à 19 h.
Future<JourneeDeCaisse> jouerJourneeDeCaisse(
  AppDatabase db, {
  required DateTime jour,
}) async {
  final j = JourneeDeCaisse();
  const uuid = Uuid();
  await avecComptabilite(db, maintenant: jour);
  final stocks = StocksDao(db, maintenant: () => jour);

  j.point = (await stocks.creerPoint(
    libelle: 'Bar E2E ${uuid.v4().substring(0, 6)}',
    type: TypePoint.bar,
    id: uuid.v4(),
  )).id;
  j.article = uuid.v4();
  await stocks.creerArticle(
    id: j.article,
    libelle: 'Bière E2E ${uuid.v4().substring(0, 6)}',
    categorie: 'Boissons',
    uniteMesure: 'bouteille',
    seuilCentiemes: 600,
    suivi: SuiviArticle.permanent,
    pointStockageId: j.point,
    auteurId: auteurEssai,
  );
  j.boisson = uuid.v4();
  await CatalogueDao(db).enregistrerBoisson(
    BoissonDistante(
      id: j.boisson,
      articleId: j.article,
      libelle: 'Bière E2E',
      categorie: 'locale',
      prixVente: 1000,
      stockDisponible: null,
    ),
  );

  j.session = (await SessionsCaisseDao(db, maintenant: () => jour).ouvrir(
    point: PointDeVenteCaisse.bar,
    fondSaisi: '10000',
    auteurId: auteurEssai,
    peutEcrire: true,
  )).id;

  Future<String> vendre(int quantite, Duration apres) async {
    final paniers = panierDaoSur(db, horloge: jour.add(apres));
    var panier = await paniers.ouvrir(
      typeVente: TypeVente.comptant,
      pointVente: 'Bar',
    );
    panier = await paniers.ajouterLigne(
      panier.id,
      ArticleVendable(
        reference: ReferenceCatalogue(
          module: ModuleVendable.m5Bar,
          code: j.boisson,
        ),
        libelle: 'Bière E2E',
        prix: 1000,
      ),
      quantite: quantite,
    );
    return (await paniers.cloturer(
      panier.id,
      modePaiement: 'especes',
      auteurId: auteurEssai,
    )).id;
  }

  j.vente1 = await vendre(2, const Duration(hours: 1));
  j.vente2 = await vendre(3, const Duration(hours: 3));

  j.depense =
      (await depenseDaoSur(
            db,
            horloge: jour.add(const Duration(hours: 5)),
          ).enregistrer(
            dateTransaction: DateTime(jour.year, jour.month, jour.day),
            tresorerie: TresorerieDepense.caisse,
            libelle: 'Glace E2E',
            lignes: const [
              SaisieLigneDepense(
                libelle: 'Glace',
                compteCharge: '6011',
                nature: NatureDepense.tomate,
                montant: 1500,
              ),
            ],
            auteurId: auteurEssai,
            centreId: await centreDe(db, 'Restaurant'),
          ))
          .id;

  await SessionsCaisseDao(
    db,
    maintenant: () => jour.add(const Duration(hours: 9)),
  ).cloturer(
    point: PointDeVenteCaisse.bar,
    constateSaisi: '15000',
    peutEcrire: true,
    especesEncaisseesCentimes: 5000 * 100,
  );
  return j;
}
