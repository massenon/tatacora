import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
// Voir la note de `employe_dao.dart` : sans cet import, le mixin généré est
// VIDE, et sans erreur de génération.
import '../../../core/database/tables/rh_tables.dart';
import '../domain/entities/bulletin_paie.dart';
import '../domain/entities/employe.dart';
import '../domain/entities/taux_paie.dart';
import '../domain/refus_rh.dart';
import '../domain/services/calcul_paie_service.dart';

part 'paie_dao.g.dart';

/// Accès Drift aux bulletins et au référentiel de taux — **unique point
/// d'écriture** sur `bulletins_paie_local` et `taux_paie_local`.
///
/// Vue Blade maîtresse (PA-183) : pwa/rh/paie.blade.php
///
/// ## Ce DAO ne calcule RIEN
///
/// Il reçoit des [RetenuesSalariales] déjà calculées par `CalculPaieService` et
/// les fige. Refaire ici la moindre formule produirait deux vérités sur le même
/// bulletin — et c'est la copie stockée qui ferait foi sur un document remis au
/// salarié.
///
/// ## Aucune suppression, aucune file de synchronisation
///
/// Un bulletin faux s'annule avec un motif ([annuler]) et reste au dossier
/// (RG-15). Et rien ne part au serveur : `bulletins_paie` n'est pas au registre
/// `TABLES_SYNCHRONISABLES`, donc aucun écran n'annonce d'attente (PA-59/60/61).
///
/// @see EF-M13-07 Calcul de la paie conforme à la réglementation béninoise
@DriftAccessor(
  tables: [BulletinsPaieLocal, EmployesLocal, ServicesRhLocal, TauxPaieLocal],
)
class PaieDao extends DatabaseAccessor<AppDatabase> with _$PaieDaoMixin {
  PaieDao(super.db, {Uuid? uuid, DateTime Function()? maintenant})
    : _uuid = uuid ?? const Uuid(),
      _maintenant = maintenant ?? DateTime.now;

  final Uuid _uuid;
  final DateTime Function() _maintenant;

  static const String _prefixeNumero = 'BUL';
  static const int _largeurNumero = 5;

  /* ================================================================== */
  /* Référentiel de taux                                                 */
  /* ================================================================== */

  /// Le référentiel courant, clé → valeur.
  Future<Map<String, String>> taux() async {
    final lignes = await select(tauxPaieLocal).get();
    return {for (final ligne in lignes) ligne.cle: ligne.valeur};
  }

  /// Installe les **quatre** taux confirmés — idempotent, unique auteur.
  ///
  /// ⚠ **Le taux de risques professionnels n'y est pas, et ne doit jamais y
  /// entrer** sans confirmation de la CNSS (PA-53). Une valeur plausible
  /// inscrite ici deviendrait la règle appliquée en production, et personne ne
  /// la rouvrirait — c'est exactement ce que `PaieReferentielSeeder` refuse de
  /// faire côté serveur.
  ///
  /// N'écrase **pas** une valeur déjà en base : un Administrateur qui a
  /// renseigné un taux révisé ne doit pas le voir revenir à sa valeur d'usine
  /// au prochain démarrage.
  Future<void> installerReferentielConfirme() async {
    await transaction(() async {
      for (final confirme in ReferentielPaie.confirmes) {
        final existant = await (select(
          tauxPaieLocal,
        )..where((t) => t.cle.equals(confirme.cle))).getSingleOrNull();
        if (existant != null) continue;

        await into(tauxPaieLocal).insert(
          TauxPaieLocalCompanion.insert(
            cle: confirme.cle,
            valeur: confirme.valeur,
            description: Value(confirme.description),
          ),
        );
      }
    });
  }

  /// Écrit un taux SAISI depuis l'écran Paramètres (09/10/2026) — insère la clé
  /// ou remplace sa valeur. Rend `true` si la valeur a changé.
  ///
  /// Ce DAO reste l'**unique auteur** de `taux_paie_local` : l'écran Paramètres
  /// ne touche pas la table, il passe par ici. La description repart à une
  /// mention de saisie — l'ancienne nommait une SOURCE (cnss.bj…) qui ne vaut
  /// plus pour une valeur changée à la main ; la garder la ferait passer pour
  /// sourcée.
  ///
  /// Aucune validation ici : la forme (décimal positif, bornes) est jugée par
  /// les règles des paramètres avant l'appel, et ce DAO ne calcule rien.
  Future<bool> enregistrerTaux(String cle, String valeur) async {
    const mention =
        'Valeur saisie depuis l’écran Paramètres : la source d’origine, si '
        'elle existait, ne vaut plus pour cette valeur.';
    final existant = await (select(
      tauxPaieLocal,
    )..where((t) => t.cle.equals(cle))).getSingleOrNull();

    if (existant == null) {
      await into(tauxPaieLocal).insert(
        TauxPaieLocalCompanion.insert(
          cle: cle,
          valeur: valeur,
          description: const Value(mention),
        ),
      );
      return true;
    }
    if (existant.valeur == valeur) return false;

    await (update(tauxPaieLocal)..where((t) => t.cle.equals(cle))).write(
      TauxPaieLocalCompanion(
        valeur: Value(valeur),
        description: const Value(mention),
      ),
    );
    return true;
  }

