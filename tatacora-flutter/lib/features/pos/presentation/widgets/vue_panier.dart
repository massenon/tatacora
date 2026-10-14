import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart' show sessionProvider;
import '../../../../core/format/formats.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../restaurant/presentation/widgets/corps_carte_commun.dart'
    show styleContenuCarte;
import '../../../caisse/domain/messages_caisse.dart';
import '../../../caisse/domain/regles_caisse.dart' show RefusCaisse;
import '../../../caisse/presentation/providers_caisse.dart'
    show sessionDuBarProvider;
import '../../../facturation/presentation/ecran_facturation.dart'
    show afficherTicket;
import '../../../facturation/presentation/providers_facturation.dart';
import '../../../comptabilite/domain/calcul_tva.dart' show RefusTva;
import '../../../comptabilite/domain/refus_comptable.dart' show RefusComptable;
import '../../domain/entities/mode_reglement.dart';
import '../../domain/entities/panier.dart';
import '../../domain/entities/table_pos.dart' show RayonSalle;
import '../../domain/messages_ventes.dart' show RefusVente;
import '../../domain/repositories/panier_repository.dart';
import '../providers_pos.dart';
import '../vocabulaire_pos.dart';

/// Le panier — **l'argent**.
///
/// ## Le total est calculé, jamais saisi
///
/// Règle non négociable du projet : toute valeur calculable est affichée en
/// lecture seule. Un total modifiable finirait par contredire ses lignes, et
/// c'est la saisie qui l'emporterait — on ne saurait alors plus quel chiffre
/// est le bon.
///
/// ## D3 — « Clôturer et facturer » facture réellement
///
/// La clôture émet la pièce du registre de facturation, dans la foulée, et
/// présente le ticket. Deux garde-fous encadrent l'enchaînement, parce qu'il
/// touche à l'argent :
///
///  - **l'émission est idempotente** (`Facturer._exigerPanierNonFacture`). Un
///    bouton qui ne réagit pas tout de suite se presse deux fois au comptoir,
///    et une seconde pièce numérotée pour la même vente ne se défait plus que
///    par un avoir ;
///  - **une émission qui échoue ne perd pas la vente.** Le panier reste
///    clôturé, et le pied propose alors « Émettre la facture » — sans quoi la
///    vente serait bloquée dans un état que rien ne rattrape.
///
/// ## La clôture anticipée pose une question, elle ne bloque pas
///
/// Règle 5. Le refus de `cloturer()` sans confirmation n'est pas une erreur :
/// c'est une question, parce que la règle 1 interdit d'ouvrir un second
/// panier. On la pose ; on ne laisse pas l'utilisateur devant un message qu'il
/// ne peut pas lever.
class VuePanier extends ConsumerWidget {
  const VuePanier({required this.panier, required this.vocabulaire, super.key});

  final Panier panier;

  /// Les mots du point de vente qui affiche ce panier.
  ///
  /// Le comptoir dit « Encaisser », le sejour « Cloturer et facturer » —
  /// deux gestes differents, deux maitres differents. Aucune valeur par
  /// defaut : un troisieme POS devra ecrire ses mots, pas heriter de ceux
  /// du voisin par omission.
  final VocabulairePos vocabulaire;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // La table du panier, pour la ligne de contexte « Poste — Table » de la
    // vue (l.339-340). Lue de la salle, jamais devinée.
    final table = panier.tableId == null
        ? null
        : (ref.watch(salleProvider).value ?? const <RayonSalle>[])
              .expand((r) => r.cases)
              .map((c) => c.table)
              .where((t) => t.id == panier.tableId)
              .firstOrNull;

