import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
// Les classes de tables doivent être dans la portée du fichier : `@DriftAccessor`
// les résout par leur type, et un import de `app_database.dart` seul ne les
// réexporte pas. Sans cette ligne, le mixin généré est VIDE — sans erreur de
// génération, ce qui rend le diagnostic trompeur (leçon `reservation_dao.dart`).
import '../../../core/database/tables/rh_tables.dart';
import '../../synchronisation/data/documents_autres_postes.dart';
import '../../synchronisation/data/operations_sync_dao.dart';
import '../../synchronisation/domain/charges_synchronisation.dart';
import '../../synchronisation/domain/operation_sync.dart';
import '../domain/entities/employe.dart';
import '../domain/entities/taux_paie.dart';
import '../domain/refus_rh.dart';

part 'employe_dao.g.dart';

/// Accès Drift au dossier du personnel — **unique point d'écriture** sur
/// `employes_local`.
///
/// Vue Blade maîtresse (PA-183) : pwa/rh/paie.blade.php
///
/// ## Le DAO ne parle qu'entités
///
/// Aucune méthode ne rend un `EmployesLocalData`. La forme des tables ne
/// franchit pas cette frontière : sans quoi renommer une colonne casserait un
/// widget, et la couche présentation saurait qu'une base existe.
///
/// ## Aucune entrée n'est mise en file de synchronisation
///
/// `TABLES_SYNCHRONISABLES` ne connaît que `reservations` et `clients` : une
/// opération sur `employes` serait refusée à chaque tentative, et le poste
/// afficherait « en attente de synchronisation » sur quelque chose qui ne
/// partira jamais (PA-59/60/61). L'écran dit « enregistré sur ce poste ».
///
/// ## Aucune suppression
///
/// Un départ passe par [archiver] — `statut = 'parti'`. RG-15 l'exige : un
/// bulletin doit continuer de porter le nom de son bénéficiaire.
///
/// @see EF-M13-01 Dossier du personnel
/// @see RG-15 Journalisation des opérations
@DriftAccessor(tables: [EmployesLocal, ServicesRhLocal])
class EmployeDao extends DatabaseAccessor<AppDatabase> with _$EmployeDaoMixin {
  EmployeDao(super.db, {Uuid? uuid, DateTime Function()? maintenant})
    : _uuid = uuid ?? const Uuid(),
      _maintenant = maintenant ?? DateTime.now;

  final Uuid _uuid;

  /// Injectable : le matricule porte l'année courante, et un test qui dépend
  /// de l'horloge réelle échoue un jour sur 365 — le 1er janvier.
  final DateTime Function() _maintenant;

  static const String _prefixeMatricule = 'EMP';
  static const int _largeurMatricule = 5;

  /* ================================================================== */
  /* Référentiel des services                                            */
  /* ================================================================== */

  Future<List<ServiceRh>> services() async {
    final lignes = await (select(
      servicesRhLocal,
    )..orderBy([(s) => OrderingTerm.asc(s.libelle)])).get();

    return lignes
        .map((s) => ServiceRh(id: s.id, libelle: s.libelle))
        .toList(growable: false);
  }

  /// Installe l'organigramme du gîte — **idempotent, et unique auteur**.
  ///
  /// Sans cet appel, `services_rh_local` serait lue par la fiche employé et
  /// écrite par personne : aucun dossier ne pourrait être créé sur un poste
  /// neuf (PA-128). L'idempotence porte sur le **libellé**, jamais sur un
  /// compteur : deux auteurs semant « Hébergement » et « Hebergement »
  /// croiraient chacun avoir fait le travail (PA-160/161).
  Future<void> installerServices() async {
    await transaction(() async {
      for (final libelle in ReferentielPaie.services) {
        final existant = await (select(
          servicesRhLocal,
        )..where((s) => s.libelle.equals(libelle))).getSingleOrNull();
        if (existant != null) continue;

        await into(servicesRhLocal).insert(
          ServicesRhLocalCompanion.insert(id: _uuid.v4(), libelle: libelle),
        );
      }
    });
  }

  /* ================================================================== */
  /* Lectures                                                            */
  /* ================================================================== */

  /// L'effectif entier, trié par nom.
  ///
  /// Le tri se départage par identifiant : deux homonymes auraient sinon un
  /// ordre indéfini, et la liste changerait d'ordre à chaque rafraîchissement
  /// sans qu'aucune donnée n'ait bougé.
  Future<List<Employe>> employes() async {
    final requete =
        select(employesLocal).join([
          leftOuterJoin(
            servicesRhLocal,
            servicesRhLocal.id.equalsExp(employesLocal.serviceId),
          ),
        ])..orderBy([
          OrderingTerm.asc(employesLocal.nom),
          OrderingTerm.asc(employesLocal.id),
        ]);

    final lignes = await requete.get();

    return lignes
        .map(
          (l) => _vers(
            l.readTable(employesLocal),
            l.readTableOrNull(servicesRhLocal),
          ),
        )
        .toList(growable: false);
  }

