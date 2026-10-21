import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/format/formats.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../restaurant/presentation/widgets/coquille_restaurant.dart';
import '../../../restaurant/presentation/widgets/corps_carte_commun.dart'
    show styleContenuCarte;
import '../../../restaurant/presentation/widgets/tableau_restaurant.dart';
import '../../domain/entities/disponibilite.dart';
import '../../domain/entities/unite_hebergement.dart';
import 'modale_reservation_rapide.dart';
import '../providers_hebergement.dart';

/// L'onglet **« Disponibilités »** — `hebergement.blade.php` l.478-550.
///
/// @see EF-M1-01 Consultation des disponibilités
/// @see RG-01 Anti-double réservation
/// @see RG-02 La disponibilité est CALCULÉE, jamais stockée
///
/// ## D'où il vient, et pourquoi il est ici (décision du Product Owner, 08/10/2026)
///
/// C'était l'écran `ecran_disponibilites.dart`, premier onglet du client
/// jusqu'au 14/09/2026, puis orphelin : aucun clic n'y menait (PA-133). Le
/// maître n'a que trois onglets ; la vue Blade en pose un quatrième pour
/// répondre à « avez-vous une chambre du 12 au 15 ? » sans quitter l'écran. Ce
/// fichier en est le portage, et l'ancien écran est retiré (09/10/2026, après
/// vérification qu'aucune route ni entrée de menu n'y menait).
///
/// ## Lecture seule, et la logique de disponibilité n'a pas bougé
///
/// Deux dates, un calcul — `ConsulterDisponibilites`, inchangé (RG-01, RG-02,
/// bornes semi-ouvertes : un départ le 12 et une arrivée le 12 ne se
/// chevauchent pas). Le montant du séjour est CALCULÉ (tarif × nuits) et
/// affiché ; aucun champ ne le reçoit. Le bouton « Réserver » ouvre la fiche de
/// réservation, qui lit la période CHERCHÉE (`periodeConsulteeProvider`) : la
/// période de la recherche devient celle de la réservation (l.538).
///
/// ## Les mots de la vue, et trois différences avec l'ancien écran (09/10/2026)
///
/// 1. **Il part vide.** La vue n'affiche rien tant que les deux dates ne sont
///    pas choisies (`dispoArrivee = ''`, l.158-161) ; l'ancien écran partait de
///    « cette nuit ». Afficher une période que personne n'a demandée répondrait
///    à une question non posée.
/// 2. **Le motif d'une unité prise dit LES DATES, pas QUI.** La vue écrit
///    « Réservée du :du au :au » (`dispo_motif_reservation`) ; l'ancien écran
///    nommait le client. Les dates sont celles de la réservation en conflit.
/// 3. **Les unités ne sont plus des cartes mais un tableau**, à six colonnes.
///
/// ⚠ Un écart de LOGIQUE, non tranché ici et à remonter au Product Owner : la
/// vue (`UniteHebergement::estCommercialisable()`) tient une unité en
/// `nettoyage` pour NON disponible et lui donne le motif « En nettoyage »
/// (`dispo_motif_nettoyage`). Ce poste ne le fait pas :
/// `StatutUnite.estLouable` ne retire que `hors_service` — une chambre en cours
/// de ménage aujourd'hui est louable la semaine prochaine. RG-02 n'est pas
/// modifiée par ce lot : ce poste garde sa règle, et le motif « En nettoyage »
/// n'est donc jamais rendu.
class VueDisponibilites extends ConsumerStatefulWidget {
  const VueDisponibilites({super.key});

  /// Le motif d'une unité indisponible (`dispoMotif`, l.997-1003), dans les mots
  /// de la vue.
  static String motif(Disponibilite d) {
    return switch (d.motif) {
      MotifIndisponibilite.horsService => 'Hors service',
      MotifIndisponibilite.dejaReservee => () {
        final c = d.reservationEnConflit;
        // Sans réservation désignée, la vue retombe sur « Indisponible ».
        if (c == null) return 'Indisponible';
        return 'Réservée du ${formaterDate(c.periode.arrivee)} '
            'au ${formaterDate(c.periode.depart)}';
      }(),
      null => 'Indisponible',
    };
  }