    // Présentation alignée sur la vue le 14/10/2026 (NOUVELLE_INSTRUCTION1
    // §5, `pos/comptant.blade.php` l.318-461) : en-tête, contexte, lignes,
    // pied. Les gestes (vider, abandonner, ±, retirer, encaisser) sont ceux
    // de toujours — seule la présentation change.
    return Container(
      color: AppColors.neutre0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          EnTetePanierComptant(
            nombreArticles: panier.lignes.length,
            // Deux gestes distincts, et le maitre les pose cote a cote dans
            // cet ordre (`pos.html:84-85`) : « Vider » retire les lignes et
            // laisse le panier OUVERT ; « Abandonner » ferme le panier et
            // LIBERE la table. Les confondre en un seul bouton perdrait le
            // premier — et sans le second, une table ouverte par erreur
            // restait bloquee pour toujours, le moteur refusant de cloturer
            // un panier vide.
            actions: [
              if (panier.estOuvert) ...[
                if (vocabulaire.retirerLignes != null)
                  _BoutonEnTete(
                    cle: const Key('pos-vider-panier'),
                    libelle: vocabulaire.retirerLignes!,
                    // Inerte sur un panier deja vide : le geste n'aurait aucun
                    // effet, et un bouton actif qui ne fait rien se presse
                    // deux fois.
                    onPressed: panier.lignes.isEmpty
                        ? null
                        : () => _vider(context, ref),
                  ),
                _BoutonEnTete(
                  cle: const Key('pos-annuler-panier'),
                  libelle: vocabulaire.fermerPanier,
                  danger: true,
                  onPressed: () => _annuler(context, ref),
                ),
              ],
            ],
          ),
          ContextePanierComptant(
            ligne: table != null
                ? '${panier.pointVente ?? ''} — ${table.libelle}'
                : TextesPanierComptant.vendreAuComptoir,
          ),
          Expanded(
            child: panier.lignes.isEmpty
                ? const PanierVideComptant()
                : ListView(
                    children: [
                      for (final l in panier.lignes)
                        _Ligne(panier: panier, ligne: l),
                    ],
                  ),
          ),
          _Pied(panier: panier, vocabulaire: vocabulaire),
        ],
      ),
    );
  }

  /// « Vider » — retire les lignes, garde le panier ouvert.
  ///
  /// **Sans confirmation, comme le maître** (`pos.html:1012`). Ce n'est pas un
  /// oubli : le geste est réversible en rescannant les articles, et une
  /// question posée à chaque correction de commande au comptoir se ferait
  /// valider machinalement — la confirmation perdrait alors tout son sens là
  /// où elle compte, sur l'annulation du panier, qui elle est irréversible.
  Future<void> _vider(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(depotPanierProvider).vider(panier.id);
      rafraichirPaniers(ref);
    } on Object catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _annuler(BuildContext context, WidgetRef ref) async {
    final controleur = TextEditingController();
    final motif = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Annuler ce panier'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Les consommations déjà saisies sont conservées : la question '
              '« qu’a-t-il consommé ? » doit rester répondable après coup.',
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const Key('pos-motif-annulation'),
              controller: controleur,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Motif de l’annulation',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Renoncer'),
          ),
          FilledButton(
            key: const Key('pos-confirmer-annulation'),
            onPressed: () => Navigator.of(context).pop(controleur.text),
            child: const Text('Annuler le panier'),
          ),
        ],
      ),
    );

    if (motif == null) return;
    try {
      await ref.read(gererPanierProvider).annuler(panier.id, motif);
      ref.read(panierActifProvider.notifier).definir(null);
      rafraichirPaniers(ref);
    } on ArgumentError catch (e) {
      if (context.mounted) _signaler(context, '${e.message}');
    }
  }
}

class _Ligne extends ConsumerWidget {
  const _Ligne({required this.panier, required this.ligne});

  final Panier panier;
  final LignePanier ligne;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modifiable = panier.estModifiable;

