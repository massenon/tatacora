/// Les CLÔTURES d'exercice du poste — v40, 26/10/2026 (décision du PO : « la
/// clôture annuelle SYSCOHADA DOIT ÊTRE IMPLÉMENTÉE EN POSTE ET WEB »).
///
/// Réplique de `clotures_exercices` du serveur (`ClotureExercice`) : l'historique
/// des clôtures d'un exercice du poste — les numéros des deux pièces qu'elle a
/// passées (solde des comptes de gestion en 131/139 au journal CL, à-nouveaux de
/// N+1 au journal AN), le résultat, l'archive légale et son empreinte SHA-256,
/// et, le cas échéant, la réouverture (qui, quand, pourquoi). Une clôture
/// rouverte reste en historique : rien ne s'efface.
///
/// ## Ce que cette table n'est PAS
///
/// Elle ne dit rien du serveur : elle consigne la clôture faite SUR CE POSTE, sur
/// SES pièces (`ecritures_local`). Le serveur, seul comptable (D246), reçoit une
/// DEMANDE (`demandes_cloture_exercice`, file d'envoi) et rejoue ses règles ; ses
/// propres pièces CL et AN descendent dans le miroir de lecture.
///
/// | Qui l'écrit | Qui la lit |
/// |---|---|
/// | `ClotureExerciceLocale`, seul | l'onglet « Clôtures » du hub, la balance (ouverture connue) |
library;

import 'package:drift/drift.dart';

import 'comptabilite_tables.dart';
import 'utilisateurs_table.dart';

@DataClassName('ClotureExerciceLigne')
class CloturesExercicesLocal extends Table {
  TextColumn get id => text()();

  /// L'exercice clôturé. Plusieurs lignes par exercice possibles (clôture,
  /// réouverture, nouvelle clôture) : une seule est ACTIVE (`rouverte_le` nul).
  TextColumn get exerciceId => text().references(ExercicesLocal, #id)();

  /// Les numéros des deux pièces passées (`CL-2026-00001`, `AN-2027-00001`).
  /// `null` : aucun compte de gestion à solder / aucun solde de bilan à
  /// reporter (comme au serveur, une pièce vide n'est pas passée).
  TextColumn get pieceCloture => text().nullable()();
  TextColumn get pieceANouveaux => text().nullable()();

  /// Le résultat de l'exercice, signé, en CENTIMES entiers (bénéfice positif).
  IntColumn get resultatCentimes => integer()();

  /// Qui a clôturé (RG-15). Vraie clé étrangère.
  TextColumn get clotureePar => text().references(UtilisateursLocal, #id)();
  DateTimeColumn get clotureeLe => dateTime()();

  /// Le dossier de l'archive légale (relatif au dossier des archives du poste)
  /// et son EMPREINTE : le SHA-256 du manifeste. `null` : archive non générée.
  TextColumn get archiveChemin => text().nullable()();
  TextColumn get archiveEmpreinte => text().nullable()();

  /// La réouverture : qui, quand, pourquoi (≥ 10 caractères).
  @ReferenceName('cloturesRouvertes')
  TextColumn get rouvertePar =>
      text().nullable().references(UtilisateursLocal, #id)();
  DateTimeColumn get rouverteLe => dateTime().nullable()();
  TextColumn get motifReouverture => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
