// Vue Blade maîtresse (PA-183) : pwa/stocks/stocks.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/format/formats.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../restaurant/presentation/widgets/textes_modale_restaurant.dart';
import '../../data/stocks_api.dart';
import '../../domain/entities/etat_stock.dart';
import '../../domain/entities/mouvement_stock.dart';
import '../../domain/messages_stock.dart';
import '../../domain/nombre_saisi.dart';
import '../providers_stocks.dart';
import 'coquille_modale_stock.dart';
import 'modale_point.dart';

/// La modale **« Nouvel article » / « Modifier l'article »** — la vue Blade
/// `pwa/stocks/stocks.blade.php` (`etatFormulaire === 'article'`), bouton
/// « + Nouvel article » et bouton de ligne « Modifier ».
///
/// ## Le stock ne se saisit toujours pas — il ENTRE
///
/// « Stock d'ouverture » et « Valeur d'achat unitaire » sont rendus depuis le
/// 09/10/2026, et c'est la source locale qui les permet : ils ne sont pas des
/// champs de l'article, ils composent une ENTRÉE (`SaisieArticle.stockOuverture`
/// et `valeurAchat`), écrite avec l'article dans une seule transaction. Le
/// stock reste la somme des mouvements ; le coût moyen pondéré se recalcule
/// depuis l'entrée. Aucune colonne ne reçoit ces deux chiffres.
///
/// Jusqu'au 08/10/2026 cette modale NOMMAIT quatre champs refusés (stock
/// d'ouverture, valeur d'achat, point, mode de suivi) en disant qu'une route
/// serveur les interdisait ou qu'aucune colonne n'existait. Les quatre motifs
/// ont cessé d'être vrais (PA-144) — le panneau est retiré, pas laissé à
/// vieillir.
///
/// ## Les paragraphes d'aide de la vue sont RENDUS (21/10/2026)
///
/// Le formulaire « compact, libellés seuls » du 14/10/2026 est dépassé par
/// l'ordre du Product Owner du 21/10/2026 (« tout doit être au complet ») : les
/// cinq aides (`point_aide`, `suivi_aide`, `valeur_achat_aide`, `seuil_aide`,
/// `stock_ouverture_aide`) sont sous leur champ, `text-[11px] text-slate-400
/// mt-1`. Elles portent les règles qui empêchent une saisie fausse (« sans
/// elle, l'article entre au bilan pour zéro »).
///
/// ## L'entrée depuis la fiche (vue l.588-620) est RENDUE
///
/// En MODIFICATION, pour un administrateur (`StocksApi.peutAjusterLeStock`) et
/// un article suivi en stock : « Faire entrer du stock » — quantité, point qui
/// reçoit, coût unitaire. Ce n'est PAS un champ « stock » : c'est un
/// MOUVEMENT d'entrée (motif « Entrée depuis la fiche article »), posé après
/// l'enregistrement de la fiche, daté, signé, visible en fiche de stock et
/// synchronisé comme tout mouvement saisi. Quantité vide : la fiche s'enregistre
/// sans toucher au stock. Le coût vide ne valorise rien.
///
/// ## Les écarts avec la vue, nommés
///
///  * **« Valeur d'achat » en modification** est en lecture seule, comme dans
///    la vue : elle est posée par l'entrée, seul geste qui l'établit.
///  * **`seuil_reappro`** n'est pas rendu : la vue ne le porte pas, et personne
///    n'écrirait la colonne (M7 la fera naître avec son auteur).
Future<ArticleEnregistre?> ouvrirModaleArticle(
  BuildContext context, {
  LigneStock? article,
  List<String> categoriesConnues = const [],
}) {
  return showDialog<ArticleEnregistre>(
    context: context,
    builder: (_) =>
        _ModaleArticle(article: article, categoriesConnues: categoriesConnues),
  );
}

class _ModaleArticle extends ConsumerStatefulWidget {
  const _ModaleArticle({
    required this.article,
    required this.categoriesConnues,
  });

  /// `null` en création. En modification, la ligne **déjà calculée** : son
  /// stock, son coût moyen pondéré et sa valorisation sont affichés en lecture
  /// seule sans nouveau calcul — les refaire donnerait deux chiffres sur le
  /// même écran si un mouvement survenait entre les deux.
  final LigneStock? article;

  final List<String> categoriesConnues;

