/// Les cinq panneaux d'onglet de M13.
///
/// Vue Blade maîtresse (PA-183) : pwa/rh/paie.blade.php
///
/// ## Un seul panneau est monté à la fois
///
/// La vue Blade rend les cinq et masque les inactifs par `hidden` — un onglet
/// dont aucune colonne n'est rendue n'est pas un onglet livré (Article 3.3), et
/// la garde serveur compare les en-têtes de tableau au premier GET. Ici, les
/// libellés vivent dans **ce fichier, importé par l'écran** : le comparateur
/// `t-blade-flutter.js` les voit donc tous (PA-196), sans qu'il faille
/// construire quatre panneaux que personne ne regarde à chaque rendu.
///
/// ## L'échelle typographique est celle de `<main>`
///
/// Ces panneaux sont dans le corps de page : `app.css` y remappe les tailles
/// (`text-[13px]` rend 12,5 px), l'interligne est 1,5 et l'interlettrage nul.
/// Tous les styles passent par `styleContenuCarte` et `TaillesContenu`.
library;

// `hide Simulation` — voir `providers_rh.dart` : le type métier garde son nom,
// celui de la physique des animations s'efface, il n'est pas employé ici.
import 'package:flutter/material.dart' hide Simulation;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/format/formats.dart';
import '../../../../core/theme/app_breakpoints.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../restaurant/presentation/widgets/corps_carte_commun.dart'
    show EncadreCarte, styleContenuCarte;
import '../../../restaurant/presentation/widgets/tableau_restaurant.dart';
import '../../domain/entities/bulletin_paie.dart';
import '../../domain/entities/employe.dart';
import '../../domain/services/bulletin_paie_service.dart';
import '../../domain/services/calcul_paie_service.dart';
import '../../domain/services/livre_de_paie_service.dart';
import '../../impression/etat_paie.dart';
import '../providers_rh.dart';

/// Le tiret du maître — « — », jamais une cellule vide.
///
/// Une case vide laisse croire à un oubli d'affichage ; le tiret dit que la
/// donnée n'existe pas.
const String tiret = tiretPaie;

/// La fourchette d'un coût employeur, ou un tiret.
///
/// ⚠ **Jamais un montant unique** : c'est ici que l'hypothèse refusée par
/// PA-53 rentrerait si on la laissait passer.
String fourchetteCout(CoutEmployeur? cout) => cout == null
    ? tiret
    : '${formaterFcfa(cout.coutMin)} $tiret ${formaterFcfa(cout.coutMax)}';

/* ====================================================================== */
/* Styles et gabarits — la vue, classe par classe                          */
/* ====================================================================== */

/// Un style de cellule ou de texte de panneau : `text-[Npx]`, interligne 1,5.
TextStyle _t(
  double taille, {
  FontWeight? poids,
  Color? couleur,
  bool mono = false,
}) {
  final base = styleContenuCarte(taille, poids: poids, couleur: couleur);
  return mono ? base.copyWith(fontFamily: AppTextStyles.policeMonospace) : base;
}

/// `text-[11px] uppercase tracking-wide text-white/90 font-semibold`
/// (`$entete`, l.76-79).
const TextStyle _enteteColonne = TextStyle(
  fontFamily: AppTextStyles.police,
  fontSize: TaillesContenu.t11,
  fontWeight: FontWeight.w600,
  height: AppLayout.interligneContenu,
  letterSpacing: TaillesContenu.t11 * AppTextStyles.suiviLarge,
  color: AppColors.blanc90,
);

/// Les tableaux de la paie : `<thead class="bg-[var(--navy)]">`, en-têtes
/// `px-3 py-2.5` (l.300), cellules `px-3 py-2` (l.331), ligne de total
/// `px-3 py-2.5` (l.393), `border-t border-slate-100`.
const GabaritTableau gabaritPaie = GabaritTableau(
  enteteFond: AppColors.navy,
  entete: _enteteColonne,
  cellule: EdgeInsets.symmetric(
    horizontal: AppSpacing.sm,
    vertical: AppSpacing.xs,
  ),
  enteteCellule: EdgeInsets.symmetric(
    horizontal: AppSpacing.sm,
    vertical: AppSpacing.xsPlus,
  ),
  celluleTotal: EdgeInsets.symmetric(
    horizontal: AppSpacing.sm,
    vertical: AppSpacing.xsPlus,
  ),
  enBas: false,
);

/// Le tableau des déclarations : ses cellules sont `px-3 py-2.5` (l.583), pas
/// `py-2` comme les autres tableaux de l'écran.
const GabaritTableau gabaritPaieDeclarations = GabaritTableau(
  enteteFond: AppColors.navy,
  entete: _enteteColonne,
  cellule: EdgeInsets.symmetric(
    horizontal: AppSpacing.sm,
    vertical: AppSpacing.xsPlus,
  ),
  enBas: false,
);

/// La hauteur d'une ligne de texte de 13 px — celle de l'étiquette étendue.
const double _hauteurLigne13 = TaillesContenu.t13 * AppLayout.interligneContenu;

/// Un libellé qui court sur plusieurs colonnes — le `colspan` des lignes de
/// total et du refus du barème.
///
/// Une `Table` n'a pas de `colspan`. Le texte est posé dans une boîte de
/// largeur NULLE, donc sans effet sur la largeur de sa colonne
/// (`IntrinsicColumnWidth` ne voit que 0), et déborde sur les cellules
/// voisines, vides. [droite] : le texte s'aligne à DROITE de sa cellule et
/// déborde vers la gauche — le `text-right` d'une cellule étendue.
class _EtiquetteEtendue extends StatelessWidget {
  const _EtiquetteEtendue(this.texte, this.style, {this.droite = false});

  final String texte;
  final TextStyle style;
  final bool droite;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 0,
      height: _hauteurLigne13,
      child: OverflowBox(
        minWidth: 0,
        maxWidth: double.infinity,
        alignment: droite ? Alignment.centerRight : Alignment.centerLeft,
        child: Text(texte, style: style, softWrap: false),
      ),
    );
  }
}

/// L'état vide d'un tableau : `px-3 py-14 text-center`, deux lignes
/// (`aucun_resultat` en `font-semibold text-slate-500`, puis le détail en
/// `text-slate-400 mt-1`).
class _EtatVide extends StatelessWidget {
  const _EtatVide({required this.titre, required this.detail});

  final String titre;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacingLarge.p14,
      ),
      child: Column(
        children: [
          Text(
            titre,
            textAlign: TextAlign.center,
            style: _t(
              TaillesContenu.t13,
              poids: FontWeight.w600,
              couleur: Ardoise.c500,
            ),
          ),
          const SizedBox(height: AppSpacing.unit),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: _t(TaillesContenu.t13, couleur: Ardoise.c400),
          ),
        ],
      ),
    );
  }
}

/// Le tableau d'un panneau, avec les options communes : pleine largeur du
/// cadre, colonnes réparties au prorata, en-tête gardé quand la liste est vide.
class _TableauPaie extends StatelessWidget {
  const _TableauPaie({
    required this.colonnes,
    required this.lignes,
    this.gabarit = gabaritPaie,
    this.clesLignes,
    this.ligneTotal,
    this.vide,
    this.decorationsLignes,
  });

  final List<ColonneRestaurant> colonnes;
  final List<List<Widget>> lignes;
  final GabaritTableau gabarit;
  final List<Key?>? clesLignes;
  final List<Widget>? ligneTotal;
  final Widget? vide;
  final List<BoxDecoration?>? decorationsLignes;

