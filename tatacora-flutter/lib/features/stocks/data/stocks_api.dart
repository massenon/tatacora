import '../domain/calcul_stock.dart';
import '../domain/entities/etat_stock.dart';
import '../domain/entities/fiche_stock.dart';
import '../domain/entities/mouvement_stock.dart';
import '../../../core/rbac/regle_archivage.dart'
    show roleNormalise, rolesAdministration;
import '../domain/messages_stock.dart';
import '../domain/nombre_saisi.dart';
import 'stocks_dao.dart';

/// Ce que la consultation du stock peut rendre.
///
/// Trois issues sont CONSERVÉES, bien que le poste n'ait plus de serveur : les
/// écrans qui consomment l'état (Stocks, Approvisionnement, tableau de bord)
/// les traitent depuis toujours, et « refusé » garde un sens — le droit de
/// lecture manque. « Injoignable » n'est plus jamais produit : une base locale
/// n'est pas hors connexion.
sealed class ResultatStock {
  const ResultatStock();
}

final class StockRecu extends ResultatStock {
  const StockRecu(this.etat);
  final EtatStock etat;
}

final class StockRefuse extends ResultatStock {
  const StockRefuse({required this.motif, this.codeHttp});
  final String motif;
  final int? codeHttp;
}

final class StockInjoignable extends ResultatStock {
  const StockInjoignable();
}

/// Ce qu'une consultation de FICHE peut rendre.
sealed class ResultatFiche {
  const ResultatFiche();
}

final class FicheRecue extends ResultatFiche {
  const FicheRecue(this.fiche);
  final FicheStock fiche;
}

final class FicheRefusee extends ResultatFiche {
  const FicheRefusee(this.motif);
  final String motif;
}

final class FicheInjoignable extends ResultatFiche {
  const FicheInjoignable();
}

/// Ce que l'enregistrement d'un article peut rendre — EF-M6-01.
///
/// Le refus porte le détail **champ par champ** et pas seulement une phrase :
/// n'en garder que le premier message obligerait le magasinier à deviner lequel
/// de ses champs est rejeté.
sealed class ResultatEcritureArticle {
  const ResultatEcritureArticle();
}

final class ArticleEnregistre extends ResultatEcritureArticle {
  const ArticleEnregistre({
    required this.id,
    required this.libelle,
    this.messageEntree,
  });
  final String id;
  final String libelle;

  /// Le message de la vue quand la fiche a AUSSI fait entrer du stock
  /// (`article.entree_enregistree`) ; `null` : la fiche a été enregistrée sans
  /// toucher au stock — annoncer une entrée qui n'a pas eu lieu serait un
  /// indicateur qui affirme un état qu'il n'a pas vérifié.
  final String? messageEntree;
}

final class ArticleRefuse extends ResultatEcritureArticle {
  const ArticleRefuse({
    required this.motif,
    this.erreurs = const {},
    this.codeHttp,
  });

  final String motif;

  /// Les messages, par champ, affichés **tels quels**.
  final Map<String, String> erreurs;

  final int? codeHttp;
}

final class ArticleInjoignable extends ResultatEcritureArticle {
  const ArticleInjoignable();
}

/// Ce que la fiche CONSOLIDÉE (« Tous les articles ») peut rendre. Jamais
/// « injoignable » : une base locale n'est pas hors connexion.
sealed class ResultatFicheConsolidee {
  const ResultatFicheConsolidee();
}

final class FicheConsolideeRecue extends ResultatFicheConsolidee {
  const FicheConsolideeRecue(this.fiche);
  final FicheConsolidee fiche;
}

final class FicheConsolideeRefusee extends ResultatFicheConsolidee {
  const FicheConsolideeRefusee(this.motif);
  final String motif;
}

/// Ce que l'enregistrement d'un mouvement peut rendre — EF-M6-02.
///
/// [RuptureAConfirmer] n'est **pas** un refus, et c'est le cœur de RG-06 : la
/// rupture est une demande de confirmation adressée à un utilisateur habilité,
/// jamais une erreur définitive. La ranger avec les refus supprimerait la
/// sortie forcée, c'est-à-dire empêcherait de servir un client au comptoir en
/// attendant une régularisation.
sealed class ResultatEcritureMouvement {
  const ResultatEcritureMouvement();
}

