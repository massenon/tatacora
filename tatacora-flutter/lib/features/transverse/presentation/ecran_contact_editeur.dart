// Vue Blade maîtresse (PA-183) : pwa/transverse/contact-editeur.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/navigation/coquille_vue.dart';
import '../../../core/navigation/trace_svg.dart';
import '../../../core/theme/app_breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/di/providers.dart';
import '../../../core/fichiers/selecteur_fichiers.dart';
import '../../../core/theme/mesures_transverses.dart';
import '../data/captures_editeur.dart';
import '../data/envoi_messages_editeur.dart';
import '../domain/messages_editeur.dart';
import 'providers_contact_editeur.dart';
import 'widgets/briques_transverses.dart';
import 'widgets/modales_contact_editeur.dart';

/// L'écran **Contactez l'éditeur** — lot D du plan du Product Owner
/// (14/10/2026).
///
/// Structure de la vue, dans son ordre : en-tête ; encart « Avant de nous
/// contacter » (lien et bouton vers l'aide) ; colonne des formulaires (les
/// deux boutons « Envoyer un message » / « Signaler un bug », puis « Vos
/// envois ») ; colonne des coordonnées de l'éditeur.
///
/// ## Le poste ENVOIE — directive du PO du 14/10/2026 (Lot J2 partie 2)
///
/// Jusqu'au 14/10/2026 (D421), les deux boutons DISAIENT seulement qu'aucun
/// message ne partait : le poste était zéro réseau. Le Product Owner a
/// ordonné l'envoi réel. Comme à la vue (`ContactEditeur::envoyerMessage` /
/// `signalerBug`), chaque bouton ouvre sa modale ; « Envoyer » ÉCRIT d'abord
/// le message dans la boîte d'envoi du poste (`messages_editeur_local`,
/// `en_attente`), PUIS tente l'envoi SMTP à l'éditeur, borné à 20 s, sans
/// retenir l'écran. Accepté : « Transmis ». Refusé ou hors connexion : le
/// message reste en attente et repart seul (`relanceMessagesEditeurProvider`,
/// au démarrage puis toutes les 5 min). Jamais perdu, jamais supprimé.
///
/// C'est l'une des DEUX actions réseau du poste, avec la synchronisation en
/// tâche de fond (lot F2a, 15/10/2026). Tout le reste lit et écrit la base
/// locale.
///
/// « Vos envois » rend la liste RÉELLE des 50 derniers envois du compte, avec
/// leur statut mesuré. AJOUT du poste (aucune vue ne l'a) : l'encart
/// « Messages en attente d'envoi » — leur nombre pour tout le poste, la
/// dernière raison d'échec (le mot de passe SMTP absent de
/// `%APPDATA%\TATACORA\poste.json`, par exemple) et « Renvoyer maintenant » :
/// sur un poste dont la connexion tombe, l'opérateur doit savoir ce qui n'est
/// pas parti.
///
/// Les adresses et le téléphone sont rendus en TEXTE sélectionnable : la vue
/// pose des liens `mailto:`/`tel:`, que ce poste n'ouvre pas (aucun greffon
/// d'ouverture de lien n'est embarqué).
class EcranContactEditeur extends StatelessWidget {
  const EcranContactEditeur({super.key});

  @override
  Widget build(BuildContext context) {
    final large = MediaQuery.sizeOf(context).width >= AppBreakpoints.lg;
    const formulaires = _ColonneFormulaires();
    const coordonnees = _Coordonnees();
    return PageTransverse(
      largeurMax: MesuresTransverses.pageEtroite,
      enfants: [
        const EnTeteTransverse(
          trace: TracesCoquille.contactEditeur,
          titre: TextesContact.titre,
          sousTitre: TextesContact.sousTitre,
        ),
        const _AvantDeContacter(),
        const SizedBox(height: AppSpacing.lg), // mb-6
        if (large)
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 2, child: formulaires),
              SizedBox(width: AppSpacing.mdPlus), // gap-5
              Expanded(child: coordonnees),
            ],
          )
        else ...[
          formulaires,
          const SizedBox(height: AppSpacing.mdPlus),
          coordonnees,
        ],
      ],
    );
  }
}

