import 'dart:convert';

import '../../../core/database/app_database.dart';
import '../../comptabilite/data/moteur_comptable.dart';
import '../../transverse/data/configuration_poste.dart';
import '../domain/bilan_synchronisation.dart';
import '../domain/descente_catalogue.dart';
import '../domain/journal_reception.dart';
import '../domain/operation_sync.dart';
import 'aligneur_catalogue.dart';
import 'descente_catalogue_dao.dart';
import 'journal_reception_dao.dart';
import 'operations_sync_dao.dart';
import 'transport_synchronisation.dart';

/// La DESCENTE du catalogue (lot F2b, 15/10/2026) — `GET /api/v1/referentiels`.
///
/// Appelée par `SyncManager.synchroniserMaintenant` APRÈS l'envoi de la
/// file, dans le même passage — et seulement quand le poste est appairé,
/// hors démonstration, sans refus 401/403 en cours.
///
/// ## L'algorithme
///
/// 1. Repli PROPRE : si un échec précédent a posé une prochaine tentative
///    non échue, aucune requête (la file, elle, est déjà partie : un échec
///    de la descente ne retarde jamais un envoi).
/// 2. Les fusions déjà rendues à l'envoi (`fusionne_avec`) sont retenues en
///    correspondances : un élément du poste fusionné ne redescend pas en
///    doublon sous l'identifiant serveur.
/// 3. Page après page, avec le curseur OPAQUE stocké : chaque page est
///    appliquée dans UNE transaction — correspondances, puis chaque élément
///    isolé dans un point de sauvegarde (une ligne fautive n'emporte pas la
///    page, piège 11), puis le curseur. Un arrêt au milieu rejoue la page
///    entière : chaque écriture est un alignement idempotent.
/// 4. Ce qui ne peut pas s'écrire encore (dépendance absente, modification
///    locale non poussée) est GARDÉ et repris en fin de descente — en boucle
///    tant qu'un élément passe — puis à la descente suivante.
/// 5. Le bilan est consigné pour l'écran de synchronisation.
///
/// ## La politique d'erreur (celle de l'envoi, sur son propre repli)
///
///  * pas de réponse, 408, 429, 5xx, réponse illisible → repli 30 s → 2 min
///    → 5 min → 15 min → 1 h (ou `Retry-After`) ;
///  * 401 / 403 → refus consigné dans `poste.json` (plus rien avant
///    réappairage, envoi compris) ;
///  * 422 sur un curseur → le curseur est oublié et la descente repart du
///    début (sans dommage : écritures idempotentes) ;
///  * autre 4xx → alerte, repli.
class DescenteCatalogue {
  DescenteCatalogue({
    required this._db,
    required this._transport,
    required this._auteur,
    DateTime Function()? maintenant,
    this.limite = 200,
    this.maxPages = 500,
    this.avantCurseur,
    this.moteur,
  }) : _maintenant = maintenant ?? DateTime.now;

  /// Lot F6 (18/10/2026) : le moteur comptable du poste, pour la SEULE
  /// contre-passation de la pièce d'un document de CE poste que le serveur
  /// a annulé (vente, encaissement, règlement). Un document descendu d'un
  /// autre poste n'a pas de pièce ici (Q1) : rien n'est passé pour lui.
  final Future<MoteurComptable> Function()? moteur;

  final AppDatabase _db;
  final TransportSynchronisation _transport;
  final Future<String?> Function() _auteur;
  final DateTime Function() _maintenant;

  /// La taille de page demandée (200 par défaut au serveur, 500 au plus).
  final int limite;

  /// Un garde-fou : aucune descente ne lit plus de pages que cela.
  final int maxPages;

  /// ESSAI SEULEMENT : appelé dans la transaction d'une page, après ses
  /// éléments et avant le curseur — un test y simule un arrêt brutal.
  final void Function()? avantCurseur;

  static const _motifsMax = 20;

  late final DescenteCatalogueDao _dao = DescenteCatalogueDao(
    _db,
    maintenant: _maintenant,
  );

  /// Le journal de réception (v37) : cette classe en est le SEUL appelant.
  late final JournalReceptionDao _journal = JournalReceptionDao(
    _db,
    maintenant: _maintenant,
  );

