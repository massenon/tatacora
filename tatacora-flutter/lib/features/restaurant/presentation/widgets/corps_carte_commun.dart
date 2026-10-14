/// Le CORPS PARTAGÉ des deux écrans de carte — bar et restaurant.
///
/// Le côté serveur n'a qu'un fichier pour les deux rayons,
/// `pwa/carte/corps.blade.php`, et il écrit sa raison en tête : « Deux écrans
/// jumeaux finiraient par diverger au premier ajustement ». Le client Flutter
/// avait fait exactement cela — la carte du bar (refaite le 08/10/2026) et la
/// carte du restaurant (refaite le 09/10/2026) portaient chacune leur copie de
/// l'en-tête, de l'accordéon, de la grille de six cartes, de la barre de
/// filtres. Elles vivent désormais ici, UNE fois, et chaque écran ne garde que
/// ce qui le distingue (titre, sous-titre, boutons, bandeau, données).
///
/// ⚠ Toute modification de ce fichier déplace DEUX vues à la fois : relancer la
/// mesure de géométrie de `bar/carte` ET de `restaurant/carte`.
///
/// Les numéros de ligne cités sont ceux de `corps.blade.php`.
library;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_breakpoints.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../shared_widgets/bouton_standard.dart';

/// `lg:` — 1 024 px de **fenêtre** (jamais celle du contenu : une barre
/// latérale déployée fausserait la décision).
bool grandEcranCarte(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= AppBreakpoints.lg;

/// Un style de texte du contenu de page (`<main>`) : taille remappée par
/// `app.css`, interligne 1,5 et aucun interlettrage, comme la vue.
TextStyle styleContenuCarte(
  double taille, {
  FontWeight? poids,
  Color? couleur,
  double? interlettrage,
}) => TextStyle(
  fontFamily: AppTextStyles.police,
  fontSize: taille,
  fontWeight: poids,
  color: couleur,
  height: 1.5,
  letterSpacing: interlettrage ?? 0,
);

/// La page : une seule colonne qui défile d'un bloc, `p-5 lg:p-8` et
/// `max-w-[1500px] mx-auto` (l.72-73).
///
/// ## La barre de défilement prend sa place (10/10/2026)
///
/// `<main class="flex-1 overflow-y-auto">` porte une barre de navigateur
/// CLASSIQUE (`app.css` l.79 : 8 px) : dès que la page déborde, elle retire ces
/// 8 px à la zone utile, alors qu'un `Scrollbar` Flutter se pose par-dessus son
/// contenu. Mesuré sur le relevé de `rh/paie` : 1 047 px utiles au navigateur
/// contre 1 055 ici, si bien que « BULLETINS MANQUANTS » (135,4 px de texte pour
/// 134,6 px disponibles) passait sur deux lignes dans la vue et sur une seule
/// ici — et toute la page était 12 px plus haut. La gouttière est réservée par
/// un surcroît de marge à DROITE (le contenu centré le reste : le milieu de
/// `[p, L - p - 8]` est celui de `[p, L - 8 - p]` de la vue), et seulement quand
/// la page déborde, comme le navigateur ([AppLayout.gouttiereDefilement]).
class PageCarte extends StatefulWidget {
  const PageCarte({super.key, required this.largeurMax, required this.enfants});

  /// `max-w-[1500px]` — un jeton par écran (`AppLayout.pageCarteBar`,
  /// `AppLayout.pageCarteRestaurant`).
  final double largeurMax;

  final List<Widget> enfants;

  @override
  State<PageCarte> createState() => _EtatPageCarte();
}

class _EtatPageCarte extends State<PageCarte> {
  /// Vrai quand la page dépasse sa hauteur : la barre existe alors, et prend
  /// sa place. Le retour à faux est sans risque d'oscillation : une page qui
  /// ne déborde pas AVEC la gouttière ne débordera pas sans elle (plus large,
  /// elle n'est jamais plus haute).
  bool _deborde = false;

  bool _onMetriques(ScrollMetricsNotification n) {
    // Les défilements INTERNES (un tableau qui défile en largeur, une liste)
    // remontent aussi : seul celui de la page — profondeur 0, vertical — dit
    // si la barre de la page existe.
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    final deborde = n.metrics.maxScrollExtent > 0;
    if (deborde != _deborde) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _deborde = deborde);
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    // `p-5 lg:p-8` : le point de rupture est celui de l'ÉCRAN.
    final marge = grandEcranCarte(context) ? AppSpacing.xl : AppSpacing.mdPlus;

    return NotificationListener<ScrollMetricsNotification>(
      onNotification: _onMetriques,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          marge,
          marge,
          marge + (_deborde ? AppLayout.gouttiereDefilement : 0),
          marge,
        ),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: widget.largeurMax),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: widget.enfants,
            ),
          ),
        ),
      ),
    );
  }
}

