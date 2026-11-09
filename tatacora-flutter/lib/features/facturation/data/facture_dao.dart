import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
// Les classes de tables doivent être dans la portée du fichier : `@DriftAccessor`
// les résout par leur type, et un import de `app_database.dart` seul ne les
// réexporte pas. Sans ces lignes, le mixin généré est VIDE — sans erreur de
// génération, ce qui rend le diagnostic trompeur (leçon `reservation_dao.dart`).
import '../../../core/database/tables/registre_facturation_tables.dart';
import '../domain/client_mecef.dart';
import '../domain/entities/piece_facturation.dart';
import '../domain/ifu_client.dart';
import '../domain/repositories/facture_repository.dart';
import '../domain/statut_normalisation.dart';
import '../../synchronisation/data/operations_sync_dao.dart';
import '../../synchronisation/domain/charges_synchronisation.dart';
import '../../synchronisation/domain/operation_sync.dart';

part 'facture_dao.g.dart';

/// Accès Drift au registre de facturation — **un seul registre, trois
/// origines**.
///
/// ## Le DAO ne parle qu'entités
///
/// Aucune méthode ne rend un `PiecesFacturationLocalData`. La forme des tables
/// ne franchit pas cette frontière : sans quoi renommer une colonne casserait
/// un widget, et la couche présentation saurait qu'une base existe.
///
/// ## La facture part au serveur (lot F5c, 17/10/2026)
///
/// Décision du PO (Q2) : le poste émet une facture PROVISOIRE
/// (`PROV-AAAA-NNNNN`), le serveur attribue le numéro continu
/// (`F-AAAA-NNNNN`), la synchronisation le pose ici
/// ([regulariserNumeros]). L'émission et l'annulation s'enfilent dans LEUR
/// transaction. Une pièce émise avant (ou en démonstration) reste
/// `non_transmissible` : elle ne part pas, son annulation non plus.
///
/// ## Aucune méthode de suppression, jamais
///
/// La correction passe par [annuler], qui **conserve** la pièce et émet un
/// avoir. Ajouter un `supprimer()` ici suffirait à défaire la propriété n°4 du
/// moteur sans que rien d'autre ne change d'apparence.
@DriftAccessor(
  tables: [
    PiecesFacturationLocal,
    LignesPieceFacturationLocal,
    SequencesFactureLocal,
  ],
)
class FactureDao extends DatabaseAccessor<AppDatabase> with _$FactureDaoMixin {
  FactureDao(super.db, {Uuid? uuid, DateTime Function()? maintenant})
    : _uuid = uuid ?? const Uuid(),
      _maintenant = maintenant ?? DateTime.now;

  final Uuid _uuid;

  /// Injectable : l'année du numéro de pièce en dépend, et un test qui repose
  /// sur l'horloge réelle change de résultat le 1er janvier.
  final DateTime Function() _maintenant;

  /* ================================================================== */
  /* Numérotation — propriété n°3                                        */
  /* ================================================================== */

  /// Le numéro suivant de la séquence — `F-2026-00042`.
  ///
  /// **Le compteur est persisté séparément de la liste** (table
  /// `sequences_facture_local`). Le déduire du nombre de pièces réattribuerait
  /// un numéro déjà utilisé dès qu'une pièce serait archivée ou purgée, et un
  /// numéro de pièce ne se réemploie jamais, même si la pièce disparaît.
  ///
  /// La lecture et l'incrément sont dans **une seule transaction** — le patron
  /// de `PanierDao.ouvrir`, lui-même transposé de
  /// `VerificationChevauchementService` (RG-01). Les séparer ouvrirait une
  /// fenêtre où deux émissions simultanées obtiendraient le même numéro, ce qui
  /// est exactement ce que la contrainte `UNIQUE` de la colonne refuserait —
  /// donc une émission perdue au comptoir.
  Future<String> numeroSuivant() =>
      transaction(() => _numeroSuivantDansTransaction());

  Future<String> _numeroSuivantDansTransaction() async {
    final annee = _maintenant().year;

    final courant = await (select(
      sequencesFactureLocal,
    )..where((s) => s.annee.equals(annee))).getSingleOrNull();

    final suivant = (courant?.dernierNumero ?? 0) + 1;

    await into(sequencesFactureLocal).insertOnConflictUpdate(
      SequencesFactureLocalCompanion.insert(
        annee: Value(annee),
        dernierNumero: suivant,
      ),
    );

    // Lot F5c : sous synchronisation, le numéro du poste est PROVISOIRE ; le
    // continu vient du serveur. En démonstration (rien ne part), l'ancien.
    final prefixe = attachedDatabase.fileSynchronisationActive
        ? prefixeNumeroProvisoire
        : 'F-';
    return '$prefixe$annee-${suivant.toString().padLeft(5, '0')}';
  }

  /* ================================================================== */
  /* Lecture                                                             */
  /* ================================================================== */

  Future<List<PieceFacturation>> pieces({
    OrigineFacture? origine,
    StatutPiece? statut,
    ModuleFacturable? module,
  }) async {
    final requete = select(piecesFacturationLocal);
    if (origine != null) {
      requete.where((p) => p.origine.equals(origine.code));
    }
    if (statut != null) {
      requete.where((p) => p.statut.equals(statut.code));
    }
    // Départage par numéro après l'horodatage : deux pièces émises dans la même
    // milliseconde auraient sinon un ordre indéfini, et la liste changerait
    // d'ordre à chaque rafraîchissement sans qu'aucune donnée n'ait bougé.
    requete.orderBy([
      (p) => OrderingTerm.desc(p.dateEmission),
      (p) => OrderingTerm.desc(p.numero),
    ]);

    final entetes = await requete.get();
    final toutes = await Future.wait(entetes.map(_avecLignes));

    if (module == null) return toutes;
    // Le filtre par activité porte sur les LIGNES : une facture mêlant bar et
    // restaurant apparaît sous les deux, ce qui est le point de la règle 4.
    return toutes
        .where((p) => p.lignes.any((l) => l.module == module))
        .toList(growable: false);
  }