  /// Les éléments déjà consignés dans le passage en cours.
  final Set<String> _vuCetPassage = {};
  late final AligneurCatalogue _aligneur = AligneurCatalogue(
    _db,
    _dao,
    auteur: _auteur,
    maintenant: _maintenant,
    moteur: moteur,
  );

  /// Descend le catalogue. Ne lève jamais. [surRefus] consigne un 401/403.
  Future<BilanDescente> descendre(
    AppairagePoste appairage, {
    required Future<void> Function(int code) surRefus,
  }) async {
    final c = _Compteurs();
    _vuCetPassage.clear();
    try {
      final bilan = await _descendre(appairage, surRefus, c);
      await _purgerJournal();
      return bilan;
    } on Object catch (e) {
      // Une base fermée pendant l'arrêt : rien ne remonte à un geste.
      return c.bilan(
        EtatDescente.alerte,
        motif: 'erreur interne : ${e.runtimeType}',
        maintenant: _maintenant(),
      );
    }
  }

  /// Les opérations de la file qui ne sont pas encore parties (en attente,
  /// en cours, bloquées).
  Future<int> _enAttente() async {
    final comptes = await OperationsSyncDao(_db).compteParStatut();
    return (comptes[StatutOperationSync.enAttente] ?? 0) +
        (comptes[StatutOperationSync.enCours] ?? 0) +
        (comptes[StatutOperationSync.bloque] ?? 0);
  }

  /// Une demande « Synchroniser » du serveur vient d'être lue : le serveur
  /// répond, le repli de la descente n'a plus de raison d'attendre.
  Future<void> leverRepli() => _dao.poserRepli(echecs: 0);

  Future<BilanDescente> _descendre(
    AppairagePoste appairage,
    Future<void> Function(int code) surRefus,
    _Compteurs c,
  ) async {
    final repli = await _dao.repli();
    final prochaine = repli.prochaine;
    if (prochaine != null && prochaine.isAfter(_maintenant())) {
      // Aucune requête ; la reprise des éléments gardés, elle, est locale.
      await _reprendre(c);
      return c.bilan(
        EtatDescente.enRepli,
        prochaineTentative: prochaine,
        maintenant: _maintenant(),
      );
    }

    await _db.transaction(_dao.retenirFusionsDeLaFile);

    var curseur = await _dao.curseur();
    final generation = await _dao.generation();
    var curseurOublie = false;
    var complet = false;
    _Echec? echec;
    for (var n = 0; n < maxPages; n++) {
      final url = urlServeur(appairage.serveur, '/referentiels').replace(
        queryParameters: {
          'poste_id': appairage.posteId,
          'depuis': ?curseur,
          'limite': '$limite',
          // Le bouton « Synchroniser » du serveur (18/10/2026) : la PWA
          // affiche la file que ce poste déclare encore à envoyer.
          'en_attente': '${await _enAttente()}',
          // La génération des données retenue (19/10/2026) : un serveur
          // réinitialisé depuis refuse (409) au lieu de servir un catalogue
          // que ce poste mêlerait à ses données d'essai.
          'generation': ?generation,
        },
      );
      final issue = await _transport.get(url, jeton: appairage.jetonApi);
      final reinitialise = reinitialisationRefusee(issue, _maintenant());
      if (reinitialise != null) {
        await _dao.consignerReinitialisationServeur(reinitialise);
        final bilan = c.bilan(
          EtatDescente.serveurReinitialise,
          codeHttp: 409,
          maintenant: _maintenant(),
        );
        await _dao.consignerBilan(bilan);
        return bilan;
      }
      if (issue case ReponseHttp(
        :final statut,
        :final entetes,
      ) when statut >= 200 && statut < 300) {
        await _dao.retenirAnnoncesServeur(entetes);
      }
      // Dans un `switch` de Dart 3, `break` sort du `switch` (pas de la
      // boucle) : chaque cas qui doit ARRÊTER la descente pose [echec] et
      // tombe sur le `break` qui suit ; `continue` passe à la page suivante.
      switch (issue) {
        case ServeurInjoignable():
          echec = const _Echec(EtatDescente.serveurIndisponible);
        case ReponseHttp(:final statut) when statut == 401 || statut == 403:
          await surRefus(statut);
          await _reprendre(c);
          final bilan = c.bilan(
            EtatDescente.refusee,
            codeHttp: statut,
            maintenant: _maintenant(),
          );
          await _dao.consignerBilan(bilan);
          return bilan;
        case ReponseHttp(statut: 422) when curseur != null && !curseurOublie:
          await _dao.effacerCurseur();
          curseur = null;
          curseurOublie = true;
          continue;
        case ReponseHttp(:final statut, :final entetes)
            when statut == 408 || statut == 429 || statut >= 500:
          echec = _Echec(
            EtatDescente.serveurIndisponible,
            codeHttp: statut,
            retryAfter: lireRetryAfter(entetes['retry-after'], _maintenant()),
          );
        case ReponseHttp(:final statut, :final corps)
            when statut >= 200 && statut < 300:
          final page = _Page.lire(corps);
          if (page == null) {
            echec = _Echec(EtatDescente.alerte, codeHttp: statut);
          } else {
            await _appliquerPage(page, c);
            curseur = page.curseur;
            complet = page.complet;
            if (!complet) continue;
          }
        case ReponseHttp(:final statut):
          echec = _Echec(EtatDescente.alerte, codeHttp: statut);
      }
      break;
    }
    // Le garde-fou de pages atteint sans `complet` : rien n'est perdu (le
    // curseur avance), mais la descente n'est pas « à jour ».
    if (echec == null && !complet) echec = const _Echec(EtatDescente.alerte);

    await _reprendre(c);
    final BilanDescente bilan;
    if (echec == null) {
      await _dao.poserRepli(echecs: 0);
      bilan = c.bilan(EtatDescente.aJour, maintenant: _maintenant());
    } else {
      final echecs = repli.echecs + 1;
      final delai = echec.retryAfter ?? delaiDeRepli(echecs);
      final suivante = _maintenant().add(delai);
      await _dao.poserRepli(echecs: echecs, prochaine: suivante);
      bilan = c.bilan(
        echec.etat,
        codeHttp: echec.codeHttp,
        prochaineTentative: suivante,
        maintenant: _maintenant(),
      );
    }
    await _dao.consignerBilan(bilan);
    return bilan;
  }

