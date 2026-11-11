/// La FILE D'ENVOI du poste — schéma v26, UNE table neuve, migration additive.
///
/// ## Pourquoi elle revient (décisions du Product Owner des 14–15/10/2026)
///
/// « Zéro réseau » n'est plus une contrainte technique mais une règle
/// d'USAGE : le poste fonctionne à 100 % sans réseau, pendant des jours, et la
/// synchronisation est une tâche de fond qui ne bloque jamais un geste (la
/// clôture de caisse en premier). Le poste pousse des documents SOURCES —
/// jamais une écriture comptable (D246) : le serveur produit lui-même les
/// pièces à la date métier. Il crée et modifie son catalogue hors ligne ; le
/// serveur fusionne (dernier saisi gagnant sur `horodatage_client`).
///
/// La v10 avait retiré `sync_queue` parce qu'une file que personne ne vide
/// annonce une attente sans fin (PA-59/60/61). Le moteur d'envoi existe
/// depuis F2a ; depuis F2b, l'écran de synchronisation (`/synchronisation`)
/// la LIT (compteurs, « À traiter ») et y fait deux gestes, par ce DAO :
/// « Renvoyer » (`renvoyer`) et « Débloquer » (`debloquer`).
///
/// ## Une ligne = une opération du protocole `/api/v1/sync`
///
/// Le `payload` est un INSTANTANÉ figé au moment de l'écriture métier, déjà
/// au contrat du serveur (noms en snake_case, unités du serveur) : rejouer
/// l'opération dans trois jours envoie ce qui a été saisi, pas ce que la base
/// contient alors. `seq` est l'ordre GLOBAL d'écriture (AUTOINCREMENT : jamais
/// réutilisé, toujours croissant) — un référentiel écrit avant le document qui
/// le cite part avant lui, sans règle d'ordre à maintenir à part.
///
/// ## Qui écrit, qui lit, qui descend (pièges 9 et 11)
///
/// | Colonne | Qui l'écrit | Qui la lit | Qui la descend |
/// |---|---|---|---|
/// | toutes | `OperationsSyncDao`, SEUL auteur : `enfiler` (dans la transaction de chaque écrivain métier), `reclamerLot` / `libererBauxExpires` / `marquerResultat` / `marquerEchecTransitoire` / `prolongerBail` (moteur F2), `renvoyer` / `debloquer` (écran F2b) | `OperationsSyncDao` (moteur, descente F2b, écran de synchronisation) | personne : c'est la moitié MONTANTE |
///
/// Le mode démonstration n'y écrit rien (`AppDatabase.fileSynchronisationActive`).
library;

import 'package:drift/drift.dart';

/// Une opération à pousser au serveur.
@DataClassName('OperationSyncLocale')
@TableIndex(name: 'idx_operations_sync_statut_seq', columns: {#statut, #seq})
@TableIndex(
  name: 'idx_operations_sync_entite',
  columns: {#tableServeur, #entiteId},
)
class OperationsSyncLocal extends Table {
  /// L'ordre local, global et croissant (`AUTOINCREMENT` : jamais réutilisé).
  IntColumn get seq => integer().autoIncrement()();

  /// UUID de la TENTATIVE, posé à l'enfilement — distinct de [entiteId] :
  /// c'est lui qui rend le rejeu idempotent côté serveur.
  TextColumn get uuidOperation => text().unique()();

  /// Le nom de table du REGISTRE serveur (`RegistreSynchronisation`), jamais
  /// le nom local (`articles`, pas `articles_local`).
  TextColumn get tableServeur => text()();

  /// L'UUID de l'élément, posé par le poste à sa création.
  TextColumn get entiteId => text()();

  /// `creation` ou `modification`.
  TextColumn get type => text()();

  /// Le document, en JSON, au contrat du serveur — figé à l'écriture.
  TextColumn get payload => text()();

  /// L'instant de la saisie sur le poste (ISO 8601, UTC) : il arbitre le
  /// dernier écrit gagnant côté serveur.
  TextColumn get horodatageClient => text()();

  /// La date du DOCUMENT (`AAAA-MM-JJ`), pour les documents datés ; nulle
  /// pour un référentiel. Le payload porte déjà le champ date que le serveur
  /// lit (`champDateDocument`) : cette colonne sert au moteur et à l'audit.
  TextColumn get dateMetier => text().nullable()();

  /// `en_attente`, `en_cours`, `synchronise`, `rejete`, `conflit`, `bloque`.
  TextColumn get statut => text().withDefault(const Constant('en_attente'))();

  /// Le lot qui a réclamé l'opération (moteur F2).
  TextColumn get lotId => text().nullable()();

  /// Fin du bail d'un lot réclamé : passé ce moment, l'opération `en_cours`
  /// est réputée abandonnée (processus tué) et redevient `en_attente`.
  DateTimeColumn get verrouJusqua => dateTime().nullable()();

  IntColumn get tentatives => integer().withDefault(const Constant(0))();

  /// Pas avant ce moment (repli après un échec transitoire).
  DateTimeColumn get prochaineTentative => dateTime().nullable()();

  TextColumn get derniereErreur => text().nullable()();

  IntColumn get codeHttp => integer().nullable()();

  /// Le résultat rendu par le serveur pour CETTE opération, tel quel (JSON).
  TextColumn get resultatJson => text().nullable()();

  /// L'identifiant serveur quand le serveur a FUSIONNÉ (`fusionne_avec`).
  TextColumn get idServeur => text().nullable()();

  DateTimeColumn get creeLe => dateTime()();

  DateTimeColumn get synchroniseLe => dateTime().nullable()();

  /// v38 (26/10/2026) — QUI a écrit : le login du compte connecté à
  /// l'enfilement (`AppDatabase.auteurEcriture`). NULLABLE : une opération d'avant
  /// la v38, le mode démonstration et un banc sans session n'ont pas d'auteur —
  /// le Journal d'Audit dit « — ». Écrit par `enfiler` (et copié par
  /// `renvoyer`), lu par le Journal d'Audit : jamais envoyé au serveur.
  TextColumn get auteurLogin => text().nullable()();

  /// v38 — le nom du POSTE (la machine) qui a écrit. Même règle que
  /// [auteurLogin].
  TextColumn get posteNom => text().nullable()();

  @override
  List<String> get customConstraints => [
    // v43 (28/10/2026, A5) : `suppression` — la purge d'une unité ou d'un véhicule
    // archivé. SQLite ne modifie pas un CHECK : `elargirTypesOperationsSync`
    // recrée la table (copie intégrale, `seq` conservé).
    "CHECK (type IN ('creation', 'modification', 'suppression'))",
    "CHECK (statut IN ('en_attente', 'en_cours', 'synchronise', 'rejete', "
        "'conflit', 'bloque'))",
  ];
}
