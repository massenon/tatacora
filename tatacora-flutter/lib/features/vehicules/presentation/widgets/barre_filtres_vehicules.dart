// Vue Blade maîtresse (PA-183) : pwa/vehicules/locations.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared_widgets/bouton_standard.dart';
import '../../../bar/presentation/widgets/modale_export_carte.dart';
import '../../../restaurant/presentation/widgets/coquille_restaurant.dart';
import '../../domain/entities/vehicule.dart';
import '../ecran_vehicules.dart';
import '../providers_vehicules.dart';
import 'etat_courant_vehicules.dart';

/// `px-3 py-2` d'un champ de la vue : 8 px de marge verticale, de sorte que le
/// champ mesure ~36 px comme au relevé (`AppLayout.hauteurChampVehicules`) et non
/// les 48 px du gabarit Material.
const EdgeInsets _remplissageChamp = EdgeInsets.symmetric(
  horizontal: AppSpacing.sm,
  vertical: AppSpacing.xs,
);

/// Les deux champs de date de l'en-tête —
/// `prototype_v2/pages/m8-locations.html` l.36-39.
///
/// Les étiquettes « du » et « au » sont **en minuscules** au maître, et le
/// restent : changer une casse est un écart (Article 4.3).
class ChampsPeriodeVehicules extends ConsumerWidget {
  const ChampsPeriodeVehicules({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final periode = ref.watch(periodeVehiculesProvider);

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      // `gap-2` — 8 px.
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        const Text('du', style: TextesRestaurant.mention),
        _ChampDate(
          cle: const Key('vehicules-date-debut'),
          valeur: periode.debut,
          onChoix: (v) =>
              ref.read(periodeVehiculesProvider.notifier).definirDebut(v),
        ),
        const Text('au', style: TextesRestaurant.mention),
        _ChampDate(
          cle: const Key('vehicules-date-fin'),
          valeur: periode.fin,
          onChoix: (v) =>
              ref.read(periodeVehiculesProvider.notifier).definirFin(v),
        ),
      ],
    );
  }
}

class _ChampDate extends StatelessWidget {
  const _ChampDate({
    required Key cle,
    required this.valeur,
    required this.onChoix,
  }) : super(key: cle);

