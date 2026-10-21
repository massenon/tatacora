import 'package:flutter/material.dart';

/// Les dix-sept variables `:root` du maître, une par une.
///
/// **Relevées dans `prototype_v2/assets/css/app.css` l.14-33**, jamais
/// recopiées d'un document — `DIRECTIVE_CONFORMITE_100.md` Article 0 : le
/// prototype fait foi sur tout ce qui se voit, et Article 2 : « valeurs
/// hexadécimales exactes, relevées dans le HTML ».
///
/// Cette classe est la **seule** source des couleurs institutionnelles. Les
/// noms lisibles vivent dans [AppColors], qui s'y adosse au lieu de recopier
/// les entiers : deux listes décrivant la même chose divergeront, ce n'est
/// qu'une question de temps (Article 10).
///
/// `conformite_jetons_maitre_test.dart` relit le bloc `:root` et confronte
/// **chacune** de ces dix-sept valeurs. Il échoue si le fichier est
/// introuvable, et il porte un plancher : sans lui, un `:root` renommé rendrait
/// l'extraction vide, donc le test vert à vide.
abstract final class JetonsCssMaitre {
  static const Color navy = Color(0xFF14213D);
  static const Color gold = Color(0xFFB8891E);

  /// « Teinte de l'état actif du menu — plus lumineuse que `--gold`, pour que
  /// la page courante se distingue du fond navy sans relecture » (app.css
  /// l.17-18, le commentaire est du maître).
  ///
  /// **Elle manquait au dépôt Flutter.** L'entrée active de la barre latérale
  /// se peignait donc en `gold`, la teinte que le maître a explicitement écarté
  /// pour ce rôle.
  static const Color goldActif = Color(0xFFCA971E);

  static const Color fondClair = Color(0xFFF2F2F2);
  static const Color texte = Color(0xFF262626);

  static const Color succes = Color(0xFF2E7D32);
  static const Color alerte = Color(0xFFED6C02);
  static const Color erreur = Color(0xFFC62828);
  static const Color info = Color(0xFF1D4ED8);
  static const Color gris = Color(0xFF6B7280);

  // ------------------------------------------------------------------------
  // L'échelle `--neutre-*` du maître.
  //
  // ⚠ Ce n'est PAS l'échelle de gris que les pages emploient. Le comptage sur
  // les 50 pages du maître le dit sans ambiguïté :
  //
  //   var(--neutre-*)  ....    5 emplois  (barre de défilement, zone de dépôt,
  //                                        fond de modale et de toast)
  //   classes slate-*  .... 2757 emplois
  //
  // Ces sept valeurs sont donc conservées **pour ce qu'elles sont** — les
  // variables déclarées par le maître, que la garde confronte — et l'échelle de
  // travail est [Ardoise]. Les confondre est ce qui a produit la dérive
  // corrigée le 26/08/2026 (voir [AppColors]).
  // ------------------------------------------------------------------------
  static const Color neutre0 = Color(0xFFFFFFFF);
  static const Color neutre50 = Color(0xFFF9FAFB);
  static const Color neutre100 = Color(0xFFF2F2F2);
  static const Color neutre200 = Color(0xFFE5E7EB);
  static const Color neutre400 = Color(0xFF9CA3AF);
  static const Color neutre600 = Color(0xFF6B7280);
  static const Color neutre900 = Color(0xFF262626);
}

