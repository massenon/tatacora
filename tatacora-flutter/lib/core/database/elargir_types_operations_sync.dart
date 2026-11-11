import 'package:drift/drift.dart';

/// v43 (28/10/2026, A5 « Purger ») : la file d'envoi accepte le type
/// `suppression` — `CHECK (type IN ('creation', 'modification', 'suppression'))`.
///
/// SQLite ne modifie pas une contrainte `CHECK` : la table est donc RECRÉE, et
/// c'est le geste que ce dépôt redoute le plus (piège 3 : « la donnée non
/// synchronisée est la seule copie qui existe »). Les garde-fous :
///
///  * **conditionnel** : si la table porte déjà le type (fixture ramenée en
///    arrière depuis la définition courante, migration rejouée, base neuve),
///    rien n'est touché ;
///  * **copie intégrale avant tout abandon** : l'ancienne table est RENOMMÉE, la
///    neuve créée, toutes les lignes recopiées colonne par colonne, et
///    l'ancienne n'est abandonnée qu'ensuite. Une exception laisse la
///    transaction de migration se défaire (SQLite : DDL transactionnel) ;
///  * **`seq` jamais réutilisé** : le compteur `AUTOINCREMENT` est reporté, même
///    quand les dernières lignes ont été purgées de la file ;
///  * **les index explicites** sont retirés puis recréés tels quels.
///
/// Aucune table ne référence `operations_sync_local` : pas de clé étrangère à
/// suspendre.
Future<void> elargirTypesOperationsSync(
  Migrator m,
  TableInfo<Table, dynamic> operations,
) async {
  final db = m.database;
  const nom = 'operations_sync_local';
  const ancienne = 'operations_sync_local_v42';

  final definition = await db
      .customSelect(
        "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?",
        variables: [Variable.withString(nom)],
      )
      .getSingleOrNull();
  final sql = definition?.read<String?>('sql');
  if (sql == null || sql.contains("'suppression'")) return;

  final index = [
    for (final r
        in await db
            .customSelect(
              "SELECT name, sql FROM sqlite_master WHERE type = 'index' "
              'AND tbl_name = ? AND sql IS NOT NULL',
              variables: [Variable.withString(nom)],
            )
            .get())
      (nom: r.read<String>('name'), sql: r.read<String>('sql')),
  ];
  final compteur = await db
      .customSelect(
        'SELECT seq FROM sqlite_sequence WHERE name = ?',
        variables: [Variable.withString(nom)],
      )
      .getSingleOrNull();
  final dernierSeq = compteur?.read<int>('seq');

  for (final i in index) {
    await db.customStatement('DROP INDEX IF EXISTS ${i.nom}');
  }
  await db.customStatement('ALTER TABLE $nom RENAME TO $ancienne');
  await m.createTable(operations);

  final colonnesAnciennes = {
    for (final c in await db.customSelect('PRAGMA table_info($ancienne)').get())
      c.read<String>('name'),
  };
  final communes = [
    for (final c in await db.customSelect('PRAGMA table_info($nom)').get())
      if (colonnesAnciennes.contains(c.read<String>('name')))
        c.read<String>('name'),
  ].join(', ');
  await db.customStatement(
    'INSERT INTO $nom ($communes) SELECT $communes FROM $ancienne',
  );
  if (dernierSeq != null) {
    await db.customStatement(
      'UPDATE sqlite_sequence SET seq = MAX(seq, $dernierSeq) '
      "WHERE name = '$nom'",
    );
    await db.customStatement(
      "INSERT INTO sqlite_sequence (name, seq) SELECT '$nom', $dernierSeq "
      "WHERE NOT EXISTS (SELECT 1 FROM sqlite_sequence WHERE name = '$nom')",
    );
  }
  await db.customStatement('DROP TABLE $ancienne');

  for (final i in index) {
    await db.customStatement(
      i.sql.replaceFirst('CREATE INDEX', 'CREATE INDEX IF NOT EXISTS'),
    );
  }
}
