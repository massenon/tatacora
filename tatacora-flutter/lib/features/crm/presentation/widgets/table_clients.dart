import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../shared_widgets/tableau_tatacora.dart' show PastilleStatut;
import '../../../achats/presentation/widgets/composants_crud_achats.dart'
    show BoutonLigneAchats;
import '../../../caisse/domain/montant_caisse.dart' show formaterCentimesEnFcfa;
import '../../domain/entities/registre_clients.dart';

/// Le tableau de la vue — `pwa/crm/clients-creances.blade.php`, onglet « Liste des
/// clients ».
///
/// ## Les colonnes de la vue, dans son ordre
///
/// `Client · Téléphone · Type · Solde dû · Pièces · Ancienneté` puis la colonne
/// d'actions. Depuis le lot 5 (12/10/2026) le tableau porte EXACTEMENT ces
/// colonnes : les deux colonnes « Séjours » et « Consommations » qu'il posait à
/// la place de « Ancienneté » et des actions (PA-112) décomposaient une autre
/// grandeur que le solde du serveur, et sont retirées avec elle (voir
/// `LigneClient`).
///
/// ## La colonne d'actions
///
/// La vue pose « Historique », « Recouvrement » et « Supprimer » (l'archivage
/// d'un client). « Historique » ouvre la modale du relevé du client
/// (`ModaleHistoriqueClient`, toujours offerte : lire n'écrit rien) ;
/// « Recouvrement » ouvre la modale d'encaissement et n'existe que si le client
/// doit quelque chose ET que le rôle écrit sur M3 et M2 — la condition de la vue
/// (`$ligne->solde !== '0.00' && $peutEncaisser`).
///
/// ## L'archivage (21/10/2026)
///
/// Un client ARCHIVÉ reste dans la liste, marqué « Archivé » : le masquer le
/// rendrait indiscernable d'une fiche inexistante. Sa ligne offre « Restaurer »
/// (à qui écrit sur M3 : fermer la bascule ne doit jamais l'enfermer aux
/// archives) ; un client actif offre « Supprimer » — qui ARCHIVE — et une case
/// de sélection, tous deux à qui `peutArchiver` seulement (la règle UNIQUE de
/// `regle_archivage.dart`, REÇUE : le tableau ne la recalcule jamais).
///
/// - **Ligne « Aucune fiche CRM — à créer »** : le maître réunit les noms des
///   clients et ceux portés par les créances, parce que ses notes de chambre
///   sont au nom d'une table. Ici, `reservations.clientId` est une **vraie clé
///   étrangère** depuis PA-116 : un débiteur sans fiche ne peut pas exister.
class TableClients extends StatelessWidget {
  const TableClients({
    super.key,
    required this.lignes,
    required this.maintenant,
    this.peutEncaisser = false,
    this.peutArchiver = false,
    this.peutRestaurer = false,
    this.selection = const {},
    this.onBasculerSelection,
    this.onSupprimer,
    this.onRestaurer,
    this.onRecouvrement,
    this.onHistorique,
  });

  final List<LigneClient> lignes;

  /// L'instant de référence de l'ancienneté (`diffInDays(now())`) — injecté : un
  /// test qui lit l'horloge réelle change de résultat tous les jours.
  final DateTime maintenant;

  /// `$peutEncaisser` de la vue : le droit d'écrire sur M3 ET sur M2.
  final bool peutEncaisser;

  /// `$peutArchiver` de la vue : la case de sélection et « Supprimer ».
  final bool peutArchiver;

  /// `$peutEcrireClient` de la vue : « Restaurer » une fiche archivée.
  final bool peutRestaurer;

  /// Les clients cochés.
  final Set<String> selection;

  /// Cocher ou décocher la case d'une ligne.
  final void Function(LigneClient ligne)? onBasculerSelection;

  /// « Supprimer » d'une ligne : ouvre la confirmation d'ARCHIVAGE.
  final void Function(LigneClient ligne)? onSupprimer;

  /// « Restaurer » d'une ligne archivée.
  final void Function(LigneClient ligne)? onRestaurer;

  /// Le geste « Recouvrement » d'une ligne.
  final void Function(LigneClient ligne)? onRecouvrement;

  /// Le geste « Historique » d'une ligne (`ouvrirHistoriqueClient`).
  final void Function(LigneClient ligne)? onHistorique;