  final String? valeur;
  final ValueChanged<String?> onChoix;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: AppLayout.champDateVehicules,
      height: AppLayout.hauteurChampVehicules,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xsPlus),
        ),
        onPressed: () async {
          final courant = valeur == null ? null : DateTime.tryParse(valeur!);
          final choisi = await showDatePicker(
            context: context,
            initialDate: courant ?? DateTime.now(),
            // Une location peut porter sur l'an prochain, et un contrat passé
            // se consulte : les bornes sont larges des deux côtés.
            firstDate: DateTime(DateTime.now().year - 5),
            lastDate: DateTime(DateTime.now().year + 5),
          );
          if (choisi == null) return;
          onChoix(
            '${choisi.year.toString().padLeft(4, '0')}-'
            '${choisi.month.toString().padLeft(2, '0')}-'
            '${choisi.day.toString().padLeft(2, '0')}',
          );
        },
        child: Text(
          valeur ?? 'jj/mm/aaaa',
          style: TextesRestaurant.petitCrud,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

/// Le bouton **« Exporter »** de l'en-tête — UN seul, qui ouvre la modale de
/// format (`vehicules/locations.blade.php` l.102-116, partiel `modale-export`
/// l.845-851).
///
/// ## Dérogation du Product Owner, rappelée par la vue
///
/// La paire « Excel » / « PDF » de l'ancien maître est FUSIONNÉE en un bouton
/// « Exporter » (`DerogationsMaquette::export_bouton_unique`, 01/09/2026) : le
/// format se choisit dans la modale. Ce client portait encore la paire ; il
/// porte le bouton unique depuis le 09/10/2026.
///
/// ## Ce que chaque choix produit, honnêtement
///
///  - **Tableur Excel (.xlsx / .csv)** : le CSV de l'onglet affiché, filtre
///    compris et DIT (PA-119), écrit par `exporterVehiculesProvider`, chemin
///    affiché. Une liste vide se refuse.
///  - **PDF Officiel A4** : REFUSÉ, avec son message. Aucun état A4 de M8 n'est
///    classé dans l'en-tête et les visas de l'application
///    (`pdf_directive_test.dart`), et câbler un `Printing` recopié ici serait la
///    non-conformité n° 1 de `RESPECT_TABLEAU_RAPPORT.md` §4. Un aperçu vide
///    serait pire.
///
/// « PDF » est présélectionné comme dans la vue (`$formatExport = 'pdf'`) —
/// demande du PO du 14/10/2026 ; le refus du PDF est dit après le clic.
class BoutonExporterVehicules extends ConsumerWidget {
  const BoutonExporterVehicules({super.key});

  /// `vehicules.pwa.export_titre`.
  static const String titreModale = 'Exporter le rapport Véhicules & Locations';

  /// Le refus du choix PDF, dit AVANT le clic (sous les deux choix).
  static const String aidePdf =
      'Le PDF n’est pas produit sur ce poste : seul le tableur (CSV) est '
      'écrit.';

  /// Le refus du choix PDF, dit APRÈS le clic.
  static const String pdfNonProduit =
      'Le PDF de cet écran n’est pas produit sur ce poste : aucun état A4 de '
      'M8 n’est classé dans l’en-tête et les visas de l’application. Rien n’a '
      'été écrit. Choisissez « Tableur Excel » pour obtenir la liste affichée '
      'en CSV.';

  /// Une liste vide se refuse (PA-119).
  static const String exportVide =
      'Rien à exporter : la liste filtrée est vide. Une page blanche remise au '
      'Gérant se lirait « aucun contrat », alors qu’elle veut dire « le filtre '
      'n’a rien retenu ».';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // `text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] font-semibold` (vue
    // l.116) : le bouton standard, variante primaire (14/10/2026).
    return BoutonStandard(
      key: const Key('vehicules-exporter'),
      variante: VarianteBouton.primaire,
      libelle: TextesExport.bouton,
      onPressed: () => _exporter(context, ref),
    );
  }

  Future<void> _exporter(BuildContext context, WidgetRef ref) async {
    final format = await choisirFormatExport(
      context,
      titre: titreModale,
      aide: aidePdf,
    );
    if (format == null || !context.mounted) return;

    // Le refus du PDF passe avant celui de la liste vide : il ne dépend pas
    // des lignes, et le dire d'abord évite d'envoyer élargir un filtre pour un
    // document qu'aucun filtre ne produira.
    if (format == FormatExport.pdf) {
      _dire(context, const Key('vehicules-pdf-refuse'), pdfNonProduit);
      return;
    }

    final etat = await construireEtatCourant(ref);
    if (!context.mounted) return;

    if (etat == null || etat.vide) {
      _dire(context, const Key('vehicules-export-vide'), exportVide);
      return;
    }

    final chemin = await ref.read(exporterVehiculesProvider)(etat);
    if (!context.mounted) return;

    _dire(
      context,
      const Key('vehicules-export-fait'),
      'Export écrit : $chemin',
    );
  }

  static void _dire(BuildContext context, Key cle, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message, key: cle)));
  }
}

/// La barre de filtres — `m8-locations.html` l.59-77.
///
/// Cinq contrôles, dans l'ordre du maître : recherche, catégorie, statut,
/// espace, « Immobiliser », « + Contrat ».
class BarreFiltresVehicules extends ConsumerStatefulWidget {
  const BarreFiltresVehicules({super.key});

  @override
  ConsumerState<BarreFiltresVehicules> createState() =>
      _BarreFiltresVehiculesState();
}

class _BarreFiltresVehiculesState extends ConsumerState<BarreFiltresVehicules> {
  final _terme = TextEditingController();

  @override
  void dispose() {
    _terme.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final recherche = TextField(
      key: const Key('vehicules-recherche'),
      controller: _terme,
      style: TextesRestaurant.corpsCrud,
      decoration: const InputDecoration(
        // L'invite de la vue (`vehicules.pwa.recherche`) — points de
        // suspension TYPOGRAPHIQUES.
        hintText: 'Véhicule, client, n° de contrat…',
        // `pl-9` réserve la place de la loupe posée à `left-3` ; sans contrainte
        // l'icône impose 48 px de haut au champ.
        prefixIcon: Padding(
          padding: EdgeInsets.only(left: AppSpacing.sm),
          child: Icon(Icons.search, size: AppLayout.iconeChamp),
        ),
        prefixIconConstraints: BoxConstraints(
          minWidth: AppLayout.prefixeRechercheEtats,
          minHeight: 0,
        ),
        isDense: true,
        // `pl-9 pr-3 py-2` (vue l.180) : 8 px de marge verticale, le champ
        // mesure ~36 px comme au relevé et non les 48 px du gabarit Material.
        contentPadding: _remplissageChamp,
        border: OutlineInputBorder(),
      ),
      onChanged: (v) =>
          ref.read(rechercheVehiculesProvider.notifier).definir(v),
    );

    final categorie = SizedBox(
      width: AppLayout.filtreCategorieVehicules,
      child: DropdownButtonFormField<CategorieVehicule?>(
        key: const Key('vehicules-filtre-categorie'),
        initialValue: ref.watch(categorieVehiculesProvider),
        isExpanded: true,
        style: TextesRestaurant.petitCrud,
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: _remplissageChamp,
          border: OutlineInputBorder(),
        ),
        items: [
          // Le libellé de l'option vide EST celui de la vue
          // (`toutes_categories`) : « Toutes catégories ».
          const DropdownMenuItem<CategorieVehicule?>(
            child: Text('Toutes catégories'),
          ),
          for (final c in CategorieVehicule.values)
            DropdownMenuItem<CategorieVehicule?>(
              value: c,
              child: Text(c.libelle),
            ),
        ],
        onChanged: (c) =>
            ref.read(categorieVehiculesProvider.notifier).definir(c),
      ),
    );