/// Les textes de la vue (`pwa.contact.*`), au mot.
abstract final class TextesContact {
  static const String titre = "Contactez l'éditeur";
  static const String sousTitre =
      "Assistance technique, suggestions et signalement d'anomalies.";
  static const String avantTitre = 'Avant de nous contacter';
  static const String avantDetailAvant = "Consultez d'abord l'";
  static const String avantLien = 'Aide & FAQ';
  static const String avantDetailApres =
      ' — la réponse à votre question s\'y trouve peut-être déjà.';
  static const String avantBouton = "Ouvrir l'aide";
  static const String coordonneesTitre = "Coordonnées de l'éditeur";
  static const String editeurInitiales = 'MR';
  static const String editeurNom = 'Dr MASSENON Rhodes';
  static const String editeurFonction = 'Éditeur du logiciel';
  static const String editeurEmail1 = 'rarhodes06@gmail.com';
  static const String editeurEmail2 = 'contact@massenonrhodes.com';
  static const String editeurTelephone = '+229 01 51 33 50 40';
  static const String editeurHoraires = 'Lun-Ven, 8h-17h (GMT)';
  static const String ongletMessage = 'Envoyer un message';
  static const String ongletBug = 'Signaler un bug';
  static const String envoisTitre = 'Vos envois';
  static const String envoisSousTitre =
      'Vos 50 derniers envois. « Transmis » signifie que le courriel est réellement parti vers l\'éditeur.';
  static const String envoisVide = 'Aucun envoi depuis ce compte.';

  /// `pwa.contact.envois_capture`.
  static const String envoisCapture = '1 capture jointe';

  static const String envoisStatutTransmis = 'Transmis';
  static const String envoisStatutATransmettre = "En attente d'envoi";
  static const String messageEnvoye = "Message envoyé à l'éditeur.";
  static const String bugSignale = "Signalement envoyé à l'éditeur.";

  /// AJOUTS du poste (Lot J2 partie 2) — l'envoi, la file, ses raisons.
  static const String envoisStatutEchec = 'Échec — à renvoyer';
  static const String enregistreEnFile =
      'Message enregistré sur ce poste — il partira dès que la connexion '
      'reviendra.';
  static String enregistreNonConfigure(String raison) =>
      'Message enregistré sur ce poste, mais il ne peut pas partir : $raison '
      'Il partira dès que ce sera réglé.';
  static const String fileTitre = "Messages en attente d'envoi";
  static String fileDetail(int n) => n > 1
      ? "$n messages écrits sur ce poste n'ont pas encore été acceptés par la "
            'messagerie : relance automatique au démarrage puis toutes les 5 '
            'minutes.'
      : "1 message écrit sur ce poste n'a pas encore été accepté par la "
            'messagerie : relance automatique au démarrage puis toutes les 5 '
            'minutes.';
  static String fileEchecs(int n) =>
      '$n message${n > 1 ? 's ont' : ' a'} épuisé les relances automatiques : '
      '« Renvoyer maintenant » ${n > 1 ? 'les' : 'le'} remet en file.';
  static String derniereErreur(String raison) => 'Dernière erreur : $raison';
  static const String renvoyer = 'Renvoyer maintenant';
  static String bilanRenvoi(int envoyes, int restants) =>
      '$envoyes envoyé${envoyes > 1 ? 's' : ''}, $restants encore en attente.';
  static const String renvoiEnCours = 'Un envoi est déjà en cours.';
}

/// L'encart or : `rounded-xl border p-4 mb-6`, fond `#FFFBEB`, bordure
/// `#FDE68A`, texte `#7C5E12`.
class _AvantDeContacter extends StatelessWidget {
  const _AvantDeContacter();

  static const String _ampoule =
      r'<path stroke-linecap="round" stroke-linejoin="round" d="M9 18h6M10 22h4M12 2a7 7 0 00-4 12.7V17h8v-2.3A7 7 0 0012 2z"/>';

