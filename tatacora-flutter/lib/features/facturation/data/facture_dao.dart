import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
// Les classes de tables doivent être dans la portée du fichier : `@DriftAccessor`
// les résout par leur type, et un import de `app_database.dart` seul ne les
// réexporte pas. Sans ces lignes, le mixin généré est VIDE — sans erreur de
// génération, ce qui rend le diagnostic trompeur (leçon `reservation_dao.dart`).
import '../../../core/database/tables/registre_facturation_tables.dart';
import '../domain/entities/piece_facturation.dart';
import '../domain/repositories/facture_repository.dart';

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
/// ## Aucune entrée n'est mise en file de synchronisation
///
/// Délibéré, et vérifié par un test. Le serveur n'a ni table `factures` au
/// registre `TABLES_SYNCHRONISABLES`, ni route d'API de facturation : une
/// opération poussée serait refusée à chaque tentative, et le poste afficherait
/// « en attente de synchronisation » sur quelque chose qui ne partira jamais.
/// C'est la famille PA-59 / PA-60 / PA-61.
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

    return 'F-$annee-${suivant.toString().padLeft(5, '0')}';
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
          statut: Value(StatutPiece.emise.code),
          // Identité FISCALE : nulle à l'émission, toujours. La certification
          // n'a pas lieu (PA-17 / PA-61).
          numeroMecef: const Value(null),
        ),
      );

      await _copierLignes([
        for (var i = 0; i < brouillon.lignes.length; i++)
          _versLigneCompanion(id, brouillon.lignes[i], i),
      ]);
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
  Future<AnnulationParAvoir> annuler(String pieceId, String motif) async {
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
        ),
      );

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
