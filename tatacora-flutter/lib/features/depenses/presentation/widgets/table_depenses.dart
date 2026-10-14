// Vue Blade maîtresse (PA-183) : pwa/depenses/depenses.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/format/formats.dart';
import '../../../../core/rbac/garde_acces.dart';
import '../../../../core/di/providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../restaurant/presentation/widgets/corps_carte_commun.dart'
    show styleContenuCarte;
import '../../../restaurant/presentation/widgets/tableau_restaurant.dart';
import '../../domain/entities/depense.dart';
import '../providers_depenses.dart';

/// Le libellé du bouton de rattrapage — `rattrapage_action` de
/// `lang/fr/depenses_pwa.php` (vue l.294), confronté au traducteur PHP.
const String libelleComptabiliser = 'Comptabiliser';

/// Le tableau à **sept colonnes** de la vue (l.246-304).
///
/// ## Un troisième gabarit, parce que la vue en pose un troisième
///
/// En-tête `bg-[var(--navy)] text-[11px] uppercase tracking-wide text-white/90`
/// **et** cellules `px-4 py-2.5`, lignes en `border-t border-slate-100`. Ce
/// n'est ni le gabarit `carte` (en-tête `slate-50`, cellules `px-3`) ni le
/// gabarit `crud` (cellules `px-4 py-3`, bordure en bas). Les y ramener serait
/// approximer, ce que l'Article 1 interdit nommément — deux pixels de
/// rembourrage vertical et une bordure du mauvais côté.
///
/// ## L'en-tête reste quand il n'y a rien à lister
///
/// La vue pose son `<thead>` hors de la boucle (l.248-256) : l'état vide est une
/// ligne `colspan="7"` SOUS les sept en-têtes (l.291-300). Les masquer quand la
/// liste est vide supprimait sept éléments de la page.
class TableDepenses extends ConsumerWidget {
  const TableDepenses({
    super.key,
    required this.depenses,
    required this.filtre,
  });

  /// `null` tant que la base n'a pas répondu — distinct d'une liste vide.
  final List<Depense>? depenses;

  /// Vrai quand au moins un filtre est posé : les deux états vides de la vue
  /// appellent des gestes **opposés** — saisir une dépense, ou élargir le
  /// filtre. Un message unique enverrait la moitié des lecteurs au mauvais.
  final bool filtre;

  /// En-tête navy, cellules `px-4 py-2.5`, bordure en haut.
  static const GabaritTableau gabarit = GabaritTableau(
    enteteFond: AppColors.navy,
    entete: _enteteColonne,
    cellule: EdgeInsets.symmetric(
      // `px-4` — 16 px.
      horizontal: AppSpacing.md,
      // `py-2.5` — 10 px, l'espacement le plus employé du maître.
      vertical: AppSpacing.xsPlus,
    ),
    enBas: false,
  );

