// Vue Blade maîtresse (PA-183) : pwa/tourisme/departs.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/format/formats.dart';
import '../../../../core/theme/app_colors.dart';
// `app_spacing.dart` réexporte `app_radius.dart` : l'importer aussi serait
// signalé comme import inutile.
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared_widgets/bouton_standard.dart';
import '../../../../shared_widgets/modale_export.dart';
import '../../../../shared_widgets/toast_export.dart';
import '../../../restaurant/presentation/widgets/coquille_restaurant.dart';
import '../../domain/entities/circuit.dart';
import '../providers_tourisme.dart';
import 'modale_prestation.dart';
import 'modale_reservation.dart';

/// `px-3 py-2` d'un champ de la vue : 8 px de marge verticale, de sorte que le
/// champ mesure ~36 px comme au relevé (`AppLayout.hauteurChampTourisme`) et
/// non les 48 px du gabarit Material.
const EdgeInsets _remplissageChamp = EdgeInsets.symmetric(
  horizontal: AppSpacing.sm,
  vertical: AppSpacing.xs,
);

/// Le remplissage d'une LISTE de filtre : 6,2 px de marge verticale, de sorte que
/// la liste mesure 36,4 px comme le champ (`AppLayout.hauteurChampTourisme`) —
/// l'option affichée d'un `DropdownButton` fait déjà 24 px.
const EdgeInsets _remplissageListe = EdgeInsets.symmetric(
  horizontal: AppSpacing.sm,
  vertical: AppLayout.remplissageVerticalListeTourisme,
);

