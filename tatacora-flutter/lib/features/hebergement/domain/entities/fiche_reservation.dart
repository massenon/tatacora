// Vue Blade maîtresse (PA-183) : pwa/hebergement/reservations.blade.php
/// Les référentiels du formulaire de réservation — ceux de la vue Blade
/// `pwa/hebergement/reservations.blade.php` et de sa classe Livewire
/// (`Reservations::TYPES_CLIENT`, `Reservations::MODES_PAIEMENT`).
///
/// ## Trois registres, et aucun n'est celui du point de vente
///
/// La fiche emploie **cinq modes de paiement** — Espèces, Mobile Money,
/// Virement, Chèque, Crédit — et le point de vente les siens, dont « Porté sur
/// la note de chambre ». Les fusionner en un seul registre « parce qu'ils se
/// ressemblent » offrirait la note de chambre sur une réservation, ce qui n'a
/// aucun sens, et « Crédit » au comptoir. Deux gestes différents, deux
/// registres.
library;

/// « Type de client » — les quatre options de la vue, dans son ordre.
///
/// ⚠ **Deux registres cohabitent** (PA-116). Le LIBELLÉ affiché est celui de
/// la vue : « Structure » depuis le 11/09/2026 (PA-185) — « Entreprise »
/// jusque-là, mot de l'ancien prototype. Le CODE écrit dans
/// `reservations_local.type_client` reste l'identifiant de l'énumération
/// (`entreprise`) : le renommer sans migration rendrait illisibles les fiches
/// déjà saisies sur ce poste.
enum TypeClient {
  particulier('Particulier'),
  groupe('Groupe'),
  agencePartenaire('Agence partenaire'),
  entreprise('Structure');

  const TypeClient(this.libelle);

  final String libelle;

  static const TypeClient parDefaut = TypeClient.particulier;
}

/// « Mode de paiement » d'une réservation.
///
/// ⚠ **À ne pas confondre avec `ModeReglement` du point de vente.** Voir
/// l'en-tête : ce sont deux registres distincts, et les unifier ferait
/// apparaître des modes absurdes de chaque côté.
///
/// Aucun n'est marqué « encaissé » ici, contrairement au POS : sur une
/// réservation, c'est l'**acompte** qui dit ce qui est entré, pas le mode.
///
/// Les cinq modes de `Reservations::MODES_PAIEMENT`, dans l'ordre de la vue.
/// « Espèces » est en tête depuis le 11/09/2026 (PA-185) : la PWA l'a ajouté
/// le 01/09/2026 — le comptoir du Gîte encaisse des acomptes en liquide. Son
/// code `especes` est celui que le serveur connaît
/// (`ReservationService::TRESORERIE_ACOMPTE_PAR_MODE`, contrepartie
/// « caisse »). Ajouté, jamais substitué : les quatre autres codes restent
/// ceux déjà écrits dans `reservations_local.mode_paiement`.
enum ModePaiementReservation {
  especes('Espèces'),
  mobileMoney('Mobile Money'),
  virement('Virement'),
  cheque('Chèque'),
  credit('Crédit');

  const ModePaiementReservation(this.libelle);

  final String libelle;

  static const ModePaiementReservation parDefaut =
      ModePaiementReservation.mobileMoney;
}

/// « Canal de réservation ».
///
/// Le maître le lit d'un référentiel ADMINISTRABLE (Paramètres › Canaux de
/// réservation), pas d'une liste écrite en dur : *« deux listes écrites à la
/// main auraient fini par diverger, et l'analyse par canal serait devenue
/// fausse sans que rien ne le signale »*. Depuis le 21/10/2026 (« tout au
/// complet ») ce poste fait de même : `canaux_reservation_local`, écrite par
/// `CanauxReservationDao`, synchronisée (création, renommage, activation), lue
/// par la fiche de réservation, la réservation rapide et le filtre de
/// l'écran Réservations.
///
/// [code] est l'IDENTIFIANT du canal — la valeur que `reservations_local.canal`
/// porte, jamais le libellé (un libellé est du texte d'interface : un canal
/// RENOMMÉ ne doit pas rendre illisibles les réservations déjà écrites).
///
/// ## Le jeu initial
///
/// Les sept constantes ci-dessous sont le jeu initial du maître
/// (`CANAUX_INITIAUX`). Elles servent à DEUX choses seulement : poser la table
/// d'un poste vierge (`CanauxReservationDao.tous`), et lire les réservations
/// d'AVANT la v35, dont la colonne porte encore ces codes `can-…`.
final class CanalReservation {
  const CanalReservation(this.code, this.libelle, {this.actif = true});

