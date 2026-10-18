import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
// Les classes de tables doivent etre dans la portee du fichier : `@DriftAccessor`
// les resout par leur type, et un import de `app_database.dart` seul ne les
// reexporte pas. Sans ces trois lignes, le mixin genere est VIDE — sans erreur
// de generation, ce qui rend le diagnostic trompeur.
import '../../../core/database/tables/clients_table.dart';
import '../../../core/database/tables/hebergement_tables.dart';
import '../../comptabilite/data/moteur_comptable.dart';
import '../../synchronisation/data/documents_autres_postes.dart';
import '../../synchronisation/data/operations_sync_dao.dart';
import '../../synchronisation/domain/charges_synchronisation.dart';
import '../../synchronisation/domain/operation_sync.dart';
import '../domain/annulation_reservation.dart';
import '../domain/messages_annulation.dart' show RefusAnnulation;
import '../domain/entities/annulation_enregistree.dart';
import '../domain/entities/periode_sejour.dart';
import '../domain/entities/fiche_reservation.dart';
import '../domain/repositories/reservation_repository.dart'
    show ReservationIntrouvable;
import '../domain/entities/reservation.dart';
import '../domain/entities/service_reservation.dart';
import '../domain/entities/unite_hebergement.dart';
import 'dto/parc_dto.dart';
import 'pieces_reservation.dart';

part 'reservation_dao.g.dart';

