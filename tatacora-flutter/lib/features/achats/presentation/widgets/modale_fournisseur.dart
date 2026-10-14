// Vue Blade maîtresse (PA-183) : pwa/achats/achats.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../restaurant/presentation/widgets/coquille_modale_restaurant.dart';
import '../../../restaurant/presentation/widgets/textes_modale_restaurant.dart';
import '../../data/achats_api.dart';
import '../../domain/entities/fournisseur.dart';
import '../providers_achats.dart';

/// La modale **« Nouveau fournisseur » / « Modifier le fournisseur »** —
/// `pwa/achats/achats.blade.php` l.425-498.
///
/// Cinq champs, dans l'ordre de la vue : raison sociale, contact, catégorie
/// fournie, conditions de paiement, évaluation. L'étiquette est AU-DESSUS du
/// champ (`block text-[13px] font-semibold text-slate-700 mb-1.5`), le pied
/// porte « Annuler » puis « Enregistrer ».
///
/// ## Un seul champ est obligatoire
///
/// Le serveur n'exige que `raison_sociale` ; les quatre autres sont
/// `sometimes|nullable`, et `EnregistrerFournisseurRequest` explique pourquoi
/// pour deux d'entre eux : fermer le registre rendrait **inmodifiable** tout
/// fournisseur déjà enregistré hors des listes. Les exiger ici obligerait à
/// attribuer une évaluation à un fournisseur que personne n'a noté.
///
/// ## `null` n'est pas « À revoir »
///
/// `FournisseurResource` le dit : `null` veut dire « pas encore évalué ». Le
/// sélecteur garde donc une entrée « Non renseigné » distincte des quatre
/// notes — c'est aussi le mot de la vue (l.449, 466, 483).
///
/// ## La valeur déjà portée par la fiche reste sélectionnable
///
/// Sans cette union, rouvrir la fiche d'un fournisseur dont la catégorie a été
/// créée au bureau la remplacerait **en silence** par la première de la liste —
/// un `PUT` qui écrase une donnée que personne n'a voulu changer (vue l.453-458
/// et l.470-472, même précaution).
///
/// ## Ce que cette fenêtre a perdu le 09/10/2026
///
/// Un pavé « Écarts assumés avec le prototype » et une aide sous l'évaluation
/// y figuraient. La vue n'en pose aucun, et leur propos était devenu FAUX :
/// ils affirmaient qu'aucun bouton « Désactiver » ne pouvait exister faute de
/// colonne `actif`, alors que cette colonne existe depuis le 03/09/2026 et
/// que « Supprimer » archive (`pwa/achats/achats.blade.php` l.257-267). Un
/// motif périmé transforme une décision en oubli (PA-107, PA-120, PA-144).
Future<Fournisseur?> ouvrirModaleFournisseur(
  BuildContext context, {
  Fournisseur? fournisseur,
}) {
  return showDialog<Fournisseur>(
    context: context,
    barrierDismissible: true,
    barrierColor: AppColors.voileModale,
    builder: (_) => _ModaleFournisseur(fournisseur: fournisseur),
  );
}

class _ModaleFournisseur extends ConsumerStatefulWidget {
  const _ModaleFournisseur({required this.fournisseur});

  final Fournisseur? fournisseur;

  @override
  ConsumerState<_ModaleFournisseur> createState() => _ModaleFournisseurState();
}

class _ModaleFournisseurState extends ConsumerState<_ModaleFournisseur> {
  final _formulaire = GlobalKey<FormState>();
  final _raisonSociale = TextEditingController();
  final _contact = TextEditingController();

  String? _categorie;
  String? _conditions;
  String? _evaluation;

  /// L'UUID est posé **une fois**, à l'ouverture, et ne change pas entre deux
  /// tentatives. C'est ce qui fait qu'un second envoi après une liaison tombée
  /// est refusé par le serveur (`unique`) au lieu de créer un doublon au
  /// référentiel — le cas normal au Gîte.
  late final String _id;

  bool _envoiEnCours = false;
  String? _refus;
  Map<String, String> _erreursServeur = const {};

