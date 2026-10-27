/// Providers de M13 Personnel & Paie — Riverpod exclusivement.
///
/// Vue Blade maîtresse (PA-183) : pwa/rh/paie.blade.php
///
/// ## Les écrans ne voient ni DAO ni table
///
/// Ils ne connaissent que les services de domaine et les entités. La
/// provenance de la donnée reste invisible à l'interface — ce qui compte
/// particulièrement ici, puisqu'elle est **exclusivement locale** et qu'aucun
/// écran ne doit un jour acquérir une branche « si connecté ».
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../comptabilite/presentation/exercice_consulte.dart';
import '../../../core/di/providers.dart';
import '../../../core/fichiers/enregistrement_export.dart';
import '../../../core/format/formats.dart';
import '../../../core/impression/export_etat_a4.dart';
import '../../../core/rbac/garde_acces.dart';
import '../../../core/rbac/regle_archivage.dart';
import '../../parametres/presentation/providers_options_systeme.dart';
import '../data/employe_dao.dart';
import '../data/paie_dao.dart';
import '../domain/entities/bulletin_paie.dart';
import '../domain/entities/employe.dart';
import '../domain/entities/periode_paie.dart';
import '../domain/entities/taux_paie.dart';
import '../domain/refus_rh.dart';
import '../domain/services/bulletin_paie_service.dart';
import '../domain/services/calcul_paie_service.dart';
import '../domain/services/livre_de_paie_service.dart';
import '../impression/etat_paie.dart';

/* ====================================================================== */
/* Câblage                                                                 */
/* ====================================================================== */

final employeDaoProvider = Provider<EmployeDao>(
  (ref) => EmployeDao(ref.watch(baseLocaleProvider)),
);

final paieDaoProvider = Provider<PaieDao>(
  (ref) => PaieDao(ref.watch(baseLocaleProvider)),
);

final bulletinPaieServiceProvider = Provider<BulletinPaieService>(
  (ref) => BulletinPaieService(
    ref.watch(paieDaoProvider),
    ref.watch(employeDaoProvider),
  ),
);

final livreDePaieServiceProvider = Provider<LivreDePaieService>(
  (ref) => LivreDePaieService(ref.watch(bulletinPaieServiceProvider)),
);

/// L'écriture est-elle permise sur M13 ?
///
/// Premier des trois niveaux de RBAC seulement : il évite de proposer ce qui
/// serait refusé, il ne protège rien. Ici, il n'y a pas de second niveau à
/// invoquer — le module est local — et c'est écrit plutôt que sous-entendu.
final peutEcrirePaieProvider = Provider<bool>(
  (ref) => ref.watch(droitsProvider).peutEcrire(ModuleTatacora.m13Rh),
);

/// Qui peut ARCHIVER le personnel (`rh/paie.blade.php` l.291, l.378).
///
/// La vue reçoit `peutArchiver` du composant (`AutoriseArchivage`) : droit `C`
/// sur M13 ET (`administrateur` / `super_admin` sans condition, tout autre rôle
/// SEULEMENT quand la bascule `activation_suppression` des Paramètres est
/// ouverte — elle naît FERMÉE). Depuis le 27/10/2026 (D272 levée par la
/// décision du PO « le poste fait comme le web ») cette règle est la règle
/// UNIQUE de `core/rbac/regle_archivage.dart`, appliquée à la session courante
/// par [peutArchiverProvider] : la Paie n'en porte plus de copie réduite aux
/// deux rôles. Ce provider ne sert qu'à RENDRE (bouton, cases) ; le geste
/// relit la règle à chaque appel ([exigerArchivagePaieProvider]).
final peutArchiverPaieProvider = Provider.autoDispose<bool>(
  (ref) => ref.watch(peutArchiverProvider(ModuleTatacora.m13Rh)),
);