/// L'échelle de gris **réellement employée** par le maître : `slate` de Tailwind.
///
/// ## Ce que le comptage a trouvé, et qui ne se devinait pas
///
/// Relevé le 26/08/2026 sur les 50 pages de `prototype_v2/` (pages, `index.html`
/// et les scripts qui construisent du DOM) :
///
/// | Famille | Emplois |
/// |---|---|
/// | `slate-*` | **2 757** |
/// | `gray-*`, `neutral-*`, `zinc-*`, `stone-*` | **0** |
///
/// Le maître n'emploie **aucune** autre famille de gris. Or `AppColors` portait
/// jusqu'à cette date les valeurs de la famille `neutral` — `#F5F5F5`,
/// `#E5E5E5`, `#D4D4D4`, `#737373`, `#404040` — c'est-à-dire un gris **neutre**
/// là où le maître pose un gris **bleuté**. L'écart est faible sur une pastille
/// isolée et systématique sur 216 emplois : exactement le défaut que
/// l'Article 1 n° 09 nomme, « approximer une couleur à l'œil ».
///
/// Les rangs se correspondent un pour un entre les deux familles ; seule la
/// famille change. Aucun appelant n'a donc eu à se déplacer — ce qui rend la
/// correction mécanique et vérifiable, au lieu d'un ré-arbitrage rang par rang.
///
/// ## Les valeurs viennent de Tailwind lui-même
///
/// Elles sont relues dans `prototype_v2/assets/css/vendor/tailwind-play-cdn.js`,
/// le bundle **effectivement servi** par le maître, et non de mémoire ni d'une
/// documentation en ligne. La garde en fait autant.
abstract final class Ardoise {
  /// `slate-50` — 253 emplois. Fonds de section, en-têtes de tableau.
  static const Color c50 = Color(0xFFF8FAFC);

  /// `slate-100` — 294 emplois. Séparateurs clairs, fonds de pastille neutre.
  static const Color c100 = Color(0xFFF1F5F9);

  /// `slate-200` — **458 emplois**, la plus fréquente. Toute bordure du maître.
  static const Color c200 = Color(0xFFE2E8F0);

  /// `slate-300` — 342 emplois. Bordures de champ, traits appuyés.
  static const Color c300 = Color(0xFFCBD5E1);

  /// `slate-400` — 432 emplois. Texte de moindre importance, icônes inertes.
  static const Color c400 = Color(0xFF94A3B8);

  /// `slate-500` — 422 emplois. Texte secondaire.
  static const Color c500 = Color(0xFF64748B);

  /// `slate-600` — 203 emplois.
  static const Color c600 = Color(0xFF475569);

  /// `slate-700` — 308 emplois. Étiquettes de formulaire.
  static const Color c700 = Color(0xFF334155);

  /// `slate-800` — 45 emplois.
  static const Color c800 = Color(0xFF1E293B);

  /// `slate-900` — le maître ne l'emploie pas en classe, mais la garde le
  /// confronte comme les autres : le rang existe au bundle, et l'omettre
  /// laisserait un futur emploi se servir ailleurs.
  static const Color c900 = Color(0xFF0F172A);
}

/// Les rangs sémantiques de Tailwind employés par le maître.
///
/// Relevés par comptage, comme [Ardoise], et lus dans le bundle vendorisé.
/// Ils vivent ici et non dans un widget : `tableau_tatacora.dart` en portait
/// **seize** en dur, chacun juste, et c'est précisément le problème — le
/// dix-septième ne l'aurait pas forcément été, et rien ne l'aurait signalé.
/// C'est le même raisonnement que les dérivées d'opacité de [AppColors], et la
/// règle absolue de l'Article 2 : aucune valeur de style en dur dans un widget.
abstract final class PaletteMaitre {
  /// `red-50` — 37 emplois.
  static const Color rouge50 = Color(0xFFFEF2F2);

  /// `red-100` — le fond de la pastille de source du taux non établi, dans le
  /// tableau des taux de la paie (`rh/paie.blade.php` l.767 : `bg-red-100
  /// text-red-800`). Relevé le 09/10/2026.
  /// `border-green-200` / `text-green-700` / `hover:bg-green-50` du bouton
  /// « Payer » des réservations du jour (vue d'accueil, l.521).
  static const Color vert50 = Color(0xFFF0FDF4);
  static const Color vert200 = Color(0xFFBBF7D0);
  static const Color vert700 = Color(0xFF15803D);

  static const Color rouge100 = Color(0xFFFEE2E2);

  /// `red-200` — 9 emplois.
  static const Color rouge200 = Color(0xFFFECACA);

  /// `red-300` — le filet qui précède la ligne de refus du barème ITS
  /// (`rh/paie.blade.php` l.702 : `border-t-2 border-red-300`). Relevé le
  /// 09/10/2026.
  static const Color rouge300 = Color(0xFFFCA5A5);

  /// `red-500` — 100 emplois. L'astérisque des champs obligatoires.
  static const Color rouge500 = Color(0xFFEF4444);

