// Vue Blade maîtresse (PA-183) : pwa/hebergement/reservations.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/format/formats.dart';
import '../../../core/rbac/garde_acces.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_durations.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared_widgets/bouton_standard.dart';
import '../../bar/presentation/widgets/modale_export_carte.dart';
import '../domain/entities/historique_reservations.dart';
import '../domain/entities/service_reservation.dart';
import '../impression/etat_historique.dart';
import 'providers_hebergement.dart';
import 'widgets/modale_annulation_reservation.dart';
import 'widgets/vue_services.dart';

/// Ouvre le panneau **Historique des réservations**.
///
/// ## Pourquoi une fonction, et pas seulement un widget
///
/// Le maître l'ouvre depuis **deux endroits** : l'en-tête de la page, et la
/// modale de saisie (`historique-reservations.js` l.5-11). La raison du second
/// point d'entrée est écrite là-bas et vaut d'être portée telle quelle : *« au
/// moment de créer une réservation, la question la plus fréquente est ce client
/// est-il déjà venu ? Devoir fermer la modale pour aller vérifier ferait perdre
/// la saisie en cours »*. Le panneau se **superpose** donc, il ne remplace
/// rien, et il arrive **pré-rempli** avec le nom déjà tapé.
///
/// Deux appels, un seul geste : recopier le `showGeneralDialog` dans chaque
/// écran ferait deux panneaux qui divergeraient au premier réglage.
Future<void> ouvrirHistoriqueReservations(
  BuildContext context, {
  String termePrerempli = '',
}) {
  return showGeneralDialog<void>(
    context: context,
    // Le voile sombre du maître (`bg-black/40`), et la fermeture au clic
    // dehors comme au `data-fermer-historique`.
    barrierColor: AppColors.voileModale,
    barrierDismissible: true,
    barrierLabel: 'Fermer l’historique',

    /// ECART DELIBERE — `prototype_v2/pages/reservations.html` l.61-63
    /// Le prototype : le panneau n'a AUCUNE transition. Il bascule une classe
    /// `hidden` et apparait instantanement ; aucune classe `transition*`,
    /// `duration-*` ni regle CSS ne le concerne.
    /// Ici : la duree d'ouverture des surfaces superposees du maitre,
    /// `.overlay-modale { transition: opacity .2s ease }` (app.css l.72).
    /// Raison : contrainte de plateforme. Un `showGeneralDialog` de Flutter
    /// anime toujours son entree ; a duree nulle, le panneau plein ecran
    /// surgit d'un coup sur un poste de comptoir. La valeur retenue est celle
    /// que le maitre applique a ses propres surfaces superposees — elle n'est
    /// donc pas inventee. Elle l'etait avant le 26/08/2026 : ce champ portait
    /// 180 ms, une valeur qui ne figure NULLE PART dans le maitre.
    transitionDuration: AppDurations.modale,
    pageBuilder: (_, _, _) => PanneauHistorique(termePrerempli: termePrerempli),
    transitionBuilder: (context, animation, _, enfant) {
      // Le panneau vient de la DROITE, comme le `inset-y-0 right-0` du maître.
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
        child: enfant,
      );
    },
  );
}

/// Le panneau **Historique des réservations** — `reservations.html` l.61-104.
///
/// ## Ce que ce panneau existe pour montrer
///
/// La liste principale ne montre que le présent. Un séjour terminé la semaine
/// dernière n'y figure plus, et « ce client est-il déjà venu ? » n'a alors
/// aucune réponse à l'écran. Le panneau porte les quatre états, les filtres et
/// les six indicateurs.
///
/// ## Les données viennent du LOCAL, comme partout ailleurs
///
/// Aucun appel réseau : `reservationsProvider` lit la base Drift. Le panneau
/// s'ouvre donc entier hors connexion — c'est précisément au comptoir, sans
/// réseau, qu'on a besoin de savoir ce qu'un client doit encore.
class PanneauHistorique extends ConsumerStatefulWidget {
  const PanneauHistorique({this.termePrerempli = '', super.key});

  final String termePrerempli;

  @override
  ConsumerState<PanneauHistorique> createState() => _PanneauHistoriqueState();
}

class _PanneauHistoriqueState extends ConsumerState<PanneauHistorique> {
  late final TextEditingController _terme = TextEditingController(
    text: widget.termePrerempli,
  );

