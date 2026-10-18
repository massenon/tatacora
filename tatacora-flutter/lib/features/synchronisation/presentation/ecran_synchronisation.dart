import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/format/formats.dart';
import '../../../core/navigation/navigation_tatacora.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/mesures_transverses.dart';
import '../../../shared_widgets/bouton_standard.dart';
import '../../../shared_widgets/liste_paginee.dart';
import '../../transverse/domain/comptes_utilisateurs.dart';
import '../../transverse/presentation/widgets/briques_transverses.dart';
import '../domain/bilan_synchronisation.dart';
import '../domain/descente_catalogue.dart';
import '../domain/operation_sync.dart';
import '../domain/suivi_synchronisation.dart';
import '../data/controle_coherence.dart';
import 'providers_synchronisation.dart';

/// Les mots de l'écran de synchronisation (lot F2b, 15/10/2026). Honnêtes
/// (piège 1) : « synchronisé » ne se dit que de ce que le serveur a
/// confirmé.
abstract final class TextesEcranSynchronisation {
  /// Le contrôle de cohérence (P1-1, 18/10/2026).
  static const String sectionCoherence = 'Contrôle de cohérence';
  static const String coherenceExplication =
      'Compare, jour par jour sur les sept derniers jours, les documents que '
      'le serveur détient à ceux de ce poste (ventes, dépenses, factures, '
      'encaissements, réservations, règlements, mouvements de stock).';
  static const String controler = 'Contrôler maintenant';
  static String coherenceBilan(CoherenceMesuree m) {
    final jusqua = m.toutRecuJusquAu;
    if (m.ecarts.isEmpty) {
      return 'Ce poste a tout reçu jusqu’au ${_jourLisible(m.au)} : aucun '
          'écart sur ${m.tables.length} table(s) comparée(s).';
    }
    return jusqua == null
        ? '${m.ecarts.length} écart(s), dès le ${_jourLisible(m.du)}.'
        : 'Ce poste a tout reçu jusqu’au ${_jourLisible(jusqua)} ; '
              '${m.ecarts.length} écart(s) ensuite.';
  }

  static String ecart(EcartCoherence e) {
    String compte(CompteJour c) => c.total == null
        ? '${c.nombre}'
        : e.table == 'mouvements_stock'
        ? '${c.nombre} (quantité ${_centiemes(c.total!)})'
        : '${c.nombre} (${formaterFcfa(c.total! ~/ 100)})';
    return '• ${e.libelleTable}, ${_jourLisible(e.jour)} : serveur '
        '${compte(e.serveur)}, ce poste ${compte(e.poste)}';
  }

  static String ecartsEnAttente(int n) =>
      '$n opération(s) de ce poste attendent encore de partir : un écart '
      'peut venir d’elles.';

  static String _jourLisible(String iso) => formaterDate(DateTime.parse(iso));

  static String _centiemes(int c) =>
      c % 100 == 0 ? '${c ~/ 100}' : (c / 100).toStringAsFixed(2);

  static const titre = 'Synchronisation';
  static const sousTitre =
      'Ce que le poste envoie au serveur, ce qu\'il en reçoit, et ce qui reste '
      'à traiter. Le poste travaille sans réseau : rien ici ne bloque un autre '
      'écran.';
  static const sectionEtat = 'État';
  static const sectionFile = 'File d\'envoi';
  static const sectionDescente = 'Catalogue reçu du serveur';
  static const sectionATraiter = 'À traiter';
  static const sectionAnomalies = 'Signalements du serveur';
  static const synchroniser = 'Synchroniser maintenant';
  static const enCours =
      'Synchronisation en cours… Vous pouvez quitter cet écran : elle continue.';
  static const nonAppaire =
      'Ce poste n\'est pas appairé au serveur : rien ne part, rien ne descend. '
      'L\'appairage se fait dans Paramètres → Synchronisation (Administrateurs).';
  static const demonstration =
      'La démonstration ne se synchronise jamais : rien ne part, rien ne '
      'descend.';
  static String appaire(String serveur, String poste) =>
      'Appairé à $serveur — poste « $poste ».';
  static const aucunBilan =
      'Aucune synchronisation depuis l\'ouverture du logiciel.';
  static String bilan(BilanSynchronisation b) =>
      'Dernière synchronisation (cette session) : ${b.etat.libelle} '
      'Opérations jugées par le serveur : ${b.envoyees} — acceptées '
      '${b.synchronisees}, rejetées ${b.rejetees}, en conflit ${b.conflits}.';
  static const descenteJamais =
      'Le catalogue du serveur n\'est encore jamais descendu sur ce poste.';
  static String descente(BilanDescente d) {
    final quand = d.termineeLe == null
        ? ''
        : ' le ${formaterDate(d.termineeLe!.toLocal())} à '
              '${_heure(d.termineeLe!.toLocal())}';
    return 'Dernière descente$quand : ${d.etat.libelle} Reçus ${d.recus}, '
        'appliqués ${d.appliques}, conservés localement '
        '${d.conservesLocalement}, en attente de dépendance '
        '${d.enAttenteDeDependance}, refusés ${d.refuses}.';
  }