  Future<PieceFacturation?> parId(String id) async {
    final entete = await (select(
      piecesFacturationLocal,
    )..where((p) => p.id.equals(id))).getSingleOrNull();
    if (entete == null) return null;
    return _avecLignes(entete);
  }

  Future<PieceFacturation?> parNumero(String numero) async {
    final entete = await (select(
      piecesFacturationLocal,
    )..where((p) => p.numero.equals(numero))).getSingleOrNull();
    if (entete == null) return null;
    return _avecLignes(entete);
  }

  /// Les avoirs qui neutralisent la facture de numéro [numero].
  ///
  /// C'est le terme « avoirs émis » du reste dû (`Facture::SQL_AVOIRS_EMIS`) :
  /// le serveur les somme sans regarder leur statut, et ce poste fait de même.
  Future<List<PieceFacturation>> avoirsDe(String numero) async {
    final entetes = await (select(
      piecesFacturationLocal,
    )..where((p) => p.avoirDe.equals(numero))).get();
    return Future.wait(entetes.map(_avecLignes));
  }

  /// ⚠ **Le piège de ce module.** Les avoirs sont exclus.
  ///
  /// Un avoir porte le **même** `reservationId` et le statut `emise`. Sans
  /// `avoirDe IS NULL`, annuler une facture ferait proposer l'avoir au
  /// téléchargement : un document à **montant négatif**, remis au client à la
  /// place de sa facture.
  ///
  /// Le prototype a déjà rencontré et corrigé ce défaut ; la condition est
  /// portée telle quelle, et un test la fige.
  Future<PieceFacturation?> facturePourReservation(String reservationId) async {
    final entete = await (select(
      piecesFacturationLocal,
    )..where((p) => p.reservationId.equals(reservationId) & _vivante(p))).get();
    if (entete.isEmpty) return null;
    return _avecLignes(entete.first);
  }

  /// Le prédicat « pièce vivante » — **émise et non avoir**, à un seul endroit.
  ///
  /// Les trois lectures qui cherchent « la facture de … » doivent poser
  /// exactement la même condition. Recopiée trois fois, c'est la troisième
  /// copie qui divergerait — celle que personne ne relit — et elle proposerait
  /// au client un avoir à montant négatif à la place de sa facture.
  Expression<bool> _vivante($PiecesFacturationLocalTable p) =>
      p.statut.equals(StatutPiece.emise.code) & p.avoirDe.isNull();

  /// La facture émise d'un panier — **avoirs exclus**, garde d'idempotence.
  ///
  /// Sans elle, un second appui sur « Clôturer et facturer » produirait une
  /// seconde pièce numérotée pour la même vente : un montant de plus au
  /// registre que personne n'a encaissé, et qu'il faudrait ensuite défaire par
  /// un avoir.
  Future<PieceFacturation?> facturePourPanier(String panierId) async {
    final entetes = await (select(
      piecesFacturationLocal,
    )..where((p) => p.panierId.equals(panierId) & _vivante(p))).get();
    if (entetes.isEmpty) return null;
    return _avecLignes(entetes.first);
  }

  /// Le numéro de facture de chaque panier facturé — **avoirs exclus**.
  ///
  /// Une seule requête pour tout un journal : [facturePourPanier] appelée par
  /// vente ferait autant d'allers-retours que de lignes, et lirait en plus les
  /// lignes de chaque pièce, dont l'écran n'a que faire pour afficher un
  /// numéro.
  ///
  /// Le prédicat est celui de [facturePourPanier] — [_vivante] — et pas une
  /// seconde version : sans quoi le journal annoncerait un numéro d'avoir là
  /// où le panier proposerait une facture.
  Future<Map<String, String>> numerosFactureParPanier() async {
    final entetes = await (select(
      piecesFacturationLocal,
    )..where((p) => p.panierId.isNotNull() & _vivante(p))).get();
    return {for (final e in entetes) e.panierId!: e.numero};
  }

  /* ================================================================== */
  /* Émission                                                            */
  /* ================================================================== */

  /// Émet une pièce — les lignes du brouillon sont **copiées**.
  ///
  /// Le nom, le prix unitaire et le module sont figés à l'émission. Si la carte
  /// change demain, cette pièce ne bouge pas.
  Future<PieceFacturation> emettre(BrouillonFacture brouillon) async {
    if (brouillon.lignes.isEmpty) throw const FactureSansLigne();
    // L'IFU du client : facultatif, 13 chiffres s'il est rempli — la règle du serveur.
    if (!IfuClient.valide(brouillon.acheteurIfu)) {
      throw const IfuClientInvalide();
    }
    final acheteurIfu = IfuClient.nettoyer(brouillon.acheteurIfu);
    final acheteurNom = (brouillon.acheteurNom ?? '').trim().isEmpty
        ? null
        : brouillon.acheteurNom!.trim();

    final id = _uuid.v4();

    await transaction(() async {
      final numero = await _numeroSuivantDansTransaction();

      await into(piecesFacturationLocal).insert(
        PiecesFacturationLocalCompanion.insert(
          id: id,
          numero: numero,
          origine: brouillon.origine.code,
          dateEmission: _maintenant(),
          clientNom: brouillon.clientNom,
          clientId: Value(brouillon.clientId),
          reservationId: Value(brouillon.reservationId),
          panierId: Value(brouillon.panierId),
          modePaiement: Value(brouillon.modePaiement),
          pointVente: Value(brouillon.pointVente),
          acheteurIfu: Value(acheteurIfu),
          acheteurNom: Value(acheteurNom),
          statut: Value(StatutPiece.emise.code),
          // Identité FISCALE : nulle à l'émission, toujours. La certification
          // n'a pas lieu (PA-17 / PA-61).
          numeroMecef: const Value(null),
          statutTransmission: Value(
            attachedDatabase.fileSynchronisationActive
                ? StatutTransmissionPiece.enAttente.code
                : StatutTransmissionPiece.nonTransmissible.code,
          ),
        ),
      );

      await _copierLignes([
        for (var i = 0; i < brouillon.lignes.length; i++)
          _versLigneCompanion(id, brouillon.lignes[i], i),
      ]);

      await OperationsSyncDao(attachedDatabase).enfiler(
        table: TableSynchronisee.factures,
        entiteId: id,
        type: TypeOperationSync.creation,
        payload: chargeFacture(
          origine: brouillon.origine.code,
          dateEmission: _maintenant(),
          clientId: brouillon.clientId,
          reservationId: brouillon.reservationId,
          panierId: brouillon.panierId,
          lignes: [
            for (final l in brouillon.lignes)
              (
                module: l.module.code,
                libelle: l.libelle,
                prixUnitaire: l.prixUnitaire,
                quantite: l.quantite,
              ),
          ],
          acheteurIfu: acheteurIfu,
          acheteurNom: acheteurNom,
          retenirIfu: brouillon.retenirIfu,
        ),
      );
    });

    return (await parId(id))!;
  }

