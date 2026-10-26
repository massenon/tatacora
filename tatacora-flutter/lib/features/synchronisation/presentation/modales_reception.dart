/// Les modales de la partie « Réception » et des corrections d'envoi de
/// l'écran de synchronisation (26/10/2026) : détail d'un élément reçu avec sa
/// CAUSE, « Corriger » (ce qu'il faut faire, et le lien qui y mène),
/// détail d'une opération de la file avec son historique, et le formulaire de
/// correction de sa charge.
///
/// AJOUT du poste : aucune vue ne les a. Elles sont HORS de `<main>` : échelle
/// typographique déclarée ([Tailles]).
library;

import 'package:flutter/material.dart';

import '../../../core/format/formats.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/mesures_transverses.dart';
import '../../../shared_widgets/bouton_standard.dart';
import '../../restaurant/presentation/widgets/coquille_modale_restaurant.dart';
import '../../restaurant/presentation/widgets/textes_modale_restaurant.dart';
import '../domain/cause_envoi.dart';
import '../domain/descente_catalogue.dart';
import '../domain/journal_reception.dart';
import '../domain/operation_sync.dart';
import '../domain/suivi_synchronisation.dart';

/// Les mots de ces modales.
abstract final class TextesModalesReception {
  static const String fermer = 'Fermer';
  static const String annuler = 'Annuler';
  static const String relancer = 'Relancer';
  static const String corriger = 'Corriger';
  static const String detail = 'Détail';
  static const String cause = 'Cause';
  static const String commentCorriger = 'Comment corriger';
  static const String historique = 'Historique des tentatives';
  static const String corrigerEtRenvoyer = 'Corriger et renvoyer';
  static const String corrigerTitre = 'Corriger l’opération';
  static const String champsAucun =
      'Aucun champ de cette opération ne se corrige ici : suivez le conseil '
      'ci-dessus.';
  static const String champsIntro =
      'Modifiez ce qui est faux ; le serveur rejugera la charge à l’envoi et '
      'ses phrases s’afficheront ici.';
  static const String phrasesServeur = 'Ce que le serveur a signalé';

  static String ouvrir(String ecran) => 'Ouvrir « $ecran »';
  static String voirElements(String table) => 'Voir « $table » dans la liste';
  static const String voirFile = 'Voir la partie Envoi';

  static String sur(DateTime d) =>
      '${formaterDate(d.toLocal())} à '
      '${d.toLocal().hour.toString().padLeft(2, '0')}:'
      '${d.toLocal().minute.toString().padLeft(2, '0')}';
}

const TextStyle _saisie = TextStyle(
  fontFamily: AppTextStyles.police,
  fontSize: Tailles.t13,
  color: Ardoise.c800,
);

const TextStyle _erreur = TextStyle(
  fontFamily: AppTextStyles.police,
  fontSize: Tailles.t12,
  color: PaletteMaitre.rouge600,
);

InputDecoration _decoration() {
  final bord = OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadius.roundedLg),
    borderSide: const BorderSide(color: Ardoise.c300),
  );
  return InputDecoration(
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.sm,
      vertical: AppSpacing.xsPlus,
    ),
    border: bord,
    enabledBorder: bord,
  );
}

Widget _bouton(
  String cle,
  String libelle,
  VoidCallback? surAppui, {
  VarianteBouton variante = VarianteBouton.secondaire,
}) => BoutonStandard(
  key: Key(cle),
  libelle: libelle,
  variante: variante,
  taillePolice: Tailles.t13,
  margeHorizontale: AppSpacing.md,
  onPressed: surAppui,
);

Widget _ligne(String etiquette, String valeur, {Key? cle}) => Padding(
  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: MesuresTransverses.colonneModuleMatrice,
        child: Text(etiquette, style: TextesModaleRestaurant.aide),
      ),
      Expanded(
        child: Text(valeur, key: cle, style: TextesModaleRestaurant.corps),
      ),
    ],
  ),
);

Widget _bloc(String titre, String texte, {Key? cle, Color? couleur}) => Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    Text(titre, style: TextesModaleRestaurant.etiquette),
    const SizedBox(height: AppSpacing.unit),
    Text(
      texte,
      key: cle,
      style: TextesModaleRestaurant.corps.copyWith(color: couleur),
    ),
    const SizedBox(height: AppSpacing.sm),
  ],
);

/* ==================================================================== */
/* Réception : détail d'un élément                                        */
/* ==================================================================== */

/// Ce que l'utilisateur a choisi dans le détail d'un élément reçu.
enum GesteReception { aucun, relancer, corriger }

