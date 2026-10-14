// Vue Blade maîtresse (PA-183) : pwa/livewire/accueil.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/format/formats.dart';
import '../../../../core/rbac/garde_acces.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../alertes/presentation/providers_alertes.dart'
    show alertesClocheProvider;
import '../../../comptabilite/domain/refus_comptable.dart';
import '../../../facturation/domain/creances.dart';
import '../../../facturation/domain/entities/paiement_facture.dart';
import '../../../facturation/domain/regles_encaissement.dart';
import '../../../facturation/presentation/providers_paiements.dart';
import '../../../hebergement/domain/entities/reservation.dart';
import '../../../hebergement/domain/entities/service_reservation.dart';
import '../../../hebergement/domain/messages_sejour.dart';
import '../../../hebergement/presentation/providers_hebergement.dart';
import '../../../hebergement/presentation/widgets/vue_services.dart'
    show couleurService;
import '../../../restaurant/presentation/widgets/coquille_modale_restaurant.dart';
import '../../domain/exploitation_locale.dart';
import '../ecran_pilotage_consolide.dart'
    show
        horlogeTableauDeBordProvider,
        parcPilotageProvider,
        reservationsPilotageProvider;
import 'champs_modale_accueil.dart';
import 'panneau_exploitation.dart';

/// Le tableau « Réservations du jour » de la vue d'accueil (l.432-541) et ses
/// trois gestes de ligne — « Payer », « Check-in », « Check-out » (lot C du
/// plan du PO, 14/10/2026).
///
/// ## Les droits, comme `Accueil::peutEcrire()`
///
/// Le tableau se rend avec le droit de LECTURE sur M1 (`@if
/// ($peutLireHebergement)`). Un geste exige le droit d'écriture sur le module
/// qu'il écrit ET sur l'écran (M11, [peutEcrireDepuisAccueil]) : « Check-in »
/// / « Check-out » sur M1, « Payer » sur M2. Un geste sans droit n'est pas
/// rendu ; sans aucun geste, la cellule porte un tiret.
///
/// ## D'où viennent les données
///
/// | Colonne / geste | Source sur ce poste | Écrivain |
/// |---|---|---|
/// | lignes | [reservationsDuJour] sur `reservationsPilotageProvider` | `ReservationDao` |
/// | « Check-out » plutôt que « Check-in » | `reservationsAuSejourOuvertProvider` | `SejourDao` |
/// | « Payer » | [factureAPayerDe] sur `creancesProvider` | `FactureDao`, `PaiementsFactureDao` |
///
/// Le check-in et le check-out passent par `SejourDao` (réplique de
/// `SejourService`) ; « Payer » par `recouvrerLaFacture` →
/// `PaiementsFactureDao.encaisser`, qui passe la PIÈCE comptable (Dr trésorerie
/// / Cr 4111) dans la MÊME transaction que le paiement — comme
/// `EncaissementFactureService`, que le composant appelle.
///
/// @see EF-M1-03 Check-in
/// @see EF-M1-04 Check-out
class TableReservationsDuJour extends ConsumerWidget {
  const TableReservationsDuJour({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final droits = ref.watch(droitsProvider);
    if (!droits.peutLire(ModuleTatacora.m1Hebergement)) {
      return const SizedBox.shrink();
    }
    final peutHeberger = peutEcrireDepuisAccueil(
      droits,
      ModuleTatacora.m1Hebergement,
    );
    final peutEncaisser = peutEcrireDepuisAccueil(
      droits,
      ModuleTatacora.m2Facturation,
    );

    final lues = ref.watch(reservationsPilotageProvider);
    final ouverts = ref.watch(reservationsAuSejourOuvertProvider);
    final creances = peutEncaisser
        ? ref.watch(creancesProvider)
        : const AsyncValue<List<CreanceFacture>>.data([]);
    final parc = ref.watch(parcPilotageProvider).value;
    final jour = ref.watch(horlogeTableauDeBordProvider)();

    // Une lecture ÉCHOUÉE ne se lit ni « aucune réservation » ni chargement
    // sans fin : la phrase de la vue pour une donnée non lue (même écart que
    // « Chambres disponibles », nommé dans `panneau_exploitation.dart`).
    final echec = lues.hasError || ouverts.hasError || creances.hasError;
    final reservations = echec ? null : lues.value;
    final sejoursOuverts = echec ? null : ouverts.value;
    final listeCreances = echec ? null : creances.value;
    final lignes = reservations == null
        ? null
        : reservationsDuJour(reservations: reservations, jour: jour);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.mdPlus), // mb-5
      child: Container(
        key: const Key('tdb-reservations-jour'),
        clipBehavior: Clip.antiAlias,
        decoration: carteAccueil(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            EnTeteCarteTableau(
              titre: 'Réservations du jour',
              lien: 'Voir tout →',
              cleLien: const Key('tdb-reservations-jour-voir-tout'),
              // `route('pwa.reservations')`.
              onLien: () => context.go('/hebergement/reservations'),
            ),
            const _EnTeteReservations(),
            if (echec)
              _LigneVide(texte: lectureImpossible, cle: 'illisible')
            else if (lignes == null ||
                sejoursOuverts == null ||
                listeCreances == null)
              const SizedBox(height: AppSpacing.xlPlus)
            else if (lignes.isEmpty)
              const _LigneVide(
                texte: 'Aucune réservation enregistrée pour le moment.',
                cle: 'vide',
              )
            else
              for (final (i, r) in lignes.indexed)
                _LigneReservation(
                  reservation: r,
                  premiere: i == 0,
                  sejourOuvert: sejoursOuverts.contains(r.id),
                  facture: peutEncaisser
                      ? factureAPayerDe(
                          creances: listeCreances,
                          reservationId: r.id,
                        )
                      : null,
                  peutHeberger: peutHeberger,
                  uniteNumero: parc
                      ?.where((u) => u.id == r.uniteId)
                      .firstOrNull
                      ?.numero,
                ),
          ],
        ),
      ),
    );
  }
}

