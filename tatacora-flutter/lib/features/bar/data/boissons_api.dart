import 'package:uuid/uuid.dart';

import '../../../core/donnees_absentes.dart';
import '../../pos/data/catalogue_dao.dart';
import '../../pos/data/dto/catalogue_dto.dart';
import '../../pos/data/indisponibilites_carte_dao.dart';
import '../domain/apercu_lien.dart';
import '../domain/motif_indisponibilite.dart';
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
/// ## L'article de stock ET son conditionnement partent ensemble (26/10/2026)
///
/// Le poste tient maintenant ses articles de stock (`articles_local`, module
/// Stocks) : « Nouvelle boisson » choisit un article et dit combien d'unités
/// VENDUES font une unité de STOCK (un casier de 24 : `24`). Un conditionnement
/// SANS article est refusé (il ne décrémenterait rien, `conversion_sans_lien`).
/// Un article SANS conditionnement est admis au niveau de l'API, comme
/// `CarteBoissonService::creer` (le serveur garde alors son défaut, 1) : c'est
/// l'import d'une carte. [articleId] vide aussi (boissons d'avant : « non
/// suivie »). Ce sont les MODALES qui exigent les deux, comme la vue exige
/// l'article.
final class SaisieBoisson {
  const SaisieBoisson({
    required this.libelle,
    required this.categorie,
    required this.prixVente,
    this.articleId = '',
    this.unitesVendablesParUniteStock = '',
    this.id,
  });

  final String libelle;
  final CategorieBoisson categorie;

  /// En chaîne : c'est ce que le champ de saisie porte. La conversion en
  /// entier — et son refus — vit à un seul endroit, [BoissonsApi.enregistrer].
  final String prixVente;

  /// Le lien vers l'article de stock (M6). Chaîne vide = aucun lien.
  final String articleId;

  /// Combien d'unités vendables dans une unité de stock, tel que saisi
  /// (« 24 », « 66,5 »). Exigé avec [articleId], refusé sans lui.
  final String unitesVendablesParUniteStock;

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
/// ## Le lien au stock s'écrit ICI (26/10/2026)
///
/// `cartes_boisson_local.unites_vendables` (v30) porte le conditionnement et
/// `articles_local` les articles du poste : « Nouvelle boisson » et « Lier au
/// stock » / « Modifier le lien » écrivent l'article ET son conditionnement par
/// [CatalogueDao], dans la file d'envoi (création ou modification). Reste
/// refusé, parce que ni colonne ni table ne le porte : **l'historique des
/// prix** et la marque **prix corrigé à la main**. Ces manques sont
/// SIGNALÉS, jamais comblés par une colonne créée au passage : le schéma Drift
/// est versionné.
///
/// ## Aucune suppression, et ce n'est pas un oubli
///
/// Une boisson est citée par `lignes_vente_bar_local` et par les lignes de
/// panier déjà saisies. La supprimer rendrait illisible ce qui a été vendu —
/// `Policy::delete()` rend `false` partout dans ce projet, et le geste métier
/// existe à la place : on retire de la carte, on ne détruit pas la ligne.
final class BoissonsApi {
  BoissonsApi(this._catalogue, {Uuid? uuid, IndisponibilitesCarteDao? retraits})
    : _uuid = uuid ?? const Uuid(),
      _retraits =
          retraits ?? IndisponibilitesCarteDao(_catalogue.attachedDatabase);

  final CatalogueDao _catalogue;

  /// Seul écrivain des retraits de la carte du jour (v31, 21/10/2026).
  final IndisponibilitesCarteDao _retraits;

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

