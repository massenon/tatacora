// Vue Blade maîtresse (PA-183) : pwa/notifications/hub.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/format/formats.dart';
import '../../../core/rbac/garde_acces.dart';
import '../../../core/responsive/mesure_texte.dart';
import '../../../core/theme/app_breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared_widgets/bouton_standard.dart';
import '../../bar/presentation/widgets/modale_export_carte.dart';
import '../../restaurant/presentation/widgets/coquille_restaurant.dart'
    show TextesRestaurant;
import '../../restaurant/presentation/widgets/corps_carte_commun.dart'
    show styleContenuCarte;
import '../data/notifications_dao.dart';
import '../domain/entities/canal_notification.dart';
import '../domain/entities/declencheur_notification.dart';
import '../domain/entities/message_notification.dart';
import '../domain/entities/modele_notification.dart';
import '../domain/registre_notifications.dart';
import '../impression/etat_notifications.dart';
import 'providers_notifications.dart';
import 'widgets/modales_notifications.dart';

/// M12 — Notifications. **Le logiciel TRACE, il n'ENVOIE pas.**
///
/// ## Le point qui commande tout cet écran
///
/// RG-20 (diffusion automatique) n'est pas implémentée, aucun canal n'est
/// contracté — ni WhatsApp, ni e-mail, ni SMS, ni Android — et ce poste
/// travaille hors ligne (« zéro réseau », 14/09/2026) : **aucun envoi n'y est
/// même techniquement possible**. Le maître écrit lui-même la conséquence, et
/// elle est reprise mot pour mot au bandeau : « un message marqué "envoyé"
/// alors que rien n'est parti serait pire que pas de module du tout : le
/// Gérant croirait son client prévenu ». C'est la famille PA-59/60/61.
///
/// ## L'ordre des blocs est celui de la vue
///
/// En-tête (l.93-122), bandeau (l.127-135), bande d'indicateurs repliable
/// (l.140-189), onglets (l.192-198), filtres (l.201-240), puis les cinq
/// panneaux (l.251-547) et les modales après `</main>` (l.553-665). La vue ne
/// porte AUCUN bloc « Ce que cet écran ne rend pas » : un panneau de ce genre
/// figurait ici, il a été retiré le 09/10/2026 — ce qui n'est pas rendu se
/// déclare dans ce commentaire, avec sa raison, et dans le contrôle concerné.
///
/// ## Ce que la vue porte et que cet écran ne rend pas (raisons vérifiées le 09/10/2026)
///
/// 1. **Le texte du bandeau** (l.131-132) : la vue écrit « Seul l'e-mail peut
///    réellement partir, et sous conditions. » — vrai d'un serveur qui *peut*
///    avoir un relais SMTP, FAUX de ce poste, qui n'a aucun transport
///    (`transportsLocauxProvider` rend un jeu vide, relu par un test). Le
///    recopier ferait de cet écran l'exemple même de ce qu'il dénonce. Le
///    bloc est rendu à sa place, avec la phrase de conséquence du maître
///    verbatim.
///    Aucun jeton `blade-refuse:` n'est posé (09/10/2026) : le comparateur
///    mesure ce texte dans le bloc « page », qu'on ne peut pas refuser en
///    entier sans masquer le reste de la page. Les deux paragraphes restent
///    donc comptés dans la dette (3 libellés absents), honnêtement.
/// 2. **Le bouton « Envoyer »** (l.284-285) : la vue ne le rend que pour un
///    message e-mail dont l'adresse est connue ET si un mailer réel existe.
///    Aucune des deux conditions ne peut être vraie ici, et un bouton qui
///    échoue toujours est la version cliquable de l'entrée inerte que
///    l'Article 3.3 refuse. Une ligne e-mail porte, comme la vue, la RAISON
///    (« Aucun relais SMTP réel configuré », dérivée de `estBranche`) ; les
///    trois autres canaux portent l'étiquette du maître, « à paramétrer au
///    déploiement ». La raison « Aucune adresse e-mail connue » (l.280) n'est
///    pas rendue : une notification locale ne porte pas d'adresse, la
///    nommerait affirmerait un état non lu.
/// 3. **Le détail « E-mails partis, comptés en base »** (l.162) : ce poste n'a
///    aucun transport, l'annoncer ferait attendre un envoi qui ne viendra
///    pas. La carte dit « Aucun transport sur ce poste ».
/// 4. **Le choix PDF de l'export** (l.119, `modale-export`) : la modale est
///    celle de la vue (partiel partagé), mais aucun A4 des notifications n'est
///    classé au registre de `pdf_directive_test.dart` (`sansPdf`) ; le choix
///    PDF est refusé avec son message ([EcranNotifications.pdfNonProduit]).
/// 5. **L'état replié de la bande, d'une session à l'autre** (l.140) : la vue
///    le retient en `localStorage`. Aucun magasin de préférences n'est
///    embarqué (voir `kpisNotificationsDepliesProvider`).
/// 6. **L'aperçu avec une occurrence réelle** de la modale : refusé par le
///    maître LUI-MÊME (l.553-560).
///
/// ## Ce que cet écran ajoute à la vue
///
/// La colonne « Détecté sur ce poste » de l'onglet Déclencheurs : sans elle, un
/// déclencheur muet se lirait comme un déclencheur sans occurrence, alors que
/// ce poste ne sait pas le regarder. La vue, elle, omet ses colonnes « Moteur »
/// et « Occurrences aujourd'hui » pour une raison voisine (l.378-387).
///
/// @see RG-20 Diffusion automatique des notifications (non implémentée)
/// @see EF-M12-01 Modèles de notification paramétrables par événement et canal
class EcranNotifications extends ConsumerWidget {
  const EcranNotifications({super.key});

  /// Le titre de la modale d'export — `export_titre`, « Exporter — :onglet ».
  static String titreExport(OngletNotifications onglet) =>
      'Exporter — ${onglet.libelle}';

  /// Le refus du choix PDF : aucun A4 de cet écran n'existe.
  static const String pdfNonProduit =
      'Le PDF des notifications n’est pas produit sur ce poste : aucun état A4 '
      'de cet écran n’est classé dans l’en-tête et les visas de l’application. '
      'Rien n’a été écrit. Choisissez « Tableur Excel » pour obtenir la liste '
      'affichée en CSV.';

  /// La ligne d'aide posée sous les deux choix de la modale, AVANT le clic.
  static const String aidePdf =
      'Le PDF n’est pas produit sur ce poste : seul le tableur (CSV) est '
      'écrit.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vue = ref.watch(vueNotificationsProvider);
    final peutEcrire = ref
        .watch(droitsProvider)
        .peutEcrire(ModuleTatacora.m12Notifications);
    final largeur = MediaQuery.sizeOf(context).width;

