/// Les phrases de refus et de confirmation de M7.
///
/// ## Un seul auteur par phrase, et c'est le serveur
///
/// Chaque phrase ci-dessous est celle de `lang/fr/achats.php`,
/// `achats_pwa.php` ou `stocks.php`, mot pour mot, **relue par exécution de
/// PHP** (`calcul_achats_contre_serveur_test.dart`) : un refus n'a qu'une
/// formulation, que l'exploitant lise le poste ou la PWA. Deux phrases
/// voisines écrites à la main finissent par se contredire.
///
/// Les phrases propres à CE POSTE n'existent pas au serveur, et le disent. Les
/// mots du règlement fournisseur (D66) vivent dans `messages_reglement.dart`.
/// Ceux de l'archivage (D63) portent leur clé de langue en commentaire.
library;

abstract final class MessagesAchats {
  /* ---- Refus du serveur, repris au mot ---- */

  static const String commandeCloturee =
      'Cette commande est déjà clôturée : une réception supplémentaire créerait '
      'une entrée de stock sans commande en face.';

  static const String receptionVide =
      'Une réception doit porter sur au moins un article.';

  static const String clotureImpossible =
      "Cette commande ne peut pas être clôturée : la réception n'est pas "
      'conforme à la tolérance configurée. Enregistrez la réception '
      "complémentaire ou faites acter l'écart par un responsable.";

  static const String toleranceAbsente =
      "La tolérance de réception n'est pas configurée (paramètre "
      '`tolerance_reception_pct`, RG-10). Aucune conformité ne peut être '
      "évaluée tant qu'un Administrateur ne l'a pas renseignée.";

  static const String envoiImpossible =
      'Seule une commande en brouillon peut être émise : une commande déjà '
      'émise, réceptionnée ou clôturée ne se réémet pas.';

  static const String factureAbsente =
      'Facture fournisseur non fournie : le rapprochement ne porte que sur '
      'commande et réception. Le troisième volet reste à vérifier manuellement.';

  static const String fournisseurInexistant =
      'Fournisseur inconnu du référentiel. Un fournisseur se choisit dans la '
      'liste, il ne se saisit pas en texte libre : le rapprochement à trois '
      'voies suppose une relation exacte.';

  static const String raisonSocialeObligatoire =
      'La raison sociale est obligatoire.';

  static const String evaluationInconnue =
      'Évaluation inconnue. Le registre est fermé : excellent, bon, moyen, '
      'a_revoir.';

  static const String lignesObligatoires =
      "Une commande d'achat porte au moins une ligne : une commande vide n'a "
      'rien à réceptionner et fausserait le rapprochement.';

  static const String articleInexistant = 'Article inconnu du référentiel.';

  static const String articleEnDouble =
      'Le même article figure deux fois. Les quantités commandées sont relues '
      'article par article : la seconde ligne écraserait la première, et le '
      'rapprochement comparerait le reçu à une quantité commandée '
      'sous-évaluée.';

  static const String quantitePositive =
      "La quantité doit être strictement positive : une saisie à zéro n'est "
      'pas une ligne de commande.';

  /// `achats_pwa.appro.prix_obligatoire` : la PWA exige un prix STRICTEMENT
  /// positif (l'API accepte zéro). Ce poste suit la vue (PA-182) : le prix
  /// sert au montant de la commande et à la dette du fournisseur.
  ///
  /// ÉCART NOMMÉ (D276) — la phrase du serveur (`achats_pwa.appro.
  /// prix_obligatoire`, vue d'approvisionnement, modale de commande) se termine par « , ni aucun coût moyen pondéré mis à jour à la
  /// réception ». FAUX : le serveur exécuté ne met aucun coût à jour à la
  /// réception (D265). Cette fin est RETIRÉE, le reste est au mot ; le test
  /// `calcul_achats_contre_serveur_test.dart` épingle l'écart (il rougit si le
  /// serveur change la phrase). Vue à faire corriger par l'Architecte.
  static const String prixObligatoire =
      'Le prix unitaire est obligatoire et strictement positif : sans lui '
      'aucun montant de commande ne peut être calculé.';

  static const String pointInexistant =
      "Point de stockage inconnu : l'entrée de stock ne peut pas être imputée.";

  /// `stocks.point_introuvable` : la phrase que le serveur lève à la réception
  /// quand le point n'existe pas (`ReceptionService::verifierPointStockage`).
  static const String pointIntrouvable =
      'Point de stockage inconnu : la réception ne peut pas être imputée.';

