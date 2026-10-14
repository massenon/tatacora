// Vue Blade maîtresse (PA-183) : pwa/hebergement/reservations.blade.php
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/format/formats.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../caisse/domain/montant_caisse.dart';
import '../../../comptabilite/domain/refus_comptable.dart';
import '../../../restaurant/presentation/widgets/coquille_modale_restaurant.dart';
import '../../domain/annulation_reservation.dart';
import '../../domain/entities/reservation.dart';
import '../../domain/messages_annulation.dart';
import '../providers_hebergement.dart';

/// Ouvre la modale **« Annuler cette réservation »** (`reservations.blade.php`
/// l.787-880, EF-M1-06) — le MÊME geste depuis la carte, depuis le détail et
/// depuis l'historique.
///
/// ## Ce qui se passe AVANT la modale — `confirmerAnnulation` du serveur
///
/// Sans montant total fiable (aucun tarif figé, aucune ligne), le serveur ne
/// l'ouvre PAS : il affiche la phrase en bannière de page. Le poste fait de
/// même, par un message — jamais une modale qui calculerait une commission sur
/// un chiffre inventé.
///
/// Le taux est PRÉ-REMPLI du paramètre, le remboursement du pourcentage de
/// l'acompte qui resterait après la commission théorique ; l'un et l'autre sont
/// MODIFIABLES. Le délai avant l'arrivée est INFORMATIF : il n'automatise rien.
///
/// Rend `true` quand la réservation a été annulée.
Future<bool> ouvrirModaleAnnulationReservation(
  BuildContext context,
  WidgetRef ref,
  Reservation reservation,
) async {
  final total = montantTotalCentimes(
    tarifNuit: reservation.tarifNuit,
    aDesLignes: reservation.lignes.isNotEmpty,
    totalDuRecapitulatifFrancs: reservation.recapitulatif.total,
  );
  if (total == null) {
    // La bannière `@error('annulation')` de la page du serveur.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          MessagesAnnulation.montantTotalInconnu,
          key: Key('annulation-banniere-page'),
        ),
      ),
    );
    return false;
  }

  final tauxInitial = await ref.read(tauxAnnulationParDefautProvider.future);
  final client = await ref.read(clientDaoProvider).parId(reservation.clientId);
  if (!context.mounted) return false;

  // `trim($client->prenom . ' ' . $client->nom)` — l'ordre de la VUE (prénom
  // d'abord), pas celui de l'affichage courant du poste (« KORA Jean »).
  final nom = client == null
      ? null
      : '${client.prenom ?? ''} ${client.nom}'.trim();

  final annulee = await showDialog<bool>(
    context: context,
    barrierColor: AppColors.voileModale,
    builder: (_) => ModaleAnnulationReservation(
      reservation: reservation,
      nomClient: nom,
      tauxInitial: tauxInitial,
      maintenant: ref.read(horlogeAnnulationProvider)(),
    ),
  );
  if (annulee != true) return false;

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          MessagesAnnulation.annuleeFlash,
          key: Key('annulation-succes'),
        ),
      ),
    );
  }
  rafraichirListes(ref);
  return true;
}

/// La modale elle-même — montée seule par les tests, ouverte par
/// [ouvrirModaleAnnulationReservation] en production.
class ModaleAnnulationReservation extends ConsumerStatefulWidget {
  const ModaleAnnulationReservation({
    required this.reservation,
    required this.tauxInitial,
    required this.maintenant,
    this.nomClient,
    super.key,
  });

  final Reservation reservation;

  /// Le nom complet à la manière de la vue (prénom puis nom), ou `null` — la
  /// vue écrit alors le tiret.
  final String? nomClient;

  /// Le taux pré-rempli : le paramètre, ou `50.00`.
  final String tauxInitial;

  /// L'instant de l'ouverture : le délai avant l'arrivée en dépend.
  final DateTime maintenant;

  @override
  ConsumerState<ModaleAnnulationReservation> createState() =>
      _EtatModaleAnnulation();
}

