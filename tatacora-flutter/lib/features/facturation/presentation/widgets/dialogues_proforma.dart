// Les DIALOGUES de la facture proforma du poste : saisie du brouillon et motif d'annulation. Ils vivent
// hors du `<main>` (échelle DÉCLARÉE, `Tailles`), comme les modales de la vue web.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../shared_widgets/bouton_standard.dart';
import '../../data/prefill_proforma_poste.dart';
import '../../data/proforma_dao.dart';
import '../../domain/textes_proforma.dart';
import '../providers_facturation.dart';
import '../providers_proformas.dart';

class _SaisieLigne {
  _SaisieLigne({
    String designation = '',
    String quantite = '1',
    String prix = '',
  }) : designation = TextEditingController(text: designation),
       quantite = TextEditingController(text: quantite),
       prix = TextEditingController(text: prix);

  final TextEditingController designation;
  final TextEditingController quantite;
  final TextEditingController prix;

  void liberer() {
    designation.dispose();
    quantite.dispose();
    prix.dispose();
  }
}

/// La saisie d'un brouillon : client, objet, lignes LIBRES (désignation, quantité, prix unitaire TTC
/// en francs entiers). Rend le message de succès.
class FormulaireProforma extends ConsumerStatefulWidget {
  const FormulaireProforma({
    super.key,
    this.prefill,
    this.existante,
    this.lignesExistantes,
  });

  final PrefillProformaPoste? prefill;
  final ProformasLocalData? existante;
  final List<LignesProformaLocalData>? lignesExistantes;

  @override
  ConsumerState<FormulaireProforma> createState() => FormulaireProformaState();
}