    return SingleChildScrollView(
      // `p-5 lg:p-8` (l.90) : le point de rupture est celui de l'ÉCRAN.
      padding: EdgeInsets.all(
        largeur >= AppBreakpoints.lg ? AppSpacing.xl : AppSpacing.mdPlus,
      ),
      child: Align(
        alignment: Alignment.topCenter,
        // `max-w-[1500px] mx-auto` (l.90).
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppLayout.pageNotifications,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _EnTete(peutEcrire: peutEcrire),
              // `mb-4` — 16 px.
              const SizedBox(height: AppSpacing.md),
              const _Bandeau(),
              // `mb-5` — 20 px.
              const SizedBox(height: AppSpacing.mdPlus),
              ...vue.when(
                loading: () => const [
                  Center(child: CircularProgressIndicator()),
                ],
                error: (e, _) => [Center(child: Text('$e'))],
                data: (v) => [
                  _Kpis(kpis: v.kpis),
                  const SizedBox(height: AppSpacing.mdPlus),
                  const _Onglets(),
                  const SizedBox(height: AppSpacing.md),
                  _Filtres(peutEcrire: peutEcrire),
                  const SizedBox(height: AppSpacing.md),
                  _Panneau(vue: v, peutEcrire: peutEcrire),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ========================================================== en-tête */

class _EnTete extends ConsumerWidget {
  const _EnTete({required this.peutEcrire});

  final bool peutEcrire;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // `flex flex-wrap items-start justify-between gap-3` (l.93).
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.start,
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // `flex items-center gap-2.5` (l.95).
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.notifications_none,
                  color: AppColors.navy,
                  size: AppLayout.iconeTitrePage,
                ),
                const SizedBox(width: AppSpacing.xsPlus),
                const Text('Notifications', style: TextesRestaurant.titrePage),
              ],
            ),
            // `mt-1.5` — 6 px.
            const SizedBox(height: AppSpacing.xxs),
            const Text(
              'Le référentiel des notifications : modèles de messages, '
              'événements déclencheurs et canaux de diffusion. Relisez les '
              'textes avant que les canaux soient contractés.',
              // Sans cela le texte prend TOUTE la largeur offerte, et les
              // boutons ne passent plus sous le titre comme à la vue.
              textWidthBasis: TextWidthBasis.longestLine,
              style: TextesRestaurant.sousTitrePage,
            ),
          ],
        ),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            if (peutEcrire)
              // `px-4 py-2` navy (l.107) — bouton standard (PO, 14/10/2026).
              BoutonStandard(
                key: const Key('notifications-detecter'),
                variante: VarianteBouton.primaire,
                libelle: 'Détecter maintenant',
                onPressed: () => _detecter(context, ref),
              ),
            // `px-3.5 py-2 border` (l.120) — bouton standard.
            BoutonStandard(
              key: const Key('notifications-exporter'),
              libelle: 'Exporter',
              onPressed: () => _exporter(context, ref),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _detecter(BuildContext context, WidgetRef ref) async {
    final bilan = await ref.read(detecterMaintenantProvider)();
    if (!context.mounted) return;

    ref.invalidate(vueNotificationsProvider);

    // ⚠ PREMIER cas, et il n'est pas dans les libellés du maître — ÉCART
    // NOMMÉ. Sa PWA a toujours des modèles, semés par le serveur ; ici le
    // référentiel peut être VIDE, et rien ne l'amorce. Répondre « Aucun
    // nouvel événement à notifier » affirmerait alors quelque chose sur les
    // ÉVÉNEMENTS, quand on n'a mesuré que les MODÈLES : le Gérant lit « rien
    // à faire » sur une réservation qui arrive demain (PA-59/60/61).
    //
    // Le libellé du maître, lui, dit l'essentiel : « aucun n'est parti ».
    // ⚠ La phrase ne PRESCRIT rien, et c'est délibéré : `rienDeRegarde` est
    // vrai dans deux situations — aucun modèle n'existe, ou aucun n'est à la
    // fois actif et détectable sur ce poste. Conseiller « créez un modèle »
    // serait faux dans la seconde, où il en existe un. Elle dit donc ce qui a
    // été mesuré, et rien de plus.
    final phrase = bilan.rienDeRegarde
        ? 'Aucun modèle actif et détectable sur ce poste : rien n’a été '
              'regardé.'
        : bilan.composes > 0
        ? '${bilan.composes} message(s) composé(s) — aucun n’est parti.'
        : bilan.dejaEnFile > 0
        ? 'Aucun nouvel événement à notifier : '
              '${bilan.dejaEnFile} déjà en file.'
        : 'Aucun nouvel événement à notifier.';

    // Les refus de composition sont AFFICHÉS, jamais avalés : un modèle mal
    // écrit doit se corriger, et c'est le seul moment où c'est gratuit.
    //
    // ⚠ TOUS les motifs, pas le premier : annoncer « 3 modèle(s) refusé(s) »
    // en n'en montrant qu'un laissait deux corrections invisibles, sous un
    // compte qui promettait trois.
    final refus = bilan.refus.isEmpty
        ? ''
        : '\n${bilan.refus.length} modèle(s) refusé(s) : '
              '${bilan.refus.map((r) => r.motif).join(' · ')}';

    _dire(context, '$phrase$refus');
  }

  /// « Exporter » : la modale de format de la vue (partiel `modale-export`),
  /// puis le document.
  ///
  /// - **Tableur Excel** : le CSV (BOM UTF-8, point-virgule), écrit par
  ///   `exporterNotificationsProvider`, chemin affiché.
  /// - **PDF Officiel A4** : [EcranNotifications.pdfNonProduit].
  Future<void> _exporter(BuildContext context, WidgetRef ref) async {
    final onglet = ref.read(ongletNotificationsProvider);
    final format = await choisirFormatExport(
      context,
      titre: EcranNotifications.titreExport(onglet),
      aide: EcranNotifications.aidePdf,
    );
    if (format == null || !context.mounted) return;

    // Le refus du PDF passe avant celui de la liste vide : il ne dépend pas
    // des lignes, et le dire d'abord évite d'envoyer élargir un filtre pour un
    // document qu'aucun filtre ne produira.
    if (format == FormatExport.pdf) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              EcranNotifications.pdfNonProduit,
              key: Key('notifications-export-pdf-absent'),
            ),
          ),
        );
      return;
    }

    try {
      final chemin = await ref.read(exporterNotificationsProvider)();
      if (!context.mounted) return;
      _dire(context, 'Export écrit : $chemin');
    } on ExportVide {
      if (!context.mounted) return;
      _dire(context, ExportVide.message);
    }
  }
}

/* ========================================================== bandeau */

