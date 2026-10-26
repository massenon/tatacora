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
import '../../../shared_widgets/bouton_standard.dart';
import '../../../shared_widgets/liste_paginee.dart';
import '../../caisse/domain/montant_caisse.dart' show formaterCentimesEnFcfa;
import '../../facturation/domain/creances.dart';
import '../../facturation/domain/entities/paiement_facture.dart';
import '../../facturation/domain/messages_encaissement.dart';
import '../../facturation/domain/regles_encaissement.dart';
import '../../facturation/presentation/providers_paiements.dart';
import '../../hebergement/domain/entities/reservation.dart';
import '../../achats/domain/entities/archivage_fournisseur.dart'
    show LotArchivage;
import '../../achats/presentation/widgets/modale_archivage_achats.dart';
import '../../hebergement/presentation/providers_hebergement.dart';
import '../domain/entities/client.dart';
import '../data/archivage_clients.dart' show RefusArchivageClient;
import '../domain/entities/registre_clients.dart';
import '../domain/entities/relance.dart';
import '../domain/messages_archivage_client.dart';
import '../domain/regles_relance.dart';
import 'providers_crm.dart';
import 'widgets/barre_exports_clients.dart';
import 'widgets/modale_historique_client.dart';
import 'widgets/modale_nouveau_client.dart';
import 'widgets/modale_recouvrement.dart';
import 'widgets/modale_relance.dart';
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
/// ## Les relances et l'archivage d'un client sont portés (21/10/2026)
///
/// **Les relances** (`relances_clients`, EF-M3-03) : « Relancer » ouvre la
/// modale « Tracer une relance » (canal, montant réclamé, promesse, compte
/// rendu), `RelancesClientsDao` écrit le fait daté et l'enfile, et l'onglet
/// « Relances clients » rend « Clients à relancer » (les débiteurs sans relance
/// depuis 30 jours : « Jamais relancé » ou la date) et l'historique. La carte
/// « Clients à relancer » les compte.
///
/// **L'archivage** (« Supprimer », case de sélection, barre de sélection
/// groupée, « Restaurer », badge « Archivé ») : `clients_local.actif` (v35),
/// écrit par le seul `ArchivageClients`, qui rejoue les quatre verrous du
/// serveur (séjour, location, circuit, facture non soldée). La case et le
/// bouton n'existent que pour qui peut archiver (`regle_archivage.dart`).
///
/// ## Ce que ce poste fait en plus de l'encaissement
///
///  - **Historique d'un client** : « Historique » (liste des clients) et
///    « Détail » (suivi des dettes) ouvrent la modale du relevé, aux
///    encaissements puis aux relances du client ; « Imprimer PDF » écrit le
///    relevé de compte (document remis au client), relances comprises.
///  - **Avances et acomptes** : le tableau est rendu, depuis les réservations
///    non annulées qui portent un acompte (`reservations_local.acompte`).
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

  /// `ClientsCreances::ouvrirRelance` : le solde vivant du client est proposé
  /// comme montant réclamé (`soldeDuClient()`).
  Future<void> _relancer(String clientId, String clientNom) async {
    final creances = await lireCreances(ref.read);
    if (!mounted) return;
    await tracerUneRelance(
      context,
      clientId: clientId,
      clientNom: clientNom,
      montantProposeCentimes: montantProposeCentimes(clientId, creances),
    );
  }

  /// `confirmerArchivageClient` puis `archiverClients` : une ligne (son
  /// identifiant) ou la sélection AFFICHÉE — cocher tout puis changer de filtre
  /// n'archive pas des clients que l'écran ne montre plus.
  ///
  /// Le droit d'archiver est exigé DÈS l'ouverture ; le lot vient de
  /// `ArchivageClients` (verrous : séjour, location, circuit, facture non
  /// soldée) et la modale rend les trois états de la vue : BLOQUÉ (le bouton
  /// disparaît), PARTIEL (le décompte des conservés) ou NOMINAL.
  Future<void> _confirmerArchivage({String? client}) async {
    final affiches = {
      for (final l
          in ref.read(registreFiltreProvider).value ?? const <LigneClient>[])
        l.client.id,
    };
    final ids = client != null
        ? [client]
        : [
            for (final id in ref.read(selectionClientsProvider))
              if (affiches.contains(id)) id,
          ];
    if (ids.isEmpty) return;

    final LotArchivage lot;
    try {
      lot = await ref.read(preparerArchivageClientsProvider)(ids);
    } on RefusArchivageClient catch (e) {
      _toastRefus(e.message);
      return;
    }
    if (!mounted) return;

    final confirme = await ouvrirArchivageAchats(
      context,
      element: lot.element,
      nombre: lot.nombre,
      messagesVerrou: lot.motifs,
      bloque: lot.bloque,
      conserves: lot.conserves,
    );
    if (confirme != true || !mounted) return;

    try {
      final resultat = await ref.read(archiverClientsProvider)(lot.ids);
      if (!mounted) return;
      // Le succès ET le refus coexistent : un client devenu engagé entre
      // l'ouverture et le clic n'empêche pas les autres archivages du lot.
      final succes = resultat.archives > 0
          ? MessagesArchivageClient.succes(resultat.archives)
          : null;
      if (resultat.refus != null) {
        _toastRefus(resultat.refus!, succes: succes);
      } else if (succes != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            key: const Key('clients-archivage-succes'),
            content: Text(succes),
          ),
        );
      }
    } on RefusArchivageClient catch (e) {
      _toastRefus(e.message);
    }
  }

  Future<void> _restaurer(Client client) async {
    try {
      final message = await ref.read(restaurerClientProvider)(client.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } on RefusArchivageClient catch (e) {
      _toastRefus(e.message);
    }
  }

  /// Le refus rendu HORS de la modale (`@error('archivage')`, vue l.807) : le
  /// geste ferme la modale avant de rendre, un message posé dedans
  /// n'apparaîtrait jamais.
  void _toastRefus(String motif, {String? succes}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        key: const Key('clients-archivage-refus'),
        backgroundColor: AppColors.erreur,
        content: succes == null
            ? Text(motif)
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(succes, key: const Key('clients-archivage-succes')),
                  Text(motif),
                ],
              ),
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
    // Le `$peutArchiver` de la vue : la règle UNIQUE, reçue — jamais recalculée.
    final peutArchiver = ref.watch(peutArchiverClientsProvider);
    final selection = ref.watch(selectionClientsProvider);
    final aRelancer = ref.watch(clientsARelancerProvider).value;
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
                // « — » tant que les relances ne sont pas lues : un « 0 » se
                // lirait comme « personne à relancer ».
                aRelancer: aRelancer?.length,
              ),
              _BarreOnglets(
                actif: _onglet,
                onChoisir: (o) => setState(() => _onglet = o),
              ),
              _Filtres(avecEtat: _onglet == 'clients'),
              switch (_onglet) {
                'dettes' => _OngletDettes(
                  terme: terme,
                  lignes: detteAffichee,
                  totalDuCentimes: creances == null
                      ? null
                      : totauxCreances(creances).totalDuCentimes,
                ),
                'relances' => _OngletRelances(
                  peutEcrire: peutEcrire,
                  onRelancer: _relancer,
                ),
                'avances' => _OngletAvances(
                  paiements: paiements,
                  clients: ref.watch(clientsProvider).value ?? const [],
                  creances: ref.watch(creancesProvider).value ?? const [],
                  reservations: ref.watch(reservationsProvider).value,
                ),
                _ => registre.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(AppSpacing.xl),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, _) => Center(child: Text('$e')),
                  // Dix lignes par page (PO, 14/10/2026) ; « Exporter » lit
                  // `registreFiltreProvider`, la liste ENTIÈRE.
                  data: (lignes) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // La barre de sélection groupée : « N sélectionné(s) »,
                      // « Supprimer », ✕ (rendue à qui peut archiver, quand la
                      // sélection n'est pas vide).
                      if (peutArchiver && selection.isNotEmpty)
                        _BarreSelection(
                          nombre: selection.length,
                          onSupprimer: () => _confirmerArchivage(),
                          onVider: () => ref
                              .read(selectionClientsProvider.notifier)
                              .vider(),
                        ),
                      ListePaginee<LigneClient>(
                        key: const Key('clients-registre-pagine'),
                        elements: lignes,
                        prefixeCle: 'clients-pagination',
                        cleRemiseAZero: (terme, ref.watch(etatCreanceProvider)),
                        masquerSiVide: true,
                        constructeur: (_, page) => TableClients(
                          lignes: page,
                          maintenant: maintenant,
                          peutEncaisser: peutEncaisser,
                          peutArchiver: peutArchiver,
                          peutRestaurer: peutEcrire,
                          selection: selection,
                          onBasculerSelection: (l) => ref
                              .read(selectionClientsProvider.notifier)
                              .basculer(l.client.id),
                          onSupprimer: (l) =>
                              _confirmerArchivage(client: l.client.id),
                          onRestaurer: (l) => _restaurer(l.client),
                          onRecouvrement: _ouvrirRecouvrement,
                          onHistorique: (l) => ouvrirHistoriqueClient(
                            context,
                            clientId: l.client.id,
                            clientNom: l.client.nomComplet,
                          ),
                        ),
                      ),
                    ],
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
                  onTap: () => _exporter(context, ref),
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
  /// `DerogationsMaquette::export_bouton_unique`) : le format s'y choisit,
  /// dans la modale d'export partagée (14/10/2026).
  /// L'export n'est offert que sur la liste : le bouton n'est affiché que sur
  /// cet onglet (PO, 14/10/2026).
  void _exporter(BuildContext context, WidgetRef ref) {
    BarreExportsClients.exporter(context, ref, lignes);
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
    required this.aRelancer,
  });

  final KpisClients kpis;

  /// Le total des tranches « + de 90 jours » et « 0 à 30 jours » de la balance
  /// âgée, ou `null` tant que les créances ne sont pas lues.
  final int? douteux;
  final int? recent;

  /// « Encaissé sur 30 j » en centimes, ou `null` tant que les encaissements ne
  /// sont pas lus.
  final int? encaisse30j;

  /// Combien de clients sont « à relancer », ou `null` tant que les relances ne
  /// sont pas lues.
  final int? aRelancer;

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
      (
        'Clients à relancer',
        aRelancer == null ? '—' : '$aRelancer',
        'Plus de 30 j sans relance récente',
        // `text-amber-600` quand il y en a, `text-slate-400` sinon.
        (aRelancer ?? 0) > 0 ? PaletteMaitre.ambre600 : Ardoise.c400,
      ),
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