/* ====================================================================== */
/* En-tête — l.75-144                                                      */
/* ====================================================================== */

/// L'en-tête de la vue : icône, titre, sous-titre, puis les boutons.
///
/// `flex flex-wrap items-start justify-between gap-3` (l.76) : tant que la
/// ligne ne tient pas, le groupe de boutons passe SOUS le titre — c'est ce que
/// fait la vue à 1 383 px, où le sous-titre seul occupe 880 px.
class EnTeteCarte extends StatelessWidget {
  const EnTeteCarte({
    super.key,
    required this.icone,
    required this.titre,
    required this.sousTitre,
    required this.boutons,
    this.cleTitre,
  });

  final IconData icone;
  final String titre;

  /// Une clé posée sur le titre, pour qu'un test le trouve (la paie la porte :
  /// `paie-titre`). Absente : aucun écran existant ne change.
  final Key? cleTitre;

  /// Le sous-titre, EN FRAGMENTS : la vue l'écrit avec un `<strong>`, et le
  /// comparateur coupe la phrase à ses balises — chaque fragment est donc UN
  /// littéral.
  final List<InlineSpan> sousTitre;

  /// `flex flex-wrap gap-2` (l.85).
  final List<Widget> boutons;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // `mb-5` (l.76).
      padding: const EdgeInsets.only(bottom: AppSpacing.mdPlus),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.start,
        // `gap-3` — 12 px.
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // `<svg width="24" height="24">`.
                  Icon(
                    icone,
                    color: AppColors.navy,
                    size: AppLayout.iconeTitrePage,
                  ),
                  // `gap-2.5` — 10 px.
                  const SizedBox(width: AppSpacing.xsPlus),
                  // MESURÉ : 17 px à 1 383 px, pas 18,5 (`lg:text-xl` ne
                  // s'applique pas dans `<main>`).
                  Text(
                    titre,
                    key: cleTitre,
                    style: styleContenuCarte(
                      TaillesContenu.lg,
                      poids: FontWeight.bold,
                      couleur: AppColors.navy,
                    ),
                  ),
                ],
              ),
              // `mt-1.5` — 6 px.
              const SizedBox(height: AppSpacing.xxs),
              Text.rich(
                TextSpan(
                  style: styleContenuCarte(
                    TaillesContenu.t15,
                    couleur: Ardoise.c500,
                  ),
                  children: sousTitre,
                ),
              ),
            ],
          ),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: boutons,
          ),
        ],
      ),
    );
  }
}

/// Les trois habits des boutons de l'en-tête (l.86-141).
enum StyleBoutonEntete {
  /// `border border-slate-300 bg-white` — les deux liens, `px-3.5`.
  lien,

  /// `bg-[var(--navy)] text-white font-semibold` — `px-4`.
  plein,

  /// `border border-[var(--gold)] text-[var(--gold)] font-semibold` — `px-4`.
  or,
}

