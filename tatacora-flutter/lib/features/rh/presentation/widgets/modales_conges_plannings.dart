// Vue Blade maîtresse (PA-183) : pwa/rh/conges-plannings.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../restaurant/presentation/widgets/coquille_modale_restaurant.dart';
import '../../../restaurant/presentation/widgets/textes_modale_restaurant.dart';
import '../../domain/entities/conge_planning.dart';
import '../providers_conges_plannings.dart';

/// Les deux modales de l'écran, `largeur="520px"` : « Planifier un créneau »
/// (RG-13) et « Demander un congé » (RG-14 s'applique à la VALIDATION, pas au
/// dépôt). Elles ne stockent rien elles-mêmes : le DAO écrit et enfile, la
/// phrase du refus est celle du serveur et s'affiche DANS la modale, saisie
/// conservée.
///
/// Chacune rend le message de succès de la vue (`planning_enregistre`,
/// `conge_demande`) — `null` si on a annulé.
Future<String?> ouvrirModalePlanning(BuildContext context) =>
    showDialog<String>(
      context: context,
      barrierColor: AppColors.voileModale,
      builder: (_) => const _ModalePlanning(),
    );

Future<String?> ouvrirModaleConge(BuildContext context) => showDialog<String>(
  context: context,
  barrierColor: AppColors.voileModale,
  builder: (_) => const _ModaleConge(),
);

/// Un jour en `JJ/MM/AAAA` (`jj/mm/aaaa` tant qu'il n'est pas choisi).
String _affiche(DateTime? d) => d == null
    ? 'jj/mm/aaaa'
    : '${d.day.toString().padLeft(2, '0')}/'
          '${d.month.toString().padLeft(2, '0')}/${d.year.toString().padLeft(4, '0')}';

/// Un sélecteur d'employé « Choisir… » — la liste des employés EN POSTE.
class _ChoixEmploye extends StatelessWidget {
  const _ChoixEmploye({
    required this.cle,
    required this.employes,
    required this.valeur,
    required this.erreur,
    required this.onChoix,
  });

  final Key cle;
  final List<EmployePlanifiable> employes;
  final String? valeur;
  final String? erreur;
  final ValueChanged<String?> onChoix;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const EtiquetteChampRestaurant(texte: 'Employé', obligatoire: true),
        DropdownButtonFormField<String>(
          key: cle,
          initialValue: employes.any((e) => e.id == valeur) ? valeur : null,
          isExpanded: true,
          style: TextesModaleRestaurant.corps,
          decoration: InputDecoration(
            isDense: true,
            border: const OutlineInputBorder(),
            errorText: erreur,
            errorMaxLines: 3,
          ),
          hint: const Text('Choisir…'),
          items: [
            for (final e in employes)
              DropdownMenuItem(
                value: e.id,
                child: Text(e.nomComplet, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: onChoix,
        ),
      ],
    );
  }
}

/// Un champ date : étiquette + bouton qui ouvre le sélecteur.
class _ChampJour extends StatelessWidget {
  const _ChampJour({
    required this.cle,
    required this.etiquette,
    required this.valeur,
    required this.erreur,
    required this.onChoix,
  });

  final Key cle;
  final String etiquette;
  final DateTime? valeur;
  final String? erreur;
  final ValueChanged<DateTime> onChoix;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        EtiquetteChampRestaurant(texte: etiquette, obligatoire: true),
        OutlinedButton(
          key: cle,
          onPressed: () async {
            final n = DateTime.now();
            final choisi = await showDatePicker(
              context: context,
              initialDate: valeur ?? n,
              firstDate: DateTime(n.year - 5),
              lastDate: DateTime(n.year + 5),
            );
            if (choisi != null) onChoix(choisi);
          },
          child: Text(_affiche(valeur), style: TextesModaleRestaurant.corps),
        ),
        if (erreur != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.demi),
            child: Text(
              erreur!,
              style: TextesModaleRestaurant.aide.copyWith(
                color: AppColors.erreur,
              ),
            ),
          ),
      ],
    );
  }
}

/// Un champ heure (`HH:MM`).
class _ChampHeure extends StatelessWidget {
  const _ChampHeure({
    required this.cle,
    required this.etiquette,
    required this.valeur,
    required this.onChoix,
  });