  /* ================================================================== */
  /* Annulation — par AVOIR, jamais par effacement                       */
  /* ================================================================== */

  /// Annule une facture en émettant un avoir.
  ///
  /// Même règle que RG-11 sur les écritures comptables : la pièce d'origine est
  /// **conservée**, un avoir de sens inverse la neutralise. Effacer une facture
  /// ferait un trou dans la séquence de numéros, et un trou dans une séquence
  /// est indistinguable d'une pièce dissimulée.
  ///
  /// L'avoir porte **son propre numéro**, pris à la même séquence : c'est une
  /// pièce à part entière, pas une annotation de la première.
  Future<AnnulationParAvoir> annuler(
    String pieceId,
    String motif, {
    String? auteurId,
  }) async {
    final motifNet = motif.trim();
    if (motifNet.isEmpty) throw const MotifAnnulationRequis();
    // 09/11/2026 (décision du PO) : plus de règle « facture d'un autre poste » ici ni au
    // serveur ; qui peut annuler est jugé par l'ÉCRAN (droit ANNULATIONS + M2 en écriture de
    // l'utilisateur connecté). Ce geste exécute, et garde la cohérence : une facture NORMALISÉE
    // est figée et se corrige par avoir, un avoir total déjà émis refuse, déjà annulée = refusée.

    final idAvoir = _uuid.v4();

    await transaction(() async {
      final entete = await (select(
        piecesFacturationLocal,
      )..where((p) => p.id.equals(pieceId))).getSingleOrNull();
      if (entete == null) throw PieceIntrouvable(pieceId);

      if (entete.avoirDe != null) throw AvoirNonAnnulable(entete.numero);
      if (StatutPiece.depuisCode(entete.statut) == StatutPiece.annulee) {
        throw FactureDejaAnnulee(entete.numero);
      }
      // Un avoir sur une facture NORMALISÉE se fait EN LIGNE (décision du PO du 07/11/2026,
      // point 4) : RIEN n'est écrit ici — ni avoir, ni statut, ni file.
      _exigerNonNormalisee(entete);

      final maintenant = _maintenant();

      await (update(
        piecesFacturationLocal,
      )..where((p) => p.id.equals(pieceId))).write(
        PiecesFacturationLocalCompanion(
          statut: Value(StatutPiece.annulee.code),
          motifAnnulation: Value(motifNet),
          dateAnnulation: Value(maintenant),
        ),
      );

      final lignes = await _lignesDe(pieceId);
      final numeroAvoir = await _numeroSuivantDansTransaction();

      await into(piecesFacturationLocal).insert(
        PiecesFacturationLocalCompanion.insert(
          id: idAvoir,
          numero: numeroAvoir,
          origine: entete.origine,
          dateEmission: maintenant,
          clientNom: entete.clientNom,
          clientId: Value(entete.clientId),
          reservationId: Value(entete.reservationId),
          panierId: Value(entete.panierId),
          modePaiement: Value(entete.modePaiement),
          pointVente: Value(entete.pointVente),
          // L'avoir est une pièce ÉMISE : elle vit, elle s'exporte, elle
          // s'archive. C'est la facture d'origine qui devient `annulee`.
          statut: Value(StatutPiece.emise.code),
          numeroMecef: const Value(null),
          avoirDe: Value(entete.numero),
          motifAvoir: Value(motifNet),
          statutTransmission: Value(
            entete.statutTransmission ==
                    StatutTransmissionPiece.nonTransmissible.code
                ? StatutTransmissionPiece.nonTransmissible.code
                : StatutTransmissionPiece.enAttente.code,
          ),
        ),
      );

      // Lot F5c : l'annulation part si la facture est connue du serveur
      // (envoyée, ou descendue) — le serveur émet l'avoir et rend son numéro.
      if (entete.statutTransmission !=
          StatutTransmissionPiece.nonTransmissible.code) {
        await OperationsSyncDao(attachedDatabase).enfiler(
          table: TableSynchronisee.factures,
          entiteId: pieceId,
          type: TypeOperationSync.modification,
          payload: chargeAnnulationFacture(motif: motifNet),
        );
      }

      await _copierLignes([
        for (final l in lignes)
          LignesPieceFacturationLocalCompanion.insert(
            id: _uuid.v4(),
            pieceId: idAvoir,
            moduleSource: l.moduleSource,
            codeArticle: Value(l.codeArticle),
            libelle: l.libelle,
            prixUnitaire: l.prixUnitaire,
            // Sens inverse par la QUANTITÉ, pour que l'invariant
            // `montant = prix × quantité` tienne sur toutes les lignes du
            // registre (voir `LigneFacture`).
            quantite: -l.quantite,
            ordre: l.ordre,
          ),
      ]);
    });

    return AnnulationParAvoir(
      facture: (await parId(pieceId))!,
      avoir: (await parId(idAvoir))!,
    );
  }

