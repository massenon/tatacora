import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../../../core/di/providers.dart';
import '../../../core/fichiers/enregistrement_export.dart';
import '../../../core/impression/entete_parametree.dart';
import '../impression/etat_carte.dart';
import '../impression/etat_ventes_bar.dart';

import '../../pos/data/dto/catalogue_dto.dart';
import '../../pos/data/indisponibilites_carte_dao.dart';
import '../../pos/domain/entities/reference_catalogue.dart';
import '../../pos/presentation/providers_pos.dart';
import '../../stocks/presentation/providers_stocks.dart' show stocksDaoProvider;
import '../data/boissons_api.dart';
import '../domain/apercu_lien.dart';
import '../domain/entities/boisson.dart';
import '../domain/entities/carte_bar.dart';
import '../domain/entities/trace_prix.dart';
import '../domain/entities/ventes_bar.dart';
import 'providers_catalogue_boissons.dart';

/// La carte **locale** — libellés, catégories et prix, répliqués (PA-129).
///
/// Elle est lue par le même `CatalogueDao` que le point de vente : deux
/// lectures écrites séparément finiraient par vendre autre chose que ce que
/// la carte affiche.
final carteLocaleProvider = FutureProvider<List<LigneCarte>>((ref) async {
  final catalogue = ref.watch(catalogueProvider);
  final rayons = await catalogue.rayons();
  final bar = rayons.where((r) => r.module == ModuleVendable.m5Bar);
  // Le lien de stock RÉPLIQUÉ (PA-199) : il valait `null` ici jusqu'au
  // 11/09/2026, et hors connexion la bande et l'onglet Couverture auraient
  // compté toute la carte « sans lien ». La réponse serveur, quand elle
  // arrive, le remplace ([composerCarte]).
  final liens = await catalogue.liensDeStockDesBoissons();
  // Les retraits EN COURS, écrits ici ou descendus : le poste SAIT l'état de
  // chaque ligne, donc « Rendre indispo. » / « Remettre » sont offerts.
  final retraits = await IndisponibilitesCarteDao(
    ref.watch(baseLocaleProvider),
  ).boissonsRetirees();

  // La colonne « Article de stock » (vue l.373-380) : le libellé de l'article
  // lié et son conditionnement en clair (« 24 par casier »), lus des tables
  // LOCALES — `articles_local` et `cartes_boisson_local.unites_vendables`.
  // Un lien dont l'article n'est pas (encore) sur ce poste reste lié, sans
  // libellé : la cellule dit « non consulté », pas « aucun article ».
  final dao = ref.watch(catalogueDaoProvider);
  final facteurs = {
    for (final b in await dao.boissonsDuCatalogue()) b.id: b.unitesVendables,
  };
  final articles = <String, ArticleDeStock?>{
    for (final articleId in liens.values.toSet())
      articleId: await dao.articleDeStock(articleId),
  };

  return bar
      .expand((r) => r.articles)
      .map((a) {
        final article = articles[liens[a.reference.code]];
        final facteur = facteurs[a.reference.code];
        return LigneCarte(
          id: a.reference.code,
          libelle: a.libelle,
          categorie: a.categorie ?? '',
          prix: a.prix ?? 0,
          articleId: liens[a.reference.code],
          stock: null,
          indisponibilite: retraits[a.reference.code],
          disponibiliteConnue: true,
          lienLibelle: article?.libelle,
          lienDetail: article == null || facteur == null
              ? null
              : conversionLisible(facteur, article.uniteMesure),
        );
      })
      .toList(growable: false);
});

/// Le stock, **inconnu de ce poste** depuis le 14/09/2026.
///
/// ⚠ Il était demandé au serveur (`CatalogueApi.boissons()`), seul à savoir le
/// calculer : il vit sur les tables M6, absentes du périmètre local et
/// délibérément vides (PA-134). Le poste est zéro réseau — plus personne ne le
/// calcule, et le client ne doit surtout pas s'y essayer.
///
/// **`null`, et jamais une liste vide.** `composerCarte` lit `null` comme « on
/// ne sait pas » et la colonne affiche « non consulté » ; une liste vide se
/// lirait « aucune boisson en stock », c'est-à-dire une rupture générale —
/// un chiffre faux, plausible, sur l'écran même qui sert à commander
/// (PA-129, PA-199). La carte, ses libellés et ses prix continuent de
/// s'afficher : ils viennent du catalogue LOCAL répliqué.
///
/// Le jour où un inventaire local existera, c'est ici qu'il se branche.
final stockBarProvider = FutureProvider<List<BoissonDistante>?>(
  (ref) async => null,
);

