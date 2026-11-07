// Vue Blade maîtresse : pwa/facturation/proformas.blade.php (écran propre à la PWA, PO 07/11/2026).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/app_database.dart';
import '../../../core/di/providers.dart';
import '../../../core/rbac/garde_acces.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared_widgets/bouton_standard.dart';
import '../data/prefill_proforma_poste.dart';
import '../data/proforma_dao.dart';
import '../domain/mise_en_page_proforma.dart';
import '../domain/textes_proforma.dart';
import 'providers_facturation.dart';
import 'widgets/dialogues_proforma.dart';
import 'providers_proformas.dart';

/// FACTURES PROFORMA du poste — document NON FISCAL, HORS LIGNE (PO, 07/11/2026).
///
/// Jumeau de `pwa/facturation/proformas.blade.php` : mêmes libellés (`textes_proforma.dart`, relus du
/// serveur par un test), droits M2 (lecture : voir et imprimer ; écriture : tout le reste), aucune
/// requête réseau. Création libre ou arrivée depuis un module (`flux`, `source`) qui prérempli le
/// client, l'objet et les lignes ; les lignes restent modifiables. Aucun geste de cet écran ne
/// parle de MECeF.
class EcranProformas extends ConsumerStatefulWidget {
  const EcranProformas({this.flux = '', this.source = '', super.key});

  final String flux;
  final String source;

  @override
  ConsumerState<EcranProformas> createState() => _EcranProformasState();
}

class _EcranProformasState extends ConsumerState<EcranProformas> {
  String _statut = '';
  String _terme = '';
  String? _message;
  bool _erreur = false;

  bool get _peutEcrire =>
      ref.read(droitsProvider).niveau(ModuleTatacora.m2Facturation).peutEcrire;

