// Vue Blade maîtresse (PA-183) : pwa/transverse/aide-a-propos.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/providers.dart';
import '../../../core/navigation/coquille_vue.dart';
import '../../../core/navigation/navigation_tatacora.dart';
import '../../../core/navigation/trace_svg.dart';
import '../../../core/rbac/garde_acces.dart';
import '../../../core/theme/app_assets.dart';
import '../../../core/theme/app_breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/mesures_transverses.dart';
import 'widgets/briques_transverses.dart';

/// L'écran **Aide & À propos** — lot D du plan du Product Owner (14/10/2026).
///
/// Contenu STATIQUE de la vue (`pwa.aide.*`), au mot, dans son ordre :
/// en-tête ; présentation sur fond navy (logo `AppAssets.logo`, marque,
/// « Système de gestion Intégré — … », deux paragraphes, quatre cartes) ;
/// modules du logiciel (seize cartes, droit de la SESSION) ; foire aux
/// questions filtrée par la recherche ; ressources ; bandeau de contact.
///
/// ## Écarts nommés (14/10/2026, D420)
///
/// - **Cartes M12 et M13** : la vue les rend en `<span>` « Écran de
///   consultation à venir dans la PWA » (`AideAPropos::ROUTES_MODULES` n'a ni
///   M12 ni M13 alors que la PWA sert `/notifications` et `/paie` : registre
///   périmé du serveur, à remonter). Ce poste a les deux écrans : la carte y
///   mène.
/// - **Phrases fausses sur ce poste** : la présentation (« se synchronise au
///   retour de la liaison ») et cinq réponses de la FAQ décrivent le serveur,
///   la synchronisation ou le prototype. La phrase de la vue est rendue au
///   mot, suivie d'une ligne « Sur ce poste : … » qui dit le vrai (même
///   forme que les corrections des Paramètres, piège 14) — SAUF la réponse
///   « … sans réseau ? », qui affirme un statut « en attente de
///   synchronisation » qu'aucun écran de ce poste n'a le droit d'afficher :
///   elle est REMPLACÉE par la phrase vraie.
/// - **« Modèles d'import »** : la vue la rend inerte (`hors_perimetre`) ;
///   ici le clic DIT que l'import n'existe pas sur ce poste (Article 3.3).
class EcranAideAPropos extends ConsumerStatefulWidget {
  const EcranAideAPropos({super.key});

  @override
  ConsumerState<EcranAideAPropos> createState() => _EcranAideAProposState();
}

/// Les textes de la vue (`lang/fr/pwa.php`, groupe `aide`), au mot.
abstract final class TextesAide {
  static const String titre = 'Aide & À propos';
  static const String sousTitre =
      'Documentation complète, guide des modules et foire aux questions.';
  static const String enseigne =
      'Système de gestion Intégré — Gîte Chez Noël, Natitingou (Bénin)';
  static const String presentation1 =
      "TATACORA AFRIQUE réunit en une seule application les quatorze métiers du Gîte : l'hébergement et les réservations, la restauration et le bar, les stocks et les achats, le tourisme et la location de véhicules, la comptabilité SYSCOHADA révisé, la paie et le pilotage.";
  static const String presentation2Avant = "L'ensemble est conçu ";
  static const String presentation2Fort = "hors connexion d'abord";
  static const String presentation2Apres =
      " : la saisie fonctionne sans réseau et se synchronise au retour de la liaison. C'est une contrainte du terrain à Natitingou, pas une option de confort — une réservation prise pendant une coupure ne doit pas être perdue, et un guide en circuit de plusieurs jours travaille sans couverture.";
  static const String versionTitre = 'Version du prototype';
  static const String versionValeur = 'Maquette de référence v2.0 — 18/08/2026';
  static const String moeTitre = "Maîtrise d'œuvre";
  static const String moeValeur = 'Cabinet FAGUEZ SARL / PAEB';
  static const String poTitre = 'Product Owner';
  static const String poValeur = 'Mr NABOGOU Winribasse Noël';
  static const String referentielTitre = 'Référentiel comptable';
  static const String referentielValeur = 'SYSCOHADA révisé (AUDCIF)';
  static const String modulesTitre = 'Modules du logiciel';
  static const String modulesSousTitre =
      "Quatorze modules, plus l'administration. Cliquez sur une carte pour ouvrir le module.";
  static String modulesCompteur(int accessibles, int total) =>
      '$accessibles module(s) accessible(s) sur $total avec votre profil';
  static const String modulesNote =
      "Les modules sur lesquels votre profil n'a aucun droit sont affichés en grisé et ne sont pas cliquables. Ils restent visibles ici — savoir qu'un module existe n'est pas y accéder, et masquer la carte laisserait croire à une application incomplète.";
  static const String badgeLecture = 'LECTURE';
  static const String badgeSansAcces = 'SANS ACCÈS';
  static const String sansAccesTitre = "Votre profil n'a pas accès à ce module";
  static const String faqTitre = 'Foire aux questions';
  static const String faqSousTitre =
      'Les questions qui reviennent le plus souvent en formation et en exploitation.';
  static const String faqRecherche = "Rechercher dans l'aide…";
  static const String faqVide =
      'Aucune réponse ne correspond à cette recherche.';
  static const String ressourcesTitre = 'Ressources utiles';
  static const String modelesImportTitre = "Modèles d'import";
  static const String modelesImportDetail =
      "Fichiers d'exemple par module, colonnes et libellés attendus.";
  static const String journalAuditTitre = "Journal d'audit";
  static const String journalAuditDetail =
      'Qui a fait quoi, quand, depuis quel poste.';
  static const String rolesTitre = 'Rôles & permissions';
  static const String rolesDetail =
      'La matrice des droits, module par module et rôle par rôle.';
  static const String contactTitre = 'Vous ne trouvez pas de réponse ?';
  static const String contactDetail =
      "Contactez l'éditeur : assistance technique, suggestions d'évolution et signalement d'anomalies.";
  static const String contactBouton = "Contacter l'éditeur";
}

