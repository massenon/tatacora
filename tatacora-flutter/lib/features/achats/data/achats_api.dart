import '../domain/entities/archivage_fournisseur.dart';
import '../domain/entities/bon_reception.dart';
import '../domain/entities/commande_achat.dart';
import '../domain/entities/fournisseur.dart';
import '../domain/entities/page_achats.dart';
import '../domain/entities/reglement_fournisseur.dart';
import '../domain/messages_achats.dart';
import '../domain/regles_reglement.dart';
import 'achats_dao.dart';
import 'reglements_fournisseur_dao.dart';

export '../domain/entities/page_achats.dart';

/// Ce qu'un appel de M7 peut rendre — **trois issues distinctes, toujours**.
///
/// ## Pourquoi un type générique ici, là où M6 en a écrit trois
///
/// `StocksApi` déclare une famille scellée par appel, et le dit : les deux
/// appels de M6 sont traités séparément par l'écran. M7 en compte **douze**.
/// Douze familles de trois classes seraient trente-six déclarations que rien
/// ne distinguerait, et la trente-sixième finirait par oublier l'issue
/// « injoignable » — c'est-à-dire par confondre une coupure avec un refus.
///
/// La propriété qui compte est conservée, et elle est même **imposée par le
/// type** : les trois issues restent distinctes, le `switch` reste exhaustif,
/// et chaque provider garde son type de charge utile. Ce qui disparaît, c'est
/// la recopie.
sealed class ResultatAchats<T> {
  const ResultatAchats();
}

final class AchatsRecu<T> extends ResultatAchats<T> {
  const AchatsRecu(this.donnees);
  final T donnees;
}

final class AchatsRefuse<T> extends ResultatAchats<T> {
  const AchatsRefuse({required this.motif, this.erreurs = const {}, this.code});

  final String motif;

  /// Les messages, **par champ**, affichés tels quels. N'en garder que le
  /// premier obligerait l'acheteur à deviner lequel de ses champs a été
  /// rejeté.
  final Map<String, String> erreurs;

  final int? code;
}

/// Conservée par le type, **jamais produite** : une base locale n'est pas hors
/// connexion. Les `switch` des écrans restent exhaustifs.
final class AchatsInjoignable<T> extends ResultatAchats<T> {
  const AchatsInjoignable();
}

/// Ce que l'enregistrement d'une réception peut rendre — EF-M7-03, RG-10.
///
/// **Quatre issues, pas trois.** [ToleranceNonConfiguree] n'est pas un refus
/// ordinaire : c'est un refus que l'acheteur ne peut pas corriger dans son
/// formulaire, parce qu'il vient d'un paramètre système absent
/// (`tolerance_reception_pct`, RG-10). Le ranger avec les autres refus
/// renverrait le magasinier corriger des quantités parfaitement justes.
///
/// Même forme que `RuptureAConfirmer` en M6 : un refus qui appelle un geste,
/// pas une correction de saisie.
sealed class ResultatReception {
  const ResultatReception();
}

final class ReceptionEnregistree extends ResultatReception {
  const ReceptionEnregistree(this.bon);
  final BonReception bon;
}

final class ToleranceNonConfiguree extends ResultatReception {
  const ToleranceNonConfiguree(this.message);

  /// La phrase du serveur, affichée telle quelle — elle nomme la clé et dit
  /// qui doit la renseigner.
  final String message;
}

final class ReceptionRefusee extends ResultatReception {
  const ReceptionRefusee({
    required this.motif,
    this.erreurs = const {},
    this.code,
  });

  final String motif;
  final Map<String, String> erreurs;
  final int? code;
}

/// Conservée par le type, **jamais produite** (voir [AchatsInjoignable]).
final class ReceptionInjoignable extends ResultatReception {
  const ReceptionInjoignable();
}