/// Le bandeau qui doit rester en tête, quoi qu'il arrive (l.127-135).
///
/// C'est la seule phrase de la page qui dise au Gérant que rien ne part. Voir
/// l'écart n° 1 documenté en tête de fichier. Ses trois phrases tiennent en un
/// seul paragraphe, comme à la vue, pour que la hauteur du bloc — et donc la
/// position de tout ce qui suit — reste celle de la vue.
/// Refus de TEXTE, déclaré ci-dessus, sans jeton (voir l'écart n° 1).
class _Bandeau extends StatelessWidget {
  const _Bandeau();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('notifications-bandeau'),
      // `p-4` — 16 px.
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: PaletteMaitre.rouge50,
        border: Border.all(color: PaletteMaitre.rouge200),
        borderRadius: BorderRadius.circular(AppRadius.roundedXl),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // `shrink-0 mt-0.5` (l.129) : 2 px de retrait.
          const Padding(
            padding: EdgeInsets.only(top: AppSpacing.demi),
            child: Icon(
              Icons.warning_amber_outlined,
              color: PaletteMaitre.rouge600,
              size: AppLayout.iconeBandeauNotifications,
            ),
          ),
          // `gap-3` — 12 px.
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Aucun message ne part de ce poste.',
                  style: styleContenuCarte(
                    TaillesContenu.t14,
                    poids: FontWeight.bold,
                    couleur: PaletteMaitre.rouge900,
                  ),
                ),
                // `mt-1` — 4 px.
                const SizedBox(height: AppSpacing.unit),
                Text(
                  'WhatsApp, e-mail, Android et SMS restent à transmettre à la '
                  'main : aucun des quatre n’est contracté ni configuré, et ce '
                  'poste travaille hors ligne. Les messages sont composés et '
                  'mis en file, mais le destinataire n’a rien reçu : appelez-le, '
                  'puis tracez la transmission à la main. Un message marqué '
                  '« envoyé » alors que rien n’est parti serait pire que pas de '
                  'module du tout : le Gérant croirait son client prévenu.',
                  style: styleContenuCarte(
                    TaillesContenu.t13,
                    couleur: PaletteMaitre.rouge900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/* ======================================================== indicateurs */

/// La bande d'indicateurs (l.140-189), **repliable**.
class _Kpis extends ConsumerWidget {
  const _Kpis({required this.kpis});

  final KpisNotifications kpis;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deplies = ref.watch(kpisNotificationsDepliesProvider);
    final largeur = MediaQuery.sizeOf(context).width;

    // `grid grid-cols-2 lg:grid-cols-6 gap-3` (l.148).
    final colonnes = largeur >= AppBreakpoints.lg ? 6 : 2;

    final cartes = <Widget>[
      _Carte(
        cle: const Key('notifications-kpi-attente'),
        libelle: 'En file d’attente',
        valeur: '${kpis.enAttente}',
        detail: 'Composés, prêts, non partis',
      ),
      _Carte(
        cle: const Key('notifications-kpi-envoyes'),
        libelle: 'Réellement envoyés',
        valeur: '${kpis.envoyesReels}',
        // Rouge tant qu'il est nul — rien n'est parti. Il passerait au vert
        // au premier envoi RÉEL, jamais sur une constante (PA-61).
        accent: kpis.envoyesReels > 0
            ? PaletteMaitre.emeraude600
            : PaletteMaitre.rouge600,
        // ⚠ Écart assumé avec la vue (l.162), qui écrit « E-mails partis,
        // comptés en base » : ce poste n'a aucun transport, et l'annoncer
        // ferait attendre un envoi qui ne viendra pas.
        detail: 'Aucun transport sur ce poste',
      ),
      _Carte(
        cle: const Key('notifications-kpi-transmis'),
        libelle: 'Transmis à la main',
        valeur: '${kpis.transmis}',
        detail: 'Par un opérateur',
        accent: PaletteMaitre.emeraude600,
      ),
      _Carte(
        cle: const Key('notifications-kpi-abandonnes'),
        libelle: 'Abandonnés',
        valeur: '${kpis.abandonnes}',
        detail: 'Avec motif',
      ),
      _Carte(
        cle: const Key('notifications-kpi-modeles'),
        libelle: 'Modèles actifs',
        valeur: '${kpis.modelesActifs} / ${kpis.modelesTotal}',
        detail: '${kpis.nombreDeclencheurs} déclencheurs',
      ),
      _Carte(
        cle: const Key('notifications-kpi-canaux'),
        libelle: 'Canaux branchés',
        valeur: '${kpis.canauxBranches} / ${kpis.canauxTotal}',
        accent: kpis.canauxBranches > 0
            ? PaletteMaitre.emeraude600
            : PaletteMaitre.rouge600,
        detail: 'Dépendances externes',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // La bascule de la vue (l.141-146) : tout le bandeau est la zone de
        // clic, sans icône.
        InkWell(
          key: const Key('notifications-kpis-bascule'),
          borderRadius: BorderRadius.circular(AppRadius.roundedXl),
          onTap: () =>
              ref.read(kpisNotificationsDepliesProvider.notifier).basculer(),
          child: Container(
            // `px-4 py-3 bg-white border border-slate-200 rounded-xl`.
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: AppColors.neutre0,
              borderRadius: BorderRadius.circular(AppRadius.roundedXl),
              border: Border.all(color: Ardoise.c200),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Indicateurs des notifications',
                  style: styleContenuCarte(
                    TaillesContenu.sm,
                    poids: FontWeight.bold,
                    couleur: Ardoise.c700,
                  ),
                ),
                // `hidden sm:inline` (l.145) : masquée sous 640 px.
                if (largeur >= AppBreakpoints.sm)
                  Text(
                    'Repliez la bande pour gagner de la hauteur de tableau.',
                    style: styleContenuCarte(
                      TaillesContenu.t11,
                      couleur: Ardoise.c400,
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (deplies) ...[
          // `mt-3` — 12 px.
          const SizedBox(height: AppSpacing.sm),
          for (var debut = 0; debut < cartes.length; debut += colonnes) ...[
            // `gap-3` — 12 px entre les rangées.
            if (debut > 0) const SizedBox(height: AppSpacing.sm),
            // `IntrinsicHeight` : une `Row` étirée dans une liste défilante
            // reçoit une hauteur infinie (doctrine §3.3).
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < colonnes; i++) ...[
                    if (i > 0) const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: debut + i < cartes.length
                          ? cartes[debut + i]
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ],
    );
  }
}

/// Une carte de la bande (l.149-187) : `bg-white rounded-xl border
/// border-slate-200 p-3.5`.
class _Carte extends StatelessWidget {
  const _Carte({
    required Key cle,
    required this.libelle,
    required this.valeur,
    required this.detail,
    this.accent,
  }) : super(key: cle);

  final String libelle;
  final String valeur;
  final String detail;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      // `p-3.5` — 14 px.
      padding: const EdgeInsets.all(AppSpacing.smPlus),
      decoration: BoxDecoration(
        color: AppColors.neutre0,
        borderRadius: BorderRadius.circular(AppRadius.roundedXl),
        border: Border.all(color: Ardoise.c200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // `text-[11px] uppercase tracking-wide text-slate-400 font-semibold`.
          Text(
            libelle.toUpperCase(),
            style: styleContenuCarte(
              TaillesContenu.t11,
              poids: FontWeight.w600,
              couleur: Ardoise.c400,
              interlettrage: AppTextStyles.suiviLarge * TaillesContenu.t11,
            ),
          ),
          // `mt-1` — 4 px ; `text-[17px] font-bold`.
          const SizedBox(height: AppSpacing.unit),
          Text(
            valeur,
            style: styleContenuCarte(
              TaillesContenu.t17,
              poids: FontWeight.bold,
              couleur: accent ?? AppColors.navy,
            ),
          ),
          // `mt-0.5` — 2 px ; `text-[11px] text-slate-400`.
          const SizedBox(height: AppSpacing.demi),
          Text(
            detail,
            style: styleContenuCarte(TaillesContenu.t11, couleur: Ardoise.c400),
          ),
        ],
      ),
    );
  }
}

/* ============================================================ onglets */

class _Onglets extends ConsumerWidget {
  const _Onglets();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final courant = ref.watch(ongletNotificationsProvider);

    // `flex flex-wrap gap-1.5` (l.192) — 6 px.
    return Wrap(
      spacing: AppSpacing.xxs,
      runSpacing: AppSpacing.xxs,
      children: [
        for (final onglet in OngletNotifications.values)
          _BoutonOnglet(
            onglet: onglet,
            actif: onglet == courant,
            onTap: () =>
                ref.read(ongletNotificationsProvider.notifier).definir(onglet),
          ),
      ],
    );
  }
}

/// Un onglet : `px-3.5 py-2 rounded-lg text-[13px] font-semibold`, plein navy
/// à l'état actif, blanc bordé de `slate-200` sinon (`Onglets.php`, directive
/// du Product Owner du 01/09/2026 : UNE forme pour tous les écrans).
class _BoutonOnglet extends StatelessWidget {
  const _BoutonOnglet({
    required this.onglet,
    required this.actif,
    required this.onTap,
  });

  final OngletNotifications onglet;
  final bool actif;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: Key('notifications-onglet-${onglet.name}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.smPlus,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: actif ? AppColors.navy : AppColors.neutre0,
          // L'onglet actif n'a AUCUNE bordure (`Onglets::ACTIF`).
          border: actif ? null : Border.all(color: Ardoise.c200),
          borderRadius: BorderRadius.circular(AppRadius.roundedLg),
        ),
        child: Text(
          onglet.libelle,
          style: styleContenuCarte(
            TaillesContenu.t13,
            poids: FontWeight.w600,
            couleur: actif ? AppColors.neutre0 : Ardoise.c500,
          ),
        ),
      ),
    );
  }
}

/* ============================================================ filtres */

class _Filtres extends ConsumerStatefulWidget {
  const _Filtres({required this.peutEcrire});

  final bool peutEcrire;

  @override
  ConsumerState<_Filtres> createState() => _FiltresState();
}

class _FiltresState extends ConsumerState<_Filtres> {
  final _terme = TextEditingController();

  /// `text-[13px]` d'un champ de la barre (l.209-231).
  static final TextStyle _texteChamp = styleContenuCarte(
    TaillesContenu.t13,
    couleur: Ardoise.c700,
  );

