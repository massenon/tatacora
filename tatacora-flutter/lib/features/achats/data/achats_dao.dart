import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../synchronisation/data/documents_autres_postes.dart';
import '../../synchronisation/data/operations_sync_dao.dart';
import '../../synchronisation/domain/charges_synchronisation.dart';
import '../../synchronisation/domain/operation_sync.dart';
import '../../../core/format/cle_comparaison.dart';
import '../../stocks/data/stocks_dao.dart';
import '../../stocks/domain/entities/etat_stock.dart' show SuiviArticle;
import '../../stocks/domain/entities/mouvement_stock.dart';
import '../../stocks/domain/messages_stock.dart';
import '../domain/calcul_achats.dart';
import '../domain/decimal_texte.dart';
import '../domain/entities/archivage_fournisseur.dart';
import '../domain/entities/bon_reception.dart';
import '../domain/entities/commande_achat.dart';
import '../domain/entities/fournisseur.dart';
import '../domain/entities/page_achats.dart';
import '../domain/messages_achats.dart';
import '../domain/regles_reglement.dart' show resteDuCentimes;

/// Un refus du DAO : une règle que la base ne peut pas porter seule. Il porte
/// une phrase écrite pour l'exploitant (celle du serveur quand il en a une),
/// et le champ fautif quand il y en a un.
final class RefusAchats implements Exception {
  const RefusAchats(this.motif, {this.champ});

  final String motif;
  final String? champ;

  @override
  String toString() => 'RefusAchats($motif)';
}

/// La tolérance de réception n'est pas renseignée (RG-10).
///
/// Distincte de [RefusAchats] : le magasinier ne peut rien corriger dans son
/// formulaire, c'est un paramètre qui manque. L'écran l'envoie vers les
/// Paramètres au lieu de lui montrer une erreur de saisie.
final class ToleranceAbsente implements Exception {
  const ToleranceAbsente();

  String get message => MessagesAchats.toleranceAbsente;

  @override
  String toString() => 'ToleranceAbsente';
}

/// Accès Drift à M7 — **local pur**, et UNIQUE point d'écriture des cinq
/// tables d'achats.
///
/// ## Aucun mixin généré
///
/// Comme `StocksDao` : on passe par `attachedDatabase.<table>`, sans
/// `@DriftAccessor` ni `part`.
///
/// ## Ce que le DAO garantit
///
///  * **une écriture, une transaction** : une commande et ses lignes naissent
///    ensemble ou pas du tout ; une réception, son bon, ses lignes ET les
///    entrées de stock qu'elle génère s'écrivent dans la MÊME transaction —
///    si l'une est refusée, rien n'est écrit (jamais une marchandise qui
///    entre en stock sans bon, ni un bon sans marchandise) ;
///  * **prix et libellé figés à l'ajout** sur chaque ligne de commande ;
///  * **l'auteur** (RG-15) sur toute écriture : sans session, rien ne s'écrit ;
///  * **les règles de gestion sont celles de `calcul_achats.dart`** : le DAO
///    lit, la fonction pure décide.
///
/// ## La commande et la réception n'écrivent aucune pièce — et c'est DIT
///
/// Une commande n'est pas un mouvement d'argent, et une réception ne règle
/// personne. Le seul vrai mouvement d'argent de M7, le règlement fournisseur,
/// vit dans `ReglementsFournisseurDao` (Dr 4011 / Cr trésorerie, même
/// transaction). Ce DAO LIT les règlements actifs pour chiffrer « Réglé » et
/// « Reste dû » de chaque commande ; il n'en écrit aucun.
///
/// ## Qui lit, qui écrit, qui descend
///
/// Voir `core/database/tables/achats_tables.dart` : un seul auteur par table,
/// et personne ne les descend (zéro réseau).
class AchatsDao extends DatabaseAccessor<AppDatabase> {
  AchatsDao(
    super.db, {
    required this._stocks,
    Uuid? uuid,
    DateTime Function()? maintenant,
  }) : _uuid = uuid ?? const Uuid(),
       _maintenant = maintenant ?? DateTime.now;

  final StocksDao _stocks;
  final Uuid _uuid;
  final DateTime Function() _maintenant;

  /// La clé du paramètre de tolérance (RG-10).
  static const cleTolerance = 'tolerance_reception_pct';

