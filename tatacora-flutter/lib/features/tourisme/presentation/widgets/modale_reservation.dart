// Vue Blade maîtresse (PA-183) : pwa/tourisme/departs.blade.php
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/format/formats.dart';
import '../../../../core/theme/app_colors.dart';
// `app_spacing.dart` réexporte `app_radius.dart`.
import '../../../../core/theme/app_spacing.dart';
import '../../../restaurant/presentation/widgets/coquille_modale_restaurant.dart';
import '../../../restaurant/presentation/widgets/coquille_restaurant.dart';
import '../../../crm/domain/entities/client.dart';
import '../../../restaurant/presentation/widgets/textes_modale_restaurant.dart';
import '../../domain/departs.dart';
import '../../domain/entities/circuit.dart';
import '../../domain/entities/guide.dart';
import '../providers_tourisme.dart';
import 'modale_ajout_guide.dart';

/// Ouvre **« Réserver des places »** — vue l.643-745.
///
/// Sans argument, c'est aussi le geste qui **CRÉE un départ** : le premier
/// enregistrement sur un couple (circuit, date) le fait exister. Avec
/// [circuitId] et [date], le départ est imposé et ses champs sont verrouillés.
Future<bool?> ouvrirModaleReservation(
  BuildContext context, {
  String? circuitId,
  DateTime? date,
  String? guideImposeId,
}) => showDialog<bool>(
  context: context,
  barrierDismissible: true,
  barrierColor: AppColors.voileModale,
  builder: (_) => _ModaleReservation(
    circuitId: circuitId,
    date: date,
    guideImposeId: guideImposeId,
  ),
);

class _ModaleReservation extends ConsumerStatefulWidget {
  const _ModaleReservation({this.circuitId, this.date, this.guideImposeId});

  final String? circuitId;
  final DateTime? date;
  final String? guideImposeId;

  @override
  ConsumerState<_ModaleReservation> createState() => _ModaleReservationState();
}

class _ModaleReservationState extends ConsumerState<_ModaleReservation> {
  final _nbPersonnes = TextEditingController(text: '1');

  String? _circuitId;
  DateTime? _date;
  String? _guideId;
  String? _clientId;

  bool _envoi = false;
  String? _refus;

  /// Le départ est imposé quand la modale est ouverte depuis SA ligne : ni le
  /// circuit ni la date ne peuvent alors changer (vue l.669, l.681).
  bool get _departImpose => widget.circuitId != null && widget.date != null;

  @override
  void initState() {
    super.initState();
    _circuitId = widget.circuitId;
    _date = widget.date;
    _guideId = widget.guideImposeId;
  }

