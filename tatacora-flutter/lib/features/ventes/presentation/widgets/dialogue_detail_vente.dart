// Vue Blade maîtresse (PA-183) : pwa/pos/historique-ventes.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart' show droitsProvider;
import '../../../../core/format/formats.dart';
import '../../../../core/rbac/garde_acces.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../shared_widgets/tableau_tatacora.dart';
import '../../../../shared_widgets/toast_export.dart';
import '../../../pos/domain/messages_ventes.dart' show RefusVente;
import '../../domain/entities/vente.dart';
import '../../impression/etat_journal_ventes.dart';
import '../providers_ventes.dart';

/// La modale « Détail » — `prototype_v2/pages/historique-ventes.html`
/// l.268-320.
///
/// ## Ce qu'elle rend, et ce qu'elle ne rend pas
///
/// Rendus : l'en-tête (référence, date, poste, table), les lignes avec leur
/// activité, le total précédé du règlement, l'encadré ambre « Porté en note »,
/// l'encadré rouge des articles sans lien au stock, l'encadré d'annulation, le
/// champ « Motif de l'annulation » avec « Annuler la vente », et les boutons du
/// pied dont « Ticket 80 mm ».
///
/// **L'annulation d'une vente encaissée est portée** (21/10/2026, ordre du PO :
/// « tout doit être au complet ») : `PanierDao.annulerVente` contre-passe la
/// pièce, la vente reste au journal marquée annulée, et l'annulation part au
/// serveur, qui compense les sorties de stock. L'encadré des articles sans lien
/// au stock lit le catalogue d'AUJOURD'HUI (`stock_non_impacte` du serveur est
/// écrit à la vente) — écart nommé à `CatalogueDao.referencesSansLienDeStock`.
///
/// ## Le maître n'a AUCUNE hauteur maximale, et il n'en faut pas non plus ici
///
/// `style="max-width:520px"` (l.272) ne borne que la largeur : chez lui, la
/// boîte grandit et la page défile derrière elle. `Dialog` borne déjà la
/// hauteur à celle de l'écran moins ses marges — poser un `maxHeight` par
/// dessus serait un jeton qui ne garde rien, et un commentaire qui affirme une
/// garantie qu'il ne tient pas est le piège n° 8 de ce dépôt.
///
/// **Ce qui garde réellement**, c'est le `Flexible` autour du corps défilant :
/// une addition de trente lignes rendue dans un `Column` non borné déborde, et
/// le pied disparaît **avec les trois boutons**. C'est le piège n° 7 — une
/// borne ne se teste que sur un contenu plus grand qu'elle, et le cas qui la
/// mesure remplit donc la modale jusqu'à déborder, sur un écran court.
class DialogueDetailVente extends ConsumerWidget {
  const DialogueDetailVente({required this.vente, super.key});

  final Vente vente;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dialog(
      backgroundColor: AppColors.neutre0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppLayout.modaleVente),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _EnTete(vente: vente),
            const Divider(height: 1, color: AppColors.neutre200),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: _Corps(vente: vente),
              ),
            ),
            const Divider(height: 1, color: AppColors.neutre200),
            _Pied(vente: vente),
          ],
        ),
      ),
    );
  }
}

class _EnTete extends StatelessWidget {
  const _EnTete({required this.vente});

  final Vente vente;

