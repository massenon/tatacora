// Vue Blade maîtresse (PA-183) : pwa/pos/comptant.blade.php
/// Les mots de la caisse — ceux de `lang/fr/pos_pwa.php` (`comptant.*`) et de
/// `lang/fr/validation.php`, relus par PHP dans
/// `test/features/caisse/caisse_contre_serveur_test.dart` : une phrase
/// recopiée sans cette épreuve ne vérifierait qu'elle-même.
///
/// Les « écarts du poste » en fin de fichier sont les SEULS textes qui n'ont pas
/// d'équivalent au serveur ; chacun dit lequel de ses comportements il remplace.
library;

abstract final class MessagesCaisse {
  // --- Barre de session (comptant.blade.php l.74-150) -----------------------

  /// `pos_pwa.comptant.caisse_ouverte`.
  static String caisseOuverte(String point) => 'Caisse $point ouverte';

  /// `pos_pwa.comptant.caisse_depuis`.
  static String depuis(String heure) => 'depuis $heure';

  /// `pos_pwa.comptant.caisse_fond`.
  static String fond(String montant) => 'Fond $montant';

  /// `pos_pwa.comptant.caisse_ventes`.
  static String ventes(int nombre) => '$nombre vente(s)';

  /// `pos_pwa.comptant.caisse_ca`.
  static String chiffreAffaires(String montant) => 'CA $montant';

  /// `pos_pwa.comptant.caisse_encaisse`.
  static String encaisse(String montant) => 'Encaissé $montant';

  /// `pos_pwa.comptant.caisse_en_note`.
  static String enNote(String montant) => 'En note $montant';

  /// `pos_pwa.comptant.journal_du_jour`.
  static const String journalDuJour = 'Journal du jour';

  /// `pos_pwa.comptant.caisse_aucune`.
  static const String aucuneCaisse = 'Aucune caisse ouverte';

  /// `pos_pwa.comptant.caisse_aucune_aide` — vrai sur ce poste pour une vente
  /// au comptant (la clôture refuse sans caisse `bar` ouverte).
  static const String aucuneCaisseAide =
      'Aucune vente n\'est possible tant que la caisse n\'est pas ouverte.';

  /// `pos_pwa.comptant.ouvrir_caisse`.
  static const String ouvrirLaCaisse = 'Ouvrir la caisse';

  /// `pos_pwa.comptant.cloturer_caisse`.
  static const String cloturerLaCaisse = 'Clôturer la caisse';

  // --- Modale d'ouverture (l.638-660) ----------------------------------------

  /// `pos_pwa.comptant.ouverture_titre`.
  static String titreOuverture(String point) => 'Ouvrir la caisse $point';

  /// `pos_pwa.comptant.ouverture_fond`.
  static const String etiquetteFond = 'Fond de caisse (FCFA)';

  // --- Modale de clôture (l.660-700) -----------------------------------------

  /// `pos_pwa.comptant.cloture_titre`.
  static String titreCloture(String point) => 'Clôturer la caisse $point';

  /// `pos_pwa.comptant.cloture_theorique` (sous-titre).
  static const String sousTitreCloture = 'Théorique — fond + ventes encaissées';

  /// `pos_pwa.comptant.cloture_recap_fond`.
  static const String recapFond = 'Fond de caisse';

  /// `pos_pwa.comptant.cloture_recap_especes`.
  static const String recapEspeces = 'Espèces encaissées';

  /// `pos_pwa.comptant.cloture_recap_theorique`.
  static const String recapTheorique = 'Théorique en caisse';

  /// `pos_pwa.comptant.cloture_constate`.
  static const String etiquetteConstate = 'Montant réellement compté';

  /// `pos_pwa.comptant.cloture_recap_aide`.
  static const String aideRecap =
      'Seules les espèces sont dans le tiroir. Mobile Money, carte et notes de '
      'chambre en sont exclus.';

  /// `pos_pwa.comptant.encaisser_sans_caisse` — le libellé du bouton d'encaissement
  /// quand aucune caisse n'est ouverte (il est alors désactivé).
  static const String encaisserSansCaisse = 'Ouvrez la caisse pour encaisser';

  /// `pwa.modale.annuler`.
  static const String annuler = 'Annuler';

  // --- Issues ----------------------------------------------------------------

  /// `pos_pwa.comptant.caisse_ouverte_message`.
  static String ouverte(String point) => 'Caisse $point ouverte.';

  /// `pos_pwa.comptant.caisse_cloturee` — « écart de :ecart », jamais un signe
  /// brut devant un zéro.
  static String cloturee(String point, String ecart) =>
      'Caisse $point clôturée — écart de $ecart.';