/// Une carte de module : `pwa.aide.modules.<code>`, la route de CE poste.
typedef _ModuleAide = ({
  ModuleTatacora module,
  String trace,
  String nom,
  String description,
  String route,
});

final List<_ModuleAide> _modules = [
  (
    module: ModuleTatacora.m1Hebergement,
    trace: IconeModule.hebergement.trace,
    nom: 'Hébergement & Réservations',
    description:
        'Unités, disponibilités, séjours et check-in. Contrôle de chevauchement : deux réservations ne peuvent pas occuper la même chambre aux mêmes dates.',
    route: '/hebergement',
  ),
  (
    module: ModuleTatacora.m2Facturation,
    trace: IconeModule.facturation.trace,
    nom: 'Facturation',
    description:
        'Factures normalisées MECeF, avoirs et suivi de certification DGI. Une facture validée ne se modifie pas : elle se corrige par avoir.',
    route: '/facturation',
  ),
  (
    module: ModuleTatacora.m3Crm,
    trace: IconeModule.crm.trace,
    nom: 'Clients & Créances',
    description:
        'Fiche client unique et balance âgée. Le solde est calculé depuis les pièces, jamais saisi à la main.',
    route: '/crm',
  ),
  (
    module: ModuleTatacora.m4Restaurant,
    trace: IconeModule.restaurant.trace,
    nom: 'Restaurant',
    description:
        "Carte, fiches techniques et disponibilité des plats. Un plat sans fiche technique ne décrémente aucun stock, et c'est signalé.",
    route: '/restaurant',
  ),
  (
    module: ModuleTatacora.m5Bar,
    trace: IconeModule.bar.trace,
    nom: 'Bar & Point de vente',
    description:
        "Carte des boissons et encaissement au POS. La vente d'une boisson sort l'article du stock au coût moyen pondéré.",
    route: '/bar',
  ),
  (
    module: ModuleTatacora.m6Stocks,
    trace: IconeModule.stocks.trace,
    nom: 'Stocks',
    description:
        "Articles, mouvements, inventaires et seuils d'alerte. Valorisation au coût moyen pondéré, recalculée à chaque entrée.",
    route: '/stocks',
  ),
  (
    module: ModuleTatacora.m7Achats,
    trace: IconeModule.achats.trace,
    nom: 'Achats & Fournisseurs',
    description:
        "Commandes, réceptions et fournisseurs. La réception d'une commande alimente le stock et la comptabilité.",
    route: '/fournisseurs',
  ),
  (
    module: ModuleTatacora.m8Vehicules,
    trace: IconeModule.vehicules.trace,
    nom: 'Véhicules & Locations',
    description:
        "Parc, contrats de location, entretiens et disponibilité. Un véhicule loué ou en entretien n'est pas proposé ailleurs.",
    route: '/vehicules',
  ),
  (
    module: ModuleTatacora.m9Tourisme,
    trace: IconeModule.tourisme.trace,
    nom: 'Tourisme',
    description:
        'Circuits, départs, guides et capacités. La capacité se contrôle cumulée sur le départ, pas réservation par réservation.',
    route: '/tourisme',
  ),
  (
    module: ModuleTatacora.m10Comptabilite,
    trace: IconeModule.comptabilite.trace,
    nom: 'Comptabilité SYSCOHADA',
    description:
        'Plan comptable, journal, grand livre, balance, compte de résultat et bilan. Une écriture validée se corrige par contre-passation.',
    route: '/comptabilite',
  ),
  (
    module: ModuleTatacora.m11TableauxDeBord,
    trace: IconeModule.dashboard.trace,
    nom: 'Tableau de bord',
    description:
        "Indicateurs consolidés de toute l'exploitation. Les intitulés disent ce qui est réellement calculé — « encaissé », pas « payé ».",
    route: '/tableau-de-bord',
  ),
  (
    module: ModuleTatacora.m12Notifications,
    trace: IconeModule.notifications.trace,
    nom: 'Notifications',
    description:
        "Modèles de messages WhatsApp, e-mail et Android, et leurs déclencheurs. L'envoi effectif dépend d'une API non encore contractée.",
    route: '/notifications',
  ),
  (
    module: ModuleTatacora.m13Rh,
    trace: IconeModule.rh.trace,
    nom: 'Personnel & Paie',
    description:
        'Employés, planning, congés et bulletins. CNSS, ITS et VPS calculés ; la part de charge patronale non confirmée est refusée, pas estimée.',
    route: '/paie',
  ),
  (
    module: ModuleTatacora.m14Etats,
    trace: IconeModule.etats.trace,
    nom: 'États & Rapports',
    description:
        "Catalogue d'états exportables en PDF et CSV, avec en-tête normalisée unique. Le droit d'éditer un état suit son module source.",
    route: '/etats',
  ),
  (
    module: ModuleTatacora.roles,
    trace: IconeModule.roles.trace,
    nom: 'Rôles & Permissions',
    description:
        "Matrice des droits par module et par rôle. Trois niveaux : masquage de l'interface, contrôle serveur, filtrage en base.",
    route: '/roles-permissions',
  ),
  (
    module: ModuleTatacora.parametres,
    trace: IconeModule.parametres.trace,
    nom: 'Paramètres & Import/Export',
    description:
        "Identité de l'entreprise, canaux de communication, activation des actions sensibles, sauvegardes et restauration.",
    route: '/parametres',
  ),
];