  @override
  Widget build(BuildContext context) {
    // `${date} · ${point_vente} ${table ? '· ' + table : ''}` du maître
    // (l.277-280). Sur une vente de séjour, ni poste ni table n'existent : le
    // client prend leur place, parce que c'est la seule chose qui dit où la
    // consommation a été servie.
    final situation = [
      formaterDate(vente.date),
      vente.pointVente ?? vente.clientNom ?? '—',
      if (vente.tableLibelle != null) vente.tableLibelle!,
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  key: const Key('vente-detail-reference'),
                  vente.referenceLocale,
                  style: const TextStyle(
                    fontFamily: AppTextStyles.policeMonospace,
                    fontSize: Tailles.t14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.navy,
                  ),
                ),
                Text(
                  situation,
                  style: const TextStyle(
                    fontFamily: AppTextStyles.police,
                    fontSize: Tailles.t11,
                    color: AppColors.neutre500,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: const Key('vente-detail-fermer-croix'),
            tooltip: 'Fermer',
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

class _Corps extends StatelessWidget {
  const _Corps({required this.vente});

  final Vente vente;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final ligne in vente.lignes) _Ligne(ligne: ligne),
        const SizedBox(height: AppSpacing.xs),
        const Divider(height: 1, color: AppColors.neutre300),
        const SizedBox(height: AppSpacing.xs),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text(
                // `Total · ${mode.libelle}` du maître (l.294). Le règlement est
                // collé au total parce que le total ne dit pas tout : porté en
                // note, il n'est pas dans le tiroir.
                'Total · ${vente.mode?.libelle ?? 'règlement non renseigné'}',
                style: const TextStyle(
                  fontFamily: AppTextStyles.police,
                  fontSize: Tailles.t13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.anthracite,
                ),
              ),
            ),
            Text(
              key: const Key('vente-detail-total'),
              formaterFcfa(vente.montant),
              style: const TextStyle(
                fontFamily: AppTextStyles.policeMonospace,
                fontSize: Tailles.t17,
                fontWeight: FontWeight.bold,
                color: AppColors.navy,
              ),
            ),
          ],
        ),
        if (!vente.montantFige) ...[
          const SizedBox(height: AppSpacing.sm),
          const _Encadre(
            cle: Key('vente-detail-montant-non-fige'),
            texte:
                'Ce montant est la somme des lignes : aucun montant n’a été '
                'arrêté à la clôture. C’est le cas d’une vente annulée, qui a '
                'été abandonnée avant paiement.',
            fond: CouleursTableau.neutreFond,
            texteCouleur: CouleursTableau.neutreTexte,
          ),
        ],
        if (vente.encaisse == false) ...[
          const SizedBox(height: AppSpacing.sm),
          const _Encadre(
            cle: Key('vente-detail-note'),
            // La phrase du maître (l.298-301), au mot.
            texte:
                'Porté en note de chambre : ce montant n’est PAS dans le '
                'tiroir. Il devient une créance, réglée au départ du client.',
            fond: CouleursTableau.alerteFond,
            texteCouleur: CouleursTableau.alerteTexte,
          ),
        ],
        if (vente.encaisse == null) ...[
          const SizedBox(height: AppSpacing.sm),
          const _Encadre(
            cle: Key('vente-detail-reglement-inconnu'),
            // Le troisième cas, absent du maître : ni encaissé ni porté en
            // note. Le ranger dans l'un des deux affirmerait un état que
            // personne n'a vérifié.
            texte:
                'Mode de règlement non renseigné : cette vente ne dit pas si '
                'le montant est entré en caisse.',
            fond: CouleursTableau.alerteFond,
            texteCouleur: CouleursTableau.alerteTexte,
          ),
        ],
        if (vente.aDesLignesSansImpactStock) ...[
          const SizedBox(height: AppSpacing.sm),
          _Encadre(
            cle: const Key('vente-detail-stock'),
            // `pos_pwa.journal.detail_stock`, au mot.
            texte:
                '${vente.lignesSansImpactStock.length} article(s) n’ont décrémenté aucun stock : ${vente.lignesSansImpactStock.join(', ')}. Leur lien au stock est absent.',
            fond: CouleursTableau.refusFond,
            texteCouleur: CouleursTableau.refusTexte,
          ),
        ],
        if (vente.estAnnulee) ...[
          const SizedBox(height: AppSpacing.sm),
          _Encadre(
            cle: const Key('vente-detail-annulation'),
            texte:
                'Vente annulée'
                '${vente.motifAnnulation == null ? '' : ' — ${vente.motifAnnulation}'}. '
                'Elle reste au journal : rien n’est effacé.',
            fond: CouleursTableau.neutreFond,
            texteCouleur: CouleursTableau.neutreTexte,
          ),
        ],
        if (!vente.estAnnulee) ...[
          const SizedBox(height: AppSpacing.sm),
          _BlocAnnulation(vente: vente),
        ],
        const SizedBox(height: AppSpacing.sm),
        _Encadre(
          cle: const Key('vente-detail-piece'),
          // Une vente sans facture n'affirme RIEN de fiscal (PA-119) : ni
          // « non certifiée », qui laisserait croire qu'une pièce attend son
          // cachet, ni le silence, qui laisserait croire qu'elle en a une.
          texte: vente.aUneFacture
              ? 'Facture ${vente.numeroFacture} émise pour cette vente. Le '
                    'registre des factures en porte la pièce.'
              : 'Aucune facture n’a été émise pour cette vente. Une vente peut '
                    'exister sans facture.',
          fond: CouleursTableau.neutreFond,
          texteCouleur: CouleursTableau.neutreTexte,
        ),
      ],
    );
  }
}

