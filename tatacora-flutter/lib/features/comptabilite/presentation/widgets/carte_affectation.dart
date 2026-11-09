import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/format/formats.dart';
import '../../../../core/rbac/garde_acces.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../transverse/presentation/widgets/briques_transverses.dart';
import '../../data/affectation_resultat_locale.dart';
import '../../domain/affectation_resultat.dart';
import '../../domain/entities/comptabilite.dart';
import '../../domain/messages_affectation.dart';
import '../../domain/montant_comptable.dart';
import '../../domain/refus_comptable.dart';
import '../providers_cloture.dart';
import 'modales_hub_comptabilite.dart';

/// Les mots de la carte qui ne sont pas des phrases de langue : la phrase
/// d'échec inattendu et le refus de droit.
abstract final class TextesCarteAffectation {
  static const String sansDroit =
      "Votre profil n'a pas le droit de modifier la comptabilité.";
  static const String echecInattendu =
      "L'affectation n'a pas pu être menée : rien n'a été modifié.";

  /// Une affectation passée au web ou sur un autre poste (v53) : ce poste la connaît,
  /// il n'en détient pas la pièce. Phrase propre au poste — la vue web n'a pas ce cas.
  static const String passeeAilleurs =
      'Cette affectation a été passée depuis le serveur ou depuis un autre poste : elle se contre-passe au même endroit, puis redescend ici à la synchronisation.';
}

String _t(String cle, [Map<String, String> v = const {}]) =>
    MessagesAffectation.dire('comptabilite_pwa.$cle', v);

String _fcfa(int centimes) =>
    formaterMontantDecimal(chaineDepuisCentimes(centimes), suffixe: 'FCFA') ??
    '—';

/// `d/m/Y H:i`.
String _dateHeure(DateTime d) {
  String deux(int n) => n.toString().padLeft(2, '0');
  return '${deux(d.day)}/${deux(d.month)}/${d.year} ${deux(d.hour)}:${deux(d.minute)}';
}

/// La carte « Affectation du résultat de l'exercice N-1 » de l'onglet
/// « Clôtures » (09/11/2026) : le résultat de l'exercice clôturé (lecture
/// seule), la date d'approbation, la ventilation (le report à nouveau reçoit le
/// reste), le contrôle EN DIRECT que le total égale le résultat, « Passer
/// l'affectation » avec confirmation ; passée, « Affectation passée le … par …
/// (pièce n° …) » et « Contre-passer l'affectation » (motif obligatoire).
///
/// Une extension de TATACORA : l'onglet du maître n'a pas ce bloc. Les mots sont
/// ceux de la vue web (`lang/fr/comptabilite_pwa.php`), relus du serveur par un
/// test ; les refus sont ceux d'`AffectationResultatService`, dits à la phrase du
/// serveur.
///
/// La carte est reconstruite (clé de la carte) quand l'exercice, le résultat ou
/// l'affectation active changent : la ventilation est alors ré-amorcée par la
/// proposition.
class CarteAffectationResultat extends ConsumerStatefulWidget {
  const CarteAffectationResultat({
    required this.exercice,
    required this.etat,
    super.key,
  });

  /// L'exercice clôturé dont le résultat s'affecte (N-1).
  final ExerciceComptable exercice;
  final EtatAffectation etat;

  @override
  ConsumerState<CarteAffectationResultat> createState() =>
      _CarteAffectationResultatState();
}

