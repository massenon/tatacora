// Vue Blade maîtresse (PA-183) : pwa/pos/comptant.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/rbac/garde_acces.dart';
import '../../../core/responsive/breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../restaurant/presentation/widgets/corps_carte_commun.dart'
    show styleContenuCarte;
import '../../caisse/presentation/widgets/barre_session_caisse.dart';
import '../domain/entities/panier.dart';
import '../domain/entities/table_pos.dart';
import '../domain/repositories/panier_repository.dart';
import 'providers_pos.dart';
import 'vocabulaire_pos.dart';
import 'widgets/vue_catalogue.dart';
import 'widgets/vue_salle.dart';
import 'widgets/vue_panier.dart';

/// **POS au comptant** — client de passage, encaissement immédiat.
///
/// ⚠ **Portage d'une PROPOSITION non ratifiée**
/// (`docs/PROPOSITION_MODELE_PANIER_POS.md`, Q1/Q2/Q3). Le porter dans un
/// second client le rend plus difficile à amender ; les trois questions sont
/// isolées derrière des points nommés.
///
/// ## Ce que cet écran ne fait pas, et pourquoi c'est le point
///
/// **Changer de filtre ne vide pas le panier.** Le défaut existait (PA-79) :
/// le sélecteur de catalogue désignait aussi la caisse, si bien qu'un client
/// prenant une bière puis un plat perdait sa première ligne — et l'addition
/// unique qu'il demandait devenait impossible.
///
/// La séparation n'est pas seulement documentaire : le panier vit **en base**
/// sous son propre identifiant, et [rayonAfficheProvider] ne le connaît pas.
/// Le filtre ne pourrait pas l'atteindre même si quelqu'un le voulait.
///
/// **Le poste dit où se trouve l'argent, pas ce qui est vendu.**
class EcranPosComptant extends ConsumerWidget {
  const EcranPosComptant({super.key});

  /// Le poste du panier, **déclaré** et non lu d'une caisse ouverte.
  ///
  /// ⚠ La phrase « `SessionCaisse` n'est pas implémentée (PA-21) » était vraie
  /// jusqu'au 12/10/2026 et ne l'est plus : les sessions de caisse existent sur
  /// ce poste (schéma v17, `SessionsCaisseDao`) et la barre de session ci-dessus
  /// les ouvre et les clôture. Depuis la v18 (D231), le panier au comptant est
  /// rattaché à la session qui l'ENCAISSE (`session_encaissement_id`, écrit à
  /// la clôture) — mais pas à son ouverture : le poste d'un panier est fixé
  /// quand il s'ouvre, avant tout encaissement, et ne vient donc toujours pas
  /// de la session. (La phrase « `paniers_local` ne porte pas de
  /// `session_id` », écrite ici avant le lot 5, est périmée — D282.) Nommé ici
  /// plutôt que dissimulé dans un littéral.
  static const String posteParDefaut = 'Réception';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final peutVendre = ref
        .watch(droitsProvider)
        .peutEcrire(ModuleTatacora.m5Bar);
    final panier = ref.watch(panierCourantProvider).value;
    final large = Breakpoints.de(context) == Palier.desktop;

    // Le vocabulaire du COMPTOIR — `prototype_v2/pages/pos.html`.
    // « Encaisser », « Vider », « Abandonner », « Rechercher un article… ».
    const mots = PointDeVentePos.comptoir;

