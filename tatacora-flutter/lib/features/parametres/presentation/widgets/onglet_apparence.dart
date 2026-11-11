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
import '../../../../core/di/providers.dart';
import '../../../../core/rbac/garde_acces.dart';
import '../../../facturation/data/depot_images_document.dart';
import '../../../facturation/data/images_document_poste.dart';
import '../../../restaurant/presentation/widgets/coquille_modale_restaurant.dart';
import '../../../restaurant/presentation/widgets/corps_carte_commun.dart';
import '../../../restaurant/presentation/widgets/textes_modale_restaurant.dart';
import '../../../transverse/domain/comptes_utilisateurs.dart';
import '../../data/apparence_poste.dart';

/// Les mots de l'onglet « Logo & Apparence » — `lang/fr/pwa.php`,
/// `parametres.apparence_*` et `parametres.charte_*`, au mot.
abstract final class TextesOngletApparence {
  /// Signature et cachet des factures et proformas (PO, 07/11/2026), DÉPOSÉS depuis le poste
  /// ou le web (PO, 11/11/2026) : `pwa.parametres.apparence_signature_titre`, `_bouton`,
  /// `_enregistre`, `_retire`, `apparence_cachet_*`, `apparence_retirer`, `_image_absente`.
  static const signatureTitre = 'Signature du signataire';
  static const cachetTitre = "Cachet de l'entreprise";
  static const imageAbsente = 'Aucune image déposée.';
  static const signatureBouton = 'Changer la signature';
  static const cachetBouton = 'Changer le cachet';
  static const retirer = 'Retirer';
  static const signatureEnregistree =
      "Signature remplacée — l'ancien fichier n'est pas conservé.";
  static const cachetEnregistre =
      "Cachet remplacé — l'ancien fichier n'est pas conservé.";
  static const signatureRetiree =
      "Signature retirée — les documents n'impriment plus que le nom et la fonction.";
  static const cachetRetire = 'Cachet retiré.';

  /// Le bloc sous l'interrupteur « Afficher la signature et le cachet sur les factures »
  /// (`pwa.parametres.signature_cachet_bloc_titre`, `_aide`). Depuis le 11/11/2026 le poste
  /// DÉPOSE aussi les images (administrateurs, comme au web) : plus aucune phrase « se déposent
  /// depuis la version web ».
  static const blocSignatureCachetTitre = 'Signature et cachet';
  static const blocSignatureCachetAide =
      "Images des factures A4 et des proformas, jamais du ticket : PNG, JPG ou WebP, réduites à 400 Ko. Elles ne s'impriment que si l'interrupteur ci-dessus est activé.";

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
  static const charteTitre = 'Couleurs de la charte graphique (lecture seule)';
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