class _CarteAffectationResultatState
    extends ConsumerState<CarteAffectationResultat> {
  late final Map<String, TextEditingController> _champs;
  late final TextEditingController _date;
  final _motif = TextEditingController();
  String? _erreur;
  bool _envoi = false;

  @override
  void initState() {
    super.initState();
    final e = widget.etat;
    _champs = {
      for (final p in e.postes)
        p: TextEditingController(
          text: chaineDepuisCentimes(e.proposition[p] ?? 0),
        ),
    };
    _date = TextEditingController(text: e.dateParDefaut);
  }

  @override
  void dispose() {
    for (final c in _champs.values) {
      c.dispose();
    }
    _date.dispose();
    _motif.dispose();
    super.dispose();
  }

  bool get _peutEcrire =>
      ref.read(droitsProvider).peutEcrire(ModuleTatacora.m10Comptabilite);

  bool get _estComptable => ref.read(sessionProvider)?.role == roleAffectation;

  /// Les montants lisibles saisis, en centimes (un champ illisible compte pour
  /// zéro dans le contrôle en direct ; le serveur — et le moteur — le refusent
  /// au passage).
  int _centimes(String poste) {
    final brut = _champs[poste]?.text ?? '';
    if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(brut)) return 0;
    return centimesDepuisChaine(brut);
  }

  int get _total => widget.etat.postes.fold<int>(0, (t, p) => t + _centimes(p));

  /// Le report à nouveau reçoit LE RESTE : changer un autre poste le recalcule
  /// (jamais en dessous de zéro). Une saisie directe du report se garde.
  void _modifie(String poste) {
    if (poste != 'report_a_nouveau') {
      final autres = widget.etat.postes
          .where((p) => p != 'report_a_nouveau')
          .fold<int>(0, (t, p) => t + _centimes(p));
      final reste = widget.etat.resultatAbsoluCentimes - autres;
      _champs['report_a_nouveau']?.text = chaineDepuisCentimes(
        reste > 0 ? reste : 0,
      );
    }
    setState(() {});
  }

  Future<void> _faire(
    Future<String> Function(GestesAffectation gestes) geste, {
    required Key cleSucces,
  }) async {
    if (!_peutEcrire) {
      direTransverse(
        context,
        TextesCarteAffectation.sansDroit,
        cle: const Key('compta-affectation-sans-droit'),
      );
      return;
    }
    setState(() {
      _envoi = true;
      _erreur = null;
    });
    String succes;
    try {
      succes = await geste(GestesAffectation(ref));
    } on RefusComptable catch (e) {
      if (!mounted) return;
      setState(() {
        _envoi = false;
        _erreur = e.message;
      });
      return;
    } on Object {
      if (!mounted) return;
      setState(() {
        _envoi = false;
        _erreur = TextesCarteAffectation.echecInattendu;
      });
      return;
    }
    invaliderApresCloture(ref);
    if (!mounted) return;
    setState(() => _envoi = false);
    direTransverse(context, succes, cle: cleSucces);
  }

  Future<void> _confirmer() async {
    final e = widget.etat;
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: AppColors.voileModale,
      builder: (_) => CadreModaleComptabilite(
        cle: const Key('compta-affectation-confirmation'),
        largeur: 520,
        titre: _t('affectation_confirmer_titre', {'annee': '${e.annee}'}),
        corps: [
          Text(
            _t('affectation_confirmer_texte', {
              'montant': _fcfa(e.resultatAbsoluCentimes),
              'date': _date.text,
            }),
            style: styleTransverse(TaillesContenu.t13, couleur: Ardoise.c600),
          ),
        ],
        pied: [
          Builder(
            builder: (contexte) => BoutonTransverse(
              cle: const Key('compta-affectation-annuler'),
              libelle: _t('affectation_annuler'),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              onTap: () => Navigator.of(contexte).pop(false),
            ),
          ),
          Builder(
            builder: (contexte) => BoutonTransverse(
              cle: const Key('compta-affectation-confirmer'),
              libelle: _t('affectation_confirmer'),
              fond: AppColors.navy,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              onTap: () => Navigator.of(contexte).pop(true),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _faire(
      (g) => g.affecter(
        widget.exercice,
        saisie: {for (final p in postesAffectation) p: _champs[p]?.text ?? ''},
        date: _date.text,
      ),
      cleSucces: const Key('compta-affectation-passee'),
    );
  }

  InputDecoration get _decoration => InputDecoration(
    isDense: true,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.roundedMd),
      borderSide: const BorderSide(color: Ardoise.c200),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final e = widget.etat;
    final titre = styleTransverse(
      TaillesContenu.t14,
      poids: FontWeight.bold,
      couleur: AppColors.navy,
    );
    final note = styleTransverse(TaillesContenu.t12, couleur: Ardoise.c500);
    final etiquette = styleTransverse(
      TaillesContenu.t13,
      poids: FontWeight.w600,
      couleur: Ardoise.c700,
    );
    final perte = !e.estBenefice;

    Widget bouton(
      Key cle,
      String libelle,
      VoidCallback onTap, {
      bool plein = true,
      bool danger = false,
    }) => BoutonTransverse(
      cle: cle,
      libelle: libelle,
      fond: plein ? AppColors.navy : null,
      couleurContour: danger ? PaletteMaitre.rouge200 : Ardoise.c300,
      couleurTexteContour: danger ? PaletteMaitre.rouge700 : Ardoise.c700,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.smPlus,
      ),
      onTap: _envoi ? () {} : onTap,
    );

    final resultat = Container(
      key: const Key('compta-affectation-resultat'),
      padding: const EdgeInsets.all(AppSpacing.smPlus),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: Ardoise.c200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _t('affectation_resultat').toUpperCase(),
            style: styleTransverse(
              TaillesContenu.t11,
              poids: FontWeight.w600,
              couleur: Ardoise.c400,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            _fcfa(e.resultatCentimes),
            style: styleTransverse(
              TaillesContenu.t18,
              poids: FontWeight.bold,
              couleur: perte ? PaletteMaitre.rouge600 : AppColors.navy,
            ),
          ),
          Text(
            _t(
              perte
                  ? 'affectation_resultat_perte'
                  : 'affectation_resultat_benefice',
              {'compte': e.compteResultat},
            ),
            style: styleTransverse(TaillesContenu.t11, couleur: Ardoise.c400),
          ),
        ],
      ),
    );

    final active = e.active;
    final Widget corps;
    if (active != null) {
      corps = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _t('affectation_passee', {
              'date': _dateHeure(active.passeeLe),
              'auteur': active.auteur,
              'piece': active.numeroPiece,
            }),
            key: const Key('compta-affectation-passee-texte'),
            style: styleTransverse(TaillesContenu.t13, couleur: Ardoise.c600),
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final p in postesAffectation)
            if ((active.ventilation[p] ?? 0) > 0)
              Text(
                '• ${_t('affectation_passee_ventilation', {'poste': libellePoste(p), 'montant': _fcfa(active.ventilation[p]!)})}',
                style: styleTransverse(
                  TaillesContenu.t12,
                  couleur: Ardoise.c600,
                ),
              ),
          const SizedBox(height: AppSpacing.sm),
          if (active.parAilleurs)
            Text(
              TextesCarteAffectation.passeeAilleurs,
              key: const Key('compta-affectation-ailleurs'),
              style: note,
            )
          else ...[
            Text(
              _t('affectation_contrepasser'),
              style: styleTransverse(
                TaillesContenu.t13,
                poids: FontWeight.bold,
                couleur: AppColors.navy,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(_t('affectation_contrepasser_note'), style: note),
            const SizedBox(height: AppSpacing.xs),
          ],
          if (active.parAilleurs)
            const SizedBox.shrink()
          else if (_estComptable) ...[
            Text(_t('affectation_contrepasser_motif'), style: etiquette),
            const SizedBox(height: AppSpacing.xxs),
            TextField(
              key: const Key('compta-affectation-motif'),
              controller: _motif,
              enabled: !_envoi,
              minLines: 2,
              maxLines: 3,
              style: styleTransverse(TaillesContenu.t13),
              decoration: _decoration,
            ),
            const SizedBox(height: AppSpacing.xs),
            bouton(
              const Key('compta-affectation-contrepasser'),
              _t('affectation_contrepasser'),
              () => _faire(
                (g) => g.contrepasser(widget.exercice, _motif.text),
                cleSucces: const Key('compta-affectation-contrepassee'),
              ),
              plein: false,
              danger: true,
            ),
          ] else
            Text(
              _t('affectation_reserve_comptable'),
              key: const Key('compta-affectation-reservee'),
              style: styleTransverse(TaillesContenu.t12, couleur: Ardoise.c400),
            ),
        ],
      );
    } else if (!e.affectable) {
      corps = Text(
        _t('affectation_non_affectable', {'suivant': '${e.anneeAffectation}'}),
        key: const Key('compta-affectation-non-affectable'),
        style: note,
      );
    } else {
      final ecart = e.resultatAbsoluCentimes - _total;
      final juste = ecart == 0;
      corps = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_t('affectation_date'), style: etiquette),
          const SizedBox(height: AppSpacing.xxs),
          SizedBox(
            width: 220,
            child: TextField(
              key: const Key('compta-affectation-date'),
              controller: _date,
              enabled: !_envoi,
              style: styleTransverse(TaillesContenu.t13),
              decoration: _decoration,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            _t(
              e.estBenefice
                  ? 'affectation_ventilation'
                  : 'affectation_ventilation_perte',
            ),
            style: styleTransverse(
              TaillesContenu.t13,
              poids: FontWeight.bold,
              couleur: AppColors.navy,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final p in e.postes)
                SizedBox(
                  width: 280,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        libellePoste(p),
                        style: styleTransverse(
                          TaillesContenu.t13,
                          couleur: Ardoise.c700,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      TextField(
                        key: Key('compta-affectation-$p'),
                        controller: _champs[p],
                        enabled: !_envoi,
                        textAlign: TextAlign.right,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        style: styleTransverse(TaillesContenu.t13),
                        decoration: _decoration,
                        onChanged: (_) => _modifie(p),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Column(
            key: const Key('compta-affectation-controle'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_t('affectation_total')} : ${_fcfa(_total)}    '
                '${_t('affectation_reste')} : ${_fcfa(ecart)}',
                style: styleTransverse(
                  TaillesContenu.t13,
                  couleur: Ardoise.c600,
                ),
              ),
              const SizedBox(height: AppSpacing.demi),
              Text(
                juste
                    ? _t('affectation_somme_ok')
                    : _t('affectation_somme_ecart', {'ecart': _fcfa(ecart)}),
                key: const Key('compta-affectation-somme'),
                style: styleTransverse(
                  TaillesContenu.t13,
                  couleur: juste
                      ? PaletteMaitre.emeraude700
                      : PaletteMaitre.rouge600,
                ),
              ),
            ],
          ),
          if (e.estBenefice) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              e.plafondReserveLegaleAtteint
                  ? _t('affectation_reserve_plafond')
                  : e.reserveLegalePropose
                  ? _t('affectation_reserve_proposee')
                  : _t('affectation_reserve_indeterminee'),
              key: const Key('compta-affectation-reserve-note'),
              style: note,
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          if (_estComptable)
            bouton(
              const Key('compta-affectation-passer'),
              _t('affectation_passer'),
              _confirmer,
            )
          else
            Text(
              _t('affectation_reserve_comptable'),
              key: const Key('compta-affectation-reservee'),
              style: styleTransverse(TaillesContenu.t12, couleur: Ardoise.c400),
            ),
        ],
      );
    }

    return CarteTransverse(
      key: const Key('compta-affectation'),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_t('affectation_titre', {'annee': '${e.annee}'}), style: titre),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            _t('affectation_note', {
              'compte': e.compteResultat,
              'suivant': '${e.anneeAffectation}',
            }),
            style: note,
          ),
          const SizedBox(height: AppSpacing.sm),
          if (_erreur != null) ...[
            EncadreTransverse(
              fond: PaletteMaitre.rouge50,
              bordure: PaletteMaitre.rouge200,
              padding: const EdgeInsets.all(AppSpacing.smPlus),
              child: Text(
                _erreur!,
                key: const Key('compta-affectation-erreur'),
                style: styleTransverse(
                  TaillesContenu.t13,
                  couleur: PaletteMaitre.rouge800,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          Align(alignment: Alignment.centerLeft, child: resultat),
          const SizedBox(height: AppSpacing.sm),
          corps,
        ],
      ),
    );
  }
}