  /// Les colonnes, dans l'ordre de la vue. La dernière, vide, porte les actions.
  /// Les parts sont les largeurs relevées dans le navigateur
  /// (`<table class="w-full">`, 1 055 px) : la largeur de colonne vient de son
  /// contenu, pas d'une règle qu'on pourrait relire.
  static const _titres = [
    'Client',
    'Téléphone',
    'Type',
    'Solde dû',
    'Pièces',
    'Ancienneté',
    '',
  ];
  static const _parts = [2000, 1595, 1146, 1080, 858, 1300, 2571];
  static const _aDroite = {
    'Téléphone',
    'Type',
    'Solde dû',
    'Pièces',
    'Ancienneté',
    '',
  };

  @override
  Widget build(BuildContext context) {
    final droite = [for (final t in _titres) _aDroite.contains(t)];

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.neutre0,
        borderRadius: BorderRadius.circular(AppRadius.roundedXl),
        border: Border.all(color: AppColors.neutre200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: AppColors.navy,
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xsPlus),
            child: _Rangee(
              cellules: [
                for (final t in _titres)
                  Text(
                    t.toUpperCase(),
                    style: _style(
                      TaillesContenu.t11,
                      poids: FontWeight.w600,
                      couleur: AppColors.neutre0.withValues(alpha: 0.90),
                      espacement: 0.5,
                    ),
                  ),
              ],
              aDroite: droite,
            ),
          ),
          if (lignes.isEmpty)
            // Un écran qui ne rend jamais rien passe pour cassé (leçon PA-90).
            Container(
              key: const Key('clients-registre-vide'),
              padding: const EdgeInsets.all(AppSpacingLarge.p10),
              alignment: Alignment.center,
              child: Text(
                'Aucun client ne correspond à ces critères.',
                style: _style(TaillesContenu.t13, couleur: AppColors.neutre400),
              ),
            )
          else
            for (final l in lignes)
              Container(
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: AppColors.neutre100)),
                ),
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: _Rangee(
                  cellules: [
                    _Nom(
                      ligne: l,
                      avecCase: peutArchiver && l.client.actif,
                      cochee: selection.contains(l.client.id),
                      onBasculer: onBasculerSelection == null
                          ? null
                          : () => onBasculerSelection!(l),
                    ),
                    Text(l.client.telephone, style: _style(TaillesContenu.t13)),
                    Text(
                      l.client.type.libelle,
                      style: _style(TaillesContenu.t13),
                    ),
                    Text(
                      key: Key('clients-solde-${l.client.id}'),
                      _montant(l.soldeCentimes),
                      style: _style(
                        TaillesContenu.t13,
                        poids: FontWeight.w700,
                        couleur: l.estDebiteur
                            ? AppColors.erreur
                            : AppColors.neutre500,
                      ),
                    ),
                    Text(
                      l.nbPieces == 0 ? '—' : '${l.nbPieces}',
                      style: _style(TaillesContenu.t13),
                    ),
                    _Anciennete(jours: l.ancienneteJours(maintenant), ligne: l),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: AppSpacing.unit,
                      children: [
                        if (onHistorique != null)
                          _BoutonHistorique(
                            cle: Key('clients-historique-${l.client.id}'),
                            onTap: () => onHistorique!(l),
                          ),
                        if (l.estDebiteur &&
                            peutEncaisser &&
                            onRecouvrement != null)
                          _BoutonRecouvrement(
                            cle: Key('clients-recouvrement-${l.client.id}'),
                            onTap: () => onRecouvrement!(l),
                          ),
                        // « Supprimer » du maître, rendu comme ARCHIVAGE : le
                        // mot du bouton est celui que le client a validé, le
                        // geste pose `actif = false`.
                        if (!l.client.actif) ...[
                          if (peutRestaurer && onRestaurer != null)
                            BoutonLigneAchats(
                              cle: Key('clients-restaurer-${l.client.id}'),
                              libelle: 'Restaurer',
                              onTap: () => onRestaurer!(l),
                            ),
                        ] else if (peutArchiver && onSupprimer != null)
                          BoutonLigneAchats(
                            cle: Key('clients-supprimer-${l.client.id}'),
                            libelle: 'Supprimer',
                            danger: true,
                            onTap: () => onSupprimer!(l),
                          ),
                      ],
                    ),
                  ],
                  aDroite: droite,
                ),
              ),
        ],
      ),
    );
  }

  static TextStyle _style(
    double taille, {
    FontWeight? poids,
    Color? couleur,
    double? espacement,
  }) => TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: taille,
    fontWeight: poids,
    color: couleur ?? AppColors.neutre700,
    height: 1.5,
    letterSpacing: espacement,
  );

  /// Le tiret de la vue : un zéro se lit comme un montant calculé à zéro, le
  /// tiret dit qu'il n'y a rien à devoir (`MontantFcfa::TIRET`).
  static String _montant(int centimes) =>
      centimes > 0 ? formaterCentimesEnFcfa(centimes) : '—';
}

