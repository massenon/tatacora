// Vue Blade maîtresse (PA-183) : pwa/crm/clients-creances.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/providers.dart';
import '../../../core/format/formats.dart';
import '../../../core/rbac/garde_acces.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/donnees_absentes.dart';
import '../../../shared_widgets/bouton_standard.dart';
import '../../caisse/domain/montant_caisse.dart' show formaterCentimesEnFcfa;
import '../../facturation/domain/creances.dart';
import '../../facturation/domain/entities/paiement_facture.dart';
import '../../facturation/domain/messages_encaissement.dart';
import '../../facturation/domain/regles_encaissement.dart';
import '../../facturation/presentation/providers_paiements.dart';
import '../../hebergement/presentation/providers_hebergement.dart';
import '../domain/entities/client.dart';
import '../domain/entities/registre_clients.dart';
import 'providers_crm.dart';
import 'widgets/barre_exports_clients.dart';
import 'widgets/modale_nouveau_client.dart';
import 'widgets/modale_recouvrement.dart';
import 'widgets/table_clients.dart';

/// L'écran **Clients & Créances** — la vue `crm/clients-creances`.
///
/// ## Les QUATRE onglets de la vue sont rendus (Phase 2, 08/10/2026)
///
/// « Liste des clients », « Suivi des dettes », « Relances clients » et
/// « Historique & avances » existent, avec la structure de la vue.
///
/// ## Ce que l'encaissement local (lot 5, 12/10/2026) a changé
///
/// `paiements` a désormais un écrivain (`PaiementsFactureDao`), et la formule du
/// reste dû est celle du serveur (`creances.dart`). Trois choses en découlent :
///
///  - le **solde** du client est le reste dû de ses factures impayées, plus le
///    « maximum » d'avant ; le bouton **« Recouvrement »** ouvre la modale
///    d'encaissement ;
///  - la carte **« Encaissé sur 30 j »** et le tableau **« Recouvrements
///    encaissés »** lisent les encaissements réels ;
///  - la **balance âgée** (deux cartes et l'onglet « Suivi des dettes ») est
///    portée : elle se lit des mêmes créances, par tranche d'ancienneté depuis la
///    date d'ÉMISSION. L'ancienne raison (« PA-20, une date d'échéance que
///    personne n'a décidée ») n'était déjà plus celle du serveur, et la phrase
///    qui la refusait à l'écran serait devenue fausse.
///
/// Les relances supposent un historique de relances, donc M12, module vide : elles
/// restent sans source, et le disent (`donneeNonDisponible`) au lieu d'afficher
/// « Aucun client à relancer », qui affirmerait que personne n'est en retard.
///
/// Les avances et acomptes (réservations à acompte) ont leur source depuis
/// toujours (`reservations_local.acompte`) et n'étaient refusées qu'à cause d'une
/// prémisse fausse (« elles supposent des encaissements ») : le TABLEAU des
/// avances n'est pas porté dans ce lot, nommé ici et au ticket (D236) plutôt que
/// dissimulé.
///
/// ## Les cartes sans source rendent « — », jamais « 0 »
///
/// « Créances totales », « Dont + de 90 jours », « 0 à 30 jours » et « Encaissé
/// sur 30 j » ont une source ; seule « Clients à relancer » n'en a pas (M12 est
/// vide). Les deux cartes de la balance âgée suivent `MontantFcfa::formatOuTiret`
/// du serveur : un montant NUL est un tiret, jamais « 0 FCFA » — la vue le fait,
/// et un zéro plausible se lirait comme « aucune dette douteuse » (PA-126).
///
/// Deux modales du maître restent refusées (les relances et l'historique d'un
/// client), pour la raison dite plus haut :
///  - maitre-refuse:m3-clients-creances.html#modale-relance
///  - maitre-refuse:m3-clients-creances.html#modale-hist
const _onglets = <(String, String)>[
  ('clients', 'Liste des clients'),
  ('dettes', 'Suivi des dettes'),
  ('relances', 'Relances clients'),
  ('avances', 'Historique & avances'),
];

class EcranClients extends ConsumerStatefulWidget {
  const EcranClients({super.key});

  @override
  ConsumerState<EcranClients> createState() => _EtatEcranClients();
}

class _EtatEcranClients extends ConsumerState<EcranClients> {
  String _onglet = 'clients';