  @override
  Widget build(BuildContext context) {
    return TableauRestaurant(
      gabarit: gabarit,
      colonnes: colonnes,
      lignes: lignes,
      clesLignes: clesLignes,
      ligneTotal: ligneTotal,
      decorationsLignes: decorationsLignes,
      // `<table class="w-full">` dans un cadre `overflow-hidden`.
      pleineLargeur: true,
      repartitionProportionnelle: true,
      // `<thead>` hors de la boucle : l'état vide est une ligne SOUS l'en-tête.
      videSousEntete: true,
      vide: vide,
      decorationTotal: const BoxDecoration(color: AppColors.navy),
    );
  }
}

/* ====================================================================== */
/* Coquille commune — la carte blanche à titre du maître                   */
/* ====================================================================== */

/// `bg-white rounded-xl border border-slate-200 overflow-hidden mb-3`, et son
/// en-tête `px-4 py-3 border-b border-slate-200` (`h3` en `text-[14px]
/// font-bold`, mention de droite en `text-[11px] text-amber-700`).
class CartePaie extends StatelessWidget {
  const CartePaie({
    required this.titre,
    required this.enfant,
    this.note,
    this.action,
    super.key,
  });

  final String titre;
  final String? note;

  /// Un contrôle à droite du titre — le bouton « Archiver la sélection ».
  final Widget? action;
  final Widget enfant;

  @override
  Widget build(BuildContext context) {
    return Container(
      // `mb-3`.
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.neutre0,
        borderRadius: BorderRadius.circular(AppRadius.roundedXl),
        border: Border.all(color: Ardoise.c200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Ardoise.c200)),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                Text(
                  titre,
                  style: _t(
                    TaillesContenu.t14,
                    poids: FontWeight.bold,
                    couleur: AppColors.navy,
                  ),
                ),
                if (note != null)
                  Text(
                    note!,
                    style: _t(
                      TaillesContenu.t11,
                      couleur: PaletteMaitre.ambre700,
                    ),
                  ),
                ?action,
              ],
            ),
          ),
          enfant,
        ],
      ),
    );
  }
}

/// Un bouton de ligne : `text-[11px] px-2 py-0.5 rounded border` (l.362-380).
enum HabitBoutonLigne {
  /// `border-slate-300`.
  neutre,

  /// `border-emerald-300 bg-emerald-50 text-emerald-700` — « Bulletin ».
  succes,

  /// `bg-[var(--erreur)] text-white font-bold` — « Archiver ».
  danger,
}

class BoutonLigne extends StatelessWidget {
  const BoutonLigne({
    required Key cle,
    required this.libelle,
    required this.onPressed,
    this.habit = HabitBoutonLigne.neutre,
  }) : super(key: cle);

  final String libelle;
  final VoidCallback onPressed;
  final HabitBoutonLigne habit;

  @override
  Widget build(BuildContext context) {
    final (fond, bord, texte, poids) = switch (habit) {
      HabitBoutonLigne.neutre => (
        null,
        Ardoise.c300,
        Ardoise.c700,
        FontWeight.normal,
      ),
      HabitBoutonLigne.succes => (
        PaletteMaitre.emeraude50,
        PaletteMaitre.emeraude300,
        PaletteMaitre.emeraude700,
        FontWeight.normal,
      ),
      HabitBoutonLigne.danger => (
        AppColors.erreur,
        AppColors.erreur,
        AppColors.neutre0,
        FontWeight.bold,
      ),
    };

    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.demi,
        ),
        decoration: BoxDecoration(
          color: fond,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: bord),
        ),
        child: Text(
          libelle,
          style: _t(TaillesContenu.t11, poids: poids, couleur: texte),
        ),
      ),
    );
  }
}

/// Les boutons d'une ligne, SUR UNE LIGNE : `whitespace-nowrap`, séparés de
/// `ml-1` (4 px) (l.359, l.451). Un `Wrap` les aurait fait passer à la ligne
/// dans une colonne étroite — la vue ne le fait jamais, elle élargit la colonne.
class _RangeeBoutons extends StatelessWidget {
  const _RangeeBoutons({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.unit),
          children[i],
        ],
      ],
    );
  }
}

/// Une pastille : `text-[11px] px-2 py-0.5 rounded` (l.352, l.593, l.732).
class _Pastille extends StatelessWidget {
  const _Pastille(
    this.libelle, {
    required this.fond,
    required this.texte,
    this.gras = false,
    this.horizontal = AppSpacing.xs,
  });

  final String libelle;
  final Color fond;
  final Color texte;
  final bool gras;
  final double horizontal;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: horizontal,
        vertical: AppSpacing.demi,
      ),
      decoration: BoxDecoration(
        color: fond,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        libelle,
        style: _t(
          TaillesContenu.t11,
          poids: gras ? FontWeight.w600 : null,
          couleur: texte,
        ),
      ),
    );
  }
}

/// Le montant d'une cellule : `text-right`, gras éventuel, couleur éventuelle.
Widget _c(
  String texte, {
  double taille = TaillesContenu.t13,
  FontWeight? poids,
  Color? couleur = Ardoise.c600,
  bool mono = false,
}) => Text(
  texte,
  style: _t(taille, poids: poids, couleur: couleur, mono: mono),
);

/* ====================================================================== */
/* Onglet « Personnel »                                                    */
/* ====================================================================== */

class PanneauPersonnel extends ConsumerWidget {
  const PanneauPersonnel({
    required this.onEtablir,
    required this.onModifier,
    required this.onArchiver,
    super.key,
  });

  final void Function(Employe employe) onEtablir;
  final void Function(Employe employe) onModifier;

  /// `ouvrirArchivageEmployes(?id)` : un identifiant pour la ligne, `null`
  /// pour la sélection.
  final void Function(String? employeId) onArchiver;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final employes = ref.watch(employesAffichesProvider).value ?? const [];
    final couts = ref.watch(coutParEmployeProvider).value ?? const {};
    final bulletins = ref.watch(bulletinsParEmployeProvider).value ?? const {};
    final coutMasse = ref.watch(coutMasseProvider).value;
    final peutEcrire = ref.watch(peutEcrirePaieProvider);
    final peutArchiver = ref.watch(peutArchiverPaieProvider);
    final periode = ref.watch(periodeValideProvider);
    final selection = ref.watch(selectionPaieProvider);
    final affichee = ref.watch(selectionAfficheePaieProvider).value ?? const [];

    final masse = employes.fold<int>(0, (somme, e) => somme + e.salaireBase);
    final archivables = [
      for (final e in employes)
        if (e.statut != StatutEmploye.parti) e.id,
    ];

    final styleTotal = _t(
      TaillesContenu.t13,
      poids: FontWeight.bold,
      couleur: AppColors.neutre0,
    );

    // Le `colspan` du total court jusqu'à la colonne « Salaire de base » :
    // cinq colonnes, six avec la case (l.393).
    final avantSalaire = peutArchiver ? 6 : 5;

