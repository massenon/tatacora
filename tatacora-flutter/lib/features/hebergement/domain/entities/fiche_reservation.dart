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
/// ⚠ **Le maître le lit d'un référentiel ADMINISTRABLE** (Paramètres >
/// Canaux), pas d'une liste écrite en dur : *« deux listes écrites à la main
/// auraient fini par diverger, et l'analyse par canal serait devenue fausse
/// sans que rien ne le signale »*.
///
/// Ce client n'a **aucun écran Paramètres**, donc aucun endroit où administrer
/// la liste. Ce qui est porté ici est donc le **jeu initial** du maître
/// (`CANAUX_INITIAUX`), et la limite est nommée plutôt que dissimulée : le
/// jour où l'écran Paramètres existera, cette énumération devra céder la place
/// à une table, exactement comme les tables de salle l'ont fait (PA-108).
enum CanalReservation {
  physique('can-physique', 'Physique'),
  telephone('can-telephone', 'Téléphone'),
  whatsapp('can-whatsapp', 'WhatsApp'),
  booking('can-booking', 'Booking.com'),
  siteWeb('can-site', 'Site web'),
  facebook('can-facebook', 'Facebook'),
  agencePartenaire('can-agence', 'Agence partenaire');

  const CanalReservation(this.code, this.libelle);

  /// Le code du maître — conservé pour que l'analyse par canal reste
  /// comparable entre les deux implémentations.
  final String code;

  final String libelle;

  static const CanalReservation parDefaut = CanalReservation.physique;
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