  FiltreHistorique _filtre = const FiltreHistorique();

  /// Ce que les deux boutons d'export enverront — composé au dernier rendu.
  /// `null` tant que les réservations n'ont pas été lues : les boutons sont
  /// alors inertes plutôt que d'exporter un document vide qu'on prendrait pour
  /// un historique vide.
  EtatHistorique? _etatCourant;

  @override
  void initState() {
    super.initState();
    _filtre = FiltreHistorique(terme: widget.termePrerempli);
  }

  @override
  void dispose() {
    _terme.dispose();
    super.dispose();
  }

  void _reinitialiser() {
    setState(() {
      _terme.clear();
      _filtre = const FiltreHistorique();
    });
  }

  @override
  Widget build(BuildContext context) {
    final reservations = ref.watch(reservationsProvider);

    // ⚠ L'état d'export se compose ICI, AVANT l'en-tête qui porte les deux
    // boutons — et non dans la branche `data` plus bas.
    //
    // Le défaut que cet ordre évite est un défaut de séquence, invisible à la
    // relecture : l'en-tête est construite avant le corps dans la même passe.
    // Un état posé dans la branche `data` n'aurait donc jamais été vu par
    // l'en-tête du même rendu, et rien ne déclenchait de rendu suivant — les
    // deux boutons seraient restés grisés **pour toujours**, sur un panneau
    // par ailleurs parfaitement fonctionnel.
    final lignes = reservations.maybeWhen(
      data: (liste) =>
          filtrerHistorique(liste, filtre: _filtre, maintenant: DateTime.now()),
      orElse: () => null,
    );
    final kpis = lignes == null ? null : KpisHistorique.calculer(lignes);
    // Ce qui part au PDF est EXACTEMENT ce que l'utilisateur a sous les yeux,
    // filtres compris : les mêmes lignes, pas un second calcul.
    _etatCourant = (lignes == null || kpis == null)
        ? null
        : EtatHistorique.composer(lignes: lignes, kpis: kpis, filtre: _filtre);

    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        // `max-w-5xl` du maître : 1024 px, valeur mesurée et non supposée.
        constraints: const BoxConstraints(maxWidth: AppLayout.panneauLateral),
        child: Material(
          color: AppColors.neutre0,
          child: SafeArea(
            child: Column(
              children: [
                _entete(context),
                Expanded(
                  child: reservations.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('$e')),
                    data: (_) => Column(
                      children: [
                        _Kpis(kpis: kpis!),
                        _filtres(context),
                        Expanded(child: _liste(lignes!)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _entete(BuildContext context) {
    final textes = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.neutre200)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Historique des réservations',
                  style: textes.titleMedium?.copyWith(color: AppColors.navy),
                ),
                Text(
                  'Toutes les réservations, passées et à venir, avec leur '
                  'état réel.',
                  style: textes.labelSmall?.copyWith(
                    color: AppColors.neutre500,
                  ),
                ),
              ],
            ),
          ),
          // UN bouton « Exporter » qui ouvre la modale d'export PARTAGÉE
          // (demande du PO du 14/10/2026 ; vue des réservations, modale
          // `hebergement_pwa.reservations.export_titre`) : la paire
          // « PDF » / « Excel » de l'ancien maître est fusionnée, le format se
          // choisit dans la modale.
          BoutonStandard(
            key: const Key('hist-exporter'),
            libelle: TextesExport.bouton,
            onPressed: _etatCourant == null ? null : _choisirExport,
          ),
          const SizedBox(width: AppSpacing.unit),
          IconButton(
            key: const Key('fermer-historique'),
            tooltip: 'Fermer',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _filtres(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.neutre200)),
      ),
      child: Wrap(
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: AppLayout.champRechercheHistorique,
            child: TextField(
              key: const Key('hist-terme'),
              controller: _terme,
              decoration: const InputDecoration(
                hintText: 'Client, canal ou n°…',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (v) =>
                  setState(() => _filtre = _filtre.copyWith(terme: v)),
            ),
          ),
          _Choix<EtatSejour>(
            cle: const Key('hist-etat'),
            valeur: _filtre.etat,
            libelleVide: 'Tous les états',
            options: EtatSejour.values,
            // Le PLURIEL du maître : une option de filtre désigne un ensemble.
            libelle: (e) => e.libelleFiltre,
            onChange: (e) => setState(
              () => _filtre = e == null
                  ? _filtre.copyWith(viderEtat: true)
                  : _filtre.copyWith(etat: e),
            ),
          ),
          _Choix<ServiceReservation>(
            cle: const Key('hist-service'),
            valeur: _filtre.service,
            libelleVide: 'Tous les services',
            options: ServiceReservation.values,
            libelle: (s) => s.nom,
            onChange: (s) => setState(
              () => _filtre = s == null
                  ? _filtre.copyWith(viderService: true)
                  : _filtre.copyWith(service: s),
            ),
          ),
          _ChampDateFiltre(
            cle: const Key('hist-debut'),
            etiquette: 'Depuis',
            valeur: _filtre.debut,
            onChange: (d) => setState(
              () => _filtre = d == null
                  ? _filtre.copyWith(viderDebut: true)
                  : _filtre.copyWith(debut: d),
            ),
          ),
          _ChampDateFiltre(
            cle: const Key('hist-fin'),
            etiquette: 'Jusqu’à',
            valeur: _filtre.fin,
            onChange: (d) => setState(
              () => _filtre = d == null
                  ? _filtre.copyWith(viderFin: true)
                  : _filtre.copyWith(fin: d),
            ),
          ),
          OutlinedButton(
            key: const Key('hist-reset'),
            onPressed: _reinitialiser,
            child: const Text('Réinitialiser'),
          ),
        ],
      ),
    );
  }