    // `w-7 h-7 rounded-lg border border-slate-300 font-bold` (l.366-370).
    Widget bouton(
      Key cle,
      String signe,
      String aide,
      Future<void> Function() f,
    ) => Tooltip(
      message: aide,
      child: InkWell(
        key: cle,
        borderRadius: BorderRadius.circular(AppRadius.roundedLg),
        onTap: f,
        child: Container(
          width: LargeursPos.controleQuantiteComptant,
          height: LargeursPos.controleQuantiteComptant,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: Ardoise.c300),
            borderRadius: BorderRadius.circular(AppRadius.roundedLg),
          ),
          child: Text(
            signe,
            style: styleContenuCarte(
              TaillesContenu.t13,
              poids: FontWeight.bold,
            ).copyWith(height: Tailles.interligneAucun),
          ),
        ),
      ),
    );

    // `px-4 py-2.5 border-b border-slate-100 flex items-center gap-2` (l.360).
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xsPlus,
      ),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Ardoise.c100)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // `text-[13px] font-medium truncate` navy.
                Text(
                  ligne.libelle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: styleContenuCarte(
                    TaillesContenu.t13,
                    poids: FontWeight.w500,
                    couleur: AppColors.navy,
                  ),
                ),
                // `text-[11px] text-slate-400` : « prix × quantité ». Le prix
                // FIGÉ : celui du moment où l'article a été servi.
                Text(
                  '${formaterFcfa(ligne.prixUnitaire)} × ${ligne.quantite}',
                  style: styleContenuCarte(
                    TaillesContenu.t11,
                    couleur: Ardoise.c400,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          if (modifiable)
            bouton(
              Key('pos-moins-${ligne.id}'),
              '−',
              'Retirer une unité',
              () async {
                await ref.read(gererPanierProvider).diminuer(panier.id, ligne);
                rafraichirPaniers(ref);
              },
            ),
          // `w-7 text-center text-[13px] font-semibold`.
          SizedBox(
            width: LargeursPos.controleQuantiteComptant,
            child: Text(
              '${ligne.quantite}',
              textAlign: TextAlign.center,
              style: styleContenuCarte(
                TaillesContenu.t13,
                poids: FontWeight.w600,
              ),
            ),
          ),
          if (modifiable)
            bouton(
              Key('pos-plus-${ligne.id}'),
              '+',
              'Ajouter une unité',
              () async {
                await ref
                    .read(gererPanierProvider)
                    .changerQuantite(panier.id, ligne.id, ligne.quantite + 1);
                rafraichirPaniers(ref);
              },
            ),
          const SizedBox(width: AppSpacing.xs),
          // `w-20 text-right text-[13px] font-bold` navy.
          SizedBox(
            width: LargeursPos.montantLigne,
            child: Text(
              // Calculé, jamais stocké ni saisi.
              formaterFcfa(ligne.montant),
              textAlign: TextAlign.right,
              style: styleContenuCarte(
                TaillesContenu.t13,
                poids: FontWeight.bold,
                couleur: AppColors.navy,
              ),
            ),
          ),
          if (modifiable) ...[
            const SizedBox(width: AppSpacing.xs),
            // `text-red-500 hover:bg-red-50 p-1 rounded` — infobulle
            // `pos_pwa.comptant.retirer_ligne`.
            Tooltip(
              message: 'Retirer « ${ligne.libelle} » du panier',
              child: InkWell(
                key: Key('pos-retirer-${ligne.id}'),
                borderRadius: BorderRadius.circular(AppRadius.rounded),
                onTap: () async {
                  await ref
                      .read(gererPanierProvider)
                      .retirer(panier.id, ligne.id);
                  rafraichirPaniers(ref);
                },
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.unit),
                  child: Text(
                    '✕',
                    style: styleContenuCarte(
                      TaillesContenu.t13,
                      couleur: PaletteMaitre.rouge500,
                    ).copyWith(height: Tailles.interligneAucun),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Pied extends ConsumerWidget {
  const _Pied({required this.panier, required this.vocabulaire});

  final Panier panier;

  /// Le pied porte les deux elements qui different d'un maitre a l'autre :
  /// le choix du reglement (comptoir seulement) et le bouton qui engage
  /// l'argent.
  final VocabulairePos vocabulaire;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // « Encaisser » exige une caisse ouverte AU COMPTOIR : le serveur désactive
    // le bouton (`@disabled(! $session)`) et en change le libellé. Un panier de
    // séjour se porte sur la note de chambre : aucune caisse n'est requise.
    // Tant que la session se charge, le bouton reste désactivé (jamais armé sur
    // une donnée qu'on n'a pas encore lue).
    final caisseRequise = panier.typeVente == TypeVente.comptant;
    final caisseOuverte =
        !caisseRequise || ref.watch(sessionDuBarProvider).value != null;

    // Le pied de la vue (l.383-460) : `shrink-0 border-t border-slate-200 p-4
    // bg-slate-50` — total, remise, mode de règlement et client sur une
    // ligne, puis « Encaisser ». La ventilation par module (puces) n'est pas
    // dans la vue du comptoir : retirée le 14/10/2026.
    final etiquette = styleContenuCarte(
      TaillesContenu.t11,
      poids: FontWeight.w600,
      couleur: Ardoise.c500,
    );

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: const BoxDecoration(
        color: Ardoise.c50,
        border: Border(top: BorderSide(color: Ardoise.c200)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // `flex justify-between items-baseline mb-1` : « Total » `text-[13px]
          // text-slate-500`, le montant `text-2xl font-bold` navy.
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                TextesPanierComptant.total,
                style: styleContenuCarte(
                  TaillesContenu.t13,
                  couleur: Ardoise.c500,
                ),
              ),
              Flexible(
                child: Text(
                  key: const Key('pos-total'),
                  formaterFcfa(panier.total),
                  textAlign: TextAlign.right,
                  style: styleContenuCarte(
                    TaillesContenu.xxl,
                    poids: FontWeight.bold,
                    couleur: AppColors.navy,
                  ).copyWith(height: TaillesContenu.interligneXxl),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.unit),
          if (panier.estOuvert) ...[
            // La ligne « Remise » (l.397-408) : ce poste n'en porte aucune.
            LigneRemiseComptant(etiquette: etiquette),
            const SizedBox(height: AppSpacing.xs),
          ],
          // Le maitre pose le reglement ENTRE le total et le bouton
          // (`pos.html:106-108`) : un libelle, puis le choix, puis l'action.
          // L'ordre compte — le caissier lit le montant, dit comment le client
          // paie, puis encaisse. Mode et client sur UNE ligne (`grid
          // grid-cols-2 gap-2 mb-3`, directive PO du 03/09/2026).
          if (panier.estOuvert && vocabulaire.libelleReglement != null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(vocabulaire.libelleReglement!, style: etiquette),
                      const SizedBox(height: AppSpacing.unit),
                      DropdownButtonFormField<ModeReglement>(
                        key: const Key('pos-mode-reglement'),
                        initialValue: _modeAuComptoir(ref),
                        isDense: true,
                        // Le panier fait 380 px au maitre : « Porte sur la
                        // note de chambre » n'y tient pas a sa taille
                        // naturelle. `isExpanded` contraint le bouton a la
                        // largeur disponible, l'ellipse coupe proprement.
                        isExpanded: true,
                        style: styleContenuCarte(
                          TaillesContenu.t13,
                          couleur: AppColors.anthracite,
                        ),
                        decoration: _decorationChamp(),
                        // `$modesPaiementComptoir` de la vue : la note de
                        // chambre n'est pas proposée au comptoir (voir
                        // `ModeReglement.auComptoir`, décision du 14/10/2026).
                        items: [
                          for (final m in ModeReglement.auComptoir)
                            DropdownMenuItem(
                              value: m,
                              child: Text(
                                m.libelle,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (m) {
                          if (m != null) {
                            ref.read(modeReglementProvider.notifier).definir(m);
                          }
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(TextesPanierComptant.client, style: etiquette),
                      const SizedBox(height: AppSpacing.unit),
                      const ChampClientComptant(),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          if (panier.estOuvert)
            // `w-full py-3 rounded-lg bg-navy text-white font-bold text-[14px]
            // disabled:opacity-40`.
            FilledButton(
              key: const Key('pos-cloturer'),
              style: styleBoutonEncaisser,
              onPressed: panier.lignes.isEmpty || !caisseOuverte
                  ? null
                  : () => _cloturer(context, ref, anticipe: false),
              child: Text(
                caisseOuverte
                    ? vocabulaire.actionPrincipale
                    : MessagesCaisse.encaisserSansCaisse,
              ),
            )
          else ...[
            Text(
              key: const Key('pos-panier-fige'),
              panier.statut == StatutPanier.cloture
                  ? 'Panier clôturé à ${panier.montantCloture} FCFA — '
                        'toute correction passe désormais par un avoir.'
                  : 'Panier annulé : ${panier.motifAnnulation}',
              style: styleContenuCarte(
                TaillesContenu.t12,
                couleur: Ardoise.c500,
              ),
            ),
            if (panier.statut == StatutPanier.cloture)
              ActionFacture(panier: panier),
          ],
        ],
      ),
    );
  }

  /// Le mode affiché au comptoir. Le choix vit dans [modeReglementProvider],
  /// PARTAGÉ avec le POS des clients hébergés : s'il y vaut encore « Porté sur
  /// la note de chambre », le sélecteur du comptoir ne peut pas l'afficher (il
  /// n'est plus dans sa liste). Le choix est alors ramené au défaut — après
  /// l'image, jamais pendant la construction —, pour que le mode encaissé soit
  /// toujours celui qui s'affiche.
  ModeReglement _modeAuComptoir(WidgetRef ref) {
    final choisi = ref.watch(modeReglementProvider);
    if (ModeReglement.auComptoir.contains(choisi)) return choisi;
    // Le notifier est lu MAINTENANT : la référence du widget ne doit pas servir
    // après un éventuel démontage.
    final notifier = ref.read(modeReglementProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => notifier.reinitialiser(),
    );
    return ModeReglement.parDefaut;
  }

  Future<void> _cloturer(
    BuildContext context,
    WidgetRef ref, {
    required bool anticipe,
  }) async {
    try {
      // Le mode CHOISI, plus une constante. Ecrire « especes » en dur faisait
      // entrer en caisse un argent que personne n'avait recu, et rendait
      // « Porte sur la note de chambre » — qui n'est PAS un encaissement —
      // inatteignable.
      final mode = ref.read(modeReglementProvider);
      final cloture = await ref
          .read(gererPanierProvider)
          .cloturer(
            panier.id,
            anticipe: anticipe,
            modePaiement: mode.code,
            // Celui qui encaisse (RG-15) : la vente passe sa pièce comptable
            // dans la même transaction, et une pièce sans auteur est refusée.
            auteurId: ref.read(sessionProvider)?.utilisateurId ?? '',
          );
      // Remis a l'etat neutre : un mode choisi pour un client resterait arme
      // pour le suivant, qui paierait comptant sans que rien ne l'encaisse.
      ref.read(modeReglementProvider.notifier).reinitialiser();
      rafraichirPaniers(ref);
      if (context.mounted) await facturerPanier(context, ref, cloture);
    } on ClotureAnticipeeNonConfirmee catch (e) {
      if (!context.mounted) return;
      // Le refus n'est pas une erreur : c'est une question. On la pose.
      final confirme = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Clôturer avant le départ ?'),
          content: Text(
            '$e\n\nAucune consommation ne pourra plus être enregistrée pour '
            'ce séjour.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Laisser ouvert'),
            ),
            FilledButton(
              key: const Key('pos-confirmer-cloture-anticipee'),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Clôturer quand même'),
            ),
          ],
        ),
      );
      if (confirme ?? false) {
        if (!context.mounted) return;
        await _cloturer(context, ref, anticipe: true);
      }
    } on PanierVide catch (e) {
      if (context.mounted) _signaler(context, '$e');
    } on RefusCaisse catch (e) {
      // La caisse a été close entre l'affichage du bouton et le clic : le DAO
      // refuse avec la phrase du serveur, et le panier reste OUVERT et intact.
      if (context.mounted) _signaler(context, e.message);
    } on RefusVente catch (e) {
      // Un refus de la vente (module non encaissable, mode, article retiré du
      // catalogue) : la phrase est celle du serveur, le panier reste OUVERT.
      if (context.mounted) _signaler(context, e.message);
    } on RefusTva catch (e) {
      // La TVA est active sans taux (ou la convention est illisible) : la pièce
      // ne peut pas être calculée, donc la vente n'est pas enregistrée.
      if (context.mounted) _signaler(context, e.message);
    } on RefusComptable catch (e) {
      // La pièce est refusée (exercice, compte, journal, centre) : RIEN n'a été
      // écrit, ni la clôture ni la pièce, et le panier reste OUVERT et intact.
      if (context.mounted) _signaler(context, e.message);
    }
  }
}

/// Émet la pièce du panier clôturé, puis présente le ticket.
///
/// Partagée par la clôture et par le bouton de rattrapage : deux copies de cet
/// enchaînement divergeraient, et c'est la seconde que personne ne relit.
///
/// L'échec est **rattrapable** et le dit : la vente est déjà clôturée et son
/// montant figé, seule la pièce manque. Le pied propose alors de la réémettre.
Future<void> facturerPanier(
  BuildContext context,
  WidgetRef ref,
  Panier cloture,
) async {
  try {
    final piece = await ref.read(emettrePourPanierProvider)(cloture);
    rafraichirFacturation(ref);
    if (context.mounted) await afficherTicket(context, piece);
  } on Object catch (e) {
    if (context.mounted) {
      _signaler(
        context,
        'Facture non émise : $e La vente est clôturée à '
        '${cloture.montantCloture} FCFA ; la facture reste à émettre.',
      );
    }
  }
}

/// Le pied d'un panier clôturé : voir le ticket, ou l'émettre.
///
/// **Public, et pour une raison précise.** Le POS au comptant ne rend pas
/// [VuePanier] lorsqu'un panier est clôturé — il bascule sur son écran « aucun
/// panier en cours », qui annonce le montant de la vente. Sans cet accès, une
/// vente au comptant dont l'émission a échoué n'offrirait plus aucun chemin
/// vers sa facture.
///
/// Le bouton n'apparaît **jamais** pour un document qui n'existe pas : proposer
/// un ticket qui ne pointe vers rien est pire qu'un bouton absent, l'utilisateur
/// ne sachant alors pas si la pièce manque ou si l'écran est cassé (PA-89).
class ActionFacture extends ConsumerWidget {
  const ActionFacture({required this.panier, super.key});

  final Panier panier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final facture = ref.watch(facturePourPanierProvider(panier.id));

    return facture.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => Text('$e', style: Theme.of(context).textTheme.bodySmall),
      data: (piece) => piece == null
          ? FilledButton.tonal(
              key: const Key('pos-emettre-facture'),
              onPressed: () => facturerPanier(context, ref, panier),
              child: const Text('Émettre la facture'),
            )
          : TextButton.icon(
              key: const Key('pos-voir-ticket'),
              icon: const Icon(Icons.receipt_long_outlined),
              label: Text('Ticket ${piece.numero}'),
              onPressed: () => afficherTicket(context, piece),
            ),
    );
  }
}

void _signaler(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

/* ====================================================================== */
/* Briques du panneau Panier du comptoir — `pos/comptant.blade.php`        */
/* l.318-461, alignées sur la vue le 14/10/2026 (NOUVELLE_INSTRUCTION1 §5). */
/* Partagées par [VuePanier] (panier ouvert) et l'état « aucun panier » de  */
/* l'écran : deux copies de l'en-tête divergeraient.                        */
/* ====================================================================== */

/// Les mots du panneau Panier du comptoir — clés `pos_pwa.comptant.*`.
abstract final class TextesPanierComptant {
  /// `pos_pwa.comptant.panier`.
  static const String panier = 'Panier';

  /// `pos_pwa.comptant.articles`.
  static String articles(int nombre) => '$nombre article(s)';

  /// `pos_pwa.comptant.vendre_au_comptoir`.
  static const String vendreAuComptoir = 'Vendre au comptoir';

  /// `pos_pwa.comptant.panier_aucun`.
  static const String aucunPanier = 'Aucun panier ouvert';

  /// `pos_pwa.comptant.panier_choisir`.
  static const String choisir =
      'Choisissez une table ou le comptoir dans la salle.';

  /// `pos_pwa.comptant.panier_sur_ce_poste`, « de navigateur » remplacé par
  /// « la fermeture de l'application » : ce client n'a pas de navigateur (même
  /// écart que le panier de séjour, `PanierHeberges.surCePoste`).
  static const String surCePoste =
      'Enregistré sur ce poste : le panier reste ouvert après un changement '
      'd’équipe ou la fermeture de l’application. Il ne part vers aucun '
      'autre poste.';

  /// `pos_pwa.comptant.panier_vide`.
  static const String panierVide = 'Panier vide';

  /// `pos_pwa.comptant.panier_vide_aide`.
  static const String panierVideAide = 'Touchez un article pour l\'ajouter.';

  /// `pos_pwa.comptant.total`.
  static const String total = 'Total';

  /// `pos_pwa.commun.remise`.
  static const String remise = 'Remise';

  /// `pos_pwa.commun.remise_aucune`.
  static const String remiseAucune = 'Aucune';

  /// `pos_pwa.commun.remise_valeur` (l'`aria-label` du champ).
  static const String remiseValeur = 'Valeur de la remise';

  /// `pos_pwa.comptant.client`.
  static const String client = 'Client (facultatif)';

  /// `pos_pwa.comptant.client_mention_aide` (le `placeholder`).
  static const String clientAide =
      'Nom à imprimer sur le ticket — aucun compte client n\'est créé.';

  /// Ce que dit la ligne « Remise » quand on la touche : le panier du poste
  /// ne porte AUCUNE remise (`PanierDao`, « Aucune remise »), une valeur
  /// saisie n'aurait aucun effet sur le total encaissé. Jamais un champ qui
  /// accepterait une valeur sans effet (Article 3.3).
  static const String remiseNonDisponible =
      'La remise ne s’applique pas sur ce poste : le panier ne porte aucune '
      'remise, donc le montant encaissé reste le total des lignes. Rien n’a '
      'été enregistré.';

  /// Ce que dit le champ « Client » quand on le touche : la mention n'est
  /// conservée nulle part sur ce poste et ne s'imprime pas sur le ticket.
  static const String clientNonDisponible =
      'La mention client n’est pas encore enregistrée sur ce poste : elle ne '
      's’imprimerait pas sur le ticket. Rien n’a été enregistré.';
}

/// `px-4 py-3 border-b border-slate-200 flex items-center justify-between`
/// (l.319-330) : « Panier » `text-[14px] font-bold` navy, « N article(s) »
/// `text-[11px] text-slate-400`, puis les boutons.
class EnTetePanierComptant extends StatelessWidget {
  const EnTetePanierComptant({
    required this.nombreArticles,
    this.actions = const [],
    super.key,
  });

  final int nombreArticles;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Ardoise.c200)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  TextesPanierComptant.panier,
                  style: styleContenuCarte(
                    TaillesContenu.t14,
                    poids: FontWeight.bold,
                    couleur: AppColors.navy,
                  ),
                ),
                Text(
                  TextesPanierComptant.articles(nombreArticles),
                  key: const Key('pos-nombre-articles'),
                  style: styleContenuCarte(
                    TaillesContenu.t11,
                    couleur: Ardoise.c400,
                  ),
                ),
              ],
            ),
          ),
          // `flex items-center gap-1.5`.
          for (final (i, a) in actions.indexed) ...[
            if (i > 0) const SizedBox(width: AppSpacing.xxs),
            a,
          ],
        ],
      ),
    );
  }
}