  /// `pos_pwa.comptant.caisse_cloturee_sans_ecart`.
  static String clotureeSansEcart(String point) =>
      'Caisse $point clôturée — aucun écart.';

  /// `pos_pwa.comptant.refus_caisse_deja_ouverte`.
  static const String refusDejaOuverte =
      'Une caisse est déjà ouverte à ce point de vente. '
      'Clôturez-la avant d\'en ouvrir une seconde.';

  /// `pos_pwa.comptant.refus_sans_caisse`.
  static const String refusSansCaisse =
      'Aucune caisse n\'est ouverte à ce point de vente. '
      'Ouvrez-la avant d\'encaisser : sans elle, la vente ne serait rattachée '
      'à aucun fond.';

  // --- Validation (lang/fr/validation.php) -----------------------------------
  //
  // ⚠ Le serveur nomme le champ par le nom de la PROPRIÉTÉ Livewire passée à
  // `snake_case` : « fond caisse saisi », « montant constate saisi ». Aucune
  // entrée de `validation.attributes` ne les traduit. Le message est répliqué
  // tel quel — un nom technique devant le caissier est une incohérence du
  // serveur, signalée, pas corrigée ici.

  /// `validation.required`.
  static String obligatoire(String attribut) =>
      'Le champ $attribut est obligatoire.';

  /// `validation.numeric`.
  static String nombre(String attribut) =>
      'Le champ $attribut doit être un nombre.';

  /// `validation.min.numeric` — sans accent, comme le fichier de langue.
  static String minimum(String attribut, String min) =>
      'Le champ $attribut doit etre au minimum de $min.';

  /// L'attribut de `fondCaisseSaisi`.
  static const String attributFond = 'fond caisse saisi';

  /// L'attribut de `montantConstateSaisi`.
  static const String attributConstate = 'montant constate saisi';

  // --- Écarts du poste : AUCUN équivalent au serveur -------------------------

  /// Le serveur lève ici une `QueryException` SQL (« Out of range value for
  /// column ») et n'écrit rien, sans phrase pour l'exploitant.
  static const String horsPlage =
      'Ce montant dépasse ce que la caisse peut porter '
      '(9 999 999 999 999,99 FCFA). Rien n\'est enregistré.';

  /// Le serveur accepte « 1.5e3 » au contrôle `numeric`, puis `bcsub` lève une
  /// `ValueError` (HTTP 500) AVANT d'écrire : la session reste ouverte.
  static const String malForme =
      'Ce montant n\'est pas un nombre décimal simple (ni exposant, ni espace) : '
      'l\'écart ne peut pas en être calculé. Rien n\'est enregistré.';

  /// Le tiret des montants non établis — `MontantFcfa::TIRET`.
  static const String tiret = '—';

  /// ⚠ ÉCART DU POSTE (lot 6, réserve R2) — aucun équivalent au serveur, qui
  /// écrit `ventes.session_id` depuis toujours. Le poste, lui, a des ventes
  /// d'AVANT la v18 : réglées en espèces, clôturées depuis l'ouverture de cette
  /// caisse, rattachées à AUCUNE session. Le théorique ne les compte pas.
  ///
  /// La phrase dit ce que le poste SAIT (le nombre, le montant, que le théorique
  /// ne les compte pas) et ce qu'il ne sait pas (si l'argent est dans le tiroir).
  static String ventesSansSession(int nombre, String montant) => nombre == 1
      ? 'Une vente en espèces ($montant), clôturée depuis l\'ouverture de cette '
            'caisse, n\'est rattachée à aucune session : elle date d\'avant le '
            'rattachement des ventes à une caisse. Elle n\'est PAS comptée dans '
            '« Espèces encaissées » ni dans le théorique ci-dessus — comptez le '
            'tiroir en conséquence : le chiffre pré-rempli peut être inférieur à '
            'ce qu\'il contient.'
      : '$nombre ventes en espèces ($montant au total), clôturées depuis '
            'l\'ouverture de cette caisse, ne sont rattachées à aucune session : '
            'elles datent d\'avant le rattachement des ventes à une caisse. Elles '
            'ne sont PAS comptées dans « Espèces encaissées » ni dans le '
            'théorique ci-dessus — comptez le tiroir en conséquence : le chiffre '
            'pré-rempli peut être inférieur à ce qu\'il contient.';

  /// Le serveur répond 403 (`auth.module_refuse`) avant toute validation.
  static const String refusDroit = 'Vous n avez pas acces a ce module.';
}
