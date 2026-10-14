import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../comptabilite/data/comptabilite_dao.dart';
import '../../comptabilite/data/moteur_comptable.dart';
import '../../depenses/domain/categories_depense.dart';
import '../../facturation/domain/messages_encaissement.dart';
import '../domain/calcul_achats.dart';
import '../domain/entities/reglement_fournisseur.dart';
import '../domain/messages_achats.dart';
import '../domain/messages_reglement.dart';
import '../domain/regles_reglement.dart';
import 'piece_du_reglement.dart';

/// Accès Drift aux règlements fournisseur — **local pur**, SEUL auteur de
/// `reglements_fournisseur_local`.
///
/// ## Aucun mixin généré, et c'est délibéré
///
/// Même forme que `PaiementsFactureDao` et `DepenseDao` : la table est
/// enregistrée par la session principale, `attachedDatabase.
/// reglementsFournisseurLocal` suffit. Aucun `part` de plus.
///
/// ## Le déroulement est celui du SERVEUR, étage par étage
///
/// [regler] est le composant `Approvisionnement::enregistrerReglement` : la
/// validation de la saisie (commande, montant, trésorerie), puis le service.
/// [reglerParLeService] est `ReglementFournisseurService::regler` : trésorerie
/// connue, montant lisible et positif, montant ≤ reste dû — dans CET ordre, et
/// chaque refus porte la phrase du serveur (relue par PHP,
/// `reglement_contre_serveur_test.dart`).
///
/// ## Le règlement et sa pièce comptable : UNE transaction (règle du 31/08/2026)
///
/// Le règlement est écrit PUIS sa pièce passe par le moteur comptable
/// (`MoteurComptable.passerEtValider`, Dr 4011 / Cr trésorerie du mode), le tout
/// dans une seule transaction Drift. Un refus de pièce (exercice absent, compte
/// inconnu, journal inconnu…) annule le règlement ET le compteur de séquence :
/// ni l'un ni l'autre n'existe. C'est le déroulement du service, qui crée le
/// `ReglementFournisseur` puis `passerEtValider` dans `DB::transaction`.
///
/// ## Le reste dû est relu DANS la transaction
///
/// Le service le lit avant d'ouvrir la sienne ; lire puis écrire dans deux
/// temps laisse passer deux règlements concurrents dont chacun tient seul dans
/// le reste. Ici la lecture, la comparaison et l'écriture sont une seule
/// transaction (même leçon que `annulerAvecConditions`, D252) — un écart de
/// protection par rapport au serveur, jamais un écart de résultat.
///
/// ## Le moteur arrive par un résolveur, pas par une instance
///
/// `moteurComptableProvider` attend l'installation du référentiel : une instance
/// construite trop tôt servirait un plan vide. Sans résolveur, écrire LÈVE
/// (`StateError`) — jamais un règlement sans pièce par omission.
///
/// ## Rien ne part en file de synchronisation
///
/// Zéro réseau : un règlement saisi ici reste ici. L'écran dit « enregistré sur
/// ce poste ».
class ReglementsFournisseurDao extends DatabaseAccessor<AppDatabase> {
  ReglementsFournisseurDao(
    super.db, {
    Uuid? uuid,
    DateTime Function()? maintenant,
    this.moteur,
  }) : _uuid = uuid ?? const Uuid(),
       _maintenant = maintenant ?? DateTime.now;

  final Uuid _uuid;

  /// Injectable : la date du règlement et celle de la pièce en dépendent, et un
  /// test qui lit l'horloge réelle échoue un jour sur mille.
  final DateTime Function() _maintenant;

  /// Le résolveur du moteur comptable (voir l'en-tête de la classe).
  final Future<MoteurComptable> Function()? moteur;

  $ReglementsFournisseurLocalTable get _reglements =>
      attachedDatabase.reglementsFournisseurLocal;

