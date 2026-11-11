import '../../../../core/impression/visas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/di/providers.dart';
import '../../../../core/rbac/garde_acces.dart';
import '../../../../shared_widgets/liste_paginee.dart';
import '../../data/achats_api.dart';
import '../../domain/dettes_fournisseurs.dart';
import '../../domain/decimal_texte.dart';
import '../../domain/entities/commande_achat.dart';
import '../../domain/messages_reglement.dart';
import '../../impression/etat_liste_achats.dart';
import '../geste_reglement.dart';
import '../providers_achats.dart';
import 'barre_outils_achats.dart';
import 'coquille_achats.dart';
import 'modale_reception.dart';
import 'vue_rapprochement.dart';

/// L'onglet **« Commandes »** — `m7-approvisionnement.html` l.329-399.
///
/// ## « Réglé », « Reste dû » et « Régler » sont rendus (D66, 12/10/2026)
///
/// Le règlement fournisseur est un mouvement d'argent : il écrit sa pièce
/// comptable (Dr 4011 / Cr trésorerie) dans la même transaction
/// (`ReglementsFournisseurDao`, règle du Product Owner du 31/08/2026). « Réglé »
/// est la somme des règlements ACTIFS de la commande, « Reste dû » le montant
/// moins ce réglé, planché à zéro ; un zéro s'affiche « — » (`formatOuTiret`).
/// Le bouton « Régler » n'est rendu qu'à qui peut écrire sur M7 et tant qu'il
/// reste quelque chose à devoir — la condition de la vue (`$peutEcrire` et un
/// reste positif).
///
/// ## Le « N° » n'existe pas non plus
///
/// `commandes_achat` n'a **aucune séquence**, seulement un UUID. Fabriquer un
/// « CMD-0001 » à l'affichage donnerait un numéro qui changerait au prochain
/// tri — et qui ne correspondrait à rien sur le bon papier. L'identifiant est
/// affiché tel quel, sous le nom de « Référence ».
///
/// ## Deux boutons du serveur que le maître n'a pas
///
/// « Émettre » (`PATCH /commandes/{id}/envoi`) et « Clôturer »
/// (`PATCH /commandes/{id}/cloture`) sont **ajoutés**, et l'ajout est
/// délibéré :
///
/// - sans « Émettre », `brouillon` serait un état **sans sortie** : le maître
///   l'offre à son filtre et une commande y resterait indéfiniment ;
/// - « Clôturer » porte RG-10, et `CommandeAchatResource` envoie `cloturable`
///   **précisément pour qu'un écran conditionne ce bouton**. Un drapeau que
///   personne ne lit est un drapeau qui finit par mentir.
///
/// Les deux sont conditionnés par ce que le SERVEUR dit — `cloturable`,
/// `receptionnable` —, jamais par un calcul refait ici : deux lectures
/// indépendantes finiraient par diverger, et l'écran proposerait un bouton que
/// le serveur refuse.
class VueCommandes extends ConsumerStatefulWidget {
  const VueCommandes({super.key, this.visas = Visas.achats});

  /// Les visas de l'export : ceux de pdf/achats.blade.php sur l'écran
  /// Achats, ceux de pdf/approvisionnement-bon.blade.php sur
  /// l'Approvisionnement — la même liste, deux documents serveur (PA-195).
  final List<String> visas;

  @override
  ConsumerState<VueCommandes> createState() => _VueCommandesState();
}

class _VueCommandesState extends ConsumerState<VueCommandes> {
  final _recherche = TextEditingController();

  @override
  void initState() {
    super.initState();
    _recherche.text = ref.read(rechercheCommandeProvider);
  }

  @override
  void dispose() {
    _recherche.dispose();
    super.dispose();
  }

