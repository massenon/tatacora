// Vue Blade maîtresse (PA-183) : pwa/facturation/facturation.blade.php
// Vue Blade maîtresse (PA-183) : pwa/pos/historique-ventes.blade.php
import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_text_styles.dart';

/// Le tableau du maître de mise en page.
///
/// **Source : `prototype_v2/pages/m2-facturation.html` l.129-160**, dont le
/// balisage est repris valeur par valeur :
///
/// ```html
/// <div class="overflow-x-auto"><table class="w-full text-[13px]">
///   <thead class="bg-slate-50 text-[11px] uppercase text-slate-500">
///     <th class="text-left px-4 py-2.5">…</th>
///   <tbody>
///     <tr class="border-t border-slate-100">
///       <td class="px-4 py-2.5">…</td>
/// ```
///
/// ## Pourquoi un composant, et pas un tableau par écran
///
/// `AUDIT_CONFORMITE_ECRANS_FLUTTER.md` §7.1 : **aucun `DataTable` n'existait
/// dans tout le client**, alors que le maître pose des tableaux à en-têtes sur
/// plusieurs pages — 7 colonnes en Facturation, 5 en Hébergement. C'est le plus
/// grand écart de forme après la coquille, et **douze des vingt-sept manquants
/// en dépendent**. Les traiter écran par écran donnerait sept tableaux
/// légèrement différents ; c'est exactement ce que la doctrine §3.4 refuse —
/// « mêmes colonnes, même ordre, mêmes alignements, en-têtes en capitales ».
///
/// ## `DataTable` de Material n'a pas été retenu
///
/// Il impose ses propres hauteurs de ligne, ses séparateurs et son en-tête, et
/// les ramener aux valeurs du maître demande de combattre le composant à chaque
/// propriété. La doctrine §2 interdit d'ailleurs de substituer un composant
/// Material par défaut à un composant maquetté : une `Table` nue traduit le
/// balisage sans rien imposer.
///
/// ## `overflow-x-auto` n'est pas décoratif
///
/// Sept colonnes ne tiennent pas sur un écran étroit. Le maître laisse défiler
/// **horizontalement** plutôt que comprimer ; comprimer tronquerait des
/// montants, et un montant tronqué est un montant faux.
class TableauTatacora extends StatelessWidget {
  const TableauTatacora({
    required this.colonnes,
    required this.lignes,
    this.messageVide = 'Aucune donnée.',
    this.onTapLigne,
    this.clesLignes,
    this.corpsVide,
    super.key,
  });

  final List<ColonneTableau> colonnes;
  final List<List<Widget>> lignes;

  /// Un tableau vide **dit pourquoi**, il ne reste pas blanc — doctrine §5.
  final String messageVide;

  /// ÉCART DÉLIBÉRÉ — les `<tr>` du maître ne portent aucun gestionnaire.
  ///
  /// L'ajouter donne accès, depuis la ligne, à des fonctions que le maître
  /// n'expose pas à cet endroit mais qui existent et comptent : l'aperçu du
  /// ticket, son impression, et la facture A4 (PA-99, PA-101). Les retirer par
  /// fidélité supprimerait des livrables réels ; la doctrine §5 demande de
  /// documenter l'écart, pas de renoncer à la fonction.
  ///
  /// `null` reproduit exactement le maître : lignes inertes.
  final void Function(int index)? onTapLigne;

  /// Le `<tbody>` d'un tableau VIDE, sous des en-têtes qui restent visibles.
  ///
  /// Par défaut (`null`), un tableau sans ligne est REMPLACÉ par [messageVide]
  /// et ne rend aucun en-tête — doctrine §5 : un tableau vide dit pourquoi, il
  /// ne reste pas blanc.
  ///
  /// Le maître, lui, garde parfois son `<thead>` au-dessus d'un `<tbody>` qui
  /// ne porte qu'une cellule d'explication (`paie.blade.php` l.547-558). Ce
  /// n'est pas un détail de rendu : au livre de paie, c'est le SQUELETTE des
  /// colonnes qui montre qu'aucune écriture n'est inventée. Recopier les
  /// libellés dans [messageVide] les rendrait comme une phrase, pas comme des
  /// en-têtes, et l'inventaire des libellés cesserait de correspondre.
  final Widget? corpsVide;

