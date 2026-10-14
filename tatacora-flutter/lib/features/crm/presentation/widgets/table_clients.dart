import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
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
/// ## La colonne d'actions : un seul bouton rendu, et pourquoi
///
/// La vue pose « Historique », « Recouvrement » et « Archiver ». Seul
/// **« Recouvrement »** est rendu : il a un écran (la modale d'encaissement) et
/// une source. « Historique » (modale du relevé) et l'archivage d'un client n'ont
/// pas d'écran sur ce poste : un bouton qui n'ouvre rien empêche de savoir si la
/// fonction manque ou si l'écran est cassé (PA-112). Le bouton n'existe que si
/// le client doit quelque chose ET que le rôle écrit sur M3 et M2 — la condition
/// de la vue (`$ligne->solde !== '0.00' && $peutEncaisser`).
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
    this.onRecouvrement,
  });

  final List<LigneClient> lignes;

  /// L'instant de référence de l'ancienneté (`diffInDays(now())`) — injecté : un
  /// test qui lit l'horloge réelle change de résultat tous les jours.
  final DateTime maintenant;

  /// `$peutEncaisser` de la vue : le droit d'écrire sur M3 ET sur M2.
  final bool peutEncaisser;

  /// Le geste « Recouvrement » d'une ligne.
  final void Function(LigneClient ligne)? onRecouvrement;

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
                    _Nom(ligne: l),
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
                    if (l.estDebiteur &&
                        peutEncaisser &&
                        onRecouvrement != null)
                      _BoutonRecouvrement(
                        cle: Key('clients-recouvrement-${l.client.id}'),
                        onTap: () => onRecouvrement!(l),
                      )
                    else
                      const SizedBox.shrink(),
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
  const _Nom({required this.ligne});

  final LigneClient ligne;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          ligne.client.nomComplet,
          key: Key('clients-ligne-${ligne.client.id}'),
          style: TableClients._style(
            TaillesContenu.t13,
            poids: FontWeight.w600,
            couleur: AppColors.neutre800,
          ),
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