  ListeAchats? _liste(PageAchats<CommandeAchat> page) {
    if (page.elements.isEmpty) return null;

    final statut = ref.read(statutCommandeProvider);
    final terme = ref.read(rechercheCommandeProvider).trim();

    return ListeAchats(
      titre: 'Bons de commande fournisseurs',
      visas: widget.visas,
      portee: Portee(
        filtre: [
          // Le libellé que l'utilisateur A VU au filtre (PA-119) — un seul
          // registre depuis PA-185, `Achats::STATUTS`, commun aux deux vues.
          statut == null ? 'Tous les statuts' : 'Statut : ${statut.libelle}',
          if (terme.isNotEmpty) 'recherche « $terme »',
        ].join(' — '),
        lignesRapportees: page.elements.length,
        totalServeur: page.total,
      ),
      entetes: const [
        'Référence',
        'Fournisseur',
        'Date',
        'Lignes',
        'Montant',
        'Statut',
      ],
      // L'export ne porte ni « Réglé » ni « Reste dû » : `AchatsExport` du
      // serveur n'a pas ces colonnes (D262) — un tableur relu hors de l'écran
      // qui l'a produit ne doit pas en dire plus que le serveur.
      colonnesNumeriques: const {3, 4},
      lignes: [
        for (final c in page.elements)
          [
            c.id,
            c.fournisseurRaisonSociale,
            c.dateCommande,
            '${c.nombreLignes}',
            // Le montant du serveur, tel quel — nombre brut : un tableur ne
            // sait pas additionner « 56 000 FCFA ».
            c.montantTotal,
            c.libelleStatut,
          ],
      ],
    );
  }

  void _rafraichir() {
    ref.invalidate(commandesProvider(null));
    ref.invalidate(receptionsProvider(null));
    // Les besoins se lisent du STOCK, que la réception vient de modifier (elle
    // écrit l'entrée dans la même opération). Sans cette ligne, la bande dirait
    // « 2 articles sous seuil » sur un stock reconstitué — l'indicateur qui
    // affirme un état qu'il n'a pas relu (PA-59/60/61). Invisible tant que le
    // stock venait d'un serveur que ce poste ne pouvait pas modifier.
    ref.invalidate(besoinsProvider);
    ref.invalidate(kpisApprovisionnementProvider);
  }

