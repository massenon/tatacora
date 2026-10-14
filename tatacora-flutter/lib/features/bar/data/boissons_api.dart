import 'package:uuid/uuid.dart';

import '../../../core/donnees_absentes.dart';
import '../../pos/data/catalogue_dao.dart';
import '../../pos/data/dto/catalogue_dto.dart';
import '../domain/entities/boisson.dart';
import '../domain/entities/trace_prix.dart';
import '../domain/entities/ventes_bar.dart';

/// Ce qu'un appel de M5 peut rendre — **trois issues distinctes, toujours**.
///
/// Même famille scellée que M4 et M7, et pour la même raison : « pas de
/// réseau » et « droit manquant » ne se corrigent pas de la même façon, et au
/// Gîte la coupure est l'état normal une partie de la journée.
///
/// ⚠ [BarInjoignable] n'est plus produite par personne depuis le 14/09/2026 :
/// il n'y a plus de serveur à joindre. Le type est **conservé** parce que les
/// écrans le traitent déjà, et parce qu'il redeviendra utile le jour où un
/// client MECeF/DGI existera. Ne le rétablissez pas comme issue d'une lecture
/// locale : « injoignable » enverrait l'exploitant réessayer une liaison qui
/// n'existe pas.
sealed class ResultatBar<T> {
  const ResultatBar();
}

final class BarRecu<T> extends ResultatBar<T> {
  const BarRecu(this.donnees);
  final T donnees;
}

final class BarRefuse<T> extends ResultatBar<T> {
  const BarRefuse({required this.motif, this.erreurs = const {}, this.code});

  final String motif;

  /// Les messages **par champ**. N'en garder que le premier obligerait
  /// l'utilisateur à deviner lequel de ses champs a été rejeté.
  final Map<String, String> erreurs;

  final int? code;
}

final class BarInjoignable<T> extends ResultatBar<T> {
  const BarInjoignable();
}

/// Une page, avec le total que le FILTRE retient.
///
/// Sans [total], une page pleine se lirait comme « c'est tout ». Le maître
/// affiche ce total au mot près : « Affichage de 1-10 **sur 43** »
/// (`crud-engine.js` l.254).
final class PageBar<T> {
  const PageBar({
    required this.elements,
    required this.total,
    required this.page,
    required this.derniere,
    required this.parPage,
  });

  final List<T> elements;
  final int total;
  final int page;
  final int derniere;
  final int parPage;

  /// Le rang du premier élément affiché, à partir de 1.
  int get premier => total == 0 ? 0 : (page - 1) * parPage + 1;

  /// Le rang du dernier.
  int get dernier => (page - 1) * parPage + elements.length;
}

/// La saisie d'une boisson.
///
/// ## `articleId` n'est plus obligatoire, et c'est un CHANGEMENT de fond
///
/// Il l'était tant que la boisson naissait au serveur : `cartes_boisson.
/// article_id` y est NOT NULL et `exists:articles,id`. Sur ce poste,
/// `articles_local` est **délibérément vide** (PA-134) — le stock était calculé
/// par le serveur, et aucun référentiel d'articles n'y est répliqué. Exiger un
/// article ici rendrait la création **impossible**, c'est-à-dire laisserait le
/// point de vente sans rien à vendre : exactement le défaut que ce lot referme.
///
/// Une boisson saisie au comptoir naît donc **sans lien de stock**, la carte
/// l'affiche « non suivi », et sa vente ne décrémente aucun casier — ce qui est
/// la vérité de ce poste, pas une approximation.
final class SaisieBoisson {
  const SaisieBoisson({
    required this.libelle,
    required this.categorie,
    required this.prixVente,
    this.articleId = '',
    this.id,
  });

  final String libelle;
  final CategorieBoisson categorie;

  /// En chaîne : c'est ce que le champ de saisie porte. La conversion en
  /// entier — et son refus — vit à un seul endroit, [BoissonsApi.enregistrer].
  final String prixVente;

  /// Le lien vers l'article de stock (M6). Chaîne vide = aucun lien.
  final String articleId;

  /// L'identifiant de la boisson à MODIFIER. `null` = création.
  final String? id;
}

