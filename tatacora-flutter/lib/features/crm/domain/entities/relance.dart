// Vue Blade maîtresse (PA-183) : pwa/crm/clients-creances.blade.php
/// Les RELANCES des clients débiteurs (M3, EF-M3-03) — `relances_clients` du
/// serveur, `RelanceClientService`.
///
/// Une relance est un FAIT daté : « on a réclamé tant, le client a promis pour
/// telle date ». Elle n'est pas un mouvement d'argent (aucune pièce comptable),
/// ne s'envoie pas (l'encadré de la vue le dit) et ne se modifie jamais.
library;

/// Le registre FERMÉ des canaux de la vue — `RelanceClient::CANAUX`, la même
/// liste que la contrainte CHECK du schéma serveur (un test la relit du code
/// PHP) — avec les mots de `libelleCanal` de la vue.
///
/// Un canal inconnu se lit « Appel téléphonique » (le `default` de la vue) : la
/// liste d'une relance venue d'ailleurs ne doit pas devenir illisible.
enum CanalRelance {
  telephone('telephone', 'Appel téléphonique'),
  whatsapp('whatsapp', 'WhatsApp'),
  email('email', 'E-mail'),
  courrier('courrier', 'Courrier remis en main propre'),
  visite('visite', 'Visite');

  const CanalRelance(this.code, this.libelle);

  final String code;
  final String libelle;

  /// `null` si [code] n'est pas au registre (le serveur le refuse :
  /// `crm.relance_canal_inconnu`).
  static CanalRelance? depuisCode(String? code) {
    for (final c in values) {
      if (c.code == code) return c;
    }
    return null;
  }

  /// Le libellé de la vue : le `default` est le téléphone.
  static String libelleDe(String? code) =>
      (depuisCode(code) ?? telephone).libelle;
}

/// Une relance tracée.
final class Relance {
  const Relance({
    required this.id,
    required this.clientId,
    required this.clientNom,
    required this.dateRelance,
    required this.canal,
    required this.montantReclameCentimes,
    this.promesse,
    this.commentaire,
    this.creePar,
  });

  final String id;
  final String clientId;

  /// Le nom du client, ou `null` s'il n'est pas (encore) connu de ce poste :
  /// l'historique rend alors un tiret (`?? MontantFcfa::TIRET`).
  final String? clientNom;

  /// Le jour de la relance (minuit local).
  final DateTime dateRelance;

  /// Le code du canal tel qu'écrit (`CanalRelance.code`).
  final String canal;

  /// FIGÉ au jour de l'appel : le solde vivant se recalcule, la parole donnée
  /// non.
  final int montantReclameCentimes;

  final DateTime? promesse;
  final String? commentaire;

  /// Le login de qui a tracé la relance ; `null` pour une relance descendue du
  /// serveur (colonne « Par » : un tiret).
  final String? creePar;
}

/// Un client débiteur à relancer — une ligne de « Clients à relancer ».
final class ClientARelancer {
  const ClientARelancer({
    required this.clientId,
    required this.nom,
    required this.soldeCentimes,
    required this.ancienneteMaxJours,
    required this.derniereRelance,
  });

  final String clientId;
  final String nom;
  final int soldeCentimes;

  /// Jours depuis la PLUS ANCIENNE facture impayée du client.
  final int ancienneteMaxJours;

  /// `null` : « Jamais relancé ».
  final DateTime? derniereRelance;
}
