import '../../../core/rbac/garde_acces.dart';

/// Le REGISTRE FERMÉ des états de M14 — `CatalogueEtatsService::REGISTRE`.
///
/// @see EF-M14-02 Bibliothèque d'états standards par module
/// @see RG-19 Moteur d'états
///
/// ## Fermé, dans l'ordre du serveur
///
/// Les états sont énumérés, jamais découverts : un code qui n'est pas ici est
/// refusé ([EtatLocal.depuisCode] rend `null`), et rien ne se compose pour un
/// code inconnu. L'ordre est celui du registre PHP — c'est lui que la vue
/// regroupe par module (`groupBy`, `studio.blade.php`).
///
/// ## Une copie CONFRONTÉE, pas recopiée de mémoire
///
/// Code, module, libellé du catalogue, phrase de période, libellés des
/// indicateurs et en-têtes sont relus dans le code PHP des douze classes
/// `Etat*` et dans leurs fichiers de langue par
/// `test/features/etats/registre_contre_serveur_test.dart`
/// (`tool/etats/exporter_registre.php`) : une copie qui ne vérifierait qu'elle
/// même resterait verte le jour où le serveur renomme une colonne.
///
/// ## Ce que ce poste calcule — et pourquoi pas le reste
///
/// Un état se calcule ici SI TOUTES ses sources sont détenues ET écrites sur ce
/// poste ; sinon il reste LISTÉ (le catalogue est celui du serveur) et son
/// aperçu est refusé avec sa raison, vraie et datée. [raisonRefus] est cette
/// raison : un état qui en a une n'est jamais calculé, quelles que soient les
/// données.
enum EtatLocal {
  stocks(
    code: 'stocks',
    module: ModuleTatacora.m6Stocks,
    libelle: 'État des stocks — tous points de stockage',
    periode: 'Arrêté au :date',
    indicateurs: ['Références', 'Sous seuil', 'Valeur du stock (CMP)'],
    entetes: [
      'Article',
      'Catégorie',
      'Unité',
      'Quantité',
      'Seuil',
      'Statut',
      'Valeur',
    ],
  ),
  tableauDeBord(
    code: 'tableau-de-bord',
    module: ModuleTatacora.m11TableauxDeBord,
    libelle: 'Tableau de bord — synthèse consolidée',
    // La période n'est pas une phrase de langue : c'est le libellé de la
    // fenêtre (`Periode::libelle()`), calculé sur le poste.
    periode: null,
    indicateurs: [
      "Chiffre d'affaires encaissé",
      "Taux d'occupation (nuitées)",
      'Dépenses cumulées',
      'Employés actifs',
    ],
    entetes: ['Indicateur', 'Période', 'Période précédente', 'Variation'],
  ),
  parcVehicules(
    code: 'parc-vehicules',
    module: ModuleTatacora.m8Vehicules,
    libelle: 'État du parc de véhicules',
    periode: 'Arrêté au :date',
    indicateurs: [
      'Véhicules',
      'Louables',
      'Immobilisés',
      'Tarif journalier cumulé',
    ],
    entetes: [
      'Immatriculation',
      'Catégorie',
      'Année',
      'Places',
      'Tarif / jour',
      'Statut',
      'Permis requis',
    ],
  ),
  reservations(
    code: 'reservations',
    module: ModuleTatacora.m1Hebergement,
    libelle: 'État des réservations',
    periode: 'Toutes dates',
    indicateurs: [
      'Réservations',
      'Montant total',
      'Reste dû',
      'Sans tarif figé',
    ],
    entetes: [
      'Client',
      'Unité',
      'Arrivée',
      'Départ',
      'Nuits',
      'Statut',
      'Montant',
      'Reste dû',
    ],
  ),
  creancesClients(
    code: 'creances-clients',
    module: ModuleTatacora.m3Crm,
    libelle: 'État des créances clients',
    periode: 'Arrêté au :date',
    indicateurs: ['Clients débiteurs', 'Pièces impayées', 'Total dû (maximum)'],
    entetes: ['Client', 'Téléphone', 'Type', 'Pièces', 'Solde dû'],
  ),
  ventes(
    code: 'ventes',
    module: ModuleTatacora.m5Bar,
    libelle: 'État des ventes',
    periode: 'Toutes dates',
    indicateurs: ['Ventes', 'Encaissées', 'Montant total'],
    entetes: [
      'N°',
      'Date',
      'Point de vente',
      'Client',
      'Mode de paiement',
      'Encaissée',
      'Montant',
    ],
  ),
  depenses(
    code: 'depenses',
    module: ModuleTatacora.m10Comptabilite,
    libelle: 'État des dépenses',
    periode: 'Toutes dates',
    indicateurs: ['Dépenses', 'Montant total'],
    entetes: ['N°', 'Date', 'Libellé', 'Trésorerie', 'Montant', 'Écriture'],
  ),
  achatsFournisseurs(
    code: 'achats-fournisseurs',
    module: ModuleTatacora.m7Achats,
    libelle: 'État des achats et dettes fournisseurs',
    periode: 'Toutes dates',
    indicateurs: ['Commandes', 'Montant total', 'Reste dû'],
    entetes: ['Fournisseur', 'Date', 'Statut', 'Montant', 'Réglé', 'Reste dû'],
  ),
  locationsVehicules(
    code: 'locations-vehicules',
    module: ModuleTatacora.m8Vehicules,
    libelle: 'État des locations de véhicules',
    periode: 'Toutes dates',
    indicateurs: ['Contrats', 'Montant total'],
    entetes: ['Client', 'Véhicule', 'Début', 'Fin', 'Jours', 'Montant'],
  ),
  tourisme(
    code: 'tourisme',
    module: ModuleTatacora.m9Tourisme,
    libelle: 'État des réservations de circuits',
    periode: 'Toutes dates',
    indicateurs: ['Réservations', 'Participants', 'Montant total'],
    entetes: [
      'Circuit',
      'Client',
      'Guide',
      'Date',
      'Participants',
      'Statut',
      'Montant',
    ],
  ),
  paieEffectif(
    code: 'paie-effectif',
    module: ModuleTatacora.m13Rh,
    libelle: 'État Paie & Effectif',
    periode: 'Période :periode',
    indicateurs: [
      'Effectif total',
      'Actifs',
      'Masse salariale brute',
      'Net à payer (période)',
      'Bulletins de la période',
    ],
    entetes: [
      'Nom',
      'Matricule',
      'Poste',
      'Service',
      'Embauche',
      'Statut',
      'Salaire de base',
    ],
  ),
  balance(
    code: 'balance',
    module: ModuleTatacora.m10Comptabilite,
    libelle: 'Balance générale',
    // Sans exercice ouvert, le serveur écrit « Aucun exercice comptable… ».
    // Ce poste ouvre l'exercice de l'année à chaque démarrage (D210) mais ne
    // calcule pas la balance : il ne produit donc jamais cette phrase d'état.
    // (« ce poste n'en a aucun », écrit ici le 10/10, est périmé — D282.)
    periode: null,
    indicateurs: [
      'Comptes mouvementés',
      'Total débit',
      'Total crédit',
      'Équilibrée',
    ],
    entetes: [
      'Compte',
      'Libellé',
      'Débit',
      'Crédit',
      'Solde débiteur',
      'Solde créditeur',
    ],
    // ⚠ Revue le 12/10/2026 (D282) : la version du 10/10 disait que « les
    // ventes » ne produisent aucune pièce. Faux depuis le lot 6 (ventes,
    // acomptes, remboursements) et le lot 7 (règlements fournisseurs).
    // ⚠ Revue une seconde fois le 12/10/2026 (R7 du contrôle du pilotage,
    // D289) : la version D282 rangeait « la réception des achats » et « la
    // paie » parmi les MANQUES DU POSTE. Faux pour les deux, vérifié dans le
    // code serveur : aucun service de réception n'appelle
    // `PasserEcritureService` (`app/Domain/Achats` : seul le règlement le
    // fait), et `LivreDePaieService` n'en passe aucune — son docblock
    // l.48-56 le dit, le listener « GenererEcritureDepuisPaie » annoncé par la
    // migration n'existe nulle part. Le vrai manque du poste est la SAISIE
    // MANUELLE de pièces du comptable (`Pwa\Livewire\Comptabilite\Hub` :
    // `enregistrerPieceBrouillon` / `enregistrerPieceValidee`), par laquelle
    // le serveur reçoit les opérations diverses — paie comprise —, et les
    // ventes et dépenses du poste antérieures au portage des pièces (D246).
    raisonRefus: 'La balance générale n\'est pas disponible dans cet état.',
  );

