// Vue Blade maîtresse (PA-183) : pwa/hebergement/reservations.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/format/formats.dart';
import '../../../core/rbac/garde_acces.dart';
import '../../crm/domain/entities/client.dart';
import '../../crm/presentation/dialogue_nouveau_client.dart';
import '../../../core/di/providers.dart';
import '../../comptabilite/domain/refus_comptable.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../domain/entities/fiche_reservation.dart';
import '../domain/entities/periode_sejour.dart';
import '../domain/entities/reservation.dart';
import '../domain/entities/service_reservation.dart';
import '../domain/repositories/reservation_repository.dart';
import '../impression/confirmation_reservation.dart';
import 'panneau_historique.dart';
import 'providers_hebergement.dart';
import 'widgets/dialogue_impression_reservation.dart';
import 'widgets/vue_services.dart';

/// Ouvre la **fiche de réservation** — `reservations.html` l.107-190.
///
/// ## Une modale, pas une page
///
/// Le maître ouvre `#modale-reservation` **par-dessus la grille**, et c'est un
/// choix de fond, pas de décoration : la liste des réservations reste derrière,
/// et la fiche se ferme sur ce qu'on regardait avant. Une page à part fait
/// perdre le contexte — on ne sait plus, en refermant, où l'on revient.
///
/// C'est aussi ce qui rend possible le panneau Historique par-dessus la fiche
/// (`historique-reservations.js` l.5-11) : trois plans superposés, la grille,
/// la fiche, l'historique, chacun conservant l'état du précédent.
///
/// Rend la réservation créée ou modifiée, `null` si l'utilisateur a renoncé.
Future<Reservation?> ouvrirFicheReservation(
  BuildContext context, {
  String? uniteId,
  String? reservationId,
}) {
  return showDialog<Reservation>(
    context: context,
    // Fermer d'un clic dehors perdrait une saisie en cours **sans rien
    // demander** — et le maître ne le permet pas non plus : sa boîte n'a que
    // la croix et « Annuler ».
    barrierDismissible: false,
    builder: (context) {
      final ecran = MediaQuery.sizeOf(context);

      return Dialog(
        insetPadding: const EdgeInsets.all(AppSpacing.md),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            // `max-width:760px` du maître — valeur mesurée, pas supposée.
            maxWidth: AppLayout.ficheReservation,
            // `max-h-[72vh]` : la boîte ne dépasse jamais les trois quarts de
            // l'écran, et c'est son CORPS qui défile. Sans cette borne, une
            // fiche à cinq services pousserait l'en-tête et le pied hors de
            // l'écran, avec le bouton d'enregistrement.
            maxHeight: ecran.height * 0.72,
          ),
          child: FicheReservation(
            uniteId: uniteId,
            reservationId: reservationId,
          ),
        ),
      );
    },
  );
}

/// Écran **Nouvelle réservation** — portage de `prototype_v2/pages/
/// reservations.html` l.107-190.
///
/// ## L'ordre du maître, et rien d'autre
///
/// Client, Type de client, Canal, dates d'arrivée et de départ ; puis les
/// **services inclus** ; puis leurs lignes ; puis le Récapitulatif — Remise,
/// Acompte versé, Mode de paiement, et le bloc à cinq lignes. Le pied porte
/// « Annuler » et « Enregistrer la réservation ».
///
/// L'ordre n'est pas une préférence de mise en page : il suit le geste du
/// réceptionniste, qui identifie le client, fixe les dates, compose le séjour,
/// puis annonce un montant. Le réordonner obligerait à annoncer un prix avant
/// de savoir ce qu'il couvre.
///
/// ## Une réservation combine cinq services
///
/// C'est la phrase que le maître met en sous-titre de la page (l.30). Le
/// sous-total du récapitulatif est la **somme des lignes**, jamais
/// `tarif × nuits` : cette dernière formule est juste pour un séjour sec et
/// fausse dès qu'un circuit entre dans la même fiche.
///
/// ## Deux écarts assumés, tous deux tenus par un refus explicite
///
///  1. Le maître permet **plusieurs chambres** sur une fiche ; le schéma
///     serveur n'a qu'une colonne `unite_id` (`FULL_MIGRATIONS_DATABASE.md`
///     l.411). Deux chambres partiraient comme une seule et la seconde serait
///     perdue en silence — elle resterait libre au planning, et le
///     double-booking que M1 existe pour empêcher se produirait. Le cas est
///     refusé et nommé, jamais deviné.
///  2. Le maître permet une réservation **sans hébergement** (un circuit
///     seul). `reservations.unite_id` est NOT NULL : impossible à représenter.
///     Refusé de la même façon.
///
/// Les deux sont inscrits au registre PA. Le jour où le schéma serveur les
/// accueillera, c'est `CreerReservation` qu'on rouvre.
class FicheReservation extends ConsumerStatefulWidget {
  const FicheReservation({this.uniteId, this.reservationId, super.key});

  /// Unité pré-retenue quand on arrive depuis l'onglet Disponibilités ou depuis
  /// une carte du plan.
  ///
  /// Optionnelle : on peut aussi choisir la chambre dans les lignes du
  /// service. Le raccourci est conservé parce qu'il
  /// existe déjà au comptoir — il **pré-coche** l'hébergement et pose la
  /// ligne, il ne verrouille rien.
  final String? uniteId;

  /// Réservation à MODIFIER. `null` pour une création.
  ///
  /// Le maître emploie **la même modale** pour les deux gestes
  /// (`ouvrirModale(id)`) : les champs sont identiques, seuls le titre et la
  /// destination de l'enregistrement changent. Un second écran d'édition
  /// finirait par diverger du premier — le formulaire de création recevrait un
  /// champ que celui de modification n'aurait pas, et la fiche perdrait la
  /// valeur en se rouvrant.
  final String? reservationId;

