import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/rbac/garde_acces.dart';
import '../../../../core/impression/entete_parametree.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../domain/entities/piece_facturation.dart';
import '../../impression/facture_a4.dart';
import '../../impression/ticket_facture.dart';
import '../ecran_facturation.dart';
import '../providers_facturation.dart';

/// L'impression, exposée comme une **action injectable**.
///
/// ## Pourquoi un provider plutôt qu'un appel direct à `Printing`
///
/// Deux raisons, et la seconde est la vraie.
///
/// 1. Un test de widget n'a pas de greffon natif : appeler `Printing` y
///    lèverait, et l'écran deviendrait intestable.
/// 2. Surtout, **il doit exister un endroit unique où l'impression est
///    déclenchée**. Un `Printing.layoutPdf` recopié dans chaque écran serait
///    un chemin de plus à ne jamais exécuter, et c'est la famille de défauts
///    que ce dépôt a passé deux jours à démonter (PA-63).
///
/// L'implémentation par défaut ouvre la boîte de dialogue d'impression du
/// système avec le document **déjà composé au format rouleau 80 mm** — c'est
/// `TicketCompose.pdf()` qui décide du format, pas le pilote.
final imprimerTicketProvider = Provider<Future<void> Function(TicketCompose)>(
  (ref) => (ticket) async {
    await Printing.layoutPdf(
      onLayout: (_) => ticket.pdf(),
      name: ticket.piece.numero,
      format: formatRouleau80mm,
    );
  },
);

/// L'impression de la **facture A4**, exposée de la même façon.
///
/// Un second provider et non un paramètre du premier : les deux documents ont
/// des formats différents, et `Printing.layoutPdf` doit recevoir celui du
/// document qu'on lui donne. Un format hérité de l'autre papier sortirait
/// tronqué ou minuscule — c'est précisément la faute que `formatRouleau80mm`
/// existe pour éviter.
final imprimerFactureA4Provider =
    Provider<Future<void> Function(FactureA4Composee)>(
      (ref) => (facture) async {
        await Printing.layoutPdf(
          onLayout: (_) => facture.pdf(),
          name: facture.piece.numero,
          format: formatFactureA4,
        );
      },
    );

/// Le ticket, à l'écran puis au papier.
///
/// ## Ce qui est affiché est exactement ce qui sera imprimé
///
/// Les deux rendus partent du **même** [TicketCompose], donc des mêmes textes
/// déjà normalisés. Un aperçu construit à part finirait par diverger du
/// document, et c'est l'aperçu qu'on croirait.
class VueTicket extends ConsumerWidget {
  const VueTicket({required this.piece, super.key});

  final PieceFacturation piece;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final ticket = TicketFacture.composer(piece);
    final auteur = ref.watch(auteurEditionProvider);
    final peutAnnuler = ref
        .watch(droitsProvider)
        .niveau(ModuleTatacora.m2Facturation)
        .peutEcrire;