/// `Accueil::peutEcrire($module)` : niveau `C` sur le module écrit ET sur
/// l'écran (M11) — « le raccourci vit sur CET écran : son droit d'écriture est
/// exigé en plus de celui du module écrit ».
bool peutEcrireDepuisAccueil(GardeAcces droits, ModuleTatacora module) =>
    droits.peutEcrire(module) &&
    droits.peutEcrire(ModuleTatacora.m11TableauxDeBord);

/// Relit tout ce qu'un geste de l'accueil fait bouger : réservations, séjours,
/// parc (statut de l'unité), créances, cloche, bande d'indicateurs.
void rafraichirApresGesteAccueil(WidgetRef ref) {
  ref
    ..invalidate(reservationsPilotageProvider)
    ..invalidate(reservationsAuSejourOuvertProvider)
    ..invalidate(parcPilotageProvider)
    ..invalidate(reservationsProvider)
    ..invalidate(unitesProvider)
    ..invalidate(etatsDuJourProvider)
    ..invalidate(clientsProvider)
    ..invalidate(alertesClocheProvider);
  rafraichirEncaissements(ref);
}

/// `Client::nomComplet()` — `trim(prenom . ' ' . nom)`, le PRÉNOM d'abord :
/// c'est ce que les messages de succès du serveur nomment.
Future<String> nomCompletClient(WidgetRef ref, String clientId) async {
  final client = await ref.read(clientDaoProvider).parId(clientId);
  if (client == null) return '';
  return '${client.prenom ?? ''} ${client.nom}'.trim();
}

const List<int> _poids = MesuresAccueil.colonnesReservationsJour;

/// L'en-tête navy — `text-[11px] font-semibold text-white/90 uppercase
/// tracking-wide`, `px-5 py-2.5`, « Actions » à droite.
class _EnTeteReservations extends StatelessWidget {
  const _EnTeteReservations();