  /// Une clé par ligne, posée sur sa **première** cellule.
  ///
  /// Une ligne doit rester désignable de l'extérieur — c'est ce qui permet à un
  /// test de dire « celle-ci » plutôt que « la troisième », et un index se
  /// périme au premier tri. Posée sur la première cellule seulement : la
  /// répéter sur les sept ferait sept widgets portant la même clé, ce que
  /// Flutter refuse.
  final List<Key?>? clesLignes;

  /// `px-4 py-2.5` — 16 px horizontal, 10 px vertical, en-tête comme cellules.
  static const EdgeInsets _cellule = EdgeInsets.symmetric(
    horizontal: AppSpacing.md,
    // `py-2.5` du maitre — 10 px, l'espacement le plus employe de toute la
    // maquette (672 emplois). Il n'avait aucun jeton avant le 26/08/2026.
    vertical: AppSpacing.xsPlus,
  );

  Key? _cleDe(int index) => (clesLignes != null && index < clesLignes!.length)
      ? clesLignes![index]
      : null;

  @override
  Widget build(BuildContext context) {
    assert(
      lignes.every((l) => l.length == colonnes.length),
      'chaque ligne doit porter autant de cellules que de colonnes',
    );

    if (lignes.isEmpty && corpsVide == null) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Center(
          child: Text(
            messageVide,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.neutre500,
              fontFamily: AppTextStyles.police,
              fontSize: TaillesContenu.t13,
            ),
          ),
        ),
      );
    }

    final tableau = SingleChildScrollView(
      // `overflow-x-auto`
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        // `w-full` : le tableau occupe au moins la largeur disponible, et
        // s'étend au-delà quand ses colonnes l'exigent.
        constraints: BoxConstraints(
          minWidth: MediaQuery.sizeOf(context).width - AppLayout.sidebarWidth,
        ),
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          children: [
            TableRow(
              // `bg-slate-50`
              decoration: const BoxDecoration(
                color: CouleursTableau.enteteFond,
              ),
              children: [
                for (final c in colonnes)
                  Padding(
                    padding: _cellule,
                    child: Align(
                      alignment: c.aDroite
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Text(
                        // `uppercase` est une transformation CSS : le maître
                        // écrit « N° », l'écran affiche « N° ». On applique la
                        // même transformation plutôt que de recopier des
                        // libellés déjà en capitales, sans quoi l'inventaire
                        // des libellés ne correspondrait plus au maître.
                        c.titre.toUpperCase(),
                        style: TextStyle(
                          color: CouleursTableau.enteteTexte,
                          fontFamily: AppTextStyles.police,
                          fontSize: TaillesContenu.t11,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            for (final ligne in lignes)
              TableRow(
                // `border-t border-slate-100`
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: CouleursTableau.separateur),
                  ),
                ),
                children: [
                  for (var i = 0; i < ligne.length; i++)
                    _Cellule(
                      key: i == 0 ? _cleDe(lignes.indexOf(ligne)) : null,
                      alignement: colonnes[i].aDroite
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      onTap: onTapLigne == null
                          ? null
                          : () => onTapLigne!(lignes.indexOf(ligne)),
                      child: ligne[i],
                    ),
                ],
              ),
          ],
        ),
      ),
    );

    // Les en-têtes restent, le corps est celui de l'appelant. Le tableau garde
    // son défilement horizontal : les en-têtes seules peuvent déjà déborder.
    if (lignes.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [tableau, corpsVide!],
      );
    }
    return tableau;
  }
}

