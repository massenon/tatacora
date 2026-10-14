import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../data/achats_api.dart';
import '../../domain/decimal_texte.dart';
import '../../domain/entities/commande_achat.dart';
import '../../domain/entities/fournisseur.dart';
import '../../domain/messages_achats.dart';
import '../providers_achats.dart';
import 'coquille_modale_achats.dart';

/// La modale **« Nouveau bon de commande »** — `m7-approvisionnement.html`
/// l.543-615, ouverte par « Commander la sélection » (l.195-198).
///
/// ## Le fournisseur est une VRAIE clé étrangère
///
/// Le maître propose cinq raisons sociales **écrites en dur dans son
/// JavaScript** (l.555-556) et commente lui-même : *« Regroupement par
/// fournisseur habituel non disponible dans le prototype : on demande le
/// fournisseur plutôt que d'en inventer un. »* Ici, la liste vient de
/// `GET /achats/fournisseurs` — `commandes_achat.fournisseur_id` est une
/// relation, et le texte libre casserait silencieusement le rapprochement à
/// trois voies (EF-M7-04), qui suppose une relation exacte.
///
/// Quand le référentiel est **injoignable**, la modale refuse de s'ouvrir sur
/// un sélecteur vide : « on ne sait pas » n'est pas « aucun fournisseur
/// enregistré », et les confondre ferait chercher un fournisseur au bureau
/// alors que c'est la liaison qui est tombée.
///
/// ## Le prix unitaire est SAISI, jamais pré-rempli au coût moyen pondéré
///
/// Le maître pré-remplit `l.article.prix_achat` (l.606). **Aucune colonne
/// `prix_achat` n'existe** au référentiel serveur : la seule valeur voisine est
/// `cout_moyen_pondere`, et ce n'est pas la même chose. Le CMP est la moyenne
/// de ce qu'on a **déjà** payé ; le prix unitaire d'une commande est ce que le
/// fournisseur demande **aujourd'hui**.
///
/// Les confondre ferait passer une moyenne d'achats passés pour un tarif
/// négocié : le CMP est donc affiché **à côté**, nommé pour ce qu'il est, et le
/// champ reste à remplir. (Jusqu'au 12/10/2026 ce raisonnement invoquait une
/// « boucle » : la réception aurait valorisé l'entrée au prix de la commande.
/// Elle ne valorise rien, comme au serveur — D132 —, et la boucle n'existe
/// pas ; la raison de ne pas pré-remplir reste l'absence de colonne
/// `prix_achat` au référentiel de la vue.)
///
/// ## Trois statuts du maître sont REFUSÉS à la création
///
/// `receptionnee`, `receptionnee_partiellement` et `cloturee` sont produits par
/// une réception qui a réellement généré ses entrées de stock. Le maître les
/// offre au formulaire (`m7-achats.html` l.277) ; les accepter permettrait
/// d'afficher une commande « Reçue » dont aucune marchandise n'est entrée en
/// stock — un indicateur qui affirme un état qu'il n'a pas vérifié
/// (PA-59/60/61). Le refus est **visible**, pas un champ silencieusement
/// tronqué.
Future<CommandeAchatDetail?> ouvrirModaleCommande(
  BuildContext context, {
  required List<LigneSaisieCommande> selection,
}) {
  return showDialog<CommandeAchatDetail>(
    context: context,
    builder: (_) => _ModaleCommande(selection: selection),
  );
}

class _ModaleCommande extends ConsumerStatefulWidget {
  const _ModaleCommande({required this.selection});

  final List<LigneSaisieCommande> selection;

  @override
  ConsumerState<_ModaleCommande> createState() => _ModaleCommandeState();
}

class _ModaleCommandeState extends ConsumerState<_ModaleCommande> {
  late List<LigneSaisieCommande> _lignes;
  late final List<TextEditingController> _prix;
  late final List<TextEditingController> _quantites;

  String? _fournisseurId;
  StatutCommande _statut = StatutCommande.brouillon;
  late DateTime _date;

