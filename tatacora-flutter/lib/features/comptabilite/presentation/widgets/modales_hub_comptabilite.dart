// Vue Blade maîtresse (PA-183) : pwa/comptabilite/hub.blade.php
// (les modales « Créer un compte » et « Ouvrir un exercice » : `etatFormulaire
// === 'compte'` et `=== 'exercice'`).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../shared_widgets/bouton_standard.dart';
import '../../../transverse/presentation/widgets/briques_transverses.dart';
import '../../data/moteur_comptable.dart';
import '../../domain/refus_comptable.dart';
import '../../domain/regle_numero_compte.dart';
import '../providers_comptabilite.dart';
import '../providers_consultation_comptable.dart';
import '../providers_etats_financiers.dart';

/// Les mots des deux modales — `lang/fr/comptabilite_pwa.php` (`compte_*`,
/// `champ_*`, `nature_*`, `exercice_*`), `pwa.modale.annuler`.
abstract final class TextesModalesHubComptabilite {
  // « Créer un compte ».
  static const String compteTitre = 'Créer un compte';
  static const String champNumero = 'Numéro';
  static const String champIntitule = 'Intitulé';
  static const String champIntituleInvite = 'Produits d’entretien';
  static const String champNature = 'Type';
  static const String choisir = 'Choisir…';
  static const String natureActif = 'Actif';
  static const String naturePassif = 'Passif';
  static const String natureCharge = 'Charge';
  static const String natureProduit = 'Produit';
  static const String champNatureAide =
      'Le type commande le poste de bilan. Un type faux rend le compte '
      'invisible au bilan : il ne se devine pas.';
  static const String annuler = 'Annuler';

  /// L'invite est un numéro VALIDE (deux à quatre chiffres) : la même règle
  /// que le service de la vue ([RegleNumeroCompte.format]), la même
  /// invite que la vue du hub.
  static const String champNumeroInvite = RegleNumeroCompte.exemple;

  // « Ouvrir un exercice ».
  static const String exerciceTitre = 'Ouvrir un exercice';
  static const String exerciceAnnee = 'Année de l’exercice';
  static const String exerciceValider = 'Ouvrir l’exercice';

  /// Les messages de succès, à la manière de la saisie d'écriture : DITS
  /// « sur ce poste » (ni le compte ni l'exercice ne sont envoyés au serveur
  /// par ce poste — voir l'écart nommé de l'écran).
  static String compteCree(String numero) =>
      'Compte $numero créé sur ce poste.';
  static String exerciceOuvert(int annee) =>
      'Exercice $annee ouvert sur ce poste.';
  static const String echecInattendu =
      "L'opération n'a pas pu être enregistrée sur ce poste. Rien n'a été "
      'écrit.';
}

/// Ouvre « Créer un compte » et DIT le résultat. La modale rend le message de
/// succès (`null` : annulée).
Future<void> ouvrirModaleCompte(BuildContext context) async {
  final message = await showDialog<String>(
    context: context,
    barrierColor: AppColors.voileModale,
    builder: (_) => const _ModaleCompte(),
  );
  if (message == null || !context.mounted) return;
  direTransverse(context, message, cle: const Key('compta-compte-cree'));
}

/// Ouvre « Ouvrir un exercice », l'année proposée étant [anneeInitiale] (le
/// dernier exercice + 1, comme la vue).
Future<void> ouvrirModaleExercice(
  BuildContext context, {
  required int anneeInitiale,
}) async {
  final message = await showDialog<String>(
    context: context,
    barrierColor: AppColors.voileModale,
    builder: (_) => _ModaleExercice(anneeInitiale: anneeInitiale),
  );
  if (message == null || !context.mounted) return;
  direTransverse(context, message, cle: const Key('compta-exercice-ouvert'));
}

