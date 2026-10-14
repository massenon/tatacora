// Vue Blade maîtresse (PA-183) : pwa/depenses/depenses.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../shared_widgets/bouton_standard.dart';
import '../../../../shared_widgets/modale_export.dart';
import '../../../../shared_widgets/toast_export.dart';
import '../../../restaurant/presentation/widgets/corps_carte_commun.dart'
    show styleContenuCarte;
import '../../domain/categories_depense.dart';
import '../../domain/entities/depense.dart';
import '../../impression/etat_depenses.dart';
import '../providers_depenses.dart';

/// La barre de contrôles de la vue (l.206-244) : recherche, « À partir du »,
/// « Jusqu'au », trésorerie, catégorie, « Réinitialiser », puis « Exporter »
/// poussé à droite par le `<div class="flex-1">` de la vue (l.233).
///
/// Le cadre — `px-4 py-3 border-b border-slate-200 flex flex-wrap items-center
/// gap-2` (l.206) — est posé ICI : la bordure du bas appartient à la barre, pas
/// au tableau qui la suit.
///
/// ## Les deux listes sont des `DropdownButton`, pas des `…FormField`
///
/// Un `DropdownButtonFormField` garde sa valeur dans l'état du `FormField` :
/// « Réinitialiser » remettrait le filtre à vide **sans que la liste change
/// d'étiquette**, et l'écran montrerait la liste entière sous un filtre qui dit
/// encore « Caisse ». Le `DropdownButton` rend exactement la valeur qu'on lui
/// donne — ici celle du provider, seule source.
///
/// ## « Exporter » ouvre la modale de FORMAT de la vue
///
/// `ouvrirExport` → partiel `modale-export` (l.515-517) : le choix PDF / tableur
/// se fait dans la modale partagée, comme sur les cartes. Voir [exporter] pour
/// ce que chaque choix produit sur ce poste.
class BarreFiltresDepenses extends ConsumerStatefulWidget {
  const BarreFiltresDepenses({super.key, required this.depenses});

  /// La liste **affichée** — c'est elle que l'export emporte (PA-119).
  final List<Depense>? depenses;

  /// Le titre de la modale d'export, au mot de la vue (`export_titre`).
  static const String titreExport = 'Exporter — Dépenses';

  /// Ce que dit le poste quand « PDF Officiel A4 Imprimable » est choisi.
  ///
  /// ÉCART DÉLIBÉRÉ — `depenses.blade.php` l.515-517 (partiel
  /// `pwa/partials/modale-export.blade.php`).
  /// La vue : le choix PDF produit un document A4 avec en-tête et signatures.
  /// Ici : le choix est OFFERT, comme dans la vue, mais il ne produit aucun
  /// fichier et le dit. Seul le tableur (CSV) est écrit.
  /// Raison (09/10/2026) : tout document A4 de ce client passe par
  /// `core/impression/entete_a4.dart` et ses visas, relus contre les gabarits
  /// serveur (`pdf_directive_test.dart`) ; cet état n'y est pas classé, et
  /// recopier une impression dans l'écran serait la non-conformité n° 1 de
  /// `RESPECT_TABLEAU_RAPPORT.md` §4. Retirer le choix PDF de la modale
  /// l'écarterait de la vue ; le produire sans visas serait un faux document.
  /// Un choix qui ne dit rien serait un bouton inerte (Directive, article 3.3).
  ///
  /// ÉCART DÉLIBÉRÉ n° 2 — décision du Lead (D26, 09/10/2026).
  /// La vue : le partiel présélectionne le PDF (`$formatExport = 'pdf'`,
  /// `EcranDeCarte` l.183 pour les cartes).
  /// Ici : la modale présélectionne le TABLEUR, le seul format réellement
  /// produit, et une ligne d'aide dit avant le clic que le PDF ne l'est pas.
  /// Raison : un clic naïf sur « Générer & Télécharger » n'aboutit pas à un
  /// refus. Les cartes du bar et du restaurant gardent le PDF par défaut.
  /// À remonter au Product Owner : le vrai PDF A4 (en-tête `entete_a4`, visas)
  /// est un arbitrage ouvert (PA-192) ; il n'est pas implémenté ici.
  static const String pdfNonProduit =
      'Le PDF de la dépense courante n’est pas produit sur ce poste : aucun '
      'état A4 de cet écran n’est classé dans l’en-tête et les visas de '
      'l’application. Rien n’a été écrit. Choisissez « Tableur Excel » pour '
      'obtenir la liste affichée en CSV.';

