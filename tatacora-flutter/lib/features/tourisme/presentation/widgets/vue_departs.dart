// Vue Blade maîtresse (PA-183) : pwa/tourisme/departs.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/format/formats.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared_widgets/liste_paginee.dart';
import '../../../restaurant/presentation/widgets/coquille_restaurant.dart';
import '../../../restaurant/presentation/widgets/tableau_restaurant.dart';
import '../../domain/departs.dart';
import '../providers_tourisme.dart';
import 'coquille_tourisme.dart';
import 'modale_annulation.dart';
import 'modale_guide.dart';
import 'modale_reservation.dart';

/// L'onglet **« Départs planifiés »** — vue l.250-405.
///
/// ## Un départ est DÉRIVÉ, il n'est pas stocké
///
/// C'est le point central de tout M9, et il explique la moitié de cet écran :
/// il n'existe aucune table `departs`, ni au serveur ni sur ce poste. Un départ
/// est le couple (circuit, date) porté par les lignes de `reservations_tour`,
/// plus le guide que ces lignes désignent. Il **naît de sa première
/// réservation**, et c'est pourquoi le bouton « + Départ » du maître HTML est
/// refusé par la vue Blade elle-même : il ouvrirait un formulaire qui n'écrit
/// nulle part. Le geste qui crée un départ est « + Réservation ».
///
/// ## Trois colonnes sur dix n'ont aucune source, et gardent leur place
///
/// « N° », « Véhicule » et la durée sous le nom du circuit. Les retirer
/// supprimerait des éléments visibles de la vue ; les remplir inventerait des
/// données sur l'écran où l'on décide d'engager un véhicule.
class VueDeparts extends ConsumerWidget {
  const VueDeparts({super.key});

  /// Les colonnes de la vue (l.272-281), dans son ordre.
  ///
  /// ⚠ La dernière n'a **pas d'en-tête** : la vue termine ses tableaux par une
  /// chaîne vide (`<th class="px-3 py-2.5"></th>`, l.281). Lui donner un titre
  /// (« Actions ») serait ajouter un mot que le maître n'écrit pas.
  static const colonnes = [
    ColonneRestaurant('N°'),
    ColonneRestaurant('Circuit'),
    ColonneRestaurant('Départ', aDroite: true),
    ColonneRestaurant('Guide', aDroite: true),
    ColonneRestaurant('Véhicule', aDroite: true),
    ColonneRestaurant('Remplissage', aDroite: true),
    ColonneRestaurant('Prix / pers.', aDroite: true),
    ColonneRestaurant('CA', aDroite: true),
    ColonneRestaurant('État', aDroite: true),
    ColonneRestaurant('', aDroite: true),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final departs = ref.watch(departsProvider);

    return departs.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => NoteRestaurant(
        cle: const Key('tourisme-departs-erreur'),
        texte: '$e',
        icone: Icons.error_outline,
      ),
      data: (liste) => liste.isEmpty
          ? const EtatVideTourisme(
              cle: Key('tourisme-departs-vide'),
              // Le message de la vue (l.262), au mot.
              message: 'Aucun départ ne correspond à ces critères.',
            )
          : _Corps(departs: liste),
    );
  }
}

class _Corps extends ConsumerWidget {
  const _Corps({required this.departs});

