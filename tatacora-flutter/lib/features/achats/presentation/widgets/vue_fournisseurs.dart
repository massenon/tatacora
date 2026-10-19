// Vue Blade maîtresse (PA-183) : pwa/achats/achats.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/impression/visas.dart';
import '../../../../core/rbac/garde_acces.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../shared_widgets/tableau_tatacora.dart';
import '../../../../shared_widgets/modale_export.dart';
import 'barre_outils_achats.dart';
import '../../../restaurant/presentation/widgets/corps_carte_commun.dart'
    show styleContenuCarte;
import '../../../restaurant/presentation/widgets/tableau_restaurant.dart'
    show ColonneRestaurant;
import '../../../parametres/presentation/providers_options_systeme.dart';
import '../../data/achats_api.dart';
import '../../domain/entities/archivage_fournisseur.dart';
import '../../domain/messages_achats.dart';
import '../../domain/entities/fournisseur.dart';
import '../../impression/etat_liste_achats.dart';
import '../providers_achats.dart';
import 'composants_crud_achats.dart';
import 'modale_archivage_achats.dart';
import 'modale_detail_fournisseur.dart';
import 'modale_fournisseur.dart';

/// L'onglet **« Fournisseurs »** — `pwa/achats/achats.blade.php` l.194-292.
///
/// Dans l'ordre de la vue : la barre d'outils (recherche, évaluation,
/// « Actualiser », « Exporter », « Ajouter fournisseur »), la barre de
/// sélection quand une ligne est cochée, puis le cadre — tableau à en-tête
/// navy de six colonnes plus la case, état vide, pied « Affichage de … ».
///
/// ## La source est LOCALE (09/10/2026)
///
/// `AchatsApi.fournisseurs()` lit `fournisseurs_local`. Sans DROIT de lecture
/// M7, le corps du tableau dit la raison ([CorpsIndisponibleAchats]) et le
/// décompte rend des tirets — jamais « Aucun résultat », qui affirmerait un
/// référentiel vide. Créer, modifier, archiver et restaurer ÉCRIVENT.
///
/// ## « Supprimer » ARCHIVE, et le droit est plus étroit que l'écriture (D63)
///
/// La vue ne propose « Supprimer » (la ligne, et le lien de la barre de
/// sélection) qu'à `peutArchiver()` : droit `C` sur M7 ET (administrateur,
/// super_admin, ou l'option « Suppression d'un enregistrement » ouverte en
/// Paramètres) — `AutoriseArchivage`. Le poste l'applique depuis le 12/10/2026 :
/// la règle est UNE (`regle_archivage.dart`), la bascule est lue par
/// `OptionsSysteme` (`suppressionActiveProvider`), le rôle vient de la session.
/// Jusqu'au 12/10/2026 le bouton suivait le seul droit `C` et son clic aboutissait
/// à un refus « décision du PO en attente » : ce motif est périmé et retiré.
///
/// « Restaurer » n'est PAS derrière la même garde (vue l.257-267) : l'écriture
/// suffit — fermer la bascule pendant qu'une fiche est aux archives ne doit
/// jamais l'y enfermer. Le fournisseur « supprimé » est ARCHIVÉ (`actif =
/// false`), pas effacé : il reste dans la liste, marqué « Archivé ».
class VueFournisseurs extends ConsumerStatefulWidget {
  const VueFournisseurs({super.key});

  @override
  ConsumerState<VueFournisseurs> createState() => _VueFournisseursState();
}

class _VueFournisseursState extends ConsumerState<VueFournisseurs> {
  final _recherche = TextEditingController();

  /// Les lignes cochées. Remise à zéro à chaque changement de page ou de
  /// filtre : la sélection porte sur CE QUI EST AFFICHÉ (vue l.372-374, même
  /// règle que l'export) — cocher puis changer de filtre ne doit pas agir sur
  /// des lignes que l'écran ne montre plus.
  final Set<String> _selection = {};

  @override
  void initState() {
    super.initState();
    _recherche.text = ref.read(rechercheFournisseurProvider);
  }

  @override
  void dispose() {
    _recherche.dispose();
    super.dispose();
  }

  bool get _peutEcrire =>
      ref.read(droitsProvider).peutEcrire(ModuleTatacora.m7Achats);

  void _revenirPage1() {
    ref.read(pageFournisseurProvider.notifier).definir(1);
    _selection.clear();
  }