  @override
  Widget build(BuildContext context) {
    final large = MediaQuery.sizeOf(context).width >= AppBreakpoints.sm;
    void aide() => GoRouter.of(context).go('/aide-a-propos');
    final textes = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          TextesContact.avantTitre,
          style: styleTransverse(
            TaillesContenu.t15,
            poids: FontWeight.bold,
            couleur: PaletteTransverse.texteOr,
          ),
        ),
        const SizedBox(height: AppSpacing.demi),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              TextesContact.avantDetailAvant,
              style: styleTransverse(
                TaillesContenu.t13,
                couleur: PaletteTransverse.texteOr,
              ),
            ),
            InkWell(
              key: const Key('contact-lien-aide'),
              onTap: aide,
              child: Text(
                TextesContact.avantLien,
                style: styleTransverse(
                  TaillesContenu.t13,
                  poids: FontWeight.w600,
                  couleur: PaletteTransverse.texteOr,
                ).copyWith(decoration: TextDecoration.underline),
              ),
            ),
            Text(
              TextesContact.avantDetailApres,
              style: styleTransverse(
                TaillesContenu.t13,
                couleur: PaletteTransverse.texteOr,
              ),
            ),
          ],
        ),
      ],
    );
    final bouton = BoutonTransverse(
      cle: const Key('contact-bouton-aide'),
      libelle: TextesContact.avantBouton,
      fond: AppColors.gold,
      onTap: aide,
    );
    const icone = IconeTrace(
      trace: _ampoule,
      taille: MesuresTransverses.iconeRessource,
      couleur: AppColors.gold,
      epaisseur: MesuresTransverses.traitAppuye,
    );
    return EncadreTransverse(
      fond: PaletteMaitre.ambre50,
      bordure: PaletteMaitre.ambre200,
      child: large
          ? Row(
              children: [
                icone,
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: textes),
                const SizedBox(width: AppSpacing.sm),
                bouton,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                icone,
                const SizedBox(height: AppSpacing.sm),
                textes,
                const SizedBox(height: AppSpacing.sm),
                bouton,
              ],
            ),
    );
  }
}

/// Le geste d'un des deux boutons : la modale ÉCRIT le message, puis l'envoi
/// est tenté HORS de la modale — l'écran reste utilisable pendant les 20 s
/// au plus que peut durer la tentative — et son issue est DITE.
Future<void> _contacter(
  BuildContext context,
  WidgetRef ref,
  TypeMessageEditeur type,
) async {
  final service = ref.read(serviceMessagesEditeurProvider);
  final session = ref.read(sessionProvider);
  final revision = ref.read(revisionBoiteEditeurProvider.notifier);
  final messager = ScaffoldMessenger.of(context);
  final ecrit = await ouvrirModaleContact(
    context,
    type: type,
    enregistrer: (saisie) => service.enregistrer(
      saisie,
      auteurId: session?.utilisateurId,
      auteurLogin: session?.login,
    ),
    choisirCapture: () => ref
        .read(selecteurFichiersProvider)
        .ouvrirImage(extensions: BornesCapture.extensions),
    joindreCapture: (ecrit, capture) async {
      await service.captures.joindre(
        ecrit.id,
        nom: capture.nom,
        octets: capture.octets,
      );
    },
  );
  if (ecrit == null) return;
  revision.avancer();
  final resultat = await service.envoyer(ecrit);
  revision.avancer();
  switch (resultat.issue) {
    case IssueEnvoiEditeur.envoye:
      _toast(
        messager,
        type == TypeMessageEditeur.bug
            ? TextesContact.bugSignale
            : TextesContact.messageEnvoye,
        fond: AppColors.succes,
        cle: const Key('contact-toast-envoye'),
      );
    case IssueEnvoiEditeur.nonConfigure:
      _toast(
        messager,
        TextesContact.enregistreNonConfigure(resultat.raison ?? ''),
        fond: AppColors.alerte,
        cle: const Key('contact-toast-non-configure'),
      );
    case IssueEnvoiEditeur.echoue:
    case IssueEnvoiEditeur.dejaEnCours:
      _toast(
        messager,
        TextesContact.enregistreEnFile,
        fond: AppColors.alerte,
        cle: const Key('contact-toast-en-file'),
      );
  }
}

