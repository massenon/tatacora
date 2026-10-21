// Vue Blade maîtresse (PA-183) : pwa/hebergement/hebergement.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart' show sessionProvider;
import '../../../../core/format/formats.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../caisse/presentation/widgets/modale_ouverture_caisse.dart'
    show BoutonActionCaisse, BoutonAnnulerCaisse;
import '../../../crm/domain/entities/client.dart';
import '../../../restaurant/presentation/widgets/coquille_modale_restaurant.dart';
import '../../domain/entities/periode_sejour.dart';
import '../../domain/entities/unite_hebergement.dart';
import '../../domain/repositories/reservation_repository.dart';
import '../providers_hebergement.dart';

/// Les mots de la modale « Réservation rapide » — `lang/fr/hebergement_pwa.php`
/// (`hebergement.*`).
abstract final class TextesReservationRapide {
  static const String titre = 'Réservation rapide';
  static const String client = 'Client';
  static const String clientInvite = 'Choisir un client…';
  static const String arrivee = 'Arrivée';
  static const String depart = 'Départ';
  static const String nombreNuits = 'Nombre de nuits';
  static const String montant = 'Montant hébergement';
  static const String pied =
      "La réservation est créée avec l'hébergement seul. Restauration, bar, tourisme et véhicule s'ajoutent dans Réservations.";
  static const String bouton = 'Enregistrer et compléter plus tard';
  static const String departApresArrivee =
      "La date de départ doit être postérieure à la date d'arrivée.";

  /// `:nombre nuit(s)`.
  static String nuits(int n) => '$n nuit(s)';

  /// `reservation_creee`.
  static String creee(String client, int nuits, String numero) =>
      "Réservation enregistrée pour $client — $nuits nuit(s) sur l'unité $numero.";
}

/// Ouvre la modale **« Réservation rapide »** (`ouvrirReservationRapide`,
/// `hebergement.blade.php` l.560-628) sur [unite], depuis « Réserver cette
/// unité » du plan et « Réserver » des disponibilités.
///
/// [arrivee] et [depart] sont la PÉRIODE CHERCHÉE de l'onglet Disponibilités :
/// elle devient la période réservée. Sans eux, la vue propose cette nuit
/// (aujourd'hui → demain).
Future<void> ouvrirReservationRapideParc(
  BuildContext context, {
  required UniteHebergement unite,
  DateTime? arrivee,
  DateTime? depart,
}) => showDialog<void>(
  context: context,
  builder: (_) =>
      ModaleReservationRapide(unite: unite, arrivee: arrivee, depart: depart),
);

/// La modale, dans l'ordre de la vue : le client (obligatoire, une vraie clé
/// étrangère choisie au référentiel — jamais un nom tapé), les deux dates, puis le
/// bloc CALCULÉ (nombre de nuits, montant hébergement), le pied qui dit ce que la
/// réservation contient, « Annuler » et « Enregistrer et compléter plus tard ».
///
/// ## Nuits et montant sont calculés, jamais saisis
///
/// « un total modifiable finit par contredire les dates » (vue, l.99-110).
/// Montant = tarif de base de l'unité × nuits ; « — » tant que la période n'est
/// pas valide, jamais un zéro qui se lirait comme une nuit gratuite.
///
/// ## RG-01 se dit SUR L'UNITÉ, la modale reste ouverte
///
/// Un chevauchement est un refus du service posé sur `rrUniteId` : fermer sur un
/// refus ferait retaper les dates. Le contrôle est celui de [CreerReservation],
/// le même que la fiche complète — une seconde saisie, plus courte, qui écrit les
/// mêmes lignes par le même chemin.
///
/// ## Hébergement seul, et le reste « se complète plus tard »
///
/// La réservation naît sans canal, sans acompte ni service annexe (le pied de la
/// vue le dit) ; « Réservations » les ajoute. Le canal n'a pas de champ ici, comme
/// à la vue.
class ModaleReservationRapide extends ConsumerStatefulWidget {
  const ModaleReservationRapide({
    required this.unite,
    this.arrivee,
    this.depart,
    super.key,
  });

  final UniteHebergement unite;
  final DateTime? arrivee;
  final DateTime? depart;

  @override
  ConsumerState<ModaleReservationRapide> createState() => _EtatModale();
}

class _EtatModale extends ConsumerState<ModaleReservationRapide> {
  Client? _client;
  late DateTime _arrivee;
  late DateTime _depart;
  String? _refusClient;
  String? _refusDepart;
  String? _refusUnite;
  bool _envoi = false;