  bool get enEdition => reservationId != null;

  @override
  ConsumerState<FicheReservation> createState() => _FicheReservationState();
}

class _FicheReservationState extends ConsumerState<FicheReservation> {
  static const _uuid = Uuid();

  final _formulaire = GlobalKey<FormState>();
  final _acompte = TextEditingController(text: '0');
  final _remiseValeur = TextEditingController(text: '0');

  // Les listes du maître. Chacune a une valeur initiale, comme les `<select>`
  // du maître qui affichent tous leur première option.
  TypeClient _typeClient = TypeClient.parDefaut;

  /// Canal et mode de paiement partent VIDES, comme les `<select>` de la vue
  /// dont la première option est « Choisissez un canal » / « Choisissez un
  /// mode » : les deux sont `nullable` au serveur (`rCanalId`,
  /// `rModePaiement`). Une origine ou un mode devinés fausseraient l'analyse
  /// par canal et la pièce de l'acompte sans que rien ne le signale.
  CanalReservation? _canal;
  ModePaiementReservation? _modePaiement;
  TypeRemise _typeRemise = TypeRemise.aucune;

  DateTime? _arrivee;
  DateTime? _depart;

  /// Le client RETENU — une vraie clé étrangère, jamais un nom tapé.
  ///
  /// Jusqu'au 25/08/2026, la fiche écrivait `clientId: 'cli-comptoir'` en dur :
  /// toutes les réservations du poste portaient le même client fictif, et le
  /// nom saisi au clavier n'était enregistré nulle part.
  Client? _client;

  /// L'identifiant à retrouver dans le référentiel, en modification.
  /// Résolu dès que la liste des clients est disponible.
  String? _clientPrerempli;

  final _coches = <ServiceReservation>{};
  final _lignes = <ServiceReservation, List<LigneService>>{};

  bool _preselectionFaite = false;

  /// La fiche a-t-elle déjà été reprise depuis la réservation à modifier ?
  ///
  /// Distinct de [_preselectionFaite] : les deux remplissages n'ont pas lieu au
  /// même moment du rendu — l'un avant la demande du catalogue, l'autre après.
  bool _ficheReprise = false;

  /// La réservation en cours de modification, relue en base. `null` en
  /// création — et tant que la lecture n'a pas abouti.
  Reservation? _existante;
  bool _envoiEnCours = false;
  String? _erreur;
  String? _erreurServices;

  @override
  void initState() {
    super.initState();
    // Les dates de l'onglet Disponibilités servent de valeurs initiales : le
    // réceptionniste vient de les saisir là-bas, les lui redemander serait une
    // double saisie. Elles restent modifiables ici, comme au maître.
    final periode = ref.read(periodeConsulteeProvider);
    _arrivee = periode.arrivee;
    _depart = periode.depart;
  }

  @override
  void dispose() {
    _acompte.dispose();
    _remiseValeur.dispose();
    super.dispose();
  }

  /* ================================================================== */
  /* Dérivations — toutes calculées, aucune saisie                       */
  /* ================================================================== */

  /// Nombre de nuits, bornes **semi-ouvertes** : arrivée le 10, départ le 12,
  /// deux nuits. Même convention que le contrôle de chevauchement (RG-01) — en
  /// retenir une autre ici ferait facturer une nuit de plus que celles
  /// réellement bloquées.
  ///
  /// `null` tant que les deux dates ne sont pas connues, pour que l'écran
  /// affiche une consigne plutôt qu'un zéro qui ressemblerait à un calcul.
  int? get _nuits {
    final a = _arrivee;
    final d = _depart;
    if (a == null || d == null) return null;
    final n = PeriodeSejour(arrivee: a, depart: d).nuits;
    return n > 0 ? n : null;
  }

  List<LigneService> get _toutesLignes => [
    for (final service in ServiceReservation.values)
      if (_coches.contains(service)) ...(_lignes[service] ?? const []),
  ];

  int get _sousTotal =>
      _toutesLignes.fold(0, (somme, ligne) => somme + ligne.sousTotal);

  int get _acompteSaisi => int.tryParse(_acompte.text.trim()) ?? 0;

  RecapitulatifReservation get _recap => RecapitulatifReservation.calculer(
    sousTotal: _sousTotal,
    typeRemise: _typeRemise,
    valeurRemise: num.tryParse(_remiseValeur.text.trim()) ?? 0,
    acompte: _acompteSaisi,
  );

  /* ================================================================== */
  /* Gestes                                                              */
  /* ================================================================== */

  void _basculerService(ServiceReservation service) {
    setState(() {
      _erreurServices = null;
      if (_coches.remove(service)) return;
      _coches.add(service);
      // Le maître ouvre le bloc vide : c'est l'utilisateur qui ajoute sa
      // première ligne. Une ligne posée d'office ferait apparaître un
      // « Choisir... » que personne n'a demandé, et qu'il faudrait retirer.
      _lignes.putIfAbsent(service, () => []);
    });
  }

  void _ajouterLigne(ServiceReservation service) {
    setState(() {
      // Une chambre ajoutée prend d'emblée la durée du séjour : démarrer à une
      // nuit afficherait un montant faux entre l'ajout et le premier
      // recalcul (`reservations-services.js:ajouterLigne`).
      final quantite = service.quantiteEstCalculee ? (_nuits ?? 1) : 1;
      (_lignes[service] ??= []).add(
        LigneService(
          id: 'l-${_uuid.v4()}',
          service: service,
          itemId: '',
          libelle: '',
          prixUnitaire: 0,
          quantite: quantite,
        ),
      );
    });
  }

  void _retirerLigne(ServiceReservation service, String ligneId) {
    setState(
      () => _lignes[service]?.removeWhere((ligne) => ligne.id == ligneId),
    );
  }

