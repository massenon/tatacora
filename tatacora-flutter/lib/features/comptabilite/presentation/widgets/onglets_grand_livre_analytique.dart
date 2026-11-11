import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/format/formats.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/mesures_transverses.dart';
import '../../../transverse/presentation/widgets/briques_transverses.dart';
import '../../domain/consultation_comptable.dart';
import '../../domain/entities/comptabilite.dart';
import '../../domain/grand_livre_analytique.dart';
import '../../domain/montant_comptable.dart';
import '../providers_consultation_comptable.dart';
import '../providers_etats_financiers.dart';

/// Onglets « Grand livre » et « Analytique » du hub Comptabilité, calculés sur
/// les écritures de CE poste — sans serveur.
///
/// Vue Blade maîtresse (PA-183) : pwa/comptabilite/onglets/grandlivre.blade.php
/// et pwa/comptabilite/onglets/analytique.blade.php — les colonnes, le
/// sélecteur de compte, la ligne de totaux, les soldes d'ouverture et de
/// clôture et l'encadré des marges sont ceux de la vue.
abstract final class TextesGrandLivreAnalytique {
  static const String compte = 'Compte';
  static const String aucunCompte = 'Aucun compte mouvementé sur la période.';
  static const String sansMouvement =
      "Ce compte n'a aucun mouvement sur l'exercice.";
  static const String totaux = 'Totaux';
  static const String soldeOuverture = "Solde d'ouverture";
  static const String soldeCloture = 'Solde de clôture';
  static const String soldeOuvertureInconnu =
      "Solde d'ouverture inconnu, jamais zéro : aucun report à nouveau n'existe encore. Le solde progressif part donc des seuls mouvements de l'exercice.";
  static String ouvertureProvisoire(int annee) =>
      "Ouverture PROVISOIRE : l'exercice $annee n'est pas clôturé, son report à nouveau est calculé à chaque lecture.";
  static const String centresVide = 'Aucune écriture ventilée sur la période.';
  static const String structureTitre =
      "Aucune charge de structure n'est répartie.";
  static const String structureDetail =
      ' Les charges imputées au centre ADM y restent. Les résultats par centre sont donc des marges sur coûts directs, pas des résultats nets.';
  static const String titreCentres = "Résultat par centre d'analyse";
  static const String total = 'TOTAL';
  static const String tiret = '—';
}

String _montant(int centimes) =>
    formaterMontantDecimal(
      chaineDepuisCentimes(centimes.abs()),
      suffixe: 'FCFA',
    ) ??
    TextesGrandLivreAnalytique.tiret;

String _montantOuTiret(int centimes) =>
    centimes == 0 ? TextesGrandLivreAnalytique.tiret : _montant(centimes);

/// Le solde avec son sens : valeur absolue puis D (débiteur) ou C (créditeur).
String _soldeAvecSens(int centimes) =>
    '${_montant(centimes)} ${centimes < 0 ? 'C' : 'D'}';

String _date(String iso) {
  final p = iso.split('-');
  return p.length == 3 ? '${p[2]}/${p[1]}/${p[0]}' : iso;
}

/// Onglet « Grand livre » : un compte à la fois, comme la vue.
class OngletGrandLivre extends ConsumerStatefulWidget {
  const OngletGrandLivre({
    required this.exercice,
    required this.donnees,
    required this.statut,
    super.key,
  });

  final ExerciceComptable exercice;
  final DonneesComptabilite donnees;
  final FiltreStatutEcritures statut;

  @override
  ConsumerState<OngletGrandLivre> createState() => _OngletGrandLivreState();
}

class _OngletGrandLivreState extends ConsumerState<OngletGrandLivre> {
  String? _compteId;