  /// `text-[11px] uppercase tracking-wide text-white/90 font-semibold` (l.248),
  /// interligne 1,5 comme tout `<main>`.
  static const TextStyle _enteteColonne = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: TaillesContenu.t11,
    fontWeight: FontWeight.w600,
    height: AppLayout.interligneContenu,
    letterSpacing: TaillesContenu.t11 * AppTextStyles.suiviLarge,
    color: AppColors.blanc90,
  );

  /// Les sept colonnes, dans l'ordre et au mot de la vue (l.249-255).
  static const colonnes = [
    ColonneRestaurant('Date'),
    ColonneRestaurant('Libellé'),
    ColonneRestaurant('Nature'),
    ColonneRestaurant('Charge (SYSCOHADA)'),
    ColonneRestaurant('Trésorerie'),
    ColonneRestaurant('Montant', aDroite: true),
    ColonneRestaurant('Pièces'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lignes = depenses;

    if (lignes == null) {
      return const Padding(
        key: Key('depenses-chargement'),
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final secondaire = styleContenuCarte(
      TaillesContenu.t13,
      couleur: Ardoise.c500,
    );
    final libelles = ref.watch(libellesComptesProvider);

    return TableauRestaurant(
      gabarit: gabarit,
      colonnes: colonnes,
      // `<table class="w-full">` dans un cadre `overflow-hidden` (l.205-247).
      pleineLargeur: true,
      repartitionProportionnelle: true,
      videSousEntete: true,
      vide: _Vide(filtre: filtre),
      clesLignes: [for (final d in lignes) Key('depense-${d.id}')],
      lignes: [
        for (final d in lignes)
          [
            Text(formaterDate(d.dateTransaction), style: secondaire),
            Text(
              d.libelle,
              style: styleContenuCarte(
                TaillesContenu.t13,
                poids: FontWeight.w600,
                couleur: Ardoise.c700,
              ),
            ),
            Text(d.naturesAffichees, style: secondaire),
            // La vue empile un compte PAR LIGNE, sans les fondre : une dépense
            // à trois achats sur deux comptes doit montrer les deux.
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final l in d.lignes)
                  Text.rich(
                    TextSpan(
                      style: secondaire,
                      children: [
                        // `font-mono-tatacora` (l.265).
                        TextSpan(
                          text: l.compteCharge,
                          style: const TextStyle(
                            fontFamily: AppTextStyles.policeMonospace,
                          ),
                        ),
                        TextSpan(
                          text:
                              ' · ${libelles.de(l.compteCharge) ?? tiretAbsence}',
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            Text(
              // « — » quand la trésorerie n'a pas de libellé au registre.
              d.tresorerie?.libelle ?? tiretAbsence,
              style: secondaire,
            ),
            Text(
              formaterFcfa(d.montantTotal),
              style: styleContenuCarte(
                TaillesContenu.t13,
                poids: FontWeight.w600,
                // Aucune classe de couleur à la vue (l.270) : le texte du
                // `<body>`, `--texte`.
                couleur: AppColors.anthracite,
              ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
            ),
            _Pieces(depense: d),
          ],
      ],
    );
  }
}

/// La colonne « Pièces » (l.271-288).
///
/// ## Trois choses y vivent, et la troisième n'est pas à la vue
///
/// 1. La pastille « sans reçu » de la vue est rendue, et elle est **vraie pour
///    toutes les lignes** : aucun reçu ne peut être joint sur ce poste, faute de
///    sélecteur de fichier. Elle n'est donc pas un état parmi deux, et son
///    infobulle le dit — sinon « sans reçu » se lirait comme un oubli de saisie
///    réparable, et quelqu'un chercherait où joindre la photo.
/// 2. Une dépense SANS pièce comptable porte la pastille rouge « non
///    comptabilisée » et le bouton « Comptabiliser » (vue l.283-287, rendus
///    depuis la v16 : le poste a maintenant un moteur comptable). Le bouton
///    lance `DepenseDao.comptabiliser`, geste EXPLICITE, jamais automatique ; il
///    n'apparaît qu'avec le droit d'écriture sur M10 (la vue le montre à tous et
///    refuse au clic : ici un bouton qui ne produirait qu'un refus est omis).
/// 3. Une dépense comptabilisée montre le NUMÉRO DE PIÈCE du moteur
///    (`CAI-2026-00007`). **ÉCART DÉLIBÉRÉ — `depenses.blade.php` l.268-290** :
///    la vue ne montre aucun numéro de pièce. Ici : une pastille neutre en
///    police à chasse fixe. Raison (10/10/2026, demande du lead du lot) : c'est
///    la seule trace visible qu'une pièce existe, et la référence que le
///    Comptable cherchera au grand livre. Elle est LUE de l'écriture
///    ([Depense.numeroPiece]), jamais recopiée sur la dépense.
class _Pieces extends ConsumerWidget {
  const _Pieces({required this.depense});

  final Depense depense;

  /// L'infobulle de la pastille — testée au mot près.
  static const String infobulle =
      'Aucun reçu ne peut être joint sur ce poste : aucun sélecteur de '
      'fichier n’est embarqué dans ce client. La pastille est donc vraie '
      'pour toutes les lignes, ce n’est pas un état parmi deux.';

  /// L'infobulle de « non comptabilisée » quand aucun rattrapage n'a encore
  /// été tenté : sans elle, la pastille serait muette sur son origine.
  static const String infobulleSansPiece =
      'Cette dépense a été saisie avant que ce poste tienne une comptabilité : '
      'aucune pièce comptable n’existe pour elle. « Comptabiliser » en passe '
      'une.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final peutEcrire = ref
        .watch(droitsProvider)
        .peutEcrire(ModuleTatacora.m10Comptabilite);

    return ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: AppLayout.largeurMaxPiecesDepense,
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.unit,
        runSpacing: AppSpacing.unit,
        children: [
          const Tooltip(
            message: infobulle,
            child: _Badge(
              key: Key('depenses-sans-recu'),
              texte: 'sans reçu',
              fond: PaletteMaitre.ambre50,
              couleur: PaletteMaitre.ambre700,
            ),
          ),
          if (depense.estComptabilisee)
            _Badge(
              key: Key('depense-piece-${depense.id}'),
              texte: depense.numeroPiece ?? tiretAbsence,
              fond: Ardoise.c100,
              couleur: Ardoise.c600,
              monospace: true,
            )
          else ...[
            Tooltip(
              message: depense.ecritureRefus ?? infobulleSansPiece,
              child: _Badge(
                key: Key('depense-sans-piece-${depense.id}'),
                texte: 'non comptabilisée',
                fond: PaletteMaitre.rouge50,
                couleur: PaletteMaitre.rouge700,
              ),
            ),
            if (peutEcrire)
              InkWell(
                key: Key('depense-comptabiliser-${depense.id}'),
                borderRadius: BorderRadius.circular(AppRadius.rounded),
                onTap: () => comptabiliserLaDepense(ref, depense),
                child: Container(
                  // `px-2 py-0.5` — 8 px et 2 px.
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: AppSpacing.demi,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.navy,
                    borderRadius: BorderRadius.circular(AppRadius.rounded),
                  ),
                  child: Text(
                    libelleComptabiliser,
                    style: styleContenuCarte(
                      TaillesContenu.t11,
                      poids: FontWeight.w600,
                      couleur: AppColors.neutre0,
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// `text-[11px] px-2 py-0.5 rounded` (l.64) — la pastille de la colonne
/// « Pièces », sans graisse particulière.
class _Badge extends StatelessWidget {
  const _Badge({
    super.key,
    required this.texte,
    required this.fond,
    required this.couleur,
    this.monospace = false,
  });

  final String texte;
  final Color fond;
  final Color couleur;

  /// Le numéro de pièce se lit en chasse fixe (`font-mono-tatacora`).
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    return Container(
      // `px-2 py-0.5` — 8 px et 2 px.
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.demi,
      ),
      decoration: BoxDecoration(
        color: fond,
        borderRadius: BorderRadius.circular(AppRadius.rounded),
      ),
      child: Text(
        texte,
        style: styleContenuCarte(TaillesContenu.t11, couleur: couleur).copyWith(
          fontFamily: monospace ? AppTextStyles.policeMonospace : null,
        ),
      ),
    );
  }
}

/// Les DEUX états vides de la vue (l.290-300) — ils appellent des gestes
/// opposés, et le lien « Tout afficher » n'accompagne que le second.
class _Vide extends ConsumerWidget {
  const _Vide({required this.filtre});

  final bool filtre;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // `text-[13px] text-slate-400` (l.292).
    final style = styleContenuCarte(TaillesContenu.t13, couleur: Ardoise.c400);

    return Container(
      alignment: Alignment.center,
      // `px-4 py-10` — 40 px.
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xlPlus,
      ),
      child: filtre
          ? Text.rich(
              key: const Key('depenses-vide-filtre'),
              textAlign: TextAlign.center,
              TextSpan(
                style: style,
                children: [
                  const TextSpan(
                    text: 'Aucune dépense ne correspond à ces filtres. ',
                  ),
                  // Le lien « Tout afficher » (l.295) : `font-semibold
                  // underline`, dans la couleur du texte qui le porte.
                  WidgetSpan(
                    alignment: PlaceholderAlignment.baseline,
                    baseline: TextBaseline.alphabetic,
                    child: InkWell(
                      key: const Key('depenses-tout-afficher'),
                      onTap: () => ref
                          .read(filtreDepensesProvider.notifier)
                          .reinitialiser(),
                      child: Text(
                        'Tout afficher',
                        style: style.copyWith(
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            )
          : Text(
              'Aucune dépense enregistrée. Le bouton « Nouvelle Dépense » '
              'ouvre la saisie.',
              key: const Key('depenses-vide'),
              textAlign: TextAlign.center,
              style: style,
            ),
    );
  }
}