  @override
  void dispose() {
    _nbPersonnes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final circuits =
        donneeOuNull(ref.watch(circuitsProvider)) ?? const <Circuit>[];
    final guides =
        donneeOuNull(ref.watch(guidesTourismeProvider)) ?? const <Guide>[];
    final clients =
        donneeOuNull(ref.watch(clientsTourismeProvider)) ?? const <Client>[];

    // Le circuit par défaut est le premier du catalogue, comme à la vue
    // (`Circuit::query()->orderBy('nom')->value('id')`).
    _circuitId ??= circuits.isEmpty ? null : circuits.first.id;
    _date ??= ref.read(periodeTourismeProvider).corrigee.debut;
    _clientId ??= clients.isEmpty ? null : clients.first.id;

    final circuit = circuits.where((c) => c.id == _circuitId).firstOrNull;
    final cle = _circuitId == null || _date == null
        ? null
        : (_circuitId!, cleDeJour(_date!));

    // ⚠ UN DÉPART A UN GUIDE, et le champ s'aligne dessus AVANT la saisie.
    //
    // Sans cela, l'écran proposerait une liste libre et l'enregistrement
    // serait refusé sur un formulaire déjà rempli. Le guide du départ se lit,
    // il ne se découvre pas au refus. L'alignement est un confort de saisie :
    // c'est le DAO qui protège, et lui seul.
    final guideEnPlace = cle == null
        ? null
        : donneeOuNull(ref.watch(guideDuDepartProvider(cle)));
    if (guideEnPlace != null) _guideId = guideEnPlace.id;
    _guideId ??= guides.isEmpty ? null : guides.first.id;

    final restantes = cle == null
        ? null
        : donneeOuNull(ref.watch(placesRestantesProvider(cle)));
    final capacite = circuit?.capaciteMax;

    return CoquilleModaleRestaurant(
      cle: const Key('tourisme-modale-reservation'),
      // Le titre de la vue (l.646), au mot.
      titre: 'Réserver des places',
      // Le sous-titre de la vue (l.647) : « :circuit — départ du :date ».
      sousTitre:
          '${circuit?.nom ?? CarteIndicateurRestaurant.absent} — départ du '
          '${_date == null ? CarteIndicateurRestaurant.absent : formaterDate(_date!)}',
      largeur: AppLayout.modaleReservationTourisme,
      refus: _refus,
      cleRefus: const Key('tourisme-modale-reservation-refus'),
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _BlocCapacite(capacite: capacite, restantes: restantes),
          const SizedBox(height: AppSpacing.sm),

          // ------------------------------------------- Prestation (l.667-675)
          if (circuits.isEmpty)
            const _Avertissement(
              cle: Key('tourisme-aucune-prestation'),
              // Le message de la vue (l.665), au mot.
              texte: 'Aucune prestation au catalogue.',
            )
          else ...[
            const EtiquetteChampRestaurant(
              texte: 'Prestation',
              obligatoire: true,
            ),
            DropdownButtonFormField<String>(
              key: const Key('tourisme-resa-prestation'),
              initialValue: _circuitId,
              isExpanded: true,
              style: TextesModaleRestaurant.corps,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: [
                for (final c in circuits)
                  DropdownMenuItem(
                    value: c.id,
                    // La vue compose « nom — prix · durée » (l.671). La durée
                    // n'est pas répliquée : elle est omise plutôt que rendue
                    // « — » au milieu d'une ligne d'option, où le tiret se
                    // lirait comme une valeur.
                    child: Text('${c.nom} — ${formaterFcfa(c.prix)}'),
                  ),
              ],
              // Départ imposé : le champ est présent et DÉSACTIVÉ, pas absent.
              onChanged: _departImpose
                  ? null
                  : (v) => setState(() {
                      _circuitId = v;
                      _guideId = null;
                    }),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),

          // --------------------------------- Date de départ + Guide (l.678-704)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _champDate()),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: _champGuide(guides, guideEnPlace)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          // ------------------------------ Client + Nombre de personnes (l.706-726)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _champClient(clients)),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: _champNombre()),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          // ------------------------------------------------- Notes (l.728-733)
          const _Note(
            cle: Key('tourisme-note-cumul'),
            texte:
                'Le contrôle porte sur le cumul des places vendues sur ce '
                'départ, pas sur cette seule réservation : trois groupes de 5 '
                'sur un circuit à 12 places sont refusés au troisième.',
          ),
          const SizedBox(height: AppSpacing.xs),
          if (guideEnPlace != null)
            const _Note(
              cle: Key('tourisme-note-guide-depart'),
              texte:
                  'Un départ a un guide : celui de sa première réservation. '
                  'Les groupes suivants le reprennent — sinon chacun '
                  'arriverait avec le sien. En changer relève de « Réaffecter '
                  'le guide », qui porte sur le départ entier (UC-39).',
            )
          else
            const _Note(
              cle: Key('tourisme-note-guide-obligatoire'),
              texte:
                  'Le guide est obligatoire dès la création : une prestation '
                  'ne peut pas exister sans lui. La réaffectation se fait '
                  'ensuite depuis la liste des départs.',
            ),
        ],
      ),
      actions: [
        OutlinedButton(
          key: const Key('tourisme-resa-annuler'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler', style: TextesModaleRestaurant.bouton),
        ),
        FilledButton(
          key: const Key('tourisme-resa-valider'),
          onPressed: _envoi ? null : _enregistrer,
          // Le libellé de la vue (l.742), au mot.
          child: const Text('Réserver', style: TextesModaleRestaurant.bouton),
        ),
      ],
    );
  }