  /// Émet un avoir PARTIEL sur la facture [pieceId] — l'« Émettre un avoir » de
  /// la PWA (`emettreAvoir($facture, $montant, $motif)`).
  ///
  /// ## La règle est celle du SERVICE, pas une règle du poste
  ///
  /// Un avoir ne dépasse jamais le TTC de sa facture ([AvoirExcessif]) ; il peut
  /// s'ajouter à d'autres, le service ne les cumule pas — le reste dû
  /// (`creances.dart`, UNE formule : TTC − avoirs − paiements − acomptes) le
  /// montrera négatif si on le pousse trop loin, et c'est visible. Le montant
  /// entier du TTC est une ANNULATION : [annuler] (la facture devient
  /// `annulee`) ; ce geste-ci ne l'est pas.
  ///
  /// ## Ce qu'il écrit
  ///
  /// Une pièce-avoir à elle, de son propre numéro, d'UNE ligne « Avoir partiel
  /// — motif » (quantité −1, prix = montant) : la forme que prend un avoir
  /// partiel descendu du serveur ([inscrireAvoirDescendu]). La facture d'origine
  /// n'est PAS touchée (RG-03). L'avoir part au serveur sous SON identifiant
  /// (`avoir_id`) : il y naît sous le même UUID, son rejeu ne le double pas, et
  /// la descente le reconnaît.
  Future<PieceFacturation> emettreAvoirPartiel(
    String pieceId,
    int montant,
    String motif,
  ) async {
    final motifNet = motif.trim();
    if (motifNet.isEmpty) throw const MotifAnnulationRequis();
    final idAvoir = _uuid.v4();

    await transaction(() async {
      final entete = await (select(
        piecesFacturationLocal,
      )..where((p) => p.id.equals(pieceId))).getSingleOrNull();
      if (entete == null) throw PieceIntrouvable(pieceId);
      if (entete.avoirDe != null) throw AvoirNonAnnulable(entete.numero);
      if (StatutPiece.depuisCode(entete.statut) == StatutPiece.annulee) {
        throw FactureDejaAnnulee(entete.numero);
      }
      _exigerNonNormalisee(entete);

      final lignes = await _lignesDe(pieceId);
      final ttc = lignes.fold<int>(
        0,
        (t, l) => t + l.prixUnitaire * l.quantite,
      );
      if (montant <= 0) throw const AvoirMontantNul();
      if (montant > ttc) throw const AvoirExcessif();

      final numeroAvoir = await _numeroSuivantDansTransaction();
      await into(piecesFacturationLocal).insert(
        PiecesFacturationLocalCompanion.insert(
          id: idAvoir,
          numero: numeroAvoir,
          origine: entete.origine,
          dateEmission: _maintenant(),
          clientNom: entete.clientNom,
          clientId: Value(entete.clientId),
          reservationId: Value(entete.reservationId),
          panierId: Value(entete.panierId),
          modePaiement: Value(entete.modePaiement),
          pointVente: Value(entete.pointVente),
          statut: Value(StatutPiece.emise.code),
          numeroMecef: const Value(null),
          avoirDe: Value(entete.numero),
          motifAvoir: Value(motifNet),
          statutTransmission: Value(
            entete.statutTransmission ==
                    StatutTransmissionPiece.nonTransmissible.code
                ? StatutTransmissionPiece.nonTransmissible.code
                : StatutTransmissionPiece.enAttente.code,
          ),
        ),
      );
      await _copierLignes([
        LignesPieceFacturationLocalCompanion.insert(
          id: _uuid.v4(),
          pieceId: idAvoir,
          moduleSource: lignes.isEmpty
              ? ModuleFacturable.m1Hebergement.code
              : lignes.first.moduleSource,
          libelle: 'Avoir partiel — $motifNet',
          prixUnitaire: montant,
          quantite: -1,
          ordre: 0,
        ),
      ]);

      // Une pièce d'avant la synchronisation (non transmissible) ne part pas :
      // le serveur répondrait « facture inconnue » à chaque tentative.
      if (entete.statutTransmission !=
          StatutTransmissionPiece.nonTransmissible.code) {
        await OperationsSyncDao(attachedDatabase).enfiler(
          table: TableSynchronisee.factures,
          entiteId: pieceId,
          type: TypeOperationSync.modification,
          payload: chargeAvoirPartielFacture(
            montantFrancs: montant,
            motif: motifNet,
            avoirId: idAvoir,
          ),
        );
      }
    });

    return (await parId(idAvoir))!;
  }

  /* ================================================================== */
  /* Normalisation fiscale — boîtier CC300 (07/11/2026, schéma v50)       */
  /* ================================================================== */

  /// Une facture NORMALISÉE n'a d'avoir qu'EN LIGNE (décision du PO du 07/11/2026) : l'avoir
  /// naît au serveur, sous l'identifiant du serveur, puis descend ici (`inscrireAvoirDescendu`).
  /// Lever AVANT toute écriture : rien de local n'est jamais écrit hors ligne.
  void _exigerNonNormalisee(PiecesFacturationLocalData facture) {
    if (facture.normalisationStatut == StatutNormalisation.normalisee.code) {
      throw const AvoirEnLigneRequis();
    }
  }

  /// Note, AVANT l'envoi d'une requête de facturation, le compteur du boîtier
  /// lu à l'instant : si l'application s'arrête brutalement, le rejeu sait qu'une
  /// tentative est partie et compare le compteur avant de reposter. Une pièce
  /// déjà normalisée n'est jamais touchée.
  Future<void> noterTentativeNormalisation(
    String pieceId, {
    required String compteurAvant,
    required VoieNormalisation voie,
  }) async {
    final entete = await _enteteOuLeve(pieceId);
    if (entete.normalisationStatut == StatutNormalisation.normalisee.code) {
      throw FactureDejaNormalisee(entete.numero);
    }
    await (update(
      piecesFacturationLocal,
    )..where((p) => p.id.equals(pieceId))).write(
      PiecesFacturationLocalCompanion(
        normalisationStatut: Value(StatutNormalisation.enAttente.code),
        normalisationMode: Value(voie.code),
        normalisationCompteurAvant: Value(compteurAvant),
      ),
    );
  }