class _Ligne extends StatelessWidget {
  const _Ligne({required this.ligne});

  final LigneVente ligne;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // `py-1.5` du maitre — 6 px. C'est un rang de l'echelle Tailwind, pas
      // une somme : l'ecrire `unit + 2` etait une reconstruction.
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(
                  fontFamily: AppTextStyles.police,
                  fontSize: Tailles.t13,
                  color: AppColors.anthracite,
                ),
                children: [
                  TextSpan(text: ligne.libelle),
                  TextSpan(
                    // `× ${quantite}` du maître (l.286), en gris.
                    text: '  × ${ligne.quantite}',
                    style: const TextStyle(color: AppColors.neutre500),
                  ),
                  TextSpan(
                    text: '  ${ligne.module.libelle}',
                    style: const TextStyle(
                      fontSize: Tailles.t10,
                      color: AppColors.neutre500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            formaterFcfa(ligne.montant),
            style: const TextStyle(
              fontFamily: AppTextStyles.policeMonospace,
              fontSize: Tailles.t13,
              fontWeight: FontWeight.w600,
              color: AppColors.anthracite,
            ),
          ),
        ],
      ),
    );
  }
}

class _Encadre extends StatelessWidget {
  const _Encadre({
    required Key cle,
    required this.texte,
    required this.fond,
    required this.texteCouleur,
  }) : super(key: cle);

  final String texte;
  final Color fond;
  final Color texteCouleur;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: fond,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Text(
        texte,
        style: TextStyle(
          fontFamily: AppTextStyles.police,
          fontSize: Tailles.t12,
          color: texteCouleur,
        ),
      ),
    );
  }
}

class _Pied extends ConsumerWidget {
  const _Pied({required this.vente});

  final Vente vente;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.sm),
      // `Wrap` et non `Row` : les trois boutons du maître ne tiennent pas
      // toujours sur la largeur de 520 px de la modale — « Télécharger » et
      // « Imprimer » débordaient de 7,8 px, et un débordement rogne le bouton
      // le plus à droite, celui qui produit le document. Passer à la ligne est
      // laid ; perdre un bouton ne se voit pas.
      child: Wrap(
        alignment: WrapAlignment.end,
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        children: [
          OutlinedButton(
            key: const Key('vente-detail-fermer'),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fermer'),
          ),
          // `detail_ticket_thermique` : la MÊME vente sur le rouleau 80 mm
          // (PA-101), sans dépendre d'une facture.
          OutlinedButton(
            key: const Key('vente-detail-ticket-80'),
            onPressed: () => ref.read(imprimerTicketVenteProvider)(vente),
            child: const Text('Ticket 80 mm'),
          ),
          OutlinedButton(
            key: const Key('vente-detail-imprimer'),
            onPressed: () => ref.read(imprimerVenteProvider)(_etat()),
            child: const Text('Imprimer'),
          ),
          FilledButton(
            key: const Key('vente-detail-telecharger'),
            onPressed: () => _telecharger(context, ref),
            child: const Text('Télécharger'),
          ),
        ],
      ),
    );
  }

  EtatVente _etat() => EtatVente(vente: vente);

  /// « Télécharger » — la fenêtre « Enregistrer sous » puis le toast commun
  /// (14/10/2026). Annulé : rien n'est écrit, rien n'est dit.
  Future<void> _telecharger(BuildContext context, WidgetRef ref) =>
      executerExport(
        context,
        () => ref.read(exporterVenteProvider)(_etat()),
        cleSucces: const Key('vente-detail-chemin'),
      );
}