  /// `red-600` — **103 emplois**. Montants négatifs, actions destructrices.
  static const Color rouge600 = Color(0xFFDC2626);

  /// `red-700` — 23 emplois.
  static const Color rouge700 = Color(0xFFB91C1C);

  /// `red-800` — le texte de cette même pastille (voir [rouge100]).
  static const Color rouge800 = Color(0xFF991B1B);

  /// `red-900` — le titre des alertes rouges du pilotage consolidé
  /// (`m11-pilotage.js`, `rendreAlertes` : `['#FEF2F2', '#DC2626',
  /// '#7F1D1D']`).
  static const Color rouge900 = Color(0xFF7F1D1D);

  /// `emerald-50` — 29 emplois.
  static const Color emeraude50 = Color(0xFFECFDF5);

  /// `emerald-200` — 6 emplois.
  static const Color emeraude200 = Color(0xFFA7F3D0);

  /// `emerald-300` — la bordure du bouton de consultation d'une ligne de
  /// l'effectif de la paie (`rh/paie.blade.php` l.362 : `border-emerald-300
  /// bg-emerald-50 text-emerald-700`). Relevé le 09/10/2026.
  static const Color emeraude300 = Color(0xFF6EE7B7);

  /// `emerald-400` — la pastille « caisse ouverte » de l'indicateur de caisse
  /// de la barre supérieure (`barre-superieure` l.179 : `bg-emerald-400`).
  /// Relevé le 12/10/2026 dans le bundle vendorisé (`#34d399`).
  static const Color emeraude400 = Color(0xFF34D399);

  /// `red-400` — la pastille et la bordure (à 60 %) de l'indicateur de caisse
  /// ouverte depuis plus de 24 h (`barre-superieure` l.177-179). Relevé le
  /// 12/10/2026 (`#f87171`).
  static const Color rouge400 = Color(0xFFF87171);

  /// `emerald-500` — la pastille « caisse ouverte » de la barre de session du
  /// point de vente (`pos/comptant.blade.php` l.79 : `bg-emerald-500`). Relevé
  /// le 12/10/2026.
  static const Color emeraude500 = Color(0xFF10B981);

  /// `emerald-600` — 40 emplois.
  static const Color emeraude600 = Color(0xFF059669);

  /// `emerald-700` — 36 emplois.
  static const Color emeraude700 = Color(0xFF047857);

  /// `amber-50` — 42 emplois.
  static const Color ambre50 = Color(0xFFFFFBEB);

  /// `amber-200` — 14 emplois.
  static const Color ambre200 = Color(0xFFFDE68A);

  /// `amber-300` — le liseré du pavé d'avertissement de doublon
  /// (`m3-clients-creances.js` l.673 : `border border-amber-300`).
  ///
  /// Relevé le 27/08/2026. Il manquait à cette palette parce que le comptage
  /// d'origine portait sur les `.html` du maître, et que ce pavé est construit
  /// en JavaScript. Le remplacer par `ambre200`, qui existait déjà, aurait été
  /// l'approximation « à l'œil » que l'Article 1 interdit au n° 09.
  static const Color ambre300 = Color(0xFFFCD34D);

  /// `amber-400` — le point orange d'un article vendable sans lien de stock
  /// (`pos/comptant.blade.php` l.268 et l.300), 14/10/2026.
  static const Color ambre400 = Color(0xFFFBBF24);

  /// `amber-600` — 31 emplois.
  static const Color ambre600 = Color(0xFFD97706);

  /// `amber-700` — 37 emplois.
  static const Color ambre700 = Color(0xFFB45309);

  /// `blue-50` — 7 emplois.
  static const Color bleu50 = Color(0xFFEFF6FF);

  /// `blue-100` — le fond des pastilles d'information.
  static const Color bleu100 = Color(0xFFDBEAFE);

  /// `blue-200` — la BORDURE d'une bulle de message du canal e-mail
  /// (`pwa/notifications/hub.blade.php` l.55 : `bg-blue-50 border-blue-200
  /// text-blue-900`).
  ///
  /// Relevé le 14/09/2026, au portage de M12. Il manquait à cette palette :
  /// le bleu de la bulle n'avait que son fond (`bleu50`) et son texte n'avait
  /// aucun rang. Reprendre [bleu100] pour la bordure ou [bleu700] pour le
  /// texte serait l'approximation « à l'œil » que l'Article 1 interdit au
  /// n° 09 — `blue-200` vaut #BFDBFE, `blue-100` #DBEAFE.
  static const Color bleu200 = Color(0xFFBFDBFE);