/// `exigerArchivage()` : le droit d'archiver, relu À CHAQUE geste — à
/// l'OUVERTURE de la confirmation (`ouvrirArchivageEmployes`) comme à
/// l'EXÉCUTION (`archiverEmployes`) : la bascule peut se refermer entre les
/// deux, et le rôle est celui de la session, jamais celui du rendu. Lève
/// [ArchivageEmployeRefuse] aux mots du serveur (`pwa.archivage.refus_bascule`).
final exigerArchivagePaieProvider = Provider<Future<void> Function()>(
  (ref) => () async {
    final autorise = peutArchiver(
      droits: ref.read(droitsProvider),
      module: ModuleTatacora.m13Rh,
      role: ref.read(sessionProvider)?.role,
      suppressionActive: await lireSuppressionActive(
        ref.read(baseLocaleProvider),
      ),
    );
    if (!autorise) throw const ArchivageEmployeRefuse();
  },
);

/// Le bilan d'un archivage en lot : combien d'employés ont été archivés et les
/// refus du service (`Paie::archiverEmployes` : « perdre le lot entier pour une
/// ligne déjà traitée serait le refus d'opération de PA-65 appliqué à
/// l'envers »).
typedef BilanArchivageEmployes = ({int archives, List<String> refus});

/// `Paie::archiverEmployes` : le droit est exigé de nouveau, puis chaque
/// employé du lot est archivé par [EmployeDao.archiver] (écrivain unique, il
/// enfile dans sa transaction) ; un refus n'empêche pas les autres.
final archiverEmployesProvider =
    Provider<Future<BilanArchivageEmployes> Function(List<String>)>(
      (ref) => (ids) async {
        await ref.read(exigerArchivagePaieProvider)();
        final dao = ref.read(employeDaoProvider);
        var archives = 0;
        final refus = <String>[];
        for (final id in ids) {
          try {
            await dao.archiver(id);
            archives++;
          } on RefusRh catch (r) {
            refus.add(r.message);
          }
        }
        return (archives: archives, refus: refus);
      },
    );

/* ====================================================================== */
/* Amorçage — les DEUX référentiels ont ici leur appelant réel              */
/* ====================================================================== */

/// Installe l'organigramme et les taux confirmés, puis rend l'état réel.
///
/// ## Pourquoi une écriture au montage, et pourquoi elle est assumée
///
/// PA-128 : une table lue partout et écrite nulle part laisse un poste neuf
/// sans issue — sans services, aucune fiche ne se crée ; sans taux, aucun
/// bulletin ne se calcule, et le message « les taux ne sont pas paramétrés »
/// décrirait un état dont **aucun chemin ne permet de sortir**. L'installation
/// est idempotente, n'écrase aucune valeur existante, et n'écrit **jamais** le
/// taux de risques professionnels (PA-53).
///
/// L'état est ensuite lu tel quel : si une clé manque malgré tout, le bandeau
/// rouge du maître la nomme. Cette branche reste donc réelle, elle n'est pas
/// rendue inatteignable par l'amorçage.
final referentielPaieProvider = FutureProvider<EtatReferentiel>((ref) async {
  await ref.watch(employeDaoProvider).installerServices();
  await ref.watch(paieDaoProvider).installerReferentielConfirme();

  return ref.watch(bulletinPaieServiceProvider).etatReferentiel();
});

/* ====================================================================== */
/* Filtres — des colonnes de lecture, jamais des entrepôts                 */
/* ====================================================================== */

/// Les cinq onglets du maître.
enum OngletPaie {
  personnel('Personnel'),
  bulletins('Bulletins de paie'),
  livre('Livre de paie'),
  declarations('Déclarations'),
  bareme('Barèmes & taux');

  const OngletPaie(this.libelle);

  final String libelle;
}

/// Les quatre choix du filtre de statut.
///
/// ⚠ Le maître écrit ces libellés au **pluriel** : ce sont des ensembles, pas
/// des qualificatifs d'une ligne. « Sortis », jamais « Sorti ».
enum FiltreStatutPersonnel {
  actifs('Actifs'),
  tous('Tous'),
  sortis('Sortis'),
  sansCnss('Sans n° CNSS');