/// Le bloc d'annulation de la vue (l.480-494) : « Motif de l'annulation », le
/// champ, « Annuler la vente » — RG-02, le motif est OBLIGATOIRE parce que le
/// journal doit dire pourquoi. Réservé à qui écrit sur M5 (masquage d'interface,
/// premier des niveaux de RG-16 ; le DAO refuse aussi la vente d'un autre poste
/// à qui n'est ni administrateur ni comptable).
class _BlocAnnulation extends ConsumerStatefulWidget {
  const _BlocAnnulation({required this.vente});

  final Vente vente;

  @override
  ConsumerState<_BlocAnnulation> createState() => _EtatBlocAnnulation();
}

class _EtatBlocAnnulation extends ConsumerState<_BlocAnnulation> {
  final _motif = TextEditingController();
  String? _erreur;
  bool _envoi = false;

  @override
  void dispose() {
    _motif.dispose();
    super.dispose();
  }

  Future<void> _annuler() async {
    final messager = ScaffoldMessenger.of(context);
    final navigateur = Navigator.of(context);
    setState(() {
      _envoi = true;
      _erreur = null;
    });
    try {
      await annulerUneVente(ref, widget.vente.id, _motif.text);
    } on RefusVente catch (e) {
      if (mounted) {
        setState(() {
          _envoi = false;
          _erreur = e.message;
        });
      }
      return;
    }
    navigateur.pop();
    messager.showSnackBar(
      SnackBar(
        content: Text(
          'Vente ${widget.vente.referenceLocale} annulée. Elle reste au journal.',
          key: const Key('vente-detail-annulee-message'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final peutEcrire = ref
        .watch(droitsProvider)
        .peutEcrire(ModuleTatacora.m5Bar);
    if (!peutEcrire) return const SizedBox.shrink();

    const etiquette = TextStyle(
      fontFamily: AppTextStyles.police,
      fontSize: Tailles.t12,
      fontWeight: FontWeight.w600,
      color: AppColors.neutre700,
    );

    return Container(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.neutre100)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // `detail_motif`.
          const Text('Motif de l’annulation', style: etiquette),
          const SizedBox(height: AppSpacing.xxs),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('vente-detail-motif'),
                  controller: _motif,
                  enabled: !_envoi,
                  style: const TextStyle(
                    fontFamily: AppTextStyles.police,
                    fontSize: Tailles.t12,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              // `detail_annuler`, en rouge `--erreur` comme la vue.
              FilledButton(
                key: const Key('vente-detail-annuler'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.erreur,
                ),
                onPressed: _envoi ? null : _annuler,
                child: const Text('Annuler la vente'),
              ),
            ],
          ),
          if (_erreur != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                _erreur!,
                key: const Key('vente-detail-annulation-refus'),
                style: const TextStyle(
                  fontFamily: AppTextStyles.police,
                  fontSize: Tailles.t12,
                  color: AppColors.erreur,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Ouvre le détail d'une vente.
///
/// Fonction partagée plutôt que recopiée : la ligne du tableau et le bouton
/// « Détail » doivent ouvrir **la même** modale, sans quoi l'une des deux
/// finirait par en présenter une variante.
Future<void> afficherDetailVente(BuildContext context, Vente vente) =>
    showDialog<void>(
      context: context,
      builder: (context) => DialogueDetailVente(vente: vente),
    );