  /// `border border-slate-300 rounded-lg` (l.210).
  static final OutlineInputBorder _bordureChamp = OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadius.roundedLg),
    borderSide: const BorderSide(color: Ardoise.c300),
  );

  /// `gap-2.5` (l.202) — 10 px.
  static const double _ecart = AppSpacing.xsPlus;

  @override
  void dispose() {
    _terme.dispose();
    super.dispose();
  }

  /// La largeur d'un `<select>` natif : son texte le plus long, `px-3`, la
  /// bordure et la flèche.
  static double _largeurListe(Iterable<String> libelles) {
    var plus = 0.0;
    for (final l in libelles) {
      final w = largeurMaxContent(l, _texteChamp);
      if (w > plus) plus = w;
    }
    return plus +
        AppSpacing.sm * 2 +
        AppLayout.bordureControle * 2 +
        AppLayout.flecheSelectNotifications;
  }

  @override
  Widget build(BuildContext context) {
    final libellesCanal = [
      'Tous les canaux',
      for (final c in CanalNotification.values) c.libelle,
    ];
    final libellesPublic = [
      'Tous les publics',
      for (final p in PublicNotification.values) p.libelle,
    ];
    final libellesEtat = [for (final e in EtatModeleFiltre.values) e.libelle];

    final largeurCanal = _largeurListe(libellesCanal);
    final largeurPublic = _largeurListe(libellesPublic);
    final largeurEtat = _largeurListe(libellesEtat);
    final largeurBouton =
        largeurMaxContent('+ Modèle', _texteChamp) +
        AppSpacing.md * 2 +
        AppLayout.bordureControle * 2;

    final listes = <Widget>[
      _Liste<CanalNotification>(
        cle: const Key('notifications-filtre-canal'),
        largeur: largeurCanal,
        valeur: ref.watch(canalFiltreProvider),
        videLibelle: 'Tous les canaux',
        options: {for (final c in CanalNotification.values) c: c.libelle},
        onChoix: (c) => ref.read(canalFiltreProvider.notifier).definir(c),
      ),
      _Liste<PublicNotification>(
        cle: const Key('notifications-filtre-public'),
        largeur: largeurPublic,
        valeur: ref.watch(publicFiltreProvider),
        videLibelle: 'Tous les publics',
        options: {for (final p in PublicNotification.values) p: p.libelle},
        onChoix: (p) => ref.read(publicFiltreProvider.notifier).definir(p),
      ),
      _ListeEtat(
        largeur: largeurEtat,
        valeur: ref.watch(etatModeleFiltreProvider),
        onChoix: (e) => ref.read(etatModeleFiltreProvider.notifier).definir(e),
      ),
    ];

    final bouton = widget.peutEcrire
        // `px-4 py-2 border` (l.237) — bouton standard (PO, 14/10/2026).
        ? BoutonStandard(
            key: const Key('notifications-nouveau-modele'),
            libelle: '+ Modèle',
            margeHorizontale: AppSpacing.md,
            onPressed: () => _nouveauModele(context, ref),
          )
        : null;

    return Container(
      // `p-3.5 bg-white rounded-xl border border-slate-200` (l.201).
      padding: const EdgeInsets.all(AppSpacing.smPlus),
      decoration: BoxDecoration(
        color: AppColors.neutre0,
        borderRadius: BorderRadius.circular(AppRadius.roundedXl),
        border: Border.all(color: Ardoise.c200),
      ),
      child: LayoutBuilder(
        builder: (context, contraintes) {
          final interieur = contraintes.maxWidth;
          final fixes =
              largeurCanal +
              largeurPublic +
              largeurEtat +
              (bouton == null ? 0 : largeurBouton);
          // La recherche, trois listes, l'espaceur `flex-1` et le bouton.
          final elements = 5 + (bouton == null ? 0 : 1);
          final ecarts = _ecart * (elements - 1);
          final libre = interieur - fixes - ecarts;

          // `flex-1` : la recherche et l'espaceur se partagent le libre, la
          // recherche ne descend jamais sous son plancher (`min-w-[200px]`).
          final tient = AppLayout.rechercheMinNotifications <= libre;
          if (!tient) {
            return Wrap(
              spacing: _ecart,
              runSpacing: _ecart,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: interieur < AppLayout.rechercheMinNotifications
                      ? interieur
                      : AppLayout.rechercheMinNotifications,
                  child: _recherche(),
                ),
                ...listes,
                ?bouton,
              ],
            );
          }

          final largeurRecherche =
              libre / 2 < AppLayout.rechercheMinNotifications
              ? AppLayout.rechercheMinNotifications
              : libre / 2;
          final largeurEspaceur = libre - largeurRecherche;

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(width: largeurRecherche, child: _recherche()),
              for (final l in listes) ...[const SizedBox(width: _ecart), l],
              SizedBox(width: _ecart + largeurEspaceur),
              if (bouton != null) ...[const SizedBox(width: _ecart), bouton],
            ],
          );
        },
      ),
    );
  }

  /// Le champ de recherche (l.203-211) : la loupe est posée en `absolute
  /// left-3`, le texte part à `pl-9`.
  Widget _recherche() {
    return Stack(
      alignment: Alignment.centerLeft,
      children: [
        TextField(
          key: const Key('notifications-recherche'),
          controller: _terme,
          style: _texteChamp,
          decoration: InputDecoration(
            hintText: 'Destinataire, contenu, modèle…',
            hintStyle: _texteChamp.copyWith(color: Ardoise.c400),
            isDense: true,
            // `pl-9 pr-3 py-2` + la bordure de 1 px, que Flutter ne compte pas
            // dans le remplissage.
            contentPadding: const EdgeInsets.fromLTRB(
              AppLayout.prefixeRechercheNotifications +
                  AppLayout.bordureControle,
              AppSpacing.xs + AppLayout.bordureControle,
              AppSpacing.sm + AppLayout.bordureControle,
              AppSpacing.xs + AppLayout.bordureControle,
            ),
            enabledBorder: _bordureChamp,
            focusedBorder: _bordureChamp,
          ),
          onChanged: (v) =>
              ref.read(rechercheNotificationsProvider.notifier).definir(v),
        ),
        const Positioned(
          left: AppSpacing.sm,
          child: IgnorePointer(
            child: Icon(
              Icons.search,
              size: AppLayout.iconeChamp,
              color: Ardoise.c400,
            ),
          ),
        ),
      ],
    );
  }
}

/// Une boîte de filtre : `px-3 py-2 border border-slate-300 rounded-lg`.
class _BoiteFiltre extends StatelessWidget {
  const _BoiteFiltre({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.roundedLg),
        border: Border.all(color: Ardoise.c300),
      ),
      child: child,
    );
  }
}

/// Un `<select>` à option vide (l.213-225).
class _Liste<T> extends StatelessWidget {
  const _Liste({
    required Key cle,
    required this.largeur,
    required this.valeur,
    required this.videLibelle,
    required this.options,
    required this.onChoix,
  }) : super(key: cle);

  final double largeur;
  final T? valeur;
  final String videLibelle;
  final Map<T, String> options;
  final ValueChanged<T?> onChoix;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: largeur,
      child: _BoiteFiltre(
        // Hauteur de l'interligne SEUL : `DropdownButton` impose au moins
        // 24 px de haut, même dense.
        child: SizedBox(
          height: TaillesContenu.t13 * AppLayout.interligneContenu,
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T?>(
              value: valeur,
              isExpanded: true,
              isDense: true,
              itemHeight: null,
              iconSize: AppLayout.iconeChamp,
              style: styleContenuCarte(
                TaillesContenu.t13,
                couleur: Ardoise.c700,
              ),
              items: [
                DropdownMenuItem<T?>(child: Text(videLibelle)),
                for (final entree in options.entries)
                  DropdownMenuItem<T?>(
                    value: entree.key,
                    child: Text(entree.value),
                  ),
              ],
              onChanged: onChoix,
            ),
          ),
        ),
      ),
    );
  }
}

/// Le `<select>` d'état (l.227-231) : trois options, dont la première est
/// « Tous les états » — il n'a pas d'option vide à part.
class _ListeEtat extends StatelessWidget {
  const _ListeEtat({
    required this.largeur,
    required this.valeur,
    required this.onChoix,
  });