  @override
  ConsumerState<_ModaleArticle> createState() => _ModaleArticleState();
}

class _ModaleArticleState extends ConsumerState<_ModaleArticle> {
  final _formulaire = GlobalKey<FormState>();
  final _libelle = TextEditingController();
  final _seuil = TextEditingController();
  final _valeurAchat = TextEditingController();
  final _stockOuverture = TextEditingController();
  final _entreeQuantite = TextEditingController();
  final _entreeCout = TextEditingController();

  String? _categorie;
  late String _unite;
  late SuiviArticle _suivi;
  String? _pointId;

  /// Le point CHOISI pour recevoir l'entrée de la fiche (voir
  /// [_pointQuiRecoit] pour les défauts) — un défaut faux se valide sans se
  /// lire, mais une liste sans défaut oblige à un clic que l'on oublie.
  String? _entreePointId;

  /// Le point qui reçoit l'entrée : le choix posé, à défaut le rattachement de
  /// l'article, à défaut le premier point par libellé (`Stocks::editerArticle`,
  /// l.369). `null` : le poste n'a AUCUN point — l'entrée est alors refusée.
  String? _pointQuiRecoit(List<PointStockage> points) =>
      _entreePointId ?? (points.isEmpty ? null : points.first.id);

  /// La clé du champ « Point », pour lui imposer la valeur d'un point qu'on
  /// vient de créer : `initialValue` ne se relit pas après le premier rendu.
  final _cleChampPoint = GlobalKey<FormFieldState<String?>>();

  /// L'UUID est posé **une fois**, à l'ouverture, et ne change pas entre deux
  /// tentatives d'enregistrement : un second envoi est refusé (identifiant déjà
  /// utilisé) au lieu de créer un doublon au référentiel.
  late final String _id;

  bool _envoiEnCours = false;
  String? _refus;
  Map<String, String> _erreurs = const {};

  bool get _modification => widget.article != null;

  @override
  void initState() {
    super.initState();
    final a = widget.article;
    _id = a?.id ?? const Uuid().v4();
    _libelle.text = a?.libelle ?? '';
    _seuil.text = a?.seuilAlerte ?? '0';
    // À la création, la première catégorie du maître (la vue fait de même) ; en
    // modification, celle de l'article — y compris « aucune » : la remplacer
    // par la première de la liste écraserait une donnée que personne n'a voulu
    // changer.
    _categorie = a == null ? categoriesMaitre.first : a.categorie;
    _unite = a?.uniteMesure ?? unitesMaitre[2];
    _suivi = a?.suivi ?? SuiviArticle.permanent;
    _pointId = a?.pointStockageId;
    _entreePointId = a?.pointStockageId;
  }

  @override
  void dispose() {
    _libelle.dispose();
    _seuil.dispose();
    _valeurAchat.dispose();
    _stockOuverture.dispose();
    _entreeQuantite.dispose();
    _entreeCout.dispose();
    super.dispose();
  }

  /// Les catégories du maître, plus celles réellement saisies.
  ///
  /// Sans cette union, rouvrir la fiche d'un article dont la catégorie a été
  /// créée ailleurs la remplacerait **en silence** par la première de la
  /// liste — une modification qui écrase une donnée que personne n'a voulu
  /// changer.
  List<String> get _categories {
    final vues = {
      ...categoriesMaitre,
      ...widget.categoriesConnues,
      if (widget.article?.categorie != null) widget.article!.categorie!,
    };
    return vues.toList();
  }

  /// `$articleId !== null && $peutAjusterLeStock && $suiviSaisi !== 'journalier'`
  /// (vue l.588) : le bloc « Faire entrer du stock » n'est rendu qu'en
  /// modification, pour un administrateur, sur un article suivi en stock —
  /// retiré sinon, jamais grisé.
  bool get _entreeOfferte =>
      _modification &&
      ref.read(stocksApiProvider).peutAjusterLeStock &&
      _suivi != SuiviArticle.journalier;