  /// `blue-300` — la bordure d'une table « ouverte » du point de vente
  /// comptant (`pos/comptant.blade.php` l.199), 14/10/2026.
  static const Color bleu300 = Color(0xFF93C5FD);

  /// `blue-600` — la colonne « Sortie » et la carte « Articles mouvementes » de
  /// la fiche de stock consolidée (`stocks/inventaires.blade.php` l.248, 300,
  /// 340 : `text-blue-600`), 21/10/2026. Tailwind : #2563EB.
  static const Color bleu600 = Color(0xFF2563EB);

  /// `blue-700` — 7 emplois. C'est aussi `--info` du maître, au bit près.
  static const Color bleu700 = Color(0xFF1D4ED8);

  /// `blue-900` — le TEXTE d'une bulle de message du canal e-mail
  /// (`pwa/notifications/hub.blade.php` l.55).
  static const Color bleu900 = Color(0xFF1E3A8A);

  /// `emerald-900` — le TEXTE d'une bulle de message du canal WhatsApp
  /// (`pwa/notifications/hub.blade.php` l.57 : `bg-emerald-50
  /// border-emerald-200 text-emerald-900`), la branche `default` du
  /// `$classeBulle` de la vue.
  static const Color emeraude900 = Color(0xFF064E3B);

  /* ------------------------------------------------------------------ */
  /* Les fonds de pastille du moteur CRUD                                 */
  /*                                                                      */
  /* Ces quatre nuances ne viennent d'AUCUNE echelle Tailwind : le maitre  */
  /* les ecrit en hexadecimal, a la main, dans les `couleurs` de chaque    */
  /* colonne de type `badge` (`m4-restauration.html` l.86-119) et dans le  */
  /* defaut de `crud-engine.js` l.216. Les rapprocher d'un rang Tailwind   */
  /* voisin — `emerald-50` vaut #ECFDF5, pas #E8F5E9 — serait exactement   */
  /* l'interdit 09 de l'Article 1 : approximer une couleur a l'oeil.       */
  /* ------------------------------------------------------------------ */

  /// `#E8F5E9` — fond d'une pastille verte du moteur CRUD.
  /// `m4-restauration.html` l.88 (« Local ») et l.112 (« Oui »).
  static const Color badgeVertFond = Color(0xFFE8F5E9);

  /// `#E8EEFD` — fond d'une pastille bleue. `m4-restauration.html` l.92
  /// (« Européen »).
  static const Color badgeBleuFond = Color(0xFFE8EEFD);

  /// `#FDECEC` — fond d'une pastille rouge. `m4-restauration.html` l.116
  /// (« Non »).
  static const Color badgeRougeFond = Color(0xFFFDECEC);

  /// `#78350F` — `amber-900`. Le texte d'un pave d'explication ambre
  /// (`carte-module.js` l.55) et du bandeau « Ecran remplace » de
  /// `m4-restaurant.html` l.20.
  static const Color ambre900 = Color(0xFF78350F);

  /// `#F3F4F6` — le fond de repli d'une pastille dont la valeur n'est
  /// **prevue par aucune couleur** de la configuration (`crud-engine.js`
  /// l.216, `{bg:'#F3F4F6', txt:'#6B7280'}`).
  ///
  /// C'est ce fond que porte une valeur inconnue — et c'est lui qui rend le
  /// tiret de l'Article 7 : « — » se distingue a l'oeil d'un « Oui » vert.
  static const Color badgeGrisFond = Color(0xFFF3F4F6);
}