/// `text-[12px] px-2.5 py-1 rounded-lg border border-slate-300 font-medium`
/// (l.325-328) ; « Abandonner » en `text-red-600`.
class _BoutonEnTete extends StatelessWidget {
  const _BoutonEnTete({
    required this.cle,
    required this.libelle,
    required this.onPressed,
    this.danger = false,
  });

  final Key cle;
  final String libelle;
  final VoidCallback? onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final couleur = onPressed == null
        ? Ardoise.c400
        : danger
        ? PaletteMaitre.rouge600
        : AppColors.anthracite;
    return InkWell(
      key: cle,
      onTap: onPressed,
      borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xsPlus,
          vertical: AppSpacing.unit,
        ),
        decoration: BoxDecoration(
          border: Border.all(color: Ardoise.c300),
          borderRadius: BorderRadius.circular(AppRadius.roundedLg),
        ),
        child: Text(
          libelle,
          style: styleContenuCarte(
            TaillesContenu.t12,
            poids: FontWeight.w500,
            couleur: couleur,
          ),
        ),
      ),
    );
  }
}

/// La bande de contexte (l.337-350) : `px-4 py-2.5 border-b bg-slate-50` —
/// la table (ou le comptoir, ou « Aucun panier ouvert ») en `text-[13px]
/// font-semibold text-slate-700`, puis deux phrases `text-[11px]
/// text-slate-400`.
class ContextePanierComptant extends StatelessWidget {
  const ContextePanierComptant({required this.ligne, super.key});