final class MouvementEnregistre extends ResultatEcritureMouvement {
  const MouvementEnregistre(this.mouvement);
  final MouvementStock mouvement;
}

final class RuptureAConfirmer extends ResultatEcritureMouvement {
  const RuptureAConfirmer({
    required this.message,
    required this.stockDisponible,
    required this.quantiteDemandee,
  });

  /// La phrase de RG-06 (`stocks.rupture`), affichée telle quelle.
  final String message;

  /// Chaînes : ce sont les deux chiffres que le contrôle a comparés.
  final String stockDisponible;
  final String quantiteDemandee;
}

final class MouvementRefuse extends ResultatEcritureMouvement {
  const MouvementRefuse({
    required this.motif,
    this.erreurs = const {},
    this.codeHttp,
  });

  final String motif;
  final Map<String, String> erreurs;
  final int? codeHttp;
}

final class MouvementInjoignable extends ResultatEcritureMouvement {
  const MouvementInjoignable();
}

/// Ce que la consultation du journal peut rendre.
sealed class ResultatJournal {
  const ResultatJournal();
}

final class JournalRecu extends ResultatJournal {
  const JournalRecu({required this.mouvements, required this.total});

  final List<MouvementStock> mouvements;

  /// Le nombre total de mouvements que le filtre retient, pas celui de la page
  /// affichée. Sans lui, une page pleine se lirait comme « c'est tout ».
  final int total;
}

final class JournalRefuse extends ResultatJournal {
  const JournalRefuse(this.motif);
  final String motif;
}

final class JournalInjoignable extends ResultatJournal {
  const JournalInjoignable();
}

/// Ce que la création d'un point de stockage peut rendre.
sealed class ResultatPoint {
  const ResultatPoint();
}

final class PointEnregistre extends ResultatPoint {
  const PointEnregistre(this.point);
  final PointStockage point;
}

final class PointRefuse extends ResultatPoint {
  const PointRefuse(this.motif);
  final String motif;
}

/// La phrase quand le droit de lecture de M6 manque.
const String refusLectureStocks =
    'Vous n’avez pas le droit de consulter les stocks.';

/// La phrase quand le droit d'écriture de M6 manque. Rien n'a été enregistré.
const String refusEcritureStocks =
    'Vous n’avez pas le droit de modifier les stocks. Rien n’a été '
    'enregistré.';

/// M6 Stocks — **source LOCALE** (décision du Product Owner, 09/10/2026).
///
/// ⚠ Le nom `StocksApi` est historique : ce n'était qu'un client HTTP, et la
/// classe n'appelle plus aucun serveur. Il est conservé pour ne pas rouvrir les
/// quatre écrans qui la consomment (Stocks, Inventaires, Approvisionnement,
/// tableau de bord) ; c'est désormais le cas d'usage de M6, devant
/// [StocksDao].
///
/// ## Ce que cette classe décide, et ce qu'elle laisse au DAO
///
///  * **Les droits** — `M6` en lecture pour consulter, en écriture pour toute
///    saisie. Un écran qui masque un bouton ne protège rien.
///  * **La forme des saisies** — un nombre reste une chaîne jusqu'ici, où il
///    devient un entier ; une troisième décimale est refusée, jamais tronquée.
///  * **La phrase de RG-06** — `stocks.rupture`, relue sur le fichier PHP par
///    un test.
///
/// Le DAO tient les règles qui exigent la base (clé inconnue, article
/// journalier, disponibilité) dans une transaction.
///
/// ## Qui écrit, qui lit, qui descend
///
/// Voir `core/database/tables/stocks_tables.dart` : un seul auteur par table,
/// et personne ne les descend — zéro réseau.
///
/// ## Ce que ce stock ne sait pas
///
/// Il ne compte que les mouvements saisis ici. Les ventes du bar et du
/// restaurant n'écrivent aucune sortie (RG-05 n'est pas portée) : le stock
/// affiché peut donc dépasser le stock réel d'autant. L'écran le dit en toutes
/// lettres plutôt que de laisser un chiffre exact en apparence.
final class StocksApi {
  StocksApi({
    required this._dao,
    required this._peutLire,
    required this._peutEcrire,
    required this._auteurId,
    String? Function()? roleUtilisateur,
  }) : _role = roleUtilisateur;