/// Accès Drift aux réservations et au parc.
///
/// ## Le DAO ne parle qu'entités
///
/// Aucune méthode ne rend un `ReservationsLocalData`. La forme des tables ne
/// franchit pas cette frontière : sans quoi renommer une colonne casserait un
/// widget, et la couche présentation saurait qu'une base existe.
///
/// ## Chaque écriture alimente la file, dans la MÊME transaction
///
/// Écrire la réservation puis la mettre en file en deux temps ouvre une
/// fenêtre — courte, mais réelle — où l'application peut être tuée entre les
/// deux. La réservation existerait alors localement sans que rien ne la
/// pousse jamais au serveur : perdue sans erreur, découverte des semaines plus
/// tard par un client qui se présente avec une confirmation.
@DriftAccessor(
  tables: [
    ReservationsLocal,
    UnitesHebergementLocal,
    CategoriesHebergementLocal,
    ClientsLocal,
    LignesReservationLocal,
  ],
)
class ReservationDao extends DatabaseAccessor<AppDatabase>
    with _$ReservationDaoMixin {
  ReservationDao(super.db, {DateTime Function()? maintenant, this.moteur})
    : _maintenant = maintenant ?? DateTime.now;

  /// Injectable : la date de la pièce et celle de l'annulation en dépendent, et
  /// un test qui lit l'horloge réelle échoue un jour sur mille.
  final DateTime Function() _maintenant;

  /// Le résolveur du moteur comptable, qui écrit la PIÈCE d'un acompte et d'un
  /// remboursement.
  ///
  /// Un résolveur et non une instance : `moteurComptableProvider` attend
  /// l'installation du référentiel. **Il n'est exigé que quand une pièce doit
  /// être passée** (un acompte encaissé, un remboursement) : une réservation sans
  /// argent n'en a pas besoin, et sans lui un geste qui DOIT produire une pièce
  /// LÈVE (`StateError`) — jamais un acompte sans sa pièce par omission (règle
  /// du PO du 31/08/2026).
  final Future<MoteurComptable> Function()? moteur;

  Future<MoteurComptable> _moteurObligatoire() {
    final resolveur = moteur;
    if (resolveur == null) {
      throw StateError(
        'ReservationDao sans moteur comptable : un acompte ou un '
        'remboursement ne s’enregistre jamais sans sa pièce.',
      );
    }
    return resolveur();
  }

  /* ================================================================== */
  /* Lecture                                                             */
  /* ================================================================== */

  /// Le parc, avec le libellé et le tarif de sa catégorie.
  ///
  /// Le tarif et la capacité vivent sur la **catégorie** au schéma, et sur
  /// l'**unité** au domaine. La jointure est faite ici, une fois : la remonter
  /// jusqu'aux écrans obligerait chacun d'eux à connaître la structure des
  /// deux tables.
  Future<List<UniteHebergement>> unites() async {
    final requete = select(unitesHebergementLocal).join([
      innerJoin(
        categoriesHebergementLocal,
        categoriesHebergementLocal.id.equalsExp(
          unitesHebergementLocal.categorieId,
        ),
      ),
    ]);

    final lignes = await requete.get();
    return lignes.map((l) {
      final unite = l.readTable(unitesHebergementLocal);
      final categorie = l.readTable(categoriesHebergementLocal);
      return UniteHebergement(
        id: unite.id,
        numero: unite.numero,
        categorieId: categorie.id,
        categorieLibelle: categorie.libelle,
        statut: StatutUnite.depuisCode(unite.statut),
        // Le tarif est stocké en `REAL` par le schéma documenté, alors que le
        // domaine le manipule en entier — le XOF n'a pas de sous-unité en
        // circulation. La conversion est faite ici plutôt que d'imposer un
        // `double` au domaine, où il finirait par produire un arrondi sur une
        // addition de lignes.
        tarifBase: categorie.tarifBase.round(),
        capaciteMax: categorie.capaciteMax,
      );
    }).toList();
  }

  Future<List<Reservation>> reservations({
    bool seulementEnSuspens = false,
  }) async {
    final requete = select(reservationsLocal).join([
      innerJoin(
        clientsLocal,
        clientsLocal.id.equalsExp(reservationsLocal.clientId),
      ),
    ]);

    if (seulementEnSuspens) {
      requete.where(
        reservationsLocal.statutSync.isIn(const ['local', 'en_attente']),
      );
    }
    // Départage par identifiant après l'horodatage : deux réservations créées
    // dans la même milliseconde — import par lot, double appui — auraient
    // sinon un ordre indéfini, et la liste changerait d'ordre à chaque
    // rafraîchissement sans qu'aucune donnée n'ait bougé.
    requete.orderBy([
      OrderingTerm.desc(reservationsLocal.dateCreationLocale),
      OrderingTerm.desc(reservationsLocal.id),
    ]);

    final resultats = await requete.get();
    final reservations = resultats
        .map((l) => l.readTable(reservationsLocal))
        .toList();
    final lignesParReservation = await _lignesDe(reservations.map((r) => r.id));
    final logins = await _loginsDe(reservations);

    return resultats
        .map(
          (l) => _versEntite(
            l.readTable(reservationsLocal),
            l.readTable(clientsLocal),
            lignes:
                lignesParReservation[l.readTable(reservationsLocal).id] ??
                const [],
            logins: logins,
          ),
        )
        .toList();
  }

  /// Écrit le parc **venu du serveur** — catégories puis unités (PA-128).
  ///
  /// L'ordre est contraint : `unites_hebergement_local.categorie_id` est une
  /// clé étrangère. Écrire les unités d'abord échouerait sur la première.
  ///
  /// **Aucune suppression.** Une unité retirée du serveur reste ici : elle est
  /// peut-être référencée par une réservation locale, et la supprimer
  /// casserait la clé étrangère de cette réservation — c'est-à-dire la seule
  /// trace d'un séjour, potentiellement pas encore poussé. Le nettoyage d'un
  /// parc est une décision d'exploitation, pas un effet de bord d'alignement.
  ///
  /// **Aucune entrée de file** : ces données VIENNENT du serveur, et
  /// `unites_hebergement` n'est de toute façon pas au registre synchronisable
  /// (PA-118) — une opération y serait rejetée à chaque tentative.
  Future<int> alignerParc(ParcDistant parc) async {
    if (parc.estVide) return 0;

    var ecrits = 0;

    await transaction(() async {
      for (final c in parc.categories) {
        await into(categoriesHebergementLocal).insertOnConflictUpdate(
          CategoriesHebergementLocalCompanion.insert(
            id: c.id,
            libelle: c.libelle,
            capaciteMax: c.capaciteMax,
            tarifBase: c.tarifBase,
          ),
        );
        ecrits++;
      }

      for (final u in parc.unites) {
        await into(unitesHebergementLocal).insertOnConflictUpdate(
          UnitesHebergementLocalCompanion.insert(
            id: u.id,
            categorieId: u.categorieId,
            numero: u.numero,
            statut: u.statut,
          ),
        );
        ecrits++;
      }
    });

    return ecrits;
  }

  Future<Reservation?> parId(String id) async {
    final ligne =
        await (select(reservationsLocal)..where((r) => r.id.equals(id))).join([
          innerJoin(
            clientsLocal,
            clientsLocal.id.equalsExp(reservationsLocal.clientId),
          ),
        ]).getSingleOrNull();

    if (ligne == null) return null;
    return _versEntite(
      ligne.readTable(reservationsLocal),
      ligne.readTable(clientsLocal),
      lignes: (await _lignesDe([id]))[id] ?? const [],
      logins: await _loginsDe([ligne.readTable(reservationsLocal)]),
    );
  }

  /// Le `login` de ceux qui ont annulé — UNE requête pour toutes les lignes (un
  /// tableau n'en fait pas une par réservation). C'est la colonne « Par » de
  /// l'onglet Annulations.
  Future<Map<String, String>> _loginsDe(
    Iterable<ReservationsLocalData> reservations,
  ) async {
    final ids = {
      for (final r in reservations)
        if (r.utilisateurAnnulationId != null) r.utilisateurAnnulationId!,
    };
    if (ids.isEmpty) return const {};
    final u = attachedDatabase.utilisateursLocal;
    final lignes = await (select(u)..where((x) => x.id.isIn(ids))).get();
    return {for (final l in lignes) l.id: l.login};
  }

  /// Réservations actives qui touchent la période, sur toutes les unités.
  ///
  /// Le filtre de chevauchement est fait **en SQL**, pas en mémoire : charger
  /// tout l'historique pour n'en garder que deux lignes fonctionne à la
  /// démonstration et s'écroule à la troisième saison d'exploitation.
  ///
  /// Bornes **semi-ouvertes** : `arrivée < finDemandée ET débutDemandé < départ`.
  /// C'est la traduction littérale de `PeriodeSejour.chevauche`, et il ne doit
  /// exister qu'une seule autre écriture de cette condition — celle-là.
  Future<List<Reservation>> chevauchant(
    PeriodeSejour periode, {
    String? exclureReservationId,
  }) async {
    var condition =
        reservationsLocal.statut.equals('annulee').not() &
        reservationsLocal.dateArrivee.isSmallerThanValue(periode.depart) &
        reservationsLocal.dateDepart.isBiggerThanValue(periode.arrivee);

    // Une réservation ne chevauche jamais elle-même. Sans cette exclusion,
    // modifier une réservation sans toucher à ses dates serait refusé — par
    // elle-même.
    if (exclureReservationId != null) {
      condition =
          condition & reservationsLocal.id.equals(exclureReservationId).not();
    }

    final requete = select(reservationsLocal).join([
      innerJoin(
        clientsLocal,
        clientsLocal.id.equalsExp(reservationsLocal.clientId),
      ),
    ])..where(condition);

    final lignes = await requete.get();
    // Sans leurs lignes de service, délibérément : l'appelant est le contrôle
    // de chevauchement, qui ne regarde que les dates et l'unité. Les charger
    // ici ferait une requête de plus à chaque saisie de date, pour une donnée
    // que personne ne lit.
    return lignes
        .map(
          (l) => _versEntite(
            l.readTable(reservationsLocal),
            l.readTable(clientsLocal),
          ),
        )
        .toList();
  }

  /* ================================================================== */
  /* Écriture                                                            */
  /* ================================================================== */

  /// Enregistre la réservation et ses lignes, atomiquement.
  ///
  /// ## Une seule méthode depuis le 14/09/2026 — ZÉRO RÉSEAU
  ///
  /// ⚠ Il y en avait DEUX, et l'histoire mérite d'être gardée. `enregistrer`
  /// écrivait la réservation **et son entrée de file**, tandis que
  /// `enregistrerSansFile` était réservée à ce qui VENAIT du serveur : remettre
  /// en file une donnée descendue l'aurait renvoyée à son expéditeur, en
  /// boucle. La distinction portait donc sur l'ORIGINE de la donnée, et elle
  /// était juste tant qu'une file existait.
  ///
  /// La décision « zéro réseau » l'a vidée de son objet : sans file, les deux
  /// corps étaient devenus identiques au caractère près. Les garder aurait
  /// laissé un nom — « SansFile » — qui se définit par rapport à une chose qui
  /// n'existe plus, et que le premier lecteur venu aurait cherchée en vain.
  ///
  /// Ce qui s'est perdu avec la file, et qu'aucun code ne rattrape ici :
  /// l'idempotence au rejeu, qui tenait à un `uuid_operation` identifiant la
  /// **tentative** — distinct de l'identifiant métier, sans quoi le serveur
  /// rejetait le lot entier en 422.
  Future<void> enregistrer(Reservation r) {
    return transaction(() async {
      final avant = await (select(
        reservationsLocal,
      )..where((x) => x.id.equals(r.id))).getSingleOrNull();
      await into(reservationsLocal).insertOnConflictUpdate(
        ReservationsLocalCompanion.insert(
          id: r.id,
          reference: r.reference,
          clientId: r.clientId,
          uniteId: r.uniteId,
          dateArrivee: r.periode.arrivee,
          dateDepart: r.periode.depart,
          statut: r.statut.code,
          tarifNuit: r.tarifNuit,
          acompte: Value(r.acompte.toDouble()),
          typeClient: Value(r.typeClient?.name),
          canal: Value(r.canal?.code),
          modePaiement: Value(r.modePaiement?.name),
          remiseType: Value(r.remiseType?.name),
          remiseValeur: Value(r.remiseValeur?.toDouble()),
          statutSync: Value(r.statutSynchronisation.code),
          motifRejet: Value(r.motifRejet),
          motifAnnulation: Value(r.motifAnnulation),
          dateCreationLocale: Value(r.creeeLe),
          // Les colonnes de l'annulation (v19) ne sont écrites QUE si l'entité
          // les porte : réécrire une réservation (statut de synchronisation,
          // modification) ne doit jamais effacer ce qu'une annulation a fixé.
          tauxAnnulationCentiemes: r.annulation == null
              ? const Value.absent()
              : Value(r.annulation!.tauxCentiemes),
          montantTotalAnnulationCentimes: r.annulation == null
              ? const Value.absent()
              : Value(r.annulation!.totalCentimes),
          montantCommissionAnnulationCentimes: r.annulation == null
              ? const Value.absent()
              : Value(r.annulation!.commissionCentimes),
          montantRembourseAnnulationCentimes: r.annulation == null
              ? const Value.absent()
              : Value(r.annulation!.rembourseCentimes),
          modeSaisieRemboursement: r.annulation == null
              ? const Value.absent()
              : Value(r.annulation!.modeSaisie),
          dateAnnulation: r.annulation == null
              ? const Value.absent()
              : Value(r.annulation!.date),
          utilisateurAnnulationId: r.annulation == null
              ? const Value.absent()
              : Value(r.annulation!.auteurId),
          ecritureRemboursementId: r.annulation == null
              ? const Value.absent()
              : Value(r.annulation!.ecritureRemboursementId),
        ),
      );
      await _ecrireLignes(r);

      // Lot F6 : un DÉPLACEMENT (chambre, dates) d'une réservation que le
      // serveur détient part, champs changés seulement. Les autres
      // retouches de la fiche (tarif, services, client) restent locales :
      // le serveur n'offre aucune modification générique (écart nommé).
      final avantPeriode = avant == null
          ? null
          : PeriodeSejour(arrivee: avant.dateArrivee, depart: avant.dateDepart);
      if (avant != null &&
          await DocumentsAutresPostes(
            attachedDatabase,
          ).connuDuServeur(TableSynchronisee.reservations, r.id)) {
        await OperationsSyncDao(attachedDatabase).enfiler(
          table: TableSynchronisee.reservations,
          entiteId: r.id,
          type: TypeOperationSync.modification,
          payload: chargeDeplacementReservation(
            uniteId: avant.uniteId == r.uniteId ? null : r.uniteId,
            // Le serveur ne connaît que le JOUR (`Y-m-d`) : la comparaison
            // se fait au jour, jamais à l'instant (un fuseau ou une heure
            // relue ne déplace pas un séjour).
            dateArrivee:
                jourIso(avantPeriode!.arrivee) == jourIso(r.periode.arrivee)
                ? null
                : r.periode.arrivee,
            dateDepart:
                jourIso(avantPeriode.depart) == jourIso(r.periode.depart)
                ? null
                : r.periode.depart,
          ),
        );
      }
    });
  }

  /// Crée la réservation ET la pièce de son acompte, dans la MÊME transaction —
  /// `ReservationService::creer` + `comptabiliserAcompte`.
  ///
  /// Un acompte encaissé (montant > 0, mode espèces, Mobile Money, virement ou
  /// chèque) débite la trésorerie du mode et crédite `4191`. Une pièce refusée
  /// (exercice, compte, journal, centre) refuse la réservation ENTIÈRE : rien
  /// n'est écrit. Trois cas n'ont pas de pièce et c'est un fait, pas un oubli :
  /// acompte nul, mode « crédit », mode absent (voir [tresorerieDeLAcompte]).
  ///
  /// ⚠ **Seule la CRÉATION passe la pièce.** `modifier` ne la repasse pas, au
  /// serveur comme ici (`ReservationService::modifier` ne touche pas à la
  /// comptabilité) : relever ou baisser un acompte en rouvrant la fiche déplace
  /// de l'argent sans écriture. Défaut du SERVEUR répliqué à l'identique, non
  /// corrigé ici — à remonter (D-ticket du lot 6).
  Future<void> creer(Reservation r, {required String auteurId}) async {
    final demande = pieceDeLAcompte(
      reservationId: r.id,
      mode: r.modePaiement,
      acompteCentimes: r.acompte * 100,
      dateIso: formaterDateIso(_maintenant()),
    );
    final moteurComptable = demande == null ? null : await _moteurObligatoire();

    await transaction(() async {
      await enregistrer(r);
      if (demande != null) {
        await moteurComptable!.passerEtValider(demande, auteurId: auteurId);
      }
      // Lot F1 : la réservation part au serveur — création SEULE (le serveur
      // refuse toute modification d'une réservation : l'écriture brute
      // contournait RG-01). La pièce de l'acompte ne part jamais (D246) : le
      // serveur passe la sienne, datée de la date métier.
      await OperationsSyncDao(attachedDatabase).enfiler(
        table: TableSynchronisee.reservations,
        entiteId: r.id,
        type: TypeOperationSync.creation,
        payload: chargeReservation(
          clientId: r.clientId,
          uniteId: r.uniteId,
          dateArrivee: r.periode.arrivee,
          dateDepart: r.periode.depart,
          statut: r.statut.code,
          acompteFrancs: r.acompte,
          tarifNuitFrancs: r.tarifNuit,
          remiseType: (r.remiseType ?? TypeRemise.aucune).name,
          remiseValeur: r.remiseValeur,
          modePaiement: switch (r.modePaiement) {
            null => null,
            ModePaiementReservation.especes => 'especes',
            ModePaiementReservation.mobileMoney => 'mobile_money',
            ModePaiementReservation.virement => 'virement',
            ModePaiementReservation.cheque => 'cheque',
            ModePaiementReservation.credit => 'credit',
          },
        ),
      );
    });
  }

  /// Annule la réservation AVEC commission et remboursement —
  /// `AnnulationReservationService::annuler`, dans le même ordre : réservation
  /// déjà annulée, montant total inconnu, taux hors bornes, remboursement ; puis,
  /// dans UNE transaction, le statut, la pièce du remboursement (s'il y en a un)
  /// et les huit colonnes que l'annulation fixe. Pièce refusée : RIEN n'est écrit.
  ///
  /// [tauxSaisi], [modeRemboursement] et [valeurRemboursement] sont les saisies
  /// BRUTES du formulaire : les refus de forme (obligatoire, nombre, bornes) sont
  /// ceux de [validerSaisieAnnulation], appelée par l'appelant avant ce geste,
  /// comme le composant du serveur valide avant d'appeler le service.
  ///
  /// Le motif d'annulation n'existe pas au serveur : la colonne
  /// `motif_annulation` reste pour les annulations d'AVANT la v19, et ce geste ne
  /// l'écrit pas.
  Future<Reservation> annulerAvecConditions(
    String id, {
    required String tauxSaisi,
    required String modeRemboursement,
    required String valeurRemboursement,
    required String auteurId,
  }) async {
    // Pré-lecture NON autoritaire, hors transaction, pour la seule chose qui ne
    // peut pas se résoudre à l'intérieur : le moteur arrive par un résolveur
    // asynchrone (installation du référentiel). Un remboursement n'existe que si
    // la réservation porte un acompte. Sans résolveur, rien n'est exigé ici : le
    // refus de forme garde sa priorité et le `StateError` tombe à sa place.
    final apercu = await parId(id);
    // Q3 (lot F6) : la réservation d'un autre poste ne s'annule que par
    // l'administration ou le comptable — la règle du serveur.
    if (apercu != null &&
        !await DocumentsAutresPostes(
          attachedDatabase,
        ).peutAnnuler('reservations', id, auteurId)) {
      throw const RefusAnnulation(
        DocumentsAutresPostes.refus,
        champ: 'annulation',
      );
    }
    final resolveur = moteur;
    final moteurPrealable =
        (apercu != null && apercu.acompte > 0 && resolveur != null)
        ? await resolveur()
        : null;

    final quand = _maintenant();

    await transaction(() async {
      // **Lecture et validation DANS la transaction d'écriture.** Lues avant,
      // deux gestes concurrents voyaient tous deux « pas encore annulée » et
      // passaient chacun leur pièce de remboursement : l'argent sorti deux fois
      // pour une seule annulation. La transaction sérialise les écritures du
      // poste : le second geste relit une réservation déjà annulée et est
      // refusé (`RefusAnnulation`, « déjà annulée ») avant d'écrire quoi que ce soit.
      final existante = await parId(id);
      if (existante == null) throw ReservationIntrouvable(id);

      final resultat = calculerAnnulation(
        dejaAnnulee: existante.statut == StatutReservation.annulee,
        totalCentimes: montantTotalCentimes(
          tarifNuit: existante.tarifNuit,
          aDesLignes: existante.lignes.isNotEmpty,
          totalDuRecapitulatifFrancs: existante.recapitulatif.total,
        ),
        acompteCentimes: existante.acompte * 100,
        tauxSaisi: tauxSaisi,
        modeSaisi: modeRemboursement,
        valeurSaisie: valeurRemboursement,
      );

      final moteurComptable = resultat.rembourseCentimes > 0
          ? (moteurPrealable ?? await _moteurObligatoire())
          : null;

      String? ecritureId;

      // Le statut d'abord (`ReservationService::annuler`), la pièce ensuite : une
      // pièce refusée annule tout, le statut compris.
      await (update(reservationsLocal)..where((r) => r.id.equals(id))).write(
        ReservationsLocalCompanion(
          statut: Value(StatutReservation.annulee.code),
          // `local` : cette ligne vit sur ce poste et nulle part ailleurs.
          statutSync: Value(StatutSynchronisation.local.code),
        ),
      );

      if (moteurComptable != null) {
        final client = await (select(
          clientsLocal,
        )..where((c) => c.id.equals(existante.clientId))).getSingleOrNull();
        // `trim($client->prenom . ' ' . $client->nom)` — l'ORDRE du serveur
        // (prénom d'abord), pas celui de `Reservation.clientNom`.
        final nomComplet = client == null
            ? existante.id
            : '${client.prenom ?? ''} ${client.nom}'.trim();

        final piece = await moteurComptable.passerEtValider(
          pieceDuRemboursement(
            client: nomComplet,
            rembourseCentimes: resultat.rembourseCentimes,
            dateIso: formaterDateIso(quand),
          ),
          auteurId: auteurId,
        );
        // La ligne DÉBIT (4191) : c'est elle que la réservation désigne.
        ecritureId = piece.firstWhere((e) => e.debitCentimes > 0).id;
      }

      await (update(reservationsLocal)..where((r) => r.id.equals(id))).write(
        ReservationsLocalCompanion(
          tauxAnnulationCentiemes: Value(resultat.tauxCentiemes),
          montantTotalAnnulationCentimes: Value(resultat.totalCentimes),
          montantCommissionAnnulationCentimes: Value(
            resultat.commissionCentimes,
          ),
          montantRembourseAnnulationCentimes: Value(resultat.rembourseCentimes),
          modeSaisieRemboursement: Value(resultat.modeSaisie),
          dateAnnulation: Value(quand),
          utilisateurAnnulationId: Value(auteurId),
          ecritureRemboursementId: Value(ecritureId),
        ),
      );

      // Lot F6 : l'annulation part (si le serveur détient la réservation),
      // avec ce que CE poste a appliqué ; la pièce, elle, ne part jamais.
      if (await DocumentsAutresPostes(
        attachedDatabase,
      ).connuDuServeur(TableSynchronisee.reservations, id)) {
        await OperationsSyncDao(attachedDatabase).enfiler(
          table: TableSynchronisee.reservations,
          entiteId: id,
          type: TypeOperationSync.modification,
          payload: chargeAnnulationReservation(
            tauxCentiemes: resultat.tauxCentiemes,
            rembourseCentimes: resultat.rembourseCentimes,
          ),
        );
      }
    });

    return (await parId(id))!;
  }

  /// Réécrit les lignes de service de la réservation.
  ///
  /// **Retrait puis réécriture**, jamais une fusion ligne à ligne : une ligne
  /// supprimée par l'utilisateur doit disparaître, et une fusion la laisserait
  /// vivre. L'opération est appelée dans la transaction de l'appelant — les
  /// lignes et leur réservation n'existent jamais l'une sans l'autre.
  ///
  /// Les réservations venues du serveur n'ont pas de ligne : `r.lignes` est
  /// alors vide, et le retrait seul s'applique. Ce n'est PAS une perte
  /// silencieuse — le serveur ne connaît pas les lignes (voir `_versPayload`),
  /// donc aucune réservation poussée puis relue n'en a jamais porté.
  Future<void> _ecrireLignes(Reservation r) async {
    await (delete(
      lignesReservationLocal,
    )..where((l) => l.reservationId.equals(r.id))).go();

    var ordre = 0;
    for (final ligne in r.lignes) {
      await into(lignesReservationLocal).insert(
        LignesReservationLocalCompanion.insert(
          id: ligne.id,
          reservationId: r.id,
          service: ligne.service.cle,
          itemId: ligne.itemId,
          libelle: ligne.libelle,
          prixUnitaire: ligne.prixUnitaire,
          quantite: ligne.quantite,
          ordre: ordre++,
        ),
      );
    }
  }

  /// Les lignes de plusieurs réservations, en **une** requête.
  ///
  /// Une requête par réservation ferait N+1 appels sur la liste : imperceptible
  /// à la démonstration, sensible à la troisième saison d'exploitation.
  Future<Map<String, List<LigneService>>> _lignesDe(
    Iterable<String> reservationIds,
  ) async {
    if (reservationIds.isEmpty) return const {};

    final lignes =
        await (select(lignesReservationLocal)
              ..where((l) => l.reservationId.isIn(reservationIds))
              ..orderBy([(l) => OrderingTerm.asc(l.ordre)]))
            .get();

    final parReservation = <String, List<LigneService>>{};
    for (final l in lignes) {
      final service = ServiceReservation.parCle(l.service);
      // Un service inconnu vient d'une version plus récente de l'application.
      // La ligne est ÉCARTÉE de l'affichage plutôt que rangée dans un service
      // arbitraire — mais elle reste en base : la ranger ailleurs fausserait
      // un sous-total, la supprimer perdrait une saisie.
      if (service == null) continue;
      (parReservation[l.reservationId] ??= []).add(
        LigneService(
          id: l.id,
          service: service,
          itemId: l.itemId,
          libelle: l.libelle,
          prixUnitaire: l.prixUnitaire,
          quantite: l.quantite,
        ),
      );
    }
    return parReservation;
  }

  /// Met à jour le seul statut de synchronisation, sans toucher au métier.
  ///
  /// Utilisé au retour du serveur. Passer par `enregistrer` réécrirait la
  /// réservation entière et remettrait une entrée en file — donc la
  /// renverrait, indéfiniment.
  Future<void> majStatutSync(
    String id,
    StatutSynchronisation statut, {
    String? motifRejet,
  }) {
    return (update(reservationsLocal)..where((r) => r.id.equals(id))).write(
      ReservationsLocalCompanion(
        statutSync: Value(statut.code),
        motifRejet: Value(motifRejet),
      ),
    );
  }

  /* ================================================================== */
  /* Correspondances                                                     */
  /* ================================================================== */

  Reservation _versEntite(
    ReservationsLocalData d,
    ClientsLocalData client, {
    List<LigneService> lignes = const [],
    Map<String, String> logins = const {},
  }) {
    return Reservation(
      id: d.id,
      reference: d.reference,
      clientId: d.clientId,
      clientNom: [
        client.nom,
        client.prenom,
      ].whereType<String>().join(' ').trim(),
      uniteId: d.uniteId,
      periode: PeriodeSejour(arrivee: d.dateArrivee, depart: d.dateDepart),
      tarifNuit: d.tarifNuit,
      statut: StatutReservation.depuisCode(d.statut),
      statutSynchronisation: StatutSynchronisation.depuisCode(d.statutSync),
      creeeLe: d.dateCreationLocale,
      acompte: d.acompte.round(),
      // La fiche du maitre. `_parCode` rend `null` plutot qu'un repli : une
      // valeur absente doit RESTER absente. La remplacer par « Physique »
      // inventerait une origine, et l'analyse par canal deviendrait fausse.
      //
      // ⚠ La colonne porte le CODE, jamais le libelle affiche. Un libelle est
      // du texte d'interface : le jour ou « Agence partenaire » devient
      // « Agence », les lignes deja ecrites cessent d'etre relues et leur type
      // de client disparait, sans erreur ni trace. `name` et le `code` du
      // maitre sont, eux, des identifiants.
      typeClient: _parCode(TypeClient.values, d.typeClient, (t) => t.name),
      canal: _parCode(CanalReservation.values, d.canal, (c) => c.code),
      modePaiement: _parCode(
        ModePaiementReservation.values,
        d.modePaiement,
        (m) => m.name,
      ),
      remiseType: _parCode(TypeRemise.values, d.remiseType, (r) => r.name),
      remiseValeur: d.remiseValeur,
      motifRejet: d.motifRejet,
      motifAnnulation: d.motifAnnulation,
      annulation: _annulationDe(d, logins),
      lignes: lignes,
    );
  }

  /// Ce que l'annulation a FIXÉ, ou `null` : une réservation jamais annulée, et
  /// une annulation d'AVANT la v19, n'ont ni taux ni montants — jamais un zéro.
  AnnulationEnregistree? _annulationDe(
    ReservationsLocalData d,
    Map<String, String> logins,
  ) {
    final taux = d.tauxAnnulationCentiemes;
    final total = d.montantTotalAnnulationCentimes;
    final commission = d.montantCommissionAnnulationCentimes;
    final rembourse = d.montantRembourseAnnulationCentimes;
    final mode = d.modeSaisieRemboursement;
    final date = d.dateAnnulation;
    if (taux == null ||
        total == null ||
        commission == null ||
        rembourse == null ||
        mode == null ||
        date == null) {
      return null;
    }
    return AnnulationEnregistree(
      tauxCentiemes: taux,
      totalCentimes: total,
      commissionCentimes: commission,
      rembourseCentimes: rembourse,
      modeSaisie: mode,
      date: date,
      auteurId: d.utilisateurAnnulationId,
      auteurLogin: logins[d.utilisateurAnnulationId],
      ecritureRemboursementId: d.ecritureRemboursementId,
    );
  }

  // ⚠ `_versPayload` et `_dateSeule` ONT ÉTÉ RETIRÉS le 14/09/2026, avec la
  // file de synchronisation qui était leur seule appelante (décision « zéro
  // réseau »). Ce qu'ils disaient mérite d'être gardé ici, parce que le jour
  // où un serveur reviendra, les deux pièges reviendront avec lui :
  //
  //  1. La fiche du maître (canal, mode de paiement, remise, type de client)
  //     n'était PAS envoyée : le schéma serveur ne porte aucune de ces
  //     colonnes (PA-29). Les envoyer faisait rejeter le lot à la validation,
  //     ou — pire — les faisait accepter puis jeter en silence.
  //  2. Les dates partaient en **ISO 8601 date seule**. L'heure n'a aucun sens
  //     pour une nuitée, et l'envoyer exposait à un décalage de fuseau qui
  //     déplaçait un séjour d'un jour.
  //
  // Garder le code mort aurait été pire que cette note : un lecteur l'aurait
  // pris pour un chemin vivant, et aurait cherché qui l'appelle.
}

/// Relit une valeur d'enumeration depuis son code persiste.
///
/// Rend `null` — jamais un repli — quand la colonne est vide OU quand le code
/// est inconnu. Un repli sur la premiere valeur affirmerait un choix que
/// personne n'a fait, et un code inconnu signale une ecriture par une autre
/// version : le ranger silencieusement fausserait l'analyse sans un mot.
T? _parCode<T>(List<T> valeurs, String? code, String Function(T) cle) {
  if (code == null) return null;
  for (final v in valeurs) {
    if (cle(v) == code) return v;
  }
  return null;
}