  Future<Employe?> parId(String id) async {
    final ligne = await (select(employesLocal).join([
      leftOuterJoin(
        servicesRhLocal,
        servicesRhLocal.id.equalsExp(employesLocal.serviceId),
      ),
    ])..where(employesLocal.id.equals(id))).getSingleOrNull();

    if (ligne == null) return null;
    return _vers(
      ligne.readTable(employesLocal),
      ligne.readTableOrNull(servicesRhLocal),
    );
  }

  /// Les salariés qui portent déjà les mêmes nom et prénom.
  ///
  /// RG-18 appliquée au personnel : **avertir, jamais bloquer**. Deux
  /// homonymes réels existent dans un village ; refuser la saisie obligerait à
  /// contourner le contrôle par une faute d'orthographe volontaire, et le
  /// doublon serait alors indétectable.
  Future<List<Employe>> homonymes(
    String nom,
    String prenom, {
    String? exclureId,
  }) async {
    final cherche = nom.trim();
    if (cherche.isEmpty) return const [];

    final prenomCherche = prenom.trim();

    return (await employes())
        .where(
          (e) =>
              e.nom == cherche &&
              (prenomCherche.isEmpty || e.prenom == prenomCherche) &&
              e.id != exclureId,
        )
        .toList(growable: false);
  }

  /* ================================================================== */
  /* Écritures                                                           */
  /* ================================================================== */

  /// Crée un salarié et lui **alloue** son matricule, dans la même transaction.
  ///
  /// Hors transaction, deux créations concurrentes rendraient le même numéro —
  /// et c'est ce numéro que le bulletin de paie imprime.
  Future<Employe> creer({
    required String nom,
    required String prenom,
    required String poste,
    required String serviceId,
    required DateTime dateEmbauche,
    required int salaireBase,
    DateTime? dateFinContrat,
    String? numeroCnss,
    TypeContrat? typeContrat,
    StatutEmploye statut = StatutEmploye.actif,
  }) async {
    if (salaireBase < 0) throw SalaireInvalide(salaireBase);

    final id = _uuid.v4();

    await transaction(() async {
      await _exigerService(serviceId);

      await into(employesLocal).insert(
        EmployesLocalCompanion.insert(
          id: id,
          matricule: await _matriculeSuivant(),
          nom: nom.trim(),
          prenom: Value(prenom.trim()),
          poste: poste.trim(),
          serviceId: serviceId,
          dateEmbauche: dateEmbauche,
          dateFinContrat: Value(dateFinContrat),
          numeroCnss: Value(_videEnNull(numeroCnss)),
          typeContrat: Value(typeContrat?.code),
          salaireBase: salaireBase,
          statut: Value(statut.code),
        ),
      );
      await envoyerAuServeur(id);
    });

    return (await parId(id))!;
  }

  /// Met à jour un dossier.
  ///
  /// ⚠ Le matricule n'est **jamais** réattribué : il est imprimé sur les
  /// bulletins déjà remis.
  Future<Employe> mettreAJour(
    String id, {
    required String nom,
    required String prenom,
    required String poste,
    required String serviceId,
    required DateTime dateEmbauche,
    required int salaireBase,
    DateTime? dateFinContrat,
    String? numeroCnss,
    TypeContrat? typeContrat,
    required StatutEmploye statut,
  }) async {
    if (salaireBase < 0) throw SalaireInvalide(salaireBase);

    await transaction(() async {
      final existant = await (select(
        employesLocal,
      )..where((e) => e.id.equals(id))).getSingleOrNull();
      if (existant == null) throw EmployeIntrouvable(id);

      await _exigerService(serviceId);

      await (update(employesLocal)..where((e) => e.id.equals(id))).write(
        EmployesLocalCompanion(
          nom: Value(nom.trim()),
          prenom: Value(prenom.trim()),
          poste: Value(poste.trim()),
          serviceId: Value(serviceId),
          dateEmbauche: Value(dateEmbauche),
          dateFinContrat: Value(dateFinContrat),
          numeroCnss: Value(_videEnNull(numeroCnss)),
          typeContrat: Value(typeContrat?.code),
          salaireBase: Value(salaireBase),
          statut: Value(statut.code),
        ),
      );
      await envoyerAuServeur(id, modification: true);
    });

    return (await parId(id))!;
  }