/// Un bouton de l'en-tête : `text-[13px] py-2 rounded-lg`.
///
/// Les boutons pleins portent une bordure de leur couleur : la vue étire tous
/// les boutons de la rangée à la hauteur du plus haut (les liens, bordés) et
/// centre leur texte, si bien que leur texte tombe au même niveau. En
/// Flutter, chaque bouton prend sa propre hauteur — sans cette bordure le
/// texte des boutons pleins serait 1 px plus haut.
class BoutonEnteteCarte extends StatelessWidget {
  const BoutonEnteteCarte({
    super.key,
    required this.libelle,
    required this.style,
    required this.onPressed,
  });

  final String libelle;
  final StyleBoutonEntete style;
  final VoidCallback onPressed;

  /// Le bouton standard (PO, 14/10/2026) : ses trois variantes sont
  /// exactement les trois styles d'en-tête (lien = secondaire, plein =
  /// primaire, or = or).
  @override
  Widget build(BuildContext context) => BoutonStandard(
    libelle: libelle,
    variante: switch (style) {
      StyleBoutonEntete.lien => VarianteBouton.secondaire,
      StyleBoutonEntete.plein => VarianteBouton.primaire,
      StyleBoutonEntete.or => VarianteBouton.or,
    },
    onPressed: onPressed,
  );
}

/* ====================================================================== */
/* Indicateurs — l.146-209                                                 */
/* ====================================================================== */

/// L'accordéon « Indicateurs de la carte » (l.163-209, directive PO du
/// 03/09/2026), DÉPLIÉ par défaut : un écran qui s'ouvre vide se lit comme un
/// écran cassé. ⚠ La PWA retient l'état dans `localStorage` ; ce poste le garde
/// le temps de l'écran seulement.
class AccordeonIndicateurs extends StatefulWidget {
  const AccordeonIndicateurs({
    super.key,
    required this.cleBouton,
    required this.contenu,
    this.titre = 'Indicateurs de la carte',
  });

  final Key cleBouton;

  /// Le titre de la bande. Par défaut celui des deux cartes ; la paie
  /// (`rh/paie.blade.php` l.152) porte le sien — même accordéon, même habit,
  /// un seul auteur (09/10/2026).
  final String titre;

  /// Ce que l'accordéon plie : la grille des six cartes.
  final Widget contenu;

  @override
  State<AccordeonIndicateurs> createState() => _AccordeonIndicateursState();
}

class _AccordeonIndicateursState extends State<AccordeonIndicateurs> {
  bool _ouvert = true;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // `mb-5` (l.163).
      padding: const EdgeInsets.only(bottom: AppSpacing.mdPlus),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            key: widget.cleBouton,
            onTap: () => setState(() => _ouvert = !_ouvert),
            borderRadius: BorderRadius.circular(AppRadius.roundedXl),
            child: Container(
              // `px-4 py-3 bg-white border border-slate-200 rounded-xl`.
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: AppColors.neutre0,
                borderRadius: BorderRadius.circular(AppRadius.roundedXl),
                border: Border.all(color: Ardoise.c200),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    widget.titre,
                    // `text-sm font-bold text-slate-700`.
                    style: styleContenuCarte(
                      TaillesContenu.sm,
                      poids: FontWeight.bold,
                      couleur: Ardoise.c700,
                    ),
                  ),
                  // `hidden sm:inline` : masqué sous 640 px.
                  if (MediaQuery.sizeOf(context).width >= AppBreakpoints.sm)
                    Text(
                      'Repliez la bande pour gagner de la hauteur de tableau.',
                      style: styleContenuCarte(
                        TaillesContenu.t11,
                        couleur: Ardoise.c400,
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (_ouvert) ...[
            // `mt-3` — 12 px.
            const SizedBox(height: AppSpacing.sm),
            widget.contenu,
          ],
        ],
      ),
    );
  }
}

/// `grid grid-cols-2 lg:grid-cols-6 gap-3` (l.170) : six colonnes égales à
/// partir de 1 024 px de fenêtre, deux en dessous. Les cartes d'une même
/// rangée s'étirent à la hauteur de la plus haute, comme une grille CSS.
class GrilleIndicateurs extends StatelessWidget {
  const GrilleIndicateurs({super.key, required this.cartes});