/// `<h3 class="text-[15px] font-bold mb-2.5">`. Le nombre de lignes n'est rendu
/// QUE quand la source est lue : « (0) » avant la lecture affirmerait qu'il n'y
/// en a aucune (PA-126).
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
  const _OngletDettes({
    required this.terme,
    required this.lignes,
    required this.totalDuCentimes,
  });

  /// La recherche : la changer ramène la pagination à la page 1.
  final String terme;

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
                  'date d\'émission. Au-delà de 90 jours, le recouvrement '
                  'devient incertain et une provision pour dépréciation doit '
                  'être envisagée — son taux relève d\'une décision du Comptable '
                  'et du Gérant, il n\'est pas calculé ici.',
            ),
          ],
        ),
        if (lignes == null)
          _TableauDettes(lignes: null, totalDuCentimes: totalDuCentimes)
        else
          ListePaginee<LigneDetteAgee>(
            elements: lignes!,
            prefixeCle: 'clients-dettes-pagination',
            cleRemiseAZero: terme,
            masquerSiVide: true,
            constructeur: (_, page) => _TableauDettes(
              lignes: page,
              toutes: lignes,
              totalDuCentimes: totalDuCentimes,
            ),
          ),
      ],
    );
  }
}

/// Le tableau « Suivi des dettes » (`clients-creances.blade.php` l.371-411) :
/// `Client · 0 à 30 jours · 31 à 60 jours · 61 à 90 jours · Plus de 90 jours ·
/// Total dû` puis la colonne d'actions, vide ici (« Détail » ouvre la modale
/// d'historique, qui n'a pas d'écran sur ce poste).
class _TableauDettes extends StatelessWidget {
  const _TableauDettes({
    required this.lignes,
    required this.totalDuCentimes,
    this.toutes,
  });