  final List<Depart> departs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final agregats = agregerDeparts(departs);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Le bandeau de la vue (l.251-258), SEULEMENT s'il y a des départs à
        // durée indéterminée : `@if ($dureeIndetermineeCount > 0)`. Le nombre
        // est celui de la carte « Durée indéterminée » (départs AFFICHÉS), et
        // la donnée existe depuis la v10 (14/09/2026) : ce bandeau figurait
        // jusqu'au 09/10/2026 parmi les éléments « non rendus », sous le motif
        // que la colonne manquait — motif devenu faux (PA-144).
        if (agregats.dureeIndeterminee > 0) ...[
          EncadreRestaurant(
            cle: const Key('tourisme-bandeau-duree'),
            ton: TonEncadre.ambre,
            titre:
                '${agregats.dureeIndeterminee} départ(s) à durée indéterminée.',
            texte:
                'La durée de ce circuit est un texte libre au catalogue : '
                '« Plusieurs jours » n\'est pas une durée exploitable. Le '
                'véhicule n\'est alors immobilisé que sur le jour de départ, et '
                'non sur la durée réelle du circuit.',
          ),
          // `mb-4` — 16 px.
          const SizedBox(height: AppSpacing.md),
        ],
        CadreTableauRestaurant(
          // Le titre du cadre à la vue (l.266).
          titre: 'Départs planifiés',
          // Dix départs par page (PO, 14/10/2026) ; la ligne TOTAL porte
          // TOUS les départs retenus, jamais la seule page.
          corps: ListePaginee<Depart>(
            elements: departs,
            prefixeCle: 'tourisme-departs-pagination',
            cleRemiseAZero: (
              ref.watch(rechercheTourismeProvider),
              ref.watch(prestationTourismeProvider),
              ref.watch(statutTourismeProvider),
              ref.watch(remplissageTourismeProvider),
            ),
            constructeur: (_, page) => TableauRestaurant(
              gabarit: gabaritTourisme,
              colonnes: VueDeparts.colonnes,
              clesLignes: [
                for (final d in page)
                  Key('tourisme-depart-${Depart.cle(d.circuitId, d.date)}'),
              ],
              lignes: [for (final d in page) _ligne(context, ref, d)],
              ligneTotal: _ligneTotal(agregats),
              decorationTotal: decorationTotalTourisme,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        // L'encadré de la vue (l.352-356) : il porte la RAISON pour laquelle
        // la capacité n'est pas saisissable. Le retirer laisserait la règle
        // sans son explication, sur l'écran même où on la subit.
        const EncadreRestaurant(
          cle: Key('tourisme-encadre-capacite'),
          ton: TonEncadre.gris,
          titre: 'La capacité vient du circuit, pas d\'une saisie.',
          texte:
              'Elle est lue de la fiche du circuit et contrôlée cumulée sur le '
              'départ par le service de domaine : trois groupes de 5 sur un '
              'circuit à 12 places sont refusés au troisième.',
        ),
      ],
    );
  }

  List<Widget> _ligne(BuildContext context, WidgetRef ref, Depart d) {
    return [
      // « N° » — aucune colonne `numero` sur `reservations_tour`.
      const CelluleAbsenteTourisme(
        raison: 'Une réservation de circuit n\'a pas de numéro sur ce poste.',
      ),
      _CelluleCircuit(depart: d),
      Text(formaterDate(d.date), style: TextesRestaurant.corps),
      Text(
        d.guideNom ?? CarteIndicateurRestaurant.absent,
        style: TextesRestaurant.corps,
      ),
      // « Véhicule » — aucune colonne au schéma, ni ici ni au serveur.
      const CelluleAbsenteTourisme(
        raison:
            // Sans nom de table (directive du PO, 14/10/2026) : aucune
            // colonne `vehicule_id` sur `reservations_tour`.
            'Aucun départ n\'est rattaché à un véhicule.',
      ),
      JaugeRemplissage(
        cle: Key('tourisme-jauge-${Depart.cle(d.circuitId, d.date)}'),
        depart: d,
      ),
      Text(formaterFcfa(d.prixUnitaire), style: TextesRestaurant.corps),
      Text(
        formaterFcfa(d.chiffreAffaires),
        style: TextesRestaurant.corpsFort.copyWith(color: AppColors.navy),
      ),
      PastilleEtatDepart(
        cle: Key('tourisme-pastille-${Depart.cle(d.circuitId, d.date)}'),
        depart: d,
      ),
      _ActionsDepart(depart: d),
    ];
  }

