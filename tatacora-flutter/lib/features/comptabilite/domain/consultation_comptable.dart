/// La CONSULTATION du moteur comptable du poste — journal et balance du hub
/// Comptabilité (lot D du plan du Product Owner, 14/10/2026, D417). Fonctions
/// PURES, réplique de la portée du serveur :
///
/// - `PorteeEcrituresService::requete` : un exercice, un registre FERMÉ de
///   statuts, un journal facultatif ; ordre `date_ecriture`, `created_at`,
///   `id` ;
/// - `JournalGeneralService` : les lignes de cette portée, leurs totaux ;
/// - `BalanceGeneraleService` : la même portée SANS journal, agrégée par
///   compte, triée par numéro ; soldes EXCLUSIFS (un solde nul porte zéro aux
///   deux colonnes).
///
/// Montants en CENTIMES entiers — aucun flottant (`montant_comptable.dart`).
library;

import 'entities/comptabilite.dart';

/// `EcritureComptable::FILTRES_STATUT` — trois valeurs, jamais interprétées
/// « au mieux ».
enum FiltreStatutEcritures {
  toutes(['brouillon', 'validee']),
  validee(['validee']),
  brouillon(['brouillon']);

  const FiltreStatutEcritures(this.statuts);

  /// Les statuts retenus — `whereIn('statut', …)`.
  final List<String> statuts;
}

/// Les lignes de la portée, dans l'ordre du serveur.
List<EcritureComptable> porteeEcritures(
  List<EcritureComptable> toutes, {
  required String exerciceId,
  required FiltreStatutEcritures statut,
  String? journalId,
}) {
  final retenues = [
    for (final e in toutes)
      if (e.exerciceId == exerciceId &&
          statut.statuts.contains(e.statut.valeur) &&
          (journalId == null || e.journalId == journalId))
        e,
  ];
  retenues.sort((a, b) {
    final d = a.dateEcriture.compareTo(b.dateEcriture);
    if (d != 0) return d;
    final c = a.creeLe.compareTo(b.creeLe);
    if (c != 0) return c;
    return a.id.compareTo(b.id);
  });
  return retenues;
}

/// `PorteeEcrituresService::statuts` : le décompte par statut de l'exercice
/// (journal facultatif), SANS le filtre de statut.
({int validee, int brouillon}) repartitionStatuts(
  List<EcritureComptable> toutes, {
  required String exerciceId,
  String? journalId,
}) {
  var validee = 0;
  var brouillon = 0;
  for (final e in toutes) {
    if (e.exerciceId != exerciceId) continue;
    if (journalId != null && e.journalId != journalId) continue;
    if (e.statut == StatutEcriture.validee) {
      validee++;
    } else {
      brouillon++;
    }
  }
  return (validee: validee, brouillon: brouillon);
}

/// Une ligne de la balance générale, en centimes.
final class LigneBalance {
  const LigneBalance({
    required this.compteId,
    required this.numero,
    required this.libelle,
    required this.debit,
    required this.credit,
  });

  final String compteId;
  final String numero;
  final String libelle;
  final int debit;
  final int credit;

  int get _solde => debit - credit;

  /// Exclusifs : un solde nul porte zéro aux deux colonnes.
  int get soldeDebiteur => _solde > 0 ? _solde : 0;
  int get soldeCrediteur => _solde < 0 ? -_solde : 0;
}

/// La balance générale de [lignes] (la portée SANS journal) : par compte,
/// triée par numéro. Un compte introuvable au plan garde son identifiant en
/// guise de numéro — jamais un libellé inventé.
List<LigneBalance> balanceGenerale(
  List<EcritureComptable> lignes,
  Map<String, CompteDuPlan> comptes,
) {
  final debits = <String, int>{};
  final credits = <String, int>{};
  for (final e in lignes) {
    debits[e.compteId] = (debits[e.compteId] ?? 0) + e.debitCentimes;
    credits[e.compteId] = (credits[e.compteId] ?? 0) + e.creditCentimes;
  }
  final balance = [
    for (final id in debits.keys)
      LigneBalance(
        compteId: id,
        numero: comptes[id]?.numero ?? id,
        libelle: comptes[id]?.libelle ?? '',
        debit: debits[id]!,
        credit: credits[id] ?? 0,
      ),
  ]..sort((a, b) => a.numero.compareTo(b.numero));
  return balance;
}
