// Vue Blade maîtresse (PA-183) : pwa/transverse/comptes-utilisateurs.blade.php
// Vue Blade maîtresse (PA-183) : pwa/transverse/mon-profil.blade.php
/// La fenêtre d'un SECRET AFFICHÉ UNE SEULE FOIS (29/10/2026, option A du PO) :
/// le mot de passe temporaire que l'administrateur vient de générer, le code de
/// secours qu'il doit ranger au coffre.
///
/// Jumeau du `x-pwa.modale` + `x-pwa.secret-unique` des vues du serveur : le
/// secret, « Copier », « Imprimer » (si offert) et un seul bouton de fermeture.
/// `barrierDismissible: false` — un clic à côté ne doit pas détruire un secret
/// qui ne reviendra plus ; « Fermer », ✕ et Échap restent des choix délibérés.
///
/// Modale : hors `<main>`, échelle typographique DÉCLARÉE ([Tailles]).
library;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/mesures_transverses.dart';
import '../../../../shared_widgets/affichage_secret_unique.dart';
import '../../../../shared_widgets/bouton_standard.dart';
import '../../../restaurant/presentation/widgets/coquille_modale_restaurant.dart';

Future<void> ouvrirModaleSecretUnique(
  BuildContext context, {
  required String titre,
  required String secret,
  required String consigne,
  required String libelleFermer,
  String? sousTitre,
  Future<void> Function()? surImprimer,
  String prefixeCle = 'secret',
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  barrierColor: AppColors.voileModale,
  builder: (_) => CoquilleModaleRestaurant(
    cle: Key('$prefixeCle-modale'),
    titre: titre,
    sousTitre: sousTitre,
    largeur: MesuresTransverses.modaleCompte,
    corps: AffichageSecretUnique(
      secret: secret,
      consigne: consigne,
      surImprimer: surImprimer,
      prefixeCle: prefixeCle,
    ),
    actions: [
      Builder(
        builder: (contexte) => BoutonStandard(
          key: Key('$prefixeCle-fermer'),
          libelle: libelleFermer,
          variante: VarianteBouton.primaire,
          taillePolice: Tailles.t13,
          onPressed: () => Navigator.of(contexte).pop(),
        ),
      ),
    ],
  ),
);