  final StocksDao _dao;
  final bool Function() _peutLire;
  final bool Function() _peutEcrire;
  final String? Function() _auteurId;

  /// Le rôle de la session, lu à CHAQUE appel — jamais capturé. `null` (un banc
  /// qui ne le fournit pas) : personne n'est administrateur.
  final String? Function()? _role;

  /// `Stocks::peutAjusterLeStock()` : l'entrée depuis la fiche article est un
  /// geste d'ADMINISTRATION — elle valorise la marchandise et déplace le coût
  /// moyen pondéré. Le rôle ne dispense jamais du droit d'écriture sur M6 : il
  /// s'y ajoute.
  bool get peutAjusterLeStock =>
      _peutEcrire() &&
      rolesAdministration.contains(roleNormalise(_role?.call()));

  /// Le code du suivi permanent, lu par M5 pour filtrer les articles.
  /// Identifiant métier, pas donnée de transport : conservé.
  static const String suiviPermanent = 'permanent';

  /* ================================================================== */
  /* Lecture                                                             */
  /* ================================================================== */

  Future<ResultatStock> etat({String? pointId, EtatStockFiltre? etat}) async {
    if (!_peutLire()) {
      return const StockRefuse(motif: refusLectureStocks, codeHttp: 403);
    }
    return StockRecu(
      await _dao.etat(pointId: pointId, filtre: etat ?? EtatStockFiltre.tous),
    );
  }

  /// Les points de stockage enregistrés sur ce poste — une liste VIDE est ici
  /// la vérité : aucun point n'a été créé. (Le sélecteur dit alors comment en
  /// créer un.)
  Future<List<PointStockage>> points() async =>
      _peutLire() ? _dao.points() : const <PointStockage>[];

  /// `null` — « on ne sait pas », jamais une liste vide — quand le droit de
  /// lecture manque : une liste vide se lirait « aucun article ».
  Future<List<ArticleFiche>?> articles({
    String? suivi,
    String? pointId,
    int pagesMax = 20,
  }) async {
    if (!_peutLire()) return null;
    return _dao.articlesFiche(
      suivi: SuiviArticle.depuisCode(suivi),
      pointId: pointId,
    );
  }

  Future<ResultatFiche> fiche({
    required String articleId,
    required DateTime debut,
    required DateTime fin,
    String? pointId,
  }) async {
    if (!_peutLire()) return const FicheRefusee(refusLectureStocks);

    final j = DateTime(debut.year, debut.month, debut.day);
    final f = DateTime(fin.year, fin.month, fin.day);
    if (f.isBefore(j)) {
      return const FicheRefusee(MessagesStock.periodeInversee);
    }

    final fiche = await _dao.fiche(
      articleId: articleId,
      debut: debut,
      fin: fin,
      pointId: pointId,
    );
    return fiche == null
        ? const FicheRefusee('Article inconnu du référentiel.')
        : FicheRecue(fiche);
  }

  /// « Tous les articles » : la fiche consolidée sur la période. Les bornes
  /// inversées sont refusées avec la phrase du serveur, comme pour un article.
  Future<ResultatFicheConsolidee> ficheConsolidee({
    required DateTime debut,
    required DateTime fin,
    String? pointId,
  }) async {
    if (!_peutLire()) return const FicheConsolideeRefusee(refusLectureStocks);

    final j = DateTime(debut.year, debut.month, debut.day);
    final f = DateTime(fin.year, fin.month, fin.day);
    if (f.isBefore(j)) {
      return const FicheConsolideeRefusee(MessagesStock.periodeInversee);
    }

    return FicheConsolideeRecue(
      await _dao.ficheConsolidee(debut: debut, fin: fin, pointId: pointId),
    );
  }