  const FiltreStatutPersonnel(this.libelle);

  final String libelle;
}

final ongletPaieProvider = NotifierProvider<_OngletPaieNotifier, OngletPaie>(
  _OngletPaieNotifier.new,
);

final class _OngletPaieNotifier extends Notifier<OngletPaie> {
  @override
  OngletPaie build() => OngletPaie.personnel;

  void definir(OngletPaie onglet) => state = onglet;
}

/// La période affichée, `AAAA-MM`.
///
/// Le mois courant par défaut, comme au composant. Une saisie illisible est
/// ramenée au mois courant à la lecture ([periodeValideProvider]) plutôt que
/// refusée : elle vient d'un champ, et une exception au milieu d'un rendu
/// n'apprend rien à personne.
final periodePaieProvider = NotifierProvider<_PeriodeNotifier, String>(
  _PeriodeNotifier.new,
);

final class _PeriodeNotifier extends Notifier<String> {
  @override
  // Sélecteur d'exercice global (PO, 20/10/2026) : le mois courant, ou le
  // dernier mois de l'exercice consulté quand il est passé.
  String build() =>
      PeriodePaie.deLaDate(ref.watch(horlogeExerciceConsulteProvider)()).code;

  void definir(String periode) => state = periode;
}

final periodeValideProvider = Provider<PeriodePaie>(
  (ref) =>
      PeriodePaie.depuisTexte(ref.watch(periodePaieProvider)) ??
      PeriodePaie.deLaDate(ref.watch(horlogeExerciceConsulteProvider)()),
);

final recherchePersonnelProvider = NotifierProvider<_TexteNotifier, String>(
  _TexteNotifier.new,
);

final class _TexteNotifier extends Notifier<String> {
  @override
  String build() => '';

  void definir(String terme) => state = terme;
}

final filtreServicePaieProvider =
    NotifierProvider<_FiltreServiceNotifier, String?>(
      _FiltreServiceNotifier.new,
    );

final class _FiltreServiceNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void definir(String? serviceId) => state = serviceId;
}

final filtreContratProvider =
    NotifierProvider<_FiltreContratNotifier, TypeContrat?>(
      _FiltreContratNotifier.new,
    );

final class _FiltreContratNotifier extends Notifier<TypeContrat?> {
  @override
  TypeContrat? build() => null;

  void definir(TypeContrat? contrat) => state = contrat;
}

/// « Actifs » par défaut — le choix du maître.
final filtreStatutPaieProvider =
    NotifierProvider<_FiltreStatutNotifier, FiltreStatutPersonnel>(
      _FiltreStatutNotifier.new,
    );

final class _FiltreStatutNotifier extends Notifier<FiltreStatutPersonnel> {
  @override
  FiltreStatutPersonnel build() => FiltreStatutPersonnel.actifs;

  void definir(FiltreStatutPersonnel statut) => state = statut;
}

/// La sélection de lignes de l'effectif, pour l'archivage en lot (l.305-333).
///
/// Des identifiants, jamais des objets : la liste se recompose à chaque filtre
/// et la sélection doit survivre à une recomposition. Mais elle n'est jamais
/// LUE telle quelle — voir [selectionAfficheePaieProvider].
final selectionPaieProvider =
    NotifierProvider<SelectionPaieNotifier, Set<String>>(
      SelectionPaieNotifier.new,
    );

final class SelectionPaieNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void basculer(String id) {
    final suivant = {...state};
    if (!suivant.remove(id)) suivant.add(id);
    state = suivant;
  }

  void definir(Set<String> ids) => state = {...ids};

  void vider() => state = const {};
}

/// Le brut du simulateur — 150 000 F, la valeur de départ du composant.
final brutSimuleProvider = NotifierProvider<_BrutSimuleNotifier, int>(
  _BrutSimuleNotifier.new,
);

final class _BrutSimuleNotifier extends Notifier<int> {
  @override
  int build() => 150000;

