import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import 'coquille_restaurant.dart';

/// Le tableau des deux écrans de M4.
///
/// ## Pourquoi pas `TableauTatacora`
///
/// Le composant partagé est figé sur **un** gabarit : en-tête `bg-slate-50` et
/// cellules `px-4 py-2.5` (`m2-facturation.html` l.129-160). Les deux tableaux
/// de M4 n'ont ni l'un ni l'autre :
///
/// | | En-tête | Cellules |
/// |---|---|---|
/// | Carte (`carte-module.js` l.49-52) | `bg-slate-50` | `px-3 py-2.5` |
/// | Catalogue (`crud-ui.js` l.66-73) | **`bg-[var(--navy)]`**, texte blanc | `px-4 py-3` |
/// | `TableauTatacora` | `bg-slate-50` | `px-4 py-2.5` |
///
/// Les y ramener demanderait d'ajouter au composant partagé autant de
/// paramètres qu'il a de propriétés — ou d'approximer, ce que l'Article 1
/// interdit nommément (interdit 09, et 04 pour les largeurs de colonne). Ce
/// tableau-ci porte donc son gabarit en paramètre, et les deux écrans de M4
/// passent le leur.
class TableauRestaurant extends StatelessWidget {
  const TableauRestaurant({
    super.key,
    required this.colonnes,
    required this.lignes,
    required this.gabarit,
    this.clesLignes,
    this.ligneTotal,
    this.decorationTotal,
    this.vide,
    this.pleineLargeur = false,
    this.repartitionProportionnelle = false,
    this.videSousEntete = false,
    this.decorationsLignes,
    this.largeursFixes = const {},
  });

  /// Les colonnes à largeur FIXE, par rang : un `<th class="w-10">` du
  /// navigateur garde sa largeur et ne reçoit aucune part du surplus
  /// (`pwa/achats/achats.blade.php` l.201 : la colonne de la case à cocher,
  /// 48 px avec ses marges). Les autres colonnes se partagent le reste.
  /// Vide par défaut : aucun autre écran ne change (09/10/2026).
  final Map<int, double> largeursFixes;

  /// Une décoration PAR LIGNE, quand la bordure et le fond ne sont pas ceux du
  /// gabarit : le livre de paie pose un fond `bg-slate-100`, un fond navy et
  /// une bordure de 2 px sur trois de ses lignes (`rh/paie.blade.php`
  /// l.503-511). `null` pour une ligne : celle du gabarit. Aligné sur
  /// [lignes] ; absent : aucune ligne ne change (09/10/2026).
  final List<BoxDecoration?>? decorationsLignes;

  final List<ColonneRestaurant> colonnes;

  /// Vrai quand le tableau doit remplir son CADRE (`w-full` dans un conteneur
  /// de `max-w-[1500px]` : la carte, depuis le 09/10/2026) plutôt que la
  /// largeur de l'écran moins la barre latérale. Cette seconde mesure ignore
  /// la marge de la page (`p-8`) et la colonne bornée, si bien que le tableau
  /// débordait de son cadre. Faux par défaut : aucun autre écran ne change.
  final bool pleineLargeur;

  /// Vrai quand les colonnes se PARTAGENT la largeur du cadre comme le fait un
  /// `<table class="w-full">` du navigateur (algorithme `auto`) : chaque
  /// colonne garde sa largeur de contenu, et le surplus est réparti au
  /// PRORATA de ces largeurs. Faux par défaut (surplus réparti à égalité par
  /// `IntrinsicColumnWidth`) : aucun autre écran ne change.
  ///
  /// Mesuré sur la dépense courante : à 1 383 px, les sept en-têtes du
  /// navigateur commencent à x = 312,8 / 414 / 538,3 / 666,3 / 933,4 /
  /// 1 159,4 / 1 248 ; une répartition à égalité les décalait de plusieurs
  /// dizaines de pixels.
  final bool repartitionProportionnelle;

  /// Vrai quand l'EN-TÊTE reste affiché au-dessus de [vide] : la vue pose son
  /// `<thead>` en dehors de la boucle, et son état vide est une ligne
  /// `colspan` SOUS l'en-tête (`depenses.blade.php` l.248-256 et l.290-300).
  /// Faux par défaut : un tableau vide disparaît derrière [vide].
  final bool videSousEntete;

  /// Une liste de cellules par ligne, dans l'ordre des colonnes.
  final List<List<Widget>> lignes;

  final GabaritTableau gabarit;

  /// Une clé par ligne, posée sur sa **première cellule**.
  ///
  /// Jamais sur la ligne elle-même : une clé de ligne de tableau n'atteint pas
  /// l'arbre de widgets, et `find.byKey` ne la trouverait jamais — le piège 10
  /// de ce dépôt, rencontré deux fois. Une clé introuvable est une clé qui ment.
  final List<Key?>? clesLignes;

