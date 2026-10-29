import 'package:flutter/painting.dart';

/// Les mesures et les pictogrammes de l'ÉCRAN DE CONNEXION —
/// la vue Blade de connexion (refonte du 29/10/2026, demande du PO,
/// `docs/HANDOFF_ECRAN_CONNEXION_LOGIRESTOCK.md`). L'écran est HORS `<main>` :
/// ses tailles de police sont celles de `Tailles`, jamais `TaillesContenu`.
///
/// Les couleurs ne sont pas ici : l'écran emploie `AppColors` (navy en couleur
/// primaire, gold en accent, ardoise, erreur) — aucun hexadécimal nouveau.
abstract final class MesuresConnexion {
  /// `max-w-[560px]` — la carte.
  static const double largeurCarte = 560;

  /// `max-w-[520px]` — le contenu de la connexion, posé sur le blanc du
  /// panneau droit (plus de carte : correction du PO du 29/10/2026).
  static const double largeurContenu = 520;

  /// `p-4` / `md:p-6` — la marge autour de la carte (16, puis 24 dès `md`).
  static const double margeEtroit = 16;
  static const double margeLarge = 24;

  /// `p-6` / `md:p-8` — la marge intérieure de la carte (24, puis 32).
  static const double interieurEtroit = 24;
  static const double interieurLarge = 32;

  /// `rounded-2xl` — le rayon de la carte (16).
  static const double rayonCarte = 16;

  /// `shadow-sm` de Tailwind : `0 1px 2px 0 rgb(0 0 0 / 0.05)`.
  static const List<BoxShadow> ombreCarte = [
    BoxShadow(color: Color(0x0D000000), blurRadius: 2, offset: Offset(0, 1)),
  ];

  /// `.btn:hover { filter: brightness(0.92) }` — le voile de survol du bouton
  /// plein, en noir à 8 %.
  static const Color voileSurvolBouton = Color(0x14000000);

  /// `right-1.5` — le retrait de l'œil à droite du champ (6).
  static const double retraitOeil = 6;

  /// `px-3.5` — le remplissage horizontal du champ (14), qui laisse la place du
  /// pictogramme et de l'œil.
  static const double remplissageChamp = 14;

  /// `h-[52px]` — champs ET bouton (cible tactile ≥ 48 px).
  static const double hauteurChamp = 52;

  /// `rounded-xl` — le rayon des champs et du bouton (12).
  static const double rayonChamp = 12;

  /// `pl-11` — la place de l'icône à gauche du champ (44).
  static const double retraitIcone = 44;

  /// `left-3.5` — la marge de l'icône à gauche du champ (14).
  static const double margeIcone = 14;

  /// `width="20"` — les icônes des champs, de l'œil et du cadenas du bouton.
  static const double iconeChamp = 20;

  /// `h-16` — le logo téléversé de l'établissement, en tête de la carte (64).
  static const double hauteurLogo = 64;

  /// `w-[68px]` — le pictogramme de la marque.
  static const double iconeMarque = 68;

  /// `width="26"` — les pictogrammes du bandeau de sept modules.
  static const double iconeModule = 26;

  /// `w-10 h-10` — la cible de l'œil afficher/masquer (40).
  static const double cibleOeil = 40;

  /// `w-4 h-4` — la case « Se souvenir de moi » (16).
  static const double caseACocher = 16;

  /// Resserrés le 29/10/2026 (PO : aucun ascenseur à 768 px) : `mt-3` / `mb-4` /
  /// `py-2` / `py-2.5` ; avant `mt-5` / `mb-6` / `py-3` / `py-4`. Autrefois `mt-5` / `mb-6` / `mt-8` / `mt-1` / `mb-1.5` / `gap-3` / `gap-2` en px.
  static const double filetHaut = 12;
  static const double filetBas = 16;
  static const double piedHaut = 32;

  /// `mt-4` — le pied de page de la CONNEXION (resserré le 29/10/2026 pour que
  /// la page tienne à 768 px de haut sans ascenseur).
  static const double piedHautConnexion = 16;
  static const double ecartMarque = 12;
  static const double ecartLabel = 6;
  static const double ecartPetit = 4;
  static const double ecartCase = 8;

  /// `py-3` (slogan) / `py-4` (bandeau) — marges verticales (12 / 16).
  static const double margeSlogan = 8;
  static const double margeBandeau = 10;

  // -------------------------------------------------------------------------
  // Les tracés : COPIE OCTET POUR OCTET de
  // le partial de pictogrammes de la vue de connexion (fil de 2,
  // coins arrondis, viewBox 24 × 24). `ecran_connexion_test.dart` les relit
  // dans la vue : modifier l'un sans l'autre fait rougir.
  // -------------------------------------------------------------------------
  static const String _arrondi =
      'stroke-linecap="round" stroke-linejoin="round"';