    return CartePaie(
      titre: 'Effectif — ${periode.libelleLong}',
      // Archivage en bloc : le bouton n'apparaît qu'avec une sélection — un
      // bouton rouge permanent inviterait au clic (l.283-296).
      action: peutArchiver && affichee.isNotEmpty
          ? _BoutonArchivageLot(
              nombre: affichee.length,
              onPressed: () => onArchiver(null),
            )
          : null,
      enfant: _TableauPaie(
        vide: const _EtatVide(
          titre: 'Aucun résultat',
          detail: 'Aucun employé ne correspond à ces critères.',
        ),
        colonnes: [
          if (peutArchiver)
            ColonneRestaurant(
              '',
              enteteSpecial: _CaseACocher(
                cle: const Key('paie-case-tout'),
                etiquette: 'Sélectionner tout le personnel affiché',
                valeur:
                    archivables.isNotEmpty &&
                    archivables.every(selection.contains),
                onChanged: (coche) {
                  final notifier = ref.read(selectionPaieProvider.notifier);
                  if (coche) {
                    notifier.definir(archivables.toSet());
                  } else {
                    notifier.vider();
                  }
                },
              ),
            ),
          const ColonneRestaurant('Matricule'),
          const ColonneRestaurant('Employé'),
          const ColonneRestaurant('Contrat', aDroite: true),
          const ColonneRestaurant('Embauche', aDroite: true),
          const ColonneRestaurant('N° CNSS', aDroite: true),
          const ColonneRestaurant('Salaire de base', aDroite: true),
          const ColonneRestaurant('Coût employeur', aDroite: true),
          // La colonne d'actions n'a PAS d'en-tête : le maître termine ses
          // tableaux par une chaîne vide.
          const ColonneRestaurant('', aDroite: true),
        ],
        clesLignes: [for (final e in employes) Key('paie-employe-${e.id}')],
        lignes: [
          for (final employe in employes)
            _ligneEmploye(
              ref: ref,
              employe: employe,
              cout: couts[employe.id],
              bulletin: bulletins[employe.id],
              peutEcrire: peutEcrire,
              peutArchiver: peutArchiver,
              coche: selection.contains(employe.id),
            ),
        ],
        ligneTotal: employes.isEmpty
            ? null
            : [
                _EtiquetteEtendue(
                  'TOTAL — ${employes.length} employé(s)',
                  styleTotal,
                ),
                for (var i = 1; i < avantSalaire; i++) const SizedBox.shrink(),
                Text(formaterFcfa(masse), style: styleTotal),
                Text(
                  fourchetteCout(coutMasse),
                  style: _t(
                    TaillesContenu.t12,
                    poids: FontWeight.bold,
                    couleur: AppColors.neutre0,
                  ),
                ),
                const SizedBox.shrink(),
              ],
      ),
    );
  }

  List<Widget> _ligneEmploye({
    required WidgetRef ref,
    required Employe employe,
    required CoutEmployeur? cout,
    required BulletinPaie? bulletin,
    required bool peutEcrire,
    required bool peutArchiver,
    required bool coche,
  }) {
    return [
      // La CELLULE existe toujours (sans quoi la ligne perdrait une colonne et
      // le tableau se décalerait) ; la case, elle, n'est offerte que sur une
      // ligne réellement archivable (l.325-337).
      if (peutArchiver)
        employe.statut == StatutEmploye.parti
            ? const SizedBox(
                width: AppLayout.casePaie,
                height: AppLayout.casePaie,
              )
            : _CaseACocher(
                cle: Key('paie-case-${employe.id}'),
                etiquette: 'Sélectionner cet employé',
                valeur: coche,
                onChanged: (_) => ref
                    .read(selectionPaieProvider.notifier)
                    .basculer(employe.id),
              ),
      _c(
        employe.matricule,
        taille: TaillesContenu.t12,
        couleur: Ardoise.c500,
        mono: true,
      ),
      _CelluleEmploye(employe: employe),
      _CelluleContrat(employe: employe),
      _c(formaterDate(employe.dateEmbauche)),
      if (employe.sansNumeroCnss)
        const _Pastille(
          'absent',
          fond: PaletteMaitre.ambre50,
          texte: PaletteMaitre.ambre700,
          horizontal: AppSpacing.xxs,
        )
      else
        _c(
          employe.numeroCnss!,
          taille: TaillesContenu.t11,
          couleur: Ardoise.c500,
          mono: true,
        ),
      _c(
        formaterFcfa(employe.salaireBase),
        poids: FontWeight.w600,
        couleur: AppColors.navy,
      ),
      // FOURCHETTE, jamais un chiffre unique (PA-53).
      _c(fourchetteCout(cout), taille: TaillesContenu.t12),
      _ActionsEmploye(
        employe: employe,
        bulletin: bulletin,
        peutEcrire: peutEcrire,
        peutArchiver: peutArchiver,
        onEtablir: onEtablir,
        onModifier: onModifier,
        onArchiver: onArchiver,
      ),
    ];
  }
}

/// `w-4 h-4 rounded` (l.306, l.333).
class _CaseACocher extends StatelessWidget {
  const _CaseACocher({
    required this.cle,
    required this.etiquette,
    required this.valeur,
    required this.onChanged,
  });

  final Key cle;
  final String etiquette;
  final bool valeur;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: AppLayout.casePaie,
      height: AppLayout.casePaie,
      child: Checkbox(
        key: cle,
        value: valeur,
        semanticLabel: etiquette,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        onChanged: (v) => onChanged(v ?? false),
      ),
    );
  }
}

/// `text-[12px] px-3 py-1.5 rounded-lg bg-[var(--erreur)] text-white font-bold`
/// (l.292-295).
class _BoutonArchivageLot extends StatelessWidget {
  const _BoutonArchivageLot({required this.nombre, required this.onPressed});

  final int nombre;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: const Key('paie-archiver-selection'),
      onTap: onPressed,
      borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xxs,
        ),
        decoration: BoxDecoration(
          color: AppColors.erreur,
          borderRadius: BorderRadius.circular(AppRadius.roundedLg),
        ),
        child: Text(
          'Archiver la sélection ($nombre)',
          style: _t(
            TaillesContenu.t12,
            poids: FontWeight.bold,
            couleur: AppColors.neutre0,
          ),
        ),
      ),
    );
  }
}

class _CelluleEmploye extends StatelessWidget {
  const _CelluleEmploye({required this.employe});

  final Employe employe;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          employe.nomComplet(),
          style: _t(
            TaillesContenu.t13,
            poids: FontWeight.w600,
            couleur: Ardoise.c800,
          ),
        ),
        Text(
          employe.serviceLibelle == null
              ? employe.poste
              : '${employe.poste} · ${employe.serviceLibelle}',
          style: _t(TaillesContenu.t11, couleur: Ardoise.c400),
        ),
      ],
    );
  }
}

/// Le contrat, et — s'il a une fin — « jusqu’au jj/mm/aaaa » en dessous
/// (l.343-348).
class _CelluleContrat extends StatelessWidget {
  const _CelluleContrat({required this.employe});

  final Employe employe;

  @override
  Widget build(BuildContext context) {
    final fin = employe.dateFinContrat;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          employe.typeContrat?.code ?? tiret,
          style: _t(TaillesContenu.t13, couleur: Ardoise.c600),
        ),
        if (fin != null)
          Text(
            'jusqu’au ${formaterDate(fin)}',
            style: _t(TaillesContenu.t11, couleur: Ardoise.c400),
          ),
      ],
    );
  }
}

class _ActionsEmploye extends StatelessWidget {
  const _ActionsEmploye({
    required this.employe,
    required this.bulletin,
    required this.peutEcrire,
    required this.peutArchiver,
    required this.onEtablir,
    required this.onModifier,
    required this.onArchiver,
  });