  void _actualiser() {
    setState(_selection.clear);
    ref.invalidate(fournisseursProvider(null));
    ref.invalidate(tousLesFournisseursProvider);
  }

  /// Les lignes visées par un export : les cochées, sinon toutes celles de la
  /// page (`genererExport`, `Achats.php` l.495-500).
  List<Fournisseur> _visees(PageAchats<Fournisseur> page) {
    if (_selection.isEmpty) return page.elements;
    return [
      for (final f in page.elements)
        if (_selection.contains(f.id)) f,
    ];
  }

  ListeAchats? _liste(PageAchats<Fournisseur> page) {
    final lignes = _visees(page);
    if (lignes.isEmpty) return null;

    final evaluation = ref.read(evaluationFournisseurProvider);
    final terme = ref.read(rechercheFournisseurProvider).trim();

    return ListeAchats(
      titre: 'Référentiel fournisseurs',
      // pdf/fournisseurs-liste.blade.php (PA-195).
      visas: Visas.achats,
      portee: Portee(
        filtre: [
          evaluation == null
              ? 'Toutes les évaluations'
              : 'Évaluation : ${evaluation.libelle}',
          if (terme.isNotEmpty) 'recherche « $terme »',
          if (_selection.isNotEmpty) 'sélection de ${lignes.length} ligne(s)',
        ].join(' — '),
        lignesRapportees: lignes.length,
        // Une sélection est exportée en entier : elle ne se dit pas tronquée.
        totalServeur: _selection.isEmpty ? page.total : lignes.length,
      ),
      entetes: const [
        'Fournisseur',
        'Contact',
        'Catégorie fournie',
        'Conditions',
        'Évaluation',
      ],
      lignes: [
        for (final f in lignes)
          [
            f.raisonSociale,
            f.contact ?? '',
            f.categorie ?? '',
            f.conditionsPaiement ?? '',
            f.libelleEvaluation,
          ],
      ],
    );
  }

  /// « Exporter » : le format se choisit dans la modale PARTAGÉE
  /// (`pwa/partials/modale-export`), dont le sous-titre DIT sur quoi porte le
  /// document (PA-119) — `descriptionDuFiltre()`, `Achats.php` l.642-653.
  Future<void> _exporter(PageAchats<Fournisseur>? page, String? motif) async {
    final messager = ScaffoldMessenger.of(context);

    if (page == null) {
      // Pas de liste, pas de document : et la raison est celle de l'absence,
      // pas « la liste filtrée est vide ».
      messager.showSnackBar(
        SnackBar(
          key: const Key('achats-export-indisponible'),
          content: Text(motif ?? ''),
        ),
      );
      return;
    }

    final liste = _liste(page);
    if (liste == null) {
      messager.showSnackBar(
        const SnackBar(
          key: Key('export-refuse'),
          content: Text(messageExportVide),
        ),
      );
      return;
    }

    final format = await choisirFormatExport(
      context,
      titre: 'Exporter — Fournisseurs',
      sousTitre: _selection.isEmpty
          ? 'Le document portera exactement les ${liste.lignes.length} '
                'ligne(s) affichées, filtres compris.'
          : 'Le document portera exactement les ${liste.lignes.length} '
                'ligne(s) sélectionnées.',
    );
    if (format == null || !mounted) return;

    await enregistrerListeAchats(context, ref, liste, format);
  }