/// Jetons de couleur — `DIRECTIVE_CONFORMITE_100.md` Article 2.
///
/// **Aucune couleur ne s'improvise.** Une nuance ajoutée localement échappe au
/// contrôle de contraste et finit par produire un badge illisible sur un écran
/// en plein soleil — le cas d'usage réel à Natitingou.
///
/// Rien n'est écrit ici en hexadécimal : tout s'adosse à [JetonsCssMaitre]
/// (les variables `:root` du maître), à [Ardoise] (son échelle de gris) ou à
/// [PaletteMaitre] (ses rangs sémantiques), sauf les dérivées d'opacité, qui se
/// **calculent** à partir du jeton et non d'un entier recopié.
abstract final class AppColors {
  // ---------------------------------------------------------- Institutionnel
  /// Topbar, sidebar, boutons primaires, titres.
  static const Color navy = JetonsCssMaitre.navy;

  /// Actions critiques, sélection active, montants, liens.
  static const Color gold = JetonsCssMaitre.gold;

  /// L'entrée courante de la barre latérale — et **elle seule**. Le maître la
  /// distingue de [gold] délibérément (app.css l.17-18) ; les confondre efface
  /// le repère de la page courante.
  static const Color goldActif = JetonsCssMaitre.goldActif;

  /// Arrière-plan général.
  static const Color fondClair = JetonsCssMaitre.fondClair;

  /// Texte principal — `--texte`.
  static const Color anthracite = JetonsCssMaitre.texte;

  // -------------------------------------------------------------- Sémantique
  /// Statut « Libre », confirmations.
  static const Color succes = JetonsCssMaitre.succes;

  /// Seuils, avertissements.
  static const Color alerte = JetonsCssMaitre.alerte;

  /// Statut « Occupée », erreurs.
  static const Color erreur = JetonsCssMaitre.erreur;

  /// Information neutre — `--info`.
  static const Color info = JetonsCssMaitre.info;

  /// `--gris` du maître. Distinct de [Ardoise.c500] : le maître déclare les
  /// deux et ne les emploie pas au même endroit.
  static const Color gris = JetonsCssMaitre.gris;

  // ------------------------------------------- Pastilles du moteur CRUD
  /// Fond et texte des pastilles de `m4-restauration.html`, dans les quatre
  /// combinaisons que sa configuration declare (l.86-119) plus le repli du
  /// moteur (`crud-engine.js` l.216).
  ///
  /// Le TEXTE de ces pastilles reprend des jetons deja nommes — `#2E7D32` est
  /// [succes], `#1D4ED8` est [info], `#B8891E` est [gold], `#C62828` est
  /// [erreur] : le maitre y emploie ses propres variables. Seuls les FONDS
  /// sont des valeurs propres, portees par [PaletteMaitre].
  static const Color badgeVertFond = PaletteMaitre.badgeVertFond;
  static const Color badgeBleuFond = PaletteMaitre.badgeBleuFond;
  static const Color badgeRougeFond = PaletteMaitre.badgeRougeFond;

  /// Le fond d'une pastille dont la valeur n'est prevue par aucune couleur —
  /// c'est celui que porte le « — » de l'Article 7.
  static const Color badgeGrisFond = PaletteMaitre.badgeGrisFond;

  /// Le texte du meme repli — `#6B7280`, soit [gris] au bit pres
  /// (`crud-engine.js` l.216).
  static const Color badgeGrisTexte = JetonsCssMaitre.gris;

  // ----------------------------------------------------------------- Dérivées
  /// Badge « Réservée » — **exclusivement**. Ne pas réemployer ailleurs :
  /// c'est ce qui rend le statut reconnaissable d'un coup d'œil sur le plan.
  static const Color reserveGoldTexte = gold;
  static const Color reserveGoldFond = Color(0xFFFDF3E0);

  /// `#F0DCB0` — la bordure du bandeau ambre de la dépense courante
  /// (`depenses.blade.php` l.122, `border:1px solid #F0DCB0`), à côté de
  /// [reserveGoldFond] (`#FDF3E0`) et de [gold] pour le texte.
  static const Color bordureReserveGold = Color(0xFFF0DCB0);

  /// `#F5C6C6` — la bordure du bandeau de refus de la dépense courante
  /// (`depenses.blade.php` l.108, `border:1px solid #F5C6C6`), à côté de
  /// [badgeRougeFond] (`#FDECEC`) et de [erreur] pour le texte.
  static const Color bordureRefusRouge = Color(0xFFF5C6C6);

  /// Badge « Nettoyage » / information neutre.
  static const Color infoBleuTexte = JetonsCssMaitre.info;
  static const Color infoBleuFond = PaletteMaitre.bleu100;

