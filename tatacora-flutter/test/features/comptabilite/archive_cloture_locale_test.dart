import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/impression/entete_etablissement.dart';
import 'package:tatacora_flutter/features/comptabilite/data/archive_cloture_locale.dart';
import 'package:tatacora_flutter/features/comptabilite/data/cloture_exercice_locale.dart';
import 'package:tatacora_flutter/features/comptabilite/data/comptabilite_dao.dart';
import 'package:tatacora_flutter/features/comptabilite/data/moteur_comptable.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/montant_comptable.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/refus_comptable.dart';

import 'support/outils_comptabilite.dart';

/// L'archive légale d'une clôture du poste (26/10/2026) : ses quatre fichiers,
/// l'empreinte SHA-256 du manifeste, l'immuabilité, la détection d'une
/// altération, le ZIP — et le CSV, quoté comme `fputcsv` de PHP.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late ComptabiliteDao dao;
  late MoteurComptable moteur;
  late ClotureExerciceLocale service;
  late ArchiveClotureLocale archive;
  late Directory racine;
  late String id2031;
  var horloge = DateTime(2031, 6, 15, 10);

  Future<void> exploiter() async {
    final centres = {for (final c in await dao.centres()) c.libelle: c.id};
    for (final (date, libelle, compteD, compteC, montant, centre) in [
      ('2031-03-10', 'Ventes du bar', '5711', '7011', '100000.00', 'Bar'),
      (
        '2031-03-11',
        'Marché "frais"; légumes',
        '6011',
        '5711',
        '30000.00',
        'Restaurant',
      ),
    ]) {
      await moteur.passerEtValider(
        DemandePiece(
          journal: 'CAI',
          date: date,
          libelle: libelle,
          lignes: [
            LigneDemandee(
              compte: compteD,
              debitCentimes: centimesDepuisChaine(montant),
              centreId: centres[centre],
            ),
            LigneDemandee(
              compte: compteC,
              creditCentimes: centimesDepuisChaine(montant),
              centreId: centres[centre],
            ),
          ],
        ),
        auteurId: auteurEssai,
      );
    }
  }

  Future<String> cloturer() async {
    await service.demarrer(id2031, auteurId: auteurEssai);
    return (await service.cloturer(id2031, auteurId: auteurEssai)).id;
  }

  setUp(() async {
    horloge = DateTime(2031, 6, 15, 10);
    db = await baseInstallee(maintenant: horloge);
    dao = ComptabiliteDao(db);
    moteur = moteurSur(db, maintenant: () => horloge);
    service = ClotureExerciceLocale(db, moteur, maintenant: () => horloge);
    racine = await Directory.systemTemp.createTemp('archive_cloture_');
    archive = ArchiveClotureLocale(
      dao,
      service,
      () async => racine,
      maintenant: () => horloge,
    );
    id2031 = (await dao.exerciceDeLAnnee(2031))!.id;
    await exploiter();
  });
  tearDown(() async {
    await db.close();
    if (racine.existsSync()) await racine.delete(recursive: true);
  });

  const entete = EnteteEtablissement();

  Directory dossierDe(String chemin) => Directory('${racine.path}/$chemin');

  group('Les quatre fichiers et l’empreinte', () {
    test('chaque fichier est écrit, le manifeste note leur SHA-256 et leur '
        'taille, l’empreinte est celle du manifeste — consignée', () async {
      final id = await cloturer();
      final faite = await archive.archiver(id, entete: entete);

      expect(faite.archiveEmpreinte, hasLength(64));
      expect(faite.archiveChemin, 'exercices/2031/$id');
      final dossier = dossierDe(faite.archiveChemin!);
      final noms = dossier.listSync().map((f) => f.uri.pathSegments.last);
      expect(noms.toSet(), {
        'ecritures.csv',
        'balance.csv',
        'etats-cloture.pdf',
        'manifeste.json',
      });

      final manifeste = File(
        '${dossier.path}/manifeste.json',
      ).readAsBytesSync();
      expect(sha256.convert(manifeste).toString(), faite.archiveEmpreinte);
      final lu = jsonDecode(utf8.decode(manifeste)) as Map<String, dynamic>;
      expect(lu['exercice'], 2031);
      expect(lu['periode'], ['2031-01-01', '2031-12-31']);
      expect(lu['referentiel'], 'SYSCOHADA révisé');
      expect(lu['algorithme'], 'sha256');
      expect(lu['origine'], 'poste');
      expect(lu['etablissement'], entete.raisonSociale);
      expect((lu['cloture'] as Map)['id'], id);
      expect((lu['cloture'] as Map)['resultat'], '70000.00');
      expect((lu['cloture'] as Map)['piece_cloture'], faite.pieceCloture);
      final fichiers = (lu['fichiers'] as Map)
          .cast<String, Map<String, dynamic>>();
      expect(fichiers.keys, [
        'ecritures.csv',
        'balance.csv',
        'etats-cloture.pdf',
      ]);
      for (final MapEntry(key: nom, value: note) in fichiers.entries) {
        final octets = File('${dossier.path}/$nom').readAsBytesSync();
        expect(note['sha256'], sha256.convert(octets).toString(), reason: nom);
        expect(note['octets'], octets.length, reason: nom);
      }
      expect(
        String.fromCharCodes(
          File('${dossier.path}/etats-cloture.pdf').readAsBytesSync().take(4),
        ),
        '%PDF',
      );
      expect(await archive.verifier(faite), isTrue);

      // L'empreinte est consignée sur la clôture, relue de la base.
      final active = (await service.clotureActive(id2031))!;
      expect(active.archiveEmpreinte, faite.archiveEmpreinte);
      expect(active.archiveChemin, faite.archiveChemin);
    });

    test(
      'le fichier des écritures dit TOUT : clôture et à-nouveaux compris, '
      'colonnes du serveur, libellé à guillemets et point-virgule quoté',
      () async {
        final id = await cloturer();
        final faite = await archive.archiver(id, entete: entete);
        final csv = utf8.decode(
          File(
            '${racine.path}/${faite.archiveChemin}/ecritures.csv',
          ).readAsBytesSync(),
        );
        final lignes = const LineSplitter().convert(csv);
        expect(lignes.first.split(';'), ArchiveClotureLocale.colonnesEcritures);
        expect(csv, contains('"Marché ""frais""; légumes"'));
        expect(
          csv,
          contains('CL;"Journal de clôture";CL-2031-00001;20311231;'),
        );
        // Les deux pièces de clôture de l'exercice 2031 : CL (7011, 6011, 131) ; les
        // à-nouveaux vont à l'exercice SUIVANT, donc pas dans cette archive.
        expect(lignes.where((l) => l.startsWith('CL;')), hasLength(3));
        expect(lignes.where((l) => l.startsWith('AN;')), isEmpty);
        // 2 pièces de 2 lignes, 3 lignes de clôture, l'en-tête.
        expect(lignes, hasLength(1 + 4 + 3));
      },
    );
  });

  group('Immuable : jamais réécrite, jamais délivrée altérée', () {
    test(
      'une seconde génération rend l’archive qui existe, octet pour octet',
      () async {
        final id = await cloturer();
        final une = await archive.archiver(id, entete: entete);
        final manifeste = File(
          '${racine.path}/${une.archiveChemin}/manifeste.json',
        ).readAsBytesSync();

        horloge = DateTime(2032, 1, 2, 9);
        final deux = await archive.archiver(id, entete: entete);
        expect(deux.archiveEmpreinte, une.archiveEmpreinte);
        expect(
          File(
            '${racine.path}/${une.archiveChemin}/manifeste.json',
          ).readAsBytesSync(),
          manifeste,
          reason: 'le manifeste (donc sa date de génération) n’a pas bougé',
        );
      },
    );

    test('un fichier modifié, supprimé ou un manifeste retouché : l’archive '
        'n’est plus intacte et le ZIP est refusé', () async {
      final id = await cloturer();
      final faite = await archive.archiver(id, entete: entete);
      final dossier = dossierDe(faite.archiveChemin!);
      expect(await archive.verifier(faite), isTrue);
      expect((await archive.zip(faite)).length, greaterThan(100));

      // 1. Une écriture retouchée.
      final ecritures = File('${dossier.path}/ecritures.csv');
      final original = ecritures.readAsBytesSync();
      ecritures.writeAsBytesSync([...original, 0x20]);
      expect(await archive.verifier(faite), isFalse);
      await expectLater(
        archive.zip(faite),
        throwsA(
          isA<RefusComptable>()
              .having((e) => e.motif, 'motif', MotifRefus.archiveAlteree)
              .having(
                (e) => e.message,
                'message',
                "L'archive de clôture ne correspond plus à son empreinte : un "
                    "fichier a été modifié ou supprimé. Elle n'est pas délivrée.",
              ),
        ),
      );
      ecritures.writeAsBytesSync(original);
      expect(await archive.verifier(faite), isTrue);

      // 2. Un fichier supprimé.
      final balance = File('${dossier.path}/balance.csv');
      final octets = balance.readAsBytesSync();
      balance.deleteSync();
      expect(await archive.verifier(faite), isFalse);
      balance.writeAsBytesSync(octets);

      // 3. Le manifeste lui-même (ses empreintes recalculées par un faussaire).
      final manifeste = File('${dossier.path}/manifeste.json');
      final texte = manifeste.readAsStringSync();
      manifeste.writeAsStringSync(texte.replaceAll('2031', '2030'));
      expect(await archive.verifier(faite), isFalse);
      manifeste.writeAsStringSync(texte);
      expect(await archive.verifier(faite), isTrue);
    });

    test(
      'une archive qui manque, ou sans empreinte, n’est jamais « intacte »',
      () async {
        final id = await cloturer();
        final cloture = (await service.clotureActive(id2031))!;
        expect(cloture.id, id);
        expect(await archive.verifier(cloture), isFalse);
        await expectLater(archive.zip(cloture), throwsA(isA<RefusComptable>()));
      },
    );

    test('une clôture rouverte n’a plus d’archive à produire ; la suivante a '
        'la sienne, l’ancienne reste', () async {
      final id1 = await cloturer();
      await service.rouvrir(
        id2031,
        auteurId: auteurEssai,
        motif: 'Facture oubliée en décembre',
      );
      await expectLater(
        archive.archiver(id1, entete: entete),
        throwsA(
          isA<RefusComptable>().having(
            (e) => e.motif,
            'motif',
            MotifRefus.archiveClotureRouverte,
          ),
        ),
      );

      final id2 = (await service.cloturer(id2031, auteurId: auteurEssai)).id;
      final neuve = await archive.archiver(id2, entete: entete);
      expect(neuve.archiveChemin, 'exercices/2031/$id2');
      expect(dossierDe('exercices/2031/$id1').existsSync(), isFalse);

      // Et si la première avait été archivée avant la réouverture, elle reste.
      await service.rouvrir(
        id2031,
        auteurId: auteurEssai,
        motif: 'Seconde correction tardive',
      );
      final id3 = (await service.cloturer(id2031, auteurId: auteurEssai)).id;
      await archive.archiver(id3, entete: entete);
      expect(dossierDe('exercices/2031/$id2').existsSync(), isTrue);
      expect(dossierDe('exercices/2031/$id3').existsSync(), isTrue);
    });

    test('une clôture inconnue est refusée à la phrase du serveur', () async {
      await expectLater(
        archive.archiver('inconnue', entete: entete),
        throwsA(
          isA<RefusComptable>().having(
            (e) => e.message,
            'message',
            "Cet exercice n'a pas de clôture active : il n'y a pas d'archive.",
          ),
        ),
      );
    });
  });

  group('Le ZIP', () {
    test('contient les quatre fichiers, octet pour octet', () async {
      final id = await cloturer();
      final faite = await archive.archiver(id, entete: entete);
      final octets = await archive.zip(faite);

      final tmp = File('${racine.path}/essai.zip')..writeAsBytesSync(octets);
      final sortie = await Process.run('php', [
        '-r',
        r'''
$z = new ZipArchive();
if ($z->open($argv[1], ZipArchive::CHECKCONS) !== true) { exit(2); }
$r = [];
for ($i = 0; $i < $z->numFiles; $i++) {
    $r[$z->getNameIndex($i)] = sha1((string) $z->getFromIndex($i));
}
echo json_encode($r);
''',
        tmp.path,
      ]);
      expect(sortie.exitCode, 0, reason: '${sortie.stderr}');
      final lu = (jsonDecode(sortie.stdout as String) as Map)
          .cast<String, String>();
      expect(lu.keys.toSet(), {
        'balance.csv',
        'ecritures.csv',
        'etats-cloture.pdf',
        'manifeste.json',
      });
      for (final MapEntry(key: nom, value: sha) in lu.entries) {
        expect(
          sha1
              .convert(
                File(
                  '${racine.path}/${faite.archiveChemin}/$nom',
                ).readAsBytesSync(),
              )
              .toString(),
          sha,
          reason: nom,
        );
      }
    });
  });

  group('Le CSV est quoté comme fputcsv de PHP', () {
    test('MÊMES OCTETS que PHP sur des champs à espaces, guillemets, point-'
        'virgule, tabulations et sauts de ligne', () async {
      final champs = <List<String>>[
        ['simple', 'avec espace', 'a;b', 'dit "oui"', '', 'tab\there'],
        [
          'ligne\nsuivante',
          'retour\rchariot',
          "l'apostrophe",
          'é à ç — ’',
          ' ',
          '12500,00',
        ],
        ['', '', '', '', '', ''],
        ['"', '""', ';', r'\', r'a\"b', 'x'],
      ];
      final php = await Process.run('php', [
        '-r',
        r'''
$lignes = json_decode($argv[1], true);
$f = fopen('php://temp', 'r+');
fwrite($f, "\xEF\xBB\xBF");
foreach ($lignes as $l) { fputcsv($f, $l, ';', '"', ''); }
rewind($f);
echo base64_encode(stream_get_contents($f));
''',
        jsonEncode(champs),
      ]);
      expect(php.exitCode, 0, reason: '${php.stderr}');
      expect(
        utf8.encode(ArchiveClotureLocale.ecrireCsv(champs)),
        base64Decode(php.stdout as String),
      );
    });

    test('les montants s’écrivent à virgule, les dates sans tiret', () {
      final ligne = LigneDArchive(
        codeJournal: 'VTE',
        libelleJournal: 'Journal des ventes',
        numeroPiece: 'VTE-2031-00001',
        dateEcriture: '2031-03-04',
        numeroCompte: '7011',
        libelleCompte: 'Ventes',
        libelleCentre: 'Bar',
        libelle: 'Vente',
        debitCentimes: 0,
        creditCentimes: 1250050,
        statut: 'validee',
        pieceContrepassee: 'VTE-2031-00000',
        saisieLe: DateTime(2031, 3, 5, 23, 59),
        saisiePar: 'kora',
      );
      expect(
        ArchiveClotureLocale.csvEcritures([ligne]).split('\n')[1],
        'VTE;"Journal des ventes";VTE-2031-00001;20310304;7011;Ventes;Bar;'
        'Vente;0,00;12500,50;validee;VTE-2031-00000;20310305;kora',
      );
    });
  });
}