  final String ligne;

  @override
  Widget build(BuildContext context) {
    final aide = styleContenuCarte(TaillesContenu.t11, couleur: Ardoise.c400);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xsPlus,
      ),
      decoration: const BoxDecoration(
        color: Ardoise.c50,
        border: Border(bottom: BorderSide(color: Ardoise.c200)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ligne,
            key: const Key('pos-contexte-panier'),
            style: styleContenuCarte(
              TaillesContenu.t13,
              poids: FontWeight.w600,
              couleur: Ardoise.c700,
            ),
          ),
          const SizedBox(height: AppSpacing.demi),
          Text(TextesPanierComptant.choisir, style: aide),
          const SizedBox(height: AppSpacing.demi),
          // Ce panier ne part pas au serveur, et l'écran ne le laisse pas
          // croire : annoncer « en attente de synchronisation » serait un
          // indicateur affirmant un état qu'il n'a pas vérifié (PA-59/60/61).
          Text(
            TextesPanierComptant.surCePoste,
            key: const Key('pos-transmission'),
            style: aide,
          ),
        ],
      ),
    );
  }
}

/// Le panier vide (l.354-357) : `py-16 px-6 text-center`, « Panier vide »
/// `text-[13px] text-slate-400` et « Touchez un article pour l'ajouter. »
/// `text-[11.5px] text-slate-300 mt-1`.
class PanierVideComptant extends StatelessWidget {
  const PanierVideComptant({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacingLarge.p16,
      ),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          children: [
            Text(
              TextesPanierComptant.panierVide,
              key: const Key('pos-panier-vide'),
              textAlign: TextAlign.center,
              style: styleContenuCarte(
                TaillesContenu.t13,
                couleur: Ardoise.c400,
              ),
            ),
            const SizedBox(height: AppSpacing.unit),
            Text(
              TextesPanierComptant.panierVideAide,
              textAlign: TextAlign.center,
              style: styleContenuCarte(
                TaillesContenu.t11_5,
                couleur: Ardoise.c300,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// La ligne « Remise » (l.397-408) : étiquette, `<select>` « Aucune »,
/// valeur. Touchés, les deux champs DISENT que la remise n'existe pas sur ce
/// poste — jamais un champ qui accepterait une valeur sans effet.
class LigneRemiseComptant extends StatelessWidget {
  const LigneRemiseComptant({required this.etiquette, super.key});

  final TextStyle etiquette;

  @override
  Widget build(BuildContext context) {
    void dire() => ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text(TextesPanierComptant.remiseNonDisponible)),
    );
    return Row(
      children: [
        Text(TextesPanierComptant.remise, style: etiquette),
        const SizedBox(width: AppSpacing.xs),
        _ChampDisant(
          cle: const Key('pos-remise-type'),
          texte: TextesPanierComptant.remiseAucune,
          taille: TaillesContenu.t12,
          onTap: dire,
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Semantics(
            label: TextesPanierComptant.remiseValeur,
            child: _ChampDisant(
              cle: const Key('pos-remise-valeur'),
              texte: '',
              taille: TaillesContenu.t12,
              onTap: dire,
            ),
          ),
        ),
      ],
    );
  }
}

/// Le champ « Client (facultatif) » (l.448-451) : son `placeholder`, et,
/// touché, la raison pour laquelle rien n'y est saisi sur ce poste.
class ChampClientComptant extends StatelessWidget {
  const ChampClientComptant({super.key});

  @override
  Widget build(BuildContext context) {
    return _ChampDisant(
      cle: const Key('pos-client-mention'),
      texte: TextesPanierComptant.clientAide,
      taille: TaillesContenu.t13,
      indication: true,
      onTap: () => ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(TextesPanierComptant.clientNonDisponible)),
      ),
    );
  }
}

/// Le gabarit d'un `<select>` / `<input>` de la vue (`border border-slate-300
/// rounded-lg bg-white`) qui, touché, DIT pourquoi il n'agit pas.
class _ChampDisant extends StatelessWidget {
  const _ChampDisant({
    required this.cle,
    required this.texte,
    required this.taille,
    required this.onTap,
    this.indication = false,
  });

