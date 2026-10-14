import '../../features/crm/data/client_dao.dart';
import '../../features/depenses/data/depense_dao.dart';
import '../../features/depenses/domain/entities/depense.dart';
import '../../features/hebergement/data/reservation_dao.dart';
import '../../features/notifications/data/notifications_dao.dart';
import '../../features/pos/data/catalogue_dao.dart';
import '../../features/pos/data/tables_pos_dao.dart';
import '../../features/rh/data/employe_dao.dart';
import '../../features/rh/data/paie_dao.dart';
import '../../features/tourisme/data/tourisme_dao.dart';
import '../config/environnement.dart';
import '../database/app_database.dart';
import 'donnees_demonstration.dart';
import 'donnees_exploitation_demonstration.dart';

/// Amorce la base locale du flavor **démo** — `SEEDER_TEST_FLUTTER.md` §4.
///
/// ## Pourquoi ce fichier existe
///
/// Le flavor `demo` fonctionne sans backend. Jusqu'au 12/09/2026 il n'amorçait
/// **rien** : toutes les tables restaient vides, et son entête affirmait
/// pourtant qu'il « change la source des données ». Il n'en changeait aucune —
/// il interdisait seulement le réseau, c'est-à-dire la seule source qui
/// existait. Une démonstration commerciale s'y ouvrait sur un catalogue vide.
///
/// ## Cette fonction n'écrit RIEN elle-même
///
/// Chaque référentiel a **un seul auteur**, et c'est la règle la plus chère de
/// ce dépôt : cinq défauts de `database/seeders/` sont nés d'un second auteur
/// qui semait les mêmes libellés autrement. Le jeu de démonstration passe donc
/// par les auteurs existants — ceux-là mêmes qu'emprunte la descente réseau :
///
///  - le parc par [ReservationDao.alignerParc] ;
///  - les clients par [ClientDao.aligner] ;
///  - les trois catalogues par [CatalogueDao.alignerCatalogue] (PA-129) ;
///  - les réservations par [ReservationDao.enregistrer], via
///    `versEntiteSansLocal` — le chemin exact d'une réservation découverte sur
///    un autre poste ;
///  - les tables de salle par [TablesPosDao.toutes], qui sème son jeu initial
///    si et seulement si le référentiel est vide.
///
/// ## L'idempotence vient de l'UPSERT, pas d'un drapeau « déjà semé »
///
/// ⚠ La première version refusait de semer dès qu'un client existait, en
/// prenant sa présence pour la preuve d'un amorçage antérieur. **Le poste
/// d'essai l'a démentie le jour même** : il portait un compte, un client et
/// treize tables — et rien d'autre. Le lot entier était donc écarté au motif
/// qu'une seule ligne existait, et la démonstration restait vide, ce que cette
/// fonction existe précisément pour empêcher. Un drapeau posé sur une table
/// pour parler de six autres est un indicateur qui affirme un état qu'il n'a
/// pas vérifié (PA-59/60/61).
///
/// Les auteurs écrivent tous en `insertOnConflictUpdate` **par identifiant** :
/// réamorcer réécrit les lignes de démonstration et ne touche à rien d'autre.
/// Ce qui a été saisi sur le poste porte d'autres identifiants, et
/// [ClientDao.aligner] épargne en plus tout client en attente de
/// synchronisation — sur un poste hors ligne, c'est la seule copie qui existe.
///
/// ## L'ordre est la substance, pas une commodité
///
/// Le parc et les clients **avant** les réservations :
/// `reservations_local.client_id` et `unite_id` sont de vraies clés
/// étrangères, et l'ordre inverse rejoue exactement la violation de PA-127.
/// Une réservation qui ne trouve pas la sienne est **comptée**, jamais tue :
/// un compteur unique dirait « 4 » aussi bien quand tout passe que quand la
/// moitié du lot est écartée.
///
/// ## Ce qu'il ne sème JAMAIS
///
///  - **Aucun compte, aucun mot de passe.** « Aucun mot de passe par défaut
///    n'existe nulle part dans ce dépôt, et ne doit jamais y entrer » : un mot
///    de passe posé par un seeder est connu de quiconque lit le code. Le poste
///    de démonstration affiche donc son écran de premier démarrage et
///    l'opérateur choisit ses identifiants, comme en exploitation.
///  - **Les trois tables de stock** (`articles_local`, `points_stockage_local`,
///    `mouvements_stock_local`), vides : elles ont leur auteur depuis la v12
///    (`StocksDao`, 09/10/2026), mais aucun point, article ni mouvement n'est
///    semé — un stock « d'usine » serait plausible, donc invisible.
///  - **Aucun stock de boisson** : `stockDisponible` vaut `null`, et la carte
///    dira « non consulté ». Un chiffre semé ici serait un indicateur qui
///    affirme un état que personne n'a vérifié (PA-59/60/61).
Future<BilanAmorcageDemo> amorcerModeDemo(
  AppDatabase db, {
  bool? modeDemo,
  DateTime? maintenant,
}) async {
  // Le flavor se résout au BUILD (`--dart-define=ENV=demo`) : un test, lui,
  // tourne en `dev` et ne peut pas le changer. D'où ce paramètre — il ne
  // relâche pas la garde, il la rend éprouvable dans les deux sens.
  final autorise = modeDemo ?? Environnement.actuel.estHorsLigneIntegral;
  if (!autorise) {
    throw StateError(
      'amorcerModeDemo() est réservé au flavor demo : semer un jeu de '
      'démonstration sur un poste relié à un vrai backend y mêlerait des '
      'données fictives.',
    );
  }

  final reservations = ReservationDao(db);
  final parcEcrit = await reservations.alignerParc(parcDemonstration);
  final clientsEcrits = await ClientDao(db).aligner(clientsDemonstration);
  final catalogueEcrit = await CatalogueDao(db).alignerCatalogue(
    boissons: boissonsDemonstration,
    circuits: circuitsDemonstration,
    vehicules: vehiculesDemonstration,
  );

  final creeeLe = maintenant ?? DateTime.now();
  var reservationsEcrites = 0;
  var reservationsIgnorees = 0;
  for (final dto in reservationsDemonstration) {
    try {
      await reservations.enregistrer(dto.versEntiteSansLocal(creeeLe: creeeLe));
      reservationsEcrites++;
    } catch (_) {
      // Client ou unité absents : on écarte CETTE réservation et on la
      // compte. Laisser l'exception remonter emporterait le reste du lot,
      // exactement comme en PA-127.
      reservationsIgnorees++;
    }
  }

  final tables = await TablesPosDao(db).toutes();

  /* ------------------------------------------------------------------ */
  /* Les quatre modules d'exploitation — 14/09/2026                      */
  /*                                                                     */
  /* Mêmes règles que ci-dessus : aucun écrivain nouveau, tout passe par  */
  /* l'auteur existant de chaque table. Mais l'IDEMPOTENCE n'y est pas    */
  /* uniforme, et c'est ce qui commande la forme de ce bloc.             */
  /* ------------------------------------------------------------------ */

  // Guides : `enregistrerGuide` écrit en upsert PAR IDENTIFIANT, comme le
  // parc et les catalogues. Rejouable tel quel.
  //
  // ⚠ C'est aussi le seul écrivain de `guides_local` atteignable aujourd'hui.
  // Sur un poste RÉEL, la table reste sans auteur et aucune réservation de
  // circuit ne peut naître (`reservations_tour.guide_id` est NOT NULL) : ce
  // jeu de démonstration ne referme PAS ce trou, il le contourne pour la
  // démo seulement.
  final tourisme = TourismeDao(db);
  var guidesEcrits = 0;
  for (final g in guidesDemonstration) {
    await tourisme.enregistrerGuide(
      id: g.id,
      nom: g.nom,
      zoneCompetence: g.zone,
    );
    guidesEcrits++;
  }

  // Paie : les deux amorçages sont idempotents par construction — l'un par
  // le LIBELLÉ du service, l'autre par la clé du taux.
  final employesDao = EmployeDao(db, maintenant: () => creeeLe);
  await employesDao.installerServices();
  await PaieDao(db, maintenant: () => creeeLe).installerReferentielConfirme();

  // ⚠ À partir d'ici, les trois auteurs ne sont PAS idempotents : ils
  // frappent leur propre identifiant (`creer`, `enregistrer`) ou refusent le
  // doublon (`creerModele`). Un second amorçage dupliquerait donc l'effectif
  // et les dépenses, et lèverait sur les modèles.
  //
  // La garde est posée TABLE PAR TABLE, sur le vide de CETTE table — jamais
  // un drapeau global « déjà semé » : c'est la première version de cet
  // amorçage qui l'a essayé, et le poste d'essai l'a démentie le jour même.
  // Le précédent est `TablesPosDao.toutes`, qui ne sème que sur un
  // référentiel vide, pour la même raison.
  final services = await employesDao.services();
  var employesEcrits = 0;
  var employesIgnores = 0;
  if ((await employesDao.employes()).isEmpty) {
    for (final e in employesDemonstration) {
      // Résolution EXACTE du service. Un `?? services.first` en repli ferait
      // entrer le dossier sous une affectation que personne n'a choisie, et
      // la fiche paraîtrait juste (PA-161).
      final correspondants = services.where((s) => s.libelle == e.service);
      if (correspondants.isEmpty) {
        employesIgnores++;
        continue;
      }
      final service = correspondants.first;

      await employesDao.creer(
        nom: e.nom,
        prenom: e.prenom,
        poste: e.poste,
        serviceId: service.id,
        dateEmbauche: DateTime(e.anneeEmbauche, e.moisEmbauche, e.jourEmbauche),
        salaireBase: e.salaire,
        numeroCnss: e.cnss,
        typeContrat: e.contrat,
      );
      employesEcrits++;
    }
  }

  final depensesDao = DepenseDao(db, maintenant: () => creeeLe);
  var depensesEcrites = 0;
  if ((await depensesDao.depenses()).isEmpty) {
    for (final d in depensesDemonstration) {
      await depensesDao.enregistrerHistoriqueSansPiece(
        dateTransaction: creeeLe.subtract(Duration(days: d.ilYaJours)),
        tresorerie: d.tresorerie,
        libelle: d.libelle,
        lignes: [
          for (final l in d.lignes)
            SaisieLigneDepense(
              libelle: l.libelle,
              compteCharge: l.compte,
              nature: l.nature,
              montant: l.montant,
            ),
        ],
      );
      depensesEcrites++;
    }
  }

  final notifications = NotificationsDao(db);
  var modelesEcrits = 0;
  if ((await notifications.modeles()).isEmpty) {
    for (final m in modelesDemonstration) {
      await notifications.creerModele(
        declencheur: m.declencheur,
        canal: m.canal,
        contenuTemplate: m.contenu,
        objet: m.objet,
      );
      modelesEcrits++;
    }
  }

  return BilanAmorcageDemo(
    parc: parcEcrit,
    clients: clientsEcrits,
    catalogue: catalogueEcrit,
    reservations: reservationsEcrites,
    reservationsIgnorees: reservationsIgnorees,
    tables: tables.length,
    guides: guidesEcrits,
    employes: employesEcrits,
    employesIgnores: employesIgnores,
    depenses: depensesEcrites,
    modeles: modelesEcrits,
  );
}

