import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/format/formats.dart';
import '../../../../core/theme/app_breakpoints.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/mesures_transverses.dart';
import '../../../transverse/presentation/widgets/briques_transverses.dart';
import '../../domain/etats_financiers.dart';
import '../../domain/montant_comptable.dart';
import '../providers_etats_financiers.dart';

/// Onglets « Compte de résultat » et « Bilan » du hub Comptabilité, calculés
/// sur le poste depuis les écritures VALIDÉES du serveur (21/10/2026).
///
/// Vue Blade maîtresse (PA-183) : pwa/comptabilite/onglets/resultat.blade.php
/// et pwa/comptabilite/onglets/bilan.blade.php — les colonnes, les totaux, les
/// bandeaux et la colonne comparative N-1 y sont ceux de la vue.
///
/// ## Ce que ce poste ajoute à la vue, et pourquoi
///
/// Un encadré de PROVENANCE (« écritures du serveur reçues… »), absent de la
/// vue : le serveur lit sa base, le poste lit ce qu'il a reçu, et un chiffre
/// d'état financier qui ne dit pas jusqu'où il a reçu ment par omission. Il dit
/// aussi que le filtre de statut ne s'applique pas ici (seules les écritures
/// VALIDÉES descendent).
abstract final class TextesEtatsFinanciers {
  static String colonnePrecedente(int annee) => 'Exercice $annee';
  static const String titreResultat = 'Compte de résultat — Système Normal';
  static const String avantImpotTitre = 'Résultat AVANT impôt.';
  static const String avantImpotDetail =
      "Résultat affiché avant Impôt sur les Sociétés : aucun impôt n'est comptabilisé en classe 89 sur cet exercice. Le montant est celui qui a été enregistré, jamais un taux appliqué.";
  static const String libelleAvantImpot =
      'RÉSULTAT AVANT IMPÔT SUR LES SOCIÉTÉS';
  static const String bilanDesequilibre = 'Bilan déséquilibré.';
  static String ecartBilan(String montant) =>
      'Écart de $montant entre actif et passif.';
  static const String traitementsTitre =
      'Deux traitements que la lecture littérale du plan manquerait :';
  static const String traitementsDetail =
      "amortissements et dépréciations en soustraction de l'actif (présentation brut / amort. / net), et reclassement des classes 4 et 5 selon le sens réel du solde — un compte 521 créditeur est un découvert, donc une trésorerie-passif, pas un actif négatif.";
  static const String horsRubriqueTitre =
      'Comptes mouvementés hors nomenclature';
  static const String horsRubriqueDetail =
      "Leur solde n'apparaît ni au Bilan ni au Compte de résultat. Sans cette liste, ils ne produiraient qu'un déséquilibre inexplicable.";
  static const String totalActif = 'TOTAL ACTIF';
  static const String totalPassif = 'TOTAL PASSIF';
  static const String tiret = '—';

  /// AJOUTS du poste (provenance), absents de la vue.
  static const String provenanceVide =
      "Aucune écriture du serveur n'a encore été reçue sur ce poste : cet état reste vide tant que la synchronisation n'a rien descendu.";
  static String provenance(int nombre, String? derniere) =>
      'Calculé sur ce poste depuis les écritures validées reçues du serveur : '
      '$nombre écriture(s)${derniere == null ? '' : ", la plus récente du $derniere"}. '
      'Ne descendent que les écritures validées : le filtre de statut ne '
      "s'applique pas ici.";
  static String enAttente(int n) =>
      "$n opération(s) de ce poste attendent encore leur envoi : leurs écritures ne sont pas comptées tant que le serveur n'a pas passé ses pièces.";
  static String reportProvisoire(int annee) =>
      "À-nouveaux provisoires : l'exercice $annee n'est pas clôturé, ses soldes sont reportés sans l'être définitivement.";
  static const String illisible =
      "Les écritures du serveur n'ont pas pu être lues sur ce poste.";
}

String _montant(int centimes) =>
    formaterMontantDecimal(chaineDepuisCentimes(centimes), suffixe: 'FCFA') ??
    TextesEtatsFinanciers.tiret;