  const EtatLocal({
    required this.code,
    required this.module,
    required this.libelle,
    required this.periode,
    required this.indicateurs,
    required this.entetes,
    this.raisonRefus,
  });

  /// Le code stable du registre — partie du contrat avec le serveur.
  final String code;

  /// Le module SOURCE : celui qui porte le droit d'éditer l'état.
  final ModuleTatacora module;

  /// Le libellé générique du catalogue (`libelle([])`).
  final String libelle;

  /// Le modèle de la phrase de période (`:date`, `:periode`), ou `null`
  /// quand elle est calculée.
  final String? periode;

  /// Les libellés des indicateurs, dans l'ordre du serveur.
  final List<String> indicateurs;

  /// Les en-têtes de colonnes, dans l'ordre du serveur.
  final List<String> entetes;

  /// Si non nul, l'état est listé mais jamais calculé sur ce poste.
  final String? raisonRefus;

  bool get estCalculable => raisonRefus == null;

  /// Retrouve un état par son code. `null` pour un code inconnu : le registre
  /// est fermé, un repli sur un état par défaut ferait éditer un document que
  /// personne n'a demandé.
  static EtatLocal? depuisCode(String? code) {
    if (code == null) return null;
    for (final e in values) {
      if (e.code == code) return e;
    }
    return null;
  }
}
