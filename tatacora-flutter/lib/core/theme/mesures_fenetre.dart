/// Les mesures des TROIS BOUTONS DE FENÊTRE du poste Windows (réduire,
/// agrandir / restaurer, fermer) et de la zone de déplacement de la barre
/// supérieure — demande du PO du 09/11/2026.
///
/// La vue Blade n'a pas ces boutons (c'est une page de navigateur) : ces
/// mesures ne se relèvent donc pas sur elle. Elles reprennent le gabarit des
/// boutons de légende de Windows, que le PO a montrés en capture (« — ❐ ✕ »).
library;

abstract final class MesuresFenetre {
  /// La largeur d'un bouton de légende de Windows (46 px logiques) ; la
  /// hauteur est celle de la barre supérieure.
  static const double largeurBouton = 46;

  /// La largeur d'un bouton en barre COMPACTE (fenêtre étroite) : la hauteur
  /// minimale d'une cible, ni plus, ni moins.
  static const double largeurBoutonCompact = hauteurMinimale;

  /// Sous cette largeur de fenêtre, la barre supérieure d'un poste qui porte
  /// les boutons passe en mode COMPACT : boutons de 32 px et identité du compte
  /// (login, rôle) masquée — l'avatar, le chevron et l'infobulle restent. Mesuré
  /// le 09/11/2026 : la barre, avec les boutons, tenait à partir de 1160 px (portée à 1300 px le même jour, pour le pire cas : login long) ;
  /// en dessous elle débordait à droite et la croix aurait été coupée, sur le
  /// portable 1366 x 768 à 125 % (1093 px logiques) que vise le poste.
  static const double seuilBarreCompacte = 1300;

  /// Une cible tactile / souris ne descend jamais sous cette hauteur.
  static const double hauteurMinimale = 32;

  /// Le côté du tracé — plus petit que les 22 px des boutons de la vue : une
  /// légende de fenêtre est discrète.
  static const double icone = 16;

  /// Le trait des quatre tracés (réduire, agrandir, restaurer, fermer).
  static const double epaisseurTrace = 1.5;

  /// La taille minimale commandée au contrôle de fenêtre : sous elle, les
  /// écrans à plusieurs colonnes se chevauchent (le runner la tient déjà, à
  /// 1024 x 640 ; cette valeur n'est qu'un repère pour les tests).
  static const double largeurFenetreMinimale = 1024;

  /// L'épaisseur de la zone de saisie INVISIBLE du bord haut de la fenêtre
  /// (redimensionnement). Sans barre de titre native, le haut n'a plus de
  /// cadre : 4 px, assez pour être saisie, trop peu pour gêner la barre.
  static const double epaisseurBordRedimensionnement = 4;

  /// Le côté des zones de saisie des COINS haut-gauche et haut-droit. Le coin
  /// droit recouvre l'angle de la croix : seuls ces 6 x 6 px redimensionnent
  /// au lieu de fermer (la croix de Windows se comporte de même).
  static const double tailleCoinRedimensionnement = 6;

  // ── Barre supérieure : repli par priorité (09/11/2026) ───────────────────
  //
  // La barre ne déborde à aucune largeur de 320 à 2560 px. À mesure que la
  // fenêtre se rétrécit, les éléments se replient DANS CET ORDRE ; les trois
  // boutons de fenêtre, le menu de compte et le bouton de menu ne disparaissent
  // jamais. Chaque seuil est une largeur de fenêtre en px logiques, relevée
  // contre les cas les plus larges (caisse « Clôturer la caisse », sélecteur
  // d'exercice avec sa pastille).

  /// En dessous : la recherche globale devient une icône (le champ s'ouvre
  /// par-dessus la barre).
  // 10/11/2026 (PO, capture d'une fenêtre de 1900 px — soit 1536 px logiques à 125 % —
  // où ne restaient qu'une loupe et un point) : abaissé de 1560 à 1440, le plus bas qui garde
  // la barre sans débordement dans le pire cas (caisse « Clôturer », exercice autre, login long).
  static const double seuilRechercheIcone = 1440;

  /// En dessous : l'indicateur de caisse devient sa seule pastille.
  static const double seuilCaisseIcone = 1440;

  /// En dessous : le sélecteur d'exercice perd son libellé et son lien « Revenir ».
  static const double seuilExerciceReduit = 1800;

  /// En dessous : le sélecteur d'exercice disparaît (le runner interdit déjà
  /// une fenêtre de moins de 1024 px : ce repli n'est qu'une sûreté).
  static const double seuilExerciceMasque = 1000;

  /// En dessous : « Vente » devient son icône seule.
  static const double seuilVenteIcone = 1160;

  /// En dessous : le logo disparaît (la marque reste dans la barre latérale).
  static const double seuilLogoMasque = 1000;

  /// En dessous : le bouton de synchronisation passe dans l'ombre — masqué,
  /// la cloche et le menu de compte restent.
  static const double seuilSynchroMasquee = 360;

  /// La part de la largeur de fenêtre que le sélecteur d'exercice ne dépasse
  /// pas : au-delà, sa pastille et « Revenir » se coupent par une ellipse.
  static const double fractionMaxSelecteurExercice = 0.2;

  /// Mais jamais moins que sa liste déroulante (228 px, le plus long libellé).
  static const double largeurMinSelecteurExercice = 240;

  /// La largeur maximale du login et du rôle à côté de l'avatar : au-delà, une
  /// ellipse (le menu de compte porte le login entier).
  static const double largeurMaxIdentiteCompte = 160;

  /// La marge autour de l'icône de « Vente » (15 px) en mode icône seule, pour
  /// une cible de 32 px : (32 - 15) / 2.
  static const double margeVenteIcone = 8.5;
}