/// M7 Achats — **source LOCALE** (décision du Product Owner, 09/10/2026).
///
/// ⚠ Le nom `AchatsApi` est historique : ce n'était qu'un client HTTP de douze
/// routes, vidé de son corps le 14/09/2026 (zéro réseau), et la classe
/// n'appelle aucun serveur. Il est conservé pour ne pas rouvrir les écrans qui
/// la consomment ; c'est désormais le cas d'usage de M7, devant [AchatsDao].
///
/// ## Ce que cette classe décide, et ce qu'elle laisse au DAO
///
///  * **Les droits** — `M7` en lecture pour consulter, en écriture pour toute
///    saisie. Un écran qui masque un bouton ne protège rien.
///  * **La traduction des refus** — le DAO lève [RefusAchats] ou
///    [ToleranceAbsente] ; ici ils deviennent les issues que les écrans
///    traitent depuis toujours, sans qu'aucun écran n'ait à changer.
///
/// ## Ce que ce module ne fait PAS, et le dit
///
///  * **Le règlement fournisseur est un vrai geste** (D66, 12/10/2026) :
///    [reglerCommande] écrit le règlement ET sa pièce comptable (Dr 4011 / Cr
///    trésorerie) dans la même transaction, par `ReglementsFournisseurDao`.
///  * **L'archivage d'un fournisseur est un vrai geste** (D63, 12/10/2026) :
///    [preparerArchivage] compose le lot de la modale (verrous, états bloqué /
///    partiel / nominal), [archiverFournisseurs] l'exécute, [restaurerFournisseur]
///    le défait. Qui peut archiver est la règle UNIQUE de `regle_archivage.dart`
///    (droit `C` sur M7 ET un des deux rôles d'administration OU la bascule
///    `activation_suppression` ouverte) ; restaurer n'exige que l'écriture.
///  * **Aucune annulation de commande** : l'enum `commandes_achat.statut` n'a
///    pas de valeur `annulee`, au serveur comme ici.
///  * **Aucune facture fournisseur au rapprochement** : aucune table n'en
///    porte.
final class AchatsApi {
  AchatsApi({
    required this._dao,
    required this._peutLire,
    required this._peutEcrire,
    required this._auteurId,
    this._reglements,
    Future<bool> Function()? peutArchiver,
  }) : _peutArchiver = peutArchiver ?? _archivageFerme;

  /// Sans règle injectée, l'archivage reste FERMÉ : un appelant qui oublie de la
  /// brancher n'ouvre pas un geste que le serveur réserve — il le refuse.
  static Future<bool> _archivageFerme() async => false;

  /// `AutoriseArchivage::peutArchiver()` — la règle, relue À CHAQUE appel (la
  /// bascule peut changer entre deux gestes, et la session aussi).
  final Future<bool> Function() _peutArchiver;

  final AchatsDao _dao;

  /// Le DAO des règlements. Optionnel au constructeur pour les appelants qui ne
  /// règlent rien ; sans lui, régler LÈVE (`StateError`) — jamais un règlement
  /// silencieusement perdu.
  final ReglementsFournisseurDao? _reglements;
  final bool Function() _peutLire;
  final bool Function() _peutEcrire;
  final String? Function() _auteurId;

  /// La clé du paramètre de tolérance de réception (RG-10).
  ///
  /// Identifiant d'un paramètre, pas donnée de transport : les écrans s'en
  /// servent pour NOMMER ce qu'un administrateur doit renseigner.
  static const cleTolerance = AchatsDao.cleTolerance;

  static ResultatAchats<T> _refusLecture<T>() =>
      AchatsRefuse<T>(motif: MessagesAchats.droitLectureRefuse, code: 403);

  static ResultatAchats<T> _refusDroitEcriture<T>() =>
      AchatsRefuse<T>(motif: MessagesAchats.droitEcritureRefuse, code: 403);

  /// Exécute une écriture en traduisant les refus du DAO.
  Future<ResultatAchats<T>> _ecrire<T>(Future<T> Function() ecriture) async {
    if (!_peutEcrire()) return _refusDroitEcriture<T>();
    try {
      return AchatsRecu<T>(await ecriture());
    } on RefusAchats catch (e) {
      return AchatsRefuse<T>(
        motif: e.motif,
        erreurs: e.champ == null ? const {} : {e.champ!: e.motif},
        code: 422,
      );
    } on ToleranceAbsente catch (e) {
      return AchatsRefuse<T>(motif: e.message, code: 422);
    }
  }

  /* ================================================================== */
  /* Fournisseurs                                                        */
  /* ================================================================== */

  Future<ResultatAchats<PageAchats<Fournisseur>>> fournisseurs({
    String? recherche,
    EvaluationFournisseur? evaluation,
    String? categorie,
    int page = 1,
  }) async {
    if (!_peutLire()) return _refusLecture();
    return AchatsRecu(
      await _dao.fournisseurs(
        recherche: recherche,
        evaluation: evaluation,
        page: page,
      ),
    );
  }

  /// `null` — « on ne sait pas », jamais une liste vide — quand le droit de
  /// lecture manque : une liste vide se lirait « aucun fournisseur
  /// enregistré », et le sélecteur s'afficherait vide sous un formulaire qui
  /// semble fonctionner (PA-129). Avec le droit, une liste vide est la vérité.
  Future<List<Fournisseur>?> tousLesFournisseurs({int pagesMax = 20}) async {
    if (!_peutLire()) return null;
    return _dao.tousLesFournisseurs();
  }

  Future<ResultatAchats<Fournisseur>> enregistrerFournisseur(
    SaisieFournisseur saisie, {
    required bool modification,
  }) => _ecrire(
    () => modification
        ? _dao.modifierFournisseur(saisie, auteurId: _auteurId())
        : _dao.creerFournisseur(saisie, auteurId: _auteurId()),
  );