  final double largeur;
  final EtatModeleFiltre valeur;
  final ValueChanged<EtatModeleFiltre> onChoix;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('notifications-filtre-etat'),
      width: largeur,
      child: _BoiteFiltre(
        child: SizedBox(
          height: TaillesContenu.t13 * AppLayout.interligneContenu,
          child: DropdownButtonHideUnderline(
            child: DropdownButton<EtatModeleFiltre>(
              value: valeur,
              isExpanded: true,
              isDense: true,
              itemHeight: null,
              iconSize: AppLayout.iconeChamp,
              style: styleContenuCarte(
                TaillesContenu.t13,
                couleur: Ardoise.c700,
              ),
              items: [
                for (final e in EtatModeleFiltre.values)
                  DropdownMenuItem(value: e, child: Text(e.libelle)),
              ],
              onChanged: (e) {
                if (e != null) onChoix(e);
              },
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _nouveauModele(BuildContext context, WidgetRef ref) async {
  final saisie = await demanderModele(context);
  if (saisie == null || !context.mounted) return;

  try {
    await ref
        .read(notificationsDaoProvider)
        .creerModele(
          declencheur: saisie.declencheur,
          canal: saisie.canal,
          contenuTemplate: saisie.contenu,
          objet: saisie.objet,
          actif: saisie.actif,
        );
    ref.invalidate(vueNotificationsProvider);
    if (context.mounted) _dire(context, 'Modèle enregistré.');
  } on RefusNotification catch (refus) {
    if (context.mounted) _dire(context, refus.message);
  }
}

/* ============================================================ panneaux */

class _Panneau extends StatelessWidget {
  const _Panneau({required this.vue, required this.peutEcrire});

  final VueNotifications vue;
  final bool peutEcrire;

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) => switch (ref.watch(
        ongletNotificationsProvider,
      )) {
        OngletNotifications.file => _PanneauFile(
          groupes: vue.groupes,
          peutEcrire: peutEcrire,
        ),
        OngletNotifications.modeles => _PanneauModeles(
          modeles: vue.modeles,
          peutEcrire: peutEcrire,
        ),
        OngletNotifications.declencheurs => _PanneauDeclencheurs(
          declencheurs: vue.declencheurs,
          tousModeles: vue.tousModeles,
        ),
        OngletNotifications.journal => _PanneauJournal(journal: vue.journal),
        OngletNotifications.canaux => _PanneauCanaux(enFile: vue.enFile),
      },
    );
  }
}

/* --------------------------------------------------------- file d'attente */

class _PanneauFile extends StatelessWidget {
  const _PanneauFile({required this.groupes, required this.peutEcrire});

  final List<GroupeFile> groupes;
  final bool peutEcrire;

  @override
  Widget build(BuildContext context) {
    if (groupes.isEmpty) {
      // Une SEULE phrase, comme la vue (l.314) : « Aucun message en attente.
      // Lancez « Détecter maintenant » pour composer les messages du jour. »
      return const _EtatVideSimple(
        cle: Key('notifications-file-vide'),
        texte:
            'Aucun message en attente. Lancez « Détecter maintenant » pour '
            'composer les messages du jour.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final groupe in groupes)
          Padding(
            // `mb-3` — 12 px.
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _Bloc(
              enTete: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        groupe.declencheur?.libelle ?? groupe.code,
                        style: styleContenuCarte(
                          TaillesContenu.t14,
                          poids: FontWeight.bold,
                          couleur: AppColors.navy,
                        ),
                      ),
                      if (groupe.declencheur != null) ...[
                        // `mt-0.5` — 2 px.
                        const SizedBox(height: AppSpacing.demi),
                        Text(
                          groupe.declencheur!.description,
                          style: styleContenuCarte(
                            TaillesContenu.t11,
                            couleur: Ardoise.c400,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (groupe.declencheur != null)
                    _Pastille(
                      texte: 'Module ${groupe.declencheur!.module}',
                      fond: Ardoise.c100,
                      texteCouleur: Ardoise.c600,
                      taille: TaillesContenu.t11,
                      horizontal: AppSpacing.xs,
                    ),
                ],
              ),
              enfants: [
                for (final message in groupe.messages)
                  _LigneMessage(message: message, peutEcrire: peutEcrire),
              ],
            ),
          ),
      ],
    );
  }
}

class _LigneMessage extends ConsumerWidget {
  const _LigneMessage({required this.message, required this.peutEcrire});

  final MessageNotification message;
  final bool peutEcrire;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transports = ref.watch(transportsLocauxProvider);
    final email = message.canal == CanalNotification.email;

    return Container(
      key: Key('notifications-message-${message.id}'),
      // `px-4 py-3 border-b border-slate-100` (l.265).
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Ardoise.c100)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // `flex flex-wrap items-center justify-between gap-2 mb-2` (l.266).
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.demi,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    message.destinataire,
                    style: styleContenuCarte(
                      TaillesContenu.t13,
                      poids: FontWeight.w600,
                      couleur: Ardoise.c800,
                    ),
                  ),
                  _Pastille(
                    texte: message.canal?.libelle ?? '',
                    fond: Ardoise.c100,
                    texteCouleur: Ardoise.c500,
                  ),
                  // Le badge du maître, et il ne bouge jamais : rien ne part.
                  _Pastille(
                    cle: Key('notifications-non-envoye-${message.id}'),
                    texte: 'non envoyé',
                    fond: PaletteMaitre.rouge50,
                    texteCouleur: PaletteMaitre.rouge900,
                  ),
                ],
              ),
              if (peutEcrire)
                Wrap(
                  spacing: AppSpacing.xxs,
                  runSpacing: AppSpacing.xxs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // ⚠ Là où la vue met « Envoyer » (l.278-289). Aucun
                    // transport n'existe : un bouton qui échouerait toujours
                    // serait l'entrée inerte que l'Article 3.3 refuse. Comme
                    // la vue, la RAISON remplace le bouton : le relais absent
                    // pour l'e-mail (dérivé de `estBranche`, jamais écrit en
                    // dur), l'étiquette du maître pour les trois autres canaux.
                    if (email &&
                        !transports.estBranche(CanalNotification.email))
                      _Pastille(
                        cle: Key('notifications-sans-relais-${message.id}'),
                        texte: TransportsLocaux.etiquetteSansRelais,
                        fond: PaletteMaitre.rouge50,
                        texteCouleur: PaletteMaitre.rouge700,
                        taille: TaillesContenu.t11,
                        horizontal: AppSpacing.xs,
                        vertical: AppSpacing.unit,
                      )
                    else
                      _Pastille(
                        cle: Key('notifications-a-parametrer-${message.id}'),
                        texte: TransportsLocaux.etiquetteSansTransport,
                        fond: Ardoise.c100,
                        texteCouleur: Ardoise.c400,
                        taille: TaillesContenu.t11,
                        horizontal: AppSpacing.xs,
                        vertical: AppSpacing.unit,
                      ),
                    _BoutonPetit(
                      cle: Key('notifications-transmis-${message.id}'),
                      libelle: 'Transmis à la main',
                      bordure: PaletteMaitre.emeraude300,
                      texte: PaletteMaitre.emeraude700,
                      onTap: () => _transmettre(context, ref, message),
                    ),
                    _BoutonPetit(
                      cle: Key('notifications-abandonner-${message.id}'),
                      libelle: 'Abandonner',
                      bordure: Ardoise.c300,
                      texte: Ardoise.c700,
                      onTap: () => _abandonner(context, ref, message),
                    ),
                  ],
                ),
            ],
          ),
          // `mb-2` — 8 px.
          const SizedBox(height: AppSpacing.xs),
          if (message.objet != null) ...[
            Text(
              'Objet : ${message.objet}',
              style: styleContenuCarte(
                TaillesContenu.t12,
                poids: FontWeight.w600,
                couleur: Ardoise.c600,
              ),
            ),
            // `mb-1` — 4 px.
            const SizedBox(height: AppSpacing.unit),
          ],
          _Bulle(texte: message.contenu, canal: message.canal),
          // `mt-1.5` — 6 px.
          const SizedBox(height: AppSpacing.xxs),
          Text(
            _meta(message),
            style: styleContenuCarte(
              TaillesContenu.t10_5,
              couleur: Ardoise.c400,
            ),
          ),
        ],
      ),
    );
  }

  String _meta(MessageNotification m) {
    final limite = m.canal?.limite;
    final longueur = limite == null
        ? '${m.longueur} caractère(s)'
        : '${m.longueur} caractère(s) / $limite';
    return '$longueur · composé le ${formaterDate(m.composeLe)} '
        '${m.composeLe.hour.toString().padLeft(2, '0')}:'
        '${m.composeLe.minute.toString().padLeft(2, '0')} '
        '· réf. ${m.reference}';
  }
}

/// Un petit bouton à bordure : `text-[11px] px-2 py-1 rounded border`
/// (l.285-293).
class _BoutonPetit extends StatelessWidget {
  const _BoutonPetit({
    required this.cle,
    required this.libelle,
    required this.bordure,
    required this.texte,
    required this.onTap,
    this.horizontal = AppSpacing.xs,
  });

  final Key cle;
  final String libelle;
  final Color bordure;
  final Color texte;
  final VoidCallback onTap;
  final double horizontal;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: cle,
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.rounded),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: horizontal,
          vertical: AppSpacing.unit,
        ),
        decoration: BoxDecoration(
          border: Border.all(color: bordure),
          borderRadius: BorderRadius.circular(AppRadius.rounded),
        ),
        child: Text(
          libelle,
          style: styleContenuCarte(TaillesContenu.t11, couleur: texte),
        ),
      ),
    );
  }
}

