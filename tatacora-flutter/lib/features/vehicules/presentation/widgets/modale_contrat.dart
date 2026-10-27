// Vue Blade maîtresse (PA-183) : pwa/vehicules/locations.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/format/formats.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../crm/domain/entities/client.dart';
import '../../../hebergement/presentation/providers_hebergement.dart';
import '../../../restaurant/presentation/widgets/coquille_modale_restaurant.dart';
import '../../../restaurant/presentation/widgets/textes_modale_restaurant.dart';
import '../../domain/entities/contrat_location.dart';
import '../../domain/entities/vehicule.dart';
import '../../domain/indicateurs_vehicules.dart';
import '../../domain/regles_vehicules.dart';
import '../providers_vehicules.dart';

/// La modale **« Nouveau contrat de location »** — `largeur="620px"`.
///
/// @see EF-M8-03 Contrat de location
/// @see RG-08 Chevauchement
/// @see RG-09 Pièce d'identité et permis
///
/// ## Ce formulaire ÉCRIT désormais, et c'est le lot du 14/09/2026
///
/// Il appelait `VehiculesApi.creerContrat()`, dont le corps ne faisait plus que
/// rendre « refusé » depuis le passage zéro réseau : la saisie était complète,
/// le bouton répondait, et **rien n'était enregistré**. Il appelle maintenant
/// `VehiculeDao.creerContrat()`, qui tient RG-08 et RG-09 dans la transaction
/// qui insère.
///
/// ## « Remise (FCFA) » et « Acompte reçu (FCFA) » sont saisis (v41, 27/10/2026)
///
/// Ils étaient rendus inertes tant que `contrats_location_local` n'avait pas leurs
/// colonnes. Le contrat porte désormais sa remise, son acompte et son montant NET
/// FIGÉ à la signature : la modale les demande comme la vue, l'aperçu montre le
/// reste à payer, et le DAO refuse (avec les phrases du serveur) une remise
/// supérieure au montant brut puis un acompte supérieur au net. « Téléphone » reste
/// ce que la vue en fait : la lecture du client choisi.
///
/// ## Sur un référentiel vide, la modale REFUSE de s'ouvrir
///
/// Sans véhicule ou sans client, aucun contrat ne peut aboutir : la modale le
/// dit et n'offre pas de bouton d'enregistrement. C'est PA-128 appliqué à M8 —
/// et les deux référentiels se saisissent maintenant sur le poste, ce que le
/// message indique.
Future<bool?> ouvrirModaleContrat(BuildContext context, {Vehicule? vehicule}) =>
    showDialog<bool>(
      context: context,
      // Fermeture au voile — Article 4.6. L'échappement est branché par la
      // coquille.
      barrierDismissible: true,
      barrierColor: AppColors.voileModale,
      builder: (_) => _ModaleContrat(vehiculePrechoisi: vehicule),
    );

class _ModaleContrat extends ConsumerStatefulWidget {
  const _ModaleContrat({this.vehiculePrechoisi});

  final Vehicule? vehiculePrechoisi;

  @override
  ConsumerState<_ModaleContrat> createState() => _ModaleContratState();
}

class _ModaleContratState extends ConsumerState<_ModaleContrat> {
  final _piece = TextEditingController();
  final _permis = TextEditingController();
  final _remise = TextEditingController();
  final _acompte = TextEditingController();

  late String? _vehiculeId = widget.vehiculePrechoisi?.id;
  String? _clientId;
  late String? _debut = ref.read(periodeVehiculesProvider).debut;
  late String? _fin = ref.read(periodeVehiculesProvider).fin;

  bool _envoi = false;
  String? _refus;
  Map<String, String> _parChamp = const {};

