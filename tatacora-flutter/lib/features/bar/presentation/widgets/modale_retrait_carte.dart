// Vue Blade maîtresse (PA-183) : pwa/bar/carte.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../restaurant/presentation/widgets/coquille_modale_restaurant.dart';
import '../../../restaurant/presentation/widgets/textes_modale_restaurant.dart';
import '../../data/boissons_api.dart';
import '../../domain/entities/boisson.dart';
import '../../domain/entities/carte_bar.dart';
import '../../domain/motif_indisponibilite.dart';
import '../providers_bar.dart';

/// La modale **« Retirer de la carte du jour »** de la Carte du bar —
/// composant `modal-retirerdelacartedujour` inclus par le corps partagé des
/// cartes (l.776-778), ouvert par « Rendre indispo. » (l.403-405).
///
/// @see EF-M5-02 Carte des boissons
/// @see RG-15 La décision est imputée — `utilisateur_id` NOT NULL
///
/// ## Il écrit DANS LA BASE LOCALE depuis le 21/10/2026 (v31)
///
/// Motif du registre fermé, commentaire et instant sont écrits dans
/// `indisponibilites_carte_local` et mis en file ; le serveur fusionne si
/// l'article est déjà retiré, et les autres postes (comme la PWA) le voient
/// retiré. Il était refusé jusqu'alors, faute de table : la décision de
/// « ce que le web fait, le poste le fait » (PO, 21/10/2026) l'a créée.
///
/// ## Ce que la vue fait, et qui est tenu à l'identique
///
/// Le titre, le sous-titre (le nom de l'article), « Motif » (obligatoire, une
/// option par motif, avec sa nature), « Commentaire », l'aide au caractère
/// près, « Annuler » puis « Retirer ». Un seul écart reste, celui de la vue
/// elle-même : l'invite « Rechercher un motif… » n'est pas rendue — trois
/// motifs d'un registre fermé ne se cherchent pas.
///
Future<bool?> ouvrirModaleRetraitCarte(
  BuildContext context,
  WidgetRef ref,
  LigneCarte ligne,
) => ouvrirModaleRetraitArticle(
  context,
  libelle: ligne.libelle,
  soumettre: (motif, commentaire) async {
    final r = await ref.read(retirerDeLaCarteProvider)(
      id: ligne.id,
      motif: motif,
      commentaire: commentaire,
    );
    return switch (r) {
      BarRecu<Boisson>(:final donnees) => BarRecu(donnees.libelle),
      BarRefuse<Boisson>(:final motif, :final erreurs, :final code) =>
        BarRefuse(motif: motif, erreurs: erreurs, code: code),
      BarInjoignable<Boisson>() => const BarInjoignable(),
    };
  },
);

/// La même modale pour un article quelconque de la carte du jour (boisson ou
/// plat) : [soumettre] écrit le retrait et rend le libellé de l'article.
Future<bool?> ouvrirModaleRetraitArticle(
  BuildContext context, {
  required String libelle,
  required Future<ResultatBar<String>> Function(
    String motif,
    String? commentaire,
  )
  soumettre,
}) => showDialog<bool>(
  context: context,
  barrierDismissible: true,
  barrierColor: AppColors.voileModale,
  builder: (_) => _ModaleRetrait(libelle: libelle, soumettre: soumettre),
);

/// Les messages de la modale et du geste « Remettre » — un seul endroit pour
/// l'écran et les essais.
abstract final class TextesRetraitCarte {
  // Les mots de la vue — `lang/fr/carte_pwa.php`, `commun` et `modale_dispo`.
  static const String boutonRetirer = 'Rendre indispo.';
  static const String boutonRemettre = 'Remettre';
  static const String titre = 'Retirer de la carte du jour';
  static const String champMotif = 'Motif';
  static const String champCommentaire = 'Commentaire';
  static const String inviteCommentaire = 'Ex. livraison attendue jeudi';
  static const String temporaire = 'revient au réapprovisionnement';
  static const String definitif = 'décision commerciale';
  static const String annuler = 'Annuler';
  static const String confirmer = 'Retirer';
  static String retire(String article) =>
      '« $article » retiré de la carte du jour.';
  static String remis(String article) =>
      '« $article » est de nouveau à la carte.';