  @override
  void initState() {
    super.initState();
    final aujourdhui = DateTime.now();
    final jour = DateTime(aujourdhui.year, aujourdhui.month, aujourdhui.day);
    final a = widget.arrivee;
    final d = widget.depart;
    // `ouvrirReservationRapide` : cette nuit, sauf période cherchée valide
    // (`$depart > $arrivee`).
    if (a != null && d != null && d.isAfter(a)) {
      _arrivee = DateTime(a.year, a.month, a.day);
      _depart = DateTime(d.year, d.month, d.day);
    } else {
      _arrivee = jour;
      _depart = DateTime(jour.year, jour.month, jour.day + 1);
    }
  }

  /// `null` tant que la période n'est pas valide : le bloc rend « — ».
  ///
  /// Le garde `isAfter` précède [PeriodeSejour] : son constructeur REFUSE un
  /// séjour de zéro nuit, et un départ ramené au jour de l'arrivée par le
  /// sélecteur est une saisie qu'on dit, pas une exception qu'on laisse
  /// remonter au rendu.
  int? get _nuits {
    if (!_depart.isAfter(_arrivee)) return null;
    final n = PeriodeSejour(arrivee: _arrivee, depart: _depart).nuits;
    return n > 0 ? n : null;
  }

  Future<void> _choisirDate({required bool arrivee}) async {
    final initiale = arrivee ? _arrivee : _depart;
    final choisie = await showDatePicker(
      context: context,
      initialDate: initiale,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (choisie == null) return;
    setState(() {
      if (arrivee) {
        _arrivee = choisie;
        // Une arrivée poussée au-delà du départ pousse le départ (`.live`).
        if (!_depart.isAfter(choisie)) {
          _depart = choisie.add(const Duration(days: 1));
        }
      } else {
        _depart = choisie;
      }
      _refusDepart = null;
      _refusUnite = null;
    });
  }

  Future<void> _enregistrer() async {
    final client = _client;
    final refusClient = client == null ? 'Choisissez un client.' : null;
    final refusDepart = _nuits == null
        ? TextesReservationRapide.departApresArrivee
        : null;
    if (refusClient != null || refusDepart != null) {
      setState(() {
        _refusClient = refusClient;
        _refusDepart = refusDepart;
        _refusUnite = null;
      });
      return;
    }

    setState(() {
      _envoi = true;
      _refusClient = null;
      _refusDepart = null;
      _refusUnite = null;
    });
    final navigateur = Navigator.of(context);
    final messages = ScaffoldMessenger.of(context);
    try {
      final reservation = await ref.read(creerReservationProvider)(
        unite: widget.unite,
        clientId: client!.id,
        clientNom: client.nomComplet,
        periode: PeriodeSejour(arrivee: _arrivee, depart: _depart),
        auteurId: ref.read(sessionProvider)?.utilisateurId ?? '',
      );
      if (!mounted) return;
      rafraichirListes(ref);
      navigateur.pop();
      messages.showSnackBar(
        SnackBar(
          content: Text(
            TextesReservationRapide.creee(
              client.nomComplet,
              reservation.nuits,
              widget.unite.numero,
            ),
            key: const Key('rapide-succes'),
          ),
        ),
      );
    } on ChevauchementDetecte catch (e) {
      final c = e.reservationEnConflit;
      _refuserUnite(
        'Unité déjà réservée par ${c.clientNom}, '
        'du ${formaterDate(c.periode.arrivee)} '
        'au ${formaterDate(c.periode.depart)}.',
      );
    } on UniteIndisponible catch (e) {
      _refuserUnite(e.message);
    } on ArgumentError catch (e) {
      _refuserUnite('${e.message}');
    }
  }

  void _refuserUnite(String message) {
    if (!mounted) return;
    setState(() {
      _refusUnite = message;
      _envoi = false;
    });
  }

  static const TextStyle _etiquette = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: Tailles.t15,
    fontWeight: FontWeight.w600,
    color: Ardoise.c700,
  );