  /// `ClientsCreances::ouvrirRecouvrement` : les factures impayées DU client, de
  /// la plus ancienne à la plus récente (`orderBy('factures.date_emission')`) ;
  /// aucune → « Ce client n'a aucune créance en cours. ».
  ///
  /// Au serveur cette phrase est posée sur une propriété que la vue n'affiche
  /// JAMAIS (aucun `@error('recouvrementClientId')`) : le bouton n'existant que
  /// pour un solde non nul, le cas est inatteignable en pratique. Le poste le dit
  /// par une bannière plutôt que de l'avaler.
  Future<void> _ouvrirRecouvrement(LigneClient ligne) async {
    final creances = await lireCreances(ref.read);
    final factures = facturesImpayeesDuClient(creances, ligne.client.id);

    if (!mounted) return;
    if (factures.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(MessagesEncaissement.aucuneCreance)),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (_) => ModaleRecouvrement(
        clientNom: ligne.client.nomComplet,
        factures: [
          for (final c in factures)
            (
              id: c.piece.id,
              libelle: libelleDeLaFacture(c.piece),
              resteCentimes: c.resteDuCentimes,
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final registre = ref.watch(registreFiltreProvider);
    final droits = ref.watch(droitsProvider);
    final peutEcrire = droits.peutEcrire(ModuleTatacora.m3Crm);
    // Le `$peutEncaisser` de la vue : M3 (l'écran) ET M2 (l'écriture).
    final peutEncaisser = peutEncaisserUneFacture(droits);
    final maintenant = ref.watch(horlogeCreancesProvider)();
    final paiements = ref.watch(paiementsFactureProvider).value;
    // La balance âgée COMPLÈTE sert l'onglet ET les deux cartes (une seule
    // composition, comme `render()` du serveur) ; la recherche ne filtre que le
    // corps de l'onglet.
    final creances = ref.watch(creancesProvider).value;
    final repertoire = {
      for (final c in ref.watch(clientsProvider).value ?? const <Client>[])
        c.id: (nom: c.nom, prenom: c.prenom),
    };
    final terme = ref.watch(rechercheClientProvider).trim();
    final detteGlobale = creances == null
        ? null
        : detteAgeeParClient(creances, repertoire, maintenant);
    final detteAffichee = creances == null
        ? null
        : (_onglet == 'dettes' && terme.isNotEmpty
              ? detteAgeeParClient(
                  creances,
                  repertoire,
                  maintenant,
                  terme: terme,
                )
              : detteGlobale);

    return SingleChildScrollView(
      // `max-w-[1440px] mx-auto p-5 lg:p-8` : 32 px au poste de travail.
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppLayout.maxContentWidth,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _EnTete(
                peutEcrire: peutEcrire,
                onglet: _onglet,
                lignes: registre.value ?? const [],
              ),
              _Kpis(
                kpis: KpisClients.calculer(registre.value ?? const []),
                douteux: detteGlobale == null
                    ? null
                    : totalDeLaTranche(detteGlobale, TrancheAge.plus90),
                recent: detteGlobale == null
                    ? null
                    : totalDeLaTranche(detteGlobale, TrancheAge.jusqua30),
                // « — » tant que les encaissements ne sont pas lus : un zéro se
                // lirait comme « rien encaissé » (PA-126).
                encaisse30j: paiements == null
                    ? null
                    : encaisseDepuisCentimes(
                        paiements,
                        ilYa30Jours(maintenant),
                      ),
              ),
              _BarreOnglets(
                actif: _onglet,
                onChoisir: (o) => setState(() => _onglet = o),
              ),
              _Filtres(avecEtat: _onglet == 'clients'),
              switch (_onglet) {
                'dettes' => _OngletDettes(
                  lignes: detteAffichee,
                  totalDuCentimes: creances == null
                      ? null
                      : totauxCreances(creances).totalDuCentimes,
                ),
                'relances' => const _OngletRelances(),
                'avances' => _OngletAvances(
                  paiements: paiements,
                  clients: ref.watch(clientsProvider).value ?? const [],
                  creances: ref.watch(creancesProvider).value ?? const [],
                ),
                _ => registre.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(AppSpacing.xl),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, _) => Center(child: Text('$e')),
                  data: (lignes) => TableClients(
                    lignes: lignes,
                    maintenant: maintenant,
                    peutEncaisser: peutEncaisser,
                    onRecouvrement: _ouvrirRecouvrement,
                  ),
                ),
              },
            ],
          ),
        ),
      ),
    );
  }
}

TextStyle _t(
  double taille, {
  FontWeight? poids,
  Color? couleur,
  double? espacement,
  double interligne = 1.5,
}) => TextStyle(
  fontFamily: AppTextStyles.police,
  fontSize: taille,
  fontWeight: poids,
  color: couleur,
  height: interligne,
  letterSpacing: espacement,
);

/// L'en-tête de la vue : titre, sous-titre dont « calculé » est en gras, et
/// les trois boutons « Réservations », « + Nouveau client » (qui l'a le droit)
/// et « Exporter ».
class _EnTete extends ConsumerWidget {
  const _EnTete({
    required this.peutEcrire,
    required this.onglet,
    required this.lignes,
  });

