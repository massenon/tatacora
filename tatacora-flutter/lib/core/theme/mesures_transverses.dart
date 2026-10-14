/// Les jetons des ÉCRANS TRANSVERSES et de la Comptabilité — lot D du plan du
/// Product Owner (14/10/2026) : Comptabilité, Import & Export, Rôles &
/// Permissions, Mon profil, Journal d'Audit, Aide & À propos, Contactez
/// l'éditeur.
///
/// Chaque valeur est relue sur la classe de la vue qui la porte (chemins écrits
/// sans leur préfixe : ce fichier ne porte aucune vue, PA-187). Une valeur
/// entre crochets le dit ; une valeur de l'échelle nommée de Tailwind dit son
/// rang.
library;

import 'package:flutter/painting.dart';

/// Largeurs et tailles.
abstract final class MesuresTransverses {
  /// `max-w-[1200px]` — Aide & À propos, Contactez l'éditeur, Import &
  /// Export. Valeur ENTRE CROCHETS.
  static const double pageEtroite = 1200;

  /// `max-w-[1100px]` — Mon profil. Valeur ENTRE CROCHETS.
  static const double pageProfil = 1100;

  /// `max-w-[1440px]` — Journal d'Audit, Rôles & Permissions. Un jeton
  /// distinct de `AppLayout.maxContentWidth` : deux écrans qui portent
  /// aujourd'hui la même largeur ne sont pas le même réglage.
  static const double pageLarge = 1440;

  /// `max-w-[1600px]` — le hub Comptabilité. Valeur ENTRE CROCHETS.
  static const double pageComptabilite = 1600;

  /// `max-w-[640px]` — le texte de l'état « aucun exercice ».
  static const double texteAucunExercice = 640;

  /// `max-w-[720px]` — la phrase du rythme des sauvegardes.
  static const double texteRythmeSauvegardes = 720;

  /// `sm:w-72` — le champ de recherche de la foire aux questions (288 px).
  static const double rechercheFaq = 288;

  /// `w-12 h-12` — le logo de la présentation (Aide) et le cercle du bandeau
  /// de contact.
  static const double logoAide = 48;

  /// `w-9 h-9` — la pastille d'icône d'une carte de module (Aide).
  static const double pastilleModule = 36;

  /// `<svg width="18">` — l'icône d'une carte de module, d'une tuile M10.
  static const double iconeModule = 18;

  /// `<svg width="20">` — l'icône d'une ressource (Aide) et d'un bandeau.
  static const double iconeRessource = 20;

  /// `<svg width="15">` — l'icône d'un bouton (contact, onglets de contact).
  static const double iconeBouton = 15;

  /// `<svg width="16">` — loupe, chevron de question, coordonnées.
  static const double iconePetite = 16;

  /// `stroke-width="2.2"` — le trait appuyé des icônes d'encart (ampoule,
  /// coche, croix, avertissement).
  static const double traitAppuye = 2.2;

  /// `w-14 h-14` — l'avatar de Mon profil.
  static const double avatarProfil = 56;

  /// `w-11 h-11` — l'avatar de l'éditeur.
  static const double avatarEditeur = 44;

  /// `w-10 h-10` — l'avatar d'une carte de rôle et la pastille d'une tuile M10.
  static const double avatarRole = 40;

  /// `w-6 h-6` — une cellule de la matrice des droits.
  static const double celluleMatrice = 24;

  /// `w-3 h-3` — un carré de légende de la matrice.
  static const double legendeMatrice = 12;

  /// `w-5 h-5` — la pastille numérotée d'une étape de la démarche d'import.
  static const double pastilleEtape = 20;

  /// `.zone-depot { border: 2px dashed }` (`app.css`) — la zone de dépôt du
  /// fichier d'import ; tirets et espaces à 3 × l'épaisseur (Chromium), comme
  /// la carte du comptoir (D407).
  static const double bordureZoneDepot = 2;
  static const double tiretZoneDepot = 3 * bordureZoneDepot;
  static const double espaceZoneDepot = 3 * bordureZoneDepot;

  /// `<svg width="30">` — la flèche de la zone de dépôt.
  static const double iconeDepot = 30;

  /// `w-12 h-12` — le cadenas de l'état verrouillé de la réinitialisation.
  static const double cadenasReinitialisation = 48;

  /// Les colonnes d'une grille de cartes au-delà du point `lg`/`xl`.
  static const int colonnesModulesXl = 4;
  static const int colonnesModulesLg = 3;
  static const int colonnesModulesSm = 2;
  static const int colonnesRolesXl = 3;
  static const int colonnesRolesMd = 2;
  static const int colonnesKpiComptaLg = 6;
  static const int colonnesKpiCompta = 2;
  static const int colonnesKpiSauvegardes = 4;
  static const int colonnesRessources = 4;

