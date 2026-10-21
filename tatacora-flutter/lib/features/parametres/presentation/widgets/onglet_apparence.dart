// Vue Blade maîtresse (PA-183) : pwa/transverse/parametres.blade.php
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/fichiers/selecteur_fichiers.dart';
import '../../../../core/theme/app_assets.dart';
import '../../../../core/theme/app_breakpoints.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../shared_widgets/bouton_standard.dart';
import '../../../restaurant/presentation/widgets/coquille_modale_restaurant.dart';
import '../../../restaurant/presentation/widgets/corps_carte_commun.dart';
import '../../../restaurant/presentation/widgets/textes_modale_restaurant.dart';
import '../../data/apparence_poste.dart';

/// Les mots de l'onglet « Logo & Apparence » — `lang/fr/pwa.php`,
/// `parametres.apparence_*` et `parametres.charte_*`, au mot.
abstract final class TextesOngletApparence {
  static const logoTitre = "Logo de l'entreprise";
  static const logoBouton = 'Changer le logo';
  static const logoAide =
      'Format carré recommandé, fond transparent de préférence.';
  static const faviconTitre = "Favicon (icône d'onglet navigateur)";
  static const faviconBouton = 'Changer le favicon';
  static const champLogo =
      'Sélectionnez un fichier PNG/JPG (recommandé 512×512px).';
  static const champFavicon = 'Sélectionnez un fichier .ico ou .png 32×32px.';
  static const logoEnregistre =
      "Logo remplacé — l'ancien fichier n'est pas conservé.";
  static const faviconEnregistre =
      "Favicon remplacé — l'ancien fichier n'est pas conservé.";

  /// `apparence_logo_alt` / `apparence_favicon_alt` — l'`alt` des deux aperçus.
  static const logoAlt = 'Logo actuel';
  static const faviconAlt = 'Favicon actuel';

  /// `apparence_televersement` : la phrase affichée pendant l'envoi.
  static const televersement = 'Téléversement en cours…';
  static const charteTitre =
      'Couleurs de la charte graphique (lecture seule — chap. 9.3.1 du CdCF)';
  static const choisir = 'Choisir un fichier';
  static const aucunFichier = 'Aucun fichier choisi';
  static const annuler = 'Annuler';
  static const enregistrer = 'Enregistrer';
}

/// **Paramètres → Logo & Apparence** : les aperçus du logo et du favicon
/// actuels, leur remplacement (fenêtre « Ouvrir » native, fichier copié à côté
/// de `poste.json`) et la charte graphique en lecture seule.
///
/// Tant que rien n'est téléversé, l'aperçu montre l'actif livré — comme la vue,
/// dont le repli est le même (`ApparenceEtablissementService::ACTIF_LIVRE`).
class OngletApparence extends ConsumerWidget {
  const OngletApparence({super.key, required this.peutEcrire});

  final bool peutEcrire;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logo = ref.watch(logoTeleverseProvider).value;
    final favicon = ref.watch(faviconTeleverseProvider).value;

    final colonneLogo = _Bloc(
      titre: TextesOngletApparence.logoTitre,
      enfant: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _Apercu(
            cle: const Key('apparence-logo-apercu'),
            octets: logo,
            cote: AppLayout.apercuLogo,
            alt: TextesOngletApparence.logoAlt,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (peutEcrire)
                  BoutonStandard(
                    key: const Key('apparence-logo-changer'),
                    libelle: TextesOngletApparence.logoBouton,
                    onPressed: () =>
                        _changer(context, ref, UsageApparence.logo),
                  ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  TextesOngletApparence.logoAide,
                  style: styleContenuCarte(
                    TaillesContenu.t13,
                    couleur: Ardoise.c400,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    final colonneFavicon = _Bloc(
      titre: TextesOngletApparence.faviconTitre,
      enfant: Row(
        children: [
          _Apercu(
            cle: const Key('apparence-favicon-apercu'),
            octets: favicon,
            cote: AppLayout.apercuFavicon,
            alt: TextesOngletApparence.faviconAlt,
          ),
          const SizedBox(width: AppSpacing.md),
          if (peutEcrire)
            BoutonStandard(
              key: const Key('apparence-favicon-changer'),
              libelle: TextesOngletApparence.faviconBouton,
              onPressed: () => _changer(context, ref, UsageApparence.favicon),
            ),
        ],
      ),
    );

    final large = MediaQuery.sizeOf(context).width >= AppBreakpoints.sm;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (large)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: colonneLogo),
                const SizedBox(width: AppSpacing.lg),
                Expanded(child: colonneFavicon),
              ],
            )
          else ...[
            colonneLogo,
            const SizedBox(height: AppSpacing.lg),
            colonneFavicon,
          ],
          const SizedBox(height: AppSpacing.lg),
          const _Charte(),
        ],
      ),
    );
  }

  Future<void> _changer(
    BuildContext context,
    WidgetRef ref,
    UsageApparence usage,
  ) async {
    final message = await showDialog<String>(
      context: context,
      barrierColor: AppColors.voileModale,
      builder: (_) => _ModaleImage(usage: usage),
    );
    if (message == null) return;
    ref.invalidate(
      usage == UsageApparence.logo
          ? logoTeleverseProvider
          : faviconTeleverseProvider,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(message, key: const Key('apparence-toast'))),
        );
    }
  }
}

class _Bloc extends StatelessWidget {
  const _Bloc({required this.titre, required this.enfant});