  Future<void> _ouvrirFormulaire({Fournisseur? fournisseur}) async {
    final enregistre = await ouvrirModaleFournisseur(
      context,
      fournisseur: fournisseur,
    );
    if (enregistre == null || !mounted) return;

    // Le référentiel est redemandé : la liste est paginée et triée par raison
    // sociale, et insérer la fiche en mémoire la poserait au mauvais endroit.
    _actualiser();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        // « enregistré sur ce poste », jamais « sur le serveur » (ce poste
        // n'en a aucun, 14/09/2026) ni « en attente de synchronisation » :
        // la table ne part nulle part. Le chemin est ATTEIGNABLE depuis le
        // 09/10/2026 (`AchatsDao.creerFournisseur`) et testé de bout en bout.
        content: Text(
          'Fournisseur « ${enregistre.raisonSociale} » enregistré sur ce '
          'poste.',
        ),
      ),
    );
  }

  Future<void> _voirDetail(Fournisseur fournisseur) async {
    final modifier = await ouvrirDetailFournisseur(
      context,
      fournisseur: fournisseur,
      peutEcrire: _peutEcrire,
    );
    if (modifier != true || !mounted) return;
    await _ouvrirFormulaire(fournisseur: fournisseur);
  }

  /// `Achats::confirmerArchivageFournisseur` puis `archiverFournisseurs` : une
  /// ligne (son identifiant) ou la sélection AFFICHÉE.
  ///
  /// ## Le lot vient du DAO, la modale rend les trois états de la vue
  ///
  /// Le droit d'archiver est exigé DÈS l'ouverture (`exigerArchivage`) : sans lui,
  /// un profil sans la bascule ouvrirait une modale que l'exécution refuserait. Le
  /// lot compose, pour chaque fiche ACTIVE visée, son verrou (une commande en
  /// cours l'engage) : BLOQUÉ (rien n'est archivable : le bouton disparaît),
  /// PARTIEL (le décompte des fiches conservées) ou NOMINAL.
  ///
  /// ## Une sélection vide ne fait rien ; une sélection d'ARCHIVÉS ouvre la modale
  /// bloquée
  ///
  /// Le serveur ne retourne que si la sélection (∩ lignes affichées) est vide. Une
  /// sélection qui ne porte que des fiches déjà archivées donne un lot vide, donc
  /// BLOQUÉ, sans motif : la modale s'ouvre sur « Archivage impossible » (D271).
  /// Jusqu'au 12/10/2026 ce poste affichait ici un message de son cru (« Les
  /// fournisseurs cochés sont déjà archivés. ») qu'aucune vue ne porte.
  Future<void> _confirmerArchivage(List<String> ids) async {
    if (ids.isEmpty) return;

    final ouverture = await ref.read(preparerArchivageProvider)(ids);
    if (!mounted) return;

    final LotArchivage lot;
    switch (ouverture) {
      case AchatsRecu(:final donnees):
        lot = donnees;
      case AchatsRefuse(:final motif):
        _toastRefus(motif);
        return;
      case AchatsInjoignable():
        _toastRefus(motifInjoignable);
        return;
    }

    final confirme = await ouvrirArchivageAchats(
      context,
      // Une ligne : son nom, en gras. Plusieurs : le nombre qui PART.
      element: lot.element,
      nombre: lot.nombre,
      messagesVerrou: lot.motifs,
      bloque: lot.bloque,
      conserves: lot.conserves,
    );
    if (confirme != true || !mounted) return;

    final resultat = await ref.read(archiverFournisseursProvider)(lot.ids);
    if (!mounted) return;

    switch (resultat) {
      case AchatsRecu(:final donnees):
        _actualiser();
        // Le succès ET le refus coexistent : un fournisseur devenu engagé entre
        // l'ouverture et le clic n'empêche pas les autres archivages du lot. La
        // vue les pose ensemble (bandeau vert, toast rouge) ; deux SnackBar se
        // mettraient en file et le refus resterait caché quatre secondes — ils
        // partent donc dans UNE seule, qui garde les deux messages.
        final succes = donnees.archives > 0
            ? MessagesAchats.archivesSucces(donnees.archives)
            : null;
        if (donnees.refus != null) {
          _toastRefus(donnees.refus!, succes: succes);
        } else if (succes != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              key: const Key('achats-archivage-succes'),
              content: Text(succes),
            ),
          );
        }
      case AchatsRefuse(:final motif):
        _toastRefus(motif);
      case AchatsInjoignable():
        _toastRefus(motifInjoignable);
    }
  }

  Future<void> _restaurer(Fournisseur fournisseur) async {
    final resultat = await ref.read(restaurerFournisseurProvider)(
      fournisseur.id,
    );
    if (!mounted) return;

    switch (resultat) {
      case AchatsRecu(:final donnees):
        _actualiser();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(MessagesAchats.restaure(donnees.raisonSociale)),
          ),
        );
      case AchatsRefuse(:final motif):
        _toastRefus(motif);
      case AchatsInjoignable():
        _toastRefus(motifInjoignable);
    }
  }

  /// Le refus rendu HORS de la modale (vue l.513-521) : le geste ferme la
  /// modale avant de rendre, un message posé dedans n'apparaîtrait jamais.
  /// [succes] accompagne le refus quand une partie du lot est partie.
  void _toastRefus(String motif, {String? succes}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        key: const Key('achats-archivage-refus'),
        backgroundColor: AppColors.erreur,
        content: succes == null
            ? Text(motif)
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(succes, key: const Key('achats-archivage-succes')),
                  Text(motif),
                ],
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final resultat = ref.watch(fournisseursProvider(null));
    final peutEcrire = ref
        .watch(droitsProvider)
        .peutEcrire(ModuleTatacora.m7Achats);
    // Qui peut ARCHIVER : la règle UNIQUE (droit C sur M7 ET un rôle
    // d'administration OU la bascule « Suppression d'un enregistrement »). La vue
    // la reçoit, elle ne la rejoue jamais.
    final peutArchiver = ref.watch(
      peutArchiverProvider(ModuleTatacora.m7Achats),
    );

    final (
      PageAchats<Fournisseur>? page,
      String? motif,
      bool charge,
    ) = switch (resultat) {
      AsyncData(:final value) => switch (value) {
        AchatsRecu(:final donnees) => (donnees, null, true),
        AchatsRefuse(:final motif) => (null, motif, true),
        AchatsInjoignable() => (null, motifInjoignable, true),
      },
      AsyncError(:final error) => (null, '$error', true),
      _ => (null, null, false),
    };

    // La sélection ne retient que des lignes affichées.
    final affichees = {
      for (final f in page?.elements ?? const <Fournisseur>[]) f.id,
    };
    final selection = _selection.intersection(affichees);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BarreOutilsCrudAchats(
          cle: const Key('outils-fournisseurs'),
          prefixeCle: 'fournisseurs',
          // Le placeholder de la vue (l.93), au mot.
          placeholder: 'Rechercher un fournisseur...',
          controleurRecherche: _recherche,
          onRecherche: (v) {
            ref.read(rechercheFournisseurProvider.notifier).definir(v);
            setState(_revenirPage1);
          },
          filtre: FiltreListeAchats<EvaluationFournisseur?>(
            cle: const Key('filtre-four'),
            valeur: ref.watch(evaluationFournisseurProvider),
            items: [
              const DropdownMenuItem<EvaluationFournisseur?>(
                child: Text('Toutes les évaluations'),
              ),
              for (final e in EvaluationFournisseur.values)
                DropdownMenuItem<EvaluationFournisseur?>(
                  value: e,
                  child: Text(e.libelle),
                ),
            ],
            onChanged: (e) {
              ref.read(evaluationFournisseurProvider.notifier).definir(e);
              setState(_revenirPage1);
            },
          ),
          onActualiser: _actualiser,
          onExporter: () => _exporter(page, motif),
          libelleAjout: 'Ajouter fournisseur',
          onAjout: peutEcrire ? () => _ouvrirFormulaire() : null,
        ),
        if (selection.isNotEmpty)
          BarreSelectionAchats(
            nombre: selection.length,
            // Le lien « Supprimer » de la barre n'existe QUE pour qui peut
            // archiver (vue l.183) : retiré, pas grisé. La sélection est
            // envoyée telle quelle, archivés compris — c'est le lot qui les
            // écarte.
            onSupprimer: peutArchiver
                ? () => _confirmerArchivage([
                    for (final f in page!.elements)
                      if (selection.contains(f.id)) f.id,
                  ])
                : null,
            onExporter: () => _exporter(page, motif),
            onEffacer: () => setState(_selection.clear),
          ),
        _Cadre(
          page: page,
          motif: motif,
          charge: charge,
          selection: selection,
          peutEcrire: peutEcrire,
          peutArchiver: peutArchiver,
          numeroPage: ref.watch(pageFournisseurProvider),
          onBasculerTout: (coche) => setState(() {
            _selection.clear();
            if (coche) _selection.addAll(affichees);
          }),
          onBasculer: (id, coche) => setState(() {
            coche ? _selection.add(id) : _selection.remove(id);
          }),
          onDetail: _voirDetail,
          onModifier: (f) => _ouvrirFormulaire(fournisseur: f),
          onSupprimer: (f) => _confirmerArchivage([f.id]),
          onRestaurer: _restaurer,
          onPage: (p) {
            ref.read(pageFournisseurProvider.notifier).definir(p);
            setState(_selection.clear);
          },
        ),
      ],
    );
  }
}

