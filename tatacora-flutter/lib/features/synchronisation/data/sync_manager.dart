import 'dart:convert';

import '../../comptabilite/data/immobilisations_dao.dart';
import '../../facturation/data/facture_dao.dart';
import '../../pos/data/panier_dao.dart';
import '../../rh/data/employe_dao.dart';
import '../../rh/data/paie_dao.dart';
import '../../transverse/data/configuration_poste.dart';
import '../domain/bilan_synchronisation.dart';
import '../domain/descente_catalogue.dart';
import '../domain/operation_sync.dart';
import 'descente_catalogue.dart';
import 'descente_catalogue_dao.dart';
import 'operations_sync_dao.dart';
import 'transport_synchronisation.dart';

/// Le MOTEUR D'ENVOI de la file (lot F2a, 15/10/2026) — `POST /api/v1/sync`.
///
/// ## Un seul point d'entrée : [synchroniserMaintenant]
///
/// Appelé par trois déclencheurs, tous réels (`providers_synchronisation.dart`) :
/// le démarrage du poste puis toutes les 5 minutes (`main.dart`), et la
/// clôture de caisse (`cloturerLaCaisse`, sans l'attendre). Le bouton
/// « Synchroniser maintenant » de Paramètres → Synchronisation l'appelle aussi.
/// Rien n'attend jamais la synchronisation : aucun geste n'en dépend.
///
/// ## Un seul envoi à la fois
///
/// Dans le processus : un appel pendant un autre rend le MÊME futur. Entre
/// processus (deux fenêtres sur la même base) : le bail de
/// [OperationsSyncDao.reclamerLot] — une opération `en_cours` sous un bail
/// non échu n'est réclamée par personne d'autre.
///
/// ## La politique d'erreur (convenue au plan du lot)
///
///  * pas de réponse, délai, 408, 429, 5xx → le lot redevient `en_attente`
///    avec un repli (30 s → 2 min → 5 min → 15 min → 1 h, ou le
///    `Retry-After` du serveur) ; la synchronisation s'arrête ;
///  * 401 → jeton refusé : le lot est rendu INTACT, le refus est consigné dans
///    `poste.json`, plus aucun envoi avant un nouvel appairage ;
///  * 403 → poste non reconnu : idem ;
///  * 409 `generation_perimee` → le serveur a été réinitialisé depuis : le
///    lot est rendu INTACT, la réinitialisation est consignée, plus rien ne
///    part ni n'arrive avant la réinitialisation de CE poste (19/10/2026) ;
///  * 422 sur le lot ENTIER → bissection : le lot est coupé en deux, puis
///    encore, jusqu'à isoler la ou les opérations fautives — elles seules sont
///    `rejete` (code 422, phrase du serveur), les autres partent ;
///  * 413 → la taille du lot est divisée par deux, et le lot renvoyé en deux ;
///  * tout autre 4xx → les opérations du lot sont `rejete` avec ce code, état
///    [EtatSynchronisation.alerte], arrêt ;
///  * 200 → chaque résultat est consigné tel quel
///    ([OperationsSyncDao.marquerResultat]).
///
/// Rien n'est jamais supprimé de la file.
///
/// ## Puis la DESCENTE du catalogue (lot F2b)
///
/// Après l'envoi, dans le même passage, [DescenteCatalogue] descend le
/// catalogue du serveur (`GET /referentiels`) — sauf refus 401/403 (de
/// l'envoi ou de la descente elle-même). Elle a son PROPRE repli : un
/// échec de la descente ne retarde jamais un envoi, et un serveur
/// indisponible à l'envoi n'empêche pas d'essayer la descente.
///
/// ## Le bail se RENOUVELLE avant chaque requête
///
/// Une bissection sur un réseau lent peut durer plus que le bail initial :
/// avant CHAQUE `POST /sync`, le bail du lot est prolongé
/// ([OperationsSyncDao.prolongerBail]) — un autre processus ne reprend
/// jamais un lot en cours d'envoi.
class SyncManager {
  SyncManager({
    required this._dao,
    required this._transport,
    required String? urlServeur,
    required this._demonstration,
    LecteurConfigurationPoste? lecteur,
    EcrivainConfigurationPoste? ecrivain,
    DateTime Function()? maintenant,
    this.tailleLot = 50,
    this.bail = const Duration(minutes: 5),
    this._surBilan,
    this._descente,
  }) : _url = urlServeur,
       _lecteur = lecteur ?? LecteurConfigurationPoste(),
       _ecrivain = ecrivain ?? EcrivainConfigurationPoste(),
       _maintenant = maintenant ?? DateTime.now;