  static String archivesNonPortees(int n) =>
      '$n article(s) ou client(s) archivé(s) au serveur restent proposés sur '
      'ce poste : ces fiches n\'ont pas d\'archive locale.';
  static const conservesExplication =
      '« Conservé localement » : une modification faite sur ce poste attend '
      'encore de partir ; le serveur tranchera (dernière saisie gagnante) et '
      'sa version redescendra.';
  static String remplacees(int n) =>
      'dont $n rejetée(s) renvoyée(s) sous une nouvelle opération';
  static const aTraiterVide =
      'Aucune opération rejetée, en conflit ou bloquée.';
  static const anomaliesVide = 'Aucun signalement du serveur.';
  static const reserveAdministrateurs =
      '« Renvoyer » et « Débloquer » sont réservés aux Administrateurs.';
  static const renvoyer = 'Renvoyer';
  static const debloquer = 'Débloquer';
  static const renvoyee =
      'Opération renvoyée sous un nouvel identifiant : elle partira à la '
      'prochaine synchronisation. L\'opération rejetée reste dans '
      'l\'historique.';
  static const debloquee =
      'Opération débloquée : elle partira à la prochaine synchronisation.';
  static const colTable = 'Table';
  static const colDocument = 'Document';
  static const colDate = 'Date';
  static const colStatut = 'Statut';
  static const colMotif = 'Motif';
  static const colAnomalie = 'Signalement';
  static const colActions = 'Actions';
  static const lectureImpossible =
      'Lecture de la file impossible sur ce poste.';

  static String _heure(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';

  static String date(DateTime d) =>
      '${formaterDate(d.toLocal())} ${_heure(d.toLocal())}';
}

/// L'écran **Synchronisation** — route `/synchronisation` (lot F2b).
///
/// Un AJOUT du poste : la PWA parle au serveur en direct et n'a pas de file
/// (décision du PO du 15/10/2026, `classification-exemptions.json`). On y
/// arrive par le lien de Paramètres → Synchronisation ; la route est gardée
/// par le module Paramètres (`modulesDesRoutesHorsMenu`). Les gestes qui
/// changent la file (« Renvoyer », « Débloquer ») sont réservés aux
/// Administrateurs, comme l'appairage. « Synchroniser maintenant » est
/// ouvert à qui voit l'écran : il ne fait que hâter ce que le réveil
/// automatique fera dans cinq minutes.
class EcranSynchronisation extends ConsumerWidget {
  const EcranSynchronisation({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final admin = peutAdministrerComptes(ref.watch(sessionProvider)?.role);
    final lus = ref.watch(etatFileSynchronisationProvider);

    return PageTransverse(
      largeurMax: MesuresTransverses.pageLarge,
      enfants: [
        EnTeteTransverse(
          trace: IconeModule.parametres.trace,
          titre: TextesEcranSynchronisation.titre,
          sousTitre: TextesEcranSynchronisation.sousTitre,
        ),
        const _CarteEtat(),
        const SizedBox(height: AppSpacing.md),
        switch (lus) {
          AsyncData(:final value) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Compteurs(etat: value),
              const SizedBox(height: AppSpacing.md),
              _CarteDescente(bilan: value.derniereDescente),
              const SizedBox(height: AppSpacing.md),
              const _CarteCoherence(),
              const SizedBox(height: AppSpacing.md),
              _ATraiter(lignes: value.aTraiter, admin: admin),
              const SizedBox(height: AppSpacing.md),
              _Anomalies(operations: value.anomalies),
            ],
          ),
          AsyncError() => Text(
            TextesEcranSynchronisation.lectureImpossible,
            key: const Key('sync-ecran-lecture-impossible'),
            style: styleTransverse(
              TaillesContenu.t13,
              couleur: AppColors.erreur,
            ),
          ),
          _ => const LinearProgressIndicator(),
        },
      ],
    );
  }
}