/// Le texte d'une liste dont la réponse est « injoignable » : jamais rendue
/// par `AchatsApi` depuis le 14/09/2026, mais le type la garde — et le
/// `switch` doit rester exhaustif.
const motifInjoignable =
    'La base du poste n’a pas répondu : le référentiel fournisseurs n’est pas '
    'affiché. Rien ne part dans une file : ce poste ne parle à aucun serveur.';

/// Le cadre `bg-white rounded-xl border border-slate-200 overflow-hidden`
/// (l.196) : le tableau, son état vide, son pied.
class _Cadre extends StatelessWidget {
  const _Cadre({
    required this.page,
    required this.motif,
    required this.charge,
    required this.selection,
    required this.peutEcrire,
    required this.peutArchiver,
    required this.numeroPage,
    required this.onBasculerTout,
    required this.onBasculer,
    required this.onDetail,
    required this.onModifier,
    required this.onSupprimer,
    required this.onRestaurer,
    required this.onPage,
  });

  final PageAchats<Fournisseur>? page;
  final String? motif;
  final bool charge;
  final Set<String> selection;
  final bool peutEcrire;
  final bool peutArchiver;
  final int numeroPage;
  final ValueChanged<bool> onBasculerTout;
  final void Function(String id, bool coche) onBasculer;
  final ValueChanged<Fournisseur> onDetail;
  final ValueChanged<Fournisseur> onModifier;
  final ValueChanged<Fournisseur> onSupprimer;
  final ValueChanged<Fournisseur> onRestaurer;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) {
    final lignes = page?.elements ?? const <Fournisseur>[];
    final toutCoche =
        lignes.isNotEmpty && lignes.every((f) => selection.contains(f.id));

    final Widget vide;
    if (!charge) {
      vide = const Padding(
        key: Key('fournisseurs-chargement'),
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (page == null) {
      vide = CorpsIndisponibleAchats(
        cle: const Key('fournisseurs-indisponible'),
        motif: motif ?? '',
      );
    } else {
      vide = const EtatVideTableauAchats();
    }

    final decompte = decompteAchats(
      disponible: page != null,
      total: page?.total ?? 0,
      numeroPage: numeroPage,
      affiches: lignes.length,
    );

    return CadreTableauAchats(
      colonnes: [
        ColonneRestaurant(
          '',
          enteteSpecial: CaseSelectionAchats(
            cle: const Key('achats-fournisseurs-tout'),
            valeur: toutCoche,
            etiquette: 'Tout sélectionner',
            surMarine: true,
            onChanged: onBasculerTout,
          ),
        ),
        // Les colonnes de la vue, dans son ordre et à ses mots (l.205-210).
        const ColonneRestaurant('Fournisseur'),
        const ColonneRestaurant('Contact'),
        const ColonneRestaurant('Catégorie fournie'),
        const ColonneRestaurant('Conditions'),
        const ColonneRestaurant('Évaluation'),
        const ColonneRestaurant('Actions', aDroite: true),
      ],
      vide: vide,
      lignes: [
        for (final f in lignes)
          [
            CaseSelectionAchats(
              cle: Key('fournisseur-case-${f.id}'),
              valeur: selection.contains(f.id),
              etiquette: 'Sélectionner cette ligne',
              onChanged: (c) => onBasculer(f.id, c),
            ),
            _Nom(fournisseur: f),
            // Article 7 : « — » quand la donnée n'existe pas. Une case vide se
            // lirait comme une donnée non chargée.
            _Texte(f.contact),
            _Texte(f.categorie),
            _Texte(f.conditionsPaiement),
            _Evaluation(fournisseur: f),
            _Actions(
              fournisseur: f,
              peutEcrire: peutEcrire,
              peutArchiver: peutArchiver,
              onDetail: onDetail,
              onModifier: onModifier,
              onSupprimer: onSupprimer,
              onRestaurer: onRestaurer,
            ),
          ],
      ],
      pied: PiedTableauAchats(
        debut: decompte.debut,
        fin: decompte.fin,
        total: decompte.total,
        page: numeroPage,
        derniere: page?.derniere ?? 1,
        onPage: onPage,
      ),
    );
  }
}

/// `font-medium text-slate-800`, et la pastille « Archivé » d'une fiche
/// archivée (l.220-229) : elle reste dans la liste, marquée.
class _Nom extends StatelessWidget {
  const _Nom({required this.fournisseur});

  final Fournisseur fournisseur;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          fournisseur.raisonSociale,
          key: Key('fournisseur-ligne-${fournisseur.id}'),
          style: styleContenuCarte(
            TaillesContenu.t13,
            poids: FontWeight.w500,
            couleur: Ardoise.c800,
          ),
        ),
        if (!fournisseur.actif) ...[
          const SizedBox(width: AppSpacing.unit), // ml-1
          PastilleStatut(
            'Archivé',
            key: Key('fournisseur-archive-${fournisseur.id}'),
            fond: AppColors.badgeGrisFond,
            texte: JetonsCssMaitre.neutre600,
          ),
        ],
      ],
    );
  }
}