  Future<void> _enregistrer() async {
    if (!(_formulaire.currentState?.validate() ?? false)) return;

    // L'entrée de la fiche : vide, la fiche s'enregistre sans toucher au stock.
    final quantiteEntree = _entreeOfferte ? _entreeQuantite.text.trim() : '';
    final pointEntree = _pointQuiRecoit(
      ref.read(pointsStockProvider).value ?? const [],
    );
    if (quantiteEntree.isNotEmpty && pointEntree == null) {
      // `entree_point_requis`, dit AVANT d'écrire quoi que ce soit : la vue
      // enregistre d'abord la fiche puis refuse l'entrée, ce qui laisse une
      // fiche modifiée sous un message d'erreur. Ici, rien n'est écrit.
      setState(() => _refus = MessagesStock.entreePointRequis);
      return;
    }

    setState(() {
      _envoiEnCours = true;
      _refus = null;
      _erreurs = const {};
    });

    final resultat = await ref
        .read(stocksApiProvider)
        .enregistrerArticle(
          SaisieArticle(
            id: _id,
            libelle: _libelle.text.trim(),
            categorie: _categorie,
            uniteMesure: _unite,
            seuilAlerte: _suivi == SuiviArticle.journalier
                ? '0'
                : normaliserNombre(_seuil.text),
            suivi: _suivi,
            pointStockageId: _pointId,
            stockOuverture: normaliserNombre(_stockOuverture.text),
            valeurAchat: normaliserNombre(_valeurAchat.text),
          ),
          modification: _modification,
        );

    if (!mounted) return;

    switch (resultat) {
      case ArticleEnregistre():
        if (quantiteEntree.isEmpty) {
          Navigator.of(context).pop(resultat);
          return;
        }
        await _faireEntrer(resultat, quantiteEntree, pointEntree!);
      case ArticleRefuse(:final motif, :final erreurs):
        setState(() {
          _envoiEnCours = false;
          _refus = motif;
          _erreurs = erreurs;
        });
      case ArticleInjoignable():
        // Jamais produit : une base locale n'est pas hors connexion. L'arm
        // reste parce que le type scellé est partagé.
        setState(() => _envoiEnCours = false);
    }
  }