/// Le catalogue des boissons, **écrit et lu dans la base locale**.
///
/// @see EF-M5-02 Carte des boissons
/// @see RG-05 Le lien `article_id` rend la décrémentation possible
///
/// ## Pourquoi ce fichier a changé de nature le 14/09/2026
///
/// Il portait le client HTTP des cinq routes `Route::prefix('bar')`. Le poste
/// est **zéro réseau** : ces routes n'existent plus pour lui. Or la carte du
/// bar et le catalogue des boissons **descendaient du serveur** (PA-129) — ils
/// n'avaient donc plus aucun auteur, et un poste neuf n'avait *rien à vendre*.
/// Décision du Product Owner du 14/09/2026 : **le catalogue se saisit sur le
/// poste**. C'est ce que fait cette classe.
///
/// ⚠ Le NOM du fichier et de la classe dit encore « Api » alors qu'ils ne
/// parlent qu'à Drift. Le renommer touche onze fichiers sans changer un
/// comportement ; l'arbitrage est **ouvert**, il n'est pas tranché en silence
/// ici — c'est la même décision que pour les briques `features/restaurant/`
/// employées par M5.
///
/// ## L'auteur du catalogue reste UNIQUE
///
/// Rien n'est écrit ici : tout passe par [CatalogueDao], seul auteur de
/// `cartes_boisson_local` — celui-là même qu'empruntaient la descente réseau
/// et l'amorçage de démonstration. Un second auteur est le défaut que
/// `database/seeders/` a produit cinq fois.
///
/// ## Ce que ce poste ne peut PAS porter, et pourquoi — sans rien inventer
///
/// Quatre gestes de l'écran restent **refusés avec leur raison**, parce que la
/// colonne ou la table qui les porterait n'existe pas au schéma local. Les
/// rendre « en session » les ferait disparaître au redémarrage, sur l'écran qui
/// dit au barman ce qui est vendable — la famille PA-59/60/61 :
///
///  - **retrait et remise à la carte du jour** : aucune colonne
///    d'indisponibilité (ni motif, ni commentaire) ;
///  - **lien au stock** : aucune colonne `unites_vendables_par_unite_stock`, et
///    aucun article auquel se lier (`articles_local` est vide, PA-134) ;
///  - **historique des prix** : aucune table de trace ;
///  - **prix provisoire / corrigé à la main** : aucune colonne.
///
/// Ces quatre manques sont **signalés**, jamais comblés par une colonne créée
/// au passage : le schéma Drift est versionné, et une table modifiée ici
/// exigerait sa migration, sa fixture de retour arrière et son arbitrage.
///
/// ## Aucune suppression, et ce n'est pas un oubli
///
/// Une boisson est citée par `lignes_vente_bar_local` et par les lignes de
/// panier déjà saisies. La supprimer rendrait illisible ce qui a été vendu —
/// `Policy::delete()` rend `false` partout dans ce projet, et le geste métier
/// existe à la place : on retire de la carte, on ne détruit pas la ligne.
final class BoissonsApi {
  BoissonsApi(this._catalogue, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final CatalogueDao _catalogue;

  /// Injectable : un identifiant tiré au hasard rendrait les cas d'essai
  /// illisibles, et l'UUID naît **côté client** par règle de projet.
  final Uuid _uuid;

  /// La pagination d'AFFICHAGE du maître (`m5-bar.html`), appliquée côté
  /// client. C'est une règle de mise en page, pas de transport.
  static const int boissonsParPage = 10;

  /* ================================================================== */
  /* Lectures                                                            */
  /* ================================================================== */

  /// Le catalogue local, filtré par catégorie.
  ///
  /// [page] n'est pas lue : la découpe en pages de dix est faite par
  /// `decouperCommeLeMaitre`, sur la liste entière. Le poste détient tout son
  /// catalogue — il n'y a pas de tranche serveur à annoncer, et `total` vaut
  /// donc exactement le nombre d'éléments rendus.
  Future<ResultatBar<PageBar<Boisson>>> boissons({
    CategorieBoisson? categorie,
    int page = 1,
  }) async {
    final toutes = await _catalogue.boissonsDuCatalogue();
    final retenues = categorie == null
        ? toutes
        : toutes.where((b) => b.categorie == categorie.code).toList();

    final elements = retenues.map(_versBoisson).toList(growable: false);

    return BarRecu(
      PageBar(
        elements: elements,
        total: elements.length,
        page: 1,
        derniere: 1,
        parPage: elements.length,
      ),
    );
  }

  Future<ResultatBar<Boisson>> boisson(String id) async {
    final b = await _catalogue.boissonDuCatalogue(id);
    return b == null ? _introuvable() : BarRecu(_versBoisson(b));
  }

  /// L'historique des prix — **aucune trace n'existe sur ce poste**.
  ///
  /// Elle était écrite au serveur par `CarteBoissonObserver`, dans une table
  /// `historiques_prix_carte` qui n'a jamais été répliquée. Rendre une liste
  /// vide dirait « aucun changement de prix », ce qui est un FAIT — et un fait
  /// faux dès la première modification faite ici.
  Future<ResultatBar<List<TracePrix>>> historiquePrix(
    String id,
  ) async => const BarRefuse(
    motif:
        'L’historique des prix n’est pas tenu sur ce poste : aucune table '
        'ne trace les changements du catalogue local. Ce n’est pas « aucun '
        'changement » — la trace n’existe pas, elle n’est pas vide. Le prix '
        'affiché sur la carte est le prix en cours, et lui seul.',
  );

  /* ================================================================== */
  /* Écritures                                                           */
  /* ================================================================== */

  /// Crée une boisson, ou remplace celle que [SaisieBoisson.id] désigne.
  ///
  /// @see EF-M5-02 Carte des boissons
  ///
  /// L'UUID naît **ici**, côté client, à la création — jamais un compteur, et
  /// jamais à l'envoi : c'est la règle du dépôt, et elle reste vraie sans
  /// réseau puisque c'est elle qui rend un réenregistrement idempotent.
  ///
  /// Les règles de saisie sont vérifiées **avant** l'écriture, et nommées champ
  /// par champ : un refus global obligerait à deviner lequel des trois champs
  /// est en cause.
  Future<ResultatBar<Boisson>> enregistrer(SaisieBoisson saisie) async {
    final libelle = saisie.libelle.trim();
    final prix = _lirePrix(saisie.prixVente);

    final erreurs = <String, String>{
      if (libelle.isEmpty)
        'libelle': TextesCatalogueLocal.libelleManquant
      else if (libelle.length > 255)
        'libelle': TextesCatalogueLocal.libelleTropLong,
      if (saisie.prixVente.trim().isEmpty)
        'prix_vente': TextesCatalogueLocal.prixManquant
      else if (prix == null || prix < 0)
        'prix_vente': TextesCatalogueLocal.prixIllisible,
    };
    if (erreurs.isNotEmpty) {
      return BarRefuse(
        motif: TextesCatalogueLocal.saisieRefusee,
        erreurs: erreurs,
      );
    }

    final id = saisie.id;
    if (id != null && await _catalogue.boissonDuCatalogue(id) == null) {
      return _introuvable();
    }

    // Le doublon se refuse AVANT l'écriture : `insertOnConflictUpdate` porte
    // sur l'identifiant, pas sur le libellé — deux créations successives du
    // même nom produiraient deux lignes, et le point de vente en montrerait
    // deux sans que rien ne les distingue.
    if (await _catalogue.libelleBoissonExiste(libelle, sauf: id)) {
      return BarRefuse(
        motif: TextesCatalogueLocal.saisieRefusee,
        erreurs: {'libelle': TextesCatalogueLocal.libelleDejaPris(libelle)},
      );
    }

    final ecrite = BoissonDistante(
      id: id ?? _uuid.v4(),
      articleId: saisie.articleId.isEmpty ? null : saisie.articleId,
      libelle: libelle,
      categorie: saisie.categorie.code,
      // Le franc CFA n'a pas de sous-unité en circulation : le catalogue ne
      // porte que des francs entiers, et la conversion se fait ICI, une fois.
      prixVente: prix!.roundToDouble(),
      stockDisponible: null,
    );

    await _catalogue.enregistrerBoisson(ecrite);
    return BarRecu(_versBoisson(ecrite));
  }

  /// Change le PRIX, et rien d'autre.
  ///
  /// Le libellé et la catégorie sont **relus au catalogue** juste avant
  /// l'écriture plutôt que repris de la ligne affichée : la carte à l'écran
  /// peut dater d'avant une modification faite dans un autre onglet, et le
  /// changement de prix les écraserait sans un mot.
  ///
  /// ⚠ **Modifier la carte ne réécrit jamais une ligne de panier déjà
  /// saisie** : prix et libellé y sont figés à l'ajout (règle 3), et
  /// `PanierDao.ajouterLigne` fait du prix une part de sa clé de regroupement.
  /// La ligne servie garde le prix auquel elle a été servie.
  Future<ResultatBar<Boisson>> modifierPrix(String id, String prix) async {
    final actuelle = await _catalogue.boissonDuCatalogue(id);
    if (actuelle == null) return _introuvable();

    final lu = _lirePrix(prix);
    if (prix.trim().isEmpty) {
      return BarRefuse(
        motif: TextesCatalogueLocal.saisieRefusee,
        erreurs: {'prix_vente': TextesCatalogueLocal.prixManquant},
      );
    }
    if (lu == null) {
      return BarRefuse(
        motif: TextesCatalogueLocal.saisieRefusee,
        erreurs: {'prix_vente': TextesCatalogueLocal.prixIllisible},
      );
    }
    // `gt:0` — la règle du GESTE, pas celle de la colonne : suspendre la vente
    // est le rôle de « Retirer de la carte », qui porte son motif.
    if (lu <= 0) {
      return BarRefuse(
        motif: TextesCatalogueLocal.saisieRefusee,
        erreurs: {'prix_vente': TextesCatalogueLocal.prixNul},
      );
    }

    final ecrite = BoissonDistante(
      id: actuelle.id,
      articleId: actuelle.articleId,
      libelle: actuelle.libelle,
      categorie: actuelle.categorie,
      prixVente: lu.roundToDouble(),
      stockDisponible: null,
    );

    await _catalogue.enregistrerBoisson(ecrite);
    return BarRecu(_versBoisson(ecrite));
  }

  /* ================================================================== */
  /* Les quatre gestes que le SCHÉMA LOCAL ne porte pas                  */
  /* ================================================================== */

  /// « Rendre indispo. » — **refusé, faute de colonne**.
  ///
  /// Le serveur écrivait une ligne `indisponibilites_carte` (motif, commentaire,
  /// utilisateur, sous verrou). `cartes_boisson_local` n'a que cinq colonnes :
  /// `id`, `article_id`, `libelle`, `categorie`, `prix_vente`. Il n'existe donc
  /// **aucun endroit** où écrire un retrait.
  ///
  /// Le tenir en mémoire le ferait disparaître à la fermeture de la fenêtre :
  /// le barman aurait retiré la Béninoise le matin et la verrait revenir à
  /// midi, sans que personne ne sache s'il faut la racheter. C'est le défaut
  /// même que la PWA a fermé, et l'inverse serait pire que l'absence.
  Future<ResultatBar<Boisson>> retirer({
    required String id,
    required String motif,
    String? commentaire,
  }) async => const BarRefuse(motif: TextesCatalogueLocal.retraitSansColonne);

  /// « Remettre » — refusé pour la même raison que [retirer] : il n'y a rien à
  /// lever, puisqu'il n'y a rien où écrire un retrait.
  Future<ResultatBar<Boisson>> remettre(String id) async =>
      const BarRefuse(motif: TextesCatalogueLocal.retraitSansColonne);

  /// « Lier au stock » — **refusé deux fois plutôt qu'une**.
  ///
  /// Il n'y a aucun article auquel se lier (`articles_local` est délibérément
  /// vide, PA-134), et aucune colonne où ranger le conditionnement — qui est la
  /// raison d'être même de ce geste : un casier de 24 et une bouteille à
  /// l'unité ne décrémentent pas pareil. Écrire le seul `article_id` en jetant
  /// le conditionnement serait le champ collecté puis ignoré.
  Future<ResultatBar<Boisson>> lierAuStock({
    required String id,
    required String articleId,
    required String unitesVendablesParUniteStock,
  }) async => const BarRefuse(motif: TextesCatalogueLocal.lienSansColonne);

  /* ================================================================== */
  /* Les ventes du bar — hors de ce lot                                  */
  /* ================================================================== */

  /// ⚠ `ventes_bar_local` existe au schéma et **n'a aucun auteur** : aucune
  /// vente n'y est écrite, ni par le point de vente (qui tient ses paniers)
  /// ni par personne d'autre. Rendre une liste vide annoncerait « aucune vente
  /// aujourd'hui », un fait — et faux. Ce lot ne referme pas ce point ; il le
  /// nomme.
  Future<ResultatBar<PageVentesBar>> ventes(FiltreVentesBar filtre) async =>
      BarRefuse(motif: donneeNonDisponible(_ventes));

  Future<ResultatBar<(List<LigneVenteBar>, TotauxVentesBar)>> toutesLesVentes(
    FiltreVentesBar filtre, {
    int pagesMax = 500,
  }) async => BarRefuse(motif: donneeNonDisponible(_ventes));

  static const String _ventes = 'Les ventes du bar (module M5)';

  /* ================================================================== */

  // ⚠ `BarRefuse<T>` explicitement, et sans `const` : un `const BarRefuse(…)`
  // sans argument de type produirait un `BarRefuse<dynamic>`, que le transtypage
  // en `ResultatBar<Boisson>` ferait LEVER à l'exécution — sur le seul chemin
  // qu'aucun écran n'emprunte au quotidien, celui de la boisson introuvable.
  ResultatBar<T> _introuvable<T>() =>
      BarRefuse<T>(motif: TextesCatalogueLocal.introuvable);

  /// Le prix saisi, en francs. `null` si la chaîne n'est pas un nombre.
  ///
  /// La virgule est acceptée : c'est celle qu'on tape au Bénin.
  double? _lirePrix(String brut) {
    final texte = brut.trim().replaceAll(',', '.').replaceAll(' ', '');
    if (texte.isEmpty) return null;
    final lu = double.tryParse(texte);
    return (lu == null || !lu.isFinite) ? null : lu;
  }

  /// ⚠ **Le stock reste ABSENT, toujours.**
  ///
  /// [Boisson.stockDisponible] est `null` et le restera : il se calcule des
  /// mouvements, et ce poste n'en a aucun (PA-134). L'écran rend « — » ou
  /// « non consulté ». Un `0` s'y lirait « rupture » — une bonne nouvelle
  /// affichée à la place d'une absence, sur l'écran qui sert à commander.
  Boisson _versBoisson(BoissonDistante b) => Boisson(
    id: b.id,
    libelle: b.libelle,
    categorie: CategorieBoisson.depuisCode(b.categorie),
    categorieBrute: b.categorie,
    // Des francs ENTIERS : le catalogue n'en porte pas d'autres.
    prixVente: b.prixVente.round().toString(),
    articleId: b.articleId ?? '',
    stockDisponible: null,
    // Le stock ne se saisit jamais (PA-24). Ici ce n'est plus une affirmation
    // du serveur relue, c'est un fait du poste : aucun champ ne l'accepte.
    stockLectureSeule: true,
    // Aucune colonne ne porte le conditionnement — voir [lierAuStock].
    unitesVendablesParUniteStock: null,
  );
}

/// Les refus du catalogue local — un seul endroit, pour que l'écran et les cas
/// d'essai ne puissent pas diverger.
abstract final class TextesCatalogueLocal {
  static const String saisieRefusee =
      'La saisie n’a pas été enregistrée : un champ au moins est refusé.';

