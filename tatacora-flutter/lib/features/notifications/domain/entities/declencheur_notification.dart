/// Les neuf événements qui déclenchent une notification — REGISTRE FERMÉ.
///
/// Maître : `pwa/notifications/hub.blade.php`, onglet Déclencheurs, et le
/// registre serveur `App\Domain\Notifications\Services\RegistreDeclencheurs`.
/// Les libellés sont ceux de `lang/fr/notifications_pwa.php`, mot pour mot.
///
/// ## Pourquoi un `enum` et un `switch` exhaustif, jamais une chaîne
///
/// Un code ajouté demain ne doit pas obtenir un comportement par omission. Un
/// `Map<String, ...>` rendrait `null` pour un code inconnu et l'écran
/// afficherait un modèle actif que rien ne déclenche — la même forme que la
/// clé `mecef_actif` qu'un écran confirmerait et que rien ne lit (PA-124).
/// Avec un `enum`, le compilateur exige que chaque nouveau cas soit traité
/// partout où le registre est lu.
///
/// [parCode] rend `null` sur un code inconnu et **ne fabrique jamais d'entrée
/// de repli** : un modèle dont l'événement a disparu du registre doit se VOIR à
/// l'écran, pas se fondre derrière son propre code affiché comme un libellé.
/// C'est le choix explicite du registre serveur, repris tel quel.
///
/// ## L'apostrophe suit le MAÎTRE, caractère pour caractère
///
/// `lang/fr/notifications_pwa.php` pose l'apostrophe typographique (U+2019), et
/// les libellés ci-dessous la reprennent telle quelle. La garde de conformité
/// compare LITTÉRALEMENT : un libellé recopié avec une apostrophe droite
/// compterait comme ABSENT et gonflerait la dette — l'inverse du but.
///
/// ⚠ La tendance générale du dépôt est l'apostrophe droite (581 contre 39), et
/// elle reste la règle pour les commentaires, les messages de test et tout
/// texte qui n'est pas repris du maître. Ce n'est pas une norme à appliquer à
/// un libellé recopié : sur une chaîne du maître, la fidélité prime.
library;

/// À qui le message s'adresse — jeu fermé, ordre du maître.
enum PublicNotification {
  client('client', 'Client'),
  personnel('personnel', 'Salarié'),
  interne('interne', 'Équipe interne');

  const PublicNotification(this.code, this.libelle);

  final String code;
  final String libelle;

  static PublicNotification? parCode(String? code) {
    for (final p in values) {
      if (p.code == code) return p;
    }
    return null;
  }
}

/// Les neuf déclencheurs, dans l'ordre du maître.
///
/// Les [variables] sont celles que le maître offre à un modèle : les changer
/// ferait mentir l'aide « Variables disponibles » de la modale d'édition, puis
/// refuserait à la composition des messages que l'écran présentait comme
/// valides.
enum DeclencheurNotification {
  sejourDemain(
    'sejour_demain',
    'Séjour — arrivée demain',
    'Rappel la veille de l’arrivée, avec les informations d’accès.',
    PublicNotification.client,
    'M1',
    ['client', 'date_arrivee', 'date_depart', 'nuits'],
  ),
  sejourDepart(
    'sejour_depart',
    'Séjour — départ du jour',
    'Remerciement au départ, avec le solde restant s’il y en a un.',
    PublicNotification.client,
    'M1',
    ['client', 'date_depart', 'reste_du'],
  ),
  creanceEchue(
    'creance_echue',
    'Créance échue — plus de 30 jours',
    'Relance amiable sur une créance que le moteur signale à relancer.',
    PublicNotification.client,
    'M3',
    ['client', 'montant', 'anciennete'],
  ),
  creanceDouteuse(
    'creance_douteuse',
    'Créance de plus de 90 jours',
    'Alerte au Gérant : une provision pour dépréciation est à envisager.',
    PublicNotification.interne,
    'M3',
    ['nb_clients', 'montant', 'part'],
  ),
  stockSousSeuil(
    'stock_sous_seuil',
    'Article sous le seuil d’alerte',
    'Alerte au magasinier, article par article.',
    PublicNotification.interne,
    'M6',
    ['article', 'stock', 'seuil', 'point'],
  ),
  departCircuitDemain(
    'depart_circuit_demain',
    'Circuit — départ demain',
    'Rappel aux clients inscrits, avec l’heure et le guide.',
    PublicNotification.client,
    'M9',
    ['client', 'circuit', 'date', 'guide', 'personnes'],
  ),
  restitutionVehicule(
    'restitution_vehicule',
    'Véhicule — restitution du jour',
    'Rappel de restitution, avec le solde éventuel.',
    PublicNotification.client,
    'M8',
    ['client', 'vehicule', 'date', 'reste_du'],
  ),
  bulletinDisponible(
    'bulletin_disponible',
    'Bulletin de paie disponible',
    'Information au salarié : son bulletin du mois est établi.',
    PublicNotification.personnel,
    'M13',
    ['employe', 'periode', 'net'],
  ),
  echeanceVps(
    'echeance_vps',
    'Échéance VPS — le 10 du mois',
    'Rappel au Comptable : le VPS est exigible au plus tard le 10.',
    PublicNotification.interne,
    'M13',
    ['periode', 'montant', 'echeance'],
  );