  /// UNE page, dans UNE transaction : correspondances, éléments (chacun
  /// isolé), puis le curseur — jamais avant.
  Future<void> _appliquerPage(_Page page, _Compteurs c) async {
    final local = _Compteurs();
    await _db.transaction(() async {
      for (final corr in page.correspondances) {
        await _dao.retenirCorrespondance(
          table: corr.table,
          idServeur: corr.idServeur,
          idLocal: corr.idPoste,
          origine: 'flux',
        );
      }
      for (final (rang, brut) in page.elements.indexed) {
        local.recus++;
        final e = ElementCatalogue.depuisJson(brut);
        if (e == null) {
          local.refuser('élément illisible du serveur');
          await _journal.consignerIllisible(brut, rang);
          continue;
        }
        final issue = await _isoler(e);
        await _consigner(e, issue, local);
      }
      avantCurseur?.call();
      await _dao.poserCurseur(page.curseur);
    });
    // La page est ÉCRITE : ses compteurs comptent.
    c.ajouter(local);
    c.pages++;
  }

  /// Aligne [e] dans un point de sauvegarde : une exception (contrainte
  /// imprévue) n'annule que lui, et il est compté refusé — jamais avalé.
  Future<IssueAlignement> _isoler(ElementCatalogue e) async {
    try {
      return await _db.transaction(() async {
        final issue = await _aligneur.aligner(e);
        return issue;
      });
    } on Object catch (x) {
      return RefuseParLePoste(
        'écriture impossible sur ce poste (${x.runtimeType})',
      );
    }
  }

  Future<void> _consigner(
    ElementCatalogue e,
    IssueAlignement issue,
    _Compteurs c, {
    bool automatique = false,
  }) async {
    // Une seule tentative par élément et par passage : la reprise de fin de
    // descente ne recompte pas un élément que la page vient de consigner.
    await _journal.consigner(
      e,
      issue,
      tentative: _vuCetPassage.add('${e.table.nomServeur}:${e.id}'),
      seulementSiChange: automatique,
    );
    switch (issue) {
      case Aligne(:final archiveNonPortee):
        c.appliques++;
        if (archiveNonPortee) c.archivesNonPortees++;
        await _dao.oublier(e.table, e.id);
      case RefuseParLePoste(:final motif):
        c.refuser('${libelleTableServeur(e.table.nomServeur)} : $motif');
        await _dao.oublier(e.table, e.id);
      case ConserveLocalement(:final raison):
        await _dao.garder(e, nature: 'conserve', motif: raison);
      case EnAttenteDeDependance(:final motif):
        await _dao.garder(e, nature: 'dependance', motif: motif);
    }
  }