  /// Range l'issue d'une normalisation sur la pièce, et la met en file vers le
  /// serveur (qui la RANGE, sans re-certifier). **Une pièce déjà normalisée est
  /// figée** : elle n'est jamais écrasée ([FactureDejaNormalisee]).
  ///
  /// Le compteur noté avant l'envoi est retiré quand l'issue est CERTAINE
  /// (normalisée, refusée, échec avant envoi) et conservé quand elle ne l'est pas
  /// (à vérifier, ou en attente après une requête partie sans réponse).
  Future<PieceFacturation> enregistrerIssueNormalisation(
    String pieceId,
    IssueCertification issue, {
    required VoieNormalisation voie,
  }) => transaction(() async {
    final entete = await _enteteOuLeve(pieceId);
    if (entete.normalisationStatut == StatutNormalisation.normalisee.code) {
      throw FactureDejaNormalisee(entete.numero);
    }
    final maintenant = _maintenant();

    final PiecesFacturationLocalCompanion champs;
    String statut;
    String? motif;
    String? numeroMecef;
    String? qr;
    String? code;
    String? compteur;
    DateTime? date;
    switch (issue) {
      case Certifiee(:final resultat):
        statut = StatutNormalisation.normalisee.code;
        numeroMecef = resultat.numeroMecef;
        qr = resultat.qrCode;
        code = resultat.codeMecef;
        compteur = '${resultat.compteur}';
        date = resultat.dateCertification;
        champs = PiecesFacturationLocalCompanion(
          normalisationStatut: Value(statut),
          normalisationMotif: const Value(null),
          normalisationMode: Value(voie.code),
          normalisationCompteur: Value(compteur),
          normalisationCompteurAvant: const Value(null),
          numeroMecef: Value(numeroMecef),
          qrCodeFiscal: Value(qr),
          codeMecef: Value(code),
          normaliseeLe: Value(date),
        );
      case EnAttente(motif: final m, :final incertaine, :final compteurAvant):
        statut = StatutNormalisation.enAttente.code;
        motif = m;
        champs = PiecesFacturationLocalCompanion(
          normalisationStatut: Value(statut),
          normalisationMotif: Value(motif),
          normalisationMode: Value(voie.code),
          // Une requête partie sans réponse : le compteur noté RESTE.
          normalisationCompteurAvant: incertaine
              ? Value(compteurAvant ?? entete.normalisationCompteurAvant)
              : const Value(null),
        );
      case Refusee(motif: final m):
        statut = StatutNormalisation.refusee.code;
        motif = m;
        champs = PiecesFacturationLocalCompanion(
          normalisationStatut: Value(statut),
          normalisationMotif: Value(motif),
          normalisationMode: Value(voie.code),
          normalisationCompteurAvant: const Value(null),
        );
      case AVerifier(
        motif: final m,
        :final compteurAvant,
        :final qrCode,
        :final codeMecef,
      ):
        statut = StatutNormalisation.aVerifier.code;
        motif = m;
        qr = qrCode;
        code = codeMecef;
        champs = PiecesFacturationLocalCompanion(
          normalisationStatut: Value(statut),
          normalisationMotif: Value(motif),
          normalisationMode: Value(voie.code),
          normalisationCompteurAvant: Value(
            compteurAvant ?? entete.normalisationCompteurAvant,
          ),
          // Le QR rendu par le boîtier est CONSERVÉ (la facture existe), sans
          // numéro fiscal tant que son compteur n'est pas confirmé : la pièce
          // n'est PAS « normalisée ».
          qrCodeFiscal: Value(qr),
          codeMecef: Value(code),
        );
    }

    await (update(
      piecesFacturationLocal,
    )..where((p) => p.id.equals(pieceId))).write(champs);

    // Vers le serveur : il range, il ne re-certifie jamais. Une pièce que le
    // serveur ne connaît pas (d'avant la synchronisation) ne part pas.
    if (entete.statutTransmission !=
        StatutTransmissionPiece.nonTransmissible.code) {
      final String? factureId;
      final String? avoirId;
      if (entete.avoirDe != null) {
        factureId = (await parNumero(entete.avoirDe!))?.id;
        avoirId = entete.id;
      } else {
        factureId = entete.id;
        avoirId = null;
      }
      if (factureId != null) {
        await OperationsSyncDao(attachedDatabase).enfiler(
          table: TableSynchronisee.factures,
          entiteId: factureId,
          type: TypeOperationSync.modification,
          payload: chargeNormalisationFacture(
            statut: statut,
            mode: voie.code,
            motif: motif,
            numeroMecef: numeroMecef,
            qrCode: qr,
            codeMecef: code,
            compteur: compteur,
            date: date ?? maintenant,
            avoirId: avoirId,
          ),
        );
      }
    }
    return (await parId(pieceId))!;
  });

  /// Une normalisation faite AILLEURS (un autre poste, ou e-MECeF au serveur),
  /// reçue par la descente : adoptée seulement si CE poste n'a pas déjà normalisé
  /// la pièce. Jamais renvoyée au serveur, jamais d'écrasement.
  Future<void> adopterNormalisationDescendue(
    String pieceId, {
    required StatutNormalisation statut,
    required VoieNormalisation? voie,
    String? motif,
    String? numeroMecef,
    String? qrCode,
    String? codeMecef,
    String? compteur,
    DateTime? date,
  }) async {
    final entete = await _enteteOuLeve(pieceId);
    if (entete.normalisationStatut == StatutNormalisation.normalisee.code) {
      return;
    }
    // Une pièce « à vérifier » ici ne se laisse pas écraser par un simple
    // « en attente » du serveur : seule une normalisation réelle l'emporte.
    if (statut != StatutNormalisation.normalisee &&
        entete.normalisationStatut != null) {
      return;
    }
    await (update(
      piecesFacturationLocal,
    )..where((p) => p.id.equals(pieceId))).write(
      PiecesFacturationLocalCompanion(
        normalisationStatut: Value(statut.code),
        normalisationMotif: Value(
          statut == StatutNormalisation.normalisee ? null : motif,
        ),
        normalisationMode: Value(voie?.code),
        normalisationCompteur: Value(compteur),
        normalisationCompteurAvant: const Value(null),
        numeroMecef: statut == StatutNormalisation.normalisee
            ? Value(numeroMecef)
            : const Value.absent(),
        qrCodeFiscal: statut == StatutNormalisation.normalisee
            ? Value(qrCode)
            : const Value.absent(),
        codeMecef: statut == StatutNormalisation.normalisee
            ? Value(codeMecef)
            : const Value.absent(),
        normaliseeLe: statut == StatutNormalisation.normalisee
            ? Value(date)
            : const Value.absent(),
      ),
    );
  }