  /// `exigerArchivage()` : le droit d'ÉCRITURE d'abord (403), PUIS la règle
  /// d'archivage — la bascule fermée refuse avec la phrase du serveur. Rend le
  /// refus, ou `null` quand le geste est permis.
  Future<AchatsRefuse<T>?> _refusArchivage<T>() async {
    if (!_peutEcrire()) {
      return AchatsRefuse<T>(
        motif: MessagesAchats.droitEcritureRefuse,
        code: 403,
      );
    }
    if (!await _peutArchiver()) {
      return AchatsRefuse<T>(motif: MessagesAchats.refusBascule, code: 403);
    }
    return null;
  }

  /// « Supprimer » de la vue — l'OUVERTURE de la confirmation
  /// (`confirmerArchivageFournisseur`) : exige le droit d'archiver dès ici, puis
  /// compose le lot. Les motifs datent de l'ouverture et ne protègent rien : le
  /// verrou qui tranche est recontrôlé par [archiverFournisseurs].
  Future<ResultatAchats<LotArchivage>> preparerArchivage(
    List<String> ids,
  ) async {
    final refus = await _refusArchivage<LotArchivage>();
    if (refus != null) return refus;
    return AchatsRecu(await _dao.composerLotArchivage(ids));
  }

  /// « Supprimer définitivement » de la modale — l'EXÉCUTION (`archiverFournisseurs`
  /// du composant) : le droit d'archiver est exigé de nouveau, la bascule ayant pu
  /// se refermer entre le rendu et le clic. Archive : `actif = false`, jamais un
  /// effacement.
  Future<ResultatAchats<ResultatArchivage>> archiverFournisseurs(
    List<String> ids,
  ) async {
    final refus = await _refusArchivage<ResultatArchivage>();
    if (refus != null) return refus;
    try {
      return AchatsRecu(await _dao.archiverLot(ids, auteurId: _auteurId()));
    } on RefusAchats catch (e) {
      return AchatsRefuse<ResultatArchivage>(motif: e.motif, code: 422);
    }
  }

  /// « Restaurer » de la vue. **Pas derrière la règle d'archivage** : seul le
  /// droit d'écriture est exigé (`exigerEcriture`, `restaurerFournisseur` du
  /// serveur) — fermer la bascule pendant qu'un fournisseur est aux archives ne
  /// doit jamais l'y enfermer.
  Future<ResultatAchats<Fournisseur>> restaurerFournisseur(String id) =>
      _ecrire(() => _dao.restaurerFournisseur(id, auteurId: _auteurId()));

  /* ================================================================== */
  /* Commandes                                                           */
  /* ================================================================== */

  Future<ResultatAchats<PageAchats<CommandeAchat>>> commandes({
    String? recherche,
    StatutCommande? statut,
    String? fournisseurId,
    int page = 1,
    int? parPage,
    ({String debut, String fin})? periode,
  }) async {
    if (!_peutLire()) return _refusLecture();
    return AchatsRecu(
      await _dao.commandes(
        recherche: recherche,
        statut: statut,
        fournisseurId: fournisseurId,
        periode: periode,
        page: page,
        parPage: parPage ?? 200,
      ),
    );
  }

  Future<ResultatAchats<int>> compterCommandes(StatutCommande statut) async {
    if (!_peutLire()) return _refusLecture();
    return AchatsRecu(await _dao.compterCommandes({statut}));
  }

  /// « Commandes en attente » de la vue : `brouillon` ET `envoyee`
  /// (`Approvisionnement::render`, `whereIn('statut', [...])`). Le client ne
  /// comptait que `envoyee` jusqu'au 09/10/2026 : un brouillon est une commande
  /// qui attend, et le compteur de la vue le compte.
  Future<ResultatAchats<int>> compterCommandesEnAttente() async {
    if (!_peutLire()) return _refusLecture();
    return AchatsRecu(
      await _dao.compterCommandes({
        StatutCommande.brouillon,
        StatutCommande.envoyee,
      }),
    );
  }

  Future<ResultatAchats<CommandeAchatDetail>> commande(String id) async {
    if (!_peutLire()) return _refusLecture();
    final detail = await _dao.commande(id);
    if (detail == null) {
      return const AchatsRefuse<CommandeAchatDetail>(
        motif: MessagesAchats.commandeIntrouvable,
        code: 404,
      );
    }
    return AchatsRecu(detail);
  }

  Future<ResultatAchats<CommandeAchatDetail>> creerCommande(
    SaisieCommande saisie,
  ) => _ecrire(() => _dao.creerCommande(saisie, auteurId: _auteurId()));

  Future<ResultatAchats<CommandeAchatDetail>> envoyerCommande(String id) =>
      _ecrire(() => _dao.envoyerCommande(id));

  Future<ResultatAchats<CommandeAchatDetail>> cloturerCommande(String id) =>
      _ecrire(() => _dao.cloturerCommande(id));