/// La carte telle que l'écran l'affiche, avant filtres.
final carteBarProvider = FutureProvider<List<LigneCarte>>((ref) async {
  final local = await ref.watch(carteLocaleProvider.future);
  final distantes = await ref.watch(stockBarProvider.future);

  return composerCarte(local: local, distantes: distantes);
});

/// Les deux onglets du maître, dans son ordre — `m5-bar-carte.html` l.53-54.
///
/// `carte-module.js` l.419 les enregistre sous ces deux clés, et l.35 pose
/// `carte` comme actif par défaut.
///
/// Le troisième, « Ventes du Bar », est un AJOUT de la vue au maître (Product
/// Owner, 03/09/2026 — `pwa/carte/corps.blade.php` l.218-226, libellé
/// `carte_pwa.bar.onglet_ventes`), porté le 11/09/2026 (PA-197).
enum OngletCarteBar {
  carteDuJour('carte', 'Carte du jour'),
  couvertureDuStock('couverture', 'Couverture du stock'),
  ventes('ventes', 'Ventes du Bar');

  const OngletCarteBar(this.cle, this.libelle);

  final String cle;
  final String libelle;
}

final ongletCarteBarProvider =
    NotifierProvider<_OngletNotifier, OngletCarteBar>(_OngletNotifier.new);

final class _OngletNotifier extends Notifier<OngletCarteBar> {
  @override
  OngletCarteBar build() => OngletCarteBar.carteDuJour;

  void definir(OngletCarteBar valeur) => state = valeur;
}

/// La couverture, **calculée sur la carte locale** — donc hors ligne.
///
/// Trois choix, chacun pour une raison :
///
///  - source [carteLocaleProvider] et non [carteBarProvider] : ce dernier
///    attend `stockBarProvider`, c'est-à-dire le réseau. Le décompte par
///    catégorie ne doit rien lui devoir — il vient de `cartes_boisson_local` ;
///  - carte **non filtrée**, comme le maître (l.150) ;
///  - aucun taux, aucun décompte de liens : voir [CouvertureCategorieBar].
///
/// Depuis PA-200, la réponse serveur l'enrichit QUAND ELLE EST DÉJÀ LÀ —
/// retraits et prix provisoires — sans jamais l'attendre : `.value` d'un
/// fournisseur en cours vaut `null`, et la carte locale suffit alors.
final couvertureBarProvider = FutureProvider<List<CouvertureCategorieBar>>((
  ref,
) async {
  final locale = await ref.watch(carteLocaleProvider.future);
  final distantes = ref.watch(stockBarProvider).value;

  return couvertureParCategorie(
    composerCarte(local: locale, distantes: distantes),
  );
});

final rechercheCarteProvider = NotifierProvider<_RechercheNotifier, String>(
  _RechercheNotifier.new,
);

final class _RechercheNotifier extends Notifier<String> {
  @override
  String build() => '';

  void definir(String terme) => state = terme;
}

final categorieCarteProvider = NotifierProvider<_CategorieNotifier, String?>(
  _CategorieNotifier.new,
);

final class _CategorieNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void definir(String? categorie) => state = categorie;
}

final etatCarteProvider = NotifierProvider<_EtatNotifier, EtatCarte>(
  _EtatNotifier.new,
);

final class _EtatNotifier extends Notifier<EtatCarte> {
  @override
  EtatCarte build() => EtatCarte.tous;

  void definir(EtatCarte etat) => state = etat;
}

/// La carte **filtrée** — c'est elle que les exports emportent (PA-119).
final carteFiltreeProvider = FutureProvider<List<LigneCarte>>((ref) async {
  final lignes = await ref.watch(carteBarProvider.future);

  return filtrerCarte(
    lignes,
    terme: ref.watch(rechercheCarteProvider),
    categorie: ref.watch(categorieCarteProvider),
    etat: ref.watch(etatCarteProvider),
  );
});

// Les catégories du filtre ne sont plus DÉRIVÉES de la carte (08/10/2026) :
// la vue offre toujours son registre fermé (`CarteBoisson::CATEGORIES`, corps
// l.241), que le client lit dans `CategorieBoisson`. Une liste dérivée des
// lignes se vidait avec la carte et ne montrait jamais une catégorie encore
// sans article.

/* ====================================================================== */
/* « Nouvelle boisson » — corps partagé `carte/corps`, l.110-120, 717-774  */
/* ====================================================================== */