void _toast(
  ScaffoldMessengerState messager,
  String texte, {
  required Color fond,
  required Key cle,
}) {
  messager
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: fond,
        content: Text(texte, key: cle),
      ),
    );
}

/// `lg:col-span-2 space-y-5` : les deux boutons, l'encart de la file (ajout
/// du poste), puis « Vos envois ».
class _ColonneFormulaires extends ConsumerWidget {
  const _ColonneFormulaires();

  static const String _avion =
      r'<path stroke-linecap="round" stroke-linejoin="round" d="M22 2L11 13M22 2l-7 20-4-9-9-4 20-7z"/>';
  static const String _insecte =
      r'<rect x="8" y="6" width="8" height="14" rx="4"/><path stroke-linecap="round" d="M19 8l-3 2M5 8l3 2M19 16l-3-2M5 16l3-2M12 6V4M9 4h6"/>';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const marge = EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.xsPlus,
    );
    final envois = ref.watch(envoisDuCompteProvider);
    final avecCapture =
        ref.watch(envoisAvecCaptureProvider).value ?? const <String>{};
    final file = ref.watch(etatFileEditeurProvider).value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            BoutonTransverse(
              cle: const Key('contact-envoyer-message'),
              libelle: TextesContact.ongletMessage,
              fond: AppColors.navy,
              trace: _avion,
              taille: TaillesContenu.t15,
              padding: marge,
              onTap: () => _contacter(context, ref, TypeMessageEditeur.message),
            ),
            BoutonTransverse(
              cle: const Key('contact-signaler-bug'),
              libelle: TextesContact.ongletBug,
              trace: _insecte,
              taille: TaillesContenu.t15,
              padding: marge,
              couleurContour: Ardoise.c200,
              couleurTexteContour: Ardoise.c500,
              onTap: () => _contacter(context, ref, TypeMessageEditeur.bug),
            ),
          ],
        ),
        if (file != null && file.enAttente + file.enEchec > 0) ...[
          const SizedBox(height: AppSpacing.mdPlus),
          _FileEnAttente(etat: file),
        ],
        const SizedBox(height: AppSpacing.mdPlus),
        CarteTransverse(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.mdPlus,
                  vertical: AppSpacing.smPlus,
                ),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Ardoise.c100)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      TextesContact.envoisTitre,
                      style: styleTransverse(
                        TaillesContenu.sm,
                        poids: FontWeight.bold,
                        couleur: Ardoise.c700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.demi),
                    Text(
                      TextesContact.envoisSousTitre,
                      style: styleTransverse(
                        TaillesContenu.t12,
                        couleur: Ardoise.c500,
                      ),
                    ),
                  ],
                ),
              ),
              switch (envois) {
                AsyncData(:final value) when value.isNotEmpty => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < value.length; i++) ...[
                      if (i > 0) const Divider(height: 1, color: Ardoise.c100),
                      _LigneEnvoi(
                        envoi: value[i],
                        avecCapture: avecCapture.contains(value[i].id),
                      ),
                    ],
                  ],
                ),
                AsyncError(:final error) => Padding(
                  padding: const EdgeInsets.all(AppSpacing.mdPlus),
                  child: Text(
                    '$error',
                    style: styleTransverse(
                      TaillesContenu.t13,
                      couleur: AppColors.erreur,
                    ),
                  ),
                ),
                _ => Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.mdPlus,
                    vertical: AppSpacing.xl,
                  ),
                  child: Text(
                    TextesContact.envoisVide,
                    key: const Key('contact-envois-vide'),
                    textAlign: TextAlign.center,
                    style: styleTransverse(
                      TaillesContenu.t13,
                      couleur: Ardoise.c400,
                    ),
                  ),
                ),
              },
            ],
          ),
        ),
      ],
    );
  }
}

/// Une ligne de « Vos envois » : `px-5 py-3.5`, pastille BUG / MESSAGE, objet,
/// extrait du message (180 caractères), date `d/m/Y H:i` et statut.
class _LigneEnvoi extends StatelessWidget {
  const _LigneEnvoi({required this.envoi, this.avecCapture = false});