/// La bulle d'un message — les trois familles de couleurs de la vue (l.54-58) :
/// l'e-mail en bleu, Android et SMS en ardoise, et la branche `default` —
/// WhatsApp, et tout canal inconnu — en émeraude.
///
/// Elle sert le message composé (l.300) comme le gabarit d'un modèle (l.351) :
/// la vue pose les mêmes classes aux deux endroits.
class _Bulle extends StatelessWidget {
  const _Bulle({required this.texte, required this.canal});

  final String texte;
  final CanalNotification? canal;

  @override
  Widget build(BuildContext context) {
    final (fond, bordure, couleur) = switch (canal) {
      CanalNotification.email => (
        PaletteMaitre.bleu50,
        PaletteMaitre.bleu200,
        PaletteMaitre.bleu900,
      ),
      CanalNotification.android ||
      CanalNotification.sms => (Ardoise.c50, Ardoise.c200, Ardoise.c700),
      CanalNotification.whatsapp || null => (
        PaletteMaitre.emeraude50,
        PaletteMaitre.emeraude200,
        PaletteMaitre.emeraude900,
      ),
    };

    return ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: AppLayout.bulleMessageNotification,
      ),
      child: Container(
        // `px-3 py-2.5` (l.300).
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xsPlus,
        ),
        decoration: BoxDecoration(
          color: fond,
          border: Border.all(color: bordure),
          borderRadius: BorderRadius.circular(AppRadius.roundedXl),
        ),
        child: Text(
          texte,
          style: styleContenuCarte(
            TaillesContenu.t13,
            couleur: couleur,
          ).copyWith(height: AppLayout.interligneDetendu),
        ),
      ),
    );
  }
}

Future<void> _transmettre(
  BuildContext context,
  WidgetRef ref,
  MessageNotification message,
) async {
  final saisie = await demanderTransmission(context);
  if (saisie == null || !context.mounted) return;

  final auteur = ref.read(auteurGesteProvider);
  if (auteur == null) {
    _dire(context, _sansSession);
    return;
  }

  try {
    await ref
        .read(notificationsDaoProvider)
        .marquerTransmis(
          message.id,
          auteur: auteur,
          commentaire: saisie.commentaire,
        );
    ref.invalidate(vueNotificationsProvider);
    if (context.mounted) _dire(context, 'Message sorti de la file.');
  } on RefusNotification catch (refus) {
    if (context.mounted) _dire(context, refus.message);
  }
}

Future<void> _abandonner(
  BuildContext context,
  WidgetRef ref,
  MessageNotification message,
) async {
  final motif = await demanderAbandon(context);
  if (motif == null || !context.mounted) return;

  final auteur = ref.read(auteurGesteProvider);
  if (auteur == null) {
    _dire(context, _sansSession);
    return;
  }

  try {
    await ref
        .read(notificationsDaoProvider)
        .abandonner(message.id, auteur: auteur, motif: motif);
    ref.invalidate(vueNotificationsProvider);
    if (context.mounted) _dire(context, 'Message abandonné.');
  } on RefusNotification catch (refus) {
    if (context.mounted) _dire(context, refus.message);
  }
}

/* --------------------------------------------------------------- modèles */

class _PanneauModeles extends ConsumerWidget {
  const _PanneauModeles({required this.modeles, required this.peutEcrire});

