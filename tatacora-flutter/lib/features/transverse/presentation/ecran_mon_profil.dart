// Vue Blade maîtresse (PA-183) : pwa/transverse/mon-profil.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/providers.dart';
import '../../../core/navigation/coquille_vue.dart';
import '../../../core/rbac/garde_acces.dart';
import '../../../core/theme/app_breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/mesures_transverses.dart';
import 'providers_transverses.dart';
import 'widgets/briques_transverses.dart';

/// L'écran **Mon profil** — lot D du plan du Product Owner (14/10/2026).
///
/// Structure de la vue, dans son ordre : en-tête ; métadonnées de session
/// (avatar aux initiales, login, rôle, trois cartes) ; informations
/// personnelles et mot de passe côte à côte ; journal d'audit des dernières
/// actions.
///
/// ## Ce qui vient du poste, et ce qui y manque (D422)
///
/// - **Login, rôle, initiales** : la session locale (`SessionRepositoryLocal`),
///   mises en forme comme la barre supérieure (`initialesDeLogin`,
///   `roleAffiche`).
/// - **Statut du compte** : `utilisateurs_local.actif`, relu (« Actif » /
///   « Désactivé », couleurs de `MonProfil::STATUTS`) ; « — » si la lecture
///   échoue.
/// - **Dernière connexion, adresse IP** : « — » — le poste ne relève ni l'une
///   ni l'autre (Article 7 de la vue : jamais une date inventée).
/// - **Nom complet** : la vue lit la fiche RH ; ce poste n'a pas de lien
///   compte → employé, il affiche le NOM DU COMPTE saisi à sa création
///   (`utilisateurs_local.nom`). Écart nommé.
/// - **Fonction** : « — » (aucune fiche RH rattachée).
/// - **Mot de passe** : aucun écran de ce poste ne le change ; le bouton est
///   rendu et DIT qu'il n'y a pas de geste (Article 3.3).
/// - **Journal d'audit** : ce poste n'en tient pas ; le tableau dit pourquoi
///   il est vide, au lieu de « Aucune action tracée » qui se lirait comme
///   « vous n'avez rien fait ».
class EcranMonProfil extends ConsumerWidget {
  const EcranMonProfil({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final droits = ref.watch(droitsProvider);
    final actif = ref.watch(compteSessionActifProvider);
    final large = MediaQuery.sizeOf(context).width >= AppBreakpoints.lg;

    final statut = switch (actif) {
      AsyncData(value: true) => (TextesProfil.statutActif, AppColors.succes),
      AsyncData(value: false) => (
        TextesProfil.statutDesactive,
        AppColors.erreur,
      ),
      _ => (TextesProfil.tiret, AppColors.navy),
    };

    final infos = _Informations(
      nom: session?.nom,
      versRoles: () {
        if (droits.peutLire(ModuleTatacora.roles)) {
          GoRouter.of(context).go('/roles-permissions');
        } else {
          direTransverse(context, LibellesCoquille.sansDroit);
        }
      },
    );
    const motDePasse = _MotDePasse();

    return PageTransverse(
      largeurMax: MesuresTransverses.pageProfil,
      enfants: [
        const EnTeteTransverse(
          trace: TracesCoquille.monProfil,
          titre: TextesProfil.titre,
          sousTitre: TextesProfil.sousTitre,
        ),
        _Metadonnees(
          login: session?.login,
          role: session == null ? null : roleAffiche(session.role),
          statut: statut.$1,
          couleurStatut: statut.$2,
        ),
        const SizedBox(height: AppSpacing.mdPlus), // mb-5
        if (large)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: infos),
                const SizedBox(width: AppSpacing.mdPlus),
                const Expanded(child: motDePasse),
              ],
            ),
          )
        else ...[
          infos,
          const SizedBox(height: AppSpacing.mdPlus),
          motDePasse,
        ],
        const SizedBox(height: AppSpacing.mdPlus),
        _JournalProfil(
          versJournal: () {
            if (droits.peutLire(ModuleTatacora.m14Etats)) {
              GoRouter.of(context).go('/journal-audit');
            } else {
              direTransverse(context, LibellesCoquille.sansDroit);
            }
          },
        ),
      ],
    );
  }
}

