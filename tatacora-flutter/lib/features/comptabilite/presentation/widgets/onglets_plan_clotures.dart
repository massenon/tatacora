import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/format/formats.dart';
import '../../../../core/rbac/garde_acces.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/mesures_transverses.dart';
import '../../../transverse/presentation/widgets/briques_transverses.dart';
import '../../domain/entities/comptabilite.dart';
import '../providers_consultation_comptable.dart';
import 'modales_hub_comptabilite.dart';

/// Onglets « Plan comptable » et « Clôtures » du hub Comptabilité, aux
/// affordances de la vue : le bouton « + Créer un compte » (et sa recherche)
/// et le bouton « Ouvrir un exercice » (et la liste des exercices).
///
/// Vue Blade maîtresse (PA-183) : pwa/comptabilite/onglets/plan.blade.php et
/// pwa/comptabilite/onglets/clotures.blade.php.
///
/// ## Écarts, nommés
///
/// - **Plan** : l'encadré ambre de la vue (« Socle d'exploitation, pas le plan
///   officiel intégral… ») dit du plan du SERVEUR ce que le plan de ce poste
///   n'est pas — il porte le fichier du PO, SYSCOHADA révisé en entier. Le
///   rendre dirait une chose fausse : il n'est pas posé.
/// - **Clôtures** : la colonne « Résultat reporté » porte un tiret partout (la
///   vue ne calcule que pour l'exercice consulté, par `EtatClotureService`,
///   que ce poste ne tient pas) ; la clôture annuelle, l'archive légale et les
///   trois cartes (résultat à reporter, blocages, avertissements) ne sont pas
///   portées, et l'onglet le DIT.
/// - Le compte créé et l'exercice ouvert ici restent sur ce poste : ni l'un
///   ni l'autre n'est envoyé au serveur (aucune table du registre de
///   synchronisation ne les porte), les messages de succès le disent.
abstract final class TextesOngletsPlanClotures {
  static const String planRecherche =
      'Rechercher un compte (numéro ou libellé)';
  static const String creerCompte = 'Créer un compte';
  static const String planAucun = 'Aucun compte ne correspond.';
  static const String colCompte = 'Compte';
  static const String colIntitule = 'Intitulé';
  static const String colType = 'Type';
  static const String tiret = '—';

  /// `$classesLibelle` de la vue.
  static const Map<String, String> classes = {
    '1': 'Capitaux',
    '2': 'Immobilisations',
    '3': 'Stocks',
    '4': 'Tiers',
    '5': 'Trésorerie',
    '6': 'Charges',
    '7': 'Produits',
    '8': 'Hors activités ordinaires',
    '9': 'Analytique',
  };
  static String titreClasse(String classe) =>
      'Classe $classe — ${classes[classe] ?? ''}';

  static const String exercicesTitre = 'Exercices comptables';
  static const String ouvrirExercice = 'Ouvrir un exercice';
  static const String colExercice = 'Exercice';
  static const String colDebut = 'Début';
  static const String colFin = 'Fin';
  static const String colStatut = 'Statut';
  static const String colResultatReporte = 'Résultat reporté';
  static const String colClotureLe = 'Clôturé le';
  static const String statutOuvert = 'Ouvert';
  static const String statutEnCloture = 'En clôture';
  static const String statutCloture = 'Clôturé';

  static const String sansDroit =
      "Votre profil n'a pas le droit de modifier la comptabilité.";
  static const String illisible =
      "Le plan comptable de ce poste n'a pas pu être lu.";
}

/// `AAAA-MM-JJ` -> `d/m/Y` (`->format('d/m/Y')` de la vue).
String _dateCourte(String iso) {
  final d = DateTime.tryParse(iso);
  return d == null ? iso : formaterDate(d);
}

/// Onglet « Plan comptable » : un tableau PAR CLASSE, filtré par la recherche
/// (numéro ou libellé), et « + Créer un compte ».
class OngletPlan extends ConsumerStatefulWidget {
  const OngletPlan({super.key});

  @override
  ConsumerState<OngletPlan> createState() => _OngletPlanState();
}

class _OngletPlanState extends ConsumerState<OngletPlan> {
  String _recherche = '';