  final Employe employe;
  final BulletinPaie? bulletin;
  final bool peutEcrire;
  final bool peutArchiver;
  final void Function(Employe employe) onEtablir;
  final void Function(Employe employe) onModifier;
  final void Function(String? employeId) onArchiver;

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) => _RangeeBoutons(
        children: [
          // Le bouton n'existe QUE si le bulletin existe : un bouton qui
          // n'ouvre rien empêche de savoir si la fonction manque ou si l'écran
          // est cassé.
          if (bulletin != null)
            BoutonLigne(
              cle: Key('paie-voir-bulletin-${employe.id}'),
              libelle: 'Bulletin',
              habit: HabitBoutonLigne.succes,
              onPressed: () => ref
                  .read(bulletinAfficheProvider.notifier)
                  .definir(bulletin!.id),
            )
          else if (peutEcrire)
            BoutonLigne(
              cle: Key('paie-etablir-${employe.id}'),
              libelle: 'Établir',
              onPressed: () => onEtablir(employe),
            ),
          if (peutEcrire)
            BoutonLigne(
              cle: Key('paie-modifier-${employe.id}'),
              libelle: 'Modifier',
              onPressed: () => onModifier(employe),
            ),
          // Absent des lignes déjà parties : l'archivage les refuserait, et un
          // bouton qui ne peut que refuser est un faux bouton (l.371-381).
          if (peutArchiver && employe.statut != StatutEmploye.parti)
            BoutonLigne(
              cle: Key('paie-archiver-${employe.id}'),
              libelle: 'Archiver',
              habit: HabitBoutonLigne.danger,
              onPressed: () => onArchiver(employe.id),
            ),
        ],
      ),
    );
  }
}

/* ====================================================================== */
/* Onglet « Bulletins de paie »                                            */
/* ====================================================================== */

class PanneauBulletins extends ConsumerWidget {
  const PanneauBulletins({
    required this.onGenererManquants,
    required this.onAnnuler,
    super.key,
  });

  final VoidCallback onGenererManquants;
  final void Function(BulletinPaie bulletin) onAnnuler;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bulletins = ref.watch(bulletinsDuMoisProvider).value ?? const [];
    final totaux = ref.watch(totauxLivreProvider).value;
    final manquants = ref.watch(employesSansBulletinProvider).value ?? const [];
    final peutEcrire = ref.watch(peutEcrirePaieProvider);
    final periode = ref.watch(periodeValideProvider);

    final styleTotal = _t(
      TaillesContenu.t13,
      poids: FontWeight.bold,
      couleur: AppColors.neutre0,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (peutEcrire)
          Padding(
            // `flex flex-wrap gap-2 mb-3`.
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Align(
              alignment: Alignment.centerLeft,
              child: InkWell(
                key: const Key('paie-generer-manquants'),
                onTap: onGenererManquants,
                borderRadius: BorderRadius.circular(AppRadius.roundedLg),
                child: Container(
                  // `text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)]
                  // text-white font-semibold`.
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.navy,
                    borderRadius: BorderRadius.circular(AppRadius.roundedLg),
                  ),
                  child: Text(
                    'Générer les bulletins manquants (${manquants.length})',
                    style: _t(
                      TaillesContenu.t13,
                      poids: FontWeight.w600,
                      couleur: AppColors.neutre0,
                    ),
                  ),
                ),
              ),
            ),
          ),
        CartePaie(
          titre: 'Bulletins — ${periode.libelleLong}',
          note: '* hors risques professionnels, taux non confirmé',
          enfant: _TableauPaie(
            vide: _EtatVide(
              titre: 'Aucun résultat',
              detail: 'Aucun bulletin sur ${periode.libelleLong}.',
            ),
            colonnes: const [
              ColonneRestaurant('Matricule'),
              ColonneRestaurant('Employé'),
              ColonneRestaurant('Brut', aDroite: true),
              ColonneRestaurant('CNSS 3,6 %', aDroite: true),
              ColonneRestaurant('ITS', aDroite: true),
              ColonneRestaurant('Autres retenues', aDroite: true),
              ColonneRestaurant('Net à payer', aDroite: true),
              ColonneRestaurant('Charges patronales', aDroite: true),
              ColonneRestaurant('', aDroite: true),
            ],
            clesLignes: [
              for (final b in bulletins) Key('paie-bulletin-${b.id}'),
            ],
            lignes: [
              for (final bulletin in bulletins)
                _ligneBulletin(ref, bulletin, peutEcrire),
            ],
            ligneTotal: totaux == null || totaux.effectif == 0
                ? null
                : [
                    _EtiquetteEtendue(
                      'TOTAL — ${totaux.effectif} bulletin(s)',
                      styleTotal,
                    ),
                    const SizedBox.shrink(),
                    Text(formaterFcfa(totaux.brut), style: styleTotal),
                    Text(formaterFcfa(totaux.cnssSalarie), style: styleTotal),
                    Text(formaterFcfa(totaux.its), style: styleTotal),
                    Text(
                      formaterFcfa(totaux.autresRetenues),
                      style: styleTotal,
                    ),
                    Text(formaterFcfa(totaux.net), style: styleTotal),
                    Text(
                      '${formaterFcfa(totaux.patronalesConfirmees)}*',
                      style: styleTotal,
                    ),
                    const SizedBox.shrink(),
                  ],
          ),
        ),
      ],
    );
  }

  /// Un montant retenu : « — » quand il vaut zéro (`formatOuTiret`, l.446-448).
  String _retenue(int montant) => montant == 0 ? tiret : formaterFcfa(montant);

  List<Widget> _ligneBulletin(
    WidgetRef ref,
    BulletinPaie bulletin,
    bool peutEcrire,
  ) {
    final cellules = <Widget>[
      _c(
        bulletin.employe.matricule,
        taille: TaillesContenu.t11,
        couleur: Ardoise.c500,
        mono: true,
      ),
      _CelluleBulletinEmploye(bulletin: bulletin),
      _c(formaterFcfa(bulletin.brut), poids: FontWeight.w600, couleur: null),
      _c(_retenue(bulletin.cnssSalarie), couleur: PaletteMaitre.rouge600),
      _c(_retenue(bulletin.its), couleur: PaletteMaitre.rouge600),
      _c(_retenue(bulletin.autresRetenues), couleur: PaletteMaitre.rouge600),
      _c(
        formaterFcfa(bulletin.netAPayer),
        poids: FontWeight.bold,
        couleur: AppColors.navy,
      ),
      // L'astérisque N'EST PAS décoratif : il renvoie à « hors risques
      // professionnels, taux non confirmé ». Sans lui, cette colonne se
      // lirait comme un total de charge patronale (PA-53).
      Text.rich(
        TextSpan(
          style: _t(TaillesContenu.t12, couleur: Ardoise.c500),
          children: [
            TextSpan(text: formaterFcfa(bulletin.chargesPatronalesConfirmees)),
            TextSpan(
              text: '*',
              style: _t(TaillesContenu.t12, couleur: PaletteMaitre.ambre600),
            ),
          ],
        ),
      ),
      _RangeeBoutons(
        children: [
          BoutonLigne(
            cle: Key('paie-voir-${bulletin.id}'),
            libelle: 'Voir',
            onPressed: () =>
                ref.read(bulletinAfficheProvider.notifier).definir(bulletin.id),
          ),
          if (peutEcrire && !bulletin.estAnnule)
            BoutonLigne(
              cle: Key('paie-annuler-${bulletin.id}'),
              libelle: 'Annuler',
              onPressed: () => onAnnuler(bulletin),
            ),
        ],
      ),
    ];

    // `opacity-50` sur la ligne d'un bulletin annulé (l.436).
    return bulletin.estAnnule
        ? [for (final c in cellules) Opacity(opacity: 0.5, child: c)]
        : cellules;
  }
}

class _CelluleBulletinEmploye extends StatelessWidget {
  const _CelluleBulletinEmploye({required this.bulletin});