/// Le cadre commun : titre + filet, corps défilant, pied « justify-end gap-2 ».
class CadreModaleComptabilite extends StatelessWidget {
  const CadreModaleComptabilite({
    required this.cle,
    required this.largeur,
    required this.titre,
    required this.corps,
    required this.pied,
    super.key,
  });

  final Key cle;
  final double largeur;
  final String titre;
  final List<Widget> corps;
  final List<Widget> pied;

  @override
  Widget build(BuildContext context) => Dialog(
    key: cle,
    backgroundColor: AppColors.neutre0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.roundedXl),
    ),
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: largeur),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.mdPlus,
              vertical: AppSpacing.md,
            ),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Ardoise.c200)),
            ),
            child: Text(
              titre,
              style: styleTransverse(
                Tailles.t16,
                poids: FontWeight.bold,
                couleur: AppColors.navy,
              ),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.mdPlus),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: corps,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.mdPlus,
              vertical: AppSpacing.sm,
            ),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Ardoise.c200)),
            ),
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: pied,
            ),
          ),
        ],
      ),
    ),
  );
}

/// Le refus, en rouge, au-dessus du formulaire (`@error('compte')`).
Widget refusModaleComptabilite(Key cle, String message) => Padding(
  padding: const EdgeInsets.only(bottom: AppSpacing.md),
  child: EncadreTransverse(
    key: cle,
    fond: PaletteMaitre.rouge50,
    bordure: PaletteMaitre.rouge200,
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.sm,
      vertical: AppSpacing.xs,
    ),
    child: Text(
      message,
      style: styleTransverse(
        Tailles.t13,
        poids: FontWeight.w600,
        couleur: AppColors.erreur,
      ),
    ),
  ),
);

/// `block text-[13px] font-semibold text-slate-700 mb-1.5` + l'astérisque.
class ChampModaleComptabilite extends StatelessWidget {
  const ChampModaleComptabilite({
    required this.libelle,
    required this.child,
    this.aide,
    super.key,
  });

  final String libelle;
  final Widget child;
  final String? aide;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text.rich(
        TextSpan(
          children: [
            TextSpan(text: libelle),
            const TextSpan(
              text: ' *',
              style: TextStyle(color: PaletteMaitre.rouge500),
            ),
          ],
        ),
        style: styleTransverse(
          Tailles.t13,
          poids: FontWeight.w600,
          couleur: Ardoise.c700,
        ),
      ),
      const SizedBox(height: AppSpacing.xxs),
      child,
      if (aide != null) ...[
        const SizedBox(height: AppSpacing.xxs),
        Text(aide!, style: styleTransverse(Tailles.t11, couleur: Ardoise.c500)),
      ],
    ],
  );
}

InputDecoration decorationModaleComptabilite({String? invite}) {
  OutlineInputBorder bord(Color couleur) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadius.roundedMd),
    borderSide: BorderSide(color: couleur),
  );
  return InputDecoration(
    isDense: true,
    hintText: invite,
    hintStyle: styleTransverse(Tailles.t13, couleur: Ardoise.c400),
    counterText: '',
    contentPadding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.sm,
      vertical: AppSpacing.xsPlus,
    ),
    border: bord(Ardoise.c300),
    enabledBorder: bord(Ardoise.c300),
    disabledBorder: bord(Ardoise.c200),
    focusedBorder: bord(AppColors.navy),
  );
}

/* ====================================================================== */
/* Créer un compte                                                         */
/* ====================================================================== */

/// La modale « Créer un compte » (`etatFormulaire === 'compte'`) — le geste de
/// `PlanComptableService::creerCompte`, rejoué par [MoteurComptable.creerCompte]
/// du poste : numéro, intitulé, type ; la classe se DÉRIVE du numéro. Tout
/// refus du moteur est DIT dans la modale, à la phrase du serveur ; rien n'est
/// écrit sur un refus (une transaction).
class _ModaleCompte extends ConsumerStatefulWidget {
  const _ModaleCompte();

