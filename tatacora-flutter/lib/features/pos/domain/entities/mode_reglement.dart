/// Les modes de règlement — **registre fermé**, porté de `ventes-engine.js`.
///
/// ## Le défaut corrigé (24/08/2026)
///
/// Le client Flutter clôturait toute vente avec `modePaiement: 'especes'`,
/// **écrit en dur**. Aucun écran ne demandait comment le client réglait, et
/// aucun ne l'affichait. Trois conséquences, et la troisième est la plus
/// coûteuse :
///
///   1. le journal de caisse annonçait des espèces que personne n'avait
///      reçues, et le comptage de fin de service ne pouvait pas tomber juste ;
///   2. Mobile Money — le moyen de paiement courant au Bénin — n'était pas
///      représentable ;
///   3. **« Porté sur la note de chambre » était inatteignable.** Or ce mode
///      n'est *pas* un encaissement : il crée une créance réglée au départ du
///      client. L'enregistrer en espèces fait entrer en caisse un argent qui
///      n'y est pas, et le fait disparaître de ce que le client doit encore.
///
/// C'est la famille de défauts que ce dépôt connaît : une valeur qui affirme
/// un état que personne n'a vérifié.
///
/// ## Pourquoi [encaisse] est porté par le mode, et non déduit ailleurs
///
/// `ventes-engine.js:300` écrit `encaisse: mode_paiement !== 'note_chambre'`.
/// Recopier cette comparaison sur chaque appelant ferait qu'un mode ajouté
/// demain — un règlement différé, un bon de commande — serait compté comme
/// encaissé par **omission**. Ici, ajouter un mode oblige à répondre à la
/// question.
///
/// @see prototype_v2/assets/js/ventes-engine.js §MODES_PAIEMENT
library;

/// Un mode de règlement du maître. Registre **fermé** : la liste ne se
/// découvre pas, elle se déclare.
enum ModeReglement {
  especes(code: 'especes', libelle: 'Espèces', encaisse: true),
  mobileMoney(code: 'mobile_money', libelle: 'Mobile Money', encaisse: true),
  carte(code: 'carte', libelle: 'Carte bancaire', encaisse: true),
  virement(code: 'virement', libelle: 'Virement', encaisse: true),

  /// Une consommation portée sur la note de chambre **n'est pas un
  /// encaissement** : elle crée une créance, réglée au départ du client.
  noteChambre(
    code: 'note_chambre',
    libelle: 'Porté sur la note de chambre',
    encaisse: false,
  );

  const ModeReglement({
    required this.code,
    required this.libelle,
    required this.encaisse,
  });

  /// Le code persisté — **identique à celui du serveur et du maître**. Une
  /// divergence ici rendrait les ventes des deux canaux incomparables.
  final String code;

  /// Ce que l'utilisateur lit.
  final String libelle;

  /// L'argent est-il réellement entré en caisse ?
  final bool encaisse;

  /// Le mode par défaut à l'ouverture d'un panier.
  ///
  /// Les espèces restent le règlement le plus courant au comptoir du Gîte, et
  /// un sélecteur sans valeur initiale obligerait à un clic de plus à chaque
  /// vente. **La différence avec l'ancien comportement est qu'il est
  /// maintenant AFFICHÉ et modifiable** : une valeur par défaut visible n'est
  /// pas une valeur écrite en dur.
  static const ModeReglement parDefaut = ModeReglement.especes;

  /// Les modes proposés AU COMPTOIR — `VenteService::modesPaiementComptoir()`
  /// du serveur : tous les modes SAUF la note de chambre, dans l'ordre de
  /// `MODES_PAIEMENT`. La vue du comptoir rend cette liste
  /// (`$modesPaiementComptoir`, directive du PO du 02/09/2026 : « aucune
  /// chambre au comptoir ») et le serveur refuse le mode s'il revient quand
  /// même. Décision du Lead du 14/10/2026 (lot B, « le serveur fait foi ») : le
  /// sélecteur du comptoir de ce poste ne le propose plus ; le POS des clients
  /// hébergés le garde.
  static List<ModeReglement> get auComptoir => [
    for (final m in values)
      if (m != noteChambre) m,
  ];

  /// Relit un code persisté.
  ///
  /// Lève plutôt que de rendre un repli : un code inconnu en base signale une
  /// vente écrite par une version que celle-ci ne comprend pas, et la ranger
  /// silencieusement en espèces fausserait la caisse — le défaut même que ce
  /// fichier corrige.
  static ModeReglement parCode(String code) => values.firstWhere(
    (m) => m.code == code,
    orElse: () => throw ArgumentError.value(
      code,
      'code',
      'Mode de règlement inconnu — la vente a été écrite par une autre version.',
    ),
  );
}