  final MessageEditeur envoi;

  /// `@if ($envoi->capture_nom)` : « · 1 capture jointe ».
  final bool avecCapture;

  @override
  Widget build(BuildContext context) {
    final bug = envoi.type == TypeMessageEditeur.bug;
    final (statut, couleurStatut) = switch (envoi.statut) {
      StatutMessageEditeur.envoye => (
        TextesContact.envoisStatutTransmis,
        AppColors.succes,
      ),
      StatutMessageEditeur.enAttente => (
        TextesContact.envoisStatutATransmettre,
        AppColors.alerte,
      ),
      StatutMessageEditeur.echec => (
        TextesContact.envoisStatutEchec,
        AppColors.erreur,
      ),
    };
    final corps = envoi.corps.length > MesuresTransverses.extraitEnvoi
        ? '${envoi.corps.substring(0, MesuresTransverses.extraitEnvoi)}...'
        : envoi.corps;
    return Padding(
      key: Key('contact-envoi-${envoi.id}'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.mdPlus,
        vertical: AppSpacing.smPlus,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: AppSpacing.unit),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xxs,
              vertical: AppSpacing.demi,
            ),
            decoration: BoxDecoration(
              color: bug ? AppColors.badgeRougeFond : AppColors.badgeBleuFond,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Text(
              bug ? 'BUG' : 'MESSAGE',
              style: styleTransverse(
                TaillesContenu.t10,
                poids: FontWeight.bold,
                couleur: bug ? AppColors.erreur : AppColors.info,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xsPlus),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  envoi.sujet,
                  style: styleTransverse(
                    TaillesContenu.t15,
                    poids: FontWeight.w600,
                    couleur: Ardoise.c700,
                  ),
                ),
                const SizedBox(height: AppSpacing.demi),
                Text(
                  corps,
                  style: styleTransverse(
                    TaillesContenu.t13,
                    couleur: Ardoise.c500,
                  ),
                ),
                const SizedBox(height: AppSpacing.unit),
                Text.rich(
                  TextSpan(
                    style: styleTransverse(
                      TaillesContenu.t12,
                      couleur: Ardoise.c400,
                    ),
                    children: [
                      TextSpan(text: '${dateHeureEditeur(envoi.creeLe)} · '),
                      if (avecCapture)
                        const TextSpan(
                          text: '${TextesContact.envoisCapture} · ',
                        ),
                      TextSpan(
                        text: statut,
                        style: TextStyle(color: couleurStatut),
                      ),
                    ],
                  ),
                ),
                if (envoi.statut != StatutMessageEditeur.envoye &&
                    envoi.derniereErreur != null) ...[
                  const SizedBox(height: AppSpacing.unit),
                  Text(
                    TextesContact.derniereErreur(envoi.derniereErreur!),
                    key: Key('contact-envoi-erreur-${envoi.id}'),
                    style: styleTransverse(
                      TaillesContenu.t12,
                      couleur: AppColors.erreur,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// AJOUT du poste — « Messages en attente d'envoi » : combien, pourquoi, et
/// « Renvoyer maintenant ». Rendu seulement quand la file n'est pas vide.
class _FileEnAttente extends ConsumerWidget {
  const _FileEnAttente({required this.etat});

  final EtatFileEditeur etat;

  Future<void> _renvoyer(BuildContext context, WidgetRef ref) async {
    final service = ref.read(serviceMessagesEditeurProvider);
    final revision = ref.read(revisionBoiteEditeurProvider.notifier);
    final messager = ScaffoldMessenger.of(context);
    final bilan = await service.relancer(forcer: true);
    revision.avancer();
    _toast(
      messager,
      bilan == null
          ? TextesContact.renvoiEnCours
          : TextesContact.bilanRenvoi(bilan.envoyes, bilan.restants),
      fond: bilan != null && bilan.restants == 0
          ? AppColors.succes
          : AppColors.alerte,
      cle: const Key('contact-toast-renvoi'),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final texte = styleTransverse(
      TaillesContenu.t13,
      couleur: PaletteTransverse.texteOr,
    );
    final total = etat.enAttente + etat.enEchec;
    final erreur = etat.derniereErreur;
    return EncadreTransverse(
      key: const Key('contact-file-en-attente'),
      fond: PaletteMaitre.ambre50,
      bordure: PaletteMaitre.ambre200,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${TextesContact.fileTitre} ($total)',
            style: styleTransverse(
              TaillesContenu.t15,
              poids: FontWeight.bold,
              couleur: PaletteTransverse.texteOr,
            ),
          ),
          const SizedBox(height: AppSpacing.demi),
          Text(TextesContact.fileDetail(total), style: texte),
          if (etat.enEchec > 0) ...[
            const SizedBox(height: AppSpacing.demi),
            Text(TextesContact.fileEchecs(etat.enEchec), style: texte),
          ],
          if (erreur != null) ...[
            const SizedBox(height: AppSpacing.xxs),
            SelectableText(
              TextesContact.derniereErreur(erreur),
              key: const Key('contact-file-erreur'),
              style: texte.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          BoutonTransverse(
            cle: const Key('contact-renvoyer'),
            libelle: TextesContact.renvoyer,
            fond: AppColors.gold,
            onTap: () => _renvoyer(context, ref),
          ),
        ],
      ),
    );
  }
}

/// `<aside>` : « Coordonnées de l'éditeur », avatar navy, nom, fonction, deux
/// adresses, téléphone, horaires.
class _Coordonnees extends StatelessWidget {
  const _Coordonnees();

  static const String _telephone =
      r'<path stroke-linecap="round" stroke-linejoin="round" d="M22 16.92v3a2 2 0 01-2.18 2 19.79 19.79 0 01-8.63-3.07 19.5 19.5 0 01-6-6A19.79 19.79 0 012.12 4.18 2 2 0 014.11 2h3a2 2 0 012 1.72c.13.96.36 1.9.7 2.81a2 2 0 01-.45 2.11L8.09 9.91a16 16 0 006 6l1.27-1.27a2 2 0 012.11-.45c.9.34 1.85.57 2.81.7A2 2 0 0122 16.92z"/>';
  static const String _horloge =
      r'<circle cx="12" cy="12" r="10"/><path stroke-linecap="round" stroke-linejoin="round" d="M12 6v6l4 2"/>';

  @override
  Widget build(BuildContext context) {
    final texte = styleTransverse(TaillesContenu.t13, couleur: Ardoise.c700);
    Widget ligne(String trace, Widget enfant) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.demi),
          child: IconeTrace(
            trace: trace,
            taille: MesuresTransverses.iconePetite,
            couleur: AppColors.gold,
          ),
        ),
        const SizedBox(width: AppSpacing.xsPlus),
        Expanded(child: enfant),
      ],
    );
    return CarteTransverse(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            TextesContact.coordonneesTitre,
            style: styleTransverse(
              TaillesContenu.sm,
              poids: FontWeight.bold,
              couleur: Ardoise.c700,
            ),
          ),
          const SizedBox(height: AppSpacing.smPlus),
          Row(
            children: [
              Container(
                width: MesuresTransverses.avatarEditeur,
                height: MesuresTransverses.avatarEditeur,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.navy,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  TextesContact.editeurInitiales,
                  style: styleTransverse(
                    TaillesContenu.sm,
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
                      TextesContact.editeurNom,
                      style: styleTransverse(
                        TaillesContenu.t15,
                        poids: FontWeight.bold,
                        couleur: Ardoise.c800,
                      ),
                    ),
                    Text(
                      TextesContact.editeurFonction,
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
          ligne(
            TracesCoquille.contactEditeur,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(TextesContact.editeurEmail1, style: texte),
                SelectableText(TextesContact.editeurEmail2, style: texte),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          ligne(
            _telephone,
            SelectableText(TextesContact.editeurTelephone, style: texte),
          ),
          const SizedBox(height: AppSpacing.sm),
          ligne(_horloge, Text(TextesContact.editeurHoraires, style: texte)),
        ],
      ),
    );
  }
}