  /// Archive un salarié — « supprimer = archiver ».
  ///
  /// Le statut passe à `parti` : jamais une suppression (RG-15). Réversible par
  /// la fiche. La génération de bulletins l'ignore désormais — c'est le piège
  /// réel, et il est porté **à l'écran** (la modale nomme les salariés sans
  /// bulletin sur la période) plutôt qu'en verrou : un départ sans solde dû est
  /// légitime.
  Future<Employe> archiver(String id) async {
    final employe = await parId(id);
    if (employe == null) throw EmployeIntrouvable(id);
    if (employe.statut == StatutEmploye.parti) {
      throw EmployeDejaArchive(employe.nomComplet());
    }

    await transaction(() async {
      await (update(employesLocal)..where((e) => e.id.equals(id))).write(
        const EmployesLocalCompanion(statut: Value('parti')),
      );
      await envoyerAuServeur(id, archivage: true);
    });

    return (await parId(id))!;
  }

  /* ================================================================== */
  /* Synchronisation — audit de couverture (18/10/2026)                  */
  /* ================================================================== */

  /// Le dossier part au serveur, dans la transaction du geste : inconnu du
  /// serveur → sa CRÉATION (valeurs courantes) ; connu → le dossier entier en
  /// modification ([modification]) ou l'archivage seul ([archivage]).
  Future<void> envoyerAuServeur(
    String id, {
    bool modification = false,
    bool archivage = false,
  }) async {
    final e = await (select(
      employesLocal,
    )..where((x) => x.id.equals(id))).getSingleOrNull();
    if (e == null) return;
    final service = await (select(
      servicesRhLocal,
    )..where((s) => s.id.equals(e.serviceId))).getSingleOrNull();
    final charge = chargeEmploye(
      nom: e.nom,
      prenom: e.prenom,
      poste: e.poste,
      serviceId: e.serviceId,
      serviceLibelle: service?.libelle ?? '',
      dateEmbauche: e.dateEmbauche,
      salaireBase: e.salaireBase,
      dateFinContrat: e.dateFinContrat,
      numeroCnss: e.numeroCnss,
      typeContrat: e.typeContrat,
      statut: e.statut,
    );
    final file = OperationsSyncDao(attachedDatabase);
    final connu = await DocumentsAutresPostes(
      attachedDatabase,
    ).connuDuServeur(TableSynchronisee.employes, id);
    if (!connu) {
      await file.enfiler(
        table: TableSynchronisee.employes,
        entiteId: id,
        type: TypeOperationSync.creation,
        payload: charge,
      );
      return;
    }
    if (!modification && !archivage) return;
    await file.enfiler(
      table: TableSynchronisee.employes,
      entiteId: id,
      type: TypeOperationSync.modification,
      payload: archivage ? const {'statut': 'parti'} : charge,
    );
  }

  /// Le MATRICULE attribué par le serveur remplace celui du poste (réponse
  /// de l'envoi, ou descente).
  Future<void> regulariserMatricule(String id, String matricule) async {
    await (update(employesLocal)..where((e) => e.id.equals(id))).write(
      EmployesLocalCompanion(matricule: Value(matricule)),
    );
  }

  /* ================================================================== */
  /* Gardes et correspondances                                           */
  /* ================================================================== */

  Future<void> _exigerService(String serviceId) async {
    final service = await (select(
      servicesRhLocal,
    )..where((s) => s.id.equals(serviceId))).getSingleOrNull();
    if (service == null) throw const ServiceInconnu();
  }

  /// `EMP-AAAA-NNNNN`. À appeler **dans** une transaction.
  ///
  /// Le rang est le SUFFIXE, pas le matricule entier : `EMP-2026-00042` lu
  /// comme un entier vaudrait 2026.
  Future<String> _matriculeSuivant() async {
    final motif = '$_prefixeMatricule-${_maintenant().year}-';

    final dernier =
        await (select(employesLocal)
              ..where((e) => e.matricule.like('$motif%'))
              ..orderBy([(e) => OrderingTerm.desc(e.matricule)])
              ..limit(1))
            .getSingleOrNull();

    final rang = dernier == null
        ? 0
        : int.tryParse(dernier.matricule.substring(motif.length)) ?? 0;

    return '$motif${(rang + 1).toString().padLeft(_largeurMatricule, '0')}';
  }

  String? _videEnNull(String? valeur) {
    final propre = (valeur ?? '').trim();
    return propre.isEmpty ? null : propre;
  }

  Employe _vers(EmployesLocalData d, ServicesRhLocalData? service) => Employe(
    id: d.id,
    matricule: d.matricule,
    nom: d.nom,
    prenom: d.prenom,
    poste: d.poste,
    serviceId: d.serviceId,
    serviceLibelle: service?.libelle,
    dateEmbauche: d.dateEmbauche,
    dateFinContrat: d.dateFinContrat,
    numeroCnss: d.numeroCnss,
    typeContrat: TypeContrat.depuisCode(d.typeContrat),
    salaireBase: d.salaireBase,
    statut: StatutEmploye.depuisCode(d.statut),
  );
}