  void definir(int brut) => state = brut < 0 ? 0 : brut;
}

/// Le bulletin ouvert en consultation — **l'identifiant, pas l'objet**.
///
/// Le garder en mémoire ferait diverger la modale de la base dès la première
/// annulation.
final bulletinAfficheProvider =
    NotifierProvider<BulletinAfficheNotifier, String?>(
      BulletinAfficheNotifier.new,
    );

final class BulletinAfficheNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void definir(String? bulletinId) => state = bulletinId;
}

/* ====================================================================== */
/* Lectures                                                                */
/* ====================================================================== */

final servicesRhProvider = FutureProvider<List<ServiceRh>>((ref) async {
  // L'amorçage d'abord : sans lui, la liste serait vide au premier rendu et le
  // formulaire refuserait une création que rien n'empêche.
  await ref.watch(referentielPaieProvider.future);
  return ref.watch(employeDaoProvider).services();
});

final effectifTotalProvider = FutureProvider<int>((ref) async {
  await ref.watch(referentielPaieProvider.future);
  return (await ref.watch(employeDaoProvider).employes()).length;
});

/// L'effectif **retenu par les filtres affichés** — c'est cette liste que les
/// totaux et les indicateurs mesurent.
final employesAffichesProvider = FutureProvider<List<Employe>>((ref) async {
  await ref.watch(referentielPaieProvider.future);

  final tous = await ref.watch(employeDaoProvider).employes();
  final terme = ref.watch(recherchePersonnelProvider).trim().toLowerCase();
  final serviceId = ref.watch(filtreServicePaieProvider);
  final contrat = ref.watch(filtreContratProvider);
  final statut = ref.watch(filtreStatutPaieProvider);

  return tous
      .where((e) {
        if (serviceId != null && e.serviceId != serviceId) return false;
        if (contrat != null && e.typeContrat != contrat) return false;

        switch (statut) {
          case FiltreStatutPersonnel.actifs:
            if (!e.estEnPoste) return false;
          case FiltreStatutPersonnel.sortis:
            if (e.statut != StatutEmploye.parti) return false;
          case FiltreStatutPersonnel.sansCnss:
            if (!e.sansNumeroCnss) return false;
          case FiltreStatutPersonnel.tous:
            break;
        }

        if (terme.isNotEmpty) {
          final champs = '${e.nomComplet()} ${e.matricule} ${e.poste}'
              .toLowerCase();
          if (!champs.contains(terme)) return false;
        }

        return true;
      })
      .toList(growable: false);
});

final bulletinsDuMoisProvider = FutureProvider<List<BulletinPaie>>((ref) async {
  await ref.watch(referentielPaieProvider.future);
  return ref
      .watch(bulletinPaieServiceProvider)
      .bulletinsDuMois(ref.watch(periodeValideProvider).code);
});

/// Le bulletin de chaque salarié sur la période, par identifiant de salarié.
///
/// C'est lui qui décide si une ligne propose « Bulletin » ou « Établir ». Un
/// bouton qui n'ouvre rien empêcherait de savoir si la fonction manque ou si
/// l'écran est cassé.
final bulletinsParEmployeProvider = FutureProvider<Map<String, BulletinPaie>>((
  ref,
) async {
  final bulletins = await ref.watch(bulletinsDuMoisProvider.future);
  return {for (final b in bulletins) b.employe.id: b};
});

final employesSansBulletinProvider = FutureProvider<List<Employe>>((ref) async {
  await ref.watch(referentielPaieProvider.future);
  return ref
      .watch(bulletinPaieServiceProvider)
      .employesSansBulletin(ref.watch(periodeValideProvider).code);
});

final totauxLivreProvider = FutureProvider<TotauxLivre>((ref) async {
  await ref.watch(referentielPaieProvider.future);
  // Les bulletins du mois sont réobservés pour que le livre se recompose
  // après un établissement : sans cette dépendance, l'onglet resterait sur le
  // total d'avant sans que rien ne le signale.
  await ref.watch(bulletinsDuMoisProvider.future);

  return ref
      .watch(livreDePaieServiceProvider)
      .totaux(ref.watch(periodeValideProvider).code);
});

