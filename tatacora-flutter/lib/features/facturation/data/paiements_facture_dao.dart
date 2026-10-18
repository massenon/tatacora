import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../caisse/data/sessions_caisse_dao.dart';
import '../../comptabilite/data/comptabilite_dao.dart';
import '../../comptabilite/data/moteur_comptable.dart';
import '../domain/creances.dart';
import '../domain/entities/paiement_facture.dart';
import '../domain/entities/piece_facturation.dart';
import '../domain/messages_encaissement.dart';
import '../domain/regles_encaissement.dart';
import '../domain/repositories/paiements_facture_repository.dart';
import '../../synchronisation/data/documents_autres_postes.dart';
import '../../synchronisation/data/operations_sync_dao.dart';
import '../../synchronisation/domain/charges_synchronisation.dart';
import '../../synchronisation/domain/operation_sync.dart';
import 'facture_dao.dart';
import 'piece_de_l_encaissement.dart';

/// Accès Drift aux encaissements de factures — **local pur**, SEUL auteur de
/// `paiements_facture_local`.
///
/// ## Aucun mixin généré, et c'est délibéré
///
/// Même forme que `SessionsCaisseDao` et `DepenseDao` : la table est enregistrée
/// par la session principale, `attachedDatabase.paiementsFactureLocal` suffit.
/// Aucun `part` de plus, donc aucun mixin vide possible (piège de
/// `panier_dao.dart`).
///
/// ## Le déroulement est celui du SERVEUR, étage par étage
///
/// [recouvrer] est le composant `ClientsCreances::enregistrerRecouvrement` : le
/// droit (403 avant toute validation), la validation de la saisie, puis le
/// service. [encaisser] est `EncaissementFactureService::encaisser` : facture
/// encaissable, mode connu, montant lisible et positif, montant ≤ reste dû, caisse
/// ouverte — dans CET ordre, et chaque refus porte la phrase du serveur (relue
/// par PHP, `encaissement_contre_serveur_test.dart`).
///
/// ## L'encaissement et sa pièce comptable : UNE transaction (règle du 31/08/2026)
///
/// Le paiement est écrit PUIS sa pièce passe par le moteur comptable
/// (`MoteurComptable.passerEtValider`), le tout dans une seule transaction
/// Drift. Un refus de pièce (exercice absent, compte inconnu, journal inconnu,
/// centre manquant…) annule le paiement ET le compteur de séquence : ni l'un ni
/// l'autre n'existe. C'est le déroulement de `EncaissementFactureService`, qui
/// crée le `Paiement` puis `passerEtValider` dans `DB::transaction`.
///
/// ## Le moteur arrive par un résolveur, pas par une instance
///
/// `moteurComptableProvider` attend l'installation du référentiel : une instance
/// construite trop tôt servirait un plan vide. Sans résolveur, écrire LÈVE
/// (`StateError`) — jamais un encaissement sans pièce par omission.
///
/// ## Rien ne part en file de synchronisation
///
/// Zéro réseau : un encaissement saisi ici reste ici. L'écran dit « enregistré
/// sur ce poste ».
class PaiementsFactureDao extends DatabaseAccessor<AppDatabase>
    implements PaiementsFactureRepository {
  PaiementsFactureDao(
    super.db, {
    Uuid? uuid,
    DateTime Function()? maintenant,
    this.moteur,
  }) : _uuid = uuid ?? const Uuid(),
       _maintenant = maintenant ?? DateTime.now;

  final Uuid _uuid;

  /// Injectable : la date du paiement et celle de la pièce en dépendent, et un
  /// test qui lit l'horloge réelle échoue un jour sur mille.
  final DateTime Function() _maintenant;

  /// Le résolveur du moteur comptable (voir l'en-tête de la classe).
  final Future<MoteurComptable> Function()? moteur;

  $PaiementsFactureLocalTable get _paiements =>
      attachedDatabase.paiementsFactureLocal;

  FactureDao get _factures => FactureDao(attachedDatabase);

  Future<MoteurComptable> _moteurObligatoire() {
    final resolveur = moteur;
    if (resolveur == null) {
      throw StateError(
        'PaiementsFactureDao sans moteur comptable : un encaissement ne '
        's’enregistre jamais sans sa pièce.',
      );
    }
    return resolveur();
  }

  PaiementFacture _vers(
    PaiementsFactureLocalData l, [
    String? login,
  ]) => PaiementFacture(
    loginCreation: login,
    id: l.id,
    pieceId: l.pieceId,
    sessionId: l.sessionId,
    // Le CHECK de la colonne borne les quatre valeurs : un code inconnu ne peut
    // pas venir de ce poste. S'il venait d'ailleurs, on le dirait.
    mode:
        ModePaiementFacture.depuisCode(l.modePaiement) ??
        (throw StateError('Mode de paiement inconnu : « ${l.modePaiement} ».')),
    montantCentimes: l.montantCentimes,
    datePaiement: l.datePaiement,
    statut: StatutPaiementFacture.depuisCode(l.statut),
    utilisateurCreationId: l.utilisateurCreationId,
    motifAnnulation: l.motifAnnulation,
    annuleParId: l.annuleParId,
    dateAnnulation: l.dateAnnulation,
  );

  /* ================================================================== */
  /* Lecture                                                             */
  /* ================================================================== */

  @override
  Future<List<PaiementFacture>> paiements() async {
    // Départage par identifiant : deux encaissements de la même seconde auraient
    // sinon un ordre indéfini (le serveur ne le départage pas).
    final q = select(_paiements)
      ..orderBy([
        (p) => OrderingTerm.desc(p.datePaiement),
        (p) => OrderingTerm.desc(p.id),
      ]);
    final lignes = await q.get();
    final logins = await _logins(lignes.map((l) => l.utilisateurCreationId));
    return [for (final l in lignes) _vers(l, logins[l.utilisateurCreationId])];
  }

  /// Le `login` de chaque auteur : UNE requête pour tous (un tableau n'en fait
  /// pas une par ligne).
  Future<Map<String, String>> _logins(Iterable<String> ids) async {
    final demandes = ids.toSet();
    if (demandes.isEmpty) return const {};
    final u = attachedDatabase.utilisateursLocal;
    final lignes = await (select(u)..where((x) => x.id.isIn(demandes))).get();
    return {for (final l in lignes) l.id: l.login};
  }

  @override
  Future<PaiementFacture?> parId(String id) async {
    final l = await (select(
      _paiements,
    )..where((p) => p.id.equals(id))).getSingleOrNull();
    if (l == null) return null;
    final logins = await _logins([l.utilisateurCreationId]);
    return _vers(l, logins[l.utilisateurCreationId]);
  }

  /// La créance d'UNE facture, par la formule unique de [composerCreances] :
  /// la pièce, ses avoirs, ses paiements ACTIFS et l'acompte lié.
  Future<CreanceFacture> creanceDe(PieceFacturation piece) async {
    final avoirs = await _factures.avoirsDe(piece.numero);
    final paiements = [
      for (final l in await (select(
        _paiements,
      )..where((p) => p.pieceId.equals(piece.id))).get())
        _vers(l),
    ];
    final acomptes = <String, int>{};
    final reservation = piece.reservationId;
    if (reservation != null) {
      final r = await (attachedDatabase.select(
        attachedDatabase.reservationsLocal,
      )..where((x) => x.id.equals(reservation))).getSingleOrNull();
      if (r != null) acomptes[reservation] = r.acompte.round();
    }
    return composerCreances(
      pieces: [piece, ...avoirs],
      paiements: paiements,
      acomptesParReservation: acomptes,
    ).firstWhere((c) => c.piece.id == piece.id);
  }

  /* ================================================================== */
  /* Écriture                                                            */
  /* ================================================================== */

  @override
  Future<PaiementFacture> recouvrer({
    required String? pieceId,
    required String? montantSaisi,
    required String? modeSaisi,
    required String auteurId,
    required bool peutEncaisser,
  }) async {
    // Le serveur répond 403 AVANT toute validation : un rôle sans droit
    // n'apprend rien de la validité des données qu'il a soumises.
    if (!peutEncaisser) {
      throw const RefusEncaissement(MessagesEncaissement.refusDroit);
    }

    // `recouvrementFactureId` : ['required', 'uuid', 'exists:factures,id'].
    const champPiece = ChampEncaissement.piece;
    if (estVideAuSensDePhp(pieceId)) {
      throw RefusEncaissement(
        MessagesEncaissement.obligatoire(champPiece.attribut),
        champ: champPiece,
      );
    }
    if (!estUnUuid(pieceId!)) {
      throw RefusEncaissement(
        MessagesEncaissement.uuid(champPiece.attribut),
        champ: champPiece,
      );
    }
    if (await _factures.parId(pieceId) == null) {
      throw RefusEncaissement(
        MessagesEncaissement.invalide(champPiece.attribut),
        champ: champPiece,
      );
    }
    validerMontantRecouvrement(montantSaisi);
    final mode = validerModeRecouvrement(modeSaisi);

    try {
      return await encaisser(
        pieceId: pieceId,
        montant: montantSaisi!,
        mode: mode.code,
        auteurId: auteurId,
      );
    } on RefusEncaissement catch (refus) {
      // `addError('recouvrementMontant', $refus->getMessage())` : TOUT refus du
      // service s'affiche sous le champ montant, caisse fermée comprise.
      throw RefusEncaissement(refus.message, champ: ChampEncaissement.montant);
    }
  }

  @override
  Future<PaiementFacture> encaisser({
    required String pieceId,
    required String montant,
    required String mode,
    required String auteurId,
  }) async {
    final moteurComptable = await _moteurObligatoire();

    final id = await transaction(() async {
      final piece = await _factures.parId(pieceId);
      if (piece == null) {
        throw RefusEncaissement(
          MessagesEncaissement.invalide(ChampEncaissement.piece.attribut),
          champ: ChampEncaissement.piece,
        );
      }

      // Premier garde du service : « facture figée ». Toute pièce du registre
      // l'est dès l'émission ; reste à écarter ce qui n'est PAS une facture
      // (avoir, ticket au comptant) — écart du poste, voir
      // `MessagesEncaissement.pieceNonEncaissable`.
      if (!estUneCreance(piece)) {
        throw const RefusEncaissement(MessagesEncaissement.pieceNonEncaissable);
      }

      final modeConnu = ModePaiementFacture.depuisCode(mode);
      if (modeConnu == null) {
        throw RefusEncaissement(MessagesEncaissement.modeInconnu(mode));
      }

      final demande = montantDuServiceCentimes(montant);

      final creance = await creanceDe(piece);
      final reste = creance.resteDuCentimes;
      if (demande > BigInt.from(reste)) {
        throw RefusEncaissement(
          MessagesEncaissement.superieurAuReste(chaineDuServeur(reste)),
        );
      }
      final montantCentimes = demande.toInt();

      // Le tiroir OUVERT — pas « le dernier connu » : un encaissement hors
      // session fausserait la clôture de caisse de tout le monde. TOUS points de
      // vente confondus, comme le serveur (`whereNull('date_cloture')->
      // orderByDesc('date_ouverture')`), alors que le comptoir, lui, ne regarde
      // que le point `bar` : deux définitions du tiroir (D230).
      final session = await SessionsCaisseDao(
        attachedDatabase,
      ).sessionOuverteLaPlusRecente();
      if (session == null) {
        throw const RefusEncaissement(MessagesEncaissement.caisseFermee);
      }

      if (auteurId.isEmpty) {
        throw const RefusEncaissement(MessagesEncaissement.auteurInconnu);
      }

      final id = _uuid.v4();
      final maintenant = _maintenant();

      await into(_paiements).insert(
        PaiementsFactureLocalCompanion.insert(
          id: id,
          pieceId: piece.id,
          sessionId: session.id,
          modePaiement: modeConnu.code,
          montantCentimes: montantCentimes,
          datePaiement: maintenant,
          utilisateurCreationId: auteurId,
        ),
      );

      // La pièce DANS la transaction : refusée, elle emporte le paiement.
      await moteurComptable.passerEtValider(
        pieceDeLEncaissement(
          mode: modeConnu,
          dateIso: formaterDateIso(maintenant),
          libelle: libellePieceEncaissement(piece.numero, id),
          montantCentimes: montantCentimes,
        ),
        auteurId: auteurId,
      );

      // Lot F5d : l'encaissement part au serveur (document source, D246 : la
      // pièce ci-dessus ne part jamais), si sa facture y part aussi.
      if (await _factures.partAuServeur(piece.id)) {
        await OperationsSyncDao(attachedDatabase).enfiler(
          table: TableSynchronisee.paiements,
          entiteId: id,
          type: TypeOperationSync.creation,
          payload: chargePaiementFacture(
            factureId: piece.id,
            sessionId: session.id,
            modePaiement: modeConnu.code,
            montantCentimes: montantCentimes,
            datePaiement: maintenant,
          ),
          horodatage: maintenant,
        );
      }

      return id;
    });

    // Relu plutôt que composé de mémoire : c'est la base qui fait foi.
    return (await parId(id))!;
  }

  @override
  Future<PaiementFacture> annuler(
    String paiementId,
    String motif, {
    required String auteurId,
  }) async {
    final paiement = await parId(paiementId);
    if (paiement == null) {
      throw const RefusEncaissement(MessagesEncaissement.paiementIntrouvable);
    }
    if (paiement.statut == StatutPaiementFacture.annule) {
      throw const RefusEncaissement(MessagesEncaissement.dejaAnnule);
    }
    if (estVideAuSensDePhp(motif)) {
      throw const RefusEncaissement(MessagesEncaissement.motifRequis);
    }
    // Q3 (lot F6) : l'encaissement d'un autre poste, par l'administration ou
    // le comptable seulement.
    if (!await DocumentsAutresPostes(
      attachedDatabase,
    ).peutAnnuler('paiements', paiement.id, auteurId)) {
      throw const RefusEncaissement(DocumentsAutresPostes.refus);
    }

    final moteurComptable = await _moteurObligatoire();
    final piece = await _factures.parId(paiement.pieceId);
    final libelle = libellePieceEncaissement(piece?.numero ?? '', paiement.id);

    // La pièce se retrouve par son libellé (PA-52) et se VÉRIFIE avant d'être
    // inversée : une pièce à moitié retrouvée serait contre-passée à moitié, en
    // silence.
    final comptabilite = ComptabiliteDao(attachedDatabase);
    var lignes = await comptabilite.lignesParLibelle(libelle);
    // Lot F5c : la facture a pu recevoir depuis le numéro du serveur ; la
    // pièce garde le numéro PROVISOIRE du jour de l'encaissement, et se
    // retrouve alors par l'UUID du paiement, unique (PA-52). Seul ce cas (la
    // pièce a été RÉGULARISÉE) : un autre numéro changé reste refusé, comme
    // au serveur.
    if (lignes.isEmpty && await _factures.regularisee(paiement.pieceId)) {
      lignes = await comptabilite.lignesParSuffixeLibelle(
        ' — ${paiement.id}',
        prefixe: 'Encaissement $prefixeNumeroProvisoire',
      );
    }
    var debit = 0;
    var credit = 0;
    for (final l in lignes) {
      debit += l.debitCentimes;
      credit += l.creditCentimes;
    }
    if (lignes.length < 2 ||
        debit != credit ||
        debit != paiement.montantCentimes) {
      throw RefusEncaissement(MessagesEncaissement.pieceIntrouvable(libelle));
    }

    await transaction(() async {
      await moteurComptable.contrepasserPiece(
        lignes,
        auteurId: auteurId,
        motif: motif,
      );
      await (update(_paiements)..where((p) => p.id.equals(paiement.id))).write(
        PaiementsFactureLocalCompanion(
          statut: Value(StatutPaiementFacture.annule.code),
          motifAnnulation: Value(motif),
          annuleParId: Value(auteurId),
          dateAnnulation: Value(_maintenant()),
        ),
      );
      if (await _factures.partAuServeur(paiement.pieceId)) {
        await OperationsSyncDao(attachedDatabase).enfiler(
          table: TableSynchronisee.paiements,
          entiteId: paiement.id,
          type: TypeOperationSync.modification,
          payload: chargeAnnulationPaiement(motif: motif),
        );
      }
    });

    return (await parId(paiement.id))!;
  }

  /* ================================================================== */
  /* Encaissements DESCENDUS du serveur — lot F5d                        */
  /* ================================================================== */

  /// Inscrit un encaissement reçu du serveur (un autre poste, ou la PWA),
  /// sous SON identifiant. Aucune pièce (Q1 : le journal du poste ne tient
  /// que ses propres pièces, le serveur a passé celle-ci), aucune file. Le
  /// reste dû de la facture le compte aussitôt. Appelé par la seule descente.
  Future<void> inscrireDescendu({
    required String id,
    required String pieceId,
    required String sessionId,
    required ModePaiementFacture mode,
    required int montantCentimes,
    required DateTime datePaiement,
    required StatutPaiementFacture statut,
    required String? motifAnnulation,
    required DateTime? dateAnnulation,
    required String auteurId,
  }) => into(_paiements).insert(
    PaiementsFactureLocalCompanion.insert(
      id: id,
      pieceId: pieceId,
      sessionId: sessionId,
      modePaiement: mode.code,
      montantCentimes: montantCentimes,
      datePaiement: datePaiement,
      statut: Value(statut.code),
      motifAnnulation: Value(motifAnnulation),
      annuleParId: Value(
        statut == StatutPaiementFacture.annule ? auteurId : null,
      ),
      dateAnnulation: Value(dateAnnulation),
      utilisateurCreationId: auteurId,
    ),
  );

  /// Un encaissement déjà détenu, ANNULÉ au serveur : l'état suit, jamais
  /// à rebours (un paiement annulé ne redevient pas actif). Aucune
  /// contre-passation ici : la pièce de ce poste, s'il l'a passée, reste
  /// — écart nommé, l'annulation d'un document d'un autre poste relève du
  /// lot F6 (Q3 : l'administration et le comptable).
  Future<void> suivreAnnulationDescendue({
    required String id,
    required String? motif,
    required DateTime? date,
    required String auteurId,
  }) async {
    await (update(_paiements)..where(
          (p) =>
              p.id.equals(id) &
              p.statut.equals(StatutPaiementFacture.actif.code),
        ))
        .write(
          PaiementsFactureLocalCompanion(
            statut: Value(StatutPaiementFacture.annule.code),
            motifAnnulation: Value(motif),
            annuleParId: Value(auteurId),
            dateAnnulation: Value(date ?? _maintenant()),
          ),
        );
  }
}