/// Le détail d'un élément reçu : sa fiche, sa CAUSE en français, comment la
/// corriger. [gestes] `false` : lecture seule (non administrateur).
Future<GesteReception?> ouvrirDetailReception(
  BuildContext context,
  EntreeJournalReception e, {
  required bool gestes,
}) => showDialog<GesteReception>(
  context: context,
  builder: (_) => _DetailReception(entree: e, gestes: gestes),
);

class _DetailReception extends StatelessWidget {
  const _DetailReception({required this.entree, required this.gestes});

  final EntreeJournalReception entree;
  final bool gestes;

  @override
  Widget build(BuildContext context) {
    final x = entree.explication;
    final ouverte = entree.issue.ouverte;
    return CoquilleModaleRestaurant(
      cle: const Key('recep-detail'),
      titre: entree.etiquette ?? entree.libelleTable,
      sousTitre: entree.libelleTable,
      largeur: MesuresTransverses.modaleDroits,
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _ligne(
            'Issue',
            entree.issue.libelle,
            cle: const Key('recep-detail-issue'),
          ),
          _ligne('Reçu le', TextesModalesReception.sur(entree.recuLe)),
          _ligne(
            'Dernière mise à jour',
            TextesModalesReception.sur(entree.derniereTentativeLe),
          ),
          _ligne(
            'Tentatives',
            '${entree.tentatives}',
            cle: const Key('recep-detail-tentatives'),
          ),
          if (entree.posteOrigine != null)
            _ligne('Saisi sur le poste', entree.posteOrigine!),
          if (entree.champ != null) _ligne('Champ en cause', entree.champ!),
          const SizedBox(height: AppSpacing.sm),
          if (ouverte) ...[
            _bloc(
              '${TextesModalesReception.cause} — ${x.titre}',
              x.phrase,
              cle: const Key('recep-detail-cause'),
              couleur: AppColors.erreur,
            ),
            _bloc(
              TextesModalesReception.commentCorriger,
              x.correction,
              cle: const Key('recep-detail-correction'),
            ),
          ] else
            _bloc(
              TextesModalesReception.cause,
              entree.motif.isEmpty ? x.phrase : entree.motif,
              cle: const Key('recep-detail-cause'),
            ),
        ],
      ),
      actions: [
        _bouton(
          'recep-detail-fermer',
          TextesModalesReception.fermer,
          () => Navigator.of(context).pop(GesteReception.aucun),
        ),
        if (ouverte && gestes) ...[
          _bouton(
            'recep-detail-relancer',
            TextesModalesReception.relancer,
            () => Navigator.of(context).pop(GesteReception.relancer),
          ),
          _bouton(
            'recep-detail-corriger',
            TextesModalesReception.corriger,
            () => Navigator.of(context).pop(GesteReception.corriger),
            variante: VarianteBouton.primaire,
          ),
        ],
      ],
    );
  }
}

/* ==================================================================== */
/* Réception : « Corriger »                                               */
/* ==================================================================== */

/// Le choix fait dans « Corriger ».
enum ChoixCorrection {
  fermer,
  relancer,
  ouvrirEcran,
  voirElementsLies,
  voirFileEnvoi,
}

/// « Corriger » un élément reçu : la cause exacte, la correction à faire, et
/// les gestes que le poste sait faire pour elle (ouvrir l'écran où l'on crée ce
/// qui manque, voir les éléments liés, voir la file d'envoi), puis relancer.
Future<ChoixCorrection?> ouvrirCorrectionReception(
  BuildContext context,
  EntreeJournalReception e,
) => showDialog<ChoixCorrection>(
  context: context,
  builder: (_) => _CorrectionReception(entree: e),
);

class _CorrectionReception extends StatelessWidget {
  const _CorrectionReception({required this.entree});

  final EntreeJournalReception entree;