  static const CanalReservation physique = CanalReservation(
    'can-physique',
    'Physique',
  );
  static const CanalReservation telephone = CanalReservation(
    'can-telephone',
    'Téléphone',
  );
  static const CanalReservation whatsapp = CanalReservation(
    'can-whatsapp',
    'WhatsApp',
  );
  static const CanalReservation booking = CanalReservation(
    'can-booking',
    'Booking.com',
  );
  static const CanalReservation siteWeb = CanalReservation(
    'can-site',
    'Site web',
  );
  static const CanalReservation facebook = CanalReservation(
    'can-facebook',
    'Facebook',
  );
  static const CanalReservation agencePartenaire = CanalReservation(
    'can-agence',
    'Agence partenaire',
  );

  /// Le jeu initial du maître, dans son ordre.
  static const List<CanalReservation> jeuInitial = [
    physique,
    telephone,
    whatsapp,
    booking,
    siteWeb,
    facebook,
    agencePartenaire,
  ];

  /// Le canal proposé d'emblée à une nouvelle réservation.
  static const CanalReservation parDefaut = physique;

  /// L'identifiant du canal (l'`id` de sa ligne), ou — pour une réservation
  /// d'avant la v35 — le code `can-…` du jeu initial.
  final String code;

  final String libelle;

  /// `false` : désactivé. Il n'est plus proposé aux nouvelles saisies, mais les
  /// réservations qui le portent le gardent (jamais de suppression).
  final bool actif;

  /// Ce canal est-il le même qu'[autre] ? Même identifiant, ou — le temps que
  /// la table prenne le relais d'un code d'avant la v35 — même libellé du jeu
  /// initial.
  bool memeQue(CanalReservation? autre) {
    if (autre == null) return false;
    if (autre.code == code) return true;
    final ancien = jeuInitial.any(
      (c) => c.code == autre.code || c.code == code,
    );
    return ancien &&
        autre.libelle.trim().toLowerCase() == libelle.trim().toLowerCase();
  }

  @override
  bool operator ==(Object other) =>
      other is CanalReservation && other.code == code;

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => 'CanalReservation($code, $libelle)';
}

/// Le type de remise appliqué.
enum TypeRemise {
  aucune('Aucune'),
  pourcentage('%'),
  montant('FCFA');

  const TypeRemise(this.libelle);

  final String libelle;
}

/// Le récapitulatif financier d'une réservation — **entièrement calculé**.
///
/// Règle non négociable du projet : toute valeur calculable est affichée en
/// lecture seule, jamais un champ de formulaire soumis. Un total saisissable
/// finirait par contredire ses lignes, et c'est la saisie qui l'emporterait.
///
/// Porté de `reservations-services.js:recalculerTotaux()`.
final class RecapitulatifReservation {
  const RecapitulatifReservation._({
    required this.sousTotal,
    required this.montantRemise,
    required this.total,
    required this.acompte,
    required this.reste,
  });

  final int sousTotal;
  final int montantRemise;
  final int total;
  final int acompte;
  final int reste;

  /// Calcule le récapitulatif.
  ///
  /// Deux bornes viennent du maître et comptent autant que la formule :
  ///
  ///  - le **total** ne descend jamais sous zéro (`Math.max(0, …)`) — une
  ///    remise supérieure au sous-total ne doit pas produire un montant
  ///    négatif, qui se lirait comme un avoir ;
  ///  - le **reste à payer** non plus : un acompte supérieur au total ne
  ///    signifie pas que l'établissement doit de l'argent, il signifie qu'une
  ///    saisie est fausse.
  factory RecapitulatifReservation.calculer({
    required int sousTotal,
    required TypeRemise typeRemise,
    required num valeurRemise,
    required int acompte,
  }) {
    final remise = switch (typeRemise) {
      TypeRemise.aucune => 0,
      // Le maître calcule en flottant puis affiche ; on arrondit ici, une
      // fois, plutôt que de laisser un demi-franc se propager.
      TypeRemise.pourcentage => (sousTotal * (valeurRemise / 100)).round(),
      TypeRemise.montant => valeurRemise.round(),
    };

    final montantRemise = remise.clamp(0, sousTotal);
    final total = sousTotal - montantRemise;
    final acompteBorne = acompte < 0 ? 0 : acompte;

    return RecapitulatifReservation._(
      sousTotal: sousTotal,
      montantRemise: montantRemise,
      total: total,
      acompte: acompteBorne,
      reste: total - acompteBorne < 0 ? 0 : total - acompteBorne,
    );
  }
}
