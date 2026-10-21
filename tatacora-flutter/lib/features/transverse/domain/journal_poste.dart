/// Le Journal d'Audit DE CE POSTE — la lecture de la file d'envoi.
///
/// La vue lit `journal_audit` du serveur, écrit par les observateurs d'audit
/// (création, modification, connexion…). Ce poste n'a AUCUNE table d'audit, et
/// n'en reçoit pas (changement de schéma refusé, décrit au rapport du
/// 21/10/2026). La plus proche vérité honnête : la file d'envoi
/// (`operations_sync_local`) est, elle, un registre INALTÉRABLE et horodaté de
/// chaque création et de chaque modification que ce poste a écrites pour le
/// serveur. On la lit telle quelle.
///
/// Ce qu'elle ne sait pas, et que l'écran dit : QUI a écrit (aucun login n'y
/// est conservé : « — », comme la vue pour une entrée sans utilisateur) et
/// depuis quel poste (« — »). Les connexions, déconnexions et suppressions
/// n'y figurent pas : le poste n'en écrit aucune trace.
library;

import '../../synchronisation/domain/operation_sync.dart';

/// Le plafond de lignes rendues — `JournalAudit::PLAFOND` de la vue.
const int plafondJournalAudit = 200;

/// Les actions que ce poste écrit, avec le libellé de la vue
/// (`JournalAudit::ACTIONS`).
enum ActionJournalPoste {
  creation('creation', 'Création'),
  modification('modification', 'Modification');

  const ActionJournalPoste(this.code, this.libelle);

  final String code;
  final String libelle;
}

/// Le libellé FRANÇAIS de chaque table tracée — `pwa.journal_audit.tables`,
/// pour les tables que la file d'envoi porte. Une table absente d'ici garde son
/// nom technique : un manque à combler, jamais un libellé inventé.
const Map<String, String> libellesTablesJournal = {
  'reservations': 'Réservation',
  'clients': 'Client',
  'factures': 'Facture',
  'cartes_boisson': 'Article de la carte du bar',
  'indisponibilites_carte': 'Indisponibilité de carte',
  'depenses': 'Dépense',
  'menus': 'Menu',
  'plats': 'Plat',
  'recettes': 'Recette',
  'bulletins_paie': 'Bulletin de paie',
  'conges': 'Congé',
  'employes': 'Employé',
  'plannings': 'Planning',
  'articles': 'Article de stock',
  'mouvements_stock': 'Mouvement de stock',
  'points_stockage': 'Point de stockage',
  'circuits': 'Circuit touristique',
  'guides': 'Guide',
  'reservations_tour': 'Réservation de circuit',
  'contrats_location': 'Contrat de location',
  'entretiens_vehicule': 'Entretien de véhicule',
  'vehicules': 'Véhicule',
  'paniers': 'Panier',
  'ventes': 'Vente',
  'commandes_achat': 'Commande d\'achat',
  'fournisseurs': 'Fournisseur',
  'parametres_systeme': 'Paramètre système',
};

/// Une entrée du journal du poste.
final class EntreeJournalPoste {
  const EntreeJournalPoste({
    required this.action,
    required this.table,
    required this.entiteId,
    required this.dateHeure,
  });

  factory EntreeJournalPoste.depuisOperation(OperationSync o) =>
      EntreeJournalPoste(
        action: switch (o.type) {
          TypeOperationSync.creation => ActionJournalPoste.creation,
          TypeOperationSync.modification => ActionJournalPoste.modification,
        },
        table: o.table.nomServeur,
        entiteId: o.entiteId,
        dateHeure: o.creeLe,
      );

  final ActionJournalPoste action;

  /// Le nom serveur de la table concernée.
  final String table;
  final String entiteId;
  final DateTime dateHeure;

  /// Le libellé français de la table, ou son nom technique.
  String get libelleTable => libellesTablesJournal[table] ?? table;
}

/// Ce que l'écran rend : les entrées les plus récentes (au plus
/// [plafondJournalAudit]) et le décompte réel du filtre.
typedef VueJournalPoste = ({List<EntreeJournalPoste> entrees, int total});

/// Filtre le journal comme la vue : une action, puis une recherche libre sur
/// l'action, la table (nom technique et libellé) et l'identifiant — le
/// « détail » de la vue. Les plus récentes d'abord, plafonnées.
VueJournalPoste filtrerJournalPoste(
  Iterable<EntreeJournalPoste> toutes, {
  String recherche = '',
  ActionJournalPoste? action,
}) {
  final terme = recherche.trim().toLowerCase();
  final retenues = [
    for (final e in toutes)
      if ((action == null || e.action == action) &&
          (terme.isEmpty ||
              e.action.code.contains(terme) ||
              e.action.libelle.toLowerCase().contains(terme) ||
              e.table.toLowerCase().contains(terme) ||
              e.libelleTable.toLowerCase().contains(terme) ||
              e.entiteId.toLowerCase().contains(terme)))
        e,
  ]..sort((a, b) => b.dateHeure.compareTo(a.dateHeure));
  return (
    entrees: retenues.take(plafondJournalAudit).toList(growable: false),
    total: retenues.length,
  );
}