  final List<ModeleNotification> modeles;
  final bool peutEcrire;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (modeles.isEmpty) {
      return const _EtatVide(
        cle: Key('notifications-modeles-vide'),
        titre: 'Aucun résultat',
        detail: 'Aucun modèle ne correspond.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final modele in modeles)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Container(
              key: Key('notifications-modele-${modele.id}'),
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.neutre0,
                borderRadius: BorderRadius.circular(AppRadius.roundedXl),
                border: Border.all(color: Ardoise.c200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: [
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: AppSpacing.xs,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                modele.declencheur?.libelle ??
                                    modele.evenementCode,
                                style: styleContenuCarte(
                                  TaillesContenu.t14,
                                  poids: FontWeight.bold,
                                  couleur: AppColors.navy,
                                ),
                              ),
                              _Pastille(
                                texte:
                                    modele.canal?.libelle ?? modele.canalCode,
                                fond: Ardoise.c100,
                                texteCouleur: Ardoise.c500,
                              ),
                              if (modele.actif)
                                _Pastille(
                                  texte: 'actif',
                                  fond: PaletteMaitre.emeraude50,
                                  texteCouleur: PaletteMaitre.emeraude700,
                                )
                              else
                                _Pastille(
                                  texte: 'désactivé',
                                  fond: Ardoise.c100,
                                  texteCouleur: Ardoise.c400,
                                ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.demi),
                          Text(
                            modele.evenementCode,
                            style:
                                styleContenuCarte(
                                  TaillesContenu.t11,
                                  couleur: Ardoise.c400,
                                ).copyWith(
                                  fontFamily: AppTextStyles.policeMonospace,
                                ),
                          ),
                        ],
                      ),
                      if (peutEcrire)
                        Wrap(
                          spacing: AppSpacing.xxs,
                          children: [
                            _BoutonPetit(
                              cle: Key('notifications-bascule-${modele.id}'),
                              libelle: modele.actif ? 'Désactiver' : 'Activer',
                              bordure: Ardoise.c300,
                              texte: Ardoise.c700,
                              horizontal: AppSpacing.xsPlus,
                              onTap: () async {
                                await ref
                                    .read(notificationsDaoProvider)
                                    .basculerActivation(modele.id);
                                ref.invalidate(vueNotificationsProvider);
                              },
                            ),
                            _BoutonPetit(
                              cle: Key('notifications-modifier-${modele.id}'),
                              libelle: 'Modifier',
                              bordure: Ardoise.c300,
                              texte: Ardoise.c700,
                              horizontal: AppSpacing.xsPlus,
                              onTap: () =>
                                  _modifierModele(context, ref, modele),
                            ),
                          ],
                        ),
                    ],
                  ),
                  // `mb-2.5` — 10 px.
                  const SizedBox(height: AppSpacing.xsPlus),
                  if (modele.objet != null) ...[
                    Text(
                      'Objet : ${modele.objet}',
                      style: styleContenuCarte(
                        TaillesContenu.t12,
                        poids: FontWeight.w600,
                        couleur: Ardoise.c600,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.unit),
                  ],
                  _Bulle(texte: modele.contenuTemplate, canal: modele.canal),
                  const SizedBox(height: AppSpacing.xs),
                  if (modele.declencheurHorsRegistre)
                    Text(
                      'Événement hors registre — ce modèle n’est rattaché à '
                      'aucun déclencheur connu.',
                      key: Key('notifications-hors-registre-${modele.id}'),
                      style: styleContenuCarte(
                        TaillesContenu.t11,
                        couleur: PaletteMaitre.rouge600,
                      ),
                    )
                  else
                    Text(
                      'Variables disponibles : '
                      '${modele.declencheur!.variables.map((v) => '{$v}').join(' ')}',
                      style: styleContenuCarte(
                        TaillesContenu.t10_5,
                        couleur: Ardoise.c400,
                      ),
                    ),
                  if (modele.variablesInconnues.isNotEmpty)
                    Text(
                      'Variable(s) non résolue(s) : '
                      '${modele.variablesInconnues.map((v) => '{$v}').join(', ')}'
                      ' — le message serait refusé.',
                      key: Key('notifications-variables-${modele.id}'),
                      style: styleContenuCarte(
                        TaillesContenu.t11,
                        couleur: PaletteMaitre.rouge600,
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

Future<void> _modifierModele(
  BuildContext context,
  WidgetRef ref,
  ModeleNotification modele,
) async {
  final saisie = await demanderModele(context, existant: modele);
  if (saisie == null || !context.mounted) return;

  try {
    await ref
        .read(notificationsDaoProvider)
        .modifierModele(
          modele.id,
          canal: saisie.canal,
          contenuTemplate: saisie.contenu,
          objet: saisie.objet,
          actif: saisie.actif,
        );
    ref.invalidate(vueNotificationsProvider);
    if (context.mounted) _dire(context, 'Modèle enregistré.');
  } on RefusNotification catch (refus) {
    if (context.mounted) _dire(context, refus.message);
  }
}

/* ---------------------------------------------------------- déclencheurs */

class _PanneauDeclencheurs extends StatelessWidget {
  const _PanneauDeclencheurs({
    required this.declencheurs,
    required this.tousModeles,
  });

  final List<DeclencheurNotification> declencheurs;
  final List<ModeleNotification> tousModeles;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // L'en-tête reste quand il n'y a rien à lister : la vue pose son `<thead>`
    // hors de la boucle, l'état vide est une ligne SOUS les en-têtes (l.394,
    // l.415-417).
    return _Bloc(
      enTete: Text(
        'Déclencheurs — ${DeclencheurNotification.values.length} événements '
        'du registre',
        style: styleContenuCarte(
          TaillesContenu.t14,
          poids: FontWeight.bold,
          couleur: AppColors.navy,
        ),
      ),
      enfants: [
        _Tableau(
          colonnes: const [
            'Déclencheur',
            'Public',
            'Module',
            'Modèles',
            'Variables',
            // ⚠ Colonne AJOUTÉE : elle n'existe pas à la vue. Sans elle, un
            // déclencheur muet se lirait comme un déclencheur sans occurrence
            // — alors que ce poste ne sait pas le regarder.
            'Détecté sur ce poste',
          ],
          lignes: [
            for (final d in declencheurs)
              DataRow(
                cells: [
                  DataCell(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          d.libelle,
                          key: Key('notifications-declencheur-${d.code}'),
                          style: styleContenuCarte(
                            TaillesContenu.t13,
                            poids: FontWeight.w600,
                            couleur: Ardoise.c800,
                          ),
                        ),
                        Text(
                          d.description,
                          style: styleContenuCarte(
                            TaillesContenu.t11,
                            couleur: Ardoise.c400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  DataCell(Text(d.public.libelle)),
                  DataCell(
                    _Pastille(
                      texte: d.module,
                      fond: Ardoise.c100,
                      texteCouleur: Ardoise.c600,
                      taille: TaillesContenu.t11,
                      horizontal: AppSpacing.xxs,
                    ),
                  ),
                  DataCell(
                    Builder(
                      builder: (_) {
                        final c = comptageParDeclencheur(tousModeles, d);
                        return Text('${c.actifs} / ${c.total}');
                      },
                    ),
                  ),
                  DataCell(
                    Text(
                      d.variables.map((v) => '{$v}').join(' '),
                      style: styleContenuCarte(
                        TaillesContenu.t11,
                        couleur: Ardoise.c400,
                      ),
                    ),
                  ),
                  DataCell(
                    ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: AppLayout.bulleMessageNotification,
                      ),
                      child: d.estDetecteSurCePoste
                          ? _Pastille(
                              texte: 'oui',
                              fond: PaletteMaitre.emeraude50,
                              texteCouleur: PaletteMaitre.emeraude700,
                            )
                          : Text(
                              d.motifNonDetecte,
                              key: Key('notifications-motif-${d.code}'),
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: Ardoise.c500,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
          ],
        ),
        if (declencheurs.isEmpty)
          const _LigneVide(
            key: Key('notifications-declencheurs-vide'),
            titre: 'Aucun résultat',
            detail: 'Aucun déclencheur ne correspond.',
          ),
      ],
    );
  }
}

/* --------------------------------------------------------------- journal */

class _PanneauJournal extends StatelessWidget {
  const _PanneauJournal({required this.journal});

  final List<MessageNotification> journal;

  @override
  Widget build(BuildContext context) {
    return _Bloc(
      // `flex flex-wrap items-center justify-between gap-2` (l.434).
      enTete: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        children: [
          Text(
            'Journal — ${journal.length} message(s)',
            style: styleContenuCarte(
              TaillesContenu.t14,
              poids: FontWeight.bold,
              couleur: AppColors.navy,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // La phrase de la vue (`journal_reserve`, l.436), au mot.
              Text(
                'La colonne « Envoi système » dit « oui » uniquement pour un '
                'message que le transport a réellement accepté — WhatsApp, '
                'Android et SMS restent « non » tant qu’aucun n’est branché.',
                style: styleContenuCarte(
                  TaillesContenu.t11,
                  couleur: PaletteMaitre.rouge700,
                ),
              ),
              // Ajouté : ce que la vue ne peut pas dire de ce poste. Elle
              // laisse entendre que l'e-mail peut passer au « oui » ; ici
              // aucun des quatre canaux n'a de transport.
              Text(
                'Sur ce poste, aucun des quatre ne l’est.',
                key: const Key('notifications-journal-aucun-transport'),
                style: styleContenuCarte(
                  TaillesContenu.t11,
                  couleur: PaletteMaitre.rouge700,
                ),
              ),
            ],
          ),
        ],
      ),
      enfants: [
        _Tableau(
          colonnes: const [
            'Date',
            'Destinataire',
            'Déclencheur',
            'Canal',
            'Statut',
            'Envoi système',
            'Par',
            'Commentaire',
          ],
          lignes: [
            for (final m in journal)
              DataRow(
                cells: [
                  DataCell(Text(formaterDate(m.traiteLe ?? m.composeLe))),
                  DataCell(
                    Text(
                      m.destinataire,
                      key: Key('notifications-journal-${m.id}'),
                      style: styleContenuCarte(
                        TaillesContenu.t13,
                        poids: FontWeight.w600,
                        couleur: Ardoise.c800,
                      ),
                    ),
                  ),
                  DataCell(Text(m.declencheur?.libelle ?? '')),
                  DataCell(Text(m.canal?.libelle ?? '')),
                  DataCell(
                    m.statut == StatutMessageNotification.transmisALaMain
                        ? _Pastille(
                            texte: m.statut.libelle,
                            fond: PaletteMaitre.emeraude50,
                            texteCouleur: PaletteMaitre.emeraude700,
                            taille: TaillesContenu.t11,
                            horizontal: AppSpacing.xs,
                          )
                        : _Pastille(
                            texte: m.statut.libelle,
                            fond: Ardoise.c100,
                            texteCouleur: Ardoise.c500,
                            taille: TaillesContenu.t11,
                            horizontal: AppSpacing.xs,
                          ),
                  ),
                  DataCell(
                    // Dérivé du STATUT, jamais écrit en dur : le jour où un
                    // transport écrira, la colonne suivra (PA-61).
                    _Pastille(
                      cle: Key('notifications-envoi-systeme-${m.id}'),
                      texte: m.statut.estUnEnvoiDuSysteme ? 'oui' : 'non',
                      fond: m.statut.estUnEnvoiDuSysteme
                          ? PaletteMaitre.emeraude50
                          : PaletteMaitre.rouge50,
                      texteCouleur: m.statut.estUnEnvoiDuSysteme
                          ? PaletteMaitre.emeraude700
                          : PaletteMaitre.rouge900,
                      taille: TaillesContenu.t11,
                      horizontal: AppSpacing.xs,
                    ),
                  ),
                  DataCell(Text(m.auteurAffiche)),
                  DataCell(
                    ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: AppLayout.bulleMessageNotification,
                      ),
                      child: Text(m.commentaireAffiche),
                    ),
                  ),
                ],
              ),
          ],
        ),
        if (journal.isEmpty)
          const _LigneVide(
            key: Key('notifications-journal-vide'),
            titre: 'Aucun résultat',
            // La vue (l.484) dit « Ce journal lit la table réelle des envois —
            // il se remplit dès qu'un e-mail est réellement délivré » : faux
            // ici, aucun e-mail ne peut partir de ce poste.
            detail:
                'Aucun message n’est encore sorti de la file. Ce journal porte '
                'les messages transmis à la main et abandonnés — la colonne '
                '« Envoi système » y dira toujours « non » tant qu’aucun canal '
                'n’est branché.',
          ),
      ],
    );
  }
}

/* ---------------------------------------------------------------- canaux */

class _PanneauCanaux extends ConsumerWidget {
  const _PanneauCanaux({required this.enFile});

  final Map<CanalNotification, int> enFile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transports = ref.watch(transportsLocauxProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Bloc(
          enTete: Text(
            'Canaux de diffusion',
            style: styleContenuCarte(
              TaillesContenu.t14,
              poids: FontWeight.bold,
              couleur: AppColors.navy,
            ),
          ),
          enfants: [
            _Tableau(
              colonnes: const [
                'Canal',
                'État',
                'Ce qui bloque',
                'Limite',
                'Destinataire attendu',
                'En file',
              ],
              lignes: [
                for (final c in CanalNotification.values)
                  DataRow(
                    cells: [
                      DataCell(
                        Text(
                          c.libelle,
                          key: Key('notifications-canal-${c.code}'),
                          style: styleContenuCarte(
                            TaillesContenu.t13,
                            poids: FontWeight.w600,
                            couleur: Ardoise.c800,
                          ),
                        ),
                      ),
                      DataCell(
                        transports.estBranche(c)
                            ? _Pastille(
                                texte: 'branché',
                                fond: PaletteMaitre.emeraude50,
                                texteCouleur: PaletteMaitre.emeraude700,
                                taille: TaillesContenu.t11,
                                horizontal: AppSpacing.xs,
                              )
                            : _Pastille(
                                texte: 'non branché',
                                fond: PaletteMaitre.rouge50,
                                texteCouleur: PaletteMaitre.rouge700,
                                taille: TaillesContenu.t11,
                                horizontal: AppSpacing.xs,
                              ),
                      ),
                      DataCell(
                        ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: AppLayout.bulleMessageNotification,
                          ),
                          child: Text(c.blocage),
                        ),
                      ),
                      DataCell(
                        Text(c.limite == null ? '—' : '${c.limite} car.'),
                      ),
                      DataCell(Text(c.cible)),
                      // Le décompte RÉEL : zéro s'écrit « 0 », c'est une
                      // mesure de la file et non un état affirmé.
                      DataCell(Text('${enFile[c] ?? 0}')),
                    ],
                  ),
              ],
            ),
          ],
        ),
        // `mb-3` du bloc précédent (l.502).
        const SizedBox(height: AppSpacing.sm),
        Container(
          // `rounded-xl p-4` avec fond et bordure en dur (l.541).
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: Ardoise.c50,
            border: Border.all(color: Ardoise.c200),
            borderRadius: BorderRadius.circular(AppRadius.roundedXl),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  style: styleContenuCarte(
                    TaillesContenu.t13,
                    couleur: Ardoise.c700,
                  ),
                  children: const [
                    TextSpan(
                      text: 'Ce qu’il faut lever, dans l’ordre.',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    TextSpan(
                      text:
                          ' Le canal WhatsApp suppose un contrat WhatsApp '
                          'Business et un numéro vérifié — c’est le plus long '
                          'à obtenir, et c’est aussi celui que le Gîte utilise '
                          'déjà à la main. L’e-mail ne demande qu’un relais '
                          'SMTP. Le canal Android attend l’application '
                          'Flutter, qui n’est pas démarrée. Le SMS suppose un '
                          'agrégateur retenu.',
                    ),
                  ],
                ),
              ),
              // `mt-2` — 8 px.
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Aucun de ces quatre points n’est un développement : ce sont '
                'des décisions et des contrats. Les modèles, eux, sont prêts '
                'et relisibles dès maintenant.',
                style: styleContenuCarte(
                  TaillesContenu.t13,
                  couleur: Ardoise.c700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/* =========================================================== fragments */

/// Un bloc blanc à en-tête — le motif de carte de la vue (`px-4 py-3
/// border-b border-slate-200`).
class _Bloc extends StatelessWidget {
  const _Bloc({required this.enTete, required this.enfants});

  final Widget enTete;
  final List<Widget> enfants;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.neutre0,
        borderRadius: BorderRadius.circular(AppRadius.roundedXl),
        border: Border.all(color: Ardoise.c200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Ardoise.c200)),
            ),
            child: enTete,
          ),
          ...enfants,
        ],
      ),
    );
  }
}

