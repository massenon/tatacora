// Vue Blade maîtresse (PA-183) : pwa/livewire/accueil.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/rbac/garde_acces.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../crm/domain/avertissement_doublon_serveur.dart';
import '../../../crm/domain/entities/client.dart';
import '../../../hebergement/domain/entities/fiche_reservation.dart';
import '../../../hebergement/domain/entities/periode_sejour.dart';
import '../../../hebergement/domain/entities/unite_hebergement.dart';
import '../../../hebergement/domain/messages_sejour.dart';
import '../../../hebergement/domain/repositories/reservation_repository.dart';
import '../../../hebergement/presentation/providers_hebergement.dart';
import '../../../restaurant/presentation/widgets/coquille_modale_restaurant.dart';
import '../../domain/exploitation_locale.dart';
import '../../domain/regles_saisie_accueil.dart';
import '../ecran_pilotage_consolide.dart'
    show
        horlogeTableauDeBordProvider,
        parcPilotageProvider,
        reservationsPilotageProvider;
import 'champ_date_periode.dart';
import 'champs_modale_accueil.dart';
import 'reservations_du_jour.dart';

/// Les trois modales RAPIDES de la vue d'accueil (lot C du plan du PO,
/// 14/10/2026) — elles remplacent la fiche de réservation complète et la
/// modale du registre M3 qu'ouvraient jusqu'ici les raccourcis :
///
/// | Modale de la vue | Geste du serveur | Ici |
/// |---|---|---|
/// | « Ajouter un client » (l.1420-1447) | `enregistrerClientRapide` | [ouvrirClientRapide] → `ClientDao.creer` |
/// | « Réservation rapide — Hébergement » (l.1449-1547) | `enregistrerReservationRapide` | [ouvrirReservationRapide] → `ClientDao.creer` + `CreerReservation`, UNE transaction |
/// | « Check-in — `:unite` » (l.1593-1647) | `confirmerCheckinDepuisChambre` | [ouvrirCheckinDepuisChambre] → client + réservation + `SejourDao.checkin`, UNE transaction |
///
/// Les champs, refus et effets sont ceux du composant : validation de
/// `validerEcriture` (messages Laravel, [regles_saisie_accueil.dart]), client
/// et réservation dans la MÊME transaction (« un refus RG-01 ne laisse aucune
/// fiche »), avertissement de doublon RG-18 du serveur à la création d'un
/// client, conflit RG-01 sous l'unité.
///
/// ## Écarts nommés (14/10/2026)
///
/// * **Arrivée passée** : le serveur l'accepte depuis la modale rapide ; ce
///   poste la REFUSE (règle de `CreerReservation`, seul chemin de création du
///   poste) et le dit sous la date. Ne pas contourner la règle locale pour un
///   seul formulaire.
/// * **Unité hors service** : `CreerReservation` la refuse aussi (la liste ne
///   la propose de toute façon pas, comme au serveur).
/// * **Unité sélectionnée qui sort de la liste** quand la date change : la
///   vue garde l'identifiant (un `<select>` Livewire), ce poste remet le choix
///   à vide — une liste déroulante Flutter ne peut pas afficher une valeur
///   absente de ses options.
/// * **Ordre de la liste des clients** : `orderBy('nom')->orderBy('id')` au
///   serveur, nom puis prénom ici (`ClientDao.clients`).
/// * Après « Ajouter un client », la vue présélectionne la fiche créée dans
///   la réservation rapide (état du composant) ; les modales de ce poste ne
///   partagent pas d'état, la fiche est simplement en tête de liste par son
///   nom.

/// Les quatre types de client du schéma, avec les libellés de la VUE
/// (`Accueil::TYPES_CLIENT` → `accueil_pwa.modale_client.type_*`) : « Structure »,
/// pas l'« Entreprise » de l'écran Clients.
const List<(TypeClientReferentiel, String)> typesClientAccueil = [
  (TypeClientReferentiel.particulier, 'Particulier'),
  (TypeClientReferentiel.groupe, 'Groupe'),
  (TypeClientReferentiel.agence, 'Agence partenaire'),
  (TypeClientReferentiel.structure, 'Structure'),
];