String _montantOuTiret(int centimes) =>
    centimes == 0 ? TextesEtatsFinanciers.tiret : _montant(centimes);

class _Bandeau extends StatelessWidget {
  const _Bandeau({
    required this.cle,
    required this.fond,
    required this.bordure,
    required this.texte,
    required this.enfants,
  });

  final Key cle;
  final Color fond;
  final Color bordure;
  final Color texte;
  final List<Widget> enfants;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: CarteTransverse(
      key: cle,
      fond: fond,
      bordure: bordure,
      padding: const EdgeInsets.all(AppSpacing.smPlus),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final e in enfants)
            DefaultTextStyle.merge(
              style: TextStyle(color: texte),
              child: e,
            ),
        ],
      ),
    ),
  );
}

/// L'encadré de provenance, sous les deux onglets.
class EncadreProvenance extends ConsumerWidget {
  const EncadreProvenance({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lu = ref.watch(provenanceEtatsFinanciersProvider).value;
    if (lu == null) return const SizedBox.shrink();
    final r = lu.reception;
    final jour = r.derniereDate == null ? null : _jourFrancais(r.derniereDate!);
    final lignes = [
      if (r.nombre == 0)
        TextesEtatsFinanciers.provenanceVide
      else
        TextesEtatsFinanciers.provenance(r.nombre, jour),
      if (lu.enAttenteDEnvoi > 0)
        TextesEtatsFinanciers.enAttente(lu.enAttenteDEnvoi),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Column(
        key: const Key('compta-etats-provenance'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final l in lignes)
            Text(
              l,
              style: styleTransverse(TaillesContenu.t12, couleur: Ardoise.c500),
            ),
        ],
      ),
    );
  }
}

String _jourFrancais(String iso) {
  final p = iso.split('-');
  return p.length == 3 ? '${p[2]}/${p[1]}/${p[0]}' : iso;
}

/// Onglet « Compte de résultat ».
class OngletResultat extends ConsumerWidget {
  const OngletResultat({required this.annee, super.key});

