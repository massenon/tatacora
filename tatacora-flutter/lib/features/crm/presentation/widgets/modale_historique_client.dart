// Vue Blade maîtresse (PA-183) : pwa/crm/clients-creances.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../shared_widgets/toast_export.dart';
import '../../../caisse/domain/montant_caisse.dart' show formaterCentimesEnFcfa;
import '../../../facturation/presentation/providers_paiements.dart'
    show horlogeCreancesProvider;
import '../../../restaurant/presentation/widgets/coquille_modale_restaurant.dart';
import '../../domain/historique_client.dart';
import '../../impression/releve_client.dart';
import '../providers_crm.dart';
import '../../../../core/format/formats.dart' show formaterDate;

/// Ouvre la modale **« Historique d'un client »** — `ouvrirHistoriqueClient`
/// de la vue (l.726-768), depuis « Historique » (liste des clients) et
/// « Détail » (suivi des dettes).
Future<void> ouvrirHistoriqueClient(
  BuildContext context, {
  required String clientId,
  required String clientNom,
}) => showDialog<void>(
  context: context,
  builder: (_) =>
      ModaleHistoriqueClient(clientId: clientId, clientNom: clientNom),
);

/// La modale de lecture : le nom du client en titre, un tableau à cinq colonnes,
/// « Imprimer PDF » et « Fermer ».
///
/// ## Les cinq colonnes de la vue
///
/// `Date · Type · Libellé · Détail · Montant`. Le libellé est le numéro de la
/// pièce réglée, le détail le mode de règlement. Un client sans mouvement le
/// DIT : « Aucun mouvement pour ce client. »
///
/// ## Les relances y figurent
///
/// La vue mêle aux encaissements les relances du client : ici aussi (type
/// « Relance », canal en détail, montant réclamé ce jour-là). Un client sans
/// mouvement le DIT.
///
/// ## « Imprimer PDF »
///
/// Le relevé de compte client ([ReleveClient]) : un document REMIS AU CLIENT, que
/// la vue télécharge (`streamDownload`) et que ce poste enregistre par la fenêtre
/// « Enregistrer sous ». Il porte les mêmes lignes que l'écran, et la même
/// mention.
class ModaleHistoriqueClient extends ConsumerWidget {
  const ModaleHistoriqueClient({
    required this.clientId,
    required this.clientNom,
    super.key,
  });

  final String clientId;
  final String clientNom;

  static const _parts = [140, 150, 200, 190, 160];
  static const _titres = ['Date', 'Type', 'Libellé', 'Détail', 'Montant'];

  static const TextStyle _celluleBase = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: Tailles.t13,
    color: Ardoise.c700,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historique = ref.watch(historiqueClientProvider(clientId));

    return CoquilleModaleRestaurant(
      cle: const Key('modale-historique-client'),
      titre: clientNom,
      largeur: AppLayout.modaleHistoriqueClientCrm,
      corps: historique.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(AppSpacing.xl),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Text('$e'),
        data: (mouvements) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                border: Border.all(color: Ardoise.c200),
                borderRadius: BorderRadius.circular(AppRadius.roundedXl),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _rangee(
                    fond: AppColors.navy,
                    cellules: [
                      for (final (i, t) in _titres.indexed)
                        Text(
                          t.toUpperCase(),
                          textAlign: i == 4 ? TextAlign.right : TextAlign.left,
                          style: TextStyle(
                            fontFamily: AppTextStyles.police,
                            fontSize: Tailles.t11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                            color: AppColors.neutre0.withValues(alpha: 0.90),
                          ),
                        ),
                    ],
                  ),
                  if (mouvements.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                      child: Text(
                        ReleveClient.aucunMouvement,
                        key: Key('historique-client-vide'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: AppTextStyles.police,
                          fontSize: Tailles.t13,
                          color: Ardoise.c400,
                        ),
                      ),
                    )
                  else
                    for (final m in mouvements) _ligne(m),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        OutlinedButton(
          key: const Key('historique-client-imprimer'),
          onPressed: historique.hasValue
              ? () => _imprimer(context, ref, historique.requireValue)
              : null,
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Ardoise.c300),
            foregroundColor: AppColors.anthracite,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.roundedLg),
            ),
          ),
          child: const Text(
            'Imprimer PDF',
            style: TextStyle(
              fontFamily: AppTextStyles.police,
              fontSize: Tailles.t13,
            ),
          ),
        ),
        FilledButton(
          key: const Key('historique-client-fermer'),
          onPressed: () => Navigator.of(context).pop(),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.navy,
            foregroundColor: AppColors.neutre0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.roundedLg),
            ),
          ),
          child: const Text(
            'Fermer',
            style: TextStyle(
              fontFamily: AppTextStyles.police,
              fontSize: Tailles.t13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _rangee({required List<Widget> cellules, Color? fond}) => Container(
    color: fond,
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xsPlus),
    child: Row(
      children: [
        for (var i = 0; i < cellules.length; i++)
          Expanded(
            flex: _parts[i],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: Align(
                alignment: i == 4
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: cellules[i],
              ),
            ),
          ),
      ],
    ),
  );

  Widget _ligne(MouvementClient m) {
    // `bg-emerald-50 text-emerald-700` pour un encaissement, `bg-amber-50
    // text-amber-700` pour une relance ; le montant d'une relance est en
    // `text-slate-700` (c'est une somme RÉCLAMÉE, pas reçue).
    final relance = m.type == typeRelance;
    return DecoratedBox(
      key: Key(
        'historique-client-ligne-${m.date.microsecondsSinceEpoch}-${m.libelle}',
      ),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Ardoise.c100)),
      ),
      child: _rangee(
        cellules: [
          Text(
            formaterDate(m.date),
            style: _celluleBase.copyWith(color: Ardoise.c600),
          ),
          // La pastille du type (`text-[10px] px-1.5 py-0.5 rounded`).
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xxs,
              vertical: AppSpacing.demi,
            ),
            decoration: BoxDecoration(
              color: relance ? PaletteMaitre.ambre50 : PaletteMaitre.emeraude50,
              borderRadius: BorderRadius.circular(AppRadius.rounded),
            ),
            child: Text(
              m.type,
              style: TextStyle(
                fontFamily: AppTextStyles.police,
                fontSize: Tailles.t10,
                color: relance
                    ? PaletteMaitre.ambre700
                    : PaletteMaitre.emeraude700,
              ),
            ),
          ),
          Text(m.libelle, style: _celluleBase),
          Text(m.detail, style: _celluleBase.copyWith(color: Ardoise.c600)),
          Text(
            formaterCentimesEnFcfa(m.montantCentimes),
            style: _celluleBase.copyWith(
              fontWeight: FontWeight.w600,
              color: relance ? Ardoise.c700 : PaletteMaitre.emeraude600,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _imprimer(
    BuildContext context,
    WidgetRef ref,
    List<MouvementClient> mouvements,
  ) async {
    final releve = ReleveClient(
      clientNom: clientNom,
      mouvements: [
        for (final m in mouvements)
          (date: m.date, type: m.type, montantCentimes: m.montantCentimes),
      ],
      editeLe: ref.read(horlogeCreancesProvider)(),
    );
    await executerExport(
      context,
      () => ref.read(exporterReleveClientProvider)(releve),
      cleSucces: const Key('historique-client-enregistre'),
    );
  }
}