  @override
  ConsumerState<VueDisponibilites> createState() => _VueDisponibilitesState();
}

class _VueDisponibilitesState extends ConsumerState<VueDisponibilites> {
  DateTime? _arrivee;
  DateTime? _depart;

  /// Vrai quand les deux dates sont choisies ET que le départ suit l'arrivée
  /// (`! $depart->greaterThan($arrivee)`, l.966-968).
  bool get _valide {
    final a = _arrivee;
    final d = _depart;
    if (a == null || d == null) return false;
    return DateTime.utc(
      d.year,
      d.month,
      d.day,
    ).isAfter(DateTime.utc(a.year, a.month, a.day));
  }

  void _choisir({DateTime? arrivee, DateTime? depart}) {
    setState(() {
      _arrivee = arrivee ?? _arrivee;
      _depart = depart ?? _depart;
    });
    // La période CHERCHÉE devient celle de la fiche de réservation. Elle n'est
    // posée que valide : `PeriodeSejour` refuse un séjour de zéro nuit.
    if (_valide) {
      ref
          .read(periodeConsulteeProvider.notifier)
          .definir(arrivee: _arrivee, depart: _depart);
    }
  }

  @override
  Widget build(BuildContext context) {
    final peutReserver = ref.watch(peutEcrireHebergementProvider);

    return Container(
      // `bg-white rounded-xl border border-slate-200 p-5` (l.482).
      padding: const EdgeInsets.all(AppSpacing.mdPlus),
      decoration: BoxDecoration(
        color: AppColors.neutre0,
        border: Border.all(color: Ardoise.c200),
        borderRadius: BorderRadius.circular(AppRadius.roundedXl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Disponibilités sur une période',
            style: styleContenuCarte(
              TaillesContenu.sm,
              poids: FontWeight.bold,
              couleur: Ardoise.c700,
            ),
          ),
          // `mt-1 mb-4` (l.484).
          const SizedBox(height: AppSpacing.unit),
          Text(
            'Choisissez une arrivée et un départ : chaque unité du parc est '
            'listée, libre ou non, avec son motif. Le départ est exclu (la '
            'nuit du départ reste libre).',
            style: styleContenuCarte(TaillesContenu.t13, couleur: Ardoise.c500),
          ),
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              // `grid grid-cols-2 gap-3 max-w-md` (l.486).
              constraints: const BoxConstraints(
                maxWidth: AppLayout.largeurDatesDisponibilites,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _ChampDate(
                      cle: const Key('dispo-arrivee'),
                      etiquette: 'Arrivée',
                      valeur: _arrivee,
                      horloge: ref.watch(horlogeHebergementProvider),
                      onChoix: (d) => _choisir(arrivee: d),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _ChampDate(
                      cle: const Key('dispo-depart'),
                      etiquette: 'Départ',
                      valeur: _depart,
                      horloge: ref.watch(horlogeHebergementProvider),
                      onChoix: (d) => _choisir(depart: d),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (_arrivee != null && _depart != null && !_valide)
            Text(
              'Le départ doit suivre l\'arrivée.',
              key: const Key('dispo-invalide'),
              style: styleContenuCarte(
                TaillesContenu.t13,
                couleur: AppColors.erreur,
              ),
            ),
          if (_valide) _Resultat(peutReserver: peutReserver),
        ],
      ),
    );
  }
}

/// `<label class="block text-[13px] font-semibold text-slate-700 mb-1.5">` et
/// le champ `w-full text-[13px] border border-slate-300 rounded-lg px-3
/// py-2.5` (l.488-495). Un sélecteur de date plutôt qu'un `<input type=date>` :
/// il ne reçoit pas de saisie libre.
class _ChampDate extends StatelessWidget {
  const _ChampDate({
    required this.cle,
    required this.etiquette,
    required this.valeur,
    required this.onChoix,
    required this.horloge,
  });

  final DateTime Function() horloge;
  final Key cle;
  final String etiquette;
  final DateTime? valeur;
  final ValueChanged<DateTime> onChoix;

  @override
  Widget build(BuildContext context) {
    final v = valeur;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          etiquette,
          style: styleContenuCarte(
            TaillesContenu.t13,
            poids: FontWeight.w600,
            couleur: Ardoise.c700,
          ),
        ),
        // `mb-1.5`.
        const SizedBox(height: AppSpacing.xxs),
        InkWell(
          key: cle,
          borderRadius: BorderRadius.circular(AppRadius.roundedLg),
          onTap: () async {
            final maintenant = horloge();
            final choisi = await showDatePicker(
              context: context,
              initialDate: v ?? maintenant,
              // Aucune date antérieure à hier : une arrivée dans le passé
              // fausserait la disponibilité de toutes les périodes antérieures.
              firstDate: maintenant.subtract(const Duration(days: 1)),
              lastDate: maintenant.add(const Duration(days: 730)),
            );
            if (choisi != null) onChoix(choisi);
          },
          child: Container(
            // `px-3 py-2.5` plus la bordure de 1 px.
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xsPlus,
            ),
            decoration: BoxDecoration(
              color: AppColors.neutre0,
              border: Border.all(color: Ardoise.c300),
              borderRadius: BorderRadius.circular(AppRadius.roundedLg),
            ),
            child: Text(
              v == null ? 'jj/mm/aaaa' : formaterDate(v),
              style: styleContenuCarte(
                TaillesContenu.t13,
                couleur: v == null ? Ardoise.c400 : Ardoise.c700,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Le résumé et le tableau (l.503-548), une fois la période valide.
class _Resultat extends ConsumerWidget {
  const _Resultat({required this.peutReserver});

  final bool peutReserver;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final disponibilites = ref.watch(disponibilitesProvider);

    return disponibilites.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      ),
      // Le message est affiché tel quel : le masquer derrière « une erreur est
      // survenue » oblige à ouvrir les journaux pour un diagnostic que
      // l'utilisateur pourrait faire lui-même.
      error: (e, _) => Text(
        '$e',
        key: const Key('dispo-erreur'),
        style: styleContenuCarte(TaillesContenu.t13, couleur: AppColors.erreur),
      ),
      data: (liste) {
        // Les nuits viennent de la PÉRIODE cherchée, pas d'une ligne : un parc
        // vide n'aurait aucune ligne d'où les lire, et la vue les affiche quand
        // même (l.504).
        final nuits = ref.watch(periodeConsulteeProvider).nuits;
        final libres = liste.where((d) => d.disponible).length;
        final texte = styleContenuCarte(
          TaillesContenu.t13,
          couleur: Ardoise.c600,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // `mb-3`. Le résumé de la vue : « N libre(s) sur M unité(s) pour K
            // nuit(s). » — rendu en un seul texte, comme la phrase de la vue.
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(
                '$libres libre(s) sur ${liste.length} unité(s) pour $nuits '
                'nuit(s).',
                key: const Key('dispo-resume'),
                style: texte,
              ),
            ),
            if (liste.isEmpty)
              Padding(
                // `py-10`.
                padding: const EdgeInsets.symmetric(
                  vertical: AppSpacingLarge.p10,
                ),
                child: Text(
                  'Le parc ne compte aucune unité.',
                  key: const Key('dispo-vide'),
                  textAlign: TextAlign.center,
                  style: styleContenuCarte(
                    TaillesContenu.t13,
                    couleur: Ardoise.c400,
                  ),
                ),
              )
            else
              _Tableau(liste: liste, peutReserver: peutReserver),
          ],
        );
      },
    );
  }
}

class _Tableau extends StatelessWidget {
  const _Tableau({required this.liste, required this.peutReserver});