  final bool peutEcrire;
  final String onglet;
  final List<LigneClient> lignes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.mdPlus), // mb-5
      child: Wrap(
        // `flex flex-wrap items-start justify-between gap-3`
        alignment: WrapAlignment.spaceBetween,
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.people_outline,
                    size: AppLayout.iconeTitrePage,
                    color: AppColors.navy,
                  ),
                  const SizedBox(width: AppSpacing.xsPlus), // gap-2.5
                  Text(
                    'Clients & Créances',
                    style: _t(
                      TaillesContenu.lg,
                      poids: FontWeight.bold,
                      couleur: AppColors.navy,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xxs), // mt-1.5
              Text.rich(
                TextSpan(
                  style: _t(TaillesContenu.t15, couleur: AppColors.neutre500),
                  children: const [
                    TextSpan(text: 'Le solde d’un client est '),
                    TextSpan(
                      text: 'calculé',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    TextSpan(
                      text:
                          ' : factures certifiées non soldées, diminuées des '
                          'règlements reçus. Il ne se saisit jamais.',
                    ),
                  ],
                ),
              ),
            ],
          ),
          Wrap(
            spacing: AppSpacing.xs, // gap-2
            children: [
              _Bouton(
                cle: const Key('clients-reservations'),
                libelle: 'Réservations',
                onTap: () =>
                    GoRouter.of(context).go('/hebergement/reservations'),
              ),
              if (peutEcrire)
                _Bouton(
                  cle: const Key('clients-nouveau'),
                  libelle: '+ Nouveau client',
                  plein: true,
                  onTap: () => _nouveauClient(context, ref),
                ),
              // PO, 14/10/2026 : « Exporter » n'est AFFICHÉ que sur l'onglet
              // « Liste des clients », le seul que l'export sait servir.
              if (onglet == 'clients')
                _Bouton(
                  cle: const Key('clients-exporter'),
                  libelle: 'Exporter',
                  onTap: () => _exporter(context),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _nouveauClient(BuildContext context, WidgetRef ref) async {
    // La modale du REGISTRE (`m3-clients-creances.js` l.609-650), pas celle de
    // la fiche de réservation : le maître écrit ici « Nouveau client », « Nom /
    // Raison sociale » et « Créer le client », là où `reservations.html` dit
    // « Ajouter un client ».
    final saisie = await demanderClientRegistre(context);
    if (saisie == null) return;

    // Le DAO écrit le client ET son entrée de file dans la même transaction
    // (PA-116) : les séparer laisserait un client que rien ne pousse.
    await ref
        .read(clientDaoProvider)
        .creer(nom: saisie.nom, telephone: saisie.telephone, type: saisie.type);

    // Le registre lit la base : sans invalidation, le client n'apparaîtrait
    // qu'au prochain passage sur l'écran, et on le recréerait.
    ref
      ..invalidate(registreClientsProvider)
      ..invalidate(clientsProvider);
  }

  /// UN bouton « Exporter » (dérogation du Product Owner du 01/09/2026,
  /// `DerogationsMaquette::export_bouton_unique`) : le format s'y choisit.
  /// L'export n'est offert que sur la liste : le bouton n'est affiché que sur
  /// cet onglet (PO, 14/10/2026), d'où l'absence de refus ici.
  void _exporter(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Exporter — Clients & Créances'),
        content: BarreExportsClients(lignes: lignes),
      ),
    );
  }
}

/// `text-[13px] px-3.5 py-2 rounded-lg border` (ou `px-4 … bg-navy` pour le
/// bouton plein).
class _Bouton extends StatelessWidget {
  const _Bouton({
    required Key cle,
    required this.libelle,
    required this.onTap,
    this.plein = false,
  }) : super(key: cle);

  final String libelle;
  final VoidCallback onTap;
  final bool plein;

  /// Le bouton standard (PO, 14/10/2026) : mêmes classes que la vue.
  @override
  Widget build(BuildContext context) => BoutonStandard(
    libelle: libelle,
    variante: plein ? VarianteBouton.primaire : VarianteBouton.secondaire,
    onPressed: onTap,
  );
}

/// Les CINQ cartes de la vue (`grid-cols-2 lg:grid-cols-5 gap-3 mb-5`). Seule
/// la première vient du registre local.
class _Kpis extends StatelessWidget {
  const _Kpis({
    required this.kpis,
    required this.encaisse30j,
    required this.douteux,
    required this.recent,
  });

  final KpisClients kpis;