  final OperationsSyncDao _dao;
  final TransportSynchronisation _transport;
  final String? _url;
  final bool _demonstration;
  final LecteurConfigurationPoste _lecteur;
  final EcrivainConfigurationPoste _ecrivain;
  final DateTime Function() _maintenant;
  final void Function(BilanSynchronisation)? _surBilan;

  /// La descente du catalogue (lot F2b) ; `null` : envoi seul.
  final DescenteCatalogue? _descente;

  /// La taille d'un lot — 50, le plafond de `SynchroniserRequest`.
  final int tailleLot;

  /// Le bail d'un lot réclamé. Il couvre une bissection complète (une
  /// douzaine de requêtes de 20 s au plus) ; un processus tué laisse ses
  /// opérations reprises à son échéance (`libererBauxExpires`).
  final Duration bail;

  /// Un garde-fou : aucune synchronisation n'émet plus de requêtes que cela.
  static const int maxRequetes = 2000;

  Future<BilanSynchronisation>? _enCours;

  /// L'état de synchronisation du poste : la génération des données
  /// retenue, la réinitialisation du serveur constatée (19/10/2026).
  late final DescenteCatalogueDao _etat = DescenteCatalogueDao(
    _dao.attachedDatabase,
    maintenant: _maintenant,
  );

  /// Synchronise la file, jusqu'à ce qu'aucune opération ne soit échue ou
  /// qu'une condition d'arrêt survienne. Ne lève jamais.
  Future<BilanSynchronisation> synchroniserMaintenant() {
    final enCours = _enCours;
    if (enCours != null) return enCours;
    final nouveau = _executerSansLever();
    _enCours = nouveau;
    nouveau.whenComplete(() => _enCours = null).ignore();
    return nouveau;
  }

  /// La dernière demande « Synchroniser » du serveur déjà suivie par ce
  /// poste (en mémoire : au redémarrage, la première lue est suivie — une
  /// synchronisation de plus, jamais une de moins).
  String? _demandeSuivie;

  /// Le PASSAGE COURT (toutes les 30 s, décision PO du 18/10/2026 : « le
  /// serveur doit avoir aussi le bouton synchroniser ») : lit la dernière
  /// demande faite à la PWA (`GET /sync/demande`) ; une demande nouvelle
  /// lance aussitôt la synchronisation complète — envoi de la file, puis
  /// descente de tout ce que le serveur détient. Rend vrai si une
  /// synchronisation a été lancée. Ne lève jamais ; ne fait rien sur un
  /// poste non appairé, refusé ou en démonstration.
  Future<bool> suivreDemandeDuServeur() async {
    try {
      final url = _url;
      if (_demonstration || url == null) return false;
      // L'interrupteur éteint : aucune requête, pas même la lecture de la
      // demande du serveur.
      if (!await _lecteur.synchronisationActivee()) return false;
      final appairage = await _lecteur.appairage();
      if (appairage == null ||
          appairage.refus != null ||
          _normaliser(appairage.serveur) != _normaliser(url)) {
        return false;
      }
      if (await _etat.reinitialisationServeur() != null) return false;
      final generation = await _etat.generation();
      final issue = await _transport.get(
        urlServeur(appairage.serveur, '/sync/demande').replace(
          queryParameters: {
            'poste_id': appairage.posteId,
            'generation': ?generation,
          },
        ),
        jeton: appairage.jetonApi,
      );
      final reinitialise = reinitialisationRefusee(issue, _maintenant());
      if (reinitialise != null) {
        await _etat.consignerReinitialisationServeur(reinitialise);
        return false;
      }
      if (issue is! ReponseHttp || issue.statut != 200) return false;
      await _etat.retenirAnnoncesServeur(issue.entetes);
      final data = issue.corps?['data'];
      final demande = data is Map ? data['demandee_le'] : null;
      if (demande is! String || demande == _demandeSuivie) return false;
      _demandeSuivie = demande;
      await _descente?.leverRepli();
      await synchroniserMaintenant();
      return true;
    } on Object {
      return false;
    }
  }