/// Une cellule.
///
/// `TableRowInkWell` et non `InkWell` : l'ondulation d'un `InkWell` ordinaire
/// s'arrêterait au bord de SA cellule, ce qui donnerait sept réactions
/// distinctes pour une seule ligne.
class _Cellule extends StatelessWidget {
  const _Cellule({
    required this.alignement,
    required this.child,
    this.onTap,
    super.key,
  });

  final Alignment alignement;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final contenu = Padding(
      padding: TableauTatacora._cellule,
      child: Align(alignment: alignement, child: child),
    );
    if (onTap == null) return contenu;
    return TableRowInkWell(onTap: onTap, child: contenu);
  }
}

/// Une colonne — son libellé et son alignement.
final class ColonneTableau {
  const ColonneTableau(this.titre, {this.aDroite = false});

  /// Le libellé **au caractère près**, tel que le maître l'écrit.
  final String titre;

  /// `text-right`. Réservé aux montants : une colonne de chiffres alignée à
  /// gauche est illisible dès la troisième ligne.
  final bool aDroite;
}

/// Les couleurs des tableaux du maître.
///
/// ⚠ **Incohérence du maître, signalée et non tranchée** (doctrine §2) : ces
/// pastilles et ces fonds emploient la palette **Tailwind par défaut**
/// (`slate`, `emerald`, `red`), alors que le reste du maître passe par ses
/// propres variables CSS — `--erreur` vaut `#C62828`, pas `#B91C1C`.
///
/// Les deux cohabitent donc dans la maquette validée. **Les rapprocher
/// silencieusement créerait un troisième comportement qui n'existe nulle
/// part** ; les valeurs ci-dessous sont donc celles du maître, à l'octet près.
/// Le jour où le Product Owner unifiera la charte, c'est ici qu'on le fera.
///
/// **Révision du 26/08/2026 — le constat tient, les seize entiers partent.**
/// Cette classe portait seize `Color(0x…)` en dur, ce que l'Article 2 interdit
/// nommément (« aucune valeur de style en dur dans un widget »). Chacune était
/// juste, et c'est précisément le problème : la dix-septième ne l'aurait pas
/// forcément été, et rien ne l'aurait signalé.
///
/// Les rangs viennent désormais de [Ardoise] et [PaletteMaitre], relus dans le
/// bundle Tailwind du maître par `conformite_jetons_maitre_test.dart`. Les noms
/// de RÔLE restent ici — c'est eux qui portent le sens, et le tableau
/// ci-dessus reste vrai : ce sont bien les palettes Tailwind, distinctes des
/// variables CSS du maître.
abstract final class CouleursTableau {
  /// `bg-slate-50`
  static const Color enteteFond = Ardoise.c50;

  /// `text-slate-500`
  static const Color enteteTexte = Ardoise.c500;

  /// `border-slate-100`
  static const Color separateur = Ardoise.c100;

  /// `text-slate-500` — dates, libellés secondaires.
  static const Color texteSecondaire = Ardoise.c500;

  /// `text-red-600` — un montant négatif.
  static const Color montantNegatif = PaletteMaitre.rouge600;

  /// Pastille « émise » — `bg-emerald-50 text-emerald-700`.
  static const Color succesFond = PaletteMaitre.emeraude50;
  static const Color succesTexte = PaletteMaitre.emeraude700;

  /// Pastille « annulée » — `bg-red-50 text-red-700`.
  static const Color refusFond = PaletteMaitre.rouge50;
  static const Color refusTexte = PaletteMaitre.rouge700;

  /// Pastille « avoir de … » — `bg-slate-100 text-slate-600`.
  static const Color neutreFond = Ardoise.c100;
  static const Color neutreTexte = Ardoise.c600;

  /// Pastille « en note » — `bg-amber-50 text-amber-700`
  /// (`prototype_v2/pages/historique-ventes.html` l.226).
  ///
  /// Ni un succès ni un refus, et c'est tout l'enjeu : une consommation portée
  /// sur la note de chambre **n'est pas dans le tiroir**. La rendre verte la
  /// ferait lire comme un encaissement ; la rendre rouge, comme un incident.
  /// C'est une créance, et le maître lui donne sa propre couleur.
  static const Color alerteFond = PaletteMaitre.ambre50;
  static const Color alerteTexte = PaletteMaitre.ambre700;

