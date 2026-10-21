/// Les LIBELLÉS et les TRACÉS de la coquille de la vue — barre supérieure,
/// menu de compte, pied de la barre latérale (lot 1 « coquille », 12/10/2026).
///
/// ## D'où vient chaque chaîne
///
/// Des clés de langue que la vue rend (`lang/fr/pwa.php`, groupes `coquille`,
/// `accueil` et la racine ; `lang/fr/rapports.php` pour la ligne sous la
/// marque depuis le 13/10/2026). Elles sont recopiées ici UNE fois, et
/// `coquille_rendu_test.dart` les
/// confronte aux clés résolues par PHP à chaque exécution : la copie n'est pas
/// une source, elle est vérifiée. Les tracés SVG sont ceux de la vue, au
/// caractère près — barre supérieure et menu de compte (`$entreesDeCompte`,
/// `$entreesDAide`), pied de la barre latérale.
///
/// Chemins écrits sans leur préfixe : ce fichier ne porte aucune vue de page
/// (PA-187 — citer le chemin complet en ferait un porteur).
library;

import 'dart:convert' show utf8;

/// Les chaînes de la coquille.
abstract final class LibellesCoquille {
  /// `pwa.marque`.
  static const String marque = 'TATACORA AFRIQUE';

  /// `pwa.enseigne_courte` — le badge doré de la barre supérieure.
  static const String enseigneCourte = 'Gîte Chez Noël';

  /// La ligne sous la marque — `rapports.entete.localisation`, que la barre
  /// supérieure de la vue rend sous la marque (`partials/barre-superieure`).
  ///
  /// DÉCISION DU PRODUCT OWNER DU 13/10/2026 (« faut remplacer logiRestock par
  /// système d'information intégré », D373) : la vue écrivait en dur une
  /// mention au nom d'un autre produit (PA-194) ; elle rend désormais la clé de
  /// localisation des états, la même qu'imprime l'en-tête des PDF. La vue a
  /// été corrigée D'ABORD, ce client la suit. La décision D307 du 12/10/2026,
  /// qui gardait l'ancienne mention parce que la vue l'écrivait, est renversée.
  ///
  /// SECONDE DÉCISION DU PO DU 13/10/2026 (PA-209, D389) : « Système
  /// d'Information Intégré » devient « Système de gestion Intégré », casse
  /// exacte du PO. La clé de la vue a changé d'abord ; ce client la suit.
  ///
  /// TROISIÈME DÉCISION DU PO DU 14/10/2026 : la ligne sous la marque
  /// devient « Système de gestion Intégré — Gîte Chez Noël, Natitingou
  /// (Bénin) », comme la clé serveur `rapports.entete.localisation`.
  static const String localisation =
      'Système de gestion Intégré — Gîte Chez Noël, Natitingou (Bénin)';

  /// `pwa.alt_logo` — le texte de remplacement du logo, rendu en sémantique.
  static const String altLogo = 'Logo TATACORA AFRIQUE';

  /// `pwa.mention_pied_menu` — le pied de la barre latérale.
  static const String mentionPiedMenu = 'TATACORA AFRIQUE — PAEB / FAGUEZ SARL';

  /// `pwa.accueil.deconnexion`.
  static const String deconnexion = 'Déconnexion';

  /// `pwa.coquille.banniere_lecture_titre` — le gras du bandeau de la coquille.
  static const String banniereLectureTitre = 'Accès lecture seule';

  /// `pwa.coquille.banniere_lecture_detail` — la suite du bandeau, UN seul
  /// littéral (la vue écrit « les actions d'écriture » à la place des trois
  /// boutons du maître ; écart motivé dans le partiel de la vue).
  static const String banniereLectureDetail =
      "sur ce module avec le profil actuel — les actions d'écriture sont masquées (droits RBAC).";

  /// `pwa.coquille.banniere_changer_profil` — la flèche fait partie du libellé.
  static const String banniereChangerProfil =
      'Se connecter avec un autre profil →';

  /// `pwa.coquille.ouvrir_menu` — l'`aria-label` du bouton de menu mobile.
  static const String ouvrirMenu = 'Ouvrir le menu';

  /// `pwa.coquille.plein_ecran`.
  static const String pleinEcran =
      'Masquer ou afficher le menu latéral (vue plein écran)';

  /// `pwa.coquille.vente` et son infobulle `pwa.coquille.vente_titre`.
  static const String vente = 'Vente';
  static const String venteTitre =
      'Vente — encaisser une consommation sans réservation';

  /// `pwa.coquille.caisse_fermee`, `caisse_cloturer`, `caisse_cloturer_titre`.
  static const String caisseFermee = 'Caisse fermée';
  static const String caisseCloturer = 'Clôturer la caisse';
  static String caisseCloturerTitre(String point) =>
      'Clôturer la caisse du $point';