  static const List<String> _colonnes = [
    'Client',
    'Services',
    'Arrivée',
    'Départ',
    'Canal',
    'Acompte',
    'Actions',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.navy,
      child: Row(
        children: [
          for (final (i, c) in _colonnes.indexed)
            Expanded(
              flex: _poids[i],
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.mdPlus,
                  vertical: AppSpacing.xsPlus,
                ),
                child: Text(
                  c.toUpperCase(),
                  textAlign: i == _colonnes.length - 1
                      ? TextAlign.right
                      : TextAlign.left,
                  style:
                      styleExploitation(
                        TaillesContenu.t11,
                        poids: FontWeight.w600,
                        couleur: AppColors.neutre0.withValues(
                          alpha: OpacitesAccueil.enTeteTableau,
                        ),
                      ).copyWith(
                        letterSpacing:
                            AppTextStyles.suiviLarge * TaillesContenu.t11,
                      ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// `<td colspan="7" class="py-10 text-center text-slate-400 text-sm">`.
class _LigneVide extends StatelessWidget {
  const _LigneVide({required this.texte, required this.cle});

  final String texte;
  final String cle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xlPlus),
      child: Text(
        texte,
        key: Key('tdb-reservations-jour-$cle'),
        textAlign: TextAlign.center,
        style: styleExploitation(
          TaillesContenu.sm,
          interligne: TaillesContenu.interligneSm,
          couleur: AppColors.neutre400,
        ),
      ),
    );
  }
}

class _LigneReservation extends ConsumerWidget {
  const _LigneReservation({
    required this.reservation,
    required this.premiere,
    required this.sejourOuvert,
    required this.facture,
    required this.peutHeberger,
    required this.uniteNumero,
  });

  final Reservation reservation;
  final bool premiere;
  final bool sejourOuvert;
  final CreanceFacture? facture;
  final bool peutHeberger;
  final String? uniteNumero;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = reservation;
    Widget cellule(int i, Widget enfant, {bool droite = false}) => Expanded(
      flex: _poids[i],
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.mdPlus, // px-5
          vertical: AppSpacing.sm, // py-3
        ),
        child: Align(
          alignment: droite ? Alignment.centerRight : Alignment.centerLeft,
          child: enfant,
        ),
      ),
    );
    final gris = styleExploitation(
      TaillesContenu.sm,
      couleur: AppColors.neutre500,
    );

    // `array_unique(array_merge(['hebergement'], lignes->pluck('service')))` :
    // « Hébergement » toujours (une fiche a toujours une unité), puis les
    // services des lignes, sans doublon, dans leur ordre.
    final services = <ServiceReservation>[ServiceReservation.hebergement];
    for (final l in r.lignes) {
      if (!services.contains(l.service)) services.add(l.service);
    }

    final payer = facture;
    final gestes = <Widget>[
      if (payer != null)
        _BoutonLigne(
          cle: Key('tdb-payer-${r.id}'),
          libelle: 'Payer',
          bordure: PaletteMaitre.vert200,
          texte: PaletteMaitre.vert700,
          onTap: () =>
              _ouvrir(context, _ModalePayer(reservation: r, creance: payer)),
        ),
      if (payer != null && peutHeberger)
        const SizedBox(width: AppSpacing.xxs), // mr-1.5
      if (peutHeberger)
        sejourOuvert
            ? _BoutonLigne(
                cle: Key('tdb-checkout-${r.id}'),
                libelle: 'Check-out',
                bordure: AppColors.neutre200,
                texte: AppColors.neutre600,
                onTap: () => _ouvrir(context, _ModaleCheckout(reservation: r)),
              )
            : _BoutonLigne(
                cle: Key('tdb-checkin-jour-${r.id}'),
                libelle: 'Check-in',
                bordure: PaletteMaitre.emeraude200,
                texte: PaletteMaitre.emeraude700,
                onTap: () => _ouvrir(
                  context,
                  _ModaleCheckin(reservation: r, uniteNumero: uniteNumero),
                ),
              ),
    ];

    return Container(
      key: Key('tdb-reservation-jour-${r.id}'),
      decoration: BoxDecoration(
        border: premiere
            ? null
            : const Border(top: BorderSide(color: AppColors.neutre100)),
      ),
      child: Row(
        children: [
          cellule(
            0,
            Text(
              r.clientNom,
              style: styleExploitation(
                TaillesContenu.sm,
                poids: FontWeight.w500,
                couleur: AppColors.neutre700,
              ),
            ),
          ),
          cellule(
            1,
            Wrap(
              spacing: AppSpacing.unit, // gap-1
              runSpacing: AppSpacing.unit,
              children: [
                for (final s in services)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs, // px-2
                      vertical: AppSpacing.demi, // py-0.5
                    ),
                    decoration: BoxDecoration(
                      color: couleurService(
                        s,
                      ).withValues(alpha: OpacitesAccueil.fondAccesRapide),
                      borderRadius: BorderRadius.circular(AppRadius.rounded),
                    ),
                    child: Text(
                      s.nom,
                      style: styleExploitation(
                        TaillesContenu.t12,
                        poids: FontWeight.w600,
                        couleur: couleurService(s),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          cellule(2, Text(formaterDate(r.periode.arrivee), style: gris)),
          cellule(3, Text(formaterDate(r.periode.depart), style: gris)),
          // Le canal SAISI ou un tiret — jamais « Physique » d'office.
          cellule(4, Text(r.canal?.libelle ?? '—', style: gris)),
          cellule(
            5,
            Text(
              formaterFcfa(r.acompte),
              style: styleExploitation(
                TaillesContenu.sm,
                poids: FontWeight.w600,
                couleur: AppColors.gold,
              ),
            ),
          ),
          cellule(
            6,
            droite: true,
            gestes.isEmpty
                ? Text(
                    '—',
                    style: styleExploitation(
                      TaillesContenu.t12,
                      couleur: AppColors.neutre400,
                    ),
                  )
                : Row(mainAxisSize: MainAxisSize.min, children: gestes),
          ),
        ],
      ),
    );
  }

  static Future<void> _ouvrir(BuildContext context, Widget modale) =>
      showDialog<void>(context: context, builder: (_) => modale);
}

/// `text-[12px] font-semibold px-2.5 py-1 rounded border …`.
class _BoutonLigne extends StatelessWidget {
  const _BoutonLigne({
    required this.cle,
    required this.libelle,
    required this.bordure,
    required this.texte,
    required this.onTap,
  });

  final Key cle;
  final String libelle;
  final Color bordure;
  final Color texte;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.neutre0,
      borderRadius: BorderRadius.circular(AppRadius.rounded),
      child: InkWell(
        key: cle,
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.rounded),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xsPlus, // px-2.5
            vertical: AppSpacing.unit, // py-1
          ),
          decoration: BoxDecoration(
            border: Border.all(color: bordure),
            borderRadius: BorderRadius.circular(AppRadius.rounded),
          ),
          child: Text(
            libelle,
            style: styleExploitation(
              TaillesContenu.t12,
              poids: FontWeight.w600,
              couleur: texte,
            ),
          ),
        ),
      ),
    );
  }
}