/// Une entrée de la FAQ (`pwa.aide.faq`).
typedef _EntreeFaq = ({
  String categorie,
  String question,
  String reponse,
});

const List<_EntreeFaq> _faq = [
  (
    categorie: 'Prise en main',
    question: 'Je ne vois pas un module dans le menu — est-ce une erreur ?',
    reponse:
        "Non. Le menu est filtré par votre rôle : un module sur lequel vous n'avez aucun droit est retiré, pas grisé. Un élément grisé invite à cliquer et ne produit qu'un refus. Pour savoir ce que couvre chaque profil, ouvrez Rôles & Permissions ; pour obtenir un accès, la demande passe par l'administrateur système.",
  ),
  (
    categorie: 'Prise en main',
    question: 'Pourquoi certains montants ne sont-ils pas modifiables ?',
    reponse:
        "Toute valeur calculable est affichée en lecture seule : stock disponible, total d'une réservation, net à payer, résultat de l'exercice. Un champ calculé que l'on peut saisir finit par contredire le calcul, et c'est la saisie qui gagne — on ne sait alors plus quel chiffre est le bon. Pour changer un total, changez ce qui le produit : les quantités, les dates, les tarifs.",
  ),
  (
    categorie: 'Données',
    question: "J'ai supprimé une fiche par erreur. Est-elle perdue ?",
    reponse:
        "Non. Dans tous les modules, « supprimer » archive : l'enregistrement complet part aux archives et reste restaurable depuis Import & Export › Restaurer. Seul un administrateur peut purger définitivement une archive, et c'est le seul endroit de l'application où une donnée disparaît vraiment.",
  ),
  (
    categorie: 'Données',
    question: "Pourquoi le bouton Supprimer n'apparaît-il pas ?",
    reponse:
        "La suppression et la duplication sont désactivées par défaut, pour toute l'application. Un administrateur les ouvre dans Paramètres › Activation & Sécurité, et son choix est tracé au journal d'audit. Sur un outil d'exploitation, l'action destructrice ne doit pas être à portée de clic par défaut.",
  ),
  (
    categorie: 'Données',
    question: "Je n'arrive pas à archiver une boisson ou un plat.",
    reponse:
        "C'est un refus volontaire : l'élément est engagé dans une réservation ou une vente encaissée. L'archiver laisserait une ligne pointant vers le vide, et le montant facturé deviendrait inexplicable lors d'un contrôle. Le message précise les opérations concernées. Pour retirer l'article de la carte sans toucher à l'historique, passez-le en indisponible.",
  ),
  (
    categorie: 'Import & export',
    question: "Mon fichier d'import est refusé. Que dois-je faire ?",
    reponse:
        "Téléchargez d'abord le modèle du module concerné dans Import & Export › Importer : il porte les colonnes et les libellés exacts attendus. Après dépôt, un contrôle de cohérence compare votre fichier au référentiel et liste les écarts ligne par ligne — colonne manquante, valeur hors liste, doublon, montant illisible. Corrigez le fichier et redéposez-le : rien n'est importé tant qu'une erreur bloquante subsiste.",
  ),
  (
    categorie: 'Import & export',
    question: 'À quelle fréquence dois-je sauvegarder la base ?',
    reponse:
        "Une sauvegarde est générée automatiquement chaque semaine et vous êtes averti de la télécharger. Une sauvegarde qui reste sur la machine ne protège de rien : c'est le téléchargement qui la met à l'abri. Vous pouvez en générer une à tout moment depuis Import & Export › Sauvegardes, avant une opération sensible par exemple.",
  ),
  (
    categorie: 'Comptabilité',
    question: 'Puis-je corriger une écriture comptable validée ?',
    reponse:
        "Non, et c'est une règle du référentiel SYSCOHADA, pas une limite de l'outil. Une écriture validée est immuable ; la correction passe exclusivement par une contre-passation, qui laisse les deux écritures visibles. Modifier ou supprimer effacerait la trace de l'erreur, ce qu'un contrôle fiscal considère comme une anomalie plus grave que l'erreur elle-même.",
  ),
  (
    categorie: 'Comptabilité',
    question:
        "Pourquoi le total des charges patronales n'est-il pas affiché sur les bulletins ?",
    reponse:
        "Parce qu'un de ses taux n'est pas confirmé. La CNSS annonce un taux « risques professionnels » de 1 % à 4 % selon l'activité, sans valeur publiée pour l'hôtellerie-restauration. La part établie — 19,4 % du brut : pension 6,4 %, prestations familiales 9 %, VPS 4 % — est calculée et affichée. Pour le reste, l'application publie la fourchette au lieu de retenir un milieu : un taux plausible inscrit une fois devient la règle appliquée en production, et personne ne le rouvre.",
  ),
  (
    categorie: 'Hors connexion',
    question: 'Que se passe-t-il si je saisis une réservation sans réseau ?',
    // La réponse de la vue décrit un statut d'attente de synchronisation et
    // un rejet par le serveur, que ce poste n'affiche pas : phrase vraie, à la
    // place (14/10/2026).
    reponse:
        'Elle est enregistrée immédiatement dans la base locale et y reste. '
        'Le contrôle de chevauchement porte sur les réservations du poste.',
  ),
  (
    categorie: 'Hors connexion',
    question: 'Deux postes ont modifié la même fiche. Laquelle gagne ?',
    reponse:
        "Sur les données non financières, la plus récente. Sur les factures, paiements, mouvements de caisse et mouvements de stock, aucune résolution automatique n'a lieu : le conflit part dans une file d'arbitrage manuel, réservée aux profils gérant, comptable et administrateur. Choisir automatiquement entre deux montants revient à en effacer un sans que personne ne le sache.",
  ),
  (
    categorie: 'Sécurité',
    question: 'Où sont stockées mes données ?',
    reponse:
        "Sur ce prototype, dans le navigateur du poste (localStorage) — c'est une maquette de démonstration, pas un environnement de production. L'application réelle stocke sur un serveur MySQL, avec sauvegarde quotidienne automatique. Ne saisissez aucune donnée client réelle dans le prototype.",
  ),
];

