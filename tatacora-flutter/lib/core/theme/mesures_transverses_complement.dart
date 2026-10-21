/// Jetons des libellés repris de la vue pour le groupe `transverse/*`,
/// `livewire/*` (accueil, connexion), `chassis`, `demarrage` et
/// `notifications/*` — ajoutés le 21/10/2026 (ordre du Product Owner « tout
/// doit être au complet »).
///
/// Fichier d'AJOUT : il ne réécrit aucun jeton existant. Chaque valeur dit la
/// classe de la vue qui la porte (chemins écrits sans leur préfixe, PA-187).
library;

import 'package:flutter/painting.dart';

import 'app_colors.dart';

/// Le bandeau « Accès lecture seule » de la coquille
/// (`partials/banniere` : `bg-amber-50 border-b-2 border-amber-300 px-6 py-3`).
abstract final class MesuresBandeauLectureSeule {
  /// `border-b-2`.
  static const double filetBas = 2;

  /// `w-4 h-4` de l'icône d'avertissement (`width="16"`).
  static const double icone = 16;

  /// `px-3 py-1.5` du bouton « Se connecter avec un autre profil → ».
  static const EdgeInsets margeBouton = EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 6,
  );
}

/// L'accordéon « Indicateurs clés (8) » de l'accueil, sous `lg`
/// (`accueil.blade.php` l.405-409 : `<svg width="16" height="16">`).
abstract final class MesuresAccordeonIndicateurs {
  static const double icone = 16;
}

/// Les bascules de l'onglet « Activation & Sécurité » de Paramètres
/// (`parametres.blade.php` l.449-463) : `w-11 h-6 rounded-full`, curseur
/// `w-5 h-5` à `left:22px` actif / `2px` inactif, `top-0.5`.
abstract final class MesuresBasculeActivation {
  static const double largeur = 44;
  static const double hauteur = 24;
  static const double curseur = 20;
  static const double decalageActif = 22;
  static const double decalageInactif = 2;
  static const double haut = 2;

  /// `style="background:#CBD5E1"` — la piste d'une bascule inactive.
  static const Color pisteInactive = Ardoise.c300;

  /// `px-1.5 py-0.5` de la pastille de risque.
  static const EdgeInsets margePastille = EdgeInsets.symmetric(
    horizontal: 6,
    vertical: 2,
  );

  /// `px-3.5 py-3` de l'encadré d'information bleu.
  static const EdgeInsets margeInfo = EdgeInsets.symmetric(
    horizontal: 14,
    vertical: 12,
  );

  /// `<svg width="15">` de l'encadré d'information.
  static const double iconeInfo = 15;
}

/// L'envoi de l'email de test et ses messages (`email_test_bouton`).
abstract final class MesuresEmailDeTest {
  /// `px-4 py-2.5` du bouton.
  static const EdgeInsets margeBouton = EdgeInsets.symmetric(
    horizontal: 16,
    vertical: 10,
  );

  /// `<svg width="14">` de l'avion en papier.
  static const double icone = 14;
}