/// L'ancienneté de la plus ancienne facture impayée : « 45 j », rouge au-delà de
/// 90 jours, ambre en deçà ; « — » quand le client ne doit rien (jamais un zéro).
class _Anciennete extends StatelessWidget {
  const _Anciennete({required this.jours, required this.ligne});

  final int? jours;
  final LigneClient ligne;

  @override
  Widget build(BuildContext context) {
    final j = jours;
    final texte = j == null ? '—' : '$j j';
    final couleur = j == null
        ? Ardoise.c300
        : (j > 90 ? PaletteMaitre.rouge600 : PaletteMaitre.ambre600);

    return Text(
      texte,
      key: Key('clients-anciennete-${ligne.client.id}'),
      style: TableClients._style(
        TaillesContenu.t13,
        poids: j != null && j > 90 ? FontWeight.w600 : null,
        couleur: couleur,
      ),
    );
  }
}

/// `text-[12px] px-2.5 py-1 rounded-lg border border-slate-300 hover:bg-white` :
/// « Historique » — le bouton de lecture de la ligne.
class _BoutonHistorique extends StatelessWidget {
  const _BoutonHistorique({required Key cle, required this.onTap})
    : super(key: cle);

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.neutre0,
      borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.roundedLg),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xsPlus,
            vertical: AppSpacing.unit,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.roundedLg),
            border: Border.all(color: AppColors.neutre300),
          ),
          child: Text(
            'Historique',
            style: TableClients._style(
              TaillesContenu.t12,
              couleur: AppColors.neutre700,
            ),
          ),
        ),
      ),
    );
  }
}

/// `text-[12px] px-2.5 py-1 rounded-lg bg-[var(--navy)] text-white`.
class _BoutonRecouvrement extends StatelessWidget {
  const _BoutonRecouvrement({required Key cle, required this.onTap})
    : super(key: cle);

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.navy,
      borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.roundedLg),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xsPlus,
            vertical: AppSpacing.unit,
          ),
          child: Text(
            'Recouvrement',
            style: TableClients._style(
              TaillesContenu.t12,
              couleur: AppColors.neutre0,
            ),
          ),
        ),
      ),
    );
  }
}

/// Une rangée de cellules `px-3`, aux parts de largeur de la vue.
class _Rangee extends StatelessWidget {
  const _Rangee({required this.cellules, required this.aDroite});

  final List<Widget> cellules;
  final List<bool> aDroite;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < cellules.length; i++)
          Expanded(
            flex: TableClients._parts[i],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: Align(
                alignment: aDroite[i]
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: cellules[i],
              ),
            ),
          ),
      ],
    );
  }
}

class _Nom extends StatelessWidget {
  const _Nom({
    required this.ligne,
    required this.avecCase,
    required this.cochee,
    required this.onBasculer,
  });

  final LigneClient ligne;

  /// La case de sélection : à qui peut archiver, sur un client ACTIF (une case
  /// sans action serait un contrôle qui n'ouvre rien).
  final bool avecCase;
  final bool cochee;
  final VoidCallback? onBasculer;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (avecCase) ...[
              // `w-4 h-4 rounded`, libellé accessible « Sélectionner ce client ».
              Semantics(
                label: 'Sélectionner ce client',
                child: SizedBox(
                  width: AppSpacing.md,
                  height: AppSpacing.md,
                  child: Checkbox(
                    key: Key('clients-case-${ligne.client.id}'),
                    value: cochee,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: onBasculer == null ? null : (_) => onBasculer!(),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs), // gap-2
            ],
            Text(
              ligne.client.nomComplet,
              key: Key('clients-ligne-${ligne.client.id}'),
              style: TableClients._style(
                TaillesContenu.t13,
                poids: FontWeight.w600,
                couleur: AppColors.neutre800,
              ),
            ),
            if (!ligne.client.actif) ...[
              const SizedBox(width: AppSpacing.xs),
              PastilleStatut(
                'Archivé',
                key: Key('clients-archive-${ligne.client.id}'),
                fond: AppColors.badgeGrisFond,
                texte: JetonsCssMaitre.neutre600,
              ),
            ],
          ],
        ),
        // Les clients partent RÉELLEMENT au serveur : ce badge dit quelque
        // chose de vrai, à la différence d'un panier, qui ne part jamais et
        // sur lequel « en attente » serait un mensonge (PA-98).
        if (ligne.client.enAttenteDeSynchronisation)
          Text(
            'En attente de synchronisation',
            key: Key('clients-attente-${ligne.client.id}'),
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: AppColors.alerte),
          ),
      ],
    );
  }
}