  bool _envoiEnCours = false;
  String? _refus;
  Map<String, String> _erreursServeur = const {};

  @override
  void initState() {
    super.initState();
    _lignes = List.of(widget.selection);
    _date = DateTime.now();
    _quantites = [
      for (final l in _lignes) TextEditingController(text: l.quantite),
    ];
    _prix = [
      for (final l in _lignes) TextEditingController(text: l.prixUnitaire),
    ];
  }

  @override
  void dispose() {
    for (final c in _quantites) {
      c.dispose();
    }
    for (final c in _prix) {
      c.dispose();
    }
    super.dispose();
  }

  SaisieCommande get _saisie => SaisieCommande(
    fournisseurId: _fournisseurId ?? '',
    dateCommande: _iso(_date),
    statut: _statut,
    lignes: _lignes,
  );

  void _majLigne(int index, {String? quantite, String? prixUnitaire}) {
    setState(() {
      _lignes[index] = _lignes[index].copyWith(
        quantite: quantite,
        prixUnitaire: prixUnitaire,
      );
    });
  }

  /// Le motif de refus AVANT tout envoi, ou `null`.
  ///
  /// Ces contrôles doublent ceux du serveur **délibérément** : le serveur
  /// refuse le lot entier après un aller-retour, et le message qui revient
  /// désigne un index de ligne (`lignes.3.article_id`) que l'utilisateur ne
  /// peut pas relier à ce qu'il voit. Ici, le refus nomme l'article.
  String? get _erreurLocale {
    if (_fournisseurId == null) {
      return 'Choisissez un fournisseur. Une commande sans fournisseur n’a '
          'personne à qui être adressée, et le rapprochement à trois voies '
          'suppose une relation exacte.';
    }
    if (_lignes.isEmpty) {
      return 'Une commande d’achat porte au moins une ligne : une commande '
          'vide n’a rien à réceptionner et fausserait le rapprochement.';
    }

    final double = _saisie.erreurArticlesEnDouble;
    if (double != null) return double;

    for (final l in _lignes) {
      if (!estStrictementPositif(l.quantite)) {
        return 'La quantité de « ${l.libelle} » doit être strictement '
            'positive, avec au plus deux décimales. Une saisie à zéro n’est '
            'pas une ligne de commande : la réception ne pourrait jamais la '
            'satisfaire.';
      }
      if (!estStrictementPositif(l.prixUnitaire)) {
        // La phrase de la PWA (`achats_pwa.appro.prix_obligatoire`) : strictement
        // positif. Une entrée de stock valorisée à zéro abaisserait le coût
        // moyen pondéré en silence.
        return '${MessagesAchats.prixObligatoire} (« ${l.libelle} », au plus '
            'deux décimales).';
      }
    }
    return null;
  }