class _Texte extends StatelessWidget {
  const _Texte(this.valeur);

  final String? valeur;

  @override
  Widget build(BuildContext context) => Text(
    valeur ?? '—',
    style: styleContenuCarte(TaillesContenu.t13, couleur: Ardoise.c600),
  );
}

/// Le badge d'évaluation, aux couleurs de `Achats::EVALUATIONS` (l.236-244).
///
/// Un fournisseur PAS ENCORE ÉVALUÉ rend « — », comme la vue : « Non évaluée »
/// n'est pas une note et n'a pas de pastille. Un code que ce client ne connaît
/// pas garde, lui, son code brut sur fond gris — la vue rend « — » dans ce cas,
/// et ce client préfère montrer le code (qui se voit) à un tiret qui dirait
/// « pas de note » d'une fiche qui en porte une.
class _Evaluation extends StatelessWidget {
  const _Evaluation({required this.fournisseur});

  final Fournisseur fournisseur;

  @override
  Widget build(BuildContext context) {
    if (!fournisseur.estEvalue) {
      return Text(
        '—',
        style: styleContenuCarte(TaillesContenu.t13, couleur: Ardoise.c600),
      );
    }

    final (couleur, fond) = switch (fournisseur.evaluation) {
      EvaluationFournisseur.excellent => (
        AppColors.succes,
        AppColors.badgeVertFond,
      ),
      EvaluationFournisseur.bon => (
        AppColors.infoBleuTexte,
        AppColors.badgeBleuFond,
      ),
      EvaluationFournisseur.moyen => (
        AppColors.gold,
        AppColors.reserveGoldFond,
      ),
      EvaluationFournisseur.aRevoir => (
        AppColors.erreur,
        AppColors.badgeRougeFond,
      ),
      null => (JetonsCssMaitre.neutre600, AppColors.badgeGrisFond),
    };

    return PastilleStatut(
      fournisseur.libelleEvaluation,
      key: Key('fournisseur-evaluation-${fournisseur.id}'),
      fond: fond,
      texte: couleur,
    );
  }
}

