// Vue Blade maîtresse (PA-183) : pwa/comptabilite/hub.blade.php
// (l'onglet « Immobilisations » : `onglets/immo.blade.php`).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/rbac/garde_acces.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/mesures_transverses.dart';
import '../../../transverse/presentation/widgets/briques_transverses.dart';
import '../../domain/immobilisations.dart';
import '../providers_immobilisations.dart';
import 'modales_immobilisations.dart';

/// Les mots de l'onglet — `lang/fr/comptabilite_pwa.php` (`immo_*`, `col_*`).
abstract final class TextesOngletImmobilisations {
  static const String dureeTitre =
      'Durée d’utilité : une estimation de l’entité, jamais un défaut.';
  static const String dureeDetail =
      'Sous SYSCOHADA révisé, la durée d’utilité relève de l’entité (AUDCIF art. 45) et non d’un barème. Elle est donc obligatoire à la saisie et sans valeur pré-remplie. Amortissement linéaire, prorata temporis de la première annuité en mois entamés.';
  static const String recherche =
      'Rechercher une immobilisation (code ou libellé)';
  static const String ajouter = 'Immobilisation';
  static const String aucune = 'Aucune immobilisation enregistrée.';
  static const String aucuneFiltre =
      'Aucune immobilisation ne correspond à cette recherche.';
  static const String plan = 'Plan';
  static const String colCode = 'Code';
  static const String colImmobilisation = 'Immobilisation';
  static const String colDuree = 'Durée';
  static const String colValeurOrigine = 'Valeur d’origine';
  static const String colDotation = 'Dotation';
  static const String colAmortCumules = 'Amort. cumulés';
  static const String colVnc = 'VNC';
  static const String total = 'TOTAL';
  static const String tiret = '—';
  static const String illisible =
      "Les immobilisations de ce poste n'ont pas pu être lues.";
  static const String sansDroit =
      "Votre profil n'a pas le droit de modifier la comptabilité.";

  static String titreTableau(int annee) =>
      'Tableau des immobilisations — exercice $annee';
  static String duree(int ans) => '$ans ans';
  static String sousLigne(Immobilisation i) =>
      '${i.compteImmobilisation ?? tiret} · mise en service '
      '${i.dateMiseServiceCourte}';
}

/// Onglet « Immobilisations » : l'encadré de la durée d'utilité, la recherche
/// (code ou libellé), « + Immobilisation », puis le tableau de l'exercice
/// consulté — brut, dotation de l'exercice, amortissements cumulés, VNC — CALCULÉ
/// sur le poste depuis les immobilisations détenues (`tableauPourExercice`).
///
/// ## Écarts, nommés
///
/// - Aucune écriture de dotation n'est passée, ici comme au serveur.
/// - Le centre d'affectation du maître n'est pas porté : le serveur ne le porte
///   pas non plus.
/// - Une immobilisation créée ici part au serveur (file d'envoi) ; son code
///   `IMMO-AAAA-NNNNN` est PROVISOIRE jusqu'à l'accusé du serveur.
class OngletImmobilisations extends ConsumerStatefulWidget {
  const OngletImmobilisations({required this.annee, super.key});

  /// L'année de l'exercice consulté.
  final int annee;

  @override
  ConsumerState<OngletImmobilisations> createState() =>
      _OngletImmobilisationsState();
}

class _OngletImmobilisationsState extends ConsumerState<OngletImmobilisations> {
  String _recherche = '';