  /// Fonds et bordures dérivés des couleurs sémantiques, par transparence.
  ///
  /// Ajoutés le 18/08/2026, à la revue du Sprint 1 : les écrans M1 posaient
  /// cinq `Color(0x…)` en dur — toutes des variantes d'opacité de `erreur` et
  /// `succes`. Chacune était juste, et c'est précisément le problème : la
  /// suivante ne l'aurait pas forcément été, et rien ne l'aurait signalé.
  ///
  /// Elles restent `const` — plusieurs appelants les posent dans un
  /// constructeur `const` —, mais la garde `conformite_jetons_maitre_test.dart`
  /// vérifie que leur composante RVB est bien celle du jeton dont elles se
  /// disent dérivées. Une dérivée qui cesserait de suivre son jeton fait donc
  /// rougir la suite, au lieu de vivre sa vie en silence.
  /// `#8C1D1D` — le texte de l'encadré de rappel de la modale d'annulation d'une
  /// réservation (`style="background:#FDECEC;color:#8C1D1D"`) et la couleur de
  /// la colonne « Commission retenue » de l'onglet Annulations
  /// (`reservations.blade.php` l.316 et l.862). À côté de [badgeRougeFond].
  static const Color annulationTexteRouge = Color(0xFF8C1D1D);

  /// `#8A6412` — le texte du bandeau « moins de 24h avant la prestation » de la
  /// même modale (`style="background:#FDF3E0;color:#8A6412"`), à côté de
  /// [reserveGoldFond] (`#FDF3E0`).
  static const Color annulationTexteOr = Color(0xFF8A6412);

  static const Color erreurFond = Color(0x1AC62828);
  static const Color erreurFondLeger = Color(0x0DC62828);
  static const Color erreurBordure = Color(0x33C62828);
  static const Color succesFond = Color(0x1A2E7D32);

  /* ================================================================== */
  /* Les cinq services d'une reservation                                 */
  /* ================================================================== */
  //
  // Les couleurs du maitre, relevees une a une dans le registre `SERVICES`
  // (`prototype_v2/pages/reservations-services.js` l.40 et suivantes). Elles
  // vivent ici et non dans le widget : la doctrine de portage interdit toute
  // valeur en dur dans un widget, et ces cinq-la se retrouvent sur trois
  // ecrans — la case a cocher, le bandeau du bloc de lignes, et la pastille de
  // service sur la carte de reservation.
  //
  // Trois d'entre elles retombent sur des couleurs deja nommees plus haut, et
  // ce n'est PAS une coincidence a factoriser : le maitre les a choisies
  // service par service. Les aliaser sur `navy`/`gold`/`succes` ferait suivre
  // le Tourisme le jour ou la couleur de succes changerait.
  static const Color serviceHebergement = Color(0xFF14213D);
  static const Color serviceRestauration = Color(0xFFED6C02);
  static const Color serviceBar = Color(0xFFB8891E);
  static const Color serviceTourisme = Color(0xFF2E7D32);
  static const Color serviceVehicule = Color(0xFF1D4ED8);

  /// Le voile des modales et panneaux glissants — `bg-black/40` du maitre.
  /// `rgba(255,255,255,.15)` — la pastille de module sur une entree
  /// SELECTIONNEE du catalogue (`m14-etats-studio.html` l.25).
  static const double opaciteBadgeActif = 0.15;

  /// `disabled:opacity-40` — l'opacite d'un bouton desactive
  /// (`m14-etats-studio.html` l.66-68).
  ///
  /// Le maitre garde le bouton VISIBLE plutot que de le masquer : sa presence
  /// dit que la fonction existe et qu'il manque une condition, la masquer
  /// laisserait croire qu'elle n'existe pas.
  static const double opaciteDesactive = 0.4;

  /// `opacity-60` — une carte d'article NON ajoutable du point de vente
  /// clients hébergés (`heberges.blade.php` l.155). Visible, atténuée : la
  /// masquer laisserait croire que l'article n'est pas à la carte.
  static const double opaciteArticleInactif = 0.6;