Widget _titreSection(String texte) => Padding(
  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
  child: Text(
    texte,
    style: styleTransverse(
      TaillesContenu.t15,
      poids: FontWeight.w700,
      couleur: AppColors.navy,
    ),
  ),
);

Widget _ligneTexte(
  String texte, {
  Key? cle,
  Color couleur = AppColors.neutre700,
  FontWeight? poids,
}) => Text(
  texte,
  key: cle,
  style: styleTransverse(TaillesContenu.t13, couleur: couleur, poids: poids),
);

/* ==================================================================== */
/* État et action                                                        */
/* ==================================================================== */

class _CarteEtat extends ConsumerWidget {
  const _CarteEtat();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final interdite =
        ref.watch(synchronisationInterditeProvider) ||
        ref.watch(urlServeurSynchronisationProvider) == null;
    final appairage = ref.watch(appairageActuelProvider);
    final bilan = ref.watch(dernierBilanSynchronisationProvider);
    final enCours = ref.watch(synchronisationEnCoursProvider);
    final appaire = appairage.value != null;

    return CarteTransverse(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _titreSection(TextesEcranSynchronisation.sectionEtat),
          if (interdite)
            _ligneTexte(
              TextesEcranSynchronisation.demonstration,
              cle: const Key('sync-ecran-etat'),
            )
          else
            switch (appairage) {
              AsyncData(:final value) when value != null => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ligneTexte(
                    TextesEcranSynchronisation.appaire(
                      value.serveur,
                      value.posteId,
                    ),
                    cle: const Key('sync-ecran-etat'),
                  ),
                  if (value.refus != null)
                    _ligneTexte(
                      value.refus!.codeHttp == 403
                          ? EtatSynchronisation.posteNonReconnu.libelle
                          : EtatSynchronisation.jetonRefuse.libelle,
                      cle: const Key('sync-ecran-refus'),
                      couleur: AppColors.erreur,
                      poids: FontWeight.w600,
                    ),
                ],
              ),
              AsyncData() => _ligneTexte(
                TextesEcranSynchronisation.nonAppaire,
                cle: const Key('sync-ecran-etat'),
              ),
              _ => const LinearProgressIndicator(),
            },
          const SizedBox(height: AppSpacing.xs),
          _ligneTexte(
            bilan == null
                ? TextesEcranSynchronisation.aucunBilan
                : TextesEcranSynchronisation.bilan(bilan),
            cle: const Key('sync-ecran-bilan'),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              BoutonStandard(
                key: const Key('sync-ecran-maintenant'),
                libelle: TextesEcranSynchronisation.synchroniser,
                variante: VarianteBouton.primaire,
                onPressed: interdite || !appaire || enCours
                    ? null
                    : ref.read(synchroniserDepuisEcranProvider),
              ),
            ],
          ),
          if (enCours) ...[
            const SizedBox(height: AppSpacing.xs),
            const LinearProgressIndicator(key: Key('sync-ecran-progression')),
            const SizedBox(height: AppSpacing.xxs),
            _ligneTexte(TextesEcranSynchronisation.enCours),
          ],
        ],
      ),
    );
  }
}

/* ==================================================================== */
/* Compteurs de la file                                                  */
/* ==================================================================== */

class _Compteurs extends StatelessWidget {
  const _Compteurs({required this.etat});

  final EtatFileSynchronisation etat;