  Future<BilanSynchronisation> _executerSansLever() async {
    BilanSynchronisation bilan;
    try {
      bilan = await _executer();
    } on Object catch (e) {
      // Une base fermée pendant l'arrêt, un fichier verrouillé : rien ne
      // remonte jusqu'à un geste. Les opérations réclamées retrouveront la
      // file à l'échéance de leur bail.
      bilan = BilanSynchronisation(
        etat: EtatSynchronisation.alerte,
        detail: 'erreur interne : ${e.runtimeType}',
      );
    }
    try {
      _surBilan?.call(bilan);
    } on Object {
      // L'observateur ne casse pas le moteur.
    }
    return bilan;
  }

  Future<BilanSynchronisation> _executer() async {
    final url = _url;
    if (_demonstration || url == null) {
      return const BilanSynchronisation(
        etat: EtatSynchronisation.demonstration,
      );
    }
    // L'INTERRUPTEUR « Synchronisation activée » (Paramètres du poste), relu
    // à chaque passage : éteint, ni l'envoi, ni la descente du catalogue ne
    // touchent le réseau. La file, elle, continue de se remplir.
    if (!await _lecteur.synchronisationActivee()) {
      return const BilanSynchronisation(etat: EtatSynchronisation.desactivee);
    }
    final appairage = await _lecteur.appairage();
    if (appairage == null) {
      return const BilanSynchronisation(etat: EtatSynchronisation.nonAppaire);
    }
    final refus = appairage.refus;
    if (refus != null) {
      return BilanSynchronisation(
        etat: refus.codeHttp == 403
            ? EtatSynchronisation.posteNonReconnu
            : EtatSynchronisation.jetonRefuse,
        codeHttp: refus.codeHttp,
      );
    }
    if (_normaliser(appairage.serveur) != _normaliser(url)) {
      return const BilanSynchronisation(etat: EtatSynchronisation.autreServeur);
    }
    // Le serveur a été réinitialisé depuis (19/10/2026) : aucune requête
    // avant la réinitialisation de ce poste, qui oublie cet état.
    if (await _etat.reinitialisationServeur() != null) {
      return const BilanSynchronisation(
        etat: EtatSynchronisation.serveurReinitialise,
        codeHttp: 409,
      );
    }

    await _dao.libererBauxExpires();
    final envoi = await _envoyerFile(appairage);

    final descente = _descente;
    if (descente == null ||
        envoi.etat == EtatSynchronisation.jetonRefuse ||
        envoi.etat == EtatSynchronisation.posteNonReconnu ||
        envoi.etat == EtatSynchronisation.serveurReinitialise) {
      return envoi;
    }
    final bilanDescente = await descente.descendre(
      appairage,
      surRefus: _consignerRefus,
    );
    if (bilanDescente.etat == EtatDescente.serveurReinitialise) {
      return envoi.copierAvec(
        etat: EtatSynchronisation.serveurReinitialise,
        codeHttp: 409,
        descente: bilanDescente,
      );
    }
    if (bilanDescente.etat == EtatDescente.refusee) {
      // Le refus vaut pour tout le poste : plus rien ne part non plus.
      return envoi.copierAvec(
        etat: bilanDescente.codeHttp == 403
            ? EtatSynchronisation.posteNonReconnu
            : EtatSynchronisation.jetonRefuse,
        codeHttp: bilanDescente.codeHttp,
        descente: bilanDescente,
      );
    }
    return envoi.copierAvec(descente: bilanDescente);
  }

