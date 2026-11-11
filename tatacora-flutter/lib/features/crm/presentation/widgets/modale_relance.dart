// Vue Blade maîtresse (PA-183) : pwa/crm/clients-creances.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../caisse/presentation/widgets/modale_ouverture_caisse.dart'
    show BoutonActionCaisse, BoutonAnnulerCaisse, ChampMontantCaisse;
import '../../../comptabilite/domain/montant_comptable.dart'
    show chaineDepuisCentimes;
import '../../../restaurant/presentation/widgets/coquille_modale_restaurant.dart';
import '../../domain/entities/relance.dart';
import '../../domain/messages_relance.dart';
import '../providers_crm.dart';

/// Ouvre la modale **« Tracer une relance »** — `ouvrirRelance` de la vue
/// (l.409-421), depuis « Relancer » (onglet « Relances clients »). Rend `true`
/// quand la relance a été enregistrée.
Future<bool> tracerUneRelance(
  BuildContext context, {
  required String clientId,
  required String clientNom,
  required int montantProposeCentimes,
}) async {
  final fait = await showDialog<bool>(
    context: context,
    builder: (_) => ModaleRelance(
      clientId: clientId,
      clientNom: clientNom,
      montantProposeCentimes: montantProposeCentimes,
    ),
  );
  return fait ?? false;
}

/// La modale **« Tracer une relance »** (`pwa/crm/clients-creances.blade.php`
/// l.691-724), posée dans le châssis partagé des modales.
///
/// ## Ce qu'elle rend, dans l'ordre de la vue
///
/// Le nom du client (rappel), « Canal utilisé » (les cinq canaux du registre
/// fermé, `*`), « Montant réclamé » (pré-rempli du solde vivant du client,
/// `soldeDuClient()`), « Promesse de règlement », « Compte rendu » (« Ce que le
/// client a répondu. »), l'avertissement, « Annuler » et « Enregistrer la
/// relance ».
///
/// ## La relance est TRACÉE, pas envoyée
///
/// L'avertissement le dit avec les mots de la vue. Rien n'est émis : aucun canal
/// n'est branché sur ce système, la relance est un fait daté que le serveur
/// rejouera.
///
/// ## Le refus s'affiche SOUS le montant, la saisie reste
///
/// Comme `@error('relanceMontant')` (l.707) : au serveur TOUT refus (validation
/// du montant, service) y est posé.
class ModaleRelance extends ConsumerStatefulWidget {
  const ModaleRelance({
    required this.clientId,
    required this.clientNom,
    required this.montantProposeCentimes,
    super.key,
  });

  final String clientId;
  final String clientNom;

  /// Le solde vivant du client, proposé comme montant réclamé.
  final int montantProposeCentimes;

  @override
  ConsumerState<ModaleRelance> createState() => _EtatModaleRelance();
}

class _EtatModaleRelance extends ConsumerState<ModaleRelance> {
  late final TextEditingController _montant;
  final _promesse = TextEditingController();
  final _commentaire = TextEditingController();
  CanalRelance _canal = CanalRelance.telephone;
  String? _refusMontant;
  String? _refusPromesse;
  bool _envoi = false;

  @override
  void initState() {
    super.initState();
    // `ouvrirRelance` : canal « téléphone », montant = le solde du client,
    // promesse et compte rendu vides.
    _montant = TextEditingController(
      text: chaineDepuisCentimes(widget.montantProposeCentimes),
    );
  }

  @override
  void dispose() {
    _montant.dispose();
    _promesse.dispose();
    _commentaire.dispose();
    super.dispose();
  }

  static final RegExp _jour = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

  /// `nullable|date` : vide passe, une date lisible passe, le reste est refusé.
  ({DateTime? date, String? refus}) _lirePromesse() {
    final t = _promesse.text.trim();
    if (t.isEmpty) return (date: null, refus: null);
    final m = _jour.firstMatch(t);
    if (m != null) {
      final a = int.parse(m.group(1)!);
      final mo = int.parse(m.group(2)!);
      final j = int.parse(m.group(3)!);
      final d = DateTime(a, mo, j);
      if (d.year == a && d.month == mo && d.day == j) {
        return (date: d, refus: null);
      }
    }
    return (date: null, refus: MessagesRelance.promesseIllisible);
  }

  Future<void> _choisirDate() async {
    final lue = _lirePromesse().date;
    final choisie = await showDatePicker(
      context: context,
      initialDate: lue ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (choisie == null) return;
    setState(() {
      _promesse.text =
          '${choisie.year.toString().padLeft(4, '0')}-'
          '${choisie.month.toString().padLeft(2, '0')}-'
          '${choisie.day.toString().padLeft(2, '0')}';
    });
  }

  Future<void> _enregistrer() async {
    final promesse = _lirePromesse();
    if (promesse.refus != null) {
      setState(() {
        _refusMontant = null;
        _refusPromesse = promesse.refus;
      });
      return;
    }
    setState(() {
      _refusMontant = null;
      _refusPromesse = null;
      _envoi = true;
    });
    final navigateur = Navigator.of(context);
    final messages = ScaffoldMessenger.of(context);
    try {
      final succes = await ref.read(enregistrerRelanceProvider)((
        clientId: widget.clientId,
        clientNom: widget.clientNom,
        canal: _canal.code,
        montant: _montant.text,
        promesse: promesse.date,
        commentaire: _commentaire.text,
      ));
      navigateur.pop(true);
      messages.showSnackBar(SnackBar(content: Text(succes)));
    } on RefusRelance catch (e) {
      if (mounted) setState(() => _refusMontant = e.message);
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  static const TextStyle _etiquette = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: Tailles.t13,
    fontWeight: FontWeight.w600,
    color: Ardoise.c700,
  );

  static const TextStyle _valeur = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: Tailles.t13,
    color: AppColors.anthracite,
  );

  /// `block text-[13px] font-semibold text-slate-700 mb-1.5` (+ astérisque).
  Widget _libelle(String texte, {bool requis = false}) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
    child: Text.rich(
      TextSpan(
        style: _etiquette,
        children: [
          TextSpan(text: texte),
          if (requis)
            const TextSpan(
              text: ' *',
              style: TextStyle(color: PaletteMaitre.rouge500),
            ),
        ],
      ),
    ),
  );

