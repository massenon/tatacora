// Vue Blade maîtresse (PA-183) : pwa/bar/carte.blade.php
// Le corps de modale est PARTAGÉ par les deux cartes (bar ET restaurant) : ce
// fichier sert aussi la vue ci-dessous, et c'est ici que se rendent ses mots.
// Vue Blade maîtresse (PA-183) : pwa/restaurant/carte.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/format/formats.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../restaurant/presentation/widgets/coquille_modale_restaurant.dart';
import '../../../restaurant/presentation/widgets/textes_modale_restaurant.dart';
import '../../data/boissons_api.dart';
import '../../domain/entities/trace_prix.dart';

/// L'abonnement d'une modale à l'historique d'UN article.
typedef LectureHistoriquePrix =
    AsyncValue<ResultatBar<List<TracePrix>>> Function(WidgetRef ref);

/// La modale **« Historique des prix »** des cartes du bar ET du restaurant —
/// corps partagé des cartes, l.821-875, ouverte par le bouton de chaque ligne
/// (l.436-437).
///
/// @see EF-M5-02 Carte des boissons
/// @see EF-M4-01 Gestion des menus et cartes
///
/// Demande du Product Owner du 01/09/2026 côté PWA (« on doit retracer les
/// changements de prix »). La trace est écrite par `CarteBoissonObserver` et
/// `PlatObserver` au serveur ; ici, par `HistoriquePrixCarteDao` (schéma v38),
/// dans la transaction qui change le prix, et complétée par la descente des
/// traces des autres postes et de la PWA. La modale LIT cette table locale.
///
/// ## Une LECTURE, ouverte au droit `L`
///
/// Comme `ouvrirHistoriquePrix()`, qui n'exige aucun droit d'écriture : un
/// barman en lecture doit pouvoir vérifier depuis quand un tarif a changé.
///
/// ## Un seul corps pour les deux rayons
///
/// [lecture] est le fournisseur de l'historique de l'article : celui du bar
/// (`historiquePrixProvider`) ou celui du restaurant
/// (`historiquePrixPlatProvider`). La modale ne sait pas d'où il vient ; elle
/// n'affiche jamais « aucun changement » sur une lecture en échec.
///
/// [lecture] s'abonne à la liste de l'article (`ref.watch(fournisseur(id))`) et
/// rend son état : la modale reste ainsi indifférente au rayon.
Future<void> ouvrirModaleHistoriquePrix(
  BuildContext context, {
  required String libelle,
  required LectureHistoriquePrix lecture,
}) => showDialog<void>(
  context: context,
  barrierDismissible: true,
  barrierColor: AppColors.voileModale,
  builder: (_) => _ModaleHistorique(libelle: libelle, lecture: lecture),
);

/// Les mots de la vue — `lang/fr/carte_pwa.php`, `modale_historique_prix`.
abstract final class TextesHistoriquePrix {
  static const String bouton = 'Historique des prix';
  static const String titre = 'Historique des prix';
  static const String colDate = 'Date';
  static const String colChamp = 'Champ';
  static const String colAncien = 'Ancien';
  static const String colNouveau = 'Nouveau';
  static const String colPar = 'Par';
  static const String champPrixVente = 'Prix de vente';
  static const String champCorrigeMain = 'Corrigé à la main';
  static const String oui = 'Oui';
  static const String non = 'Non';
  static const String vide =
      'Aucun changement de prix enregistré pour cet article.';
  static const String fermer = 'Fermer';

  /// `MontantFcfa::TIRET` — « on ne sait pas », jamais « 0 ».
  static const String tiret = '—';

  /// Propre à ce poste.
  ///
  /// ⚠ Cette phrase disait « Serveur injoignable […] rétablissez la liaison »
  /// jusqu'au 14/09/2026. Elle est devenue fausse le jour où le poste est passé
  /// zéro réseau : il n'y a plus de liaison à rétablir. Elle ne sert plus que
  /// de repli si la lecture de la table locale échoue.
  static const String lectureImpossible =
      'L’historique des prix n’a pas pu être lu. Ce n’est pas « aucun '
      'changement » : une lecture en échec et une liste vide ne se '
      'corrigent pas de la même façon.';
}

/// Le libellé d'un champ retracé — `$libelleChampPrix` (l.823-826).
String libelleChampPrix(String champ) => champ == TracePrix.champCorrigeMain
    ? TextesHistoriquePrix.champCorrigeMain
    : TextesHistoriquePrix.champPrixVente;

/// Une valeur retracée, dite comme la vue — `$valeurAffichee` (l.828-840) :
/// « — » sans valeur, « Oui » / « Non » pour la marque, le montant en FCFA
/// pour le prix.
///
/// Le montant est lu en ENTIER depuis la chaîne `decimal:2` : le XOF n'a pas
/// de sous-unité, et passer par un flottant pour le seul affichage serait
/// ouvrir une porte que la règle projet ferme.
String valeurTracee(String? valeur, String champ) {
  if (valeur == null) return TextesHistoriquePrix.tiret;

  final entiere = int.tryParse(valeur.split('.').first);
  if (champ == TracePrix.champCorrigeMain) {
    // `bccomp($valeur, '1', 2) === 0`.
    return valeur.replaceFirst(RegExp(r'\.0*$'), '') == '1'
        ? TextesHistoriquePrix.oui
        : TextesHistoriquePrix.non;
  }
  return entiere == null ? valeur : formaterFcfa(entiere);
}