  @override
  Widget build(BuildContext context) {
    final d = widget.donnees;
    final portee = porteeEcritures(
      d.ecritures,
      exerciceId: widget.exercice.id,
      statut: widget.statut,
    );
    final comptes = comptesMouvementes(portee, d.comptes);
    final choisi =
        comptes.where((c) => c.id == _compteId).firstOrNull ??
        comptes.firstOrNull;
    final etats = ref.watch(donneesEtatsDuPosteProvider).value;
    final style = styleTransverse(TaillesContenu.t13);

    final selecteur = CarteTransverse(
      padding: const EdgeInsets.all(AppSpacing.smPlus),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            TextesGrandLivreAnalytique.compte,
            style: styleTransverse(TaillesContenu.t12, couleur: Ardoise.c500),
          ),
          const SizedBox(height: AppSpacing.xxs),
          DropdownButton<String>(
            key: const Key('compta-grand-livre-compte'),
            isExpanded: true,
            value: choisi?.id,
            style: style,
            hint: Text(TextesGrandLivreAnalytique.aucunCompte, style: style),
            onChanged: (id) => setState(() => _compteId = id),
            items: [
              for (final c in comptes)
                DropdownMenuItem(
                  value: c.id,
                  child: Text('${c.numero} — ${c.libelle}', style: style),
                ),
            ],
          ),
        ],
      ),
    );

    if (choisi == null || etats == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          selecteur,
          const SizedBox(height: AppSpacing.sm),
          CarteTransverse(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
            child: Text(
              TextesGrandLivreAnalytique.aucunCompte,
              key: const Key('compta-grand-livre-vide'),
              textAlign: TextAlign.center,
              style: styleTransverse(TaillesContenu.t13, couleur: Ardoise.c400),
            ),
          ),
        ],
      );
    }

    final report = reportOuverture(widget.exercice.annee, etats);
    final livre = grandLivreDe(
      compte: choisi,
      portee: portee,
      reportCentimes: report.connu ? (report.soldes[choisi.numero] ?? 0) : null,
      reportProvisoire: report.provisoire,
      anneeReport: report.annee,
    );
    final blanc = styleTransverse(
      TaillesContenu.t13,
      poids: FontWeight.bold,
      couleur: AppColors.neutre0,
    );
    final journaux = {for (final j in d.journaux) j.id: j.code};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        selecteur,
        const SizedBox(height: AppSpacing.sm),
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
          child: Text(
            '${choisi.numero} — ${choisi.libelle}',
            style: styleTransverse(
              TaillesContenu.t14,
              poids: FontWeight.bold,
              couleur: AppColors.navy,
            ),
          ),
        ),
        CarteTransverse(
          padding: EdgeInsets.zero,
          child: TableauTransverse(
            largeurs: const {3: MesuresTransverses.colonneLibelleCompta},
            colonnes: const [
              (titre: 'Date', alignement: TextAlign.left),
              (titre: 'N° pièce', alignement: TextAlign.left),
              (titre: 'Journal', alignement: TextAlign.right),
              (titre: 'Libellé', alignement: TextAlign.left),
              (titre: 'Débit', alignement: TextAlign.right),
              (titre: 'Crédit', alignement: TextAlign.right),
              (titre: 'Solde', alignement: TextAlign.right),
            ],
            vide: TextesGrandLivreAnalytique.sansMouvement,
            cleVide: const Key('compta-grand-livre-sans-mouvement'),
            lignes: [
              for (final l in livre.lignes)
                [
                  celluleTexte(_date(l.ecriture.dateEcriture)),
                  celluleTexte(
                    l.ecriture.numeroPiece ?? TextesGrandLivreAnalytique.tiret,
                    mono: true,
                    taille: TaillesContenu.t12,
                  ),
                  celluleTexte(
                    journaux[l.ecriture.journalId] ?? '',
                    alignement: TextAlign.right,
                  ),
                  celluleTexte(l.ecriture.libelle),
                  celluleTexte(
                    _montantOuTiret(l.ecriture.debitCentimes),
                    alignement: TextAlign.right,
                  ),
                  celluleTexte(
                    _montantOuTiret(l.ecriture.creditCentimes),
                    alignement: TextAlign.right,
                  ),
                  celluleTexte(
                    _soldeAvecSens(l.soldeProgressifCentimes),
                    alignement: TextAlign.right,
                    poids: FontWeight.w600,
                  ),
                ],
            ],
            pied: livre.estSansMouvement
                ? null
                : [
                    Text(TextesGrandLivreAnalytique.totaux, style: blanc),
                    const SizedBox.shrink(),
                    const SizedBox.shrink(),
                    const SizedBox.shrink(),
                    const SizedBox.shrink(),
                    const SizedBox.shrink(),
                    Text(
                      _soldeAvecSens(livre.soldeMouvementsCentimes),
                      key: const Key('compta-grand-livre-total'),
                      textAlign: TextAlign.right,
                      style: blanc,
                    ),
                  ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (livre.soldeOuvertureCentimes == null)
          Text(
            TextesGrandLivreAnalytique.soldeOuvertureInconnu,
            key: const Key('compta-grand-livre-ouverture-inconnue'),
            style: styleTransverse(TaillesContenu.t13, couleur: Ardoise.c400),
          )
        else ...[
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.xxs,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${TextesGrandLivreAnalytique.soldeOuverture} : ',
                    ),
                    TextSpan(
                      text: _soldeAvecSens(livre.soldeOuvertureCentimes!),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                key: const Key('compta-grand-livre-ouverture'),
                style: styleTransverse(
                  TaillesContenu.t13,
                  couleur: Ardoise.c600,
                ),
              ),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${TextesGrandLivreAnalytique.soldeCloture} : ',
                    ),
                    TextSpan(
                      text: _soldeAvecSens(livre.soldeClotureCentimes!),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                key: const Key('compta-grand-livre-cloture'),
                style: styleTransverse(
                  TaillesContenu.t13,
                  couleur: Ardoise.c600,
                ),
              ),
            ],
          ),
          if (livre.ouvertureProvisoire)
            Text(
              TextesGrandLivreAnalytique.ouvertureProvisoire(
                livre.anneeOuverture!,
              ),
              key: const Key('compta-grand-livre-provisoire'),
              style: styleTransverse(TaillesContenu.t12, couleur: Ardoise.c500),
            ),
        ],
      ],
    );
  }
}