  @override
  void dispose() {
    _piece.dispose();
    _permis.dispose();
    _remise.dispose();
    _acompte.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final parc = ref.watch(parcProvider);
    final vehicules = switch (parc) {
      AsyncData(value: final v) => v,
      _ => const <Vehicule>[],
    };

    final clients = ref.watch(clientsProvider);
    final liste = switch (clients) {
      AsyncData(value: final v) => v,
      _ => null,
    };

    final choisi = vehicules.where((v) => v.id == _vehiculeId).firstOrNull;
    final referentielsPrets =
        vehicules.isNotEmpty && (liste?.isNotEmpty ?? false);

    return CoquilleModaleRestaurant(
      cle: const Key('modale-contrat'),
      // Le titre de la vue, au mot.
      titre: 'Nouveau contrat de location',
      // Le sous-titre de `vehicules.pwa.modale_contrat_sous_titre`, AU MOT.
      //
      // ⚠ Il portait ici une reformulation — « le véhicule est vérifié sur la
      // période » — au motif que la référence RG-08 vit au fichier de langue et
      // non à l'écran (Article 8). C'était une erreur de raisonnement : cette
      // clé EST le fichier de langue, et c'est elle qui écrit « RG-08 : ». Le
      // comparateur Blade l'a relevé. Un libellé repris d'une clé se recopie au
      // caractère près, y compris ce qu'on aurait formulé autrement.
      sousTitre:
          'Le véhicule est verrouillé sur la période avant l\'écriture du contrat.',
      largeur: AppLayout.modaleContrat,
      refus: _refus,
      cleRefus: const Key('modale-contrat-refus'),
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ---------------------------------------------- 1. Véhicule (l.615)
          const EtiquetteChampRestaurant(texte: 'Véhicule', obligatoire: true),
          DropdownButtonFormField<String>(
            key: const Key('modale-contrat-vehicule'),
            initialValue: vehicules.any((v) => v.id == _vehiculeId)
                ? _vehiculeId
                : null,
            isExpanded: true,
            style: TextesModaleRestaurant.corps,
            decoration: InputDecoration(
              isDense: true,
              border: const OutlineInputBorder(),
              errorText: _parChamp['vehicule_id'],
            ),
            items: [
              for (final v in vehicules)
                DropdownMenuItem(
                  value: v.id,
                  // Le gabarit de la vue (l.618) : « <plaque> — <tarif>/jour ».
                  child: Text(
                    '${v.immatriculation} — ${v.tarifJour}/jour',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (v) => setState(() => _vehiculeId = v),
          ),
          if (choisi != null) _InfoVehicule(vehicule: choisi),
          const SizedBox(height: AppSpacing.md),

          // ------------------------------- 2 et 3. Départ / Restitution (l.634)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _ChampDateModale(
                  cle: const Key('modale-contrat-debut'),
                  etiquette: 'Départ',
                  valeur: _debut,
                  erreur: _parChamp['date_debut'],
                  onChoix: (v) => setState(() => _debut = v),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _ChampDateModale(
                  cle: const Key('modale-contrat-fin'),
                  etiquette: 'Restitution',
                  valeur: _fin,
                  erreur: _parChamp['date_fin'],
                  onChoix: (v) => setState(() => _fin = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // ------------------------------ 4 et 5. Client / Téléphone (l.647)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const EtiquetteChampRestaurant(
                      texte: 'Client',
                      obligatoire: true,
                    ),
                    _SelecteurClient(
                      clients: liste,
                      chargement: clients.isLoading,
                      valeur: _clientId,
                      erreur: _parChamp['client_id'],
                      onChoix: (id) => setState(() => _clientId = id),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                // La vue affiche ici le téléphone du client CHOISI, en lecture
                // seule (l.665) : « le saisir ici en dupliquerait la source ».
                child: _Telephone(
                  client: liste?.where((c) => c.id == _clientId).firstOrNull,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // --------------------- 6 et 7. Pièce d'identité / Permis (l.669)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const EtiquetteChampRestaurant(
                      texte: 'Pièce d’identité',
                      obligatoire: true,
                    ),
                    TextField(
                      key: const Key('modale-contrat-piece'),
                      controller: _piece,
                      style: TextesModaleRestaurant.corps,
                      decoration: InputDecoration(
                        // L'invite de la vue (l.672), au mot.
                        hintText: 'N° CNI ou passeport',
                        isDense: true,
                        border: const OutlineInputBorder(),
                        errorText: _parChamp['piece_identite'],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                // La vue masque ce bloc quand le véhicule n'exige pas de permis
                // (l.676). Même comportement, sur la MÊME règle : `exigePermis`
                // est dérivé de l'unique auteur, jamais recalculé ici.
                child: (choisi?.exigePermis ?? true)
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const EtiquetteChampRestaurant(
                            texte: 'Permis de conduire',
                            obligatoire: true,
                          ),
                          TextField(
                            key: const Key('modale-contrat-permis'),
                            controller: _permis,
                            style: TextesModaleRestaurant.corps,
                            decoration: InputDecoration(
                              // L'invite de la vue (l.679).
                              hintText: 'N° de permis',
                              isDense: true,
                              border: const OutlineInputBorder(),
                              errorText: _parChamp['permis_conduire'],
                            ),
                          ),
                        ],
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          const Text(
            // Sans nom de table (directive du PO, 14/10/2026) : la table
            // des contrats ne porte que des chemins de fichier.
            'Les deux numéros sont exigés pour établir le contrat ; ce poste '
            'ne les conserve pas.',
            key: Key('modale-contrat-aide-pieces'),
            style: TextesModaleRestaurant.aide,
          ),
          const SizedBox(height: AppSpacing.md),

          // ------------------------- 8 et 9. Remise / Acompte reçu (l.686)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _ChampMontant(
                  cle: const Key('modale-contrat-remise'),
                  etiquette: MessagesVehicules.libelleRemise,
                  controleur: _remise,
                  erreur: _parChamp['remise'],
                  onChanged: () => setState(() {}),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _ChampMontant(
                  cle: const Key('modale-contrat-acompte'),
                  etiquette: MessagesVehicules.libelleAcompte,
                  controleur: _acompte,
                  erreur: _parChamp['acompte'],
                  onChanged: () => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // ------------------------------------------ L'aperçu (l.699-714)
          _Apercu(
            vehicule: choisi,
            debut: _debut,
            fin: _fin,
            remise: _montantSaisi(_remise.text) ?? 0,
            acompte: _montantSaisi(_acompte.text) ?? 0,
          ),

          if (!referentielsPrets && !clients.isLoading && !parc.isLoading) ...[
            const SizedBox(height: AppSpacing.md),
            _ReferentielAbsent(
              parcVide: vehicules.isEmpty,
              clientsVides: liste != null && liste.isEmpty,
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          key: const Key('modale-contrat-annuler'),
          onPressed: _envoi ? null : () => Navigator.of(context).pop(false),
          child: const Text('Annuler', style: TextesModaleRestaurant.bouton),
        ),
        // Le bouton n'existe PAS tant qu'un référentiel manque : grisé, il
        // inviterait à cliquer pour ne produire qu'un refus.
        if (referentielsPrets)
          FilledButton(
            key: const Key('modale-contrat-etablir'),
            onPressed: _envoi ? null : _etablir,
            // Le libellé de la vue (l.720), au mot.
            child: const Text(
              'Établir le contrat',
              style: TextesModaleRestaurant.bouton,
            ),
          ),
      ],
    );
  }

  Future<void> _etablir() async {
    final vehiculeId = _vehiculeId;
    final clientId = _clientId;
    final debut = _debut == null ? null : DateTime.tryParse(_debut!);
    final fin = _fin == null ? null : DateTime.tryParse(_fin!);

    final vehicules = switch (ref.read(parcProvider)) {
      AsyncData(value: final v) => v,
      _ => const <Vehicule>[],
    };
    final choisi = vehicules.where((v) => v.id == vehiculeId).firstOrNull;

    // Ces contrôles ne REMPLACENT pas ceux du DAO : ils évitent d'écrire une
    // transaction pour rien et posent l'erreur sous le bon champ. Le refus qui
    // fait autorité est celui du DAO, dans la transaction qui insère.
    final manquants = <String, String>{
      if (vehiculeId == null) 'vehicule_id': 'Le véhicule est obligatoire.',
      if (clientId == null) 'client_id': 'Le client est obligatoire.',
      if (debut == null) 'date_debut': 'La date de départ est obligatoire.',
      if (fin == null) 'date_fin': 'La date de restitution est obligatoire.',
      if (debut != null &&
          fin != null &&
          nombreDeJoursEntre(debut, fin) == null)
        'date_fin': MessagesVehicules.finApresDebut,
      if (_piece.text.trim().isEmpty)
        'piece_identite': MessagesVehicules.pieceIdentiteRequise,
      // La remise et l'acompte : des francs entiers, zéro ou plus. Les bornes
      // (remise <= brut, acompte <= net) sont celles du DAO, qui rend la phrase.
      'remise': ?_refusMontant(_remise.text, MessagesVehicules.libelleRemise),
      'acompte': ?_refusMontant(
        _acompte.text,
        MessagesVehicules.libelleAcompte,
      ),
      // RG-09 n'est PAS recopiée ici : la condition est lue sur `exigePermis`,
      // que le DAO dérive de l'unique auteur.
      if ((choisi?.exigePermis ?? false) && _permis.text.trim().isEmpty)
        'permis_conduire': MessagesVehicules.permisRequis(
          choisi?.categorieLibelle ?? '',
        ),
    };

    if (manquants.isNotEmpty) {
      setState(() => _parChamp = manquants);
      return;
    }

    setState(() {
      _envoi = true;
      _refus = null;
      _parChamp = const {};
    });

    try {
      await ref
          .read(vehiculeDaoProvider)
          .creerContrat(
            SaisieContrat(
              vehiculeId: vehiculeId!,
              clientId: clientId!,
              debut: debut!,
              fin: fin!,
              pieceIdentite: _piece.text.trim(),
              permisConduire: _permis.text.trim().isEmpty
                  ? null
                  : _permis.text.trim(),
              remiseFrancs: _montantSaisi(_remise.text) ?? 0,
              acompteFrancs: _montantSaisi(_acompte.text) ?? 0,
            ),
          );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on RefusVehicule catch (refus) {
      if (!mounted) return;
      // Les deux refus de montant se posent sous leur champ, comme la vue
      // (`addError('remiseSaisie')` / `addError('acompteSaisi')`).
      final champ = refus.message.startsWith(
            'Le champ ${MessagesVehicules.libelleRemise} ',
          )
          ? 'remise'
          : refus.message.startsWith(
              'Le champ ${MessagesVehicules.libelleAcompte} ',
            )
          ? 'acompte'
          : null;
      setState(() {
        _envoi = false;
        if (champ == null) {
          _refus = refus.message;
        } else {
          _parChamp = {champ: refus.message};
        }
      });
    }
  }

  /// Un montant saisi en francs entiers ; vide = zéro (la vue pose 0 par défaut) ;
  /// `null` si illisible.
  static int? _montantSaisi(String saisie) {
    final texte = saisie.trim().replaceAll(' ', '');
    return texte.isEmpty ? 0 : int.tryParse(texte);
  }

  static String? _refusMontant(String saisie, String libelle) {
    final valeur = _montantSaisi(saisie);
    if (valeur == null) return MessagesVehicules.champEntier(libelle);
    if (valeur < 0) return MessagesVehicules.champMinimum(libelle, 0);
    return null;
  }
}

/// La ligne d'information sous le sélecteur — vue l.622-629.
class _InfoVehicule extends StatelessWidget {
  const _InfoVehicule({required this.vehicule});

  final Vehicule vehicule;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.unit),
      child: Text.rich(
        TextSpan(
          children: [
            // Le gabarit de `vehicules.pwa.info_vehicule`, AU MOT :
            // « :places place(s) · :categorie · chauffeur inclus », suivi du
            // permis. Les places valent « — » pour un véhicule d'avant la v41.
            //
            // ⚠ « · chauffeur inclus » avait disparu de cette ligne. Ce n'est
            // pas une mention décorative : le tarif du catalogue INCLUT le
            // chauffeur, et l'omettre laisse croire qu'il se facture en plus.
            TextSpan(
              text:
                  '${vehicule.capacite?.toString() ?? '—'} place(s) · '
                  '${vehicule.categorieLibelle ?? '—'} · chauffeur inclus · ',
            ),
            TextSpan(
              text: vehicule.exigePermis
                  ? 'permis exigé'
                  : 'dispensé de permis',
              style: TextStyle(
                color: vehicule.exigePermis
                    ? PaletteMaitre.ambre700
                    : PaletteMaitre.emeraude700,
              ),
            ),
          ],
        ),
        key: const Key('modale-contrat-info-vehicule'),
        style: TextesModaleRestaurant.aide,
      ),
    );
  }
}

/// L'aperçu de la vue (l.699-714) : « N jour(s) × tarif », « Remise », « Acompte »
/// et « Reste à payer » (brut − remise − acompte). Depuis la v41 les trois dernières
/// lignes existent : le reste à payer annoncé est celui que le contrat portera.
class _Apercu extends StatelessWidget {
  const _Apercu({
    required this.vehicule,
    required this.debut,
    required this.fin,
    required this.remise,
    required this.acompte,
  });

  final Vehicule? vehicule;
  final String? debut;
  final String? fin;
  final int remise;
  final int acompte;

  @override
  Widget build(BuildContext context) {
    final v = vehicule;
    final jours = nombreDeJours(debut, fin);
    if (v == null || jours == null) return const SizedBox.shrink();

    final montant = sommeDecimales(List<String>.filled(jours, v.tarifJour));
    final brut = montant == null ? null : double.tryParse(montant)?.round();
    final reste = brut == null ? null : brut - remise - acompte;
    String fcfa(int? francs) => francs == null
        ? '—'
        : formaterMontantDecimal('$francs.00', suffixe: 'FCFA') ?? '—';

    Widget ligne(Key cle, String libelle, String valeur, {bool fort = false}) =>
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              libelle,
              style: fort
                  ? TextesModaleRestaurant.corps.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.navy,
                    )
                  : TextesModaleRestaurant.aide,
            ),
            Text(
              valeur,
              key: cle,
              style: TextesModaleRestaurant.corps.copyWith(
                fontWeight: fort ? FontWeight.w700 : FontWeight.w400,
                color: fort ? AppColors.navy : PaletteMaitre.emeraude700,
              ),
            ),
          ],
        );

    return Container(
      // `border border-slate-200 rounded-lg p-3 text-[12px]`.
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        border: Border.all(color: Ardoise.c200),
        borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$jours jour(s) × ${v.tarifJour}',
                style: TextesModaleRestaurant.aide,
              ),
              Text(
                montant ?? '—',
                key: const Key('modale-contrat-apercu-montant'),
                style: TextesModaleRestaurant.corps.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.navy,
                ),
              ),
            ],
          ),
          ligne(
            const Key('modale-contrat-apercu-remise'),
            'Remise',
            '− ${fcfa(remise)}',
          ),
          ligne(
            const Key('modale-contrat-apercu-acompte'),
            'Acompte',
            '− ${fcfa(acompte)}',
          ),
          const Divider(height: AppSpacing.sm),
          ligne(
            const Key('modale-contrat-apercu-reste'),
            'Reste à payer',
            fcfa(reste),
            fort: true,
          ),
        ],
      ),
    );
  }
}

