import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../transverse/data/configuration_poste.dart';
import '../domain/descente_catalogue.dart' show libelleTableServeur;
import '../domain/operation_sync.dart';
import 'operations_sync_dao.dart';
import 'transport_synchronisation.dart';

/// Un compte d'un jour : nombre de documents actifs, total en centimes
/// (`null` quand la table ne compare que le nombre).
typedef CompteJour = ({int nombre, int? total});

/// Un écart entre ce que le serveur détient et ce que ce poste tient.
final class EcartCoherence {
  const EcartCoherence({
    required this.table,
    required this.jour,
    required this.serveur,
    required this.poste,
  });

  final String table;
  final String jour;
  final CompteJour serveur;
  final CompteJour poste;

  String get libelleTable => libelleTableServeur(table);
}

sealed class IssueCoherence {
  const IssueCoherence();
}

final class CoherenceMesuree extends IssueCoherence {
  const CoherenceMesuree({
    required this.du,
    required this.au,
    required this.ecarts,
    required this.tables,
    required this.enAttente,
  });

  final String du;
  final String au;
  final List<EcartCoherence> ecarts;

  /// Les tables comparées (celles que le compte lit au serveur).
  final List<String> tables;

  /// Les opérations de ce poste pas encore parties : un écart peut venir
  /// d'elles.
  final int enAttente;

  /// Le dernier jour JUSQU'AUQUEL tout concorde (`null` : un écart dès le
  /// premier jour de la fenêtre).
  String? get toutRecuJusquAu {
    if (ecarts.isEmpty) return au;
    final premier = ecarts
        .map((e) => e.jour)
        .reduce((a, b) => a.compareTo(b) <= 0 ? a : b);
    final veille = DateTime.parse(premier).subtract(const Duration(days: 1));
    final v = _jourIso(veille);
    return v.compareTo(du) < 0 ? null : v;
  }
}

final class CoherenceIndisponible extends IssueCoherence {
  const CoherenceIndisponible(this.raison);

  final String raison;
}

/// Le CONTRÔLE DE COHÉRENCE du poste (P1-1 de la spécification de
/// synchronisation, 18/10/2026) : le serveur rend, par table et par jour
/// MÉTIER, le nombre de documents actifs et leur total
/// (`GET /api/v1/sync/coherence`) ; ce poste fait le même compte sur ses
/// propres tables — ses documents ET ceux descendus des autres postes — et
/// rend les écarts. Lecture seule : rien n'est écrit, rien n'est corrigé.
class ControleCoherence {
  ControleCoherence({
    required this._db,
    required this._transport,
    required String? urlServeur,
    LecteurConfigurationPoste? lecteur,
  }) : _url = urlServeur,
       _lecteur = lecteur ?? LecteurConfigurationPoste();

  final AppDatabase _db;
  final TransportSynchronisation _transport;
  final String? _url;
  final LecteurConfigurationPoste _lecteur;

  static const String horsReseau =
      'Le serveur ne répond pas : le contrôle de cohérence compare ce poste '
      'au serveur, il exige une connexion.';
  static const String desactivee =
      'La synchronisation est désactivée sur ce poste : le contrôle de '
      'cohérence compare ce poste au serveur, il reprend à la réactivation.';
  static const String nonAppaire =
      'Ce poste n’est pas appairé à un serveur : rien à comparer.';

  /// Le même compte que `CoherenceService::INDICATEURS` au serveur, sur les
  /// tables de ce poste : jour métier (heure LOCALE, celle du serveur) et
  /// total en centimes.
  static const Map<String, ({String sql, bool total})> requetes = {
    'ventes': (
      sql:
          "SELECT date(cloture_le, 'unixepoch', 'localtime') AS jour, "
          'COUNT(*) AS nombre, SUM(montant_cloture) * 100 AS total '
          "FROM paniers_local WHERE statut = 'cloture' AND cloture_le IS NOT NULL",
      total: true,
    ),
    'depenses': (
      sql:
          "SELECT date(d.date_transaction, 'unixepoch', 'localtime') AS jour, "
          'COUNT(*) AS nombre, SUM((SELECT COALESCE(SUM(l.montant), 0) '
          'FROM lignes_depense_local l WHERE l.depense_id = d.id)) * 100 '
          'AS total FROM depenses_local d WHERE 1 = 1',
      total: true,
    ),
    'paiements': (
      sql:
          "SELECT date(date_paiement, 'unixepoch', 'localtime') AS jour, "
          'COUNT(*) AS nombre, SUM(montant_centimes) AS total '
          "FROM paiements_facture_local WHERE statut <> 'annule'",
      total: true,
    ),
    'factures': (
      sql:
          "SELECT date(date_emission, 'unixepoch', 'localtime') AS jour, "
          'COUNT(*) AS nombre, NULL AS total '
          'FROM pieces_facturation_local WHERE avoir_de IS NULL',
      total: false,
    ),
    'reservations': (
      sql:
          "SELECT date(date_arrivee, 'unixepoch') AS jour, "
          'COUNT(*) AS nombre, NULL AS total '
          "FROM reservations_local WHERE statut <> 'annulee'",
      total: false,
    ),
    'reglements_fournisseur': (
      sql:
          'SELECT date_reglement AS jour, COUNT(*) AS nombre, '
          'SUM(montant_centimes) AS total '
          "FROM reglements_fournisseur_local WHERE statut <> 'annule'",
      total: true,
    ),
    'mouvements_stock': (
      sql:
          "SELECT date(date_mouvement, 'unixepoch', 'localtime') AS jour, "
          'COUNT(*) AS nombre, SUM(CAST(ROUND(quantite * 100) AS INTEGER)) '
          'AS total FROM mouvements_stock_local WHERE 1 = 1',
      total: true,
    ),
  };