/// Les textes de la vue (`pwa.profil.*`), au mot.
abstract final class TextesProfil {
  static const String titre = 'Mon profil';
  static const String sousTitre =
      'Vos informations personnelles, votre mot de passe et la trace de vos dernières actions dans le système.';
  static const String metadonnees = 'MÉTADONNÉES DE SESSION';
  static const String derniereConnexion = 'Dernière connexion';
  static const String adresseIp = 'Adresse IP du poste';
  static const String statutCompte = 'Statut du compte';
  static const String noteIp =
      "L'adresse IP affichée est celle relevée par le poste. Sur l'application réelle elle vient du serveur : une adresse déclarée par le navigateur ne prouve rien et ne doit jamais servir de contrôle d'accès.";
  static const String infosTitre = 'Informations personnelles';
  static const String nomComplet = 'Nom complet';
  static const String email = 'Email';
  static const String telephone = 'Téléphone';
  static const String fonction = 'Fonction';
  static const String exempleEmail = 'ex. nom@tatacora.com';
  static const String exempleTelephone = '+229 01 XX XX XX XX';
  static const String noteFonctionAvant =
      "La fonction et les droits d'accès (RBAC) sont gérés par l'administrateur système — voir ";
  static const String noteFonctionLien = 'Rôles & Permissions';
  static const String noteFonctionApres =
      '. Un utilisateur qui pourrait modifier sa propre fonction contournerait la matrice de droits en un clic.';
  static const String sansColonne = 'Non porté par le schéma.';
  static const String mdpTitre = 'Modifier le mot de passe';
  static const String mdpSousTitre =
      'Le changement est immédiat et ne ferme pas votre session.';
  static const String mdpOuvrir = 'Modifier le mot de passe';
  static const String journalTitre = "Journal d'audit — 10 dernières actions";
  static const String journalSousTitre =
      'Vos actions uniquement. Le journal complet, tous utilisateurs, est réservé aux profils qui y ont droit.';
  static const String journalComplet = 'Journal complet →';
  static const String colDateHeure = 'DATE / HEURE';
  static const String colAction = 'ACTION';
  static const String colModule = 'MODULE';
  static const String colIp = 'IP';

  /// `MonProfil::STATUTS`.
  static const String statutActif = 'Actif';
  static const String statutDesactive = 'Désactivé';
  static const String tiret = '—';

  /// AJOUTS déclarés (D422).
  static const String sansFicheRhPoste =
      'Sur ce poste : nom saisi à la création du compte — aucune fiche '
      'employé ne lui est rattachée.';
  static const String mdpSansGeste =
      "Le changement de mot de passe n'est pas disponible sur ce poste : "
      "aucun écran ne l'écrit encore. Rien n'a été modifié.";
  static const String journalSurCePoste =
      "Ce poste ne tient pas de journal d'audit : aucune action n'y est "
      'tracée.';
}

TextStyle get _etiquette =>
    styleTransverse(TaillesContenu.t12, couleur: Ardoise.c500);

class _Metadonnees extends StatelessWidget {
  const _Metadonnees({
    required this.login,
    required this.role,
    required this.statut,
    required this.couleurStatut,
  });

  final String? login;
  final String? role;
  final String statut;
  final Color couleurStatut;