  /// Retire un taux (écran Paramètres : « vider »). Rend `true` si la clé
  /// existait.
  ///
  /// ⚠ Pour une clé CONFIRMÉE, [installerReferentielConfirme] la réinstallerait
  /// à la prochaine ouverture de l'écran Paie : l'écran Paramètres refuse donc
  /// de vider ces quatre-là (`raisonTauxConfirmeNonVidable`). Seul le taux de
  /// risques professionnels — qui n'est jamais installé — peut être retiré.
  Future<bool> retirerTaux(String cle) async {
    final n = await (delete(
      tauxPaieLocal,
    )..where((t) => t.cle.equals(cle))).go();
    return n > 0;
  }

  /* ================================================================== */
  /* Lectures                                                            */
  /* ================================================================== */

  /// Les bulletins d'une période, salariés joints, triés par nom du salarié.
  Future<List<BulletinPaie>> bulletinsDuMois(String periode) async {
    final lignes =
        await (_requete()..where(bulletinsPaieLocal.periode.equals(periode)))
            .get();

    final bulletins = lignes.map(_vers).toList();
    bulletins.sort((a, b) {
      final parNom = a.employe.nomComplet().compareTo(b.employe.nomComplet());
      return parNom != 0 ? parNom : a.id.compareTo(b.id);
    });

    return List.unmodifiable(bulletins);
  }

  Future<BulletinPaie?> parId(String id) async {
    final ligne = await (_requete()..where(bulletinsPaieLocal.id.equals(id)))
        .getSingleOrNull();
    return ligne == null ? null : _vers(ligne);
  }

  Future<BulletinPaie?> pourEmployeEtPeriode(
    String employeId,
    String periode,
  ) async {
    final ligne =
        await (_requete()..where(
              bulletinsPaieLocal.employeId.equals(employeId) &
                  bulletinsPaieLocal.periode.equals(periode),
            ))
            .getSingleOrNull();
    return ligne == null ? null : _vers(ligne);
  }

  /// Les salariés qui ont **déjà** un bulletin sur la période, annulés compris.
  ///
  /// Les annulés comptent : réétablir buterait sur `unique(employeId, periode)`,
  /// et l'écran afficherait une erreur de base pour une raison sans rapport
  /// avec le geste demandé.
  Future<Set<String>> employeIdsAvecBulletin(String periode) async {
    final lignes = await (select(
      bulletinsPaieLocal,
    )..where((b) => b.periode.equals(periode))).get();

    return lignes.map((b) => b.employeId).toSet();
  }

  /* ================================================================== */
  /* Écritures                                                           */
  /* ================================================================== */

  /// Fige un bulletin — **idempotent**.
  ///
  /// La lecture du bulletin existant et l'écriture du nouveau sont dans la
  /// **même transaction** : les séparer ouvrirait une fenêtre où deux
  /// établissements simultanés passeraient tous les deux, et l'index unique
  /// rejetterait le second sous un message que personne ne rattache au geste.
  ///
  /// Un second appel rend le bulletin existant et **ne brûle aucun numéro**
  /// (PA-101) : l'allocation vit après la garde, jamais avant.
  Future<BulletinPaie> etablir({
    required Employe employe,
    required String periode,
    required RetenuesSalariales retenues,
    required int chargesPatronalesConfirmees,
  }) async {
    final id = _uuid.v4();
    var idRetenu = id;

    await transaction(() async {
      final existant =
          await (select(bulletinsPaieLocal)..where(
                (b) =>
                    b.employeId.equals(employe.id) & b.periode.equals(periode),
              ))
              .getSingleOrNull();

      if (existant != null) {
        idRetenu = existant.id;
        return;
      }

      await into(bulletinsPaieLocal).insert(
        BulletinsPaieLocalCompanion.insert(
          id: id,
          numero: await _numeroSuivant(periode),
          employeId: employe.id,
          periode: periode,
          salaireBase: retenues.brut,
          // Aucune prime : aucune table de primes n'est alimentée dans ce
          // dépôt. Le brut est donc le salaire de base, et le « + Ajouter un
          // élément » du maître n'est pas rendu — le refus est nommé à
          // l'écran plutôt que laissé en bouton inerte.
          totalPrimes: const Value(0),
          totalRetenues: retenues.totalRetenues,
          cnssSalarie: retenues.cnssSalarie,
          its: retenues.its,
          chargesPatronalesConfirmees: chargesPatronalesConfirmees,
          netAPayer: retenues.netAPayer,
          statut: const Value('brouillon'),
          etabliLe: Value(_maintenant()),
        ),
      );
    });

    return (await parId(idRetenu))!;
  }

