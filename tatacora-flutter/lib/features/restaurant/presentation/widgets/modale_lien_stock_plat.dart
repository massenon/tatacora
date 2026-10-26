import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/format/cle_comparaison.dart';
import '../../../../core/format/formats.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../stocks/domain/calcul_stock.dart' show ecrireCentiemes;
import '../../data/restaurant_api.dart';
import '../../domain/calcul_restaurant.dart';
import '../../domain/entities/carte_restaurant.dart';
import '../../domain/entities/plat.dart';
import '../../domain/messages_restaurant.dart';
import '../providers_restaurant.dart';
import 'coquille_modale_restaurant.dart';
import 'textes_modale_restaurant.dart';

/// Les mots de la modale « Lier au stock » et du dialogue « Retirer le lien »
/// du restaurant — `lang/fr/carte_pwa.php` (`modale_lien`, `modale_delier`,
/// `commun`), au mot.
abstract final class TextesLienPlat {
  static const String boutonLier = 'Lier au stock';
  static const String boutonModifier = 'Modifier le lien';
  static const String boutonDelier = 'Délier';
  static const String titre = 'Lier au stock';
  static const String champArticle = 'Article de stock';
  static const String inviteArticle = 'Rechercher un article de stock…';
  static const String aucunArticle =
      'Aucun article en suivi permanent ne correspond à cette recherche.';
  static String champConversion(String plat) =>
      'Combien de « $plat » dans une unité de stock ?';
  static const String apercuStock = 'Stock actuel';
  static const String apercuVendables = 'Soit, en unités vendables';
  static const String apercuDecrement = 'Chaque vente décrémentera';
  static const String nonConsulte = 'non consulté';
  static const String annuler = 'Annuler';
  static const String confirmer = 'Enregistrer le lien';
  static const String delierTitre = 'Retirer le lien au stock ?';
  static const String delierMessage =
      'Les ventes de cet article ne décrémenteront plus aucun stock.';
  static const String delierDetail =
      "La fiche de stock cessera de refléter ce qui sort réellement de l'établissement.";
  static const String delierConfirmer = 'Retirer le lien';
}

/// « Lier au stock » / « Modifier le lien » d'un plat de la carte : l'article
/// de stock ET son conditionnement vont ensemble. Rend `true` si le lien a été
/// enregistré.
Future<bool?> ouvrirModaleLienStockPlat(
  BuildContext context, {
  required LigneCarteRestaurant ligne,
}) => showDialog<bool>(
  context: context,
  barrierDismissible: true,
  barrierColor: AppColors.voileModale,
  builder: (_) => _ModaleLienPlat(ligne: ligne),
);

/// « Délier » : confirme, puis retire les DEUX colonnes. Rend `true` si fait.
Future<bool?> ouvrirDialogueDelierPlat(
  BuildContext context, {
  required LigneCarteRestaurant ligne,
}) => showDialog<bool>(
  context: context,
  barrierDismissible: true,
  barrierColor: AppColors.voileModale,
  builder: (_) => _DialogueDelier(ligne: ligne),
);

class _ModaleLienPlat extends ConsumerStatefulWidget {
  const _ModaleLienPlat({required this.ligne});

  final LigneCarteRestaurant ligne;

  @override
  ConsumerState<_ModaleLienPlat> createState() => _ModaleLienPlatState();
}

class _ModaleLienPlatState extends ConsumerState<_ModaleLienPlat> {
  late final TextEditingController _conversion = TextEditingController(
    // La valeur proposée est CELLE QUI EST ENREGISTRÉE, jamais 1 par défaut sur
    // un lien existant : rouvrir un casier de 24 et repartir avec 1 diviserait
    // la déduction par vingt-quatre. Sans lien, « 1 » comme la vue.
    text: widget.ligne.unitesVendables ?? '1',
  );
  final TextEditingController _recherche = TextEditingController();

