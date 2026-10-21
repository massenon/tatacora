import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/format/formats.dart';
import '../../../core/navigation/navigation_tatacora.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/mesures_transverses.dart';
import '../../../shared_widgets/bouton_standard.dart';
import '../../../shared_widgets/liste_paginee.dart';
import '../domain/comptes_utilisateurs.dart';
import '../domain/roles_du_poste.dart';
import 'providers_transverses.dart';
import 'widgets/briques_transverses.dart';
import 'widgets/modales_comptes.dart';

/// L'écran **Comptes utilisateurs** — Lot J2, directive du Product Owner du
/// 14/10/2026.
///
/// ## Un AJOUT du poste : la vue n'a pas d'écran de comptes
///
/// Relu le 14/10/2026 : la PWA ne gère pas les comptes (aucun composant, vue
/// ni route ; au serveur, l'opérateur les crée). Sur ce poste sans serveur,
/// seul le premier compte naissait (`FormulairePremierCompte`) — aucun autre
/// employé ne pouvait se connecter. La mise en page reprend les briques des
/// écrans transverses (en-tête, carte, tableau à en-tête navy, pied de
/// pagination) et les modales de « Rôles & Permissions » ; les colonnes
/// reprennent les mots de cet écran (« Rôle », libellés des rôles).
///
/// ## Qui y entre
///
/// Les deux rôles d'administration (`administrateur`, `super_admin` — par
/// leur CODE), avec le droit sur ROLES : l'entrée de menu le déclare
/// (`rolesExiges`), la garde du routeur relit la même règle, cet écran la
/// rejoue au rendu et `ComptesUtilisateursDao` au geste.
///
/// ## Ce qu'on y fait — jamais de suppression
///
/// Créer un compte (le rôle donne ses droits), désactiver / réactiver,
/// réinitialiser le mot de passe. Aucun compte ne se supprime (RG-15). Un
/// administrateur ne se désactive pas lui-même, et le dernier administrateur
/// actif ne se désactive pas. Rien ne part au réseau.
class EcranComptesUtilisateurs extends ConsumerWidget {
  const EcranComptesUtilisateurs({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final entree = toutesLesDestinations.firstWhere(
      (d) => d.route == routeComptesUtilisateurs,
    );
    final admis =
        session != null &&
        destinationAccessible(
          entree,
          droits: ref.watch(droitsProvider),
          role: session.role,
        );
    if (!admis) {
      return const RefusDroitTransverse(message: MessagesComptes.refusDroit);
    }
    final lus = ref.watch(comptesEtRolesProvider);

    return PageTransverse(
      largeurMax: MesuresTransverses.pageLarge,
      enfants: [
        EnTeteTransverse(
          trace: IconeModule.crm.trace,
          titre: TextesComptes.titre,
          sousTitre: TextesComptes.sousTitre,
        ),
        Row(
          children: [
            BoutonStandard(
              key: const Key('comptes-nouveau'),
              libelle: TextesComptes.boutonNouveau,
              variante: VarianteBouton.primaire,
              onPressed: lus.hasValue
                  ? () => _nouveauCompte(context, ref, lus.requireValue.roles)
                  : null,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        switch (lus) {
          AsyncData(:final value) => _Tableau(
            comptes: value.comptes,
            sessionId: session.utilisateurId,
            onReinitialiser: (c) => _reinitialiser(context, ref, c),
            onBasculer: (c) => _basculer(context, ref, c),
          ),
          AsyncError() => Text(
            TextesComptes.lectureImpossible,
            key: const Key('comptes-lecture-impossible'),
            style: styleTransverse(
              TaillesContenu.t13,
              couleur: AppColors.erreur,
            ),
          ),
          _ => const SizedBox.shrink(),
        },
      ],
    );
  }

  /// L'auteur du geste : l'identifiant de la session, RELU au geste (le DAO
  /// relit ensuite son rôle et son état en base).
  static String _auteur(WidgetRef ref) =>
      ref.read(sessionProvider)?.utilisateurId ?? '';

  static void _apres(BuildContext context, WidgetRef ref, String message) {
    ref.invalidate(comptesEtRolesProvider);
    // Le décompte des comptes de « Rôles & Permissions » change aussi.
    ref.invalidate(matriceDuPosteProvider);
    if (context.mounted) {
      direTransverse(context, message, cle: const Key('comptes-succes'));
    }
  }

  static Future<void> _nouveauCompte(
    BuildContext context,
    WidgetRef ref,
    List<RoleDuPoste> roles,
  ) async {
    String? identifiant;
    final fait = await ouvrirModaleNouveauCompte(
      context,
      roles: roles,
      enregistrer: (s) async {
        await ref
            .read(comptesUtilisateursDaoProvider)
            .creerCompte(
              auteurId: _auteur(ref),
              nom: s.nom,
              identifiant: s.identifiant,
              role: s.role,
              motDePasse: s.motDePasse,
              confirmation: s.confirmation,
            );
        identifiant = ReglesComptes.normaliserIdentifiant(s.identifiant);
      },
    );
    if (fait == true && context.mounted) {
      _apres(context, ref, MessagesComptes.compteCree(identifiant ?? ''));
    }
  }

  static Future<void> _reinitialiser(
    BuildContext context,
    WidgetRef ref,
    CompteUtilisateur compte,
  ) async {
    final fait = await ouvrirModaleReinitialiserMotDePasse(
      context,
      compte: compte,
      enregistrer: (nouveau, confirmation) => ref
          .read(comptesUtilisateursDaoProvider)
          .reinitialiserMotDePasse(
            auteurId: _auteur(ref),
            compteId: compte.id,
            nouveau: nouveau,
            confirmation: confirmation,
          ),
    );
    if (fait == true && context.mounted) {
      _apres(
        context,
        ref,
        MessagesComptes.motDePasseReinitialise(compte.identifiant),
      );
    }
  }

  /// Désactiver passe par une confirmation (le compte ne se connectera plus) ;
  /// réactiver est immédiat.
  static Future<void> _basculer(
    BuildContext context,
    WidgetRef ref,
    CompteUtilisateur compte,
  ) async {
    final dao = ref.read(comptesUtilisateursDaoProvider);
    if (compte.actif) {
      final fait = await ouvrirModaleDesactiver(
        context,
        compte: compte,
        desactiver: () => dao.definirActif(
          auteurId: _auteur(ref),
          compteId: compte.id,
          actif: false,
        ),
      );
      if (fait == true && context.mounted) {
        _apres(
          context,
          ref,
          MessagesComptes.compteDesactive(compte.identifiant),
        );
      }
      return;
    }
    try {
      await dao.definirActif(
        auteurId: _auteur(ref),
        compteId: compte.id,
        actif: true,
      );
      if (context.mounted) {
        _apres(
          context,
          ref,
          MessagesComptes.compteReactive(compte.identifiant),
        );
      }
    } on RefusComptes catch (refus) {
      if (context.mounted) {
        direTransverse(context, refus.message, cle: const Key('comptes-refus'));
      }
    }
  }
}

/// Les textes de l'écran.
abstract final class TextesComptes {
  static const String titre = 'Comptes utilisateurs';
  static const String sousTitre =
      "Les comptes d'accès de ce poste — chacun reçoit les droits de son rôle "
      '(« Rôles & Permissions »). Un compte ne se supprime jamais : il se '
      "désactive, et ce qu'il a saisi garde son auteur.";
  static const String boutonNouveau = '+ Nouveau compte';
  static const String lectureImpossible =
      'Les comptes de ce poste ne peuvent pas être lus.';
  static const String colNom = 'Nom complet';
  static const String colIdentifiant = 'Identifiant';
  static const String colRole = 'Rôle';
  static const String colStatut = 'Statut';
  static const String colCreeLe = 'Créé le';
  static const String colMotDePasse = 'Mot de passe modifié le';
  static const String colActions = 'Actions';
  static const String actif = 'Actif';
  static const String desactive = 'Désactivé';
  static const String vous = '(vous)';
  static const String reinitialiser = 'Réinitialiser le mot de passe';
  static const String desactiver = 'Désactiver';
  static const String reactiver = 'Réactiver';
  static const String vide = 'Aucun compte sur ce poste.';
}

class _Tableau extends StatelessWidget {
  const _Tableau({
    required this.comptes,
    required this.sessionId,
    required this.onReinitialiser,
    required this.onBasculer,
  });

  final List<CompteUtilisateur> comptes;
  final String sessionId;
  final ValueChanged<CompteUtilisateur> onReinitialiser;
  final ValueChanged<CompteUtilisateur> onBasculer;

  @override
  Widget build(BuildContext context) {
    return CarteTransverse(
      padding: EdgeInsets.zero,
      child: ListePaginee<CompteUtilisateur>(
        elements: comptes,
        prefixeCle: 'comptes-pagination',
        masquerSiVide: true,
        constructeur: (context, page) => TableauTransverse(
          colonnes: const [
            (titre: TextesComptes.colNom, alignement: TextAlign.left),
            (titre: TextesComptes.colIdentifiant, alignement: TextAlign.left),
            (titre: TextesComptes.colRole, alignement: TextAlign.left),
            (titre: TextesComptes.colStatut, alignement: TextAlign.left),
            (titre: TextesComptes.colCreeLe, alignement: TextAlign.left),
            (titre: TextesComptes.colMotDePasse, alignement: TextAlign.left),
            (titre: TextesComptes.colActions, alignement: TextAlign.right),
          ],
          // Largeurs FIXES (21/10/2026) : sans elles, chaque colonne libre
          // prenait la largeur de la plus large cellule du tableau (les deux
          // boutons d'action) et la page débordait de la fenêtre. Seul le nom
          // reste libre et prend le reste.
          largeurs: const {
            1: MesuresTransverses.colonneCompteIdentifiant,
            2: MesuresTransverses.colonneCompteRole,
            3: MesuresTransverses.colonneCompteStatut,
            4: MesuresTransverses.colonneCompteCreeLe,
            5: MesuresTransverses.colonneCompteMotDePasse,
            6: MesuresTransverses.colonneCompteActions,
          },
          vide: TextesComptes.vide,
          cleVide: const Key('comptes-vide'),
          lignes: [for (final c in page) _ligne(c)],
        ),
      ),
    );
  }

  List<Widget> _ligne(CompteUtilisateur c) {
    final soi = c.id == sessionId;
    return [
      Text.rich(
        TextSpan(
          children: [
            TextSpan(text: c.nom),
            if (soi) const TextSpan(text: ' ${TextesComptes.vous}'),
          ],
        ),
        key: Key('comptes-nom-${c.identifiant}'),
        style: styleTransverse(
          TaillesContenu.t13,
          poids: FontWeight.w600,
          couleur: Ardoise.c800,
        ),
      ),
      celluleTexte(c.identifiant, mono: true),
      celluleTexte(libelleRole(c.role)),
      Text(
        c.actif ? TextesComptes.actif : TextesComptes.desactive,
        key: Key('comptes-statut-${c.identifiant}'),
        style: styleTransverse(
          TaillesContenu.t12,
          poids: FontWeight.w600,
          couleur: c.actif ? PaletteMaitre.emeraude700 : PaletteMaitre.rouge700,
        ),
      ),
      celluleTexte(formaterDate(c.dateCreation)),
      celluleTexte(formaterDate(c.dateMotDePasse)),
      Wrap(
        alignment: WrapAlignment.end,
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        children: [
          BoutonStandard(
            key: Key('comptes-reinitialiser-${c.identifiant}'),
            libelle: TextesComptes.reinitialiser,
            compact: true,
            onPressed: () => onReinitialiser(c),
          ),
          // Sa propre ligne n'offre pas « Désactiver » : le DAO le refuserait,
          // et un bouton qui mène à un refus certain est un bouton inerte.
          if (!soi)
            BoutonStandard(
              key: Key('comptes-basculer-${c.identifiant}'),
              libelle: c.actif
                  ? TextesComptes.desactiver
                  : TextesComptes.reactiver,
              variante: c.actif
                  ? VarianteBouton.contourRouge
                  : VarianteBouton.secondaire,
              compact: true,
              onPressed: () => onBasculer(c),
            ),
        ],
      ),
    ];
  }
}