class _EcranAideAProposState extends ConsumerState<EcranAideAPropos> {
  final _recherche = TextEditingController();
  String _terme = '';

  @override
  void dispose() {
    _recherche.dispose();
    super.dispose();
  }

  /// `AideAPropos::faq()` : `mb_strtolower`, `str_contains` sur la question OU
  /// la réponse, puis regroupement par catégorie dans l'ordre d'apparition.
  Map<String, List<_EntreeFaq>> _faqFiltree() {
    final terme = _terme.toLowerCase();
    final groupes = <String, List<_EntreeFaq>>{};
    for (final e in _faq) {
      if (terme.isNotEmpty &&
          !e.question.toLowerCase().contains(terme) &&
          !e.reponse.toLowerCase().contains(terme)) {
        continue;
      }
      (groupes[e.categorie] ??= []).add(e);
    }
    return groupes;
  }

  @override
  Widget build(BuildContext context) {
    final droits = ref.watch(droitsProvider);
    return PageTransverse(
      largeurMax: MesuresTransverses.pageEtroite,
      enfants: [
        const EnTeteTransverse(
          trace: TracesCoquille.aideAPropos,
          titre: TextesAide.titre,
          sousTitre: TextesAide.sousTitre,
        ),
        const _Presentation(),
        const SizedBox(height: AppSpacing.lg), // mb-6
        _Modules(droits: droits),
        const SizedBox(height: AppSpacing.xl), // mb-8
        _Faq(
          controleur: _recherche,
          groupes: _faqFiltree(),
          ouvertes: _terme.isNotEmpty,
          onRecherche: (v) => setState(() => _terme = v),
        ),
        const SizedBox(height: AppSpacing.xl),
        _Ressources(droits: droits),
        const SizedBox(height: AppSpacing.xl),
        const _BandeauContact(),
      ],
    );
  }
}