/* ====================================================================== */
/* Check-in — `modale_checkin` (l.1549-1574)                               */
/* ====================================================================== */

class _ModaleCheckin extends ConsumerStatefulWidget {
  const _ModaleCheckin({required this.reservation, required this.uniteNumero});

  final Reservation reservation;
  final String? uniteNumero;

  @override
  ConsumerState<_ModaleCheckin> createState() => _ModaleCheckinState();
}

class _ModaleCheckinState extends ConsumerState<_ModaleCheckin> {
  String? _erreur;
  bool _enCours = false;

  Future<void> _confirmer() async {
    setState(() => _enCours = true);
    final r = widget.reservation;
    try {
      await ref.read(sejourDaoProvider).checkin(r.id);
    } on RefusSejour catch (refus) {
      // Le refus du service, sous la modale, modale OUVERTE (la vue).
      if (mounted) {
        setState(() {
          _erreur = refus.message;
          _enCours = false;
        });
      }
      return;
    }
    if (!mounted) return;
    final client = await nomCompletClient(ref, r.clientId);
    if (!mounted) return;
    rafraichirApresGesteAccueil(ref);
    final messager = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messager
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            // `accueil_pwa.modale_checkin.succes`.
            'Check-in enregistré pour $client.',
            key: const Key('tdb-checkin-succes'),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.reservation;
    return CoquilleModaleRestaurant(
      cle: const Key('tdb-modale-checkin'),
      titre: 'Check-in',
      largeur: MesuresAccueil.modaleRapide,
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // `<p class="text-[12px] text-slate-500">` en tête du corps.
          const AideModaleAccueil(
            'Le client et le nombre de nuits sont ceux de la réservation.',
          ),
          BlocChampAccueil(
            libelle: 'Client',
            champ: ValeurAfficheeAccueil(r.clientNom),
          ),
          BlocChampAccueil(
            libelle: 'Unité',
            champ: ValeurAfficheeAccueil(widget.uniteNumero ?? ''),
          ),
          BlocChampAccueil(
            libelle: 'Nombre de nuits',
            champ: ValeurAfficheeAccueil('${r.nuits}'),
          ),
          ErreurChampAccueil(_erreur, key: const Key('tdb-checkin-erreur')),
        ],
      ),
      actions: [
        const BoutonAnnulerAccueil(cle: Key('tdb-checkin-annuler')),
        BoutonValiderAccueil(
          cle: const Key('tdb-checkin-confirmer'),
          libelle: 'Confirmer le Check-in',
          fond: AppColors.succes,
          onPressed: _enCours ? null : _confirmer,
        ),
      ],
    );
  }
}