/// Le sélecteur de client — une vraie clé étrangère, jamais du texte libre.
class _SelecteurClient extends StatelessWidget {
  const _SelecteurClient({
    required this.clients,
    required this.chargement,
    required this.valeur,
    required this.erreur,
    required this.onChoix,
  });

  final List<Client>? clients;
  final bool chargement;
  final String? valeur;
  final String? erreur;
  final ValueChanged<String?> onChoix;

  @override
  Widget build(BuildContext context) {
    if (chargement) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: LinearProgressIndicator(
          key: Key('modale-contrat-clients-charge'),
        ),
      );
    }

    final liste = clients ?? const <Client>[];

    return DropdownButtonFormField<String>(
      key: const Key('modale-contrat-client'),
      initialValue: liste.any((c) => c.id == valeur) ? valeur : null,
      isExpanded: true,
      style: TextesModaleRestaurant.corps,
      decoration: InputDecoration(
        isDense: true,
        border: const OutlineInputBorder(),
        errorText: erreur,
      ),
      items: [
        for (final c in liste)
          DropdownMenuItem(
            value: c.id,
            child: Text(c.nomComplet, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onChoix,
    );
  }
}

/// Le téléphone du client choisi — **lu**, jamais saisi (vue l.663-666).
class _Telephone extends StatelessWidget {
  const _Telephone({required this.client});

  final Client? client;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const EtiquetteChampRestaurant(texte: 'Téléphone'),
        Container(
          key: const Key('modale-contrat-telephone'),
          padding: const EdgeInsets.all(AppSpacing.xs),
          decoration: BoxDecoration(
            color: Ardoise.c50,
            border: Border.all(color: Ardoise.c200),
            borderRadius: BorderRadius.circular(AppRadius.roundedLg),
          ),
          child: Text(
            // Le téléphone est un attribut du client, pas du contrat : le
            // saisir ici en créerait une seconde vérité.
            client?.telephone ?? '—',
            style: TextesModaleRestaurant.corps,
          ),
        ),
      ],
    );
  }
}