/// `rounded-xl overflow-hidden mb-6` sur fond navy, `p-6 lg:p-8 grid
/// grid-cols-1 lg:grid-cols-3 gap-6`.
class _Presentation extends StatelessWidget {
  const _Presentation();

  @override
  Widget build(BuildContext context) {
    final large = MediaQuery.sizeOf(context).width >= AppBreakpoints.lg;
    final texte = styleTransverse(
      TaillesContenu.t15,
      couleur: AppColors.neutre0.withValues(alpha: PaletteTransverse.texteNavy),
      interligne: AppLayout.interligneDetendu,
    );

    final gauche = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: MesuresTransverses.logoAide,
              height: MesuresTransverses.logoAide,
              decoration: BoxDecoration(
                color: AppColors.neutre0,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: AppColors.gold,
                  width: AppLayout.anneauLogo,
                  strokeAlign: BorderSide.strokeAlignOutside,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Semantics(
                label: LibellesCoquille.altLogo,
                image: true,
                child: Image.asset(AppAssets.logo, fit: BoxFit.contain),
              ),
            ),
            const SizedBox(width: AppSpacing.sm), // gap-3
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    LibellesCoquille.marque,
                    style: styleTransverse(
                      TaillesContenu.base,
                      poids: FontWeight.bold,
                      couleur: AppColors.neutre0,
                    ),
                  ),
                  Text(
                    TextesAide.enseigne,
                    style: styleTransverse(
                      TaillesContenu.t13,
                      couleur: AppColors.gold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm), // mb-3
        Text(TextesAide.presentation1, style: texte),
        const SizedBox(height: AppSpacing.xsPlus), // mt-2.5
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: TextesAide.presentation2Avant),
              TextSpan(
                text: TextesAide.presentation2Fort,
                style: texte.copyWith(
                  color: AppColors.neutre0,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const TextSpan(text: TextesAide.presentation2Apres),
            ],
          ),
          style: texte,
        ),
      ],
    );

    Widget carte(String titre, String valeur, {bool mono = false}) => Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.neutre0.withValues(
          alpha: PaletteTransverse.fondCarteNavy,
        ),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titre,
            style: styleTransverse(
              TaillesContenu.t12,
              couleur: AppColors.neutre0.withValues(
                alpha: PaletteTransverse.libelleNavy,
              ),
            ),
          ),
          Text(
            valeur,
            style: styleTransverse(
              TaillesContenu.sm,
              poids: FontWeight.bold,
              couleur: AppColors.neutre0,
              police: mono ? AppTextStyles.policeMonospace : null,
            ),
          ),
        ],
      ),
    );

    final droite = Column(
      children: [
        carte(TextesAide.versionTitre, TextesAide.versionValeur, mono: true),
        const SizedBox(height: AppSpacing.xsPlus),
        carte(TextesAide.moeTitre, TextesAide.moeValeur),
        const SizedBox(height: AppSpacing.xsPlus),
        carte(TextesAide.poTitre, TextesAide.poValeur),
        const SizedBox(height: AppSpacing.xsPlus),
        carte(TextesAide.referentielTitre, TextesAide.referentielValeur),
      ],
    );

    return Container(
      padding: EdgeInsets.all(large ? AppSpacing.xl : AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: large
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(flex: 2, child: gauche),
                const SizedBox(width: AppSpacing.lg),
                Expanded(child: droite),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                gauche,
                const SizedBox(height: AppSpacing.lg),
                droite,
              ],
            ),
    );
  }
}

/// « Modules du logiciel » : `grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3
/// xl:grid-cols-4 gap-3.5`, une carte par module, son droit RÉEL.
class _Modules extends StatelessWidget {
  const _Modules({required this.droits});

  final GardeAcces droits;

