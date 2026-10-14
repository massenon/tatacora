// Vue Blade maîtresse (PA-183) : pwa/transverse/contact-editeur.blade.php
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/navigation/coquille_vue.dart';
import '../../../core/navigation/trace_svg.dart';
import '../../../core/theme/app_breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/mesures_transverses.dart';
import 'widgets/briques_transverses.dart';

/// L'écran **Contactez l'éditeur** — lot D du plan du Product Owner
/// (14/10/2026).
///
/// Structure de la vue, dans son ordre : en-tête ; encart « Avant de nous
/// contacter » (lien et bouton vers l'aide) ; colonne des formulaires (les
/// deux boutons « Envoyer un message » / « Signaler un bug », puis « Vos
/// envois ») ; colonne des coordonnées de l'éditeur.
///
/// ## Ce que ce poste ne fait pas, et le DIT (D421)
///
/// La vue ouvre une modale, ENREGISTRE l'envoi et le transmet par courriel
/// (`ContactEditeur::envoyerMessage` / `signalerBug`). Ce poste est zéro
/// réseau : il n'envoie rien et n'enregistre aucun envoi. Les deux boutons
/// sont rendus, comme à la vue, et leur clic DIT qu'aucun message ne part,
/// avec les coordonnées de l'éditeur (Article 3.3 : jamais un bouton muet ;
/// jamais un formulaire qui ferait croire à un envoi). « Vos envois » rend
/// l'état vide de la vue — vrai sur ce poste — suivi de la raison.
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

  /// AJOUT déclaré (D421) : ce que le clic dit, et la raison sous la liste.
  static const String aucunEnvoi =
      "Ce poste n'envoie aucun message à l'éditeur : il ne communique avec "
      'aucun serveur, et rien n\'est enregistré. Écrivez à $editeurEmail1 '
      'ou appelez le $editeurTelephone.';
  static const String envoisSurCePoste =
      "Sur ce poste : aucun envoi n'est enregistré — ni message ni "
      'signalement ne part de ce poste.';
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

/// `lg:col-span-2 space-y-5` : les deux boutons, puis « Vos envois ».
class _ColonneFormulaires extends StatelessWidget {
  const _ColonneFormulaires();

  static const String _avion =
      r'<path stroke-linecap="round" stroke-linejoin="round" d="M22 2L11 13M22 2l-7 20-4-9-9-4 20-7z"/>';
  static const String _insecte =
      r'<rect x="8" y="6" width="8" height="14" rx="4"/><path stroke-linecap="round" d="M19 8l-3 2M5 8l3 2M19 16l-3-2M5 16l3-2M12 6V4M9 4h6"/>';

  @override
  Widget build(BuildContext context) {
    void dire() => direTransverse(
      context,
      TextesContact.aucunEnvoi,
      cle: const Key('contact-aucun-envoi'),
    );
    const marge = EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.xsPlus,
    );
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
              onTap: dire,
            ),
            BoutonTransverse(
              cle: const Key('contact-signaler-bug'),
              libelle: TextesContact.ongletBug,
              trace: _insecte,
              taille: TaillesContenu.t15,
              padding: marge,
              couleurContour: Ardoise.c200,
              couleurTexteContour: Ardoise.c500,
              onTap: dire,
            ),
          ],
        ),
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
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.mdPlus,
                  vertical: AppSpacing.xl,
                ),
                child: Column(
                  children: [
                    Text(
                      TextesContact.envoisVide,
                      key: const Key('contact-envois-vide'),
                      textAlign: TextAlign.center,
                      style: styleTransverse(
                        TaillesContenu.t13,
                        couleur: Ardoise.c400,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      TextesContact.envoisSurCePoste,
                      textAlign: TextAlign.center,
                      style: styleTransverse(
                        TaillesContenu.t12,
                        couleur: Ardoise.c400,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
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
