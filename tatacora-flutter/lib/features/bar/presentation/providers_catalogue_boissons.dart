/// Les providers du **catalogue des boissons** — `m5-bar.html`.
///
/// ## À ne pas confondre avec `providers_bar.dart`
///
/// Celui-là sert la **Carte du bar** (`m5-bar-carte.html`), qui lit le
/// catalogue LOCAL répliqué et s'ouvre au comptoir sans réseau (PA-129).
/// Celui-ci sert l'écran où l'on **crée et modifie** une boisson : il ne parle
/// qu'au serveur, et n'a aucun cache.
///
/// ## Tous en `autoDispose`, comme M4, M6 et M7
///
/// Quitter l'écran doit **oublier** la réponse. `cartes_boisson` n'est pas au
/// registre `TABLES_SYNCHRONISABLES` : il n'existe aucune copie locale à
/// laquelle retomber, et réafficher au retour la liste de la visite précédente
/// montrerait un catalogue qui date sans dire qu'il date.
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../pos/presentation/providers_pos.dart';
import '../data/boissons_api.dart';
import '../domain/entities/boisson.dart';
import '../impression/etat_catalogue_boissons.dart';

/// Le catalogue des boissons, **lu et écrit dans la base locale** depuis le
/// 14/09/2026 : il descendait du serveur (PA-129), qui n'existe plus pour ce
/// poste. Il s'appuie sur [CatalogueDao], seul auteur de
/// `cartes_boisson_local` — jamais sur un second écrivain.
final boissonsApiProvider = Provider<BoissonsApi>(
  (ref) => BoissonsApi(ref.watch(catalogueDaoProvider)),
);

/* ====================================================================== */
/* Les filtres — un provider par contrôle du maître                        */
/* ====================================================================== */

/// La recherche — `m5-bar.html` l.79, « Rechercher une boisson... ».
///
/// ⚠ Elle est appliquée **sur la page reçue**, et non envoyée au serveur :
/// `BoissonController@index` ne lit que `categorie` et `page`. L'écart est
/// nommé sur [BoissonsApi.boissons] et dit à l'écran.
final rechercheBoissonsProvider = NotifierProvider<_TexteNotifier, String>(
  _TexteNotifier.new,
);

/// Le filtre « Toutes les catégories » — l.81-88.
final categorieBoissonsProvider =
    NotifierProvider<_CategorieNotifier, CategorieBoisson?>(
      _CategorieNotifier.new,
    );

/// La page courante. Elle revient à 1 dès qu'un filtre change — c'est ce que
/// fait le maître (`crud-engine.js` l.89, `pageActuelle = 1`) : rester en
/// page 4 après un filtre qui n'en rend qu'une afficherait une page vide sous
/// un total non nul.
final pageBoissonsProvider = NotifierProvider<_PageNotifier, int>(
  _PageNotifier.new,
);

final class _TexteNotifier extends Notifier<String> {
  @override
  String build() => '';

  void definir(String valeur) => state = valeur;
}

final class _CategorieNotifier extends Notifier<CategorieBoisson?> {
  @override
  CategorieBoisson? build() => null;

  void definir(CategorieBoisson? valeur) => state = valeur;
}

final class _PageNotifier extends Notifier<int> {
  @override
  int build() => 1;

  void definir(int valeur) => state = valeur;

  void premiere() => state = 1;
}

/* ====================================================================== */
/* Les lectures                                                            */
/* ====================================================================== */

/// La page de catalogue, **filtrée et repaginée comme le maître**.
///
/// Le serveur pagine par 50 en dur ; le maître affiche 10 lignes par page. La
/// tranche est donc découpée ici, sur la page serveur reçue — et
/// [PageBoissons.avertissement] dit que le décompte porte sur cette tranche,
/// plutôt que de laisser croire à une pagination serveur qui n'existe pas.
final boissonsProvider = FutureProvider.autoDispose<ResultatBar<PageBoissons>>((
  ref,
) async {
  final categorie = ref.watch(categorieBoissonsProvider);
  final page = ref.watch(pageBoissonsProvider);
  final terme = ref.watch(rechercheBoissonsProvider).trim().toLowerCase();

  // La catégorie part au SERVEUR (il la lit) ; le terme est appliqué ici
  // (il ne le lit pas). Les deux ne se traitent pas au même endroit, et
  // c'est mesuré, pas supposé.
  final brut = await ref
      .watch(boissonsApiProvider)
      .boissons(categorie: categorie);

  return switch (brut) {
    BarRecu<PageBar<Boisson>>(:final donnees) => BarRecu(
      decouperCommeLeMaitre(donnees, terme: terme, page: page),
    ),
    BarRefuse<PageBar<Boisson>>(:final motif, :final erreurs, :final code) =>
      BarRefuse<PageBoissons>(motif: motif, erreurs: erreurs, code: code),
    BarInjoignable<PageBar<Boisson>>() => const BarInjoignable(),
  };
});

