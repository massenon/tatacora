/// Le Journal d'Audit DE CE POSTE — la lecture de la file d'envoi.
///
/// La vue lit `journal_audit` du serveur, écrit par les observateurs d'audit
/// (création, modification, connexion…). Ce poste n'a AUCUNE table d'audit, et
/// n'en reçoit pas. La plus proche vérité honnête : la file d'envoi
/// (`operations_sync_local`) est, elle, un registre INALTÉRABLE et horodaté de
/// chaque création et de chaque modification que ce poste a écrites pour le
/// serveur. On la lit telle quelle.
///
/// ## L'utilisateur et le poste (schéma v38, 26/10/2026)
///
/// Chaque opération porte, depuis la v38, le login du compte CONNECTÉ à
/// l'instant de l'écriture et le nom du poste (`operations_sync_local.auteur_login`,
/// `.poste_nom`, posés par `OperationsSyncDao.enfiler` d'après
/// `AppDatabase.auteurEcriture`). La colonne « Poste » de la vue montre l'adresse
/// réseau de l'appelant (`adresse_poste`) ; un poste de comptoir n'en a pas de
/// stable, son NOM de machine tient lieu — écart dit au pied de l'écran.
///
/// Ce que le registre ne sait pas, et que l'écran dit : « — » pour une opération
/// d'avant la v38 ou écrite sans compte connecté (jamais un compte inventé), et
/// l'absence des connexions, déconnexions et suppressions (le poste n'en écrit
/// aucune trace). Les entrées des AUTRES postes et de la PWA ne descendent pas :
/// le journal du serveur reste le registre de tous les postes.
library;

import '../../synchronisation/domain/operation_sync.dart';

/// Le plafond de lignes rendues — `JournalAudit::PLAFOND` de la vue.
const int plafondJournalAudit = 200;

/// Les actions que ce poste écrit, avec le libellé de la vue
/// (`JournalAudit::ACTIONS`).
enum ActionJournalPoste {
  creation('creation', 'Création'),
  modification('modification', 'Modification'),
  suppression('suppression', 'Suppression'),

  // Mot de passe perdu SANS e-mail (29/10/2026, option A du PO) : les gestes
  // sensibles sur les comptes, consignés en LOCAL (`journal_securite_local`) —
  // jamais dans la file d'envoi. Les libellés sont ceux de
  // `JournalAudit::ACTIONS` du serveur. Jamais le secret ni son dérivé.
  reinitialisationMotDePasse(
    'reinitialisation_mot_de_passe',
    'Réinitialisation du mot de passe',
  ),
  codeSecoursGenere('code_secours_genere', 'Code de secours généré'),
  codeSecoursUtilise(
    'code_secours_utilise',
    'Réinitialisation par code de secours',
  ),
  codeSecoursRefuse('code_secours_refuse', 'Code de secours refusé'),
  codeSecoursBloque('code_secours_bloque', 'Code de secours bloqué');

  const ActionJournalPoste(this.code, this.libelle);

  final String code;
  final String libelle;

  /// Une action du journal de SÉCURITÉ du poste (les trois premières viennent
  /// de la file d'envoi).
  bool get estDeSecurite => index >= reinitialisationMotDePasse.index;

  /// L'action portant ce [code], `null` si le poste ne la connaît pas.
  static ActionJournalPoste? depuisCode(String code) {
    for (final a in values) {
      if (a.code == code) return a;
    }
    return null;
  }
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
  // Le journal de sécurité du poste (v46) — `pwa.journal_audit.tables.utilisateurs`.
  'utilisateurs': 'Compte utilisateur',
};

/// Une entrée du journal du poste.
final class EntreeJournalPoste {
  const EntreeJournalPoste({
    required this.action,
    required this.table,
    required this.entiteId,
    required this.dateHeure,
    this.utilisateur,
    this.poste,
  });

  factory EntreeJournalPoste.depuisOperation(OperationSync o) =>
      EntreeJournalPoste(
        action: switch (o.type) {
          TypeOperationSync.creation => ActionJournalPoste.creation,
          TypeOperationSync.modification => ActionJournalPoste.modification,
          TypeOperationSync.suppression => ActionJournalPoste.suppression,
        },
        table: o.table.nomServeur,
        entiteId: o.entiteId,
        dateHeure: o.creeLe,
        utilisateur: o.auteurLogin,
        poste: o.posteNom,
      );

  final ActionJournalPoste action;

  /// Le nom serveur de la table concernée.
  final String table;
  final String entiteId;
  final DateTime dateHeure;

  /// Le login de qui a écrit ; `null` : « — ».
  final String? utilisateur;

  /// Le nom du poste ; `null` : « — ».
  final String? poste;

  /// Le libellé français de la table, ou son nom technique.
  String get libelleTable => libellesTablesJournal[table] ?? table;
}

/// Une entrée du journal de SÉCURITÉ du poste, vue comme une entrée du journal :
/// le compte visé tient lieu d'enregistrement (le login, comme la vue du serveur
/// qui résout `utilisateurs` en login).
EntreeJournalPoste? entreeDepuisSecurite({
  required String action,
  required DateTime creeLe,
  String? auteurLogin,
  String? posteNom,
  String? cibleId,
  String? cibleLogin,
}) {
  final a = ActionJournalPoste.depuisCode(action);
  if (a == null || !a.estDeSecurite) return null;
  return EntreeJournalPoste(
    action: a,
    table: 'utilisateurs',
    entiteId: cibleLogin ?? cibleId ?? '—',
    dateHeure: creeLe,
    utilisateur: auteurLogin,
    poste: posteNom,
  );
}

/// Ce que l'écran rend : les entrées les plus récentes (au plus
/// [plafondJournalAudit]) et le décompte réel du filtre.
typedef VueJournalPoste = ({List<EntreeJournalPoste> entrees, int total});

/// Filtre le journal comme la vue : une action, puis une recherche libre sur
/// l'utilisateur, l'action, la table (nom technique et libellé) et
/// l'identifiant — le « détail » de la vue. Les plus récentes d'abord, plafonnées.
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
              (e.utilisateur ?? '').toLowerCase().contains(terme) ||
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