  /// La ligne d'aide posée sous les deux choix de la modale, AVANT le clic.
  static const String aidePdf =
      'Le PDF n’est pas produit sur ce poste : seul le tableur (CSV) est '
      'écrit.';

  @override
  ConsumerState<BarreFiltresDepenses> createState() =>
      _BarreFiltresDepensesState();
}

class _BarreFiltresDepensesState extends ConsumerState<BarreFiltresDepenses> {
  final _terme = TextEditingController();

  @override
  void dispose() {
    _terme.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtre = ref.watch(filtreDepensesProvider);
    final notifier = ref.read(filtreDepensesProvider.notifier);

    return Container(
      // `px-4 py-3 border-b border-slate-200` (l.206).
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Ardoise.c200)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // `flex-1` (l.233) : tout ce qui précède se range à gauche, et
          // « Exporter » reste à droite.
          Expanded(
            // `flex flex-wrap items-center gap-2` — 8 px.
            child: Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: AppLayout.rechercheDepenses,
                  child: TextField(
                    key: const Key('depenses-recherche'),
                    controller: _terme,
                    style: _texteChamp,
                    decoration: InputDecoration(
                      // L'invite de la vue, au mot (l.207).
                      hintText: 'Libellé, nature, compte…',
                      hintStyle: _texteChamp.copyWith(color: Ardoise.c400),
                      isDense: true,
                      // `px-3 py-1.5` + la bordure de 1 px, que Flutter ne
                      // compte pas dans le remplissage.
                      contentPadding: _remplissageChamp,
                      enabledBorder: _bordureChamp,
                      focusedBorder: _bordureChamp,
                    ),
                    onChanged: notifier.definirTerme,
                  ),
                ),

                // Les deux `<input type="date">` de la vue (l.209-210). Leurs
                // `title` — « À partir du », « Jusqu'au » — deviennent
                // l'étiquette visible : une infobulle de survol n'existe pas
                // au doigt, et un bouton de date sans étiquette ne dit pas
                // laquelle des deux bornes il porte.
                _ChampDate(
                  cle: const Key('depenses-du'),
                  etiquette: 'À partir du',
                  valeur: filtre.du,
                  onChoix: notifier.definirDu,
                ),
                _ChampDate(
                  cle: const Key('depenses-au'),
                  etiquette: 'Jusqu\'au',
                  valeur: filtre.au,
                  onChoix: notifier.definirAu,
                ),

                _Liste<TresorerieDepense>(
                  cle: const Key('depenses-tresorerie'),
                  largeur: AppLayout.filtreTresorerieDepenses,
                  valeur: filtre.tresorerie,
                  // Le libellé de l'option vide EST celui de la vue (l.213).
                  videLibelle: 'Toute trésorerie',
                  options: {
                    for (final t in TresorerieDepense.values) t: t.libelle,
                  },
                  onChoix: notifier.definirTresorerie,
                ),
                _Liste<FamilleDepense>(
                  cle: const Key('depenses-famille'),
                  largeur: AppLayout.filtreCategorieDepenses,
                  valeur: filtre.famille,
                  videLibelle: 'Toute catégorie',
                  // La vue liste les CLÉS de son registre, c'est-à-dire les
                  // deux familles — jamais les douze natures (l.221-223).
                  options: {
                    for (final f in FamilleDepense.values) f: f.libelle,
                  },
                  onChoix: notifier.definirFamille,
                ),

                // « Réinitialiser » est un LIEN, pas une action protégée :
                // vider un filtre est une lecture, et l'exiger derrière un
                // droit d'écriture empêcherait un profil en consultation de
                // revenir à la liste entière (la vue le dit en toutes
                // lettres, l.226-229).
                TextButton(
                  key: const Key('depenses-reinitialiser'),
                  style: TextButton.styleFrom(
                    // `px-2` (l.231).
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () {
                    _terme.clear();
                    notifier.reinitialiser();
                  },
                  child: Text(
                    'Réinitialiser',
                    style: styleContenuCarte(
                      TaillesContenu.t12,
                      poids: FontWeight.w600,
                      couleur: Ardoise.c500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          // `text-[12px] px-3 py-1.5 border` (l.243) — bouton standard
          // compact (PO, 14/10/2026).
          BoutonStandard(
            key: const Key('depenses-exporter'),
            libelle: 'Exporter',
            compact: true,
            margeVerticale: AppSpacing.xxs,
            onPressed: () => exporter(context, ref, widget.depenses),
          ),
        ],
      ),
    );
  }

  /// `text-[13px]` d'un champ de la barre (l.207-224).
  static final TextStyle _texteChamp = styleContenuCarte(
    TaillesContenu.t13,
    couleur: Ardoise.c700,
  );

  /// `px-3 py-1.5` (l.208 et l.243) plus la bordure, que la boîte du
  /// navigateur compte et pas celle de Flutter.
  static const EdgeInsets _remplissageChamp = EdgeInsets.symmetric(
    horizontal: AppSpacing.sm + AppLayout.bordureControle,
    vertical: AppSpacing.xxs + AppLayout.bordureControle,
  );

  /// `border border-slate-300 rounded-lg` (l.208).
  static final OutlineInputBorder _bordureChamp = OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadius.roundedLg),
    borderSide: const BorderSide(color: Ardoise.c300),
  );

  /// « Exporter » : la modale de format de la vue, puis le document.
  ///
  /// L'export porte sur CE QUI EST AFFICHÉ, et il DIT son filtre (PA-119).
  /// Une liste vide se **refuse** : un fichier sans ligne se lirait « aucune
  /// dépense », alors qu'il veut dire « le filtre n'a rien retenu ».
  ///
  /// - **Tableur Excel** : le CSV (BOM UTF-8, point-virgule), écrit par
  ///   `exporterDepensesProvider`, chemin affiché.
  /// - **PDF Officiel A4** : [BarreFiltresDepenses.pdfNonProduit].
  static Future<void> exporter(
    BuildContext context,
    WidgetRef ref,
    List<Depense>? lignes,
  ) async {
    final format = await choisirFormatExport(
      context,
      titre: BarreFiltresDepenses.titreExport,
      aide: BarreFiltresDepenses.aidePdf,
    );
    if (format == null || !context.mounted) return;

    // Le refus du PDF passe avant celui de la liste vide : il ne dépend pas
    // des lignes, et le dire d'abord évite d'envoyer élargir un filtre pour
    // un document qu'aucun filtre ne produira.
    if (format == FormatExport.pdf) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            BarreFiltresDepenses.pdfNonProduit,
            key: Key('depenses-export-pdf-absent'),
          ),
        ),
      );
      return;
    }

    if (lignes == null || lignes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          key: Key('depenses-export-vide'),
          content: Text(
            'La liste filtrée est vide : il n’y a rien à exporter. Élargissez '
            'la période ou retirez un filtre.',
          ),
        ),
      );
      return;
    }

    final filtre = ref.read(filtreDepensesProvider);
    final etat = EtatDepenses(
      lignes: lignes,
      portee: filtre.description,
      libelles: ref.read(libellesComptesProvider),
    );
    // La fenêtre « Enregistrer sous », puis le toast commun (14/10/2026).
    await executerExport(
      context,
      () => ref.read(exporterDepensesProvider)(etat),
      cleSucces: const Key('depenses-export-fait'),
    );
  }
}