/// « nom prénom — téléphone », l'option de la vue (l.1491).
String _optionClient(Client c) =>
    '${'${c.nom} ${c.prenom ?? ''}'.trim()} — ${c.telephone}';

void _direSucces(BuildContext context, String message, Key cle) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message, key: cle)));
}

/* ====================================================================== */
/* Ajouter un client — `modale_client`                                     */
/* ====================================================================== */

/// `wire:click="ouvrirClientRapide"`.
Future<void> ouvrirClientRapide(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => const _ModaleClientRapide(),
);

class _ModaleClientRapide extends ConsumerStatefulWidget {
  const _ModaleClientRapide();

  @override
  ConsumerState<_ModaleClientRapide> createState() =>
      _ModaleClientRapideState();
}

class _ModaleClientRapideState extends ConsumerState<_ModaleClientRapide> {
  final _nom = TextEditingController();
  final _telephone = TextEditingController();
  TypeClientReferentiel _type = TypeClientReferentiel.particulier;
  Map<String, String> _erreurs = const {};
  bool _enCours = false;

  @override
  void dispose() {
    _nom.dispose();
    _telephone.dispose();
    super.dispose();
  }

  Future<void> _enregistrer() async {
    final erreurs = {
      'nom': ?texteRequis255(_nom.text, AttributsAccueil.clientNom),
      'telephone': ?texteRequis255(
        _telephone.text,
        AttributsAccueil.clientTelephone,
      ),
    };
    if (erreurs.isNotEmpty) {
      setState(() => _erreurs = erreurs);
      return;
    }
    setState(() => _enCours = true);
    final dao = ref.read(clientDaoProvider);
    // RG-18 : AVERTIT, ne bloque pas — calculé AVANT la création, sur le
    // référentiel d'avant (`rechercherDoublons` puis `Client::create`).
    final avertissement = avertissementDoublonServeur(
      referentiel: await dao.clients(),
      nom: _nom.text,
      telephone: _telephone.text,
    );
    await dao.creer(nom: _nom.text, telephone: _telephone.text, type: _type);
    if (!mounted) return;
    rafraichirApresGesteAccueil(ref);
    final nom = _nom.text;
    Navigator.of(context).pop();
    _direSucces(
      context,
      // `avertissement_doublon ?? accueil_pwa.modale_client.succes`.
      avertissement ?? 'Client « $nom » ajouté.',
      const Key('tdb-client-ajoute'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CoquilleModaleRestaurant(
      cle: const Key('tdb-modale-client'),
      titre: 'Ajouter un client',
      largeur: MesuresAccueil.modaleRapide,
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          BlocChampAccueil(
            libelle: 'Nom complet',
            requis: true,
            champ: ChampTexteAccueil(
              key: const Key('tdb-client-nom'),
              controleur: _nom,
            ),
            erreur: _erreurs['nom'],
          ),
          BlocChampAccueil(
            libelle: 'Téléphone',
            requis: true,
            champ: ChampTexteAccueil(
              key: const Key('tdb-client-telephone'),
              controleur: _telephone,
            ),
            erreur: _erreurs['telephone'],
          ),
          BlocChampAccueil(
            libelle: 'Type de client',
            champ: ChampChoixAccueil<TypeClientReferentiel>(
              key: const Key('tdb-client-type'),
              valeur: _type,
              choix: typesClientAccueil,
              onChange: (t) {
                if (t != null) setState(() => _type = t);
              },
            ),
          ),
        ],
      ),
      actions: [
        const BoutonAnnulerAccueil(cle: Key('tdb-client-annuler')),
        BoutonValiderAccueil(
          cle: const Key('tdb-client-valider'),
          libelle: 'Ajouter',
          fond: AppColors.navy,
          onPressed: _enCours ? null : _enregistrer,
        ),
      ],
    );
  }
}

