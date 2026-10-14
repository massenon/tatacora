// Vue Blade maîtresse (PA-183) : pwa/achats/achats.blade.php
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import 'widgets/coquille_achats.dart';
import 'widgets/vue_commandes_achats.dart';
import 'widgets/vue_fournisseurs.dart';

/// L'écran **Fournisseurs & Achats** — la vue `achats/achats`.
///
/// ## La page, dans l'ordre de la vue
///
/// Une colonne qui défile d'un bloc (`max-w-[1440px] mx-auto p-5 lg:p-8`) :
/// l'en-tête (icône, titre, sous-titre, puis les DEUX onglets cliquables, l.63-81),
/// la barre d'outils de l'onglet courant, son tableau et son pied. Chaque onglet
/// reconstruit sa barre d'outils — le libellé du bouton de création suit
/// l'onglet (« Ajouter fournisseur » / « Ajouter commande d'achat »).
///
/// ## Source LOCALE depuis le 09/10/2026
///
/// Les deux tableaux lisent la base du poste (`AchatsDao`, cinq tables
/// neuves, schéma v13). « Aucun résultat » est la vérité d'un référentiel
/// réellement vide ; l'absence de DROIT de lecture, elle, est dite à part
/// ([CorpsIndisponibleAchats]) et le décompte rend alors des tirets : un
/// « 0 » se lirait comme une mesure. L'archivage d'un fournisseur est un vrai
/// geste depuis le 12/10/2026 (D63) : réplique de `ReferentielFournisseurService`,
/// réservé par la règle unique `peutArchiver` (droit C et rôle d'administration
/// ou bascule `activation_suppression`).
///
/// ## Le sous-titre est celui de la vue — et il promet plus que le contrôle
///
/// « … et rapprochement à trois voies » est rendu au mot. Le contrôle du
/// serveur (`ControleTroisVoiesService`, relu le 09/10/2026) ne confronte que
/// deux voies, commande et réception : la facture fournisseur n'a aucune table
/// au schéma. Jusqu'au 09/10/2026 ce client CORRIGEAIT la phrase ; la vue gagne
/// quand elle se contredit avec une spécification sur ce qui se voit
/// (PA-182/183), et la correction est désormais DITE sous la page
/// ([_NoteRapprochement]) plutôt que substituée au texte. Le défaut est celui de
/// la vue elle-même : à remonter au Product Owner.
class EcranFournisseurs extends StatefulWidget {
  const EcranFournisseurs({super.key});

  @override
  State<EcranFournisseurs> createState() => _EcranFournisseursState();
}

class _EcranFournisseursState extends State<EcranFournisseurs> {
  int _onglet = 0;

  /// Les deux onglets de la vue (l.76-79), dans son ordre et à ses mots.
  static const _onglets = [
    (cle: 'fournisseurs', libelle: 'Fournisseurs'),
    (cle: 'commandes', libelle: "Commandes d'achat"),
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl), // lg:p-8
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppLayout.maxContentWidth,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _EnTete(
                onglets: [
                  for (final (i, o) in _onglets.indexed)
                    OngletAchats(
                      cle: Key('onglet-achats-${o.cle}'),
                      libelle: o.libelle,
                      actif: _onglet == i,
                      onChoix: () => setState(() => _onglet = i),
                    ),
                ],
              ),
              if (_onglet == 1)
                const VueCommandesAchats()
              else
                const VueFournisseurs(),
              const _NoteRapprochement(),
            ],
          ),
        ),
      ),
    );
  }
}

TextStyle _t(
  double taille, {
  FontWeight? poids,
  Color? couleur,
  double interligne = AppLayout.interligneContenu,
}) => TextStyle(
  fontFamily: AppTextStyles.police,
  fontSize: taille,
  fontWeight: poids,
  color: couleur,
  height: interligne,
);

/// `mb-5` : icône de 24 px, titre, sous-titre, puis la rangée d'onglets en
/// `flex gap-2 mt-4` (l.63-81).
class _EnTete extends StatelessWidget {
  const _EnTete({required this.onglets});

  final List<Widget> onglets;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.mdPlus), // mb-5
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.shopping_cart_outlined,
                size: AppLayout.iconeTitrePage,
                color: AppColors.navy,
              ),
              const SizedBox(width: AppSpacing.xsPlus), // gap-2.5
              Text(
                // Le titre de la vue (l.68), au mot.
                'Fournisseurs & Achats',
                style: _t(
                  TaillesContenu.lg,
                  poids: FontWeight.bold,
                  couleur: AppColors.navy,
                  interligne: TaillesContenu.interligneLg,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs), // mt-1.5
          Text(
            // Le sous-titre de la vue (l.70), au mot — voir l'en-tête de classe.
            "Référentiel fournisseurs, commandes d'achat et rapprochement à trois voies",
            style: _t(TaillesContenu.t15, couleur: Ardoise.c500),
          ),
          const SizedBox(height: AppSpacing.md), // mt-4
          Wrap(
            spacing: AppSpacing.xs, // gap-2
            runSpacing: AppSpacing.xs,
            children: onglets,
          ),
        ],
      ),
    );
  }
}

/// Ce que le sous-titre de la vue promet, et ce que le contrôle fait.
///
/// ÉCART DÉLIBÉRÉ — `pwa/achats/achats.blade.php` l.70 et
/// `lang/fr/pwa.php` `achats.sous_titre`.
/// La vue : « … et rapprochement à trois voies », sans réserve.
/// Ici : la phrase est rendue au mot, et cette note dit ce qu'elle ne couvre
/// pas.
/// Raison (09/10/2026, relue contre `ControleTroisVoiesService`) : le service
/// documente lui-même que la facture fournisseur « n'a aucune table » et qu'il
/// « compare réellement deux voies sur trois ». Ce poste fait de même : son
/// rapprochement (bouton de l'Approvisionnement) confronte commande et
/// réception, et aucune table ne porte la facture. Lire « trois voies » sous
/// un écran qui n'en contrôle que deux est la phrase qu'un acheteur lit juste
/// avant d'autoriser un paiement (PA-59/60/61 sur la pièce qui décaisse).
/// Le texte précédent (« ce poste ne lit aucune des deux listes ») est devenu
/// FAUX le 09/10/2026 : M7 est local, les listes se lisent.
class _NoteRapprochement extends StatelessWidget {
  const _NoteRapprochement();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Text(
        'Le rapprochement de ce poste ne confronte que deux voies, commande '
        'et réception : la facture fournisseur n’a aucune table. Il ne vaut '
        'donc pas autorisation de paiement.',
        key: const Key('achats-note-rapprochement'),
        style: _t(TaillesContenu.t11, couleur: Ardoise.c500),
      ),
    );
  }
}