  /// Issue inatteignable (l'écriture est locale), dite quand même.
  static const String illisible =
      'Le retrait n’a pas pu être enregistré sur ce poste.';
}

/// L'option d'un motif — `{{ libelle }} — {{ temporaire ? … : … }}` (l.69).
///
/// Éprouvée par `motif_indisponibilite_test.dart`.
String libelleOptionMotif(MotifIndisponibilite m) =>
    '${m.libelle} — ${m.temporaire ? TextesRetraitCarte.temporaire : TextesRetraitCarte.definitif}';

class _ModaleRetrait extends StatefulWidget {
  const _ModaleRetrait({required this.libelle, required this.soumettre});

  final String libelle;
  final Future<ResultatBar<String>> Function(String motif, String? commentaire)
  soumettre;

  @override
  State<_ModaleRetrait> createState() => _ModaleRetraitState();
}

class _ModaleRetraitState extends State<_ModaleRetrait> {
  final _commentaire = TextEditingController();

  // Le premier motif du registre, comme la vue (`motifIndisponibilite`).
  MotifIndisponibilite _motif = MotifIndisponibilite.values.first;

  bool _envoi = false;
  String? _refus;
  Map<String, String> _parChamp = const {};

  @override
  void dispose() {
    _commentaire.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CoquilleModaleRestaurant(
      cle: const Key('modale-retrait-carte'),
      titre: TextesRetraitCarte.titre,
      // `:sousTitre="$nom"` (l.57).
      sousTitre: widget.libelle,
      largeur: AppLayout.modaleRetraitCarte,
      refus: _refus,
      cleRefus: const Key('retrait-carte-refus'),
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ----------------------------------------------- Motif (l.78-91)
          const EtiquetteChampRestaurant(
            texte: TextesRetraitCarte.champMotif,
            obligatoire: true,
          ),
          DropdownButtonFormField<MotifIndisponibilite>(
            key: const Key('retrait-carte-motif'),
            initialValue: _motif,
            isExpanded: true,
            style: TextesModaleRestaurant.corps,
            decoration: InputDecoration(
              isDense: true,
              border: const OutlineInputBorder(),
              errorText: _parChamp['motif'],
              errorMaxLines: 3,
            ),
            items: [
              for (final m in MotifIndisponibilite.values)
                DropdownMenuItem(value: m, child: Text(libelleOptionMotif(m))),
            ],
            onChanged: _envoi
                ? null
                : (m) {
                    if (m != null) setState(() => _motif = m);
                  },
          ),
          const SizedBox(height: AppSpacing.sm),

          // ------------------------------------------- Commentaire (l.93-103)
          const EtiquetteChampRestaurant(
            texte: TextesRetraitCarte.champCommentaire,
          ),
          TextField(
            key: const Key('retrait-carte-commentaire'),
            controller: _commentaire,
            style: TextesModaleRestaurant.corps,
            decoration: InputDecoration(
              isDense: true,
              border: const OutlineInputBorder(),
              hintText: TextesRetraitCarte.inviteCommentaire,
              errorText: _parChamp['commentaire'],
              errorMaxLines: 3,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          // ------------------------------------------------ l.95-97 : aide
          // `text-[11px] text-slate-500 bg-slate-50 border border-slate-200
          // rounded-lg p-2.5` ; « rupture » et « retrait » en gras.
          Container(
            key: const Key('retrait-carte-aide'),
            padding: const EdgeInsets.all(AppSpacing.xs),
            decoration: BoxDecoration(
              color: Ardoise.c50,
              border: Border.all(color: Ardoise.c200),
              borderRadius: BorderRadius.circular(AppRadius.roundedLg),
            ),
            child: const Text.rich(
              TextSpan(
                style: TextesModaleRestaurant.aide,
                children: [
                  TextSpan(text: 'Une '),
                  TextSpan(
                    text: 'rupture',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  // Sur UNE ligne : apostrophes droites de la vue, et le
                  // comparateur ne recolle que des littéraux de même guillemet.
                  TextSpan(
                    text: " revient d'elle-même au réapprovisionnement ; un ",
                  ),
                  TextSpan(
                    text: 'retrait',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(
                    text:
                        " est une décision commerciale. Les confondre ferait disparaître un plat sans que personne ne sache s'il faut le racheter.",
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('retrait-carte-annuler'),
          onPressed: _envoi ? null : () => Navigator.of(context).pop(false),
          child: const Text(
            TextesRetraitCarte.annuler,
            style: TextesModaleRestaurant.bouton,
          ),
        ),
        FilledButton(
          key: const Key('retrait-carte-confirmer'),
          onPressed: _envoi ? null : _retirer,
          child: const Text(
            TextesRetraitCarte.confirmer,
            style: TextesModaleRestaurant.bouton,
          ),
        ),
      ],
    );
  }

  Future<void> _retirer() async {
    setState(() {
      _envoi = true;
      _refus = null;
      _parChamp = const {};
    });

    final resultat = await widget.soumettre(_motif.code, _commentaire.text);
    if (!mounted) return;

    switch (resultat) {
      case BarRecu<String>(:final donnees):
        final messager = ScaffoldMessenger.of(context);
        Navigator.of(context).pop(true);
        messager.showSnackBar(
          SnackBar(
            content: Text(
              TextesRetraitCarte.retire(donnees),
              key: const Key('retrait-carte-issue'),
            ),
          ),
        );
      case BarRefuse<String>(:final motif, :final erreurs):
        setState(() {
          _envoi = false;
          _refus = erreurs['etat'] ?? motif;
          _parChamp = erreurs;
        });
      // Inatteignable : l'écriture est locale. Le cas reste écrit parce que le
      // registre est FERMÉ.
      case BarInjoignable<String>():
        setState(() {
          _envoi = false;
          _refus = TextesRetraitCarte.illisible;
        });
    }
  }
}

/// « Remettre » — le geste direct de la vue (l.407), sans modale.
///
/// Il ferme le retrait en cours (v31). Quand rien n'est retiré — remis entre
/// temps depuis un autre poste —, le refus se DIT : un silence laisserait
/// croire que l'article vient de revenir à la carte.
Future<void> remettreALaCarte(
  BuildContext context,
  WidgetRef ref,
  LigneCarte ligne,
) => remettreArticle(context, () async {
  final r = await ref.read(remettreALaCarteProvider)(ligne.id);
  return switch (r) {
    BarRecu<Boisson>(:final donnees) => BarRecu(donnees.libelle),
    BarRefuse<Boisson>(:final motif, :final erreurs, :final code) => BarRefuse(
      motif: motif,
      erreurs: erreurs,
      code: code,
    ),
    BarInjoignable<Boisson>() => const BarInjoignable(),
  };
});

/// « Remettre » pour un article quelconque : [remettre] ferme le retrait et rend
/// le libellé. Le refus se DIT dans tous les cas.
Future<void> remettreArticle(
  BuildContext context,
  Future<ResultatBar<String>> Function() remettre,
) async {
  final messager = ScaffoldMessenger.of(context);
  final resultat = await remettre();

  final texte = switch (resultat) {
    BarRecu<String>(:final donnees) => TextesRetraitCarte.remis(donnees),
    BarRefuse<String>(:final motif, :final erreurs) => erreurs['etat'] ?? motif,
    // Inatteignable : l'écriture est locale. Le cas reste écrit parce que le
    // registre est FERMÉ.
    BarInjoignable<String>() => TextesRetraitCarte.illisible,
  };

  messager.showSnackBar(
    SnackBar(content: Text(texte, key: const Key('remise-carte-issue'))),
  );
}