  void _choisir(
    ServiceReservation service,
    String ligneId,
    OptionService option,
  ) {
    setState(() {
      _remplacer(
        service,
        ligneId,
        (ligne) => ligne.copyWith(
          itemId: option.id,
          // Libellé et prix FIGÉS à l'ajout : les relire au catalogue ferait
          // varier le montant d'une réservation déjà prise au premier
          // changement de grille (même raisonnement que `tarifNuit`, PA-55).
          libelle: option.libelle,
          prixUnitaire: option.prix,
        ),
      );
    });
  }

  void _changerQuantite(
    ServiceReservation service,
    String ligneId,
    int quantite,
  ) {
    setState(
      () => _remplacer(
        service,
        ligneId,
        (ligne) => ligne.copyWith(quantite: quantite),
      ),
    );
  }

  void _remplacer(
    ServiceReservation service,
    String ligneId,
    LigneService Function(LigneService) transformation,
  ) {
    final lignes = _lignes[service];
    if (lignes == null) return;
    final index = lignes.indexWhere((ligne) => ligne.id == ligneId);
    if (index < 0) return;
    lignes[index] = transformation(lignes[index]);
  }

  Future<void> _choisirDate({required bool arrivee}) async {
    final initiale = (arrivee ? _arrivee : _depart) ?? DateTime.now();
    final choisie = await showDatePicker(
      context: context,
      initialDate: initiale,
      // Une arrivée dans le passé fausserait la disponibilité de toutes les
      // périodes antérieures : le sélecteur ne la propose pas, plutôt que de
      // la refuser après coup.
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (choisie == null) return;

    setState(() {
      if (arrivee) {
        _arrivee = choisie;
        // Une arrivée déplacée au-delà du départ pousse le départ : c'est ce
        // que l'utilisateur veut dire, et refuser sa saisie l'obligerait à
        // s'y reprendre dans un ordre qu'il n'a pas choisi.
        final d = _depart;
        if (d != null && !d.isAfter(choisie)) {
          _depart = choisie.add(const Duration(days: 1));
        }
      } else {
        _depart = choisie;
      }
      _synchroniserNuits();
    });
  }

  /// Aligne les quantités d'hébergement sur la durée du séjour.
  ///
  /// Allonger le séjour d'un jour doit remonter le nombre de nuits, le
  /// sous-total et le total **sans aucune saisie**
  /// (`reservations-services.js:synchroniserNuits`).
  void _synchroniserNuits() {
    final n = _nuits;
    if (n == null) return;
    final chambres = _lignes[ServiceReservation.hebergement];
    if (chambres == null) return;
    for (var i = 0; i < chambres.length; i++) {
      chambres[i] = chambres[i].copyWith(quantite: n);
    }
  }

  /* ================================================================== */
  /* Rendu                                                               */
  /* ================================================================== */

  @override
  Widget build(BuildContext context) {
    // ⚠ L'ORDRE DE CE QUI SUIT N'EST PAS INDIFFÉRENT.
    //
    // La réservation est lue d'abord, et le formulaire pré-rempli **avant**
    // que le catalogue ne soit demandé. La première version faisait l'inverse :
    // le catalogue partait avec la période par défaut (« cette nuit »), le
    // pré-remplissage posait ensuite les vraies dates du séjour, et rien ne
    // relançait la requête. Les chambres proposées étaient donc celles libres
    // **cette nuit**, sur une fiche qui porte un séjour dans dix jours — une
    // chambre déjà prise s'y serait présentée libre.
    //
    // Le défaut ne se voit pas à la relecture : les dates affichées, elles,
    // étaient justes.
    final existante = widget.enEdition
        ? ref.watch(reservationParIdProvider(widget.reservationId!))
        : const AsyncValue<Reservation?>.data(null);

    if (existante.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (existante.hasError) return Center(child: Text('${existante.error}'));

    final reservation = existante.value;
    if (widget.enEdition && reservation == null) {
      // Elle a pu être supprimée d'un autre poste entre l'ouverture de la
      // grille et le clic. Le dire vaut mieux qu'un formulaire vide, qu'on
      // remplirait pour rien.
      return const Center(child: Text('Réservation introuvable sur ce poste.'));
    }

    _preremplirDepuisReservation(reservation);

    // Les canaux viennent de la TABLE (Paramètres › Canaux de réservation), pas
    // d'une liste écrite en dur — et, comme le client ci-dessous, ils doivent
    // être LUS avant que la liste ne se monte : une liste déroulante ne retient
    // pas une valeur qui arrive après ses options (piège 6).
    final canauxLus = ref.watch(canauxReservationProvider);
    if (canauxLus.isLoading && !canauxLus.hasValue) {
      return const Center(child: CircularProgressIndicator());
    }

    // Le client pré-rempli est résolu contre le RÉFÉRENTIEL, dès qu'il est
    // lisible. C'est encore une question d'ordre : la liste déroulante ne peut
    // retenir une valeur qui n'est pas dans ses options, et les options
    // arrivent après la réservation.
    final prerempli = _clientPrerempli;
    if (_client == null && prerempli != null) {
      final connus = ref.watch(clientsProvider).value ?? const [];
      final trouves = connus.where((c) => c.id == prerempli);
      if (trouves.isNotEmpty) _client = trouves.first;
    }

    // ⚠ La réservation modifiée est EXCLUE du calcul d'occupation.
    //
    // Sans cela, rouvrir une fiche ferait apparaître sa propre chambre comme
    // « indisponible, déjà retenu » — retenue par elle-même —, et le seul
    // choix proposé serait d'en prendre une autre.
    final rayons = ref.watch(
      rayonsServicesProvider((
        arrivee: _arrivee,
        depart: _depart,
        exclure: widget.reservationId,
      )),
    );

    if (rayons.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (rayons.hasError) return Center(child: Text('${rayons.error}'));

    _preselectionnerUnite(rayons.requireValue);
    return _formulaire_(rayons.requireValue, reservation);
  }

  /// Les canaux PROPOSABLES : les actifs, plus celui déjà retenu par la fiche
  /// rouverte — un canal désactivé après coup ne disparaît pas d'une réservation
  /// qui le porte (`CanalReservation::proposables`). Sans table lisible, le jeu
  /// initial du maître.
  List<CanalReservation> _canauxProposables(List<CanalReservation>? lus) => [
    for (final c in lus ?? CanalReservation.jeuInitial)
      if (c.actif || c.memeQue(_canal)) c,
  ];

  /// Remplit le formulaire depuis la réservation à modifier — une seule fois.
  ///
  /// Refaire le remplissage à chaque rendu réécrirait la ligne, la date ou le
  /// canal que l'utilisateur vient de changer : la saisie serait littéralement
  /// impossible.
  ///
  /// Appelé **avant** que le catalogue ne soit demandé : c'est lui qui pose les
  /// dates, et le catalogue en dépend.
  void _preremplirDepuisReservation(Reservation? existante) {
    if (_ficheReprise) return;
    _ficheReprise = true;

    if (existante != null) {
      _existante = existante;
      // Le client est relu du référentiel : `clientNom` n'est qu'un affichage
      // reconstruit par le DAO. Repartir du nom rouvrirait la porte au texte
      // libre — et à une réservation rattachée à personne.
      _clientPrerempli = existante.clientId;
      _acompte.text = '${existante.acompte}';
      _typeClient = existante.typeClient ?? TypeClient.parDefaut;
      _canal = existante.canal;
      _modePaiement = existante.modePaiement;
      _typeRemise = existante.remiseType ?? TypeRemise.aucune;
      _remiseValeur.text = '${existante.remiseValeur ?? 0}';
      _arrivee = existante.periode.arrivee;
      _depart = existante.periode.depart;

      // Les lignes sont reprises TELLES QU'ELLES SONT EN BASE — libellé et
      // prix figés compris. Les recomposer depuis le catalogue courant
      // réécrirait le prix d'une réservation déjà prise au tarif du jour, ce
      // que `tarifNuit` existe précisément pour empêcher (PA-55).
      for (final ligne in existante.lignes) {
        _coches.add(ligne.service);
        (_lignes[ligne.service] ??= []).add(ligne);
      }
    }
  }

  /// Pré-coche l'hébergement quand on arrive depuis Disponibilités.
  ///
  /// Ne s'applique qu'à la CRÉATION : en modification, les lignes viennent de
  /// la réservation, et les recomposer depuis le catalogue courant réécrirait
  /// le prix figé d'une réservation déjà prise (PA-55).
  void _preselectionnerUnite(List<RayonService> rayons) {
    if (_preselectionFaite) return;
    _preselectionFaite = true;

    if (_existante != null) return;

    final uniteId = widget.uniteId;
    if (uniteId == null) return;

    final chambres = rayons
        .firstWhere((r) => r.service == ServiceReservation.hebergement)
        .options
        .where((o) => o.id == uniteId);
    if (chambres.isEmpty) return;

    final chambre = chambres.first;
    _coches.add(ServiceReservation.hebergement);
    _lignes[ServiceReservation.hebergement] = [
      LigneService(
        id: 'l-${_uuid.v4()}',
        service: ServiceReservation.hebergement,
        itemId: chambre.id,
        libelle: chambre.libelle,
        prixUnitaire: chambre.prix,
        quantite: _nuits ?? 1,
      ),
    ];
  }

  Widget _formulaire_(List<RayonService> rayons, Reservation? existante) {
    final textes = Theme.of(context).textTheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ---- En-tête FIXE de la modale (`reservations.html` l.110-120) ----
        //
        // Fixe, et non défilante : le maître la sort du corps (`p-6
        // max-h-[72vh] overflow-y-auto` ne couvre que le corps). Le titre et la
        // croix doivent rester visibles quand on fait défiler une fiche à cinq
        // services — sans quoi on ne sait plus ce qu'on remplit, ni comment en
        // sortir.
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.neutre200)),
          ),
          child: Row(
            children: [
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      // Le titre de la vue, au mot : `modale_titre_creation` ou
                      // `modale_titre_modification` (« Modifier la
                      // réservation »). Le nom du client, qui figurait ici en
                      // modification, est dans le champ « Client » juste
                      // dessous.
                      existante == null
                          ? 'Nouvelle réservation'
                          : 'Modifier la réservation',
                      key: const Key('titre-modale-reservation'),
                      overflow: TextOverflow.ellipsis,
                      style: textes.titleMedium?.copyWith(
                        color: AppColors.navy,
                      ),
                    ),
                    // `:sousTitre="__('hebergement_pwa.reservations.modale_sous_titre')"`.
                    Text(
                      'Les cinq champs que le schéma serveur porte pour une réservation.',
                      key: const Key('sous-titre-modale-reservation'),
                      overflow: TextOverflow.ellipsis,
                      style: textes.labelSmall?.copyWith(
                        color: AppColors.neutre500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              // Le second point d'entrée de l'historique, et le maître dit
              // pourquoi il existe (`historique-reservations.js` l.5-11) : au
              // moment de créer une réservation, la question la plus fréquente
              // est « ce client est-il déjà venu ? ». Devoir fermer la fiche
              // pour aller vérifier ferait perdre la saisie en cours — le
              // panneau se superpose, et il arrive **pré-rempli**.
              OutlinedButton.icon(
                key: const Key('bouton-historique-client'),
                onPressed: () => ouvrirHistoriqueReservations(
                  context,
                  termePrerempli: _client?.nomComplet ?? '',
                ),
                icon: const Icon(Icons.history, size: 14),
                label: const Text('Historique du client'),
              ),
              const Spacer(),
              IconButton(
                key: const Key('fermer-fiche-reservation'),
                tooltip: 'Fermer',
                onPressed: _envoiEnCours ? null : _fermer,
                icon: const Icon(Icons.close, size: 20),
              ),
            ],
          ),
        ),

        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Form(
              key: _formulaire,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ---- Identité et dates (grille à deux colonnes) --------
                  _Deux(
                    gauche: _ChampClient(
                      valeur: _client,
                      onChange: (c) => setState(() => _client = c),
                    ),
                    droite: _Liste<TypeClient>(
                      cle: const Key('champ-type-client'),
                      etiquette: 'Type de client',
                      valeur: _typeClient,
                      options: TypeClient.values,
                      libelle: (t) => t.libelle,
                      onChange: (t) =>
                          setState(() => _typeClient = t ?? _typeClient),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _Deux(
                    gauche: _Liste<CanalReservation>(
                      cle: const Key('champ-canal'),
                      etiquette: 'Canal de réservation',
                      invite: 'Choisissez un canal',
                      valeur: _canauxProposables(
                        ref.watch(canauxReservationProvider).value,
                      ).where((c) => c.memeQue(_canal)).firstOrNull,
                      options: _canauxProposables(
                        ref.watch(canauxReservationProvider).value,
                      ),
                      libelle: (c) => c.libelle,
                      onChange: (c) => setState(() => _canal = c),
                    ),
                    // La cellule vide du maître (l.136) : le canal occupe la
                    // colonne de gauche, les dates commencent une ligne neuve.
                    droite: const SizedBox.shrink(),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _Deux(
                    gauche: _ChampDate(
                      cle: const Key('champ-date-arrivee'),
                      // L'apostrophe est DROITE, comme au maître (l.137) : il
                      // en écrit 581 contre 39 typographiques. Et c'est aussi
                      // la sûre — les polices intégrées des PDF ne couvrent
                      // pas U+2019, qui disparaît du papier sans rien dire.
                      etiquette: 'Date d\'arrivée *',
                      valeur: _arrivee,
                      onAppui: () => _choisirDate(arrivee: true),
                    ),
                    droite: _ChampDate(
                      cle: const Key('champ-date-depart'),
                      etiquette: 'Date de départ *',
                      valeur: _depart,
                      onAppui: () => _choisirDate(arrivee: false),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // ---- Services inclus ------------------------------------
                  GrilleServices(
                    coches: _coches,
                    onBascule: _basculerService,
                    erreur: _erreurServices,
                  ),
                  const SizedBox(height: AppSpacing.md),

                  for (final rayon in rayons)
                    if (_coches.contains(rayon.service))
                      BlocLignesService(
                        rayon: rayon,
                        lignes: _lignes[rayon.service] ?? const [],
                        nuits: _nuits,
                        onAjouter: () => _ajouterLigne(rayon.service),
                        onRetirer: (id) => _retirerLigne(rayon.service, id),
                        onChoisir: (id, option) =>
                            _choisir(rayon.service, id, option),
                        onQuantite: (id, q) =>
                            _changerQuantite(rayon.service, id, q),
                      ),

                  // ---- Récapitulatif --------------------------------------
                  const SizedBox(height: AppSpacing.xs),
                  const Divider(),
                  const SizedBox(height: AppSpacing.xs),
                  Text('Récapitulatif', style: textes.titleMedium),
                  const SizedBox(height: AppSpacing.sm),

                  _Deux(
                    gauche: _Remise(
                      type: _typeRemise,
                      valeur: _remiseValeur,
                      onType: (t) => setState(() => _typeRemise = t),
                      onValeur: () => setState(() {}),
                    ),
                    droite: TextFormField(
                      key: const Key('champ-acompte'),
                      controller: _acompte,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        // « versé » et non « reçu » : c'est le mot du maître,
                        // et il dit le geste du client, pas celui du comptoir.
                        labelText: 'Acompte versé (FCFA)',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                      validator: (v) {
                        final saisi = int.tryParse((v ?? '').trim());
                        if (saisi == null) return 'Montant illisible.';
                        if (saisi < 0) {
                          return 'Un acompte ne peut pas être négatif.';
                        }
                        if (saisi > _recap.total) {
                          return 'L’acompte dépasse le total à payer '
                              '(${formaterFcfa(_recap.total)}).';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),

                  _Liste<ModePaiementReservation>(
                    cle: const Key('champ-mode-paiement'),
                    etiquette: 'Mode de paiement',
                    invite: 'Choisissez un mode',
                    valeur: _modePaiement,
                    options: ModePaiementReservation.values,
                    libelle: (m) => m.libelle,
                    onChange: (m) => setState(() => _modePaiement = m),
                  ),
                  const SizedBox(height: AppSpacing.sm),

                  _BlocRecapitulatif(recap: _recap),

                  if (_erreur != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Container(
                      key: const Key('message-erreur'),
                      padding: const EdgeInsets.all(AppSpacing.xs),
                      decoration: BoxDecoration(
                        color: AppColors.erreurFond,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: AppColors.erreur,
                            size: 16,
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(
                            child: Text(
                              _erreur!,
                              style: textes.bodySmall?.copyWith(
                                color: AppColors.erreur,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),

        // ---- Pied du maître : Annuler, puis Enregistrer -----------------
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: const BoxDecoration(
            color: AppColors.neutre100,
            border: Border(top: BorderSide(color: AppColors.neutre200)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    key: const Key('bouton-annuler'),
                    onPressed: _envoiEnCours ? null : _fermer,
                    child: const Text('Annuler'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  FilledButton(
                    key: const Key('bouton-enregistrer'),
                    onPressed: _envoiEnCours ? null : _enregistrer,
                    child: Text(
                      _envoiEnCours
                          ? 'Enregistrement…'
                          : 'Enregistrer la réservation',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.unit),
              // Écart assumé avec le maître, et il dit la vérité du poste :
              // la réservation est écrite ici, son envoi au serveur suit. Le
              // maître, lui, n'a pas de serveur.
              Text(
                'La réservation est enregistrée sur ce poste immédiatement, '
                'même sans réseau. Son envoi au serveur suit.',
                textAlign: TextAlign.right,
                style: textes.labelSmall?.copyWith(color: AppColors.neutre500),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _fermer() {
    final navigateur = Navigator.of(context);
    if (navigateur.canPop()) navigateur.pop();
  }

  Future<void> _enregistrer() async {
    final valide = _formulaire.currentState?.validate() ?? false;

    // Le maître rend la sélection de services obligatoire (l.144) et affiche
    // son refus SOUS le libellé, pas dans une bannière : c'est là que
    // l'utilisateur regarde quand il cherche ce qui manque.
    final lignes = _toutesLignes.where((l) => l.estRenseignee).toList();
    setState(() {
      _erreurServices = lignes.isEmpty
          ? 'Choisissez au moins un service et son élément.'
          : null;
    });
    if (!valide || lignes.isEmpty) return;

    final a = _arrivee;
    final d = _depart;
    if (a == null || d == null) {
      setState(() => _erreur = 'Renseignez les dates d’arrivée et de départ.');
      return;
    }

    final client = _client;
    if (client == null) {
      // Le maître marque le champ d'un astérisque rouge ; ici le refus tient
      // à davantage qu'à une obligation d'écran : sans client, la réservation
      // n'a aucune clé étrangère à écrire, et le serveur la rejetterait.
      setState(() => _erreur = 'Choisissez un client, ou ajoutez-en un.');
      return;
    }

    final chambres = lignes
        .where((l) => l.service == ServiceReservation.hebergement)
        .toList();
    if (chambres.length != 1) {
      // Voir l'en-tête de classe : le schéma serveur ne représente qu'une
      // unité par réservation. On refuse et on dit pourquoi.
      setState(
        () => _erreur = chambres.isEmpty
            ? 'Une réservation doit porter exactement une chambre : le serveur '
                  'l’enregistre sur une unité d’hébergement. Pour un circuit '
                  'ou une location seuls, passez par leur module.'
            : 'Une réservation ne peut porter qu’une seule chambre : le '
                  'serveur n’en enregistre qu’une, et les suivantes seraient '
                  'perdues sans que rien ne le signale. Créez une réservation '
                  'par chambre.',
      );
      return;
    }

    final unites = await ref.read(depotReservationProvider).unites();
    final visees = unites.where((u) => u.id == chambres.single.itemId);
    if (visees.isEmpty) {
      setState(() => _erreur = 'Chambre introuvable sur ce poste.');
      return;
    }

    setState(() {
      _envoiEnCours = true;
      _erreur = null;
    });

    final existante = _existante;

    try {
      // Deux gestes, deux cas d'usage — et surtout deux TYPES D'OPÉRATION au
      // serveur. Réutiliser la création pour une modification marcherait
      // localement et serait faux au serveur : il traiterait la mise à jour
      // comme une création, et c'est la déduplication par UUID qui
      // rattraperait l'erreur, silencieusement.
      final reservation = existante == null
          ? await ref.read(creerReservationProvider)(
              unite: visees.first,
              clientId: client.id,
              clientNom: client.nomComplet,
              periode: PeriodeSejour(arrivee: a, depart: d),
              acompte: _acompteSaisi,
              typeClient: _typeClient,
              canal: _canal,
              modePaiement: _modePaiement,
              remiseType: _typeRemise,
              remiseValeur: num.tryParse(_remiseValeur.text.trim()),
              lignes: lignes,
              // Celui qui encaisse l'acompte (RG-15) : la réservation passe la
              // pièce de son acompte dans la même transaction.
              auteurId: ref.read(sessionProvider)?.utilisateurId ?? '',
            )
          : await ref.read(modifierReservationProvider)(
              existante: existante,
              unite: visees.first,
              clientNom: client.nomComplet,
              periode: PeriodeSejour(arrivee: a, depart: d),
              acompte: _acompteSaisi,
              typeClient: _typeClient,
              canal: _canal,
              modePaiement: _modePaiement,
              remiseType: _typeRemise,
              remiseValeur: num.tryParse(_remiseValeur.text.trim()),
              lignes: lignes,
            );

      if (!mounted) return;
      rafraichirListes(ref);

      // La modale du maître, dans son ordre : la réservation est ENREGISTRÉE,
      // puis on propose le papier. La proposer avant l'écriture ferait croire
      // que l'impression conditionne l'enregistrement.
      final choix = await demanderImpressionReservation(context);
      if (choix == ChoixImpression.imprimer) {
        await ref.read(imprimerConfirmationReservationProvider)(
          ConfirmationReservation(
            reservation: reservation,
            emiseLe: DateTime.now(),
          ),
        );
      }

      if (!mounted) return;
      // `Navigator` plutôt que `context.pop()` de go_router, et seulement si
      // une page peut être dépilée. L'écran ne doit pas EXIGER un routeur pour
      // fonctionner : il devient sinon impossible à monter seul — en test, ou
      // embarqué dans une vue maître-détail sur grand écran.
      final navigateur = Navigator.of(context);
      if (navigateur.canPop()) navigateur.pop(reservation);
    } on ChevauchementDetecte catch (e) {
      // Refus LOCAL : certain, immédiat, et il nomme le conflit. Le refus
      // serveur, lui, arrivera plus tard sous forme de statut « rejetée ».
      final c = e.reservationEnConflit;
      setState(() {
        _erreur =
            'Unité déjà réservée par ${c.clientNom}, '
            'du ${formaterDate(c.periode.arrivee)} '
            'au ${formaterDate(c.periode.depart)}.';
      });
    } on UniteIndisponible catch (e) {
      setState(() => _erreur = e.message);
    } on ArgumentError catch (e) {
      setState(() => _erreur = '${e.message}');
    } on RefusComptable catch (e) {
      // La pièce de l'acompte est refusée (exercice, compte, journal, centre) :
      // RIEN n'a été écrit, pas même la réservation — et la fiche reste ouverte,
      // saisie intacte, avec la phrase du serveur.
      setState(() => _erreur = e.message);
    } finally {
      if (mounted) setState(() => _envoiEnCours = false);
    }
  }
}

/* ====================================================================== */
/* Fragments de mise en page                                               */
/* ====================================================================== */

/// Le champ « Client » — une **liste du référentiel**, plus le bouton du maître.
///
/// ## Pourquoi ce n'est pas un champ texte, contrairement au maître
///
/// Le maître pose un `<input>` libre. C'est un **anti-pattern de démonstration**
/// que le dépôt nomme explicitement : *« tout champ relationnel est une vraie
/// clé étrangère avec autocomplete, jamais du texte libre »*. Et le maître
/// lui-même le dit à sa façon — il place, à trois centimètres de ce champ, un
/// bouton « Ajouter client » qui crée une vraie fiche dans le module Clients.
///
/// Le défaut n'était pas théorique : jusqu'au 25/08/2026, ce que le
/// réceptionniste tapait ici n'était **écrit nulle part**. Le nom affiché sur
/// la carte venait de `cli-comptoir`, un client fictif partagé par toutes les
/// réservations du poste.
class _ChampClient extends ConsumerWidget {
  const _ChampClient({required this.valeur, required this.onChange});

  final Client? valeur;
  final void Function(Client?) onChange;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clients = ref.watch(clientsProvider);
    final textes = Theme.of(context).textTheme;
    // Créer un client, c'est écrire dans M3 — et la synchronisation vérifie
    // les droits PAR OPÉRATION (PA-65). Sans `C` sur M3, le client serait
    // refusé au serveur et la réservation partirait vers un client
    // inexistant : le bouton est retiré, pas grisé.
    final peutCreer = ref
        .watch(droitsProvider)
        .peutEcrire(ModuleTatacora.m3Crm);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'Client '),
              TextSpan(
                text: '*',
                style: textes.labelMedium?.copyWith(color: AppColors.erreur),
              ),
            ],
          ),
          style: textes.labelMedium,
        ),
        const SizedBox(height: AppSpacing.unit),
        Row(
          children: [
            Expanded(
              child: clients.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('$e'),
                data: (liste) => DropdownButtonFormField<Client>(
                  key: const Key('champ-client'),
                  initialValue: liste.contains(valeur) ? valeur : null,
                  isExpanded: true,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    isDense: true,
                    // Un référentiel vide le DIT, au lieu d'afficher une liste
                    // déroulante qui ne s'ouvre sur rien.
                    // Le maître pose ici un champ de TEXTE LIBRE, invite
                    // « Ex. Jean KORA ou Agence Bénin Tour »
                    // (`prototype_v2/pages/reservations.html` l.125). Refus
                    // assumé : le client d'une réservation est une vraie clé
                    // étrangère (PA-116), et une saisie libre créerait un
                    // homonyme à chaque faute de frappe. L'invite du maître
                    // n'a donc pas d'endroit où s'afficher : une liste
                    // déroulante ne se remplit pas au clavier.
                    hintText: liste.isEmpty
                        ? 'Aucun client sur ce poste'
                        : 'Choisir un client…',
                  ),
                  items: [
                    for (final c in liste)
                      DropdownMenuItem(
                        value: c,
                        child: Text(
                          '${c.nomComplet} — ${c.telephone}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: onChange,
                ),
              ),
            ),
            if (peutCreer) ...[
              const SizedBox(width: AppSpacing.xs),
              OutlinedButton.icon(
                key: const Key('bouton-nouveau-client'),
                onPressed: () => _ajouter(context, ref),
                icon: const Icon(Icons.person_add_alt, size: 16),
                label: const Text('Ajouter client'),
              ),
            ],
          ],
        ),
      ],
    );
  }

  /// Crée le client, **puis le retient** dans le formulaire.
  ///
  /// Le maître fait exactement cela : il recopie le nom dans le champ de la
  /// réservation en fermant la modale. Le créer sans le sélectionner
  /// obligerait à le rechercher dans une liste où il vient d'apparaître —
  /// c'est-à-dire à refaire le geste qu'on vient de faire.
  Future<void> _ajouter(BuildContext context, WidgetRef ref) async {
    final saisie = await demanderNouveauClient(context);
    if (saisie == null) return;

    final cree = await ref
        .read(clientDaoProvider)
        .creer(nom: saisie.nom, telephone: saisie.telephone, type: saisie.type);

    ref.invalidate(clientsProvider);
    onChange(cree);
  }
}

/// La grille `sm:grid-cols-2` du maître : deux colonnes côte à côte au-delà de
/// 640 px, empilées en dessous.
class _Deux extends StatelessWidget {
  const _Deux({required this.gauche, required this.droite});

  final Widget gauche;
  final Widget droite;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, contraintes) {
        if (contraintes.maxWidth < 640) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              gauche,
              const SizedBox(height: AppSpacing.md),
              droite,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: gauche),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: droite),
          ],
        );
      },
    );
  }
}

/// Le bloc gris à cinq lignes du maître (l.175-181).
///
/// Les deux déductions s'affichent **précédées d'un moins**, comme au maître :
/// sans le signe, « Remise 5 000 FCFA » se lit comme un montant dû et non comme
/// un montant retiré.
class _BlocRecapitulatif extends StatelessWidget {
  const _BlocRecapitulatif({required this.recap});

  final RecapitulatifReservation recap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.neutre100,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        children: [
          _LigneCalculee(
            etiquette: 'Sous-total',
            valeur: formaterFcfa(recap.sousTotal),
            cle: const Key('recap-sous-total'),
          ),
          _LigneCalculee(
            etiquette: 'Remise',
            valeur: '- ${formaterFcfa(recap.montantRemise)}',
            cle: const Key('recap-remise'),
          ),
          const Divider(),
          _LigneCalculee(
            etiquette: 'Total à payer',
            valeur: formaterFcfa(recap.total),
            cle: const Key('recap-total'),
            accentue: true,
          ),
          _LigneCalculee(
            etiquette: 'Acompte versé',
            valeur: '- ${formaterFcfa(recap.acompte)}',
            cle: const Key('recap-acompte'),
          ),
          const Divider(),
          _LigneCalculee(
            etiquette: 'Reste à payer',
            valeur: formaterFcfa(recap.reste),
            cle: const Key('recap-reste'),
            accentue: true,
          ),
        ],
      ),
    );
  }
}

/// Ligne d'un bloc calculé — affichage seul, jamais un champ.
class _LigneCalculee extends StatelessWidget {
  const _LigneCalculee({
    required this.etiquette,
    required this.valeur,
    required Key cle,
    this.accentue = false,
  }) : super(key: cle);

  final String etiquette;
  final String valeur;
  final bool accentue;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.unit),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(etiquette, style: Theme.of(context).textTheme.bodySmall),
          Text(
            valeur,
            style: accentue
                ? AppTextStyles.montant
                : Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

/// « Remise » — le type commande la saisie.
///
/// Le maître **désactive** le champ de valeur tant que le type vaut « Aucune »,
/// plutôt que de le masquer : un champ qui disparaît fait chercher où il est
/// passé, un champ grisé dit qu'il existe et pourquoi il dort.
class _Remise extends StatelessWidget {
  const _Remise({
    required this.type,
    required this.valeur,
    required this.onType,
    required this.onValeur,
  });

  final TypeRemise type;
  final TextEditingController valeur;
  final void Function(TypeRemise) onType;
  final VoidCallback onValeur;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Remise', style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: AppSpacing.unit),
        Row(
          children: [
            SizedBox(
              width: 104,
              child: DropdownButtonFormField<TypeRemise>(
                key: const Key('champ-remise-type'),
                initialValue: type,
                isExpanded: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (final t in TypeRemise.values)
                    DropdownMenuItem(value: t, child: Text(t.libelle)),
                ],
                onChanged: (t) {
                  if (t != null) onType(t);
                },
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: TextFormField(
                key: const Key('champ-remise-valeur'),
                controller: valeur,
                enabled: type != TypeRemise.aucune,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) => onValeur(),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Un champ de date, libellé au-dessus comme au maître.
class _ChampDate extends StatelessWidget {
  const _ChampDate({
    required Key cle,
    required this.etiquette,
    required this.valeur,
    required this.onAppui,
  }) : super(key: cle);

  final String etiquette;
  final DateTime? valeur;
  final VoidCallback onAppui;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(etiquette, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: AppSpacing.unit),
        OutlinedButton.icon(
          onPressed: onAppui,
          icon: const Icon(Icons.calendar_today, size: 14),
          label: Align(
            alignment: Alignment.centerLeft,
            child: Text(valeur == null ? 'Choisir…' : formaterDate(valeur!)),
          ),
        ),
      ],
    );
  }
}

/// Une liste déroulante étiquetée, à la forme du maître : le libellé AU-DESSUS
/// du champ, jamais dedans.
///
/// Le maître pose un `<label>` distinct (`block ... mb-1.5`) et non un
/// `floatingLabel` Material. La différence se voit : un libellé flottant
/// disparaît sous la valeur choisie, et l'écran perd le nom de ce qu'il
/// affiche dès qu'il est rempli.
class _Liste<T> extends StatelessWidget {
  const _Liste({
    required Key cle,
    required this.etiquette,
    required this.valeur,
    required this.options,
    required this.libelle,
    required this.onChange,
    this.invite,
  }) : super(key: cle);

  final String etiquette;

  /// `null` : aucune option choisie — seulement quand [invite] existe.
  final T? valeur;
  final List<T> options;
  final String Function(T) libelle;
  final void Function(T?) onChange;

  /// La PREMIÈRE option de la vue, à valeur vide (« Choisissez un canal »).
  /// Absente : la liste n'a pas d'option vide (« Type de client »).
  final String? invite;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(etiquette, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: AppSpacing.unit),
        DropdownButtonFormField<T?>(
          initialValue: valeur,
          // Le panneau peut être étroit : sans ces deux réglages, « Agence
          // partenaire » déborde au lieu d'être tronqué.
          isExpanded: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: [
            if (invite != null)
              DropdownMenuItem<T?>(
                child: Text(invite!, overflow: TextOverflow.ellipsis),
              ),
            for (final o in options)
              DropdownMenuItem<T?>(
                value: o,
                child: Text(libelle(o), overflow: TextOverflow.ellipsis),
              ),
          ],
          // L'option vide (`null`) remet la saisie à « non choisi » ; une liste
          // sans [invite] n'en propose pas, et ne reçoit donc jamais `null`.
          onChanged: onChange,
        ),
      ],
    );
  }
}