  Future<void> _creer() async {
    final erreur = _erreurLocale;
    if (erreur != null) {
      setState(() => _refus = erreur);
      return;
    }

    setState(() {
      _envoiEnCours = true;
      _refus = null;
      _erreursServeur = const {};
    });

    final resultat = await ref.read(achatsApiProvider).creerCommande(_saisie);
    if (!mounted) return;

    switch (resultat) {
      case AchatsRecu(:final donnees):
        Navigator.of(context).pop(donnees);
      case AchatsRefuse(:final motif, :final erreurs):
        setState(() {
          _envoiEnCours = false;
          _refus = motif;
          _erreursServeur = erreurs;
        });
      case AchatsInjoignable():
        setState(() {
          _envoiEnCours = false;
          // Jamais produite (la base est locale) ; le type la garde.
          _refus =
              'La base du poste n’a pas répondu : rien n’a été enregistré.';
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final fournisseurs = ref.watch(tousLesFournisseursProvider);
    final total = _saisie.montantTotal;

    return CoquilleModaleAchats(
      cle: const Key('modale-commande'),
      titre: 'Nouveau bon de commande',
      // Le sous-titre du maître (l.565) : nombre d'articles et total.
      sousTitre:
          '${_lignes.length} article(s) — ${total ?? 'total incalculable'}',
      libelleValidation: 'Créer le bon de commande',
      cleValidation: const Key('commande-valider'),
      envoiEnCours: _envoiEnCours,
      onValider: _creer,
      refus: _refus,
      cleRefus: const Key('commande-refus'),
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          fournisseurs.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => _NoteChamp(
              cle: const Key('commande-fournisseurs-erreur'),
              texte: '$e',
            ),
            data: (liste) => liste == null
                ? const _NoteChamp(
                    cle: Key('commande-fournisseurs-injoignables'),
                    texte:
                        'Le référentiel fournisseurs n’a pas pu être consulté. '
                        'Aucun sélecteur n’est proposé : une liste vide se '
                        'lirait comme « aucun fournisseur enregistré », et le '
                        'fournisseur d’une commande est une vraie clé '
                        'étrangère — il ne se tape pas.',
                  )
                : _SelecteurFournisseur(
                    fournisseurs: liste,
                    valeur: _fournisseurId,
                    erreur: _erreursServeur['fournisseur_id'],
                    onChoix: (id) => setState(() => _fournisseurId = id),
                  ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _ChampDate(
            date: _date,
            erreur: _erreursServeur['date_commande'],
            onChoix: (d) => setState(() => _date = d),
          ),
          const SizedBox(height: AppSpacing.sm),
          _SelecteurStatut(
            valeur: _statut,
            erreur: _erreursServeur['statut'],
            onChoix: (s) => setState(() => _statut = s),
          ),
          const SizedBox(height: AppSpacing.sm),
          _TableLignes(
            lignes: _lignes,
            quantites: _quantites,
            prix: _prix,
            onQuantite: (i, v) => _majLigne(i, quantite: v),
            onPrix: (i, v) => _majLigne(i, prixUnitaire: v),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text('Total', style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(width: AppSpacing.xs),
              Text(
                // Le total est CALCULÉ, ligne à ligne, en chaînes. Le maître le
                // pose aussi en champ de formulaire (« Montant estimé »,
                // `m7-achats.html` l.276) : `CreerCommandeAchatRequest` le
                // REFUSE (PA-24), il n'est donc jamais soumis.
                total ?? 'incalculable',
                key: const Key('commande-total'),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(color: AppColors.navy),
              ),
            ],
          ),
          // Le pavé « Écarts assumés avec le prototype » qui suivait est
          // RETIRÉ (directive absolue du PO, 14/10/2026 : aucune note de
          // conception à l'écran). Ses quatre écarts restent tenus par le
          // code : statuts de réception refusés à la création, montant
          // calculé des lignes, prix non pré-rempli, article unique.
        ],
      ),
    );
  }

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

class _SelecteurFournisseur extends StatelessWidget {
  const _SelecteurFournisseur({
    required this.fournisseurs,
    required this.valeur,
    required this.erreur,
    required this.onChoix,
  });

  final List<Fournisseur> fournisseurs;
  final String? valeur;
  final String? erreur;
  final ValueChanged<String?> onChoix;

  @override
  Widget build(BuildContext context) {
    if (fournisseurs.isEmpty) {
      return const _NoteChamp(
        cle: Key('commande-fournisseurs-vides'),
        texte:
            'Le référentiel fournisseurs est vide. Enregistrez d’abord un '
            'fournisseur depuis l’écran Fournisseurs : la commande le référence '
            'par une clé étrangère, elle ne peut pas en inventer un.',
      );
    }

    return DropdownButtonFormField<String>(
      key: const Key('commande-fournisseur'),
      initialValue: valeur,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Fournisseur',
        border: const OutlineInputBorder(),
        errorText: erreur,
      ),
      items: [
        for (final f in fournisseurs)
          DropdownMenuItem(value: f.id, child: Text(f.raisonSociale)),
      ],
      onChanged: onChoix,
    );
  }
}

class _ChampDate extends StatelessWidget {
  const _ChampDate({
    required this.date,
    required this.erreur,
    required this.onChoix,
  });

  final DateTime date;
  final String? erreur;
  final ValueChanged<DateTime> onChoix;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: 'Date de commande',
        border: const OutlineInputBorder(),
        errorText: erreur,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('${date.year}-${_d(date.month)}-${_d(date.day)}'),
          TextButton(
            key: const Key('commande-choisir-date'),
            onPressed: () async {
              final choisie = await showDatePicker(
                context: context,
                initialDate: date,
                firstDate: DateTime(date.year - 2),
                lastDate: DateTime(date.year + 2),
              );
              if (choisie != null) onChoix(choisie);
            },
            child: const Text('Changer'),
          ),
        ],
      ),
    );
  }

  static String _d(int n) => n.toString().padLeft(2, '0');
}

