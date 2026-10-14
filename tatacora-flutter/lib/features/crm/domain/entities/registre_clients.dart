// Vue Blade maîtresse (PA-183) : pwa/crm/clients-creances.blade.php
import '../../../facturation/domain/creances.dart';
import 'client.dart';

/// Le registre des clients tel que l'écran l'affiche —
/// `pwa/crm/clients-creances.blade.php`, onglet « Liste des clients ».
///
/// ## Le solde est CALCULÉ, jamais lu — et c'est celui du SERVEUR
///
/// Le sous-titre de la page l'écrit : *« Le solde d'un client est calculé :
/// factures certifiées non soldées, diminuées des règlements reçus. Il ne se
/// saisit jamais. »* `SoldeClientService::registre()` le calcule ainsi, et ce
/// poste fait de même depuis le lot 5 (12/10/2026) : la somme du RESTE DÛ de ses
/// factures impayées (`creances.dart`, UNE formule), avoirs, encaissements actifs
/// et acomptes déduits.
///
/// `clients_local` porte pourtant une colonne `solde`, qui vaut `0` pour tout le
/// monde : **rien ne l'écrit** (PA-126). L'afficher donnerait un zéro plausible
/// sur la fiche d'un client qui doit 200 000 F.
///
/// ## Ce que ce solde REMPLACE, et pourquoi
///
/// Jusqu'au 12/10/2026 le poste affichait « restes à payer sur séjours +
/// consommations non facturées » (PA-112, PA-126) : une AUTRE grandeur, assumée
/// parce que `paiements` n'avait aucun écrivain et que la facture ne pouvait
/// pas être soldée. Elle ne se déduisait pas d'un recouvrement : après un
/// encaissement, le solde affiché n'aurait pas bougé. Le serveur ne l'a jamais
/// connue — ses consommations « portées sur la note de chambre » sont des
/// `ventes`, pas des créances, tant que le départ n'a pas émis la facture. La
/// règle du PO (le serveur fait foi) la retire, et avec elle les colonnes
/// « Séjours » et « Consommations » que la vue ne porte pas.
///
/// ## Tout est en CENTIMES
///
/// Le serveur accepte un encaissement décimal (« 100.5 ») : le reste dû d'une
/// facture peut porter des centimes. Les afficher en francs entiers (arrondi de
/// `MontantFcfa::format`) est le seul endroit où le poste arrondit.
final class LigneClient {
  const LigneClient({
    required this.client,
    required this.soldeCentimes,
    required this.nbPieces,
    this.plusAncienne,
  });

  final Client client;

  /// `SUM(reste dû)` des factures impayées du client, sans plancher par facture.
  final int soldeCentimes;

  /// Nombre de factures impayées — colonne « Pièces » de la vue.
  final int nbPieces;

  /// La date d'émission de la plus ancienne facture impayée, ou `null`.
  final DateTime? plusAncienne;

  bool get estDebiteur => soldeCentimes > 0;

  /// `diffInDays(now())` du serveur, depuis la DATE d'émission (`factures.
  /// date_emission` est une date, pas un instant) : des jours ENTIERS. `null`
  /// quand le client ne doit rien — jamais un zéro plausible.
  int? ancienneteJours(DateTime maintenant) {
    final debut = plusAncienne;
    if (debut == null) return null;
    final emission = DateTime(debut.year, debut.month, debut.day);
    return maintenant.difference(emission).inDays;
  }
}

/// Le filtre « état » du maître (l.56-60).
///
/// Quatre entrées au maître ; **« À relancer » est absent**, et son absence est
/// une décision : une relance suppose un historique de relances, qui relève de
/// M12 — module entièrement vide, l'API WhatsApp n'étant pas contractée.
/// Rendre l'entrée sans l'historique classerait tous les débiteurs comme « à
/// relancer », ce qui est une affirmation sur un fait jamais vérifié.
enum EtatCreance {
  tous('', 'Tous les clients'),
  debiteur('debiteur', 'Débiteurs uniquement'),
  solde('solde', 'Sans dette');

  const EtatCreance(this.code, this.libelle);

  final String code;
  final String libelle;
}

/// Compose le registre à partir des clients et des créances **locales**.
///
/// Fonction pure : elle ne lit ni base ni réseau. C'est la réplique de
/// `SoldeClientService::registre()` — tous les clients figurent, un client sans
/// dette rend un solde nul et zéro pièce, et le tri est celui du maître : solde
/// décroissant, puis nom.
List<LigneClient> composerRegistre({
  required List<Client> clients,
  required List<CreanceFacture> creances,
}) {
  final soldes = soldesParClient(creances);

  final lignes = [
    for (final client in clients)
      LigneClient(
        client: client,
        soldeCentimes: soldes[client.id]?.soldeCentimes ?? 0,
        nbPieces: soldes[client.id]?.nbPieces ?? 0,
        plusAncienne: soldes[client.id]?.plusAncienne,
      ),
  ];

  // L'ordre du maître : les plus gros débiteurs d'abord, puis l'alphabet, puis
  // l'identifiant (le serveur départage ainsi : `solde desc, nom, id`).
  lignes.sort((a, b) {
    final parSolde = b.soldeCentimes.compareTo(a.soldeCentimes);
    if (parSolde != 0) return parSolde;
    final parNom = a.client.nomComplet.compareTo(b.client.nomComplet);
    return parNom != 0 ? parNom : a.client.id.compareTo(b.client.id);
  });

  return List.unmodifiable(lignes);
}

List<LigneClient> filtrerRegistre(
  List<LigneClient> lignes, {
  String terme = '',
  EtatCreance etat = EtatCreance.tous,
}) {
  final recherche = terme.trim().toLowerCase();

  return lignes
      .where((l) {
        if (recherche.isNotEmpty) {
          // Le téléphone autant que le nom : au comptoir, c'est souvent le seul
          // élément que le client donne.
          final champs = '${l.client.nomComplet} ${l.client.telephone}'
              .toLowerCase();
          if (!champs.contains(recherche)) return false;
        }

        return switch (etat) {
          EtatCreance.tous => true,
          EtatCreance.debiteur => l.estDebiteur,
          EtatCreance.solde => !l.estDebiteur,
        };
      })
      .toList(growable: false);
}

/// Les indicateurs du registre : la carte « Créances totales » de la vue et son
/// détail « N pièce(s) · M client(s) » — `SoldeClientService::totaux()`.
///
/// Les quatre autres cartes ne se calculent pas depuis le registre : « Encaissé
/// sur 30 j » lit les encaissements, les deux tranches de la balance âgée lisent
/// les dates des factures, « Clients à relancer » un historique de relances.
final class KpisClients {
  const KpisClients({
    required this.nbClients,
    required this.nbDebiteurs,
    required this.totalDuCentimes,
    required this.nbPieces,
  });

  factory KpisClients.calculer(List<LigneClient> lignes) {
    var debiteurs = 0;
    var total = 0;
    var pieces = 0;

    for (final l in lignes) {
      if (l.estDebiteur) debiteurs++;
      total += l.soldeCentimes;
      pieces += l.nbPieces;
    }

    return KpisClients(
      nbClients: lignes.length,
      nbDebiteurs: debiteurs,
      totalDuCentimes: total,
      nbPieces: pieces,
    );
  }

  final int nbClients;
  final int nbDebiteurs;
  final int totalDuCentimes;
  final int nbPieces;
}