  final Key cle;
  final String texte;
  final double taille;
  final VoidCallback onTap;

  /// Vrai : [texte] est un `placeholder` (gris), pas une valeur.
  final bool indication;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: cle,
      borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minWidth: LargeursPos.montantLigne),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.xxs,
        ),
        decoration: BoxDecoration(
          color: AppColors.neutre0,
          border: Border.all(color: Ardoise.c300),
          borderRadius: BorderRadius.circular(AppRadius.roundedLg),
        ),
        child: Text(
          texte,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: styleContenuCarte(
            taille,
            couleur: indication ? Ardoise.c400 : AppColors.anthracite,
          ),
        ),
      ),
    );
  }
}

/// `border border-slate-300 rounded-lg px-3 py-2 bg-white` — le `<select>` du
/// mode de règlement (l.433-434).
InputDecoration _decorationChamp() {
  OutlineInputBorder bordure(Color couleur) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadius.roundedLg),
    borderSide: BorderSide(color: couleur),
  );
  return InputDecoration(
    isDense: true,
    filled: true,
    fillColor: AppColors.neutre0,
    contentPadding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.sm,
      vertical: AppSpacing.xs,
    ),
    border: bordure(Ardoise.c300),
    enabledBorder: bordure(Ardoise.c300),
    focusedBorder: bordure(AppColors.gold),
  );
}

/// `w-full py-3 rounded-lg bg-[var(--navy)] text-white font-bold text-[14px]
/// disabled:opacity-40` (l.456-459) — « Encaisser » et « Nouvelle vente au
/// comptoir » partagent ce gabarit.
final ButtonStyle styleBoutonEncaisser = FilledButton.styleFrom(
  backgroundColor: AppColors.navy,
  foregroundColor: AppColors.neutre0,
  disabledBackgroundColor: AppColors.navy.withValues(
    alpha: AppColors.opaciteDesactive,
  ),
  disabledForegroundColor: AppColors.neutre0.withValues(
    alpha: AppColors.opaciteDesactive,
  ),
  padding: const EdgeInsets.symmetric(
    horizontal: AppSpacing.md,
    vertical: AppSpacing.sm,
  ),
  minimumSize: Size.zero,
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppRadius.roundedLg),
  ),
  textStyle: styleContenuCarte(TaillesContenu.t14, poids: FontWeight.bold),
);