    // `flex flex-wrap gap-2.5 items-center` (vue l.176) : tant que tout tient
    // sur une ligne, la recherche (`flex-1 min-w-[200px]`) et un espace
    // (`flex-1`) se partagent le reste — les trois boutons finissent à droite.
    // Plus étroit, la vue passe à la ligne : un `Wrap`.
    return Container(
      // `bg-white rounded-xl border border-slate-200 p-3.5` (l.175).
      padding: const EdgeInsets.all(AppSpacing.smPlus),
      decoration: BoxDecoration(
        color: AppColors.neutre0,
        borderRadius: BorderRadius.circular(AppRadius.roundedXl),
        border: Border.all(color: Ardoise.c200),
      ),
      child: LayoutBuilder(
        builder: (context, contraintes) {
          if (contraintes.maxWidth >= AppLayout.barreFiltresRangeeVehicules) {
            return Row(
              children: [
                Expanded(child: recherche),
                const SizedBox(width: AppSpacing.xsPlus),
                categorie,
                const SizedBox(width: AppSpacing.xsPlus),
                const _FiltreStatutContrat(),
                const SizedBox(width: AppSpacing.xsPlus),
                // Le `<div class="flex-1">` de la vue (l.196).
                const Expanded(child: SizedBox.shrink()),
                const SizedBox(width: AppSpacing.xsPlus),
                const ActionsVehicules(),
              ],
            );
          }
          return Wrap(
            spacing: AppSpacing.xsPlus,
            runSpacing: AppSpacing.xsPlus,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: AppLayout.rechercheMinVehicules,
                child: recherche,
              ),
              categorie,
              const _FiltreStatutContrat(),
              const ActionsVehicules(),
            ],
          );
        },
      ),
    );
  }
}

/// Le filtre « Contrats actifs / Tous / Annulés » (l.66-70).
///
/// ÉCART DÉLIBÉRÉ — `prototype_v2/pages/m8-locations.html` l.66-70.
/// Le maître : une liste à trois options, `actif` sélectionnée par défaut.
/// Ici : la liste garde ses trois options **et son ordre**, mais elle est
/// inerte, et un texte à côté dit pourquoi.
/// Raison : `contrats_location` n'a **aucune colonne `statut`** (PA-50). Les
/// trois options désignent le même ensemble — tous les contrats. Une liste
/// active qui rendrait les mêmes lignes sur les trois choix ferait chercher un
/// défaut de filtre ; une liste retirée masquerait que le maître en pose un.
class _FiltreStatutContrat extends StatelessWidget {
  const _FiltreStatutContrat();

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message:
          // Sans code interne ni nom de table (directive du PO, 14/10/2026).
          'Un contrat ne peut pas être annulé sur ce poste : les trois '
          'options désignent le même ensemble.',
      child: SizedBox(
        width: AppLayout.filtreStatutVehicules,
        child: DropdownButtonFormField<String>(
          key: const Key('vehicules-filtre-statut'),
          initialValue: 'actif',
          isExpanded: true,
          style: TextesRestaurant.petitCrud,
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: _remplissageChamp,
            border: OutlineInputBorder(),
          ),
          // Les trois libellés du maître, dans son ordre.
          items: const [
            DropdownMenuItem(value: 'actif', child: Text('Contrats actifs')),
            DropdownMenuItem(value: '', child: Text('Tous')),
            DropdownMenuItem(value: 'annule', child: Text('Annulés')),
          ],
          // Inerte, et non grisé : le maître pose la liste, on la montre.
          onChanged: null,
        ),
      ),
    );
  }
}