  Widget _champDate() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const EtiquetteChampRestaurant(
          texte: 'Date de départ',
          obligatoire: true,
        ),
        OutlinedButton(
          key: const Key('tourisme-resa-date'),
          onPressed: _departImpose
              ? null
              : () async {
                  final choisi = await showDatePicker(
                    context: context,
                    initialDate: _date ?? DateTime.now(),
                    firstDate: DateTime(DateTime.now().year - 5),
                    lastDate: DateTime(DateTime.now().year + 5),
                  );
                  if (choisi == null) return;
                  // Changer de date change de DÉPART : le guide en place n'est
                  // plus forcément le bon, il se recalcule.
                  setState(() {
                    _date = jourDe(choisi);
                    _guideId = null;
                  });
                },
          child: Text(
            _date == null
                ? CarteIndicateurRestaurant.absent
                : formaterDate(_date!),
            style: TextesModaleRestaurant.corps,
          ),
        ),
      ],
    );
  }

  Widget _champGuide(List<Guide> guides, Guide? guideEnPlace) {
    // Le départ existe déjà : son guide est IMPOSÉ, on n'en ajoute pas.
    final peutAjouter = guideEnPlace == null && !_departImpose;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const EtiquetteChampRestaurant(texte: 'Guide', obligatoire: true),
        if (guides.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: AppSpacing.xxs),
            child: _Avertissement(
              cle: Key('tourisme-aucun-guide'),
              // Le message de la vue, au mot.
              texte:
                  'Aucun guide au référentiel — une réservation ne peut pas '
                  'être prise sans lui.',
            ),
          )
        else
          DropdownButtonFormField<String>(
            key: const Key('tourisme-resa-guide'),
            initialValue: _guideId,
            isExpanded: true,
            style: TextesModaleRestaurant.corps,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
            ),
            items: [
              for (final g in guides)
                DropdownMenuItem(value: g.id, child: Text(g.nom)),
            ],
            // Le départ existe déjà : son guide est IMPOSÉ. Le champ reste
            // rendu et lié — il n'est pas libre, il n'est pas absent.
            onChanged: guideEnPlace != null || _departImpose
                ? null
                : (v) => setState(() => _guideId = v),
          ),
        if (peutAjouter)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const Key('tourisme-resa-guide-ajouter'),
              onPressed: _ajouterGuide,
              child: const Text('+ Ajouter'),
            ),
          ),
      ],
    );
  }

  /// Ouvre « Ajouter un guide touristique » et sélectionne le guide créé.
  Future<void> _ajouterGuide() async {
    final guide = await ouvrirModaleAjoutGuide(context);
    if (guide == null || !mounted) return;
    setState(() => _guideId = guide.id);
  }

  Widget _champClient(List<Client> clients) {
    if (clients.isEmpty) {
      return const _Avertissement(
        cle: Key('tourisme-aucun-client'),
        // Le message de la vue (l.711), au mot.
        texte:
            'Aucun client au référentiel — créez-le d\'abord depuis '
            '« Clients & Créances ».',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // RG-18 : le client est une CLÉ ÉTRANGÈRE, jamais un nom libre.
        const EtiquetteChampRestaurant(texte: 'Client', obligatoire: true),
        DropdownButtonFormField<String>(
          key: const Key('tourisme-resa-client'),
          initialValue: _clientId,
          isExpanded: true,
          style: TextesModaleRestaurant.corps,
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
          ),
          items: [
            for (final c in clients)
              DropdownMenuItem<String>(value: c.id, child: Text(c.nomComplet)),
          ],
          onChanged: (v) => setState(() => _clientId = v),
        ),
      ],
    );
  }

  Widget _champNombre() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const EtiquetteChampRestaurant(
          texte: 'Nombre de personnes',
          obligatoire: true,
        ),
        TextField(
          key: const Key('tourisme-resa-nb-personnes'),
          controller: _nbPersonnes,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: TextesModaleRestaurant.corps,
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  Future<void> _enregistrer() async {
    final circuitId = _circuitId;
    final date = _date;
    final guideId = _guideId;
    final clientId = _clientId;

    // ⚠ Un nombre VIDE n'est pas un 1. `int.tryParse('')` rend `null`, et
    // retomber sur 1 facturerait une place que personne n'a demandée — c'est
    // la leçon de `QuantiteSaisie` au panier (PA-98).
    final nb = int.tryParse(_nbPersonnes.text.trim());

    if (circuitId == null ||
        date == null ||
        guideId == null ||
        clientId == null ||
        nb == null) {
      setState(
        () => _refus =
            'Prestation, date de départ, guide, client et nombre de personnes '
            'sont tous obligatoires.',
      );
      return;
    }

    setState(() {
      _envoi = true;
      _refus = null;
    });

    try {
      final reservation = await ref
          .read(tourismeDaoProvider)
          .reserver(
            circuitId: circuitId,
            clientId: clientId,
            guideId: guideId,
            dateCircuit: date,
            nbParticipants: nb,
          );

      if (!mounted) return;

      rechargerTourisme(ref);
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const Key('tourisme-reservation-faite'),
          // Le message de la vue (`tourisme.pwa.reservation_faite`), au mot.
          content: Text(
            'Réservation de $nb place(s) enregistrée pour '
            '${reservation.clientNom}.',
          ),
        ),
      );
    } on RefusTourisme catch (e) {
      // Le refus du domaine est affiché TEL QUEL, dans la modale : la saisie
      // est encore là, et le message doit rester lisible pendant qu'on la
      // corrige. Le réécrire ici donnerait une seconde règle de capacité.
      if (!mounted) return;
      setState(() {
        _envoi = false;
        _refus = e.message;
      });
    }
  }
}