  Future<ResultatJournal> mouvements({
    String? articleId,
    String? pointId,
    TypeMouvement? type,
    int parPage = 20,
  }) async {
    if (!_peutLire()) return const JournalRefuse(refusLectureStocks);
    final r = await _dao.journal(
      articleId: articleId,
      pointId: pointId,
      type: type,
      limite: parPage,
    );
    return JournalRecu(mouvements: r.mouvements, total: r.total);
  }

  /* ================================================================== */
  /* Écriture                                                            */
  /* ================================================================== */

  Future<ResultatPoint> creerPoint({
    required String libelle,
    TypePoint? type,
  }) async {
    if (!_peutEcrire()) return const PointRefuse(refusEcritureStocks);
    try {
      return PointEnregistre(
        await _dao.creerPoint(libelle: libelle, type: type),
      );
    } on RefusStock catch (e) {
      return PointRefuse(e.motif);
    }
  }

  Future<ResultatEcritureArticle> enregistrerArticle(
    SaisieArticle saisie, {
    bool modification = false,
  }) async {
    if (!_peutEcrire()) {
      return const ArticleRefuse(motif: refusEcritureStocks, codeHttp: 403);
    }

    final erreurs = <String, String>{};
    if (saisie.libelle.trim().isEmpty) {
      erreurs['libelle'] = MessagesStock.libelleObligatoire;
    }
    if (saisie.uniteMesure.trim().isEmpty) {
      erreurs['unite_mesure'] = MessagesStock.uniteObligatoire;
    }

    // Le seuil est un PARAMÈTRE, pas un état : il commande l'alerte (RG-07).
    // Un article journalier n'a pas de stock à comparer : le champ disparaît de
    // la modale, et le seuil retombe à zéro (maître l.358).
    var seuil = 0;
    if (saisie.suivi == SuiviArticle.permanent) {
      final lu = lireCentiemes(saisie.seuilAlerte);
      if (saisie.seuilAlerte.trim().isEmpty) {
        erreurs['seuil_alerte'] = MessagesStock.seuilObligatoire;
      } else if (lu == null) {
        erreurs['seuil_alerte'] =
            'Nombre attendu, au plus deux décimales (ex. 12 ou 12,5).';
      } else {
        seuil = lu;
      }
    }

    // Le stock d'ouverture, à la création d'un article suivi en stock. Il n'est
    // pas un champ : c'est une ENTRÉE (voir `SaisieArticle.stockOuverture`).
    ({int centiemes, int? coutDixMilliemes})? ouverture;
    if (!modification && saisie.suivi == SuiviArticle.permanent) {
      final brut = saisie.stockOuverture.trim();
      if (brut.isNotEmpty) {
        final quantite = lireCentiemes(brut);
        if (quantite == null) {
          erreurs['stock_ouverture'] =
              'Nombre attendu, au plus deux décimales (ex. 12 ou 12,5).';
        } else if (quantite > 0) {
          int? cout;
          final coutBrut = saisie.valeurAchat.trim();
          if (coutBrut.isNotEmpty) {
            cout = lireCout(coutBrut);
            if (cout == null) {
              erreurs['valeur_achat'] =
                  'Nombre attendu, au plus quatre décimales (ex. 1250 ou '
                  '1250,75).';
            }
          }
          ouverture = (centiemes: quantite, coutDixMilliemes: cout);
        }
      }
    }

    if (erreurs.isNotEmpty) {
      return ArticleRefuse(motif: erreurs.values.first, erreurs: erreurs);
    }

    final categorie = saisie.categorie?.trim();
    try {
      if (modification) {
        await _dao.modifierArticle(
          id: saisie.id,
          libelle: saisie.libelle,
          categorie: (categorie == null || categorie.isEmpty)
              ? null
              : categorie,
          uniteMesure: saisie.uniteMesure,
          seuilCentiemes: seuil,
          suivi: saisie.suivi,
          pointStockageId: saisie.pointStockageId,
        );
      } else {
        await _dao.creerArticle(
          id: saisie.id,
          libelle: saisie.libelle,
          categorie: (categorie == null || categorie.isEmpty)
              ? null
              : categorie,
          uniteMesure: saisie.uniteMesure,
          seuilCentiemes: seuil,
          suivi: saisie.suivi,
          pointStockageId: saisie.pointStockageId,
          auteurId: _auteurId(),
          ouverture: ouverture,
        );
      }
    } on RefusStock catch (e) {
      return ArticleRefuse(
        motif: e.motif,
        erreurs: e.champ == null ? const {} : {e.champ!: e.motif},
      );
    }

    return ArticleEnregistre(id: saisie.id, libelle: saisie.libelle.trim());
  }

