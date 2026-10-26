// Vue Blade maîtresse (PA-183) : pwa/transverse/roles-permissions.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/navigation/coquille_vue.dart';
import '../../../core/navigation/navigation_tatacora.dart';
import '../../../core/rbac/garde_acces.dart';
import '../../../core/theme/app_breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/mesures_transverses.dart';
import '../../../shared_widgets/bouton_standard.dart';
import '../domain/roles_du_poste.dart';
import 'providers_transverses.dart';
import 'widgets/briques_transverses.dart';
import 'widgets/modales_roles.dart';

/// L'écran **Rôles & Permissions** — COMPLET depuis le 14/10/2026 (demande du
/// Product Owner) : les trois gestes de la vue ÉCRIVENT sur le poste, comme
/// `RolePermissionService` au serveur.
///
/// Structure de la vue : en-tête ; rangée d'actions (profil `C` sur ROLES :
/// « + Nouveau rôle », « Rétablir le socle du CdCF », badge d'état de la
/// matrice) ; total des comptes ; cartes de rôles ; matrice complète (légende,
/// une ligne par module, une colonne par rôle).
///
/// ## La source : le référentiel des rôles du poste (schéma v24)
///
/// `roles_local`, seul auteur `RolesDao` — réplique de `roles` et de sa
/// matrice. Le socle du CdCF (`RolePermissionSeeder::MATRICE`, douze rôles)
/// est posé à la première lecture s'il manque, jamais réécrit ensuite. Les
/// droits d'un rôle modifié ou rétabli sont recopiés sur les comptes qui le
/// portent (`utilisateurs_local.droitsJson`), et la session ouverte relit les
/// siens : l'effet est immédiat, comme au serveur.
///
/// Les badges « Conforme au socle du CdCF » / « Matrice amendée » sont
/// désormais rendus : ils sont DÉRIVÉS du socle, que le poste détient (D418
/// les refusait faute de socle — raison levée le 14/10/2026).
///
/// ## Écarts restants, datés (14/10/2026)
///
/// - « Tout retirer » (`roles-permissions.blade.php` l.222, `mr-auto`) se
///   tient à côté de « Annuler » et non à gauche du pied : le châssis partagé
///   des modales range ses boutons à droite.
/// - L'erreur de droit d'un module (`@error('niveauxSaisis')`, l.217) : la vue
///   l'ajoute sous la clé `niveauxSaisis.<module>`, que `@error('niveauxSaisis')`
///   ne lit pas — le refus n'y est jamais affiché. Le poste l'affiche.
class EcranRolesPermissions extends ConsumerWidget {
  const EcranRolesPermissions({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final droits = ref.watch(droitsProvider);
    if (!droits.peutLire(ModuleTatacora.roles)) {
      return const RefusDroitTransverse(message: LibellesCoquille.sansDroit);
    }
    final lus = ref.watch(matriceDuPosteProvider);
    final peutEcrire = droits.peutEcrire(ModuleTatacora.roles);
    final roles = lus.value?.roles;

    return PageTransverse(
      largeurMax: MesuresTransverses.pageLarge,
      enfants: [
        EnTeteTransverse(
          trace: IconeModule.roles.trace,
          titre: TextesRoles.titre,
          sousTitre: TextesRoles.sousTitre,
        ),
        if (peutEcrire) ...[
          // `flex flex-wrap items-center gap-2 mb-4` : les deux boutons, un
          // espaceur `flex-1`, puis le badge d'état de la matrice.
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    BoutonStandard(
                      key: const Key('roles-nouveau'),
                      libelle: TextesRoles.boutonNouveauRole,
                      variante: VarianteBouton.primaire,
                      onPressed: () => _nouveauRole(context, ref),
                    ),
                    BoutonStandard(
                      key: const Key('roles-retablir-socle'),
                      libelle: TextesRoles.boutonRetablirSocle,
                      onPressed: () => _retablirSocle(context, ref),
                    ),
                  ],
                ),
              ),
              if (roles != null)
                _BadgeMatrice(conforme: matriceConformeAuSocle(roles)),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        switch (lus) {
          AsyncData(:final value) => _Corps(
            roles: value.roles,
            totalComptes: value.totalComptes,
            peutEcrire: peutEcrire,
            onModifier: (r) => _modifierDroits(context, ref, r),
          ),
          AsyncError() => Text(
            TextesRoles.lectureImpossible,
            key: const Key('roles-lecture-impossible'),
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

  /// Après une écriture : la liste est relue, la session relit ses droits
  /// (un droit retiré au rôle de la session prend effet tout de suite), et le
  /// message de la vue (`toast-succes`) s'affiche.
  static Future<void> _apres(
    BuildContext context,
    WidgetRef ref,
    String message,
  ) async {
    ref.invalidate(matriceDuPosteProvider);
    await ref.read(sessionProvider.notifier).relireDroits();
    if (context.mounted) {
      direTransverse(context, message, cle: const Key('roles-succes'));
    }
  }

  static Future<void> _nouveauRole(BuildContext context, WidgetRef ref) async {
    final fait = await ouvrirModaleNouveauRole(
      context,
      enregistrer: (libelle, description) => ref
          .read(rolesDaoProvider)
          .creerRole(
            // Le droit est RELU au geste, jamais celui du rendu.
            auteur: ref.read(droitsProvider),
            libelle: libelle,
            description: description,
          ),
    );
    if (fait == true && context.mounted) {
      await _apres(context, ref, MessagesRoles.roleCree);
    }
  }

  static Future<void> _modifierDroits(
    BuildContext context,
    WidgetRef ref,
    RoleDuPoste role,
  ) async {
    final fait = await ouvrirModaleDroits(
      context,
      role: role,
      enregistrer: (niveaux) => ref
          .read(rolesDaoProvider)
          .definirDroits(
            auteur: ref.read(droitsProvider),
            roleId: role.id,
            niveaux: niveaux,
          ),
    );
    if (fait == true && context.mounted) {
      await _apres(context, ref, MessagesRoles.droitsEnregistres);
    }
  }

  static Future<void> _retablirSocle(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final nombre = await ouvrirModaleRetablirSocle(
      context,
      retablir: () => ref
          .read(rolesDaoProvider)
          .retablirSocle(auteur: ref.read(droitsProvider)),
    );
    if (nombre != null && context.mounted) {
      await _apres(context, ref, MessagesRoles.socleRetabli(nombre));
    }
  }
}

/// Les textes de la vue (`pwa.roles.*`), au mot.
abstract final class TextesRoles {
  static const String titre = 'Rôles & Permissions';
  static const String sousTitre =
      "Contrôle d'accès basé sur les rôles (RBAC) — socle amendable. C = accès complet, L = lecture seule, — = aucun accès.";
  static const String matriceTitre = 'Matrice complète des permissions';
  static const String legendeComplet = 'Accès complet (C)';
  static const String legendeLecture = 'Lecture seule (L)';
  static const String legendeAucun = 'Aucun accès';
  static const String colModule = 'Module';
  static String carteComplet(int n) => '$n accès complet';
  static String carteLecture(int n) => '$n lecture seule';
  static String carteComptes(int n) => '$n compte(s) rattaché(s)';
  static const String carteAucunCompte = 'Aucun compte rattaché';
  static const String referentielVide =
      "Aucun rôle n'est enregistré : le référentiel RBAC n'a pas été semé sur cette base. Sans lui, aucun profil ne peut se connecter — c'est une anomalie d'installation, pas un écran vide.";
  static String totalComptes(int n) => "$n compte(s) d'accès au total.";
  static const String boutonNouveauRole = '+ Nouveau rôle';
  static const String boutonRetablirSocle = 'Rétablir le socle du CdCF';
  static const String boutonModifierDroits = 'Modifier les droits';
  static const String badgeConforme = 'Conforme au socle du CdCF';
  static const String badgeAmendee =
      'Matrice amendée — elle diffère du socle du CdCF';

  /// AJOUT déclaré (D418) : la lecture du référentiel a échoué.
  static const String lectureImpossible =
      "Les rôles de ce poste n'ont pas pu être lus.";
}

/// Le badge d'état de la rangée d'actions : `text-[12px] text-emerald-700`
/// ou `text-amber-700`.
class _BadgeMatrice extends StatelessWidget {
  const _BadgeMatrice({required this.conforme});

  final bool conforme;

  @override
  Widget build(BuildContext context) => Text(
    conforme ? TextesRoles.badgeConforme : TextesRoles.badgeAmendee,
    key: const Key('roles-etat-matrice'),
    style: styleTransverse(
      TaillesContenu.t12,
      couleur: conforme ? PaletteMaitre.emeraude700 : PaletteMaitre.ambre700,
    ),
  );
}

class _Corps extends StatelessWidget {
  const _Corps({
    required this.roles,
    required this.totalComptes,
    required this.peutEcrire,
    required this.onModifier,
  });

  final List<RoleDuPoste> roles;
  final int totalComptes;
  final bool peutEcrire;
  final ValueChanged<RoleDuPoste> onModifier;

  @override
  Widget build(BuildContext context) {
    final largeur = MediaQuery.sizeOf(context).width;
    final colonnes = largeur >= AppBreakpoints.xl
        ? MesuresTransverses.colonnesRolesXl
        : largeur >= AppBreakpoints.md
        ? MesuresTransverses.colonnesRolesMd
        : 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          TextesRoles.totalComptes(totalComptes),
          key: const Key('roles-total-comptes'),
          style: styleTransverse(TaillesContenu.t12, couleur: Ardoise.c400),
        ),
        const SizedBox(height: AppSpacing.md),
        if (roles.isEmpty)
          EncadreTransverse(
            fond: PaletteMaitre.ambre50,
            bordure: PaletteMaitre.ambre200,
            child: Text(
              TextesRoles.referentielVide,
              style: styleTransverse(
                TaillesContenu.t13,
                couleur: PaletteMaitre.ambre900,
              ),
            ),
          )
        else
          GrilleTransverse(
            colonnes: colonnes,
            ecart: AppSpacing.md,
            enfants: [
              for (final r in roles)
                _CarteRole(
                  role: r,
                  peutEcrire: peutEcrire,
                  onModifier: () => onModifier(r),
                ),
            ],
          ),
        const SizedBox(height: AppSpacing.xl), // mb-8
        _Matrice(roles: roles),
      ],
    );
  }
}

/// Une carte de rôle : avatar aux initiales, libellé, comptes, deux pastilles
/// « N accès complet » / « N lecture seule », badge de conformité (rôle du
/// socle seulement), « Modifier les droits ».
class _CarteRole extends StatelessWidget {
  const _CarteRole({
    required this.role,
    required this.peutEcrire,
    required this.onModifier,
  });