/// Ce que l'amorçage a RÉELLEMENT écrit.
///
/// Un booléen « semé » dirait la même chose d'un lot complet et d'un lot où
/// seul le parc est passé — l'écran de démonstration s'ouvrirait sur un
/// catalogue vide sans que rien ne le signale.
final class BilanAmorcageDemo {
  const BilanAmorcageDemo({
    required this.parc,
    required this.clients,
    required this.catalogue,
    required this.reservations,
    required this.tables,
    this.reservationsIgnorees = 0,
    this.guides = 0,
    this.employes = 0,
    this.employesIgnores = 0,
    this.depenses = 0,
    this.modeles = 0,
  });

  /// Catégories et unités d'hébergement écrites.
  final int parc;

  final int clients;

  /// Boissons, circuits et véhicules confondus — le compte que rend
  /// [CatalogueDao.alignerCatalogue].
  final int catalogue;

  final int reservations;

  /// Réservations écartées faute de client ou d'unité. Jamais silencieuses.
  final int reservationsIgnorees;

  /// Les tables de salle PRÉSENTES après l'amorçage — pas celles écrites :
  /// [TablesPosDao.toutes] ne sème que sur un référentiel vide, et un poste
  /// dont l'exploitant a retiré des tables ne doit pas les voir revenir.
  final int tables;

  /// Guides écrits — upsert par identifiant, donc réécrits à chaque amorçage.
  final int guides;

  /// Salariés écrits. Zéro sur un poste dont l'effectif n'est pas vide : les
  /// trois auteurs qui suivent ne sont pas idempotents, et la garde porte sur
  /// le vide de LEUR table.
  final int employes;

  /// Salariés écartés faute de service correspondant. Jamais silencieux : un
  /// service renommé au référentiel doit se voir, pas se deviner.
  final int employesIgnores;

  final int depenses;
  final int modeles;

  int get total =>
      parc +
      clients +
      catalogue +
      reservations +
      guides +
      employes +
      depenses +
      modeles;

  /// Le lot est passé en entier — rien d'écarté, ni réservation ni salarié.
  bool get estComplet => reservationsIgnorees == 0 && employesIgnores == 0;
}