/* ====================================================================== */
/* Le client d'une modale de réservation : choisi OU créé                  */
/* ====================================================================== */

/// La case « + Nouveau client » et ce qu'elle ouvre — commune à la
/// réservation rapide et au check-in depuis une chambre (même markup dans la
/// vue). Masquée sans droit d'écriture sur M3 (`@if ($peutEcrireClient)`).
class _ClientDeLaModale extends ConsumerWidget {
  const _ClientDeLaModale({
    required this.prefixe,
    required this.nouveau,
    required this.onNouveau,
    required this.clientId,
    required this.onClient,
    required this.nom,
    required this.telephone,
    required this.type,
    required this.onType,
    required this.erreurs,
  });

  final String prefixe;
  final bool nouveau;
  final ValueChanged<bool> onNouveau;
  final String? clientId;
  final ValueChanged<String?> onClient;
  final TextEditingController nom;
  final TextEditingController telephone;
  final TypeClientReferentiel type;
  final ValueChanged<TypeClientReferentiel> onType;
  final Map<String, String> erreurs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final peutCreer = peutEcrireDepuisAccueil(
      ref.watch(droitsProvider),
      ModuleTatacora.m3Crm,
    );
    final clients = ref.watch(clientsProvider).value ?? const <Client>[];
    return BlocChampAccueil(
      libelle: 'Client',
      requis: true,
      aDroite: peutCreer
          ? InkWell(
              key: Key('$prefixe-nouveau-client'),
              onTap: () => onNouveau(!nouveau),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    value: nouveau,
                    onChanged: (v) => onNouveau(v ?? false),
                    visualDensity: VisualDensity.compact,
                  ),
                  const Text(
                    '+ Nouveau client',
                    style: TextStyle(
                      fontFamily: AppTextStyles.police,
                      fontSize: Tailles.t12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.neutre500,
                    ),
                  ),
                ],
              ),
            )
          : null,
      erreur: nouveau ? null : erreurs['client'],
      champ: nouveau
          // `space-y-2 bg-slate-50 rounded-lg p-3` : nom, téléphone, type.
          ? Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: Ardoise.c50,
                borderRadius: BorderRadius.circular(AppRadius.roundedLg),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ChampTexteAccueil(
                    key: Key('$prefixe-client-nom'),
                    controleur: nom,
                    indication: 'Nom complet',
                  ),
                  ErreurChampAccueil(erreurs['nom']),
                  const SizedBox(height: AppSpacing.xs),
                  ChampTexteAccueil(
                    key: Key('$prefixe-client-telephone'),
                    controleur: telephone,
                    indication: 'Téléphone',
                  ),
                  ErreurChampAccueil(erreurs['telephone']),
                  const SizedBox(height: AppSpacing.xs),
                  ChampChoixAccueil<TypeClientReferentiel>(
                    key: Key('$prefixe-client-type'),
                    valeur: type,
                    choix: typesClientAccueil,
                    onChange: (t) {
                      if (t != null) onType(t);
                    },
                  ),
                ],
              ),
            )
          : ChampChoixAccueil<String>(
              key: Key('$prefixe-client'),
              valeur: clients.any((c) => c.id == clientId) ? clientId : null,
              consigne: 'Choisissez un client',
              choix: [for (final c in clients) (c.id, _optionClient(c))],
              onChange: onClient,
            ),
    );
  }
}

/* ====================================================================== */
/* Réservation rapide — `modale_reservation`                               */
/* ====================================================================== */

/// `wire:click="ouvrirReservationRapide"` : arrivée aujourd'hui, une nuit.
Future<void> ouvrirReservationRapide(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => const _ModaleReservationRapide(),
);