  const DeclencheurNotification(
    this.code,
    this.libelle,
    this.description,
    this.public,
    this.module,
    this.variables,
  );

  final String code;
  final String libelle;
  final String description;
  final PublicNotification public;

  /// Le module d'ORIGINE de l'information — une chaîne affichée (« M1 »,
  /// « M3 »…), jamais une dépendance : ce fichier ne charge le modèle d'aucun
  /// autre domaine.
  final String module;

  final List<String> variables;

  /// `null` sur un code inconnu — jamais une entrée fabriquée.
  static DeclencheurNotification? parCode(String? code) {
    for (final d in values) {
      if (d.code == code) return d;
    }
    return null;
  }

  /// Ce poste sait-il RÉELLEMENT détecter les occurrences de ce déclencheur ?
  ///
  /// Deux sur neuf, et c'est une conséquence directe du périmètre offline :
  /// `reservations_local` est la seule table métier que des gestes LOCAUX
  /// remplissent réellement. Le serveur lui-même n'en couvre que cinq sur neuf,
  /// chacun avec sa raison datée — la même honnêteté est reprise ici.
  ///
  /// Un modèle actif sur un déclencheur non détecté reste visible partout
  /// ailleurs (Modèles, Déclencheurs) ; il ne compose simplement jamais de
  /// message. Ce n'est pas une faute de saisie, et rien ne le signale comme
  /// telle.
  bool get estDetecteSurCePoste => switch (this) {
    DeclencheurNotification.sejourDemain => true,
    DeclencheurNotification.sejourDepart => true,
    DeclencheurNotification.creanceEchue => false,
    DeclencheurNotification.creanceDouteuse => false,
    DeclencheurNotification.stockSousSeuil => false,
    DeclencheurNotification.departCircuitDemain => false,
    DeclencheurNotification.restitutionVehicule => false,
    DeclencheurNotification.bulletinDisponible => false,
    DeclencheurNotification.echeanceVps => false,
  };

  /// Pourquoi ce déclencheur ne compose rien sur ce poste — DATÉ, et vérifiable.
  ///
  /// Une raison de refus qui a cessé d'être vraie transforme une décision en
  /// oubli (PA-144, trois occurrences dans ce dépôt). Chaque motif porte donc la
  /// date à laquelle il a été vérifié, et se relit avant qu'on s'y fie.
  String get motifNonDetecte => switch (this) {
    DeclencheurNotification.sejourDemain ||
    DeclencheurNotification.sejourDepart => '',

    // Vérifié le 14/09/2026.
    DeclencheurNotification.creanceEchue ||
    DeclencheurNotification.creanceDouteuse =>
      // Texte affiché : codes internes et noms de tables retirés le
      // 14/10/2026 (directive du PO). Références : PA-20, PA-134, PA-129,
      // PA-53, `reservations_tour_local`, `contrats_location_local`.
      "La règle d'ancienneté 30 / 90 jours suppose une balance âgée, jamais "
          "arbitrée. L'écran Clients bloque déjà trois onglets sur "
          "quatre pour cette raison : l'inventer ici créerait deux vérités sur "
          'la même question, et on classerait ensuite un client en créance '
          "douteuse sur une date d'échéance que personne n'a décidée.",

    // Vérifié le 14/09/2026.
    DeclencheurNotification.stockSousSeuil =>
      'Les trois tables de stock de ce poste restent délibérément VIDES '
          ': le stock est calculé par le serveur, et ce poste est hors '
          'ligne. Détecter sur une table vide ne rendrait jamais aucune alerte '
          '— un silence qui se lirait comme « aucun article sous le seuil ».',

    // Vérifié le 14/09/2026.
    DeclencheurNotification.departCircuitDemain =>
      'Le catalogue des circuits descend du serveur et ce poste est hors '
          'ligne : les réservations de circuit ne sont écrites par aucun geste '
          'local. Même silence trompeur que le stock.',

    // Vérifié le 14/09/2026.
    DeclencheurNotification.restitutionVehicule =>
      'Les contrats de location ne sont lus par aucune détection de ce '
          'poste. Le déclencheur est pourtant portable tel quel le '
          'jour où les contrats seront répliqués — c\'est une absence de '
          "données, pas un refus d'architecture.",

    // Vérifié le 14/09/2026.
    DeclencheurNotification.bulletinDisponible ||
    DeclencheurNotification.echeanceVps =>
      "M13 n'a aucune table sur ce poste : la paie n'est pas au périmètre "
          'offline. Et le calcul de paie du serveur REFUSE déjà de rendre un '
          'total, faute de taux CNSS risques professionnels confirmé — '
          'un montant composé ici serait un chiffre que le serveur lui-même '
          'refuse de produire.',
  };

  /// Les codes, dans l'ordre du maître.
  static List<String> get codes =>
      values.map((d) => d.code).toList(growable: false);
}