  @override
  Widget build(BuildContext context) {
    final x = entree.explication;
    void choisir(ChoixCorrection c) => Navigator.of(context).pop(c);
    return CoquilleModaleRestaurant(
      cle: const Key('recep-correction'),
      titre: TextesModalesReception.corrigerTitre,
      sousTitre: '${entree.libelleTable} — ${entree.etiquette ?? x.titre}',
      largeur: MesuresTransverses.modaleDroits,
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _bloc(
            '${TextesModalesReception.cause} — ${x.titre}',
            x.phrase,
            cle: const Key('recep-correction-cause'),
            couleur: AppColors.erreur,
          ),
          _bloc(
            TextesModalesReception.commentCorriger,
            x.correction,
            cle: const Key('recep-correction-etapes'),
          ),
        ],
      ),
      actions: [
        _bouton(
          'recep-correction-fermer',
          TextesModalesReception.fermer,
          () => choisir(ChoixCorrection.fermer),
        ),
        if (x.action == ActionCorrection.ouvrirEcran && x.route != null)
          _bouton(
            'recep-correction-ecran',
            TextesModalesReception.ouvrir(x.libelleRoute ?? 'écran'),
            () => choisir(ChoixCorrection.ouvrirEcran),
          ),
        if (x.dependance != null)
          _bouton(
            'recep-correction-liens',
            TextesModalesReception.voirElements(
              libelleTableServeur(x.dependance!),
            ),
            () => choisir(ChoixCorrection.voirElementsLies),
          ),
        if (x.action == ActionCorrection.voirFileEnvoi)
          _bouton(
            'recep-correction-file',
            TextesModalesReception.voirFile,
            () => choisir(ChoixCorrection.voirFileEnvoi),
          ),
        _bouton(
          'recep-correction-relancer',
          TextesModalesReception.relancer,
          () => choisir(ChoixCorrection.relancer),
          variante: VarianteBouton.primaire,
        ),
      ],
    );
  }
}

/* ==================================================================== */
/* Envoi : détail d'une opération et son historique                       */
/* ==================================================================== */

/// Le détail d'une opération à traiter : sa cause, les phrases du serveur
/// champ par champ, et l'historique des tentatives de cet élément
/// ([historique] : toutes les opérations du même élément, de la plus ancienne
/// à la plus récente).
Future<void> ouvrirDetailOperation(
  BuildContext context, {
  required OperationSync operation,
  required CauseEnvoi cause,
  required List<OperationSync> historique,
}) => showDialog<void>(
  context: context,
  builder: (_) => CoquilleModaleRestaurant(
    cle: const Key('envoi-detail'),
    titre: libelleDocument(operation) ?? libelleTableOperation(operation),
    sousTitre: libelleTableOperation(operation),
    largeur: MesuresTransverses.modaleDroits,
    corps: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _ligne('Statut', libelleStatutOperation(operation.statut)),
        _ligne(
          'Tentatives',
          '${operation.tentatives}',
          cle: const Key('envoi-detail-tentatives'),
        ),
        _ligne(
          'Dernier code du serveur',
          operation.codeHttp == null ? '—' : '${operation.codeHttp}',
          cle: const Key('envoi-detail-http'),
        ),
        const SizedBox(height: AppSpacing.sm),
        _bloc(
          '${TextesModalesReception.cause} — ${cause.titre}',
          cause.motif.isEmpty ? cause.titre : cause.motif,
          cle: const Key('envoi-detail-cause'),
          couleur: AppColors.erreur,
        ),
        _bloc(
          TextesModalesReception.commentCorriger,
          cause.conseil,
          cle: const Key('envoi-detail-conseil'),
        ),
        if (cause.erreurs.isNotEmpty) ...[
          Text(
            TextesModalesReception.phrasesServeur,
            style: TextesModaleRestaurant.etiquette,
          ),
          const SizedBox(height: AppSpacing.unit),
          for (final (i, e) in cause.erreurs.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.unit),
              child: Text(
                '${e.libelle} : ${e.messages.join(' ')}',
                key: Key('envoi-detail-erreur-$i'),
                style: TextesModaleRestaurant.corps,
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
        ],
        Text(
          TextesModalesReception.historique,
          style: TextesModaleRestaurant.etiquette,
        ),
        const SizedBox(height: AppSpacing.unit),
        for (final (i, h) in historique.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.unit),
            child: Text(
              '${TextesModalesReception.sur(h.creeLe)} — '
              '${libelleStatutOperation(h.statut)}, ${h.tentatives} '
              'tentative(s)'
              '${h.codeHttp == null ? '' : ', code ${h.codeHttp}'}'
              '${(h.derniereErreur ?? '').isEmpty ? '' : ' : ${h.derniereErreur}'}',
              key: Key('envoi-detail-historique-$i'),
              style: TextesModaleRestaurant.corps,
            ),
          ),
      ],
    ),
    actions: [
      _bouton(
        'envoi-detail-fermer',
        TextesModalesReception.fermer,
        () => Navigator.of(context).pop(),
      ),
    ],
  ),
);

/* ==================================================================== */
/* Envoi : le formulaire de correction de la charge                       */
/* ==================================================================== */

/// Le formulaire GÉNÉRÉ du contrat de la charge de [operation] : un champ par
/// valeur que le registre sait corriger, validé avant l'envoi
/// ([corrigerCharge]). [enregistrer] reçoit la charge corrigée et crée
/// l'opération remplaçante ; il peut lever [StateError] (message affiché).
/// Rend `true` quand la correction est enregistrée.
Future<bool?> ouvrirCorrectionOperation(
  BuildContext context, {
  required OperationSync operation,
  required CauseEnvoi cause,
  required Future<void> Function(Map<String, Object?> charge) enregistrer,
}) => showDialog<bool>(
  context: context,
  builder: (_) => _CorrectionOperation(
    operation: operation,
    cause: cause,
    enregistrer: enregistrer,
  ),
);

