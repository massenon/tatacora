// Vue Blade maîtresse (PA-183) : pwa/achats/approvisionnement.blade.php
/// Les mots du règlement fournisseur (M7, D66) — ceux de `lang/fr/achats.php`
/// (`reglement_*`), de `lang/fr/achats_pwa.php` (`appro.*`), de
/// `lang/fr/pwa.php` (`appro.*`) et de `lang/fr/validation.php`, RELUS par PHP
/// dans `test/features/achats/reglement_contre_serveur_test.dart` : une phrase
/// recopiée sans cette épreuve ne vérifierait qu'elle-même.
///
/// Ce fichier cite la vue Approvisionnement parce qu'il porte les mots de sa
/// modale « Régler » et de son onglet « Dettes fournisseurs » : le comparateur
/// ne les lit que dans les fichiers qui la citent. La citation est honnête —
/// ces phrases SONT rendues, et un test de rendu le prouve.
///
/// Les « écarts du poste » en fin de fichier sont les SEULS textes qui n'ont pas
/// d'équivalent au serveur ; chacun dit lequel de ses comportements il remplace.
library;

abstract final class MessagesReglement {
  // --- Refus du SERVICE (`ReglementFournisseurService`) -----------------------

  /// `achats.reglement_tresorerie_inconnue`.
  static String tresorerieInconnue(String code) =>
      "La trésorerie « $code » n'existe pas au registre.";

  /// `achats.reglement_montant_invalide`.
  static const String montantInvalide =
      'Le montant réglé doit être supérieur à zéro.';

  /// `achats.reglement_superieur_au_reste` — [reste] est la chaîne à deux
  /// décimales du serveur (« 2500.00 »), pas un montant mis en forme.
  static String superieurAuReste(String reste) =>
      'Le montant dépasse le reste dû ($reste F). Un trop-payé ne '
      "s'enregistre pas : réglez le reste dû exact.";

  // --- Annulation (PA-168) ----------------------------------------------------

  /// `achats.reglement_deja_annule`.
  static const String dejaAnnule = 'Ce règlement est déjà annulé.';

  /// `achats.reglement_motif_requis`.
  static const String motifRequis =
      'Un motif est obligatoire pour annuler un règlement.';

  /// `achats.reglement_piece_introuvable`.
  static String pieceIntrouvable(String libelle) =>
      'La pièce comptable de ce règlement est introuvable ou déséquilibrée '
      "($libelle) : l'annulation est refusée plutôt que de contre-passer à "
      'moitié.';

  // --- Refus du COMPOSANT (`Approvisionnement`) --------------------------------

  /// `achats_pwa.appro.reglement_commande_soldee` — erreur `selection` à
  /// l'ouverture de la modale.
  static const String commandeSoldee =
      'Cette commande est déjà intégralement réglée.';

  // --- La modale « Régler » (vue l.574-608) -----------------------------------

  /// `achats_pwa.appro.form_reglement`.
  static String titreModale(String fournisseur) => 'Régler — $fournisseur';

  /// `achats_pwa.appro.form_reglement_sous_titre` — [reste] est DÉJÀ mis en forme
  /// par `MontantFcfa::format` ; il porte la valeur COURANTE du champ montant
  /// (voir `resteAffiche` de la modale).
  static String sousTitreModale(String commande, String reste) =>
      'Commande $commande — reste dû $reste';

  static const String libelleMontant = 'Montant réglé (FCFA)';
  static const String libelleTresorerie = 'Trésorerie';
  static const String libelleValider = 'Enregistrer le règlement';

  /// `pwa.modale.annuler`.
  static const String libelleAnnuler = 'Annuler';

  /// `achats_pwa.appro.reglement_enregistre` — ⚠ [montant] est la SAISIE brute
  /// (« 1500 »), sans mise en forme ni unité : le serveur passe
  /// `$donnees['regMontant']` tel quel. Incohérence répliquée, consignée D260.
  static String enregistre(String montant, String fournisseur) =>
      'Règlement de $montant enregistré pour $fournisseur.';