  static const String aucunPoint =
      "Aucun point de stockage n'est enregistré : une réception doit dire OÙ "
      'la marchandise entre, sans quoi aucun mouvement de stock ne peut être '
      'écrit.';

  static const String aucunFournisseur =
      "Aucun fournisseur n'est enregistré : une commande d'achat porte une "
      'vraie clé étrangère vers le référentiel. Créez le fournisseur sur '
      "l'écran « Fournisseurs & Achats » d'abord.";

  /* ---- Gabarits à trous ---- */

  /// `achats.motif_reception` : `Réception commande :commande — bon :bon`.
  /// Le motif de l'entrée de stock générée par la réception.
  static String motifReception({
    required String commande,
    required String bon,
  }) => 'Réception commande $commande — bon $bon';

  /// `achats_pwa.appro.commande_creee`.
  static String commandeCreee(String fournisseur) =>
      'Bon de commande créé pour $fournisseur.';

  // `achats_pwa.appro.reception_enregistree` (« Réception enregistrée (:conformite)
  // — stock et coût moyen pondéré mis à jour. ») n'est PAS portée (D276) : le
  // poste n'a aucun toast de réception (la modale se ferme et rend le bon), et
  // la phrase du serveur est FAUSSE sur le coût moyen pondéré. Un gabarit sans
  // appelant de production, de surcroît faux, serait une affirmation prête à
  // être branchée. Le test `reception_valorisation_contre_serveur_test.dart`
  // épingle l'absence.

  /// `achats_pwa.achats.cree` / `modifie`.
  static String fournisseurCree(String nom) =>
      'Fournisseur « $nom » enregistré.';
  static String fournisseurModifie(String nom) =>
      'Fournisseur « $nom » mis à jour.';

  /* ---- Propres à ce poste ---- */

  /// `achats_pwa.archivage.verrou` — le motif d'un fournisseur ENGAGÉ : une
  /// commande qui n'est ni réceptionnée ni clôturée a encore besoin de lui.
  static String verrouArchivage(int nombre) =>
      "Engagé dans $nombre commande(s) d'achat en cours : la réception à venir "
      'a besoin de ce fournisseur au sélecteur.';

  /// `achats_pwa.archivage.succes` (`trans_choice`) : « {1} Fournisseur
  /// archivé… | [2,*] :nombre fournisseurs archivés… ».
  static String archivesSucces(int nombre) => nombre == 1
      ? 'Fournisseur archivé — il reste restaurable.'
      : '$nombre fournisseurs archivés — ils restent restaurables.';

  /// `achats_pwa.archivage.restaure`.
  static String restaure(String nom) =>
      'Fournisseur « $nom » restauré : il revient au sélecteur des commandes.';

  /// `pwa.archivage.refus_bascule` — le refus d'`exigerArchivage()` : l'option
  /// « Suppression d'un enregistrement » est fermée pour ce profil.
  static const String refusBascule =
      "Archivage refusé : l'option « Suppression d'un enregistrement » est "
      'fermée en Paramètres pour ce profil.';

  static const String droitLectureRefuse =
      "Vous n'avez pas le droit de consulter les achats.";

  static const String droitEcritureRefuse =
      "Vous n'avez pas le droit de modifier les achats. Rien n'a été "
      'enregistré.';

  static const String auteurInconnu =
      "L'auteur est inconnu : aucune session n'est ouverte, et une écriture "
      'sans « qui » ne peut pas être opposée à un inventaire.';

  /// Propre à ce poste : le DAO du stock a rendu autre chose qu'une entrée
  /// posée. Le bon n'est pas écrit.
  static const String entreeNonEcrite =
      "L'entrée de stock n'a pas pu être écrite : la réception est annulée, "
      'ni le bon ni le stock ne sont modifiés.';

  static const String commandeIntrouvable = 'Commande introuvable.';

  static const String fournisseurIntrouvable = 'Fournisseur introuvable.';

  static const String toleranceIllisible =
      "La tolérance de réception saisie en Paramètres n'est pas lisible "
      "(au plus deux décimales, positive ou nulle) : aucune conformité n'est "
      'évaluée sur une règle que le poste ne sait pas lire.';

  static const String quantiteRecuePositive =
      'La quantité reçue de chaque article doit être strictement positive : '
      "une quantité à zéro s'omet, elle ne se déclare pas.";

  static const String articleEnDoubleReception =
      'Le même article figure deux fois dans la réception : la seconde ligne '
      'écraserait la première, et la marchandise entrerait en stock amputée '
      'de la première.';

  static const String dateIllisible =
      'La date de commande doit être une date valide (AAAA-MM-JJ).';
}
