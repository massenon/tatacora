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
import '../domain/repositories/depenses_repository.dart';
import 'piece_de_la_depense.dart';

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
class DepenseDao extends DatabaseAccessor<AppDatabase>
    implements DepensesRepository {
  DepenseDao(
    super.db, {
    Uuid? uuid,
    DateTime Function()? maintenant,
    this.moteur,
  }) : _uuid = uuid ?? const Uuid(),
       _maintenant = maintenant ?? DateTime.now;

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

    return entetes
        .map((e) => _versDepense(e, parDepense[e.id] ?? const [], numeros))
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
    );
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
  }) async {
    final libelleNet = libelle.trim();
    await _validerLaSaisie(libelleNet, lignes);

    final moteur = await _moteurObligatoire();
    final id = _uuid.v4();
    final maintenant = _maintenant();

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

    // Relu plutôt que composé de mémoire : c'est la base qui fait foi, et le
    // montant décaissé se somme des lignes réellement écrites.
    return (await parId(id))!;
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
  );

  LigneDepense _versLigne(LignesDepenseLocalData l) => LigneDepense(
    id: l.id,
    libelle: l.libelle,
    compteCharge: l.compteCharge,
    nature: l.nature,
    famille: l.famille,
    montant: l.montant,
  );
}