  @override
  Widget build(BuildContext context) {
    final lu = ref.watch(immobilisationsProvider);
    if (lu.hasError) {
      return Text(
        TextesOngletImmobilisations.illisible,
        key: const Key('compta-immo-illisible'),
        style: styleTransverse(TaillesContenu.t13, couleur: AppColors.erreur),
      );
    }
    final tableau = tableauPourExercice(
      lu.value ?? const <Immobilisation>[],
      widget.annee,
      recherche: _recherche.trim(),
    );
    final blanc = styleTransverse(
      TaillesContenu.t13,
      poids: FontWeight.bold,
      couleur: AppColors.neutre0,
    );
    String ouTiret(int c) =>
        c == 0 ? TextesOngletImmobilisations.tiret : montantFcfa(c);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EncadreTransverse(
          fond: Ardoise.c50,
          bordure: Ardoise.c200,
          padding: const EdgeInsets.all(AppSpacing.smPlus),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${TextesOngletImmobilisations.dureeTitre} ',
                  style: styleTransverse(
                    TaillesContenu.t13,
                    poids: FontWeight.bold,
                    couleur: Ardoise.c700,
                  ),
                ),
                const TextSpan(text: TextesOngletImmobilisations.dureeDetail),
              ],
            ),
            style: styleTransverse(TaillesContenu.t13, couleur: Ardoise.c700),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
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
                key: const Key('compta-immo-recherche'),
                onChanged: (v) => setState(() => _recherche = v),
                style: styleTransverse(TaillesContenu.t13),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: TextesOngletImmobilisations.recherche,
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
              cle: const Key('compta-immo-ajouter'),
              libelle: '+ ${TextesOngletImmobilisations.ajouter}',
              fond: AppColors.navy,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xsPlus,
              ),
              onTap: () =>
                  ref
                      .read(droitsProvider)
                      .peutEcrire(ModuleTatacora.m10Comptabilite)
                  ? ouvrirModaleImmobilisation(context)
                  : direTransverse(
                      context,
                      TextesOngletImmobilisations.sansDroit,
                      cle: const Key('compta-immo-sans-droit'),
                    ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (tableau.lignes.isEmpty && lu.hasValue)
          CarteTransverse(
            padding: const EdgeInsets.symmetric(
              vertical: AppSpacingLarge.p14,
              horizontal: AppSpacing.mdPlus,
            ),
            child: Text(
              _recherche.trim().isEmpty
                  ? TextesOngletImmobilisations.aucune
                  : TextesOngletImmobilisations.aucuneFiltre,
              key: const Key('compta-immo-aucune'),
              textAlign: TextAlign.center,
              style: styleTransverse(TaillesContenu.t13, couleur: Ardoise.c400),
            ),
          )
        else if (tableau.lignes.isNotEmpty)
          CarteTransverse(
            key: const Key('compta-immo-tableau'),
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
                    TextesOngletImmobilisations.titreTableau(widget.annee),
                    style: styleTransverse(
                      TaillesContenu.t14,
                      poids: FontWeight.bold,
                      couleur: AppColors.navy,
                    ),
                  ),
                ),
                TableauTransverse(
                  largeurs: const {1: MesuresTransverses.colonneLibelleCompta},
                  colonnes: const [
                    (
                      titre: TextesOngletImmobilisations.colCode,
                      alignement: TextAlign.left,
                    ),
                    (
                      titre: TextesOngletImmobilisations.colImmobilisation,
                      alignement: TextAlign.left,
                    ),
                    (
                      titre: TextesOngletImmobilisations.colDuree,
                      alignement: TextAlign.right,
                    ),
                    (
                      titre: TextesOngletImmobilisations.colValeurOrigine,
                      alignement: TextAlign.right,
                    ),
                    (
                      titre: TextesOngletImmobilisations.colDotation,
                      alignement: TextAlign.right,
                    ),
                    (
                      titre: TextesOngletImmobilisations.colAmortCumules,
                      alignement: TextAlign.right,
                    ),
                    (
                      titre: TextesOngletImmobilisations.colVnc,
                      alignement: TextAlign.right,
                    ),
                    (titre: '', alignement: TextAlign.right),
                  ],
                  vide: TextesOngletImmobilisations.aucune,
                  lignes: [
                    for (final l in tableau.lignes)
                      [
                        celluleTexte(
                          l.immobilisation.code,
                          mono: true,
                          taille: TaillesContenu.t12,
                          couleur: Ardoise.c500,
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            celluleTexte(
                              l.immobilisation.libelle,
                              poids: FontWeight.w600,
                              couleur: Ardoise.c700,
                            ),
                            Text(
                              TextesOngletImmobilisations.sousLigne(
                                l.immobilisation,
                              ),
                              style: styleTransverse(
                                TaillesContenu.t11,
                                couleur: Ardoise.c400,
                              ),
                            ),
                          ],
                        ),
                        celluleTexte(
                          TextesOngletImmobilisations.duree(
                            l.immobilisation.dureeAnnees,
                          ),
                          alignement: TextAlign.right,
                        ),
                        celluleTexte(
                          montantFcfa(l.brutCentimes),
                          alignement: TextAlign.right,
                        ),
                        celluleTexte(
                          ouTiret(l.dotationCentimes),
                          alignement: TextAlign.right,
                        ),
                        celluleTexte(
                          ouTiret(l.cumulCentimes),
                          alignement: TextAlign.right,
                          couleur: AppColors.erreur,
                        ),
                        celluleTexte(
                          montantFcfa(l.vncCentimes),
                          alignement: TextAlign.right,
                          poids: FontWeight.w600,
                        ),
                        BoutonTransverse(
                          cle: Key('compta-immo-plan-${l.immobilisation.id}'),
                          libelle: TextesOngletImmobilisations.plan,
                          taille: TaillesContenu.t11,
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.xs,
                            vertical: AppSpacing.demi,
                          ),
                          onTap: () => ouvrirModalePlanAmortissement(
                            context,
                            l.immobilisation,
                          ),
                        ),
                      ],
                  ],
                  pied: [
                    Text(TextesOngletImmobilisations.total, style: blanc),
                    const SizedBox.shrink(),
                    const SizedBox.shrink(),
                    Text(
                      montantFcfa(tableau.totalBrutCentimes),
                      textAlign: TextAlign.right,
                      style: blanc,
                    ),
                    Text(
                      montantFcfa(tableau.totalDotationCentimes),
                      textAlign: TextAlign.right,
                      style: blanc,
                    ),
                    Text(
                      montantFcfa(tableau.totalCumulCentimes),
                      textAlign: TextAlign.right,
                      style: blanc,
                    ),
                    Text(
                      montantFcfa(tableau.totalVncCentimes),
                      textAlign: TextAlign.right,
                      style: blanc,
                    ),
                    const SizedBox.shrink(),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}