  /// La ligne TOTAL — vue l.340-346.
  ///
  /// ÉCART DE RENDU, nommé : la vue fusionne ses cellules (`colspan="5"`, puis
  /// `colspan="2"`). Une `Table` Flutter n'a pas de fusion de cellules ; le
  /// libellé occupe donc la première cellule et les suivantes restent vides,
  /// aux mêmes emplacements. Les trois nombres — départs, places, chiffre
  /// d'affaires — tombent dans les mêmes colonnes qu'à la vue.
  List<Widget> _ligneTotal(AgregatsDeparts agregats) {
    Widget vide() => const SizedBox.shrink();

    return [
      Text(
        // La formulation de la vue (l.341).
        'TOTAL — ${agregats.departs} départ(s)',
        key: const Key('tourisme-departs-total'),
        style: styleTotalTourisme,
      ),
      vide(),
      vide(),
      vide(),
      vide(),
      Text(
        '${agregats.placesVendues}/${agregats.capaciteOfferte}',
        key: const Key('tourisme-departs-total-places'),
        style: styleTotalTourisme,
      ),
      vide(),
      Text(
        formaterFcfa(agregats.chiffreAffaires),
        key: const Key('tourisme-departs-total-ca'),
        style: styleTotalTourisme,
      ),
      vide(),
      vide(),
    ];
  }
}

/// La cellule « Circuit » : le nom, et la durée en dessous (vue l.298-301).
class _CelluleCircuit extends StatelessWidget {
  const _CelluleCircuit({required this.depart});

  final Depart depart;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(depart.circuitNom, style: TextesRestaurant.corpsFort),
        // La durée — texte LIBRE, lue depuis la v10 (14/09/2026). « — » quand
        // aucune n'est renseignée : le départ compte alors comme indéterminé,
        // et le véhicule n'est immobilisé que sur son jour de départ.
        Text(
          depart.duree ?? CarteIndicateurRestaurant.absent,
          style: TextesRestaurant.mention,
        ),
      ],
    );
  }
}

/// Les trois actions de ligne — vue l.326-336.
///
/// « Réserver » n'apparaît que **s'il reste des places** (l.327), et les trois
/// disparaissent sur un départ annulé (l.326) : un bouton qui ouvrirait une
/// modale pour se faire refuser est exactement ce que l'Article 6 refuse.
class _ActionsDepart extends ConsumerWidget {
  const _ActionsDepart({required this.depart});

  final Depart depart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (depart.annule) return const SizedBox.shrink();

    // `@if ($peutEcrire && ! $d['annule'])` de la vue (l.326) : les trois
    // actions disparaissent pour un rôle en lecture.
    if (!ref.watch(peutEcrireTourismeProvider)) return const SizedBox.shrink();

    final cle = Depart.cle(depart.circuitId, depart.date);

    return Wrap(
      alignment: WrapAlignment.end,
      spacing: AppSpacing.unit,
      runSpacing: AppSpacing.unit,
      children: [
        if (depart.placesRestantes > 0)
          ActionLigneTourisme(
            cle: Key('tourisme-reserver-$cle'),
            libelle: 'Réserver',
            pleine: true,
            onPresse: () => ouvrirModaleReservation(
              context,
              circuitId: depart.circuitId,
              date: depart.date,
              guideImposeId: depart.guideId,
            ),
          ),
        ActionLigneTourisme(
          cle: Key('tourisme-guide-$cle'),
          libelle: 'Guide',
          onPresse: () => ouvrirModaleGuide(
            context,
            circuitId: depart.circuitId,
            date: depart.date,
          ),
        ),
        ActionLigneTourisme(
          cle: Key('tourisme-annuler-depart-$cle'),
          libelle: 'Annuler',
          onPresse: () => ouvrirModaleAnnulationDepart(context, depart: depart),
        ),
      ],
    );
  }
}