    return AlertDialog(
      key: const Key('facturation-ticket'),
      title: Text(piece.estAvoir ? 'Avoir ${piece.numero}' : piece.numero),
      content: SizedBox(
        width: 320,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Rendu monospace : c'est ainsi que sort une thermique, et voir
              // l'alignement réel évite de découvrir sur le papier qu'un
              // libellé long repousse le montant hors de la bande.
              Container(
                padding: const EdgeInsets.all(AppSpacing.xs),
                decoration: BoxDecoration(
                  color: AppColors.neutre100,
                  border: Border.all(color: AppColors.neutre300),
                ),
                child: Text(
                  key: const Key('facturation-ticket-texte'),
                  ticket.texteBrut,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: Tailles.t11,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('facturation-fermer-ticket'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fermer'),
        ),
        // L'annulation par avoir vit ICI depuis le 21/08/2026 : le tableau du
        // maitre ne porte aucune colonne d'action, et lui en ajouter une aurait
        // ete une reinterpretation. La ligne ouvre le ticket, le ticket porte
        // les gestes — c'est le meme endroit que l'impression et la facture A4.
        //
        // **Une piece deja annulee ne se rannule pas**, et un AVOIR encore
        // moins : annuler un avoir produirait un avoir d'avoir, c'est-a-dire
        // une facture positive que personne n'a emise.
        // **Le droit d'ECRITURE sur M2 est exige**, et c'est le premier des
        // trois niveaux de RG-16 : masquage a l'interface, garde au serveur,
        // filtrage en base. Il vivait sur la ligne du tableau avant le
        // 21/08/2026 ; le deplacement l'a un instant PERDU, et un compte en
        // lecture seule aurait pu contre-passer une facture. Le test
        // « sans droit d'ecriture sur M2, aucune annulation possible » l'a
        // rattrape — une violation RBAC est bloquante sans exception.
        if (peutAnnuler && !piece.estAnnulee && piece.avoirDe == null)
          TextButton(
            key: const Key('facturation-annuler-avoir'),
            onPressed: () async {
              // **On ne ferme PAS le ticket d'abord**, et c'est le point que
              // deux essais ont manque : `ref` meurt avec le widget qui l'a
              // fourni. Apres un `pop()`, `ref.read(...)` leve — et
              // l'exception, avalee par le `catch` d'`emettreUnAvoir`,
              // faisait croire a une annulation qui n'avait pas eu lieu.
              // Aucun avoir n'etait emis, et rien ne le disait.
              //
              // La confirmation s'ouvre donc PAR-DESSUS le ticket ; celui-ci
              // ne se ferme qu'une fois le travail fait.
              final emis = await emettreUnAvoir(context, piece);
              // Le ticket ne se ferme que si l'avoir est émis : renoncer dans
              // la modale laisse le ticket où il était.
              if (emis && context.mounted) Navigator.of(context).pop();
            },
            child: Text(
              // `facturation_pwa.avoir_action` : le mot du bouton de la vue.
              'Avoir',
              style: TextStyle(color: AppColors.erreur),
            ),
          ),
        // ⚠ **Deux papiers, deux boutons** — c'est la réponse du dépôt à la
        // question du Product Owner (« ticket ou facture A4 ? ») :
        // `05_MODULE_SPECIFICATIONS.md` §M14 en fait deux documents distincts,
        // de la MÊME pièce. Le numéro et le registre sont uniques ; seul le
        // papier change.
        OutlinedButton.icon(
          key: const Key('facturation-facture-a4'),
          icon: const Icon(Icons.description_outlined),
          label: const Text('Facture A4'),
          // Sans session, pas d'édition : une facture signée par personne — ou
          // pire, par un « Administrateur » en dur — est la non-conformité n°3
          // de RESPECT_TABLEAU_RAPPORT §4.
          onPressed: auteur == null
              ? null
              : () => _imprimerFactureA4(context, ref, auteur),
        ),
        FilledButton.icon(
          key: const Key('facturation-imprimer'),
          icon: const Icon(Icons.print_outlined),
          label: const Text('Ticket 80 mm'),
          onPressed: () async {
            try {
              await ref.read(imprimerTicketProvider)(ticket);
            } on Object catch (e) {
              // Une panne d'imprimante ne doit pas faire perdre la pièce : elle
              // est déjà en base, numérotée. On le dit, on ne remonte pas
              // l'exception jusqu'à l'écran de vente.
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Impression impossible : $e. La pièce '
                      '${piece.numero} reste enregistrée et réimprimable.',
                    ),
                  ),
                );
              }
            }
          },
        ),
      ],
      actionsOverflowAlignment: OverflowBarAlignment.end,
      // La mention de certification est déjà DANS le ticket, dérivée de la
      // pièce. La répéter ici avec un autre libellé créerait deux vérités.
      contentTextStyle: theme.textTheme.bodySmall,
    );
  }

  /// Compose puis imprime la facture A4 de **cette même pièce**.
  ///
  /// Le logo est chargé depuis le paquet applicatif, jamais depuis le réseau
  /// (`logoEtablissementProvider`), et son absence ne bloque rien : une facture
  /// sans logo reste une facture, une facture qui attend Internet n'en est plus
  /// une.
  Future<void> _imprimerFactureA4(
    BuildContext context,
    WidgetRef ref,
    AuteurEdition auteur,
  ) async {
    try {
      final logo = await ref.read(logoEtablissementProvider.future);
      // L'en-tête est lu des paramètres du poste (directive du PO du
      // 14/10/2026), le logo y est greffé.
      final entete = await ref.read(lireEnteteEtablissementProvider)();
      final facture = FactureA4.composer(
        piece,
        auteur: auteur,
        dateEdition: DateTime.now(),
        entete: entete.avecLogo(logo),
      );
      await ref.read(imprimerFactureA4Provider)(facture);
    } on Object catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Édition impossible : $e. La pièce ${piece.numero} reste '
              'enregistrée et rééditable.',
            ),
          ),
        );
      }
    }
  }
}

/// « Facture A4 » depuis la LIGNE du registre (`imprimerFacture` de la vue,
/// bouton par ligne) : même document que celui du ticket, même garde — sans
/// session, pas d'édition, et on le DIT plutôt que de rester muet.
Future<void> imprimerLaFactureA4Depuis(
  BuildContext context,
  WidgetRef ref,
  PieceFacturation piece,
) async {
  final auteur = ref.read(auteurEditionProvider);
  if (auteur == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Aucune session ouverte : une facture ne s\'édite pas sans '
          'auteur.',
        ),
      ),
    );
    return;
  }
  await VueTicket(piece: piece)._imprimerFactureA4(context, ref, auteur);
}
