import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/periode_sejour.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/reservation.dart';
import 'package:tatacora_flutter/features/notifications/data/notifications_dao.dart';
import 'package:tatacora_flutter/features/notifications/domain/entities/canal_notification.dart';
import 'package:tatacora_flutter/features/notifications/domain/entities/declencheur_notification.dart';
import 'package:tatacora_flutter/features/notifications/domain/entities/message_notification.dart';
import 'package:tatacora_flutter/features/notifications/domain/entities/modele_notification.dart';

/// M12 — le référentiel, la file, et LE point qui commande tout le module.
///
/// ## Ce que ces cas protègent
///
/// **Qu'aucun geste de ce poste ne puisse affirmer un envoi.** Le maître écrit
/// la conséquence : « un message marqué "envoyé" alors que rien n'est parti
/// serait pire que pas de module du tout : le Gérant croirait son client
/// prévenu ». C'est la famille PA-59/60/61, et c'est le dernier cas de ce
/// fichier qui la tient.
void main() {
  late AppDatabase db;
  late NotificationsDao dao;

  final aujourdHui = DateTime(2026, 9, 14);

  setUp(() {
    db = AppDatabase.enMemoire();
    dao = NotificationsDao(db);
  });

  tearDown(() => db.close());

  // ⚠ Le type de retour comptait : déclaré `Future<void>`, ce raccourci
  // JETAIT le modèle que `creerModele` rend, et `final m = await semerModele()`
  // valait alors `void` — d'où « use_of_void_result » sur `m.id`. Le défaut
  // n'était pas dans le DAO, qui a toujours rendu son modèle.
  Future<ModeleNotification> semerModele({
    DeclencheurNotification declencheur = DeclencheurNotification.sejourDemain,
    CanalNotification canal = CanalNotification.whatsapp,
    String contenu = 'Bonjour {client}, arrivée le {date_arrivee}.',
    bool actif = true,
  }) => dao.creerModele(
    declencheur: declencheur,
    canal: canal,
    contenuTemplate: contenu,
    actif: actif,
  );

  List<Reservation> arriveeDemain() => [
    Reservation(
      id: 'r1',
      reference: 'LOC-1',
      clientId: 'c1',
      clientNom: 'KORA',
      uniteId: 'u1',
      periode: PeriodeSejour(
        arrivee: DateTime(2026, 9, 15),
        depart: DateTime(2026, 9, 18),
      ),
      tarifNuit: 25000,
      statut: StatutReservation.confirmee,
      statutSynchronisation: StatutSynchronisation.local,
      creeeLe: aujourdHui,
    ),
  ];

  Future<BilanDetection> detecter() =>
      dao.detecter(reservations: arriveeDemain(), aujourdHui: aujourdHui);

  /* ================================================================== */
  group('Le référentiel des modèles', () {
    test('un modèle se crée et se relit avec son déclencheur', () async {
      await semerModele();
      final modeles = await dao.modeles();

      expect(modeles.length, 1);
      expect(modeles.single.declencheur, DeclencheurNotification.sejourDemain);
      expect(modeles.single.canal, CanalNotification.whatsapp);
      expect(modeles.single.actif, isTrue);
    });

    test('le même couple (événement, canal) est REFUSÉ', () async {
      await semerModele();

      expect(
        () => semerModele(),
        throwsA(
          isA<RefusNotification>().having(
            (e) => e.message,
            'message',
            contains('existe déjà'),
          ),
        ),
      );
    });

    test('le même événement sur un AUTRE canal est accepté', () async {
      await semerModele();
      await semerModele(canal: CanalNotification.email);

      expect((await dao.modeles()).length, 2);
    });

    test('un contenu vide est refusé', () async {
      expect(
        () => semerModele(contenu: '   '),
        throwsA(isA<RefusNotification>()),
      );
    });

    test('la bascule active et désactive, sans jamais supprimer', () async {
      final m = await semerModele();

      final apres = await dao.basculerActivation(m.id);
      expect(apres.actif, isFalse);
      // Le modèle est TOUJOURS là : la désactivation EST le geste métier.
      expect((await dao.modeles()).length, 1);

      expect((await dao.basculerActivation(m.id)).actif, isTrue);
    });
  });

  /* ================================================================== */
  group('La détection', () {
    test('elle compose un message réel à partir des réservations', () async {
      await semerModele();

      final bilan = await detecter();

      expect(bilan.composes, 1);
      final file = await dao.file();
      expect(file.single.destinataire, 'KORA');
      // De VRAIES données : ni accolade, ni valeur de démonstration.
      expect(file.single.contenu, 'Bonjour KORA, arrivée le 15/09/2026.');
      expect(file.single.declencheur, DeclencheurNotification.sejourDemain);
    });

    test('relancée, elle ne DUPLIQUE pas — idempotence', () async {
      // Sans elle, la file se remplirait de doublons à chaque clic, et le
      // Gérant relancerait deux fois le même client.
      await semerModele();

      await detecter();
      final second = await detecter();

      expect(second.composes, 0);
      expect(second.dejaEnFile, 1);
      expect((await dao.file()).length, 1);
    });

    test('un modèle DÉSACTIVÉ ne compose rien', () async {
      await semerModele(actif: false);

      final bilan = await detecter();
      expect(bilan.composes, 0);
      // Il n'a pas été passé au crible : rien n'a donc été REGARDÉ.
      expect(bilan.modelesExamines, 0);
      expect(await dao.file(), isEmpty);
    });

    test('aucun modèle : rien n’a été REGARDÉ, et le bilan le dit', () async {
      // ⚠ LE CAS QUI COMPTE. Sans `modelesExamines`, les trois autres nombres
      // valent zéro ici EXACTEMENT comme quand des modèles ont été examinés
      // sans rien trouver — et l'écran concluait « Aucun nouvel événement à
      // notifier », une affirmation sur les ÉVÉNEMENTS tirée d'une mesure qui
      // n'a porté que sur les MODÈLES (PA-59/60/61). Rien ne sème le
      // référentiel sur ce poste : le cas est celui d'un poste neuf.
      final bilan = await detecter();

      expect(bilan.modelesExamines, 0);
      expect(bilan.rienDeRegarde, isTrue);
      expect(bilan.composes, 0);
      expect(bilan.dejaEnFile, 0);
      expect(bilan.refus, isEmpty);
    });

    test(
      'un modèle EXAMINÉ qui ne trouve rien n’est pas « rien regardé »',
      () async {
        // Le pendant du cas précédent, et il est indispensable : sans lui,
        // `rienDeRegarde` passerait tout aussi bien s'il valait TOUJOURS vrai.
        await semerModele();

        final bilan = await dao.detecter(
          reservations: const [],
          aujourdHui: aujourdHui,
        );

        expect(bilan.modelesExamines, 1);
        expect(bilan.rienDeRegarde, isFalse);
        expect(bilan.composes, 0);
      },
    );

    test('un modèle sur un déclencheur non détecté ne compose rien, et ce '
        'n est pas une erreur', () async {
      // Ce n'est pas une faute de saisie : le signaler comme telle ferait
      // chercher une erreur là où il n'y a qu'une absence de données.
      await semerModele(
        declencheur: DeclencheurNotification.stockSousSeuil,
        contenu: '{article} sous le seuil.',
      );

      final bilan = await detecter();

      expect(bilan.composes, 0);
      expect(bilan.refus, isEmpty);
      // Filtré avant tout examen : le modèle existe, mais ce poste ne sait
      // pas regarder son déclencheur. « Rien regardé » reste donc vrai — et
      // c'est pourquoi la phrase de l'écran ne conseille RIEN : ici, « créez
      // un modèle » serait un mauvais conseil, il y en a un.
      expect(bilan.modelesExamines, 0);
    });

    test('une variable non résolue REFUSE, et rien n entre en file', () async {
      await semerModele(contenu: 'Vous devez {montant} FCFA.');

      final bilan = await detecter();

      expect(bilan.composes, 0);
      expect(bilan.refus.single.motif, contains('{montant}'));
      expect(await dao.file(), isEmpty);
    });
  });

  /* ================================================================== */
  group('Les gestes sur la file', () {
    Future<MessageNotification> unMessageEnFile() async {
      await semerModele();
      await detecter();
      return (await dao.file()).single;
    }

    test(
      '« Transmis à la main » sort de la file et garde son auteur',
      () async {
        final m = await unMessageEnFile();

        final apres = await dao.marquerTransmis(
          m.id,
          auteur: 'reception',
          commentaire: 'Appelé au téléphone',
        );

        expect(apres.statut, StatutMessageNotification.transmisALaMain);
        expect(apres.traitePar, 'reception');
        expect(apres.commentaireAffiche, 'Appelé au téléphone');
        expect(await dao.file(), isEmpty);
        expect((await dao.journal()).length, 1);
      },
    );

    test('un abandon SANS motif est refusé', () async {
      final m = await unMessageEnFile();

      expect(
        () => dao.abandonner(m.id, auteur: 'reception', motif: '  '),
        throwsA(isA<RefusNotification>()),
      );
      // Le message reste en file : un refus n'écrit rien.
      expect((await dao.file()).length, 1);
    });

    test('un abandon motivé reste au journal, avec son motif', () async {
      final m = await unMessageEnFile();

      final apres = await dao.abandonner(
        m.id,
        auteur: 'gerant',
        motif: 'Client déjà prévenu sur place',
      );

      expect(apres.statut, StatutMessageNotification.abandonne);
      expect(apres.commentaireAffiche, 'Client déjà prévenu sur place');
    });

    test('un message déjà traité ne se retraite pas', () async {
      final m = await unMessageEnFile();
      await dao.marquerTransmis(m.id, auteur: 'reception');

      expect(
        () => dao.abandonner(m.id, auteur: 'gerant', motif: 'trop tard'),
        throwsA(
          isA<RefusNotification>().having(
            (e) => e.message,
            'message',
            contains('déjà'),
          ),
        ),
      );
    });
  });

  /* ================================================================== */
  group('AUCUN envoi n est jamais affirmé', () {
    test('aucun geste du DAO ne produit le statut « envoyé »', () async {
      // ⚠ LE cas du module. Il énumère les gestes publics qui écrivent, les
      // exécute tous, et exige qu'aucun n'ait pu affirmer un départ.
      //
      // Il ne se contente pas de lire le compteur : il fait passer un message
      // par CHAQUE sortie de file possible, parce qu'un statut d'envoi
      // n'apparaîtrait que sur un chemin réellement emprunté (piège n° 5).
      await semerModele();
      await semerModele(canal: CanalNotification.email);
      await detecter();

      final enFile = await dao.file();
      expect(enFile.length, 2, reason: 'les deux modèles ont composé');

      await dao.marquerTransmis(enFile.first.id, auteur: 'reception');
      await dao.abandonner(enFile.last.id, auteur: 'gerant', motif: 'doublon');

      for (final m in await dao.messages()) {
        expect(
          m.statut,
          isNot(StatutMessageNotification.envoyeParLeSysteme),
          reason: 'aucun transport n existe sur ce poste',
        );
        expect(m.statut.estUnEnvoiDuSysteme, isFalse);
      }
    });

    test(
      '« Réellement envoyés » vaut zéro, et il est COMPTÉ en base',
      () async {
        // Il vaut zéro parce que rien ne peut produire ce statut, pas parce
        // qu'une constante le dit (PA-61). Le compteur interroge la table.
        await semerModele();
        await detecter();

        expect(await dao.nombreEnvoisReels(), 0);

        final m = (await dao.file()).single;
        await dao.marquerTransmis(m.id, auteur: 'reception');

        // Et transmettre à la main ne l'incrémente PAS : ce n'est pas le
        // logiciel qui a fait partir le message.
        expect(await dao.nombreEnvoisReels(), 0);
      },
    );

    test('« transmis à la main » n est JAMAIS un envoi système', () async {
      await semerModele();
      await detecter();
      final m = (await dao.file()).single;

      final apres = await dao.marquerTransmis(m.id, auteur: 'reception');

      expect(apres.statut.estUnEnvoiDuSysteme, isFalse);
      expect(apres.statut.libelle, 'Transmis à la main');
    });
  });
}