final declarationsProvider = FutureProvider<List<Declaration>>((ref) async {
  await ref.watch(bulletinsDuMoisProvider.future);
  return ref
      .watch(livreDePaieServiceProvider)
      .declarations(ref.watch(periodeValideProvider).code);
});

/// Le coût employeur de chaque salarié affiché — **en fourchette** (PA-53).
final coutParEmployeProvider = FutureProvider<Map<String, CoutEmployeur?>>((
  ref,
) async {
  final service = ref.watch(bulletinPaieServiceProvider);
  final employes = await ref.watch(employesAffichesProvider.future);

  final couts = <String, CoutEmployeur?>{};
  for (final employe in employes) {
    couts[employe.id] = await service.coutEmployeur(employe.salaireBase);
  }
  return couts;
});

/// Le coût de la masse salariale affichée — fourchette, jamais un chiffre.
final coutMasseProvider = FutureProvider<CoutEmployeur?>((ref) async {
  final employes = await ref.watch(employesAffichesProvider.future);
  final masse = employes.fold<int>(0, (somme, e) => somme + e.salaireBase);

  return ref.watch(bulletinPaieServiceProvider).coutEmployeur(masse);
});

final indicateursPaieProvider = FutureProvider<IndicateursPaie>((ref) async {
  return IndicateursPaie.composer(
    affiches: await ref.watch(employesAffichesProvider.future),
    effectifTotal: await ref.watch(effectifTotalProvider.future),
    totaux: await ref.watch(totauxLivreProvider.future),
    bulletinsManquants: (await ref.watch(
      employesSansBulletinProvider.future,
    )).length,
    coutMasse: await ref.watch(coutMasseProvider.future),
  );
});

final simulationProvider = FutureProvider<Simulation>((ref) async {
  await ref.watch(referentielPaieProvider.future);
  return ref
      .watch(bulletinPaieServiceProvider)
      .simuler(ref.watch(brutSimuleProvider));
});

final baremeAfficheProvider = FutureProvider<List<LigneBareme>>((ref) async {
  await ref.watch(referentielPaieProvider.future);
  return (await ref.watch(bulletinPaieServiceProvider).calcul())
      .baremeAffiche();
});

final bulletinCourantProvider = FutureProvider<BulletinPaie?>((ref) async {
  final id = ref.watch(bulletinAfficheProvider);
  if (id == null) return null;
  return ref.watch(paieDaoProvider).parId(id);
});

/// La sélection RESTREINTE aux lignes réellement affichées
/// (`selectionAffichee()` du composant, PA-119) : cocher tout l'effectif puis
/// changer de filtre ne doit pas archiver des lignes que l'écran ne montre
/// plus. Une ligne déjà partie n'est jamais retenue — `archiver` la refuserait.
final selectionAfficheePaieProvider = FutureProvider<List<String>>((ref) async {
  final affiches = await ref.watch(employesAffichesProvider.future);
  final choisis = ref.watch(selectionPaieProvider);

  return [
    for (final e in affiches)
      if (choisis.contains(e.id) && e.statut != StatutEmploye.parti) e.id,
  ];
});