  @override
  ConsumerState<_ModaleCompte> createState() => _ModaleCompteState();
}

class _ModaleCompteState extends ConsumerState<_ModaleCompte> {
  final _numero = TextEditingController();
  final _intitule = TextEditingController();
  String? _nature;
  String? _erreur;
  bool _envoi = false;

  @override
  void dispose() {
    _numero.dispose();
    _intitule.dispose();
    super.dispose();
  }

  Future<void> _creer() async {
    setState(() {
      _envoi = true;
      _erreur = null;
    });
    final numero = _numero.text.trim();
    try {
      final moteur = await ref.read(moteurComptableProvider.future);
      await moteur.creerCompte(numero, _intitule.text, _nature ?? '');
    } on RefusComptable catch (e) {
      if (!mounted) return;
      setState(() {
        _envoi = false;
        _erreur = e.message;
      });
      return;
    } on Object {
      if (!mounted) return;
      setState(() {
        _envoi = false;
        _erreur = TextesModalesHubComptabilite.echecInattendu;
      });
      return;
    }
    ref
      ..invalidate(planComptableCompletProvider)
      ..invalidate(comptesImputablesProvider);
    if (mounted) {
      Navigator.of(
        context,
      ).pop(TextesModalesHubComptabilite.compteCree(numero));
    }
  }