  final List<Widget> cartes;

  @override
  Widget build(BuildContext context) {
    final colonnes = grandEcranCarte(context) ? 6 : 2;

    return LayoutBuilder(
      builder: (context, contraintes) {
        const ecart = AppSpacing.sm;
        final largeur =
            (contraintes.maxWidth - ecart * (colonnes - 1)) / colonnes;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var debut = 0; debut < cartes.length; debut += colonnes) ...[
              if (debut > 0) const SizedBox(height: ecart),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var c = 0; c < colonnes; c++) ...[
                      if (c > 0) const SizedBox(width: ecart),
                      SizedBox(
                        width: largeur,
                        child: debut + c < cartes.length
                            ? cartes[debut + c]
                            : null,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Une carte d'indicateur : `bg-white rounded-xl border border-slate-200
/// p-3.5` (l.171), libellé en capitales, valeur, détail.
///
/// [raison] n'existe que pour une carte dont le chiffre N'EXISTE PAS : la carte
/// affiche « — » en [valeur] et dit pourquoi, jamais « 0 » (Article 7). La vue
/// n'en a pas besoin, ses six chiffres existent côté serveur.
///
/// ## La raison est une INFOBULLE, pas une ligne (09/10/2026)
///
/// Elle était un texte visible de six lignes sous le chiffre. Dès que la carte
/// du restaurant lit une base locale, ce texte est rendu en PRODUCTION (il ne
/// l'était que dans un état de mesure surchargé) : trois cartes de plus d'une
/// ligne faisaient grandir la rangée et décalaient tout ce qui suit — cinq
/// éléments de la vue sortaient de leur place (mesuré : 24 alignés → 19). Le
/// « — » reste visible et le survol dit pourquoi, comme les autres cartes sans
/// source de ce dépôt (D22, D110). Une raison cachée derrière un survol est
/// moins visible qu'un texte : c'est un coût assumé, daté, réversible en
/// retirant le `Tooltip`.
class CarteKpi extends StatelessWidget {
  const CarteKpi({
    required Key cle,
    required this.libelle,
    required this.valeur,
    this.detail,
    this.raison,
    this.accent,
  }) : super(key: cle);

  final String libelle;
  final String valeur;
  final String? detail;
  final String? raison;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final carte = _carte();
    return raison == null ? carte : Tooltip(message: raison!, child: carte);
  }

  Widget _carte() {
    return Container(
      // `p-3.5` — 14 px.
      padding: const EdgeInsets.all(AppSpacing.smPlus),
      decoration: BoxDecoration(
        color: AppColors.neutre0,
        borderRadius: BorderRadius.circular(AppRadius.roundedXl),
        border: Border.all(color: Ardoise.c200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            // `uppercase` est une règle CSS : on applique la même.
            libelle.toUpperCase(),
            // `text-[11px] uppercase tracking-wide text-slate-400
            // font-semibold`.
            style: styleContenuCarte(
              TaillesContenu.t11,
              poids: FontWeight.w600,
              couleur: Ardoise.c400,
              interlettrage: TaillesContenu.t11 * AppTextStyles.suiviLarge,
            ),
          ),
          // `mt-1` — 4 px.
          const SizedBox(height: AppSpacing.unit),
          Text(
            valeur,
            // `text-[17px] font-bold`.
            style: styleContenuCarte(
              TaillesContenu.t17,
              poids: FontWeight.bold,
              couleur: accent ?? AppColors.navy,
            ),
          ),
          // `mt-0.5` — 2 px.
          const SizedBox(height: AppSpacing.demi),
          if (detail != null)
            Text(
              detail!,
              style: styleContenuCarte(
                TaillesContenu.t11,
                couleur: Ardoise.c400,
              ),
            ),
        ],
      ),
    );
  }
}

/* ====================================================================== */
/* Filtres — l.229-256                                                     */
/* ====================================================================== */

/// Un `<select>` de la barre de filtres :
/// `text-[13px] border border-slate-300 rounded-lg px-3 py-2`.
class ListeFiltre<T> extends StatelessWidget {
  const ListeFiltre({
    super.key,
    required this.cleListe,
    required this.largeur,
    required this.valeur,
    required this.options,
    required this.onChange,
    this.selectionnable,
  });

  /// Posée sur le `DropdownButton` lui-même, pour qu'un test le trouve.
  final Key cleListe;
  final double largeur;
  final T valeur;
  final List<(T, String)> options;
  final ValueChanged<T?> onChange;

  /// Les options qui NE se choisissent PAS : elles restent visibles, grisées.
  /// La vue n'en a aucune ; le restaurant en garde une que le serveur refuse
  /// (« Retirés du jour »), parce que la retirer supprimerait un élément de la
  /// vue — et que la laisser active ferait échouer l'écran en 422.
  final bool Function(T)? selectionnable;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: largeur,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.neutre0,
          borderRadius: BorderRadius.circular(AppRadius.roundedLg),
          border: Border.all(color: Ardoise.c300),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          child: SizedBox(
            // Une ligne de texte, ni plus ni moins : un `DropdownButton`
            // dense réserve 24 px, soit 5 px de trop par rapport au
            // `<select>` de la vue (18,75 px + `py-2` + bordure).
            height: TaillesContenu.t13 * 1.5,
            child: DropdownButtonHideUnderline(
              child: DropdownButton<T>(
                key: cleListe,
                // Sans cela la liste impose 48 px de haut
                // (`kMinInteractiveDimension`) à un texte de 13 px.
                itemHeight: null,
                isDense: true,
                isExpanded: true,
                iconSize: AppLayout.iconeChamp,
                style: styleContenuCarte(
                  TaillesContenu.t13,
                  couleur: Ardoise.c700,
                ),
                value: valeur,
                items: [
                  for (final (v, libelle) in options)
                    DropdownMenuItem<T>(
                      value: v,
                      enabled: selectionnable?.call(v) ?? true,
                      child: Text(
                        libelle,
                        style: (selectionnable?.call(v) ?? true)
                            ? null
                            : styleContenuCarte(
                                TaillesContenu.t13,
                                couleur: Ardoise.c400,
                              ),
                      ),
                    ),
                ],
                onChanged: onChange,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Le champ de recherche de la vue — `relative flex-1 min-w-[200px]` et son
/// `<input type="search">` `w-full text-[13px] border border-slate-300
/// rounded-lg pl-9 pr-3 py-2 focus:border-[var(--gold)]` (l.232-237 et
/// l.569-574). UN seul auteur pour la barre de filtres de la carte et celle du
/// panneau « Ventes » : le panneau reprend exactement ce champ (09/10/2026).
InputDecoration decorationRechercheCarte(String indice) {
  final bordure = OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadius.roundedLg),
    borderSide: const BorderSide(color: Ardoise.c300),
  );

  return InputDecoration(
    hintText: indice,
    hintStyle: styleContenuCarte(TaillesContenu.t13, couleur: Ardoise.c400),
    isDense: true,
    // `pl-9 pr-3 py-2` : la loupe est à `left-3`, `pl-9` lui réserve la
    // place. Sans contrainte, l'icône impose 48 px de haut au champ.
    prefixIcon: const Padding(
      padding: EdgeInsets.only(left: AppSpacing.sm),
      child: Icon(
        Icons.search,
        size: AppLayout.iconeChamp,
        color: Ardoise.c400,
      ),
    ),
    prefixIconConstraints: const BoxConstraints(
      minWidth: AppLayout.prefixeRechercheEtats,
      minHeight: 0,
    ),
    contentPadding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.sm,
      vertical: AppSpacing.xs,
    ),
    border: bordure,
    enabledBorder: bordure,
    focusedBorder: bordure.copyWith(
      borderSide: const BorderSide(color: AppColors.gold),
    ),
  );
}

/// Recherche, puis deux listes — l.229-256.
///
/// `bg-white rounded-xl border border-slate-200 p-3.5 mb-4`, puis une rangée
/// `flex flex-wrap gap-2.5 items-center` dont la recherche est `flex-1
/// min-w-[200px]` : elle prend ce que les deux listes laissent.
class BarreFiltresCarte extends StatefulWidget {
  const BarreFiltresCarte({
    super.key,
    required this.cleRecherche,
    required this.onRecherche,
    required this.categorie,
    required this.etat,
  });

  final Key cleRecherche;
  final ValueChanged<String> onRecherche;

  /// Les deux listes, dans l'ordre de la vue (catégorie, puis état).
  final ListeFiltre<Object?> categorie;
  final ListeFiltre<Object?> etat;

  @override
  State<BarreFiltresCarte> createState() => _BarreFiltresCarteState();
}

class _BarreFiltresCarteState extends State<BarreFiltresCarte> {
  final _terme = TextEditingController();

  @override
  void dispose() {
    _terme.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final recherche = TextField(
      key: widget.cleRecherche,
      controller: _terme,
      style: styleContenuCarte(TaillesContenu.t13),
      decoration: decorationRechercheCarte('Rechercher un article…'),
      onChanged: widget.onRecherche,
    );

    return Container(
      // `p-3.5 mb-4`.
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.smPlus),
      decoration: BoxDecoration(
        color: AppColors.neutre0,
        borderRadius: BorderRadius.circular(AppRadius.roundedXl),
        border: Border.all(color: Ardoise.c200),
      ),
      child: LayoutBuilder(
        builder: (context, contraintes) {
          // `gap-2.5` — 10 px.
          const ecart = AppSpacing.xsPlus;
          final minimum =
              AppLayout.rechercheMinCarteRestaurant +
              widget.categorie.largeur +
              widget.etat.largeur +
              ecart * 2;

          if (contraintes.maxWidth >= minimum) {
            return Row(
              children: [
                Expanded(child: recherche),
                const SizedBox(width: ecart),
                widget.categorie,
                const SizedBox(width: ecart),
                widget.etat,
              ],
            );
          }

          // Trop étroit : `flex-wrap` — la recherche prend sa ligne.
          return Wrap(
            spacing: ecart,
            runSpacing: ecart,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(width: contraintes.maxWidth, child: recherche),
              widget.categorie,
              widget.etat,
            ],
          );
        },
      ),
    );
  }
}

/* ====================================================================== */
/* Encadrés — l.258-289                                                    */
/* ====================================================================== */

/// Un encadré de la vue : `rounded-xl p-3.5 mb-4`, couleurs posées en `style`.
class EncadreCarte extends StatelessWidget {
  const EncadreCarte({
    super.key,
    required this.fond,
    required this.bordure,
    required this.enfant,
  });

  final Color fond;
  final Color bordure;
  final Widget enfant;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: AppSpacing.md),
    padding: const EdgeInsets.all(AppSpacing.smPlus),
    decoration: BoxDecoration(
      color: fond,
      borderRadius: BorderRadius.circular(AppRadius.roundedXl),
      border: Border.all(color: bordure),
    ),
    child: enfant,
  );
}

/// Un avertissement ambre de la vue (`#FFFBEB` / `#FDE68A` / `#78350F`),
/// `rounded-xl p-3.5 mb-4` (l.267-283).
class AvertissementCarte extends StatelessWidget {
  const AvertissementCarte({super.key, required this.cle, required this.texte});

  final Key cle;
  final String texte;

  @override
  Widget build(BuildContext context) => KeyedSubtree(
    key: cle,
    child: EncadreCarte(
      fond: PaletteMaitre.ambre50,
      bordure: PaletteMaitre.ambre200,
      enfant: Text(
        texte,
        style: styleContenuCarte(
          TaillesContenu.t13,
          couleur: PaletteMaitre.ambre900,
        ),
      ),
    ),
  );
}