  @override
  Widget build(BuildContext context) {
    final largeur = MediaQuery.sizeOf(context).width;
    final colonnes = largeur >= AppBreakpoints.xl
        ? MesuresTransverses.colonnesModulesXl
        : largeur >= AppBreakpoints.lg
        ? MesuresTransverses.colonnesModulesLg
        : largeur >= AppBreakpoints.sm
        ? MesuresTransverses.colonnesModulesSm
        : 1;
    final accessibles = _modules.where((m) => droits.peutLire(m.module)).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    TextesAide.modulesTitre,
                    style: styleTransverse(
                      TaillesContenu.base,
                      poids: FontWeight.bold,
                      couleur: AppColors.navy,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.demi),
                  Text(
                    TextesAide.modulesSousTitre,
                    style: styleTransverse(
                      TaillesContenu.t13,
                      couleur: Ardoise.c500,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              TextesAide.modulesCompteur(accessibles, _modules.length),
              key: const Key('aide-compteur-modules'),
              style: styleTransverse(TaillesContenu.t13, couleur: Ardoise.c400),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.smPlus), // mb-3.5
        GrilleTransverse(
          colonnes: colonnes,
          ecart: AppSpacing.smPlus,
          enfants: [
            for (final m in _modules)
              _CarteModule(module: m, niveau: droits.niveau(m.module)),
          ],
        ),
        const SizedBox(height: AppSpacing.sm), // mt-3
        Text(
          TextesAide.modulesNote,
          style: styleTransverse(TaillesContenu.t12, couleur: Ardoise.c400),
        ),
      ],
    );
  }
}

class _CarteModule extends StatelessWidget {
  const _CarteModule({required this.module, required this.niveau});

  final _ModuleAide module;
  final NiveauAcces niveau;

  @override
  Widget build(BuildContext context) {
    final ouvert = niveau.peutLire;
    final contenu = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: MesuresTransverses.pastilleModule,
              height: MesuresTransverses.pastilleModule,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: ouvert
                    ? AppColors.reserveGoldFond
                    : AppColors.badgeGrisFond,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: IconeTrace(
                trace: module.trace,
                taille: MesuresTransverses.iconeModule,
                couleur: ouvert ? AppColors.gold : AppColors.neutre400,
              ),
            ),
            const SizedBox(width: AppSpacing.xsPlus),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    module.nom,
                    style: styleTransverse(
                      TaillesContenu.t15,
                      poids: FontWeight.bold,
                      couleur: ouvert ? Ardoise.c800 : Ardoise.c400,
                      interligne: Tailles.interligneSerre,
                    ),
                  ),
                  Text(
                    module.module.code,
                    style: styleTransverse(
                      TaillesContenu.t12,
                      couleur: ouvert ? Ardoise.c400 : Ardoise.c300,
                      police: AppTextStyles.policeMonospace,
                    ),
                  ),
                ],
              ),
            ),
            if (!ouvert)
              const _Badge(
                TextesAide.badgeSansAcces,
                fond: Ardoise.c100,
                couleur: Ardoise.c400,
              )
            else if (niveau == NiveauAcces.lecture)
              const _Badge(
                TextesAide.badgeLecture,
                fond: AppColors.badgeBleuFond,
                couleur: AppColors.info,
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          module.description,
          style: styleTransverse(
            TaillesContenu.t13,
            couleur: ouvert ? Ardoise.c500 : Ardoise.c400,
            interligne: AppLayout.interligneDetendu,
          ),
        ),
      ],
    );

    if (!ouvert) {
      return Tooltip(
        message: TextesAide.sansAccesTitre,
        child: CarteTransverse(
          padding: const EdgeInsets.all(AppSpacing.md),
          fond: AppColors.neutre0.withValues(
            alpha: PaletteTransverse.carteSansDroit,
          ),
          bordure: Ardoise.c100,
          child: contenu,
        ),
      );
    }
    return InkWell(
      key: Key('aide-module-${module.module.code}'),
      borderRadius: BorderRadius.circular(AppRadius.lg),
      onTap: () => GoRouter.of(context).go(module.route),
      child: CarteTransverse(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: contenu,
      ),
    );
  }
}

/// `text-[10px] font-bold rounded px-1.5 py-0.5`.
class _Badge extends StatelessWidget {
  const _Badge(this.texte, {required this.fond, required this.couleur});

  final String texte;
  final Color fond;
  final Color couleur;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.xxs,
      vertical: AppSpacing.demi,
    ),
    decoration: BoxDecoration(
      color: fond,
      borderRadius: BorderRadius.circular(AppRadius.sm),
    ),
    child: Text(
      texte,
      style: styleTransverse(
        TaillesContenu.t10,
        poids: FontWeight.bold,
        couleur: couleur,
      ),
    ),
  );
}

/// « Foire aux questions » : titre, recherche (`sm:w-72`), catégories en
/// capitales et questions dépliables (`<details>`, ouvertes pendant une
/// recherche).
class _Faq extends StatelessWidget {
  const _Faq({
    required this.controleur,
    required this.groupes,
    required this.ouvertes,
    required this.onRecherche,
  });

  final TextEditingController controleur;
  final Map<String, List<_EntreeFaq>> groupes;
  final bool ouvertes;
  final ValueChanged<String> onRecherche;