  /// Après la fiche, l'ENTRÉE (`Stocks::faireEntrerLeStock`) : un mouvement
  /// daté et signé, jamais une valeur de stock. Un refus de l'entrée laisse la
  /// modale ouverte ET dit que la fiche, elle, est enregistrée.
  Future<void> _faireEntrer(
    ArticleEnregistre fiche,
    String quantite,
    String pointId,
  ) async {
    final cout = _entreeCout.text.trim();
    final issue = await ref
        .read(stocksApiProvider)
        .faireEntrerDepuisFiche(
          articleId: fiche.id,
          pointId: pointId,
          quantite: normaliserNombre(quantite),
          // `null` reste `null` : sans coût saisi, l'entrée ne valorise rien.
          coutUnitaire: cout.isEmpty ? null : normaliserNombre(cout),
        );
    if (!mounted) return;

    switch (issue) {
      case MouvementEnregistre():
        Navigator.of(context).pop(
          ArticleEnregistre(
            id: fiche.id,
            libelle: fiche.libelle,
            messageEntree: MessagesStock.entreeEnregistree(
              quantite: quantite,
              unite: widget.article!.uniteMesure,
              libelle: fiche.libelle,
            ),
          ),
        );
      case MouvementRefuse(:final motif, :final erreurs):
        setState(() {
          _envoiEnCours = false;
          _refus = '$motif La fiche est enregistrée ; l’entrée, non.';
          _erreurs = erreurs;
        });
      case RuptureAConfirmer() || MouvementInjoignable():
        // Une entrée n'est jamais en rupture ; une base locale n'est pas hors
        // connexion. Les arms restent parce que le type scellé est partagé.
        setState(() => _envoiEnCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.article;
    final points = ref.watch(pointsStockProvider).value ?? const [];
    final journalier = _suivi == SuiviArticle.journalier;

    return CoquilleModaleStock(
      cle: const Key('modale-article'),
      titre: _modification ? "Modifier l'article" : 'Nouvel article',
      // Le sous-titre de la vue — il porte la règle de tout l'écran.
      sousTitre: _modification
          ? a!.libelle
          : 'Le stock se constitue par mouvements, jamais par saisie directe.',
      libelleValidation: _modification ? 'Enregistrer' : "Créer l'article",
      cleValidation: const Key('article-enregistrer'),
      envoiEnCours: _envoiEnCours,
      onValider: _enregistrer,
      refus: _refus,
      cleRefus: const Key('article-refus'),
      corps: Form(
        key: _formulaire,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Formulaire COMPACT (demande du PO du 14/10/2026) : l'étiquette
            // AU-DESSUS du champ (`block text-[11px] font-semibold
            // text-slate-500 mb-1`, vue l.472) et le champ `px-3 py-2.5`, au
            // lieu de l'étiquette flottante Material de 56 px.
            const _Etiquette("Nom de l'article"),
            TextFormField(
              key: const Key('article-libelle'),
              controller: _libelle,
              autofocus: true,
              style: _styleChamp,
              decoration: _decoration(
                invite: 'Ex. Riz local (sac 50 kg)',
                erreur: _erreurs['libelle'],
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? "Le libellé de l'article est obligatoire."
                  : null,
            ),
            const SizedBox(height: AppSpacing.sm),
            const _Etiquette('Catégorie'),
            DropdownButtonFormField<String?>(
              key: const Key('article-categorie'),
              initialValue: _categorie,
              isExpanded: true,
              style: _styleChamp,
              decoration: _decoration(erreur: _erreurs['categorie']),
              items: [
                // `null` reste offert : `articles.categorie` est facultative, et
                // forcer une catégorie en inventerait une.
                const DropdownMenuItem<String?>(child: Text('Sans catégorie')),
                for (final c in _categories)
                  DropdownMenuItem<String?>(value: c, child: Text(c)),
              ],
              onChanged: (c) => setState(() => _categorie = c),
            ),
            const SizedBox(height: AppSpacing.sm),
            const _Etiquette('Unité de mesure'),
            DropdownButtonFormField<String>(
              key: const Key('article-unite'),
              initialValue: _unite,
              isExpanded: true,
              style: _styleChamp,
              decoration: _decoration(erreur: _erreurs['unite_mesure']),
              items: [
                for (final u in {..._uniteEtCellesDuMaitre})
                  DropdownMenuItem(value: u, child: Text(u)),
              ],
              onChanged: (u) => setState(() => _unite = u ?? _unite),
            ),
            const SizedBox(height: AppSpacing.sm),
            _ChampPoint(
              points: points,
              valeur: _pointId,
              modification: _modification,
              erreur: _erreurs['point_stockage_id'],
              onChanged: (p) => setState(() => _pointId = p),
              cleChamp: _cleChampPoint,
              onCreer: () async {
                final cree = await ouvrirModalePoint(context);
                if (cree == null) return;
                setState(() => _pointId = cree.id);
                _cleChampPoint.currentState?.didChange(cree.id);
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            const _Etiquette('Mode de suivi'),
            DropdownButtonFormField<SuiviArticle>(
              key: const Key('article-suivi'),
              initialValue: _suivi,
              isExpanded: true,
              style: _styleChamp,
              decoration: _decoration(),
              items: const [
                DropdownMenuItem(
                  value: SuiviArticle.permanent,
                  child: Text(
                    'Gros stock — suivi permanent (sacs, cartons, viandes…)',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                DropdownMenuItem(
                  value: SuiviArticle.journalier,
                  child: Text(
                    'Petit stock — acheté au jour le jour (tomates, laitue…)',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              onChanged: (s) => setState(() => _suivi = s ?? _suivi),
            ),
            const _Aide(_aideSuivi),
            if (!_modification && !journalier) ...[
              const SizedBox(height: AppSpacing.sm),
              // L'encadré ambre de la vue autour de la valeur d'achat.
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: PaletteMaitre.ambre50,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: PaletteMaitre.ambre200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const _Etiquette("Valeur d'achat unitaire (FCFA)"),
                    TextFormField(
                      key: const Key('article-valeur-achat'),
                      controller: _valeurAchat,
                      style: _styleChamp,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: _decoration(
                        invite: 'Ex. 32000',
                        erreur: _erreurs['valeur_achat'],
                        fond: AppColors.neutre0,
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? null
                          : erreurNombre(
                              v,
                              strictementPositif: false,
                              quatreDecimales: true,
                            ),
                    ),
                    const _Aide(_aideValeurAchat),
                  ],
                ),
              ),
            ],
            if (!journalier) ...[
              const SizedBox(height: AppSpacing.sm),
              const _Etiquette("Seuil d'alerte"),
              TextFormField(
                key: const Key('article-seuil'),
                controller: _seuil,
                style: _styleChamp,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: _decoration(erreur: _erreurs['seuil_alerte']),
                validator: (v) =>
                    erreurNombre(v ?? '', strictementPositif: false),
              ),
              const _Aide(_aideSeuil),
              if (!_modification) ...[
                const SizedBox(height: AppSpacing.sm),
                const _Etiquette("Stock d'ouverture"),
                TextFormField(
                  key: const Key('article-stock-ouverture'),
                  controller: _stockOuverture,
                  style: _styleChamp,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: _decoration(erreur: _erreurs['stock_ouverture']),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? null
                      : erreurNombre(v, strictementPositif: false),
                ),
                const _Aide(_aideStockOuverture),
              ],
            ],
            if (_entreeOfferte) ...[
              const SizedBox(height: AppSpacing.sm),
              _BlocEntree(
                points: points,
                pointId: _pointQuiRecoit(points),
                quantite: _entreeQuantite,
                cout: _entreeCout,
                erreurs: _erreurs,
                onPoint: (p) => setState(() => _entreePointId = p),
              ),
            ],
            if (_modification) ...[
              const SizedBox(height: AppSpacing.sm),
              _BlocCalcule(article: a!),
            ],
          ],
        ),
      ),
    );
  }

  /// L'unité courante d'abord, puis celles du maître.
  ///
  /// Une unité déjà portée par l'article et absente de la liste du maître doit
  /// rester sélectionnée : sans elle, `initialValue` ne correspondrait à aucun
  /// élément et Flutter lèverait — ou pire, la modification écraserait
  /// silencieusement l'unité au premier enregistrement.
  Iterable<String> get _uniteEtCellesDuMaitre sync* {
    yield _unite;
    yield* unitesMaitre;
  }
}

/// Les aides de la vue (`stocks_pwa.article.*_aide`), UNE fois chacune. Elles
/// disent la règle que le champ porte — celle qui empêche une saisie fausse.
const String _aideSuivi =
    "Le petit stock n'est ni décrémenté à la vente, ni inventorié, ni alerté : "
    "seule la dépense d'achat est constatée.";
// Les aides qui suivent tiennent sur UNE ligne de littéral : la mesure de
// conformité recolle deux littéraux de MÊME guillemet, pas un double puis un
// simple.
const String _aideValeurAchat =
    "Elle valorise le stock d'ouverture et fixe le premier coût moyen pondéré. Sans elle, l'article entre au bilan pour zéro et la variation de stock — donc le résultat — est fausse.";
const String _aideSeuil =
    "Un paramètre, pas un état : il déclenche l'alerte de sous-stock.";
const String _aideStockOuverture =
    "Enregistré comme un MOUVEMENT d'entrée, pas comme une colonne : c'est ce qui le rend visible en fiche de stock.";
const String _aidePoint =
    "Point de rattachement principal de l'article, et point d'imputation de son stock d'ouverture. Il ne limite pas le stock : un article peut être détenu en plusieurs endroits, et le total se calcule point par point.";

/// `text-[11px] text-slate-400 mt-1` — le paragraphe d'aide sous un champ.
class _Aide extends StatelessWidget {
  const _Aide(this.texte);

  final String texte;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.unit), // mt-1
      child: Text(texte, style: TextesModaleRestaurant.aide),
    );
  }
}

/// `rounded-lg bg-emerald-50 border border-emerald-200 p-3` — « Faire entrer du
/// stock » (vue l.588-620) : quantité, point qui reçoit, coût unitaire, et la
/// phrase qui dit que c'est une ENTRÉE, jamais une valeur de stock.
class _BlocEntree extends StatelessWidget {
  const _BlocEntree({
    required this.points,
    required this.pointId,
    required this.quantite,
    required this.cout,
    required this.erreurs,
    required this.onPoint,
  });

  final List<PointStockage> points;
  final String? pointId;
  final TextEditingController quantite;
  final TextEditingController cout;
  final Map<String, String> erreurs;
  final ValueChanged<String?> onPoint;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('article-bloc-entree'),
      padding: const EdgeInsets.all(AppSpacing.sm), // p-3
      decoration: BoxDecoration(
        color: PaletteMaitre.emeraude50,
        borderRadius: BorderRadius.circular(AppRadius.roundedLg),
        border: Border.all(color: PaletteMaitre.emeraude200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // `text-[11px] font-semibold text-slate-600 mb-2`.
          const Padding(
            padding: EdgeInsets.only(bottom: AppSpacing.xs),
            child: Text(
              'Faire entrer du stock',
              style: TextStyle(
                fontFamily: AppTextStyles.police,
                fontSize: Tailles.t11,
                fontWeight: FontWeight.w600,
                color: Ardoise.c600,
              ),
            ),
          ),
          // `grid grid-cols-1 sm:grid-cols-2 gap-3`.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _Etiquette('Quantité à faire entrer'),
                    TextFormField(
                      key: const Key('article-entree-quantite'),
                      controller: quantite,
                      style: _styleChamp,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: _decoration(erreur: erreurs['quantite']),
                      // `gt:0` : une quantité à zéro n'est pas une entrée.
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? null
                          : erreurNombre(v, strictementPositif: true),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _Etiquette('Point de stockage qui reçoit'),
                    DropdownButtonFormField<String?>(
                      key: const Key('article-entree-point'),
                      initialValue: points.any((p) => p.id == pointId)
                          ? pointId
                          : null,
                      isExpanded: true,
                      style: _styleChamp,
                      decoration: _decoration(),
                      items: [
                        for (final p in points)
                          DropdownMenuItem<String?>(
                            value: p.id,
                            child: Text(p.libelle),
                          ),
                      ],
                      onChanged: onPoint,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm), // mt-3
          const _Etiquette('Coût unitaire de cette entrée (FCFA)'),
          TextFormField(
            key: const Key('article-entree-cout'),
            controller: cout,
            style: _styleChamp,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: _decoration(erreur: erreurs['cout_unitaire']),
            validator: (v) => (v == null || v.trim().isEmpty)
                ? null
                : erreurNombre(
                    v,
                    strictementPositif: false,
                    quatreDecimales: true,
                  ),
          ),
          // `text-[11px] text-slate-500 mt-2`.
          const Padding(
            padding: EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              'Ajoute au stock, sans jamais l’écraser : l’entrée est enregistrée '
              'comme un mouvement daté et signé, visible en fiche article. '
              'Laissez la quantité vide pour enregistrer la fiche sans toucher '
              'au stock. Sans coût unitaire, l’entrée ne valorise rien — zéro '
              'se lirait « reçu gratuitement » et fausserait le coût moyen '
              'pondéré.',
              key: Key('article-entree-aide'),
              style: TextStyle(
                fontFamily: AppTextStyles.police,
                fontSize: Tailles.t11,
                color: Ardoise.c500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// `text-[13px]` d'un champ de modale (hors `<main>` : 13 px).
const TextStyle _styleChamp = TextStyle(
  fontFamily: AppTextStyles.police,
  fontSize: Tailles.t13,
  color: Ardoise.c800,
);

/// Le champ compact de la vue : `w-full text-[13px] border border-slate-300
/// rounded-lg px-3 py-2.5 focus:border-[var(--gold)]`.
InputDecoration _decoration({String? invite, String? erreur, Color? fond}) {
  final bord = OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadius.roundedLg),
    borderSide: const BorderSide(color: Ardoise.c300),
  );
  return InputDecoration(
    hintText: invite,
    errorText: erreur,
    errorMaxLines: 3,
    isDense: true,
    filled: fond != null,
    fillColor: fond,
    contentPadding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.sm,
      vertical: AppSpacing.xsPlus,
    ),
    border: bord,
    enabledBorder: bord,
    focusedBorder: bord.copyWith(
      borderSide: const BorderSide(color: AppColors.gold),
    ),
  );
}

/// L'étiquette AU-DESSUS du champ : `block text-[11px] font-semibold
/// text-slate-500 mb-1` (vue l.472).
class _Etiquette extends StatelessWidget {
  const _Etiquette(this.texte);

  final String texte;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.unit),
      child: Text(
        texte,
        style: const TextStyle(
          fontFamily: AppTextStyles.police,
          fontSize: Tailles.t11,
          fontWeight: FontWeight.w600,
          color: Ardoise.c500,
        ),
      ),
    );
  }
}

/// Le point de stockage — la vue le rend en création COMME en modification
/// (l.503-515). À la création il est OBLIGATOIRE (`pointOuverture` requis,
/// `Stocks::enregistrerArticle`) : il rattache l'article et reçoit son stock
/// d'ouverture. En modification, « — » reste offert : un article jamais
/// rattaché doit pouvoir le rester.
class _ChampPoint extends StatelessWidget {
  const _ChampPoint({
    required this.points,
    required this.valeur,
    required this.modification,
    required this.erreur,
    required this.onChanged,
    required this.onCreer,
    required this.cleChamp,
  });

  final List<PointStockage> points;
  final String? valeur;
  final bool modification;
  final String? erreur;
  final ValueChanged<String?> onChanged;
  final Future<void> Function() onCreer;
  final GlobalKey<FormFieldState<String?>> cleChamp;

  @override
  Widget build(BuildContext context) {
    final libelle = Theme.of(context).textTheme.labelMedium;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Etiquette('Point de stockage'),
        KeyedSubtree(
          key: const Key('article-point'),
          child: DropdownButtonFormField<String?>(
            key: cleChamp,
            initialValue: points.any((p) => p.id == valeur) ? valeur : null,
            isExpanded: true,
            style: _styleChamp,
            // L'aide de la vue (`point_aide`) est rendue sous le champ.
            decoration: _decoration(erreur: erreur),
            items: [
              if (modification)
                const DropdownMenuItem<String?>(child: Text('—')),
              for (final p in points)
                DropdownMenuItem<String?>(value: p.id, child: Text(p.libelle)),
            ],
            onChanged: onChanged,
            validator: (v) => (!modification && v == null)
                ? 'Choisissez le point de stockage : il rattache l’article et '
                      'reçoit son stock d’ouverture.'
                : null,
          ),
        ),
        const _Aide(_aidePoint),
        if (points.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              // Une liste vide DIT pourquoi et dit quoi faire.
              "Aucun point de stockage n'est défini : un mouvement ne peut être imputé nulle part. Créez-en un avant de saisir une entrée.",
              key: const Key('article-sans-point'),
              style: libelle?.copyWith(color: AppColors.erreur),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const Key('article-nouveau-point'),
            onPressed: onCreer,
            child: const Text('Nouveau point de stockage'),
          ),
        ),
      ],
    );
  }
}