  /// L'ENVOI de la file : lot après lot, jusqu'à une file sans opération
  /// échue ou une condition d'arrêt.
  Future<BilanSynchronisation> _envoyerFile(AppairagePoste appairage) async {
    final c = _Contexte(
      appairage,
      urlServeur(appairage.serveur, '/sync'),
      taille: tailleLot,
    )..generation = await _etat.generation();
    while (c.requetes < maxRequetes) {
      final lot = await _dao.reclamerLot(taille: c.taille, bail: bail);
      if (lot.isEmpty) return c.bilan(EtatSynchronisation.termine);
      c.reclames = lot;
      c.lotId = lot.first.lotId;
      final arret = await _envoyer(lot, c);
      if (arret != null) {
        await _dao.rendreEnAttente([
          for (final o in lot)
            if (!c.traites.contains(o.uuidOperation)) o.uuidOperation,
        ]);
        return c.bilan(
          arret.etat,
          codeHttp: arret.codeHttp,
          detail: arret.detail,
        );
      }
    }
    return c.bilan(
      EtatSynchronisation.alerte,
      detail: 'plus de $maxRequetes requêtes en une synchronisation',
    );
  }

  static String _normaliser(String url) =>
      url.endsWith('/') ? url.substring(0, url.length - 1) : url;

  /// Envoie [ops] (une partie du lot réclamé) et consigne l'issue. Rend
  /// l'arrêt de la synchronisation, ou `null` pour continuer.
  Future<_Arret?> _envoyer(List<OperationSync> ops, _Contexte c) async {
    final aEnvoyer = [
      for (final o in ops)
        if (!c.traites.contains(o.uuidOperation)) o,
    ];
    if (aEnvoyer.isEmpty) return null;
    // Le bail est RENOUVELÉ avant chaque requête (lot F2b) : la précédente
    // a pu durer jusqu'au délai du transport, une bissection en enchaîne
    // une douzaine — sans renouvellement, un autre processus reprendrait le
    // lot en cours et l'enverrait une seconde fois.
    final lotId = c.lotId;
    if (lotId != null) await _dao.prolongerBail(lotId, bail);
    c.requetes++;
    final issue = await _transport.post(
      c.url,
      jeton: c.appairage.jetonApi,
      corps: {
        'poste_id': c.appairage.posteId,
        // La génération des données retenue (19/10/2026) — absente sur un
        // poste neuf ou réinitialisé, qui adopte celle du serveur.
        'generation': ?c.generation,
        'operations': [for (final o in aEnvoyer) _auProtocole(o)],
      },
    );

    final reinitialise = reinitialisationRefusee(issue, _maintenant());
    if (reinitialise != null) {
      await _etat.consignerReinitialisationServeur(reinitialise);
      return const _Arret(
        EtatSynchronisation.serveurReinitialise,
        codeHttp: 409,
      );
    }
    if (issue case ReponseHttp(
      :final statut,
      :final entetes,
    ) when statut >= 200 && statut < 300) {
      await _etat.retenirAnnoncesServeur(entetes);
      c.generation ??= entetes[enteteGeneration];
    }

    switch (issue) {
      case ServeurInjoignable(:final raison):
        return _transitoire(aEnvoyer, c, 'Serveur injoignable ($raison).');
      case ReponseHttp(:final statut) when statut >= 200 && statut < 300:
        return _appliquer(aEnvoyer, issue, c);
      case ReponseHttp(statut: 401):
        await _consignerRefus(401);
        return const _Arret(EtatSynchronisation.jetonRefuse, codeHttp: 401);
      case ReponseHttp(statut: 403):
        await _consignerRefus(403);
        return const _Arret(EtatSynchronisation.posteNonReconnu, codeHttp: 403);
      case ReponseHttp(statut: 413):
        if (aEnvoyer.length == 1) {
          await _rejeter(
            aEnvoyer.single,
            c,
            code: 413,
            motif:
                'Opération trop volumineuse pour le serveur (413) : elle ne '
                'peut pas être envoyée.',
          );
          return null;
        }
        final moitie = (aEnvoyer.length + 1) ~/ 2;
        if (moitie < c.taille) c.taille = moitie;
        return _parMoities(aEnvoyer, c);
      case ReponseHttp(statut: 422, :final corps):
        if (aEnvoyer.length == 1) {
          await _rejeter(
            aEnvoyer.single,
            c,
            code: 422,
            motif: _phrase422(corps),
            erreurs: corps?['errors'],
          );
          return null;
        }
        return _parMoities(aEnvoyer, c);
      case ReponseHttp(:final statut, :final entetes)
          when statut == 408 || statut == 429 || statut >= 500:
        return _transitoire(
          aEnvoyer,
          c,
          'Serveur indisponible (HTTP $statut).',
          codeHttp: statut,
          retryAfter: lireRetryAfter(entetes['retry-after'], _maintenant()),
        );
      case ReponseHttp(:final statut):
        for (final o in aEnvoyer) {
          await _rejeter(
            o,
            c,
            code: statut,
            motif: 'Refusée par le serveur (HTTP $statut).',
          );
        }
        return _Arret(
          EtatSynchronisation.alerte,
          codeHttp: statut,
          detail: 'HTTP $statut sur un lot',
        );
    }
  }

