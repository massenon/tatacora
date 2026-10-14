import 'package:flutter/material.dart';

import '../../../../core/format/formats.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../shared_widgets/tableau_tatacora.dart';
import '../../domain/entities/vente.dart';
import 'dialogue_detail_vente.dart';

/// Le tableau du journal — les colonnes de la vue, dans son ordre, aux largeurs
/// relevées dans le navigateur (`<table class="w-full">`, `px-4 py-2.5`).
///
/// ## Ce que cet écran ne rend pas — les écarts, DITS
///
/// Ils étaient dans un panneau affiché sous le tableau ; il est retiré de
/// l'affichage (Phase 2, 08/10/2026) et les refus restent écrits ici.
///
///  - **Le numéro « V-2026-00016 »** : aucune séquence de numéros de vente
///    n'existe sur ce poste. La colonne N° porte la référence réelle de la
///    vente, abrégée ; en fabriquer un serait pire que de ne pas en avoir
///    (deux postes hors ligne attribueraient les mêmes numéros).
///  - **Le badge « stock ✕ »** : ce poste n'écrit aucun mouvement de stock
///    (PA-134) ; un badge qui ne s'affiche jamais est indistinguable d'un
///    écran cassé.
///  - **La recherche par chambre ou par numéro de facture** : un panier de
///    séjour porte la réservation, pas l'unité ; c'est le registre des
///    factures qui répond à la seconde question.
///  - **« Export Excel » produit un CSV** (BOM UTF-8, point-virgule, RG-19).
class TableauVentes extends StatelessWidget {
  const TableauVentes({required this.ventes, super.key});

  final List<Vente> ventes;

  static const String messageVide =
      'Aucune vente ne correspond à ces critères.';

  static const _titres = [
    'N°',
    'Date',
    'Poste',
    'Activités',
    'Règlement',
    'Montant',
    'Statut',
    'Actions',
  ];
  static const _parts = [792, 1046, 1182, 1566, 2000, 1243, 1800, 919];

  @override
  Widget build(BuildContext context) {
    return Column(
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
                  style: const TextStyle(
                    fontFamily: AppTextStyles.police,
                    fontSize: TaillesContenu.t11,
                    fontWeight: FontWeight.w600,
                    height: 1.5,
                    letterSpacing: 0.5,
                    color: CouleursTableau.enteteTexte,
                  ),
                ),
            ],
          ),
        ),
        if (ventes.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(
              vertical: AppSpacingLarge.p10,
              horizontal: AppSpacing.md,
            ),
            child: Center(
              child: Text(
                messageVide,
                style: const TextStyle(
                  fontFamily: AppTextStyles.police,
                  fontSize: TaillesContenu.t13,
                  height: 1.5,
                  color: AppColors.neutre400,
                ),
              ),
            ),
          )
        else
          for (final v in ventes)
            // La ligne entière ouvre le détail, comme le bouton « Détail ».
            // Écart : les `tr` de la vue sont inertes, mais son bouton ne
            // l'est pas, et il ouvre la même fenêtre.
            InkWell(
              key: Key('vente-ligne-${v.id}'),
              onTap: () => afficherDetailVente(context, v),
              child: Container(
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: AppColors.neutre100)),
                ),
                padding: const EdgeInsets.symmetric(
                  vertical: AppSpacing.xsPlus,
                ),
                child: _Rangee(cellules: _cellules(context, v)),
              ),
            ),
      ],
    );
  }
}

/// Une rangée de cellules `px-4`, aux parts de largeur de la vue ; la dernière
/// colonne (« Actions ») et « Montant » sont alignées à droite.
class _Rangee extends StatelessWidget {
  const _Rangee({required this.cellules});

  final List<Widget> cellules;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < cellules.length; i++)
          Expanded(
            flex: TableauVentes._parts[i],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Align(
                alignment: i == 5 || i == 7
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

List<Widget> _cellules(BuildContext context, Vente v) {
  final activites = v.activites.map((m) => m.libelle).join(', ');

  return [
    CelluleTableau(v.referenceLocale, monospace: true),
    CelluleTableau(formaterDate(v.date), secondaire: true),
    _Poste(vente: v),
    // Un tiret quand il n'y a rien, jamais une case vide : « — » dit que la
    // donnée n'existe pas, une case vide laisse croire à un oubli d'affichage.
    CelluleTableau(activites.isEmpty ? '—' : activites, secondaire: true),
    CelluleTableau(
      v.mode?.libelle ?? 'non renseigné',
      secondaire: true,
      // Le règlement inconnu se voit : sans couleur, il se lirait comme un
      // mode parmi d'autres, alors qu'il veut dire « personne n'a dit où est
      // l'argent ».
      couleur: v.mode == null ? CouleursTableau.alerteTexte : null,
    ),
    CelluleTableau(formaterFcfa(v.montant), gras: true),
    _Statut(vente: v),
    _Actions(vente: v),
  ];
}

class _Poste extends StatelessWidget {
  const _Poste({required this.vente});

  final Vente vente;

  @override
  Widget build(BuildContext context) {
    // Une vente de séjour n'a ni poste ni table : `ecran_pos_heberges.dart`
    // n'en passe aucun. Son client prend la place du complément, parce que
    // c'est la seule chose qui dise où la consommation a été servie.
    final complement = vente.tableLibelle ?? vente.clientNom;

    return RichText(
      text: TextSpan(
        style: const TextStyle(
          fontFamily: AppTextStyles.police,
          fontSize: TaillesContenu.t13,
          height: 1.5,
          color: AppColors.anthracite,
        ),
        children: [
          TextSpan(text: vente.pointVente ?? '—'),
          if (complement != null)
            TextSpan(
              text: ' · $complement',
              style: const TextStyle(color: CouleursTableau.texteSecondaire),
            ),
        ],
      ),
    );
  }
}

class _Statut extends StatelessWidget {
  const _Statut({required this.vente});

  final Vente vente;

  @override
  Widget build(BuildContext context) {
    if (vente.estAnnulee) {
      return const PastilleStatut.refus('annulée');
    }
    return switch (vente.encaisse) {
      true => const PastilleStatut.succes('encaissée'),
      false => const PastilleStatut.alerte('en note'),
      // Le quatrième cas, que la vue n'a pas : ni encaissée ni en note. Le
      // ranger dans l'une des deux affirmerait un état non vérifié.
      null => const PastilleStatut.alerte('règlement inconnu'),
    };
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.vente});

  final Vente vente;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // `text-[12px] px-2.5 py-1 rounded-lg border border-slate-300`
        Material(
          color: AppColors.neutre0,
          borderRadius: BorderRadius.circular(AppRadius.roundedLg),
          child: InkWell(
            key: Key('vente-detail-${vente.id}'),
            onTap: () => afficherDetailVente(context, vente),
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
              child: const Text(
                'Détail',
                style: TextStyle(
                  fontFamily: AppTextStyles.police,
                  fontSize: TaillesContenu.t12,
                  fontWeight: FontWeight.w600,
                  height: 1.5,
                  color: AppColors.neutre700,
                ),
              ),
            ),
          ),
        ),
        if (vente.aUneFacture) ...[
          const SizedBox(width: AppSpacing.unit),
          Text(
            vente.numeroFacture!,
            key: Key('vente-facture-${vente.id}'),
            style: const TextStyle(
              fontFamily: AppTextStyles.policeMonospace,
              fontSize: TaillesContenu.t11,
              height: 1.5,
              color: CouleursTableau.texteSecondaire,
            ),
          ),
        ],
      ],
    );
  }
}