  @override
  Widget build(BuildContext context) {
    final large = MediaQuery.sizeOf(context).width >= AppBreakpoints.sm;
    Widget meta(String titre, String valeur, Color couleur, {Key? cle}) =>
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.smPlus,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: Ardoise.c50,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: Ardoise.c100),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titre, style: _etiquette),
              const SizedBox(height: AppSpacing.demi),
              Text(
                valeur,
                key: cle,
                style: styleTransverse(
                  TaillesContenu.t15,
                  poids: FontWeight.w600,
                  couleur: couleur,
                  police: AppTextStyles.policeMonospace,
                ),
              ),
            ],
          ),
        );

    final cartes = [
      meta(
        TextesProfil.derniereConnexion,
        TextesProfil.tiret,
        AppColors.navy,
        cle: const Key('profil-meta-connexion'),
      ),
      meta(
        TextesProfil.adresseIp,
        TextesProfil.tiret,
        AppColors.navy,
        cle: const Key('profil-meta-ip'),
      ),
      meta(
        TextesProfil.statutCompte,
        statut,
        couleurStatut,
        cle: const Key('profil-meta-statut'),
      ),
    ];

    return CarteTransverse(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: MesuresTransverses.avatarProfil,
                height: MesuresTransverses.avatarProfil,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.gold,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  login == null ? TextesProfil.tiret : initialesDeLogin(login!),
                  key: const Key('profil-avatar'),
                  style: styleTransverse(
                    TaillesContenu.lg,
                    poids: FontWeight.bold,
                    couleur: AppColors.neutre0,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      login ?? TextesProfil.tiret,
                      key: const Key('profil-login'),
                      style: styleTransverse(
                        TaillesContenu.base,
                        poids: FontWeight.bold,
                        couleur: AppColors.navy,
                      ),
                    ),
                    Text(
                      role ?? TextesProfil.tiret,
                      key: const Key('profil-role'),
                      style: styleTransverse(
                        TaillesContenu.t13,
                        couleur: Ardoise.c500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            TextesProfil.metadonnees,
            style:
                styleTransverse(
                  TaillesContenu.t13,
                  poids: FontWeight.bold,
                  couleur: Ardoise.c400,
                ).copyWith(
                  letterSpacing:
                      AppTextStyles.suiviPlusLarge * TaillesContenu.t13,
                ),
          ),
          const SizedBox(height: AppSpacing.xsPlus),
          if (large)
            Row(
              children: [
                for (final (i, c) in cartes.indexed) ...[
                  if (i > 0) const SizedBox(width: AppSpacing.sm),
                  Expanded(child: c),
                ],
              ],
            )
          else
            for (final (i, c) in cartes.indexed) ...[
              if (i > 0) const SizedBox(height: AppSpacing.sm),
              c,
            ],
          const SizedBox(height: AppSpacing.xsPlus),
          Text(
            TextesProfil.noteIp,
            style: styleTransverse(TaillesContenu.t12, couleur: Ardoise.c400),
          ),
        ],
      ),
    );
  }
}

/// « Informations personnelles » : quatre champs en LECTURE (la vue les rend
/// en `<p>` grisés), puis l'encart bleu de la fonction.
class _Informations extends StatelessWidget {
  const _Informations({required this.nom, required this.versRoles});

  final String? nom;
  final VoidCallback versRoles;

