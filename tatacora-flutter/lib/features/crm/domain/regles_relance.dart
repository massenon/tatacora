// Vue Blade maîtresse (PA-183) : pwa/crm/clients-creances.blade.php
import '../../comptabilite/domain/montant_comptable.dart'
    show centimesDepuisChaine;
import '../../facturation/domain/creances.dart';
import '../../facturation/domain/regles_encaissement.dart'
    show estVideAuSensDePhp;
import 'entities/registre_clients.dart';
import 'entities/relance.dart';
import 'messages_relance.dart';

/// Un client n'est plus « à relancer » avant ce délai depuis sa dernière
/// relance — `ClientsCreances::JOURS_AVANT_RELANCE` (maître, KPI 5 : « Plus de
/// 30 j sans relance récente »). Un test relit la constante du serveur.
const int joursAvantRelance = 30;

/// `ClientsCreances::clientsARelancer()` — les débiteurs sans relance récente.
///
/// * le point de départ est le registre des SOLDES (`SoldeClientService::
///   registre(null, 'debiteur')`), jamais une seconde formule de créance ;
/// * `derniere` = `MAX(date_relance)` du client ; il est écarté si
///   `derniere >= aujourd'hui − 30 jours` (comparaison de JOURS, bornes
///   incluses : une relance faite il y a exactement 30 jours est récente) ;
/// * l'ancienneté est celle de la plus ancienne facture impayée, en jours.
///
/// L'ordre est celui du registre (plus gros débiteurs d'abord, puis le nom).
List<ClientARelancer> clientsARelancer({
  required List<LigneClient> registre,
  required List<Relance> relances,
  required DateTime maintenant,
}) {
  final dernieres = <String, DateTime>{};
  for (final r in relances) {
    final connue = dernieres[r.clientId];
    if (connue == null || r.dateRelance.isAfter(connue)) {
      dernieres[r.clientId] = r.dateRelance;
    }
  }

  final seuil = DateTime(
    maintenant.year,
    maintenant.month,
    maintenant.day - joursAvantRelance,
  );

  return [
    for (final ligne in registre)
      if (ligne.estDebiteur)
        if (!_recente(dernieres[ligne.client.id], seuil))
          ClientARelancer(
            clientId: ligne.client.id,
            nom: ligne.client.nomComplet,
            soldeCentimes: ligne.soldeCentimes,
            ancienneteMaxJours: ligne.ancienneteJours(maintenant) ?? 0,
            derniereRelance: dernieres[ligne.client.id],
          ),
  ];
}

bool _recente(DateTime? derniere, DateTime seuil) =>
    derniere != null && !_jour(derniere).isBefore(seuil);

DateTime _jour(DateTime d) => DateTime(d.year, d.month, d.day);

/// Le solde en centimes proposé à la relance : le solde vivant du client
/// (`soldeDuClient()` de la vue, qui pré-remplit le montant réclamé).
int montantProposeCentimes(String clientId, List<CreanceFacture> creances) =>
    soldesParClient(creances)[clientId]?.soldeCentimes ?? 0;

/// Le montant saisi dans la modale « Tracer une relance » — la validation
/// Livewire de la vue, dans son ordre : `required`, `numeric`, `min:0`.
///
/// Rend les CENTIMES (le serveur tronque à deux décimales, `bcadd`), ou le
/// refus avec SA phrase, posé sous le champ. Un seul message sort.
({int? centimes, String? refus}) lireMontantRelance(String? saisie) {
  if (estVideAuSensDePhp(saisie)) {
    return (centimes: null, refus: MessagesRelance.montantObligatoire);
  }
  final texte = saisie!;
  final int centimes;
  try {
    centimes = centimesDepuisChaine(texte);
  } on FormatException {
    return (centimes: null, refus: MessagesRelance.montantIllisible);
  }
  // `min:0` se juge sur la valeur EXACTE : « -0.004 » est négatif pour Laravel
  // alors que la troncature à deux décimales le ramène à zéro.
  final negatif = texte.startsWith('-') && RegExp('[1-9]').hasMatch(texte);
  if (negatif) {
    return (centimes: null, refus: MessagesRelance.montantNegatif);
  }
  return (centimes: centimes, refus: null);
}