  @override
  void initState() {
    super.initState();
    if (widget.flux.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted || !_peutEcrire) return;
        final p = await PrefillProformaPoste.depuis(
          ref.read(baseLocaleProvider),
          widget.flux,
          widget.source.isEmpty ? null : widget.source,
        );
        if (p != null && mounted) await _ouvrirFormulaire(prefill: p);
      });
    }
  }

  void _dire(String texte, {bool erreur = false}) => setState(() {
    _message = texte;
    _erreur = erreur;
  });

  Future<void> _ouvrirFormulaire({
    PrefillProformaPoste? prefill,
    ProformasLocalData? existante,
  }) async {
    final lignes = existante == null
        ? null
        : await ref.read(proformaDaoProvider).lignes(existante.id);
    if (!mounted) return;
    final retour = await showDialog<String>(
      context: context,
      builder: (_) => FormulaireProforma(
        prefill: prefill,
        existante: existante,
        lignesExistantes: lignes,
      ),
    );
    if (retour != null) _dire(retour);
  }

  Future<void> _emettre(ProformasLocalData p) async {
    try {
      final reglages = await ref.read(reglagesDocumentsProvider.future);
      final e = await ref
          .read(proformaDaoProvider)
          .emettre(p.id, reglages: reglages);
      _dire(TextesProforma.ui['emise']!.replaceAll(':numero', e.numero ?? ''));
    } on RefusProforma catch (r) {
      _dire(r.message, erreur: true);
    }
  }

  Future<void> _annuler(ProformasLocalData p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => DialogueAnnulation(proformaId: p.id),
    );
    if (ok == true) _dire(TextesProforma.ui['annulee']!);
  }

  /// La conversion se CONFIRME toujours (une expirée surtout) : une fois faite, elle est définitive.
  Future<void> _convertir(ProformasLocalData p) async {
    final dao = ref.read(proformaDaoProvider);
    final confirme = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(TextesProforma.ui['conversion_titre']!),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(TextesProforma.ui['conversion_message']!),
            if (dao.estExpiree(p)) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                TextesProforma.ui['conversion_expiree']!,
                key: const Key('proforma-conversion-expiree'),
                style: const TextStyle(color: AppColors.erreur),
              ),
            ],
          ],
        ),
        actions: [
          BoutonStandard(
            libelle: 'Annuler',
            onPressed: () => Navigator.pop(ctx, false),
          ),
          BoutonStandard(
            key: const Key('proforma-conversion-confirmer'),
            libelle: TextesProforma.ui['conversion_confirmer']!,
            variante: VarianteBouton.primaire,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (confirme != true) return;
    try {
      await dao.convertirEnFacture(p.id);
      final numero = (await dao.parId(p.id))?.factureId ?? '';
      _dire(
        TextesProforma.ui['convertie']!.replaceAll(
          ':numero',
          numero.isEmpty ? '' : await _numeroDe(numero),
        ),
      );
    } on RefusProforma catch (r) {
      _dire(r.message, erreur: true);
    }
  }

  Future<String> _numeroDe(String factureId) async {
    final piece = await ref.read(factureDaoProvider).parId(factureId);
    return piece?.numero ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final liste = ref.watch(proformasProvider);
    final peutEcrire = ref
        .watch(droitsProvider)
        .niveau(ModuleTatacora.m2Facturation)
        .peutEcrire;
    final dao = ref.read(proformaDaoProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppLayout.maxContentWidth,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.receipt_long_outlined,
                    size: AppLayout.iconeTitrePage,
                    color: AppColors.navy,
                  ),
                  const SizedBox(width: AppSpacing.xsPlus),
                  Expanded(
                    child: Text(
                      TextesProforma.ui['titre']!,
                      style: _t(
                        TaillesContenu.lg,
                        poids: FontWeight.bold,
                        couleur: AppColors.navy,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                TextesProforma.ui['sous_titre']!,
                style: _t(TaillesContenu.t15, couleur: AppColors.neutre500),
              ),
              const SizedBox(height: AppSpacing.mdPlus),
              if (_message != null)
                Container(
                  key: const Key('proforma-message'),
                  margin: const EdgeInsets.only(bottom: AppSpacing.md),
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: _erreur
                        ? PaletteMaitre.rouge50
                        : AppColors.badgeVertFond,
                    borderRadius: BorderRadius.circular(AppRadius.roundedXl),
                  ),
                  child: Text(
                    _message!,
                    style: _t(
                      TaillesContenu.t13,
                      poids: FontWeight.w600,
                      couleur: _erreur
                          ? PaletteMaitre.rouge800
                          : AppColors.succes,
                    ),
                  ),
                ),
              Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: AppColors.neutre0,
                  borderRadius: BorderRadius.circular(AppRadius.roundedXl),
                  border: Border.all(color: AppColors.neutre200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _barre(peutEcrire),
                    liste.when(
                      loading: () => const Padding(
                        padding: EdgeInsets.all(AppSpacing.xl),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                      error: (e, _) => Padding(
                        padding: const EdgeInsets.all(AppSpacing.xl),
                        child: Center(child: Text('$e')),
                      ),
                      data: (toutes) {
                        final vues = toutes.where(_filtrer).toList();
                        if (vues.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.all(AppSpacing.xl),
                            child: Center(
                              child: Text(
                                key: const Key('proformas-vide'),
                                TextesProforma.ui['vide']!,
                                style: _t(
                                  TaillesContenu.t13,
                                  couleur: AppColors.neutre400,
                                ),
                              ),
                            ),
                          );
                        }
                        return Column(
                          children: [
                            for (final p in vues)
                              _Ligne(
                                proforma: p,
                                expiree: dao.estExpiree(p),
                                peutEcrire: peutEcrire,
                                onImprimer: () =>
                                    ref.read(imprimerProformaProvider)(p.id),
                                onModifier: () =>
                                    _ouvrirFormulaire(existante: p),
                                onEmettre: () => _emettre(p),
                                onConvertir: () => _convertir(p),
                                onAnnuler: () => _annuler(p),
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _filtrer(ProformasLocalData p) {
    if (_statut.isNotEmpty && p.statut != _statut) return false;
    final t = _terme.trim().toLowerCase();
    if (t.isEmpty) return true;
    return [
      p.numero,
      p.clientNom,
      p.objet,
    ].any((v) => (v ?? '').toLowerCase().contains(t));
  }

  Widget _barre(bool peutEcrire) => Padding(
    padding: const EdgeInsets.all(AppSpacing.sm),
    child: Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        TextButton(
          key: const Key('proformas-retour'),
          onPressed: () => context.go('/facturation'),
          child: Text(TextesProforma.ui['retour']!),
        ),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: AppLayout.rechercheFacture,
              child: TextField(
                key: const Key('proformas-recherche'),
                onChanged: (v) => setState(() => _terme = v),
                decoration: InputDecoration(
                  hintText: TextesProforma.ui['recherche'],
                  isDense: true,
                ),
              ),
            ),
            SizedBox(
              width: AppLayout.rechercheFacture,
              child: DropdownButton<String>(
                isExpanded: true,
                key: const Key('proformas-filtre-statut'),
                value: _statut,
                items: [
                  DropdownMenuItem(
                    value: '',
                    child: Text(TextesProforma.ui['tous_statuts']!),
                  ),
                  for (final s in StatutProforma.values)
                    DropdownMenuItem(
                      value: s.code,
                      child: Text(TextesProforma.statut[s.code]!),
                    ),
                ],
                onChanged: (v) => setState(() => _statut = v ?? ''),
              ),
            ),
            if (peutEcrire)
              BoutonStandard(
                key: const Key('proformas-nouvelle'),
                libelle: TextesProforma.ui['nouvelle']!,
                variante: VarianteBouton.primaire,
                onPressed: () =>
                    _ouvrirFormulaire(prefill: PrefillProformaPoste.vide),
              ),
          ],
        ),
      ],
    ),
  );
}

TextStyle _t(double taille, {FontWeight? poids, Color? couleur}) => TextStyle(
  fontFamily: AppTextStyles.police,
  fontSize: taille,
  fontWeight: poids,
  color: couleur,
  height: 1.5,
);

/// Une proforma : numéro, client, objet, total, état — et ses gestes, selon son état et les droits.
class _Ligne extends StatelessWidget {
  const _Ligne({
    required this.proforma,
    required this.expiree,
    required this.peutEcrire,
    required this.onImprimer,
    required this.onModifier,
    required this.onEmettre,
    required this.onConvertir,
    required this.onAnnuler,
  });

  final ProformasLocalData proforma;
  final bool expiree;
  final bool peutEcrire;
  final VoidCallback onImprimer;
  final VoidCallback onModifier;
  final VoidCallback onEmettre;
  final VoidCallback onConvertir;
  final VoidCallback onAnnuler;

  @override
  Widget build(BuildContext context) {
    final p = proforma;
    final statut = TextesProforma.statut[expiree ? 'expiree' : p.statut]!;
    final modifiable =
        p.statut == StatutProforma.brouillon.code ||
        p.statut == StatutProforma.emise.code;
    return Container(
      key: Key('proforma-${p.id}'),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.neutre200)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.demi,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                p.numero ?? TextesProforma.ui['brouillon_sans_numero']!,
                key: Key('proforma-numero-${p.id}'),
                style: _t(
                  TaillesContenu.t13,
                  poids: FontWeight.bold,
                  couleur: AppColors.navy,
                ),
              ),
              Text(
                statut,
                key: Key('proforma-statut-${p.id}'),
                style: _t(
                  TaillesContenu.t12,
                  poids: FontWeight.w600,
                  couleur: expiree || p.statut == StatutProforma.annulee.code
                      ? AppColors.erreur
                      : AppColors.neutre600,
                ),
              ),
              Text(
                montantAvecEspaces(p.total),
                style: _t(TaillesContenu.t13, poids: FontWeight.w600),
              ),
            ],
          ),
          Text(
            [p.clientNom, if ((p.objet ?? '').isNotEmpty) p.objet!].join(' — '),
            style: _t(TaillesContenu.t13),
          ),
          if (p.dateEmission != null)
            Text(
              [
                '${p.dateEmission!.day.toString().padLeft(2, '0')}/'
                    '${p.dateEmission!.month.toString().padLeft(2, '0')}/${p.dateEmission!.year}',
                if (p.valideJusquAu != null &&
                    p.statut == StatutProforma.emise.code)
                  TextesProforma.ui['valable']!.replaceAll(
                    ':date',
                    '${p.valideJusquAu!.day.toString().padLeft(2, '0')}/'
                        '${p.valideJusquAu!.month.toString().padLeft(2, '0')}/${p.valideJusquAu!.year}',
                  ),
                if ((p.motifAnnulation ?? '').isNotEmpty) p.motifAnnulation!,
              ].join(' · '),
              style: _t(TaillesContenu.t11, couleur: AppColors.neutre400),
            ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              BoutonStandard(
                key: Key('proforma-pdf-${p.id}'),
                libelle: TextesProforma.ui['pdf']!,
                compact: true,
                onPressed: onImprimer,
              ),
              if (peutEcrire && modifiable)
                BoutonStandard(
                  key: Key('proforma-modifier-${p.id}'),
                  libelle: TextesProforma.ui['modifier']!,
                  compact: true,
                  onPressed: onModifier,
                ),
              if (peutEcrire && p.statut == StatutProforma.brouillon.code)
                BoutonStandard(
                  key: Key('proforma-emettre-${p.id}'),
                  libelle: TextesProforma.ui['emettre']!,
                  compact: true,
                  onPressed: onEmettre,
                ),
              if (peutEcrire && p.statut == StatutProforma.emise.code)
                BoutonStandard(
                  key: Key('proforma-convertir-${p.id}'),
                  libelle: TextesProforma.ui['convertir']!,
                  compact: true,
                  variante: VarianteBouton.primaire,
                  onPressed: onConvertir,
                ),
              if (peutEcrire && modifiable)
                BoutonStandard(
                  key: Key('proforma-annuler-${p.id}'),
                  libelle: TextesProforma.ui['annuler']!,
                  compact: true,
                  variante: VarianteBouton.contourRouge,
                  onPressed: onAnnuler,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