  bool get _modification => widget.fournisseur != null;

  @override
  void initState() {
    super.initState();
    final f = widget.fournisseur;
    _id = f?.id ?? const Uuid().v4();
    _raisonSociale.text = f?.raisonSociale ?? '';
    _contact.text = f?.contact ?? '';
    _categorie = f?.categorie;
    _conditions = f?.conditionsPaiement;
    _evaluation = f?.evaluationCode;
  }

  @override
  void dispose() {
    _raisonSociale.dispose();
    _contact.dispose();
    super.dispose();
  }

  /// Les listes de la vue, plus la valeur déjà portée par la fiche.
  List<String> _options(List<String> maitre, String? actuelle) {
    final vues = {
      ...maitre,
      if (actuelle != null && actuelle.isNotEmpty) actuelle,
    };
    return vues.toList(growable: false);
  }

  Future<void> _enregistrer() async {
    if (!(_formulaire.currentState?.validate() ?? false)) return;

    setState(() {
      _envoiEnCours = true;
      _refus = null;
      _erreursServeur = const {};
    });

    final resultat = await ref
        .read(achatsApiProvider)
        .enregistrerFournisseur(
          SaisieFournisseur(
            id: _id,
            raisonSociale: _raisonSociale.text.trim(),
            // Chaîne vide ramenée à `null` : « pas de contact » n'est pas
            // « un contact dont le nom est vide », et le schéma distingue les
            // deux.
            contact: _vide(_contact.text),
            categorie: _categorie,
            conditionsPaiement: _conditions,
            evaluationCode: _evaluation,
          ),
          modification: _modification,
        );

    if (!mounted) return;

    switch (resultat) {
      case AchatsRecu(:final donnees):
        Navigator.of(context).pop(donnees);
      case AchatsRefuse(:final motif, :final erreurs):
        setState(() {
          _envoiEnCours = false;
          _refus = motif;
          _erreursServeur = erreurs;
        });
      case AchatsInjoignable():
        setState(() {
          _envoiEnCours = false;
          // Jamais produite (la base est locale) ; le type la garde. Aucune
          // file n'emporterait cette écriture : annoncer une mise en attente
          // décrirait une attente sans fin.
          _refus =
              'La base du poste n’a pas répondu : rien n’a été enregistré.';
        });
    }
  }