  /// Bissection : la première moitié, puis la seconde, dans l'ordre de `seq`.
  Future<_Arret?> _parMoities(List<OperationSync> ops, _Contexte c) async {
    final milieu = (ops.length + 1) ~/ 2;
    final arret = await _envoyer(ops.sublist(0, milieu), c);
    if (arret != null) return arret;
    return _envoyer(ops.sublist(milieu), c);
  }

  /// Le serveur a répondu 2xx : un résultat par opération, consigné tel quel.
  Future<_Arret?> _appliquer(
    List<OperationSync> ops,
    ReponseHttp reponse,
    _Contexte c,
  ) async {
    final liste = reponse.corps?['resultats'];
    if (liste is! List) {
      return _transitoire(
        ops,
        c,
        'Réponse illisible du serveur (HTTP ${reponse.statut}).',
        codeHttp: reponse.statut,
        etat: EtatSynchronisation.alerte,
      );
    }
    final parUuid = <String, Map<String, Object?>>{
      for (final r in liste)
        if (r is Map<String, Object?> && r['uuid_operation'] is String)
          r['uuid_operation']! as String: r,
    };
    final envoyes = {for (final o in ops) o.uuidOperation};
    final sansResultat = <OperationSync>[];
    for (final o in ops) {
      final resultat = parUuid[o.uuidOperation];
      if (resultat == null || !_statutsConnus.contains(resultat['statut'])) {
        sansResultat.add(o);
        continue;
      }
      await _consigner(o, resultat, c, codeHttp: reponse.statut, lot: envoyes);
    }
    if (sansResultat.isEmpty) return null;
    return _transitoire(
      sansResultat,
      c,
      'Réponse incomplète du serveur : ${sansResultat.length} opération(s) '
      'sans résultat lisible.',
      codeHttp: reponse.statut,
      etat: EtatSynchronisation.alerte,
    );
  }

  static const _statutsConnus = {
    'synchronise',
    'cloture_sans_session_serveur',
    'rejete',
    'conflit',
  };