  static const String tresorerieCaisse = 'Caisse';
  static const String tresorerieMobileMoney = 'Mobile Money';
  static const String tresorerieBanque = 'Banque';

  /// Le bouton de la ligne (`achats_pwa.appro.regler`).
  static const String regler = 'Régler';

  // --- Les colonnes et l'onglet « Dettes fournisseurs » ------------------------

  static const String colRegle = 'Réglé';
  static const String colResteDu = 'Reste dû';
  static const String colNumeroCommande = 'N° commande';
  static const String colAnciennete = 'Ancienneté';

  static const String dettesTitre = 'Dettes fournisseurs';

  /// `achats_pwa.appro.dettes_portee`.
  static const String dettesPortee =
      "Cette liste porte sur les commandes non clôturées. « Réglé » et « Reste dû » viennent des règlements réellement enregistrés. La colonne « Ancienneté » mesure l'âge du bon de commande, pas le retard d'un paiement.";

  /// `pwa.appro.dettes_vide`.
  static const String dettesVide =
      'Aucune dette fournisseur. Toutes les commandes sont soldées.';

  static const String totalDu = 'Total dû';
  static const String kpiAPayer = 'Fournisseurs à payer';

  /// `pwa.appro.jours`.
  static String jours(int nombre) => '$nombre j';

  // --- Validation Livewire (`lang/fr/validation.php`) --------------------------
  //
  // ⚠ Le serveur nomme le champ par le nom de la PROPRIÉTÉ Livewire passée à
  // `snake_case` : « reg montant ». Aucune entrée de `validation.attributes` ne
  // la traduit. Les phrases elles-mêmes (`obligatoire`, `nombre`, `invalide`)
  // sont celles de l'encaissement (`MessagesEncaissement`) : un seul auteur des
  // phrases de Laravel.

  static const String attributCommande = 'reg commande id';
  static const String attributMontant = 'reg montant';
  static const String attributTresorerie = 'reg tresorerie';

  /// `validation.gt.numeric` : clé ABSENTE de `lang/fr/validation.php`, que
  /// Laravel rend telle quelle comme message. Défaut du SERVEUR, répliqué (D233,
  /// déjà consigné pour l'encaissement).
  static const String superieurAZero = 'validation.gt.numeric';

  // --- Écarts du poste : AUCUN équivalent au serveur ---------------------------

  /// Le serveur accepte « 1e3 » ou « 100 » (avec espace) au contrôle `numeric`,
  /// puis `bccomp` lève une `ValueError` — au rendu de la modale, HTTP 500 —
  /// AVANT d'écrire. Le poste refuse avec une phrase (D259).
  static const String malForme =
      "Ce montant n'est pas un nombre décimal simple (ni exposant, ni espace) : "
      'il ne peut pas être comparé au reste dû. Rien n\'est enregistré.';

  /// L'auteur est inconnu : `auth()->id()` n'est jamais nul au serveur (la route
  /// est authentifiée).
  static const String auteurInconnu =
      "L'auteur est inconnu : aucun règlement n'est enregistré, et un règlement "
      'sans nom de qui l\'a décaissé n\'est pas permis.';

  /// Le service reçoit un MODÈLE chargé (`regler(CommandeAchat $commande, …)`) :
  /// une commande absente n'y est pas un cas. Sur le poste, le service reçoit
  /// un identifiant, et ce cas a sa phrase. (Au geste d'ENREGISTREMENT, le
  /// serveur répond par la validation `exists` ; à l'OUVERTURE, par la phrase de
  /// `achats.commande_cloturee` — D258.)
  static const String commandeIntrouvable = 'Commande introuvable.';

  /// L'identifiant ne désigne aucun règlement. Le serveur reçoit un MODÈLE chargé
  /// par la liaison de route : le cas n'y existe pas.
  static const String reglementIntrouvable = 'Règlement introuvable.';
}
