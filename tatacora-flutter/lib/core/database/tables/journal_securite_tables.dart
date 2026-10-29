/// Le JOURNAL DE SÉCURITÉ DU POSTE — v46, 29/10/2026 (mot de passe perdu, option A
/// du PO).
///
/// Le poste n'a pas de table d'audit : son « Journal d'Audit » relit la file
/// d'envoi (`operations_sync_local`), qui ne porte que ce qui part au serveur. Or
/// les comptes ne se synchronisent pas — une réinitialisation de mot de passe ne
/// doit JAMAIS entrer dans cette file. Les gestes sensibles sur les comptes
/// (réinitialisation par un administrateur, code de secours posé, utilisé ou
/// refusé) sont donc consignés ICI, en LOCAL, et le Journal d'Audit les lit avec
/// la file.
///
/// ## Ce qui n'y figure JAMAIS
///
/// Ni un mot de passe, ni un code de secours, ni leur dérivé : seulement QUI
/// (le compte connecté, quand il y en a un), QUEL compte, QUAND et depuis QUELLE
/// MACHINE — comme les autres entrées du journal du poste.
///
/// | Qui l'écrit | Qui la lit |
/// |---|---|
/// | `JournalSecuriteDao.tracer`, seul | le Journal d'Audit du poste, le blocage du code de secours |
library;

import 'package:drift/drift.dart';

@DataClassName('EntreeSecurite')
class JournalSecuriteLocal extends Table {
  TextColumn get id => text()();

  /// `reinitialisation_mot_de_passe`, `code_secours_genere`,
  /// `code_secours_utilise`, `code_secours_refuse`, `code_secours_bloque`.
  TextColumn get action => text()();

  /// Le login du compte CONNECTÉ qui a fait le geste ; nul : personne n'était
  /// connecté (le recours par code de secours se fait sans session).
  TextColumn get auteurLogin => text().nullable()();

  /// Le nom de la machine (`Platform.localHostname`), comme les autres écritures.
  TextColumn get posteNom => text().nullable()();

  /// L'identifiant du compte visé, s'il existe sur ce poste.
  TextColumn get cibleId => text().nullable()();

  /// Le login visé (celui qui a été saisi, pour un compte inconnu).
  TextColumn get cibleLogin => text().nullable()();

  DateTimeColumn get creeLe => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