  final int annee;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lu = ref.watch(donneesEtatsFinanciersProvider);
    if (lu.hasError) {
      return Text(
        TextesEtatsFinanciers.illisible,
        key: const Key('compta-etats-illisible'),
        style: styleTransverse(TaillesContenu.t13, couleur: AppColors.erreur),
      );
    }
    final d = lu.value;
    if (d == null) return const SizedBox.shrink();
    final resultat = compteResultatDe(annee, d);
    final precedent = d.existe(annee - 1) ? annee - 1 : null;
    final avant = precedent == null ? null : compteResultatDe(precedent, d);
    final anterieurs = {
      for (final l in avant?.lignes ?? const <LigneResultatEtat>[])
        l.rubrique.code: l.montantCentimes,
    };
    final blanc = styleTransverse(
      TaillesContenu.t13,
      poids: FontWeight.bold,
      couleur: AppColors.neutre0,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (resultat.impotNonComptabilise)
          _Bandeau(
            cle: const Key('compta-resultat-avant-impot'),
            fond: PaletteMaitre.ambre50,
            bordure: PaletteMaitre.ambre200,
            texte: PaletteMaitre.ambre900,
            enfants: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: TextesEtatsFinanciers.avantImpotTitre,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    TextSpan(
                      text: ' ${TextesEtatsFinanciers.avantImpotDetail}',
                    ),
                  ],
                ),
                style: styleTransverse(TaillesContenu.t13),
              ),
            ],
          ),
        if (resultat.aNouveauxProvisoiresDe != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Text(
              TextesEtatsFinanciers.reportProvisoire(
                resultat.aNouveauxProvisoiresDe!,
              ),
              key: const Key('compta-etats-report-provisoire'),
              style: styleTransverse(TaillesContenu.t12, couleur: Ardoise.c500),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
          child: Text(
            TextesEtatsFinanciers.titreResultat,
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
            largeurs: const {1: MesuresTransverses.colonneLibelleCompta},
            colonnes: [
              (titre: 'Réf.', alignement: TextAlign.left),
              (titre: 'Libellé', alignement: TextAlign.left),
              (titre: 'Charges', alignement: TextAlign.right),
              (titre: 'Produits / Solde', alignement: TextAlign.right),
              if (precedent != null)
                (
                  titre: TextesEtatsFinanciers.colonnePrecedente(precedent),
                  alignement: TextAlign.right,
                ),
            ],
            vide: TextesEtatsFinanciers.provenanceVide,
            lignes: [
              for (final l in resultat.lignes)
                _ligneResultat(l, anterieurs, precedent != null),
            ],
            pied: [
              Text(
                resultat.impotNonComptabilise
                    ? TextesEtatsFinanciers.libelleAvantImpot
                    : 'RÉSULTAT NET',
                style: blanc,
              ),
              const SizedBox.shrink(),
              const SizedBox.shrink(),
              Text(
                _montant(resultat.resultatNetCentimes),
                key: const Key('compta-resultat-net'),
                textAlign: TextAlign.right,
                style: blanc,
              ),
              if (precedent != null)
                Text(
                  _montant(avant!.resultatNetCentimes),
                  textAlign: TextAlign.right,
                  style: blanc,
                ),
            ],
          ),
        ),
        const EncadreProvenance(),
      ],
    );
  }

  List<Widget> _ligneResultat(
    LigneResultatEtat l,
    Map<String, int> anterieurs,
    bool avecPrecedent,
  ) {
    final r = l.rubrique;
    final solde = r.estSolde;
    final charge = r.sens == SensRubrique.charge;
    final precedent = anterieurs[r.code] ?? 0;
    final poids = solde ? FontWeight.bold : null;
    return [
      celluleTexte(
        r.code,
        mono: true,
        taille: TaillesContenu.t12,
        poids: poids,
        couleur: solde ? AppColors.navy : Ardoise.c400,
      ),
      celluleTexte(
        r.prefixes.isEmpty
            ? r.libelle
            : '${r.libelle} · ${r.prefixes.join(', ')}',
        poids: poids,
        couleur: solde ? AppColors.navy : Ardoise.c700,
      ),
      if (solde)
        const SizedBox.shrink()
      else
        celluleTexte(
          charge
              ? _montantOuTiret(l.montantCentimes)
              : TextesEtatsFinanciers.tiret,
          alignement: TextAlign.right,
          couleur: charge ? PaletteMaitre.rouge600 : Ardoise.c300,
        ),
      celluleTexte(
        solde
            ? _montant(l.montantCentimes)
            : (charge
                  ? TextesEtatsFinanciers.tiret
                  : _montantOuTiret(l.montantCentimes)),
        alignement: TextAlign.right,
        poids: solde || !charge ? FontWeight.bold : null,
        couleur: solde
            ? (l.montantCentimes < 0 ? PaletteMaitre.rouge600 : AppColors.navy)
            : (charge ? Ardoise.c300 : PaletteMaitre.vert700),
      ),
      if (avecPrecedent)
        celluleTexte(
          solde ? _montant(precedent) : _montantOuTiret(precedent),
          alignement: TextAlign.right,
          couleur: Ardoise.c500,
        ),
    ];
  }
}

/// Onglet « Bilan ».
class OngletBilan extends ConsumerWidget {
  const OngletBilan({required this.annee, super.key});

  final int annee;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lu = ref.watch(donneesEtatsFinanciersProvider);
    if (lu.hasError) {
      return Text(
        TextesEtatsFinanciers.illisible,
        key: const Key('compta-etats-illisible'),
        style: styleTransverse(TaillesContenu.t13, couleur: AppColors.erreur),
      );
    }
    final d = lu.value;
    if (d == null) return const SizedBox.shrink();
    final bilan = bilanDe(annee, d);
    final precedent = d.existe(annee - 1) ? annee - 1 : null;
    final avant = precedent == null ? null : bilanDe(precedent, d);
    final nets = <String, int>{
      for (final p in [...?avant?.actif, ...?avant?.passif])
        '${p.section.name}|${p.code}': p.netCentimes,
    };
    final blanc = styleTransverse(
      TaillesContenu.t13,
      poids: FontWeight.bold,
      couleur: AppColors.neutre0,
    );