  final List<Disponibilite> liste;
  final bool peutReserver;

  /// `th px-4 py-3` sur `bg-[var(--navy)]`, `td px-4 py-3`, `border-t
  /// border-slate-100` (l.511-523).
  static const GabaritTableau _gabarit = GabaritTableau(
    enteteFond: AppColors.navy,
    entete: TextesRestaurant.enteteColonneNavy,
    cellule: EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.sm,
    ),
    enBas: false,
  );

  @override
  Widget build(BuildContext context) {
    final base = TextesRestaurant.corpsCrud;

    return Container(
      // `overflow-x-auto border border-slate-200 rounded-lg` (l.509).
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(color: Ardoise.c200),
        borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      ),
      child: TableauRestaurant(
        colonnes: const [
          ColonneRestaurant('Unité'),
          ColonneRestaurant('Catégorie'),
          ColonneRestaurant('Capacité'),
          ColonneRestaurant('Montant du séjour'),
          ColonneRestaurant('Disponibilité'),
          ColonneRestaurant('', aDroite: true),
        ],
        gabarit: _gabarit,
        pleineLargeur: true,
        repartitionProportionnelle: true,
        clesLignes: [for (final d in liste) Key('dispo-ligne-${d.unite.id}')],
        lignes: [
          for (final d in liste)
            [
              Text(
                d.unite.numero,
                style: base.copyWith(fontWeight: FontWeight.w600),
              ),
              Text(d.unite.categorieLibelle, style: base),
              Text('${d.unite.capaciteMax}', style: base),
              // Montant CALCULÉ : tarif × nuits. Aucun champ ne le reçoit.
              Text(formaterFcfa(d.montantSejour), style: base),
              _Etat(disponibilite: d),
              d.disponible && peutReserver
                  ? _BoutonReserver(unite: d.unite)
                  : const SizedBox.shrink(),
            ],
        ],
      ),
    );
  }
}

