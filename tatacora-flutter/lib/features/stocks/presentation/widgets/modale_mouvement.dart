// Vue Blade maîtresse (PA-183) : pwa/stocks/stocks.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/format/formats.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../data/stocks_api.dart';
import '../../domain/entities/etat_stock.dart';
import '../../domain/entities/mouvement_stock.dart';
import '../../domain/messages_stock.dart';
import '../../domain/nombre_saisi.dart';
import '../providers_stocks.dart';
import 'coquille_modale_stock.dart';
import 'journal_mouvements.dart';
import 'modale_point.dart';

/// La modale **« Mouvement de stock »** — la vue Blade
/// `pwa/stocks/stocks.blade.php` (`etatFormulaire === 'mouvement'`), bouton
/// « Mouvement » de chaque ligne.
///
/// ## RG-06 : la rupture est une CONFIRMATION, pas une erreur
///
/// `StocksApi.enregistrerMouvement` rend [RuptureAConfirmer] quand le
/// disponible DU POINT ne couvre pas la sortie. Ce n'est pas un refus
/// définitif : c'est une décision de gestion qu'un utilisateur habilité peut
/// assumer, et le forçage laisse alors une trace nominative (qui, quand, le
/// drapeau « rupture forcée » sur le mouvement, relu par le journal et la
/// fiche). La traiter comme une erreur empêcherait de servir un client au
/// comptoir en attendant une régularisation ; l'accepter sans demander
/// produirait des stocks négatifs que personne n'aurait décidés.
///
/// ## Quatre points à retenir
///
/// 1. **Le point de stockage est une vraie clé étrangère**, proposé par défaut
///    au rattachement de l'article (vue l.617) : c'est là que la marchandise
///    arrive le plus souvent, et un défaut faux se valide sans se lire.
/// 2. **Le coût unitaire n'est PAS pré-rempli.** La vue le pré-remplit avec le
///    coût moyen pondéré (`mvtCout = cmp`) ; ici il reste vide, écart conservé
///    des livraisons précédentes : une réception saisie sans y penser
///    reconduirait l'ancien coût et le CMP ne bougerait jamais, alors que
///    c'est exactement ce qu'une entrée valorisée doit faire. Vide = simple
///    transfert, qui ne revalorise rien.
/// 3. **Aucune modale ne s'ouvre pour un article « journalier »** : l'écran
///    Stocks affiche la phrase de la vue (l.380-383), et `StocksDao` refuse de
///    toute façon — l'ouverture d'une fenêtre ne protège rien.
/// 4. **« Nouveau point de stockage »** est un AJOUT à la vue (voir
///    `modale_point.dart`) : sans lui, ce poste n'aurait aucun point à
///    proposer, et aucun mouvement ne pourrait jamais être saisi.
Future<MouvementStock?> ouvrirModaleMouvement(
  BuildContext context, {
  required LigneStock article,
}) {
  return showDialog<MouvementStock>(
    context: context,
    builder: (_) => _ModaleMouvement(article: article),
  );
}

class _ModaleMouvement extends ConsumerStatefulWidget {
  const _ModaleMouvement({required this.article});

  final LigneStock article;

  @override
  ConsumerState<_ModaleMouvement> createState() => _ModaleMouvementState();
}

class _ModaleMouvementState extends ConsumerState<_ModaleMouvement> {
  final _formulaire = GlobalKey<FormState>();
  final _quantite = TextEditingController();
  final _cout = TextEditingController();
  final _motif = TextEditingController();

  TypeMouvement _type = TypeMouvement.entree;
  String? _pointId;

  bool _envoiEnCours = false;
  String? _refus;
  Map<String, String> _erreursServeur = const {};

  @override
  void dispose() {
    _quantite.dispose();
    _cout.dispose();
    _motif.dispose();
    super.dispose();
  }

  SaisieMouvement? _saisie() {
    if (!(_formulaire.currentState?.validate() ?? false)) return null;

    final point = _pointId;
    if (point == null) {
      setState(
        () => _refus =
            'Choisissez un point de stockage : un mouvement qui ne dit pas où '
            'la marchandise entre ou sort ne peut être rapproché de rien.',
      );
      return null;
    }

    return SaisieMouvement(
      articleId: widget.article.id,
      pointId: point,
      type: _type,
      quantite: normaliserNombre(_quantite.text),
      motif: _motif.text.trim(),
      // Envoyé uniquement sur une entrée : le serveur pose
      // `prohibited_unless:type_mouvement,entree`, et l'envoyer ailleurs ferait
      // refuser un mouvement par ailleurs valide.
      coutUnitaire:
          _type == TypeMouvement.entree && _cout.text.trim().isNotEmpty
          ? normaliserNombre(_cout.text)
          : null,
    );
  }