class _EtatModaleAnnulation extends ConsumerState<ModaleAnnulationReservation> {
  late final TextEditingController _taux;
  late final TextEditingController _valeur;
  String _mode = ModesRemboursement.pourcentage;
  Map<String, List<String>> _erreurs = const {};
  String? _banniere;
  bool _envoi = false;

  int get _acompteCentimes => widget.reservation.acompte * 100;

  int get _totalCentimes => widget.reservation.recapitulatif.total * 100;

  @override
  void initState() {
    super.initState();
    _taux = TextEditingController(text: widget.tauxInitial);
    // Le remboursement suggéré se calcule UNE fois, à l'ouverture, depuis le
    // taux pré-rempli : `annulerReservation` ne le relit jamais, seule la valeur
    // soumise compte.
    _valeur = TextEditingController(
      text: pourcentageRembourseSuggere(
        acompteCentimes: _acompteCentimes,
        totalCentimes: _totalCentimes,
        taux: widget.tauxInitial,
      ),
    );
  }

  @override
  void dispose() {
    _taux.dispose();
    _valeur.dispose();
    super.dispose();
  }

  Future<void> _confirmer() async {
    final erreurs = validerSaisieAnnulation(
      taux: _taux.text,
      mode: _mode,
      valeur: _valeur.text,
    );
    if (erreurs.isNotEmpty) {
      setState(() {
        _erreurs = erreurs;
        _banniere = null;
      });
      return;
    }

    setState(() {
      _erreurs = const {};
      _banniere = null;
      _envoi = true;
    });
    final navigateur = Navigator.of(context);
    try {
      await ref.read(annulerReservationProvider)(
        widget.reservation.id,
        tauxSaisi: _taux.text,
        modeRemboursement: _mode,
        valeurRemboursement: _valeur.text,
        // Celui qui annule (RG-15) : la pièce du remboursement le nomme.
        auteurId: ref.read(sessionProvider)?.utilisateurId ?? '',
      );
      navigateur.pop(true);
    } on RefusAnnulation catch (e) {
      // Le composant du serveur rattache les `InvalidArgumentException` au champ
      // du remboursement, les `RuntimeException` à la bannière.
      if (!mounted) return;
      setState(() {
        if (e.champ == 'annulation' || e.champ == null) {
          _banniere = e.message;
        } else {
          _erreurs = {
            e.champ!: [e.message],
          };
        }
      });
    } on RefusComptable catch (e) {
      // La pièce du remboursement est refusée : RIEN n'a été écrit, pas même le
      // statut. La phrase est celle du serveur.
      if (mounted) setState(() => _banniere = e.message);
    } on StateError catch (e) {
      if (mounted) setState(() => _banniere = e.message);
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.reservation;
    final delai = delaiHeuresAvantArrivee(r.periode.arrivee, widget.maintenant);
    final sousSeuil = delai < ReglesAnnulation.seuilHeures;
    final aUnAcompte = _acompteCentimes > 0;

    return CoquilleModaleRestaurant(
      cle: const Key('modale-annulation-reservation'),
      titre: MessagesAnnulation.titre,
      sousTitre: MessagesAnnulation.element(
        widget.nomClient == null || widget.nomClient!.isEmpty
            ? '—'
            : widget.nomClient!,
        formaterDate(r.periode.arrivee),
        formaterDate(r.periode.depart),
      ),
      largeur: AppLayout.modaleAnnulationReservation,
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_banniere != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Text(
                _banniere!,
                key: const Key('annulation-banniere'),
                style: const TextStyle(
                  fontFamily: AppTextStyles.police,
                  fontSize: Tailles.t12,
                  color: PaletteMaitre.rouge600,
                ),
              ),
            ),

          // Le délai — INFORMATIF : le compte rendu client ne valide qu'UN cas
          // (« moins de 24h -> 50 % ») et renvoie le reste à confirmation.
          Container(
            key: const Key('annulation-delai'),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xsPlus,
            ),
            decoration: BoxDecoration(
              color: sousSeuil ? AppColors.reserveGoldFond : Ardoise.c100,
              borderRadius: BorderRadius.circular(AppRadius.roundedLg),
            ),
            child: Text(
              [
                delai >= 0
                    ? MessagesAnnulation.delai(formaterHeures(delai))
                    : MessagesAnnulation.delaiPasse,
                if (sousSeuil) '— ${MessagesAnnulation.sousSeuil}',
              ].join(' '),
              style: TextStyle(
                fontFamily: AppTextStyles.police,
                fontSize: Tailles.t12,
                color: sousSeuil ? AppColors.annulationTexteOr : Ardoise.c700,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Les deux montants de référence (`bg-slate-50 rounded-lg p-3`).
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: Ardoise.c50,
              borderRadius: BorderRadius.circular(AppRadius.roundedLg),
            ),
            child: Column(
              children: [
                _ligneMontant(
                  MessagesAnnulation.montantTotal,
                  formaterCentimesEnFcfa(_totalCentimes),
                  const Key('annulation-total'),
                ),
                const SizedBox(height: AppSpacing.unit),
                _ligneMontant(
                  MessagesAnnulation.acompteVerse,
                  formaterCentimesEnFcfa(_acompteCentimes),
                  const Key('annulation-acompte'),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Le taux — obligatoire, pré-rempli, modifiable ligne par ligne.
          _etiquette(MessagesAnnulation.champTaux, obligatoire: true),
          Row(
            children: [
              Expanded(
                child: _champ(
                  const Key('annulation-taux'),
                  _taux,
                  erreur: _erreurs.containsKey('aTaux'),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              const Text(
                '%',
                style: TextStyle(
                  fontFamily: AppTextStyles.police,
                  fontSize: Tailles.t14,
                  color: Ardoise.c400,
                ),
              ),
            ],
          ),
          _erreur('aTaux', const Key('annulation-erreur-taux')),
          const _Aide(MessagesAnnulation.tauxAide),
          const SizedBox(height: AppSpacing.md),

          // Le remboursement — SOIT en pourcentage de l'acompte, SOIT en FCFA.
          // Rien à restituer si l'acompte est nul : la section n'a pas de sens.
          if (aUnAcompte) ...[
            _etiquette(MessagesAnnulation.champRemboursement),
            Row(
              children: [
                DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    key: const Key('annulation-mode'),
                    value: _mode,
                    style: const TextStyle(
                      fontFamily: AppTextStyles.police,
                      fontSize: Tailles.t15,
                      color: Ardoise.c900,
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: ModesRemboursement.pourcentage,
                        child: Text(MessagesAnnulation.modePourcentage),
                      ),
                      DropdownMenuItem(
                        value: ModesRemboursement.montant,
                        child: Text(MessagesAnnulation.modeMontant),
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _mode = v);
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: _champ(
                    const Key('annulation-valeur'),
                    _valeur,
                    erreur: _erreurs.containsKey('aRembourseValeur'),
                  ),
                ),
              ],
            ),
            _erreur('aRembourseValeur', const Key('annulation-erreur-valeur')),
            const _Aide(MessagesAnnulation.remboursementAide),
          ] else ...[
            const Text(
              MessagesAnnulation.aucunAcompte,
              key: Key('annulation-aucun-acompte'),
              style: TextStyle(
                fontFamily: AppTextStyles.police,
                fontSize: Tailles.t12,
                fontStyle: FontStyle.italic,
                color: Ardoise.c400,
              ),
            ),
            // Un refus du remboursement a quand même un endroit où s'afficher :
            // le champ n'est pas rendu, mais le serveur valide sa valeur.
            _erreur('aRembourseValeur', const Key('annulation-erreur-valeur')),
          ],
          const SizedBox(height: AppSpacing.md),

          // Le rappel de RG-02 (`style="background:#FDECEC;color:#8C1D1D"`).
          Container(
            key: const Key('annulation-rappel'),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xsPlus,
            ),
            decoration: BoxDecoration(
              color: AppColors.badgeRougeFond,
              borderRadius: BorderRadius.circular(AppRadius.roundedLg),
            ),
            child: Text.rich(
              const TextSpan(
                style: TextStyle(
                  fontFamily: AppTextStyles.police,
                  fontSize: Tailles.t12,
                  color: AppColors.annulationTexteRouge,
                ),
                children: [
                  TextSpan(text: MessagesAnnulation.rappelAvant),
                  // Le `<strong>` de la chaîne du serveur.
                  TextSpan(
                    text: MessagesAnnulation.rappelGras,
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  TextSpan(text: MessagesAnnulation.rappelApres),
                ],
              ),
            ),
          ),
        ],
      ),
      actions: [
        OutlinedButton(
          key: const Key('annulation-renoncer'),
          onPressed: _envoi ? null : () => Navigator.of(context).pop(false),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Ardoise.c300),
            foregroundColor: AppColors.anthracite,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.roundedLg),
            ),
          ),
          child: const Text(
            MessagesAnnulation.renoncer,
            style: TextStyle(
              fontFamily: AppTextStyles.police,
              fontSize: Tailles.t13,
            ),
          ),
        ),
        FilledButton(
          key: const Key('annulation-confirmer'),
          onPressed: _envoi ? null : _confirmer,
          style: FilledButton.styleFrom(
            backgroundColor: PaletteMaitre.rouge600,
            foregroundColor: AppColors.neutre0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.roundedLg),
            ),
          ),
          child: const Text(
            MessagesAnnulation.confirmer,
            style: TextStyle(
              fontFamily: AppTextStyles.police,
              fontSize: Tailles.t13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _ligneMontant(String etiquette, String valeur, Key cle) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Flexible(
        child: Text(
          etiquette,
          style: const TextStyle(
            fontFamily: AppTextStyles.police,
            fontSize: Tailles.t13,
            color: Ardoise.c500,
          ),
        ),
      ),
      const SizedBox(width: AppSpacing.xs),
      Text(
        valeur,
        key: cle,
        style: const TextStyle(
          fontFamily: AppTextStyles.policeMonospace,
          fontSize: Tailles.t13,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );

  Widget _etiquette(String texte, {bool obligatoire = false}) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
    child: Text.rich(
      TextSpan(
        style: const TextStyle(
          fontFamily: AppTextStyles.police,
          fontSize: Tailles.t15,
          fontWeight: FontWeight.w600,
          color: Ardoise.c700,
        ),
        children: [
          TextSpan(text: texte),
          if (obligatoire)
            const TextSpan(
              text: ' *',
              style: TextStyle(color: PaletteMaitre.rouge500),
            ),
        ],
      ),
    ),
  );

  Widget _champ(Key cle, TextEditingController c, {required bool erreur}) {
    final bordure = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      borderSide: BorderSide(
        color: erreur ? PaletteMaitre.rouge600 : Ardoise.c200,
      ),
    );
    return TextField(
      key: cle,
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(
        fontFamily: AppTextStyles.police,
        fontSize: Tailles.t14,
      ),
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xsPlus,
        ),
        enabledBorder: bordure,
        border: bordure,
        focusedBorder: bordure.copyWith(
          borderSide: const BorderSide(color: AppColors.gold),
        ),
      ),
    );
  }

  /// Le message du champ, tel que le serveur le rend (`@error` — le PREMIER).
  Widget _erreur(String champ, Key cle) {
    final messages = _erreurs[champ];
    if (messages == null || messages.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.unit),
      child: Text(
        messages.first,
        key: cle,
        style: const TextStyle(
          fontFamily: AppTextStyles.police,
          fontSize: Tailles.t12,
          color: PaletteMaitre.rouge600,
        ),
      ),
    );
  }
}

/// `text-[11px] text-slate-400 mt-1` — l'aide sous un champ.
class _Aide extends StatelessWidget {
  const _Aide(this.texte);

  final String texte;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.unit),
    child: Text(
      texte,
      style: const TextStyle(
        fontFamily: AppTextStyles.police,
        fontSize: Tailles.t11,
        color: Ardoise.c400,
      ),
    ),
  );
}