  /// Consigne un résultat. Un REJET bloque d'abord les opérations suivantes
  /// du même élément encore réclamées et non envoyées dans la requête en
  /// cours : elles redeviennent `en_attente`, et `marquerResultat` les
  /// bloque (règle de F1) — l'envoi d'une bissection ne les fera pas partir
  /// sur un état que le serveur n'a pas.
  Future<void> _consigner(
    OperationSync o,
    Map<String, Object?> resultat,
    _Contexte c, {
    required int codeHttp,
    Set<String> lot = const {},
  }) async {
    final statut = resultat['statut'];
    if (statut == 'rejete') {
      final suivantes = [
        for (final s in c.reclames)
          if (s.seq > o.seq &&
              s.table == o.table &&
              s.entiteId == o.entiteId &&
              !c.traites.contains(s.uuidOperation) &&
              !lot.contains(s.uuidOperation))
            s.uuidOperation,
      ];
      await _dao.rendreEnAttente(suivantes);
      c.traites.addAll(suivantes);
    }
    await _dao.marquerResultat(
      o.uuidOperation,
      resultat: resultat,
      codeHttp: codeHttp,
    );
    if (statut == 'synchronise' && o.table == TableSynchronisee.factures) {
      await _regulariserFacture(o, resultat);
    }
    // Audit de couverture (18/10/2026) : le matricule et le numéro de
    // bulletin attribués par le serveur remplacent ceux du poste.
    final matricule = resultat['matricule'];
    if (statut == 'synchronise' &&
        o.table == TableSynchronisee.employes &&
        matricule is String) {
      await EmployeDao(
        _dao.attachedDatabase,
      ).regulariserMatricule(o.entiteId, matricule);
    }
    // 21/10/2026 : le code `IMMO-AAAA-NNNNN` du serveur remplace celui du poste.
    final codeImmobilisation = resultat['code'];
    if (statut == 'synchronise' &&
        o.table == TableSynchronisee.immobilisations &&
        resultat['fusionne_avec'] == null &&
        codeImmobilisation is String) {
      await ImmobilisationsDao(
        _dao.attachedDatabase,
      ).regulariserCode(o.entiteId, codeImmobilisation);
    }
    // 26/10/2026 : le numéro `V-` de la vente est celui du serveur (séquence
    // continue) — il ne se pose qu'à l'accusé, le poste n'en invente aucun.
    final numeroVente = resultat['numero'];
    if (statut == 'synchronise' &&
        o.table == TableSynchronisee.ventes &&
        o.type == TypeOperationSync.creation &&
        numeroVente is String) {
      await PanierDao(
        _dao.attachedDatabase,
      ).regulariserNumeroVente(o.entiteId, numeroVente);
    }
    final numeroBulletin = resultat['numero'];
    if (statut == 'synchronise' &&
        o.table == TableSynchronisee.bulletinsPaie &&
        resultat['fusionne_avec'] == null &&
        numeroBulletin is String) {
      await PaieDao(
        _dao.attachedDatabase,
      ).regulariserNumero(o.entiteId, numeroBulletin);
    }
    c.traites.add(o.uuidOperation);
    c.envoyees++;
    switch (statut) {
      case 'rejete':
        c.rejetees++;
      case 'conflit':
        c.conflits++;
      default:
        c.synchronisees++;
    }
  }

  /// Lot F5c : le numéro continu rendu par le serveur remplace le
  /// provisoire (et celui de l'avoir, pour une annulation). Une
  /// régularisation impossible (numéro déjà porté par une pièce reçue) ne
  /// change rien à l'envoi : la descente de la facture la retente, et la
  /// compte refusée si elle échoue encore.
  Future<void> _regulariserFacture(
    OperationSync o,
    Map<String, Object?> resultat,
  ) async {
    final numero = resultat['numero'];
    final numeroAvoir = resultat['numero_avoir'];
    // Un avoir PARTIEL est né sous l'identifiant du poste : son numéro se pose
    // sur CET avoir (pas sur « le premier avoir » de la facture).
    final avoirId = resultat['avoir_id'];
    final factures = FactureDao(_dao.attachedDatabase);
    try {
      if (avoirId is String && numeroAvoir is String) {
        await factures.regulariserNumeros(
          o.entiteId,
          numero: numero is String ? numero : null,
        );
        await factures.regulariserAvoir(avoirId, numeroAvoir);
        return;
      }
      await factures.regulariserNumeros(
        o.entiteId,
        numero: numero is String ? numero : null,
        numeroAvoir: numeroAvoir is String ? numeroAvoir : null,
      );
    } on StateError {
      // Voir la doc : la descente reprend.
    }
  }