/// Le bloc **en lecture seule** de la modification — vue l.622-641.
///
/// Les chiffres calculés, **tels quels**, et les deux phrases de la vue qui
/// disent où on les corrige. Sans elles, quelqu'un chercherait le champ
/// pendant dix minutes avant de conclure que l'écran est cassé.
class _BlocCalcule extends StatelessWidget {
  const _BlocCalcule({required this.article});

  final LigneStock article;

  @override
  Widget build(BuildContext context) {
    final fin = Theme.of(context).textTheme.labelMedium;

    return Container(
      key: const Key('article-bloc-calcule'),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.neutre100,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.neutre200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ligne(
            context,
            "Valeur d'achat (dernière entrée)",
            article.prixAchat == null
                ? 'aucune entrée valorisée'
                : (formaterMontantDecimal(article.prixAchat, suffixe: 'FCFA') ??
                      article.prixAchat!),
          ),
          _ligne(
            context,
            'Stock actuel (calculé)',
            article.estJournalier
                ? 'non suivi'
                : '${article.stock} ${article.uniteMesure}',
          ),
          _ligne(
            context,
            'Coût moyen pondéré',
            article.cmpInconnu
                ? '—'
                : (formaterMontantDecimal(
                        article.coutMoyenPondere,
                        suffixe: 'FCFA',
                      ) ??
                      article.coutMoyenPondere),
          ),
          _ligne(
            context,
            'Valeur du stock',
            (article.estJournalier || article.valeurInconnue)
                ? '—'
                : formaterFcfa(int.parse(article.valeurStock)),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            "Elle est posée par l'entrée de stock, seul geste qui l'établit. La corriger ici réécrirait un prix d'achat après coup, sans réception pour l'appuyer.",
            style: fin,
          ),
          const SizedBox(height: AppSpacing.unit),
          Text(
            'Le stock ne se modifie pas ici : il se corrige par un mouvement ou un inventaire, qui en conserve la raison.',
            style: fin,
          ),
        ],
      ),
    );
  }

  Widget _ligne(BuildContext context, String libelle, String valeur) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.unit),
    // `Flexible` des deux côtés : une modale de 512 px ne doit pas déborder
    // quand le libellé ou la valeur s'allonge (police de remplacement, valeur
    // « aucune entrée valorisée »).
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(libelle, style: Theme.of(context).textTheme.labelMedium),
        ),
        const SizedBox(width: AppSpacing.xs),
        Flexible(
          child: Text(
            valeur,
            textAlign: TextAlign.end,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}