  /// Le menu de compte, dans l'ordre de la vue (`$entreesDeCompte` puis
  /// `$entreesDAide`).
  static const String monProfil = 'Mon profil';
  static const String parametresCompte = 'Paramètres du compte';
  static const String importExport = 'Import & Export';
  static const String journalAudit = "Journal d'Audit";

  /// Décision PO du 18/10/2026 : le bouton « Synchroniser » du serveur.
  static const String synchronisationPostes = 'Synchroniser les postes';
  static const String aideAPropos = 'Aide & À propos';
  static const String contactEditeur = "Contactez l'éditeur";

  /// `pwa.coquille.ecran_a_venir` — l'infobulle que la vue pose sur une entrée
  /// SANS écran servi (`entree-menu.blade.php`, branche `<span aria-disabled>`).
  static const String ecranAVenir = 'Écran de consultation à venir';

  /// `pwa.coquille.sans_droit` — l'infobulle d'un lien de châssis refusé par le
  /// droit (`lien-chassis.blade.php`, branche `url = null`).
  static const String sansDroit = "Votre profil n'a pas accès à cet écran";

  /// Le message affiché AU CLIC sur une entrée sans écran Flutter.
  ///
  /// ÉCART à la vue, daté du 12/10/2026 : la vue rend une `<span>` que le clic
  /// n'atteint pas (son infobulle est la seule explication). Ici, l'Article 3.3
  /// de `DIRECTIVE_CONFORMITE_100.md` interdit un contrôle muet : le clic DIT
  /// que l'écran n'est pas encore porté sur CE poste — « consultation » est le
  /// mot du canal web, il ne suffit pas à dire ce qui manque ici.
  static String ecranNonPorte(String nom) =>
      '« $nom » : écran non encore porté sur ce poste.';

  /// `pwa.recherche_globale.*` — la recherche globale de la barre supérieure.
  static const String rechercheInvite = 'Rechercher partout…';
  static const String rechercheTropCourt =
      'Saisissez au moins deux caractères.';
  static const String rechercheAucun = 'Aucun résultat pour cette recherche.';

  /// AJOUT déclaré (14/10/2026) — la vue n'a pas d'état d'échec : sa requête
  /// part au serveur, une erreur y est une page d'erreur. Ici, une lecture de
  /// la base locale qui lève ne doit pas se lire « Aucun résultat ».
  static const String rechercheLectureImpossible =
      "La recherche n'a pas pu lire la base de ce poste.";
  static const String rechercheFamillePages = 'Pages';
  static const String rechercheFamilleClients = 'Clients';
  static const String rechercheFamilleArticles = 'Articles en stock';
  static const String rechercheFamillePlats = 'Plats';
  static const String rechercheFamilleCarteBar = 'Carte du bar';
  static const String rechercheFamilleFactures = 'Factures';
  static const String rechercheFamilleFournisseurs = 'Fournisseurs';
  static const String rechercheFamilleVehicules = 'Véhicules';
  static const String rechercheFamilleCircuits = 'Circuits';

  /// Le message affiché APRÈS l'ouverture d'un écran depuis un résultat de
  /// DONNÉES. ÉCART à la vue, daté du 14/10/2026 : la vue passe le terme en
  /// `?q=` et l'écran se filtre lui-même ; les écrans de ce poste ne lisent
  /// aucun paramètre d'URL, ils s'ouvrent donc non filtrés. Le dire évite de
  /// laisser croire que la liste affichée est le résultat de la recherche.
  static String rechercheEcranNonFiltre(String terme, String famille) =>
      '« $famille » ouvert sans filtre sur ce poste : saisissez « $terme » '
      "dans la recherche de l'écran.";
}

/// Les tracés SVG de la coquille — contenus des `<svg viewBox="0 0 24 24">` de
/// la vue, au caractère près.
abstract final class TracesCoquille {
  /// La sortie — bouton « Déconnexion » du pied de la barre latérale et du menu
  /// de compte (`menu-lateral` l.31, `barre-superieure` l.262).
  static const String deconnexion =
      r'<path stroke-linecap="round" stroke-linejoin="round" d="M9 21H5a2 2 0 01-2-2V5a2 2 0 012-2h4M16 17l5-5-5-5M21 12H9"/>';

  /// Le chevron du bouton de compte (`barre-superieure` l.221).
  static const String chevron =
      r'<path stroke-linecap="round" stroke-linejoin="round" d="M6 9l6 6 6-6"/>';

  /// La bascule plein écran (`barre-superieure` l.123).
  static const String pleinEcran =
      r'<rect x="3" y="4" width="18" height="16" rx="2"/><path stroke-linecap="round" d="M9 4v16"/>';

  /// Le bouton de menu mobile (`barre-superieure` l.111).
  static const String menuMobile =
      r'<path stroke-linecap="round" d="M4 6h16M4 12h16M4 18h16"/>';

  /// Le bouton « Vente » (`barre-superieure` l.192), tracé à 2,5.
  static const String vente =
      r'<rect x="2" y="7" width="20" height="14" rx="2"/><path stroke-linecap="round" d="M16 7V5a2 2 0 00-2-2h-4a2 2 0 00-2 2v2M2 12h20"/>';