  @override
  Widget build(BuildContext context) {
    final large = MediaQuery.sizeOf(context).width >= AppBreakpoints.sm;
    final titre = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          TextesAide.faqTitre,
          style: styleTransverse(
            TaillesContenu.base,
            poids: FontWeight.bold,
            couleur: AppColors.navy,
          ),
        ),
        const SizedBox(height: AppSpacing.demi),
        Text(
          TextesAide.faqSousTitre,
          style: styleTransverse(TaillesContenu.t13, couleur: Ardoise.c500),
        ),
      ],
    );
    final champ = SizedBox(
      width: large ? MesuresTransverses.rechercheFaq : double.infinity,
      child: TextField(
        key: const Key('aide-recherche-faq'),
        controller: controleur,
        onChanged: onRecherche,
        style: styleTransverse(TaillesContenu.t15),
        decoration: InputDecoration(
          isDense: true,
          hintText: TextesAide.faqRecherche,
          prefixIcon: const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: IconeTrace(
              trace: TracesCoquille.loupe,
              taille: MesuresTransverses.iconeBouton,
              couleur: AppColors.neutre400,
            ),
          ),
          prefixIconConstraints: const BoxConstraints(),
          filled: true,
          fillColor: AppColors.neutre0,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide: const BorderSide(color: Ardoise.c200),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide: const BorderSide(color: Ardoise.c200),
          ),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (large)
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: titre),
              const SizedBox(width: AppSpacing.sm),
              champ,
            ],
          )
        else ...[
          titre,
          const SizedBox(height: AppSpacing.sm),
          champ,
        ],
        const SizedBox(height: AppSpacing.smPlus),
        for (final entree in groupes.entries) ...[
          Padding(
            padding: const EdgeInsets.only(
              top: AppSpacing.md,
              bottom: AppSpacing.xxs,
            ),
            child: Text(
              entree.key.toUpperCase(),
              style:
                  styleTransverse(
                    TaillesContenu.t12,
                    poids: FontWeight.bold,
                    couleur: Ardoise.c400,
                  ).copyWith(
                    letterSpacing:
                        AppTextStyles.suiviPlusLarge * TaillesContenu.t12,
                  ),
            ),
          ),
          for (final q in entree.value)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: _Question(
                // La clé change avec l'état « ouvert » : `<details open>` se
                // rouvre à chaque recherche, comme la vue.
                key: ValueKey('${q.question}-$ouvertes'),
                entree: q,
                ouverte: ouvertes,
              ),
            ),
        ],
        if (groupes.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xlPlus),
            child: Text(
              TextesAide.faqVide,
              key: const Key('aide-faq-vide'),
              textAlign: TextAlign.center,
              style: styleTransverse(TaillesContenu.t15, couleur: Ardoise.c400),
            ),
          ),
      ],
    );
  }
}

class _Question extends StatefulWidget {
  const _Question({required this.entree, required this.ouverte, super.key});

  final _EntreeFaq entree;
  final bool ouverte;

  @override
  State<_Question> createState() => _QuestionState();
}

class _QuestionState extends State<_Question> {
  late bool _ouverte = widget.ouverte;