  /// Le total des tranches « + de 90 jours » et « 0 à 30 jours » de la balance
  /// âgée, ou `null` tant que les créances ne sont pas lues.
  final int? douteux;
  final int? recent;

  /// « Encaissé sur 30 j » en centimes, ou `null` tant que les encaissements ne
  /// sont pas lus.
  final int? encaisse30j;

  @override
  Widget build(BuildContext context) {
    final cartes = <(String, String, String, Color?)>[
      (
        'Créances totales',
        formaterCentimesEnFcfa(kpis.totalDuCentimes),
        '${kpis.nbPieces} pièce(s) · ${kpis.nbDebiteurs} client(s)',
        kpis.totalDuCentimes > 0 ? AppColors.erreur : null,
      ),
      (
        'Dont + de 90 jours',
        _montantOuTiret(douteux),
        'Part de la créance totale sur cette tranche',
        // `text-red-600` quand le montant n'est pas nul.
        (douteux ?? 0) > 0 ? AppColors.erreur : null,
      ),
      ('0 à 30 jours', _montantOuTiret(recent), 'Récent, non échu', null),
      (
        'Encaissé sur 30 j',
        encaisse30j == null ? '—' : formaterCentimesEnFcfa(encaisse30j!),
        'Recouvrements réellement enregistrés',
        null,
      ),
      ('Clients à relancer', '—', 'Plus de 30 j sans relance récente', null),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.mdPlus),
      // `grid grid-cols-5 gap-3` : les cartes d'une rangée s'étirent à la hauteur
      // de la plus haute — une carte au détail sur deux lignes grandit toutes
      // les autres.
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < cartes.length; i++) ...[
              if (i > 0) const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _Carte(
                  cle: Key('clients-kpi-$i'),
                  libelle: cartes[i].$1,
                  valeur: cartes[i].$2,
                  detail: cartes[i].$3,
                  accent: cartes[i].$4,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// `MontantFcfa::formatOuTiret` : « — » pour zéro (jamais « 0 FCFA », qui se lirait
/// comme un montant calculé) et pour une valeur pas encore lue.
String _montantOuTiret(int? centimes) =>
    centimes == null || centimes == 0 ? '—' : formaterCentimesEnFcfa(centimes);

class _Carte extends StatelessWidget {
  const _Carte({
    required Key cle,
    required this.libelle,
    required this.valeur,
    required this.detail,
    this.accent,
  }) : super(key: cle);

  final String libelle;
  final String valeur;
  final String detail;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.smPlus), // p-3.5
      decoration: BoxDecoration(
        color: AppColors.neutre0,
        borderRadius: BorderRadius.circular(AppRadius.roundedXl),
        border: Border.all(color: AppColors.neutre200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            libelle.toUpperCase(),
            style: _t(
              TaillesContenu.t11,
              poids: FontWeight.w600,
              couleur: AppColors.neutre400,
              espacement: 0.5,
            ),
          ),
          const SizedBox(height: AppSpacing.unit), // mt-1
          Text(
            valeur,
            style: _t(
              TaillesContenu.lg,
              poids: FontWeight.bold,
              interligne: TaillesContenu.interligneLg,
              couleur: valeur == '—'
                  ? AppColors.neutre400
                  : (accent ?? AppColors.navy),
            ),
          ),
          const SizedBox(height: AppSpacing.demi), // mt-0.5
          Text(
            detail,
            style: _t(TaillesContenu.t11, couleur: AppColors.neutre400),
          ),
        ],
      ),
    );
  }
}

/// `flex flex-wrap gap-2 mb-4` — le style d'onglet de `Onglets::classes()`.
class _BarreOnglets extends StatelessWidget {
  const _BarreOnglets({required this.actif, required this.onChoisir});