/// Crée une boisson **sur ce poste** — décision du PO du 14/09/2026.
///
/// @see EF-M5-02 Carte des boissons
///
/// ## Il n'y a plus de « puis » : l'écriture EST locale
///
/// Jusqu'au 14/09/2026, ce fournisseur écrivait au serveur puis **descendait**
/// la réponse dans la carte locale, et rendait un couple disant si les deux
/// avaient réussi. Le poste est zéro réseau : l'écriture locale est la seule,
/// elle réussit ou elle échoue, et il n'y a plus de second état à annoncer.
///
/// La boisson naît **sans lien de stock** : aucun article n'est répliqué ici
/// (PA-134). La carte l'affichera « non suivi » — voir [SaisieBoisson].
final creerBoissonProvider =
    Provider<Future<ResultatBar<Boisson>> Function(SaisieBoisson)>(
      (ref) => (saisie) async {
        final resultat = await ref
            .read(boissonsApiProvider)
            .enregistrer(saisie);
        if (resultat is BarRecu<Boisson>) _rafraichirCatalogue(ref);
        return resultat;
      },
    );

/// Renomme et reclasse une boisson — la modale « Modifier la boisson — » de la
/// vue. Le prix et le lien au stock ne bougent pas (`BoissonsApi.modifier`).
final modifierBoissonProvider =
    Provider<
      Future<ResultatBar<Boisson>> Function(
        String id, {
        required String libelle,
        required CategorieBoisson categorie,
      })
    >(
      (ref) => (id, {required libelle, required categorie}) async {
        final resultat = await ref
            .read(boissonsApiProvider)
            .modifier(id, libelle: libelle, categorie: categorie);
        if (resultat is BarRecu<Boisson>) _rafraichirCatalogue(ref);
        return resultat;
      },
    );

/// Change le PRIX d'une boisson — la modale « Modifier le prix — » de la vue.
///
/// @see EF-M5-02 Carte des boissons
///
/// ## Le prix, et RIEN d'autre
///
/// `BoissonsApi.modifierPrix` relit le libellé et la catégorie **au catalogue**
/// juste avant d'écrire, plutôt que de les reprendre de la ligne affichée : la
/// carte à l'écran peut dater d'avant une modification faite ailleurs, et le
/// changement de prix les écraserait sans un mot.
///
/// ⚠ **Une ligne de panier déjà saisie n'est jamais réécrite** : son prix et
/// son libellé sont figés à l'ajout (règle 3). Le catalogue dit ce qu'on vend
/// aujourd'hui, la ligne dit ce qui a été servi.
///
/// La marque « corrigé à la main » n'est pas posée : aucune colonne ne la
/// porte au schéma local — voir l'en-tête de `boissons_api.dart`.
final modifierPrixBoissonProvider =
    Provider<Future<ResultatBar<Boisson>> Function(String id, String prix)>(
      (ref) => (id, prix) async {
        final resultat = await ref
            .read(boissonsApiProvider)
            .modifierPrix(id, prix);
        if (resultat is BarRecu<Boisson>) _rafraichirCatalogue(ref);
        return resultat;
      },
    );

/// « Lier au stock » / « Modifier le lien » — écrit l'article ET son
/// conditionnement dans la carte locale (et la file d'envoi), puis recharge ce
/// qui lit le catalogue (26/10/2026).
///
/// ⚠ `lierAuStockProvider` avait été RETIRÉ le 14/09/2026 : ni article ni
/// colonne de conditionnement n'existaient sur le poste. Les deux existent
/// (`articles_local`, `cartes_boisson_local.unites_vendables` v30).
final lierAuStockProvider =
    Provider<
      Future<ResultatBar<Boisson>> Function({
        required String id,
        required String articleId,
        required String unitesVendablesParUniteStock,
      })
    >(
      (ref) =>
          ({
            required id,
            required articleId,
            required unitesVendablesParUniteStock,
          }) async {
            final resultat = await ref
                .read(boissonsApiProvider)
                .lierAuStock(
                  id: id,
                  articleId: articleId,
                  unitesVendablesParUniteStock: unitesVendablesParUniteStock,
                );
            if (resultat is BarRecu<Boisson>) _rafraichirCatalogue(ref);
            return resultat;
          },
    );

/// Les articles de stock proposés par la recherche des deux modales — suivi
/// permanent seulement (`articlesDeStock()` de la vue). `autoDispose` : un
/// article créé dans Stocks pendant que la modale était fermée doit y être.
final articlesDeStockProvider = FutureProvider.autoDispose
    .family<List<ArticleDeStock>, String>(
      (ref, terme) =>
          ref.watch(catalogueDaoProvider).articlesDeStockLiables(terme: terme),
    );