/* ====================================================================== */
/* Check-out — `modale_checkout` (l.1576-1591)                             */
/* ====================================================================== */

class _ModaleCheckout extends ConsumerStatefulWidget {
  const _ModaleCheckout({required this.reservation});

  final Reservation reservation;

  @override
  ConsumerState<_ModaleCheckout> createState() => _ModaleCheckoutState();
}

class _ModaleCheckoutState extends ConsumerState<_ModaleCheckout> {
  String? _erreur;
  bool _enCours = false;

  Future<void> _confirmer() async {
    setState(() => _enCours = true);
    try {
      await ref.read(sejourDaoProvider).checkout(widget.reservation.id);
    } on RefusSejour catch (refus) {
      if (mounted) {
        setState(() {
          _erreur = refus.message;
          _enCours = false;
        });
      }
      return;
    }
    if (!mounted) return;
    rafraichirApresGesteAccueil(ref);
    final messager = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messager
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            // `accueil_pwa.modale_checkout.succes`.
            "Check-out enregistré. L'unité passe en nettoyage.",
            key: Key('tdb-checkout-succes'),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return CoquilleModaleRestaurant(
      cle: const Key('tdb-modale-checkout'),
      titre: 'Check-out',
      largeur: MesuresAccueil.modaleRapide,
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const AideModaleAccueil(
            "L'unité passe en NETTOYAGE, pas en « libre » : elle n'est pas "
            "prête à recevoir tant que le ménage n'est pas fait.",
          ),
          BlocChampAccueil(
            libelle: 'Client',
            champ: ValeurAfficheeAccueil(widget.reservation.clientNom),
          ),
          ErreurChampAccueil(_erreur, key: const Key('tdb-checkout-erreur')),
        ],
      ),
      actions: [
        const BoutonAnnulerAccueil(cle: Key('tdb-checkout-annuler')),
        BoutonValiderAccueil(
          cle: const Key('tdb-checkout-confirmer'),
          libelle: 'Confirmer le départ',
          fond: AppColors.navy,
          onPressed: _enCours ? null : _confirmer,
        ),
      ],
    );
  }
}

/* ====================================================================== */
/* « Payer » — `modale_payer` (l.1649-1683)                                */
/* ====================================================================== */

/// `Accueil::ouvrirRecouvrementDuJour` / `confirmerRecouvrementDuJour` : le
/// reste dû de la facture pré-rempli (`$facture->resteDu()`, la chaîne du
/// serveur), « Espèces » par défaut, puis `EncaissementFactureService::
/// encaisser` — ici `recouvrerLaFacture`, qui passe la pièce comptable dans la
/// même transaction que le paiement.
///
/// ÉCART nommé : le serveur nomme le champ « payer montant » dans ses
/// messages de validation, ce poste « recouvrement montant » (la règle est la
/// MÊME, `required|numeric|gt:0`, et passe par l'unique validation de
/// l'encaissement, `regles_encaissement.dart`). Le montant pré-rempli rend ces
/// messages rares ; les refus du SERVICE (reste dépassé, caisse fermée,
/// pièce refusée) sont, eux, les phrases du serveur.
class _ModalePayer extends ConsumerStatefulWidget {
  const _ModalePayer({required this.reservation, required this.creance});