  /// Les [jours] derniers jours, jusqu'à [aujourdHui] compris.
  Future<IssueCoherence> controler({
    required DateTime aujourdHui,
    int jours = 7,
  }) async {
    if (_url == null) return const CoherenceIndisponible(nonAppaire);
    if (!await _lecteur.synchronisationActivee()) {
      return const CoherenceIndisponible(desactivee);
    }
    final appairage = await _lecteur.appairage();
    if (appairage == null || appairage.refus != null) {
      return const CoherenceIndisponible(nonAppaire);
    }
    final au = _jourIso(aujourdHui);
    final du = _jourIso(aujourdHui.subtract(Duration(days: jours - 1)));
    final issue = await _transport.get(
      urlServeur(
        appairage.serveur,
        '/sync/coherence',
      ).replace(queryParameters: {'du': du, 'au': au}),
      jeton: appairage.jetonApi,
    );
    final corps = issue is ReponseHttp && issue.estSucces ? issue.corps : null;
    final data = corps == null ? null : corps['data'];
    final tables = data is Map ? data['tables'] : null;
    if (tables is! Map) return const CoherenceIndisponible(horsReseau);

    final ecarts = <EcartCoherence>[];
    final comparees = <String>[];
    for (final e in tables.entries) {
      final table = '${e.key}';
      final requete = requetes[table];
      if (requete == null) continue;
      comparees.add(table);
      final serveur = _lireServeur(e.value);
      final poste = await _comptesLocaux(requete.sql, du, au);
      for (final jour in {...serveur.keys, ...poste.keys}.toList()..sort()) {
        final s = serveur[jour] ?? (nombre: 0, total: requete.total ? 0 : null);
        final p = poste[jour] ?? (nombre: 0, total: requete.total ? 0 : null);
        if (s.nombre != p.nombre || (requete.total && s.total != p.total)) {
          ecarts.add(
            EcartCoherence(table: table, jour: jour, serveur: s, poste: p),
          );
        }
      }
    }
    final comptes = await OperationsSyncDao(_db).compteParStatut();
    return CoherenceMesuree(
      du: du,
      au: au,
      ecarts: ecarts,
      tables: comparees,
      enAttente:
          (comptes[StatutOperationSync.enAttente] ?? 0) +
          (comptes[StatutOperationSync.enCours] ?? 0) +
          (comptes[StatutOperationSync.bloque] ?? 0),
    );
  }

  Future<Map<String, CompteJour>> _comptesLocaux(
    String sql,
    String du,
    String au,
  ) async {
    final lignes = await _db
        .customSelect(
          'SELECT jour, nombre, total FROM ($sql GROUP BY jour) '
          'WHERE jour BETWEEN ? AND ?',
          variables: [Variable.withString(du), Variable.withString(au)],
        )
        .get();
    return {
      for (final l in lignes)
        l.data['jour'] as String: (
          nombre: l.data['nombre'] as int,
          total: (l.data['total'] as num?)?.round(),
        ),
    };
  }

  static Map<String, CompteJour> _lireServeur(Object? brut) {
    if (brut is! Map) return const {};
    return {
      for (final e in brut.entries)
        if (e.value is Map)
          '${e.key}': (
            nombre: ((e.value as Map)['nombre'] as num?)?.toInt() ?? 0,
            total: ((e.value as Map)['total'] as num?)?.toInt(),
          ),
    };
  }
}

String _jourIso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