  /// La cloche (`transverse/cloche-notifications` l.15), tracé 20 px.
  static const String cloche =
      r'<path stroke-linecap="round" stroke-linejoin="round" d="M18 8a6 6 0 00-12 0c0 7-3 9-3 9h18s-3-2-3-9"/><path stroke-linecap="round" stroke-linejoin="round" d="M13.73 21a2 2 0 01-3.46 0"/>';

  /// Le bouton de SYNCHRONISATION (lot F3, ajout du PO du 16/10/2026 — la
  /// vue n'en a pas) : deux flèches en cercle, tracé 20 px comme la cloche.
  static const String synchronisation =
      r'<path stroke-linecap="round" stroke-linejoin="round" d="M3 12a9 9 0 019-9 9.75 9.75 0 016.74 2.74L21 8M21 3v5h-5M21 12a9 9 0 01-9 9 9.75 9.75 0 01-6.74-2.74L3 16M8 16H3v5"/>';

  /// La loupe du champ de recherche (`transverse/recherche-globale` l.9).
  static const String loupe =
      r'<circle cx="11" cy="11" r="8"/><path stroke-linecap="round" d="M21 21l-4.35-4.35"/>';

  /// La flèche d'un résultat « Pages » (`transverse/recherche-globale` l.29).
  static const String flechePage =
      r'<path stroke-linecap="round" stroke-linejoin="round" d="M5 12h14M12 5l7 7-7 7"/>';

  /// Les entrées du menu de compte (`$entreesDeCompte`, `$entreesDAide`).
  static const String monProfil =
      r'<path stroke-linecap="round" stroke-linejoin="round" d="M20 21v-2a4 4 0 00-4-4H8a4 4 0 00-4 4v2"/><circle cx="12" cy="7" r="4"/>';
  static const String parametresCompte = r'<circle cx="12" cy="12" r="3"/>';
  static const String importExport =
      r'<path stroke-linecap="round" stroke-linejoin="round" d="M21 15v4a2 2 0 01-2 2H5a2 2 0 01-2-2v-4M7 10l5 5 5-5M12 15V3"/>';
  static const String journalAudit =
      r'<path stroke-linecap="round" stroke-linejoin="round" d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8z"/><path stroke-linecap="round" stroke-linejoin="round" d="M14 2v6h6"/>';
  static const String aideAPropos =
      r'<circle cx="12" cy="12" r="10"/><path stroke-linecap="round" stroke-linejoin="round" d="M9.09 9a3 3 0 015.83 1c0 2-3 3-3 3M12 17h.01"/>';
  static const String contactEditeur =
      r'<path stroke-linecap="round" stroke-linejoin="round" d="M4 4h16a2 2 0 012 2v12a2 2 0 01-2 2H4a2 2 0 01-2-2V6a2 2 0 012-2z"/><path stroke-linecap="round" stroke-linejoin="round" d="M22 6l-10 7L2 6"/>';
}

/// `Str::ucfirst($utilisateur->role->libelle)` — la vue affiche le rôle avec SA
/// première lettre en capitale, et rien d'autre (« Super_admin »,
/// « Receptionniste » : le code du rôle, sans accent ajouté).
///
/// ⚠ Le défaut corrigé le 12/10/2026 : la barre affichait `session.role` brut,
/// donc « administrateur » en minuscule sur un vrai poste — le rôle stocké par
/// `SessionRepositoryLocal` est le code. Les tests ne le voyaient pas : leur
/// banc (`coquille_montee.dart`) capitalisait le rôle AVANT de le donner à la
/// session, et faisait donc le travail à la place de l'écran.
String roleAffiche(String role) =>
    role.isEmpty ? role : role[0].toUpperCase() + role.substring(1);

/// `strtoupper(substr($login, 0, 2))` (`MenuLateral::initiales`).
///
/// Deux propriétés de PHP sont rejouées, parce qu'elles se voient : `substr`
/// coupe en OCTETS (un login qui commence par « é » rend ce seul caractère,
/// deux octets en UTF-8), et `strtoupper` ne touche que l'ASCII depuis PHP 8.2
/// (« é » reste minuscule). Un octet orphelin laissé par la coupe rend U+FFFD,
/// comme le navigateur qui le reçoit. (Le repli « OP » de la vue vaut pour un
/// compte ABSENT ; ce client n'affiche aucune identité sans session.)
String initialesDeLogin(String login) {
  final octets = utf8.encode(login);
  final deux = octets.length <= 2 ? octets : octets.sublist(0, 2);
  final texte = utf8.decode(deux, allowMalformed: true);
  final sortie = StringBuffer();
  for (final r in texte.runes) {
    sortie.writeCharCode(r >= 0x61 && r <= 0x7A ? r - 0x20 : r);
  }
  return sortie.toString();
}