  final String actif;
  final ValueChanged<String> onChoisir;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md), // mb-4
      child: Wrap(
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        children: [
          for (final (cle, libelle) in _onglets)
            Material(
              key: Key('clients-onglet-$cle'),
              color: cle == actif ? AppColors.navy : AppColors.neutre0,
              borderRadius: BorderRadius.circular(AppRadius.roundedLg),
              child: InkWell(
                onTap: () => onChoisir(cle),
                borderRadius: BorderRadius.circular(AppRadius.roundedLg),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.smPlus,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.roundedLg),
                    // Le contour existe aussi sur l'onglet actif (marine sur
                    // marine) : sans lui le bouton est 2 px plus court.
                    border: Border.all(
                      color: cle == actif
                          ? AppColors.navy
                          : AppColors.neutre200,
                    ),
                  ),
                  child: Text(
                    libelle,
                    style: _t(
                      TaillesContenu.t13,
                      poids: FontWeight.w600,
                      couleur: cle == actif
                          ? AppColors.neutre0
                          : AppColors.neutre500,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// La carte des filtres (`bg-white rounded-xl border p-3.5 mb-4`) : la
/// recherche, avec sa loupe à gauche, et — sur la liste seulement — l'état.
class _Filtres extends ConsumerStatefulWidget {
  const _Filtres({required this.avecEtat});

  final bool avecEtat;

  @override
  ConsumerState<_Filtres> createState() => _FiltresState();
}

class _FiltresState extends ConsumerState<_Filtres> {
  final _terme = TextEditingController();

  @override
  void dispose() {
    _terme.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bordure = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      borderSide: const BorderSide(color: AppColors.neutre300),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.smPlus),
      decoration: BoxDecoration(
        color: AppColors.neutre0,
        borderRadius: BorderRadius.circular(AppRadius.roundedXl),
        border: Border.all(color: AppColors.neutre200),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: const Key('clients-recherche'),
              controller: _terme,
              style: _t(TaillesContenu.t13),
              decoration: InputDecoration(
                hintText: 'Rechercher un client…',
                isDense: true,
                // `pl-9` : 36 px à gauche, la loupe à `left-3`. Sans contrainte,
                // l'icône impose 48 px de haut au champ (mesuré : +11,6 px).
                prefixIcon: const Padding(
                  padding: EdgeInsets.only(left: AppSpacing.sm),
                  child: Icon(
                    Icons.search,
                    size: AppLayout.iconeChamp,
                    color: AppColors.neutre400,
                  ),
                ),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: AppSpacing.xl + AppSpacing.unit, // pl-9
                  minHeight: 0,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                border: bordure,
                enabledBorder: bordure,
                focusedBorder: bordure.copyWith(
                  borderSide: const BorderSide(color: AppColors.gold),
                ),
              ),
              onChanged: (v) =>
                  ref.read(rechercheClientProvider.notifier).definir(v),
            ),
          ),
          if (widget.avecEtat) ...[
            const SizedBox(width: AppSpacing.xsPlus), // gap-2.5
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.roundedLg),
                border: Border.all(color: AppColors.neutre300),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<EtatCreance>(
                    key: const Key('clients-filtre-etat'),
                    // Sans cela le champ impose 48 px de haut (`kMinInteractiveDimension`)
                    // à une liste de 13 px : la carte de filtres grandit de 12 px.
                    itemHeight: null,
                    value: ref.watch(etatCreanceProvider),
                    isDense: true,
                    // L'icône par défaut (24 px) grandit la liste au-delà de sa
                    // ligne de texte (19,5 px).
                    iconSize: AppLayout.iconeChamp,
                    style: _t(TaillesContenu.t13, couleur: AppColors.neutre700),
                    items: [
                      for (final e in EtatCreance.values)
                        DropdownMenuItem(value: e, child: Text(e.libelle)),
                    ],
                    onChanged: (e) => e == null
                        ? null
                        : ref.read(etatCreanceProvider.notifier).definir(e),
                  ),
                ),
              ),
            ),
          ],
          // `<div class="flex-1"></div>` : la vue partage l'espace libre entre
          // la recherche et cet espaceur — le champ n'occupe que la moitié.
          const Expanded(child: SizedBox.shrink()),
        ],
      ),
    );
  }
}

/* ====================================================================== */
/* Les trois onglets sans source locale                                    */
/* ====================================================================== */

/// Le tableau de la vue : en-têtes marine TOUJOURS rendus, corps qui dit que la
/// donnée n'a pas de source sur ce poste.
class _TableauSansSource extends StatelessWidget {
  const _TableauSansSource({
    required this.cle,
    required this.colonnes,
    required this.sujet,
    this.aDroite = const {},
  });

  final String cle;
  final List<String> colonnes;
  final String sujet;
  final Set<String> aDroite;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: Key(cle),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.neutre0,
        borderRadius: BorderRadius.circular(AppRadius.roundedXl),
        border: Border.all(color: AppColors.neutre200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: AppColors.navy,
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xsPlus),
            child: Row(
              children: [
                for (final c in colonnes)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm, // px-3
                      ),
                      child: Text(
                        c.toUpperCase(),
                        textAlign: aDroite.contains(c)
                            ? TextAlign.right
                            : TextAlign.left,
                        style: _t(
                          TaillesContenu.t11,
                          poids: FontWeight.w600,
                          couleur: AppColors.neutre0.withValues(alpha: 0.90),
                          espacement: 0.5,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
            child: Text(
              donneeNonDisponible(sujet),
              textAlign: TextAlign.center,
              style: _t(TaillesContenu.t13, couleur: AppColors.neutre400),
            ),
          ),
        ],
      ),
    );
  }
}