  @override
  Widget build(BuildContext context) {
    final e = widget.entree;
    return CarteTransverse(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _ouverte = !_ouverte),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.smPlus,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      e.question,
                      style: styleTransverse(
                        TaillesContenu.t15,
                        poids: FontWeight.w600,
                        couleur: Ardoise.c700,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  RotatedBox(
                    quarterTurns: _ouverte ? 2 : 0,
                    child: const IconeTrace(
                      trace: TracesCoquille.chevron,
                      taille: MesuresTransverses.iconePetite,
                      couleur: AppColors.neutre400,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_ouverte)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                0,
                AppSpacing.md,
                AppSpacing.md,
              ),
              child: Container(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Ardoise.c100)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.reponse,
                      style: styleTransverse(
                        TaillesContenu.t15,
                        couleur: Ardoise.c600,
                        interligne: AppLayout.interligneDetendu,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// « Ressources utiles » : `grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4
/// gap-3.5`, trois cartes (la quatrième, « Revoir mes alertes », n'est pas
/// rendue par la vue elle-même).
class _Ressources extends StatelessWidget {
  const _Ressources({required this.droits});

  final GardeAcces droits;

  @override
  Widget build(BuildContext context) {
    final largeur = MediaQuery.sizeOf(context).width;
    final colonnes = largeur >= AppBreakpoints.lg
        ? MesuresTransverses.colonnesRessources
        : largeur >= AppBreakpoints.sm
        ? MesuresTransverses.colonnesModulesSm
        : 1;

    Widget carte({
      required Key cle,
      required String trace,
      required String titre,
      required String detail,
      required VoidCallback onTap,
    }) => InkWell(
      key: cle,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      onTap: onTap,
      child: CarteTransverse(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconeTrace(
              trace: trace,
              taille: MesuresTransverses.iconeRessource,
              couleur: AppColors.gold,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              titre,
              style: styleTransverse(
                TaillesContenu.t15,
                poids: FontWeight.bold,
                couleur: Ardoise.c700,
              ),
            ),
            const SizedBox(height: AppSpacing.demi),
            Text(
              detail,
              style: styleTransverse(TaillesContenu.t13, couleur: Ardoise.c500),
            ),
          ],
        ),
      ),
    );

    // La vue lie sans regarder le droit (la route le refuse) ; ce poste DIT
    // le refus au clic plutôt que d'ouvrir un écran qui le dirait.
    void aller(ModuleTatacora module, String route) {
      if (droits.peutLire(module)) {
        GoRouter.of(context).go(route);
      } else {
        direTransverse(context, LibellesCoquille.sansDroit);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          TextesAide.ressourcesTitre,
          style: styleTransverse(
            TaillesContenu.base,
            poids: FontWeight.bold,
            couleur: AppColors.navy,
          ),
        ),
        const SizedBox(height: AppSpacing.smPlus),
        GrilleTransverse(
          colonnes: colonnes,
          ecart: AppSpacing.smPlus,
          enfants: [
            carte(
              cle: const Key('aide-ressource-modeles-import'),
              trace: TracesCoquille.importExport,
              titre: TextesAide.modelesImportTitre,
              detail: TextesAide.modelesImportDetail,
              // ÉCART NOMMÉ (14/10/2026) : la vue rend cette carte inerte
              // (« hors périmètre ») ; sur ce poste l'import existe — onglet
              // « Importer les données » d'Import & Export, où chaque module
              // a son modèle. La carte y mène.
              onTap: () => aller(ModuleTatacora.parametres, '/import-export'),
            ),
            carte(
              cle: const Key('aide-ressource-journal-audit'),
              trace: TracesCoquille.journalAudit,
              titre: TextesAide.journalAuditTitre,
              detail: TextesAide.journalAuditDetail,
              onTap: () => aller(ModuleTatacora.m14Etats, '/journal-audit'),
            ),
            carte(
              cle: const Key('aide-ressource-roles'),
              trace: IconeModule.roles.trace,
              titre: TextesAide.rolesTitre,
              detail: TextesAide.rolesDetail,
              onTap: () => aller(ModuleTatacora.roles, '/roles-permissions'),
            ),
          ],
        ),
      ],
    );
  }
}

/// Le bandeau de contact : cercle doré, titre, détail, bouton navy vers
/// « Contactez l'éditeur ».
class _BandeauContact extends StatelessWidget {
  const _BandeauContact();

  static const String _casque =
      r'<path stroke-linecap="round" stroke-linejoin="round" d="M4 14v-3a8 8 0 0116 0v3"/><path stroke-linecap="round" stroke-linejoin="round" d="M4 14a2 2 0 002 2h1v-5H6a2 2 0 00-2 2zM20 14a2 2 0 01-2 2h-1v-5h1a2 2 0 012 2z"/><path stroke-linecap="round" stroke-linejoin="round" d="M18 16v1a3 3 0 01-3 3h-3"/>';

  @override
  Widget build(BuildContext context) {
    final large = MediaQuery.sizeOf(context).width >= AppBreakpoints.sm;
    final cercle = Container(
      width: MesuresTransverses.logoAide,
      height: MesuresTransverses.logoAide,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: AppColors.reserveGoldFond,
        shape: BoxShape.circle,
      ),
      child: const IconeTrace(
        trace: _casque,
        taille: AppLayout.iconeTitrePage,
        couleur: AppColors.gold,
      ),
    );
    final textes = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          TextesAide.contactTitre,
          style: styleTransverse(
            TaillesContenu.sm,
            poids: FontWeight.bold,
            couleur: AppColors.navy,
          ),
        ),
        const SizedBox(height: AppSpacing.demi),
        Text(
          TextesAide.contactDetail,
          style: styleTransverse(TaillesContenu.t15, couleur: Ardoise.c500),
        ),
      ],
    );
    final bouton = BoutonTransverse(
      cle: const Key('aide-contacter-editeur'),
      libelle: TextesAide.contactBouton,
      fond: AppColors.navy,
      trace: TracesCoquille.contactEditeur,
      taille: TaillesContenu.sm,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.mdPlus,
        vertical: AppSpacing.xsPlus,
      ),
      onTap: () => GoRouter.of(context).go('/contact-editeur'),
    );
    return CarteTransverse(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: large
          ? Row(
              children: [
                cercle,
                const SizedBox(width: AppSpacing.md),
                Expanded(child: textes),
                const SizedBox(width: AppSpacing.md),
                bouton,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                cercle,
                const SizedBox(height: AppSpacing.md),
                textes,
                const SizedBox(height: AppSpacing.md),
                bouton,
              ],
            ),
    );
  }
}