  Widget _liste(List<LigneHistorique> lignes) {
    if (lignes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Text(
            'Aucune réservation ne correspond à ces filtres.',
            key: const Key('hist-vide'),
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: AppColors.neutre500),
          ),
        ),
      );
    }

    // Deux défilements imbriqués, et c'est le tableau du maître : neuf colonnes
    // ne tiennent pas dans un panneau, il défile horizontalement dans son
    // propre conteneur — jamais la page entière.
    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStatePropertyAll(AppColors.neutre100),
          columns: const [
            DataColumn(label: Text('Client')),
            DataColumn(label: Text('Séjour')),
            DataColumn(label: Text('Nuits'), numeric: true),
            DataColumn(label: Text('Unités')),
            DataColumn(label: Text('Services')),
            DataColumn(label: Text('Total'), numeric: true),
            DataColumn(label: Text('Reste dû'), numeric: true),
            DataColumn(label: Text('État')),
            DataColumn(label: Text('')),
          ],
          rows: [for (final l in lignes) _ligne(l)],
        ),
      ),
    );
  }

  DataRow _ligne(LigneHistorique l) {
    final textes = Theme.of(context).textTheme;
    final annulee = l.etat == EtatSejour.annulee;

    return DataRow(
      key: ValueKey('hist-ligne-${l.reservation.id}'),
      // Le maître grise la ligne annulée (`opacity-60`) : elle reste lisible,
      // elle n'est jamais retirée — une réservation annulée qui disparaît de
      // l'historique laisse croire qu'elle n'a jamais existé.
      color: annulee ? const WidgetStatePropertyAll(AppColors.neutre100) : null,
      cells: [
        DataCell(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(l.client, style: textes.bodyMedium),
              Text(
                l.canal ?? '—',
                style: textes.labelSmall?.copyWith(color: AppColors.neutre500),
              ),
            ],
          ),
        ),
        DataCell(
          Text(
            '${formaterDate(l.reservation.periode.arrivee)} → '
            '${formaterDate(l.reservation.periode.depart)}',
          ),
        ),
        DataCell(Text('${l.nuits}')),
        DataCell(
          Text(
            l.unites.isEmpty ? '—' : l.unites.join(', '),
            style: textes.labelSmall,
          ),
        ),
        DataCell(
          Wrap(
            spacing: AppSpacing.unit,
            children: [
              for (final s in l.services)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.unit,
                    vertical: AppSpacing.demi,
                  ),
                  decoration: BoxDecoration(
                    color: couleurService(s).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Text(
                    s.nom,
                    style: textes.labelSmall?.copyWith(
                      color: couleurService(s),
                    ),
                  ),
                ),
            ],
          ),
        ),
        DataCell(
          Text(formaterFcfa(l.totalAPayer), style: AppTextStyles.montant),
        ),
        DataCell(
          Text(
            formaterFcfa(l.resteAPayer),
            // Un reste dû est une créance : le maître le passe en rouge dès
            // qu'il dépasse zéro, et en gris quand il est soldé.
            style: AppTextStyles.montant.copyWith(
              color: l.resteAPayer > 0 ? AppColors.erreur : AppColors.neutre500,
            ),
          ),
        ),
        DataCell(_Etat(etat: l.etat)),
        DataCell(_actionAnnuler(l)),
      ],
    );
  }

  Widget _actionAnnuler(LigneHistorique l) {
    // Le maître n'offre « annuler » que sur un séjour ni terminé ni déjà
    // annulé : annuler un séjour consommé ne libère rien et fausserait le
    // chiffre d'affaires du mois écoulé.
    final annulable =
        l.etat != EtatSejour.annulee && l.etat != EtatSejour.termine;
    if (!annulable) return const SizedBox.shrink();

    // Le droit d'écriture sur M1 commande l'action, comme dans la liste : un
    // bouton retiré plutôt que grisé, pour ne pas inviter à un refus.
    if (!ref.watch(droitsProvider).peutEcrire(ModuleTatacora.m1Hebergement)) {
      return const SizedBox.shrink();
    }

    return TextButton(
      key: Key('hist-annuler-${l.reservation.id}'),
      onPressed: () => _demanderAnnulation(l),
      child: const Text('annuler'),
    );
  }

  /// `hebergement_pwa.reservations.export_titre` / `export_sous_titre` et
  /// `export_vide`, au mot.
  static const String _titreExport = 'Exporter — Historique des réservations';
  static const String _sousTitreExport =
      "L'historique tel qu'il est affiché, filtres compris.";
  static const String _exportVide =
      "Aucune réservation ne correspond aux filtres : il n'y a rien à "
      'exporter.';

  /// La modale partagée, puis le document du format choisi — sur les lignes
  /// AFFICHÉES, filtres compris (PA-119). Une liste vide se refuse.
  Future<void> _choisirExport() async {
    final format = await choisirFormatExport(
      context,
      titre: _titreExport,
      sousTitre: _sousTitreExport,
    );
    if (format == null || !mounted) return;
    final etat = _etatCourant;
    if (etat == null || etat.lignes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(_exportVide, key: Key('hist-export-vide')),
        ),
      );
      return;
    }
    switch (format) {
      case FormatExport.pdf:
        await _imprimer();
      case FormatExport.excel:
        await _exporter();
    }
  }

  Future<void> _imprimer() async {
    final etat = _etatCourant;
    if (etat == null) return;
    await ref.read(imprimerEtatHistoriqueProvider)(etat);
  }

  Future<void> _exporter() async {
    final etat = _etatCourant;
    if (etat == null) return;

    final chemin = await ref.read(exporterEtatHistoriqueProvider)(etat);
    if (!mounted) return;

    // Le chemin est DIT. Un export silencieux est un export que personne ne
    // retrouve : l'utilisateur clique, rien ne bouge à l'écran, et il
    // recommence jusqu'à croire que la fonction est cassée.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Export enregistré sur ce poste : $chemin',
          key: const Key('hist-export-chemin'),
        ),
      ),
    );
  }

  /// Le MÊME geste que la carte : la modale du serveur (taux, commission,
  /// remboursement). Le motif seul d'avant le lot 6 n'existe plus — un seul
  /// chemin d'annulation, donc une seule pièce.
  Future<void> _demanderAnnulation(LigneHistorique l) async {
    final annulee = await ouvrirModaleAnnulationReservation(
      context,
      ref,
      l.reservation,
    );
    if (!annulee || !mounted) return;
    setState(() {});
  }
}

