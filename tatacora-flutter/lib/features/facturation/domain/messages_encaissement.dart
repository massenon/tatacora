// Vue Blade maîtresse (PA-183) : pwa/crm/clients-creances.blade.php
/// Les mots de l'encaissement de facture — ceux de `lang/fr/facturation.php`
/// (`encaissement_*`, `paiement_*`), de `lang/fr/pwa.php` (`clients.*`) et de
/// `lang/fr/validation.php`, RELUS par PHP dans
/// `test/features/facturation/encaissement_contre_serveur_test.dart` : une phrase
/// recopiée sans cette épreuve ne vérifierait qu'elle-même.
///
/// Les « écarts du poste » en fin de fichier sont les SEULS textes qui n'ont pas
/// d'équivalent au serveur ; chacun dit lequel de ses comportements il remplace.
library;

abstract final class MessagesEncaissement {
  // --- Refus du SERVICE (`EncaissementFactureService`) -----------------------

  /// `facturation.encaissement_facture_non_figee`. Inatteignable sur ce poste :
  /// toute pièce du registre est figée dès son émission (aucun brouillon, aucun
  /// cycle MECeF). Gardé pour qu'une pièce non figée, le jour où il en existerait
  /// une, soit refusée par la phrase du serveur et non acceptée par omission.
  static const String factureNonFigee =
      'Cette facture n\'est pas encore figée : émettez-la avant d\'encaisser.';

  /// `facturation.encaissement_mode_inconnu`.
  static String modeInconnu(String mode) =>
      'Le mode de paiement « $mode » n\'existe pas au registre.';

  /// `facturation.encaissement_montant_invalide`.
  static const String montantInvalide =
      'Le montant encaissé doit être supérieur à zéro.';

  /// `facturation.encaissement_superieur_au_reste` — [reste] est la chaîne à
  /// deux décimales du serveur (« 6000.00 »), pas un montant mis en forme.
  static String superieurAuReste(String reste) =>
      'Le montant dépasse le reste dû ($reste F). Un trop-perçu ne s\'enregistre '
      'pas : encaissez le reste dû exact.';

  /// `facturation.encaissement_caisse_fermee`.
  static const String caisseFermee =
      'Aucune session de caisse n\'est ouverte : ouvrez la caisse avant '
      'd\'encaisser.';

  // --- Annulation (PA-168) ----------------------------------------------------

  /// `facturation.paiement_deja_annule`.
  static const String dejaAnnule = 'Cet encaissement est déjà annulé.';

  /// `facturation.paiement_motif_requis`.
  static const String motifRequis =
      'Un motif est obligatoire pour annuler un encaissement.';

  /// `facturation.paiement_piece_introuvable`.
  static String pieceIntrouvable(String libelle) =>
      'La pièce comptable de cet encaissement est introuvable ou déséquilibrée '
      '($libelle) : l\'annulation est refusée plutôt que de contre-passer à '
      'moitié.';

  // --- Refus du COMPOSANT (`ClientsCreances`) ---------------------------------

  /// `auth.module_refuse` — le serveur répond 403 avant toute validation, et le
  /// droit exigé est celui de DEUX modules : M3 (l'écran) puis M2 (l'écriture
  /// d'un encaissement de facture).
  static const String refusDroit = 'Vous n avez pas acces a ce module.';

  /// `pwa.clients.recouvrement_aucune_creance`.
  static const String aucuneCreance = 'Ce client n\'a aucune créance en cours.';

  /// `pwa.clients.recouvrement_avertissement` (l'encadré de la modale).
  static const String avertissement =
      'Un montant supérieur au reste dû est refusé.';

  /// `pwa.clients.recouvrement_succes` — [montant] est DÉJÀ mis en forme par
  /// `MontantFcfa::format`, suffixe « FCFA » compris.
  static String succes(String montant, String client) =>
      'Recouvrement de $montant enregistré pour $client.';