  @override
  Widget build(BuildContext context) {
    return CarteTransverse(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _titreSection(TextesEcranSynchronisation.sectionFile),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.xs,
            children: [
              for (final s in StatutOperationSync.values)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${etat.comptes[s] ?? 0}',
                      key: Key('sync-compteur-${s.code}'),
                      style: styleTransverse(
                        TaillesContenu.lg,
                        poids: FontWeight.w700,
                        couleur: AppColors.navy,
                      ),
                    ),
                    _ligneTexte(libelleStatutFile(s)),
                    if (s == StatutOperationSync.rejete && etat.remplacees > 0)
                      _ligneTexte(
                        TextesEcranSynchronisation.remplacees(etat.remplacees),
                        cle: const Key('sync-compteur-remplacees'),
                        couleur: AppColors.neutre500,
                      ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/* ==================================================================== */
/* Dernière descente                                                     */
/* ==================================================================== */

class _CarteDescente extends StatelessWidget {
  const _CarteDescente({required this.bilan});

  final BilanDescente? bilan;

  @override
  Widget build(BuildContext context) {
    final b = bilan;
    return CarteTransverse(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _titreSection(TextesEcranSynchronisation.sectionDescente),
          _ligneTexte(
            b == null
                ? TextesEcranSynchronisation.descenteJamais
                : TextesEcranSynchronisation.descente(b),
            cle: const Key('sync-ecran-descente'),
          ),
          if (b != null && b.archivesNonPortees > 0)
            _ligneTexte(
              TextesEcranSynchronisation.archivesNonPortees(
                b.archivesNonPortees,
              ),
              cle: const Key('sync-ecran-archives'),
            ),
          if (b != null && b.conservesLocalement > 0)
            _ligneTexte(TextesEcranSynchronisation.conservesExplication),
          if (b != null)
            for (final (i, m) in b.motifsRefus.indexed)
              _ligneTexte(
                '• $m',
                cle: Key('sync-ecran-refus-descente-$i'),
                couleur: AppColors.erreur,
              ),
        ],
      ),
    );
  }
}

/* ==================================================================== */
/* Contrôle de cohérence (P1-1)                                          */
/* ==================================================================== */

/// « Ce poste a tout reçu jusqu'au … » — le contrôle P1-1 de la
/// spécification : les comptes du serveur, par table et par jour, contre
/// ceux de ce poste. Lecture seule ; lancé à la demande (il exige le
/// serveur).
class _CarteCoherence extends ConsumerStatefulWidget {
  const _CarteCoherence();

  @override
  ConsumerState<_CarteCoherence> createState() => _EtatCarteCoherence();
}

class _EtatCarteCoherence extends ConsumerState<_CarteCoherence> {
  IssueCoherence? _issue;
  bool _enCours = false;

  Future<void> _controler() async {
    setState(() => _enCours = true);
    final issue = await ref
        .read(controleCoherenceProvider)
        .controler(aujourdHui: DateTime.now());
    if (mounted) {
      setState(() {
        _issue = issue;
        _enCours = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final issue = _issue;
    return CarteTransverse(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _titreSection(TextesEcranSynchronisation.sectionCoherence),
          _ligneTexte(TextesEcranSynchronisation.coherenceExplication),
          const SizedBox(height: AppSpacing.xs),
          Align(
            alignment: Alignment.centerLeft,
            child: BoutonStandard(
              key: const Key('sync-ecran-controler'),
              libelle: TextesEcranSynchronisation.controler,
              variante: VarianteBouton.secondaire,
              onPressed: _enCours ? null : _controler,
            ),
          ),
          if (issue != null) ...[
            const SizedBox(height: AppSpacing.xs),
            ...switch (issue) {
              CoherenceIndisponible(:final raison) => [
                _ligneTexte(
                  raison,
                  cle: const Key('sync-ecran-coherence-indisponible'),
                  couleur: AppColors.erreur,
                ),
              ],
              CoherenceMesuree() => [
                _ligneTexte(
                  TextesEcranSynchronisation.coherenceBilan(issue),
                  cle: const Key('sync-ecran-coherence-bilan'),
                  poids: FontWeight.w600,
                  couleur: issue.ecarts.isEmpty
                      ? AppColors.succes
                      : AppColors.erreur,
                ),
                for (final (i, e) in issue.ecarts.indexed)
                  _ligneTexte(
                    TextesEcranSynchronisation.ecart(e),
                    cle: Key('sync-ecran-ecart-$i'),
                  ),
                if (issue.enAttente > 0)
                  _ligneTexte(
                    TextesEcranSynchronisation.ecartsEnAttente(issue.enAttente),
                  ),
              ],
            },
          ],
        ],
      ),
    );
  }
}

/* ==================================================================== */
/* À traiter                                                             */
/* ==================================================================== */

class _ATraiter extends ConsumerWidget {
  const _ATraiter({required this.lignes, required this.admin});

  final List<OperationATraiter> lignes;
  final bool admin;

  Future<void> _geste(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function() action,
    String succes,
  ) async {
    String message;
    try {
      await action();
      message = succes;
    } on StateError catch (e) {
      message = e.message;
    }
    if (!context.mounted) return;
    ref.invalidate(etatFileSynchronisationProvider);
    direTransverse(context, message);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dao = ref.watch(operationsSyncDaoProvider);
    return CarteTransverse(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _titreSection(TextesEcranSynchronisation.sectionATraiter),
          if (!admin && lignes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: _ligneTexte(
                TextesEcranSynchronisation.reserveAdministrateurs,
                cle: const Key('sync-ecran-reserve'),
              ),
            ),
          ListePaginee<OperationATraiter>(
            elements: lignes,
            prefixeCle: 'sync-a-traiter-pagination',
            masquerSiVide: true,
            constructeur: (context, page) => TableauTransverse(
              colonnes: const [
                (
                  titre: TextesEcranSynchronisation.colTable,
                  alignement: TextAlign.left,
                ),
                (
                  titre: TextesEcranSynchronisation.colDocument,
                  alignement: TextAlign.left,
                ),
                (
                  titre: TextesEcranSynchronisation.colDate,
                  alignement: TextAlign.left,
                ),
                (
                  titre: TextesEcranSynchronisation.colStatut,
                  alignement: TextAlign.left,
                ),
                (
                  titre: TextesEcranSynchronisation.colMotif,
                  alignement: TextAlign.left,
                ),
                (
                  titre: TextesEcranSynchronisation.colActions,
                  alignement: TextAlign.right,
                ),
              ],
              vide: TextesEcranSynchronisation.aTraiterVide,
              cleVide: const Key('sync-a-traiter-vide'),
              lignes: [
                for (final l in page)
                  _ligne(
                    context,
                    ref,
                    l,
                    renvoyer: () => _geste(
                      context,
                      ref,
                      () => dao.renvoyer(l.operation.uuidOperation),
                      TextesEcranSynchronisation.renvoyee,
                    ),
                    debloquer: () => _geste(
                      context,
                      ref,
                      () => dao.debloquer(l.operation.uuidOperation),
                      TextesEcranSynchronisation.debloquee,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _ligne(
    BuildContext context,
    WidgetRef ref,
    OperationATraiter l, {
    required VoidCallback renvoyer,
    required VoidCallback debloquer,
  }) {
    final o = l.operation;
    final uuid = o.uuidOperation;
    final Widget action = switch (o.statut) {
      StatutOperationSync.rejete when admin => BoutonStandard(
        key: Key('sync-renvoyer-$uuid'),
        libelle: TextesEcranSynchronisation.renvoyer,
        compact: true,
        onPressed: renvoyer,
      ),
      StatutOperationSync.bloque when admin && l.debloquable => BoutonStandard(
        key: Key('sync-debloquer-$uuid'),
        libelle: TextesEcranSynchronisation.debloquer,
        compact: true,
        onPressed: debloquer,
      ),
      _ => const SizedBox.shrink(),
    };
    return [
      _ligneTexte(libelleTableOperation(o), cle: Key('sync-table-$uuid')),
      _ligneTexte(libelleDocument(o) ?? '—', cle: Key('sync-document-$uuid')),
      _ligneTexte(TextesEcranSynchronisation.date(o.creeLe)),
      _ligneTexte(
        libelleStatutOperation(o.statut),
        cle: Key('sync-statut-$uuid'),
      ),
      _ligneTexte(motifOperation(o), cle: Key('sync-motif-$uuid')),
      Align(alignment: Alignment.centerRight, child: action),
    ];
  }
}

/* ==================================================================== */
/* Signalements du serveur (lecture seule)                               */
/* ==================================================================== */

class _Anomalies extends StatelessWidget {
  const _Anomalies({required this.operations});

  final List<OperationSync> operations;

  @override
  Widget build(BuildContext context) {
    return CarteTransverse(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _titreSection(TextesEcranSynchronisation.sectionAnomalies),
          ListePaginee<OperationSync>(
            elements: operations,
            prefixeCle: 'sync-anomalies-pagination',
            masquerSiVide: true,
            constructeur: (context, page) => TableauTransverse(
              colonnes: const [
                (
                  titre: TextesEcranSynchronisation.colTable,
                  alignement: TextAlign.left,
                ),
                (
                  titre: TextesEcranSynchronisation.colDocument,
                  alignement: TextAlign.left,
                ),
                (
                  titre: TextesEcranSynchronisation.colDate,
                  alignement: TextAlign.left,
                ),
                (
                  titre: TextesEcranSynchronisation.colAnomalie,
                  alignement: TextAlign.left,
                ),
              ],
              vide: TextesEcranSynchronisation.anomaliesVide,
              cleVide: const Key('sync-anomalies-vide'),
              lignes: [
                for (final o in page)
                  [
                    _ligneTexte(libelleTableOperation(o)),
                    _ligneTexte(libelleDocument(o) ?? '—'),
                    _ligneTexte(TextesEcranSynchronisation.date(o.creeLe)),
                    _ligneTexte(
                      anomaliesDe(o).map(libelleAnomalie).join(' ; '),
                      cle: Key('sync-anomalie-${o.uuidOperation}'),
                    ),
                  ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