  /// La REPRISE des éléments gardés, tant qu'un élément passe (un plat dont
  /// le menu vient de passer). Puis le décompte de ce qui reste gardé.
  Future<void> _reprendre(_Compteurs c) async {
    for (var tour = 0; tour < 20; tour++) {
      var progres = false;
      for (final g in await _dao.elementsGardes()) {
        final issue = await _db.transaction(() async {
          if (g.nature == 'conserve' &&
              await _modificationDuPosteAppliquee(g.element)) {
            // Le serveur a APPLIQUÉ la modification du poste (dernier écrit
            // gagnant) : la version gardée est périmée, la nouvelle
            // redescendra (son `updated_at` a bougé).
            await _dao.oublier(g.element.table, g.element.id);
            await _journal.consigner(
              g.element,
              const Aligne(),
              note: _noteVersionPerimee,
            );
            return null;
          }
          final i = await _isoler(g.element);
          await _consigner(g.element, i, c, automatique: true);
          return i;
        });
        if (issue == null || issue is Aligne || issue is RefuseParLePoste) {
          progres = true;
        }
      }
      if (!progres) break;
    }
    for (final g in await _dao.elementsGardes()) {
      if (g.nature == 'conserve') {
        c.conservesLocalement++;
      } else {
        c.enAttenteDeDependance++;
      }
    }
  }

  static const _noteVersionPerimee =
      'La modification faite sur ce poste a été appliquée par le serveur : la '
      'version reçue était périmée, la nouvelle redescendra.';

  /// La rétention du journal (30 jours, 5 000 lignes) — sans jamais gêner la
  /// descente.
  Future<void> _purgerJournal() async {
    try {
      await _journal.purger();
    } on Object {
      // Une base fermée pendant l'arrêt : la purge viendra à la suivante.
    }
  }

  /* ================================================================== */
  /* Relances demandées depuis l'écran (partie « Réception »)            */
  /* ================================================================== */

  /// « Relancer » UN élément du journal : rejoue l'aligneur sur l'élément
  /// gardé (`element_differe:*` ou, pour un refus, l'élément du journal),
  /// MAINTENANT et sans réseau. Ne lève jamais.
  Future<ResultatRelance> relancerElement(String table, String id) async {
    _vuCetPassage.clear();
    try {
      final entree = await _journal.lire(table, id);
      if (entree == null) return ResultatRelance.introuvable;
      var element = entree.element();
      var conserve = entree.issue == IssueReception.conserve;
      for (final g in await _dao.elementsGardes()) {
        if (g.element.table.nomServeur == table && g.element.id == id) {
          element = g.element;
          conserve = g.nature == 'conserve';
        }
      }
      if (element == null) return ResultatRelance.introuvable;
      final cible = element;
      final issue = await _db.transaction(() async {
        if (conserve && await _modificationDuPosteAppliquee(cible)) {
          await _dao.oublier(cible.table, cible.id);
          await _journal.consigner(
            cible,
            const Aligne(),
            note: _noteVersionPerimee,
          );
          return const Aligne();
        }
        final i = await _isoler(cible);
        await _consigner(cible, i, _Compteurs());
        return i;
      });
      if (issue is Aligne) {
        // Cet élément débloque peut-être ceux qui le citaient.
        await _reprendre(_Compteurs());
      }
      await _purgerJournal();
      return ResultatRelance(IssueReception.depuis(issue));
    } on Object {
      return ResultatRelance.impossible;
    }
  }