  final BulletinPaie bulletin;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          bulletin.employe.nomComplet(),
          style: _t(
            TaillesContenu.t13,
            poids: FontWeight.w600,
            couleur: Ardoise.c800,
          ),
        ),
        Text(
          bulletin.employe.poste,
          style: _t(TaillesContenu.t11, couleur: Ardoise.c400),
        ),
        if (bulletin.estAnnule)
          Text(
            'Annulé — ${bulletin.motifAnnulation ?? ''}',
            style: _t(TaillesContenu.t11, couleur: PaletteMaitre.rouge600),
          ),
      ],
    );
  }
}

/* ====================================================================== */
/* Onglet « Livre de paie »                                                */
/* ====================================================================== */

class PanneauLivre extends ConsumerWidget {
  const PanneauLivre({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totaux = ref.watch(totauxLivreProvider).value;
    final periode = ref.watch(periodeValideProvider);
    final effectif = totaux?.effectif ?? 0;
    final rubriques = totaux == null || effectif == 0
        ? const <_Rubrique>[]
        : _rubriques(totaux);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CartePaie(
          titre:
              'Livre de paie — ${periode.libelleLong} · $effectif salarié(s)',
          enfant: _TableauPaie(
            vide: _EtatVide(
              titre: 'Aucun résultat',
              detail: 'Aucun bulletin sur ${periode.libelleLong}.',
            ),
            colonnes: const [
              ColonneRestaurant('Rubrique'),
              ColonneRestaurant('Montant', aDroite: true),
            ],
            lignes: [for (final r in rubriques) r.cellules()],
            decorationsLignes: [for (final r in rubriques) r.decoration],
          ),
        ),
        if (totaux != null && totaux.sansNumeroCnss > 0)
          _Encart(
            cle: 'paie-livre-sans-cnss',
            fond: PaletteMaitre.rouge50,
            bordure: PaletteMaitre.rouge200,
            texte: PaletteMaitre.rouge900,
            titre: '${totaux.sansNumeroCnss} salarié(s) sans numéro CNSS.',
            corps:
                'Leur bulletin est calculé, mais ils ne peuvent pas figurer à '
                'la déclaration. Régularisez l’immatriculation avant '
                'l’échéance.',
          ),
        const _EcritureComptableAbsente(),
      ],
    );
  }

  /// Les onze rubriques du maître, dans son ordre (l.499-511).
  ///
  /// ⚠ La ligne « CNSS — risques professionnels » rend une **fourchette**, et
  /// « COÛT TOTAL EMPLOYEUR » aussi. Ce sont les deux endroits du livre où un
  /// montant unique aurait l'air naturel — et c'est exactement pour cela qu'il
  /// n'y en a pas (PA-53).
  List<_Rubrique> _rubriques(TotauxLivre t) => [
    _Rubrique('Salaires bruts soumis à cotisations', formaterFcfa(t.brut)),
    _Rubrique(
      'CNSS — retenue salariale (3,6 %)',
      '− ${formaterFcfa(t.cnssSalarie)}',
      couleurMontant: PaletteMaitre.rouge600,
    ),
    _Rubrique(
      'ITS retenu à la source',
      '− ${formaterFcfa(t.its)}',
      couleurMontant: PaletteMaitre.rouge600,
    ),
    _Rubrique(
      'Autres retenues (avances, oppositions)',
      '− ${formaterFcfa(t.autresRetenues)}',
      couleurMontant: PaletteMaitre.rouge600,
    ),
    _Rubrique(
      'NET À PAYER AUX SALARIÉS',
      formaterFcfa(t.net),
      genre: _GenreRubrique.marine,
    ),
    const _Rubrique('Charges patronales', null, genre: _GenreRubrique.entete),
    _Rubrique(
      'CNSS — pension employeur (6,4 %)',
      formaterFcfa(t.ventilation.pension),
    ),
    _Rubrique(
      'CNSS — prestations familiales (9 %)',
      formaterFcfa(t.ventilation.prestationsFamiliales),
    ),
    _Rubrique(
      'VPS — Versement Patronal sur Salaires (4 %)',
      formaterFcfa(t.ventilation.vps),
    ),
    _Rubrique(
      'CNSS — risques professionnels (1 % à 4 %)',
      '${formaterFcfa(t.fourchette.minimum)} $tiret '
          '${formaterFcfa(t.fourchette.maximum)}',
      couleurMontant: PaletteMaitre.ambre700,
    ),
    _Rubrique(
      'Total charges patronales confirmées',
      formaterFcfa(t.patronalesConfirmees),
      genre: _GenreRubrique.gris,
    ),
    _Rubrique(
      'COÛT TOTAL EMPLOYEUR',
      '${formaterFcfa(t.coutMin)} $tiret ${formaterFcfa(t.coutMax)}',
      genre: _GenreRubrique.marine,
    ),
  ];
}

enum _GenreRubrique { ordinaire, marine, gris, entete }

/// Une ligne du livre : ses quatre habits sont ceux de la vue.
class _Rubrique {
  const _Rubrique(
    this.libelle,
    this.montant, {
    this.genre = _GenreRubrique.ordinaire,
    this.couleurMontant,
  });

  final String libelle;
  final String? montant;
  final _GenreRubrique genre;
  final Color? couleurMontant;

  /// `bg-[var(--navy)] text-white font-bold` ; `bg-slate-100 font-bold` ;
  /// `bg-slate-100 font-bold border-t-2 border-slate-300` ; sinon la bordure
  /// du gabarit (`border-t border-slate-100`).
  BoxDecoration? get decoration => switch (genre) {
    _GenreRubrique.ordinaire => null,
    _GenreRubrique.marine => const BoxDecoration(color: AppColors.navy),
    _GenreRubrique.gris => const BoxDecoration(color: Ardoise.c100),
    _GenreRubrique.entete => const BoxDecoration(
      color: Ardoise.c100,
      border: Border(
        top: BorderSide(color: Ardoise.c300, width: AppSpacing.demi),
      ),
    ),
  };

  List<Widget> cellules() {
    final fort = genre != _GenreRubrique.ordinaire;
    final surMarine = genre == _GenreRubrique.marine;
    final couleur = surMarine
        ? AppColors.neutre0
        : (fort ? null : Ardoise.c700);

    // `py-2.5` sur les lignes marine, `py-2` ailleurs : le gabarit pose py-2,
    // les deux pixels de plus sont ajoutés ici.
    Widget cellule(Widget enfant) => surMarine
        ? Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.demi),
            child: enfant,
          )
        : enfant;

    if (genre == _GenreRubrique.entete) {
      return [
        _EtiquetteEtendue(
          libelle,
          _t(TaillesContenu.t13, poids: FontWeight.bold),
        ),
        const SizedBox.shrink(),
      ];
    }

    return [
      cellule(
        Text(
          libelle,
          style: _t(
            TaillesContenu.t13,
            poids: fort ? FontWeight.bold : null,
            couleur: couleur,
          ),
        ),
      ),
      cellule(
        Text(
          montant ?? '',
          style: _t(
            TaillesContenu.t13,
            poids: fort ? FontWeight.bold : FontWeight.w600,
            couleur: surMarine ? AppColors.neutre0 : couleurMontant,
          ),
        ),
      ),
    ];
  }
}