/// Un tableau à en-tête navy : `text-[11px] uppercase tracking-wide
/// text-white/90 font-semibold`, cellules `px-3` en `text-[13px]` (l.393-400).
class _Tableau extends StatelessWidget {
  const _Tableau({required this.colonnes, required this.lignes});

  final List<String> colonnes;
  final List<DataRow> lignes;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(AppColors.navy),
        dataTextStyle: styleContenuCarte(
          TaillesContenu.t13,
          couleur: Ardoise.c600,
        ),
        // `px-3` de chaque côté d'une cellule : 12 px de marge, 24 px entre
        // deux colonnes.
        horizontalMargin: AppSpacing.sm,
        columnSpacing: AppSpacing.lg,
        columns: [for (final c in colonnes) _EnteteColonne(c)],
        rows: lignes,
      ),
    );
  }
}

class _EnteteColonne extends DataColumn {
  _EnteteColonne(String libelle)
    : super(
        label: Text(
          // Rendu en MAJUSCULES : `uppercase` est une règle CSS de la vue, que
          // Flutter n'applique pas seul.
          libelle.toUpperCase(),
          style: styleContenuCarte(
            TaillesContenu.t11,
            poids: FontWeight.w600,
            couleur: AppColors.neutre0.withValues(alpha: 0.9),
            interlettrage: AppTextStyles.suiviLarge * TaillesContenu.t11,
          ),
        ),
      );
}

class _Pastille extends StatelessWidget {
  const _Pastille({
    required this.texte,
    required this.fond,
    required this.texteCouleur,
    this.taille = TaillesContenu.t10,
    this.horizontal = AppSpacing.xxs,
    this.vertical = AppSpacing.demi,
    Key? cle,
  }) : super(key: cle);

  final String texte;
  final Color fond;
  final Color texteCouleur;

  /// `text-[10px]` par défaut ; `text-[11px]` pour les pastilles de tableau.
  final double taille;

  /// `px-1.5` par défaut ; `px-2` pour les pastilles de tableau.
  final double horizontal;

  /// `py-0.5` par défaut ; `py-1` pour la raison qui remplace « Envoyer ».
  final double vertical;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: horizontal, vertical: vertical),
      decoration: BoxDecoration(
        color: fond,
        borderRadius: BorderRadius.circular(AppRadius.rounded),
      ),
      child: Text(
        texte,
        style: styleContenuCarte(taille, couleur: texteCouleur),
      ),
    );
  }
}

/// L'état vide d'un panneau à UNE phrase (`py-14 text-center text-slate-400
/// text-[13px]`, l.314).
class _EtatVideSimple extends StatelessWidget {
  const _EtatVideSimple({required Key cle, required this.texte})
    : super(key: cle);

  final String texte;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacingLarge.p14),
      decoration: BoxDecoration(
        color: AppColors.neutre0,
        borderRadius: BorderRadius.circular(AppRadius.roundedXl),
        border: Border.all(color: Ardoise.c200),
      ),
      child: Center(
        child: Text(
          texte,
          textAlign: TextAlign.center,
          style: styleContenuCarte(TaillesContenu.t13, couleur: Ardoise.c400),
        ),
      ),
    );
  }
}

/// Un état vide à deux lignes (`py-14 text-center` : un titre `font-semibold
/// text-slate-500`, puis un détail `text-slate-400`) dans sa propre carte.
class _EtatVide extends StatelessWidget {
  const _EtatVide({required Key cle, required this.titre, required this.detail})
    : super(key: cle);

  final String titre;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.neutre0,
        borderRadius: BorderRadius.circular(AppRadius.roundedXl),
        border: Border.all(color: Ardoise.c200),
      ),
      child: _LigneVide(titre: titre, detail: detail),
    );
  }
}

/// Les deux lignes d'un état vide — dans une carte (modèles) ou SOUS les
/// en-têtes d'un tableau (déclencheurs, journal).
class _LigneVide extends StatelessWidget {
  const _LigneVide({super.key, required this.titre, required this.detail});

  final String titre;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacingLarge.p14,
      ),
      child: Column(
        children: [
          Text(
            titre,
            textAlign: TextAlign.center,
            style: styleContenuCarte(
              TaillesContenu.t13,
              poids: FontWeight.w600,
              couleur: Ardoise.c500,
            ),
          ),
          // `mt-1` — 4 px.
          const SizedBox(height: AppSpacing.unit),
          ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppLayout.videNotifications,
            ),
            child: Text(
              detail,
              textAlign: TextAlign.center,
              style: styleContenuCarte(
                TaillesContenu.t13,
                couleur: Ardoise.c400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Le refus tracé quand personne n'est identifié.
///
/// RG-15 veut que la trace porte le nom de qui a agi : écrire « compte
/// inconnu » en base serait une identité inventée.
const String _sansSession =
    'Aucune session ouverte : le geste ne peut pas être tracé.';

void _dire(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