  /// `bg-slate-50/50` — le fond de la colonne catalogue du point de vente
  /// clients hébergés (`heberges.blade.php` l.125) : la moitié de `slate-50`.
  static const double opaciteFondDemi = 0.5;

  static const Color voileModale = Color(0x66000000);

  /// Le voile de `.overlay-modale` — `rgba(0,0,0,.5)`, app.css l.71.
  ///
  /// ⚠ Distinct de [voileModale] : le maître pose **deux** voiles, l'un en CSS
  /// à 50 % pour ses modales, l'autre en classe `bg-black/40` pour ses panneaux
  /// glissants. Les harmoniser serait choisir à sa place (Article 1 n° 10).
  static const Color voileOverlayCss = Color(0x80000000);

  // ------------------------------------------------- Échelle neutre = `slate`
  //
  // ⚠ **Corrigé le 26/08/2026.** Ces rangs portaient les valeurs de la famille
  // `neutral` de Tailwind, que le maître n'emploie **pas une seule fois** ; il
  // n'emploie que `slate` (2 757 occurrences). Le rang est conservé, la famille
  // est corrigée — voir [Ardoise] pour le comptage.
  static const Color neutre0 = JetonsCssMaitre.neutre0;

  /// `text-white/90` — blanc à 90 % d'opacité (`0xE6` = 230/255), le texte des
  /// en-têtes de tableau sur fond navy (`depenses.blade.php` l.248). Distinct
  /// de [neutre0] : sur le navy, un blanc plein se lit plus dur que celui de la
  /// vue.
  static const Color blanc90 = Color(0xE6FFFFFF);
  static const Color neutre50 = Ardoise.c50;
  static const Color neutre100 = Ardoise.c100;
  static const Color neutre200 = Ardoise.c200;
  static const Color neutre300 = Ardoise.c300;
  static const Color neutre400 = Ardoise.c400;
  static const Color neutre500 = Ardoise.c500;
  static const Color neutre600 = Ardoise.c600;
  static const Color neutre700 = Ardoise.c700;
  static const Color neutre800 = Ardoise.c800;
  static const Color neutre900 = Ardoise.c900;

  /// Palette Material dérivée du navy institutionnel.
  ///
  /// Construite explicitement plutôt que par `ColorScheme.fromSeed` : un
  /// algorithme de dérivation produirait des teintes qui ne sont pas celles
  /// que le client a approuvées.
  static const ColorScheme schemeClair = ColorScheme(
    brightness: Brightness.light,
    primary: navy,
    onPrimary: neutre0,
    secondary: gold,
    onSecondary: neutre0,
    error: erreur,
    onError: neutre0,
    surface: neutre0,
    onSurface: anthracite,
  );
}

/// Les opacités de la COQUILLE — les suffixes `/NN` des classes de la vue
/// (`menu-lateral`, `entree-menu`, `barre-superieure`), relevés le 12/10/2026.
///
/// Elles s'appliquent à un jeton (`AppColors.neutre0`, `PaletteMaitre.rouge400`…)
/// par `withValues(alpha: …)` : la couleur reste nommée, seule la transparence
/// est un nombre, et il est écrit ici, une fois.
abstract final class OpacitesCoquille {
  /// `text-white/80` — le bouton de menu mobile, la bascule plein écran et le
  /// libellé « Caisse fermée ».
  static const double texteAttenue = 0.80;

  /// `text-white/90` — le libellé « Clôturer la caisse » (caisse ouverte).
  static const double texteCaisseOuverte = 0.90;

  /// `stroke-opacity=".7"` — le chevron du bouton de compte.
  static const double chevron = 0.70;

  /// `text-white/45` — les titres de groupe de la barre latérale.
  static const double titreGroupe = 0.45;

  /// `text-white/40` — la localisation sous la marque, le rôle du pied de la
  /// barre latérale.
  static const double texteSecondaire = 0.40;

  /// `text-white/25` — la mention du pied de la barre latérale.
  static const double mentionPied = 0.25;

  /// `border-white/10` — les filets du châssis (pied de barre, bouton de
  /// compte, bloc épinglé).
  static const double filet = 0.10;

  /// `border-white/15` — la bordure de l'indicateur de caisse.
  static const double bordureCaisse = 0.15;