/// Onglet « Analytique » : le résultat par centre d'analyse.
class OngletAnalytique extends StatelessWidget {
  const OngletAnalytique({
    required this.exercice,
    required this.donnees,
    required this.statut,
    super.key,
  });

  final ExerciceComptable exercice;
  final DonneesComptabilite donnees;
  final FiltreStatutEcritures statut;

  @override
  Widget build(BuildContext context) {
    final portee = porteeEcritures(
      donnees.ecritures,
      exerciceId: exercice.id,
      statut: statut,
    );
    final analytique = analytiqueDe(
      portee: portee,
      comptes: donnees.comptes,
      centres: donnees.centres,
    );
    if (analytique.centres.isEmpty) {
      return CarteTransverse(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Text(
          TextesGrandLivreAnalytique.centresVide,
          key: const Key('compta-analytique-vide'),
          textAlign: TextAlign.center,
          style: styleTransverse(TaillesContenu.t13, couleur: Ardoise.c400),
        ),
      );
    }
    final blanc = styleTransverse(
      TaillesContenu.t13,
      poids: FontWeight.bold,
      couleur: AppColors.neutre0,
    );
    String taux(LigneAnalytiquePoste c) {
      final t = c.tauxMargeDixiemes;
      if (t == null) return TextesGrandLivreAnalytique.tiret;
      final signe = t < 0 ? '-' : '';
      final a = t.abs();
      return '$signe${a ~/ 10}.${a % 10} %';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CarteTransverse(
          key: const Key('compta-analytique-structure'),
          fond: PaletteMaitre.ambre50,
          bordure: PaletteMaitre.ambre200,
          padding: const EdgeInsets.all(AppSpacing.smPlus),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: TextesGrandLivreAnalytique.structureTitre,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const TextSpan(
                  text: TextesGrandLivreAnalytique.structureDetail,
                ),
              ],
            ),
            style: styleTransverse(
              TaillesContenu.t13,
              couleur: PaletteMaitre.ambre900,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
          child: Text(
            TextesGrandLivreAnalytique.titreCentres,
            style: styleTransverse(
              TaillesContenu.t14,
              poids: FontWeight.bold,
              couleur: AppColors.navy,
            ),
          ),
        ),
        CarteTransverse(
          padding: EdgeInsets.zero,
          child: TableauTransverse(
            colonnes: const [
              (titre: 'Centre', alignement: TextAlign.left),
              (titre: 'Libellé', alignement: TextAlign.left),
              (titre: 'Produits', alignement: TextAlign.right),
              (titre: 'Charges directes', alignement: TextAlign.right),
              (titre: 'Marge sur coûts directs', alignement: TextAlign.right),
              (titre: 'Taux', alignement: TextAlign.right),
              (titre: 'Lignes', alignement: TextAlign.right),
            ],
            vide: TextesGrandLivreAnalytique.centresVide,
            lignes: [
              for (final c in analytique.centres)
                [
                  celluleTexte(c.libelle, poids: FontWeight.w600),
                  celluleTexte(c.type ?? TextesGrandLivreAnalytique.tiret),
                  celluleTexte(
                    _montantOuTiret(c.produitsCentimes),
                    alignement: TextAlign.right,
                    couleur: PaletteMaitre.emeraude700,
                    poids: FontWeight.w600,
                  ),
                  celluleTexte(
                    _montantOuTiret(c.chargesCentimes),
                    alignement: TextAlign.right,
                    couleur: PaletteMaitre.rouge600,
                  ),
                  celluleTexte(
                    '${c.resultatCentimes < 0 ? '-' : ''}${_montant(c.resultatCentimes)}',
                    alignement: TextAlign.right,
                    poids: FontWeight.bold,
                    couleur: c.resultatCentimes < 0
                        ? PaletteMaitre.rouge600
                        : AppColors.navy,
                  ),
                  celluleTexte(taux(c), alignement: TextAlign.right),
                  celluleTexte(
                    '${c.nombreLignes}',
                    alignement: TextAlign.right,
                    couleur: Ardoise.c400,
                  ),
                ],
            ],
            pied: [
              Text(TextesGrandLivreAnalytique.total, style: blanc),
              const SizedBox.shrink(),
              Text(
                _montant(analytique.totalProduitsCentimes),
                key: const Key('compta-analytique-total-produits'),
                textAlign: TextAlign.right,
                style: blanc,
              ),
              Text(
                _montant(analytique.totalChargesCentimes),
                key: const Key('compta-analytique-total-charges'),
                textAlign: TextAlign.right,
                style: blanc,
              ),
              Text(
                '${analytique.totalResultatCentimes < 0 ? '-' : ''}${_montant(analytique.totalResultatCentimes)}',
                key: const Key('compta-analytique-total-marge'),
                textAlign: TextAlign.right,
                style: blanc,
              ),
              const SizedBox.shrink(),
              const SizedBox.shrink(),
            ],
          ),
        ),
      ],
    );
  }
}