/// Le squelette du tableau « Écriture comptable proposée », **et son état vide
/// qui nomme le refus**.
///
/// Le maître propose une écriture de paie et un bouton « Comptabiliser la
/// paie ». Vérifié le 31/08/2026 côté serveur : le listener
/// « GenererEcritureDepuisPaie » que la migration RH annonce elle-même n'existe
/// nulle part, et écrire la pièce depuis M13 doublerait le seul point d'entrée
/// d'écriture comptable, où vit l'immuabilité RG-11.
///
/// **Aucune ligne d'écriture n'est inventée** : pas de lignes, pas de badge
/// « Équilibrée », pas de totaux. Les colonnes, elles, sont rendues — un
/// tableau retiré du rendu ferait disparaître la décision en même temps que le
/// signal.
///
/// Le texte est celui de la vue (`livre_ecriture_absente_texte`, l.555-556) :
/// il dit que la paie « se comptabilise depuis l’écran Comptabilité ». Sur ce
/// poste, l'écran Comptabilité ne saisit pas non plus de pièce de paie ; la
/// phrase reste celle de la vue (09/10/2026, à rouvrir avec M10 local).
class _EcritureComptableAbsente extends StatelessWidget {
  const _EcritureComptableAbsente();

  @override
  Widget build(BuildContext context) {
    return CartePaie(
      titre: 'Écriture comptable proposée',
      enfant: _TableauPaie(
        colonnes: const [
          ColonneRestaurant('Compte'),
          ColonneRestaurant('Libellé'),
          ColonneRestaurant('Débit', aDroite: true),
          ColonneRestaurant('Crédit', aDroite: true),
        ],
        lignes: const [],
        vide: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacingLarge.p14,
          ),
          child: Column(
            children: [
              Text(
                'Aucune écriture comptable n’est proposée ici.',
                key: const Key('paie-ecriture-absente'),
                textAlign: TextAlign.center,
                style: _t(
                  TaillesContenu.t13,
                  poids: FontWeight.w600,
                  couleur: Ardoise.c500,
                ),
              ),
              const SizedBox(height: AppSpacing.unit),
              ConstrainedBox(
                // `max-w-[640px] mx-auto`.
                constraints: const BoxConstraints(
                  maxWidth: AppLayout.largeurTexteEtatVidePaie,
                ),
                child: Text(
                  // Note de conception retirée de l'écran le 14/10/2026
                  // (directive du PO) : le listener « GenererEcritureDepuisPaie »
                  // n'existe pas (vérifié le 31/08/2026) et écrire la pièce
                  // depuis M13 doublerait le point d'entrée comptable (RG-11).
                  'La paie se comptabilise depuis l’écran Comptabilité, sur '
                  'les montants de ce livre.',
                  textAlign: TextAlign.center,
                  style: _t(TaillesContenu.t13, couleur: Ardoise.c400),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ====================================================================== */
/* Onglet « Déclarations »                                                 */
/* ====================================================================== */

class PanneauDeclarations extends ConsumerWidget {
  const PanneauDeclarations({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final declarations = ref.watch(declarationsProvider).value ?? const [];
    final totaux = ref.watch(totauxLivreProvider).value;
    final periode = ref.watch(periodeValideProvider);
    final effectif = totaux?.effectif ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CartePaie(
          titre: 'Déclarations sociales et fiscales — ${periode.libelleLong}',
          note: '* hors risques professionnels',
          enfant: _TableauPaie(
            gabarit: gabaritPaieDeclarations,
            vide: _EtatVide(
              titre: 'Aucun résultat',
              detail: 'Aucun bulletin sur ${periode.libelleLong}.',
            ),
            colonnes: const [
              ColonneRestaurant('Déclaration'),
              ColonneRestaurant('Objet'),
              ColonneRestaurant('Montant', aDroite: true),
              ColonneRestaurant('Échéance', aDroite: true),
              ColonneRestaurant('État', aDroite: true),
            ],
            lignes: effectif == 0
                ? const []
                : [for (final declaration in declarations) _ligne(declaration)],
          ),
        ),
        const _EncadreVps(),
      ],
    );
  }

  List<Widget> _ligne(Declaration d) => [
    _c(d.code, poids: FontWeight.bold, couleur: AppColors.navy),
    _CelluleObjet(declaration: d),
    Text.rich(
      TextSpan(
        style: _t(TaillesContenu.t13, poids: FontWeight.w600),
        children: [
          TextSpan(text: formaterFcfa(d.montant)),
          if (!d.complet)
            TextSpan(
              text: '*',
              style: _t(
                TaillesContenu.t13,
                poids: FontWeight.w600,
                couleur: PaletteMaitre.ambre600,
              ),
            ),
        ],
      ),
    ),
    _c(d.echeance == null ? tiret : formaterDate(d.echeance!)),
    // « Incomplet » n'est pas un défaut d'affichage : la CNSS est amputée des
    // risques professionnels, et la présenter comme arrêtée ferait déclarer
    // une cotisation minorée.
    if (d.complet)
      const _Pastille(
        'Montant arrêté',
        fond: PaletteMaitre.emeraude50,
        texte: PaletteMaitre.emeraude700,
      )
    else
      const _Pastille(
        'Incomplet',
        fond: PaletteMaitre.ambre50,
        texte: PaletteMaitre.ambre700,
      ),
  ];
}

class _CelluleObjet extends StatelessWidget {
  const _CelluleObjet({required this.declaration});

  final Declaration declaration;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          declaration.libelle,
          style: _t(TaillesContenu.t13, couleur: Ardoise.c700),
        ),
        Text(
          declaration.note,
          style: _t(TaillesContenu.t11, couleur: Ardoise.c400),
        ),
      ],
    );
  }
}

/// `rounded-xl p-3.5`, fond `#F8FAFC`, bordure `#E2E8F0` (l.611-615).
class _EncadreVps extends StatelessWidget {
  const _EncadreVps();

  @override
  Widget build(BuildContext context) {
    final normal = _t(TaillesContenu.t13, couleur: Ardoise.c700);
    final gras = normal.copyWith(fontWeight: FontWeight.bold);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.smPlus),
      decoration: BoxDecoration(
        color: Ardoise.c50,
        borderRadius: BorderRadius.circular(AppRadius.roundedXl),
        border: Border.all(color: Ardoise.c200),
      ),
      child: Text.rich(
        TextSpan(
          style: normal,
          children: [
            TextSpan(
              text: 'VPS — Versement Patronal sur Salaires.',
              style: gras,
            ),
            const TextSpan(text: ' Taxe directe '),
            TextSpan(text: 'à la charge de l’employeur', style: gras),
            const TextSpan(
              text: ', assise sur le montant total des salaires bruts ',
            ),
            TextSpan(text: 'sans plafond', style: gras),
            const TextSpan(text: '. Taux : '),
            TextSpan(text: '4 %', style: gras),
            const TextSpan(
              text:
                  ' pour les entreprises ordinaires, 2 % pour les structures '
                  'd’enseignement privé — le Gîte relève du taux ordinaire. '
                  'Déclaration et paiement mensuels, au plus tard le ',
            ),
            TextSpan(text: '10 du mois suivant', style: gras),
            const TextSpan(
              text: '. Elle n’est jamais retenue sur le salaire du salarié.',
            ),
          ],
        ),
      ),
    );
  }
}

/* ====================================================================== */
/* Onglet « Barèmes & taux »                                               */
/* ====================================================================== */

class PanneauBareme extends ConsumerWidget {
  const PanneauBareme({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: const [_Simulateur(), _TableauBareme(), _TableauTaux()],
    );
  }
}