  final Reservation reservation;
  final CreanceFacture creance;

  @override
  ConsumerState<_ModalePayer> createState() => _ModalePayerState();
}

class _ModalePayerState extends ConsumerState<_ModalePayer> {
  late final TextEditingController _montant;
  ModePaiementFacture _mode = ModePaiementFacture.especes;
  String _client = '';
  String? _erreur;
  bool _enCours = false;

  @override
  void initState() {
    super.initState();
    _montant = TextEditingController(
      text: chaineDuServeur(widget.creance.resteDuCentimes),
    );
    // `payerClientNom = client->nomComplet()` (prénom d'abord).
    nomCompletClient(ref, widget.reservation.clientId).then((nom) {
      if (mounted) setState(() => _client = nom);
    });
  }

  @override
  void dispose() {
    _montant.dispose();
    super.dispose();
  }

  Future<void> _confirmer() async {
    setState(() => _enCours = true);
    try {
      await ref
          .read(depotPaiementsFactureProvider)
          .recouvrer(
            pieceId: widget.creance.piece.id,
            montantSaisi: _montant.text,
            modeSaisi: _mode.code,
            auteurId: ref.read(sessionProvider)?.utilisateurId ?? '',
            // `exigerEcriture(M11)` + `exigerEcriture(M2)` — pas la règle de
            // l'écran Clients (M3 + M2).
            peutEncaisser: peutEcrireDepuisAccueil(
              ref.read(droitsProvider),
              ModuleTatacora.m2Facturation,
            ),
          );
    } on RefusEncaissement catch (refus) {
      _refuser(refus.message);
      return;
    } on RefusComptable catch (refus) {
      _refuser(refus.message);
      return;
    } finally {
      // Relu que le geste ait réussi ou non (`rafraichirEncaissements`).
      if (mounted) rafraichirApresGesteAccueil(ref);
    }
    if (!mounted) return;
    final messager = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messager
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            // `accueil_pwa.modale_payer.succes`.
            'Règlement enregistré pour $_client.',
            key: const Key('tdb-payer-succes'),
          ),
        ),
      );
  }

  /// `addError('payerMontant', $refus->getMessage())` : sous le montant,
  /// modale OUVERTE — un sur-encaissement refusé doit rester lisible.
  void _refuser(String message) {
    if (!mounted) return;
    setState(() {
      _erreur = message;
      _enCours = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return CoquilleModaleRestaurant(
      cle: const Key('tdb-modale-payer'),
      titre: 'Encaisser un règlement',
      largeur: MesuresAccueil.modaleRapide,
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          BlocChampAccueil(
            libelle: 'Client',
            champ: ValeurAfficheeAccueil(_client),
          ),
          BlocChampAccueil(
            libelle: 'Montant reçu (FCFA)',
            champ: ChampTexteAccueil(
              key: const Key('tdb-payer-montant'),
              controleur: _montant,
              numerique: true,
            ),
            erreur: _erreur,
          ),
          BlocChampAccueil(
            libelle: 'Mode',
            champ: ChampChoixAccueil<ModePaiementFacture>(
              key: const Key('tdb-payer-mode'),
              valeur: _mode,
              choix: [
                for (final m in ModePaiementFacture.values) (m, m.libelle),
              ],
              onChange: (m) {
                if (m != null) setState(() => _mode = m);
              },
            ),
          ),
        ],
      ),
      actions: [
        const BoutonAnnulerAccueil(cle: Key('tdb-payer-annuler')),
        BoutonValiderAccueil(
          cle: const Key('tdb-payer-confirmer'),
          libelle: 'Enregistrer le recouvrement',
          fond: AppColors.succes,
          onPressed: _enCours ? null : _confirmer,
        ),
      ],
    );
  }
}