// ⚠ `articlesPourBoissonProvider` a été RETIRÉ le 14/09/2026.
//
// Il lisait le référentiel d'articles de stock au serveur pour remplir le
// sélecteur « Article de stock » du formulaire. `StocksApi.articles()` rend
// désormais `null` pour tout le monde : `articles_local` est délibérément vide
// (PA-134), le stock était calculé par le serveur. Le sélecteur ne pouvait donc
// plus rien proposer, et la modale n'aurait offert qu'un avertissement parlant
// d'une liaison à rétablir — celle qui n'existe plus.
//
// Une boisson saisie sur ce poste naît **sans lien de stock**, et la modale le
// dit à la place. Voir `modale_boisson.dart`.

/// Ce que l'écran affiche : une tranche de 10, son total filtré, et la mention
/// qui borne la portée du décompte.
final class PageBoissons {
  const PageBoissons({
    required this.elements,
    required this.total,
    required this.page,
    required this.derniere,
    required this.parPage,
    required this.totalServeur,
    required this.avertissement,
  });

  final List<Boisson> elements;

  /// Le total **après filtre de recherche**, sur la page serveur reçue.
  final int total;

  final int page;
  final int derniere;
  final int parPage;

  /// Ce que le serveur a annoncé dans son `meta.total`, tous filtres serveur
  /// appliqués. Conservé pour que l'écart avec [total] se voie.
  final int totalServeur;

  /// `null` quand le catalogue tient dans la page serveur : il n'y a alors
  /// rien à borner, et une mention permanente s'apprendrait à ne plus se lire.
  final String? avertissement;

  int get premier => total == 0 ? 0 : (page - 1) * parPage + 1;
  int get dernier => (page - 1) * parPage + elements.length;
}

/// Applique la recherche puis la pagination du maître à une page serveur.
///
/// Fonction **pure**, éprouvable sans réseau ni widget.
PageBoissons decouperCommeLeMaitre(
  PageBar<Boisson> serveur, {
  required String terme,
  required int page,
}) {
  final filtrees = terme.isEmpty
      ? serveur.elements
      : serveur.elements
            .where((b) => b.libelle.toLowerCase().contains(terme))
            .toList(growable: false);

  const parPage = BoissonsApi.boissonsParPage;
  final derniere = filtrees.isEmpty
      ? 1
      : (filtrees.length + parPage - 1) ~/ parPage;
  // Une page hors bornes ramène à la dernière : le maître remet `pageActuelle`
  // à 1 sur changement de filtre, mais rien ne protège d'un total qui rétrécit
  // entre deux lectures.
  final courante = page.clamp(1, derniere);
  final debut = (courante - 1) * parPage;
  final fin = (debut + parPage).clamp(0, filtrees.length);

  // La mention n'apparaît QUE si le serveur a réellement tronqué : le dire
  // toujours ferait douter d'un catalogue complet, et une mention permanente
  // cesse d'être lue.
  final tronque = serveur.totalServeurDepasse;

  return PageBoissons(
    elements: filtrees.sublist(debut.clamp(0, filtrees.length), fin),
    total: filtrees.length,
    page: courante,
    derniere: derniere,
    parPage: parPage,
    totalServeur: serveur.total,
    avertissement: tronque
        ? 'Le serveur ne rend que ses ${serveur.elements.length} premières '
              'boissons sur ${serveur.total} : `BoissonController@index` pose '
              '`->paginate(50)` en dur et ne lit aucune taille de page. La '
              'recherche et le décompte ci-dessous portent donc sur cette '
              'tranche, pas sur le catalogue entier.'
        : null,
  );
}

extension on PageBar<Boisson> {
  /// Le serveur a-t-il des lignes qu'il n'a pas envoyées ?
  bool get totalServeurDepasse => total > elements.length;
}

/* ====================================================================== */
/* L'export                                                                */
/* ====================================================================== */

/// Écrit le CSV du catalogue et rend son chemin.
///
/// Injecté comme **action**, jamais appelé depuis un widget : un test de
/// widget n'a pas de greffon natif, et il doit exister un seul endroit où
/// l'écriture est déclenchée.
final exporterBoissonsProvider =
    Provider<Future<String> Function(List<Boisson>, String)>(
      (ref) =>
          (boissons, filtre) => _ecrireCsv(
            'boissons',
            EtatCatalogueBoissons.csvOctets(boissons, filtre: filtre),
          ),
    );

Future<String> _ecrireCsv(String prefixe, List<int> octets) async {
  final dossier = await getApplicationDocumentsDirectory();
  final m = DateTime.now();
  final horodatage =
      '${m.year}'
      '${m.month.toString().padLeft(2, '0')}'
      '${m.day.toString().padLeft(2, '0')}-'
      '${m.hour.toString().padLeft(2, '0')}'
      '${m.minute.toString().padLeft(2, '0')}'
      '${m.second.toString().padLeft(2, '0')}';
  final fichier = File(p.join(dossier.path, '$prefixe-$horodatage.csv'));
  await fichier.writeAsBytes(octets);
  return fichier.path;
}