/// `<h3 class="text-[15px] font-bold mb-2.5">`. Le nombre de lignes n'est PAS
/// rendu : « (0) » affirmerait qu'il n'y en a aucune (PA-126).
class _TitreSection extends StatelessWidget {
  const _TitreSection(this.texte);

  final String texte;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xsPlus), // mb-2.5
      child: Text(
        texte,
        style: _t(
          TaillesContenu.t15,
          poids: FontWeight.bold,
          couleur: AppColors.navy,
        ),
      ),
    );
  }
}

class _Encadre extends StatelessWidget {
  const _Encadre({
    required this.fond,
    required this.bordure,
    required this.texte,
    required this.enfant,
  });

  final Color fond;
  final Color bordure;
  final Color texte;
  final List<InlineSpan> enfant;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md), // mb-4
      padding: const EdgeInsets.all(AppSpacing.smPlus), // p-3.5
      decoration: BoxDecoration(
        color: fond,
        borderRadius: BorderRadius.circular(AppRadius.roundedXl),
        border: Border.all(color: bordure),
      ),
      child: Text.rich(
        TextSpan(
          style: _t(TaillesContenu.t13, couleur: texte),
          children: enfant,
        ),
      ),
    );
  }
}

class _OngletDettes extends StatelessWidget {
  const _OngletDettes({required this.lignes, required this.totalDuCentimes});

  /// La balance âgée (filtrée par la recherche), ou `null` tant que les créances
  /// ne sont pas lues.
  final List<LigneDetteAgee>? lignes;

  /// Le total dû de TOUTES les factures impayées (`SoldeClientService::totaux`),
  /// pied du tableau — il peut dépasser la somme des lignes (une facture sans
  /// client n'a pas de ligne).
  final int? totalDuCentimes;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Encadre(
          fond: AppColors.reserveGoldFond,
          bordure: AppColors.reserveGoldTexte.withValues(alpha: 0.3),
          texte: AppColors.reserveGoldTexte,
          enfant: const [
            TextSpan(
              text: 'Balance âgée. ',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            TextSpan(
              text:
                  'Les tranches classent chaque pièce par ancienneté depuis sa '
                  'date d’émission. Au-delà de 90 jours, le recouvrement '
                  'devient incertain et une provision pour dépréciation doit '
                  'être envisagée — son taux relève d’une décision du Comptable '
                  'et du Gérant, il n’est pas calculé ici.',
            ),
          ],
        ),
        _TableauDettes(lignes: lignes, totalDuCentimes: totalDuCentimes),
      ],
    );
  }
}

/// Le tableau « Suivi des dettes » (`clients-creances.blade.php` l.371-411) :
/// `Client · 0 à 30 jours · 31 à 60 jours · 61 à 90 jours · Plus de 90 jours ·
/// Total dû` puis la colonne d'actions, vide ici (« Détail » ouvre la modale
/// d'historique, qui n'a pas d'écran sur ce poste).
class _TableauDettes extends StatelessWidget {
  const _TableauDettes({required this.lignes, required this.totalDuCentimes});

  final List<LigneDetteAgee>? lignes;
  final int? totalDuCentimes;

  static const _colonnes = [
    'Client',
    '0 à 30 jours',
    '31 à 60 jours',
    '61 à 90 jours',
    'Plus de 90 jours',
    'Total dû',
  ];

