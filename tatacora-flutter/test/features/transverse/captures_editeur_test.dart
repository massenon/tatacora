import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/parametres/data/parametres_dao.dart';
import 'package:tatacora_flutter/features/transverse/data/captures_editeur.dart';
import 'package:tatacora_flutter/features/transverse/data/configuration_poste.dart';
import 'package:tatacora_flutter/features/transverse/data/envoi_messages_editeur.dart';
import 'package:tatacora_flutter/features/transverse/data/messages_editeur_dao.dart';
import 'package:tatacora_flutter/features/transverse/domain/messages_editeur.dart';

/// La capture d'écran d'un signalement de bug : contrôlée comme le serveur
/// (`image`, `mimes:png,jpg,jpeg`, `max:2048`), rangée à côté de `poste.json`,
/// jointe au courriel.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory dossier;
  late CapturesEditeur captures;

  setUp(() {
    dossier = Directory.systemTemp.createTempSync('captures_editeur_');
    captures = CapturesEditeur(
      cheminConfiguration: () async => '${dossier.path}/poste.json',
    );
  });
  tearDown(() => dossier.deleteSync(recursive: true));

  test('les bornes du serveur : PNG/JPG, 2048 Ko au plus', () {
    expect(verifierCapture('ecran.png', 10), isNull);
    expect(verifierCapture('ECRAN.JPG', 10), isNull);
    expect(verifierCapture('ecran.jpeg', 2048 * 1024), isNull);
    expect(verifierCapture('ecran.gif', 10), TextesCapture.nonImage);
    expect(verifierCapture('notes.txt', 10), TextesCapture.nonImage);
    expect(
      verifierCapture('ecran.png', 2048 * 1024 + 1),
      TextesCapture.tropLourde(),
    );
    expect(TextesCapture.tropLourde(), contains('2048 kilo-octets'));
  });

  test('une capture se range, se retrouve, se remplace et se retire', () async {
    expect(await captures.de('m1'), isNull);
    await captures.joindre('m1', nom: 'a.png', octets: [1, 2, 3]);
    expect(await captures.avecCapture(['m1', 'm2']), {'m1'});
    // Remplacée : une seule capture par message, même d'une autre extension.
    await captures.joindre('m1', nom: 'b.jpg', octets: [9]);
    final fichier = await captures.de('m1');
    expect(fichier!.path, endsWith('m1.jpg'));
    expect(fichier.readAsBytesSync(), [9]);
    expect(File('${dossier.path}/captures_editeur/m1.png').existsSync(), false);
    await captures.retirer('m1');
    expect(await captures.de('m1'), isNull);
  });

  test('une capture refusée n\'est pas écrite', () async {
    await expectLater(
      captures.joindre('m1', nom: 'a.gif', octets: [1]),
      throwsArgumentError,
    );
    expect(await captures.de('m1'), isNull);
  });

  test('le courriel du bug JOINT la capture, celui sans capture non', () async {
    final db = AppDatabase.enMemoire();
    addTearDown(db.close);
    await ParametresDao(db).ecrire({
      ClesSmtp.hote: 'mail.essai.local',
      ClesSmtp.utilisateur: 'contact@essai.local',
    }, auteurId: null);
    File(
      '${dossier.path}/poste.json',
    ).writeAsStringSync(jsonEncode({cleMotDePasseSmtp: 'S3cret-Gite!'}));
    final courriels = <Message>[];
    final service = ServiceMessagesEditeur(
      dao: MessagesEditeurDao(db),
      parametres: ParametresDao(db),
      configuration: LecteurConfigurationPoste(
        chemin: () async => '${dossier.path}/poste.json',
      ),
      captures: captures,
      transport: (Message m, SmtpServer s, Duration d) async =>
          courriels.add(m),
      maintenant: () => DateTime(2026, 10, 21, 9),
      envoiAutorise: true,
    );
    Future<MessageEditeur> ecrire(String sujet) => service.enregistrer(
      (
        type: TypeMessageEditeur.bug,
        sujet: sujet,
        moduleConcerne: 'M6 — Stocks',
        corps: 'Le stock ne bouge pas',
        etapes: null,
      ),
      auteurId: null,
      auteurLogin: null,
    );

    final sans = await ecrire('Bug — sans capture');
    await service.envoyer(sans);
    expect(courriels.single.attachments, isEmpty);

    final avec = await ecrire('Bug — avec capture');
    await captures.joindre(avec.id, nom: 'ecran.png', octets: [1, 2, 3]);
    await service.envoyer(avec);
    expect(courriels, hasLength(2));
    expect(courriels.last.attachments, hasLength(1));
  });
}