  Future<void> _enregistrer() async {
    final saisie = _saisie();
    if (saisie == null) return;
    await _envoyer(saisie);
  }

  Future<void> _envoyer(SaisieMouvement saisie) async {
    setState(() {
      _envoiEnCours = true;
      _refus = null;
      _erreursServeur = const {};
    });

    final resultat = await ref
        .read(stocksApiProvider)
        .enregistrerMouvement(saisie);

    if (!mounted) return;

    switch (resultat) {
      case MouvementEnregistre(:final mouvement):
        Navigator.of(context).pop(mouvement);

      case RuptureAConfirmer():
        setState(() => _envoiEnCours = false);
        final force = await _demanderForcage(resultat);
        if (!mounted || !force) return;
        // Le MÊME objet de saisie, seulement marqué comme forcé : le
        // reconstruire depuis les champs rejouerait la lecture du formulaire,
        // qui a pu changer pendant que la confirmation était affichée.
        await _envoyer(saisie.forcee());

      case MouvementRefuse(:final motif, :final erreurs):
        setState(() {
          _envoiEnCours = false;
          _refus = motif;
          _erreursServeur = erreurs;
        });

      case MouvementInjoignable():
        // Jamais produit : une base locale n'est pas hors connexion. L'arm
        // reste parce que le type scellé est partagé.
        setState(() => _envoiEnCours = false);
    }
  }