  /// Le RÉSULTAT d'une normalisation e-MECeF demandée AU SERVEUR depuis ce poste, rendu dans la
  /// réponse (07/11/2026). Écrit sur la pièce, JAMAIS renvoyé au serveur (il le détient déjà),
  /// jamais d'écrasement d'une pièce normalisée. Un « normalisée » sans numéro fiscal réel ET
  /// sans QR de la forme `F;NIM;code;IFU;date` n'est PAS écrit comme tel : la pièce reste en
  /// attente, avec la phrase qui le dit (un indicateur se dérive de ce qui est en place).
  Future<PieceFacturation> adopterResultatServeur(
    String pieceId, {
    required StatutNormalisation statut,
    String? motif,
    String? numeroMecef,
    String? qrCode,
    String? codeMecef,
    String? compteur,
    DateTime? date,
  }) => transaction(() async {
    final entete = await _enteteOuLeve(pieceId);
    if (entete.normalisationStatut == StatutNormalisation.normalisee.code) {
      return (await parId(pieceId))!;
    }
    var effectif = statut;
    var motifEffectif = motif;
    if (statut == StatutNormalisation.normalisee) {
      final qr = (qrCode ?? '').trim();
      final valide =
          RegExp(r'^[A-Za-z0-9]+-[0-9]+$').hasMatch(numeroMecef ?? '') &&
          qr.startsWith('F;') &&
          qr.split(';').length == 5;
      if (!valide) {
        effectif = StatutNormalisation.enAttente;
        motifEffectif =
            'Le serveur a répondu sans numéro fiscal ni QR valides : la '
            'facture n’est pas normalisée.';
      }
    }
    final normalisee = effectif == StatutNormalisation.normalisee;
    await (update(
      piecesFacturationLocal,
    )..where((p) => p.id.equals(pieceId))).write(
      PiecesFacturationLocalCompanion(
        normalisationStatut: Value(effectif.code),
        normalisationMotif: Value(normalisee ? null : motifEffectif),
        normalisationMode: Value(VoieNormalisation.emecef.code),
        normalisationCompteur: Value(normalisee ? compteur : null),
        normalisationCompteurAvant: const Value(null),
        numeroMecef: normalisee ? Value(numeroMecef) : const Value.absent(),
        qrCodeFiscal: normalisee ? Value(qrCode) : const Value.absent(),
        codeMecef: normalisee ? Value(codeMecef) : const Value.absent(),
        normaliseeLe: normalisee ? Value(date) : const Value.absent(),
      ),
    );
    return (await parId(pieceId))!;
  });

  Future<PiecesFacturationLocalData> _enteteOuLeve(String pieceId) async {
    final entete = await (select(
      piecesFacturationLocal,
    )..where((p) => p.id.equals(pieceId))).getSingleOrNull();
    if (entete == null) throw PieceIntrouvable(pieceId);
    return entete;
  }

  /* ================================================================== */
  /* Régularisation du numéro — lot F5c                                  */
  /* ================================================================== */

  /// Pose le numéro continu attribué par le serveur ([numero], `F-…`) sur la
  /// facture [pieceId], et celui de son avoir ([numeroAvoir], `AV-…`) sur
  /// l'avoir local qui la neutralise. Décision du PO du 17/10/2026 : « la
  /// synchronisation régularise, et les postes s'actualisent du numéro que
  /// le serveur a attribué ».
  ///
  /// Idempotent (un numéro déjà posé ne change rien). Les avoirs désignent
  /// leur facture par son NUMÉRO (clé étrangère réelle) : les deux sont
  /// réécrits dans la même transaction, contraintes différées. Une pièce
  /// ANCIENNE du poste (jamais transmise) qui porte déjà ce numéro le cède
  /// et devient `LOC-<son numéro>` ; une pièce transmise ou reçue qui le
  /// porte est une incohérence : la régularisation LÈVE, rien n'est écrit.
  Future<void> regulariserNumeros(
    String pieceId, {
    String? numero,
    String? numeroAvoir,
  }) => transaction(() async {
    await customStatement('PRAGMA defer_foreign_keys = ON');
    final entete = await (select(
      piecesFacturationLocal,
    )..where((p) => p.id.equals(pieceId))).getSingleOrNull();
    if (entete == null) return;

    var courant = entete.numero;
    if (numero != null && numero.isNotEmpty && numero != courant) {
      await _renumeroter(entete.id, courant, numero);
      courant = numero;
    }

    if (numeroAvoir != null && numeroAvoir.isNotEmpty) {
      final avoirs =
          await (select(piecesFacturationLocal)
                ..where((p) => p.avoirDe.equals(courant))
                ..orderBy([(p) => OrderingTerm.asc(p.dateEmission)]))
              .get();
      final avoir = avoirs.isEmpty ? null : avoirs.first;
      if (avoir != null && avoir.numero != numeroAvoir) {
        await _renumeroter(avoir.id, avoir.numero, numeroAvoir);
      }
      if (avoir != null) await _marquerTransmise(avoir.id);
    }

    await _marquerTransmise(entete.id);
  });