/// Les six indicateurs, dans l'ordre du maître.
class _Kpis extends StatelessWidget {
  const _Kpis({required this.kpis});

  final KpisHistorique kpis;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.neutre200)),
      ),
      child: Wrap(
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        children: [
          _Kpi(libelle: 'Réservations', valeur: '${kpis.total}'),
          _Kpi(
            libelle: 'À venir',
            valeur: '${kpis.aVenir}',
            couleur: AppColors.infoBleuTexte,
          ),
          _Kpi(
            libelle: 'En cours',
            valeur: '${kpis.enCours}',
            couleur: AppColors.succes,
          ),
          _Kpi(libelle: 'Nuitées', valeur: '${kpis.nuitees}'),
          _Kpi(
            libelle: 'Chiffre d’affaires',
            valeur: formaterFcfa(kpis.chiffreAffaires),
          ),
          _Kpi(
            libelle: 'Reste à encaisser',
            valeur: formaterFcfa(kpis.resteAEncaisser),
            // Rouge tant qu'il reste quelque chose à encaisser, vert quand
            // tout est soldé : c'est la couleur du maître, et elle dit s'il y
            // a une relance à faire.
            couleur: kpis.resteAEncaisser > 0
                ? AppColors.erreur
                : AppColors.succes,
          ),
        ],
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({required this.libelle, required this.valeur, this.couleur});

  final String libelle;
  final String valeur;
  final Color? couleur;

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;

    return Container(
      key: Key('kpi-$libelle'),
      constraints: const BoxConstraints(minWidth: AppLayout.carteKpi),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.unit,
      ),
      decoration: BoxDecoration(
        color: AppColors.neutre100,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            libelle.toUpperCase(),
            style: textes.labelSmall?.copyWith(
              color: AppColors.neutre500,
              letterSpacing: 0.6,
            ),
          ),
          Text(
            valeur,
            style: textes.titleSmall?.copyWith(
              color: couleur ?? AppColors.navy,
            ),
          ),
        ],
      ),
    );
  }
}