/// Le solde d'un article au point « bar », pour l'aperçu de « Lier au stock »
/// (« Stock actuel »). `null` : non consultable — aucun point de type « bar »,
/// ou article inconnu ; jamais un zéro, qui se lirait « rupture ».
final soldeAuBarProvider = FutureProvider.autoDispose.family<String?, String>((
  ref,
  articleId,
) async {
  final stocks = ref.watch(stocksDaoProvider);
  final bar = (await stocks.points()).where((p) => p.type == 'bar').firstOrNull;
  if (bar == null) return null;
  final fiche = await stocks.articlesFiche(pointId: bar.id);
  return fiche.where((a) => a.id == articleId).firstOrNull?.stock;
});

/// « Rendre indispo. » — écrit le retrait dans la base locale et le met en
/// file (v31, 21/10/2026) ; recharge la carte pour que la ligne passe à
/// « Retirés du jour ».
final retirerDeLaCarteProvider =
    Provider<
      Future<ResultatBar<Boisson>> Function({
        required String id,
        required String motif,
        String? commentaire,
      })
    >(
      (ref) => ({required id, required motif, commentaire}) async {
        final r = await ref
            .read(boissonsApiProvider)
            .retirer(id: id, motif: motif, commentaire: commentaire);
        ref.invalidate(carteLocaleProvider);
        return r;
      },
    );

/// « Remettre » — ferme le retrait en cours et recharge la carte.
final remettreALaCarteProvider =
    Provider<Future<ResultatBar<Boisson>> Function(String id)>(
      (ref) => (id) async {
        final r = await ref.read(boissonsApiProvider).remettre(id);
        ref.invalidate(carteLocaleProvider);
        return r;
      },
    );

/// L'historique des prix d'une boisson, relu dans la table locale à chaque
/// ouverture de la modale — `autoDispose`, sans cache : une liste gardée d'une
/// visite précédente ne dirait pas qu'elle date, sur la question même « depuis
/// quand ce prix ? ».
final historiquePrixProvider = FutureProvider.autoDispose
    .family<ResultatBar<List<TracePrix>>, String>(
      (ref, id) => ref.watch(boissonsApiProvider).historiquePrix(id),
    );

/// Les filtres de l'onglet « Ventes du Bar » — propres à l'onglet.
///
/// Tout filtre qui change REMET LA PAGE À 1 : sans cela, restreindre sa plage
/// depuis la page 4 montrerait une liste vide sous un filtre qui retient des
/// lignes (même règle que `EcranDeCarte::updated()` dans la PWA).
final filtreVentesBarProvider =
    NotifierProvider<_FiltreVentesNotifier, FiltreVentesBar>(
      _FiltreVentesNotifier.new,
    );

final class _FiltreVentesNotifier extends Notifier<FiltreVentesBar> {
  @override
  FiltreVentesBar build() => const FiltreVentesBar();

  void recherche(String terme) => state = FiltreVentesBar(
    recherche: terme,
    statut: state.statut,
    du: state.du,
    au: state.au,
  );

  void statut(StatutVenteBar? statut) => state = FiltreVentesBar(
    recherche: state.recherche,
    statut: statut,
    du: state.du,
    au: state.au,
  );

  void du(DateTime? jour) => state = FiltreVentesBar(
    recherche: state.recherche,
    statut: state.statut,
    du: jour,
    au: state.au,
  );

  void au(DateTime? jour) => state = FiltreVentesBar(
    recherche: state.recherche,
    statut: state.statut,
    du: state.du,
    au: jour,
  );

  /// La SEULE modification qui garde les filtres ET change la page.
  void page(int page) => state = FiltreVentesBar(
    recherche: state.recherche,
    statut: state.statut,
    du: state.du,
    au: state.au,
    page: page < 1 ? 1 : page,
  );
}

/// La page de lignes, CALCULÉE sur les paniers du poste à chaque changement
/// de filtre — sans cache : une liste gardée d'une visite précédente ne dirait
/// pas qu'elle date.
final ventesBarProvider =
    FutureProvider.autoDispose<ResultatBar<PageVentesBar>>((ref) {
      // Les ventes se calculent sur les paniers du poste : une vente encaissée
      // recompose l'onglet.
      ref.watch(paniersProvider);
      return ref
          .watch(boissonsApiProvider)
          .ventes(ref.watch(filtreVentesBarProvider));
    });