/// Une borne de date — le `<input type="date">` de la vue, au gabarit de la
/// barre : `border border-slate-300 rounded-lg px-2.5 py-1.5`.
class _ChampDate extends StatelessWidget {
  const _ChampDate({
    required Key cle,
    required this.etiquette,
    required this.valeur,
    required this.onChoix,
  }) : super(key: cle);

  final String etiquette;
  final DateTime? valeur;
  final ValueChanged<DateTime?> onChoix;

  @override
  Widget build(BuildContext context) {
    final d = valeur;

    return SizedBox(
      width: AppLayout.champDateDepenses,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.roundedLg),
        onTap: () async {
          final choisi = await showDatePicker(
            context: context,
            initialDate: d ?? DateTime.now(),
            // Une dépense passée se consulte loin en arrière ; rien ne se
            // saisit très en avant, mais la borne haute reste large plutôt que
            // d'interdire une saisie légitime de fin d'exercice.
            firstDate: DateTime(DateTime.now().year - 5),
            lastDate: DateTime(DateTime.now().year + 1),
          );
          if (choisi == null) return;
          onChoix(choisi);
        },
        child: _BoiteFiltre(
          child: Text(
            d == null
                ? etiquette
                : '${d.day.toString().padLeft(2, '0')}/'
                      '${d.month.toString().padLeft(2, '0')}/${d.year}',
            style: styleContenuCarte(
              TaillesContenu.t13,
              couleur: d == null ? Ardoise.c400 : Ardoise.c700,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

/// Le gabarit d'un contrôle natif de la barre : `border border-slate-300
/// rounded-lg px-2.5 py-1.5` (l.209-219).
class _BoiteFiltre extends StatelessWidget {
  const _BoiteFiltre({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      // `px-2.5 py-1.5` — 10 px et 6 px.
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xsPlus,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: AppColors.neutre0,
        borderRadius: BorderRadius.circular(AppRadius.roundedLg),
        border: Border.all(color: Ardoise.c300),
      ),
      child: child,
    );
  }
}

/// Une liste de filtre — le `<select>` de la vue.
class _Liste<T> extends StatelessWidget {
  const _Liste({
    required Key cle,
    required this.largeur,
    required this.valeur,
    required this.videLibelle,
    required this.options,
    required this.onChoix,
  }) : super(key: cle);

  final double largeur;
  final T? valeur;

  /// Le libellé de l'option « aucun filtre », au mot de la vue.
  final String videLibelle;

  final Map<T, String> options;
  final ValueChanged<T?> onChoix;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: largeur,
      child: _BoiteFiltre(
        // Hauteur de l'interligne SEUL : `DropdownButton` impose au moins
        // 24 px de haut, même dense, ce qui ferait la boîte de 38 px au lieu
        // de 32,75 et pousserait le tableau de 5 px (mesuré le 09/10/2026).
        // Le `<select>` de la vue n'a pas de hauteur minimale. Une contrainte
        // SERRÉE du parent l'emporte sur ce minimum.
        child: SizedBox(
          height: TaillesContenu.t13 * AppLayout.interligneContenu,
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T?>(
              value: valeur,
              isExpanded: true,
              isDense: true,
              itemHeight: null,
              iconSize: AppLayout.iconeChamp,
              style: styleContenuCarte(
                TaillesContenu.t13,
                couleur: Ardoise.c700,
              ),
              items: [
                DropdownMenuItem<T?>(child: Text(videLibelle)),
                for (final entree in options.entries)
                  DropdownMenuItem<T?>(
                    value: entree.key,
                    child: Text(entree.value),
                  ),
              ],
              onChanged: onChoix,
            ),
          ),
        ),
      ),
    );
  }
}