  /* ================================================================== */
  /* Règlement fournisseur (D66)                                         */
  /* ================================================================== */

  ReglementsFournisseurDao get _reglementsObligatoires =>
      _reglements ??
      (throw StateError(
        'AchatsApi sans ReglementsFournisseurDao : un règlement ne '
        's’enregistre jamais sans son DAO (et donc sans sa pièce).',
      ));

  /// `Approvisionnement::ouvrirFormulaireReglement` : le droit d'écriture sur
  /// M7 d'abord (403), puis la commande, puis son reste dû. Un refus porte la
  /// phrase du serveur et AUCUN champ : c'est l'erreur `selection` de la vue,
  /// posée en bandeau de la page.
  Future<ResultatAchats<OuvertureReglement>> ouvrirReglement(
    String commandeId,
  ) async {
    if (!_peutEcrire()) return _refusDroitEcriture<OuvertureReglement>();
    try {
      return AchatsRecu(await _reglementsObligatoires.ouvrir(commandeId));
    } on RefusReglement catch (e) {
      return AchatsRefuse<OuvertureReglement>(motif: e.message, code: 422);
    }
  }

  /// `Approvisionnement::enregistrerReglement` : le droit d'écriture sur M7,
  /// puis la validation, puis le service — le règlement ET sa pièce comptable,
  /// dans UNE transaction. Un refus du service s'affiche sous le champ montant
  /// (`erreurs['regMontant']`), comme la vue.
  Future<ResultatAchats<ReglementFournisseur>> reglerCommande({
    required String? commandeId,
    required String? montant,
    required String? tresorerie,
  }) async {
    if (!_peutEcrire()) return _refusDroitEcriture<ReglementFournisseur>();
    final auteur = _auteurId();
    if (auteur == null) {
      return const AchatsRefuse<ReglementFournisseur>(
        motif: MessagesAchats.auteurInconnu,
        code: 422,
      );
    }
    try {
      return AchatsRecu(
        await _reglementsObligatoires.regler(
          commandeId: commandeId,
          montantSaisi: montant,
          tresorerieSaisie: tresorerie,
          auteurId: auteur,
        ),
      );
    } on RefusReglement catch (e) {
      return AchatsRefuse<ReglementFournisseur>(
        motif: e.message,
        erreurs: e.champ == null ? const {} : {e.champ!.propriete: e.message},
        code: 422,
      );
    }
  }

  /* ================================================================== */
  /* Réceptions                                                          */
  /* ================================================================== */

  Future<ResultatAchats<PageAchats<BonReception>>> receptions({
    String? commandeId,
    ConformiteReception? conformite,
    int page = 1,
    ({String debut, String fin})? periode,
  }) async {
    if (!_peutLire()) return _refusLecture();
    if (conformite == null) {
      return AchatsRecu(
        await _dao.receptions(
          commandeId: commandeId,
          page: page,
          periode: periode,
        ),
      );
    }
    // Le filtre de conformité n'est plus offert par l'écran (PA-185) : il reste
    // servi, sur la liste ENTIÈRE.
    final tous = (await _dao.receptions(
      commandeId: commandeId,
      parPage: 100000,
    )).elements.where((b) => b.conformiteCode == conformite.code).toList();
    return AchatsRecu(
      PageAchats<BonReception>(
        elements: tous.take(200).toList(),
        total: tous.length,
        derniere: tous.isEmpty ? 1 : (tous.length + 199) ~/ 200,
      ),
    );
  }

  /// ⚠ L'enregistrement d'une réception est ATOMIQUE avec ses entrées de stock
  /// (voir [AchatsDao.enregistrerReception]) : si l'une est refusée, rien
  /// n'est écrit.
  Future<ResultatReception> receptionner(SaisieReception saisie) async {
    if (!_peutEcrire()) {
      return const ReceptionRefusee(
        motif: MessagesAchats.droitEcritureRefuse,
        code: 403,
      );
    }
    try {
      return ReceptionEnregistree(
        await _dao.enregistrerReception(saisie, auteurId: _auteurId()),
      );
    } on ToleranceAbsente catch (e) {
      return ToleranceNonConfiguree(e.message);
    } on RefusAchats catch (e) {
      return ReceptionRefusee(
        motif: e.motif,
        erreurs: e.champ == null ? const {} : {e.champ!: e.motif},
        code: 422,
      );
    }
  }

  Future<ResultatAchats<Rapprochement>> rapprocher(String commandeId) async {
    if (!_peutLire()) return _refusLecture();
    final r = await _dao.rapprocher(commandeId);
    if (r == null) {
      return const AchatsRefuse<Rapprochement>(
        motif: MessagesAchats.commandeIntrouvable,
        code: 404,
      );
    }
    return AchatsRecu(r);
  }
}