  /// `w-full rounded-lg px-3 py-2.5 text-[13px] border border-slate-300`.
  InputDecoration _decoration({String? hint, String? erreur}) {
    final bordure = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      borderSide: const BorderSide(color: Ardoise.c300),
    );
    return InputDecoration(
      isDense: true,
      hintText: hint,
      hintStyle: _texteChamp.copyWith(color: Ardoise.c400),
      errorText: erreur,
      errorStyle: const TextStyle(
        fontFamily: AppTextStyles.police,
        fontSize: Tailles.t12,
        color: AppColors.erreur,
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm, // px-3
        vertical: AppLayout.champBordeVertical, // py-2.5 + le filet de 1 px
      ),
      border: bordure,
      enabledBorder: bordure,
      focusedBorder: bordure.copyWith(
        borderSide: const BorderSide(color: AppColors.gold),
      ),
    );
  }

  static const TextStyle _texteChamp = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: Tailles.t13,
    color: AppColors.anthracite,
  );

  Widget _bloc(String etiquette, Widget champ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      EtiquetteChampRestaurant(texte: etiquette),
      champ,
    ],
  );

  /// Un `<select>` de la vue : « Non renseigné », puis les choix.
  Widget _liste({
    required Key cle,
    required String? valeur,
    required List<String> options,
    required String? erreur,
    required ValueChanged<String?> onChoix,
    String Function(String)? libelle,
  }) {
    return DropdownButtonFormField<String?>(
      key: cle,
      initialValue: valeur,
      isExpanded: true,
      style: _texteChamp,
      decoration: _decoration(erreur: erreur),
      items: [
        const DropdownMenuItem<String?>(child: Text('Non renseigné')),
        for (final o in options)
          DropdownMenuItem<String?>(
            value: o,
            child: Text(libelle == null ? o : libelle(o)),
          ),
      ],
      onChanged: onChoix,
    );
  }

  @override
  Widget build(BuildContext context) {
    final evaluations = [for (final e in EvaluationFournisseur.values) e.code];

    return CoquilleModaleRestaurant(
      cle: const Key('modale-fournisseur'),
      titre: _modification ? 'Modifier le fournisseur' : 'Nouveau fournisseur',
      sousTitre:
          "Le fournisseur est une vraie clé étrangère des commandes d'achat : il se choisit dans cette liste, il ne se saisit jamais en texte libre.",
      largeur: AppLayout.modaleFournisseurAchats,
      refus: _refus,
      cleRefus: const Key('fournisseur-refus'),
      corps: Form(
        key: _formulaire,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _bloc(
              'Raison sociale',
              TextFormField(
                key: const Key('fournisseur-raison-sociale'),
                controller: _raisonSociale,
                autofocus: true,
                style: _texteChamp,
                decoration: _decoration(
                  // Le placeholder de la vue (l.433), au mot.
                  hint: 'Ex. Grand Marché Natitingou SARL',
                  erreur: _erreursServeur['raison_sociale'],
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'La raison sociale est obligatoire.'
                    : null,
              ),
            ),
            const SizedBox(height: AppSpacing.md), // space-y-4
            _bloc(
              'Contact (téléphone)',
              TextFormField(
                key: const Key('fournisseur-contact'),
                controller: _contact,
                keyboardType: TextInputType.phone,
                style: _texteChamp,
                decoration: _decoration(
                  hint: '01 90 12 34 56',
                  erreur: _erreursServeur['contact'],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _bloc(
              'Catégorie fournie',
              _liste(
                cle: const Key('fournisseur-categorie'),
                valeur: _categorie,
                options: _options(
                  categoriesFournisseurMaitre,
                  widget.fournisseur?.categorie,
                ),
                erreur: _erreursServeur['categorie'],
                onChoix: (v) => setState(() => _categorie = v),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _bloc(
              'Conditions de paiement',
              _liste(
                cle: const Key('fournisseur-conditions'),
                valeur: _conditions,
                options: _options(
                  conditionsPaiementMaitre,
                  widget.fournisseur?.conditionsPaiement,
                ),
                erreur: _erreursServeur['conditions_paiement'],
                onChoix: (v) => setState(() => _conditions = v),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _bloc(
              'Évaluation',
              _liste(
                cle: const Key('fournisseur-evaluation'),
                valeur: _evaluation,
                // « Non renseigné » n'est PAS « À revoir » : les confondre
                // reprocherait à un fournisseur neuf une note que personne ne
                // lui a donnée.
                // Un code que ce client ne connaît pas reste sélectionnable :
                // un `DropdownButtonFormField` dont la valeur n'est pas parmi
                // ses choix lève, et l'écrasement serait silencieux.
                options: _options(
                  evaluations,
                  widget.fournisseur?.evaluationCode,
                ),
                erreur: _erreursServeur['evaluation'],
                libelle: (code) =>
                    EvaluationFournisseur.depuisCode(code)?.libelle ?? code,
                onChoix: (v) => setState(() => _evaluation = v),
              ),
            ),
          ],
        ),
      ),
      actions: [
        OutlinedButton(
          key: const Key('fournisseur-annuler'),
          onPressed: _envoiEnCours ? null : () => Navigator.of(context).pop(),
          child: const Text('Annuler', style: TextesModaleRestaurant.bouton),
        ),
        // Pendant l'envoi le bouton est DÉSACTIVÉ, pas seulement occupé : un
        // second clic créerait un second fournisseur.
        FilledButton(
          key: const Key('fournisseur-enregistrer'),
          onPressed: _envoiEnCours ? null : _enregistrer,
          child: const Text(
            'Enregistrer',
            style: TextesModaleRestaurant.bouton,
          ),
        ),
      ],
    );
  }

  static String? _vide(String texte) {
    final t = texte.trim();
    return t.isEmpty ? null : t;
  }
}
