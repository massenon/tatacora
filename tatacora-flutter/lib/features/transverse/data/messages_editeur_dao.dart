import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
// Les classes de tables doivent être dans la portée du fichier : sans cet
// import, le mixin généré est VIDE, sans erreur de génération (leçon
// `employe_dao.dart`).
import '../../../core/database/tables/messages_editeur_tables.dart';
import '../domain/messages_editeur.dart';

part 'messages_editeur_dao.g.dart';

/// Accès Drift à la boîte d'envoi de « Contactez l'éditeur » — **unique point
/// d'écriture** sur `messages_editeur_local` (schéma v25).
///
/// Aucune méthode ne SUPPRIME une ligne : un message, envoyé ou non, reste la
/// trace du geste de l'utilisateur (« Vos envois »), comme au serveur.
@DriftAccessor(tables: [MessagesEditeurLocal])
class MessagesEditeurDao extends DatabaseAccessor<AppDatabase>
    with _$MessagesEditeurDaoMixin {
  MessagesEditeurDao(super.db, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final Uuid _uuid;

  /// Écrit le message, statut `en_attente`, et rend sa ligne. C'est la
  /// PREMIÈRE écriture du geste : l'envoi n'est tenté qu'ensuite.
  Future<MessageEditeur> enregistrer(
    SaisieMessageEditeur saisie, {
    required String? auteurId,
    required String? auteurLogin,
    required String? poste,
    required DateTime maintenant,
  }) async {
    final id = _uuid.v4();
    await into(messagesEditeurLocal).insert(
      MessagesEditeurLocalCompanion.insert(
        id: id,
        type: saisie.type.code,
        sujet: saisie.sujet,
        moduleConcerne: Value(saisie.moduleConcerne),
        corps: saisie.corps,
        etapes: Value(saisie.etapes),
        auteurId: Value(auteurId),
        auteurLogin: Value(auteurLogin),
        poste: Value(poste),
        creeLe: maintenant,
      ),
    );
    return (await parId(id))!;
  }

  Future<MessageEditeur?> parId(String id) async {
    final ligne = await (select(
      messagesEditeurLocal,
    )..where((m) => m.id.equals(id))).getSingleOrNull();
    return ligne == null ? null : _versDomaine(ligne);
  }

  /// Les messages `en_attente`, le plus ANCIEN d'abord (comme
  /// `rejouerEnAttente` au serveur, `orderBy('date_creation')`), bornés à
  /// [limite]. Le délai de relance se juge à l'appelant
  /// (`PolitiqueRelanceEditeur.estDu`).
  Future<List<MessageEditeur>> enAttente({int limite = 100}) async {
    final lignes =
        await (select(messagesEditeurLocal)
              ..where(
                (m) => m.statut.equals(StatutMessageEditeur.enAttente.code),
              )
              ..orderBy([(m) => OrderingTerm.asc(m.creeLe)])
              ..limit(limite))
            .get();
    return [for (final l in lignes) _versDomaine(l)];
  }

  /// Le serveur SMTP a ACCEPTÉ le message.
  Future<void> marquerEnvoye(String id, {required DateTime maintenant}) =>
      (update(messagesEditeurLocal)..where((m) => m.id.equals(id))).write(
        MessagesEditeurLocalCompanion(
          statut: Value(StatutMessageEditeur.envoye.code),
          envoyeLe: Value(maintenant),
          derniereTentative: Value(maintenant),
          derniereErreur: const Value(null),
        ),
      );

  /// Une tentative RÉELLE a échoué : `tentatives` + 1, la raison, et `echec`
  /// quand le plafond de relances automatiques est atteint.
  Future<void> marquerTentativeEchouee(
    String id, {
    required String erreur,
    required DateTime maintenant,
  }) async {
    await transaction(() async {
      final ligne = await (select(
        messagesEditeurLocal,
      )..where((m) => m.id.equals(id))).getSingleOrNull();
      if (ligne == null) return;
      final tentatives = ligne.tentatives + 1;
      final statut = tentatives >= PolitiqueRelanceEditeur.tentativesMax
          ? StatutMessageEditeur.echec
          : StatutMessageEditeur.enAttente;
      await (update(messagesEditeurLocal)..where((m) => m.id.equals(id))).write(
        MessagesEditeurLocalCompanion(
          statut: Value(statut.code),
          tentatives: Value(tentatives),
          derniereErreur: Value(erreur),
          derniereTentative: Value(maintenant),
        ),
      );
    });
  }

  /// L'envoi n'a même pas été tenté (configuration absente : mot de passe,
  /// serveur ou utilisateur SMTP) : la raison est notée, `tentatives` ne
  /// bouge pas — aucune connexion n'a eu lieu — et le message reste
  /// `en_attente`, sans délai : il partira dès que la configuration existera.
  Future<void> marquerNonTente(String id, {required String erreur}) =>
      (update(messagesEditeurLocal)..where((m) => m.id.equals(id))).write(
        MessagesEditeurLocalCompanion(derniereErreur: Value(erreur)),
      );

  /// « Renvoyer maintenant » : les messages en `echec` repassent
  /// `en_attente` (leur compteur est gardé, il dit l'histoire). Rend leur
  /// nombre.
  Future<int> remettreEnFile() =>
      (update(
        messagesEditeurLocal,
      )..where((m) => m.statut.equals(StatutMessageEditeur.echec.code))).write(
        MessagesEditeurLocalCompanion(
          statut: Value(StatutMessageEditeur.enAttente.code),
          derniereTentative: const Value(null),
        ),
      );

  /// « Vos envois » — les 50 derniers envois du compte [auteurId], le plus
  /// récent d'abord (`ContactEditeur::render()` du serveur).
  Future<List<MessageEditeur>> envoisDuCompte(
    String auteurId, {
    int limite = 50,
  }) async {
    final lignes =
        await (select(messagesEditeurLocal)
              ..where((m) => m.auteurId.equals(auteurId))
              ..orderBy([(m) => OrderingTerm.desc(m.creeLe)])
              ..limit(limite))
            .get();
    return [for (final l in lignes) _versDomaine(l)];
  }

  /// L'état de la file de TOUT le poste : combien attendent, combien sont en
  /// échec, et la dernière raison connue.
  Future<EtatFileEditeur> etatFile() async {
    final lignes =
        await (select(messagesEditeurLocal)..where(
              (m) => m.statut.isIn([
                StatutMessageEditeur.enAttente.code,
                StatutMessageEditeur.echec.code,
              ]),
            ))
            .get();
    var enAttente = 0;
    var enEchec = 0;
    MessageEditeurLocal? plusRecent;
    for (final l in lignes) {
      if (l.statut == StatutMessageEditeur.echec.code) {
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

  MessageEditeur _versDomaine(MessageEditeurLocal l) => MessageEditeur(
    id: l.id,
    type: TypeMessageEditeur.depuisCode(l.type),
    sujet: l.sujet,
    moduleConcerne: l.moduleConcerne,
    corps: l.corps,
    etapes: l.etapes,
    auteurLogin: l.auteurLogin,
    poste: l.poste,
    creeLe: l.creeLe,
    statut: StatutMessageEditeur.depuisCode(l.statut),
    tentatives: l.tentatives,
    derniereErreur: l.derniereErreur,
    derniereTentative: l.derniereTentative,
    envoyeLe: l.envoyeLe,
  );
}
