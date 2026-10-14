/// Les gardes de RG-11 au niveau de la BASE — l'équivalent local de
/// `EcritureComptableObserver` du serveur (10/10/2026, lot 1 de M10).
///
/// ## Pourquoi des triggers et pas seulement un contrôle du moteur
///
/// Même raison que l'Observer du serveur : il couvre TOUS les chemins
/// d'écriture, y compris ceux que personne n'a encore écrits (un futur lot, un
/// import, une réparation à la main). Un contrôle placé dans le moteur ne
/// protégerait que les appelants qui pensent à passer par lui. Toute anomalie
/// touchant une table financière est classée bloquante par le projet.
///
/// ## Le message est un CODE, la phrase vient de la langue
///
/// `RAISE(ABORT, '<cle de langue>')` : SQLite ne porte pas de phrase accentuée
/// de plusieurs lignes proprement. Le DAO relit le code dans l'exception
/// (`traduireRefusBase`) et rend la phrase EXACTE du serveur
/// (`lang/fr/comptabilite.php`).
///
/// ## Ce que ces quatre gardes reproduisent, ligne à ligne
///
/// 1. `updating` d'une écriture déjà VALIDÉE : tout champ modifié refuse, sauf
///    les colonnes d'audit (`modifie_le`, `modifie_par`, l'équivalent de
///    `date_modification` / `utilisateur_modification_id`). « Modifié » se dit
///    comme `getDirty()` : valeur différente (`IS NOT`), pas simple présence
///    dans le `SET`.
/// 2. `updating` d'une écriture NON validée : refus seulement si son exercice
///    est clôturé.
/// 3. `creating` : aucune écriture, même en brouillon, ne s'ajoute à un
///    exercice `cloture`. (`en_cloture` reste admis ici : le serveur ne ferme
///    que `cloture` ; c'est le moteur qui refuse un exercice non ouvert à la
///    SAISIE.)
/// 4. `deleting` : jamais, validée ou non (un trou dans la séquence est
///    précisément ce qu'un contrôle fiscal recherche).
library;

import 'app_database.dart';

/// Codes portés par les exceptions des triggers.
abstract final class CodesRefusBase {
  static const ecritureImmuable = 'comptabilite.ecriture_immuable';
  static const suppressionInterdite =
      'comptabilite.ecriture_suppression_interdite';
  static const exerciceClos = 'comptabilite.exercice_clos';
}

/// Les quatorze colonnes d'une ligne d'écriture que la validation FIGE. Seules
/// `modifie_le` et `modifie_par`, l'audit, restent inscriptibles.
const colonnesProtegeesApresValidation = <String>[
  'id',
  'exercice_id',
  'journal_id',
  'compte_id',
  'centre_id',
  'date_ecriture',
  'libelle',
  'debit_centimes',
  'credit_centimes',
  'statut',
  'ecriture_contrepassee_id',
  'numero_piece',
  'cree_le',
  'cree_par',
];

/// Crée les quatre triggers. Rejouable (`IF NOT EXISTS`) : une migration doit
/// pouvoir se rejouer sur un fichier dans n'importe quel état.
Future<void> creerDeclencheursComptables(AppDatabase db) async {
  final modifie = colonnesProtegeesApresValidation
      .map((c) => 'NEW.$c IS NOT OLD.$c')
      .join(' OR ');

  await db.customStatement(
    'CREATE TRIGGER IF NOT EXISTS rg11_ecriture_validee_immuable '
    'BEFORE UPDATE ON ecritures_local '
    "WHEN OLD.statut = 'validee' AND ($modifie) "
    "BEGIN SELECT RAISE(ABORT, '${CodesRefusBase.ecritureImmuable}'); END",
  );

  await db.customStatement(
    'CREATE TRIGGER IF NOT EXISTS rg11_brouillon_exercice_clos_maj '
    'BEFORE UPDATE ON ecritures_local '
    "WHEN OLD.statut <> 'validee' AND EXISTS ("
    'SELECT 1 FROM exercices_local '
    "WHERE id = NEW.exercice_id AND statut = 'cloture') "
    "BEGIN SELECT RAISE(ABORT, '${CodesRefusBase.exerciceClos}'); END",
  );

  await db.customStatement(
    'CREATE TRIGGER IF NOT EXISTS rg11_exercice_clos_ajout '
    'BEFORE INSERT ON ecritures_local '
    'WHEN EXISTS ('
    'SELECT 1 FROM exercices_local '
    "WHERE id = NEW.exercice_id AND statut = 'cloture') "
    "BEGIN SELECT RAISE(ABORT, '${CodesRefusBase.exerciceClos}'); END",
  );

  await db.customStatement(
    'CREATE TRIGGER IF NOT EXISTS rg11_ecriture_jamais_supprimee '
    'BEFORE DELETE ON ecritures_local '
    "BEGIN SELECT RAISE(ABORT, '${CodesRefusBase.suppressionInterdite}'); END",
  );
}
