// Vue Blade maîtresse (PA-183) : pwa/achats/approvisionnement.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../stocks/domain/entities/etat_stock.dart';
import '../../../stocks/presentation/providers_stocks.dart';
import '../../data/achats_api.dart';
import '../../domain/entities/bon_reception.dart';
import '../../domain/entities/commande_achat.dart';
import '../../domain/messages_achats.dart';
import '../providers_achats.dart';
import 'coquille_modale_achats.dart';

/// La modale **« Réception »** — `m7-approvisionnement.html` l.617-687.
///
/// Trois colonnes de contexte et une seule saisie, exactement comme le maître :
/// Commandé, Déjà reçu, Reçu maintenant. Le reste à recevoir est proposé par
/// défaut.
///
/// ## Le « déjà reçu » n'est pas décoratif
///
/// Sans lui, une seconde réception repartirait de la quantité commandée entière
/// et ferait entrer la marchandise **deux fois** en stock. Sur ce poste il est
/// la SOMME des lignes des bons déjà enregistrés
/// (`lignes_bon_reception_local`), jamais reconstitué des mouvements de stock
/// comme au serveur (PA-39) : `recuReconstitue` vaut `false` et l'avertissement
/// correspondant ne s'affiche pas.
///
/// ## Le point de stockage est une vraie clé étrangère
///
/// Le maître envoie un libellé (`point_stockage: 'Bar'`, l.680) parce que son
/// moteur travaille en `localStorage`. La liste vient des points de M6
/// (`points_stockage_local`) ; sans point, la modale le dit
/// ([MessagesAchats.aucunPoint]).
///
/// ## La tolérance de RG-10 n'est pas ici, et son absence dit quoi faire
///
/// La réception refuse de calculer une conformité tant que
/// `tolerance_reception_pct` n'est pas renseigné dans les Paramètres de ce
/// poste — même discipline que le taux d'IS (PA-19) : une tolérance devinée
/// ferait accepter ou refuser des livraisons sur un critère arbitraire. Le
/// refus (`ToleranceNonConfiguree`) est distinct d'un refus de saisie : le
/// magasinier ne peut rien corriger dans son formulaire, et l'écran l'envoie
/// vers l'écran Paramètres au lieu de lui montrer une erreur brute.
Future<BonReception?> ouvrirModaleReception(
  BuildContext context, {
  required CommandeAchat commande,
}) {
  return showDialog<BonReception>(
    context: context,
    builder: (_) => _ModaleReception(commande: commande),
  );
}

class _ModaleReception extends ConsumerStatefulWidget {
  const _ModaleReception({required this.commande});

  final CommandeAchat commande;

  @override
  ConsumerState<_ModaleReception> createState() => _ModaleReceptionState();
}

class _ModaleReceptionState extends ConsumerState<_ModaleReception> {
  /// Les quantités saisies, par article. Vides tant que le détail n'est pas
  /// arrivé : le reste à recevoir est **calculé par le serveur**, et le poser
  /// avant ne servirait qu'à afficher un chiffre qu'on ne connaît pas encore.
  final Map<String, TextEditingController> _quantites = {};
  final Map<String, String> _saisies = {};

  String? _pointId;
  bool _prerempli = false;

  bool _envoiEnCours = false;
  String? _refus;
  String? _toleranceAbsente;
  Map<String, String> _erreursServeur = const {};

