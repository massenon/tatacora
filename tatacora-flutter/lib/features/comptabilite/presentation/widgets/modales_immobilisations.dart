// Vue Blade maîtresse (PA-183) : pwa/comptabilite/hub.blade.php
// (les modales « Nouvelle immobilisation » : `etatFormulaire === 'immo'`, et
// « Plan » d'amortissement : `=== 'planAmortissement'`).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/format/formats.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../shared_widgets/bouton_standard.dart';
import '../../../transverse/presentation/widgets/briques_transverses.dart';
import '../../domain/entities/comptabilite.dart';
import '../../domain/immobilisations.dart';
import '../../domain/montant_comptable.dart';
import '../providers_consultation_comptable.dart';
import '../providers_immobilisations.dart';
import 'modales_hub_comptabilite.dart';

/// Les mots des deux modales — `lang/fr/comptabilite_pwa.php` (`immo_*`,
/// `champ_*`, `col_*`, `plan_amortissement_*`, `total`), `pwa.modale.*`.
abstract final class TextesModalesImmobilisations {
  static const String titre = 'Nouvelle immobilisation';
  static const String champIntitule = 'Intitulé';
  static const String libelleInvite = 'Ex. Toyota Land Cruiser Prado';
  static const String champCompte = 'Compte d’immobilisation';
  static const String choisir = 'Choisir…';
  static const String champValeur = 'Valeur d’origine (FCFA)';
  static const String champDate = 'Mise en service';
  static const String champDuree = 'Durée d’utilité (années)';
  static const String dureeInvite = 'à décider';
  static const String aide =
      'Aucune durée n’est proposée par défaut : c’est une estimation propre à l’entité, pas un barème.';
  static const String annuler = 'Annuler';
  static const String enregistrer = 'Enregistrer';
  static const String fermer = 'Fermer';

  static const String colExercice = 'Exercice';
  static const String colBase = 'Base';
  static const String colDotation = 'Dotation';
  static const String colCumul = 'Cumul';
  static const String colVnc = 'VNC';
  static const String total = 'TOTAL';
  static const String planNote =
      'La dernière annuité absorbe l’arrondi : sans cela, la somme des annuités s’écarterait de la valeur d’origine et la VNC finale ne tomberait pas exactement à zéro.';

  /// `immo_enregistree`.
  static String enregistree(String code) => 'Immobilisation $code enregistrée.';

  /// Le sous-titre de la modale « Plan » : valeur · durée · linéaire · date.
  static String resume(Immobilisation i) =>
      '${montantFcfa(i.valeurOrigineCentimes)} · ${i.dureeAnnees} ans · '
      'linéaire · mise en service ${i.dateMiseServiceCourte}';

  static String prorata(String fraction) => 'prorata $fraction';

  /// AJOUT déclaré : la saisie illisible d'une date (le champ de la vue est
  /// natif, celui-ci est typé `JJ/MM/AAAA`).
  static const String dateInviteSaisie = 'JJ/MM/AAAA';
  static const String echecInattendu =
      "L'opération n'a pas pu être enregistrée sur ce poste. Rien n'a été "
      'écrit.';
}

/// `MontantFcfa::format` : un montant en centimes, suffixe FCFA.
String montantFcfa(int centimes) =>
    formaterMontantDecimal(chaineDepuisCentimes(centimes), suffixe: 'FCFA') ??
    '—';

/// Ouvre « Nouvelle immobilisation » et DIT le résultat (`null` : annulée).
Future<void> ouvrirModaleImmobilisation(BuildContext context) async {
  final message = await showDialog<String>(
    context: context,
    barrierColor: AppColors.voileModale,
    builder: (_) => const _ModaleImmobilisation(),
  );
  if (message == null || !context.mounted) return;
  direTransverse(context, message, cle: const Key('compta-immo-creee'));
}

/// Ouvre la modale « Plan » : LECTURE seule, rien n'est écrit.
Future<void> ouvrirModalePlanAmortissement(
  BuildContext context,
  Immobilisation immobilisation,
) => showDialog<void>(
  context: context,
  barrierColor: AppColors.voileModale,
  builder: (_) => _ModalePlan(plan: planAmortissement(immobilisation)),
);

/// `JJ/MM/AAAA` -> `AAAA-MM-JJ`, ou `''` si la saisie n'a pas cette forme.
String jourIsoDepuisSaisie(String saisie) {
  final m = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(saisie.trim());
  return m == null ? '' : '${m.group(3)}-${m.group(2)}-${m.group(1)}';
}

class _ModaleImmobilisation extends ConsumerStatefulWidget {
  const _ModaleImmobilisation();