/// Le badge d'état (l.529-534) : `text-[12px] font-semibold px-2 py-0.5
/// rounded-full`, suivi du motif en `text-[12px] text-slate-500 ml-1`.
class _Etat extends StatelessWidget {
  const _Etat({required this.disponibilite});

  final Disponibilite disponibilite;

  @override
  Widget build(BuildContext context) {
    final libre = disponibilite.disponible;
    final style = styleContenuCarte(TaillesContenu.t12, poids: FontWeight.w600);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xs,
            vertical: AppSpacing.demi,
          ),
          decoration: BoxDecoration(
            color: libre ? AppColors.badgeVertFond : AppColors.badgeRougeFond,
            borderRadius: BorderRadius.circular(AppRadius.roundedFull),
          ),
          child: Text(
            libre ? 'Libre' : 'Indisponible',
            style: style.copyWith(
              color: libre ? AppColors.succes : AppColors.erreur,
            ),
          ),
        ),
        if (!libre) ...[
          // `ml-1` — 4 px.
          const SizedBox(width: AppSpacing.unit),
          Text(
            VueDisponibilites.motif(disponibilite),
            key: Key('dispo-motif-${disponibilite.unite.id}'),
            style: styleContenuCarte(TaillesContenu.t12, couleur: Ardoise.c500),
          ),
        ],
      ],
    );
  }
}

/// `text-[12px] px-3 py-1 rounded-lg bg-[var(--navy)] text-white
/// font-semibold` (l.538-539). Il ouvre la modale « Réservation rapide » avec
/// l'unité retenue ; la période est celle de la recherche
/// (`ouvrirReservationRapide(id, arrivée, départ)`).
class _BoutonReserver extends ConsumerWidget {
  const _BoutonReserver({required this.unite});

  final UniteHebergement unite;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      key: Key('dispo-reserver-${unite.id}'),
      borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      // La modale s'ouvre PAR-DESSUS les disponibilités : on revient exactement
      // sur la liste qu'on regardait, avec sa période intacte.
      onTap: () {
        final periode = ref.read(periodeConsulteeProvider);
        ouvrirReservationRapideParc(
          context,
          unite: unite,
          arrivee: periode.arrivee,
          depart: periode.depart,
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.unit,
        ),
        decoration: BoxDecoration(
          color: AppColors.navy,
          borderRadius: BorderRadius.circular(AppRadius.roundedLg),
        ),
        child: Text(
          'Réserver',
          style: styleContenuCarte(
            TaillesContenu.t12,
            poids: FontWeight.w600,
            couleur: AppColors.neutre0,
          ),
        ),
      ),
    );
  }
}