class _ModaleReservationRapide extends ConsumerStatefulWidget {
  const _ModaleReservationRapide();

  @override
  ConsumerState<_ModaleReservationRapide> createState() =>
      _ModaleReservationRapideState();
}

class _ModaleReservationRapideState
    extends ConsumerState<_ModaleReservationRapide> {
  bool _nouveau = false;
  String? _clientId;
  final _nom = TextEditingController();
  final _telephone = TextEditingController();
  TypeClientReferentiel _type = TypeClientReferentiel.particulier;
  String? _uniteId;
  CanalReservation? _canal;
  DateTime? _arrivee;
  final _nuits = TextEditingController(text: '1');
  Map<String, String> _erreurs = const {};
  bool _enCours = false;

  @override
  void initState() {
    super.initState();
    // `resaDateArrivee = today()` à l'ouverture.
    _arrivee = ref.read(horlogeTableauDeBordProvider)();
  }

  @override
  void dispose() {
    _nom.dispose();
    _telephone.dispose();
    _nuits.dispose();
    super.dispose();
  }

  /// `unitesPourReservation()` : libres sur `[arrivée, arrivée + max(1,
  /// nuits))`, vide tant que la date manque.
  List<UniteHebergement> _libres() {
    final arrivee = _arrivee;
    final parc = ref.watch(parcPilotageProvider).value;
    final reservations = ref.watch(reservationsPilotageProvider).value;
    if (arrivee == null || parc == null || reservations == null) return [];
    return unitesLibresSurPeriode(
      unites: parc,
      reservations: reservations,
      arrivee: arrivee,
      nuits: int.tryParse(_nuits.text.trim()) ?? 1,
    );
  }

  Future<void> _enregistrer(List<UniteHebergement> libres) async {
    final (erreurNuits, nuits) = nuitsValides(
      _nuits.text,
      AttributsAccueil.resaNuits,
    );
    final erreurs = <String, String>{
      if (_nouveau) ...{
        'nom': ?texteRequis255(_nom.text, AttributsAccueil.resaClientNom),
        'telephone': ?texteRequis255(
          _telephone.text,
          AttributsAccueil.resaClientTelephone,
        ),
      } else
        'client': ?choixRequis(_clientId, AttributsAccueil.resaClientId),
      'unite': ?choixRequis(_uniteId, AttributsAccueil.resaUniteId),
      'canal': ?choixRequis(_canal, AttributsAccueil.resaCanalId),
      'arrivee': ?choixRequis(_arrivee, AttributsAccueil.resaDateArrivee),
      'nuits': ?erreurNuits,
    };
    if (erreurs.isNotEmpty) {
      setState(() => _erreurs = erreurs);
      return;
    }
    final unite = libres.where((u) => u.id == _uniteId).firstOrNull;
    if (unite == null) {
      setState(() => _erreurs = {'unite': messageChevauchementServeur});
      return;
    }
    setState(() => _enCours = true);
    final arrivee = _arrivee!;

    try {
      // Client et réservation dans la MÊME transaction (PA-116 côté
      // serveur) : si RG-01 refuse la chambre, le client créé pour cette
      // fiche est repris aussi.
      await ref.read(baseLocaleProvider).transaction(() async {
        var clientId = _clientId!;
        var clientNom = '';
        if (_nouveau) {
          final cree = await ref
              .read(clientDaoProvider)
              .creer(nom: _nom.text, telephone: _telephone.text, type: _type);
          clientId = cree.id;
          clientNom = cree.nom;
        }
        await ref
            .read(creerReservationProvider)
            .call(
              unite: unite,
              clientId: clientId,
              clientNom: clientNom,
              periode: PeriodeSejour(
                arrivee: arrivee,
                depart: DateTime(
                  arrivee.year,
                  arrivee.month,
                  arrivee.day + nuits!,
                ),
              ),
              canal: _canal,
              auteurId: ref.read(sessionProvider)?.utilisateurId ?? '',
            );
      });
    } on ChevauchementDetecte {
      _refuser('unite', messageChevauchementServeur);
      return;
    } on UniteIndisponible catch (e) {
      _refuser('unite', e.message);
      return;
    } on ArgumentError catch (e) {
      _refuser('arrivee', '${e.message}');
      return;
    }
    if (!mounted) return;
    rafraichirApresGesteAccueil(ref);
    Navigator.of(context).pop();
    _direSucces(
      context,
      // `accueil_pwa.modale_reservation.succes`.
      'Réservation enregistrée.',
      const Key('tdb-reservation-rapide-succes'),
    );
  }

  /// Le conflit arrive comme une erreur de champ, modale OUVERTE : fermer sur
  /// un refus ferait retaper les dates (le composant).
  void _refuser(String champ, String message) {
    if (!mounted) return;
    setState(() {
      _erreurs = {champ: message};
      _enCours = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final libres = _libres();
    // Une unité qui n'est plus libre sur la période saisie sort du choix
    // (écart nommé en tête de fichier).
    final uniteChoisie = libres.any((u) => u.id == _uniteId) ? _uniteId : null;
    final aujourdhui = ref.read(horlogeTableauDeBordProvider)();

    return CoquilleModaleRestaurant(
      cle: const Key('tdb-modale-reservation-rapide'),
      titre: 'Réservation rapide — Hébergement',
      largeur: MesuresAccueil.modaleReservationRapide,
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // `text-[13px] text-slate-400 bg-slate-50 rounded-lg px-3 py-2` :
          // le renvoi au formulaire complet (`route('pwa.reservations')`).
          Container(
            margin: const EdgeInsets.only(bottom: AppSpacing.md),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: Ardoise.c50,
              borderRadius: BorderRadius.circular(AppRadius.roundedLg),
            ),
            child: Wrap(
              children: [
                const Text(
                  'Pour combiner plusieurs services (restauration, bar, '
                  'tourisme, véhicule), utilisez le formulaire complet. ',
                  style: TextStyle(
                    fontFamily: AppTextStyles.police,
                    fontSize: Tailles.t13,
                    color: AppColors.neutre400,
                  ),
                ),
                InkWell(
                  key: const Key('tdb-reservation-rapide-renvoi'),
                  onTap: () {
                    final routeur = GoRouter.of(context);
                    Navigator.of(context).pop();
                    routeur.go('/hebergement/reservations');
                  },
                  child: const Text(
                    'formulaire complet',
                    style: TextStyle(
                      fontFamily: AppTextStyles.police,
                      fontSize: Tailles.t13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.gold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          _ClientDeLaModale(
            prefixe: 'tdb-resa',
            nouveau: _nouveau,
            onNouveau: (v) => setState(() => _nouveau = v),
            clientId: _clientId,
            onClient: (v) => setState(() => _clientId = v),
            nom: _nom,
            telephone: _telephone,
            type: _type,
            onType: (t) => setState(() => _type = t),
            erreurs: _erreurs,
          ),
          // L'ordre de la vue : Client, Unité, Canal, Arrivée, Nuits.
          BlocChampAccueil(
            libelle: 'Unité',
            requis: true,
            champ: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                ChampChoixAccueil<String>(
                  key: ValueKey('tdb-resa-unite-${libres.length}'),
                  valeur: uniteChoisie,
                  consigne: 'Choisissez une unité libre sur la période',
                  choix: [
                    for (final u in libres)
                      (u.id, '${u.numero} — ${u.categorieLibelle}'),
                  ],
                  onChange: (v) => setState(() => _uniteId = v),
                ),
                if (libres.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: AppSpacing.unit),
                    child: Text(
                      "Aucune unité n'est libre sur cette période.",
                      key: Key('tdb-resa-aucune-unite'),
                      style: TextStyle(
                        fontFamily: AppTextStyles.police,
                        fontSize: Tailles.t12,
                        color: PaletteMaitre.ambre700,
                      ),
                    ),
                  ),
              ],
            ),
            erreur: _erreurs['unite'],
          ),
          BlocChampAccueil(
            libelle: 'Canal de réservation',
            requis: true,
            champ: ChampChoixAccueil<CanalReservation>(
              key: const Key('tdb-resa-canal'),
              valeur: _canal,
              consigne: 'Choisissez un canal',
              choix: [for (final c in CanalReservation.values) (c, c.libelle)],
              onChange: (c) => setState(() => _canal = c),
            ),
            erreur: _erreurs['canal'],
          ),
          // `grid grid-cols-2 gap-3` : Arrivée, Nuits.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: BlocChampAccueil(
                  libelle: 'Arrivée',
                  requis: true,
                  champ: ChampDatePeriode(
                    cle: const Key('tdb-resa-arrivee'),
                    titre: 'Arrivée',
                    valeur: _arrivee,
                    initiale: aujourdhui,
                    onChoix: (d) => setState(() => _arrivee = d),
                    onEffacer: () => setState(() => _arrivee = null),
                  ),
                  erreur: _erreurs['arrivee'],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: BlocChampAccueil(
                  libelle: 'Nuits',
                  requis: true,
                  champ: ChampTexteAccueil(
                    key: const Key('tdb-resa-nuits'),
                    controleur: _nuits,
                    numerique: true,
                    // `wire:model.live` : la liste des unités suit la saisie.
                    onChange: (_) => setState(() {}),
                  ),
                  erreur: _erreurs['nuits'],
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        const BoutonAnnulerAccueil(cle: Key('tdb-resa-annuler')),
        BoutonValiderAccueil(
          cle: const Key('tdb-resa-valider'),
          libelle: 'Enregistrer',
          fond: AppColors.navy,
          onPressed: _enCours ? null : () => _enregistrer(libres),
        ),
      ],
    );
  }
}

/* ====================================================================== */
/* Check-in depuis « Chambres disponibles » — `modale_checkin_chambre`     */
/* ====================================================================== */

/// `wire:click="ouvrirCheckinDepuisChambre('…')"` : une nuit par défaut.
Future<void> ouvrirCheckinDepuisChambre(
  BuildContext context,
  UniteHebergement unite,
) => showDialog<void>(
  context: context,
  builder: (_) => _ModaleCheckinChambre(unite: unite),
);

class _ModaleCheckinChambre extends ConsumerStatefulWidget {
  const _ModaleCheckinChambre({required this.unite});

  final UniteHebergement unite;

  @override
  ConsumerState<_ModaleCheckinChambre> createState() =>
      _ModaleCheckinChambreState();
}

class _ModaleCheckinChambreState extends ConsumerState<_ModaleCheckinChambre> {
  bool _nouveau = false;
  String? _clientId;
  final _nom = TextEditingController();
  final _telephone = TextEditingController();
  TypeClientReferentiel _type = TypeClientReferentiel.particulier;
  final _nuits = TextEditingController(text: '1');
  Map<String, String> _erreurs = const {};
  bool _enCours = false;

  @override
  void dispose() {
    _nom.dispose();
    _telephone.dispose();
    _nuits.dispose();
    super.dispose();
  }

  /// `confirmerCheckinDepuisChambre` : la réservation du jour (canal
  /// « Physique », comme le serveur pour CE geste) ET l'arrivée, dans la MÊME
  /// transaction — un client qui se présente sans réservation n'en a jamais
  /// eu, et créer l'une sans l'autre laisserait soit une chambre réservée mais
  /// vide, soit un séjour sans réservation.
  Future<void> _confirmer() async {
    final (erreurNuits, nuits) = nuitsValides(
      _nuits.text,
      AttributsAccueil.checkinNuits,
    );
    final erreurs = <String, String>{
      if (_nouveau) ...{
        'nom': ?texteRequis255(_nom.text, AttributsAccueil.checkinClientNom),
        'telephone': ?texteRequis255(
          _telephone.text,
          AttributsAccueil.checkinClientTelephone,
        ),
      } else
        'client': ?choixRequis(_clientId, AttributsAccueil.checkinClientId),
      'nuits': ?erreurNuits,
    };
    if (erreurs.isNotEmpty) {
      setState(() => _erreurs = erreurs);
      return;
    }
    setState(() => _enCours = true);
    final arrivee = ref.read(horlogeTableauDeBordProvider)();

    try {
      await ref.read(baseLocaleProvider).transaction(() async {
        var clientId = _clientId!;
        var clientNom = '';
        if (_nouveau) {
          final cree = await ref
              .read(clientDaoProvider)
              .creer(nom: _nom.text, telephone: _telephone.text, type: _type);
          clientId = cree.id;
          clientNom = cree.nom;
        }
        final reservation = await ref
            .read(creerReservationProvider)
            .call(
              unite: widget.unite,
              clientId: clientId,
              clientNom: clientNom,
              periode: PeriodeSejour(
                arrivee: arrivee,
                depart: DateTime(
                  arrivee.year,
                  arrivee.month,
                  arrivee.day + nuits!,
                ),
              ),
              canal: CanalReservation.physique,
              auteurId: ref.read(sessionProvider)?.utilisateurId ?? '',
            );
        await ref.read(sejourDaoProvider).checkin(reservation.id);
      });
    } on ChevauchementDetecte {
      _refuser(messageChevauchementServeur);
      return;
    } on UniteIndisponible catch (e) {
      _refuser(e.message);
      return;
    } on RefusSejour catch (e) {
      _refuser(e.message);
      return;
    }
    if (!mounted) return;
    rafraichirApresGesteAccueil(ref);
    Navigator.of(context).pop();
    _direSucces(
      context,
      // `accueil_pwa.modale_checkin_chambre.succes`.
      'Check-in enregistré.',
      const Key('tdb-checkin-chambre-succes'),
    );
  }

  /// `addError('checkinUniteId', …)` — rendu en bas du formulaire, comme la
  /// vue (l.1640).
  void _refuser(String message) {
    if (!mounted) return;
    setState(() {
      _erreurs = {'unite': message};
      _enCours = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return CoquilleModaleRestaurant(
      cle: const Key('tdb-modale-checkin-chambre'),
      titre: 'Check-in — ${widget.unite.numero}',
      largeur: MesuresAccueil.modaleRapide,
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _ClientDeLaModale(
            prefixe: 'tdb-checkin-chambre',
            nouveau: _nouveau,
            onNouveau: (v) => setState(() => _nouveau = v),
            clientId: _clientId,
            onClient: (v) => setState(() => _clientId = v),
            nom: _nom,
            telephone: _telephone,
            type: _type,
            onType: (t) => setState(() => _type = t),
            erreurs: _erreurs,
          ),
          BlocChampAccueil(
            libelle: 'Nombre de nuits',
            requis: true,
            champ: ChampTexteAccueil(
              key: const Key('tdb-checkin-chambre-nuits'),
              controleur: _nuits,
              numerique: true,
            ),
            erreur: _erreurs['nuits'],
          ),
          ErreurChampAccueil(
            _erreurs['unite'],
            key: const Key('tdb-checkin-chambre-erreur'),
          ),
        ],
      ),
      actions: [
        const BoutonAnnulerAccueil(cle: Key('tdb-checkin-chambre-annuler')),
        BoutonValiderAccueil(
          cle: const Key('tdb-checkin-chambre-confirmer'),
          libelle: 'Confirmer le Check-in',
          fond: AppColors.succes,
          onPressed: _enCours ? null : _confirmer,
        ),
      ],
    );
  }
}
