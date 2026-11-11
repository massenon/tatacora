import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
// Les classes de tables doivent être dans la portée du fichier : sans cet
// import, le mixin généré est VIDE, sans erreur de génération.
import '../../../core/database/tables/boite_envoi_emails_tables.dart';
import '../domain/boite_envoi_emails.dart';

part 'boite_envoi_emails_dao.g.dart';

/// Accès Drift à la boîte d'envoi des e-mails du poste — **unique point
/// d'écriture** sur `boite_envoi_emails_local` (schéma v39).
///
/// Aucune méthode ne SUPPRIME une ligne. `marquerEnvoye` n'est appelée que par
/// `ServiceBoiteEnvoiEmails`, APRÈS l'accusé du relais SMTP.
@DriftAccessor(tables: [BoiteEnvoiEmailsLocal])
class BoiteEnvoiEmailsDao extends DatabaseAccessor<AppDatabase>
    with _$BoiteEnvoiEmailsDaoMixin {
  BoiteEnvoiEmailsDao(super.db, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final Uuid _uuid;

  /// Met l'e-mail en boîte, `en_attente`. IDEMPOTENT : si la clé existe déjà
  /// (le message a déjà son e-mail), RIEN n'est écrit et la ligne existante est
  /// rendue avec `cree == false` — jamais un second courriel.
  Future<({EmailEnBoite email, bool cree})> mettreEnFile({
    required String cleIdempotence,
    required String source,
    required String? sourceId,
    required String adresse,
    required String? destinataireNom,
    required String objet,
    required String corps,
    required DateTime maintenant,
  }) async {
    return transaction(() async {
      // L'existence se lit AVANT d'insérer : `insertOrIgnore` rend le dernier
      // identifiant inséré même quand la ligne est ignorée, il ne dit donc pas
      // si la clé était déjà là. La contrainte UNIQUE du schéma reste la
      // garantie ; cette lecture NOMME l'issue.
      final existante =
          await (select(boiteEnvoiEmailsLocal)
                ..where((e) => e.cleIdempotence.equals(cleIdempotence)))
              .getSingleOrNull();
      if (existante != null) {
        return (email: _versDomaine(existante), cree: false);
      }
      await into(boiteEnvoiEmailsLocal).insert(
        BoiteEnvoiEmailsLocalCompanion.insert(
          id: _uuid.v4(),
          cleIdempotence: cleIdempotence,
          source: source,
          sourceId: Value(sourceId),
          adresse: adresse.trim(),
          destinataireNom: Value(destinataireNom),
          objet: objet,
          corps: corps,
          creeLe: maintenant,
        ),
      );
      final ligne = await (select(
        boiteEnvoiEmailsLocal,
      )..where((e) => e.cleIdempotence.equals(cleIdempotence))).getSingle();
      return (email: _versDomaine(ligne), cree: true);
    });
  }

  Future<EmailEnBoite?> parId(String id) async {
    final ligne = await (select(
      boiteEnvoiEmailsLocal,
    )..where((e) => e.id.equals(id))).getSingleOrNull();
    return ligne == null ? null : _versDomaine(ligne);
  }

  /// L'e-mail d'un objet d'origine (le message de notification), ou `null`.
  Future<EmailEnBoite?> parSource(String source, String sourceId) async {
    final ligne =
        await (select(boiteEnvoiEmailsLocal)..where(
              (e) => e.source.equals(source) & e.sourceId.equals(sourceId),
            ))
            .getSingleOrNull();
    return ligne == null ? null : _versDomaine(ligne);
  }

  /// Les e-mails d'une source, par identifiant d'objet d'origine.
  Future<Map<String, EmailEnBoite>> parSources(String source) async {
    final lignes = await (select(
      boiteEnvoiEmailsLocal,
    )..where((e) => e.source.equals(source))).get();
    return {
      for (final l in lignes)
        if (l.sourceId != null) l.sourceId!: _versDomaine(l),
    };
  }

  /// Les e-mails `en_attente`, le plus ANCIEN d'abord, bornés à [limite]. Le
  /// délai de relance se juge à l'appelant (`PolitiqueRelanceEmail.estDu`).
  Future<List<EmailEnBoite>> enAttente({int limite = 100}) async {
    final lignes =
        await (select(boiteEnvoiEmailsLocal)
              ..where((e) => e.statut.equals(StatutEmail.enAttente.code))
              ..orderBy([(e) => OrderingTerm.asc(e.creeLe)])
              ..limit(limite))
            .get();
    return [for (final l in lignes) _versDomaine(l)];
  }

  /// Le relais SMTP a ACCEPTÉ le message.
  Future<void> marquerEnvoye(
    String id, {
    required DateTime maintenant,
    required int tentatives,
  }) => (update(boiteEnvoiEmailsLocal)..where((e) => e.id.equals(id))).write(
    BoiteEnvoiEmailsLocalCompanion(
      statut: Value(StatutEmail.envoye.code),
      tentatives: Value(tentatives),
      envoyeLe: Value(maintenant),
      derniereTentative: Value(maintenant),
      derniereErreur: const Value(null),
    ),
  );

  /// Une tentative RÉELLE a échoué : `tentatives` + 1, la raison, et `echec`
  /// quand le plafond de relances automatiques est atteint. Rend les
  /// tentatives après l'échec.
  Future<int> marquerTentativeEchouee(
    String id, {
    required String erreur,
    required DateTime maintenant,
  }) => transaction(() async {
    final ligne = await (select(
      boiteEnvoiEmailsLocal,
    )..where((e) => e.id.equals(id))).getSingleOrNull();
    if (ligne == null) return 0;
    final tentatives = ligne.tentatives + 1;
    final statut = tentatives >= PolitiqueRelanceEmail.tentativesMax
        ? StatutEmail.echec
        : StatutEmail.enAttente;
    await (update(boiteEnvoiEmailsLocal)..where((e) => e.id.equals(id))).write(
      BoiteEnvoiEmailsLocalCompanion(
        statut: Value(statut.code),
        tentatives: Value(tentatives),
        derniereErreur: Value(erreur),
        derniereTentative: Value(maintenant),
      ),
    );
    return tentatives;
  });

  /// L'envoi n'a même pas été tenté (configuration absente) : la raison est
  /// notée, `tentatives` ne bouge pas, l'e-mail reste `en_attente`.
  Future<void> marquerNonTente(String id, {required String erreur}) =>
      (update(boiteEnvoiEmailsLocal)..where((e) => e.id.equals(id))).write(
        BoiteEnvoiEmailsLocalCompanion(derniereErreur: Value(erreur)),
      );

  /// « Renvoyer » : l'e-mail [id] (ou, sans [id], tous ceux en `echec`)
  /// repasse `en_attente`, prêt à partir sans attendre (le compteur est gardé,
  /// il dit l'histoire). Rend leur nombre. Un e-mail `envoye` n'est JAMAIS
  /// remis en file : ce serait un doublon.
  Future<int> remettreEnFile({String? id}) =>
      (update(boiteEnvoiEmailsLocal)..where(
            (e) => id == null
                ? e.statut.equals(StatutEmail.echec.code)
                : e.id.equals(id) &
                      e.statut.isIn([
                        StatutEmail.echec.code,
                        StatutEmail.enAttente.code,
                      ]),
          ))
          .write(
            BoiteEnvoiEmailsLocalCompanion(
              statut: Value(StatutEmail.enAttente.code),
              derniereTentative: const Value(null),
            ),
          );

  /// Le message d'origine ne doit plus partir (transmis à la main, abandonné) :
  /// son e-mail encore `en_attente` ou `echec` passe `annule`. Un e-mail déjà
  /// `envoye` n'est pas touché — il est parti, et la trace le dit.
  Future<void> annulerPourSource(String source, String sourceId) =>
      (update(boiteEnvoiEmailsLocal)..where(
            (e) =>
                e.source.equals(source) &
                e.sourceId.equals(sourceId) &
                e.statut.isIn([
                  StatutEmail.enAttente.code,
                  StatutEmail.echec.code,
                ]),
          ))
          .write(
            BoiteEnvoiEmailsLocalCompanion(
              statut: Value(StatutEmail.annule.code),
            ),
          );

  /// L'état de la boîte de TOUT le poste.
  Future<EtatBoiteEmails> etatFile() async {
    final lignes =
        await (select(boiteEnvoiEmailsLocal)..where(
              (e) => e.statut.isIn([
                StatutEmail.enAttente.code,
                StatutEmail.echec.code,
              ]),
            ))
            .get();
    var enAttente = 0;
    var enEchec = 0;
    EnvoiEmailLocal? plusRecent;
    for (final l in lignes) {
      if (l.statut == StatutEmail.echec.code) {
        enEchec++;
      } else {
        enAttente++;
      }
      if (l.derniereErreur == null) continue;
      final courant = plusRecent;
      final repere = l.derniereTentative ?? l.creeLe;
      if (courant == null ||
          repere.isAfter(courant.derniereTentative ?? courant.creeLe)) {
        plusRecent = l;
      }
    }
    return (
      enAttente: enAttente,
      enEchec: enEchec,
      derniereErreur: plusRecent?.derniereErreur,
      derniereTentative: plusRecent?.derniereTentative,
    );
  }

  EmailEnBoite _versDomaine(EnvoiEmailLocal l) => EmailEnBoite(
    id: l.id,
    cleIdempotence: l.cleIdempotence,
    source: l.source,
    sourceId: l.sourceId,
    adresse: l.adresse,
    destinataireNom: l.destinataireNom,
    objet: l.objet,
    corps: l.corps,
    creeLe: l.creeLe,
    statut: StatutEmail.depuisCode(l.statut),
    tentatives: l.tentatives,
    derniereErreur: l.derniereErreur,
    derniereTentative: l.derniereTentative,
    envoyeLe: l.envoyeLe,
  );
}
