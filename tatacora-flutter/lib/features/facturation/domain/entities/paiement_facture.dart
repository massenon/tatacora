/// L'encaissement d'une facture — entité de domaine du lot 5 (12/10/2026).
///
/// Réplique de `App\Domain\Facturation\Models\Paiement` du serveur. Un
/// encaissement règle une PIÈCE du registre (la « facture » du serveur) dans une
/// SESSION de caisse ; il ne se supprime jamais (RG-15), il s'ANNULE — par un
/// état tracé (qui, quand, pourquoi) et la contre-passation de sa pièce
/// comptable.
///
/// Les montants sont des CENTIMES ENTIERS, jamais un flottant : le serveur
/// accepte une saisie décimale (« 100.5 »), qu'un entier de francs perdrait.
///
/// @see EF-M2-03 Encaissement des factures
library;

/// Le registre fermé des modes (`Paiement::MODES`) — dans l'ordre du serveur et
/// du sélecteur de la vue (`EncaissementFactureService::TRESORERIE_PAR_MODE`).
///
/// Un cinquième mode n'obtient aucun comportement par omission : le `switch` de
/// [tresorerie] est exhaustif. Le maître propose « Chèque » et « Compensation »
/// que le schéma ne connaît pas : le schéma fait foi sur la donnée, le maître sur
/// le mot affiché (voir `ClientsCreances`, en-tête).
enum ModePaiementFacture {
  especes('especes', 'Espèces'),
  mobileMoney('mobile_money', 'Mobile Money'),
  carte('carte', 'Carte'),
  virement('virement', 'Virement bancaire');

  const ModePaiementFacture(this.code, this.libelle);

  /// Le code stocké (`paiements.mode_paiement`).
  final String code;

  /// Le libellé de la vue (`pwa.clients.mode_*`) — relu contre le serveur.
  final String libelle;

  /// `null` sur un code inconnu : jamais un repli sur « Espèces ». Ranger au
  /// hasard un règlement dans le tiroir fausserait la trésorerie de caisse.
  static ModePaiementFacture? depuisCode(String code) {
    for (final m in values) {
      if (m.code == code) return m;
    }
    return null;
  }
}

/// La trésorerie dont un mode crédite le compte — les CLÉS de
/// `DepenseService::TRESORERIES`, qui font foi pour compte et journal.
///
/// `TRESORERIE_PAR_MODE` du serveur : « carte » entre en BANQUE (le TPE crédite
/// le compte bancaire, jamais le tiroir).
enum TresorerieEncaissement {
  caisse('caisse'),
  momo('momo'),
  banque('banque');

  const TresorerieEncaissement(this.code);
  final String code;
}

extension TresorerieDuMode on ModePaiementFacture {
  /// `EncaissementFactureService::TRESORERIE_PAR_MODE`, exhaustif.
  TresorerieEncaissement get tresorerie => switch (this) {
    ModePaiementFacture.especes => TresorerieEncaissement.caisse,
    ModePaiementFacture.mobileMoney => TresorerieEncaissement.momo,
    ModePaiementFacture.carte => TresorerieEncaissement.banque,
    ModePaiementFacture.virement => TresorerieEncaissement.banque,
  };
}

/// `paiements.statut`.
enum StatutPaiementFacture {
  actif('actif'),
  annule('annule');

  const StatutPaiementFacture(this.code);
  final String code;

  static StatutPaiementFacture depuisCode(String code) => values.firstWhere(
    (s) => s.code == code,
    orElse: () => throw ArgumentError.value(
      code,
      'statut',
      'Statut de paiement inconnu — la base porte un CHECK, il ne peut venir '
          'que d’une autre version.',
    ),
  );
}

/// Un encaissement, tel que le poste le relit.
final class PaiementFacture {
  const PaiementFacture({
    required this.id,
    required this.pieceId,
    required this.sessionId,
    required this.mode,
    required this.montantCentimes,
    required this.datePaiement,
    required this.statut,
    required this.utilisateurCreationId,
    this.motifAnnulation,
    this.annuleParId,
    this.dateAnnulation,
    this.loginCreation,
  });

  final String id;

  /// La pièce réglée (`paiements.facture_id`).
  final String pieceId;

  /// Le tiroir qui a reçu l'argent (`paiements.session_id`).
  final String sessionId;

  final ModePaiementFacture mode;
  final int montantCentimes;
  final DateTime datePaiement;
  final StatutPaiementFacture statut;

  /// Qui a encaissé (colonne d'audit du serveur, « la colonne Par »).
  final String utilisateurCreationId;

  /// Le `login` de qui a encaissé — la colonne « Par » de la vue
  /// (`utilisateurCreation?->login`). `null` si le compte n'est plus lisible :
  /// la vue rend alors un tiret, jamais un identifiant technique.
  final String? loginCreation;

  final String? motifAnnulation;
  final String? annuleParId;
  final DateTime? dateAnnulation;

  bool get estActif => statut == StatutPaiementFacture.actif;

  /// Les huit premiers caractères de l'identifiant : la vue les rend aux
  /// colonnes « N° » ET « Référence » (`Str::limit($paiement->id, 8, '')`), faute
  /// de colonne de référence au schéma — c'est une incohérence du serveur
  /// répliquée, pas un champ saisi.
  String get numeroCourt => id.length <= 8 ? id : id.substring(0, 8);
}