  @override
  Widget build(BuildContext context) {
    final l = lignes;

    return Container(
      key: const Key('clients-dettes-tableau'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.neutre0,
        borderRadius: BorderRadius.circular(AppRadius.roundedXl),
        border: Border.all(color: AppColors.neutre200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: AppColors.navy,
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xsPlus),
            child: Row(
              children: [
                for (final c in _colonnes)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                      ),
                      child: Text(
                        c.toUpperCase(),
                        textAlign: c == 'Client'
                            ? TextAlign.left
                            : TextAlign.right,
                        style: _t(
                          TaillesContenu.t11,
                          poids: FontWeight.w600,
                          couleur: AppColors.neutre0.withValues(alpha: 0.90),
                          espacement: 0.5,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (l == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (l.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: Text(
                'Aucune créance en cours. Tous les clients sont à jour.',
                key: const Key('clients-dettes-vide'),
                textAlign: TextAlign.center,
                style: _t(TaillesContenu.t13, couleur: AppColors.neutre400),
              ),
            )
          else ...[
            for (final ligne in l)
              Container(
                key: Key('clients-dette-${ligne.clientId}'),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: AppColors.neutre100)),
                ),
                padding: const EdgeInsets.symmetric(
                  vertical: AppSpacing.xsPlus,
                ),
                child: Row(
                  children: [
                    _cellule(
                      ligne.nom,
                      style: _t(
                        TaillesContenu.t13,
                        poids: FontWeight.w600,
                        couleur: Ardoise.c800,
                      ),
                    ),
                    for (final t in TrancheAge.values)
                      _cellule(
                        _montantOuTiret(ligne.tranchesCentimes[t]),
                        droite: true,
                        style: _t(
                          TaillesContenu.t13,
                          poids: ligne.tranchesCentimes[t] == 0
                              ? null
                              : FontWeight.w600,
                          couleur: ligne.tranchesCentimes[t] == 0
                              ? Ardoise.c300
                              : Ardoise.c700,
                        ),
                      ),
                    _cellule(
                      formaterCentimesEnFcfa(ligne.totalCentimes),
                      droite: true,
                      style: _t(
                        TaillesContenu.t13,
                        poids: FontWeight.bold,
                        couleur: AppColors.navy,
                      ),
                    ),
                  ],
                ),
              ),
            // `tfoot` : le total de chaque tranche, et le total dû de TOUTES les
            // factures impayées.
            Container(
              key: const Key('clients-dettes-total'),
              decoration: const BoxDecoration(
                color: Ardoise.c50,
                border: Border(top: BorderSide(color: Ardoise.c300, width: 2)),
              ),
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xsPlus),
              child: Row(
                children: [
                  _cellule(
                    'Total',
                    style: _t(
                      TaillesContenu.t13,
                      poids: FontWeight.bold,
                      couleur: AppColors.navy,
                    ),
                  ),
                  for (final t in TrancheAge.values)
                    _cellule(
                      _montantOuTiret(totalDeLaTranche(l, t)),
                      droite: true,
                      style: _t(TaillesContenu.t13, poids: FontWeight.bold),
                    ),
                  _cellule(
                    totalDuCentimes == null
                        ? '—'
                        : formaterCentimesEnFcfa(totalDuCentimes!),
                    droite: true,
                    style: _t(
                      TaillesContenu.t13,
                      poids: FontWeight.bold,
                      couleur: AppColors.navy,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  static Widget _cellule(
    String texte, {
    required TextStyle style,
    bool droite = false,
  }) => Expanded(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: Text(
        texte,
        textAlign: droite ? TextAlign.right : TextAlign.left,
        style: style,
      ),
    ),
  );
}

class _OngletRelances extends StatelessWidget {
  const _OngletRelances();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Encadre(
          fond: AppColors.neutre100,
          bordure: AppColors.neutre200,
          texte: AppColors.neutre700,
          enfant: const [
            TextSpan(
              text:
                  'La relance est tracée, pas envoyée. Aucun canal (WhatsApp, '
                  'e-mail) n’est branché sur ce système : enregistrer un envoi '
                  'qui n’a pas eu lieu ferait croire à un suivi inexistant.',
            ),
          ],
        ),
        const _TitreSection('Clients à relancer'),
        const Padding(
          padding: EdgeInsets.only(bottom: AppSpacing.lg), // mb-6
          child: _TableauSansSource(
            cle: 'clients-relances-tableau',
            colonnes: [
              'Client',
              'Montant dû',
              'Ancienneté max',
              'Dernière relance',
              '',
            ],
            aDroite: {'Montant dû', 'Ancienneté max'},
            sujet: 'Les relances',
          ),
        ),
        const _TitreSection('Historique des relances'),
        const _TableauSansSource(
          cle: 'clients-historique-relances-tableau',
          colonnes: [
            'Date',
            'Client',
            'Canal',
            'Montant réclamé',
            'Promesse',
            'Par',
          ],
          aDroite: {'Montant réclamé'},
          sujet: 'L’historique des relances',
        ),
      ],
    );
  }
}

class _OngletAvances extends StatelessWidget {
  const _OngletAvances({
    required this.paiements,
    required this.clients,
    required this.creances,
  });

  /// Les encaissements, ou `null` tant qu'ils ne sont pas lus.
  final List<PaiementFacture>? paiements;
  final List<Client> clients;
  final List<CreanceFacture> creances;

  /// Le plafond des journaux de la vue (`ClientsCreances::PLAFOND`).
  static const int plafond = 200;

  @override
  Widget build(BuildContext context) {
    final affiches = paiements?.take(plafond).toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _TitreSection('Avances et acomptes'),
        const Padding(
          padding: EdgeInsets.only(bottom: AppSpacing.lg),
          child: _TableauSansSource(
            cle: 'clients-avances-tableau',
            colonnes: [
              'Date',
              'Client',
              'Origine',
              'Avance versée',
              'Reste dû',
            ],
            aDroite: {'Avance versée', 'Reste dû'},
            sujet: 'Les avances',
          ),
        ),
        // Le nombre de lignes est rendu SEULEMENT quand les encaissements sont
        // lus : « (0) » avant la lecture affirmerait qu'il n'y en a aucun.
        _TitreSection(
          affiches == null
              ? 'Recouvrements encaissés'
              : 'Recouvrements encaissés (${affiches.length})',
        ),
        _TableauRecouvrements(
          paiements: affiches,
          clients: clients,
          creances: creances,
        ),
      ],
    );
  }
}

/// Le tableau « Recouvrements encaissés » (`clients-creances.blade.php`
/// l.494-516) : `N° · Date · Client · Pièce · Mode · Référence · Montant · Par`.
///
/// Les encaissements ANNULÉS y figurent sans marque, comme au serveur
/// (`Paiement::query()->orderByDesc('date_paiement')`, aucun filtre de statut) :
/// incohérence du serveur répliquée (D233). Les colonnes « N° » et « Référence »
/// portent la MÊME valeur, les huit premiers caractères de l'identifiant — le
/// schéma n'a pas de colonne de référence.
class _TableauRecouvrements extends StatelessWidget {
  const _TableauRecouvrements({
    required this.paiements,
    required this.clients,
    required this.creances,
  });

  final List<PaiementFacture>? paiements;
  final List<Client> clients;
  final List<CreanceFacture> creances;

  static const _colonnes = [
    'N°',
    'Date',
    'Client',
    'Pièce',
    'Mode',
    'Référence',
    'Montant',
    'Par',
  ];

  @override
  Widget build(BuildContext context) {
    final lignes = paiements;
    final pieces = {for (final c in creances) c.piece.id: c.piece};
    final noms = {for (final c in clients) c.id: c.nomComplet};

    return Container(
      key: const Key('clients-recouvrements-tableau'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.neutre0,
        borderRadius: BorderRadius.circular(AppRadius.roundedXl),
        border: Border.all(color: AppColors.neutre200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: AppColors.navy,
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xsPlus),
            child: Row(
              children: [
                for (final c in _colonnes)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                      ),
                      child: Text(
                        c.toUpperCase(),
                        textAlign: c == 'Montant'
                            ? TextAlign.right
                            : TextAlign.left,
                        style: _t(
                          TaillesContenu.t11,
                          poids: FontWeight.w600,
                          couleur: AppColors.neutre0.withValues(alpha: 0.90),
                          espacement: 0.5,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (lignes == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (lignes.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: Text(
                'Aucun recouvrement enregistré.',
                key: const Key('clients-recouvrements-vide'),
                textAlign: TextAlign.center,
                style: _t(TaillesContenu.t13, couleur: AppColors.neutre400),
              ),
            )
          else
            for (final p in lignes)
              Container(
                key: Key('clients-recouvrement-ligne-${p.id}'),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: AppColors.neutre100)),
                ),
                padding: const EdgeInsets.symmetric(
                  vertical: AppSpacing.xsPlus,
                ),
                child: Row(
                  children: [
                    _cellule(
                      p.numeroCourt,
                      style: _t(
                        TaillesContenu.t12,
                        couleur: AppColors.neutre500,
                      ),
                    ),
                    _cellule(
                      formaterDate(p.datePaiement),
                      style: _t(TaillesContenu.t13, couleur: Ardoise.c600),
                    ),
                    _cellule(
                      noms[pieces[p.pieceId]?.clientId] ?? '—',
                      style: _t(
                        TaillesContenu.t13,
                        poids: FontWeight.w600,
                        couleur: Ardoise.c800,
                      ),
                    ),
                    _cellule(
                      pieces[p.pieceId]?.numero ?? '—',
                      style: _t(TaillesContenu.t13, couleur: Ardoise.c600),
                    ),
                    _cellule(
                      p.mode.libelle,
                      style: _t(TaillesContenu.t13, couleur: Ardoise.c600),
                    ),
                    _cellule(
                      p.numeroCourt,
                      style: _t(TaillesContenu.t12, couleur: Ardoise.c500),
                    ),
                    _cellule(
                      formaterCentimesEnFcfa(p.montantCentimes),
                      droite: true,
                      style: _t(
                        TaillesContenu.t13,
                        poids: FontWeight.w600,
                        couleur: PaletteMaitre.emeraude600,
                      ),
                    ),
                    _cellule(
                      p.loginCreation ?? '—',
                      style: _t(TaillesContenu.t12, couleur: Ardoise.c500),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  static Widget _cellule(
    String texte, {
    required TextStyle style,
    bool droite = false,
  }) => Expanded(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: Text(
        texte,
        textAlign: droite ? TextAlign.right : TextAlign.left,
        style: style,
      ),
    ),
  );
}