    final colonneSignature = const BlocImageDocument(
      cle: 'apparence-signature',
      nature: ImageDocument.signature,
    );
    final colonneCachet = const BlocImageDocument(
      cle: 'apparence-cachet',
      nature: ImageDocument.cachet,
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
          if (large)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: colonneSignature),
                const SizedBox(width: AppSpacing.lg),
                Expanded(child: colonneCachet),
              ],
            )
          else ...[
            colonneSignature,
            const SizedBox(height: AppSpacing.lg),
            colonneCachet,
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

/// La signature ou le cachet des documents A4 (11/11/2026, décision du PO) : l'aperçu — ou
/// « Aucune image déposée. » —, et, pour un ADMINISTRATEUR qui écrit sur PARAM, « Changer … »
/// (fenêtre « Ouvrir » native) et « Retirer », comme `images-signature-cachet.blade.php`.
///
/// Le choix s'enregistre tout de suite : l'image est validée (type lu des octets), réduite à
/// 400 Ko au besoin, rangée sur ce poste puis enfilée au serveur (`DepotImagesDocumentPoste`).
/// Un refus se dit sous l'aperçu et ne change rien. Un non-administrateur voit l'image sans bouton.
class BlocImageDocument extends ConsumerStatefulWidget {
  const BlocImageDocument({super.key, required this.cle, required this.nature});

  final String cle;
  final ImageDocument nature;

  @override
  ConsumerState<BlocImageDocument> createState() => _BlocImageDocumentState();
}

class _BlocImageDocumentState extends ConsumerState<BlocImageDocument> {
  String? _refus;
  bool _occupe = false;

  bool get _signature => widget.nature == ImageDocument.signature;

  FutureProvider<Uint8List?> get _fournisseur =>
      _signature ? signatureDocumentProvider : cachetDocumentProvider;

  Future<void> _changer() async {
    final fichier = await ref
        .read(selecteurFichiersProvider)
        .ouvrirImage(extensions: extensionsImageDocument);
    if (fichier == null || !mounted) return;
    await _faire(
      () => ref
          .read(depotImagesDocumentProvider)
          .deposer(widget.nature, fichier.octets),
      _signature
          ? TextesOngletApparence.signatureEnregistree
          : TextesOngletApparence.cachetEnregistre,
    );
  }

  Future<void> _retirer() => _faire(
    () => ref.read(depotImagesDocumentProvider).retirer(widget.nature),
    _signature
        ? TextesOngletApparence.signatureRetiree
        : TextesOngletApparence.cachetRetire,
  );

  Future<void> _faire(Future<void> Function() geste, String message) async {
    setState(() {
      _occupe = true;
      _refus = null;
    });
    try {
      await geste();
      ref.invalidate(_fournisseur);
      if (!mounted) return;
      setState(() => _occupe = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(message, key: Key('${widget.cle}-toast'))),
        );
    } on RefusImageDocument catch (r) {
      if (!mounted) return;
      setState(() {
        _occupe = false;
        _refus = r.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final octets = ref.watch(_fournisseur).value;
    final peut =
        ref.watch(droitsProvider).peutEcrire(ModuleTatacora.parametres) &&
        peutAdministrerComptes(ref.watch(sessionProvider)?.role);
    final cle = widget.cle;
    final apercu = octets == null
        ? Text(
            TextesOngletApparence.imageAbsente,
            key: Key('$cle-absente'),
            style: styleContenuCarte(TaillesContenu.t13, couleur: Ardoise.c400),
          )
        : Container(
            key: Key('$cle-apercu'),
            width: AppLayout.apercuLogo,
            height: AppLayout.apercuLogo,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.roundedLg),
              border: Border.all(
                color: Ardoise.c100,
                width: AppLayout.anneauLogo,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.roundedLg),
              child: Image.memory(octets, fit: BoxFit.contain),
            ),
          );
    return _Bloc(
      titre: _signature
          ? TextesOngletApparence.signatureTitre
          : TextesOngletApparence.cachetTitre,
      enfant: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              apercu,
              if (peut)
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    BoutonStandard(
                      key: Key('$cle-changer'),
                      libelle: _signature
                          ? TextesOngletApparence.signatureBouton
                          : TextesOngletApparence.cachetBouton,
                      onPressed: _occupe ? null : _changer,
                    ),
                    if (octets != null)
                      BoutonStandard(
                        key: Key('$cle-retirer'),
                        libelle: TextesOngletApparence.retirer,
                        onPressed: _occupe ? null : _retirer,
                      ),
                  ],
                ),
            ],
          ),
          if (_refus != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              _refus!,
              key: Key('$cle-refus'),
              style: styleContenuCarte(
                TaillesContenu.t13,
                couleur: AppColors.erreur,
              ),
            ),
          ],
        ],
      ),
    );
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

/// Sous l'interrupteur de signature (Paramètres › Identité & Légal) : signature et cachet, avec
/// leur dépôt, leur remplacement et leur retrait (administrateurs).
class BlocSignatureCachet extends ConsumerWidget {
  const BlocSignatureCachet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      key: const Key('bloc-signature-cachet'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.roundedLg),
        border: Border.all(color: Ardoise.c100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            TextesOngletApparence.blocSignatureCachetTitre,
            style: styleContenuCarte(
              TaillesContenu.t15,
              poids: FontWeight.w600,
              couleur: Ardoise.c700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            TextesOngletApparence.blocSignatureCachetAide,
            key: const Key('bloc-signature-cachet-aide'),
            style: styleContenuCarte(TaillesContenu.t13, couleur: Ardoise.c500),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.md,
            children: [
              BlocImageDocument(
                cle: 'signature-sous-interrupteur',
                nature: ImageDocument.signature,
              ),
              BlocImageDocument(
                cle: 'cachet-sous-interrupteur',
                nature: ImageDocument.cachet,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
