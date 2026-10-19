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
/// ## Rien ne part, et aucun écran ne doit annoncer le contraire
///
/// Ni `vehicules` ni `contrats_location` n'ont jamais été au registre
/// `TABLES_SYNCHRONISABLES`, et il n'existe plus de file du tout. Deux
/// conséquences tenues ici :
///
/// 1. **aucune entrée de file** n'est écrite ;
/// 2. `statutSync` est écrit à [statutSyncLocal] et **jamais affiché**. Le
///    schéma lui donne pour défaut `synchronise` sur `contrats_location_local`,
///    ce qui serait faux — rien n'a jamais été synchronisé —, et le piège
///    inverse de `MouvementsStockLocal` (PA-134), dont le défaut annonce une
///    attente sans fin. On l'écrase à l'insertion plutôt que de le laisser
///    mentir en base.
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
/// ## Trois colonnes manquent au schéma local, et elles ne sont pas inventées
///
/// - `vehicules_local` n'a **ni `annee`, ni `transmission`, ni `capacite`** ;
///   l'entité les porte à `null` et l'écran affiche « — ».
/// - `contrats_location_local` n'a **aucune colonne de montant ni de tarif** :
///   le montant est donc **recalculé** au tarif COURANT du véhicule, et non
///   figé à la signature. Un changement de grille réécrit le montant d'un
///   contrat déjà signé — c'est le défaut exact que PA-55 a corrigé sur
///   `tarifNuit`, et il ne peut pas l'être ici sans colonne. L'écran le dit.
/// - `contrats_location_local` ne porte que des **chemins de fichier**
///   (`cheminPieceIdentiteLocal`), pas les NUMÉROS de pièce et de permis. RG-09
///   est donc vérifiée à la saisie — sans numéro, pas de contrat — mais le
///   numéro n'est **conservé nulle part**. Aucune de ces deux colonnes n'est
///   détournée pour l'y ranger : écrire un numéro de CNI dans une colonne
///   nommée « chemin » serait une divergence que personne ne verrait.
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
            // ⚠ RECALCULÉ au tarif COURANT — voir l'en-tête de cette classe : la
            // table ne porte aucun montant, il n'y a donc rien à figer.
            montant: v == null
                ? '0.00'
                : _decimale(_francs(v.tarifJour) * jours),
            packageAvecGuide: l.guideId != null,
            clientNom: client == null
                ? null
                : [
                    client.nom,
                    client.prenom,
                  ].whereType<String>().join(' ').trim(),
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
  }) async {
    final plaque = immatriculation.trim();
    if (plaque.isEmpty) {
      throw const RefusVehicule(MessagesVehicules.immatriculationRequise);
    }
    if (tarifJour <= 0) {
      throw const RefusVehicule(MessagesVehicules.tarifInvalide);
    }

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
      await into(attachedDatabase.vehiculesLocal).insertOnConflictUpdate(
        VehiculesLocalCompanion.insert(
          id: identifiant,
          categorie: categorie.code,
          immatriculation: plaque,
          tarifJour: tarifJour.toDouble(),
          statut: statut.code,
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
      });

      return Vehicule(
        id: identifiant,
        immatriculation: plaque,
        categorie: categorie,
        categorieBrute: categorie.code,
        // Trois colonnes que la table locale n'a pas — voir l'en-tête.
        annee: null,
        transmission: null,
        capacite: null,
        tarifJour: _decimale(tarifJour),
        statut: statut,
        statutBrut: statut.code,
        exigePermis: exigePermisPour(categorie.code),
      );
    });
  }

  /// Change le statut d'un véhicule — immobilisation et remise en service.
  ///
  /// C'est le SEUL effet qu'une immobilisation peut avoir sur ce poste :
  /// `entretiens_vehicule` n'a **aucune table locale**, ni motif, ni date, ni
  /// coût à écrire. Le véhicule cesse d'être louable, ce que [creerContrat]
  /// oppose ensuite à toute location — le reste du formulaire du maître est
  /// rendu inerte avec sa raison, plutôt que collecté puis jeté.
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

      // Un contrat dont la restitution est passée n'engage plus rien : bornes
      // demi-ouvertes, le jour de restitution est déjà libre.
      final encours = engagements
          .where((c) => c.dateFin.isAfter(jour))
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
      final vehicule = await _ligneVehicule(saisie.vehiculeId);
      if (vehicule == null) {
        throw const RefusVehicule(MessagesVehicules.vehiculeInexistant);
      }

      if (!statutsLouables.contains(vehicule.statut)) {
        throw RefusVehicule(MessagesVehicules.nonLouable(vehicule.statut));
      }

      final client = await (select(
        attachedDatabase.clientsLocal,
      )..where((c) => c.id.equals(saisie.clientId))).getSingleOrNull();
      if (client == null) {
        throw const RefusVehicule(MessagesVehicules.clientInexistant);
      }

      final jours = nombreDeJoursEntre(debut, fin);
      if (jours == null) {
        throw const RefusVehicule(MessagesVehicules.finApresDebut);
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
        ),
      );

      return ContratLocation(
        id: id,
        immatriculation: vehicule.immatriculation,
        clientId: saisie.clientId,
        debut: _iso(debut),
        fin: _iso(fin),
        nombreJours: jours,
        montant: _decimale(_francs(vehicule.tarifJour) * jours),
        packageAvecGuide: saisie.guideId != null,
        clientNom: [
          client.nom,
          client.prenom,
        ].whereType<String>().join(' ').trim(),
      );
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
  /// ## Le filtre est fait en Dart, et c'est délibéré
  ///
  /// `contrats_location` n'a **aucune colonne de statut** (PA-50) : il n'existe
  /// pas de contrat inactif à exclure, et la clause `statutsInactifs` du
  /// service serveur est vide pour la même raison. Tous les contrats du
  /// véhicule comptent, sans exception.
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
          (c) => plagesSeChevauchent(
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
    // Aucune de ces trois colonnes n'existe dans `vehicules_local`. On rend
    // `null` plutôt qu'une valeur plausible : l'écran affiche « — » et dit
    // pourquoi, là où un « 5 places » inventé se lirait comme une mesure.
    annee: null,
    transmission: null,
    capacite: null,
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