  /// Les lignes de la PAGE affichée.
  final List<LigneDetteAgee>? lignes;

  /// Toutes les lignes (la liste paginée entière) — le pied totalise CELLES-CI,
  /// jamais la seule page. `null` : [lignes] est la liste entière.
  final List<LigneDetteAgee>? toutes;
  final int? totalDuCentimes;

  static const _colonnes = [
    'Client',
    '0 à 30 jours',
    '31 à 60 jours',
    '61 à 90 jours',
    'Plus de 90 jours',
    'Total dû',
    // La colonne d'actions de la vue (entête vide) : « Détail ».
    '',
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
                    // « Détail » : l'historique du client (`action_detail`).
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                        ),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: _BoutonLigneClient(
                            cle: Key('clients-detail-${ligne.clientId}'),
                            libelle: 'Détail',
                            onTap: () => ouvrirHistoriqueClient(
                              context,
                              clientId: ligne.clientId,
                              clientNom: ligne.nom,
                            ),
                          ),
                        ),
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
                      _montantOuTiret(totalDeLaTranche(toutes ?? l, t)),
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
                  const Expanded(child: SizedBox.shrink()),
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

/// `text-[12px] px-2.5 py-1 rounded-lg border border-slate-300 hover:bg-white` :
/// le bouton de lecture d'une ligne (« Détail »).
class _BoutonLigneClient extends StatelessWidget {
  const _BoutonLigneClient({
    required Key cle,
    required this.libelle,
    required this.onTap,
  }) : super(key: cle);