/// Le simulateur — il rend le refus **tangible** plutôt que théorique.
/// `bg-white rounded-xl border border-slate-200 p-4 mb-3` (l.622).
class _Simulateur extends ConsumerWidget {
  const _Simulateur();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final simulation = ref.watch(simulationProvider).value;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.neutre0,
        borderRadius: BorderRadius.circular(AppRadius.roundedXl),
        border: Border.all(color: Ardoise.c200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Simulateur',
            style: _t(
              TaillesContenu.t14,
              poids: FontWeight.bold,
              couleur: AppColors.navy,
            ),
          ),
          // `mb-2`.
          const SizedBox(height: AppSpacing.xs),
          const Align(
            alignment: Alignment.centerLeft,
            child: _ChampBrutSimule(),
          ),
          // `mb-3`.
          const SizedBox(height: AppSpacing.sm),
          if (simulation == null)
            const SizedBox.shrink()
          else if (simulation.estRefusee)
            _Encart(
              cle: 'paie-simulateur-refus',
              fond: PaletteMaitre.rouge50,
              bordure: PaletteMaitre.rouge200,
              texte: PaletteMaitre.rouge900,
              titre: 'Calcul refusé.',
              corps: simulation.refus!,
              margeBas: 0,
            )
          else
            _DetailSimulation(simulation: simulation),
        ],
      ),
    );
  }
}

class _ChampBrutSimule extends ConsumerStatefulWidget {
  const _ChampBrutSimule();

  @override
  ConsumerState<_ChampBrutSimule> createState() => _ChampBrutSimuleState();
}

class _ChampBrutSimuleState extends ConsumerState<_ChampBrutSimule> {
  late final TextEditingController _controleur = TextEditingController(
    text: ref.read(brutSimuleProvider).toString(),
  );

  @override
  void dispose() {
    _controleur.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bordure = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      borderSide: const BorderSide(color: Ardoise.c300),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // `block text-[12px] font-semibold text-slate-600 mb-1`.
        Text(
          'Salaire brut mensuel (FCFA)',
          style: _t(
            TaillesContenu.t12,
            poids: FontWeight.w600,
            couleur: Ardoise.c600,
          ),
        ),
        const SizedBox(height: AppSpacing.unit),
        SizedBox(
          // `w-40`.
          width: AppLayout.champBrutSimulePaie,
          child: TextField(
            key: const Key('paie-simulateur-brut'),
            controller: _controleur,
            keyboardType: TextInputType.number,
            style: _t(TaillesContenu.t13),
            decoration: InputDecoration(
              isDense: true,
              // `px-3 py-2` plus la bordure, que la boîte du navigateur
              // compte et pas celle de Flutter.
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm + AppLayout.bordureControle,
                vertical: AppSpacing.xs + AppLayout.bordureControle,
              ),
              border: bordure,
              enabledBorder: bordure,
              focusedBorder: bordure,
            ),
            onChanged: (valeur) {
              // Une saisie illisible ne devient pas zéro en silence : le champ
              // garde la dernière valeur comprise, et rien ne se recalcule.
              final brut = int.tryParse(valeur.trim());
              if (brut != null) {
                ref.read(brutSimuleProvider.notifier).definir(brut);
              }
            },
          ),
        ),
      ],
    );
  }
}

class _DetailSimulation extends StatelessWidget {
  const _DetailSimulation({required this.simulation});

  final Simulation simulation;

  @override
  Widget build(BuildContext context) {
    final retenues = simulation.retenues!;
    final cout = simulation.cout!;

    final blocs = [
      _BlocSimulation(
        titre: 'Retenues salariales',
        lignes: [
          ('CNSS 3,6 %', formaterFcfa(retenues.cnssSalarie)),
          ('Revenu imposable', formaterFcfa(retenues.revenuImposable)),
          ('ITS', formaterFcfa(retenues.its)),
        ],
        total: ('Net à payer', formaterFcfa(retenues.netAPayer)),
      ),
      _BlocSimulation(
        titre: 'Charges patronales confirmées',
        lignes: const [
          ('CNSS pension 6,4 %', null),
          ('Prestations familiales 9 %', null),
          ('VPS 4 %', null),
        ],
        total: ('Total 19,4 %', formaterFcfa(cout.confirmees)),
      ),
      // ⚠ Le troisième bloc est le cœur de PA-53 : il chiffre ce qui
      // MANQUE, au lieu de compléter le total avec une hypothèse.
      _BlocSimulation(
        cle: 'paie-simulateur-manque',
        titre: 'Ce qui manque',
        ambre: true,
        lignes: [
          ('Risques prof. à 1 %', formaterFcfa(cout.rpMin)),
          ('Risques prof. à 4 %', formaterFcfa(cout.rpMax)),
        ],
        total: ('Écart mensuel', formaterFcfa(cout.ecart)),
        // « Écart annuel » : douze fois l'écart mensuel, comme au maître.
        apresTotal: ('Écart annuel', formaterFcfa(cout.ecartAnnuel)),
        pied:
            'Coût employeur entre ${formaterFcfa(cout.coutMin)} et '
            '${formaterFcfa(cout.coutMax)}.',
      ),
    ];

    // `grid-cols-1 md:grid-cols-3 gap-3` : trois colonnes dès 768 px de
    // FENÊTRE, jamais celle du contenu.
    if (MediaQuery.sizeOf(context).width < AppBreakpoints.md) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < blocs.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.sm),
            blocs[i],
          ],
        ],
      );
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < blocs.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSpacing.sm),
            Expanded(child: blocs[i]),
          ],
        ],
      ),
    );
  }
}

/// Un des trois blocs : `border rounded-lg p-3`, titre en `text-[11px]
/// uppercase font-semibold`, lignes en `text-[12px]` (l.638-673).
class _BlocSimulation extends StatelessWidget {
  const _BlocSimulation({
    required this.titre,
    required this.lignes,
    required this.total,
    this.apresTotal,
    this.pied,
    this.ambre = false,
    this.cle,
  });

  final String titre;

  /// Une valeur `null` : la ligne n'en porte pas (`colspan="2"`).
  final List<(String, String?)> lignes;
  final (String, String) total;
  final (String, String)? apresTotal;
  final String? pied;
  final bool ambre;
  final String? cle;

  @override
  Widget build(BuildContext context) {
    final couleurTexte = ambre ? PaletteMaitre.ambre900 : Ardoise.c600;
    final couleurTotal = ambre ? PaletteMaitre.rouge900 : AppColors.navy;

    Widget ligne(String libelle, String? valeur) => Row(
      children: [
        Expanded(
          child: Text(
            libelle,
            style: _t(TaillesContenu.t12, couleur: couleurTexte),
          ),
        ),
        if (valeur != null)
          Text(
            valeur,
            style: _t(
              TaillesContenu.t12,
              couleur: ambre ? couleurTexte : Ardoise.c600,
            ),
          ),
      ],
    );

    return Container(
      key: cle == null ? null : Key(cle!),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: ambre ? PaletteMaitre.ambre50 : null,
        borderRadius: BorderRadius.circular(AppRadius.roundedLg),
        border: Border.all(
          color: ambre ? PaletteMaitre.ambre200 : Ardoise.c200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            titre.toUpperCase(),
            style: _t(
              TaillesContenu.t11,
              poids: FontWeight.w600,
              couleur: ambre ? PaletteMaitre.ambre900 : Ardoise.c400,
            ),
          ),
          // `mt-1.5`.
          const SizedBox(height: AppSpacing.xxs),
          for (final l in lignes) ligne(l.$1, l.$2),
          Container(
            // `border-t border-slate-200` ; `pt-1` sur les deux cellules.
            padding: const EdgeInsets.only(top: AppSpacing.unit),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: ambre ? PaletteMaitre.ambre200 : Ardoise.c200,
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    total.$1,
                    style: _t(
                      TaillesContenu.t12,
                      poids: FontWeight.bold,
                      couleur: couleurTotal,
                    ),
                  ),
                ),
                Text(
                  total.$2,
                  style: _t(
                    TaillesContenu.t12,
                    poids: FontWeight.bold,
                    couleur: couleurTotal,
                  ),
                ),
              ],
            ),
          ),
          if (apresTotal != null)
            Row(
              children: [
                Expanded(
                  child: Text(
                    apresTotal!.$1,
                    style: _t(
                      TaillesContenu.t12,
                      poids: FontWeight.bold,
                      couleur: couleurTotal,
                    ),
                  ),
                ),
                Text(
                  apresTotal!.$2,
                  style: _t(
                    TaillesContenu.t12,
                    poids: FontWeight.bold,
                    couleur: couleurTotal,
                  ),
                ),
              ],
            ),
          if (pied != null) ...[
            // `mt-1.5`.
            const SizedBox(height: AppSpacing.xxs),
            Text(
              pied!,
              style: _t(TaillesContenu.t10, couleur: PaletteMaitre.ambre900),
            ),
          ],
        ],
      ),
    );
  }
}