class FormulaireProformaState extends ConsumerState<FormulaireProforma> {
  late final TextEditingController _client;
  late final TextEditingController _telephone;
  late final TextEditingController _ifu;
  late final TextEditingController _objet;
  late final List<_SaisieLigne> _lignes;
  String? _refus;
  String? _erreurLigne;
  bool _etroit = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existante;
    final p = widget.prefill ?? PrefillProformaPoste.vide;
    _client = TextEditingController(text: e?.clientNom ?? p.clientNom);
    _telephone = TextEditingController(
      text: e?.clientTelephone ?? p.clientTelephone,
    );
    _ifu = TextEditingController(text: e?.clientIfu ?? p.clientIfu);
    _objet = TextEditingController(text: e?.objet ?? p.objet);
    _lignes = [
      if (widget.lignesExistantes != null)
        for (final l in widget.lignesExistantes!)
          _SaisieLigne(
            designation: l.designation,
            quantite: '${l.quantite}',
            prix: '${l.prixUnitaire}',
          )
      else
        for (final l in p.lignes)
          _SaisieLigne(
            designation: l.designation,
            quantite: '${l.quantite}',
            prix: '${l.prixUnitaire}',
          ),
    ];
    if (_lignes.isEmpty) _lignes.add(_SaisieLigne());
  }

  @override
  void dispose() {
    _client.dispose();
    _telephone.dispose();
    _ifu.dispose();
    _objet.dispose();
    for (final l in _lignes) {
      l.liberer();
    }
    super.dispose();
  }

  List<LigneProformaSaisie>? _lues() {
    final lues = <LigneProformaSaisie>[];
    for (final l in _lignes) {
      final q = int.tryParse(l.quantite.text.trim());
      final p = int.tryParse(l.prix.text.trim());
      if (l.designation.text.trim().isEmpty ||
          q == null ||
          q < 1 ||
          p == null ||
          p < 0) {
        setState(() => _erreurLigne = RefusProforma.ligneInvalide);
        return null;
      }
      lues.add((
        designation: l.designation.text.trim(),
        quantite: q,
        prixUnitaire: p,
      ));
    }
    setState(() => _erreurLigne = null);
    return lues;
  }

  Future<void> _enregistrer({required bool emettre}) async {
    final lignes = _lues();
    if (lignes == null) return;
    final dao = ref.read(proformaDaoProvider);
    final reglages = await ref.read(reglagesDocumentsProvider.future);
    try {
      final e = widget.existante;
      ProformasLocalData resultat;
      if (e == null) {
        final p = widget.prefill ?? PrefillProformaPoste.vide;
        resultat = await dao.creer(
          clientNom: _client.text,
          clientId: p.clientId,
          clientTelephone: _telephone.text,
          clientIfu: _ifu.text,
          objet: _objet.text,
          sourceModule: p.sourceModule,
          sourceId: p.sourceId,
          lignes: lignes,
          emettre: emettre,
          reglages: reglages,
        );
      } else {
        resultat = await dao.modifier(
          e.id,
          clientNom: _client.text,
          clientTelephone: _telephone.text,
          clientIfu: _ifu.text,
          objet: _objet.text,
          lignes: lignes,
        );
        if (emettre) resultat = await dao.emettre(e.id, reglages: reglages);
      }
      if (!mounted) return;
      Navigator.pop(
        context,
        emettre
            ? TextesProforma.ui['emise']!.replaceAll(
                ':numero',
                resultat.numero ?? '',
              )
            : TextesProforma.ui['enregistree']!,
      );
    } on RefusProforma catch (r) {
      setState(() => _refus = r.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final creation = widget.existante == null;
    // Pas de `LayoutBuilder` : un `AlertDialog` défilant mesure son contenu en dimensions intrinsèques.
    final largeurEcran = MediaQuery.sizeOf(context).width;
    _etroit = largeurEcran < 640;
    return AlertDialog(
      scrollable: true,
      title: Text(
        TextesProforma.ui[creation
            ? 'form_titre_creation'
            : 'form_titre_modification']!,
      ),
      content: SizedBox(
        width: (largeurEcran - 112).clamp(200.0, 720.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('proforma-client'),
              controller: _client,
              decoration: InputDecoration(
                labelText: '${TextesProforma.ui['form_client']!} *',
                errorText: _refus,
              ),
            ),
            TextField(
              key: const Key('proforma-telephone'),
              controller: _telephone,
              decoration: InputDecoration(
                labelText: TextesProforma.ui['form_telephone'],
              ),
            ),
            TextField(
              key: const Key('proforma-ifu'),
              controller: _ifu,
              decoration: InputDecoration(
                labelText: TextesProforma.ui['form_ifu'],
              ),
            ),
            TextField(
              key: const Key('proforma-objet'),
              controller: _objet,
              decoration: InputDecoration(
                labelText: TextesProforma.ui['form_objet'],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              TextesProforma.ui['form_lignes']!,
              style: TextStyle(
                fontFamily: AppTextStyles.police,
                fontSize: Tailles.t14,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (_erreurLigne != null)
              Text(
                _erreurLigne!,
                style: TextStyle(
                  fontFamily: AppTextStyles.police,
                  fontSize: Tailles.t12,
                  color: AppColors.erreur,
                ),
              ),
            for (var i = 0; i < _lignes.length; i++) _ligne(i),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const Key('proforma-ajouter-ligne'),
                onPressed: () => setState(() => _lignes.add(_SaisieLigne())),
                child: Text(TextesProforma.ui['form_ajouter_ligne']!),
              ),
            ),
          ],
        ),
      ),
      actions: [
        BoutonStandard(
          libelle: 'Annuler',
          onPressed: () => Navigator.pop(context),
        ),
        BoutonStandard(
          key: const Key('proforma-enregistrer'),
          libelle: TextesProforma.ui['form_enregistrer']!,
          onPressed: () => _enregistrer(emettre: false),
        ),
        BoutonStandard(
          key: const Key('proforma-enregistrer-emettre'),
          libelle: TextesProforma.ui['form_emettre']!,
          variante: VarianteBouton.primaire,
          onPressed: () => _enregistrer(emettre: true),
        ),
      ],
    );
  }

  /// Une ligne : en rangée sur un grand écran, EMPILÉE sur un petit (aucun débordement à 320 px).
  Widget _ligne(int i) {
    final l = _lignes[i];
    final designation = TextField(
      key: Key('proforma-ligne-$i-designation'),
      controller: l.designation,
      decoration: InputDecoration(
        labelText: TextesProforma.ui['form_designation'],
      ),
    );
    final quantite = TextField(
      key: Key('proforma-ligne-$i-quantite'),
      controller: l.quantite,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: TextesProforma.ui['form_quantite'],
      ),
    );
    final prix = TextField(
      key: Key('proforma-ligne-$i-prix'),
      controller: l.prix,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: TextesProforma.ui['form_prix']),
    );
    final retirer = IconButton(
      key: Key('proforma-ligne-$i-retirer'),
      tooltip: TextesProforma.ui['form_retirer_ligne'],
      icon: const Icon(Icons.close, size: AppLayout.iconeChamp),
      onPressed: _lignes.length <= 1
          ? null
          : () => setState(() => _lignes.removeAt(i).liberer()),
    );
    if (!_etroit) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(flex: 6, child: designation),
          const SizedBox(width: AppSpacing.xs),
          Expanded(flex: 2, child: quantite),
          const SizedBox(width: AppSpacing.xs),
          Expanded(flex: 3, child: prix),
          retirer,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        designation,
        Row(
          children: [
            Expanded(child: quantite),
            const SizedBox(width: AppSpacing.xs),
            Expanded(child: prix),
            retirer,
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
      ],
    );
  }
}

/// Le motif d'annulation (obligatoire). Le contrôleur appartient à CE dialogue : il n'est libéré
/// qu'avec lui, jamais pendant son animation de fermeture.
class DialogueAnnulation extends ConsumerStatefulWidget {
  const DialogueAnnulation({super.key, required this.proformaId});

  final String proformaId;

  @override
  ConsumerState<DialogueAnnulation> createState() => DialogueAnnulationState();
}

class DialogueAnnulationState extends ConsumerState<DialogueAnnulation> {
  final _motif = TextEditingController();
  String? _refus;

  @override
  void dispose() {
    _motif.dispose();
    super.dispose();
  }

  Future<void> _confirmer() async {
    try {
      await ref
          .read(proformaDaoProvider)
          .annuler(widget.proformaId, _motif.text);
      if (mounted) Navigator.pop(context, true);
    } on RefusProforma catch (r) {
      setState(() => _refus = r.message);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(TextesProforma.ui['annulation_titre']!),
    content: TextField(
      key: const Key('proforma-motif'),
      controller: _motif,
      decoration: InputDecoration(
        labelText: '${TextesProforma.ui['annulation_motif']!} *',
        errorText: _refus,
      ),
    ),
    actions: [
      BoutonStandard(
        libelle: 'Annuler',
        onPressed: () => Navigator.pop(context, false),
      ),
      BoutonStandard(
        key: const Key('proforma-annulation-confirmer'),
        libelle: TextesProforma.ui['annuler']!,
        variante: VarianteBouton.primaire,
        onPressed: _confirmer,
      ),
    ],
  );
}