  final String libelle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.neutre0,
      borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.roundedLg),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xsPlus,
            vertical: AppSpacing.unit,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.roundedLg),
            border: Border.all(color: AppColors.neutre300),
          ),
          child: Text(
            libelle,
            style: _t(TaillesContenu.t12, couleur: AppColors.neutre700),
          ),
        ),
      ),
    );
  }
}

/// L'onglet **« Relances clients »** (`clients-creances.blade.php` l.421-471) :
/// l'encadré (« La relance est tracée, pas envoyée… »), « Clients à relancer
/// (N) » puis « Historique des relances (N) ».
///
/// « Clients à relancer » : les débiteurs sans relance depuis 30 jours, avec
/// leur ancienneté (rouge au-delà de 90 jours, ambre sinon) et leur dernière
/// relance — « Jamais relancé » quand il n'y en a aucune. « Relancer » n'est
/// offert qu'à qui écrit sur M3.
class _OngletRelances extends ConsumerWidget {
  const _OngletRelances({required this.peutEcrire, required this.onRelancer});

  final bool peutEcrire;
  final void Function(String clientId, String clientNom) onRelancer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aRelancer = ref.watch(clientsARelancerProvider).value;
    final historique = ref.watch(historiqueRelancesProvider).value;

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
                  'e-mail) n\'est branché sur ce système : enregistrer un envoi '
                  'qui n\'a pas eu lieu ferait croire à un suivi inexistant.',
            ),
          ],
        ),
        _TitreSection(
          aRelancer == null
              ? 'Clients à relancer'
              : 'Clients à relancer (${aRelancer.length})',
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.lg), // mb-6
          child: aRelancer == null
              ? const _TableauJournal(
                  cle: 'clients-relances-tableau',
                  colonnes: _colonnesARelancer,
                  aDroite: {'Montant dû', 'Ancienneté max'},
                  lignes: null,
                  vide: '',
                )
              : ListePaginee<ClientARelancer>(
                  elements: aRelancer,
                  prefixeCle: 'clients-relances-pagination',
                  masquerSiVide: true,
                  constructeur: (_, page) => _TableauJournal(
                    cle: 'clients-relances-tableau',
                    colonnes: _colonnesARelancer,
                    aDroite: const {'Montant dû', 'Ancienneté max'},
                    vide:
                        'Aucun client à relancer : toutes les créances de plus '
                        'de 30 jours ont été relancées récemment.',
                    cleVide: 'clients-relances-vide',
                    lignes: [for (final c in page) _ligneARelancer(c)],
                  ),
                ),
        ),
        _TitreSection(
          historique == null
              ? 'Historique des relances'
              : 'Historique des relances (${historique.length})',
        ),
        historique == null
            ? const _TableauJournal(
                cle: 'clients-historique-relances-tableau',
                colonnes: _colonnesHistorique,
                aDroite: {'Montant réclamé'},
                lignes: null,
                vide: '',
              )
            : ListePaginee<Relance>(
                elements: historique,
                prefixeCle: 'clients-historique-relances-pagination',
                masquerSiVide: true,
                constructeur: (_, page) => _TableauJournal(
                  cle: 'clients-historique-relances-tableau',
                  colonnes: _colonnesHistorique,
                  aDroite: const {'Montant réclamé'},
                  vide: 'Aucune relance enregistrée.',
                  cleVide: 'clients-historique-relances-vide',
                  lignes: [for (final r in page) _ligneHistorique(r)],
                ),
              ),
      ],
    );
  }

  static const _colonnesARelancer = [
    'Client',
    'Montant dû',
    'Ancienneté max',
    'Dernière relance',
    '',
  ];

  static const _colonnesHistorique = [
    'Date',
    'Client',
    'Canal',
    'Montant réclamé',
    'Promesse',
    'Par',
  ];

  _LigneJournal _ligneARelancer(ClientARelancer c) {
    final j = c.ancienneteMaxJours;
    return _LigneJournal(
      cle: 'clients-arelancer-${c.clientId}',
      cellules: [
        Text(
          c.nom,
          style: _t(
            TaillesContenu.t13,
            poids: FontWeight.w600,
            couleur: Ardoise.c800,
          ),
        ),
        Text(
          formaterCentimesEnFcfa(c.soldeCentimes),
          style: _t(
            TaillesContenu.t13,
            poids: FontWeight.w600,
            couleur: PaletteMaitre.rouge600,
          ),
        ),
        // Seuils du maître : rouge au-delà de 90 j, ambre sinon.
        Text(
          '$j j',
          style: _t(
            TaillesContenu.t13,
            poids: j > 90 ? FontWeight.w600 : null,
            couleur: j > 90 ? PaletteMaitre.rouge600 : PaletteMaitre.ambre600,
          ),
        ),
        Text(
          c.derniereRelance == null
              ? 'Jamais relancé'
              : formaterDate(c.derniereRelance!),
          style: _t(TaillesContenu.t13, couleur: Ardoise.c600),
        ),
        if (peutEcrire)
          _BoutonRelancer(
            cle: Key('clients-relancer-${c.clientId}'),
            onTap: () => onRelancer(c.clientId, c.nom),
          )
        else
          const SizedBox.shrink(),
      ],
    );
  }

  _LigneJournal _ligneHistorique(Relance r) => _LigneJournal(
    cle: 'clients-relance-ligne-${r.id}',
    cellules: [
      Text(
        formaterDate(r.dateRelance),
        style: _t(TaillesContenu.t13, couleur: Ardoise.c600),
      ),
      Text(
        r.clientNom ?? '—',
        style: _t(
          TaillesContenu.t13,
          poids: FontWeight.w600,
          couleur: Ardoise.c800,
        ),
      ),
      Text(
        CanalRelance.libelleDe(r.canal),
        style: _t(TaillesContenu.t13, couleur: Ardoise.c600),
      ),
      Text(
        formaterCentimesEnFcfa(r.montantReclameCentimes),
        style: _t(TaillesContenu.t13, couleur: Ardoise.c700),
      ),
      Text(
        r.promesse == null ? '—' : formaterDate(r.promesse!),
        style: _t(TaillesContenu.t13, couleur: Ardoise.c600),
      ),
      Text(
        r.creePar ?? '—',
        style: _t(TaillesContenu.t12, couleur: AppColors.neutre500),
      ),
    ],
  );
}

