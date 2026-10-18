import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/tables/notifications_tables.dart';
import '../../hebergement/domain/entities/reservation.dart';
import '../../synchronisation/data/operations_sync_dao.dart';
import '../../synchronisation/domain/charges_synchronisation.dart';
import '../../synchronisation/domain/operation_sync.dart';
import '../domain/entities/canal_notification.dart';
import '../domain/entities/declencheur_notification.dart';
import '../domain/entities/message_notification.dart';
import '../domain/entities/modele_notification.dart';
import '../domain/registre_notifications.dart';

part 'notifications_dao.g.dart';

/// Le refus d'un geste — le libellé est celui du maître, affiché tel quel.
final class RefusNotification implements Exception {
  const RefusNotification(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Ce qu'une détection a réellement produit.
///
/// QUATRE nombres distincts, et les confondre effacerait l'information utile :
/// « rien de neuf » (tout était déjà en file) ne se lit pas comme « rien à
/// notifier » (aucune occurrence), qui ne se lit pas comme « des modèles sont
/// mal écrits » (des refus de composition) — ni, surtout, comme « on n'a rien
/// regardé du tout ».
///
/// ⚠ [modelesExamines] est ajouté le 14/09/2026, et il répare un indicateur
/// qui affirmait un état non vérifié. Les trois autres nombres valent tous
/// zéro dans DEUX situations opposées : des modèles ont été examinés sans rien
/// trouver, ou **aucun modèle n'existe** — et sur ce poste, rien ne sème le
/// référentiel. L'écran concluait « Aucun nouvel événement à notifier », ce
/// qui parle des ÉVÉNEMENTS alors que seuls les MODÈLES avaient été mesurés
/// (PA-59/60/61).
///
/// L'ancien `sansRien` ne pouvait pas trancher : dérivé des trois mêmes
/// nombres, il était vrai dans les deux cas. Il est REMPLACÉ, pas branché —
/// un prédicat qui porte la confusion qu'on corrige est un piège.
final class BilanDetection {
  const BilanDetection({
    required this.composes,
    required this.dejaEnFile,
    required this.refus,
    required this.modelesExamines,
  });

  final int composes;
  final int dejaEnFile;
  final List<RefusComposition> refus;

  /// Les modèles réellement PASSÉS AU CRIBLE : actifs, portant un déclencheur
  /// connu, et détectables sur ce poste. C'est le seul nombre qui distingue
  /// « rien à notifier » de « rien n'a été regardé ».
  final int modelesExamines;

  /// Aucun modèle n'a été examiné : la détection n'a mesuré AUCUN événement.
  bool get rienDeRegarde => modelesExamines == 0;
}

/// Un modèle qui n'a pas pu composer son message, et pourquoi.
final class RefusComposition {
  const RefusComposition({
    required this.modele,
    required this.motif,
    this.reference,
  });

  final String modele;
  final String? reference;
  final String motif;
}

/// Accès Drift à M12 — le référentiel et la TRACE.
///
/// ## Aucun geste d'envoi, et ce n'est pas un oubli
///
/// RG-20 n'est pas implémentée, aucun canal n'est contracté, et ce poste est
/// hors ligne : aucun envoi n'y est même techniquement possible. Ce DAO
/// n'expose donc AUCUNE méthode d'envoi, et aucun de ses gestes ne peut écrire
/// le statut « envoyé » — `notifications_dao_test.dart` l'exige en énumérant
/// les gestes publics.
///
/// « Transmis à la main » fait sortir le message de la file **sans jamais**
/// prétendre à un envoi système : ce n'est pas le logiciel qui l'a fait partir,
/// et la distinction doit rester lisible à l'audit.
///
/// ## Rien ne part au serveur
///
/// Aucune entrée de `sync_queue` n'est écrite ici : M12 n'est pas au registre
/// `TABLES_SYNCHRONISABLES`, une opération y serait rejetée indéfiniment, et le
/// badge « en attente de synchronisation » qui en découlerait serait
/// l'indicateur qui affirme un état que rien n'a vérifié (PA-59/60/61).
@DriftAccessor(tables: [ModelesNotificationLocal, MessagesNotificationLocal])
class NotificationsDao extends DatabaseAccessor<AppDatabase>
    with _$NotificationsDaoMixin {
  NotificationsDao(super.db);

  static const _uuid = Uuid();

  /* ---------------------------------------------------------------- lectures */

  /// Les modèles, triés par événement puis canal — l'ordre du serveur.
  Future<List<ModeleNotification>> modeles() async {
    final lignes =
        await (select(modelesNotificationLocal)..orderBy([
              (m) => OrderingTerm.asc(m.evenement),
              (m) => OrderingTerm.asc(m.canal),
            ]))
            .get();
    return lignes.map(_versModele).toList(growable: false);
  }

  /// Tous les messages, le plus récent d'abord.
  Future<List<MessageNotification>> messages() async {
    // Le déclencheur de chaque message se lit par son MODÈLE. La table des
    // modèles est chargée UNE fois ici, et passée à la conversion : sans cela,
    // il faudrait une requête par ligne — ou, pire, un cache que quelqu'un
    // oublierait de remplir, et chaque message perdrait silencieusement son
    // déclencheur.
    final declencheurs = await _declencheursParModele();
    final lignes = await (select(
      messagesNotificationLocal,
    )..orderBy([(m) => OrderingTerm.desc(m.composeLe)])).get();
    return lignes
        .map((l) => _versMessage(l, declencheurs))
        .toList(growable: false);
  }

  /// La file : les messages en attente, le plus récent d'abord.
  Future<List<MessageNotification>> file() async {
    final tous = await messages();
    return tous.where((m) => m.estEnAttente).toList(growable: false);
  }

  /// Le journal : tout ce qui est sorti de la file, le plus récemment traité
  /// d'abord.
  Future<List<MessageNotification>> journal() async {
    final tous = await messages();
    final sortis = tous.where((m) => m.estAuJournal).toList()
      ..sort((a, b) {
        final da = a.traiteLe ?? a.composeLe;
        final db = b.traiteLe ?? b.composeLe;
        return db.compareTo(da);
      });
    return List.unmodifiable(sortis);
  }

  /// Le nombre de messages RÉELLEMENT partis — COMPTÉ en base.
  ///
  /// Il vaut zéro aujourd'hui parce qu'aucun geste de ce poste ne peut produire
  /// ce statut, pas parce qu'une constante le dit. La nuance est celle de
  /// PA-61 : un chiffre posé à la main resterait juste jusqu'au jour où il
  /// compterait.
  Future<int> nombreEnvoisReels() async {
    final compte = messagesNotificationLocal.id.count();
    final requete = selectOnly(messagesNotificationLocal)
      ..addColumns([compte])
      ..where(
        messagesNotificationLocal.statut.equals(
          StatutMessageNotification.envoyeParLeSysteme.code,
        ),
      );
    return (await requete.getSingle()).read(compte) ?? 0;
  }

  /* ------------------------------------------------------ référentiel modèles */

  /// Crée un modèle. Les deux registres fermés gardent les deux clés.
  ///
  /// L'unicité `(événement, canal)` est posée au SCHÉMA : ce contrôle-ci sert à
  /// NOMMER le refus, une violation de contrainte remontant un message SQL que
  /// personne ne rattache au couple concerné. Même partage des rôles que
  /// `ModeleNotificationService::creerModele()`.
  Future<ModeleNotification> creerModele({
    required DeclencheurNotification declencheur,
    required CanalNotification canal,
    required String contenuTemplate,
    String? objet,
    bool actif = true,
  }) async {
    final contenu = _exigerContenu(contenuTemplate);
    final id = _uuid.v4();

    await transaction(() async {
      final existe =
          await (select(modelesNotificationLocal)..where(
                (m) =>
                    m.evenement.equals(declencheur.code) &
                    m.canal.equals(canal.code),
              ))
              .getSingleOrNull();

      if (existe != null) {
        throw const RefusNotification(
          'Un modèle existe déjà pour cet événement et ce canal.',
        );
      }

      await into(modelesNotificationLocal).insert(
        ModelesNotificationLocalCompanion.insert(
          id: id,
          evenement: declencheur.code,
          canal: canal.code,
          contenuTemplate: contenu,
          objet: Value(_objetOuNull(objet)),
          actif: Value(actif),
        ),
      );
      await _envoyer(id, TypeOperationSync.creation);
    });

    return (await _modeleParId(id))!;
  }

  /// Modifie un modèle.
  ///
  /// L'ÉVÉNEMENT n'est pas modifiable, et le maître fait le même choix (son
  /// champ « Déclencheur » est `disabled` à l'édition) : changer l'événement
  /// d'un modèle reviendrait à en créer un autre en perdant la trace du
  /// premier. Le canal, lui, se change — un texte relu pour WhatsApp reste
  /// valable en e-mail.
  Future<ModeleNotification> modifierModele(
    String id, {
    required CanalNotification canal,
    required String contenuTemplate,
    required bool actif,
    String? objet,
  }) async {
    final contenu = _exigerContenu(contenuTemplate);

    await transaction(() async {
      final modele = await _ligneModele(id);

      final collision =
          await (select(modelesNotificationLocal)..where(
                (m) =>
                    m.evenement.equals(modele.evenement) &
                    m.canal.equals(canal.code) &
                    m.id.equals(id).not(),
              ))
              .getSingleOrNull();

      if (collision != null) {
        throw const RefusNotification(
          'Un modèle existe déjà pour cet événement et ce canal.',
        );
      }

      await (update(
        modelesNotificationLocal,
      )..where((m) => m.id.equals(id))).write(
        ModelesNotificationLocalCompanion(
          canal: Value(canal.code),
          contenuTemplate: Value(contenu),
          objet: Value(_objetOuNull(objet)),
          actif: Value(actif),
          modifieLe: Value(DateTime.now()),
        ),
      );
      await _envoyer(id, TypeOperationSync.modification);
    });

    return (await _modeleParId(id))!;
  }

  /// Active ou désactive — le geste « Activer / Désactiver » du maître.
  ///
  /// Aucune suppression n'existe, ici comme au serveur : la désactivation EST
  /// le geste métier.
  Future<ModeleNotification> basculerActivation(String id) async {
    await transaction(() async {
      final modele = await _ligneModele(id);
      await (update(
        modelesNotificationLocal,
      )..where((m) => m.id.equals(id))).write(
        ModelesNotificationLocalCompanion(
          actif: Value(!modele.actif),
          modifieLe: Value(DateTime.now()),
        ),
      );
      await _envoyer(id, TypeOperationSync.modification);
    });

    return (await _modeleParId(id))!;
  }

  /// Lot 10f : le modèle part au serveur, état ENTIER (l'événement compris :
  /// un modèle inconnu du serveur s'y retrouve par son couple). Les messages
  /// tracés, eux, ne partent jamais.
  Future<void> _envoyer(String id, TypeOperationSync type) async {
    final m = await _ligneModele(id);
    await OperationsSyncDao(attachedDatabase).enfiler(
      table: TableSynchronisee.modelesNotification,
      entiteId: id,
      type: type,
      payload: chargeModeleNotification(
        evenement: m.evenement,
        canal: m.canal,
        objet: m.objet,
        contenuTemplate: m.contenuTemplate,
        actif: m.actif,
      ),
    );
  }

  /// Un modèle DESCENDU du serveur (lot 10f), sous [id] (local), créé s'il
  /// manque — sans rien renvoyer. Seul appelant : l'aligneur du catalogue.
  Future<void> inscrireDescendu({
    required String id,
    required String evenement,
    required String canal,
    required String? objet,
    required String contenuTemplate,
    required bool actif,
  }) async {
    final existant = await _modeleParId(id);
    if (existant == null) {
      await into(modelesNotificationLocal).insert(
        ModelesNotificationLocalCompanion.insert(
          id: id,
          evenement: evenement,
          canal: canal,
          contenuTemplate: contenuTemplate,
          objet: Value(objet),
          actif: Value(actif),
        ),
      );
      return;
    }
    await (update(
      modelesNotificationLocal,
    )..where((m) => m.id.equals(id))).write(
      ModelesNotificationLocalCompanion(
        canal: Value(canal),
        contenuTemplate: Value(contenuTemplate),
        objet: Value(objet),
        actif: Value(actif),
        modifieLe: Value(DateTime.now()),
      ),
    );
  }

  /// Le modèle de ce couple (événement, canal), ou `null`.
  Future<ModelesNotificationLocalData?> parCouple(
    String evenement,
    String canal,
  ) =>
      (select(modelesNotificationLocal)..where(
            (m) => m.evenement.equals(evenement) & m.canal.equals(canal),
          ))
          .getSingleOrNull();

  /* --------------------------------------------------------------- détection */

  /// « Détecter maintenant » — compose réellement les messages du jour et les
  /// met en file. **N'envoie rien.**
  ///
  /// Un modèle actif sur un déclencheur que ce poste ne sait pas regarder est
  /// simplement ignoré : ce n'est pas une faute de saisie, et le signaler comme
  /// telle ferait chercher une erreur là où il n'y a qu'une absence de données.
  /// La raison, elle, est affichée à l'onglet Déclencheurs.
  Future<BilanDetection> detecter({
    required List<Reservation> reservations,
    required DateTime aujourdHui,
  }) async {
    var composes = 0;
    var deja = 0;
    var examines = 0;
    final refus = <RefusComposition>[];

    for (final modele in await modeles()) {
      final declencheur = modele.declencheur;
      if (!modele.actif || declencheur == null) continue;
      if (!declencheur.estDetecteSurCePoste) continue;

      // Compté ICI, après les trois filtres et AVANT le test d'occurrences :
      // c'est le moment où ce modèle est réellement passé au crible. Le
      // compter plus tôt inclurait des modèles inactifs ; plus tard, il
      // manquerait ceux qui n'ont simplement rien trouvé — c'est-à-dire le
      // cas que ce nombre existe pour distinguer.
      examines++;

      final occurrences = detecterOccurrences(
        declencheur: declencheur,
        reservations: reservations,
        aujourdHui: aujourdHui,
      );
      if (occurrences.isEmpty) continue;

      final dejaComposees = await _referencesDe(modele.id);

      for (final occurrence in occurrences) {
        if (dejaComposees.contains(occurrence.reference)) {
          deja++;
          continue;
        }

        final resultat = modele.composer(occurrence.variables);

        switch (resultat) {
          case CompositionRefusee(:final message):
            refus.add(
              RefusComposition(
                modele: declencheur.libelle,
                reference: occurrence.reference,
                motif: message,
              ),
            );
          case MessageCompose(:final contenu, :final objet, :final longueur):
            await into(messagesNotificationLocal).insert(
              MessagesNotificationLocalCompanion.insert(
                id: _uuid.v4(),
                modeleId: modele.id,
                canal: modele.canalCode,
                reference: occurrence.reference,
                destinataire: occurrence.destinataire,
                contenu: contenu,
                longueur: longueur,
                objet: Value(objet),
              ),
            );
            composes++;
        }
      }
    }

    return BilanDetection(
      composes: composes,
      dejaEnFile: deja,
      refus: refus,
      modelesExamines: examines,
    );
  }

  /* ------------------------------------------------------- gestes sur la file */

  /// « Transmis à la main » — le message a été transmis HORS du système, et le
  /// déclare.
  ///
  /// Le commentaire est facultatif ; l'auteur ne l'est pas (RG-15 : la trace
  /// doit continuer de porter le nom de qui a fait le geste, même si le compte
  /// est désactivé plus tard).
  Future<MessageNotification> marquerTransmis(
    String messageId, {
    required String auteur,
    String? commentaire,
  }) => _sortirDeLaFile(
    messageId,
    statut: StatutMessageNotification.transmisALaMain,
    auteur: auteur,
    commentaire: _texteOuNull(commentaire),
  );

  /// « Abandonner » — le message ne sera JAMAIS envoyé. Le motif est
  /// obligatoire, comme au maître : un message qui ne partira pas doit dire
  /// pourquoi.
  Future<MessageNotification> abandonner(
    String messageId, {
    required String auteur,
    required String motif,
  }) {
    final propre = motif.trim();
    if (propre.isEmpty) {
      throw const RefusNotification('Le motif de l’abandon est obligatoire.');
    }

    return _sortirDeLaFile(
      messageId,
      statut: StatutMessageNotification.abandonne,
      auteur: auteur,
      motifAbandon: propre,
    );
  }

  /// Le seul chemin de sortie de la file — et il ne connaît QUE les deux
  /// statuts manuels.
  ///
  /// Le statut est un paramètre, mais ses deux seuls appelants sont ci-dessus :
  /// aucun n'atteint « envoyé ». La méthode est privée pour que cela reste
  /// vrai — l'exposer offrirait un chemin vers un statut d'envoi que rien
  /// n'aurait vérifié.
  Future<MessageNotification> _sortirDeLaFile(
    String messageId, {
    required StatutMessageNotification statut,
    required String auteur,
    String? commentaire,
    String? motifAbandon,
  }) async {
    assert(
      statut == StatutMessageNotification.transmisALaMain ||
          statut == StatutMessageNotification.abandonne,
      "Aucun geste de ce poste ne produit un statut d'envoi.",
    );

    await transaction(() async {
      final ligne = await (select(
        messagesNotificationLocal,
      )..where((m) => m.id.equals(messageId))).getSingleOrNull();

      if (ligne == null) {
        throw const RefusNotification("Ce message n'existe plus.");
      }

      if (StatutMessageNotification.depuisCode(ligne.statut) !=
          StatutMessageNotification.enAttente) {
        throw const RefusNotification(
          'Ce message a déjà été transmis ou abandonné.',
        );
      }

      await (update(
        messagesNotificationLocal,
      )..where((m) => m.id.equals(messageId))).write(
        MessagesNotificationLocalCompanion(
          statut: Value(statut.code),
          commentaire: Value(commentaire),
          motifAbandon: Value(motifAbandon),
          traitePar: Value(auteur),
          traiteLe: Value(DateTime.now()),
        ),
      );
    });

    final apres = await (select(
      messagesNotificationLocal,
    )..where((m) => m.id.equals(messageId))).getSingle();

    return _versMessage(apres, await _declencheursParModele());
  }

  /* ---------------------------------------------------------------- internes */

  Future<Set<String>> _referencesDe(String modeleId) async {
    final lignes = await (select(
      messagesNotificationLocal,
    )..where((m) => m.modeleId.equals(modeleId))).get();
    return lignes.map((l) => l.reference).toSet();
  }

  Future<ModelesNotificationLocalData> _ligneModele(String id) async {
    final ligne = await (select(
      modelesNotificationLocal,
    )..where((m) => m.id.equals(id))).getSingleOrNull();
    if (ligne == null) {
      throw const RefusNotification("Ce modèle n'existe plus.");
    }
    return ligne;
  }

  Future<ModeleNotification?> _modeleParId(String id) async {
    final ligne = await (select(
      modelesNotificationLocal,
    )..where((m) => m.id.equals(id))).getSingleOrNull();
    return ligne == null ? null : _versModele(ligne);
  }

  static String _exigerContenu(String contenu) {
    final propre = contenu.trim();
    if (propre.isEmpty) {
      throw const RefusNotification('Le contenu du message est obligatoire.');
    }
    return propre;
  }

  static String? _objetOuNull(String? objet) => _texteOuNull(objet);

  static String? _texteOuNull(String? valeur) {
    final propre = valeur?.trim();
    return propre == null || propre.isEmpty ? null : propre;
  }

  ModeleNotification _versModele(ModelesNotificationLocalData d) =>
      ModeleNotification(
        id: d.id,
        evenementCode: d.evenement,
        declencheur: DeclencheurNotification.parCode(d.evenement),
        canalCode: d.canal,
        canal: CanalNotification.parCode(d.canal),
        contenuTemplate: d.contenuTemplate,
        objet: d.objet,
        actif: d.actif,
        creeLe: d.creeLe,
        modifieLe: d.modifieLe,
      );

  /// Le déclencheur de chaque modèle, par identifiant.
  ///
  /// Le message ne stocke PAS le code de l'événement : deux copies de la même
  /// information divergeraient le jour où l'une serait corrigée. Il se lit donc
  /// par son modèle.
  Future<Map<String, DeclencheurNotification?>> _declencheursParModele() async {
    final lignes = await select(modelesNotificationLocal).get();
    return {
      for (final l in lignes)
        l.id: DeclencheurNotification.parCode(l.evenement),
    };
  }

  MessageNotification _versMessage(
    MessagesNotificationLocalData d,
    Map<String, DeclencheurNotification?> declencheurs,
  ) {
    return MessageNotification(
      id: d.id,
      modeleId: d.modeleId,
      declencheur: declencheurs[d.modeleId],
      canal: CanalNotification.parCode(d.canal),
      reference: d.reference,
      destinataire: d.destinataire,
      objet: d.objet,
      contenu: d.contenu,
      longueur: d.longueur,
      statut: StatutMessageNotification.depuisCode(d.statut),
      composeLe: d.composeLe,
      commentaire: d.commentaire,
      motifAbandon: d.motifAbandon,
      traitePar: d.traitePar,
      traiteLe: d.traiteLe,
    );
  }
}