  final RoleDuPoste role;
  final bool peutEcrire;
  final VoidCallback onModifier;

  @override
  Widget build(BuildContext context) {
    Widget pastille(String texte, Color fond, Color couleur) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: fond,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Text(
          texte,
          textAlign: TextAlign.center,
          style: styleTransverse(
            TaillesContenu.t13,
            poids: FontWeight.bold,
            couleur: couleur,
          ),
        ),
      ),
    );
    final conforme = role.conforme;
    return CarteTransverse(
      key: Key('roles-carte-${role.libelle}'),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: MesuresTransverses.avatarRole,
                height: MesuresTransverses.avatarRole,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.navy,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  initialesRole(role.libelle),
                  style: styleTransverse(
                    TaillesContenu.t15,
                    poids: FontWeight.bold,
                    couleur: AppColors.neutre0,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      libelleRole(role.libelle),
                      style: styleTransverse(
                        TaillesContenu.sm,
                        poids: FontWeight.bold,
                        couleur: Ardoise.c800,
                      ),
                    ),
                    Text(
                      role.comptes == 0
                          ? TextesRoles.carteAucunCompte
                          : TextesRoles.carteComptes(role.comptes),
                      overflow: TextOverflow.ellipsis,
                      style: styleTransverse(
                        TaillesContenu.t13,
                        couleur: role.comptes == 0
                            ? PaletteMaitre.ambre600
                            : Ardoise.c400,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              pastille(
                TextesRoles.carteComplet(role.complet),
                PaletteTransverse.vert50,
                PaletteTransverse.vert700,
              ),
              const SizedBox(width: AppSpacing.xs),
              pastille(
                TextesRoles.carteLecture(role.lecture),
                PaletteTransverse.bleu50,
                PaletteTransverse.bleu700,
              ),
            ],
          ),
          if (conforme != null) ...[
            const SizedBox(height: AppSpacing.xsPlus), // mb-2.5
            // `inline-block text-[11px] px-2 py-0.5 rounded`.
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs,
                  vertical: AppSpacing.demi,
                ),
                decoration: BoxDecoration(
                  color: conforme
                      ? PaletteMaitre.emeraude50
                      : PaletteMaitre.ambre50,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Text(
                  conforme
                      ? TextesRoles.badgeConforme
                      : TextesRoles.badgeAmendee,
                  style: styleTransverse(
                    TaillesContenu.t11,
                    couleur: conforme
                        ? PaletteMaitre.emeraude700
                        : PaletteMaitre.ambre700,
                  ),
                ),
              ),
            ),
          ],
          if (peutEcrire) ...[
            const SizedBox(height: AppSpacing.xsPlus),
            BoutonTransverse(
              cle: Key('roles-modifier-${role.libelle}'),
              libelle: TextesRoles.boutonModifierDroits,
              pleineLargeur: true,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              onTap: onModifier,
            ),
          ],
        ],
      ),
    );
  }
}