  final String titre;
  final Widget enfant;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titre,
          style: styleContenuCarte(
            TaillesContenu.t15,
            poids: FontWeight.w600,
            couleur: Ardoise.c700,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        enfant,
      ],
    );
  }
}

/// Un aperçu : le fichier téléversé, à défaut l'actif livré — `object-contain`
/// dans un cadre arrondi à anneau.
class _Apercu extends StatelessWidget {
  const _Apercu({
    required Key cle,
    required this.octets,
    required this.cote,
    required this.alt,
  }) : super(key: cle);

  final Uint8List? octets;
  final double cote;

  /// L'`alt` de la vue, rendu en sémantique.
  final String alt;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: alt,
      image: true,
      child: Container(
        width: cote,
        height: cote,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.roundedLg),
          border: Border.all(color: Ardoise.c100, width: AppLayout.anneauLogo),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.roundedLg),
          child: octets == null
              ? Image.asset(AppAssets.logo, fit: BoxFit.contain)
              : Image.memory(octets!, fit: BoxFit.contain),
        ),
      ),
    );
  }
}

/// La charte graphique, en lecture seule — cinq pastilles, couleurs du maître.
class _Charte extends StatelessWidget {
  const _Charte();

  static const _couleurs = [
    ('Navy', AppColors.navy),
    ('Gold', AppColors.gold),
    ('Succès', AppColors.succes),
    ('Alerte', AppColors.alerte),
    ('Erreur', AppColors.erreur),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Bloc(
          titre: TextesOngletApparence.charteTitre,
          enfant: Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final (nom, couleur) in _couleurs)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: AppLayout.pastilleCharte,
                      height: AppLayout.pastilleCharte,
                      decoration: BoxDecoration(
                        color: couleur,
                        borderRadius: BorderRadius.circular(
                          AppRadius.roundedLg,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.demi),
                    Text(
                      nom,
                      style: styleContenuCarte(
                        TaillesContenu.t12,
                        couleur: Ardoise.c500,
                      ).copyWith(fontFamily: AppTextStyles.policeMonospace),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// La modale « Changer le logo » / « Changer le favicon » — `largeur="440px"`.
class _ModaleImage extends ConsumerStatefulWidget {
  const _ModaleImage({required this.usage});

  final UsageApparence usage;

  @override
  ConsumerState<_ModaleImage> createState() => _ModaleImageState();
}

class _ModaleImageState extends ConsumerState<_ModaleImage> {
  FichierLu? _choisi;
  String? _refus;
  bool _envoi = false;

  bool get _logo => widget.usage == UsageApparence.logo;

  @override
  Widget build(BuildContext context) {
    return CoquilleModaleRestaurant(
      cle: const Key('modale-apparence'),
      titre: _logo
          ? TextesOngletApparence.logoBouton
          : TextesOngletApparence.faviconBouton,
      sousTitre: _logo
          ? TextesOngletApparence.champLogo
          : TextesOngletApparence.champFavicon,
      largeur: AppLayout.modaleApparence,
      refus: _refus,
      cleRefus: const Key('modale-apparence-refus'),
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              OutlinedButton(
                key: const Key('modale-apparence-choisir'),
                onPressed: _envoi ? null : _choisir,
                child: const Text(
                  TextesOngletApparence.choisir,
                  style: TextesModaleRestaurant.bouton,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  _choisi?.nom ?? TextesOngletApparence.aucunFichier,
                  key: const Key('modale-apparence-nom'),
                  overflow: TextOverflow.ellipsis,
                  style: TextesModaleRestaurant.aide,
                ),
              ),
            ],
          ),
          // `wire:loading` de la vue : la phrase n'est montrée que pendant
          // l'envoi.
          if (_envoi) ...[
            const SizedBox(height: AppSpacing.xs),
            const Text(
              TextesOngletApparence.televersement,
              key: Key('modale-apparence-televersement'),
              style: TextesModaleRestaurant.aide,
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          key: const Key('modale-apparence-annuler'),
          onPressed: _envoi ? null : () => Navigator.of(context).pop(),
          child: const Text(
            TextesOngletApparence.annuler,
            style: TextesModaleRestaurant.bouton,
          ),
        ),
        FilledButton(
          key: const Key('modale-apparence-valider'),
          onPressed: _envoi ? null : _enregistrer,
          child: const Text(
            TextesOngletApparence.enregistrer,
            style: TextesModaleRestaurant.bouton,
          ),
        ),
      ],
    );
  }

  Future<void> _choisir() async {
    final fichier = await ref
        .read(selecteurFichiersProvider)
        .ouvrirImage(extensions: widget.usage.extensions);
    if (fichier == null || !mounted) return;
    setState(() {
      _choisi = fichier;
      _refus = null;
    });
  }

  Future<void> _enregistrer() async {
    final fichier = _choisi;
    if (fichier == null) {
      setState(() => _refus = 'Choisissez d’abord un fichier.');
      return;
    }
    setState(() {
      _envoi = true;
      _refus = null;
    });
    try {
      await ref.read(apparencePosteProvider).enregistrer(widget.usage, fichier);
      if (!mounted) return;
      Navigator.of(context).pop(
        _logo
            ? TextesOngletApparence.logoEnregistre
            : TextesOngletApparence.faviconEnregistre,
      );
    } on RefusApparence catch (r) {
      if (!mounted) return;
      setState(() {
        _envoi = false;
        _refus = r.message;
      });
    }
  }
}