/// Le bloc « Capacité / Déjà vendues / Restantes » — vue l.652-662.
class _BlocCapacite extends StatelessWidget {
  const _BlocCapacite({required this.capacite, required this.restantes});

  final int? capacite;
  final int? restantes;

  @override
  Widget build(BuildContext context) {
    final vendues = capacite == null || restantes == null
        ? null
        : capacite! - restantes!;

    Widget ligne(String libelle, String valeur, {Color? couleur, Key? cle}) =>
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.demi),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(libelle, style: TextesRestaurant.corps),
              Text(
                valeur,
                key: cle,
                style: TextesRestaurant.corpsFort.copyWith(color: couleur),
              ),
            ],
          ),
        );

    return Container(
      // `bg-slate-50 border border-slate-200 rounded-lg p-3`.
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: Ardoise.c50,
        border: Border.all(color: Ardoise.c200),
        borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ligne(
            'Capacité',
            capacite?.toString() ?? CarteIndicateurRestaurant.absent,
            cle: const Key('tourisme-bloc-capacite'),
          ),
          ligne(
            'Déjà vendues',
            vendues?.toString() ?? CarteIndicateurRestaurant.absent,
            cle: const Key('tourisme-bloc-vendues'),
          ),
          ligne(
            'Restantes',
            restantes?.toString() ?? CarteIndicateurRestaurant.absent,
            couleur: PaletteMaitre.emeraude700,
            cle: const Key('tourisme-bloc-restantes'),
          ),
        ],
      ),
    );
  }
}

/// Une note explicative de la modale — `text-[11px] text-slate-500 bg-slate-50`.
class _Note extends StatelessWidget {
  const _Note({required Key cle, required this.texte}) : super(key: cle);

  final String texte;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xsPlus),
      decoration: BoxDecoration(
        color: Ardoise.c50,
        border: Border.all(color: Ardoise.c200),
        borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      ),
      child: Text(texte, style: TextesRestaurant.mention),
    );
  }
}

/// Un référentiel vide — `text-[12px] text-amber-700` de la vue.
class _Avertissement extends StatelessWidget {
  const _Avertissement({required Key cle, required this.texte})
    : super(key: cle);

  final String texte;

  @override
  Widget build(BuildContext context) {
    return Text(
      texte,
      style: TextesRestaurant.secondaire.copyWith(
        color: PaletteMaitre.ambre700,
      ),
    );
  }
}