  late String? _articleId = widget.ligne.articleStockId;
  int? _stockCentiemes;
  bool _stockLu = false;
  bool _envoi = false;
  String? _refus;
  Map<String, String> _parChamp = const {};

  @override
  void initState() {
    super.initState();
    if (_articleId != null) _lireStock(_articleId!);
  }

  @override
  void dispose() {
    _conversion.dispose();
    _recherche.dispose();
    super.dispose();
  }

  Future<void> _lireStock(String id) async {
    final stock = await ref.read(restaurantApiProvider).stockCuisineDe(id);
    if (!mounted || _articleId != id) return;
    setState(() {
      _stockCentiemes = stock;
      _stockLu = true;
    });
  }

  Future<void> _enregistrer() async {
    setState(() {
      _envoi = true;
      _refus = null;
      _parChamp = const {};
    });
    final messager = ScaffoldMessenger.of(context);
    final navigateur = Navigator.of(context);

    final resultat = await ref
        .read(restaurantApiProvider)
        .lierAuStock(
          platId: widget.ligne.id,
          articleId: _articleId ?? '',
          conditionnement: _conversion.text,
        );
    if (!mounted) return;

    switch (resultat) {
      case RestaurantRecu<Plat>(:final donnees):
        invaliderRestaurant(ref);
        messager
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Text(
                MessagesRestaurant.lienEnregistre(donnees.libelle),
                key: const Key('toast-lien-plat'),
              ),
            ),
          );
        navigateur.pop(true);
      case RestaurantRefuse<Plat>(:final motif, :final erreurs):
        setState(() {
          _envoi = false;
          _refus = motif;
          _parChamp = erreurs;
        });
      case RestaurantInjoignable<Plat>():
        setState(() => _envoi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final articles = ref.watch(articlesLiensProvider);
    final choix = switch (articles) {
      AsyncData(value: final v) => v,
      _ => null,
    };
    final terme = cleDeComparaison(_recherche.text.trim());
    final proposes = [
      for (final a in choix ?? const <ArticleChoix>[])
        if (terme.isEmpty ||
            a.id == _articleId ||
            cleDeComparaison(a.libelle).contains(terme))
          a,
    ];
    final prix = prixLien(widget.ligne.prixVente);

    return CoquilleModaleRestaurant(
      cle: const Key('modale-lien-plat'),
      titre: TextesLienPlat.titre,
      // `modale_lien.sous_titre` : « :article — :prix ».
      sousTitre: '${widget.ligne.libelle} — $prix',
      largeur: AppLayout.modaleLienStock,
      refus: _parChamp.isEmpty ? _refus : null,
      cleRefus: const Key('lien-plat-refus'),
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const EtiquetteLien(texte: TextesLienPlat.champArticle),
          TextField(
            key: const Key('lien-plat-recherche'),
            controller: _recherche,
            onChanged: (_) => setState(() {}),
            style: TextesModaleRestaurant.etiquette,
            decoration: const InputDecoration(
              hintText: TextesLienPlat.inviteArticle,
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          if (choix == null)
            const LinearProgressIndicator()
          else
            DropdownButtonFormField<String>(
              key: const Key('lien-plat-article'),
              initialValue: proposes.any((a) => a.id == _articleId)
                  ? _articleId
                  : null,
              isExpanded: true,
              style: TextesModaleRestaurant.etiquette,
              decoration: InputDecoration(
                hintText: TextesLienPlat.inviteArticle,
                isDense: true,
                border: const OutlineInputBorder(),
                errorText: _parChamp['article_stock_id'],
                errorMaxLines: 4,
              ),
              items: [
                for (final a in proposes)
                  DropdownMenuItem(
                    value: a.id,
                    child: Text(
                      '${a.libelle} — ${a.uniteMesure}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (v) {
                setState(() {
                  _articleId = v;
                  _stockLu = false;
                  _stockCentiemes = null;
                });
                if (v != null) _lireStock(v);
              },
            ),
          if (choix != null && proposes.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: AppSpacing.unit),
              child: Text(
                TextesLienPlat.aucunArticle,
                key: Key('lien-plat-aucun-article'),
                style: TextesModaleRestaurant.aide,
              ),
            ),
          const SizedBox(height: AppSpacing.unit),
          const Text.rich(
            TextSpan(
              style: TextesModaleRestaurant.aide,
              children: [
                TextSpan(text: 'Seuls les articles en '),
                TextSpan(
                  text: 'suivi permanent',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(
                  text:
                      " apparaissent : un article en achat journalier n'est pas suivi, le rattacher ne décrémenterait rien.",
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          EtiquetteLien(
            texte: TextesLienPlat.champConversion(widget.ligne.libelle),
          ),
          TextField(
            key: const Key('lien-plat-conversion'),
            controller: _conversion,
            onChanged: (_) => setState(() {}),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: TextesModaleRestaurant.etiquette,
            decoration: InputDecoration(
              isDense: true,
              border: const OutlineInputBorder(),
              errorText: _parChamp['unites_vendables'],
              errorMaxLines: 6,
            ),
          ),
          const SizedBox(height: AppSpacing.unit),
          const Text.rich(
            TextSpan(
              style: TextesModaleRestaurant.aide,
              children: [
                TextSpan(text: 'Un casier de 24 bouteilles ? Saisissez '),
                TextSpan(
                  text: '24',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(
                  text: ". Un bidon d'huile utilisé entier ? Saisissez ",
                ),
                TextSpan(
                  text: '1',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(text: '.'),
              ],
            ),
          ),
          ..._apercu(),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('lien-plat-annuler'),
          onPressed: _envoi ? null : () => Navigator.of(context).pop(false),
          child: const Text(
            TextesLienPlat.annuler,
            style: TextesModaleRestaurant.bouton,
          ),
        ),
        FilledButton(
          key: const Key('lien-plat-enregistrer'),
          onPressed: _envoi ? null : _enregistrer,
          child: const Text(
            TextesLienPlat.confirmer,
            style: TextesModaleRestaurant.bouton,
          ),
        ),
      ],
    );
  }

  /// L'aperçu — il n'apparaît que quand la saisie est exploitable : un aperçu
  /// bâti sur une valeur par défaut laisserait croire qu'un champ vide vaut
  /// « une pour une ». Trois états du stock, jamais deux : un chiffre, ou
  /// « non consulté » (pas de point cuisine).
  List<Widget> _apercu() {
    final unites = lireDixMilliemes(_conversion.text);
    final article = _articleId;
    if (article == null || unites == null || unites <= 0) return const [];

    final stock = _stockCentiemes;
    final lu = _stockLu && stock != null;
    final vendables = lu ? (stock * unites ~/ 1000000) : null;
    // `bcdiv('1', conversion, 4)` : 1 / conversion, tronqué au dix-millième.
    final decrement = 100000000 ~/ unites;
    final unite = ref
        .watch(articlesLiensProvider)
        .value
        ?.where((a) => a.id == article)
        .firstOrNull
        ?.uniteMesure;

    Widget ligne(Key cle, String nom, String valeur, {bool alerte = false}) =>
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(nom, style: TextesModaleRestaurant.sousTitre),
            Text(
              valeur,
              key: cle,
              style: TextesModaleRestaurant.sousTitre.copyWith(
                fontWeight: FontWeight.bold,
                color: alerte ? PaletteMaitre.ambre700 : AppColors.navy,
              ),
            ),
          ],
        );

    return [
      const SizedBox(height: AppSpacing.md),
      Container(
        key: const Key('lien-plat-apercu'),
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          border: Border.all(color: Ardoise.c200),
          borderRadius: BorderRadius.circular(AppRadius.roundedLg),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ligne(
              const Key('lien-plat-apercu-stock'),
              TextesLienPlat.apercuStock,
              lu
                  ? '${ecrireCentiemes(stock)} ${unite ?? ''}'.trim()
                  : TextesLienPlat.nonConsulte,
              alerte: !lu,
            ),
            ligne(
              const Key('lien-plat-apercu-vendables'),
              TextesLienPlat.apercuVendables,
              lu
                  ? '$vendables × ${widget.ligne.libelle}'
                  : TextesLienPlat.nonConsulte,
              alerte: !lu,
            ),
            const SizedBox(height: AppSpacing.unit),
            ligne(
              const Key('lien-plat-apercu-decrement'),
              TextesLienPlat.apercuDecrement,
              '${lisibleDixMilliemes(decrement)} ${unite ?? ''}'.trim(),
            ),
          ],
        ),
      ),
    ];
  }
}

/// Le prix du sous-titre, au format des cartes.
String prixLien(String brut) =>
    formaterMontantDecimal(brut, suffixe: 'FCFA') ?? '—';

/// L'étiquette d'un champ de la modale, étoile rouge comprise (`required`).
class EtiquetteLien extends StatelessWidget {
  const EtiquetteLien({super.key, required this.texte});

  final String texte;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
    child: Text.rich(
      TextSpan(
        style: TextesModaleRestaurant.etiquette,
        children: [
          TextSpan(text: '$texte '),
          const TextSpan(
            text: '*',
            style: TextStyle(color: PaletteMaitre.rouge600),
          ),
        ],
      ),
    ),
  );
}

class _DialogueDelier extends ConsumerStatefulWidget {
  const _DialogueDelier({required this.ligne});

  final LigneCarteRestaurant ligne;

  @override
  ConsumerState<_DialogueDelier> createState() => _DialogueDelierState();
}

class _DialogueDelierState extends ConsumerState<_DialogueDelier> {
  bool _envoi = false;
  String? _refus;

  Future<void> _confirmer() async {
    setState(() {
      _envoi = true;
      _refus = null;
    });
    final messager = ScaffoldMessenger.of(context);
    final navigateur = Navigator.of(context);
    final resultat = await ref
        .read(restaurantApiProvider)
        .delierDuStock(widget.ligne.id);
    if (!mounted) return;
    switch (resultat) {
      case RestaurantRecu<Plat>():
        invaliderRestaurant(ref);
        messager
          ..clearSnackBars()
          ..showSnackBar(
            const SnackBar(
              content: Text(
                MessagesRestaurant.lienRetire,
                key: Key('toast-delier-plat'),
              ),
            ),
          );
        navigateur.pop(true);
      case RestaurantRefuse<Plat>(:final motif):
        setState(() {
          _envoi = false;
          _refus = motif;
        });
      case RestaurantInjoignable<Plat>():
        setState(() => _envoi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CoquilleModaleRestaurant(
      cle: const Key('dialogue-delier-plat'),
      titre: TextesLienPlat.delierTitre,
      sousTitre: widget.ligne.libelle,
      largeur: AppLayout.modaleRetraitCarte,
      refus: _refus,
      cleRefus: const Key('delier-plat-refus'),
      corps: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            TextesLienPlat.delierMessage,
            style: TextesModaleRestaurant.corps,
          ),
          SizedBox(height: AppSpacing.xs),
          Text(TextesLienPlat.delierDetail, style: TextesModaleRestaurant.note),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('delier-plat-annuler'),
          onPressed: _envoi ? null : () => Navigator.of(context).pop(false),
          child: const Text(
            TextesLienPlat.annuler,
            style: TextesModaleRestaurant.bouton,
          ),
        ),
        FilledButton(
          key: const Key('delier-plat-confirmer'),
          onPressed: _envoi ? null : _confirmer,
          child: const Text(
            TextesLienPlat.delierConfirmer,
            style: TextesModaleRestaurant.bouton,
          ),
        ),
      ],
    );
  }
}