/// Les lignes RÉELLEMENT AFFICHÉES de l'onglet courant (PA-119) — celles que
/// l'export emporte. Même contenu que `lignesExportables()` du composant, et
/// mêmes en-têtes que `PaieExport::entetesDe()`.
final etatPaieProvider = FutureProvider<EtatPaie>((ref) async {
  final onglet = ref.watch(ongletPaieProvider);
  final periode = ref.watch(periodeValideProvider);

  final morceaux = <String>[
    'Onglet : ${onglet.libelle}',
    'Période : ${periode.libelleLong}',
  ];

  final List<String> entetes;
  final List<List<String>> lignes;
  // Les colonnes de montant (FCFA au PDF) et celles que le PDF totalise.
  var montants = const <int>{};
  var totalisees = const <int>{};

  switch (onglet) {
    case OngletPaie.personnel:
      final employes = await ref.watch(employesAffichesProvider.future);
      entetes = const [
        'Matricule',
        'Employé',
        'Poste',
        'Service',
        'Contrat',
        'Embauche',
        'N° CNSS',
        'Salaire de base',
      ];
      lignes = [
        for (final e in employes)
          [
            e.matricule,
            e.nomComplet(),
            e.poste,
            e.serviceLibelle ?? tiretPaie,
            e.typeContrat?.code ?? tiretPaie,
            formaterDate(e.dateEmbauche),
            e.sansNumeroCnss ? 'absent' : e.numeroCnss!,
            e.salaireBase.toString(),
          ],
      ];
      montants = const {7};
      totalisees = const {7};

      // Le personnel est filtré par quatre contrôles : la portée les nomme
      // TOUS. (Le composant n'en nomme que deux ; en nommer davantage ne peut
      // pas tromper, en nommer moins le peut.)
      final serviceId = ref.watch(filtreServicePaieProvider);
      if (serviceId != null) {
        final services = await ref.watch(servicesRhProvider.future);
        for (final s in services) {
          if (s.id == serviceId) morceaux.add('Service : ${s.libelle}');
        }
      }
      final contrat = ref.watch(filtreContratProvider);
      if (contrat != null) morceaux.add('Contrat : ${contrat.code}');
      morceaux.add('Statut : ${ref.watch(filtreStatutPaieProvider).libelle}');
      final terme = ref.watch(recherchePersonnelProvider).trim();
      if (terme.isNotEmpty) morceaux.add('Recherche : $terme');

    case OngletPaie.bulletins:
      final bulletins = await ref.watch(bulletinsDuMoisProvider.future);
      entetes = const [
        'Matricule',
        'Employé',
        'Brut',
        'CNSS 3,6 %',
        'ITS',
        'Autres retenues',
        'Net à payer',
        'Charges patronales',
      ];
      lignes = [
        for (final b in bulletins)
          [
            b.employe.matricule,
            b.employe.nomComplet(),
            b.brut.toString(),
            b.cnssSalarie.toString(),
            b.its.toString(),
            b.autresRetenues.toString(),
            b.netAPayer.toString(),
            b.chargesPatronalesConfirmees.toString(),
          ],
      ];
      montants = const {2, 3, 4, 5, 6, 7};
      totalisees = const {2, 3, 4, 5, 6, 7};

    case OngletPaie.livre:
      final t = await ref.watch(totauxLivreProvider.future);
      entetes = const ['Rubrique', 'Montant'];
      // Sans bulletin, le livre n'a rien à dire : l'export se refuse plutôt
      // que d'écrire onze lignes à zéro.
      lignes = t.effectif == 0
          ? const []
          : [
              ['Salaires bruts soumis à cotisations', t.brut.toString()],
              ['CNSS — retenue salariale (3,6 %)', t.cnssSalarie.toString()],
              ['ITS retenu à la source', t.its.toString()],
              [
                'Autres retenues (avances, oppositions)',
                t.autresRetenues.toString(),
              ],
              ['NET À PAYER AUX SALARIÉS', t.net.toString()],
              [
                'CNSS — pension employeur (6,4 %)',
                t.ventilation.pension.toString(),
              ],
              [
                'CNSS — prestations familiales (9 %)',
                t.ventilation.prestationsFamiliales.toString(),
              ],
              [
                'VPS — Versement Patronal sur Salaires (4 %)',
                t.ventilation.vps.toString(),
              ],
              // FOURCHETTE : le taux n'est pas confirmé.
              [
                'CNSS — risques professionnels (1 % à 4 %)',
                '${t.fourchette.minimum} — ${t.fourchette.maximum}',
              ],
              [
                'Total charges patronales confirmées',
                t.patronalesConfirmees.toString(),
              ],
              ['COÛT TOTAL EMPLOYEUR', '${t.coutMin} — ${t.coutMax}'],
            ];
      montants = const {1};

    case OngletPaie.declarations:
      final declarations = await ref.watch(declarationsProvider.future);
      final t = await ref.watch(totauxLivreProvider.future);
      entetes = const ['Déclaration', 'Objet', 'Montant', 'Échéance', 'État'];
      lignes = t.effectif == 0
          ? const []
          : [
              for (final d in declarations)
                [
                  d.code,
                  d.libelle,
                  d.montant.toString(),
                  d.echeance == null ? tiretPaie : formaterDate(d.echeance!),
                  d.complet ? 'Montant arrêté' : 'Incomplet',
                ],
            ];
      montants = const {2};

    case OngletPaie.bareme:
      final bareme = await ref.watch(baremeAfficheProvider.future);
      entetes = const [
        'Tranche de revenu imposable',
        'Taux',
        'Impôt maximal de la tranche',
        'Cumul',
      ];
      lignes = [
        for (final l in bareme)
          [
            'de ${formaterFcfa(l.tranche.plancher)} à '
                '${formaterFcfa(l.tranche.plafond)}',
            '${l.tranche.taux} %',
            l.maximum.toString(),
            l.cumul.toString(),
          ],
      ];
      montants = const {2, 3};
  }

  return EtatPaie(
    cleOnglet: onglet.name,
    titreOnglet: onglet.libelle,
    entetes: entetes,
    lignes: lignes,
    portee: morceaux.join(' · '),
    colonnesMontant: montants,
    colonnesTotalisees: totalisees,
  );
});