    // Le lien : l'article ET son conditionnement, ou ni l'un ni l'autre.
    String? unitesEcrites;
    final article = saisie.articleId.trim();
    if (article.isEmpty) {
      if (saisie.unitesVendablesParUniteStock.trim().isNotEmpty) {
        return BarRefuse(
          motif: TextesCatalogueLocal.saisieRefusee,
          erreurs: {
            _champConversion: TextesCatalogueLocal.conversionSansLien(libelle),
          },
        );
      }
    } else {
      final erreursLien = await _verifierLien(
        libelle: libelle,
        articleId: article,
        conditionnement: saisie.unitesVendablesParUniteStock,
        // Comme `CarteBoissonService::creer` : une clé absente laisse le
        // conditionnement au défaut du schéma serveur (1). C'est la MODALE
        // qui l'exige (« Combien de … dans une unité de stock ? »).
        conditionnementRequis: false,
      );
      if (erreursLien.$2.isNotEmpty) {
        return BarRefuse(
          motif: TextesCatalogueLocal.saisieRefusee,
          erreurs: erreursLien.$2,
        );
      }
      unitesEcrites = erreursLien.$1;
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
      articleId: article.isEmpty ? null : article,
      libelle: libelle,
      categorie: saisie.categorie.code,
      // Le franc CFA n'a pas de sous-unité en circulation : le catalogue ne
      // porte que des francs entiers, et la conversion se fait ICI, une fois.
      prixVente: prix!.roundToDouble(),
      stockDisponible: null,
      unitesVendables: unitesEcrites,
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

  /// « Modifier la boisson » — le libellé et la catégorie, et RIEN d'autre
  /// (`CarteBar::enregistrerModificationBoisson`, `CarteBoissonService::modifier`
  /// ne reçoit que ces deux clés) : le prix, le lien au stock et l'historique
  /// restent ceux de la boisson. Le prix est donc RELU au catalogue juste avant
  /// l'écriture, jamais repris de la ligne affichée.
  ///
  /// Mêmes règles que `EnregistrerBoissonRequest` : libellé requis, 255
  /// caractères au plus, catégorie du registre fermé ; le poste refuse en plus
  /// un libellé déjà pris (deux entrées de même nom au comptoir).
  Future<ResultatBar<Boisson>> modifier(
    String id, {
    required String libelle,
    required CategorieBoisson categorie,
  }) async {
    final actuelle = await _catalogue.boissonDuCatalogue(id);
    if (actuelle == null) return _introuvable();

    final nom = libelle.trim();
    if (nom.isEmpty || nom.length > 255) {
      return BarRefuse(
        motif: TextesCatalogueLocal.saisieRefusee,
        erreurs: {
          'libelle': nom.isEmpty
              ? TextesCatalogueLocal.libelleManquant
              : TextesCatalogueLocal.libelleTropLong,
        },
      );
    }
    if (await _catalogue.libelleBoissonExiste(nom, sauf: id)) {
      return BarRefuse(
        motif: TextesCatalogueLocal.saisieRefusee,
        erreurs: {'libelle': TextesCatalogueLocal.libelleDejaPris(nom)},
      );
    }

    final ecrite = BoissonDistante(
      id: actuelle.id,
      articleId: actuelle.articleId,
      libelle: nom,
      categorie: categorie.code,
      prixVente: actuelle.prixVente,
      stockDisponible: null,
    );
    await _catalogue.enregistrerBoisson(ecrite);
    return BarRecu(_versBoisson(ecrite));
  }

  /* ================================================================== */
  /* Le retrait de la carte du jour (v31, 21/10/2026)                    */
  /* ================================================================== */

  /// « Rendre indispo. » — écrit une ligne `indisponibilites_carte_local`
  /// (motif du registre fermé, commentaire, instant) et la met en file : le
  /// serveur la fusionne si la boisson est déjà retirée, et les autres postes
  /// la reçoivent. Un motif hors registre est refusé AVANT l'écriture.
  Future<ResultatBar<Boisson>> retirer({
    required String id,
    required String motif,
    String? commentaire,
  }) async {
    final m = MotifIndisponibilite.values
        .where((x) => x.code == motif)
        .firstOrNull;
    if (m == null) {
      return BarRefuse(
        motif: 'Le motif « $motif » n’existe pas.',
        erreurs: {'motif': 'Choisissez un des motifs proposés.'},
      );
    }
    final b = await _catalogue.boissonDuCatalogue(id);
    if (b == null) return _introuvable();
    if ((commentaire?.trim().length ?? 0) > 500) {
      return const BarRefuse(
        motif: 'Le commentaire est trop long.',
        erreurs: {'commentaire': '500 caractères au plus.'},
      );
    }
    final ecrit = await _retraits.retirer(
      boissonId: id,
      motif: m,
      commentaire: commentaire,
    );
    if (ecrit == null) {
      return BarRefuse(
        motif: TextesCatalogueLocal.dejaRetiree(b.libelle),
        erreurs: {'etat': TextesCatalogueLocal.dejaRetiree(b.libelle)},
      );
    }
    return BarRecu(_versBoisson(b));
  }

  /// « Remettre » — ferme le retrait en cours (instant du retour) et le met en
  /// file. Refusé, en le DISANT, quand rien n'est retiré (déjà remise ici ou
  /// sur un autre poste).
  Future<ResultatBar<Boisson>> remettre(String id) async {
    final b = await _catalogue.boissonDuCatalogue(id);
    if (b == null) return _introuvable();
    if (!await _retraits.remettre(boissonId: id)) {
      return BarRefuse(
        motif: TextesCatalogueLocal.nonRetiree(b.libelle),
        erreurs: {'etat': TextesCatalogueLocal.nonRetiree(b.libelle)},
      );
    }
    return BarRecu(_versBoisson(b));
  }

  /// « Lier au stock » / « Modifier le lien » — l'article de stock ET son
  /// conditionnement, écrits ENSEMBLE (26/10/2026).
  ///
  /// Écrire le seul `article_id` en jetant le conditionnement serait le champ
  /// collecté puis ignoré : un casier de 24 et une bouteille à l'unité ne
  /// décrémentent pas pareil. Les deux valeurs passent donc par
  /// [CatalogueDao.enregistrerBoisson] — seul écrivain —, qui met en file une
  /// modification portant `article_id` et `unites_vendables_par_unite_stock`
  /// (les seuls champs changés ; le serveur les reçoit depuis le 26/10/2026).
  ///
  /// Refusé AVANT toute écriture, champ par champ : boisson inconnue, article
  /// absent de ce poste, conditionnement vide, illisible ou non strictement
  /// positif (`gt:0` : la décrémentation vaut `1 / conditionnement`). Le prix, le
  /// libellé et la catégorie restent ceux du catalogue, relus à l'instant.
  Future<ResultatBar<Boisson>> lierAuStock({
    required String id,
    required String articleId,
    required String unitesVendablesParUniteStock,
  }) async {
    final actuelle = await _catalogue.boissonDuCatalogue(id);
    if (actuelle == null) return _introuvable();

    final verifie = await _verifierLien(
      libelle: actuelle.libelle,
      articleId: articleId.trim(),
      conditionnement: unitesVendablesParUniteStock,
    );
    if (verifie.$2.isNotEmpty) {
      return BarRefuse(
        motif: TextesCatalogueLocal.saisieRefusee,
        erreurs: verifie.$2,
      );
    }

    final ecrite = BoissonDistante(
      id: actuelle.id,
      articleId: articleId.trim(),
      libelle: actuelle.libelle,
      categorie: actuelle.categorie,
      prixVente: actuelle.prixVente,
      stockDisponible: null,
      unitesVendables: verifie.$1,
    );
    await _catalogue.enregistrerBoisson(ecrite);
    return BarRecu(_versBoisson(ecrite));
  }

  static const String _champConversion = 'unites_vendables_par_unite_stock';

  /// Le lien est-il écrivable ? Rend le conditionnement NORMALISÉ (« 24 »,
  /// « 66.5 ») et les erreurs par champ — vides quand tout est bon.
  ///
  /// Les règles sont celles de `EcranDeCarte::enregistrerLienAuStock()` :
  /// article requis et présent, conditionnement `numeric` et `gt:0`.
  Future<(String?, Map<String, String>)> _verifierLien({
    required String libelle,
    required String articleId,
    required String conditionnement,
    bool conditionnementRequis = true,
  }) async {
    final erreurs = <String, String>{};
    if (articleId.isEmpty) {
      erreurs['article_id'] = TextesCatalogueLocal.articleObligatoire;
    } else if (await _catalogue.articleDeStock(articleId) == null) {
      erreurs['article_id'] = TextesCatalogueLocal.articleInexistant;
    }

    String? unites;
    if (conditionnement.trim().isEmpty) {
      if (conditionnementRequis) {
        erreurs[_champConversion] = TextesCatalogueLocal.conversionRequise(
          libelle,
        );
      }
    } else {
      final lu = lireDecimal(conditionnement);
      if (lu == null || lu <= BigInt.zero) {
        erreurs[_champConversion] = TextesCatalogueLocal.conversionInvalide(
          libelle,
        );
      } else {
        unites = ecrireDecimal(lu);
      }
    }
    return (unites, erreurs);
  }

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

  static const String _ventes = 'Les ventes du bar';

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
    // `cartes_boisson_local.unites_vendables` (v30) — `null` : pas reçu, et la
    // modale « Lier au stock » ne propose alors pas de valeur inventée.
    unitesVendablesParUniteStock: b.unitesVendables,
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

  /// « Rendre indispo. » sur une boisson déjà retirée : rien n'est écrit.
  static String dejaRetiree(String libelle) =>
      '« $libelle » est déjà retirée de la carte du jour.';

  /// « Remettre » sur une boisson qui n'est pas retirée : rien n'est écrit.
  static String nonRetiree(String libelle) =>
      '« $libelle » n’est pas retirée de la carte du jour.';

  /// `bar.validation.article_obligatoire`.
  static const String articleObligatoire =
      'Une boisson doit être liée à un article du stock, sinon sa vente ne '
      'décrémenterait rien.';

  /// `bar.validation.article_inexistant`, précisé : sur ce poste, la liste des
  /// articles est celle du module Stocks.
  static const String articleInexistant =
      'Cet article n’existe pas dans le référentiel Stocks de ce poste.';

  /// `carte.conversion_requise_avec_lien`.
  static String conversionRequise(String libelle) =>
      '« $libelle » est rattaché à un article de stock : le nombre d’unités '
      'vendables par unité de stock devient obligatoire. Sans lui, la vente ne '
      'saurait pas quelle fraction d’unité de stock sortir.';

  /// `carte.conversion_invalide`.
  static String conversionInvalide(String libelle) =>
      'La conversion vers le stock de « $libelle » est invalide : le nombre '
      'd’unités vendables par unité de stock doit être strictement positif.';

  /// `carte.conversion_sans_lien`.
  static String conversionSansLien(String libelle) =>
      '« $libelle » n’est rattaché à aucun article de stock : un '
      'conditionnement y serait sans objet, et laisserait croire à une '
      'décrémentation qui n’aura pas lieu.';
}
