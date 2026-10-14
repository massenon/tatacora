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
/// ## ⚠ CE GESTE EST REFUSÉ SUR CE POSTE (14/09/2026), et le refus est le
/// livrable
///
/// Il écrivait une ligne `indisponibilites_carte` au serveur — motif,
/// commentaire, auteur, sous verrou. Le poste est zéro réseau, et
/// `cartes_boisson_local` n'a que **cinq colonnes** : `id`, `article_id`,
/// `libelle`, `categorie`, `prix_vente`. Il n'existe donc **aucun endroit** où
/// écrire un retrait, ni son motif, ni son commentaire.
///
/// Trois issues étaient possibles, et deux mentent :
///
///  1. **Le tenir en mémoire.** Le retrait disparaîtrait à la fermeture de la
///     fenêtre : le barman aurait retiré la Béninoise le matin et la verrait
///     revenir à midi, sans que personne ne sache s'il faut la racheter. C'est
///     précisément le défaut que la PWA a fermé, et il est pire que l'absence.
///  2. **L'encoder ailleurs** — un prix à zéro, un préfixe dans le libellé.
///     Le catalogue cesserait de dire ce qu'il dit, et le point de vente
///     afficherait un article renommé par un état.
///  3. **Le refuser en DISANT quelle colonne manque**, et garder les mots de la
///     vue à l'écran pour que la fonction reste identifiable le jour où elle
///     reviendra. C'est ce qui est fait.
///
/// Le formulaire n'est donc **pas** rendu : un motif et un commentaire saisis
/// puis jetés seraient « un formulaire dont les champs sont collectés puis
/// ignorés » (Article 6).
///
/// ⚠ **L'aide de la vue, elle, est rendue TELLE QUELLE** (l.95-97). Elle avait
/// d'abord été remplacée par une reformulation, et la garde
/// `conformite_blade_test` l'a refusée à juste titre : on ne reformule pas un
/// libellé du maître. Elle dit exactement ce qui manque ici — pourquoi le motif
/// d'un retrait doit être STOCKÉ.
///
/// ## En pratique, la carte n'ouvre déjà plus cette modale
///
/// `TableCarte` n'offre « Rendre indispo. » et « Remettre » que si le serveur a
/// dit l'état de la ligne ([LigneCarte.disponibiliteConnue]). Plus aucune
/// source ne le dit : les deux boutons ne s'affichent plus. La modale reste
/// branchée pour que le chemin soit **complet et nommé** plutôt que muet.
///
/// ## Un écart hérité de la vue, et il est de la vue
///
/// L'invite « Rechercher un motif… » du maître n'est pas rendue — la vue le
/// déclare elle-même (en-tête du composant, 31/08/2026) : trois motifs d'un
/// registre fermé ne se cherchent pas.
Future<bool?> ouvrirModaleRetraitCarte(
  BuildContext context,
  LigneCarte ligne,
) => showDialog<bool>(
  context: context,
  barrierDismissible: true,
  barrierColor: AppColors.voileModale,
  builder: (_) => _ModaleRetrait(ligne: ligne),
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

  /// Le bouton « Fermer » remplace « Annuler » : il n'y a rien à annuler.
  static const String fermer = 'Fermer';
}

/// L'option d'un motif — `{{ libelle }} — {{ temporaire ? … : … }}` (l.69).
///
/// Conservée bien que le sélecteur ne soit plus rendu : c'est la forme exacte
/// que l'écran devra reprendre le jour où la colonne existera, et elle reste
/// éprouvée par `motif_indisponibilite_test.dart`.
String libelleOptionMotif(MotifIndisponibilite m) =>
    '${m.libelle} — ${m.temporaire ? TextesRetraitCarte.temporaire : TextesRetraitCarte.definitif}';

class _ModaleRetrait extends ConsumerWidget {
  const _ModaleRetrait({required this.ligne});

  final LigneCarte ligne;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CoquilleModaleRestaurant(
      cle: const Key('modale-retrait-carte'),
      titre: TextesRetraitCarte.titre,
      // `:sousTitre="$nom"` (l.57).
      sousTitre: ligne.libelle,
      largeur: AppLayout.modaleRetraitCarte,
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Le motif du refus vient de `BoissonsApi`, qui le rend aussi à
          // « Remettre » : deux phrases voisines écrites à deux endroits
          // finiraient par donner deux causes pour une seule situation.
          const _Avertissement(
            cle: Key('retrait-carte-sans-colonne'),
            texte: TextesCatalogueLocal.retraitSansColonne,
          ),
          const SizedBox(height: AppSpacing.md),

          // ------------------------------------------------ l.95-97 : aide
          // `text-[11px] text-slate-500 bg-slate-50 border border-slate-200
          // rounded-lg p-2.5` ; « rupture » et « retrait » en gras.
          //
          // Les mots de la vue, au caractère près : c'est elle qui dit pourquoi
          // un motif se STOCKE, donc ce que la colonne absente portait.
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
        // Un seul bouton : il n'y a rien à confirmer, donc rien à annuler.
        // « Retirer », grisé, inviterait à cliquer pour ne produire qu'un refus.
        FilledButton(
          key: const Key('retrait-carte-fermer'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text(
            TextesRetraitCarte.fermer,
            style: TextesModaleRestaurant.bouton,
          ),
        ),
      ],
    );
  }
}

/// « Remettre » — le geste direct de la vue (l.407), sans modale.
///
/// Il est **refusé** pour la même raison que le retrait : il n'y a rien à
/// lever, puisqu'il n'y a nulle part où écrire un retrait. Le refus se DIT —
/// un silence laisserait croire que l'article vient de revenir à la carte.
Future<void> remettreALaCarte(
  BuildContext context,
  WidgetRef ref,
  LigneCarte ligne,
) async {
  final messager = ScaffoldMessenger.of(context);
  final resultat = await ref.read(remettreALaCarteProvider)(ligne.id);

  final texte = switch (resultat) {
    BarRecu<Boisson>(:final donnees) => TextesRetraitCarte.remis(
      donnees.libelle,
    ),
    BarRefuse<Boisson>(:final motif, :final erreurs) =>
      erreurs['etat'] ?? motif,
    // Inatteignable : l'écriture est locale. Le cas reste écrit parce que le
    // registre est FERMÉ.
    BarInjoignable<Boisson>() => TextesCatalogueLocal.retraitSansColonne,
  };

  messager.showSnackBar(
    SnackBar(content: Text(texte, key: const Key('remise-carte-issue'))),
  );
}

/// Ce que la modale dit du geste qu'elle ne peut pas porter.
class _Avertissement extends StatelessWidget {
  const _Avertissement({required this.cle, required this.texte});

  final Key cle;
  final String texte;

  @override
  Widget build(BuildContext context) => Container(
    key: cle,
    padding: const EdgeInsets.all(AppSpacing.sm),
    decoration: BoxDecoration(
      color: PaletteMaitre.ambre50,
      border: Border.all(color: PaletteMaitre.ambre200),
      borderRadius: BorderRadius.circular(AppRadius.roundedLg),
    ),
    child: Text(
      texte,
      style: TextesModaleRestaurant.corps.copyWith(
        color: PaletteMaitre.ambre900,
      ),
    ),
  );
}