  /// Pose le numéro `AV-…` attribué par le serveur à l'avoir PARTIEL [avoirId]
  /// émis par ce poste (l'avoir y est né sous le même identifiant). Idempotent ;
  /// même règle que [regulariserNumeros] pour un numéro déjà porté (LÈVE
  /// `StateError`, rien n'est écrit).
  Future<void> regulariserAvoir(String avoirId, String numero) =>
      transaction(() async {
        await customStatement('PRAGMA defer_foreign_keys = ON');
        final avoir = await (select(
          piecesFacturationLocal,
        )..where((p) => p.id.equals(avoirId))).getSingleOrNull();
        if (avoir == null) return;
        if (numero.isNotEmpty && avoir.numero != numero) {
          await _renumeroter(avoir.id, avoir.numero, numero);
        }
        await _marquerTransmise(avoir.id);
      });

  /* ================================================================== */
  /* Pièces DESCENDUES du serveur — lot F5c                              */
  /* ================================================================== */

  /// Inscrit une facture reçue du serveur (un autre poste, ou la PWA), sous
  /// SON identifiant et SON numéro, lignes copiées. Aucune file, aucune
  /// pièce comptable (Q1 : le serveur a passé la sienne). Appelé par la
  /// seule descente (`AligneurCatalogue`).
  Future<void> inscrireDescendue({
    required String id,
    required String numero,
    required OrigineFacture origine,
    required DateTime dateEmission,
    required String clientNom,
    required String? clientId,
    required String? reservationId,
    required String? panierId,
    required List<LigneBrouillon> lignes,
    String? acheteurIfu,
    String? acheteurNom,
  }) => transaction(() async {
    await into(piecesFacturationLocal).insert(
      PiecesFacturationLocalCompanion.insert(
        id: id,
        numero: numero,
        origine: origine.code,
        dateEmission: dateEmission,
        clientNom: clientNom,
        clientId: Value(clientId),
        reservationId: Value(reservationId),
        panierId: Value(panierId),
        acheteurIfu: Value(IfuClient.nettoyer(acheteurIfu)),
        acheteurNom: Value(
          (acheteurNom ?? '').trim().isEmpty ? null : acheteurNom!.trim(),
        ),
        statut: Value(StatutPiece.emise.code),
        numeroMecef: const Value(null),
        statutTransmission: Value(StatutTransmissionPiece.recue.code),
      ),
    );
    await _copierLignes([
      for (var i = 0; i < lignes.length; i++)
        _versLigneCompanion(id, lignes[i], i),
    ]);
  });

  /// Inscrit un avoir reçu du serveur sur la facture [factureId]. Avoir du
  /// TTC entier : les lignes de la facture, en sens inverse, et la facture
  /// devient `annulee` (la règle de [annuler]). Avoir PARTIEL (saisi à la
  /// PWA) : une seule ligne du montant, la facture reste émise.
  Future<void> inscrireAvoirDescendu({
    required String id,
    required String factureId,
    required String numero,
    required String motif,
    required int montant,
    required DateTime dateEmission,
  }) => transaction(() async {
    final entete = await (select(
      piecesFacturationLocal,
    )..where((p) => p.id.equals(factureId))).getSingle();
    final lignes = await _lignesDe(factureId);
    final total = lignes.fold<int>(
      0,
      (t, l) => t + l.prixUnitaire * l.quantite,
    );
    final entier = montant == total;

    if (entier) {
      await (update(
        piecesFacturationLocal,
      )..where((p) => p.id.equals(factureId))).write(
        PiecesFacturationLocalCompanion(
          statut: Value(StatutPiece.annulee.code),
          motifAnnulation: Value(motif),
          dateAnnulation: Value(dateEmission),
        ),
      );
    }

    await into(piecesFacturationLocal).insert(
      PiecesFacturationLocalCompanion.insert(
        id: id,
        numero: numero,
        origine: entete.origine,
        dateEmission: dateEmission,
        clientNom: entete.clientNom,
        clientId: Value(entete.clientId),
        reservationId: Value(entete.reservationId),
        panierId: Value(entete.panierId),
        statut: Value(StatutPiece.emise.code),
        numeroMecef: const Value(null),
        avoirDe: Value(entete.numero),
        motifAvoir: Value(motif),
        statutTransmission: Value(StatutTransmissionPiece.recue.code),
      ),
    );

    await _copierLignes([
      if (entier)
        for (final l in lignes)
          LignesPieceFacturationLocalCompanion.insert(
            id: '$id:${l.ordre}',
            pieceId: id,
            moduleSource: l.moduleSource,
            codeArticle: Value(l.codeArticle),
            libelle: l.libelle,
            prixUnitaire: l.prixUnitaire,
            quantite: -l.quantite,
            ordre: l.ordre,
          )
      else
        LignesPieceFacturationLocalCompanion.insert(
          id: '$id:0',
          pieceId: id,
          moduleSource: lignes.isEmpty
              ? ModuleFacturable.m1Hebergement.code
              : lignes.first.moduleSource,
          libelle: 'Avoir partiel — $motif',
          prixUnitaire: montant,
          quantite: -1,
          ordre: 0,
        ),
    ]);
  });

  /// L'avoir LOCAL encore provisoire de la facture [factureId] — celui que
  /// ce poste a émis en l'ANNULANT, et dont le serveur rend le numéro.
  Future<String?> avoirProvisoireDe(String factureId) async {
    final facture = await (select(
      piecesFacturationLocal,
    )..where((p) => p.id.equals(factureId))).getSingleOrNull();
    // Seule une facture ANNULÉE par ce poste a un avoir « d'annulation » à
    // régulariser par la descente : un avoir PARTIEL provisoire, lui, se
    // reconnaît par son identifiant (`regulariserAvoir`).
    if (facture == null ||
        StatutPiece.depuisCode(facture.statut) != StatutPiece.annulee) {
      return null;
    }
    final avoirs =
        await (select(piecesFacturationLocal)..where(
              (p) =>
                  p.avoirDe.equals(facture.numero) &
                  p.numero.like('$prefixeNumeroProvisoire%'),
            ))
            .get();
    return avoirs.isEmpty ? null : avoirs.first.id;
  }