  Future<void> _receptionner(CommandeAchat commande) async {
    final bon = await ouvrirModaleReception(context, commande: commande);
    if (bon == null || !mounted) return;

    _rafraichir();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Réception enregistrée sur ce poste — conformité : '
          '${bon.libelleConformite}. L’entrée de stock a été écrite dans la '
          'même opération. Elle n’est pas valorisée : la réception ne porte '
          'aucun coût, comme sur le serveur.',
        ),
      ),
    );
  }

  Future<void> _transition(
    Future<ResultatAchats<CommandeAchatDetail>> Function() appel,
    String succes,
  ) async {
    final resultat = await appel();
    if (!mounted) return;

    switch (resultat) {
      case AchatsRecu():
        _rafraichir();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(succes)));
      case AchatsRefuse(:final motif):
        // Le message du serveur, tel quel : sur une clôture, c'est lui qui dit
        // « enregistrez la réception complémentaire ou faites acter l'écart ».
        // Le refus EST le livrable de RG-10 — forcer la clôture ferait perdre
        // la créance sur le fournisseur, sans trace.
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(motif)));
      case AchatsInjoignable():
        // Jamais produite (la base est locale) ; le type la garde.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'La base du poste n’a pas répondu : rien n’a changé.',
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final resultat = ref.watch(commandesProvider(null));

    return resultat.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) =>
          NoteAchats(cle: const Key('commandes-erreur'), texte: '$e'),
      data: (r) => switch (r) {
        AchatsRecu(:final donnees) => _corps(donnees),
        AchatsRefuse(:final motif) => NoteAchats(
          cle: const Key('commandes-refus'),
          texte: motif,
        ),
        // Jamais produite (la base est locale) ; le type la garde.
        AchatsInjoignable() => const NoteAchats(
          cle: Key('commandes-hors-ligne'),
          texte:
              'La base du poste n’a pas répondu : aucun registre n’est '
              'affiché, plutôt qu’un registre d’hier qui ferait réceptionner '
              'une commande déjà clôturée.',
        ),
      },
    );
  }

  Widget _corps(PageAchats<CommandeAchat> page) {
    // La page défile d'un bloc (`<main>` de la vue) : cette liste s'y loge.
    return ListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        CadreListeAchats(
          titre: 'Bons de commande',
          sousTitre: page.estPartielle
              // Le total du serveur est DIT : sans lui, une page pleine se
              // lirait comme « c'est tout », et un acheteur conclurait à
              // l'absence d'une commande qui est à la page suivante.
              ? '${page.elements.length} commande(s) affichée(s) sur '
                    '${page.total} retenue(s) par le filtre.'
              : '${page.total} commande(s) retenue(s) par le filtre.',
          outils: BarreOutilsAchats(
            cle: const Key('outils-commandes'),
            prefixeCle: 'cmd',
            placeholder: 'Fournisseur, n° de commande…',
            controleurRecherche: _recherche,
            onRecherche: (v) =>
                ref.read(rechercheCommandeProvider.notifier).definir(v),
            construireListe: () => _liste(page),
            filtre: SizedBox(
              width: AppLayout.filtreAchats,
              child: DropdownButtonFormField<StatutCommande?>(
                key: const Key('filtre-cmd'),
                initialValue: ref.watch(statutCommandeProvider),
                isExpanded: true,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<StatutCommande?>(
                    child: Text('Tous les statuts'),
                  ),
                  // Les CINQ statuts, y compris les trois qu'on ne peut pas
                  // saisir : on filtre un état constaté, on ne le pose pas.
                  for (final s in StatutCommande.values)
                    DropdownMenuItem<StatutCommande?>(
                      value: s,
                      child: Text(s.libelle),
                    ),
                ],
                onChanged: (s) =>
                    ref.read(statutCommandeProvider.notifier).definir(s),
              ),
            ),
          ),
          corps: page.elements.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Center(
                    child: Text(
                      // Le texte du maître (l.344), au mot.
                      "Aucune commande. Passez par l'onglet Besoins.",
                      key: const Key('commandes-vide'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                )
              // Dix commandes par page (PO, 14/10/2026) ; l'export emporte
              // toutes les lignes reçues (`_liste`), jamais la seule page.
              : ListePaginee<CommandeAchat>(
                  elements: page.elements,
                  prefixeCle: 'commandes-pagination',
                  cleRemiseAZero: (
                    ref.watch(rechercheCommandeProvider),
                    ref.watch(statutCommandeProvider),
                  ),
                  constructeur: (_, tranche) => _table(tranche),
                ),
        ),
        // Le bloc « Ce que cet onglet ne rend pas » qui suivait est RETIRÉ
        // (directive absolue du PO, 14/10/2026). Écarts toujours vrais, nommés
        // ici : pas de colonne « N° » (aucune séquence, l'identifiant réel est
        // affiché) ; pas d'annulation de commande (aucun statut « annulée »,
        // arbitrage Architecte) ; export « Excel » rendu en CSV (RG-19).
      ],
    );
  }

  Widget _table(List<CommandeAchat> commandes) {
    final peutEcrire = ref
        .watch(droitsProvider)
        .peutEcrire(ModuleTatacora.m7Achats);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Référence')),
          DataColumn(label: Text('Fournisseur')),
          DataColumn(label: Text('Date')),
          DataColumn(label: Text('Lignes'), numeric: true),
          DataColumn(label: Text('Montant'), numeric: true),
          DataColumn(label: Text(MessagesReglement.colRegle), numeric: true),
          DataColumn(label: Text(MessagesReglement.colResteDu), numeric: true),
          DataColumn(label: Text('Statut')),
          DataColumn(label: Text('Actions')),
        ],
        rows: [
          for (final c in commandes)
            DataRow(
              cells: [
                DataCell(Text(c.id, key: Key('commande-ref-${c.id}'))),
                DataCell(
                  Text(
                    // Vide quand la relation n'a pas été jointe : on affiche
                    // alors l'identifiant, jamais une raison sociale inventée.
                    c.fournisseurRaisonSociale.isEmpty
                        ? c.fournisseurId
                        : c.fournisseurRaisonSociale,
                    key: Key('commande-fournisseur-${c.id}'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                DataCell(Text(c.dateCommande)),
                DataCell(Text('${c.nombreLignes}')),
                // Le montant du serveur, tel quel : le reformater ferait
                // diverger l'écran du bon de commande.
                DataCell(Text(c.montantTotal)),
                // « Réglé » et « Reste dû » : lus des règlements ACTIFS, jamais
                // soustraits ici (`formatOuTiret`, couleurs de la vue l.261-262).
                DataCell(
                  Text(
                    montantFcfaOuTiret(enCentiemes(c.montantRegle) ?? 0),
                    key: Key('commande-regle-${c.id}'),
                    style: TextStyle(
                      fontWeight: c.montantRegle == '0.00'
                          ? null
                          : FontWeight.w600,
                      color: c.montantRegle == '0.00'
                          ? Ardoise.c400
                          : PaletteMaitre.emeraude600,
                    ),
                  ),
                ),
                DataCell(
                  Text(
                    montantFcfaOuTiret(enCentiemes(c.resteDu) ?? 0),
                    key: Key('commande-reste-${c.id}'),
                    style: TextStyle(
                      fontWeight: c.resteDu == '0.00' ? null : FontWeight.w600,
                      color: c.resteDu == '0.00'
                          ? Ardoise.c400
                          : PaletteMaitre.rouge600,
                    ),
                  ),
                ),
                DataCell(_Statut(commande: c)),
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (c.envoyable)
                        TextButton(
                          key: Key('commande-envoyer-${c.id}'),
                          onPressed: () => _transition(
                            () => ref
                                .read(achatsApiProvider)
                                .envoyerCommande(c.id),
                            'Commande émise. Elle ne peut plus revenir en '
                            'brouillon : un bon parti chez le fournisseur '
                            'ne se dé-envoie pas.',
                          ),
                          child: const Text('Émettre'),
                        ),
                      if (c.receptionnable)
                        TextButton(
                          key: Key('commande-receptionner-${c.id}'),
                          onPressed: () => _receptionner(c),
                          child: const Text('Réceptionner'),
                        ),
                      if (c.cloturable)
                        TextButton(
                          key: Key('commande-cloturer-${c.id}'),
                          onPressed: () => _transition(
                            () => ref
                                .read(achatsApiProvider)
                                .cloturerCommande(c.id),
                            'Commande clôturée.',
                          ),
                          child: const Text('Clôturer'),
                        ),
                      // « Régler » (vue l.268) : le droit d'écriture sur M7 ET
                      // un reste dû positif. Le geste lui-même est refusé par le
                      // serveur sur la même règle ; ce test évite de proposer ce
                      // qui sera refusé, il ne protège rien.
                      if (peutEcrire && (enCentiemes(c.resteDu) ?? 0) > 0)
                        TextButton(
                          key: Key('commande-regler-${c.id}'),
                          onPressed: () =>
                              reglerUneCommande(context, ref, c.id),
                          child: const Text(MessagesReglement.regler),
                        ),
                      TextButton(
                        key: Key('commande-rapprochement-${c.id}'),
                        onPressed: () =>
                            ouvrirRapprochement(context, commande: c),
                        child: const Text('Rapprochement'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// La pastille de statut, aux couleurs du maître (l.57-62).
class _Statut extends StatelessWidget {
  const _Statut({required this.commande});

  final CommandeAchat commande;

  @override
  Widget build(BuildContext context) {
    final (couleur, fond) = switch (commande.statut) {
      StatutCommande.envoyee => (
        AppColors.infoBleuTexte,
        AppColors.infoBleuFond,
      ),
      StatutCommande.receptionneePartiellement => (
        AppColors.gold,
        AppColors.reserveGoldFond,
      ),
      StatutCommande.receptionnee => (AppColors.succes, AppColors.succesFond),
      // `brouillon` et `cloturee` sont gris au maître ; un statut INCONNU l'est
      // aussi, et son code brut s'affiche — jamais un libellé de remplacement,
      // qui donnerait une couleur à un état qu'on ne sait pas lire.
      _ => (AppColors.neutre500, AppColors.neutre100),
    };

    return PastilleAchats(
      cle: Key('commande-statut-${commande.id}'),
      texte: commande.libelleStatut,
      couleur: couleur,
      fond: fond,
    );
  }
}