/// Un champ de montant en francs entiers — étiquette de la vue, jamais obligatoire.
class _ChampMontant extends StatelessWidget {
  const _ChampMontant({
    required this.cle,
    required this.etiquette,
    required this.controleur,
    required this.onChanged,
    this.erreur,
  });

  final Key cle;
  final String etiquette;
  final TextEditingController controleur;
  final VoidCallback onChanged;
  final String? erreur;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        EtiquetteChampRestaurant(texte: etiquette),
        TextField(
          key: cle,
          controller: controleur,
          keyboardType: TextInputType.number,
          style: TextesModaleRestaurant.corps,
          onChanged: (_) => onChanged(),
          decoration: InputDecoration(
            isDense: true,
            border: const OutlineInputBorder(),
            errorText: erreur,
            errorMaxLines: 3,
          ),
        ),
      ],
    );
  }
}

/// Un champ de date de modale.
class _ChampDateModale extends StatelessWidget {
  const _ChampDateModale({
    required Key cle,
    required this.etiquette,
    required this.valeur,
    required this.erreur,
    required this.onChoix,
  }) : super(key: cle);

  final String etiquette;
  final String? valeur;
  final String? erreur;
  final ValueChanged<String?> onChoix;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        EtiquetteChampRestaurant(texte: etiquette, obligatoire: true),
        OutlinedButton(
          onPressed: () async {
            final courant = valeur == null ? null : DateTime.tryParse(valeur!);
            final choisi = await showDatePicker(
              context: context,
              initialDate: courant ?? DateTime.now(),
              firstDate: DateTime(DateTime.now().year - 1),
              lastDate: DateTime(DateTime.now().year + 5),
            );
            if (choisi == null) return;
            onChoix(
              '${choisi.year.toString().padLeft(4, '0')}-'
              '${choisi.month.toString().padLeft(2, '0')}-'
              '${choisi.day.toString().padLeft(2, '0')}',
            );
          },
          child: Text(
            valeur ?? 'jj/mm/aaaa',
            style: TextesModaleRestaurant.corps,
          ),
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

/// Ce que la modale dit quand un référentiel manque.
class _ReferentielAbsent extends StatelessWidget {
  const _ReferentielAbsent({
    required this.parcVide,
    required this.clientsVides,
  });

  final bool parcVide;
  final bool clientsVides;

  @override
  Widget build(BuildContext context) {
    final manques = <String>[
      if (parcVide)
        'Aucun véhicule n’est enregistré au parc. Le véhicule est '
            'obligatoire : commencez par « + Véhicule », sur cet écran.',
      // Le message de `vehicules.pwa.client_aucun`, AU MOT — apostrophe droite
      // comprise, comme le fichier de langue l'écrit.
      if (clientsVides)
        'Aucun client au référentiel — créez-le d\'abord depuis '
            '« Clients & Créances ».',
    ];

    return Container(
      key: const Key('modale-contrat-referentiel-absent'),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: PaletteMaitre.ambre50,
        border: Border.all(color: PaletteMaitre.ambre200),
        borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final m in manques)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.unit),
              child: Text(
                m,
                style: TextesModaleRestaurant.corps.copyWith(
                  color: PaletteMaitre.ambre900,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