/// La colonne « Actions » (l.245-268) : « Voir le détail », « Modifier » pour
/// qui écrit, puis « Restaurer » sur une fiche archivée ou « Supprimer »
/// (archivage) sur une fiche active.
class _Actions extends StatelessWidget {
  const _Actions({
    required this.fournisseur,
    required this.peutEcrire,
    required this.peutArchiver,
    required this.onDetail,
    required this.onModifier,
    required this.onSupprimer,
    required this.onRestaurer,
  });

  final Fournisseur fournisseur;
  final bool peutEcrire;
  final bool peutArchiver;
  final ValueChanged<Fournisseur> onDetail;
  final ValueChanged<Fournisseur> onModifier;
  final ValueChanged<Fournisseur> onSupprimer;
  final ValueChanged<Fournisseur> onRestaurer;

  @override
  Widget build(BuildContext context) {
    final f = fournisseur;
    const ecart = SizedBox(width: AppSpacing.unit); // ml-1

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        BoutonLigneAchats(
          cle: Key('fournisseur-detail-${f.id}'),
          libelle: 'Voir le détail',
          onTap: () => onDetail(f),
        ),
        if (peutEcrire) ...[
          ecart,
          BoutonLigneAchats(
            cle: Key('fournisseur-modifier-${f.id}'),
            libelle: 'Modifier',
            onTap: () => onModifier(f),
          ),
          // « Restaurer » n'est PAS derrière la même garde que « Supprimer »
          // (vue l.257-267) : l'écriture suffit, et fermer la bascule pendant
          // qu'une fiche est aux archives ne doit jamais l'y enfermer.
          if (!f.actif) ...[
            ecart,
            BoutonLigneAchats(
              cle: Key('fournisseur-restaurer-${f.id}'),
              libelle: 'Restaurer',
              onTap: () => onRestaurer(f),
            ),
          ] else if (peutArchiver) ...[
            ecart,
            BoutonLigneAchats(
              cle: Key('fournisseur-supprimer-${f.id}'),
              libelle: 'Supprimer',
              danger: true,
              onTap: () => onSupprimer(f),
            ),
          ],
        ],
      ],
    );
  }
}
