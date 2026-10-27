/// L'ENVOI des reçus de dépenses au serveur (lot L4, décision du PO du
/// 27/10/2026 : « on accepte un transport de fichier dans la synchronisation
/// pour le reçu de dépense »).
///
/// ## Un fichier n'est pas une opération de la file
///
/// `POST /sync` est du JSON borné en lots ; un fichier n'y a pas sa place. Le
/// reçu a sa propre porte — `PUT /sync/depenses/{id}/recu` — et sa propre
/// politique, branchée sur le MÊME passage du [SyncManager] (donc sur le même
/// interrupteur « Synchronisation activée », la même génération des données, les
/// mêmes refus 401/403) : éteint, aucune requête ne part, le reçu reste
/// `en_attente`.
///
/// ## Ordre et rejeu
///
///  * un reçu ne part qu'APRÈS l'accusé de la création de sa dépense (une
///    opération `creation` de `depenses` `synchronise`) : avant, le serveur
///    répondrait 404 `depense_inconnue` ;
///  * le dépôt est IDEMPOTENT par empreinte : une réponse perdue puis un renvoi
///    du même fichier rend 200 (`rejeu`) et vaut accusé ;
///  * un 404 `depense_inconnue` laisse le reçu en attente (la dépense n'est pas
///    encore arrivée) ; injoignable, 408, 429 et 5xx l'y laissent aussi et
///    arrêtent l'envoi des reçus pour ce passage ; 401/403/409 génération
///    périmée arrêtent TOUT le passage (le [SyncManager] les consigne comme pour
///    l'envoi de la file) ;
///  * tout autre refus du serveur (type, taille, autre reçu déjà rattaché…) est
///    DÉFINITIF : le reçu devient `refuse`, avec la phrase du serveur.
///
/// ## Jamais « envoyé » sans accusé
///
/// `envoye` n'est écrit ([DepenseDao.accuserRecu]) que sur le 200 du serveur.
library;

import '../../../core/database/app_database.dart';
import '../../depenses/data/depense_dao.dart';
import '../../depenses/data/recus_depenses_locaux.dart';
import '../../depenses/domain/recu_depense.dart';
import '../../transverse/data/configuration_poste.dart';
import '../domain/operation_sync.dart';
import 'operations_sync_dao.dart';
import 'transport_synchronisation.dart';

/// Pourquoi l'envoi des reçus s'est arrêté avant la fin.
enum ArretEnvoiRecus {
  /// Pas de réponse, 408, 429, 5xx : les reçus restants attendent le prochain
  /// passage.
  serveurIndisponible,

  /// 401 : le jeton est refusé.
  jetonRefuse,

  /// 403 : le `poste_id` n'est pas celui du jeton.
  posteNonReconnu,

  /// 409 `generation_perimee` : le serveur a été réinitialisé depuis.
  serveurReinitialise,
}

/// Ce qu'un passage d'envoi des reçus a fait.
final class BilanEnvoiRecus {
  const BilanEnvoiRecus({
    this.envoyes = 0,
    this.refuses = 0,
    this.enAttente = 0,
    this.arret,
    this.codeHttp,
    this.reinitialiseLe,
  });

  /// Accusés par le serveur pendant ce passage.
  final int envoyes;

  /// Refusés définitivement pendant ce passage.
  final int refuses;

  /// Restés en attente (dépense pas encore acceptée, ou arrêt).
  final int enAttente;

  final ArretEnvoiRecus? arret;
  final int? codeHttp;

  /// La date de la réinitialisation du serveur, quand [arret] la constate.
  final DateTime? reinitialiseLe;
}

class EnvoiRecusDepenses {
  EnvoiRecusDepenses({
    required this._db,
    required this._transport,
    required this._recus,
    DateTime Function()? maintenant,
    this.maxParPassage = 25,
  }) : _maintenant = maintenant ?? DateTime.now;

  final AppDatabase _db;
  final TransportFichiers _transport;
  final RecusDepensesLocaux _recus;
  final DateTime Function() _maintenant;

  /// Un garde-fou : au plus ce nombre de dépôts par passage.
  final int maxParPassage;