  @override
  Widget build(BuildContext context) {
    Widget champ(
      String libelle,
      String valeur, {
      String? note,
      Key? cle,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.smPlus),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            libelle,
            style: styleTransverse(
              TaillesContenu.t15,
              poids: FontWeight.w600,
              couleur: Ardoise.c700,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xsPlus,
            ),
            decoration: BoxDecoration(
              color: Ardoise.c100,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: Ardoise.c200),
            ),
            child: Text(
              valeur,
              key: cle,
              style: styleTransverse(TaillesContenu.sm, couleur: Ardoise.c600),
            ),
          ),
          if (note != null) ...[
            const SizedBox(height: AppSpacing.unit),
            Text(
              note,
              style: styleTransverse(TaillesContenu.t12, couleur: Ardoise.c400),
            ),
          ],
        ],
      ),
    );

    final bleu = styleTransverse(
      TaillesContenu.t13,
      couleur: PaletteMaitre.bleu900,
    );
    return CarteTransverse(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            TextesProfil.infosTitre,
            style: styleTransverse(
              TaillesContenu.sm,
              poids: FontWeight.bold,
              couleur: Ardoise.c700,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          champ(
            TextesProfil.nomComplet,
            (nom == null || nom!.trim().isEmpty) ? TextesProfil.tiret : nom!,
            note: TextesProfil.sansFicheRhPoste,
            cle: const Key('profil-nom-complet'),
          ),
          champ(
            TextesProfil.email,
            TextesProfil.tiret,
            note: '${TextesProfil.sansColonne} ${TextesProfil.exempleEmail}',
          ),
          champ(
            TextesProfil.telephone,
            TextesProfil.tiret,
            note:
                '${TextesProfil.sansColonne} ${TextesProfil.exempleTelephone}',
          ),
          champ(TextesProfil.fonction, TextesProfil.tiret),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xsPlus,
            ),
            decoration: BoxDecoration(
              color: AppColors.badgeBleuFond,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Wrap(
              children: [
                Text(TextesProfil.noteFonctionAvant, style: bleu),
                InkWell(
                  key: const Key('profil-lien-roles'),
                  onTap: versRoles,
                  child: Text(
                    TextesProfil.noteFonctionLien,
                    style: bleu.copyWith(
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
                Text(TextesProfil.noteFonctionApres, style: bleu),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// « Modifier le mot de passe » : titre, sous-titre et le bouton doré.
class _MotDePasse extends StatelessWidget {
  const _MotDePasse();

  @override
  Widget build(BuildContext context) => CarteTransverse(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          TextesProfil.mdpTitre,
          style: styleTransverse(
            TaillesContenu.sm,
            poids: FontWeight.bold,
            couleur: Ardoise.c700,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          TextesProfil.mdpSousTitre,
          style: styleTransverse(TaillesContenu.t13, couleur: Ardoise.c500),
        ),
        const SizedBox(height: AppSpacing.md),
        BoutonTransverse(
          cle: const Key('profil-mdp-ouvrir'),
          libelle: TextesProfil.mdpOuvrir,
          fond: AppColors.gold,
          taille: TaillesContenu.sm,
          pleineLargeur: true,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.mdPlus,
            vertical: AppSpacing.xsPlus,
          ),
          onTap: () => direTransverse(
            context,
            TextesProfil.mdpSansGeste,
            cle: const Key('profil-mdp-message'),
          ),
        ),
      ],
    ),
  );
}

/// Le journal des dernières actions : titre, « Journal complet → », tableau à
/// en-tête navy, et la raison de son vide.
class _JournalProfil extends StatelessWidget {
  const _JournalProfil({required this.versJournal});

  final VoidCallback versJournal;

  @override
  Widget build(BuildContext context) => CarteTransverse(
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
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      TextesProfil.journalTitre,
                      style: styleTransverse(
                        TaillesContenu.sm,
                        poids: FontWeight.bold,
                        couleur: Ardoise.c700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.demi),
                    Text(
                      TextesProfil.journalSousTitre,
                      style: styleTransverse(
                        TaillesContenu.t12,
                        couleur: Ardoise.c500,
                      ),
                    ),
                  ],
                ),
              ),
              InkWell(
                key: const Key('profil-journal-complet'),
                onTap: versJournal,
                child: Text(
                  TextesProfil.journalComplet,
                  style: styleTransverse(
                    TaillesContenu.t13,
                    poids: FontWeight.w600,
                    couleur: AppColors.navy,
                  ),
                ),
              ),
            ],
          ),
        ),
        const TableauTransverse(
          colonnes: [
            (titre: TextesProfil.colDateHeure, alignement: TextAlign.left),
            (titre: TextesProfil.colAction, alignement: TextAlign.left),
            (titre: TextesProfil.colModule, alignement: TextAlign.left),
            (titre: TextesProfil.colIp, alignement: TextAlign.left),
          ],
          lignes: [],
          vide: TextesProfil.journalSurCePoste,
          cleVide: Key('profil-journal-vide'),
        ),
      ],
    ),
  );
}