/// Les deux champs de date de l'en-tête — vue l.98-101.
///
/// Les étiquettes « du » et « au » sont **en minuscules** à la vue, et le
/// restent : changer une casse est un écart (Article 4.3).
class ChampsPeriodeTourisme extends ConsumerWidget {
  const ChampsPeriodeTourisme({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final periode = ref.watch(periodeTourismeProvider);

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      // `gap-2` — 8 px.
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        const Text('du', style: TextesRestaurant.mention),
        _ChampDate(
          cle: const Key('tourisme-date-debut'),
          valeur: periode.debut,
          onChoix: (v) =>
              ref.read(periodeTourismeProvider.notifier).definirDebut(v),
        ),
        const Text('au', style: TextesRestaurant.mention),
        _ChampDate(
          cle: const Key('tourisme-date-fin'),
          valeur: periode.fin,
          onChoix: (v) =>
              ref.read(periodeTourismeProvider.notifier).definirFin(v),
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

  final DateTime valeur;
  final ValueChanged<DateTime> onChoix;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: AppLayout.champDateTourisme,
      height: AppLayout.hauteurChampTourisme,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xsPlus),
        ),
        onPressed: () async {
          final choisi = await showDatePicker(
            context: context,
            initialDate: valeur,
            // Un départ se programme pour la saison prochaine, et un départ
            // passé se consulte : les bornes sont larges des deux côtés.
            firstDate: DateTime(DateTime.now().year - 5),
            lastDate: DateTime(DateTime.now().year + 5),
          );
          if (choisi == null) return;
          onChoix(choisi);
        },
        child: Text(
          formaterDate(valeur),
          style: TextesRestaurant.petitCrud,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

/// Le bouton **« Exporter »** de l'en-tête — UN seul, qui ouvre la modale de
/// format (`tourisme/departs.blade.php` l.103-117, partiel `modale-export`
/// l.862-868).
///
/// ## Dérogation du Product Owner, rappelée par la vue
///
/// La paire « Excel » / « PDF » de l'ancien maître est FUSIONNÉE en un bouton
/// « Exporter » (`DerogationsMaquette::export_bouton_unique`, 01/09/2026) : le
/// format se choisit dans la modale. Ce client ne portait ni la paire ni le
/// bouton (« Aucun état de M9 n'est encore livré côté client ») ; il porte le
/// bouton unique depuis le 09/10/2026.
///
/// ## Ce que chaque choix produit, honnêtement
///
///  - **Tableur Excel (.xlsx / .csv)** : le CSV de l'onglet affiché, filtre
///    compris et DIT (PA-119), enregistré par `exporterTourismeProvider`
///    (fenêtre « Enregistrer sous »). Une liste vide se refuse.
///  - **PDF Officiel A4** : REFUSÉ, avec son message. Aucun état A4 de M9 n'est
///    classé dans l'en-tête et les visas de l'application
///    (`pdf_directive_test.dart`), et câbler un `Printing` recopié ici serait
///    la non-conformité n° 1 de `RESPECT_TABLEAU_RAPPORT.md` §4.
///
/// ÉCART — la vue présélectionne « PDF » (`$formatExport = 'pdf'`, l.198 de
/// `Departs.php`). Ici « Excel » l'est, parce que le PDF est refusé :
/// présélectionner un choix qui échoue ferait échouer le chemin le plus court.
/// Même décision que Véhicules et Notifications (09/10/2026).
class BoutonExporterTourisme extends ConsumerWidget {
  const BoutonExporterTourisme({super.key});

  /// `tourisme.pwa.export_titre`.
  static const String titreModale = 'Exporter le rapport Tourisme';

  /// Le refus du choix PDF, dit AVANT le clic (sous les deux choix).
  static const String aidePdf =
      "Le PDF n'est pas produit sur ce poste : seul le tableur (CSV) est "
      'écrit.';

  /// Le refus du choix PDF, dit APRÈS le clic.
  static const String pdfNonProduit =
      "Le PDF de cet écran n'est pas produit sur ce poste : aucun état A4 de "
      "M9 n'est classé dans l'en-tête et les visas de l'application. Rien n'a "
      'été écrit. Choisissez « Tableur Excel » pour obtenir la liste affichée '
      'en CSV.';

  /// `tourisme.pwa.export_vide` — au mot : une liste vide se refuse (PA-119).
  static const String exportVide =
      'Aucune ligne à exporter sur ce filtre — un document vide se lirait '
      'comme un registre vérifié.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // `text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)]` (vue l.117) — bouton
    // standard (PO, 14/10/2026).
    return BoutonStandard(
      key: const Key('tourisme-exporter'),
      libelle: TextesExport.bouton,
      variante: VarianteBouton.primaire,
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
      _dire(context, const Key('tourisme-pdf-refuse'), pdfNonProduit);
      return;
    }

    final etat = await construireEtatCourantTourisme(ref);
    if (!context.mounted) return;

    if (etat.vide) {
      _dire(context, const Key('tourisme-export-vide'), exportVide);
      return;
    }

    // La fenêtre « Enregistrer sous », puis le toast commun (14/10/2026).
    await executerExport(
      context,
      () => ref.read(exporterTourismeProvider)(etat),
      cleSucces: const Key('tourisme-export-fait'),
    );
  }

  static void _dire(BuildContext context, Key cle, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message, key: cle)));
  }
}

/// La barre de filtres — vue l.176-222.
///
/// Cinq contrôles dans l'ordre de la vue : recherche, prestation, remplissage,
/// statut, puis les boutons d'action poussés à droite par un `flex-1`.
class BarreFiltresTourisme extends ConsumerStatefulWidget {
  const BarreFiltresTourisme({super.key});

  @override
  ConsumerState<BarreFiltresTourisme> createState() =>
      _BarreFiltresTourismeState();
}

class _BarreFiltresTourismeState extends ConsumerState<BarreFiltresTourisme> {
  final _terme = TextEditingController();