    Widget poste(PosteBilanEtat p) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        celluleTexte(p.libelle, couleur: Ardoise.c700),
        if (p.prefixes.isNotEmpty)
          celluleTexte(
            p.prefixes.join(', '),
            taille: TaillesContenu.t11,
            couleur: Ardoise.c400,
          ),
      ],
    );

    final actif = CarteTransverse(
      padding: EdgeInsets.zero,
      child: TableauTransverse(
        largeurs: const {1: MesuresTransverses.colonneLibelleCompta},
        colonnes: [
          (titre: 'Réf.', alignement: TextAlign.left),
          (titre: 'ACTIF', alignement: TextAlign.left),
          (titre: 'Brut', alignement: TextAlign.right),
          (titre: 'Amort./Dépr.', alignement: TextAlign.right),
          (titre: 'Net', alignement: TextAlign.right),
          if (precedent != null)
            (
              titre: TextesEtatsFinanciers.colonnePrecedente(precedent),
              alignement: TextAlign.right,
            ),
        ],
        vide: TextesEtatsFinanciers.provenanceVide,
        lignes: [
          for (final p in bilan.actif)
            [
              celluleTexte(
                p.code,
                mono: true,
                taille: TaillesContenu.t12,
                couleur: Ardoise.c400,
              ),
              poste(p),
              celluleTexte(
                _montantOuTiret(p.brutCentimes),
                alignement: TextAlign.right,
              ),
              celluleTexte(
                _montantOuTiret(p.amortissementCentimes),
                alignement: TextAlign.right,
                couleur: PaletteMaitre.rouge600,
              ),
              celluleTexte(
                _montantOuTiret(p.netCentimes),
                alignement: TextAlign.right,
                poids: FontWeight.w600,
              ),
              if (precedent != null)
                celluleTexte(
                  _montantOuTiret(nets['actif|${p.code}'] ?? 0),
                  alignement: TextAlign.right,
                  couleur: Ardoise.c500,
                ),
            ],
        ],
        pied: [
          Text(TextesEtatsFinanciers.totalActif, style: blanc),
          const SizedBox.shrink(),
          Text(
            _montant(bilan.totalActifBrutCentimes),
            textAlign: TextAlign.right,
            style: blanc,
          ),
          Text(
            _montant(bilan.totalActifAmortissementCentimes),
            textAlign: TextAlign.right,
            style: blanc,
          ),
          Text(
            _montant(bilan.totalActifCentimes),
            key: const Key('compta-bilan-total-actif'),
            textAlign: TextAlign.right,
            style: blanc,
          ),
          if (precedent != null)
            Text(
              _montant(avant!.totalActifCentimes),
              textAlign: TextAlign.right,
              style: blanc,
            ),
        ],
      ),
    );

    final passif = CarteTransverse(
      padding: EdgeInsets.zero,
      child: TableauTransverse(
        largeurs: const {1: MesuresTransverses.colonneLibelleCompta},
        colonnes: [
          (titre: 'Réf.', alignement: TextAlign.left),
          (titre: 'PASSIF', alignement: TextAlign.left),
          (titre: 'Montant', alignement: TextAlign.right),
          if (precedent != null)
            (
              titre: TextesEtatsFinanciers.colonnePrecedente(precedent),
              alignement: TextAlign.right,
            ),
        ],
        vide: TextesEtatsFinanciers.provenanceVide,
        lignes: [
          for (final p in bilan.passif)
            [
              celluleTexte(
                p.code,
                mono: true,
                taille: TaillesContenu.t12,
                couleur: Ardoise.c400,
              ),
              poste(p),
              celluleTexte(
                _montantOuTiret(p.netCentimes),
                alignement: TextAlign.right,
                poids: FontWeight.w600,
                couleur: p.netCentimes < 0
                    ? PaletteMaitre.rouge600
                    : Ardoise.c600,
              ),
              if (precedent != null)
                celluleTexte(
                  _montantOuTiret(nets['passif|${p.code}'] ?? 0),
                  alignement: TextAlign.right,
                  couleur: Ardoise.c500,
                ),
            ],
        ],
        pied: [
          Text(TextesEtatsFinanciers.totalPassif, style: blanc),
          const SizedBox.shrink(),
          Text(
            _montant(bilan.totalPassifCentimes),
            key: const Key('compta-bilan-total-passif'),
            textAlign: TextAlign.right,
            style: blanc,
          ),
          if (precedent != null)
            Text(
              _montant(avant!.totalPassifCentimes),
              textAlign: TextAlign.right,
              style: blanc,
            ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!bilan.equilibre)
          _Bandeau(
            cle: const Key('compta-bilan-desequilibre'),
            fond: PaletteMaitre.rouge50,
            bordure: PaletteMaitre.rouge200,
            texte: PaletteMaitre.rouge900,
            enfants: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: TextesEtatsFinanciers.bilanDesequilibre,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    TextSpan(
                      text:
                          ' ${TextesEtatsFinanciers.ecartBilan(_montant(bilan.ecartCentimes.abs()))}',
                    ),
                  ],
                ),
                style: styleTransverse(TaillesContenu.t13),
              ),
            ],
          ),
        if (bilan.impotNonComptabilise)
          _Bandeau(
            cle: const Key('compta-bilan-avant-impot'),
            fond: PaletteMaitre.ambre50,
            bordure: PaletteMaitre.ambre200,
            texte: PaletteMaitre.ambre900,
            enfants: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: TextesEtatsFinanciers.avantImpotTitre,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    TextSpan(
                      text: ' ${TextesEtatsFinanciers.avantImpotDetail}',
                    ),
                  ],
                ),
                style: styleTransverse(TaillesContenu.t13),
              ),
            ],
          ),
        if (bilan.aNouveauxProvisoiresDe != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Text(
              TextesEtatsFinanciers.reportProvisoire(
                bilan.aNouveauxProvisoiresDe!,
              ),
              key: const Key('compta-etats-report-provisoire'),
              style: styleTransverse(TaillesContenu.t12, couleur: Ardoise.c500),
            ),
          ),
        _Bandeau(
          cle: const Key('compta-bilan-traitements'),
          fond: Ardoise.c50,
          bordure: Ardoise.c200,
          texte: Ardoise.c700,
          enfants: [
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: TextesEtatsFinanciers.traitementsTitre,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  TextSpan(text: ' ${TextesEtatsFinanciers.traitementsDetail}'),
                ],
              ),
              style: styleTransverse(TaillesContenu.t13),
            ),
          ],
        ),
        LayoutBuilder(
          builder: (context, c) => c.maxWidth >= AppBreakpoints.xl
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: actif),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: passif),
                  ],
                )
              : Column(
                  children: [
                    actif,
                    const SizedBox(height: AppSpacing.sm),
                    passif,
                  ],
                ),
        ),
        if (bilan.comptesHorsRubrique.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          _Bandeau(
            cle: const Key('compta-bilan-hors-rubrique'),
            fond: PaletteMaitre.rouge50,
            bordure: PaletteMaitre.rouge200,
            texte: PaletteMaitre.rouge900,
            enfants: [
              Text(
                TextesEtatsFinanciers.horsRubriqueTitre,
                style: styleTransverse(
                  TaillesContenu.t13,
                  poids: FontWeight.bold,
                ),
              ),
              Text(
                TextesEtatsFinanciers.horsRubriqueDetail,
                style: styleTransverse(TaillesContenu.t13),
              ),
              for (final h in bilan.comptesHorsRubrique)
                Text(
                  '${h.numeroCompte} — ${h.libelle} : ${_montant(h.soldeCentimes)}',
                  style: styleTransverse(TaillesContenu.t13),
                ),
            ],
          ),
        ],
        const EncadreProvenance(),
      ],
    );
  }
}