  /// La pièce est-elle connue (ou attendue) du serveur ? Un encaissement
  /// ou une annulation n'y part que si oui : sur une pièce ancienne, le
  /// serveur répondrait « facture inconnue » à chaque tentative.
  Future<bool> partAuServeur(String pieceId) async {
    final entete = await (select(
      piecesFacturationLocal,
    )..where((p) => p.id.equals(pieceId))).getSingleOrNull();
    return entete != null &&
        entete.statutTransmission !=
            StatutTransmissionPiece.nonTransmissible.code;
  }

  /// La pièce a-t-elle reçu son numéro du serveur ([regulariserNumeros]) ?
  Future<bool> regularisee(String pieceId) async {
    final entete = await (select(
      piecesFacturationLocal,
    )..where((p) => p.id.equals(pieceId))).getSingleOrNull();
    return entete?.statutTransmission == StatutTransmissionPiece.transmise.code;
  }

  Future<void> _marquerTransmise(String id) async {
    await (update(piecesFacturationLocal)..where(
          (p) =>
              p.id.equals(id) &
              p.statutTransmission.equals(
                StatutTransmissionPiece.enAttente.code,
              ),
        ))
        .write(
          PiecesFacturationLocalCompanion(
            statutTransmission: Value(StatutTransmissionPiece.transmise.code),
          ),
        );
  }

  /// Réécrit le numéro de la pièce [id] (et la référence de ses avoirs),
  /// après avoir LIBÉRÉ [nouveau] si une pièce ancienne le porte.
  Future<void> _renumeroter(String id, String ancien, String nouveau) async {
    final porteur = await (select(
      piecesFacturationLocal,
    )..where((p) => p.numero.equals(nouveau))).getSingleOrNull();
    if (porteur != null && porteur.id != id) {
      if (porteur.statutTransmission !=
          StatutTransmissionPiece.nonTransmissible.code) {
        throw StateError(
          'Le numéro « $nouveau » attribué par le serveur est déjà porté par '
          'la pièce ${porteur.id} : régularisation refusée.',
        );
      }
      await _renumeroter(
        porteur.id,
        porteur.numero,
        '$prefixeNumeroLocalAncien${porteur.numero}',
      );
    }
    await (update(piecesFacturationLocal)..where((p) => p.id.equals(id))).write(
      PiecesFacturationLocalCompanion(numero: Value(nouveau)),
    );
    await (update(piecesFacturationLocal)
          ..where((p) => p.avoirDe.equals(ancien)))
        .write(PiecesFacturationLocalCompanion(avoirDe: Value(nouveau)));
  }

  /* ================================================================== */
  /* Internes                                                            */
  /* ================================================================== */

  Future<void> _copierLignes(
    List<LignesPieceFacturationLocalCompanion> lignes,
  ) async {
    for (final l in lignes) {
      await into(lignesPieceFacturationLocal).insert(l);
    }
  }

  LignesPieceFacturationLocalCompanion _versLigneCompanion(
    String pieceId,
    LigneBrouillon ligne,
    int ordre,
  ) => LignesPieceFacturationLocalCompanion.insert(
    id: _uuid.v4(),
    pieceId: pieceId,
    moduleSource: ligne.module.code,
    codeArticle: Value(ligne.codeArticle),
    // COPIE, pas jointure : ce libellé et ce prix ne seront plus jamais relus
    // depuis un catalogue.
    libelle: ligne.libelle,
    prixUnitaire: ligne.prixUnitaire,
    quantite: ligne.quantite,
    ordre: ordre,
  );

  Future<List<LignesPieceFacturationLocalData>> _lignesDe(String pieceId) =>
      (select(lignesPieceFacturationLocal)
            ..where((l) => l.pieceId.equals(pieceId))
            ..orderBy([(l) => OrderingTerm.asc(l.ordre)]))
          .get();

  Future<PieceFacturation> _avecLignes(
    PiecesFacturationLocalData entete,
  ) async {
    final lignes = await _lignesDe(entete.id);

    return PieceFacturation(
      id: entete.id,
      numero: entete.numero,
      origine: OrigineFacture.depuisCode(entete.origine),
      dateEmission: entete.dateEmission,
      clientNom: entete.clientNom,
      statut: StatutPiece.depuisCode(entete.statut),
      lignes: lignes.map(_versLigne).toList(growable: false),
      clientId: entete.clientId,
      reservationId: entete.reservationId,
      panierId: entete.panierId,
      modePaiement: entete.modePaiement,
      pointVente: entete.pointVente,
      numeroMecef: entete.numeroMecef,
      avoirDe: entete.avoirDe,
      motifAvoir: entete.motifAvoir,
      motifAnnulation: entete.motifAnnulation,
      dateAnnulation: entete.dateAnnulation,
      normalisationStatut: StatutNormalisation.depuisCode(
        entete.normalisationStatut,
      ),
      normalisationMotif: entete.normalisationMotif,
      normalisationMode: VoieNormalisation.depuisCode(entete.normalisationMode),
      normalisationCompteur: entete.normalisationCompteur,
      normalisationCompteurAvant: entete.normalisationCompteurAvant,
      codeMecef: entete.codeMecef,
      qrCodeFiscal: entete.qrCodeFiscal,
      normaliseeLe: entete.normaliseeLe,
      acheteurIfu: entete.acheteurIfu,
      acheteurNom: entete.acheteurNom,
    );
  }

  LigneFacture _versLigne(LignesPieceFacturationLocalData d) => LigneFacture(
    id: d.id,
    module: ModuleFacturable.depuisCode(d.moduleSource),
    libelle: d.libelle,
    prixUnitaire: d.prixUnitaire,
    quantite: d.quantite,
    ordre: d.ordre,
    codeArticle: d.codeArticle,
  );
}