/// La pastille d'état, aux couleurs du maître.
class _Etat extends StatelessWidget {
  const _Etat({required this.etat});

  final EtatSejour etat;

  @override
  Widget build(BuildContext context) {
    final (fond, texte) = switch (etat) {
      EtatSejour.aVenir => (AppColors.infoBleuFond, AppColors.infoBleuTexte),
      EtatSejour.enCours => (AppColors.succesFond, AppColors.succes),
      EtatSejour.termine => (AppColors.neutre100, AppColors.neutre700),
      EtatSejour.annulee => (AppColors.erreurFondLeger, AppColors.erreur),
    };

    return Container(
      key: Key('etat-${etat.code}'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.demi,
      ),
      decoration: BoxDecoration(
        color: fond,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        etat.libelle,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: texte),
      ),
    );
  }
}

/// Une liste de filtre, avec son entrée « tous ».
class _Choix<T> extends StatelessWidget {
  const _Choix({
    required Key cle,
    required this.valeur,
    required this.libelleVide,
    required this.options,
    required this.libelle,
    required this.onChange,
  }) : super(key: cle);

  final T? valeur;

  /// La première `<option>` du maître, à valeur vide : « Tous les états ».
  final String libelleVide;

  final List<T> options;
  final String Function(T) libelle;
  final void Function(T?) onChange;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: AppLayout.filtreHistorique,
      child: DropdownButtonFormField<T?>(
        initialValue: valeur,
        isExpanded: true,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          isDense: true,
        ),
        items: [
          DropdownMenuItem<T?>(child: Text(libelleVide)),
          for (final o in options)
            DropdownMenuItem<T?>(
              value: o,
              child: Text(libelle(o), overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: onChange,
      ),
    );
  }
}

/// Une borne de date du filtre — effaçable, contrairement aux dates du
/// formulaire de saisie.
///
/// L'effacement compte : sans lui, poser une borne par curiosité la rendrait
/// définitive, et l'utilisateur croirait avoir perdu des réservations.
class _ChampDateFiltre extends StatelessWidget {
  const _ChampDateFiltre({
    required Key cle,
    required this.etiquette,
    required this.valeur,
    required this.onChange,
  }) : super(key: cle);

  final String etiquette;
  final DateTime? valeur;
  final void Function(DateTime?) onChange;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () async {
        final choisie = await showDatePicker(
          context: context,
          initialDate: valeur ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
        );
        if (choisie != null) onChange(choisie);
      },
      onLongPress: () => onChange(null),
      icon: Icon(
        valeur == null ? Icons.calendar_today : Icons.event_available,
        size: 14,
      ),
      label: Text(valeur == null ? etiquette : formaterDate(valeur!)),
    );
  }
}