  /// « Relancer tout » : rejoue les éléments refusés du journal, puis la
  /// reprise de tous les éléments gardés — sans réseau. Rend ce qui reste à
  /// traiter. Ne lève jamais. La descente réseau, elle, repart de son curseur
  /// à l'appel suivant de `SyncManager.synchroniserMaintenant` (l'appelant
  /// lève d'abord le repli par [leverRepli]).
  Future<int> relancerTout() async {
    _vuCetPassage.clear();
    try {
      for (final e in await _journal.aRelancer()) {
        if (e.issue != IssueReception.refuse) continue;
        final element = e.element();
        if (element == null) continue;
        await _db.transaction(() async {
          final i = await _isoler(element);
          await _consigner(element, i, _Compteurs());
        });
      }
      await _reprendre(_Compteurs());
      await _purgerJournal();
      return (await _journal.compter()).aTraiter;
    } on Object {
      return -1;
    }
  }

  /// La dernière opération de l'élément (sur ce poste) est-elle une
  /// MODIFICATION que le serveur a appliquée — synchronisée, et pas
  /// `version_serveur_conservee` ? Tant qu'une opération attend, non.
  Future<bool> _modificationDuPosteAppliquee(ElementCatalogue e) async {
    final table = e.table.tableSynchronisee;
    if (table == null) return false;
    final idLocal = await _dao.idLocal(e.table.nomServeur, e.id);
    final file = OperationsSyncDao(_db);
    if (await file.enSuspens(table.nomServeur, idLocal)) return false;
    final derniere = await file.derniereOperation(table.nomServeur, idLocal);
    if (derniere == null ||
        derniere.type != TypeOperationSync.modification ||
        derniere.statut != StatutOperationSync.synchronise) {
      return false;
    }
    final resultat = derniere.resultatJson;
    if (resultat == null) return true;
    try {
      final r = jsonDecode(resultat);
      return !(r is Map && r['resolution'] == 'version_serveur_conservee');
    } on FormatException {
      return true;
    }
  }
}

final class _Echec {
  const _Echec(this.etat, {this.codeHttp, this.retryAfter});

  final EtatDescente etat;
  final int? codeHttp;
  final Duration? retryAfter;
}

/// Une page lue : `null` si la forme n'est pas celle du contrat.
final class _Page {
  const _Page(this.elements, this.correspondances, this.curseur, this.complet);

  final List<Object?> elements;
  final List<CorrespondanceServeur> correspondances;
  final String curseur;
  final bool complet;

  static _Page? lire(Map<String, Object?>? corps) {
    final data = corps?['data'];
    final meta = corps?['meta'];
    if (data is! Map || meta is! Map) return null;
    final elements = data['elements'];
    final correspondances = data['correspondances'];
    final curseur = meta['curseur'];
    final complet = meta['complet'];
    if (elements is! List ||
        correspondances is! List ||
        curseur is! String ||
        complet is! bool) {
      return null;
    }
    return _Page(
      elements,
      [
        for (final c in correspondances)
          if (c is Map &&
              c['table'] is String &&
              c['id_poste'] is String &&
              c['id_serveur'] is String)
            (
              table: c['table']! as String,
              idPoste: c['id_poste']! as String,
              idServeur: c['id_serveur']! as String,
            ),
      ],
      curseur,
      complet,
    );
  }
}

final class _Compteurs {
  int pages = 0;
  int recus = 0;
  int appliques = 0;
  int refuses = 0;
  int archivesNonPortees = 0;
  int conservesLocalement = 0;
  int enAttenteDeDependance = 0;
  final List<String> motifs = [];

  void refuser(String motif) {
    refuses++;
    if (motifs.length < DescenteCatalogue._motifsMax) motifs.add(motif);
  }

  void ajouter(_Compteurs autre) {
    recus += autre.recus;
    appliques += autre.appliques;
    archivesNonPortees += autre.archivesNonPortees;
    refuses += autre.refuses;
    for (final m in autre.motifs) {
      if (motifs.length < DescenteCatalogue._motifsMax) motifs.add(m);
    }
  }

  BilanDescente bilan(
    EtatDescente etat, {
    required DateTime maintenant,
    int? codeHttp,
    DateTime? prochaineTentative,
    String? motif,
  }) => BilanDescente(
    etat: etat,
    pages: pages,
    recus: recus,
    appliques: appliques,
    conservesLocalement: conservesLocalement,
    enAttenteDeDependance: enAttenteDeDependance,
    refuses: refuses,
    archivesNonPortees: archivesNonPortees,
    motifsRefus: [...motifs, ?motif],
    codeHttp: codeHttp,
    prochaineTentative: prochaineTentative,
    termineeLe: maintenant,
  );
}