  static String _jour(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /* ================================================================== */
  /* Fournisseurs — lecture                                              */
  /* ================================================================== */

  Fournisseur _fournisseur(FournisseursLocalData f) => Fournisseur(
    id: f.id,
    raisonSociale: f.raisonSociale,
    contact: f.contact,
    categorie: f.categorie,
    conditionsPaiement: f.conditionsPaiement,
    evaluationCode: f.evaluation,
    // `false` = ARCHIVÉ : voir l'en-tête de `achats_tables.dart`.
    actif: f.actif,
  );

  /// Clé de comparaison : minuscules et SANS accent (`cleDeComparaison`, un
  /// seul auteur pour M4 et M7). La collation du serveur
  /// (`utf8mb4_unicode_ci`) range « Éts » avec « Ets » et `LIKE '%ets%'` le
  /// retrouve ; Dart, lui, rangerait « É » après « z » (point de code).
  static String _cle(String texte) => cleDeComparaison(texte);

  static int _comparerTexte(String a, String b) => _cle(a).compareTo(_cle(b));

  static PageAchats<T> _page<T>(List<T> tous, int page, int parPage) {
    final numero = page < 1 ? 1 : page;
    final derniere = tous.isEmpty ? 1 : (tous.length + parPage - 1) ~/ parPage;
    final debut = (numero - 1) * parPage;
    final elements = debut >= tous.length
        ? <T>[]
        : tous.sublist(
            debut,
            debut + parPage > tous.length ? tous.length : debut + parPage,
          );
    return PageAchats<T>(
      elements: elements,
      total: tous.length,
      derniere: derniere,
    );
  }

  /// La recherche porte sur la raison sociale et le contact (`colonnesRecherchables`
  /// de la vue), insensible à la casse. Le filtrage est fait ici, en Unicode :
  /// le `LIKE` de SQLite ne replie la casse que sur l'ASCII, et « éts » ne
  /// trouverait pas « Éts ».
  Future<PageAchats<Fournisseur>> fournisseurs({
    String? recherche,
    EvaluationFournisseur? evaluation,
    int page = 1,
    int parPage = 25,
  }) async {
    final lignes = await select(attachedDatabase.fournisseursLocal).get();
    final terme = _cle((recherche ?? '').trim());

    final retenues =
        lignes.where((f) {
          if (evaluation != null && f.evaluation != evaluation.code) {
            return false;
          }
          if (terme.isEmpty) return true;
          return _cle(f.raisonSociale).contains(terme) ||
              _cle(f.contact ?? '').contains(terme);
        }).toList()..sort((a, b) {
          final c = _comparerTexte(a.raisonSociale, b.raisonSociale);
          return c != 0 ? c : a.id.compareTo(b.id);
        });

    return _page([for (final f in retenues) _fournisseur(f)], page, parPage);
  }

  /// Le référentiel pour le sélecteur de la commande : les fournisseurs ACTIFS
  /// (`Fournisseur::query()->where('actif', true)` de `Approvisionnement`). Un
  /// fournisseur archivé n'est plus proposé — sans ce filtre l'archivage n'aurait
  /// rien archivé —, mais les commandes DÉJÀ passées à lui restent lisibles :
  /// c'est le sélecteur qui filtre, jamais le registre. Une liste vide est ici la
  /// vérité : aucun fournisseur actif sur ce poste.
  Future<List<Fournisseur>> tousLesFournisseurs() async {
    final lignes =
        await (select(
            attachedDatabase.fournisseursLocal,
          )..where((f) => f.actif.equals(true))).get()
          ..sort((a, b) {
            final c = _comparerTexte(a.raisonSociale, b.raisonSociale);
            return c != 0 ? c : a.id.compareTo(b.id);
          });
    return [for (final f in lignes) _fournisseur(f)];
  }

  /* ================================================================== */
  /* Fournisseurs — écriture                                             */
  /* ================================================================== */

  String? _ouNull(String? valeur) {
    final v = valeur?.trim();
    return v == null || v.isEmpty ? null : v;
  }

  void _verifierFournisseur(SaisieFournisseur s) {
    if (s.raisonSociale.trim().isEmpty) {
      throw const RefusAchats(
        MessagesAchats.raisonSocialeObligatoire,
        champ: 'raison_sociale',
      );
    }
    if (s.raisonSociale.trim().length > 255) {
      throw const RefusAchats(
        'La raison sociale ne peut pas dépasser 255 caractères.',
        champ: 'raison_sociale',
      );
    }
    final code = s.evaluationCode;
    if (code != null && EvaluationFournisseur.depuisCode(code) == null) {
      throw const RefusAchats(
        MessagesAchats.evaluationInconnue,
        champ: 'evaluation',
      );
    }
  }

  Future<Fournisseur> creerFournisseur(
    SaisieFournisseur saisie, {
    required String? auteurId,
  }) async {
    if (auteurId == null) {
      throw const RefusAchats(MessagesAchats.auteurInconnu);
    }
    _verifierFournisseur(saisie);

    return transaction(() async {
      final deja = await (select(
        attachedDatabase.fournisseursLocal,
      )..where((f) => f.id.equals(saisie.id))).getSingleOrNull();
      if (deja != null) {
        // Un second envoi du même identifiant est une anomalie qui doit se
        // voir (double clic sur « Enregistrer »), pas un doublon silencieux.
        throw const RefusAchats(
          'Cet identifiant est déjà utilisé par un autre fournisseur.',
          champ: 'id',
        );
      }
      await into(attachedDatabase.fournisseursLocal).insert(
        FournisseursLocalCompanion.insert(
          id: saisie.id,
          raisonSociale: saisie.raisonSociale.trim(),
          contact: Value(_ouNull(saisie.contact)),
          categorie: Value(_ouNull(saisie.categorie)),
          conditionsPaiement: Value(_ouNull(saisie.conditionsPaiement)),
          evaluation: Value(_ouNull(saisie.evaluationCode)),
          creeLe: _maintenant(),
          creePar: auteurId,
        ),
      );
      final ecrit = await (select(
        attachedDatabase.fournisseursLocal,
      )..where((f) => f.id.equals(saisie.id))).getSingle();
      // Lot F1 : la fiche part au serveur, dans CETTE transaction.
      await _file.enfiler(
        table: TableSynchronisee.fournisseurs,
        entiteId: ecrit.id,
        type: TypeOperationSync.creation,
        payload: _chargeFournisseur(ecrit),
      );
      return _fournisseur(ecrit);
    });
  }

  Future<Fournisseur> modifierFournisseur(
    SaisieFournisseur saisie, {
    required String? auteurId,
  }) async {
    if (auteurId == null) {
      throw const RefusAchats(MessagesAchats.auteurInconnu);
    }
    _verifierFournisseur(saisie);

    return transaction(() async {
      final existant = await (select(
        attachedDatabase.fournisseursLocal,
      )..where((f) => f.id.equals(saisie.id))).getSingleOrNull();
      if (existant == null) {
        throw const RefusAchats(MessagesAchats.fournisseurIntrouvable);
      }
      await (update(
        attachedDatabase.fournisseursLocal,
      )..where((f) => f.id.equals(saisie.id))).write(
        FournisseursLocalCompanion(
          raisonSociale: Value(saisie.raisonSociale.trim()),
          contact: Value(_ouNull(saisie.contact)),
          categorie: Value(_ouNull(saisie.categorie)),
          conditionsPaiement: Value(_ouNull(saisie.conditionsPaiement)),
          evaluation: Value(_ouNull(saisie.evaluationCode)),
          modifieLe: Value(_maintenant()),
          modifiePar: Value(auteurId),
        ),
      );
      final ecrit = await (select(
        attachedDatabase.fournisseursLocal,
      )..where((f) => f.id.equals(saisie.id))).getSingle();
      // Lot F1 : seuls les champs changés partent.
      await _file.enfiler(
        table: TableSynchronisee.fournisseurs,
        entiteId: ecrit.id,
        type: TypeOperationSync.modification,
        payload: champsModifies(
          _chargeFournisseur(existant),
          _chargeFournisseur(ecrit),
        ),
      );
      return _fournisseur(ecrit);
    });
  }

  /// La file d'envoi (lot F1). Son propre générateur d'UUID : celui de ce DAO
  /// est injectable.
  OperationsSyncDao get _file => OperationsSyncDao(attachedDatabase);

  static Map<String, Object?> _chargeFournisseur(FournisseursLocalData f) =>
      chargeFournisseur(
        raisonSociale: f.raisonSociale,
        contact: f.contact,
        categorie: f.categorie,
        conditionsPaiement: f.conditionsPaiement,
        evaluation: f.evaluation,
      );

  /* ================================================================== */
  /* Fournisseurs — archivage (D63)                                       */
  /* ================================================================== */

  /// Les commandes qui ENGAGENT le fournisseur — `ReferentielFournisseurService::
  /// engagements()` : le verrou du maître, un élément engagé ailleurs ne
  /// s'archive pas.
  ///
  /// Une commande RÉCEPTIONNÉE ou CLÔTURÉE n'engage plus rien : elle est derrière
  /// nous, et elle reste lisible puisque rien n'est effacé. Ce qui engage, c'est
  /// ce qui reste à faire — un brouillon, une commande envoyée, une réception
  /// partielle. Archiver sous une commande en cours ferait disparaître le
  /// fournisseur du sélecteur au moment même où la réception doit être saisie.
  /// Un statut INCONNU engage (`whereNotIn` du serveur) : on ne devine pas
  /// qu'une commande est derrière nous.
  Future<List<CommandesAchatLocalData>> engagements(
    String fournisseurId,
  ) async {
    final lignes =
        await (select(attachedDatabase.commandesAchatLocal)..where(
              (c) =>
                  c.fournisseurId.equals(fournisseurId) &
                  c.statut.isNotIn([
                    StatutCommande.receptionnee.code,
                    StatutCommande.cloturee.code,
                  ]),
            ))
            .get();
    return lignes..sort((a, b) {
      final c = a.dateCommande.compareTo(b.dateCommande);
      return c != 0 ? c : a.id.compareTo(b.id);
    });
  }

  /// `Achats::confirmerArchivageFournisseur` : compose le lot que la modale
  /// présente, pour les [ids] visés (une ligne, ou la sélection).
  ///
  /// Seuls les fournisseurs ACTIFS entrent dans le lot (un archivé n'est pas
  /// re-archivé), triés par raison sociale ; chacun porte, s'il est engagé, son
  /// motif « [nom] — [verrou] ». `libelle` est le nom quand LE LOT EN COMPTE UN
  /// SEUL, vide sinon — et un lot vide (la sélection ne porte que des fiches déjà
  /// archivées) est BLOQUÉ sans motif : le serveur ouvre alors la modale, il ne
  /// retourne pas (D271).
  Future<LotArchivage> composerLotArchivage(List<String> ids) async {
    final actifs =
        await (select(
            attachedDatabase.fournisseursLocal,
          )..where((f) => f.id.isIn(ids) & f.actif.equals(true))).get()
          ..sort((a, b) {
            final c = _comparerTexte(a.raisonSociale, b.raisonSociale);
            return c != 0 ? c : a.id.compareTo(b.id);
          });

    final retenus = <String>[];
    final motifs = <String>[];
    var conserves = 0;
    final noms = <String>[];
    for (final f in actifs) {
      final engages = await engagements(f.id);
      noms.add(f.raisonSociale);
      if (engages.isEmpty) {
        retenus.add(f.id);
        continue;
      }
      conserves++;
      motifs.add(
        '${f.raisonSociale} — '
        '${MessagesAchats.verrouArchivage(engages.length)}',
      );
    }

    return LotArchivage(
      ids: retenus,
      motifs: motifs,
      conserves: conserves,
      bloque: retenus.isEmpty,
      libelle: noms.length == 1 ? noms.first : '',
    );
  }

  /// `ReferentielFournisseurService::archiver` : `actif = false`, jamais un
  /// `delete()`. L'engagement est RECONTRÔLÉ au moment d'agir — entre
  /// l'ouverture de la modale et le clic, une commande a pu naître —, dans la
  /// MÊME transaction que l'écriture.
  Future<void> archiverFournisseur(
    String id, {
    required String? auteurId,
  }) async {
    if (auteurId == null) {
      throw const RefusAchats(MessagesAchats.auteurInconnu);
    }
    await transaction(() async {
      final f = await (select(
        attachedDatabase.fournisseursLocal,
      )..where((x) => x.id.equals(id))).getSingleOrNull();
      if (f == null) {
        throw const RefusAchats(MessagesAchats.fournisseurIntrouvable);
      }
      final engages = await engagements(id);
      if (engages.isNotEmpty) {
        throw RefusAchats(MessagesAchats.verrouArchivage(engages.length));
      }
      await (update(
        attachedDatabase.fournisseursLocal,
      )..where((x) => x.id.equals(id))).write(
        FournisseursLocalCompanion(
          actif: const Value(false),
          modifieLe: Value(_maintenant()),
          modifiePar: Value(auteurId),
        ),
      );
      // Lot F1 : l'archivage part en `actif: false` (le serveur l'applique
      // sous SA règle de droits, `DroitArchivageService`).
      await _file.enfiler(
        table: TableSynchronisee.fournisseurs,
        entiteId: id,
        type: TypeOperationSync.modification,
        payload: const {'actif': false},
      );
    });
  }

  /// `Achats::archiverFournisseurs` : archive chaque fournisseur du lot par
  /// [archiverFournisseur], et rend le nombre archivé ET le DERNIER refus. Un
  /// refus d'un fournisseur devenu engagé n'empêche PAS les autres archivages.
  Future<ResultatArchivage> archiverLot(
    List<String> ids, {
    required String? auteurId,
  }) async {
    if (auteurId == null) {
      throw const RefusAchats(MessagesAchats.auteurInconnu);
    }
    // Le serveur relit les fiches de `whereIn('id', …)->get()` : l'ordre est
    // celui de la base, jamais celui de la sélection.
    final fiches = await (select(
      attachedDatabase.fournisseursLocal,
    )..where((f) => f.id.isIn(ids))).get();

    var archives = 0;
    String? refus;
    for (final f in fiches) {
      try {
        await archiverFournisseur(f.id, auteurId: auteurId);
        archives++;
      } on RefusAchats catch (e) {
        refus = e.motif;
      }
    }
    return ResultatArchivage(archives: archives, refus: refus);
  }

  /// `ReferentielFournisseurService::restaurer` : `actif = true`. Déjà actif :
  /// rien ne change (ni `modifieLe`, ni `modifiePar` — comme le serveur, qui
  /// retourne avant d'écrire). Restaurer n'est PAS derrière la bascule : fermer
  /// la bascule pendant qu'un fournisseur est aux archives ne doit jamais l'y
  /// enfermer (« reste restaurable » serait sinon une promesse que rien ne tient,
  /// PA-59/60/61).
  Future<Fournisseur> restaurerFournisseur(
    String id, {
    required String? auteurId,
  }) async {
    if (auteurId == null) {
      throw const RefusAchats(MessagesAchats.auteurInconnu);
    }
    return transaction(() async {
      final f = await (select(
        attachedDatabase.fournisseursLocal,
      )..where((x) => x.id.equals(id))).getSingleOrNull();
      if (f == null) {
        throw const RefusAchats(MessagesAchats.fournisseurIntrouvable);
      }
      if (!f.actif) {
        await (update(
          attachedDatabase.fournisseursLocal,
        )..where((x) => x.id.equals(id))).write(
          FournisseursLocalCompanion(
            actif: const Value(true),
            modifieLe: Value(_maintenant()),
            modifiePar: Value(auteurId),
          ),
        );
        // Lot F1 : la restauration part en `actif: true`.
        await _file.enfiler(
          table: TableSynchronisee.fournisseurs,
          entiteId: id,
          type: TypeOperationSync.modification,
          payload: const {'actif': true},
        );
      }
      return _fournisseur(
        await (select(
          attachedDatabase.fournisseursLocal,
        )..where((x) => x.id.equals(id))).getSingle(),
      );
    });
  }

  /* ================================================================== */
  /* Commandes — lecture                                                 */
  /* ================================================================== */

  Future<Map<String, int>> _montantsParCommande() async {
    final lignes = await select(
      attachedDatabase.lignesCommandeAchatLocal,
    ).get();
    final totaux = <String, int>{};
    for (final l in lignes) {
      totaux[l.commandeId] =
          (totaux[l.commandeId] ?? 0) +
          montantLigneCentimes(
            quantiteCentiemes: l.quantiteCentiemes,
            prixUnitaireCentimes: l.prixUnitaireCentimes,
          );
    }
    return totaux;
  }

  Future<Map<String, int>> _nombreLignesParCommande() async {
    final lignes = await select(
      attachedDatabase.lignesCommandeAchatLocal,
    ).get();
    final nombres = <String, int>{};
    for (final l in lignes) {
      nombres[l.commandeId] = (nombres[l.commandeId] ?? 0) + 1;
    }
    return nombres;
  }

  /// La somme des règlements ACTIFS, par commande (`totalRegle()` du service
  /// de règlement). Lecture seule : l'unique auteur de la table est
  /// `ReglementsFournisseurDao`. Un règlement annulé ne compte plus (PA-168).
  Future<Map<String, int>> _reglesParCommande() async {
    final lignes = await (select(
      attachedDatabase.reglementsFournisseurLocal,
    )..where((r) => r.statut.equals('actif'))).get();
    final totaux = <String, int>{};
    for (final r in lignes) {
      totaux[r.commandeId] = (totaux[r.commandeId] ?? 0) + r.montantCentimes;
    }
    return totaux;
  }

  CommandeAchat _commande(
    CommandesAchatLocalData c, {
    required String raisonSociale,
    required int nombreLignes,
    required int montantCentimes,
    required int regleCentimes,
  }) {
    final statut = StatutCommande.depuisCode(c.statut);
    return CommandeAchat(
      id: c.id,
      dateCommande: c.dateCommande,
      statutCode: c.statut,
      fournisseurId: c.fournisseurId,
      fournisseurRaisonSociale: raisonSociale,
      nombreLignes: nombreLignes,
      montantTotal: depuisCentiemes(montantCentimes),
      montantRegle: depuisCentiemes(regleCentimes),
      resteDu: depuisCentiemes(
        resteDuCentimes(
          totalCommandeCentimes: montantCentimes,
          regleActifCentimes: regleCentimes,
        ),
      ),
      receptionnable: receptionnable(statut),
      cloturable: cloturable(statut),
    );
  }

  /// Le registre, `date_commande` décroissante puis identifiant — comme le
  /// serveur. La recherche porte sur la raison sociale du fournisseur.
  Future<PageAchats<CommandeAchat>> commandes({
    String? recherche,
    StatutCommande? statut,
    String? fournisseurId,
    int page = 1,
    int parPage = 200,
  }) async {
    final commandes = await select(attachedDatabase.commandesAchatLocal).get();
    final fournisseurs = {
      for (final f in await select(attachedDatabase.fournisseursLocal).get())
        f.id: f.raisonSociale,
    };
    final montants = await _montantsParCommande();
    final nombres = await _nombreLignesParCommande();
    final regles = await _reglesParCommande();
    final terme = _cle((recherche ?? '').trim());

    final retenues =
        commandes.where((c) {
          if (statut != null && c.statut != statut.code) return false;
          if (fournisseurId != null && c.fournisseurId != fournisseurId) {
            return false;
          }
          if (terme.isEmpty) return true;
          return _cle(fournisseurs[c.fournisseurId] ?? '').contains(terme);
        }).toList()..sort((a, b) {
          final c = b.dateCommande.compareTo(a.dateCommande);
          return c != 0 ? c : a.id.compareTo(b.id);
        });

    return _page(
      [
        for (final c in retenues)
          _commande(
            c,
            raisonSociale: fournisseurs[c.fournisseurId] ?? '',
            nombreLignes: nombres[c.id] ?? 0,
            montantCentimes: montants[c.id] ?? 0,
            regleCentimes: regles[c.id] ?? 0,
          ),
      ],
      page,
      parPage,
    );
  }

  /// Le décompte des commandes dont le statut est l'un de [statuts] — jamais
  /// la somme de ce qu'une page montre.
  Future<int> compterCommandes(Set<StatutCommande> statuts) async {
    final codes = {for (final s in statuts) s.code};
    final lignes = await select(attachedDatabase.commandesAchatLocal).get();
    return lignes.where((c) => codes.contains(c.statut)).length;
  }

  Future<Map<String, int>> _recuesParArticle(String commandeId) async {
    final b = attachedDatabase.bonsReceptionLocal;
    final l = attachedDatabase.lignesBonReceptionLocal;
    final lignes = await (select(l).join([
      innerJoin(b, b.id.equalsExp(l.bonId)),
    ])..where(b.commandeId.equals(commandeId))).get();
    final recues = <String, int>{};
    for (final r in lignes) {
      final ligne = r.readTable(l);
      recues[ligne.articleId] =
          (recues[ligne.articleId] ?? 0) + ligne.quantiteCentiemes;
    }
    return recues;
  }

  Future<CommandeAchatDetail?> commande(String id) async {
    final c = await (select(
      attachedDatabase.commandesAchatLocal,
    )..where((c) => c.id.equals(id))).getSingleOrNull();
    if (c == null) return null;

    final f = await (select(
      attachedDatabase.fournisseursLocal,
    )..where((f) => f.id.equals(c.fournisseurId))).getSingleOrNull();
    final lignes =
        await (select(attachedDatabase.lignesCommandeAchatLocal)
              ..where((l) => l.commandeId.equals(id))
              ..orderBy([(l) => OrderingTerm.asc(l.rang)]))
            .get();
    final recues = await _recuesParArticle(id);

    final total = lignes.fold<int>(
      0,
      (s, l) =>
          s +
          montantLigneCentimes(
            quantiteCentiemes: l.quantiteCentiemes,
            prixUnitaireCentimes: l.prixUnitaireCentimes,
          ),
    );

    return CommandeAchatDetail(
      commande: _commande(
        c,
        raisonSociale: f?.raisonSociale ?? '',
        nombreLignes: lignes.length,
        montantCentimes: total,
        regleCentimes: (await _reglesParCommande())[id] ?? 0,
      ),
      fournisseurContact: f?.contact,
      fournisseurConditionsPaiement: f?.conditionsPaiement,
      lignes: [
        for (final l in lignes)
          LigneCommande(
            id: l.id,
            articleId: l.articleId,
            articleLibelle: l.articleLibelle,
            uniteMesure: l.uniteMesure,
            quantiteCommandee: depuisCentiemes(l.quantiteCentiemes),
            prixUnitaire: depuisCentiemes(l.prixUnitaireCentimes),
            montant: depuisCentiemes(
              montantLigneCentimes(
                quantiteCentiemes: l.quantiteCentiemes,
                prixUnitaireCentimes: l.prixUnitaireCentimes,
              ),
            ),
            quantiteRecue: depuisCentiemes(recues[l.articleId] ?? 0),
            resteARecevoir: depuisCentiemes(
              resteARecevoirCentiemes(
                commandeeCentiemes: l.quantiteCentiemes,
                recueCentiemes: recues[l.articleId] ?? 0,
              ),
            ),
          ),
      ],
      receptions: (await receptions(commandeId: id, parPage: 1000)).elements,
      // Les quantités reçues sont LUES des lignes de bons, jamais reconstituées
      // des mouvements de stock (PA-39 ne vaut pas sur ce poste).
      recuReconstitue: false,
    );
  }

  /* ================================================================== */
  /* Commandes — écriture                                                */
  /* ================================================================== */

  /// Crée la commande et ses lignes dans la même transaction.
  ///
  /// Les lignes FIGENT le libellé et l'unité de l'article, relus d'ICI — jamais
  /// de la saisie : celle-ci ne les porte qu'à titre d'affichage.
  Future<CommandeAchatDetail> creerCommande(
    SaisieCommande saisie, {
    required String? auteurId,
  }) async {
    if (auteurId == null) {
      throw const RefusAchats(MessagesAchats.auteurInconnu);
    }
    if (!saisie.statut.saisissable) {
      throw const RefusAchats(
        'Ce statut ne se saisit pas à la création. Réceptionnée, '
        'réceptionnée partiellement et clôturée sont produits par une '
        "réception réelle, qui seule génère l'entrée de stock "
        'correspondante.',
        champ: 'statut',
      );
    }
    final date = DateTime.tryParse(saisie.dateCommande);
    if (date == null || _jour(date) != saisie.dateCommande) {
      throw const RefusAchats(
        MessagesAchats.dateIllisible,
        champ: 'date_commande',
      );
    }
    if (saisie.lignes.isEmpty) {
      throw const RefusAchats(
        MessagesAchats.lignesObligatoires,
        champ: 'lignes',
      );
    }
    final doublon = saisie.erreurArticlesEnDouble;
    if (doublon != null) throw RefusAchats(doublon, champ: 'lignes');

    return transaction(() async {
      final fournisseur = await (select(
        attachedDatabase.fournisseursLocal,
      )..where((f) => f.id.equals(saisie.fournisseurId))).getSingleOrNull();
      if (fournisseur == null) {
        throw const RefusAchats(
          MessagesAchats.fournisseurInexistant,
          champ: 'fournisseur_id',
        );
      }

      final lignes = <LignesCommandeAchatLocalCompanion>[];
      final id = _uuid.v4();
      var rang = 0;
      for (final l in saisie.lignes) {
        final quantite = enCentiemes(l.quantite);
        if (quantite == null || quantite <= 0) {
          throw RefusAchats(
            '${MessagesAchats.quantitePositive} (« ${l.libelle} »)',
            champ: 'lignes',
          );
        }
        final prix = enCentiemes(l.prixUnitaire);
        if (prix == null || prix <= 0) {
          throw RefusAchats(
            '${MessagesAchats.prixObligatoire} (« ${l.libelle} »)',
            champ: 'lignes',
          );
        }
        final article = await (select(
          attachedDatabase.articlesLocal,
        )..where((a) => a.id.equals(l.articleId))).getSingleOrNull();
        if (article == null) {
          throw const RefusAchats(
            MessagesAchats.articleInexistant,
            champ: 'lignes',
          );
        }
        // Un article en suivi journalier n'a pas de stock : la réception ne
        // pourrait jamais y générer d'entrée. Le refus est posé ICI, quand
        // l'acheteur peut encore le retirer, et non à la réception.
        if (SuiviArticle.depuisCode(article.suivi) == SuiviArticle.journalier) {
          throw RefusAchats(
            MessagesStock.refusJournalier(article.libelle),
            champ: 'lignes',
          );
        }
        lignes.add(
          LignesCommandeAchatLocalCompanion.insert(
            id: _uuid.v4(),
            commandeId: id,
            articleId: article.id,
            articleLibelle: article.libelle,
            uniteMesure: article.uniteMesure,
            quantiteCentiemes: quantite,
            prixUnitaireCentimes: prix,
            rang: rang++,
          ),
        );
      }

      await into(attachedDatabase.commandesAchatLocal).insert(
        CommandesAchatLocalCompanion.insert(
          id: id,
          fournisseurId: saisie.fournisseurId,
          dateCommande: saisie.dateCommande,
          statut: saisie.statut.code,
          creeLe: _maintenant(),
          utilisateurId: auteurId,
        ),
      );
      for (final l in lignes) {
        await into(attachedDatabase.lignesCommandeAchatLocal).insert(l);
      }

      // Lot F1 : la commande part au serveur (création seule : le serveur
      // n'accepte aucune modification d'une commande — `envoyerCommande` et
      // `cloturerCommande` restent locales, point ouvert).
      await _file.enfiler(
        table: TableSynchronisee.commandesAchat,
        entiteId: id,
        type: TypeOperationSync.creation,
        payload: chargeCommandeAchat(
          fournisseurId: saisie.fournisseurId,
          dateCommande: saisie.dateCommande,
          statut: saisie.statut.code,
          lignes: [
            for (final l in lignes)
              (
                articleId: l.articleId.value,
                articleLibelle: l.articleLibelle.value,
                uniteMesure: l.uniteMesure.value,
                quantiteCentiemes: l.quantiteCentiemes.value,
                prixUnitaireCentimes: l.prixUnitaireCentimes.value,
                rang: l.rang.value,
              ),
          ],
        ),
        dateMetier: saisie.dateCommande,
      );

      return (await commande(id))!;
    });
  }

  Future<CommandeAchatDetail> envoyerCommande(String id) async {
    return transaction(() async {
      final c = await (select(
        attachedDatabase.commandesAchatLocal,
      )..where((c) => c.id.equals(id))).getSingleOrNull();
      if (c == null) {
        throw const RefusAchats(MessagesAchats.commandeIntrouvable);
      }
      if (c.statut != StatutCommande.brouillon.code) {
        throw const RefusAchats(MessagesAchats.envoiImpossible);
      }
      await (update(
        attachedDatabase.commandesAchatLocal,
      )..where((c) => c.id.equals(id))).write(
        CommandesAchatLocalCompanion(
          statut: Value(StatutCommande.envoyee.code),
        ),
      );
      await _envoyerStatut(id, StatutCommande.envoyee.code);
      return (await commande(id))!;
    });
  }

  /// Lot F6 (17/10/2026) : le statut part au serveur, par son service
  /// (`envoyer`, `cloturer`), si le serveur détient la commande.
  Future<void> _envoyerStatut(String id, String statut) async {
    if (!await DocumentsAutresPostes(
      attachedDatabase,
    ).connuDuServeur(TableSynchronisee.commandesAchat, id)) {
      return;
    }
    await OperationsSyncDao(attachedDatabase).enfiler(
      table: TableSynchronisee.commandesAchat,
      entiteId: id,
      type: TypeOperationSync.modification,
      payload: chargeStatutCommande(statut),
    );
  }

  /// RG-10 : une commande ne se clôture que si elle est `receptionnee` —
  /// c'est-à-dire que sa réception a été jugée conforme à la tolérance.
  Future<CommandeAchatDetail> cloturerCommande(String id) async {
    return transaction(() async {
      final c = await (select(
        attachedDatabase.commandesAchatLocal,
      )..where((c) => c.id.equals(id))).getSingleOrNull();
      if (c == null) {
        throw const RefusAchats(MessagesAchats.commandeIntrouvable);
      }
      if (c.statut != StatutCommande.receptionnee.code) {
        throw const RefusAchats(MessagesAchats.clotureImpossible);
      }
      await (update(
        attachedDatabase.commandesAchatLocal,
      )..where((c) => c.id.equals(id))).write(
        CommandesAchatLocalCompanion(
          statut: Value(StatutCommande.cloturee.code),
        ),
      );
      await _envoyerStatut(id, StatutCommande.cloturee.code);
      return (await commande(id))!;
    });
  }

  /* ================================================================== */
  /* Réceptions                                                          */
  /* ================================================================== */

  Future<PageAchats<BonReception>> receptions({
    String? commandeId,
    int page = 1,
    int parPage = 200,
  }) async {
    final b = attachedDatabase.bonsReceptionLocal;
    final c = attachedDatabase.commandesAchatLocal;
    final f = attachedDatabase.fournisseursLocal;
    final p = attachedDatabase.pointsStockageLocal;

    final requete = select(b).join([
      innerJoin(c, c.id.equalsExp(b.commandeId)),
      innerJoin(f, f.id.equalsExp(c.fournisseurId)),
      innerJoin(p, p.id.equalsExp(b.pointStockageId)),
    ]);
    if (commandeId != null) requete.where(b.commandeId.equals(commandeId));
    requete.orderBy([
      OrderingTerm.desc(b.dateReception),
      OrderingTerm.desc(b.creeLe),
      OrderingTerm.asc(b.id),
    ]);
    final toutes = await requete.get();

    final articles = <String, int>{};
    for (final l in await select(
      attachedDatabase.lignesBonReceptionLocal,
    ).get()) {
      articles[l.bonId] = (articles[l.bonId] ?? 0) + 1;
    }

    return _page(
      [
        for (final r in toutes)
          BonReception(
            id: r.readTable(b).id,
            commandeId: r.readTable(b).commandeId,
            dateReception: r.readTable(b).dateReception,
            conformiteCode: r.readTable(b).conformite,
            fournisseurRaisonSociale: r.readTable(f).raisonSociale,
            // Les lignes sont stockées : l'aveu du serveur (PA-39) ne vaut pas.
            lignesNonStockees: false,
            pointLibelle: r.readTable(p).libelle,
            nombreArticles: articles[r.readTable(b).id] ?? 0,
          ),
      ],
      page,
      parPage,
    );
  }

  Future<String?> _toleranceBrute() async {
    final ligne = await (select(
      attachedDatabase.parametresSystemeLocal,
    )..where((p) => p.cle.equals(cleTolerance))).getSingleOrNull();
    return ligne?.valeur;
  }

  /// Enregistre une réception — EF-M7-03, RG-10.
  ///
  /// ## Une seule transaction, et ce qu'elle englobe
  ///
  /// Le contrôle de la commande, le verdict, le bon, ses lignes, **les
  /// entrées de stock** (par `StocksDao`, le seul auteur du stock) et le
  /// statut posé sur la commande. Un refus à n'importe quelle étape —
  /// tolérance absente, article en suivi journalier, point inconnu — n'écrit
  /// RIEN : jamais une marchandise entrée sans bon, ni un bon sans
  /// marchandise.
  ///
  /// ## AUCUNE valorisation, comme le serveur (D132, 12/10/2026)
  ///
  /// L'entrée de stock générée par la réception n'est PAS valorisée.
  /// `ReceptionService::receptionner` appelle `MouvementStockService::entree()`
  /// SANS coût unitaire, et `entree()` ne valorise que lorsqu'on lui en passe un
  /// (`integrerEntree` et `prix_achat`, derrière `if ($coutUnitaire !== null)`).
  /// C'est établi par EXÉCUTION (`tool/achats/rejouer_receptions.php`, comparé
  /// dans `reception_valorisation_contre_serveur_test.dart`) : après une
  /// réception, le coût moyen pondéré et le dernier prix d'achat de l'article
  /// sont exactement ceux d'avant. Jusqu'au 12/10/2026 ce poste valorisait au
  /// prix de la ligne de commande — l'intention écrite de
  /// `CreerCommandeAchatRequest`, que le service n'exécute pas : un second
  /// comportement que le serveur n'a pas.
  ///
  /// Conséquence (dite, jamais masquée) : un article qui n'entre en stock que par
  /// des réceptions n'a AUCUN coût connu — « — » en stock, « hors N article(s)
  /// sans coût » en M11 —, jamais zéro. Les entrées DÉJÀ écrites avec un coût
  /// (réceptions d'avant ce lot) le gardent : aucune réécriture rétroactive,
  /// le coût d'un mouvement passé est un fait enregistré.
  ///
  /// ⚠ Le verdict porte sur les quantités de CETTE réception, comme au serveur
  /// (voir `evaluerConformite`).
  Future<BonReception> enregistrerReception(
    SaisieReception saisie, {
    required String? auteurId,
  }) async {
    if (auteurId == null) {
      throw const RefusAchats(MessagesAchats.auteurInconnu);
    }

    final retenues = saisie.lignesRetenues;
    if (retenues.isEmpty) {
      throw const RefusAchats(MessagesAchats.receptionVide);
    }
    final vus = <String>{};
    for (final l in retenues) {
      if (!vus.add(l.articleId)) {
        throw const RefusAchats(MessagesAchats.articleEnDoubleReception);
      }
    }
    final recues = <String, int>{};
    for (final l in retenues) {
      final q = enCentiemes(l.quantiteRecue);
      if (q == null || q <= 0) {
        throw const RefusAchats(MessagesAchats.quantiteRecuePositive);
      }
      recues[l.articleId] = q;
    }

    final bonId = _uuid.v4();
    try {
      return await transaction(() async {
        final c = await (select(
          attachedDatabase.commandesAchatLocal,
        )..where((c) => c.id.equals(saisie.commandeId))).getSingleOrNull();
        if (c == null) {
          throw const RefusAchats(MessagesAchats.commandeIntrouvable);
        }
        // Un statut inconnu n'est pas réceptionnable : on ne devine pas.
        if (!receptionnable(StatutCommande.depuisCode(c.statut))) {
          throw const RefusAchats(MessagesAchats.commandeCloturee);
        }

        final point = await (select(
          attachedDatabase.pointsStockageLocal,
        )..where((p) => p.id.equals(saisie.pointStockageId))).getSingleOrNull();
        if (point == null) {
          throw const RefusAchats(
            MessagesAchats.pointInexistant,
            champ: 'point_stockage_id',
          );
        }

        final tolerance = lireTolerance(await _toleranceBrute());
        if (tolerance.illisible) {
          throw const RefusAchats(MessagesAchats.toleranceIllisible);
        }
        if (tolerance.centiemes == null) throw const ToleranceAbsente();

        final lignes = await (select(
          attachedDatabase.lignesCommandeAchatLocal,
        )..where((l) => l.commandeId.equals(c.id))).get();
        final commandees = {
          for (final l in lignes) l.articleId: l.quantiteCentiemes,
        };

        final conformite = evaluerConformite(
          commandees: commandees,
          recues: recues,
          toleranceCentiemes: tolerance.centiemes!,
        );

        final maintenant = _maintenant();
        await into(attachedDatabase.bonsReceptionLocal).insert(
          BonsReceptionLocalCompanion.insert(
            id: bonId,
            commandeId: c.id,
            dateReception: _jour(maintenant),
            conformite: conformite.code,
            pointStockageId: point.id,
            creeLe: maintenant,
            utilisateurId: auteurId,
          ),
        );

        for (final e in recues.entries) {
          await into(attachedDatabase.lignesBonReceptionLocal).insert(
            LignesBonReceptionLocalCompanion.insert(
              id: _uuid.v4(),
              bonId: bonId,
              articleId: e.key,
              quantiteCentiemes: e.value,
            ),
          );

          // L'entrée de stock générée par la réception — jamais saisie à la
          // main en plus. Dans CETTE transaction : le DAO du stock rejoint la
          // transaction en cours. SANS coût : voir « AUCUNE valorisation ».
          final issue = await _stocks.ajouterMouvement(
            articleId: e.key,
            pointId: point.id,
            type: TypeMouvement.entree,
            centiemes: e.value,
            motif: MessagesAchats.motifReception(commande: c.id, bon: bonId),
            auteurId: auteurId,
            // Lot 10f : le BON part, le serveur écrit ses entrées.
            envoyer: false,
          );
          if (issue is! MouvementPose) {
            // Une entrée ne peut pas être en rupture ; si le DAO du stock rend
            // autre chose, on refuse plutôt que d'écrire un bon sans stock.
            throw const RefusAchats(MessagesAchats.entreeNonEcrite);
          }
        }

        await (update(
          attachedDatabase.commandesAchatLocal,
        )..where((x) => x.id.equals(c.id))).write(
          CommandesAchatLocalCompanion(
            statut: Value(statutApresReception(conformite).code),
          ),
        );

        // Lot F1 : le bon part au serveur, qui recalcule son verdict et
        // SIGNALE l'écart avec celui du poste. Le nouveau statut de la
        // commande ne part pas : le serveur le dérive de SA réception.
        await _file.enfiler(
          table: TableSynchronisee.bonsReception,
          entiteId: bonId,
          type: TypeOperationSync.creation,
          payload: chargeBonReception(
            commandeId: c.id,
            dateReception: _jour(maintenant),
            pointStockageId: point.id,
            conformite: conformite.code,
            lignes: [
              for (final e in recues.entries)
                (articleId: e.key, quantiteCentiemes: e.value),
            ],
          ),
          horodatage: maintenant,
          dateMetier: _jour(maintenant),
        );

        return (await receptions(
          commandeId: c.id,
          parPage: 1000,
        )).elements.firstWhere((b) => b.id == bonId);
      });
    } on RefusStock catch (e) {
      // Le DAO du stock refuse (article en suivi journalier, point…) : la
      // transaction est défaite, et le refus remonte avec SA phrase.
      throw RefusAchats(e.motif, champ: e.champ);
    }
  }

  /* ================================================================== */
  /* Rapprochement                                                       */
  /* ================================================================== */

  /// Le contrôle commande / réception — deux voies sur trois. La troisième, la
  /// facture fournisseur, n'a aucune table : le résultat le DIT
  /// ([Rapprochement.factureVerifiable] vaut toujours `false`).
  Future<Rapprochement?> rapprocher(String commandeId) async {
    final c = await (select(
      attachedDatabase.commandesAchatLocal,
    )..where((c) => c.id.equals(commandeId))).getSingleOrNull();
    if (c == null) return null;

    final lignes =
        await (select(attachedDatabase.lignesCommandeAchatLocal)
              ..where((l) => l.commandeId.equals(commandeId))
              ..orderBy([(l) => OrderingTerm.asc(l.rang)]))
            .get();
    final recues = await _recuesParArticle(commandeId);

    var toutConcordant = true;
    final resultat = <LigneRapprochement>[];
    for (final l in lignes) {
      final recue = recues[l.articleId] ?? 0;
      final concordance = concordanceLigne(
        recueCentiemes: recue,
        commandeeCentiemes: l.quantiteCentiemes,
      );
      if (concordance != 'conforme') toutConcordant = false;
      resultat.add(
        LigneRapprochement(
          articleId: l.articleId,
          libelle: l.articleLibelle,
          commandee: depuisCentiemes(l.quantiteCentiemes),
          recue: depuisCentiemes(recue),
          ecart: depuisCentiemes(recue - l.quantiteCentiemes),
          concordance: concordance,
        ),
      );
    }

    return Rapprochement(
      commandeId: commandeId,
      concordanceGlobale: toutConcordant ? 'conforme' : 'ecart_constate',
      factureVerifiable: false,
      voiesVerifiees: const ['commande', 'reception'],
      // La phrase du serveur sur la facture absente est vraie ici aussi. Celle
      // sur la « reconstitution depuis les mouvements de stock » est FAUSSE sur
      // ce poste (les lignes de bons sont stockées) : elle n'est pas reprise.
      avertissements: const [MessagesAchats.factureAbsente],
      lignes: resultat,
    );
  }
}