  Future<void> _rejeter(
    OperationSync o,
    _Contexte c, {
    required int code,
    required String motif,
    Object? erreurs,
  }) => _consigner(
    o,
    {
      'uuid_operation': o.uuidOperation,
      'statut': 'rejete',
      'entite_id': o.entiteId,
      'motif': motif,
      'code_http': code,
      'erreurs': ?erreurs,
    },
    c,
    codeHttp: code,
  );

  /// Échec transitoire : chaque opération attend son repli (ou le
  /// `Retry-After`), et la synchronisation s'arrête.
  Future<_Arret> _transitoire(
    List<OperationSync> ops,
    _Contexte c,
    String erreur, {
    int? codeHttp,
    Duration? retryAfter,
    EtatSynchronisation etat = EtatSynchronisation.serveurIndisponible,
  }) async {
    final maintenant = _maintenant();
    DateTime? prochaine;
    for (final o in ops) {
      final delai = retryAfter ?? delaiDeRepli(o.tentatives);
      await _dao.marquerEchecTransitoire(
        o.uuidOperation,
        erreur: erreur,
        codeHttp: codeHttp,
        delai: delai,
      );
      c.traites.add(o.uuidOperation);
      final echeance = maintenant.add(delai);
      if (prochaine == null || echeance.isBefore(prochaine)) {
        prochaine = echeance;
      }
    }
    c.prochaineTentative = prochaine;
    return _Arret(etat, codeHttp: codeHttp, detail: erreur);
  }

  Future<void> _consignerRefus(int code) async {
    try {
      await _ecrivain.consignerRefus(code, _maintenant());
    } on Object {
      // Fichier illisible : le prochain envoi rencontrera le même refus.
    }
  }

  static String _phrase422(Map<String, Object?>? corps) {
    final erreurs = corps?['errors'];
    if (erreurs is Map) {
      for (final v in erreurs.values) {
        if (v is List && v.isNotEmpty && v.first is String) {
          return 'Refusée par le serveur (422) : ${v.first}';
        }
      }
    }
    final message = corps?['message'];
    return message is String && message.isNotEmpty
        ? 'Refusée par le serveur (422) : $message'
        : 'Refusée par le serveur (422) : opération invalide.';
  }

  static Map<String, Object?> _auProtocole(OperationSync o) => {
    'uuid_operation': o.uuidOperation,
    'table': o.table.nomServeur,
    'type': o.type.code,
    'entite_id': o.entiteId,
    'payload': jsonDecode(o.payload),
    'horodatage_client': o.horodatageClient,
  };
}

final class _Arret {
  const _Arret(this.etat, {this.codeHttp, this.detail});

  final EtatSynchronisation etat;
  final int? codeHttp;
  final String? detail;
}

/// L'état d'UNE synchronisation.
final class _Contexte {
  _Contexte(this.appairage, this.url, {required this.taille});

  final AppairagePoste appairage;
  final Uri url;

  /// La taille des lots réclamés — divisée par deux sur un 413.
  int taille;
  int requetes = 0;
  int envoyees = 0;
  int synchronisees = 0;
  int rejetees = 0;
  int conflits = 0;
  DateTime? prochaineTentative;

  /// Le lot réclamé en cours.
  List<OperationSync> reclames = const [];

  /// L'identifiant du lot réclamé en cours (renouvellement du bail).
  String? lotId;

  /// La génération des données rappelée au serveur (`null` : à adopter).
  String? generation;

  /// Les opérations du lot dont le sort est consigné.
  final Set<String> traites = {};

  BilanSynchronisation bilan(
    EtatSynchronisation etat, {
    int? codeHttp,
    String? detail,
  }) => BilanSynchronisation(
    etat: etat,
    lots: requetes,
    envoyees: envoyees,
    synchronisees: synchronisees,
    rejetees: rejetees,
    conflits: conflits,
    codeHttp: codeHttp,
    detail: detail,
    prochaineTentative: prochaineTentative,
  );
}