  Widget _libelle(String texte) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
    child: Text.rich(
      TextSpan(
        style: _etiquette,
        children: [
          TextSpan(text: texte),
          const TextSpan(
            text: ' *',
            style: TextStyle(color: PaletteMaitre.rouge500),
          ),
        ],
      ),
    ),
  );

  Widget _erreur(String? message, Key cle) => message == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: AppSpacing.unit),
          child: Text(
            message,
            key: cle,
            style: const TextStyle(
              fontFamily: AppTextStyles.police,
              fontSize: Tailles.t12,
              color: PaletteMaitre.rouge600,
            ),
          ),
        );

  Widget _champDate(String libelle, DateTime valeur, Key cle, bool arrivee) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _libelle(libelle),
          OutlinedButton.icon(
            key: cle,
            onPressed: _envoi ? null : () => _choisirDate(arrivee: arrivee),
            icon: const Icon(Icons.calendar_today, size: AppLayout.iconeChamp),
            label: Align(
              alignment: Alignment.centerLeft,
              child: Text(formaterDate(valeur)),
            ),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final clients = ref.watch(clientsProvider);
    final nuits = _nuits;
    final numero = widget.unite.numero;
    final categorie = widget.unite.categorieLibelle;
    final sousTitre = categorie.isEmpty ? numero : '$numero · $categorie';

    return CoquilleModaleRestaurant(
      cle: const Key('modale-reservation-rapide'),
      titre: TextesReservationRapide.titre,
      sousTitre: sousTitre,
      largeur: AppLayout.modaleReservationRapideParc,
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _libelle(TextesReservationRapide.client),
          clients.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('$e'),
            data: (liste) => DropdownButtonFormField<Client>(
              key: const Key('rapide-client'),
              initialValue: liste.contains(_client) ? _client : null,
              isExpanded: true,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                isDense: true,
                // Un référentiel vide le DIT : une liste qui ne s'ouvre sur rien
                // laisserait croire à une panne.
                hintText: liste.isEmpty
                    ? 'Aucun client sur ce poste'
                    : TextesReservationRapide.clientInvite,
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
              onChanged: _envoi
                  ? null
                  : (c) => setState(() {
                      _client = c;
                      _refusClient = null;
                    }),
            ),
          ),
          _erreur(_refusClient, const Key('rapide-erreur-client')),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _champDate(
                  TextesReservationRapide.arrivee,
                  _arrivee,
                  const Key('rapide-arrivee'),
                  true,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _champDate(
                      TextesReservationRapide.depart,
                      _depart,
                      const Key('rapide-depart'),
                      false,
                    ),
                    _erreur(_refusDepart, const Key('rapide-erreur-depart')),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          // `grid grid-cols-2 gap-3 rounded-lg p-3.5` sur `#F8FAFC` : nuits et
          // montant, CALCULÉS.
          Container(
            padding: const EdgeInsets.all(AppSpacing.smPlus),
            decoration: BoxDecoration(
              color: Ardoise.c50,
              borderRadius: BorderRadius.circular(AppRadius.roundedLg),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        TextesReservationRapide.nombreNuits,
                        style: TextStyle(
                          fontFamily: AppTextStyles.police,
                          fontSize: Tailles.t12,
                          color: Ardoise.c500,
                        ),
                      ),
                      Text(
                        nuits == null
                            ? '—'
                            : TextesReservationRapide.nuits(nuits),
                        key: const Key('rapide-nuits'),
                        style: const TextStyle(
                          fontFamily: AppTextStyles.police,
                          fontSize: Tailles.t16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.navy,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        TextesReservationRapide.montant,
                        style: TextStyle(
                          fontFamily: AppTextStyles.police,
                          fontSize: Tailles.t12,
                          color: Ardoise.c500,
                        ),
                      ),
                      Text(
                        nuits == null
                            ? '—'
                            : formaterFcfa(widget.unite.tarifBase * nuits),
                        key: const Key('rapide-montant'),
                        style: const TextStyle(
                          fontFamily: AppTextStyles.police,
                          fontSize: Tailles.t16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.gold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_refusUnite != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xsPlus,
              ),
              decoration: BoxDecoration(
                color: AppColors.erreurFond,
                borderRadius: BorderRadius.circular(AppRadius.roundedLg),
              ),
              child: Text(
                _refusUnite!,
                key: const Key('rapide-erreur-unite'),
                style: const TextStyle(
                  fontFamily: AppTextStyles.police,
                  fontSize: Tailles.t13,
                  color: AppColors.erreur,
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          const Text(
            TextesReservationRapide.pied,
            key: Key('rapide-pied'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppTextStyles.police,
              fontSize: Tailles.t12,
              color: Ardoise.c400,
            ),
          ),
        ],
      ),
      actions: [
        BoutonAnnulerCaisse(
          onPressed: _envoi ? null : () => Navigator.of(context).pop(),
        ),
        BoutonActionCaisse(
          cle: const Key('rapide-enregistrer'),
          libelle: TextesReservationRapide.bouton,
          onPressed: _envoi ? null : _enregistrer,
        ),
      ],
    );
  }
}