  /// `text-emerald-600` — l'accent « Encaissé » des cartes d'indicateurs
  /// (`historique-ventes.html` l.198).
  static const Color accentSucces = PaletteMaitre.emeraude600;

  /// `text-amber-600` — l'accent « Porté en note » (l.199).
  static const Color accentAlerte = PaletteMaitre.ambre600;

  /// `text-red-600` — l'accent d'alarme des cartes d'indicateurs (l.201).
  ///
  /// **Même valeur que [montantNegatif]**, et c'est un alias volontaire : le
  /// maître emploie la même classe aux deux endroits. Réécrire le code
  /// hexadécimal ici créerait une seconde source pour une seule couleur, et
  /// deux sources finissent toujours par diverger.
  static const Color accentErreur = montantNegatif;
}

/// Une pastille de statut — `px-2 py-0.5 rounded text-[11px] font-semibold`.
class PastilleStatut extends StatelessWidget {
  const PastilleStatut(
    this.libelle, {
    required this.fond,
    required this.texte,
    super.key,
  });

  /// La pastille verte du maître : « émise ».
  const PastilleStatut.succes(this.libelle, {super.key})
    : fond = CouleursTableau.succesFond,
      texte = CouleursTableau.succesTexte;

  /// La pastille rouge : « annulée ».
  const PastilleStatut.refus(this.libelle, {super.key})
    : fond = CouleursTableau.refusFond,
      texte = CouleursTableau.refusTexte;

  /// La pastille grise : « avoir de … ».
  const PastilleStatut.neutre(this.libelle, {super.key})
    : fond = CouleursTableau.neutreFond,
      texte = CouleursTableau.neutreTexte;

  /// La pastille ambre : « en note ».
  ///
  /// Elle existe pour un cas que les trois autres ne savent pas dire — une
  /// vente valide dont l'argent n'est PAS entré en caisse. Sans elle, il
  /// faudrait la ranger avec les succès ou avec les refus, et les deux
  /// mentiraient.
  const PastilleStatut.alerte(this.libelle, {super.key})
    : fond = CouleursTableau.alerteFond,
      texte = CouleursTableau.alerteTexte;

  final String libelle;
  final Color fond;
  final Color texte;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.demi,
      ),
      decoration: BoxDecoration(
        color: fond,
        borderRadius: BorderRadius.circular(AppRadius.sm), // rounded
      ),
      child: Text(
        libelle,
        style: TextStyle(
          color: texte,
          fontFamily: AppTextStyles.police,
          fontSize: TaillesContenu.t11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Une cellule ordinaire — `text-[13px]`, la taille dominante du maître.
class CelluleTableau extends StatelessWidget {
  const CelluleTableau(
    this.texte, {
    this.secondaire = false,
    this.monospace = false,
    this.gras = false,
    this.couleur,
    super.key,
  });

  final String texte;

  /// `text-slate-500` — dates, origines, libellés d'appoint.
  final bool secondaire;

  /// `font-mono text-[12px]` — les numéros de pièce. Une police
  /// proportionnelle rend une colonne de numéros illisible.
  final bool monospace;

  final bool gras;
  final Color? couleur;

  @override
  Widget build(BuildContext context) {
    return Text(
      texte,
      style: TextStyle(
        color:
            couleur ??
            (secondaire
                ? CouleursTableau.texteSecondaire
                : AppColors.anthracite),
        fontFamily: monospace
            ? AppTextStyles.policeMonospace
            : AppTextStyles.police,
        fontSize: monospace ? TaillesContenu.t12 : TaillesContenu.t13,
        fontWeight: gras ? FontWeight.w600 : FontWeight.normal,
      ),
    );
  }
}
