import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../synchronisation/data/documents_autres_postes.dart';
import '../../synchronisation/data/operations_sync_dao.dart';
import '../../synchronisation/domain/charges_synchronisation.dart';
import '../../synchronisation/domain/operation_sync.dart';
import '../domain/entities/contrat_location.dart';
import '../domain/entities/vehicule.dart';
import '../domain/regles_vehicules.dart';

/// M8 — l'accès aux deux tables locales des véhicules et des locations.
///
/// @see EF-M8-01 Référentiel véhicules
/// @see EF-M8-02 Disponibilité et planning
/// @see EF-M8-03 Contrat de location
/// @see RG-08 Chevauchement — le contrôle se tient DANS la transaction
/// @see RG-09 Pièce d'identité et permis de conduire
///
/// ## Le parc se saisit SUR LE POSTE — décision du PO, 14/09/2026
///
/// `vehicules_local` descendait du serveur (PA-129, `CatalogueDao`). Le poste
/// est désormais zéro réseau : la table **n'avait plus aucun auteur**, et un
/// parc vide rend le point de vente de location inutilisable — aucun contrat
/// ne peut être établi sans véhicule. Ce DAO est son premier et seul écrivain,
/// exactement comme `TourismeDao` l'est devenu pour les guides.
///
/// C'est la question des deux moitiés (piège 11), posée à chaque table qu'on
/// lit : **qui l'écrit, qui la descend ?** Ici, ce fichier l'écrit, et personne
/// ne la descend — il n'y a plus de descente.
///
/// ## Ce qui part (depuis la file d'envoi, lot F1) et ce qui ne s'affiche jamais
///
/// Le véhicule (création, retouches, statut), le contrat (création, puis son
/// ANNULATION depuis la v38) et l'entretien partent dans la file, dans la
/// transaction du geste. `statutSync` est écrit à [statutSyncLocal] et **jamais
/// affiché** : le schéma lui donne pour défaut `synchronise` sur
/// `contrats_location_local`, ce qui serait faux, et le piège inverse de
/// `MouvementsStockLocal` (PA-134) annonce une attente sans fin. On l'écrase à
/// l'insertion plutôt que de le laisser mentir en base ; l'état d'envoi se lit
/// dans la file.
///
/// ## RG-08 : le verrou pessimiste n'existe plus, et ce qui le remplace
///
/// Le contrôle se tenait sous `lockForUpdate()` côté Laravel. Ici, SQLite n'a
/// qu'un seul écrivain à la fois et la vérification est faite **dans la
/// transaction qui insère** : cela protège ce poste, entièrement — il est le
/// seul, par décision du Product Owner. ⚠ Si un second poste apparaissait,
/// **plus rien ne départagerait deux contrats concurrents** : c'est la
/// contrepartie exacte de la décision, et elle est structurelle, pas un défaut
/// de ce code.
///
/// ## Ce que la v41 (27/10/2026) a porté — et ce qui reste un « — »
///
/// - `vehicules_local` porte `annee`, `capacite` (les places) et `transmission`
///   (NULLABLES) : [enregistrerVehicule] les écrit, les enfile et les valide aux
///   bornes et aux phrases du serveur. Un véhicule d'avant la v41 les a à `null`
///   (« — »), la migration n'en fabrique aucun.
/// - `contrats_location_local` porte `numero` (`LOC-…`, rendu par le serveur à
///   l'accusé : le poste n'en invente aucun), `remise`, `acompte` et `montant`,
///   le montant NET **FIGÉ à la signature** (tarif du jour × jours − remise).
///   Il n'est plus recalculé au tarif courant : modifier la grille ne réécrit
///   plus un contrat signé. Le reste dû en est la différence avec l'acompte. Un
///   contrat d'avant a ces quatre colonnes nulles : « — », jamais un chiffre
///   déduit du tarif d'aujourd'hui.
/// - `contrats_location_local` ne porte toujours que des **chemins de fichier**
///   (`cheminPieceIdentiteLocal`), pas les NUMÉROS de pièce et de permis. RG-09
///   est donc vérifiée à la saisie — sans numéro, pas de contrat — mais le
///   numéro n'est **conservé nulle part** (il part dans la charge du serveur).
///   Aucune de ces colonnes n'est détournée pour l'y ranger : écrire un numéro
///   de CNI dans une colonne nommée « chemin » serait une divergence que
///   personne ne verrait.
class VehiculeDao extends DatabaseAccessor<AppDatabase> {
  VehiculeDao(super.db, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final Uuid _uuid;

  /// La valeur écrite dans `statutSync`, et qui n'est **jamais affichée**.
  static const String statutSyncLocal = 'local';

  /* ------------------------------------------------------------ lectures */

  /// Le parc, par immatriculation croissante.
  ///
  /// [categorie] filtre sur la valeur STOCKÉE, jamais sur le libellé affiché.
  Future<List<Vehicule>> parc({CategorieVehicule? categorie}) async {
    final requete = select(attachedDatabase.vehiculesLocal)
      ..orderBy([(v) => OrderingTerm.asc(v.immatriculation)]);

    if (categorie != null) {
      requete.where((v) => v.categorie.equals(categorie.code));
    }

    return (await requete.get()).map(_versVehicule).toList(growable: false);
  }

  Future<Vehicule?> vehicule(String id) async {
    final ligne = await _ligneVehicule(id);
    return ligne == null ? null : _versVehicule(ligne);
  }

  /// La disponibilité d'UN véhicule sur une période — **deux booléens, jamais
  /// un seul**.
  ///
  /// « Un véhicule au calendrier libre mais en entretien n'est pas louable pour
  /// autant » : les fondre en un seul « disponible » ferait proposer à la
  /// location un véhicule au garage.
  ///
  /// ⚠ **Lecture sans transaction** : c'est un confort d'affichage, jamais une
  /// garantie. Seul [creerContrat] protège réellement (RG-08).
  Future<DisponibiliteVehicule> disponibilite({
    required String vehiculeId,
    required DateTime debut,
    required DateTime fin,
  }) async {
    final ligne = await _ligneVehicule(vehiculeId);
    final conflits = await _contratsEnConflit(
      vehiculeId: vehiculeId,
      debut: debut,
      fin: fin,
    );

    return DisponibiliteVehicule(
      vehiculeId: vehiculeId,
      calendrierLibre: conflits.isEmpty,
      statutLouable: ligne != null && statutsLouables.contains(ligne.statut),
    );
  }

  /// Les contrats, du plus récent départ au plus ancien, **nom du client
  /// résolu**.
  ///
  /// Le nom vient de `clients_local` : un client absent rend `null`, et l'écran
  /// affiche « — ». Jamais l'UUID, qui ne dit rien à personne au comptoir.
  Future<List<ContratLocation>> contrats({String? vehiculeId}) async {
    final requete = select(attachedDatabase.contratsLocationLocal)
      ..orderBy([(c) => OrderingTerm.desc(c.dateDebut)]);

    if (vehiculeId != null) {
      requete.where((c) => c.vehiculeId.equals(vehiculeId));
    }

    final lignes = await requete.get();
    if (lignes.isEmpty) return const [];

    final vehicules = {
      for (final v in await select(attachedDatabase.vehiculesLocal).get())
        v.id: v,
    };
    final clients = {
      for (final c in await select(attachedDatabase.clientsLocal).get())
        c.id: c,
    };

    return lignes
        .map((l) {
          final v = vehicules[l.vehiculeId];
          final client = clients[l.clientId];
          final jours = nombreDeJoursEntre(l.dateDebut, l.dateFin) ?? 0;

          return ContratLocation(
            id: l.id,
            // La clé étrangère est réelle et `PRAGMA foreign_keys` est actif : un
            // véhicule introuvable ne peut venir que d'une base abîmée. « — »
            // plutôt qu'une immatriculation inventée.
            immatriculation: v?.immatriculation ?? '—',
            clientId: l.clientId,
            debut: _iso(l.dateDebut),
            fin: _iso(l.dateFin),
            nombreJours: jours,
            // Le montant NET FIGÉ à la signature (v41) : `null` pour un contrat
            // d'avant, JAMAIS recalculé au tarif courant — « — » à l'écran.
            montant: _francsOuNull(l.montant),
            numero: l.numero,
            remise: _francsOuNull(l.remise),
            acompte: _francsOuNull(l.acompte),
            packageAvecGuide: l.guideId != null,
            clientNom: client == null
                ? null
                : [
                    client.nom,
                    client.prenom,
                  ].whereType<String>().join(' ').trim(),
            statut: l.statut,
          );
        })
        .toList(growable: false);
  }

  /* ------------------------------------------------------------ écritures */

  /// Crée ou réédite un véhicule du parc (EF-M8-01).
  ///
  /// Aucune suppression n'est exposée : un véhicule ne se supprime pas, il
  /// cesse d'être proposé — `hors_service` est fait pour cela, et une ligne
  /// retirée rendrait illisible tout contrat qui la référence.
  ///
  /// [tarifJour] est en **francs entiers** : le XOF n'a pas de sous-unité en
  /// circulation, et la conversion vers le `REAL` de Drift a lieu ici, une
  /// fois.
  Future<Vehicule> enregistrerVehicule({
    String? id,
    required String immatriculation,
    required CategorieVehicule categorie,
    required int tarifJour,
    StatutVehicule statut = StatutVehicule.disponible,
    int? annee,
    int? capacite,
    String? transmission,
  }) async {
    final plaque = immatriculation.trim();
    if (plaque.isEmpty) {
      throw const RefusVehicule(MessagesVehicules.immatriculationRequise);
    }
    if (tarifJour <= 0) {
      throw const RefusVehicule(MessagesVehicules.tarifInvalide);
    }
    // Année, places, transmission (v41) : les bornes et les PHRASES du serveur
    // (`GestionnaireVehicules`, relues par `tool/vehicules/rejouer_champs_location.php`).
    // Un paramètre absent (`null`) laisse la colonne telle qu'elle est ; la
    // transmission vide l'efface (chaîne vide).
    final refusChamp =
        (annee == null ? null : refusAnneeEntiere(annee)) ??
        (capacite == null ? null : refusPlacesEntieres(capacite)) ??
        refusTransmission(transmission);
    if (refusChamp != null) throw RefusVehicule(refusChamp);
    final transmissionNette = transmission?.trim();

    final identifiant = id ?? _uuid.v4();

    return transaction(() async {
      // `vehicules.immatriculation` est `unique()` au schéma de référence ; la
      // table locale ne porte PAS cette contrainte. La poser ici est donc le
      // seul contrôle qui existe : sans lui, deux lignes homonymes rendraient
      // le planning et les contrats illisibles, la colonne « Véhicule » étant
      // l'immatriculation elle-même.
      final homonyme =
          await (select(attachedDatabase.vehiculesLocal)..where(
                (v) =>
                    v.immatriculation.equals(plaque) &
                    v.id.equals(identifiant).not(),
              ))
              .getSingleOrNull();

      if (homonyme != null) {
        throw RefusVehicule(MessagesVehicules.immatriculationDejaPrise(plaque));
      }

      final avant = await _ligneVehicule(identifiant);
      final anneeFinale = annee ?? avant?.annee;
      final capaciteFinale = capacite ?? avant?.capacite;
      final transmissionFinale = transmissionNette == null
          ? avant?.transmission
          : (transmissionNette.isEmpty ? null : transmissionNette);
      await into(attachedDatabase.vehiculesLocal).insertOnConflictUpdate(
        VehiculesLocalCompanion.insert(
          id: identifiant,
          categorie: categorie.code,
          immatriculation: plaque,
          tarifJour: tarifJour.toDouble(),
          statut: statut.code,
          annee: Value(anneeFinale),
          capacite: Value(capaciteFinale),
          transmission: Value(transmissionFinale),
        ),
      );
      await _envoyer(identifiant, {
        if (avant != null && avant.immatriculation != plaque)
          'immatriculation': plaque,
        if (avant != null && avant.categorie != categorie.code)
          'categorie': categorie.code,
        if (avant != null && avant.tarifJour.round() != tarifJour)
          'tarif_jour': tarifJour,
        if (avant != null && avant.statut != statut.code) 'statut': statut.code,
        // Les trois champs de la v41 : seulement ceux qui ont CHANGÉ ; vider la
        // transmission part en `null` explicite.
        if (avant != null && anneeFinale != null && avant.annee != anneeFinale)
          'annee': anneeFinale,
        if (avant != null &&
            capaciteFinale != null &&
            avant.capacite != capaciteFinale)
          'capacite': capaciteFinale,
        if (avant != null && avant.transmission != transmissionFinale)
          'transmission': transmissionFinale,
      });

      return Vehicule(
        id: identifiant,
        immatriculation: plaque,
        categorie: categorie,
        categorieBrute: categorie.code,
        annee: anneeFinale,
        transmission: transmissionFinale,
        capacite: capaciteFinale,
        tarifJour: _decimale(tarifJour),
        statut: statut,
        statutBrut: statut.code,
        exigePermis: exigePermisPour(categorie.code),
      );
    });
  }

  /// Les immobilisations (entretiens et carburations), de la plus récente à la
  /// plus ancienne, immatriculation résolue.
  Future<List<EntretienVehicule>> entretiens() async {
    final lignes = await (select(
      attachedDatabase.entretiensVehiculeLocal,
    )..orderBy([(e) => OrderingTerm.desc(e.date)])).get();
    if (lignes.isEmpty) return const [];

    final plaques = {
      for (final v in await select(attachedDatabase.vehiculesLocal).get())
        v.id: v.immatriculation,
    };

    return [
      for (final l in lignes)
        EntretienVehicule(
          id: l.id,
          vehiculeId: l.vehiculeId,
          immatriculation: plaques[l.vehiculeId] ?? '—',
          type: TypeEntretien.values.firstWhere(
            (t) => t.code == l.type,
            orElse: () => TypeEntretien.entretien,
          ),
          date: _iso(l.date),
          coutFrancs: l.cout,
          auteur: l.auteur,
        ),
    ];
  }

  /// Enregistre une immobilisation — « Immobiliser » de la PWA
  /// (`Locations::enregistrerImmobilisation`, EF-M8-05).
  ///
  /// Comme la PWA, elle écrit UNE ligne datée et **ne touche pas au statut** du
  /// véhicule (statut ≠ disponibilité). La ligne part au serveur (`creation`,
  /// jamais modifiée). [coutFrancs] : francs entiers, zéro ou plus.
  Future<EntretienVehicule> enregistrerEntretien({
    required String vehiculeId,
    required TypeEntretien type,
    required DateTime date,
    required int coutFrancs,
    String? auteur,
  }) async {
    if (coutFrancs < 0) {
      throw const RefusVehicule(MessagesVehicules.coutEntretienInvalide);
    }
    return transaction(() async {
      final ligne = await _ligneVehicule(vehiculeId);
      if (ligne == null) {
        throw const RefusVehicule(MessagesVehicules.vehiculeInexistant);
      }
      final id = _uuid.v4();
      final jour = DateTime(date.year, date.month, date.day);

      await into(attachedDatabase.entretiensVehiculeLocal).insert(
        EntretiensVehiculeLocalCompanion.insert(
          id: id,
          vehiculeId: vehiculeId,
          type: type.code,
          date: jour,
          cout: coutFrancs,
          auteur: Value(auteur),
        ),
      );
      // Le véhicule part AVANT son entretien : s'il n'est pas encore connu du
      // serveur, sa création est enfilée ici, devant celle de l'entretien.
      await _envoyer(vehiculeId, const {});
      await OperationsSyncDao(attachedDatabase).enfiler(
        table: TableSynchronisee.entretiensVehicule,
        entiteId: id,
        type: TypeOperationSync.creation,
        payload: chargeEntretienVehicule(
          vehiculeId: vehiculeId,
          type: type.code,
          date: jour,
          coutFrancs: coutFrancs,
        ),
      );

      return EntretienVehicule(
        id: id,
        vehiculeId: vehiculeId,
        immatriculation: ligne.immatriculation,
        type: type,
        date: _iso(jour),
        coutFrancs: coutFrancs,
        auteur: auteur,
      );
    });
  }

  /// Change le statut d'un véhicule — sortie du parc louable et remise en
  /// service (depuis sa ligne du parc).
  ///
  /// ⚠ Une IMMOBILISATION n'est plus ce geste (relu le 27/10/2026) : depuis la
  /// v32 elle écrit une ligne `entretiens_vehicule_local` par
  /// [enregistrerEntretien] et ne touche PAS au statut, comme la PWA (statut ≠
  /// disponibilité). Le véhicule cesse d'être louable par ce statut-ci, ce que
  /// [creerContrat] oppose ensuite à toute location.
  Future<Vehicule> changerStatut(String vehiculeId, StatutVehicule statut) {
    return transaction(() async {
      final ligne = await _ligneVehicule(vehiculeId);
      if (ligne == null) {
        throw const RefusVehicule(MessagesVehicules.vehiculeInexistant);
      }

      await (update(attachedDatabase.vehiculesLocal)
            ..where((v) => v.id.equals(vehiculeId)))
          .write(VehiculesLocalCompanion(statut: Value(statut.code)));
      await _envoyer(vehiculeId, {'statut': statut.code});

      return _versVehicule(ligne.copyWith(statut: statut.code));
    });
  }

  /// Retire un véhicule du parc actif — le geste que la vue nomme
  /// « Archiver ».
  ///
  /// ## Archiver n'est PAS supprimer, et c'est la seule forme possible ici
  ///
  /// La suppression est interdite sur une table référencée par des contrats :
  /// la ligne retirée rendrait illisible tout contrat qui la désigne. La vue
  /// écrit d'ailleurs « il reste consultable ». Le véhicule passe donc
  /// `hors_service`, exactement l'état inverse de « Remettre en service » que la
  /// vue propose sur la même ligne — c'est son propre cycle, pas une invention.
  ///
  /// ## Le verrou : on n'archive pas un véhicule engagé
  ///
  /// Un véhicule dont un contrat court encore ou commence plus tard ne peut pas
  /// être archivé — la ligne du planning deviendrait incompréhensible, et
  /// surtout le client a un véhicule réservé. Le refus nomme le nombre de
  /// contrats, comme la vue.
  Future<Vehicule> archiverVehicule(String vehiculeId, {DateTime? aujourdHui}) {
    final jour = jourDe(aujourdHui ?? DateTime.now());

    return transaction(() async {
      final ligne = await _ligneVehicule(vehiculeId);
      if (ligne == null) {
        throw const RefusVehicule(MessagesVehicules.vehiculeInexistant);
      }

      final engagements = await (select(
        attachedDatabase.contratsLocationLocal,
      )..where((c) => c.vehiculeId.equals(vehiculeId))).get();

      // Règle UNIQUE avec le serveur : un contrat engage le véhicule tant que
      // `date_fin >= aujourd'hui` — le jour de restitution COMPTE encore (le
      // véhicule peut être dehors). Un contrat ANNULÉ n'engage plus rien non plus (`ParcVehiculeService::contratsEngages`
      // : `statut != annule`).
      final encours = engagements
          .where(
            (c) =>
                c.statut != statutContratAnnule &&
                !jourDe(c.dateFin).isBefore(jour),
          )
          .toList(growable: false);

      if (encours.isNotEmpty) {
        throw RefusVehicule(
          MessagesVehicules.archivageVerrouille(encours.length),
        );
      }

      await (update(attachedDatabase.vehiculesLocal)
            ..where((v) => v.id.equals(vehiculeId)))
          .write(const VehiculesLocalCompanion(statut: Value('hors_service')));
      await _envoyer(vehiculeId, {'statut': 'hors_service'});

      return _versVehicule(ligne.copyWith(statut: 'hors_service'));
    });
  }

  /// « Purger » définitivement un véhicule ARCHIVÉ (A5, 28/10/2026) —
  /// `ParcVehiculeService::purger`, les mêmes verrous dans le même ordre et aux
  /// mots du serveur :
  ///
  /// 1. le véhicule doit être archivé (`hors_service`) ;
  /// 2. aucun contrat non annulé ne l'engage (fin du contrat AUJOURD'HUI ou
  ///    plus tard — `date_fin >= aujourd'hui`, plus large que l'archivage) :
  ///    la phrase `vehicules.verrou`, avec ses trois premiers contrats ;
  /// 3. aucun contrat (même annulé ou passé) ni entretien ne le cite.
  ///
  /// La suppression et son enfilement sont UNE transaction. Rend l'immatriculation.
  Future<String> purger(String vehiculeId, {DateTime? aujourdHui}) {
    final jour = jourDe(aujourdHui ?? DateTime.now());

    return transaction(() async {
      final ligne = await _ligneVehicule(vehiculeId);
      if (ligne == null) {
        throw const RefusVehicule(MessagesVehicules.vehiculeInexistant);
      }
      if (ligne.statut != 'hors_service') {
        throw const RefusVehicule(MessagesVehicules.purgeRefuseeNonArchive);
      }

      final contrats =
          await (select(attachedDatabase.contratsLocationLocal)
                ..where((c) => c.vehiculeId.equals(vehiculeId))
                ..orderBy([(c) => OrderingTerm.asc(c.dateDebut)]))
              .get();
      final engages = contrats
          .where(
            (c) =>
                c.statut != statutContratAnnule &&
                !jourDe(c.dateFin).isBefore(jour),
          )
          .toList(growable: false);
      if (engages.isNotEmpty) {
        throw RefusVehicule(
          MessagesVehicules.purgeVerrouille([
            for (final c in engages)
              (numero: c.numero ?? c.id, debut: c.dateDebut, fin: c.dateFin),
          ]),
        );
      }
      if (contrats.isNotEmpty || await _citeParUnEntretien(vehiculeId)) {
        throw const RefusVehicule(MessagesVehicules.purgeRefuseeReferencee);
      }

      await (delete(
        attachedDatabase.vehiculesLocal,
      )..where((v) => v.id.equals(vehiculeId))).go();
      await OperationsSyncDao(attachedDatabase).enfiler(
        table: TableSynchronisee.vehicules,
        entiteId: vehiculeId,
        type: TypeOperationSync.suppression,
        payload: {'libelle': ligne.immatriculation},
      );
      return ligne.immatriculation;
    });
  }

  /// La DESCENTE d'une purge faite ailleurs (A5) : le véhicule est retiré de CE
  /// poste SEULEMENT si aucun contrat ni entretien local ne le cite. `true` si
  /// retiré (ou déjà absent), `false` si une saisie locale y est rattachée.
  /// N'enfile rien : le serveur a déjà purgé.
  Future<bool> retirerVehiculePurgeAilleurs(String vehiculeId) {
    return transaction(() async {
      if (await _ligneVehicule(vehiculeId) == null) return true;
      final cite =
          (await (select(attachedDatabase.contratsLocationLocal)
                    ..where((c) => c.vehiculeId.equals(vehiculeId))
                    ..limit(1))
                  .get())
              .isNotEmpty ||
          await _citeParUnEntretien(vehiculeId);
      if (cite) return false;
      await (delete(
        attachedDatabase.vehiculesLocal,
      )..where((v) => v.id.equals(vehiculeId))).go();
      return true;
    });
  }

  Future<bool> _citeParUnEntretien(String vehiculeId) async =>
      (await (select(attachedDatabase.entretiensVehiculeLocal)
                ..where((e) => e.vehiculeId.equals(vehiculeId))
                ..limit(1))
              .get())
          .isNotEmpty;

  /// Établit un contrat de location — **RG-08 et RG-09 dans la transaction qui
  /// écrit**.
  ///
  /// Cinq refus, tous avant l'insertion et tous dans la même transaction :
  ///
  /// - le véhicule doit exister ;
  /// - il doit être **louable** — un véhicule en entretien ne se loue pas,
  ///   « c'est précisément parce qu'il est immobilisé que son calendrier
  ///   l'est » ;
  /// - le client doit exister (clé étrangère réelle, jamais du texte libre) ;
  /// - la restitution doit être **strictement** après le départ, comme le
  ///   `CHECK (date_fin > date_debut)` du schéma ;
  /// - RG-09 : pièce d'identité toujours, permis sauf catégorie dispensée ;
  /// - RG-08 : aucune plage en conflit, lue **ici**, pas avant.
  ///
  /// ⚠ La vérification de chevauchement est faite dans la transaction, et non
  /// depuis [disponibilite] : entre une lecture d'affichage et l'écriture, le
  /// parc a pu changer. Un contrôle juste posé au-dessus d'une lecture périmée
  /// ne protège rien.
  Future<ContratLocation> creerContrat(SaisieContrat saisie) async {
    final debut = jourDe(saisie.debut);
    final fin = jourDe(saisie.fin);

    return transaction(() async {
      // L'ORDRE DU SERVEUR (`GestionnaireContratsLocation`, rejoué par
      // `tool/vehicules/rejouer_champs_location.php`) : dates, véhicule, client,
      // remise, acompte — puis seulement les refus du service (louable, pièces,
      // permis, chevauchement).
      final jours = nombreDeJoursEntre(debut, fin);
      if (jours == null) {
        throw const RefusVehicule(MessagesVehicules.finApresDebut);
      }

      final vehicule = await _ligneVehicule(saisie.vehiculeId);
      if (vehicule == null) {
        throw const RefusVehicule(MessagesVehicules.vehiculeInexistant);
      }

      final client = await (select(
        attachedDatabase.clientsLocal,
      )..where((c) => c.id.equals(saisie.clientId))).getSingleOrNull();
      if (client == null) {
        throw const RefusVehicule(MessagesVehicules.clientInexistant);
      }

      // La remise puis l'acompte, comme `Locations::enregistrerContrat` : une
      // remise supérieure au brut produirait un montant négatif ; un acompte
      // supérieur au net, un reste dû négatif présenté comme une créance du
      // client sur le gîte. Le montant NET est FIGÉ ici, une fois.
      if (saisie.remiseFrancs < 0) {
        throw RefusVehicule(
          MessagesVehicules.champMinimum(MessagesVehicules.libelleRemise, 0),
        );
      }
      if (saisie.acompteFrancs < 0) {
        throw RefusVehicule(
          MessagesVehicules.champMinimum(MessagesVehicules.libelleAcompte, 0),
        );
      }
      final brut = _francs(vehicule.tarifJour) * jours;
      if (saisie.remiseFrancs > brut) {
        throw RefusVehicule(
          MessagesVehicules.remiseSuperieureAuBrut(_decimale(brut)),
        );
      }
      final net = brut - saisie.remiseFrancs;
      if (saisie.acompteFrancs > net) {
        throw RefusVehicule(
          MessagesVehicules.acompteSuperieurAuNet(_decimale(net)),
        );
      }

      if (!statutsLouables.contains(vehicule.statut)) {
        throw RefusVehicule(MessagesVehicules.nonLouable(vehicule.statut));
      }

      // RG-09 — la pièce d'identité est exigée quelle que soit la catégorie.
      if (saisie.pieceIdentite.trim().isEmpty) {
        throw const RefusVehicule(MessagesVehicules.pieceIdentiteRequise);
      }

      // RG-09 — le permis, seulement pour les catégories qui le requièrent. La
      // condition n'est PAS réécrite ici : elle est lue sur l'unique auteur.
      if (exigePermisPour(vehicule.categorie) &&
          (saisie.permisConduire?.trim().isEmpty ?? true)) {
        throw RefusVehicule(MessagesVehicules.permisRequis(vehicule.categorie));
      }

      // RG-08 — le contrôle de chevauchement, lu dans cette transaction.
      final conflits = await _contratsEnConflit(
        vehiculeId: saisie.vehiculeId,
        debut: debut,
        fin: fin,
      );
      if (conflits.isNotEmpty) {
        throw const RefusVehicule(MessagesVehicules.chevauchement);
      }

      final id = _uuid.v4();
      await into(attachedDatabase.contratsLocationLocal).insert(
        ContratsLocationLocalCompanion.insert(
          id: id,
          vehiculeId: saisie.vehiculeId,
          clientId: saisie.clientId,
          guideId: Value(saisie.guideId),
          dateDebut: debut,
          dateFin: fin,
          // ⚠ Les NUMÉROS de pièce et de permis ne sont écrits nulle part : la
          // table ne porte que des chemins de fichier. Les y ranger serait
          // écrire un numéro de CNI dans une colonne nommée « chemin ».
          statutSync: const Value(statutSyncLocal),
          // Comme le serveur à la création (`GestionnaireContratsLocation`).
          statut: const Value(statutContratActif),
          // v41 : le montant NET figé, la remise et l'acompte de la signature.
          // Le N° `LOC-` reste NUL : il vient du serveur, à l'accusé.
          montant: Value(net),
          remise: Value(saisie.remiseFrancs),
          acompte: Value(saisie.acompteFrancs),
        ),
      );

      // Le véhicule passe à `loue` : c'est ce que le statut décrit — l'état
      // opérationnel courant —, et non la disponibilité, qui se calcule sur
      // les plages. `loue` reste d'ailleurs louable pour une période future.
      await (update(attachedDatabase.vehiculesLocal)
            ..where((v) => v.id.equals(saisie.vehiculeId)))
          .write(const VehiculesLocalCompanion(statut: Value('loue')));

      // Audit de couverture (18/10/2026) : le contrat part — le véhicule
      // d'abord s'il est inconnu du serveur ; les numéros de pièce et de
      // permis de la SAISIE voyagent dans la charge (jamais en base ici).
      await _envoyer(saisie.vehiculeId, const {});
      await OperationsSyncDao(attachedDatabase).enfiler(
        table: TableSynchronisee.contratsLocation,
        entiteId: id,
        type: TypeOperationSync.creation,
        payload: chargeContratLocation(
          vehiculeId: saisie.vehiculeId,
          clientId: saisie.clientId,
          guideId: saisie.guideId,
          debut: debut,
          fin: fin,
          pieceIdentite: saisie.pieceIdentite.trim(),
          permisConduire: saisie.permisConduire?.trim(),
          // Envoyées quand elles existent : un serveur d'avant le lot L3-S
          // ignorerait ces clés, et zéro n'a rien à dire.
          remiseFrancs: saisie.remiseFrancs > 0 ? saisie.remiseFrancs : null,
          acompteFrancs: saisie.acompteFrancs > 0 ? saisie.acompteFrancs : null,
        ),
      );

      return ContratLocation(
        id: id,
        immatriculation: vehicule.immatriculation,
        clientId: saisie.clientId,
        debut: _iso(debut),
        fin: _iso(fin),
        nombreJours: jours,
        montant: _decimale(net),
        remise: _decimale(saisie.remiseFrancs),
        acompte: _decimale(saisie.acompteFrancs),
        packageAvecGuide: saisie.guideId != null,
        clientNom: [
          client.nom,
          client.prenom,
        ].whereType<String>().join(' ').trim(),
        statut: statutContratActif,
      );
    });
  }

  /// Pose le N° `LOC-…` rendu par le serveur à l'accusé de la création du contrat
  /// (`SyncManager`) : le poste n'en invente aucun. Une ligne qui porte déjà un
  /// numéro n'est pas réécrite (un rejeu d'accusé ne change rien).
  Future<void> regulariserNumero(String contratId, String numero) async {
    await (update(attachedDatabase.contratsLocationLocal)
          ..where((c) => c.id.equals(contratId) & c.numero.isNull()))
        .write(ContratsLocationLocalCompanion(numero: Value(numero)));
  }

  /// Annule un contrat — « Annuler » de la vue (`Locations::executerSuppression`,
  /// `ContratLocationService::annuler` au serveur), le SEUL écrivain de saisie du
  /// statut d'un contrat.
  ///
  /// Le contrat passe `annule`, il n'est jamais supprimé : la pièce reste lisible
  /// et le véhicule redevient libre sur sa plage (RG-08). Un contrat déjà annulé
  /// est refusé avec la phrase de la vue. La modification `{statut: annule}` part
  /// dans la file, dans la MÊME transaction — seulement si le serveur détient le
  /// contrat (descendu, ou création en file non rejetée) : sinon il répondrait
  /// « inconnu » à chaque essai.
  ///
  /// Comme la PWA, aucune restriction « document d'un autre poste » : la vue
  /// laisse tout compte qui écrit sur M8 annuler tout contrat.
  Future<ContratLocation> annulerContrat(String contratId) {
    return transaction(() async {
      final ligne = await (select(
        attachedDatabase.contratsLocationLocal,
      )..where((c) => c.id.equals(contratId))).getSingleOrNull();
      if (ligne == null) {
        throw const RefusVehicule(MessagesVehicules.contratInexistant);
      }
      if (ligne.statut == statutContratAnnule) {
        throw const RefusVehicule(MessagesVehicules.contratDejaAnnule);
      }

      await (update(
        attachedDatabase.contratsLocationLocal,
      )..where((c) => c.id.equals(contratId))).write(
        const ContratsLocationLocalCompanion(
          statut: Value(statutContratAnnule),
        ),
      );
      if (await DocumentsAutresPostes(
        attachedDatabase,
      ).connuDuServeur(TableSynchronisee.contratsLocation, contratId)) {
        await OperationsSyncDao(attachedDatabase).enfiler(
          table: TableSynchronisee.contratsLocation,
          entiteId: contratId,
          type: TypeOperationSync.modification,
          payload: chargeAnnulationContratLocation(),
        );
      }

      return (await contrats()).firstWhere((c) => c.id == contratId);
    });
  }

  /* --------------------------------------------------------------- privé */

  /// Audit de couverture (18/10/2026) : le véhicule part au serveur. Inconnu
  /// du serveur → sa CRÉATION (valeurs courantes ; le serveur le crée
  /// disponible, un autre statut suit en modification) ; connu → les seuls
  /// [champs] changés. « Loué » ne part jamais (le serveur le déduit des
  /// contrats). Dans la transaction du geste.
  Future<void> _envoyer(String id, Map<String, Object?> champs) async {
    final file = OperationsSyncDao(attachedDatabase);
    final transmis = champs.entries
        .where((e) => !(e.key == 'statut' && e.value == 'loue'))
        .fold(<String, Object?>{}, (m, e) => m..[e.key] = e.value);
    if (await DocumentsAutresPostes(
      attachedDatabase,
    ).connuDuServeur(TableSynchronisee.vehicules, id)) {
      if (transmis.isEmpty) return;
      await file.enfiler(
        table: TableSynchronisee.vehicules,
        entiteId: id,
        type: TypeOperationSync.modification,
        payload: transmis,
      );
      return;
    }
    final v = await _ligneVehicule(id);
    if (v == null) return;
    await file.enfiler(
      table: TableSynchronisee.vehicules,
      entiteId: id,
      type: TypeOperationSync.creation,
      payload: chargeVehicule(
        immatriculation: v.immatriculation,
        categorie: v.categorie,
        tarifJour: v.tarifJour.round(),
        annee: v.annee,
        capacite: v.capacite,
        transmission: v.transmission,
      ),
    );
    if (v.statut != 'disponible' && v.statut != 'loue') {
      await file.enfiler(
        table: TableSynchronisee.vehicules,
        entiteId: id,
        type: TypeOperationSync.modification,
        payload: {'statut': v.statut},
      );
    }
  }

  Future<VehiculesLocalData?> _ligneVehicule(String id) => (select(
    attachedDatabase.vehiculesLocal,
  )..where((v) => v.id.equals(id))).getSingleOrNull();

  /// Les contrats qui chevauchent [debut]..[fin] sur ce véhicule.
  ///
  /// ## Un contrat ANNULÉ ne bloque plus (v38, 26/10/2026)
  ///
  /// `ContratLocationService` écarte `statut = annule` de RG-08 depuis la même
  /// date (sa liste de statuts inactifs était vide : un contrat annulé bloquait
  /// encore son véhicule, pendant que l'écran disait « le véhicule redevient
  /// disponible »). Le filtre est fait en Dart : un contrat sans statut (d'avant
  /// la v38) est actif.
  Future<List<ContratsLocationLocalData>> _contratsEnConflit({
    required String vehiculeId,
    required DateTime debut,
    required DateTime fin,
  }) async {
    final lignes = await (select(
      attachedDatabase.contratsLocationLocal,
    )..where((c) => c.vehiculeId.equals(vehiculeId))).get();

    return lignes
        .where(
          (c) =>
              c.statut != statutContratAnnule &&
              plagesSeChevauchent(
                debutA: c.dateDebut,
                finA: c.dateFin,
                debutB: debut,
                finB: fin,
              ),
        )
        .toList(growable: false);
  }

  Vehicule _versVehicule(VehiculesLocalData v) => Vehicule(
    id: v.id,
    immatriculation: v.immatriculation,
    categorie: CategorieVehicule.depuisCode(v.categorie),
    categorieBrute: v.categorie,
    // Les trois colonnes de la v41 : `null` pour un véhicule d'avant, jamais une
    // valeur plausible (un « 5 places » inventé se lirait comme une mesure).
    annee: v.annee,
    transmission: v.transmission,
    capacite: v.capacite,
    tarifJour: _decimale(_francs(v.tarifJour)),
    statut: StatutVehicule.depuisCode(v.statut),
    statutBrut: v.statut,
    // RG-09, dérivée de l'unique auteur — jamais recopiée ici.
    exigePermis: exigePermisPour(v.categorie),
  );

  /// Le `REAL` de Drift ramené à des **francs entiers**.
  ///
  /// Ce DAO n'écrit que des entiers ; l'arrondi ne sert qu'à une base qui
  /// porterait une valeur héritée. Le XOF n'a pas de sous-unité en circulation.
  static int _francs(double valeur) => valeur.round();

  /// Des francs entiers stockés (v41), en décimal du domaine ; `null` reste `null`
  /// (jamais « 0.00 » : un contrat d'avant n'a pas de montant, il ne vaut pas zéro).
  static String? _francsOuNull(int? francs) =>
      francs == null ? null : _decimale(francs);

  /// Le montant décimal attendu par le domaine (« 25000.00 »).
  ///
  /// Composé par concaténation, jamais par `toStringAsFixed` sur un `double` :
  /// la règle projet interdit qu'un montant transite par un flottant.
  static String _decimale(int francs) => '$francs.00';

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
