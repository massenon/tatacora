/// ⚠ **POINT Q2 — comment garantir « un seul panier ouvert par séjour ».**
///
/// Ce fichier est le **seul endroit** du client Flutter qui porte cette
/// garantie. Si l'Architecte tranche Q2 autrement, c'est ici qu'on rouvre.
///
/// ## La question, telle que le document la pose
///
/// `docs/PROPOSITION_MODELE_PANIER_POS.md` §5 : l'expression naturelle serait
/// un index unique **partiel** — unique sur `sejour_id` là où
/// `statut = 'ouvert'`. **MySQL ne connaît pas les index partiels.** Deux
/// options sont proposées :
///
///  - **A — service applicatif à verrou pessimiste**, même patron que
///    `VerificationChevauchementService` (RG-01/RG-08/RG-13) ;
///  - **B — colonne générée** valant `sejour_id` si ouvert et `NULL` sinon,
///    avec un index unique dessus.
///
/// La position du document est A, par cohérence ; il note que B est plus
/// solide. **Aucune des deux n'est ratifiée.**
///
/// ## Ce qui est porté ici, et l'écart de moteur qu'il ne faut pas taire
///
/// **Option A**, dans une transaction Drift : lire, puis écrire, sans qu'une
/// autre écriture ne s'intercale. C'est le choix qui garde **une seule façon**
/// de traiter ce type de problème dans le dépôt.
///
/// Un fait à ne pas perdre, parce qu'il n'est vrai que d'un côté :
/// **SQLite, lui, connaît les index partiels.** Le client *pourrait* poser
/// `CREATE UNIQUE INDEX … WHERE statut = 'ouvert'` là où le serveur ne le peut
/// pas. Ce serait une garantie de plus — et une garantie **asymétrique** : le
/// poste refuserait ce que le serveur accepterait, et l'écart ne se
/// découvrirait qu'à la première synchronisation, sur une donnée déjà saisie.
/// Tant que Q2 n'est pas tranchée, les deux côtés refusent pour la **même**
/// raison, au même endroit du raisonnement.
///
/// ## Ce que cette garantie ne couvre pas, et qu'aucune ne couvrira ici
///
/// Elle vaut **sur un poste**. Deux postes hors ligne peuvent chacun ouvrir un
/// panier sur le même séjour : c'est la même famille de problème que RG-01, et
/// elle se tranche au serveur, à la synchronisation. Or `paniers` n'est pas au
/// registre des tables synchronisables — donc ce cas n'est arbitré **nulle
/// part** aujourd'hui. Le dire vaut mieux que de laisser croire l'inverse.
library;

/// Refus d'ouvrir un second panier sur un séjour qui en a déjà un.
///
/// Le message dit la **conséquence**, pas la règle : « un seul panier par
/// séjour » n'apprend rien à un réceptionniste, tandis que « la facture de
/// départ en oublierait la moitié » lui dit ce qu'il évite. C'est la
/// formulation du prototype, et `t-panier.js` l'éprouve explicitement.
final class PanierDejaOuvertException implements Exception {
  const PanierDejaOuvertException({
    required this.reservationId,
    required this.panierExistantId,
  });

  final String reservationId;
  final String panierExistantId;

  @override
  String toString() =>
      'Ce séjour a déjà un panier ouvert ($panierExistantId). '
      'En ouvrir un second scinderait les consommations, et la facture de '
      'départ en oublierait la moitié.';
}

/// Une table sert déjà un panier ouvert.
///
/// **Même règle que [PanierDejaOuvertException], appliquée à la salle** : deux
/// paniers sur une table scinderaient l'addition, et la moitié manquerait au
/// moment de l'encaisser.
///
/// L'écran ne présente jamais ce refus comme une erreur : rouvrir une table
/// servie doit **retrouver son panier**, pas en créer un second. L'exception
/// n'existe que pour le cas où deux postes ouvriraient la même table dans la
/// même milliseconde — la garde vit donc dans la transaction du DAO.
///
/// ⚠ **Non arbitrée entre deux postes hors ligne**, exactement comme Q2 : le
/// serveur ignore les paniers, et rien ne tranche entre deux appareils. Même
/// famille que RG-01, qui elle se tranche au serveur.
final class TableDejaServie implements Exception {
  const TableDejaServie({
    required this.tableId,
    required this.panierExistantId,
  });

  final String tableId;
  final String panierExistantId;

  @override
  String toString() =>
      'Cette table porte déjà un panier ouvert ($panierExistantId). '
      'Reprenez-le plutôt que d’en ouvrir un second : deux paniers sur une '
      'table scinderaient l’addition.';
}

/// La table est occupée sur un AUTRE poste (ou à la PWA) — lot F6, arbitrage
/// des tables entre postes (décision du PO du 18/10/2026). La phrase est
/// celle du serveur (`sync.tables.occupee`), qui refuserait l'ouverture.
final class TableOccupeeAilleurs implements Exception {
  const TableOccupeeAilleurs({required this.tableId, required this.libelle});

  final String tableId;
  final String libelle;

  String get message =>
      'Table $libelle déjà occupée par un autre poste (ou à la PWA) : '
      "encaissez ou libérez la table là-bas avant de l'ouvrir ici.";

  @override
  String toString() => message;
}