  @override
  Widget build(BuildContext context) {
    final valeur = styleTransverse(Tailles.t13);
    const natures = [
      ('actif', TextesModalesHubComptabilite.natureActif),
      ('passif', TextesModalesHubComptabilite.naturePassif),
      ('charge', TextesModalesHubComptabilite.natureCharge),
      ('produit', TextesModalesHubComptabilite.natureProduit),
    ];
    return CadreModaleComptabilite(
      cle: const Key('modale-compte'),
      largeur: AppLayout.modaleCompte,
      titre: TextesModalesHubComptabilite.compteTitre,
      corps: [
        if (_erreur != null)
          refusModaleComptabilite(const Key('modale-compte-refus'), _erreur!),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ChampModaleComptabilite(
                libelle: TextesModalesHubComptabilite.champNumero,
                child: TextField(
                  key: const Key('modale-compte-numero'),
                  controller: _numero,
                  enabled: !_envoi,
                  maxLength: RegleNumeroCompte.chiffresMax,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: valeur.copyWith(
                    fontFamily: AppTextStyles.policeMonospace,
                  ),
                  decoration: decorationModaleComptabilite(
                    invite: TextesModalesHubComptabilite.champNumeroInvite,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              flex: 2,
              child: ChampModaleComptabilite(
                libelle: TextesModalesHubComptabilite.champIntitule,
                child: TextField(
                  key: const Key('modale-compte-intitule'),
                  controller: _intitule,
                  enabled: !_envoi,
                  style: valeur,
                  decoration: decorationModaleComptabilite(
                    invite: TextesModalesHubComptabilite.champIntituleInvite,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        ChampModaleComptabilite(
          libelle: TextesModalesHubComptabilite.champNature,
          aide: TextesModalesHubComptabilite.champNatureAide,
          child: DropdownButtonFormField<String>(
            key: const Key('modale-compte-nature'),
            initialValue: _nature,
            isExpanded: true,
            isDense: true,
            style: valeur,
            decoration: decorationModaleComptabilite(),
            hint: Text(TextesModalesHubComptabilite.choisir, style: valeur),
            items: [
              for (final (cle, libelle) in natures)
                DropdownMenuItem(
                  value: cle,
                  child: Text(libelle, style: valeur),
                ),
            ],
            onChanged: _envoi ? null : (v) => setState(() => _nature = v),
          ),
        ),
      ],
      pied: [
        BoutonStandard(
          key: const Key('modale-compte-annuler'),
          libelle: TextesModalesHubComptabilite.annuler,
          variante: VarianteBouton.fantome,
          onPressed: _envoi ? null : () => Navigator.of(context).pop(),
        ),
        BoutonStandard(
          key: const Key('modale-compte-creer'),
          libelle: TextesModalesHubComptabilite.compteTitre,
          variante: VarianteBouton.primaire,
          onPressed: _envoi ? null : _creer,
        ),
      ],
    );
  }
}

/* ====================================================================== */
/* Ouvrir un exercice                                                      */
/* ====================================================================== */

/// La modale « Ouvrir un exercice » (`etatFormulaire === 'exercice'`) —
/// `ExerciceComptableService::ouvrir`, rejoué par
/// [MoteurComptable.ouvrirExercice] : l'année entière, du 1er janvier au 31
/// décembre, rien d'autre (ni à-nouveaux, ni reprise de solde). L'année hors de
/// 2000–2100 et l'année déjà ouverte sont refusées aux mots du serveur.
class _ModaleExercice extends ConsumerStatefulWidget {
  const _ModaleExercice({required this.anneeInitiale});

  final int anneeInitiale;

  @override
  ConsumerState<_ModaleExercice> createState() => _ModaleExerciceState();
}

class _ModaleExerciceState extends ConsumerState<_ModaleExercice> {
  late final _annee = TextEditingController(text: '${widget.anneeInitiale}');
  String? _erreur;
  bool _envoi = false;

  @override
  void dispose() {
    _annee.dispose();
    super.dispose();
  }

  Future<void> _ouvrir() async {
    setState(() {
      _envoi = true;
      _erreur = null;
    });
    // Une saisie illisible vaut une année hors plage : le moteur la refuse à la
    // phrase du serveur (`exercice_annee_invalide`).
    final annee = int.tryParse(_annee.text.trim()) ?? 0;
    try {
      final moteur = await ref.read(moteurComptableProvider.future);
      await moteur.ouvrirExercice(annee);
    } on RefusComptable catch (e) {
      if (!mounted) return;
      setState(() {
        _envoi = false;
        _erreur = e.message;
      });
      return;
    } on Object {
      if (!mounted) return;
      setState(() {
        _envoi = false;
        _erreur = TextesModalesHubComptabilite.echecInattendu;
      });
      return;
    }
    // Le sélecteur, la liste des exercices et la saisie relisent la base.
    ref
      ..invalidate(donneesComptabiliteProvider)
      ..invalidate(donneesEtatsFinanciersProvider);
    if (mounted) {
      Navigator.of(
        context,
      ).pop(TextesModalesHubComptabilite.exerciceOuvert(annee));
    }
  }

  @override
  Widget build(BuildContext context) => CadreModaleComptabilite(
    cle: const Key('modale-exercice'),
    largeur: AppLayout.modaleExercice,
    titre: TextesModalesHubComptabilite.exerciceTitre,
    corps: [
      if (_erreur != null)
        refusModaleComptabilite(const Key('modale-exercice-refus'), _erreur!),
      ChampModaleComptabilite(
        libelle: TextesModalesHubComptabilite.exerciceAnnee,
        child: TextField(
          key: const Key('modale-exercice-annee'),
          controller: _annee,
          enabled: !_envoi,
          maxLength: 4,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: styleTransverse(Tailles.t13),
          decoration: decorationModaleComptabilite(),
        ),
      ),
    ],
    pied: [
      BoutonStandard(
        key: const Key('modale-exercice-annuler'),
        libelle: TextesModalesHubComptabilite.annuler,
        variante: VarianteBouton.fantome,
        onPressed: _envoi ? null : () => Navigator.of(context).pop(),
      ),
      BoutonStandard(
        key: const Key('modale-exercice-ouvrir'),
        libelle: TextesModalesHubComptabilite.exerciceValider,
        variante: VarianteBouton.primaire,
        onPressed: _envoi ? null : _ouvrir,
      ),
    ],
  );
}