  /// `text-white/60` — le libellé « Exercice » du sélecteur d'exercice
  /// (`pwa/transverse/selecteur-exercice`, 20/10/2026).
  static const double libelleExercice = 0.60;

  /// `border-red-400/60` — la bordure de l'indicateur d'une caisse ouverte
  /// depuis plus de 24 h.
  static const double bordureCaisseTardive = 0.60;

  /// `bg-red-500/10` — son fond.
  static const double fondCaisseTardive = 0.10;

  /// `bg-[var(--succes)]/15` et `border-[var(--succes)]/40` — la forme de la
  /// pastille « Réseau » de la vue, reprise par la pastille d'ENVIRONNEMENT de
  /// ce client (voir `coquille_application.dart`, `_Pastille`).
  static const double fondPastille = 0.15;
  static const double bordurePastille = 0.40;
}

/// Les opacités de la RECHERCHE GLOBALE et de la CLOCHE de la barre supérieure
/// (composants `transverse/recherche-globale` et `transverse/cloche-
/// notifications` de la vue, lot B du 14/10/2026).
abstract final class OpacitesBarreSuperieure {
  /// `bg-white/10` — le fond du champ de recherche.
  static const double fondRecherche = 0.10;

  /// `border-white/15` — sa bordure au repos.
  static const double bordureRecherche = 0.15;

  /// `focus-within:border-white/40` — sa bordure quand le champ a le focus,
  /// et `placeholder-white/40` — le texte d'invite.
  static const double bordureRechercheFocus = 0.40;
  static const double inviteRecherche = 0.40;

  /// `text-white/50` — la loupe.
  static const double loupe = 0.50;

  /// `text-white/70` — la cloche au repos (`hover:text-white` au survol).
  static const double cloche = 0.70;

  /// `bg-amber-50/40` — le fond d'une alerte non lue.
  static const double fondNonLue = 0.40;
}

/// Les opacités du panneau « Accès rapides » (partiel `acces-rapide`, relevé
/// le 13/10/2026, lot 3).
abstract final class OpacitesAccesRapide {
  /// `opacity-30` — le chevron d'une entrée.
  static const double chevron = 0.30;
}

/// Les opacités du bouton d'action standard (`shared_widgets/bouton_standard`).
abstract final class OpacitesBouton {
  /// `disabled:opacity-50` — un bouton sans geste disponible.
  static const double desactive = 0.50;

  /// Le voile de survol (`hover:bg-slate-50` des boutons blancs de la vue).
  static const double survol = 0.60;
}

/// Les opacités du planning du parc (vue des locations, onglet Planning).
abstract final class OpacitesPlanning {
  /// `text-white/70` — le numéro d'un jour ouvré dans l'en-tête navy.
  static const double jourOuvre = 0.70;
}

/// Les opacités de la « Vue d'exploitation » de l'accueil
/// (`livewire/accueil.blade.php`), relevées le 12/10/2026 (lot 2).
abstract final class OpacitesAccueil {
  /// `background:{{ couleur }}15` — le fond d'une pastille d'accès rapide
  /// (l.328) : la couleur de l'icône suivie de l'octet alpha HEXADÉCIMAL `15`,
  /// soit 0x15 / 0xFF = 21 / 255 ≈ 8,2 %. Ce n'est PAS 15 % : le suffixe est
  /// un canal alpha à deux chiffres hexadécimaux (`#RRGGBBAA`).
  static const double fondAccesRapide = 0x15 / 0xFF;

  /// `text-white/90` — les en-têtes des tableaux à fond navy (l.446, l.739).
  static const double enTeteTableau = 0.90;

  /// `text-white/60` — les libellés du récapitulatif de la journée (l.597).
  static const double libelleRecap = 0.60;

  /// `text-white/40` — la note sous « Encaissé aujourd'hui » (l.610).
  static const double noteRecap = 0.40;

  /// `border:1px solid #F5B5B5` — l'encadré « Non consulté » qui remplace la
  /// bande d'indicateurs quand sa lecture a échoué (partiel des cartes,
  /// l.46). Fond `#FDECEC` ([AppColors.badgeRougeFond]), texte `#7F1D1D`
  /// ([PaletteMaitre.rouge900]).
  static const Color bordureNonConsulte = Color(0xFFF5B5B5);
}