  /// La ligne TOTAL de l'onglet « Couverture du stock » —
  /// `border-t-2 border-slate-300 bg-slate-50 font-bold` (`carte-module.js`
  /// l.181). Elle n'est pas une ligne comme les autres : sa bordure est deux
  /// fois plus épaisse et son fond diffère.
  final List<Widget>? ligneTotal;

  /// La décoration de [ligneTotal], quand elle n'est pas celle de M4.
  ///
  /// M8 pose une AUTRE ligne de total : `.total-fort { background:
  /// var(--navy); color: #fff; font-weight: 700 }` (`m8-locations.html`
  /// l.16). Les deux maîtres ne se ressemblent pas — l'un est un pied de
  /// tableau clair, l'autre une barre pleine — et les aligner reviendrait à
  /// « harmoniser silencieusement une incohérence du maître » (Article 1,
  /// interdit 10). Ce paramètre laisse donc chaque page porter la sienne, et
  /// son défaut reste celle de M4 : aucun écran existant ne change.
  final BoxDecoration? decorationTotal;

  /// Ce qui remplace le corps quand il n'y a rien à montrer. Un tableau vide
  /// **dit pourquoi**, il ne reste pas blanc (Article 7).
  final Widget? vide;

  @override
  Widget build(BuildContext context) {
    assert(
      lignes.every((l) => l.length == colonnes.length),
      'chaque ligne doit porter autant de cellules que de colonnes',
    );

    final sansLigne = lignes.isEmpty && ligneTotal == null;
    if (sansLigne && !videSousEntete) {
      return vide ?? const SizedBox.shrink();
    }

    final tableau = LayoutBuilder(
      builder: (context, contraintes) => SingleChildScrollView(
        // `overflow-x-auto` — le maître laisse défiler plutôt que comprimer.
        // Comprimer tronquerait un prix, et un prix tronqué est un prix faux.
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          // `w-full` : au moins la largeur disponible, davantage si les colonnes
          // l'exigent. Par défaut la largeur de l'ÉCRAN moins la barre latérale
          // — jamais `constraints.maxWidth`, qui est celle du contenu (Article
          // 5). Avec [pleineLargeur], celle du cadre.
          constraints: BoxConstraints(
            minWidth: pleineLargeur
                ? contraintes.maxWidth
                : MediaQuery.sizeOf(context).width - AppLayout.sidebarWidth,
          ),
          child: Table(
            columnWidths: {
              for (final e in largeursFixes.entries)
                e.key: FixedColumnWidth(e.value),
            },
            defaultColumnWidth: repartitionProportionnelle
                ? const _ColonneProportionnelle()
                : const IntrinsicColumnWidth(),
            children: [
              TableRow(
                decoration: BoxDecoration(color: gabarit.enteteFond),
                children: [
                  for (final c in colonnes)
                    Padding(
                      padding: gabarit.enteteCellule ?? gabarit.cellule,
                      child: Align(
                        alignment: c.aDroite
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child:
                            c.enteteSpecial ??
                            Text(
                              // `uppercase` est une transformation CSS : on
                              // applique la même plutôt que de recopier des
                              // libellés déjà en capitales, sans quoi
                              // l'inventaire des libellés ne correspondrait
                              // plus au maître.
                              c.titre.toUpperCase(),
                              style: gabarit.entete,
                            ),
                      ),
                    ),
                ],
              ),
              for (var l = 0; l < lignes.length; l++)
                TableRow(
                  decoration:
                      _decorationDe(l) ??
                      BoxDecoration(
                        border: gabarit.enBas
                            // `border-b border-slate-100` (`crud-engine.js`
                            // l.226).
                            ? const Border(
                                bottom: BorderSide(color: Ardoise.c100),
                              )
                            // `border-t border-slate-100` (`carte-module.js`
                            // l.97).
                            : const Border(
                                top: BorderSide(color: Ardoise.c100),
                              ),
                      ),
                  children: [
                    for (var c = 0; c < lignes[l].length; c++)
                      Padding(
                        key: c == 0 ? _cleDe(l) : null,
                        padding: gabarit.cellule,
                        child: Align(
                          alignment: colonnes[c].aDroite
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: lignes[l][c],
                        ),
                      ),
                  ],
                ),
              if (ligneTotal != null)
                TableRow(
                  decoration:
                      decorationTotal ??
                      const BoxDecoration(
                        color: Ardoise.c50,
                        // `border-t-2 border-slate-300`.
                        border: Border(
                          top: BorderSide(
                            color: Ardoise.c300,
                            width: AppSpacing.demi,
                          ),
                        ),
                      ),
                  children: [
                    for (var c = 0; c < ligneTotal!.length; c++)
                      Padding(
                        padding: gabarit.celluleTotal ?? gabarit.cellule,
                        child: Align(
                          alignment: colonnes[c].aDroite
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: ligneTotal![c],
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );

    if (!sansLigne) return tableau;

    // L'en-tête, puis la ligne `colspan` : elle occupe toute la largeur du
    // cadre, hors du défilement horizontal des colonnes.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [tableau, ?vide],
    );
  }

  BoxDecoration? _decorationDe(int index) =>
      (decorationsLignes != null && index < decorationsLignes!.length)
      ? decorationsLignes![index]
      : null;

  Key? _cleDe(int index) => (clesLignes != null && index < clesLignes!.length)
      ? clesLignes![index]
      : null;
}

/// La répartition d'un `<table class="w-full">` : largeur de contenu, plus le
/// surplus au PRORATA de cette largeur.
///
/// `RenderTable` fait grandir les colonnes flexibles jusqu'à
/// `cible × flex / Σflex` ; avec `flex` = largeur de contenu, on obtient
/// exactement `largeurᵢ × cible / Σlargeur`, ce que fait le navigateur.
final class _ColonneProportionnelle extends IntrinsicColumnWidth {
  const _ColonneProportionnelle();

  @override
  double? flex(Iterable<RenderBox> cells) {
    final contenu = maxIntrinsicWidth(cells, double.infinity);
    // Un `flex` doit être strictement positif : une colonne sans contenu
    // garde sa largeur nulle plutôt que de lever.
    return contenu > 0 ? contenu : null;
  }
}

/// Une colonne — son libellé **au caractère près** et son alignement.
final class ColonneRestaurant {
  const ColonneRestaurant(
    this.titre, {
    this.aDroite = false,
    this.enteteSpecial,
  });

  final String titre;

  /// Un contrôle à la place du libellé : la case « tout sélectionner » de la
  /// paie (`rh/paie.blade.php` l.305-308) est un `<th>` sans texte. `null` :
  /// [titre] en capitales, comme partout ailleurs.
  final Widget? enteteSpecial;

  /// `text-right`. Au maître, **toute** colonne d'un tableau de carte est à
  /// droite sauf celles listées dans `gauche` (`carte-module.js` l.52) — c'est
  /// l'inverse de la convention habituelle, et le recopier tel quel est le
  /// seul moyen de rendre la même image.
  final bool aDroite;
}

/// Le gabarit d'un tableau : ce qui distingue celui de la carte de celui du
/// moteur CRUD.
final class GabaritTableau {
  const GabaritTableau({
    required this.enteteFond,
    required this.entete,
    required this.cellule,
    required this.enBas,
    this.enteteCellule,
    this.celluleTotal,
  });

  final Color enteteFond;
  final TextStyle entete;
  final EdgeInsets cellule;

  /// Le remplissage des cellules d'EN-TÊTE quand il diffère de [cellule] : la
  /// paie pose `px-3 py-2.5` sur ses `<th>` et `px-3 py-2` sur ses `<td>`
  /// (`rh/paie.blade.php` l.300 et l.331). `null` : celui de [cellule] — aucun
  /// autre gabarit ne change (09/10/2026).
  final EdgeInsets? enteteCellule;

  /// Idem pour la ligne [TableauRestaurant.ligneTotal] (`px-3 py-2.5`, l.393).
  final EdgeInsets? celluleTotal;

  /// Vrai quand la bordure de ligne est **en bas** (`border-b` du moteur CRUD),
  /// faux quand elle est en haut (`border-t` de la carte).
  final bool enBas;

  /// Le tableau de la carte — `bg-slate-50`, `px-3 py-2.5`, `border-t`.
  static const GabaritTableau carte = GabaritTableau(
    enteteFond: Ardoise.c50,
    entete: TextesRestaurant.enteteColonne,
    cellule: EdgeInsets.symmetric(
      // `px-3` — 12 px, et non les 16 px de `px-4`.
      horizontal: AppSpacing.sm,
      // `py-2.5` — 10 px. L'espacement le plus employé de tout le maître.
      vertical: AppSpacing.xsPlus,
    ),
    enBas: false,
  );

  /// Le tableau de la carte tel que la VUE BLADE le dessine —
  /// `<thead class="bg-[var(--navy)]">` et des en-têtes `text-white/90`
  /// (`pwa/carte/corps.blade.php` l.312 et l.41-44), cellules `px-3 py-2.5`,
  /// `border-t border-slate-100` (l.336). Le gabarit [carte] est celui de
  /// l'ancien prototype (en-tête `bg-slate-50`) : il reste pour les écrans
  /// qui ne sont pas encore repris (véhicules, bar couverture) — 09/10/2026.
  static const GabaritTableau carteVue = GabaritTableau(
    enteteFond: AppColors.navy,
    entete: TextesRestaurant.enteteColonneNavy,
    cellule: EdgeInsets.symmetric(
      horizontal: AppSpacing.sm,
      vertical: AppSpacing.xsPlus,
    ),
    enBas: false,
  );

  /// Le tableau du moteur CRUD — en-tête **navy pleine**, `px-4 py-3`,
  /// `border-b`.
  static const GabaritTableau crud = GabaritTableau(
    enteteFond: AppColors.navy,
    entete: TextesRestaurant.enteteColonneNavy,
    cellule: EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.sm,
    ),
    enBas: true,
  );
}