/// « Matrice complète des permissions » : en-tête de carte avec la légende,
/// puis la grille module × rôle (`C` vert, `L` bleu, `-` gris).
class _Matrice extends StatelessWidget {
  const _Matrice({required this.roles});

  final List<RoleDuPoste> roles;

  @override
  Widget build(BuildContext context) {
    final legende = styleTransverse(TaillesContenu.t13, couleur: Ardoise.c500);
    Widget carre(Color fond, Color bord) => Container(
      width: MesuresTransverses.legendeMatrice,
      height: MesuresTransverses.legendeMatrice,
      decoration: BoxDecoration(
        color: fond,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: bord),
      ),
    );
    Widget entree(Widget c, String t) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        c,
        const SizedBox(width: AppSpacing.xxs),
        Text(t, style: legende),
      ],
    );

    Widget cellule(NiveauAcces n) {
      final (fond, couleur) = switch (n) {
        NiveauAcces.complet => (
          PaletteTransverse.vert50,
          PaletteTransverse.vert700,
        ),
        NiveauAcces.lecture => (
          PaletteTransverse.bleu50,
          PaletteTransverse.bleu700,
        ),
        NiveauAcces.aucun => (Ardoise.c50, Ardoise.c300),
      };
      return Container(
        width: MesuresTransverses.celluleMatrice,
        height: MesuresTransverses.celluleMatrice,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: fond,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Text(
          n.code,
          style: styleTransverse(
            TaillesContenu.t15,
            poids: FontWeight.bold,
            couleur: couleur,
            interligne: AppLayout.interligneContenu,
          ),
        ),
      );
    }

    final modules = libellesModulesMatrice.entries.toList();
    return CarteTransverse(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.mdPlus,
              vertical: AppSpacing.md,
            ),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Ardoise.c100)),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: AppSpacing.xs,
              children: [
                Text(
                  TextesRoles.matriceTitre,
                  style: styleTransverse(
                    TaillesContenu.sm,
                    poids: FontWeight.bold,
                    couleur: Ardoise.c700,
                  ),
                ),
                Wrap(
                  spacing: AppSpacing.sm,
                  children: [
                    entree(
                      carre(
                        PaletteTransverse.vert100,
                        PaletteTransverse.vert300,
                      ),
                      TextesRoles.legendeComplet,
                    ),
                    entree(
                      carre(PaletteMaitre.bleu100, PaletteMaitre.bleu300),
                      TextesRoles.legendeLecture,
                    ),
                    entree(
                      carre(Ardoise.c100, Ardoise.c300),
                      TextesRoles.legendeAucun,
                    ),
                  ],
                ),
              ],
            ),
          ),
          TableauTransverse(
            majuscules: false,
            largeurs: {
              0: MesuresTransverses.colonneModuleMatrice,
              for (var i = 1; i <= roles.length; i++)
                i: MesuresTransverses.colonneRoleMatrice,
            },
            colonnes: [
              (titre: TextesRoles.colModule, alignement: TextAlign.left),
              for (final r in roles)
                (titre: libelleRole(r.libelle), alignement: TextAlign.center),
            ],
            vide: TextesRoles.referentielVide,
            lignes: [
              for (final m in modules)
                [
                  celluleTexte(
                    m.value,
                    poids: FontWeight.w600,
                    couleur: Ardoise.c700,
                    taille: TaillesContenu.t15,
                  ),
                  for (final r in roles) cellule(r.droits.niveau(m.key)),
                ],
            ],
          ),
        ],
      ),
    );
  }
}
