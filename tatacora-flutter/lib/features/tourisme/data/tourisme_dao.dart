import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../synchronisation/data/operations_sync_dao.dart';
import '../../synchronisation/domain/charges_synchronisation.dart';
import '../../synchronisation/domain/operation_sync.dart';
import '../domain/departs.dart';
import '../domain/entities/circuit.dart';
import '../domain/entities/guide.dart';
import '../domain/entities/reservation_tour.dart';

/// M9 — l'accès aux trois tables locales du Tourisme.
///
/// ## Tout se lit en LOCAL, et tout part avec la synchronisation (relu le 27/10/2026)
///
/// ⚠ Cet en-tête disait « rien ne part » et que ces tables n'avaient « aucune
/// descente » : c'est FAUX depuis le lot F4 (17/10/2026). `circuits`, `guides`
/// et `reservations_tour` sont au registre [TableSynchronisee] ET descendent
/// (`AligneurDocuments._circuit`, `_guide`, `_reservationTour`). Chaque geste
/// d'écriture ci-dessous enfile son opération DANS sa transaction. Deux
/// conséquences restent tenues :
///
/// 1. `statutSync` est écrit à [statutSyncLocal] et **jamais affiché**. Le
///    schéma lui donne pour défaut `en_attente_synchronisation` : c'est le
///    piège de `MouvementsStockLocal` (PA-134), un statut qui décrirait une
///    attente sans fin. Ce qui attend, c'est la FILE d'envoi qui le dit ;
/// 2. « Synchronisé » ne se dit que du confirmé : l'écran dit « enregistré sur
///    ce poste ».
///
/// ## Qui écrit ces tables — la question des deux moitiés (piège 11)
///
/// Écriture de saisie : ce DAO, seul. Descente : `AligneurCatalogue` /
/// `AligneurDocuments`, qui n'enfilent jamais. Un guide saisi ici part au
/// serveur (`GestionnaireGuides`) ; un guide du serveur descend ici.
///
/// ## Le verrou pessimiste est au SERVEUR, pas ici
///
/// RG-13 se tranche sous `lockForUpdate()` côté Laravel. SQLite n'a qu'un seul
/// écrivain à la fois, et la vérification est faite **dans la transaction qui
/// insère** : cela protège ce poste. Cela ne protège pas deux postes hors
/// ligne l'un de l'autre : le serveur arbitre à la réception
/// (`GestionnaireReservationsTour`), même famille que RG-01.
///
/// @see EF-M9-01 Catalogue de circuits
/// @see EF-M9-03 Réservation avec affectation de guide
/// @see EF-M9-04 Capacité maximale par circuit
/// @see RG-13 Capacité cumulée sur le départ
/// @see UC-39 Réaffecter un guide
class TourismeDao extends DatabaseAccessor<AppDatabase> {
  TourismeDao(super.db, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final Uuid _uuid;

  /// La valeur écrite dans `statutSync`, et qui n'est **jamais affichée**.
  ///
  /// Le défaut du schéma (`en_attente_synchronisation`) annoncerait une
  /// attente qui ne finira pas : ces tables ne partent nulle part.
  static const String statutSyncLocal = 'local';

  /* ------------------------------------------------------------ lectures */

  /// Le catalogue, dans l'ordre du maître (`orderBy('nom')`).
  Future<List<Circuit>> circuits() async {
    final lignes = await (select(
      attachedDatabase.circuitsLocal,
    )..orderBy([(c) => OrderingTerm.asc(c.nom)])).get();
    return lignes.map(_versCircuit).toList(growable: false);
  }

  Future<List<Guide>> guides() async {
    final lignes = await (select(
      attachedDatabase.guidesLocal,
    )..orderBy([(g) => OrderingTerm.asc(g.nom)])).get();
    return lignes
        .map(
          (g) => Guide(
            id: g.id,
            nom: g.nom,
            zoneCompetence: g.zoneCompetence,
            certification: g.certification,
            tarifJourFrancs: g.tarifJour,
          ),
        )
        .toList(growable: false);
  }

  /// Les lignes de réservation d'une fenêtre de dates.
  ///
  /// ## Les lignes ILLISIBLES sont comptées, jamais avalées
  ///
  /// Une ligne dont le `statut` n'appartient pas au registre fermé
  /// ([StatutReservationTour]) est écartée **et comptée**. Lui prêter
  /// « réservée » par défaut la ferait compter comme une place vendue et
  /// fausserait la capacité d'un départ ; la jeter en silence ferait
  /// disparaître une réservation payée sans que personne ne le sache. Le
  /// compte remonte à l'écran (même discipline que `BilanAlignement`, PA-127).
  Future<({List<ReservationTour> reservations, int illisibles})>
  reservationsSurFenetre(DateTime debut, DateTime fin) async {
    final borneBasse = jourDe(debut);
    // La borne haute est INCLUSIVE au maître (`whereBetween` sur des dates) :
    // on prend le jour entier, sans quoi un départ du dernier jour de la
    // fenêtre disparaîtrait de la grille.
    final borneHaute = jourDe(fin).add(const Duration(days: 1));

    final lignes =
        await (select(attachedDatabase.reservationsTourLocal)
              ..where(
                (r) =>
                    r.dateCircuit.isBiggerOrEqualValue(borneBasse) &
                    r.dateCircuit.isSmallerThanValue(borneHaute),
              )
              ..orderBy([(r) => OrderingTerm.desc(r.dateCircuit)]))
            .get();

    if (lignes.isEmpty) {
      return (reservations: const <ReservationTour>[], illisibles: 0);
    }

    final circuitsParId = {for (final c in await circuits()) c.id: c};
    final guidesParId = {for (final g in await guides()) g.id: g};
    final clients = {
      for (final c in await select(attachedDatabase.clientsLocal).get())
        c.id: c,
    };

    final reservations = <ReservationTour>[];
    var illisibles = 0;

    for (final l in lignes) {
      final statut = StatutReservationTour.depuisCle(l.statut);
      final circuit = circuitsParId[l.circuitId];
      final client = clients[l.clientId];
      final guide = guidesParId[l.guideId];

      // Les trois clés étrangères sont NOT NULL et `PRAGMA foreign_keys` est
      // actif : une référence manquante ne peut venir que d'une base abîmée.
      // Elle est comptée comme illisible, pas devinée.
      if (statut == null ||
          circuit == null ||
          client == null ||
          guide == null) {
        illisibles++;
        continue;
      }

      reservations.add(
        ReservationTour(
          id: l.id,
          circuitId: circuit.id,
          circuitNom: circuit.nom,
          prixUnitaire: circuit.prix,
          capaciteCircuit: circuit.capaciteMax,
          dureeCircuit: circuit.duree,
          clientId: client.id,
          clientNom: [
            client.nom,
            client.prenom,
          ].whereType<String>().join(' ').trim(),
          clientTelephone: client.telephone,
          guideId: guide.id,
          guideNom: guide.nom,
          dateCircuit: jourDe(l.dateCircuit),
          nbParticipants: l.nbParticipants,
          statut: statut,
        ),
      );
    }

    return (reservations: reservations, illisibles: illisibles);
  }

  /// Les places restantes d'un départ — **calculées**, jamais une valeur
  /// d'échappement.
  ///
  /// Le lot PWA précédent posait `capaciteRestanteResa = 99` en édition, ce
  /// qui est une sur-réservation en puissance. La modale affiche ce que cette
  /// méthode calcule, et c'est l'écriture qui refuse.
  Future<int?> placesRestantes(String circuitId, DateTime date) async {
    final circuit = await _circuitOuNull(circuitId);
    if (circuit == null) return null;

    final vendues = await _placesVendues(circuitId, jourDe(date));
    return placesRestantesPour(
      capacite: circuit.capaciteMax,
      dejaVendues: vendues,
    );
  }

  /// Le guide DÉJÀ EN PLACE sur un départ, ou `null` si le départ n'existe pas
  /// encore.
  ///
  /// Une seule implémentation, partagée par la modale de réservation et celle
  /// de réaffectation : deux lectures de la même règle finiraient par diverger.
  Future<Guide?> guideDuDepart(String circuitId, DateTime date) async {
    final lignes = await _lignesActives(circuitId, jourDe(date));
    if (lignes.isEmpty) return null;

    final tous = await guides();
    for (final g in tous) {
      if (g.id == lignes.first.guideId) return g;
    }
    return null;
  }

  /* ------------------------------------------------------------ écritures */

  /// Réserve des places sur un départ — **le geste qui CRÉE le départ** quand
  /// c'est la première ligne du couple (circuit, date).
  ///
  /// Trois refus, tous dans la même transaction que l'insertion :
  ///
  /// - **RG-13**, capacité cumulée sur le départ ;
  /// - le **guide du départ** est imposé : un départ a UN guide, celui de sa
  ///   première réservation. Les groupes suivants le reprennent, sinon chacun
  ///   arriverait avec le sien ;
  /// - un guide ne peut pas conduire **deux circuits différents** le même
  ///   jour (règle dérivée, tracée en PA-51 : il ne peut physiquement pas).
  Future<ReservationTour> reserver({
    required String circuitId,
    required String clientId,
    required String guideId,
    required DateTime dateCircuit,
    required int nbParticipants,
  }) async {
    final jour = jourDe(dateCircuit);

    return transaction(() async {
      final circuit = await _circuitOuNull(circuitId);
      if (circuit == null) {
        throw const RefusTourisme(MessagesTourisme.circuitInexistant);
      }
      if (!await _guideExiste(guideId)) {
        throw const RefusTourisme(MessagesTourisme.guideInexistant);
      }
      if (!await _clientExiste(clientId)) {
        throw const RefusTourisme(MessagesTourisme.clientInexistant);
      }

      final lignes = await _lignesActives(circuitId, jour);
      final dejaVendues = lignes.fold<int>(
        0,
        (somme, l) => somme + l.nbParticipants,
      );

      final refus = refusDeCapaciteCumulee(
        capacite: circuit.capaciteMax,
        dejaVendues: dejaVendues,
        demandes: nbParticipants,
      );
      if (refus != null) throw RefusTourisme(refus);

      if (lignes.isNotEmpty && lignes.first.guideId != guideId) {
        throw const RefusTourisme(MessagesTourisme.guideDuDepartImpose);
      }

      await _verifierGuideLibre(
        guideId: guideId,
        jour: jour,
        circuitId: circuitId,
      );

      final id = _uuid.v4();
      await into(attachedDatabase.reservationsTourLocal).insert(
        ReservationsTourLocalCompanion.insert(
          id: id,
          circuitId: circuitId,
          clientId: clientId,
          guideId: guideId,
          dateCircuit: jour,
          nbParticipants: nbParticipants,
          statut: StatutReservationTour.reservee.cle,
          statutSync: const Value(statutSyncLocal),
        ),
      );
      // Lot F4 : la réservation part au serveur, qui arbitre capacité et
      // guide entre les postes (`GestionnaireReservationsTour`).
      await _file.enfiler(
        table: TableSynchronisee.reservationsTour,
        entiteId: id,
        type: TypeOperationSync.creation,
        payload: chargeReservationTour(
          circuitId: circuitId,
          clientId: clientId,
          guideId: guideId,
          dateCircuit: jour,
          nbParticipants: nbParticipants,
        ),
      );

      final guide = await _guideOuNull(guideId);
      final client = await _clientOuNull(clientId);

      return ReservationTour(
        id: id,
        circuitId: circuit.id,
        circuitNom: circuit.nom,
        prixUnitaire: circuit.prix,
        capaciteCircuit: circuit.capaciteMax,
        dureeCircuit: circuit.duree,
        clientId: clientId,
        clientNom: client == null
            ? ''
            : [client.nom, client.prenom].whereType<String>().join(' ').trim(),
        clientTelephone: client?.telephone,
        guideId: guideId,
        guideNom: guide?.nom ?? '',
        dateCircuit: jour,
        nbParticipants: nbParticipants,
        statut: StatutReservationTour.reservee,
      );
    });
  }

  /// UC-39 — **RÉ**affecte le guide de TOUTES les lignes actives du départ.
  ///
  /// Jamais ligne par ligne : un départ a un guide, et laisser deux groupes du
  /// même départ partir avec deux guides différents est précisément ce que le
  /// contrôle de saisie empêche. Rend le nombre de lignes réaffectées.
  Future<int> reaffecterGuide({
    required String circuitId,
    required DateTime date,
    required String nouveauGuideId,
  }) async {
    final jour = jourDe(date);

    return transaction(() async {
      if (!await _guideExiste(nouveauGuideId)) {
        throw const RefusTourisme(MessagesTourisme.guideInexistant);
      }

      final lignes = await _lignesActives(circuitId, jour);
      if (lignes.isEmpty) {
        throw const RefusTourisme(MessagesTourisme.departSansReservation);
      }

      // Une prestation clôturée ne change plus de guide : le départ est passé.
      final cloturee = StatutReservationTour.terminee.cle;
      if (lignes.any((l) => l.statut == cloturee)) {
        throw const RefusTourisme(MessagesTourisme.affectationImpossible);
      }

      await _verifierGuideLibre(
        guideId: nouveauGuideId,
        jour: jour,
        circuitId: circuitId,
      );

      for (final l in lignes) {
        await (update(
          attachedDatabase.reservationsTourLocal,
        )..where((r) => r.id.equals(l.id))).write(
          ReservationsTourLocalCompanion(guideId: Value(nouveauGuideId)),
        );
        await _file.enfiler(
          table: TableSynchronisee.reservationsTour,
          entiteId: l.id,
          type: TypeOperationSync.modification,
          payload: {'guide_id': nouveauGuideId},
        );
      }

      return lignes.length;
    });
  }

  /// Annule UNE réservation — `statut = 'annulee'`, **aucune suppression**.
  ///
  /// La place est libérée au départ dès l'écriture, puisque la capacité se
  /// calcule sur les lignes actives. Une prestation clôturée ne s'annule plus.
  Future<void> annulerReservation(String id) async {
    await transaction(() async {
      final ligne = await (select(
        attachedDatabase.reservationsTourLocal,
      )..where((r) => r.id.equals(id))).getSingleOrNull();

      if (ligne == null) {
        throw const RefusTourisme(MessagesTourisme.departSansReservation);
      }
      if (ligne.statut == StatutReservationTour.terminee.cle) {
        throw const RefusTourisme(MessagesTourisme.annulationApresCloture);
      }

      await (update(
        attachedDatabase.reservationsTourLocal,
      )..where((r) => r.id.equals(id))).write(
        ReservationsTourLocalCompanion(
          statut: Value(StatutReservationTour.annulee.cle),
        ),
      );
      await _file.enfiler(
        table: TableSynchronisee.reservationsTour,
        entiteId: id,
        type: TypeOperationSync.modification,
        payload: {'statut': StatutReservationTour.annulee.cle},
      );
    });
  }

  /// Annule un DÉPART entier : toutes ses lignes actives passent en annulation.
  ///
  /// Rend le nombre de réservations annulées — le maître l'affiche dans son
  /// message de confirmation, et le nombre de places concernées est ce qui
  /// oblige à prévenir les clients.
  Future<int> annulerDepart({
    required String circuitId,
    required DateTime date,
  }) async {
    final jour = jourDe(date);

    return transaction(() async {
      final lignes = await _lignesActives(circuitId, jour);
      if (lignes.isEmpty) {
        throw const RefusTourisme(MessagesTourisme.departSansReservation);
      }
      if (lignes.any((l) => l.statut == StatutReservationTour.terminee.cle)) {
        throw const RefusTourisme(MessagesTourisme.annulationApresCloture);
      }

      for (final l in lignes) {
        await (update(
          attachedDatabase.reservationsTourLocal,
        )..where((r) => r.id.equals(l.id))).write(
          ReservationsTourLocalCompanion(
            statut: Value(StatutReservationTour.annulee.cle),
          ),
        );
        await _file.enfiler(
          table: TableSynchronisee.reservationsTour,
          entiteId: l.id,
          type: TypeOperationSync.modification,
          payload: {'statut': StatutReservationTour.annulee.cle},
        );
      }

      return lignes.length;
    });
  }

  /// Crée ou met à jour une prestation du catalogue (EF-M9-01).
  ///
  /// La prestation PART au serveur (lot F4 : catalogue fusionné sur le nom,
  /// dernier écrit gagnant) et descend aux autres postes. Aucune suppression
  /// n'est exposée : une prestation ne se supprime pas (RG-02), elle cesse d'être
  /// proposée.
  ///
  /// La capacité est celle de la fiche : c'est elle que RG-13 contrôlera.
  Future<Circuit> enregistrerCircuit({
    String? id,
    required String nom,
    required String theme,
    required String zone,
    required int prix,
    required int capaciteMax,
    String? duree,
  }) async {
    if (nom.trim().isEmpty) {
      throw const RefusTourisme(
        'L\'intitulé de la prestation est obligatoire.',
      );
    }
    // Le registre du serveur est en minuscules : « Nature » saisi ici serait
    // rejeté à la synchronisation. La casse est donc ramenée à la sienne.
    final themeNet = theme.trim().toLowerCase();
    if (!themesCircuit.contains(themeNet)) {
      throw RefusTourisme(
        'Le thème « $theme » n\'est pas un thème du catalogue : '
        '${themesCircuit.map(libelleTheme).join(', ')}.',
      );
    }
    if (capaciteMax < 1) {
      throw const RefusTourisme(
        'La capacité maximale doit valoir au moins une place : c\'est elle '
        'que le contrôle de capacité oppose aux réservations.',
      );
    }
    if (prix < 0) {
      throw const RefusTourisme(
        'Le prix par personne ne peut pas être négatif.',
      );
    }

    final identifiant = id ?? _uuid.v4();

    // Texte LIBRE (PA-51) : rien à valider, mais une saisie vide devient
    // `null` et non `''` — les deux se liraient « indéterminée », et deux
    // façons d'écrire la même chose finissent par diverger.
    final dureeNette = duree?.trim();
    final dureeFinale = (dureeNette == null || dureeNette.isEmpty)
        ? null
        : dureeNette;

    await transaction(() async {
      final existant = await _circuitOuNull(identifiant) != null;
      await into(attachedDatabase.circuitsLocal).insertOnConflictUpdate(
        CircuitsLocalCompanion.insert(
          id: identifiant,
          nom: nom.trim(),
          theme: themeNet,
          zone: zone.trim(),
          // La colonne est un `REAL` au schéma ; le domaine ne manipule que
          // des entiers. La conversion a lieu ici, une fois, dans les deux
          // sens.
          prix: prix.toDouble(),
          capaciteMax: capaciteMax,
          duree: Value(dureeFinale),
        ),
      );
      // Lot F4 : le circuit part au serveur (catalogue : fusion sur le nom,
      // dernier écrit gagnant).
      await _file.enfiler(
        table: TableSynchronisee.circuits,
        entiteId: identifiant,
        type: existant
            ? TypeOperationSync.modification
            : TypeOperationSync.creation,
        payload: chargeCircuit(
          nom: nom.trim(),
          theme: themeNet,
          zone: zone.trim(),
          prixFrancs: prix,
          capaciteMax: capaciteMax,
          duree: dureeFinale,
        ),
      );
    });

    return Circuit(
      id: identifiant,
      nom: nom.trim(),
      theme: themeNet,
      zone: zone.trim(),
      prix: prix,
      capaciteMax: capaciteMax,
      duree: dureeFinale,
    );
  }

  /// Enregistre un guide sur ce poste.
  ///
  /// Aucune route de l'API n'expose le référentiel des guides : sans ce
  /// chemin, `guides_local` resterait vide pour toujours et **aucune
  /// réservation ne pourrait être prise** — `guide_id` est NOT NULL.
  Future<Guide> enregistrerGuide({
    String? id,
    required String nom,
    String? zoneCompetence,
    String? certification,
    int? tarifJourFrancs,
  }) async {
    if (nom.trim().isEmpty) {
      throw const RefusTourisme('Le nom du guide est obligatoire.');
    }
    if (tarifJourFrancs != null && tarifJourFrancs < 0) {
      throw const RefusTourisme(
        'Le tarif journalier ne peut pas être négatif.',
      );
    }

    final identifiant = id ?? _uuid.v4();
    final zone = _texteOuNull(zoneCompetence);
    final certif = _texteOuNull(certification);

    await transaction(() async {
      final existant = await _guideExiste(identifiant);

      // Un homonyme est refusé comme au serveur : la synchronisation fusionne
      // les guides sur le nom, deux fiches de même nom y seraient confondues.
      if (!existant) {
        final homonymes = await (select(
          attachedDatabase.guidesLocal,
        )..where((g) => g.nom.lower().equals(nom.trim().toLowerCase()))).get();
        if (homonymes.isNotEmpty) {
          throw RefusTourisme(
            'Un guide nommé « ${nom.trim()} » existe déjà au référentiel.',
          );
        }
      }

      // Depuis la v41 la certification et le tarif journalier sont RANGÉS ici (ils
      // partaient déjà au serveur sans l'être sur le poste). `null` : champ non
      // soumis, la colonne reste telle quelle ; la certification vide l'efface.
      final avant = existant
          ? await (select(
              attachedDatabase.guidesLocal,
            )..where((g) => g.id.equals(identifiant))).getSingleOrNull()
          : null;
      await into(attachedDatabase.guidesLocal).insertOnConflictUpdate(
        GuidesLocalCompanion.insert(
          id: identifiant,
          nom: nom.trim(),
          zoneCompetence: Value(zone),
          certification: Value(
            certification == null ? avant?.certification : certif,
          ),
          tarifJour: Value(tarifJourFrancs ?? avant?.tarifJour),
        ),
      );
      await _file.enfiler(
        table: TableSynchronisee.guides,
        entiteId: identifiant,
        type: existant
            ? TypeOperationSync.modification
            : TypeOperationSync.creation,
        payload: chargeGuide(
          nom: nom.trim(),
          zoneCompetence: zone,
          certification: certif,
          tarifJourFrancs: tarifJourFrancs,
        ),
      );
    });

    final range = await (select(
      attachedDatabase.guidesLocal,
    )..where((g) => g.id.equals(identifiant))).getSingle();
    return Guide(
      id: identifiant,
      nom: nom.trim(),
      zoneCompetence: zone,
      certification: range.certification,
      tarifJourFrancs: range.tarifJour,
    );
  }

  /// Une saisie vide devient `null` : deux façons d'écrire « rien » finissent
  /// par diverger.
  String? _texteOuNull(String? valeur) {
    final net = valeur?.trim();
    return (net == null || net.isEmpty) ? null : net;
  }

  /* --------------------------------------------------------------- privé */

  /// La file d'envoi (lot F4) — appelée dans la transaction de chaque geste.
  OperationsSyncDao get _file => OperationsSyncDao(attachedDatabase);

  Circuit _versCircuit(CircuitsLocalData c) => Circuit(
    id: c.id,
    nom: c.nom,
    theme: c.theme,
    zone: c.zone,
    prix: c.prix.round(),
    capaciteMax: c.capaciteMax,
    // LUE depuis la v10 (14/09/2026). ⚠ Cette ligne rendait `null` en dur, et
    // sa raison — « la colonne n'existe pas » — a cessé d'être vraie le jour
    // même où la colonne est arrivée : six messages d'écran la répétaient
    // encore. `null` veut désormais dire « aucune durée renseignée », ce que
    // la règle traite comme indéterminée, exactement comme au serveur.
    duree: c.duree,
  );

  Future<Circuit?> _circuitOuNull(String id) async {
    final ligne = await (select(
      attachedDatabase.circuitsLocal,
    )..where((c) => c.id.equals(id))).getSingleOrNull();
    return ligne == null ? null : _versCircuit(ligne);
  }

  Future<GuidesLocalData?> _guideOuNull(String id) => (select(
    attachedDatabase.guidesLocal,
  )..where((g) => g.id.equals(id))).getSingleOrNull();

  Future<ClientsLocalData?> _clientOuNull(String id) => (select(
    attachedDatabase.clientsLocal,
  )..where((c) => c.id.equals(id))).getSingleOrNull();

  Future<bool> _guideExiste(String id) async => await _guideOuNull(id) != null;

  Future<bool> _clientExiste(String id) async =>
      await _clientOuNull(id) != null;

  /// Les lignes ACTIVES d'un départ — celles qui consomment une place.
  ///
  /// `statut != 'annulee'` : c'est le seul statut inactif du serveur
  /// (`STATUTS_INACTIFS`). Une prestation clôturée a bien eu lieu, elle
  /// continue d'occuper ses places.
  Future<List<ReservationsTourLocalData>> _lignesActives(
    String circuitId,
    DateTime jour,
  ) {
    return (select(attachedDatabase.reservationsTourLocal)..where(
          (r) =>
              r.circuitId.equals(circuitId) &
              r.dateCircuit.equals(jour) &
              r.statut.equals(StatutReservationTour.annulee.cle).not(),
        ))
        .get();
  }

  Future<int> _placesVendues(String circuitId, DateTime jour) async {
    final lignes = await _lignesActives(circuitId, jour);
    return lignes.fold<int>(0, (somme, l) => somme + l.nbParticipants);
  }

  /// Un guide ne conduit pas deux circuits DIFFÉRENTS le même jour.
  ///
  /// La portée est la **journée**, et pas la durée du circuit : `circuits.duree`
  /// étant un libellé libre, un circuit de plusieurs jours ne bloque que son
  /// jour de départ (PA-51). C'est une limite connue, écrite, et non un oubli.
  Future<void> _verifierGuideLibre({
    required String guideId,
    required DateTime jour,
    required String circuitId,
  }) async {
    final ailleurs =
        await (select(attachedDatabase.reservationsTourLocal)..where(
              (r) =>
                  r.guideId.equals(guideId) &
                  r.dateCircuit.equals(jour) &
                  r.circuitId.equals(circuitId).not() &
                  r.statut.equals(StatutReservationTour.annulee.cle).not(),
            ))
            .get();

    if (ailleurs.isNotEmpty) {
      throw RefusTourisme(
        MessagesTourisme.guideDejaAffecte(
          '${jour.day.toString().padLeft(2, '0')}/'
          '${jour.month.toString().padLeft(2, '0')}/'
          '${jour.year}',
        ),
      );
    }
  }
}