class _CorrectionOperation extends StatefulWidget {
  const _CorrectionOperation({
    required this.operation,
    required this.cause,
    required this.enregistrer,
  });

  final OperationSync operation;
  final CauseEnvoi cause;
  final Future<void> Function(Map<String, Object?> charge) enregistrer;

  @override
  State<_CorrectionOperation> createState() => _EtatCorrectionOperation();
}

class _EtatCorrectionOperation extends State<_CorrectionOperation> {
  late final List<ChampEditable> _champs = champsEditables(widget.operation);
  late final Map<String, TextEditingController> _saisies = {
    for (final c in _champs) c.cle: TextEditingController(text: c.valeur),
  };
  Map<String, String> _erreurs = const {};
  String? _refus;
  bool _enCours = false;

  @override
  void dispose() {
    for (final s in _saisies.values) {
      s.dispose();
    }
    super.dispose();
  }

  Future<void> _valider() async {
    final v = corrigerCharge(widget.operation, {
      for (final e in _saisies.entries) e.key: e.value.text,
    });
    if (v.charge == null) {
      setState(() => _erreurs = v.erreurs);
      return;
    }
    setState(() {
      _erreurs = const {};
      _refus = null;
      _enCours = true;
    });
    try {
      await widget.enregistrer(v.charge!);
      if (mounted) Navigator.of(context).pop(true);
    } on StateError catch (e) {
      if (mounted) {
        setState(() {
          _refus = e.message;
          _enCours = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cause = widget.cause;
    return CoquilleModaleRestaurant(
      cle: const Key('envoi-correction'),
      titre: TextesModalesReception.corrigerTitre,
      sousTitre:
          libelleDocument(widget.operation) ??
          libelleTableOperation(widget.operation),
      largeur: MesuresTransverses.modaleDroits,
      refus: _refus ?? _erreurs['charge'],
      cleRefus: const Key('envoi-correction-refus'),
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _bloc(
            '${TextesModalesReception.cause} — ${cause.titre}',
            cause.motif,
            cle: const Key('envoi-correction-cause'),
            couleur: AppColors.erreur,
          ),
          _bloc(
            TextesModalesReception.commentCorriger,
            cause.conseil,
            cle: const Key('envoi-correction-conseil'),
          ),
          if (cause.erreurs.isNotEmpty) ...[
            Text(
              TextesModalesReception.phrasesServeur,
              style: TextesModaleRestaurant.etiquette,
            ),
            const SizedBox(height: AppSpacing.unit),
            for (final (i, e) in cause.erreurs.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.unit),
                child: Text(
                  '${e.libelle} : ${e.messages.join(' ')}',
                  key: Key('envoi-correction-erreur-serveur-$i'),
                  style: _erreur,
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
          ],
          if (_champs.isEmpty)
            Text(
              TextesModalesReception.champsAucun,
              key: const Key('envoi-correction-aucun-champ'),
              style: TextesModaleRestaurant.corps,
            )
          else ...[
            Text(
              TextesModalesReception.champsIntro,
              style: TextesModaleRestaurant.aide,
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final c in _champs) ...[
              EtiquetteChampRestaurant(
                texte: c.libelle,
                obligatoire: c.obligatoire,
              ),
              TextField(
                key: Key('envoi-saisie-${c.cle}'),
                controller: _saisies[c.cle],
                enabled: !_enCours,
                style: _saisie,
                decoration: _decoration(),
              ),
              if (c.aide != null) ...[
                const SizedBox(height: AppSpacing.unit),
                Text(c.aide!, style: TextesModaleRestaurant.aide),
              ],
              if (_erreurs[c.cle] != null) ...[
                const SizedBox(height: AppSpacing.unit),
                Text(
                  _erreurs[c.cle]!,
                  key: Key('envoi-erreur-${c.cle}'),
                  style: _erreur,
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
            ],
          ],
        ],
      ),
      actions: [
        _bouton(
          'envoi-correction-annuler',
          TextesModalesReception.annuler,
          _enCours ? null : () => Navigator.of(context).pop(false),
        ),
        _bouton(
          'envoi-correction-valider',
          TextesModalesReception.corrigerEtRenvoyer,
          _enCours || _champs.isEmpty ? null : _valider,
          variante: VarianteBouton.primaire,
        ),
      ],
    );
  }
}