  @override
  Widget build(BuildContext context) {
    final lu = ref.watch(planComptableCompletProvider);
    if (lu.hasError) {
      return Text(
        TextesOngletsPlanClotures.illisible,
        key: const Key('compta-plan-illisible'),
        style: styleTransverse(TaillesContenu.t13, couleur: AppColors.erreur),
      );
    }
    final q = _recherche.trim().toLowerCase();
    final comptes = [
      for (final c in lu.value ?? const <CompteDuPlan>[])
        if (q.isEmpty ||
            c.numero.toLowerCase().contains(q) ||
            c.libelle.toLowerCase().contains(q))
          c,
    ];
    final parClasse = <String, List<CompteDuPlan>>{};
    for (final c in comptes) {
      (parClasse[c.classe] ??= []).add(c);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppLayout.rechercheOngletComptable,
              ),
              child: TextField(
                key: const Key('compta-plan-recherche'),
                onChanged: (v) => setState(() => _recherche = v),
                style: styleTransverse(TaillesContenu.t13),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: TextesOngletsPlanClotures.planRecherche,
                  hintStyle: styleTransverse(
                    TaillesContenu.t13,
                    couleur: Ardoise.c400,
                  ),
                  prefixIcon: const Icon(
                    Icons.search,
                    size: AppLayout.iconeChamp,
                    color: Ardoise.c400,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.roundedMd),
                    borderSide: const BorderSide(color: Ardoise.c200),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.roundedMd),
                    borderSide: const BorderSide(color: Ardoise.c200),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.roundedMd),
                    borderSide: const BorderSide(color: AppColors.navy),
                  ),
                ),
              ),
            ),
            BoutonTransverse(
              cle: const Key('compta-creer-compte'),
              libelle: '+ ${TextesOngletsPlanClotures.creerCompte}',
              fond: AppColors.navy,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xsPlus,
              ),
              onTap: () =>
                  ref
                      .read(droitsProvider)
                      .peutEcrire(ModuleTatacora.m10Comptabilite)
                  ? ouvrirModaleCompte(context)
                  : direTransverse(
                      context,
                      TextesOngletsPlanClotures.sansDroit,
                      cle: const Key('compta-plan-sans-droit'),
                    ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (comptes.isEmpty && lu.hasValue)
          CarteTransverse(
            padding: const EdgeInsets.symmetric(
              vertical: AppSpacingLarge.p14,
              horizontal: AppSpacing.mdPlus,
            ),
            child: Text(
              TextesOngletsPlanClotures.planAucun,
              key: const Key('compta-plan-aucun'),
              textAlign: TextAlign.center,
              style: styleTransverse(TaillesContenu.t13, couleur: Ardoise.c400),
            ),
          ),
        for (final classe in parClasse.keys.toList()..sort())
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: CarteTransverse(
              key: Key('compta-plan-classe-$classe'),
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.smPlus,
                    ),
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: Ardoise.c200)),
                    ),
                    child: Text(
                      TextesOngletsPlanClotures.titreClasse(classe),
                      style: styleTransverse(
                        TaillesContenu.t14,
                        poids: FontWeight.bold,
                        couleur: AppColors.navy,
                      ),
                    ),
                  ),
                  TableauTransverse(
                    largeurs: const {
                      1: MesuresTransverses.colonneLibelleCompta,
                    },
                    colonnes: const [
                      (
                        titre: TextesOngletsPlanClotures.colCompte,
                        alignement: TextAlign.left,
                      ),
                      (
                        titre: TextesOngletsPlanClotures.colIntitule,
                        alignement: TextAlign.left,
                      ),
                      (
                        titre: TextesOngletsPlanClotures.colType,
                        alignement: TextAlign.right,
                      ),
                    ],
                    vide: TextesOngletsPlanClotures.planAucun,
                    lignes: [
                      for (final c in parClasse[classe]!)
                        [
                          celluleTexte(
                            c.numero,
                            mono: true,
                            poids: FontWeight.w600,
                            couleur: AppColors.navy,
                          ),
                          celluleTexte(c.libelle, couleur: Ardoise.c700),
                          celluleTexte(
                            c.nature ?? TextesOngletsPlanClotures.tiret,
                            alignement: TextAlign.right,
                            taille: TaillesContenu.t12,
                            couleur: Ardoise.c500,
                          ),
                        ],
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Onglet « Clôtures » : « Exercices comptables » et « Ouvrir un exercice ».
class OngletClotures extends ConsumerWidget {
  const OngletClotures({required this.exercices, super.key});

  /// Les exercices du poste (le plus récent d'abord, comme `$tousExercices`).
  final List<ExerciceComptable> exercices;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tries = [...exercices]..sort((a, b) => b.annee.compareTo(a.annee));
    final proposee = tries.isEmpty
        ? DateTime.now().year
        : tries.first.annee + 1;

    Widget pastille(StatutExercice s) {
      final (fond, texte, libelle) = switch (s) {
        StatutExercice.ouvert => (
          PaletteMaitre.emeraude50,
          PaletteMaitre.emeraude700,
          TextesOngletsPlanClotures.statutOuvert,
        ),
        StatutExercice.enCloture => (
          PaletteMaitre.ambre50,
          PaletteMaitre.ambre700,
          TextesOngletsPlanClotures.statutEnCloture,
        ),
        StatutExercice.cloture => (
          Ardoise.c100,
          Ardoise.c600,
          TextesOngletsPlanClotures.statutCloture,
        ),
      };
      return Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xxs,
          vertical: AppSpacing.demi,
        ),
        decoration: BoxDecoration(
          color: fond,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Text(
          libelle,
          style: styleTransverse(TaillesContenu.t11, couleur: texte),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CarteTransverse(
          key: const Key('compta-exercices'),
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.smPlus,
                ),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Ardoise.c200)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        TextesOngletsPlanClotures.exercicesTitre,
                        style: styleTransverse(
                          TaillesContenu.t14,
                          poids: FontWeight.bold,
                          couleur: AppColors.navy,
                        ),
                      ),
                    ),
                    BoutonTransverse(
                      cle: const Key('compta-ouvrir-exercice'),
                      libelle: TextesOngletsPlanClotures.ouvrirExercice,
                      taille: TaillesContenu.t12,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.smPlus,
                        vertical: AppSpacing.xxs,
                      ),
                      onTap: () =>
                          ref
                              .read(droitsProvider)
                              .peutEcrire(ModuleTatacora.m10Comptabilite)
                          ? ouvrirModaleExercice(
                              context,
                              anneeInitiale: proposee,
                            )
                          : direTransverse(
                              context,
                              TextesOngletsPlanClotures.sansDroit,
                              cle: const Key('compta-exercice-sans-droit'),
                            ),
                    ),
                  ],
                ),
              ),
              TableauTransverse(
                colonnes: const [
                  (
                    titre: TextesOngletsPlanClotures.colExercice,
                    alignement: TextAlign.left,
                  ),
                  (
                    titre: TextesOngletsPlanClotures.colDebut,
                    alignement: TextAlign.right,
                  ),
                  (
                    titre: TextesOngletsPlanClotures.colFin,
                    alignement: TextAlign.right,
                  ),
                  (
                    titre: TextesOngletsPlanClotures.colStatut,
                    alignement: TextAlign.right,
                  ),
                  (
                    titre: TextesOngletsPlanClotures.colResultatReporte,
                    alignement: TextAlign.right,
                  ),
                  (
                    titre: TextesOngletsPlanClotures.colClotureLe,
                    alignement: TextAlign.right,
                  ),
                ],
                vide: TextesOngletsPlanClotures.tiret,
                lignes: [
                  for (final e in tries)
                    [
                      celluleTexte(
                        '${e.annee}',
                        poids: FontWeight.bold,
                        couleur: AppColors.navy,
                      ),
                      celluleTexte(
                        _dateCourte(e.dateDebut),
                        alignement: TextAlign.right,
                      ),
                      celluleTexte(
                        _dateCourte(e.dateFin),
                        alignement: TextAlign.right,
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: pastille(e.statut),
                      ),
                      celluleTexte(
                        TextesOngletsPlanClotures.tiret,
                        alignement: TextAlign.right,
                        poids: FontWeight.w600,
                      ),
                      celluleTexte(
                        e.dateCloture == null
                            ? TextesOngletsPlanClotures.tiret
                            : formaterDate(e.dateCloture!),
                        alignement: TextAlign.right,
                        taille: TaillesContenu.t12,
                        couleur: Ardoise.c500,
                      ),
                    ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