  final Key cle;
  final String etiquette;
  final String valeur;
  final ValueChanged<String> onChoix;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        EtiquetteChampRestaurant(texte: etiquette),
        OutlinedButton(
          key: cle,
          onPressed: () async {
            final p = valeur.split(':');
            final choisi = await showTimePicker(
              context: context,
              initialTime: TimeOfDay(
                hour: int.tryParse(p.first) ?? 8,
                minute: int.tryParse(p.last) ?? 0,
              ),
              builder: (context, enfant) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(alwaysUse24HourFormat: true),
                child: enfant!,
              ),
            );
            if (choisi == null) return;
            onChoix(
              '${choisi.hour.toString().padLeft(2, '0')}:'
              '${choisi.minute.toString().padLeft(2, '0')}',
            );
          },
          child: Text(valeur, style: TextesModaleRestaurant.corps),
        ),
      ],
    );
  }
}

/* ====================================================================== */
/* Planifier un créneau                                                    */
/* ====================================================================== */

class _ModalePlanning extends ConsumerStatefulWidget {
  const _ModalePlanning();

  @override
  ConsumerState<_ModalePlanning> createState() => _ModalePlanningState();
}

class _ModalePlanningState extends ConsumerState<_ModalePlanning> {
  String? _employe;
  String? _service;
  late DateTime _date = ref.read(jourPlanningsProvider);
  String _debut = '08:00';
  String _fin = '16:00';

  bool _envoi = false;
  String? _refus;

  @override
  Widget build(BuildContext context) {
    final employes = switch (ref.watch(employesEnPosteProvider)) {
      AsyncData(value: final v) => v,
      _ => const <EmployePlanifiable>[],
    };
    final services = switch (ref.watch(servicesRhProvider)) {
      AsyncData(value: final v) => v,
      _ => const <({String id, String libelle})>[],
    };

    return CoquilleModaleRestaurant(
      cle: const Key('modale-planning'),
      titre: 'Planifier un créneau',
      largeur: AppLayout.modaleCongesPlannings,
      refus: _refus,
      cleRefus: const Key('modale-planning-refus'),
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _ChoixEmploye(
            cle: const Key('modale-planning-employe'),
            employes: employes,
            valeur: _employe,
            erreur: null,
            onChoix: (v) => setState(() => _employe = v),
          ),
          const SizedBox(height: AppSpacing.md),
          const EtiquetteChampRestaurant(texte: 'Service', obligatoire: true),
          DropdownButtonFormField<String>(
            key: const Key('modale-planning-service'),
            initialValue: services.any((s) => s.id == _service)
                ? _service
                : null,
            isExpanded: true,
            style: TextesModaleRestaurant.corps,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
            ),
            hint: const Text('Choisir…'),
            items: [
              for (final s in services)
                DropdownMenuItem(value: s.id, child: Text(s.libelle)),
            ],
            onChanged: (v) => setState(() => _service = v),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _ChampJour(
                  cle: const Key('modale-planning-date'),
                  etiquette: 'Date',
                  valeur: _date,
                  erreur: null,
                  onChoix: (d) => setState(() => _date = d),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _ChampHeure(
                  cle: const Key('modale-planning-debut'),
                  etiquette: 'De',
                  valeur: _debut,
                  onChoix: (h) => setState(() => _debut = h),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _ChampHeure(
                  cle: const Key('modale-planning-fin'),
                  etiquette: 'À',
                  valeur: _fin,
                  onChoix: (h) => setState(() => _fin = h),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('modale-planning-annuler'),
          onPressed: _envoi ? null : () => Navigator.of(context).pop(),
          child: const Text('Annuler', style: TextesModaleRestaurant.bouton),
        ),
        FilledButton(
          key: const Key('modale-planning-valider'),
          onPressed: _envoi ? null : _enregistrer,
          child: const Text(
            'Enregistrer',
            style: TextesModaleRestaurant.bouton,
          ),
        ),
      ],
    );
  }

  Future<void> _enregistrer() async {
    setState(() {
      _envoi = true;
      _refus = null;
    });
    try {
      await ref
          .read(congesPlanningsDaoProvider)
          .planifier(
            employeId: _employe,
            serviceId: _service,
            date: _date,
            heureDebut: _debut,
            heureFin: _fin,
          );
      // La vue montre le jour qu'on vient de planifier.
      ref.read(jourPlanningsProvider.notifier).definir(_date);
      if (!mounted) return;
      Navigator.of(context).pop('Créneau planifié.');
    } on RefusCongesPlannings catch (refus) {
      if (!mounted) return;
      setState(() {
        _envoi = false;
        _refus = refus.message;
      });
    }
  }
}

/* ====================================================================== */
/* Demander un congé                                                       */
/* ====================================================================== */

class _ModaleConge extends ConsumerStatefulWidget {
  const _ModaleConge();

