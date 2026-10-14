import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_text_styles.dart';

/// `ThemeData` assemblé — `04_UIUX_DESIGN_SYSTEM.md` §2.
///
/// Un seul thème, clair. Le mode sombre n'est pas au périmètre : le CdCF ne le
/// demande pas, et la palette institutionnelle (navy sur fond clair) n'a pas
/// d'équivalent sombre validé par le client.
abstract final class AppTheme {
  static ThemeData get clair {
    const scheme = AppColors.schemeClair;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.fondClair,
      fontFamily: AppTextStyles.police,
      textTheme: AppTextStyles.theme,

      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.navy,
        foregroundColor: AppColors.neutre0,
        elevation: 0,
        centerTitle: false,
      ),

      cardTheme: CardThemeData(
        color: AppColors.neutre0,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: const BorderSide(color: AppColors.neutre200),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.navy,
          foregroundColor: AppColors.neutre0,
          elevation: 0,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs + 4,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          textStyle: AppTextStyles.theme.labelLarge,
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.navy,
          side: const BorderSide(color: AppColors.neutre300),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs + 4,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.neutre0,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md - 4,
          vertical: AppSpacing.xs + 4,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.neutre300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.neutre300),
        ),
        // Le focus passe en gold : c'est une sélection active, donc le rôle
        // exact que le design system réserve à cette couleur.
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.gold, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.erreur),
        ),
        labelStyle: AppTextStyles.theme.labelLarge,
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.neutre0,
        indicatorColor: AppColors.reserveGoldFond,
        elevation: 0,
        labelTextStyle: WidgetStateProperty.all(AppTextStyles.theme.labelSmall),
      ),

      dividerTheme: const DividerThemeData(
        color: AppColors.neutre200,
        thickness: 1,
        space: 1,
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.neutre0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.anthracite,
        contentTextStyle: AppTextStyles.theme.bodyMedium?.copyWith(
          color: AppColors.neutre0,
        ),
        behavior: SnackBarBehavior.floating,
        // Demande du PO du 14/10/2026 : les toasts étaient cachés par la barre
        // des tâches Windows. Retrait bas élargi (la fenêtre tient désormais
        // dans la zone de travail, `win32_window.cpp`). Écart à la vue NOMMÉ :
        // elle pose ses toasts en haut à droite (`fixed top-5 right-5`,
        // vues des points de vente) ; un `SnackBar` Flutter n'a pas de
        // position haute réglable par le thème, et le déplacer exigerait de
        // reprendre chacun des appels — lot à part.
        insetPadding: const EdgeInsets.fromLTRB(
          AppLayout.retraitCoteToast,
          AppLayout.retraitHautToast,
          AppLayout.retraitCoteToast,
          AppLayout.retraitBasToast,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
    );
  }
}