/// L'export tableur — rend le **chemin** du fichier écrit, `null` : annulé
/// dans la fenêtre « Enregistrer sous » (14/10/2026).
///
/// Exposé comme action injectable, jamais appelé depuis un widget : un test de
/// widget n'a pas de greffon natif, et il doit exister un seul endroit où un
/// fichier est écrit. Un export silencieux est un export que personne ne
/// retrouve — le toast commun dit le nom du fichier.
final exporterPaieProvider = Provider<Future<String?> Function(EtatPaie)>(
  (ref) =>
      (etat) => ref
          .read(enregistrementExportProvider)
          .exporter(
            base: etat.prefixeFichier,
            type: TypeFichierEnregistre.csv,
            octets: etat.csvOctets(),
          ),
);

/// L'export « PDF Officiel A4 Imprimable » de l'onglet affiché — mêmes
/// colonnes et mêmes lignes que le CSV, en-tête lu des paramètres. Rend le
/// chemin écrit, `null` : annulé.
final exporterPaiePdfProvider = Provider<Future<String?> Function(EtatPaie)>(
  (ref) =>
      (etat) =>
          enregistrerEtatA4(ref, etat.etatA4(), base: etat.prefixeFichier),
);

/// Recharge tout ce qui dépend de la paie, après une écriture.
///
/// Une seule fonction plutôt qu'un `invalidate` recopié dans chaque geste :
/// oublier d'en invalider un laisserait un bulletin absent de l'écran alors
/// qu'il est en base — et le comptoir le rétablirait, sur une période où il
/// existe déjà.
void rafraichirPaie(WidgetRef ref) {
  ref
    ..invalidate(employesAffichesProvider)
    ..invalidate(effectifTotalProvider)
    ..invalidate(bulletinsDuMoisProvider)
    ..invalidate(bulletinsParEmployeProvider)
    ..invalidate(employesSansBulletinProvider)
    ..invalidate(totauxLivreProvider)
    ..invalidate(declarationsProvider)
    ..invalidate(coutParEmployeProvider)
    ..invalidate(coutMasseProvider)
    ..invalidate(indicateursPaieProvider)
    ..invalidate(bulletinCourantProvider)
    ..invalidate(selectionAfficheePaieProvider)
    ..invalidate(servicesRhProvider);
}
