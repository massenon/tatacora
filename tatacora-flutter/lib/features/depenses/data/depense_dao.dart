import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../comptabilite/data/comptabilite_dao.dart';
import '../../comptabilite/data/moteur_comptable.dart';
import '../../comptabilite/domain/entities/comptabilite.dart';
import '../../comptabilite/domain/refus_comptable.dart';
import '../../synchronisation/data/operations_sync_dao.dart';
import '../../synchronisation/domain/charges_synchronisation.dart';
import '../../synchronisation/domain/operation_sync.dart';
import '../domain/categories_depense.dart';
import '../domain/entities/depense.dart';
import '../domain/recu_depense.dart';
import '../domain/repositories/depenses_repository.dart';
import 'piece_de_la_depense.dart';
import 'recus_depenses_locaux.dart';

/// Accès Drift aux dépenses courantes (M10) — **local pur**.
///
/// ## Aucun mixin généré, et c'est délibéré
///
/// Ce DAO passe par `attachedDatabase.<table>` plutôt que par un
/// `@DriftAccessor` et son `part`. Même forme que `CatalogueServicesDao`. La
/// raison est pratique : les deux tables de M10 sont enregistrées par la
/// session principale, et un `part` de plus imposerait une seconde génération
/// pour rien. Aucun mixin vide ne peut donc apparaître ici — le piège nommé en
/// tête de `panier_dao.dart`, où un import manquant produit un mixin vide
/// **sans erreur de génération**.
///
/// ## Le DAO ne parle qu'entités
///
/// Aucune méthode ne rend un `DepensesLocalData`. La forme des tables ne
/// franchit pas cette frontière : sans quoi renommer une colonne casserait un
/// widget.
///
/// ## Rien ne part en file de synchronisation
///
/// `depenses` n'est à aucun registre synchronisable — celui du serveur ne
/// connaît que `reservations` et `clients`. Une entrée de file serait rejetée à
/// chaque tentative, et l'écran afficherait « en attente de synchronisation »
/// sur quelque chose qui ne partira jamais (PA-59/60/61). L'écran dit
/// « enregistré sur ce poste ».
///
/// ## La dépense et sa pièce comptable : UNE transaction (règle du 31/08/2026)
///
/// `enregistrer` passe la pièce par le moteur comptable local
/// (`MoteurComptable.passerEtValider`) PUIS écrit la dépense et ses lignes, le
/// tout dans une seule transaction Drift — le moteur ouvre la sienne dedans, qui
/// devient un point de sauvegarde. Un refus de pièce (exercice absent, centre de
/// coût manquant, compte inconnu, journal inconnu…) lève avant la moindre
/// écriture de dépense ; une panne à l'écriture de la dépense annule la pièce ET
/// le compteur de séquence. C'est le déroulement de `DepenseService::enregistrer`
/// du serveur (la pièce d'abord), répliqué.
///
/// `comptabiliser` est le rattrapage EXPLICITE d'une dépense antérieure à la
/// v16 (`DepenseService::comptabiliser`) : jamais automatique, jamais en
/// silence.
///
/// ## Le moteur arrive par un résolveur, pas par une instance
///
/// `moteurComptableProvider` attend l'installation du référentiel : une instance
/// construite trop tôt servirait un plan vide. Le résolveur est appelé à chaque
/// écriture, après l'installation. Sans résolveur, écrire une dépense LÈVE
/// (`StateError`) — jamais d'écriture sans pièce par omission.
///
/// ## Le REÇU en image (lot L4, 27/10/2026, schéma v42)
///
/// Les six colonnes `recu_*` de `depenses_local` ont UN seul écrivain, ce DAO
/// (avec le miroir du serveur, `aligneur_documents.dart`, pour la référence d'un
/// reçu descendu) : `enregistrer(recu:)` range le fichier (hors de la base,
/// [RecusDepensesLocaux]) puis écrit sa référence DANS la transaction de la
/// dépense, en `en_attente` ; l'envoi consigne ensuite l'accusé
/// ([accuserRecu]) ou le refus du serveur ([refuserRecu]). **`envoye` n'est
/// écrit que par l'accusé** (ou par la référence que le serveur redescend avec
/// la MÊME empreinte) : jamais sur la foi d'un envoi tenté.
class DepenseDao extends DatabaseAccessor<AppDatabase>
    implements DepensesRepository {
  DepenseDao(
    super.db, {
    Uuid? uuid,
    DateTime Function()? maintenant,
    this.moteur,
    this.recus,
  }) : _uuid = uuid ?? const Uuid(),
       _maintenant = maintenant ?? DateTime.now;

  /// Le rangement des reçus ; sans lui, joindre un reçu LÈVE (`StateError`) —
  /// un fichier n'est jamais abandonné en silence.
  final RecusDepensesLocaux? recus;

  final Uuid _uuid;

  /// Injectable : un test qui dépend de l'heure réelle échoue un jour sur
  /// mille — celui où l'on ne le regarde pas.
  final DateTime Function() _maintenant;

  /// Le résolveur du moteur comptable (voir l'en-tête de la classe).
  final Future<MoteurComptable> Function()? moteur;

  Future<MoteurComptable> _moteurObligatoire() {
    final resolveur = moteur;
    if (resolveur == null) {
      throw StateError(
        'DepenseDao sans moteur comptable : une dépense ne s’enregistre '
        'jamais sans sa pièce.',
      );
    }
    return resolveur();
  }

  /* ================================================================== */
  /* Lecture                                                             */
  /* ================================================================== */

  @override
  Future<List<Depense>> depenses() async {
    final entetes =
        await (select(attachedDatabase.depensesLocal)..orderBy([
              (d) => OrderingTerm.desc(d.dateTransaction),
              // Deux dépenses du même jour sont départagées par l'horodatage
              // de saisie, puis par l'identifiant : sans ces deux termes,
              // l'ordre serait indéfini et la liste changerait à chaque
              // rafraîchissement sans qu'aucune donnée n'ait bougé.
              (d) => OrderingTerm.desc(d.saisieLe),
              (d) => OrderingTerm.desc(d.id),
            ]))
            .get();

    // UNE requête pour toutes les lignes, groupée en mémoire. Une requête par
    // dépense ferait un N+1 sur l'écran qui affiche justement la ventilation
    // de chacune — c'est la raison du `with('lignes')` côté serveur.
    final lignes =
        await (select(attachedDatabase.lignesDepenseLocal)..orderBy([
              (l) => OrderingTerm.asc(l.ajouteeLe),
              (l) => OrderingTerm.asc(l.id),
            ]))
            .get();

    final parDepense = <String, List<LigneDepense>>{};
    for (final ligne in lignes) {
      parDepense.putIfAbsent(ligne.depenseId, () => []).add(_versLigne(ligne));
    }

    // Les numéros de pièce, LUS des écritures en une requête : jamais recopiés
    // sur la dépense.
    final numeros = await ComptabiliteDao(
      attachedDatabase,
    ).numerosDePiece(entetes.map((e) => e.ecritureId).whereType<String>());

    final origines = await _origines(entetes.map((e) => e.id));
    return entetes
        .map(
          (e) =>
              _versDepense(e, parDepense[e.id] ?? const [], numeros, origines),
        )
        .toList(growable: false);
  }

  Future<Depense?> parId(String id) async {
    final entete = await (select(
      attachedDatabase.depensesLocal,
    )..where((d) => d.id.equals(id))).getSingleOrNull();
    if (entete == null) return null;

    final lignes =
        await (select(attachedDatabase.lignesDepenseLocal)
              ..where((l) => l.depenseId.equals(id))
              ..orderBy([
                (l) => OrderingTerm.asc(l.ajouteeLe),
                (l) => OrderingTerm.asc(l.id),
              ]))
            .get();

    final idPiece = entete.ecritureId;
    final numeros = await ComptabiliteDao(
      attachedDatabase,
    ).numerosDePiece([?idPiece]);

    return _versDepense(
      entete,
      lignes.map(_versLigne).toList(growable: false),
      numeros,
      await _origines([id]),
    );
  }

  /// Les dépenses DESCENDUES d'un autre poste parmi [ids] (lot F4), avec
  /// leur poste d'origine (`null` : saisie au serveur).
  Future<Map<String, String?>> _origines(Iterable<String> ids) async {
    final liste = ids.toList(growable: false);
    if (liste.isEmpty) return const {};
    final o = attachedDatabase.originesDocumentsLocal;
    final lignes =
        await (select(o)..where(
              (x) => x.tableServeur.equals('depenses') & x.entiteId.isIn(liste),
            ))
            .get();
    return {for (final l in lignes) l.entiteId: l.posteOrigine};
  }

  /* ================================================================== */
  /* Écriture                                                            */
  /* ================================================================== */

  /// Enregistre la dépense, ses lignes ET sa pièce comptable, dans **une
  /// seule** transaction.
  ///
  /// Toute la validation de FORME a lieu AVANT d'ouvrir la transaction : un
  /// refus ne doit rien laisser derrière lui, et le message doit nommer la
  /// ligne fautive — une dépense à six lignes dont une est vide doit dire
  /// laquelle, sans quoi l'opérateur relit les six. Les refus COMPTABLES
  /// (exercice, centre, journal, compte imputable) tombent du moteur, avec la
  /// phrase du serveur, avant que la dépense soit écrite.
  @override
  Future<Depense> enregistrer({
    required DateTime dateTransaction,
    required TresorerieDepense tresorerie,
    required String libelle,
    required List<SaisieLigneDepense> lignes,
    required String auteurId,
    String? centreId,
    RecuAJoindre? recu,
  }) async {
    final libelleNet = libelle.trim();
    await _validerLaSaisie(libelleNet, lignes);
    if (recu != null) {
      // La MÊME règle que l'écran de saisie, rejugée ici : le DAO ne range pas
      // ce que le web refuserait.
      final issue = verifierRecu(recu.octets);
      if (issue is RecuRefuse) throw RefusDepense(issue.phrase);
    }

    final moteur = await _moteurObligatoire();
    final id = _uuid.v4();
    final maintenant = _maintenant();

    // Le fichier d'abord, hors de la base ; retiré si la dépense n'est pas
    // écrite (pièce refusée, panne) — jamais un reçu orphelin.
    RecuRange? range;
    if (recu != null) {
      final magasin = recus;
      if (magasin == null) {
        throw StateError(
          'DepenseDao sans rangement des reçus : un reçu n’est jamais '
          'abandonné en silence.',
        );
      }
      range = await magasin.ranger(id, recu.type, recu.octets);
    }

    try {
      await _ecrireLaDepense(
        id: id,
        maintenant: maintenant,
        moteur: moteur,
        dateTransaction: dateTransaction,
        tresorerie: tresorerie,
        libelleNet: libelleNet,
        lignes: lignes,
        auteurId: auteurId,
        centreId: centreId,
        recu: range == null ? null : (range: range, type: recu!.type),
      );
    } on Object {
      if (range != null) await recus?.retirer(range.nom);
      rethrow;
    }

    // Relu plutôt que composé de mémoire : c'est la base qui fait foi, et le
    // montant décaissé se somme des lignes réellement écrites.
    return (await parId(id))!;
  }

  Future<void> _ecrireLaDepense({
    required String id,
    required DateTime maintenant,
    required MoteurComptable moteur,
    required DateTime dateTransaction,
    required TresorerieDepense tresorerie,
    required String libelleNet,
    required List<SaisieLigneDepense> lignes,
    required String auteurId,
    required String? centreId,
    required ({RecuRange range, TypeRecu type})? recu,
  }) async {
    await transaction(() async {
      // La pièce D'ABORD, comme le serveur : si elle est refusée, la dépense
      // n'est jamais écrite et l'opérateur reçoit la raison comptable.
      final piece = await moteur.passerEtValider(
        pieceDeLaDepense(
          tresorerie: tresorerie,
          dateIso: formaterDateIso(dateTransaction),
          libelleDepense: libelleNet,
          lignes: [
            for (final l in lignes)
              (libelle: l.libelle, compte: l.compteCharge, montant: l.montant),
          ],
          centreId: centreId,
        ),
        auteurId: auteurId,
      );

      await into(attachedDatabase.depensesLocal).insert(
        DepensesLocalCompanion.insert(
          id: id,
          dateTransaction: dateTransaction,
          tresorerie: tresorerie.code,
          libelle: libelleNet,
          saisieLe: Value(maintenant),
          ecritureId: Value(_ligneDeTresorerie(piece)),
          // Le reçu (v42) : sa RÉFÉRENCE, en attente d'accusé du serveur.
          recuNom: Value(recu?.range.nom),
          recuSha256: Value(recu?.range.sha256),
          recuTaille: Value(recu?.range.taille),
          recuType: Value(recu?.type.mime),
          recuStatut: Value(recu == null ? null : StatutRecu.enAttente.code),
        ),
      );

      await _insererLignes(id, lignes, maintenant);

      // Lot F1 : la dépense part au serveur (document SOURCE — la pièce
      // ci-dessus ne part jamais, D246 : le serveur passe la sienne). Le
      // centre est relu sur la PIÈCE passée, seule à le porter
      // (`depenses_local` n'a pas de colonne centre).
      final centre = await _centreDeLaPiece(piece);
      final ecrites =
          await (select(attachedDatabase.lignesDepenseLocal)
                ..where((l) => l.depenseId.equals(id))
                ..orderBy([
                  (l) => OrderingTerm.asc(l.ajouteeLe),
                  (l) => OrderingTerm.asc(l.rowId),
                ]))
              .get();
      await OperationsSyncDao(attachedDatabase).enfiler(
        table: TableSynchronisee.depenses,
        entiteId: id,
        type: TypeOperationSync.creation,
        payload: chargeDepense(
          dateTransaction: dateTransaction,
          tresorerie: tresorerie.code,
          libelle: libelleNet,
          centreId: centre?.id,
          centreLibelle: centre?.libelle,
          lignes: [
            for (final l in ecrites)
              (
                libelle: l.libelle,
                compteCharge: l.compteCharge,
                nature: l.nature,
                famille: l.famille,
                montant: l.montant,
              ),
          ],
        ),
        horodatage: maintenant,
        dateMetier: jourIso(dateTransaction),
      );
    });
  }

  /// Rattrapage : passe la pièce d'une dépense qui n'en a pas
  /// (`DepenseService::comptabiliser`).
  ///
  /// Sert les dépenses saisies AVANT la v16, quand aucune pièce n'était
  /// produite. Une dépense déjà comptabilisée est rendue telle quelle — la
  /// repasser créerait une seconde pièce pour le même argent.
  ///
  /// ## Le centre de coût est OBLIGATOIRE (10/10/2026)
  ///
  /// Le serveur a corrigé son rattrapage : `comptabiliser(Depense, string
  /// $centreId)` reçoit un centre EXPLICITE, passé aux lignes de charge ET à la
  /// ligne de trésorerie, exactement comme `enregistrer`. Aucun compte de charge
  /// du plan du PO ne porte de centre par défaut, et la dépense n'en mémorise
  /// pas : sans centre, le moteur refuse avec la phrase de RG-12
  /// (`depenses.centre_absent`), jamais un centre « par défaut » global qui
  /// fausserait la comptabilité analytique sans qu'aucun total ne bouge. Un
  /// centre vide est lu comme absent ; si le COMPTE en porte un, il joue — c'est
  /// le moteur qui décide, comme au serveur.
  ///
  /// En cas de refus, la raison est PERSISTÉE sur la dépense — hors transaction,
  /// pour survivre à l'annulation — puis relancée : l'écran voit l'erreur, et la
  /// liste garde la trace de ce qui bloque. Seuls les refus à phrase
  /// ([RefusComptable], [RefusDepense]) sont consignés : une panne de disque
  /// n'est jamais rangée en infobulle.
  @override
  Future<Depense> comptabiliser(
    String depenseId, {
    required String auteurId,
    required String centreId,
  }) async {
    final depense = await parId(depenseId);
    if (depense == null) throw const RefusDepense.introuvable();
    if (depense.estComptabilisee) return depense;
    // Lot F4 : la pièce d'une dépense descendue est au SERVEUR (Q1) — la
    // passer ici doublerait la charge et la sortie de trésorerie.
    if (depense.recueDuServeur) throw const RefusDepense.recueDuServeur();

    final tresorerie = depense.tresorerie;
    if (tresorerie == null) {
      // Une trésorerie hors registre : on ne devine pas le compte à créditer.
      const refus = RefusDepense.tresorerieInconnue();
      await _consignerRefus(depenseId, refus.message);
      throw refus;
    }
    if (depense.lignes.isEmpty) {
      const refus = RefusDepense.sansLigne();
      await _consignerRefus(depenseId, refus.message);
      throw refus;
    }

    final moteur = await _moteurObligatoire();
    try {
      await transaction(() async {
        final piece = await moteur.passerEtValider(
          pieceDeLaDepense(
            tresorerie: tresorerie,
            dateIso: formaterDateIso(depense.dateTransaction),
            libelleDepense: depense.libelle,
            lignes: [
              for (final l in depense.lignes)
                (
                  libelle: l.libelle,
                  compte: l.compteCharge,
                  montant: l.montant,
                ),
            ],
            centreId: centreId,
          ),
          auteurId: auteurId,
        );
        await (update(
          attachedDatabase.depensesLocal,
        )..where((d) => d.id.equals(depenseId))).write(
          DepensesLocalCompanion(
            ecritureId: Value(_ligneDeTresorerie(piece)),
            ecritureRefus: const Value(null),
          ),
        );
      });
    } on RefusComptable catch (refus) {
      await _consignerRefus(depenseId, refus.message);
      rethrow;
    } on RefusDepense catch (refus) {
      await _consignerRefus(depenseId, refus.message);
      rethrow;
    }

    return (await parId(depenseId))!;
  }

  /// Écrit une dépense **SANS pièce comptable** — l'unique chemin d'écriture
  /// d'argent qui n'en produit pas, et il existe pour UNE raison : le jeu de
  /// démonstration (`mode_demo.dart`), qui n'a aucun utilisateur donc aucun
  /// auteur à nommer sur une pièce (RG-15), et qui doit pouvoir montrer l'état
  /// « sans pièce comptable » et le geste de rattrapage.
  ///
  /// Ne jamais l'appeler depuis un écran : un balayage de `lib/` exige que
  /// `mode_demo.dart` soit son seul appelant. Les dépenses qu'il écrit sont
  /// exactement celles qu'une base antérieure à la v16 porte.
  Future<Depense> enregistrerHistoriqueSansPiece({
    required DateTime dateTransaction,
    required TresorerieDepense tresorerie,
    required String libelle,
    required List<SaisieLigneDepense> lignes,
  }) async {
    final libelleNet = libelle.trim();
    await _validerLaSaisie(libelleNet, lignes);

    final id = _uuid.v4();
    final maintenant = _maintenant();
    await transaction(() async {
      await into(attachedDatabase.depensesLocal).insert(
        DepensesLocalCompanion.insert(
          id: id,
          dateTransaction: dateTransaction,
          tresorerie: tresorerie.code,
          libelle: libelleNet,
          saisieLe: Value(maintenant),
        ),
      );
      await _insererLignes(id, lignes, maintenant);
    });
    return (await parId(id))!;
  }

  /* ================================================================== */
  /* Le reçu en image : l'état se dit de ce que le serveur a accusé      */
  /* ================================================================== */

  /// Les reçus à envoyer : `en_attente`, du plus ancien au plus récent
  /// (identifiant, fichier, empreinte, type).
  Future<List<RecuAEnvoyer>> recusEnAttente({int limite = 25}) async {
    final lignes =
        await (select(attachedDatabase.depensesLocal)
              ..where((d) => d.recuStatut.equals(StatutRecu.enAttente.code))
              ..orderBy([
                (d) => OrderingTerm.asc(d.saisieLe),
                (d) => OrderingTerm.asc(d.id),
              ])
              ..limit(limite))
            .get();
    return [
      for (final d in lignes)
        RecuAEnvoyer(
          depenseId: d.id,
          nom: d.recuNom,
          sha256: d.recuSha256,
          type: d.recuType,
        ),
    ];
  }

  /// L'ACCUSÉ du serveur : le reçu est `envoye`. Seul chemin vers cet état
  /// avec [retenirReferenceRecu] (le serveur redit la même empreinte).
  Future<void> accuserRecu(String depenseId) =>
      (update(attachedDatabase.depensesLocal)..where(
            (d) =>
                d.id.equals(depenseId) &
                d.recuStatut.equals(StatutRecu.enAttente.code),
          ))
          .write(
            DepensesLocalCompanion(
              recuStatut: Value(StatutRecu.envoye.code),
              recuCause: const Value(null),
            ),
          );

  /// Le serveur a REFUSÉ le reçu : l'état est `refuse`, la cause est dite.
  Future<void> refuserRecu(String depenseId, String cause) =>
      (update(attachedDatabase.depensesLocal)..where(
            (d) =>
                d.id.equals(depenseId) &
                d.recuStatut.equals(StatutRecu.enAttente.code),
          ))
          .write(
            DepensesLocalCompanion(
              recuStatut: Value(StatutRecu.refuse.code),
              recuCause: Value(cause),
            ),
          );

  /// La RÉFÉRENCE du reçu que le serveur détient (descente, lot L4). Rend vrai
  /// si la ligne a changé.
  ///
  ///  * dépense sans reçu : le reçu est `du_serveur`, sans fichier — il se
  ///    télécharge à la demande ;
  ///  * reçu `en_attente` de CE poste : la MÊME empreinte vaut accusé (le
  ///    serveur détient exactement ce fichier : `envoye`) ; une AUTRE empreinte
  ///    le fait `refuse` (le serveur garde le sien, un reçu ne se remplace pas) ;
  ///  * reçu `du_serveur` : la référence se met à jour, et un fichier déjà
  ///    téléchargé mais d'une autre empreinte est oublié ;
  ///  * `envoye` et `refuse` : intouchés, ce sont des faits.
  Future<bool> retenirReferenceRecu(
    String depenseId, {
    required String? sha256,
    required int? taille,
    required String? type,
  }) async {
    final d = await (select(
      attachedDatabase.depensesLocal,
    )..where((x) => x.id.equals(depenseId))).getSingleOrNull();
    if (d == null) return false;
    final statut = StatutRecu.depuisCode(d.recuStatut);
    final cible = update(attachedDatabase.depensesLocal)
      ..where((x) => x.id.equals(depenseId));

    switch (statut) {
      case null:
        await cible.write(
          DepensesLocalCompanion(
            recuStatut: Value(StatutRecu.duServeur.code),
            recuSha256: Value(sha256),
            recuTaille: Value(taille),
            recuType: Value(type),
          ),
        );
        return true;
      case StatutRecu.enAttente:
        if (sha256 != null && sha256 == d.recuSha256) {
          await cible.write(
            DepensesLocalCompanion(
              recuStatut: Value(StatutRecu.envoye.code),
              recuCause: const Value(null),
            ),
          );
        } else {
          await cible.write(
            DepensesLocalCompanion(
              recuStatut: Value(StatutRecu.refuse.code),
              recuCause: const Value(TextesRecuPoste.autreRecuAuServeur),
            ),
          );
        }
        return true;
      case StatutRecu.duServeur:
        if (sha256 == d.recuSha256 &&
            taille == d.recuTaille &&
            type == d.recuType) {
          return false;
        }
        final memeFichier = sha256 != null && sha256 == d.recuSha256;
        await cible.write(
          DepensesLocalCompanion(
            recuSha256: Value(sha256),
            recuTaille: Value(taille),
            recuType: Value(type),
            recuNom: memeFichier ? const Value.absent() : const Value(null),
          ),
        );
        if (!memeFichier) await recus?.retirer(d.recuNom);
        return true;
      case StatutRecu.envoye || StatutRecu.refuse:
        return false;
    }
  }

  /// Le fichier d'un reçu `du_serveur` vient d'être TÉLÉCHARGÉ et vérifié :
  /// il est rangé, et la ligne sait où. L'empreinte, la taille et le type
  /// observés complètent une référence qui ne les portait pas (reçu joint par
  /// le web avant les empreintes).
  Future<void> retenirFichierTelecharge(
    String depenseId, {
    required RecuRange range,
    required TypeRecu type,
  }) =>
      (update(attachedDatabase.depensesLocal)..where(
            (d) =>
                d.id.equals(depenseId) &
                d.recuStatut.equals(StatutRecu.duServeur.code),
          ))
          .write(
            DepensesLocalCompanion(
              recuNom: Value(range.nom),
              recuSha256: Value(range.sha256),
              recuTaille: Value(range.taille),
              recuType: Value(type.mime),
            ),
          );

  /* ================================================================== */
  /* Interne                                                             */
  /* ================================================================== */

  /// La validation de FORME — la même pour toute écriture. Le compte est
  /// confronté au PLAN installé, jamais accepté sur sa forme : un numéro
  /// plausible et absent du plan produirait une imputation qui ne correspond à
  /// rien (`lignes.*.compte_charge: exists:plan_comptable` du serveur).
  Future<void> _validerLaSaisie(
    String libelleNet,
    List<SaisieLigneDepense> lignes,
  ) async {
    if (libelleNet.isEmpty) throw const RefusDepense.libelleManquant();
    if (lignes.isEmpty) throw const RefusDepense.sansLigne();

    final plan = ComptabiliteDao(attachedDatabase);
    for (var i = 0; i < lignes.length; i++) {
      final ligne = lignes[i];
      final rang = i + 1;

      if (ligne.libelle.trim().isEmpty) throw RefusDepense.libelleLigne(rang);
      if (ligne.compteCharge.trim().isEmpty) {
        throw RefusDepense.compteLigne(rang);
      }
      if (await plan.compteParNumero(ligne.compteCharge) == null) {
        throw RefusDepense.compteInconnu(rang);
      }
      // Une ligne à zéro n'est jamais enregistrée : elle affirmerait un achat
      // sans argent. Le refus nomme les deux issues — retirer la ligne, ou
      // saisir son montant.
      if (ligne.montant <= 0) throw RefusDepense.montantNul(rang);
    }
  }

  Future<void> _insererLignes(
    String depenseId,
    List<SaisieLigneDepense> lignes,
    DateTime maintenant,
  ) async {
    for (final ligne in lignes) {
      await into(attachedDatabase.lignesDepenseLocal).insert(
        LignesDepenseLocalCompanion.insert(
          id: _uuid.v4(),
          depenseId: depenseId,
          libelle: ligne.libelle.trim(),
          compteCharge: ligne.compteCharge,
          // Nature et famille sont FIGÉES ici, recopiées du registre.
          // Déplacer demain une nature d'une famille à l'autre ne doit pas
          // réécrire les dépenses déjà saisies, ni les deux indicateurs qui
          // les somment.
          nature: ligne.nature.libelle,
          famille: ligne.nature.famille.libelle,
          montant: ligne.montant,
          ajouteeLe: Value(maintenant),
        ),
      );
    }
  }

  /// Le centre de coût de la pièce passée — celui de sa ligne de TRÉSORERIE
  /// (la seule au crédit), que le moteur a pu prendre du compte quand la
  /// saisie n'en nommait pas. `null` : la pièce n'en porte aucun.
  Future<CentreDeCout?> _centreDeLaPiece(List<EcritureComptable> piece) async {
    String? centreId;
    for (final ligne in piece) {
      if (ligne.creditCentimes > 0) centreId = ligne.centreId;
    }
    if (centreId == null) return null;
    return ComptabiliteDao(attachedDatabase).centreParId(centreId);
  }

  /// L'identifiant de la ligne de trésorerie de la pièce : la seule au CRÉDIT.
  ///
  /// Reconnue à son SENS (dans une dépense, les charges sont au débit et la
  /// trésorerie seule au crédit), comme `DepenseService::ligneDeTresorerie` —
  /// non à sa position, qui n'est pas une garantie.
  String _ligneDeTresorerie(List<EcritureComptable> piece) {
    for (final ligne in piece) {
      if (ligne.creditCentimes > 0) return ligne.id;
    }
    // Inatteignable tant que `pieceDeLaDepense` ajoute la contrepartie : si ce
    // refus tombe un jour, c'est que la pièce a changé de forme, et le dire
    // vaut mieux que de rattacher la dépense à une ligne de charge.
    throw StateError('La pièce ne porte aucune contrepartie de trésorerie.');
  }

  Future<void> _consignerRefus(String depenseId, String raison) =>
      (update(attachedDatabase.depensesLocal)
            ..where((d) => d.id.equals(depenseId)))
          .write(DepensesLocalCompanion(ecritureRefus: Value(raison)));

  /* ================================================================== */
  /* Correspondances                                                     */
  /* ================================================================== */

  Depense _versDepense(
    DepensesLocalData d,
    List<LigneDepense> lignes,
    Map<String, String> numeros,
    Map<String, String?> origines,
  ) => Depense(
    id: d.id,
    dateTransaction: d.dateTransaction,
    // `null` sur un code inconnu, jamais un repli sur « Caisse » : ranger
    // au hasard une dépense dans les espèces fausserait un indicateur.
    tresorerie: TresorerieDepense.depuisCode(d.tresorerie),
    libelle: d.libelle,
    lignes: lignes,
    saisieLe: d.saisieLe,
    ecritureId: d.ecritureId,
    numeroPiece: d.ecritureId == null ? null : numeros[d.ecritureId],
    ecritureRefus: d.ecritureRefus,
    recueDuServeur: origines.containsKey(d.id),
    posteOrigine: origines[d.id],
    recu: _versRecu(d),
  );

  /// Le reçu tel que la ligne le dit, ou `null` : `recu_statut` est SEUL juge
  /// de sa présence (un statut inconnu d'une version future n'invente pas un
  /// reçu).
  static RecuDepense? _versRecu(DepensesLocalData d) {
    final statut = StatutRecu.depuisCode(d.recuStatut);
    if (statut == null) return null;
    return RecuDepense(
      statut: statut,
      nom: d.recuNom,
      sha256: d.recuSha256,
      taille: d.recuTaille,
      type: d.recuType,
      cause: d.recuCause,
    );
  }

  LigneDepense _versLigne(LignesDepenseLocalData l) => LigneDepense(
    id: l.id,
    libelle: l.libelle,
    compteCharge: l.compteCharge,
    nature: l.nature,
    famille: l.famille,
    montant: l.montant,
  );
}

/// Un reçu à envoyer au serveur : ce que l'envoi lit de la ligne.
final class RecuAEnvoyer {
  const RecuAEnvoyer({
    required this.depenseId,
    required this.nom,
    required this.sha256,
    required this.type,
  });

  final String depenseId;

  /// Le fichier rangé sur ce poste.
  final String? nom;
  final String? sha256;
  final String? type;
}
