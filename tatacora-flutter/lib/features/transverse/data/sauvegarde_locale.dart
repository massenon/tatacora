/// La SAUVEGARDE de la base du poste et l'EXPORT d'une table — onglet
/// « Sauvegardes de la base » de l'écran Import & Export (demande du PO du
/// 14/10/2026).
///
/// ## Une copie COHÉRENTE, jamais le fichier recopié à chaud
///
/// La base du poste (`tatacora.sqlite`, hors Documents depuis le 17/10/2026 —
/// `emplacement_base.dart`) est ouverte par
/// l'application pendant toute sa vie : recopier le fichier pendant qu'une
/// écriture a lieu, ou en laissant de côté un journal non reporté, donnerait
/// une copie abîmée au nom conforme — la « sauvegarde de 802 octets » de
/// PA-59/60/61. SQLite produit lui-même la copie : `VACUUM INTO` écrit, dans
/// un fichier NEUF, l'état COMMITÉ de la base, en une seule lecture cohérente.
/// Le fichier temporaire est relu, enregistré par la fenêtre « Enregistrer
/// sous », puis effacé : le poste ne CONSERVE aucune sauvegarde.
///
/// La restauration n'est pas portée (hors périmètre, décision du PO).
///
/// ## L'export d'une table — le service du serveur
///
/// `ExportTableService` : le contenu ACTUEL d'une table, en JSON, lecture
/// seule ; les tables SENSIBLES exclues par leur NOM. Sur ce poste, la seule
/// table sensible est `utilisateurs_local` (dérivés de mots de passe).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../../core/database/app_database.dart';

/// Les tables qui ne s'exportent jamais — `ExportTableService::TABLES_EXCLUES`
/// rapporté au poste : les comptes portent sel et empreinte PBKDF2.
const Set<String> tablesNonExportables = {'utilisateurs_local'};

final class SauvegardeLocale {
  const SauvegardeLocale(this.base);

  final AppDatabase base;

  /// Une copie complète et cohérente de la base, en octets (`VACUUM INTO`).
  Future<Uint8List> composer() async {
    final dossier = await Directory.systemTemp.createTemp('tatacora_svg_');
    final cible = p.join(dossier.path, 'sauvegarde.sqlite');
    try {
      // Le chemin est une chaîne SQL : l'apostrophe se double.
      final litteral = cible.replaceAll("'", "''");
      await base.customStatement("VACUUM INTO '$litteral'");
      return await File(cible).readAsBytes();
    } finally {
      try {
        await dossier.delete(recursive: true);
      } on FileSystemException {
        // Un fichier temporaire resté derrière n'invalide pas la sauvegarde.
      }
    }
  }

  /// Le nom proposé : `tatacora_sauvegarde_AAAA-MM-JJ_HHhMM.sqlite`.
  static String nomSuggere({DateTime? le}) {
    final d = le ?? DateTime.now();
    String deux(int n) => n.toString().padLeft(2, '0');
    return 'tatacora_sauvegarde_${d.year}-${deux(d.month)}-${deux(d.day)}_'
        '${deux(d.hour)}h${deux(d.minute)}.sqlite';
  }

  /// Les tables exportables, triées — toutes celles de la base, sauf
  /// [tablesNonExportables].
  List<String> tablesExportables() => [
    for (final t in base.allTables)
      if (!tablesNonExportables.contains(t.actualTableName)) t.actualTableName,
  ]..sort();

  /// Le contenu RÉEL de [table], au format JSON du serveur (`table`,
  /// `genere_le`, `nombre_lignes`, `lignes`). Une table hors liste LÈVE : un
  /// nom contourné n'est jamais une saisie légitime.
  Future<List<int>> exporterTableJson(String table, {DateTime? le}) async {
    if (!tablesExportables().contains(table)) {
      throw ArgumentError.value(
        table,
        'table',
        "Cette table ne s'exporte pas depuis cet écran.",
      );
    }
    final lignes = await base.customSelect('SELECT * FROM "$table"').get();
    final donnees = [
      for (final l in lignes)
        {
          for (final e in l.data.entries)
            e.key: e.value is Uint8List
                ? base64Encode(e.value as Uint8List)
                : e.value,
        },
    ];
    const encodeur = JsonEncoder.withIndent('    ');
    return utf8.encode(
      encodeur.convert({
        'table': table,
        'genere_le': (le ?? DateTime.now()).toIso8601String(),
        'nombre_lignes': donnees.length,
        'lignes': donnees,
      }),
    );
  }
}