  @override
  void dispose() {
    _terme.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final circuits = donneeOuNull(ref.watch(circuitsProvider));

    final recherche = TextField(
      key: const Key('tourisme-recherche'),
      controller: _terme,
      style: TextesRestaurant.corpsCrud,
      decoration: const InputDecoration(
        // L'invite de la vue (l.180) — points de suspension TYPOGRAPHIQUES, et
        // le « n° » qu'elle annonce reste dans l'invite bien qu'aucun numéro
        // n'existe : c'est le texte de la vue, et la colonne « N° » est nommée
        // absente ailleurs.
        hintText: 'Circuit, client, guide, n°…',
        // `pl-9` réserve la place de la loupe posée à `left-3` ; sans
        // contrainte l'icône impose 48 px de haut au champ.
        prefixIcon: Padding(
          padding: EdgeInsets.only(left: AppSpacing.sm),
          child: Icon(Icons.search, size: AppLayout.iconeChamp),
        ),
        prefixIconConstraints: BoxConstraints(
          minWidth: AppLayout.prefixeRechercheEtats,
          minHeight: 0,
        ),
        isDense: true,
        // `pl-9 pr-3 py-2` (l.181) : 8 px de marge verticale, le champ mesure
        // ~36 px comme au relevé et non les 48 px du gabarit Material.
        contentPadding: _remplissageChamp,
        border: OutlineInputBorder(),
      ),
      onChanged: (v) => ref.read(rechercheTourismeProvider.notifier).definir(v),
    );

    final listes = [
      _FiltrePrestation(circuits: circuits ?? const <Circuit>[]),
      const _FiltreRemplissage(),
      const _FiltreStatut(),
    ];

    // `flex flex-wrap gap-2.5 items-center` (vue l.177) : tant que tout tient
    // sur une ligne, la recherche (`flex-1 min-w-[200px]`) et l'espace
    // (`flex-1`, l.211) se partagent le reste — les boutons finissent à droite.
    // Plus étroit, la vue passe à la ligne : un `Wrap`.
    return Container(
      // `bg-white rounded-xl border border-slate-200 p-3.5` (l.176).
      padding: const EdgeInsets.all(AppSpacing.smPlus),
      decoration: BoxDecoration(
        color: AppColors.neutre0,
        borderRadius: BorderRadius.circular(AppRadius.roundedXl),
        border: Border.all(color: Ardoise.c200),
      ),
      child: LayoutBuilder(
        builder: (context, contraintes) {
          if (contraintes.maxWidth >= AppLayout.barreFiltresRangeeTourisme) {
            return Row(
              children: [
                Expanded(child: recherche),
                for (final liste in listes) ...[
                  const SizedBox(width: AppSpacing.xsPlus),
                  liste,
                ],
                // Le `<div class="flex-1">` de la vue (l.211).
                const SizedBox(width: AppSpacing.xsPlus),
                const Expanded(child: SizedBox.shrink()),
                const SizedBox(width: AppSpacing.xsPlus),
                const ActionsTourisme(),
              ],
            );
          }
          return Wrap(
            spacing: AppSpacing.xsPlus,
            runSpacing: AppSpacing.xsPlus,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(width: AppLayout.rechercheMinTourisme, child: recherche),
              ...listes,
              const ActionsTourisme(),
            ],
          );
        },
      ),
    );
  }
}

/// Le filtre par PRESTATION — vue l.191-196.
///
/// ÉCART DÉLIBÉRÉ, et il est celui de la vue elle-même : le maître HTML posait
/// un filtre « Circuits / Excursions », que le schéma ne peut pas servir (aucun
/// discriminant). La vue Blade a rebranché le contrôle sur la liste réelle des
/// prestations en gardant **la même position et le même libellé par défaut**.
/// Ce portage suit la vue, qui fait foi (PA-182).
class _FiltrePrestation extends ConsumerWidget {
  const _FiltrePrestation({required this.circuits});

  final List<Circuit> circuits;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final choisi = ref.watch(prestationTourismeProvider);

    return SizedBox(
      width: AppLayout.filtrePrestationTourisme,
      child: DropdownButtonFormField<String?>(
        key: const Key('tourisme-filtre-prestation'),
        initialValue: circuits.any((c) => c.id == choisi) ? choisi : null,
        isExpanded: true,
        // La flèche d'un `<select>` fait 16 px ; celle de Material en fait 24 et
        // porterait la liste à 40 px, contre les 36,4 de la vue.
        iconSize: AppLayout.iconeChamp,
        // Sans cela Material impose 48 px de hauteur à l'option affichée.
        itemHeight: null,
        style: TextesRestaurant.petitCrud,
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: _remplissageListe,
          border: OutlineInputBorder(),
        ),
        items: [
          // Le libellé par défaut de la vue (l.192), au mot.
          const DropdownMenuItem<String?>(
            child: Text('Circuits et excursions'),
          ),
          for (final c in circuits)
            DropdownMenuItem<String?>(value: c.id, child: Text(c.nom)),
        ],
        onChanged: (v) =>
            ref.read(prestationTourismeProvider.notifier).definir(v),
      ),
    );
  }
}