  /// L'ENTRÉE saisie depuis la fiche article (`Stocks::faireEntrerLeStock`,
  /// directive du PO du 06/09/2026) : un mouvement d'entrée, jamais une valeur
  /// de stock. Le droit est exigé ICI — l'ouverture d'un bloc ne protège rien.
  /// Sans coût, l'entrée ne valorise rien (un zéro se lirait « reçu
  /// gratuitement » et écraserait le coût moyen pondéré).
  Future<ResultatEcritureMouvement> faireEntrerDepuisFiche({
    required String articleId,
    required String pointId,
    required String quantite,
    String? coutUnitaire,
  }) async {
    if (!_peutEcrire()) {
      return const MouvementRefuse(motif: refusEcritureStocks, codeHttp: 403);
    }
    if (!peutAjusterLeStock) {
      return const MouvementRefuse(
        motif: MessagesStock.entreeRefusRole,
        codeHttp: 403,
      );
    }
    return enregistrerMouvement(
      SaisieMouvement(
        articleId: articleId,
        pointId: pointId,
        type: TypeMouvement.entree,
        quantite: quantite,
        motif: MessagesStock.entreeMotif,
        coutUnitaire: coutUnitaire,
      ),
    );
  }

  /// Enregistre un mouvement — ou demande la confirmation de RG-06.
  ///
  /// ⚠ Un refus, jamais une file d'attente : annoncer « en attente de
  /// synchronisation » décrirait une attente sans fin sur une sortie de
  /// marchandise (PA-134). Le mouvement est « enregistré sur ce poste ».
  Future<ResultatEcritureMouvement> enregistrerMouvement(
    SaisieMouvement saisie,
  ) async {
    if (!_peutEcrire()) {
      return const MouvementRefuse(motif: refusEcritureStocks, codeHttp: 403);
    }

    final erreurs = <String, String>{};

    final quantite = lireCentiemes(saisie.quantite);
    final messageQuantite = erreurNombre(
      saisie.quantite,
      strictementPositif: true,
    );
    if (messageQuantite != null || quantite == null) {
      erreurs['quantite'] =
          messageQuantite ??
          'Nombre attendu, au plus deux décimales (ex. 12 ou 12,5).';
    }

    int? cout;
    final brutCout = saisie.coutUnitaire;
    if (brutCout != null && brutCout.trim().isNotEmpty) {
      cout = lireCout(brutCout);
      if (cout == null) {
        erreurs['cout_unitaire'] =
            'Nombre attendu, au plus quatre décimales (ex. 1250 ou 1250,75).';
      }
    }

    if (saisie.motif.trim().isEmpty) {
      erreurs['motif'] = MessagesStock.motifObligatoire;
    }

    if (erreurs.isNotEmpty) {
      return MouvementRefuse(motif: erreurs.values.first, erreurs: erreurs);
    }

    try {
      final issue = await _dao.ajouterMouvement(
        articleId: saisie.articleId,
        pointId: saisie.pointId,
        type: saisie.type,
        centiemes: quantite!,
        motif: saisie.motif,
        auteurId: _auteurId(),
        coutDixMilliemes: cout,
        forcage: saisie.validationRupture,
      );
      return switch (issue) {
        MouvementPose(:final mouvement) => MouvementEnregistre(mouvement),
        RuptureConstatee(:final disponible, :final demande) =>
          RuptureAConfirmer(
            message: messageRupture(
              disponible: ecrireCentiemes(disponible),
              demande: ecrireCentiemes(demande),
            ),
            stockDisponible: ecrireCentiemes(disponible),
            quantiteDemandee: ecrireCentiemes(demande),
          ),
      };
    } on RefusStock catch (e) {
      return MouvementRefuse(
        motif: e.motif,
        erreurs: e.champ == null ? const {} : {e.champ!: e.motif},
      );
    }
  }
}
