import 'dart:convert';

import 'controle_coherence.dart';

/// Le DERNIER contrôle de cohérence, rangé (clé `coherence.dernier` de
/// `etat_synchronisation_local`, écrite par `DescenteCatalogueDao`) pour que
/// la partie « Réception » de l'écran de synchronisation le relise après un
/// redémarrage, avec ses écarts. Un contrôle `CoherenceIndisponible` n'a rien
/// mesuré : il n'est pas rangé.
String coherenceVersJson(CoherenceMesuree m, DateTime le) {
  Map<String, Object?> compte(CompteJour c) => {
    'nombre': c.nombre,
    'total': c.total,
  };
  return jsonEncode({
    'le': le.toUtc().toIso8601String(),
    'du': m.du,
    'au': m.au,
    'tables': m.tables,
    'en_attente': m.enAttente,
    'ecarts': [
      for (final e in m.ecarts)
        {
          'table': e.table,
          'jour': e.jour,
          'serveur': compte(e.serveur),
          'poste': compte(e.poste),
        },
    ],
  });
}

/// Un contrôle rangé, relu.
typedef CoherenceRangee = ({DateTime le, CoherenceMesuree mesure});

/// Relit un contrôle rangé, ou `null` s'il est illisible.
CoherenceRangee? coherenceDepuisJson(String brut) {
  try {
    final j = jsonDecode(brut);
    if (j is! Map) return null;
    final le = DateTime.tryParse('${j['le']}');
    if (le == null || j['du'] is! String || j['au'] is! String) return null;
    CompteJour compte(Object? c) => c is Map
        ? (
            nombre: (c['nombre'] as num?)?.toInt() ?? 0,
            total: (c['total'] as num?)?.toInt(),
          )
        : (nombre: 0, total: null);
    return (
      le: le.toLocal(),
      mesure: CoherenceMesuree(
        du: j['du']! as String,
        au: j['au']! as String,
        tables: [
          for (final t in (j['tables'] as List? ?? const []))
            if (t is String) t,
        ],
        enAttente: (j['en_attente'] as num?)?.toInt() ?? 0,
        ecarts: [
          for (final e in (j['ecarts'] as List? ?? const []))
            if (e is Map && e['table'] is String && e['jour'] is String)
              EcartCoherence(
                table: e['table']! as String,
                jour: e['jour']! as String,
                serveur: compte(e['serveur']),
                poste: compte(e['poste']),
              ),
        ],
      ),
    );
  } on FormatException {
    return null;
  }
}