  // --- Validation Livewire (`lang/fr/validation.php`) --------------------------
  //
  // ⚠ Le serveur nomme le champ par le nom de la PROPRIÉTÉ Livewire passée à
  // `snake_case` : « recouvrement montant ». Aucune entrée de
  // `validation.attributes` ne la traduit. Le message est répliqué tel quel — un
  // nom technique devant l'opérateur est une incohérence du serveur, signalée,
  // pas corrigée ici.

  /// `validation.required`.
  static String obligatoire(String attribut) =>
      'Le champ $attribut est obligatoire.';

  /// `validation.numeric`.
  static String nombre(String attribut) =>
      'Le champ $attribut doit être un nombre.';

  /// `validation.uuid`.
  static String uuid(String attribut) =>
      'Le champ $attribut doit être un UUID valide.';

  /// `validation.exists` / `validation.in`.
  static String invalide(String attribut) =>
      'La valeur sélectionnée pour $attribut est invalide.';

  /// `validation.gt.numeric` : cette clé N'EXISTE PAS dans `lang/fr/validation.php`
  /// (le fichier déclare `min`, `max`, `between`, `size`, `lte`… mais pas `gt`).
  /// Laravel rend alors la CLÉ elle-même comme message. C'est ce que la vue
  /// affiche à un opérateur qui saisit 0 ou un montant négatif — un défaut du
  /// SERVEUR, répliqué à l'identique et signalé à l'Architecte (D233), jamais
  /// corrigé ici.
  static const String superieurAZero = 'validation.gt.numeric';

  /// Les attributs, tels que le serveur les imprime.
  static const String attributPiece = 'recouvrement facture id';
  static const String attributMontant = 'recouvrement montant';
  static const String attributMode = 'recouvrement mode';

  // --- Écarts du poste : AUCUN équivalent au serveur ---------------------------

  /// Le serveur accepte « 1.5e3 » au contrôle `numeric` puis `bccomp` lève une
  /// `ValueError` (HTTP 500) AVANT d'écrire. Le poste refuse avec une phrase.
  static const String malForme =
      'Ce montant n\'est pas un nombre décimal simple (ni exposant, ni espace) : '
      'il ne peut pas être comparé au reste dû. Rien n\'est enregistré.';

  /// Hors plage de `DECIMAL(15,2)` : le serveur lève une `QueryException`
  /// (« Out of range value »), sans phrase pour l'opérateur.
  static const String horsPlage =
      'Ce montant dépasse ce que la caisse peut porter '
      '(9 999 999 999 999,99 FCFA). Rien n\'est enregistré.';

  /// Au serveur, une facture est une ligne de `factures` ; ici le registre
  /// unique mêle factures, AVOIRS et TICKETS de vente au comptant. Un avoir n'est
  /// pas une créance, et un ticket au comptant a déjà été encaissé par la vente
  /// (sa session est portée par le panier) : l'encaisser une seconde fois
  /// doublerait la caisse. Le serveur n'a pas ce cas — ses ventes ne sont pas
  /// des factures.
  static const String pieceNonEncaissable =
      'Cette pièce n\'est pas une facture à encaisser : un avoir ne se règle '
      'pas, et un ticket de vente au comptant a déjà été encaissé à la vente.';

  /// L'auteur est inconnu : `Auth::id()` n'est jamais nul au serveur (la route
  /// est authentifiée). Même phrase que l'ouverture de caisse.
  static const String auteurInconnu =
      'L\'auteur est inconnu : aucun encaissement n\'est enregistré, et un '
      'encaissement sans nom de qui l\'a reçu romprait RG-15.';

  /// Le serveur ne contrôle pas qu'un encaissement annulé existe avant de
  /// l'annuler (le modèle est déjà chargé) ; ici l'identifiant peut être inconnu.
  static const String paiementIntrouvable =
      'Cet encaissement est introuvable sur ce poste.';

  /// Le tiret des montants non établis — `MontantFcfa::TIRET`.
  static const String tiret = '—';
}