/// Une ligne d'un tableau de l'onglet : ses cellules, dans l'ordre des
/// colonnes.
class _LigneJournal {
  const _LigneJournal({required this.cle, required this.cellules});

  final String cle;
  final List<Widget> cellules;
}

/// Un tableau de la vue (`bg-white rounded-xl border`, en-têtes marine) : les
/// cellules s'alignent à droite pour les colonnes de [aDroite]. [lignes] nul :
/// la source n'est pas encore lue (un chargement, jamais « aucun »).
class _TableauJournal extends StatelessWidget {
  const _TableauJournal({
    required this.cle,
    required this.colonnes,
    required this.aDroite,
    required this.lignes,
    required this.vide,
    this.cleVide,
  });

  final String cle;
  final List<String> colonnes;
  final Set<String> aDroite;
  final List<_LigneJournal>? lignes;
  final String vide;
  final String? cleVide;

  @override
  Widget build(BuildContext context) {
    final l = lignes;

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
          if (l == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (l.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: Text(
                vide,
                key: cleVide == null ? null : Key(cleVide!),
                textAlign: TextAlign.center,
                style: _t(TaillesContenu.t13, couleur: AppColors.neutre400),
              ),
            )
          else
            for (final ligne in l)
              Container(
                key: Key(ligne.cle),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: AppColors.neutre100)),
                ),
                padding: const EdgeInsets.symmetric(
                  vertical: AppSpacing.xsPlus,
                ),
                child: Row(
                  children: [
                    for (var i = 0; i < ligne.cellules.length; i++)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                          ),
                          child: Align(
                            alignment:
                                aDroite.contains(colonnes[i]) ||
                                    colonnes[i].isEmpty
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: ligne.cellules[i],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

/// `text-[12px] px-2.5 py-1 rounded-lg bg-[var(--gold)] text-white` :
/// « Relancer ».
class _BoutonRelancer extends StatelessWidget {
  const _BoutonRelancer({required Key cle, required this.onTap})
    : super(key: cle);

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.gold,
      borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.roundedLg),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xsPlus,
            vertical: AppSpacing.unit,
          ),
          child: Text(
            'Relancer',
            style: _t(TaillesContenu.t12, couleur: AppColors.neutre0),
          ),
        ),
      ),
    );
  }
}