  @override
  ConsumerState<_ModaleImmobilisation> createState() =>
      _ModaleImmobilisationState();
}

class _ModaleImmobilisationState extends ConsumerState<_ModaleImmobilisation> {
  final _libelle = TextEditingController();
  final _valeur = TextEditingController();
  final _date = TextEditingController();
  final _duree = TextEditingController();
  String? _compte;
  String? _erreur;
  bool _envoi = false;

  @override
  void dispose() {
    _libelle.dispose();
    _valeur.dispose();
    _date.dispose();
    _duree.dispose();
    super.dispose();
  }

  Future<void> _choisirDate() async {
    final maintenant = DateTime.now();
    final choix = await showDatePicker(
      context: context,
      initialDate: maintenant,
      firstDate: DateTime(maintenant.year - 80),
      lastDate: DateTime(maintenant.year + 5),
    );
    if (choix != null) {
      setState(() => _date.text = formaterDate(choix));
    }
  }

  Future<void> _enregistrer() async {
    setState(() {
      _envoi = true;
      _erreur = null;
    });
    try {
      final i = await ref
          .read(immobilisationsDaoProvider)
          .creer(
            libelle: _libelle.text,
            valeurOrigineCentimes: centimesDepuisFrancsSaisis(_valeur.text),
            dureeAnnees: int.tryParse(_duree.text.trim()),
            dateMiseService: jourIsoDepuisSaisie(_date.text),
            compteImmobilisation: _compte,
          );
      ref.invalidate(immobilisationsProvider);
      if (mounted) {
        Navigator.of(
          context,
        ).pop(TextesModalesImmobilisations.enregistree(i.code));
      }
    } on RefusImmobilisation catch (e) {
      if (!mounted) return;
      setState(() {
        _envoi = false;
        _erreur = e.message;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _envoi = false;
        _erreur = TextesModalesImmobilisations.echecInattendu;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final valeur = styleTransverse(Tailles.t13);
    final comptes = [
      for (final c
          in ref.watch(planComptableCompletProvider).value ??
              const <CompteDuPlan>[])
        if (c.classe == '2') c,
    ];
    return CadreModaleComptabilite(
      cle: const Key('modale-immobilisation'),
      largeur: AppLayout.modaleImmobilisationComptable,
      titre: TextesModalesImmobilisations.titre,
      corps: [
        if (_erreur != null)
          refusModaleComptabilite(
            const Key('modale-immobilisation-refus'),
            _erreur!,
          ),
        ChampModaleComptabilite(
          libelle: TextesModalesImmobilisations.champIntitule,
          child: TextField(
            key: const Key('modale-immobilisation-libelle'),
            controller: _libelle,
            enabled: !_envoi,
            maxLength: 255,
            style: valeur,
            decoration: decorationModaleComptabilite(
              invite: TextesModalesImmobilisations.libelleInvite,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        ChampModaleComptabilite(
          libelle: TextesModalesImmobilisations.champCompte,
          child: DropdownButtonFormField<String>(
            key: const Key('modale-immobilisation-compte'),
            initialValue: _compte,
            isExpanded: true,
            isDense: true,
            style: valeur,
            decoration: decorationModaleComptabilite(),
            hint: Text(TextesModalesImmobilisations.choisir, style: valeur),
            items: [
              for (final c in comptes)
                DropdownMenuItem(
                  value: c.numero,
                  child: Text('${c.numero} — ${c.libelle}', style: valeur),
                ),
            ],
            onChanged: _envoi ? null : (v) => setState(() => _compte = v),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ChampModaleComptabilite(
                libelle: TextesModalesImmobilisations.champValeur,
                child: TextField(
                  key: const Key('modale-immobilisation-valeur'),
                  controller: _valeur,
                  enabled: !_envoi,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: valeur,
                  decoration: decorationModaleComptabilite(),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: ChampModaleComptabilite(
                libelle: TextesModalesImmobilisations.champDate,
                child: TextField(
                  key: const Key('modale-immobilisation-date'),
                  controller: _date,
                  enabled: !_envoi,
                  keyboardType: TextInputType.datetime,
                  style: valeur,
                  decoration:
                      decorationModaleComptabilite(
                        invite: TextesModalesImmobilisations.dateInviteSaisie,
                      ).copyWith(
                        suffixIcon: IconButton(
                          key: const Key('modale-immobilisation-calendrier'),
                          icon: const Icon(
                            Icons.calendar_today,
                            size: AppLayout.iconeChamp,
                          ),
                          onPressed: _envoi ? null : _choisirDate,
                        ),
                      ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        ChampModaleComptabilite(
          libelle: TextesModalesImmobilisations.champDuree,
          child: TextField(
            key: const Key('modale-immobilisation-duree'),
            controller: _duree,
            enabled: !_envoi,
            maxLength: 2,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: valeur,
            decoration: decorationModaleComptabilite(
              invite: TextesModalesImmobilisations.dureeInvite,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        EncadreTransverse(
          fond: PaletteMaitre.ambre50,
          bordure: PaletteMaitre.ambre200,
          padding: const EdgeInsets.all(AppSpacing.xsPlus),
          child: Text(
            TextesModalesImmobilisations.aide,
            style: styleTransverse(Tailles.t11, couleur: Ardoise.c500),
          ),
        ),
      ],
      pied: [
        BoutonStandard(
          key: const Key('modale-immobilisation-annuler'),
          libelle: TextesModalesImmobilisations.annuler,
          variante: VarianteBouton.fantome,
          onPressed: _envoi ? null : () => Navigator.of(context).pop(),
        ),
        BoutonStandard(
          key: const Key('modale-immobilisation-enregistrer'),
          libelle: TextesModalesImmobilisations.enregistrer,
          variante: VarianteBouton.primaire,
          onPressed: _envoi ? null : _enregistrer,
        ),
      ],
    );
  }
}

/// La modale « Plan » : une ligne par annuité, mise en service comprise.
class _ModalePlan extends StatelessWidget {
  const _ModalePlan({required this.plan});

  final PlanAmortissement plan;

  @override
  Widget build(BuildContext context) {
    final i = plan.immobilisation;
    final blanc = styleTransverse(
      Tailles.t13,
      poids: FontWeight.bold,
      couleur: AppColors.neutre0,
    );
    return CadreModaleComptabilite(
      cle: const Key('modale-plan-amortissement'),
      largeur: AppLayout.modalePlanAmortissement,
      titre: i.libelle,
      corps: [
        Text(
          TextesModalesImmobilisations.resume(i),
          key: const Key('modale-plan-resume'),
          style: styleTransverse(Tailles.t12, couleur: Ardoise.c500),
        ),
        const SizedBox(height: AppSpacing.xs),
        TableauTransverse(
          colonnes: const [
            (
              titre: TextesModalesImmobilisations.colExercice,
              alignement: TextAlign.left,
            ),
            (
              titre: TextesModalesImmobilisations.colBase,
              alignement: TextAlign.right,
            ),
            (
              titre: TextesModalesImmobilisations.colDotation,
              alignement: TextAlign.right,
            ),
            (
              titre: TextesModalesImmobilisations.colCumul,
              alignement: TextAlign.right,
            ),
            (
              titre: TextesModalesImmobilisations.colVnc,
              alignement: TextAlign.right,
            ),
          ],
          vide: '',
          lignes: [
            for (final l in plan.lignes)
              [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${l.annee}',
                        style: styleTransverse(
                          Tailles.t13,
                          poids: FontWeight.w600,
                          couleur: AppColors.navy,
                        ),
                      ),
                      if (l.prorata != null)
                        TextSpan(
                          text:
                              ' ${TextesModalesImmobilisations.prorata(l.prorata!)}',
                          style: styleTransverse(
                            Tailles.t11,
                            couleur: PaletteMaitre.ambre700,
                          ),
                        ),
                    ],
                  ),
                ),
                celluleTexte(
                  montantFcfa(l.baseCentimes),
                  alignement: TextAlign.right,
                  couleur: Ardoise.c500,
                ),
                celluleTexte(
                  montantFcfa(l.dotationCentimes),
                  alignement: TextAlign.right,
                  poids: FontWeight.w600,
                  couleur: Ardoise.c600,
                ),
                celluleTexte(
                  montantFcfa(l.cumulCentimes),
                  alignement: TextAlign.right,
                ),
                celluleTexte(
                  montantFcfa(l.vncCentimes),
                  alignement: TextAlign.right,
                ),
              ],
          ],
          pied: [
            Text(TextesModalesImmobilisations.total, style: blanc),
            const SizedBox.shrink(),
            Text(
              montantFcfa(plan.totalCentimes),
              textAlign: TextAlign.right,
              style: blanc,
            ),
            const SizedBox.shrink(),
            const SizedBox.shrink(),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          TextesModalesImmobilisations.planNote,
          style: styleTransverse(Tailles.t11, couleur: Ardoise.c500),
        ),
      ],
      pied: [
        BoutonStandard(
          key: const Key('modale-plan-fermer'),
          libelle: TextesModalesImmobilisations.fermer,
          variante: VarianteBouton.primaire,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