  InputDecoration _decoration({String? invite, Widget? fin}) {
    final bordure = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      borderSide: const BorderSide(color: Ardoise.c300),
    );
    return InputDecoration(
      isDense: true,
      hintText: invite,
      counterText: '',
      suffixIcon: fin,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xsPlus,
      ),
      enabledBorder: bordure,
      border: bordure,
      focusedBorder: bordure.copyWith(
        borderSide: const BorderSide(color: AppColors.gold),
      ),
    );
  }

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
              color: AppColors.erreur,
            ),
          ),
        );

  @override
  Widget build(BuildContext context) {
    return CoquilleModaleRestaurant(
      cle: const Key('modale-relance'),
      titre: 'Tracer une relance',
      largeur: AppLayout.modaleRelanceCrm,
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // `bg-slate-50 border border-slate-200 rounded-lg p-3`.
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: Ardoise.c50,
              borderRadius: BorderRadius.circular(AppRadius.roundedLg),
              border: Border.all(color: Ardoise.c200),
            ),
            child: Text(
              widget.clientNom,
              key: const Key('relance-client'),
              style: const TextStyle(
                fontFamily: AppTextStyles.police,
                fontSize: Tailles.t15,
                fontWeight: FontWeight.bold,
                color: AppColors.navy,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _libelle('Canal utilisé', requis: true),
          DropdownButtonFormField<CanalRelance>(
            key: const Key('relance-canal'),
            initialValue: _canal,
            isDense: true,
            isExpanded: true,
            decoration: _decoration(),
            style: _valeur,
            items: [
              for (final c in CanalRelance.values)
                DropdownMenuItem(value: c, child: Text(c.libelle)),
            ],
            onChanged: _envoi
                ? null
                : (c) {
                    if (c != null) setState(() => _canal = c);
                  },
          ),
          const SizedBox(height: AppSpacing.md),
          _libelle('Montant réclamé'),
          ChampMontantCaisse(
            cle: const Key('relance-montant'),
            controleur: _montant,
          ),
          _erreur(_refusMontant, const Key('relance-refus')),
          const SizedBox(height: AppSpacing.md),
          _libelle('Promesse de règlement'),
          TextField(
            key: const Key('relance-promesse'),
            controller: _promesse,
            style: _valeur,
            keyboardType: TextInputType.datetime,
            decoration: _decoration(
              invite: 'AAAA-MM-JJ',
              fin: IconButton(
                key: const Key('relance-promesse-calendrier'),
                icon: const Icon(Icons.calendar_today_outlined),
                iconSize: AppLayout.iconeChamp,
                onPressed: _envoi ? null : _choisirDate,
              ),
            ),
          ),
          _erreur(_refusPromesse, const Key('relance-erreur-promesse')),
          const SizedBox(height: AppSpacing.md),
          _libelle('Compte rendu'),
          TextField(
            key: const Key('relance-commentaire'),
            controller: _commentaire,
            style: _valeur,
            minLines: 3,
            maxLines: 3,
            maxLength: 500,
            decoration: _decoration(invite: 'Ce que le client a répondu.'),
          ),
          const SizedBox(height: AppSpacing.md),
          // `text-[11px] text-slate-500 bg-slate-100 border border-slate-200
          // rounded-lg p-2.5`.
          Container(
            padding: const EdgeInsets.all(AppSpacing.xsPlus),
            decoration: BoxDecoration(
              color: Ardoise.c100,
              borderRadius: BorderRadius.circular(AppRadius.roundedLg),
              border: Border.all(color: Ardoise.c200),
            ),
            child: const Text(
              'Cet écran enregistre une relance déjà effectuée. Il n\'envoie aucun message : aucun canal n\'est branché sur ce système.',
              key: Key('relance-avertissement'),
              style: TextStyle(
                fontFamily: AppTextStyles.police,
                fontSize: Tailles.t11,
                color: Ardoise.c500,
              ),
            ),
          ),
        ],
      ),
      actions: [
        BoutonAnnulerCaisse(
          onPressed: _envoi ? null : () => Navigator.of(context).pop(false),
        ),
        BoutonActionCaisse(
          cle: const Key('relance-enregistrer'),
          libelle: 'Enregistrer la relance',
          onPressed: _envoi ? null : _enregistrer,
        ),
      ],
    );
  }
}