  @override
  ConsumerState<_ModaleConge> createState() => _ModaleCongeState();
}

class _ModaleCongeState extends ConsumerState<_ModaleConge> {
  String? _employe;
  TypeConge _type = TypeConge.values.first;
  // « Du » et « Au » s'ouvrent sur dans sept jours, comme la vue.
  late DateTime _debut = _dansSeptJours();
  late DateTime _fin = _dansSeptJours();

  bool _envoi = false;
  String? _refus;

  static DateTime _dansSeptJours() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day + 7);
  }

  @override
  Widget build(BuildContext context) {
    final employes = switch (ref.watch(employesEnPosteProvider)) {
      AsyncData(value: final v) => v,
      _ => const <EmployePlanifiable>[],
    };

    return CoquilleModaleRestaurant(
      cle: const Key('modale-conge'),
      titre: 'Demander un congé',
      largeur: AppLayout.modaleCongesPlannings,
      refus: _refus,
      cleRefus: const Key('modale-conge-refus'),
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _ChoixEmploye(
            cle: const Key('modale-conge-employe'),
            employes: employes,
            valeur: _employe,
            erreur: null,
            onChoix: (v) => setState(() => _employe = v),
          ),
          const SizedBox(height: AppSpacing.md),
          const EtiquetteChampRestaurant(texte: 'Nature', obligatoire: true),
          DropdownButtonFormField<TypeConge>(
            key: const Key('modale-conge-type'),
            initialValue: _type,
            isExpanded: true,
            style: TextesModaleRestaurant.corps,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
            ),
            items: [
              for (final t in TypeConge.values)
                DropdownMenuItem(value: t, child: Text(t.libelle)),
            ],
            onChanged: (t) => setState(() => _type = t ?? _type),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _ChampJour(
                  cle: const Key('modale-conge-du'),
                  etiquette: 'Du',
                  valeur: _debut,
                  erreur: null,
                  onChoix: (d) => setState(() => _debut = d),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _ChampJour(
                  cle: const Key('modale-conge-au'),
                  etiquette: 'Au',
                  valeur: _fin,
                  erreur: null,
                  onChoix: (d) => setState(() => _fin = d),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('modale-conge-annuler'),
          onPressed: _envoi ? null : () => Navigator.of(context).pop(),
          child: const Text('Annuler', style: TextesModaleRestaurant.bouton),
        ),
        FilledButton(
          key: const Key('modale-conge-valider'),
          onPressed: _envoi ? null : _enregistrer,
          child: const Text(
            'Enregistrer',
            style: TextesModaleRestaurant.bouton,
          ),
        ),
      ],
    );
  }

  Future<void> _enregistrer() async {
    setState(() {
      _envoi = true;
      _refus = null;
    });
    try {
      await ref
          .read(congesPlanningsDaoProvider)
          .demander(
            employeId: _employe,
            type: _type,
            dateDebut: _debut,
            dateFin: _fin,
          );
      // La vue bascule sur l'onglet des congés pour montrer la demande.
      ref
          .read(ongletCongesPlanningsProvider.notifier)
          .definir(OngletCongesPlannings.conges);
      if (!mounted) return;
      Navigator.of(
        context,
      ).pop('Demande de congé enregistrée : elle attend sa validation.');
    } on RefusCongesPlannings catch (refus) {
      if (!mounted) return;
      setState(() {
        _envoi = false;
        _refus = refus.message;
      });
    }
  }
}
