// Vue Blade maîtresse (PA-183) : pwa/transverse/parametres.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../hebergement/domain/entities/fiche_reservation.dart';
import '../../../hebergement/presentation/providers_hebergement.dart';

/// Les mots de l'onglet « Canaux de réservation » (`pwa.parametres.canaux_*`),
/// au mot — l'apostrophe est celle de la vue (typographique).
abstract final class TextesCanaux {
  static const String introA =
      'Les canaux proposés à la saisie d’une réservation, ici et dans la réservation rapide du tableau de bord.';
  static const String introFort =
      'Un canal utilisé ne se supprime pas, il se désactive';
  static const String introB =
      '— l’effacer laisserait des réservations pointant vers un canal inexistant, et l’analyse par canal perdrait son historique.';
  static const String colonneCanal = 'Canal';
  static const String colonneReservations = 'Réservations';
  static const String colonneEtat = 'État';
  static const String colonneActions = 'Actions';
  static const String etatActif = 'actif';
  static const String aucun = 'Aucun canal enregistré.';

  /// AJOUT du poste, absent de la vue : ce que ce poste ne fait pas. Le
  /// référentiel `canaux_reservation` est administré sur le serveur ; ce poste
  /// n'en détient que le jeu initial (aucune table locale, aucun contrat de
  /// synchronisation), donc ni ajout, ni renommage, ni désactivation ici.
  static const String surCePoste =
      'Sur ce poste : le jeu initial des canaux. L’ajout, le renommage et la désactivation d’un canal se font sur le serveur.';
}

/// Le tableau des canaux de réservation (`partials/tableau-canaux`) : le jeu
/// initial du poste ([CanalReservation]), le nombre de réservations de chacun
/// (relu des réservations du poste, jamais deviné), « actif », et « — » en
/// colonne des actions : la vue y met les boutons « Renommer » et
/// « Désactiver » pour qui écrit, et ce poste n'en offre aucun — un bouton
/// qui ne mènerait nulle part serait une entrée inerte (Article 3.3).
class OngletCanaux extends ConsumerWidget {
  const OngletCanaux({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reservations = ref.watch(reservationsProvider).value ?? const [];
    int combien(CanalReservation c) =>
        reservations.where((r) => r.canal == c).length;

    TextStyle style(
      double taille, {
      FontWeight? poids,
      Color couleur = AppColors.neutre500,
    }) => TextStyle(
      fontFamily: AppTextStyles.police,
      fontSize: taille,
      height: 1.5,
      fontWeight: poids,
      color: couleur,
    );

    Widget cellule(Widget enfant, {int flex = 1, Alignment? alignement}) =>
        Expanded(
          flex: flex,
          child: Container(
            alignment: alignement ?? Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, // px-4
              vertical: AppSpacing.xsPlus, // py-2.5
            ),
            child: enfant,
          ),
        );

    Widget entete(String texte, {Alignment? alignement}) => cellule(
      Text(
        texte.toUpperCase(),
        style:
            style(
              TaillesContenu.t11,
              poids: FontWeight.w600,
              couleur: AppColors.neutre0.withValues(alpha: 0.9),
            ).copyWith(
              letterSpacing: AppTextStyles.suiviLarge * TaillesContenu.t11,
            ),
      ),
      alignement: alignement,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md), // mb-4
          child: Text.rich(
            key: const Key('param-canaux-intro'),
            TextSpan(
              style: style(TaillesContenu.t13),
              children: const [
                TextSpan(text: TextesCanaux.introA),
                TextSpan(text: ' '),
                TextSpan(
                  text: TextesCanaux.introFort,
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                TextSpan(text: ' '),
                TextSpan(text: TextesCanaux.introB),
              ],
            ),
          ),
        ),
        Container(
          key: const Key('param-canaux-tableau'),
          margin: const EdgeInsets.only(bottom: AppSpacing.mdPlus), // mb-5
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.neutre0,
            border: Border.all(color: AppColors.neutre200),
            borderRadius: BorderRadius.circular(AppRadius.roundedXl),
          ),
          child: Column(
            children: [
              Container(
                color: AppColors.navy,
                child: Row(
                  children: [
                    entete(TextesCanaux.colonneCanal),
                    entete(
                      TextesCanaux.colonneReservations,
                      alignement: Alignment.centerRight,
                    ),
                    entete(TextesCanaux.colonneEtat),
                    entete(
                      TextesCanaux.colonneActions,
                      alignement: Alignment.centerRight,
                    ),
                  ],
                ),
              ),
              if (CanalReservation.values.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Text(
                    TextesCanaux.aucun,
                    textAlign: TextAlign.center,
                    style: style(
                      TaillesContenu.t13,
                      couleur: AppColors.neutre400,
                    ),
                  ),
                ),
              for (final canal in CanalReservation.values)
                Container(
                  key: Key('param-canal-${canal.code}'),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: AppColors.neutre100)),
                  ),
                  child: Row(
                    children: [
                      cellule(
                        Text(
                          canal.libelle,
                          style: style(
                            TaillesContenu.t13,
                            poids: FontWeight.w600,
                            couleur: AppColors.neutre700,
                          ),
                        ),
                      ),
                      cellule(
                        Text(
                          combien(canal) == 0 ? '—' : '${combien(canal)}',
                          style: style(
                            TaillesContenu.t13,
                            poids: combien(canal) == 0 ? null : FontWeight.w600,
                            couleur: combien(canal) == 0
                                ? AppColors.neutre400
                                : AppColors.neutre500,
                          ),
                        ),
                        alignement: Alignment.centerRight,
                      ),
                      cellule(
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.xs, // px-2
                            vertical: AppSpacing.demi, // py-0.5
                          ),
                          decoration: BoxDecoration(
                            color: PaletteMaitre.emeraude50,
                            borderRadius: BorderRadius.circular(
                              AppRadius.rounded,
                            ),
                          ),
                          child: Text(
                            TextesCanaux.etatActif,
                            style: style(
                              TaillesContenu.t11,
                              poids: FontWeight.w600,
                              couleur: PaletteMaitre.emeraude700,
                            ),
                          ),
                        ),
                      ),
                      cellule(
                        Text(
                          '—',
                          style: style(
                            TaillesContenu.t13,
                            couleur: Ardoise.c300,
                          ),
                        ),
                        alignement: Alignment.centerRight,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        Text(
          TextesCanaux.surCePoste,
          key: const Key('param-canaux-sur-ce-poste'),
          style: style(TaillesContenu.t12, couleur: AppColors.neutre400),
        ),
      ],
    );
  }
}