  /// `lg:grid-cols-2` — les onze tuiles du hub Comptabilité.
  static const int colonnesTuilesCompta = 2;

  /// La colonne « Module » de la matrice des droits — la vue la laisse à sa
  /// largeur naturelle (`sticky left-0`) ; ici une largeur qui contient
  /// « Tab. de Bord » sans ellipse.
  static const double colonneModuleMatrice = 140;

  /// Une colonne de rôle de la matrice (`px-3`, en-tête `whitespace-nowrap`).
  static const double colonneRoleMatrice = 120;

  /// `<x-pwa.modale … largeur="440px">` — « Nouveau rôle » et « Rétablir le
  /// socle du CdCF ». Valeur en dur de la vue (ni `max-w-md` 448 ni
  /// `max-w-lg` 512).
  static const double modaleRole = 440;

  /// `largeur="480px"` — « Modifier les droits ».
  static const double modaleDroits = 480;

  /// Les modales de « Comptes utilisateurs » (Lot J2, ajout du poste sans
  /// vue) : la largeur de « Modifier les droits », la plus proche des
  /// formulaires compacts de la vue.
  static const double modaleCompte = modaleDroits;

  /// `max-h-[55vh]` — la liste des modules de « Modifier les droits ».
  static const double fractionListeDroits = 0.55;

  /// `<svg width="13">` — le cadenas de la case administrateur / Rôles.
  static const double iconeVerrou = 13;

  /// Une colonne de tableau sans largeur dans la vue (`<th>` nu) : la largeur
  /// minimale qui garde l'en-tête sur une ligne.
  static const double colonneTableauMin = 110;

  /// La colonne « Intitulé » / « Libellé » des tableaux comptables.
  static const double colonneLibelleCompta = 220;

  /// Lignes par page des tableaux de ce lot — la valeur du moteur de la vue
  /// (10 par page, comme `pied_pagination.dart`).
  static const int lignesParPage = 10;

  /// `max-h-80` — la liste des anomalies du rapport de contrôle d'un import
  /// (Import & Export, onglet « Importer les données »).
  static const double hauteurRapportImport = 320;

  /// `largeur="480px"` — la modale « Modifier le mot de passe » de Mon profil.
  static const double modaleMotDePasse = 480;
}

/// Les couleurs de ce lot qui n'avaient pas de jeton.
abstract final class PaletteTransverse {
  /// `#7C5E12` — le texte des encarts or (contact, import, profil).
  static const Color texteOr = Color(0xFF7C5E12);

  /// `#1B5E20` — le texte des encarts verts (sauvegarde générée, « conservé »).
  static const Color texteVert = Color(0xFF1B5E20);

  /// `#8C1D1D` — le texte du bandeau rouge et des pastilles « Ce qui sera
  /// vidé » de l'onglet Réinitialiser.
  static const Color texteRouge = Color(0xFF8C1D1D);

  /// `border-color:#F5B5B5` — la bordure du bandeau rouge de l'onglet
  /// Réinitialiser.
  static const Color bordureRouge = Color(0xFFF5B5B5);

  /// `#BFD3FD` — la bordure de l'encadré bleu « Restaurer ».
  static const Color bordureBleue = Color(0xFFBFD3FD);

  /// `bg-green-100` / `border-green-300` — légende « Accès complet ».
  static const Color vert100 = Color(0xFFDCFCE7);
  static const Color vert300 = Color(0xFF86EFAC);

  /// `bg-blue-50` / `text-blue-700` — badge et cellule « L ».
  static const Color bleu50 = Color(0xFFEFF6FF);
  static const Color bleu700 = Color(0xFF1D4ED8);

  /// `bg-green-50` / `text-green-700` — badge et cellule « C ».
  static const Color vert50 = Color(0xFFF0FDF4);
  static const Color vert700 = Color(0xFF15803D);

  /// `rgba(255,255,255,.07)` — les cartes de la présentation (Aide).
  static const double fondCarteNavy = 0.07;

  /// `text-white/70` — le texte de la présentation.
  static const double texteNavy = 0.70;

  /// `text-white/50` — les libellés des cartes de la présentation.
  static const double libelleNavy = 0.50;

  /// `bg-white/60` — une carte de module sans droit.
  static const double carteSansDroit = 0.60;

  /// `bg-[var(--navy)]/5` — la pastille d'une tuile du hub Comptabilité.
  static const double fondPastilleTuile = 0.05;

  /// `bg-slate-50/50` — une rangée impaire de la matrice.
  static const double rangeeImpaire = 0.50;
}
