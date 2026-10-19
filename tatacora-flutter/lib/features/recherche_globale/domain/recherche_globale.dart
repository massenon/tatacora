/// La RECHERCHE GLOBALE de la barre supérieure — réplique de
/// `App\Pwa\Livewire\Transverse\RechercheGlobale` du serveur (14/10/2026, lot B
/// du plan du PO). Ajout du PO à la maquette (audit du 01/09/2026), porté par
/// la vue : il fait foi.
///
/// ## Ce qu'elle cherche, et où elle mène — la règle du serveur
///
/// 1. **Les pages** : les entrées du menu latéral dont le nom contient le terme
///    (`mb_stripos`, casse ignorée), mêmes libellés et même filtre que la barre
///    latérale (droit de lecture sur le module, masquage par rôle). Cinq au plus.
/// 2. **Les données** : huit sources, chacune interrogée SEULEMENT si le compte
///    a accès à son module (`MenuLateral::moduleAccessible`). Cinq résultats par
///    source, triés par la dernière colonne affichée.
///
/// Rien n'est cherché sous deux caractères (`mb_strlen($terme) < 2`).
///
/// ## Écarts au serveur, nommés (14/10/2026)
///
/// * **Le terme ne suit pas le clic** : la vue ouvre l'écran avec `?q=` et
///   l'écran se filtre lui-même ; aucun écran de ce poste ne lit de paramètre
///   d'URL. L'écran s'ouvre non filtré, et un message le DIT
///   (`LibellesCoquille.rechercheEcranNonFiltre`).
/// * **Factures** : le serveur cherche `factures.numero_mecef` ; le registre
///   du poste n'a jamais de numéro MECeF (aucune certification réelle,
///   PA-17/PA-61) — chercher là ne trouverait jamais rien. Le numéro de pièce
///   `F-AAAA-NNNNN`, qui tient le même rôle à l'écran (`libelleDeLaFacture`),
///   est cherché à sa place. Seules les FACTURES au sens du serveur sont
///   lues : ni les avoirs (table `avoirs` au serveur), ni les tickets de vente
///   au comptant (table `ventes`) — `estUneCreance`.
/// * **Comparaison** : `LIKE` de SQLite ignore la casse des seules lettres
///   ASCII, et pas les accents ; la collation `utf8mb4_unicode_ci` du serveur
///   ignore les deux. « elise » trouve « Élise » au serveur, pas ici.
library;

import '../../../core/navigation/coquille_vue.dart';
import '../../../core/navigation/navigation_tatacora.dart';
import '../../../core/rbac/garde_acces.dart';

/// `RechercheGlobale::PLAFOND_PAR_FAMILLE`.
const int plafondRecherche = 5;

/// Les huit sources de données, dans l'ordre de `RechercheGlobale::SOURCES`.
enum FamilleRecherche {
  clients(
    LibellesCoquille.rechercheFamilleClients,
    ModuleTatacora.m3Crm,
    '/crm',
  ),
  articles(
    LibellesCoquille.rechercheFamilleArticles,
    ModuleTatacora.m6Stocks,
    '/stocks',
  ),
  plats(
    LibellesCoquille.rechercheFamillePlats,
    ModuleTatacora.m4Restaurant,
    '/restaurant/plats',
  ),
  carteBar(
    LibellesCoquille.rechercheFamilleCarteBar,
    ModuleTatacora.m5Bar,
    '/bar',
  ),
  factures(
    LibellesCoquille.rechercheFamilleFactures,
    ModuleTatacora.m2Facturation,
    '/facturation',
  ),
  fournisseurs(
    LibellesCoquille.rechercheFamilleFournisseurs,
    ModuleTatacora.m7Achats,
    '/fournisseurs',
  ),
  vehicules(
    LibellesCoquille.rechercheFamilleVehicules,
    ModuleTatacora.m8Vehicules,
    '/vehicules',
  ),
  circuits(
    LibellesCoquille.rechercheFamilleCircuits,
    ModuleTatacora.m9Tourisme,
    '/tourisme',
  );

  const FamilleRecherche(this.titre, this.module, this.route);

  /// Le titre de la famille dans le panneau (`pwa.recherche_globale.famille_*`).
  final String titre;

  /// Le module dont le droit de lecture ouvre la source.
  final ModuleTatacora module;

  /// L'écran Flutter du module (la route de la vue : `pwa.clients`,
  /// `pwa.stocks.liste`, `pwa.restaurant.plats`, `pwa.bar.carte`,
  /// `pwa.facturation`, `pwa.achats.liste`, `pwa.vehicules`, `pwa.tourisme`).
  final String route;
}

/// Un résultat « Pages » : une entrée du menu. [route] est `null` quand ce
/// poste n'a pas l'écran — le clic le DIT (Article 3.3).
final class ResultatPage {
  const ResultatPage({required this.nom, required this.route});

  final String nom;
  final String? route;
}

/// Ce que la recherche rend : les pages, puis les données famille par famille
/// (seules les familles NON vides, dans l'ordre des sources).
final class ResultatsRecherche {
  const ResultatsRecherche({required this.pages, required this.donnees});

  static const vide = ResultatsRecherche(pages: [], donnees: {});

  final List<ResultatPage> pages;
  final Map<FamilleRecherche, List<String>> donnees;

  bool get estVide => pages.isEmpty && donnees.isEmpty;
}

/// `mb_strlen(trim($terme)) >= 2`.
bool termeSuffisant(String terme) => terme.trim().runes.length >= 2;

/// Les pages du menu dont le nom contient [terme] — `MenuLateral::pour()` puis
/// `mb_stripos`. Le filtre est celui de la barre latérale : droit de lecture
/// sur le module ET masquage par rôle ; l'ordre est celui du menu (épinglées,
/// puis groupes) ; cinq au plus.
List<ResultatPage> pagesCorrespondantes({
  required GardeAcces droits,
  required String role,
  required String terme,
}) {
  final cherche = terme.trim().toLowerCase();
  final pages = <ResultatPage>[];
  for (final d in toutesLesDestinations) {
    if (!destinationVisible(d, droits: droits, role: role)) continue;
    if (!d.nom.toLowerCase().contains(cherche)) continue;
    pages.add(ResultatPage(nom: d.nom, route: d.route));
  }
  return pages.length <= plafondRecherche
      ? pages
      : pages.sublist(0, plafondRecherche);
}