/// Recharge tout ce qui LIT le catalogue local, après une écriture.
///
/// Une seule fonction plutôt qu'un `invalidate` recopié dans chaque geste :
/// en oublier un laisse une boisson absente de l'écran alors qu'elle est en
/// base, et le barman la ressaisit.
///
/// ⚠ **`rayonsProvider` en fait partie, et c'est le point à ne pas perdre.**
/// Le catalogue du bar est aussi celui du POINT DE VENTE : une boisson créée
/// ici doit être vendable tout de suite. Sans cette invalidation, elle
/// n'apparaîtrait au comptoir qu'au prochain démarrage de l'application —
/// c'est-à-dire que l'écran de vente et l'écran de carte montreraient deux
/// catalogues différents, chacun se croyant à jour.
///
/// `stockBarProvider` n'y figure pas : il rend `null` par construction, et
/// l'invalider ferait croire qu'un stock peut changer ici.
void _rafraichirCatalogue(Ref ref) {
  ref
    ..invalidate(carteLocaleProvider)
    ..invalidate(rayonsProvider)
    ..invalidate(boissonsProvider);
}

/// Les documents de la carte, exposés comme **actions injectables**.
///
/// Jamais un `Printing.layoutPdf` recopié dans un écran : un test de widget n'a
/// pas de greffon natif, et il doit exister un seul endroit où l'impression est
/// déclenchée.
///
/// « Exporter » (PDF comme tableur) passe par la fenêtre « Enregistrer sous »
/// ([enregistrementExportProvider], 14/10/2026) et rend le CHEMIN écrit,
/// `null` : annulé. Seule la fiche des prix s'imprime encore directement.
final exporterCartePdfProvider =
    Provider<Future<String?> Function(List<LigneCarte>, String)>(
      (ref) =>
          (lignes, filtre) async => ref
              .read(enregistrementExportProvider)
              .exporter(
                base: 'carte_bar',
                type: TypeFichierEnregistre.pdf,
                octets: await EtatCarteBar.pdf(
                  lignes,
                  filtre: filtre,
                  entete: await ref.read(lireEnteteEtablissementProvider)(),
                ),
              ),
    );

/// Rend le **nombre d'articles écartés** faute de tarif : l'écran le dit.
final imprimerFichePrixProvider =
    Provider<Future<int> Function(List<LigneCarte>)>(
      (ref) => (lignes) async {
        final (octets, ecartes) = await EtatCarteBar.ficheDesPrix(
          lignes,
          entete: await ref.read(lireEnteteEtablissementProvider)(),
        );
        await Printing.layoutPdf(
          onLayout: (_) => octets,
          name: EtatCarteBar.titreFiche,
          format: PdfPageFormat.a4,
        );
        return ecartes;
      },
    );

/// Le document de l'onglet « Ventes du Bar » (PA-197), action injectable —
/// enregistré par la fenêtre « Enregistrer sous », rend le CHEMIN écrit.
///
/// Il reçoit le JEU FILTRÉ ENTIER déjà lu — la lecture (et son refus, sa
/// coupure) reste à l'écran, qui doit pouvoir dire pourquoi rien n'est produit.
final exporterVentesBarPdfProvider =
    Provider<
      Future<String?> Function(
        List<LigneVenteBar>,
        TotauxVentesBar,
        String filtre,
        List<LigneCarte> carte,
      )
    >(
      (ref) =>
          (lignes, totaux, filtre, carte) async => ref
              .read(enregistrementExportProvider)
              .exporter(
                base: 'ventes_du_bar',
                type: TypeFichierEnregistre.pdf,
                octets: await EtatVentesBar.pdf(
                  lignes,
                  totaux,
                  filtre: filtre,
                  carte: carte,
                  entete: await ref.read(lireEnteteEtablissementProvider)(),
                ),
              ),
    );

/// Le tableur de l'onglet « Ventes du Bar » — rend le **chemin** écrit,
/// `null` : annulé.
final exporterVentesBarProvider =
    Provider<
      Future<String?> Function(
        List<LigneVenteBar>,
        TotauxVentesBar,
        String filtre,
        List<LigneCarte> carte,
      )
    >(
      (ref) =>
          (lignes, totaux, filtre, carte) => ref
              .read(enregistrementExportProvider)
              .exporter(
                base: 'ventes_du_bar',
                type: TypeFichierEnregistre.csv,
                octets: EtatVentesBar.csvOctets(
                  lignes,
                  totaux,
                  filtre: filtre,
                  carte: carte,
                ),
              ),
    );

/// L'export tableur — rend le **chemin** du fichier écrit, `null` : annulé.
final exporterCarteProvider =
    Provider<Future<String?> Function(List<LigneCarte>, String)>(
      (ref) =>
          (lignes, filtre) => ref
              .read(enregistrementExportProvider)
              .exporter(
                base: 'carte_bar',
                type: TypeFichierEnregistre.csv,
                octets: EtatCarteBar.csvOctets(lignes, filtre: filtre),
              ),
    );