  /// Annule un bulletin — jamais une suppression, et le motif est obligatoire.
  Future<BulletinPaie> annuler(String bulletinId, String motif) async {
    final propre = motif.trim();
    if (propre.isEmpty) throw const MotifAnnulationRequis();

    await transaction(() async {
      final existant = await (select(
        bulletinsPaieLocal,
      )..where((b) => b.id.equals(bulletinId))).getSingleOrNull();

      if (existant == null) throw BulletinIntrouvable(bulletinId);
      if (existant.statut == StatutBulletin.annulee.code) {
        throw const BulletinDejaAnnule();
      }

      await (update(
        bulletinsPaieLocal,
      )..where((b) => b.id.equals(bulletinId))).write(
        BulletinsPaieLocalCompanion(
          statut: Value(StatutBulletin.annulee.code),
          motifAnnulation: Value(propre),
        ),
      );
    });

    return (await parId(bulletinId))!;
  }

  /* ================================================================== */
  /* Interne                                                             */
  /* ================================================================== */

  JoinedSelectStatement<HasResultSet, dynamic> _requete() =>
      select(bulletinsPaieLocal).join([
        innerJoin(
          employesLocal,
          employesLocal.id.equalsExp(bulletinsPaieLocal.employeId),
        ),
        leftOuterJoin(
          servicesRhLocal,
          servicesRhLocal.id.equalsExp(employesLocal.serviceId),
        ),
      ]);

  /// `BUL-AAAA-NNNNN` — alloué **dans** la transaction appelante.
  ///
  /// ⚠ Cette méthode ALLOUE : ce n'est jamais une lecture. Pour constater le
  /// compteur, lire la table (même piège que `FactureDao.numeroSuivant()`,
  /// PA-101).
  Future<String> _numeroSuivant(String periode) async {
    final motif = '$_prefixeNumero-${periode.substring(0, 4)}-';

    final dernier =
        await (select(bulletinsPaieLocal)
              ..where((b) => b.numero.like('$motif%'))
              ..orderBy([(b) => OrderingTerm.desc(b.numero)])
              ..limit(1))
            .getSingleOrNull();

    final rang = dernier == null
        ? 0
        : int.tryParse(dernier.numero.substring(motif.length)) ?? 0;

    return '$motif${(rang + 1).toString().padLeft(_largeurNumero, '0')}';
  }

  BulletinPaie _vers(TypedResult ligne) {
    final b = ligne.readTable(bulletinsPaieLocal);
    final e = ligne.readTable(employesLocal);
    final service = ligne.readTableOrNull(servicesRhLocal);

    return BulletinPaie(
      id: b.id,
      numero: b.numero,
      employe: Employe(
        id: e.id,
        matricule: e.matricule,
        nom: e.nom,
        prenom: e.prenom,
        poste: e.poste,
        serviceId: e.serviceId,
        serviceLibelle: service?.libelle,
        dateEmbauche: e.dateEmbauche,
        dateFinContrat: e.dateFinContrat,
        numeroCnss: e.numeroCnss,
        typeContrat: TypeContrat.depuisCode(e.typeContrat),
        salaireBase: e.salaireBase,
        statut: StatutEmploye.depuisCode(e.statut),
      ),
      periode: b.periode,
      salaireBase: b.salaireBase,
      totalPrimes: b.totalPrimes,
      totalRetenues: b.totalRetenues,
      cnssSalarie: b.cnssSalarie,
      its: b.its,
      chargesPatronalesConfirmees: b.chargesPatronalesConfirmees,
      netAPayer: b.netAPayer,
      statut: StatutBulletin.depuisCode(b.statut),
      motifAnnulation: b.motifAnnulation,
      etabliLe: b.etabliLe,
    );
  }
}