    final catalogue = VueCatalogue(
      vocabulaire: VocabulairePos.de(mots),
      actif: peutVendre && panier != null && panier.estOuvert,
      onAjouter: (article) async {
        final courant = panier;
        if (courant == null) return;
        try {
          await ref.read(gererPanierProvider).ajouter(courant.id, article);
          rafraichirPaniers(ref);
        } on PrixInconnu catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('$e')));
          }
        }
      },
    );

    final colonnePanier = panier == null || !panier.estOuvert
        ? _AucunPanier(peutVendre: peutVendre, dernier: panier)
        : VuePanier(panier: panier, vocabulaire: VocabulairePos.de(mots));

    // Ouvrir une table : on RETROUVE son panier s'il existe, on n'en cree pas
    // un second. Deux paniers sur une table scinderaient l'addition, et la
    // moitie manquerait au moment d'encaisser.
    Future<void> choisirTable(TablePos table) async {
      final existant = await ref
          .read(tablesPosDaoProvider)
          .panierOuvertDe(table.id);
      if (existant != null) {
        ref.read(panierActifProvider.notifier).definir(existant);
        return;
      }
      if (!peutVendre) return;
      final p = await ref
          .read(gererPanierProvider)
          .ouvrirAuComptant(
            pointVente: posteParDefaut,
            tableId: table.id,
            espace: table.espace.code,
          );
      ref.read(panierActifProvider.notifier).definir(p.id);
      rafraichirPaniers(ref);
    }

    // Le comptoir : on DESELECTIONNE simplement la table. On n'ouvre pas de
    // panier tout seul — un panier vide serait cree a chaque passage sur
    // l'ecran, et la liste s'emplirait de coquilles que personne n'a voulues.
    void choisirComptoir() =>
        ref.read(panierActifProvider.notifier).definir(null);

    final salle = VueSalle(
      tableActive: panier?.estOuvert ?? false ? panier?.tableId : null,
      onChoisirTable: choisirTable,
      onChoisirComptoir: choisirComptoir,
    );

    // Les trois panneaux du maitre (`pos.html:32,51,72`) : la SALLE a
    // `xl:w-[320px]`, le CATALOGUE en `flex-1`, le PANIER a `xl:w-[380px]`.
    // Le maitre les empile en dessous du palier `xl` ; ici la salle passe en
    // premier dans la colonne, parce que c'est le geste qui commence la vente.
    // Séparateurs `border-slate-200` de la vue (l.157 `xl:border-r`, l.318
    // `xl:border-l`) au lieu des diviseurs du thème ; hauteurs empilées en
    // jetons (14/10/2026).
    final panneaux = large
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: LargeursPos.salle,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    border: Border(right: BorderSide(color: Ardoise.c200)),
                  ),
                  child: salle,
                ),
              ),
              Expanded(child: catalogue),
              SizedBox(
                width: LargeursPos.panier,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    border: Border(left: BorderSide(color: Ardoise.c200)),
                  ),
                  child: colonnePanier,
                ),
              ),
            ],
          )
        : Column(
            children: [
              SizedBox(
                height: LargeursPos.salleEmpilee,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: Ardoise.c200)),
                  ),
                  child: salle,
                ),
              ),
              Expanded(child: catalogue),
              SizedBox(
                height: LargeursPos.panierComptantEmpile,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: Ardoise.c200)),
                  ),
                  child: colonnePanier,
                ),
              ),
            ],
          );

    // La BARRE DE SESSION DE CAISSE précède les panneaux, comme dans la vue
    // (`comptant.blade.php` l.74-152) : c'est elle qui ouvre et clôture la
    // caisse. Rien d'autre de cet écran n'a changé (12/10/2026, D219).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const BarreSessionCaisse(),
        Expanded(child: panneaux),
      ],
    );
  }
}

/// Aucun panier ouvert : on propose de l'ouvrir, on n'en ouvre pas un tout seul.
///
/// Ouvrir automatiquement au chargement de l'écran créerait un panier vide à
/// chaque passage, et la liste s'emplirait de coquilles que personne n'a
/// voulues.
class _AucunPanier extends ConsumerWidget {
  const _AucunPanier({required this.peutVendre, this.dernier});

  final bool peutVendre;

  /// Le panier qui vient d'être clôturé ou annulé, s'il y en a un : son état
  /// reste affiché le temps d'annoncer le montant au client.
  final Panier? dernier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final secondaire = styleContenuCarte(
      TaillesContenu.t12,
      couleur: Ardoise.c500,
    );

    // Le panneau Panier SANS panier ouvert, à la forme de la vue (l.318-357,
    // 14/10/2026) : en-tête « Panier · 0 article(s) » sans « Vider » ni
    // « Abandonner » (rien à vider), bande « Aucun panier ouvert », « Panier
    // vide », puis le geste qui ouvre la vente. La vue ouvre le panier du
    // comptoir au premier article ; ce poste l'ouvre par ce bouton — en ouvrir
    // un tout seul à chaque passage emplirait la base de coquilles vides.
    return Container(
      color: AppColors.neutre0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const EnTetePanierComptant(nombreArticles: 0),
          const ContextePanierComptant(ligne: TextesPanierComptant.aucunPanier),
          const Expanded(child: PanierVideComptant()),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: const BoxDecoration(
              color: Ardoise.c50,
              border: Border(top: BorderSide(color: Ardoise.c200)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (dernier != null) ...[
                  Text(
                    key: const Key('pos-comptant-dernier'),
                    dernier!.statut == StatutPanier.cloture
                        ? 'Vente clôturée à ${dernier!.montantCloture} FCFA.'
                        : 'Panier annulé : ${dernier!.motifAnnulation}',
                    textAlign: TextAlign.center,
                    style: secondaire,
                  ),
                  // D3 — l'accès à la pièce reste ouvert après la clôture :
                  // voir le ticket, ou l'émettre si l'émission avait échoué.
                  if (dernier!.statut == StatutPanier.cloture)
                    ActionFacture(panier: dernier!),
                  const SizedBox(height: AppSpacing.xs),
                ],
                // « Nouvelle vente au comptoir » — libellé de la consigne du
                // PO (NOUVELLE_INSTRUCTION1 §5, cas A), bouton sombre à icône
                // de caddie, au gabarit d'« Encaisser ».
                FilledButton.icon(
                  key: const Key('pos-comptant-ouvrir'),
                  style: styleBoutonEncaisser,
                  icon: const Icon(
                    Icons.add_shopping_cart_outlined,
                    size: AppLayout.iconeChamp,
                  ),
                  label: const Text('Nouvelle vente au comptoir'),
                  onPressed: peutVendre
                      ? () async {
                          final p = await ref
                              .read(gererPanierProvider)
                              .ouvrirAuComptant(
                                pointVente: EcranPosComptant.posteParDefaut,
                              );
                          ref.read(panierActifProvider.notifier).definir(p.id);
                          rafraichirPaniers(ref);
                        }
                      : null,
                ),
                if (!peutVendre) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Votre rôle ne permet pas d’encaisser.',
                    textAlign: TextAlign.center,
                    style: secondaire,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