/// Le barème ITS, **et son refus rendu comme une ligne du tableau**.
class _TableauBareme extends ConsumerWidget {
  const _TableauBareme();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bareme = ref.watch(baremeAfficheProvider).value ?? const [];
    final refus = _t(
      TaillesContenu.t13,
      poids: FontWeight.w600,
      couleur: PaletteMaitre.rouge900,
    );

    return CartePaie(
      titre: 'Barème ITS / IR-PTS — progressif par tranches',
      enfant: _TableauPaie(
        colonnes: const [
          ColonneRestaurant('Tranche de revenu imposable'),
          ColonneRestaurant('Taux', aDroite: true),
          ColonneRestaurant('Impôt maximal de la tranche', aDroite: true),
          ColonneRestaurant('Cumul', aDroite: true),
        ],
        lignes: [
          for (final ligne in bareme)
            [
              _c(
                'de ${formaterFcfa(ligne.tranche.plancher)} à '
                '${formaterFcfa(ligne.tranche.plafond)}',
                couleur: Ardoise.c700,
              ),
              _c(
                '${ligne.tranche.taux} %',
                poids: FontWeight.w600,
                couleur: null,
              ),
              _c(
                ligne.maximum == 0 ? tiret : formaterFcfa(ligne.maximum),
                couleur: null,
              ),
              _c(formaterFcfa(ligne.cumul), couleur: Ardoise.c500),
            ],
          // LE REFUS, rendu comme une ligne du barème : deux sources divergent
          // sur le haut de barème (PA-53). Le retirer du tableau ferait croire
          // que le barème s'arrête naturellement à 500 000 F.
          [
            Text(
              'au-delà de '
              '${formaterFcfa(CalculPaieService.plafondItsConfirme)}',
              key: const Key('paie-bareme-refus'),
              style: refus,
            ),
            Text('non tranché', style: refus),
            const SizedBox.shrink(),
            _EtiquetteEtendue(
              'Calcul refusé — deux sources divergent sur le haut de barème',
              _t(TaillesContenu.t13, couleur: PaletteMaitre.rouge900),
              droite: true,
            ),
          ],
        ],
        decorationsLignes: [
          for (var i = 0; i < bareme.length; i++) null,
          // `border-t-2 border-red-300` sur fond `#FEF2F2`.
          const BoxDecoration(
            color: PaletteMaitre.rouge50,
            border: Border(
              top: BorderSide(
                color: PaletteMaitre.rouge300,
                width: AppSpacing.demi,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Les taux appliqués — **la colonne « Source » est le cœur de PA-53**.
class _TableauTaux extends StatelessWidget {
  const _TableauTaux();

  static const _confirme = _Pastille(
    'confirmé',
    fond: PaletteMaitre.emeraude50,
    texte: PaletteMaitre.emeraude700,
  );

  @override
  Widget build(BuildContext context) {
    Widget prelevement(String libelle) => _c(libelle, couleur: Ardoise.c700);
    Widget taux(String valeur) =>
        _c(valeur, poids: FontWeight.w600, couleur: null);
    Widget charge(String valeur) => _c(valeur);
    Widget base(String valeur) => _c(valeur, taille: TaillesContenu.t12);

    final rouge = _t(
      TaillesContenu.t13,
      poids: FontWeight.w600,
      couleur: PaletteMaitre.rouge900,
    );

    return CartePaie(
      titre: 'Taux appliqués',
      enfant: _TableauPaie(
        colonnes: const [
          ColonneRestaurant('Prélèvement'),
          ColonneRestaurant('Taux', aDroite: true),
          ColonneRestaurant('À la charge de', aDroite: true),
          ColonneRestaurant('Base', aDroite: true),
          ColonneRestaurant('Source', aDroite: true),
        ],
        lignes: [
          [
            prelevement('CNSS — pension'),
            taux('CNSS 3,6 %'),
            charge('Salarié'),
            base('Salaire brut'),
            _confirme,
          ],
          [
            prelevement('ITS / IR-PTS'),
            taux('barème progressif'),
            charge('Salarié'),
            base('Brut − CNSS salarié'),
            _confirme,
          ],
          [
            prelevement('CNSS — pension'),
            taux('CNSS pension 6,4 %'),
            charge('Employeur'),
            base('Salaire brut'),
            _confirme,
          ],
          [
            prelevement('CNSS — prestations familiales'),
            taux('Prestations familiales 9 %'),
            charge('Employeur'),
            base('Salaire brut'),
            _confirme,
          ],
          [
            prelevement('VPS — Versement Patronal sur Salaires'),
            taux('VPS 4 %'),
            charge('Employeur'),
            base('Brut total, sans plafond'),
            _confirme,
          ],
          // La seule ligne rouge du tableau, et la raison d'être de l'écran.
          [
            Text(
              'CNSS — risques professionnels',
              key: const Key('paie-taux-rp'),
              style: rouge,
            ),
            Text('1 % à 4 %', style: rouge),
            charge('Employeur'),
            base('Salaire brut'),
            const _Pastille(
              'non confirmé',
              fond: PaletteMaitre.rouge100,
              texte: PaletteMaitre.rouge800,
              gras: true,
            ),
          ],
        ],
        decorationsLignes: const [
          null,
          null,
          null,
          null,
          null,
          BoxDecoration(
            color: PaletteMaitre.rouge50,
            border: Border(top: BorderSide(color: Ardoise.c100)),
          ),
        ],
      ),
    );
  }
}

/* ====================================================================== */
/* Encart partagé                                                          */
/* ====================================================================== */

/// Un encart coloré : `rounded-xl p-3.5`, titre en gras puis texte, couleurs
/// posées en `style` (l.524-529, l.633-635).
class _Encart extends StatelessWidget {
  const _Encart({
    required this.cle,
    required this.fond,
    required this.bordure,
    required this.texte,
    required this.titre,
    required this.corps,
    this.margeBas,
  });

  final String cle;
  final Color fond;
  final Color bordure;
  final Color texte;
  final String titre;
  final String corps;

  /// `null` : `mb-4`, comme la vue hors d'une carte.
  final double? margeBas;

  @override
  Widget build(BuildContext context) {
    final contenu = Text.rich(
      TextSpan(
        style: _t(TaillesContenu.t13, couleur: texte),
        children: [
          TextSpan(
            text: titre,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          TextSpan(text: ' $corps'),
        ],
      ),
    );

    if (margeBas == 0) {
      return Container(
        key: Key(cle),
        padding: const EdgeInsets.all(AppSpacing.smPlus),
        decoration: BoxDecoration(
          color: fond,
          borderRadius: BorderRadius.circular(AppRadius.roundedXl),
          border: Border.all(color: bordure),
        ),
        child: contenu,
      );
    }

    return KeyedSubtree(
      key: Key(cle),
      child: EncadreCarte(fond: fond, bordure: bordure, enfant: contenu),
    );
  }
}