  Future<MoteurComptable> _moteurObligatoire() {
    final resolveur = moteur;
    if (resolveur == null) {
      throw StateError(
        'ReglementsFournisseurDao sans moteur comptable : un règlement ne '
        's’enregistre jamais sans sa pièce.',
      );
    }
    return resolveur();
  }

  ReglementFournisseur _vers(ReglementsFournisseurLocalData l) =>
      ReglementFournisseur(
        id: l.id,
        commandeId: l.commandeId,
        montantCentimes: l.montantCentimes,
        // Le CHECK de la colonne borne les trois valeurs : un code inconnu ne
        // peut pas venir de ce poste. S'il venait d'ailleurs, on le dirait.
        tresorerie:
            TresorerieDepense.depuisCode(l.tresorerie) ??
            (throw StateError('Trésorerie inconnue : « ${l.tresorerie} ».')),
        dateReglement: l.dateReglement,
        statut:
            StatutReglement.depuisCode(l.statut) ??
            (throw StateError(
              'Statut de règlement inconnu : « ${l.statut} ».',
            )),
        motifAnnulation: l.motifAnnulation,
        annuleParId: l.annuleParId,
        dateAnnulation: l.dateAnnulation,
        utilisateurCreationId: l.utilisateurCreationId,
      );

  static String _jour(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /* ================================================================== */
  /* Lecture                                                             */
  /* ================================================================== */

  /// Les règlements, annulés compris, du plus récent au plus ancien (date, puis
  /// identifiant : le serveur ne départage pas deux règlements du même jour).
  Future<List<ReglementFournisseur>> reglements({String? commandeId}) async {
    final q = select(_reglements)
      ..orderBy([
        (r) => OrderingTerm.desc(r.dateReglement),
        (r) => OrderingTerm.desc(r.id),
      ]);
    if (commandeId != null) q.where((r) => r.commandeId.equals(commandeId));
    return [for (final l in await q.get()) _vers(l)];
  }

  Future<ReglementFournisseur?> parId(String id) async {
    final l = await (select(
      _reglements,
    )..where((r) => r.id.equals(id))).getSingleOrNull();
    return l == null ? null : _vers(l);
  }

  /// `totalRegle()` du service : la somme des règlements ACTIFS d'une commande —
  /// un annulé (PA-168) ne compte plus.
  Future<int> totalRegleCentimes(String commandeId) async {
    var somme = 0;
    for (final r
        in await (select(_reglements)..where(
              (x) => x.commandeId.equals(commandeId) & x.statut.equals('actif'),
            ))
            .get()) {
      somme += r.montantCentimes;
    }
    return somme;
  }

  /// Le total de la commande, DES LIGNES (`CommandeAchat::montantTotal`), jamais
  /// d'une colonne : le poste n'en porte aucune (voir `achats_tables.dart`).
  Future<int> _totalCommandeCentimes(String commandeId) async {
    final lignes = await (select(
      attachedDatabase.lignesCommandeAchatLocal,
    )..where((l) => l.commandeId.equals(commandeId))).get();
    return montantTotalCentimes([
      for (final l in lignes)
        (
          quantiteCentiemes: l.quantiteCentiemes,
          prixUnitaireCentimes: l.prixUnitaireCentimes,
        ),
    ]);
  }

  /// `resteDu()` du service : total − règlements actifs, planché à zéro.
  Future<int> resteDuDe(String commandeId) async => resteDuCentimes(
    totalCommandeCentimes: await _totalCommandeCentimes(commandeId),
    regleActifCentimes: await totalRegleCentimes(commandeId),
  );

  Future<String> _raisonSociale(String fournisseurId) async {
    final f = await (attachedDatabase.select(
      attachedDatabase.fournisseursLocal,
    )..where((x) => x.id.equals(fournisseurId))).getSingleOrNull();
    return f?.raisonSociale ?? '';
  }

  /* ================================================================== */
  /* Ouverture de la modale « Régler »                                   */
  /* ================================================================== */

  /// `Approvisionnement::ouvrirFormulaireReglement` : la commande doit exister
  /// (sinon le serveur répond par la phrase de `achats.commande_cloturee`, D258),
  /// et son reste dû doit être positif (sinon « déjà intégralement réglée »).
  /// Ne lève QUE [RefusReglement] : le droit d'écriture est le premier étage,
  /// celui de l'appelant.
  Future<OuvertureReglement> ouvrir(String commandeId) async {
    final c = await (attachedDatabase.select(
      attachedDatabase.commandesAchatLocal,
    )..where((x) => x.id.equals(commandeId))).getSingleOrNull();
    if (c == null) {
      // Écart du serveur répliqué : la phrase d'une AUTRE situation (D258).
      throw const RefusReglement(MessagesAchats.commandeCloturee);
    }

    final reste = await resteDuDe(c.id);
    if (reste <= 0) {
      throw const RefusReglement(MessagesReglement.commandeSoldee);
    }

    return OuvertureReglement(
      commandeId: c.id,
      fournisseurNom: await _raisonSociale(c.fournisseurId),
      resteDuCentimes: reste,
    );
  }

  /* ================================================================== */
  /* Écriture                                                            */
  /* ================================================================== */

  /// Le composant `Approvisionnement::enregistrerReglement` : validation des
  /// trois propriétés (dans l'ordre commande, montant, trésorerie — le serveur
  /// les valide toutes et l'écran n'affiche que celle du montant), puis le
  /// service. Tout refus du service porte le champ montant, comme au serveur
  /// (`addError('regMontant', …)`).
  Future<ReglementFournisseur> regler({
    required String? commandeId,
    required String? montantSaisi,
    required String? tresorerieSaisie,
    required String auteurId,
  }) async {
    const champCommande = ChampReglement.commande;
    if (estVideAuSensDePhp(commandeId)) {
      throw RefusReglement(
        MessagesEncaissement.obligatoire(champCommande.attribut),
        champ: champCommande,
      );
    }
    final commande = await (attachedDatabase.select(
      attachedDatabase.commandesAchatLocal,
    )..where((x) => x.id.equals(commandeId!))).getSingleOrNull();
    if (commande == null) {
      throw RefusReglement(
        MessagesEncaissement.invalide(champCommande.attribut),
        champ: champCommande,
      );
    }
    validerMontantReglement(montantSaisi);
    final tresorerie = validerTresorerieReglement(tresorerieSaisie);

    try {
      return await reglerParLeService(
        commandeId: commande.id,
        montant: montantSaisi!,
        tresorerie: tresorerie.code,
        auteurId: auteurId,
      );
    } on RefusReglement catch (refus) {
      throw RefusReglement(refus.message, champ: ChampReglement.montant);
    }
  }

  /// `ReglementFournisseurService::regler` : trésorerie connue, montant lisible
  /// et positif, montant ≤ reste dû, puis le règlement ET sa pièce.
  Future<ReglementFournisseur> reglerParLeService({
    required String commandeId,
    required String montant,
    required String tresorerie,
    required String auteurId,
  }) async {
    final moteurComptable = await _moteurObligatoire();

    final id = await transaction(() async {
      final modeConnu = TresorerieDepense.depuisCode(tresorerie);
      if (modeConnu == null) {
        throw RefusReglement(MessagesReglement.tresorerieInconnue(tresorerie));
      }

      final demande = montantDuReglementCentimes(montant);

      final commande = await (select(
        attachedDatabase.commandesAchatLocal,
      )..where((c) => c.id.equals(commandeId))).getSingleOrNull();
      if (commande == null) {
        throw const RefusReglement(MessagesReglement.commandeIntrouvable);
      }

      final reste = await resteDuDe(commandeId);
      if (demande > BigInt.from(reste)) {
        throw RefusReglement(
          MessagesReglement.superieurAuReste(chaineDuReglement(reste)),
        );
      }
      final montantCentimes = demande.toInt();

      if (auteurId.isEmpty) {
        throw const RefusReglement(MessagesReglement.auteurInconnu);
      }

      final id = _uuid.v4();
      final maintenant = _maintenant();
      final raison = await _raisonSociale(commande.fournisseurId);

      await into(_reglements).insert(
        ReglementsFournisseurLocalCompanion.insert(
          id: id,
          commandeId: commandeId,
          montantCentimes: montantCentimes,
          tresorerie: modeConnu.code,
          dateReglement: _jour(maintenant),
          utilisateurCreationId: auteurId,
        ),
      );

      // La pièce DANS la transaction : refusée, elle emporte le règlement.
      await moteurComptable.passerEtValider(
        pieceDuReglement(
          tresorerie: modeConnu,
          dateIso: formaterDateIso(maintenant),
          libelle: libellePieceReglement(raison, id),
          montantCentimes: montantCentimes,
        ),
        auteurId: auteurId,
      );

      return id;
    });

    // Relu plutôt que composé de mémoire : c'est la base qui fait foi.
    return (await parId(id))!;
  }

  /// `ReglementFournisseurService::annuler` (PA-168) : état tracé jamais
  /// supprimé (RG-15), contre-passation de la pièce ENTIÈRE retrouvée par
  /// libellé et VÉRIFIÉE équilibrée (PA-52), dans la même transaction.
  ///
  /// ⚠ AUCUN écran ni aucune route du serveur n'appelle ce geste (D257) : le
  /// poste le porte parce que le service existe, pas parce qu'un bouton l'offre.
  /// `reglements_fournisseur_tables.dart` le dit ; un test l'épingle.
  Future<ReglementFournisseur> annuler(
    String reglementId,
    String motif, {
    required String auteurId,
  }) async {
    final reglement = await parId(reglementId);
    if (reglement == null) {
      throw const RefusReglement(MessagesReglement.reglementIntrouvable);
    }
    if (reglement.statut == StatutReglement.annule) {
      throw const RefusReglement(MessagesReglement.dejaAnnule);
    }
    if (estVideAuSensDePhp(motif)) {
      throw const RefusReglement(MessagesReglement.motifRequis);
    }

    final moteurComptable = await _moteurObligatoire();

    await transaction(() async {
      // Relu DANS la transaction : deux annulations concurrentes ne
      // contre-passent pas deux fois la même pièce.
      final courant = await parId(reglementId);
      if (courant == null || courant.statut == StatutReglement.annule) {
        throw const RefusReglement(MessagesReglement.dejaAnnule);
      }

      final commande = await (attachedDatabase.select(
        attachedDatabase.commandesAchatLocal,
      )..where((c) => c.id.equals(courant.commandeId))).getSingle();
      final libelle = libellePieceReglement(
        await _raisonSociale(commande.fournisseurId),
        courant.id,
      );

      // La pièce se retrouve par son libellé (PA-52) et se VÉRIFIE avant d'être
      // inversée : une pièce à moitié retrouvée serait contre-passée à moitié,
      // en silence.
      final lignes = await ComptabiliteDao(
        attachedDatabase,
      ).lignesParLibelle(libelle);
      var debit = 0;
      var credit = 0;
      for (final l in lignes) {
        debit += l.debitCentimes;
        credit += l.creditCentimes;
      }
      if (lignes.length < 2 ||
          debit != credit ||
          debit != courant.montantCentimes) {
        throw RefusReglement(MessagesReglement.pieceIntrouvable(libelle));
      }

      await moteurComptable.contrepasserPiece(
        lignes,
        auteurId: auteurId,
        motif: motif,
      );
      await (update(_reglements)..where((r) => r.id.equals(courant.id))).write(
        ReglementsFournisseurLocalCompanion(
          statut: Value(StatutReglement.annule.code),
          motifAnnulation: Value(motif),
          annuleParId: Value(auteurId),
          dateAnnulation: Value(_maintenant()),
        ),
      );
    });

    return (await parId(reglementId))!;
  }
}