  @override
  void dispose() {
    for (final c in _quantites.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Pré-remplit les champs **une fois le détail reçu**.
  ///
  /// Piège 6 — un défaut de SÉQUENCE de rendu ne se voit pas à la relecture :
  /// pré-remplir pendant la construction, avant que le détail ne soit là,
  /// poserait des champs vides que rien ne remplirait ensuite, et le magasinier
  /// ressaisirait tout à la main sans savoir pourquoi.
  void _preremplir(CommandeAchatDetail detail) {
    if (_prerempli) return;
    _prerempli = true;

    for (final l in detail.lignes) {
      _saisies[l.articleId] = l.resteARecevoir;
      _quantites[l.articleId] = TextEditingController(text: l.resteARecevoir);
    }
  }

  SaisieReception _saisie(CommandeAchatDetail detail) => SaisieReception(
    commandeId: widget.commande.id,
    pointStockageId: _pointId ?? '',
    // `null` : le DAO date du jour, par SON horloge (injectable en test). Le
    // maître ne demande pas de date non plus (l.630-634) : une date saisie ici
    // pourrait situer l'entrée de stock n'importe où.
    dateReception: null,
    lignes: [
      for (final l in detail.lignes)
        LigneSaisieReception(
          articleId: l.articleId,
          libelle: l.libelleArticle,
          uniteMesure: l.uniteMesure ?? '',
          quantiteCommandee: l.quantiteCommandee,
          quantiteDejaRecue: l.quantiteRecue,
          quantiteRecue: _saisies[l.articleId] ?? '',
        ),
    ],
  );

  Future<void> _valider(CommandeAchatDetail detail) async {
    if (_pointId == null) {
      setState(() {
        _refus =
            'Choisissez un point de stockage : c’est lui qui reçoit l’entrée '
            'de stock générée par la réception. Sans lui, la marchandise '
            'n’est imputée nulle part.';
      });
      return;
    }

    final saisie = _saisie(detail);
    final erreur = saisie.erreur;
    if (erreur != null) {
      setState(() => _refus = erreur);
      return;
    }

    setState(() {
      _envoiEnCours = true;
      _refus = null;
      _toleranceAbsente = null;
      _erreursServeur = const {};
    });

    final resultat = await ref.read(achatsApiProvider).receptionner(saisie);
    if (!mounted) return;

    switch (resultat) {
      case ReceptionEnregistree(:final bon):
        Navigator.of(context).pop(bon);
      case ToleranceNonConfiguree(:final message):
        setState(() {
          _envoiEnCours = false;
          _toleranceAbsente = message;
        });
      case ReceptionRefusee(:final motif, :final erreurs):
        setState(() {
          _envoiEnCours = false;
          _refus = motif;
          _erreursServeur = erreurs;
        });
      case ReceptionInjoignable():
        setState(() {
          _envoiEnCours = false;
          // Jamais produite (la base est locale) ; le type la garde.
          _refus =
              'La base du poste n’a pas répondu : rien n’a été enregistré, '
              'ni le bon ni l’entrée de stock.';
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(detailCommandeProvider(widget.commande.id));

    return CoquilleModaleAchats(
      cle: const Key('modale-reception'),
      // Le titre du maître (l.627) porte le numéro de la commande. Il n'en
      // existe pas : `commandes_achat` n'a aucune séquence, seulement un UUID —
      // et fabriquer un « CMD-0001 » à l'affichage donnerait un numéro qui
      // changerait au prochain tri.
      titre: 'Réception de la commande',
      sousTitre:
          '${widget.commande.fournisseurRaisonSociale} — commandé le '
          '${widget.commande.dateCommande}',
      libelleValidation: 'Valider la réception',
      cleValidation: const Key('reception-valider'),
      envoiEnCours: _envoiEnCours,
      onValider: () async {
        final d = detail.value;
        if (d is AchatsRecu<CommandeAchatDetail>) await _valider(d.donnees);
      },
      refus: _refus,
      cleRefus: const Key('reception-refus'),
      avertissement: _toleranceAbsente == null
          ? null
          : _PaveTolerance(message: _toleranceAbsente!),
      corps: detail.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Text('$e', key: const Key('reception-erreur')),
        data: (r) => switch (r) {
          AchatsRecu(:final donnees) => _corps(donnees),
          AchatsRefuse(:final motif) => Text(
            motif,
            key: const Key('reception-detail-refus'),
          ),
          // Jamais produite (la base est locale) ; le type la garde.
          AchatsInjoignable() => const Text(
            'Le détail de la commande n’a pas pu être consulté. Sans les '
            'quantités déjà reçues, une seconde réception repartirait de la '
            'quantité commandée entière et ferait entrer la marchandise deux '
            'fois en stock : la saisie est refusée.',
            key: Key('reception-detail-hors-ligne'),
          ),
        },
      ),
    );
  }

  Widget _corps(CommandeAchatDetail detail) {
    _preremplir(detail);
    final points = ref.watch(pointsStockProvider).value ?? const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _SelecteurPoint(
          points: points,
          valeur: _pointId,
          erreur: _erreursServeur['point_stockage_id'],
          onChoix: (id) => setState(() => _pointId = id),
        ),
        const SizedBox(height: AppSpacing.sm),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Article')),
              DataColumn(label: Text('Commandé'), numeric: true),
              DataColumn(label: Text('Déjà reçu'), numeric: true),
              DataColumn(label: Text('Reçu maintenant'), numeric: true),
            ],
            rows: [
              for (final l in detail.lignes)
                DataRow(
                  cells: [
                    DataCell(
                      Text(
                        l.libelleArticle,
                        key: Key('reception-ligne-${l.articleId}'),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    // Les chiffres du serveur, tels quels.
                    DataCell(
                      Text('${l.quantiteCommandee} ${l.uniteMesure ?? ''}'),
                    ),
                    DataCell(Text(l.quantiteRecue)),
                    DataCell(
                      SizedBox(
                        width: AppLayout.champQuantiteAchats,
                        child: TextField(
                          key: Key('reception-qte-${l.articleId}'),
                          controller: _quantites[l.articleId],
                          textAlign: TextAlign.right,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (v) =>
                              setState(() => _saisies[l.articleId] = v),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        // L'aide de la vue : c'est elle qui empêche la double-saisie que §M7
        // interdit. ÉCART NOMMÉ (D276) — la vue dit, dans la modale de réception
        // de la vue d'approvisionnement (`appro.form_avertissement_double`) :
        // « La réception génère l'entrée de stock et met à jour le coût moyen pondéré au prix de cette commande. Ne saisissez pas le stock une seconde fois dans l'écran Stocks : la quantité serait comptée deux fois. »
        // La première moitié est FAUSSE : le serveur exécuté ne met à jour aucun
        // coût (D265/D266). Phrase VRAIE affichée ; la seconde moitié de la vue
        // (la double-saisie) est conservée au mot ; vue à faire corriger par
        // l'Architecte (ticket D276). Cette citation intégrale est un gain de
        // MESURE, jamais un rendu : la phrase fausse n'est pas à l'écran.
        Container(
          key: const Key('reception-aide'),
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.neutre100,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Text(
            "La réception génère l'entrée de stock ; le coût moyen pondéré "
            "n'est pas recalculé à la réception. Ne saisissez pas le stock une "
            "seconde fois dans l'écran Stocks : la quantité serait comptée deux "
            'fois.',
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
        if (detail.recuReconstitue) ...[
          const SizedBox(height: AppSpacing.sm),
          const PaveAvertissementAchats(
            cle: Key('reception-recu-reconstitue'),
            titre: 'Le « déjà reçu » est reconstitué',
            corps:
                // Code interne retiré du texte affiché (directive du PO,
                // 14/10/2026) : la raison est PA-39.
                'Les quantités déjà reçues sont relues des mouvements de stock '
                'dont le motif nomme le bon. C’est fonctionnel et fragile — une '
                'entrée saisie à la main avec un motif ressemblant serait '
                'comptée comme une réception. Vérifiez le bon papier en cas '
                'de doute.',
          ),
        ],
      ],
    );
  }
}

class _SelecteurPoint extends StatelessWidget {
  const _SelecteurPoint({
    required this.points,
    required this.valeur,
    required this.erreur,
    required this.onChoix,
  });

  final List<PointStockage> points;
  final String? valeur;
  final String? erreur;
  final ValueChanged<String?> onChoix;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return Container(
        key: const Key('reception-points-vides'),
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.erreurFondLeger,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.erreurBordure),
        ),
        child: Text(
          // La phrase de la PWA (`achats_pwa.appro.aucun_point`), au mot.
          MessagesAchats.aucunPoint,
          style: Theme.of(context).textTheme.labelMedium,
        ),
      );
    }

    return DropdownButtonFormField<String>(
      key: const Key('reception-point'),
      initialValue: valeur,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Point de stockage',
        border: const OutlineInputBorder(),
        errorText: erreur,
      ),
      items: [
        for (final p in points)
          DropdownMenuItem(value: p.id, child: Text(p.libelle)),
      ],
      onChanged: onChoix,
    );
  }
}

/// Le refus de RG-10 quand la tolérance n'est pas configurée — il dit QUOI
/// FAIRE, pas seulement qu'il refuse.
class _PaveTolerance extends StatelessWidget {
  const _PaveTolerance({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;

    return Container(
      key: const Key('reception-tolerance-absente'),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.reserveGoldFond,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.gold),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Votre saisie est juste — c’est un paramètre qui manque',
            style: textes.labelMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          // Le message du serveur, tel quel : il nomme la clé et dit qui doit
          // la renseigner.
          Text(message, style: textes.labelMedium),
          const SizedBox(height: AppSpacing.unit),
          Text(
            'Un Administrateur doit renseigner la tolérance de réception dans '
            'Paramètres. Elle n’a volontairement aucune valeur par défaut : une '
            'tolérance devinée ferait accepter ou refuser des livraisons sur un '
            'critère arbitraire, et personne ne la rouvrirait.',
            style: textes.labelMedium,
          ),
        ],
      ),
    );
  }
}