/// La barre de sélection groupée (`crud-ui.js` l.36-46 ; vue l.276-286) : « N
/// sélectionné(s) » (le nombre en gras), « Supprimer » souligné, ✕. Elle
/// ARCHIVE — « supprimer = archiver ».
class _BarreSelection extends StatelessWidget {
  const _BarreSelection({
    required this.nombre,
    required this.onSupprimer,
    required this.onVider,
  });

  final int nombre;
  final VoidCallback onSupprimer;
  final VoidCallback onVider;

  @override
  Widget build(BuildContext context) {
    final blanc = _t(TaillesContenu.t12, couleur: AppColors.neutre0);
    return Container(
      key: const Key('clients-barre-selection'),
      margin: const EdgeInsets.only(bottom: AppSpacing.sm), // mb-3
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xsPlus,
      ),
      decoration: BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      ),
      child: Row(
        children: [
          Text.rich(
            TextSpan(
              style: blanc,
              children: [
                TextSpan(
                  text: '$nombre',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const TextSpan(text: ' sélectionné(s)'),
              ],
            ),
          ),
          const Spacer(),
          InkWell(
            key: const Key('clients-selection-supprimer'),
            onTap: onSupprimer,
            child: Text(
              'Supprimer',
              style: blanc.copyWith(decoration: TextDecoration.underline),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          InkWell(
            key: const Key('clients-selection-vider'),
            onTap: onVider,
            child: Text(
              '✕',
              style: blanc.copyWith(
                color: AppColors.neutre0.withValues(alpha: 0.6),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OngletAvances extends StatelessWidget {
  const _OngletAvances({
    required this.paiements,
    required this.clients,
    required this.creances,
    required this.reservations,
  });

  /// Les encaissements, ou `null` tant qu'ils ne sont pas lus.
  final List<PaiementFacture>? paiements;
  final List<Client> clients;
  final List<CreanceFacture> creances;

  /// Les réservations, ou `null` tant qu'elles ne sont pas lues : un « (0) »
  /// avant la lecture affirmerait qu'il n'y a aucune avance.
  final List<Reservation>? reservations;

  /// Le plafond des journaux de la vue (`ClientsCreances::PLAFOND`).
  static const int plafond = 200;

  /// `ClientsCreances::avances()` : les réservations dont l'acompte est
  /// strictement positif, hors annulées, de la plus récente arrivée à la plus
  /// ancienne, au plus [plafond].
  static List<Reservation>? avances(List<Reservation>? toutes) {
    if (toutes == null) return null;
    final retenues = [
      for (final r in toutes)
        if (r.acompte > 0 && r.estActive) r,
    ]..sort((a, b) => b.periode.arrivee.compareTo(a.periode.arrivee));
    return retenues.take(plafond).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final affiches = paiements?.take(plafond).toList(growable: false);
    final lesAvances = avances(reservations);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Le nombre de lignes est rendu SEULEMENT quand la source est lue :
        // « (0) » avant la lecture affirmerait qu'il n'y en a aucune.
        _TitreSection(
          lesAvances == null
              ? 'Avances et acomptes'
              : 'Avances et acomptes (${lesAvances.length})',
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.lg), // mb-6
          child: lesAvances == null
              ? const _TableauAvances(avances: null)
              : ListePaginee<Reservation>(
                  elements: lesAvances,
                  prefixeCle: 'clients-avances-pagination',
                  masquerSiVide: true,
                  constructeur: (_, page) => _TableauAvances(avances: page),
                ),
        ),
        _TitreSection(
          affiches == null
              ? 'Recouvrements encaissés'
              : 'Recouvrements encaissés (${affiches.length})',
        ),
        if (affiches == null)
          _TableauRecouvrements(
            paiements: null,
            clients: clients,
            creances: creances,
          )
        else
          ListePaginee<PaiementFacture>(
            elements: affiches,
            prefixeCle: 'clients-recouvrements-pagination',
            masquerSiVide: true,
            constructeur: (_, page) => _TableauRecouvrements(
              paiements: page,
              clients: clients,
              creances: creances,
            ),
          ),
      ],
    );
  }
}

/// Le tableau « Avances et acomptes » (`clients-creances.blade.php` l.478-497) :
/// `Date · Client · Origine · Avance versée · Reste dû`.
///
/// La date est l'ARRIVÉE du séjour (`date_arrivee`), l'origine le canal de la
/// réservation (« — » quand il est vide), l'avance l'acompte versé. Le reste dû
/// est celui de la réservation : « — » quand son montant est inconnu, « Soldé »
/// quand il est nul, le montant en rouge sinon.
///
/// ## Un montant inconnu se dit « — », jamais un négatif
///
/// Une réservation descendue d'un autre poste sans tarif ni ligne (`tarifNuit` à
/// zéro, précédent `ReservationDto`) a un montant total de zéro : son « reste »
/// vaudrait `−acompte`. La vue rend `null` dans ce cas (`resteAPayer()` sans
/// `tarif_nuit` figé) ; le poste fait de même plutôt que d'afficher une dette
/// négative qui n'existe pas.
class _TableauAvances extends StatelessWidget {
  const _TableauAvances({required this.avances});

  final List<Reservation>? avances;

  static const _colonnes = [
    'Date',
    'Client',
    'Origine',
    'Avance versée',
    'Reste dû',
  ];

  /// Le reste dû affiché, ou `null` quand le montant de la réservation est
  /// inconnu.
  static int? resteDu(Reservation r) =>
      r.lignes.isEmpty && r.tarifNuit == 0 ? null : r.resteAPayer;

  @override
  Widget build(BuildContext context) {
    final l = avances;

    return Container(
      key: const Key('clients-avances-tableau'),
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
                        textAlign: c == 'Avance versée' || c == 'Reste dû'
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
          if (l == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (l.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: Text(
                'Aucune avance enregistrée.',
                key: const Key('clients-avances-vide'),
                textAlign: TextAlign.center,
                style: _t(TaillesContenu.t13, couleur: AppColors.neutre400),
              ),
            )
          else
            for (final r in l) _ligne(r),
        ],
      ),
    );
  }

  Widget _ligne(Reservation r) {
    final reste = resteDu(r);
    final texteReste = reste == null
        ? '—'
        : (reste == 0 ? 'Soldé' : formaterFcfa(reste));
    final enRouge = reste != null && reste != 0;

    return Container(
      key: Key('clients-avance-ligne-${r.id}'),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.neutre100)),
      ),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xsPlus),
      child: Row(
        children: [
          _cellule(
            formaterDate(r.periode.arrivee),
            style: _t(TaillesContenu.t13, couleur: Ardoise.c600),
          ),
          _cellule(
            r.clientNom.isEmpty ? '—' : r.clientNom,
            style: _t(
              TaillesContenu.t13,
              poids: FontWeight.w600,
              couleur: Ardoise.c800,
            ),
          ),
          _cellule(
            r.canal?.libelle ?? '—',
            style: _t(TaillesContenu.t13, couleur: Ardoise.c600),
          ),
          _cellule(
            formaterFcfa(r.acompte),
            droite: true,
            style: _t(
              TaillesContenu.t13,
              poids: FontWeight.w600,
              couleur: PaletteMaitre.emeraude600,
            ),
          ),
          _cellule(
            texteReste,
            droite: true,
            style: _t(
              TaillesContenu.t13,
              poids: enRouge ? FontWeight.w600 : null,
              couleur: enRouge ? PaletteMaitre.rouge600 : Ardoise.c400,
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