class _FiltreRemplissage extends ConsumerWidget {
  const _FiltreRemplissage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      width: AppLayout.filtreRemplissageTourisme,
      child: DropdownButtonFormField<FiltreRemplissage>(
        key: const Key('tourisme-filtre-remplissage'),
        initialValue: ref.watch(remplissageTourismeProvider),
        isExpanded: true,
        // La flèche d'un `<select>` fait 16 px ; celle de Material en fait 24 et
        // porterait la liste à 40 px, contre les 36,4 de la vue.
        iconSize: AppLayout.iconeChamp,
        // Sans cela Material impose 48 px de hauteur à l'option affichée.
        itemHeight: null,
        style: TextesRestaurant.petitCrud,
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: _remplissageListe,
          border: OutlineInputBorder(),
        ),
        // Les quatre libellés de la vue (l.199-202), dans son ordre.
        items: [
          for (final f in FiltreRemplissage.values)
            DropdownMenuItem(value: f, child: Text(f.libelle)),
        ],
        onChanged: (v) => v == null
            ? null
            : ref.read(remplissageTourismeProvider.notifier).definir(v),
      ),
    );
  }
}

/// Le filtre de statut — vue l.205-209.
///
/// ⚠ « Planifiés » est la PREMIÈRE option **et** l'option sélectionnée par
/// défaut : la vue place « Tous » en deuxième position, contre l'usage. C'est
/// délibéré chez elle, et le réordonner serait choisir à sa place.
class _FiltreStatut extends ConsumerWidget {
  const _FiltreStatut();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      width: AppLayout.filtreStatutTourisme,
      child: DropdownButtonFormField<FiltreStatutDepart>(
        key: const Key('tourisme-filtre-statut'),
        initialValue: ref.watch(statutTourismeProvider),
        isExpanded: true,
        // La flèche d'un `<select>` fait 16 px ; celle de Material en fait 24 et
        // porterait la liste à 40 px, contre les 36,4 de la vue.
        iconSize: AppLayout.iconeChamp,
        // Sans cela Material impose 48 px de hauteur à l'option affichée.
        itemHeight: null,
        style: TextesRestaurant.petitCrud,
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: _remplissageListe,
          border: OutlineInputBorder(),
        ),
        items: [
          for (final f in FiltreStatutDepart.values)
            DropdownMenuItem(value: f, child: Text(f.libelle)),
        ],
        onChanged: (v) => v == null
            ? null
            : ref.read(statutTourismeProvider.notifier).definir(v),
      ),
    );
  }
}

/// Les deux boutons d'action — vue l.213-220.
///
/// « + Prestation » n'apparaît QUE sous l'onglet Catalogue (l.214), comme à la
/// vue. « + Réservation » est partout : c'est le geste qui crée un départ.
class ActionsTourisme extends ConsumerWidget {
  const ActionsTourisme({super.key});

  // `text-[13px] px-3.5 py-2 rounded-lg border` (vue l.216) et `text-[13px]
  // px-4 py-2 rounded-lg bg-[var(--navy)]` (vue l.219) : le bouton standard
  // (PO, 14/10/2026), même gabarit que Véhicules.

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onglet = ref.watch(ongletTourismeProvider);

    // `@if ($peutEcrire)` de la vue (l.213) : les deux boutons DISPARAISSENT
    // pour un rôle en lecture, ils ne sont pas grisés.
    if (!ref.watch(peutEcrireTourismeProvider)) return const SizedBox.shrink();

    return Wrap(
      // `gap-2.5` (l.177) — 10 px entre les boutons d'action.
      spacing: AppSpacing.xsPlus,
      runSpacing: AppSpacing.xsPlus,
      children: [
        if (onglet == OngletTourisme.catalogue)
          BoutonStandard(
            key: const Key('tourisme-nouvelle-prestation'),
            // Le libellé de la vue (l.216), signe « + » compris.
            libelle: '+ Prestation',
            onPressed: () => ouvrirModalePrestation(context),
          ),
        BoutonStandard(
          key: const Key('tourisme-nouvelle-reservation'),
          libelle: '+ Réservation',
          variante: VarianteBouton.primaire,
          onPressed: () => ouvrirModaleReservation(context),
        ),
      ],
    );
  }
}