  static const String introuvable =
      'Cette boisson ne figure pas au catalogue de ce poste. Elle a peut-être '
      'été enregistrée sur un autre poste : les catalogues ne se synchronisent '
      'plus, chacun tient le sien.';

  static const String libelleManquant = 'Le libellé est obligatoire.';
  static const String libelleTropLong =
      'Le libellé ne peut pas dépasser 255 caractères.';
  static const String prixManquant = 'Le prix de vente est obligatoire.';
  static const String prixIllisible =
      'Le prix de vente doit être un nombre positif ou nul.';
  static const String prixNul =
      'Un prix à zéro est refusé : pour suspendre la vente, retirez l’article '
      'de la carte.';

  static String libelleDejaPris(String libelle) =>
      '« $libelle » est déjà à la carte. Deux articles de même nom mettent deux '
      'entrées au point de vente, et le barman ne peut plus savoir laquelle il '
      'vend. Deux contenances différentes sont deux articles : nommez-les.';

  /// Le refus de « Rendre indispo. » et de « Remettre ».
  static const String retraitSansColonne =
      'Le retrait de la carte du jour n’est pas enregistrable sur ce poste : '
      'la table du catalogue local ne porte ni motif, ni commentaire, ni date '
      'de retrait. Le tenir en mémoire le ferait disparaître à la fermeture de '
      'la fenêtre — l’article reviendrait seul à la carte, sans que personne '
      'ne sache s’il faut le racheter. Retirez plutôt la boisson de la carte '
      'en la renommant ou signalez-la au responsable.';

  /// Le refus de « Lier au stock ».
  static const String lienSansColonne =
      'Le lien au stock n’est pas enregistrable sur ce poste : aucun article '
      'de stock n’y est répliqué, et la table du catalogue local ne porte pas '
      'le conditionnement (combien de bouteilles dans un casier ?). Sans lui, '
      'une vente ne saurait pas quoi décrémenter — et l’enregistrer à moitié '
      'ferait croire à un rattachement qui ne compte rien.';
}