  /// La confirmation de RG-06, aux mots du maître (l.428-433).
  Future<bool> _demanderForcage(RuptureAConfirmer rupture) async {
    final accepte = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('mouvement-rupture'),
        title: const Text('Stock insuffisant'),
        content: SizedBox(
          width: AppLayout.modaleStock,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Le message du SERVEUR, tel quel : il porte les deux chiffres
              // qu'il a comparés, et les réécrire ici en produirait un
              // troisième.
              Text(rupture.message),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Disponible : ${rupture.stockDisponible} · '
                'Demandé : ${rupture.quantiteDemandee}',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Forcer la sortie créera un stock négatif, tracé comme '
                '« rupture forcée » dans la fiche de stock.',
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: AppColors.erreur),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            key: const Key('rupture-annuler'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            key: const Key('rupture-forcer'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Forcer la sortie'),
          ),
        ],
      ),
    );
    return accepte ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final points = ref.watch(pointsStockProvider).value ?? const [];
    // Le défaut, décidé une fois la liste connue (voir le champ plus bas).
    if (_pointId == null && points.isNotEmpty) {
      final rattache = widget.article.pointStockageId;
      _pointId = points.any((p) => p.id == rattache)
          ? rattache
          : points.first.id;
    }

    return CoquilleModaleStock(
      cle: const Key('modale-mouvement'),
      titre: 'Mouvement de stock',
      sousTitre: widget.article.libelle,
      libelleValidation: 'Enregistrer',
      cleValidation: const Key('mouvement-enregistrer'),
      envoiEnCours: _envoiEnCours,
      onValider: _enregistrer,
      refus: _refus,
      cleRefus: const Key('mouvement-refus'),
      corps: Form(
        key: _formulaire,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _Contexte(article: widget.article),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<TypeMouvement>(
              key: const Key('mouvement-type'),
              initialValue: _type,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Type de mouvement',
                border: const OutlineInputBorder(),
                errorText: _erreursServeur['type_mouvement'],
              ),
              items: [
                // Les TROIS types saisissables, jamais les quatre du schéma :
                // une régularisation d'inventaire naît d'un comptage clôturé,
                // et l'ouvrir à la saisie libre permettrait de réécrire
                // n'importe quel solde sans qu'aucun comptage n'ait eu lieu.
                for (final t in TypeMouvement.saisissables)
                  DropdownMenuItem(value: t, child: Text(t.libelleSaisie!)),
              ],
              onChanged: (t) => setState(() => _type = t ?? _type),
            ),
            const SizedBox(height: AppSpacing.sm),
            // Le point proposé : celui de rattachement de l'article, sinon le
            // premier par ordre alphabétique (vue l.617-619). Décidé UNE fois,
            // dès que la liste est lue, et jamais écrasé ensuite.
            KeyedSubtree(
              key: const Key('mouvement-point'),
              child: DropdownButtonFormField<String>(
                // La clé suit la valeur : `initialValue` ne se relit pas, et un
                // point proposé après la lecture de la liste — ou créé à
                // l'instant — doit apparaître sélectionné.
                key: ValueKey('mouvement-point-${_pointId ?? 'aucun'}'),
                initialValue: _pointId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Point de stockage',
                  border: const OutlineInputBorder(),
                  errorText: _erreursServeur['point_id'],
                ),
                items: [
                  for (final p in points)
                    DropdownMenuItem(value: p.id, child: Text(p.libelle)),
                ],
                onChanged: (p) => setState(() => _pointId = p),
                validator: (v) =>
                    v == null ? 'Le point de stockage est obligatoire.' : null,
              ),
            ),
            if (points.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  // Une liste vide DIT pourquoi et dit quoi faire.
                  "Aucun point de stockage n'est défini : un mouvement ne peut être imputé nulle part. Créez-en un avant de saisir une entrée.",
                  key: const Key('mouvement-sans-point'),
                  style: Theme.of(
                    context,
                  ).textTheme.labelMedium?.copyWith(color: AppColors.erreur),
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const Key('mouvement-nouveau-point'),
                onPressed: () async {
                  final cree = await ouvrirModalePoint(context);
                  if (cree != null) setState(() => _pointId = cree.id);
                },
                child: const Text('Nouveau point de stockage'),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              key: const Key('mouvement-quantite'),
              controller: _quantite,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Quantité (${widget.article.uniteMesure})',
                border: const OutlineInputBorder(),
                errorText: _erreursServeur['quantite'],
              ),
              // `strictementPositif` : `gt:0` côté serveur. Une quantité à zéro
              // n'est pas un mouvement, c'est une saisie inachevée — même
              // distinction que `QuantiteSaisie` au panier (PA-98).
              validator: (v) => erreurNombre(v ?? '', strictementPositif: true),
            ),
            // Le maître masque le bloc hors « entrée » (l.406). Ici il est
            // RETIRÉ, pas masqué : un champ caché mais toujours monté garderait
            // sa valeur, et un basculement entrée -> sortie -> entrée
            // réenverrait un coût que l'utilisateur croyait avoir abandonné.
            if (_type == TypeMouvement.entree) ...[
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                key: const Key('mouvement-cout'),
                controller: _cout,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: "Coût d'achat unitaire (FCFA)",
                  // L'aide du maître, au mot (l.400).
                  helperText:
                      'Recalcule le coût moyen pondéré. Laisser vide pour un simple transfert entre points : déplacer une marchandise ne change pas son coût.',
                  helperMaxLines: 3,
                  border: const OutlineInputBorder(),
                  errorText: _erreursServeur['cout_unitaire'],
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? null
                    : erreurNombre(
                        v,
                        strictementPositif: false,
                        quatreDecimales: true,
                      ),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              key: const Key('mouvement-motif'),
              controller: _motif,
              decoration: InputDecoration(
                labelText: 'Motif',
                // Le placeholder du maître, au mot (l.402).
                hintText: 'Ex. Réception SODIS Bénin',
                helperText: MessagesStock.motifObligatoire,
                helperMaxLines: 3,
                border: const OutlineInputBorder(),
                errorText: _erreursServeur['motif'],
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Le motif est obligatoire.'
                  : null,
            ),
            const SizedBox(height: AppSpacing.sm),
            JournalMouvements(articleId: widget.article.id),
          ],
        ),
      ),
    );
  }
}

/// Le bandeau de contexte du maître (l.386-390) : stock actuel et coût moyen
/// pondéré, **en lecture seule**, tels que le serveur les a calculés.
class _Contexte extends StatelessWidget {
  const _Contexte({required this.article});

  final LigneStock article;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('mouvement-contexte'),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.neutre100,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.neutre200),
      ),
      child: Column(
        children: [
          _ligne(
            context,
            'Stock actuel',
            '${article.stock} ${article.uniteMesure}',
          ),
          _ligne(
            context,
            'CMP',
            article.cmpInconnu
                ? '—'
                : (formaterMontantDecimal(
                        article.coutMoyenPondere,
                        suffixe: 'FCFA',
                      ) ??
                      article.coutMoyenPondere),
          ),
          // La portée, que le maître n'a pas : « 12 » ne veut rien dire tant
          // qu'on ignore si c'est au bar ou tous points confondus, et servir
          // au comptoir une bouteille qui est en réserve est l'erreur que
          // cette ligne existe pour empêcher.
          _ligne(context, 'Portée du calcul', article.portee),
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
