// Vue Blade maîtresse (PA-183) : pwa/achats/approvisionnement.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/format/formats.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../caisse/domain/montant_caisse.dart' show formaterCentimesEnFcfa;
import '../../../restaurant/presentation/widgets/corps_carte_commun.dart'
    show styleContenuCarte;
import '../../../restaurant/presentation/widgets/tableau_restaurant.dart';
import '../../data/achats_api.dart';
import '../../domain/decimal_texte.dart';
import '../../domain/dettes_fournisseurs.dart';
import '../../domain/entities/commande_achat.dart';
import '../../domain/messages_reglement.dart';
import '../providers_achats.dart';
import 'coquille_achats.dart';
import 'composants_crud_achats.dart';

/// L'onglet **« Dettes fournisseurs »** — `approvisionnement.blade.php`
/// l.337-410.
///
/// ## Il est CHIFFRÉ depuis le règlement fournisseur (D66, 12/10/2026)
///
/// Jusqu'au 12/10/2026 cet onglet disait « Aucun montant n'est affiché ici, et
/// ce n'est pas zéro » : le poste n'avait aucun règlement, donc aucun reste dû à
/// calculer. Le règlement est désormais un vrai geste (`ReglementsFournisseurDao`,
/// pièce comptable dans la même transaction) : « Réglé » et « Reste dû » viennent
/// des règlements ACTIFS, et le motif d'absence est retiré avec ce qu'il
/// justifiait.
///
/// ## Ce que la vue montre, dans son ordre
///
/// Un cadre blanc : l'en-tête (titre, phrase de portée, « Total dû » à droite),
/// puis UN tableau à en-tête navy de six colonnes — N° commande, Date,
/// Ancienneté, Montant, Réglé, Reste dû — avec, par fournisseur, une bande grise
/// portant son nom et son total dû. La liste ne garde que les commandes NON
/// clôturées (`dettes()` : ni `receptionnee` ni `cloturee`) ; une commande soldée
/// y reste et affiche « — » en Reste dû. Vide : « Aucune dette fournisseur.
/// Toutes les commandes sont soldées. »
///
/// ## Le « Total dû » de l'en-tête n'est pas la somme de ce qui est listé (D262)
///
/// Il somme TOUTES les commandes de la liste filtrée, closes comprises (voir
/// `composerIndicateursDettes`). Répliqué, consigné, jamais corrigé ici.
///
/// ## L'ancienneté mesure l'âge du BON DE COMMANDE
///
/// Jamais le retard d'un paiement : la phrase de portée le dit.
class VueDettes extends ConsumerWidget {
  const VueDettes({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resultat = ref.watch(commandesProvider(null));

    return switch (resultat) {
      AsyncData(:final value) => switch (value) {
        AchatsRecu(:final donnees) => _Corps(
          commandes: donnees.elements,
          maintenant: ref.watch(horlogeApproProvider)(),
        ),
        AchatsRefuse(:final motif) => NoteAchats(
          cle: const Key('dettes-refus'),
          texte: motif,
        ),
        // Jamais produite (la base est locale) ; le type la garde.
        AchatsInjoignable() => const NoteAchats(
          cle: Key('dettes-hors-ligne'),
          texte:
              'La base du poste n’a pas répondu : aucune dette n’est '
              'affichée, plutôt qu’un reste dû d’hier.',
        ),
      },
      AsyncError(:final error) => NoteAchats(
        cle: const Key('dettes-erreur'),
        texte: '$error',
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

class _Corps extends StatelessWidget {
  const _Corps({required this.commandes, required this.maintenant});

  final List<CommandeAchat> commandes;
  final DateTime maintenant;

  static int _centimes(String montant) => enCentiemes(montant) ?? 0;

  @override
  Widget build(BuildContext context) {
    final groupes = composerDettes(commandes);
    final indicateurs = composerIndicateursDettes(commandes);

    // Les lignes du tableau, bandes de fournisseur comprises, et la décoration de
    // chacune : la bande est `bg-slate-50`.
    final lignes = <List<Widget>>[];
    final decorations = <BoxDecoration?>[];
    for (final g in groupes) {
      lignes.add([
        Text(
          g.fournisseur,
          key: Key('dette-groupe-${g.fournisseurId}'),
          style: styleContenuCarte(
            TaillesContenu.t13,
            poids: FontWeight.bold,
            couleur: AppColors.navy,
          ),
        ),
        const SizedBox.shrink(),
        const SizedBox.shrink(),
        const SizedBox.shrink(),
        const SizedBox.shrink(),
        Text(
          formaterCentimesEnFcfa(g.totalCentimes),
          key: Key('dette-groupe-total-${g.fournisseurId}'),
          style: styleContenuCarte(
            TaillesContenu.t13,
            poids: FontWeight.bold,
            couleur: PaletteMaitre.rouge600,
          ),
        ),
      ]);
      decorations.add(const BoxDecoration(color: Ardoise.c50));

      for (final c in g.commandes) {
        final jours = joursAnciennete(c.dateCommande, maintenant);
        final regle = _centimes(c.montantRegle);
        final reste = _centimes(c.resteDu);
        lignes.add([
          Text(
            c.id,
            key: Key('dette-commande-${c.id}'),
            style: const TextStyle(
              fontFamily: AppTextStyles.policeMonospace,
              fontSize: TaillesContenu.t12,
              height: AppLayout.interligneContenu,
            ),
          ),
          Text(
            _date(c.dateCommande),
            style: styleContenuCarte(TaillesContenu.t13, couleur: Ardoise.c500),
          ),
          // L'ancienneté conditionne la relance au maître : au-delà de 60 jours,
          // une dette fournisseur devient un sujet de trésorerie.
          Text(
            MessagesReglement.jours(jours),
            key: Key('dette-anciennete-${c.id}'),
            style: styleContenuCarte(
              TaillesContenu.t13,
              poids: jours > 60 ? FontWeight.bold : null,
              couleur: jours > 60
                  ? PaletteMaitre.rouge600
                  : (jours > 30 ? PaletteMaitre.ambre600 : Ardoise.c400),
            ),
          ),
          Text(
            formaterCentimesEnFcfa(_centimes(c.montantTotal)),
            key: Key('dette-montant-${c.id}'),
            style: styleContenuCarte(TaillesContenu.t13),
          ),
          Text(
            montantFcfaOuTiret(regle),
            key: Key('dette-regle-${c.id}'),
            style: styleContenuCarte(
              TaillesContenu.t13,
              couleur: c.montantRegle == '0.00'
                  ? Ardoise.c400
                  : PaletteMaitre.emeraude600,
            ),
          ),
          Text(
            montantFcfaOuTiret(reste),
            key: Key('dette-reste-${c.id}'),
            style: styleContenuCarte(
              TaillesContenu.t13,
              poids: FontWeight.bold,
              couleur: c.resteDu == '0.00'
                  ? Ardoise.c400
                  : PaletteMaitre.rouge600,
            ),
          ),
        ]);
        decorations.add(null);
      }
    }

    final total = indicateurs.totalDuCentimes;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.neutre0,
        borderRadius: BorderRadius.circular(AppRadius.roundedXl),
        border: Border.all(color: Ardoise.c200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // `px-4 py-3 border-b border-slate-200 flex flex-wrap items-center
          // justify-between gap-2` (l.341).
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Ardoise.c200)),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      MessagesReglement.dettesTitre,
                      style: styleContenuCarte(
                        TaillesContenu.t13,
                        poids: FontWeight.bold,
                        couleur: AppColors.navy,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.demi), // mt-0.5
                    Text(
                      MessagesReglement.dettesPortee,
                      style: styleContenuCarte(
                        TaillesContenu.t11,
                        couleur: Ardoise.c400,
                      ),
                    ),
                  ],
                ),
                Text.rich(
                  TextSpan(
                    style: styleContenuCarte(TaillesContenu.t13),
                    children: [
                      const TextSpan(text: '${MessagesReglement.totalDu} '),
                      TextSpan(
                        text: montantFcfaOuTiret(total),
                        style: styleContenuCarte(
                          TaillesContenu.t15,
                          poids: FontWeight.bold,
                          couleur: total > 0
                              ? PaletteMaitre.rouge600
                              : Ardoise.c400,
                        ),
                      ),
                    ],
                  ),
                  key: const Key('dettes-total-du'),
                ),
              ],
            ),
          ),
          TableauRestaurant(
            gabarit: gabaritCrudAchats,
            pleineLargeur: true,
            repartitionProportionnelle: true,
            // L'en-tête vit HORS de la boucle des groupes : posé à l'intérieur, il
            // disparaissait dès qu'aucune commande n'était due — exactement quand
            // on ouvre l'écran pour la première fois (vue l.358-364).
            videSousEntete: true,
            colonnes: const [
              ColonneRestaurant(MessagesReglement.colNumeroCommande),
              ColonneRestaurant('Date'),
              ColonneRestaurant(MessagesReglement.colAnciennete),
              ColonneRestaurant('Montant', aDroite: true),
              ColonneRestaurant(MessagesReglement.colRegle, aDroite: true),
              ColonneRestaurant(MessagesReglement.colResteDu, aDroite: true),
            ],
            lignes: lignes,
            decorationsLignes: decorations,
            vide: const EtatVideTableauAchats(
              titre: MessagesReglement.dettesVide,
            ),
          ),
        ],
      ),
    );
  }

  /// `d/m/Y` de la vue. Une date illisible reste telle que le serveur l'a
  /// rendue : la reformater en inventerait une.
  static String _date(String brut) {
    final d = DateTime.tryParse(brut);
    return d == null ? brut : formaterDate(d);
  }
}