  /// Envoie les reçus `en_attente` dont la dépense est acceptée. Ne lève
  /// jamais pour une panne réseau (elle devient un arrêt).
  Future<BilanEnvoiRecus> envoyer(
    AppairagePoste appairage, {
    String? generation,
  }) async {
    final dao = DepenseDao(_db, recus: _recus);
    final file = OperationsSyncDao(_db);
    final attente = await dao.recusEnAttente(limite: maxParPassage);
    var envoyes = 0;
    var refuses = 0;
    var restes = 0;

    for (var i = 0; i < attente.length; i++) {
      final recu = attente[i];

      // La dépense doit être ACCUSÉE avant son reçu.
      if (!await _creationAccusee(file, recu.depenseId)) {
        restes++;
        continue;
      }

      final octets = await _recus.lire(recu.nom);
      if (octets == null) {
        await dao.refuserRecu(
          recu.depenseId,
          TextesRecuPoste.fichierIntrouvable,
        );
        refuses++;
        continue;
      }
      if (recu.sha256 != null &&
          RecusDepensesLocaux.empreinte(octets) != recu.sha256) {
        await dao.refuserRecu(recu.depenseId, TextesRecuPoste.fichierModifie);
        refuses++;
        continue;
      }
      final empreinte = recu.sha256 ?? RecusDepensesLocaux.empreinte(octets);

      final issue = await _transport.deposer(
        urlServeur(
          appairage.serveur,
          '/sync/depenses/${recu.depenseId}/recu',
        ).replace(
          queryParameters: {
            'poste_id': appairage.posteId,
            'generation': ?generation,
          },
        ),
        octets: octets,
        type: recu.type ?? 'application/octet-stream',
        entetes: {'X-Recu-Sha256': empreinte},
        jeton: appairage.jetonApi,
      );

      final reinitialise = reinitialisationRefusee(issue, _maintenant());
      if (reinitialise != null) {
        return BilanEnvoiRecus(
          envoyes: envoyes,
          refuses: refuses,
          enAttente: restes + (attente.length - i),
          arret: ArretEnvoiRecus.serveurReinitialise,
          codeHttp: 409,
          reinitialiseLe: reinitialise,
        );
      }

      // Le code d'un refus du serveur (`depense_inconnue`, `recu_deja_rattache`…).
      final Object? codeRefus = switch (issue) {
        ReponseHttp(:final corps) => corps == null ? null : corps['code'],
        _ => null,
      };

      switch (issue) {
        case ServeurInjoignable():
          return _arret(
            ArretEnvoiRecus.serveurIndisponible,
            null,
            envoyes,
            refuses,
            restes + (attente.length - i),
          );
        case ReponseHttp(:final statut) when statut >= 200 && statut < 300:
          await dao.accuserRecu(recu.depenseId);
          envoyes++;
        case ReponseHttp(statut: 401):
          return _arret(
            ArretEnvoiRecus.jetonRefuse,
            401,
            envoyes,
            refuses,
            restes + (attente.length - i),
          );
        case ReponseHttp(statut: 403) when codeRefus == null:
          // 403 SANS code : le poste n'est pas celui du jeton (ou le droit
          // manque au niveau du module) — voir plus bas pour le droit.
          return _arret(
            ArretEnvoiRecus.posteNonReconnu,
            403,
            envoyes,
            refuses,
            restes + (attente.length - i),
          );
        case ReponseHttp(statut: 404) when codeRefus == 'depense_inconnue':
          // Pas encore arrivée au serveur : elle viendra, le reçu attend.
          restes++;
        case ReponseHttp(:final statut)
            when statut == 408 || statut == 429 || statut >= 500:
          return _arret(
            ArretEnvoiRecus.serveurIndisponible,
            statut,
            envoyes,
            refuses,
            restes + (attente.length - i),
          );
        case ReponseHttp(:final statut, :final corps):
          // Un refus de FOND : définitif, avec la phrase du serveur.
          await dao.refuserRecu(
            recu.depenseId,
            _phrase(corps) ?? TextesRecuPoste.refuseParLeServeur(statut),
          );
          refuses++;
      }
    }
    return BilanEnvoiRecus(
      envoyes: envoyes,
      refuses: refuses,
      enAttente: restes,
    );
  }

  BilanEnvoiRecus _arret(
    ArretEnvoiRecus arret,
    int? code,
    int envoyes,
    int refuses,
    int restants,
  ) => BilanEnvoiRecus(
    envoyes: envoyes,
    refuses: refuses,
    enAttente: restants,
    arret: arret,
    codeHttp: code,
  );

  Future<bool> _creationAccusee(
    OperationsSyncDao file,
    String depenseId,
  ) async {
    final ops = await file.operations(
      table: TableSynchronisee.depenses,
      entiteId: depenseId,
    );
    return ops.any(
      (o) =>
          o.type == TypeOperationSync.creation &&
          o.statut == StatutOperationSync.synchronise,
    );
  }

  /// La phrase lisible d'un refus : `errors.photoRecu[0]`, à défaut `message`.
  static String? _phrase(Map<String, Object?>? corps) {
    final erreurs = corps?['errors'];
    if (erreurs is Map) {
      final recu = erreurs['photoRecu'];
      if (recu is List && recu.isNotEmpty && recu.first is String) {
        return recu.first as String;
      }
    }
    final message = corps?['message'];
    return message is String && message.isNotEmpty ? message : null;
  }
}