  /// Le pictogramme « F — maison et cloche » (viewBox 64, fil de 3,2) : la
  /// maison en navy, la cloche et son plateau en or. Deux tracés, deux
  /// couleurs, deux `IconeTrace` superposés. La cloche de la vue est un groupe
  /// `translate(16 28) scale(.9)` : ses coordonnées sont ici CALCULÉES (le
  /// lecteur de tracés ne lit ni groupe ni transformation).
  static const String traceMarqueMaison =
      '<path d="M6 30L32 8l26 22" $_arrondi/>'
      '<path d="M12 26v30h40V26" $_arrondi/>';

  static const String traceMarqueCloche =
      '<path d="M17.8 47.8a12.6 12.6 0 0 1 25.2 0z" $_arrondi/>'
      '<path d="M30.4 35.2V32.5" $_arrondi/>'
      '<path d="M16 51.4h28.8" $_arrondi/>'
      '<path d="M18 52h28" $_arrondi/>';

  /// `viewBox="0 0 64 64"` et `stroke-width="3.2"` du pictogramme de marque.
  static const double coteMarque = 64;
  static const double epaisseurMarque = 3.2;

  static const String traceRestauration =
      '<path d="M6 3v6a3 3 0 0 0 6 0V3" $_arrondi/>'
      '<path d="M9 3v18" $_arrondi/>'
      '<path d="M18 21V3c-2.5 1.5-3.5 4.5-3.5 8v2h3.5" $_arrondi/>';

  static const String traceHebergement =
      '<path d="M3 20V7" $_arrondi/>'
      '<path d="M3 15h18v5" $_arrondi/>'
      '<path d="M21 15v-2a3 3 0 0 0-3-3h-7v5" $_arrondi/>'
      '<circle cx="7" cy="12" r="1.5" $_arrondi/>';

  static const String traceEcoTourisme =
      '<path d="m8 3 4 8 5-5 5 15H2z" $_arrondi/>'
      '<path d="M4.1 15.7 8 10" $_arrondi/>';

  static const String traceStock =
      '<rect x="2" y="3" width="20" height="5" rx="1" $_arrondi/>'
      '<path d="M4 8v11a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8" $_arrondi/>'
      '<path d="M10 12h4" $_arrondi/>';

  static const String traceLocation =
      '<path d="M19 17h2a1 1 0 0 0 1-1v-3a2 2 0 0 0-1.5-1.9C18.7 10.6 16 10 16 10s-1.3-1.4-2.2-2.3A3 3 0 0 0 12 7H5a1.2 1.2 0 0 0-1.1.9l-1.4 2.9A3.7 3.7 0 0 0 2 12v4a1 1 0 0 0 1 1h2" $_arrondi/>'
      '<circle cx="7" cy="17" r="2" $_arrondi/>'
      '<path d="M9 17h6" $_arrondi/>'
      '<circle cx="17" cy="17" r="2" $_arrondi/>';

  static const String traceCaisse =
      '<rect x="4" y="2" width="16" height="20" rx="2" $_arrondi/>'
      '<path d="M8 6h8" $_arrondi/>'
      '<path d="M8 10h.01M12 10h.01M16 10h.01M8 14h.01M12 14h.01M8 18h.01M12 18h.01" $_arrondi/>'
      '<path d="M16 14v4" $_arrondi/>';

  static const String traceComptabilite =
      '<path d="M3 3v16a2 2 0 0 0 2 2h16" $_arrondi/>'
      '<path d="M18 17V9" $_arrondi/>'
      '<path d="M13 17V5" $_arrondi/>'
      '<path d="M8 17v-3" $_arrondi/>';

  static const String traceUtilisateur =
      '<path d="M19 21v-2a4 4 0 0 0-4-4H9a4 4 0 0 0-4 4v2" $_arrondi/>'
      '<circle cx="12" cy="7" r="4" $_arrondi/>';

  static const String traceCadenas =
      '<rect x="3" y="11" width="18" height="11" rx="2" $_arrondi/>'
      '<path d="M7 11V7a5 5 0 0 1 10 0v4" $_arrondi/>';

  static const String traceCadenasOuvert =
      '<rect x="3" y="11" width="18" height="11" rx="2" $_arrondi/>'
      '<path d="M7 11V7a5 5 0 0 1 9.9-1" $_arrondi/>';

  static const String traceOeil =
      '<path d="M2 12s3.6-7 10-7 10 7 10 7-3.6 7-10 7-10-7-10-7z" $_arrondi/>'
      '<circle cx="12" cy="12" r="3" $_arrondi/>';

  static const String traceOeilBarre =
      '<path d="M10.7 5.1A10 10 0 0 1 12 5c6.4 0 10 7 10 7a17 17 0 0 1-2.2 3.2" $_arrondi/>'
      '<path d="M6.6 6.6A16.5 16.5 0 0 0 2 12s3.6 7 10 7a9.7 9.7 0 0 0 5.4-1.6" $_arrondi/>'
      '<path d="M14.1 14.1a3 3 0 1 1-4.2-4.2" $_arrondi/>'
      '<path d="m2 2 20 20" $_arrondi/>';
}