/// `d/m/Y H:i` — l.860.
String dateTracee(DateTime? date) {
  if (date == null) return TextesHistoriquePrix.tiret;
  final h = date.hour.toString().padLeft(2, '0');
  final m = date.minute.toString().padLeft(2, '0');
  return '${formaterDate(date)} $h:$m';
}

class _ModaleHistorique extends ConsumerWidget {
  const _ModaleHistorique({required this.libelle, required this.lecture});

  final String libelle;
  final LectureHistoriquePrix lecture;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historique = lecture(ref);

    final Widget corps = switch (historique) {
      AsyncData(value: BarRecu(:final donnees)) when donnees.isEmpty =>
        const Padding(
          // `py-10` (l.846).
          padding: EdgeInsets.symmetric(vertical: AppSpacing.xlPlus),
          child: Text(
            TextesHistoriquePrix.vide,
            key: Key('historique-prix-vide'),
            textAlign: TextAlign.center,
            style: TextesModaleRestaurant.aide,
          ),
        ),
      AsyncData(value: BarRecu(:final donnees)) => _Tableau(traces: donnees),
      AsyncData(value: BarRefuse(:final motif)) => _Message(
        cle: const Key('historique-prix-refus'),
        texte: motif,
      ),
      AsyncData(value: BarInjoignable()) => const _Message(
        cle: Key('historique-prix-injoignable'),
        texte: TextesHistoriquePrix.lectureImpossible,
      ),
      AsyncError() => const _Message(
        cle: Key('historique-prix-injoignable'),
        texte: TextesHistoriquePrix.lectureImpossible,
      ),
      _ => const LinearProgressIndicator(key: Key('historique-prix-charge')),
    };

    return CoquilleModaleRestaurant(
      cle: const Key('modale-historique-prix'),
      titre: TextesHistoriquePrix.titre,
      // `sous_titre` = `:article` (l.843).
      sousTitre: libelle,
      largeur: AppLayout.modaleHistoriquePrix,
      corps: corps,
      actions: [
        // Un seul bouton, et il est plein — `bg-[var(--navy)]` (l.872).
        FilledButton(
          key: const Key('historique-prix-fermer'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            TextesHistoriquePrix.fermer,
            style: TextesModaleRestaurant.bouton,
          ),
        ),
      ],
    );
  }
}

/// Le tableau — cinq colonnes, en-tête marine (l.849-869), défilant à
/// l'horizontale sur un écran étroit (`overflow-x-auto`).
class _Tableau extends StatelessWidget {
  const _Tableau({required this.traces});

  final List<TracePrix> traces;

  @override
  Widget build(BuildContext context) {
    TextStyle? entete() =>
        TextesModaleRestaurant.etiquette.copyWith(color: AppColors.neutre0);

    return SingleChildScrollView(
      key: const Key('historique-prix-tableau'),
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: const WidgetStatePropertyAll(AppColors.navy),
        columns: [
          DataColumn(
            label: Text(TextesHistoriquePrix.colDate, style: entete()),
          ),
          DataColumn(
            label: Text(TextesHistoriquePrix.colChamp, style: entete()),
          ),
          DataColumn(
            label: Text(TextesHistoriquePrix.colAncien, style: entete()),
            numeric: true,
          ),
          DataColumn(
            label: Text(TextesHistoriquePrix.colNouveau, style: entete()),
            numeric: true,
          ),
          DataColumn(label: Text(TextesHistoriquePrix.colPar, style: entete())),
        ],
        rows: [
          for (final t in traces)
            DataRow(
              cells: [
                DataCell(
                  Text(
                    dateTracee(t.date),
                    key: Key('historique-prix-${t.id}'),
                    style: TextesModaleRestaurant.corps.copyWith(
                      color: Ardoise.c600,
                    ),
                  ),
                ),
                DataCell(
                  Text(
                    libelleChampPrix(t.champ),
                    style: TextesModaleRestaurant.corps,
                  ),
                ),
                DataCell(
                  Text(
                    valeurTracee(t.ancien, t.champ),
                    style: TextesModaleRestaurant.corps.copyWith(
                      color: Ardoise.c500,
                    ),
                  ),
                ),
                DataCell(
                  Text(
                    valeurTracee(t.nouveau, t.champ),
                    style: TextesModaleRestaurant.corps.copyWith(
                      color: AppColors.navy,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                DataCell(
                  Text(
                    t.par ?? TextesHistoriquePrix.tiret,
                    style: TextesModaleRestaurant.aide,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.cle, required this.texte});

  final Key cle;
  final String texte;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: cle,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: PaletteMaitre.ambre50,
        border: Border.all(color: PaletteMaitre.ambre200),
        borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      ),
      child: Text(
        texte,
        style: TextesModaleRestaurant.corps.copyWith(
          color: PaletteMaitre.ambre900,
        ),
      ),
    );
  }
}
