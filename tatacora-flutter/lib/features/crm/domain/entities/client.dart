// Vue Blade maîtresse (PA-183) : pwa/crm/clients-creances.blade.php
/// Un client — M3, référentiel partagé par tous les modules (RG-18).
///
/// ## Pourquoi cette entité existe maintenant
///
/// Jusqu'au 25/08/2026, la fiche de réservation écrivait `clientId:
/// 'cli-comptoir'` **en dur**, et le nom saisi au clavier n'était **jamais
/// enregistré** : le DAO reconstruit `clientNom` depuis la fiche client jointe,
/// donc toutes les réservations du poste portaient le même client fictif.
/// Le champ existait, la saisie partait à la poubelle.
///
/// C'est la règle du projet qui tranche : *« tout champ relationnel est une
/// vraie clé étrangère avec autocomplete, jamais du texte libre »*. Le maître
/// emploie un `<input>` libre — c'est un anti-pattern de démonstration, nommé
/// comme tel dans le `CLAUDE.md` du dépôt — mais il pose **à côté** le bouton
/// « Ajouter client », qui crée une vraie fiche. C'est ce bouton qui dit ce que
/// le formulaire veut vraiment.
library;

/// Les quatre types du schéma serveur (`clients.type_client`).
///
/// **Les quatre libellés sont ceux du maître**, et c'est ici qu'ils vivent :
/// `prototype_v2/pages/m3-clients-creances.html` — sa modale « Nouveau
/// client » les écrit en toutes lettres (`m3-clients-creances.js` l.633-636 :
/// « Particulier », « Groupe », « Agence partenaire », « Entreprise »).
///
/// La citation du maître est portée par CE fichier plutôt que par l'écran,
/// parce que c'est lui qui porte les mots. Le comparateur des trois sources
/// confronte chaque modale au code qui **cite sa page** : sans cette ligne,
/// les quatre options seraient introuvables — non pas absentes du portage,
/// mais absentes du périmètre regardé. Les recopier dans la modale aurait
/// donné deux listes pour un seul registre, et deux listes finissent
/// toujours par diverger.
///
/// ⚠ **Ce ne sont PAS les quatre `TypeClient` de la fiche de réservation.**
/// Le maître propose « Particulier / Groupe / Agence partenaire / Entreprise »
/// sur la réservation ; le schéma stocke « particulier / groupe / agence /
/// structure » sur le client. Les confondre ferait écrire `structure` là où
/// l'écran affiche « Entreprise », ou pire, une valeur que l'enum MySQL
/// refuserait à la synchronisation.
enum TypeClientReferentiel {
  particulier('particulier', 'Particulier'),
  groupe('groupe', 'Groupe'),
  agence('agence', 'Agence partenaire'),
  structure('structure', 'Entreprise');

  const TypeClientReferentiel(this.code, this.libelle);

  /// Ce qui est écrit en base, et ce qui part au serveur.
  final String code;

  final String libelle;

  static TypeClientReferentiel parCode(String? code) => values.firstWhere(
    (t) => t.code == code,
    // Un code inconnu vaut « particulier » : c'est la valeur la plus
    // fréquente et la moins engageante. Lever ici rendrait la liste des
    // clients inaffichable à cause d'une seule ligne venue d'ailleurs.
    orElse: () => TypeClientReferentiel.particulier,
  );
}

final class Client {
  const Client({
    required this.id,
    required this.nom,
    required this.telephone,
    required this.type,
    this.prenom,
    this.email,
    this.solde = 0,
    this.statutSync = 'synchronise',
    this.actif = true,
  });

  /// UUID v4 posé **côté client**, comme partout ailleurs : c'est lui qui rend
  /// la création idempotente au rejeu.
  final String id;

  final String nom;
  final String? prenom;

  /// Obligatoire au schéma : c'est par le téléphone qu'on rappelle un client,
  /// et c'est aussi ce qui sert à détecter les doublons (RG-18).
  final String telephone;

  final String? email;
  final TypeClientReferentiel type;

  /// **Ne l'affichez pas.** La colonne existe au schéma, elle vaut `0` pour
  /// tout le monde : rien ne l'écrit. Le solde réel se compose des séjours et
  /// des consommations (`composerRegistre`), et un chiffre stocké deviendrait
  /// faux au premier mouvement — même refus que le total dénormalisé des
  /// réservations (PA-112). Le champ n'est conservé que parce que la table le
  /// porte et qu'un client descendu du serveur peut l'apporter.
  final double solde;

  /// `synchronise` | `en_attente_synchronisation` | `conflit_en_attente`.
  ///
  /// Les clients **partent réellement** au serveur (`TABLES_SYNCHRONISABLES`
  /// les connaît) : afficher ce statut dit quelque chose de vrai, à la
  /// différence d'un panier, qui ne part jamais et sur lequel un badge « en
  /// attente » serait un mensonge (PA-98).
  final String statutSync;

  /// `false` : le client est ARCHIVÉ (`clients.actif`) — il reste dans la liste,
  /// marqué « Archivé », et reste restaurable. `null` en base (lignes d'avant la
  /// v35) se lit actif.
  final bool actif;

  bool get enAttenteDeSynchronisation =>
      statutSync == 'en_attente_synchronisation';

  /// Ce qui s'affiche partout : « KORA Jean », ou « KORA » si le prénom manque.
  String get nomComplet => [nom, prenom].whereType<String>().join(' ').trim();

  @override
  bool operator ==(Object other) => other is Client && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Client($nomComplet, $telephone)';
}