class _SelecteurStatut extends StatelessWidget {
  const _SelecteurStatut({
    required this.valeur,
    required this.erreur,
    required this.onChoix,
  });

  final StatutCommande valeur;
  final String? erreur;
  final ValueChanged<StatutCommande> onChoix;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<StatutCommande>(
      key: const Key('commande-statut'),
      initialValue: valeur,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Statut',
        helperText:
            'Brouillon ou Envoyée seulement — voir le bloc des écarts pour '
            'les trois autres.',
        helperMaxLines: 2,
        border: const OutlineInputBorder(),
        errorText: erreur,
      ),
      items: [
        for (final s in StatutCommande.saisissables)
          DropdownMenuItem(value: s, child: Text(s.libelle)),
      ],
      onChanged: (s) => s == null ? null : onChoix(s),
    );
  }
}

/// Le tableau de la modale — `m7-approvisionnement.html` l.572-588 : Article,
/// Qté, P.U., Montant.
class _TableLignes extends StatelessWidget {
  const _TableLignes({
    required this.lignes,
    required this.quantites,
    required this.prix,
    required this.onQuantite,
    required this.onPrix,
  });

  final List<LigneSaisieCommande> lignes;
  final List<TextEditingController> quantites;
  final List<TextEditingController> prix;
  final void Function(int, String) onQuantite;
  final void Function(int, String) onPrix;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Article')),
          DataColumn(label: Text('Qté'), numeric: true),
          DataColumn(label: Text('P.U.'), numeric: true),
          DataColumn(label: Text('Montant'), numeric: true),
        ],
        rows: [
          for (final (i, l) in lignes.indexed)
            // Pas de clé sur la `DataRow` : elle n'atteint pas l'arbre de
            // widgets (piège 10). Elle est posée sur la cellule de libellé.
            DataRow(
              cells: [
                DataCell(
                  Text(
                    l.libelle,
                    key: Key('commande-ligne-${l.articleId}'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                DataCell(
                  SizedBox(
                    width: AppLayout.champQuantiteAchats,
                    child: TextField(
                      key: Key('commande-qte-${l.articleId}'),
                      controller: quantites[i],
                      textAlign: TextAlign.right,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        border: const OutlineInputBorder(),
                        suffixText: l.uniteMesure,
                      ),
                      onChanged: (v) => onQuantite(i, v),
                    ),
                  ),
                ),
                DataCell(
                  SizedBox(
                    width: AppLayout.champQuantiteAchats,
                    child: TextField(
                      key: Key('commande-pu-${l.articleId}'),
                      controller: prix[i],
                      textAlign: TextAlign.right,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => onPrix(i, v),
                    ),
                  ),
                ),
                DataCell(
                  Text(
                    // `null` s'affiche « — » : un montant absent n'est pas un
                    // montant nul, et afficher « 0 » sous une saisie en cours
                    // ferait croire à une ligne gratuite.
                    l.montant ?? '—',
                    key: Key('commande-montant-${l.articleId}'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _NoteChamp extends StatelessWidget {
  const _NoteChamp({required Key cle, required this.texte}) : super(key: cle);

  final String texte;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.erreurFondLeger,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.erreurBordure),
      ),
      child: Text(texte, style: Theme.of(context).textTheme.labelMedium),
    );
  }
}
