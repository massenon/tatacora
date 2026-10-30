import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart'
    show EntreeSecurite;
import 'package:tatacora_flutter/features/synchronisation/data/descente_catalogue_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/data/service_adresse_serveur.dart';
import 'package:tatacora_flutter/features/synchronisation/data/transport_synchronisation.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/bilan_synchronisation.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';
import 'package:tatacora_flutter/features/transverse/data/journal_securite_dao.dart';
import 'package:tatacora_flutter/features/transverse/domain/journal_poste.dart';

import 'support/faux_transport.dart';

/// Le SERVICE de l'adresse du serveur (29/10/2026) : `poste.json`, le journal,
/// les états de reprise, la file d'envoi — sur une base et un fichier réels.
void main() {
  late BancSync b;
  late JournalSecuriteDao journal;
  final heure = DateTime.utc(2026, 10, 29, 9, 30);

  setUp(() async {
    b = await BancSync.creer(appaire: false);
    journal = JournalSecuriteDao(b.db);
  });
  tearDown(() => b.fermer());

  ServiceAdresseServeur service([
    FauxTransport? t,
    String? defaut = BancSync.urlServeur,
  ]) => ServiceAdresseServeur(
    transport:
        t ?? FauxTransport((_) => const ReponseHttp(statut: 200, corps: {})),
    urlParDefaut: defaut,
    journal: journal,
    lecteur: b.lecteur,
    ecrivain: b.ecrivain,
    descente: b.descente(
      FauxTransport((_) => const ReponseHttp(statut: 200, corps: {})),
    ),
    maintenant: () => heure,
  );

  Future<void> poserFichier(Map<String, Object?> contenu) =>
      File(b.cheminPoste).writeAsString(jsonEncode(contenu));

  Future<List<EntreeSecurite>> trace() => journal.entrees();

  group('écriture et relecture de poste.json', () {
    test(
      'sans fichier : l’adresse du build, aucune écriture à la lecture',
      () async {
        final e = (await service().etat())!;
        expect(e.racine, 'https://serveur.essai');
        expect(e.choisie, isFalse);
        expect(e.appaire, isFalse);
        expect(File(b.cheminPoste).existsSync(), isFalse);
      },
    );

    test(
      'enregistrer : la clé `serveur` existante, les autres clés intactes',
      () async {
        await poserFichier({
          'smtp_mot_de_passe': 'smtp-123',
          'synchronisation_activee': false,
          'synchronisation_desactivee_par': 'gerant',
          'cle_posee_a_la_main': {'x': 1},
          'poste_id': 'COMPTOIR-1',
          'jeton_api': '12|jeton-secret',
          'serveur': BancSync.urlServeur,
          'appaire_le': '2026-10-15T09:12:00.000Z',
          'compte': 'gerant',
        });
        final r = await service().enregistrer(
          'https://nouveau.essai/api/',
          auteurLogin: 'admin',
        );
        expect(r, isA<AdresseEnregistree>());
        final f = await b.fichier();
        expect(f['serveur'], 'https://nouveau.essai/api/v1');
        expect(f['serveur_modifie_par'], 'admin');
        expect(f['serveur_modifie_le'], heure.toIso8601String());
        // Rien d'autre n'a bougé : SMTP, interrupteur, clé inconnue, jeton gardé.
        expect(f['smtp_mot_de_passe'], 'smtp-123');
        expect(f['synchronisation_activee'], isFalse);
        expect(f['synchronisation_desactivee_par'], 'gerant');
        expect(f['cle_posee_a_la_main'], {'x': 1});
        expect(f['jeton_api'], '12|jeton-secret');
        expect(f['poste_id'], 'COMPTOIR-1');
        // L'ordre des clés d'origine est conservé, les nouvelles s'ajoutent.
        expect(f.keys.take(9).toList(), [
          'smtp_mot_de_passe',
          'synchronisation_activee',
          'synchronisation_desactivee_par',
          'cle_posee_a_la_main',
          'poste_id',
          'jeton_api',
          'serveur',
          'appaire_le',
          'compte',
        ]);
        // Relue : l'adresse choisie l'emporte sur celle du build.
        final e = (await service().etat())!;
        expect(e.racine, 'https://nouveau.essai');
        expect(e.choisie, isTrue);
        expect(e.appaire, isTrue);
        expect(await b.lecteur.synchronisationActivee(), isFalse);
      },
    );

    test(
      '« Effacer le jeton » : jeton et appairage partent, l’adresse reste, SMTP aussi',
      () async {
        await poserFichier({'smtp_mot_de_passe': 'smtp-123'});
        await b.appairer();
        final r = await service().enregistrer(
          'https://nouveau.essai',
          auteurLogin: 'admin',
          effacerJeton: true,
        );
        expect((r as AdresseEnregistree).jetonEfface, isTrue);
        final f = await b.fichier();
        for (final cle in ['jeton_api', 'poste_id', 'appaire_le', 'compte']) {
          expect(f.containsKey(cle), isFalse, reason: cle);
        }
        expect(f['serveur'], 'https://nouveau.essai/api/v1');
        expect(f['smtp_mot_de_passe'], 'smtp-123');
        expect(await b.lecteur.appairage(), isNull);
        expect(jsonEncode(f), isNot(contains('jeton-essai')));
      },
    );

    test(
      '« Dissocier » après un choix d’adresse garde l’adresse choisie',
      () async {
        await b.appairer();
        await service().enregistrer(
          'https://nouveau.essai',
          auteurLogin: 'admin',
        );
        await b.ecrivain.retirerAppairage();
        final f = await b.fichier();
        expect(f['serveur'], 'https://nouveau.essai/api/v1');
        expect(f.containsKey('jeton_api'), isFalse);
        expect((await service().etat())!.racine, 'https://nouveau.essai');
      },
    );

    test(
      'fichier illisible : refusé en français, fichier non touché',
      () async {
        await File(b.cheminPoste).writeAsString('{ pas du json');
        final r = await service().enregistrer(
          'https://nouveau.essai',
          auteurLogin: 'admin',
        );
        expect(r, isA<AdresseRefusee>());
        expect((r as AdresseRefusee).message, contains('illisible'));
        expect(await File(b.cheminPoste).readAsString(), '{ pas du json');
        expect(await trace(), isEmpty);
      },
    );

    test('adresse invalide : refusée, rien d’écrit ni de tracé', () async {
      await poserFichier({'smtp_mot_de_passe': 'x'});
      for (final mauvaise in ['http://logirestock.com', 'ftp://x', 'a b']) {
        expect(
          await service().enregistrer(mauvaise, auteurLogin: 'admin'),
          isA<AdresseRefusee>(),
        );
      }
      expect(await b.fichier(), {'smtp_mot_de_passe': 'x'});
      expect(await trace(), isEmpty);
    });

    test('la même adresse : inchangée, ni écriture ni trace', () async {
      expect(
        await service().enregistrer(
          'https://serveur.essai/api/v1',
          auteurLogin: 'admin',
        ),
        isA<AdresseInchangee>(),
      );
      expect(File(b.cheminPoste).existsSync(), isFalse);
      expect(await trace(), isEmpty);
    });

    test('démonstration : refusée', () async {
      expect(
        await service(
          null,
          null,
        ).enregistrer('https://nouveau.essai', auteurLogin: 'admin'),
        isA<AdresseRefusee>(),
      );
    });
  });

  group('audit', () {
    test(
      '« Adresse du serveur modifiée » : ancienne → nouvelle, auteur, machine, SANS jeton',
      () async {
        await b.appairer();
        await service().enregistrer(
          'https://nouveau.essai',
          auteurLogin: 'admin',
        );
        final lignes = await trace();
        expect(lignes, hasLength(1));
        final l = lignes.single;
        expect(l.action, 'adresse_serveur_modifiee');
        expect(l.auteurLogin, 'admin');
        expect(l.cibleLogin, 'https://serveur.essai → https://nouveau.essai');
        expect(l.posteNom, anyOf(isNull, isNotEmpty));
        final brut = jsonEncode([
          l.action,
          l.auteurLogin,
          l.posteNom,
          l.cibleId,
          l.cibleLogin,
        ]);
        expect(brut, isNot(contains('jeton')));
        expect(brut, isNot(contains(BancSync.jeton)));
        // Le Journal d'Audit la montre, avec son libellé de la vue du poste.
        final entree = entreeDepuisSecurite(
          action: l.action,
          creeLe: l.creeLe,
          auteurLogin: l.auteurLogin,
          posteNom: l.posteNom,
          cibleLogin: l.cibleLogin,
        )!;
        expect(entree.action.libelle, 'Adresse du serveur modifiée');
        expect(entree.libelleTable, 'Configuration du poste');
        expect(entree.entiteId, contains('→'));
      },
    );

    test('effacer le jeton se trace aussi, sans le jeton', () async {
      await b.appairer();
      await service().enregistrer(
        'https://nouveau.essai',
        auteurLogin: 'admin',
        effacerJeton: true,
      );
      final l = (await trace()).single;
      expect(
        jsonEncode([l.cibleLogin, l.auteurLogin]),
        isNot(contains(BancSync.jeton)),
      );
    });
  });

  group('file d’envoi, curseurs, reprise', () {
    test(
      'la file n’est pas touchée ; le repli de la descente est levé',
      () async {
        await b.appairer();
        await b.enfilerClients(3);
        final avant = (await b.dao.operations())
            .map(
              (o) => (
                o.uuidOperation,
                o.statut,
                o.tentatives,
                o.prochaineTentative,
              ),
            )
            .toList();
        final etat = DescenteCatalogueDao(b.db);
        await etat.poserRepli(
          echecs: 4,
          prochaine: DateTime.now().add(const Duration(hours: 1)),
        );
        await etat.retenirGeneration('g-1');

        await service().enregistrer(
          'https://nouveau.essai',
          auteurLogin: 'admin',
        );

        final apres = (await b.dao.operations())
            .map(
              (o) => (
                o.uuidOperation,
                o.statut,
                o.tentatives,
                o.prochaineTentative,
              ),
            )
            .toList();
        expect(apres, avant);
        expect((await b.comptes())[StatutOperationSync.enAttente], 3);
        final repli = await etat.repli();
        expect(repli.echecs, 0);
        expect(repli.prochaine, isNull);
        expect(
          await etat.generation(),
          'g-1',
          reason: 'les curseurs ne bougent pas',
        );
      },
    );

    test('enregistrer ne fait AUCUNE requête réseau', () async {
      final t = FauxTransport((_) => throw StateError('réseau interdit'));
      await b.appairer();
      await service(
        t,
      ).enregistrer('https://nouveau.essai', auteurLogin: 'admin');
      expect(t.requetes, isEmpty);
    });

    test(
      'adresse choisie : le moteur ne la prend plus pour « un autre serveur »',
      () async {
        await b.appairer(serveur: 'https://ailleurs.essai/api/v1');
        await b.enfilerClients(1);
        final t = FauxTransport(reponseLot);
        expect(
          (await b.manager(t).synchroniserMaintenant()).etat,
          EtatSynchronisation.autreServeur,
        );
        expect(t.requetes, isEmpty);

        await service().enregistrer(
          'https://ailleurs.essai',
          auteurLogin: 'admin',
        );
        final t2 = FauxTransport(reponseLot);
        final bilan = await b.manager(t2).synchroniserMaintenant();
        expect(bilan.etat, isNot(EtatSynchronisation.autreServeur));
        expect(
          t2.requetes.first.url.toString(),
          startsWith('https://ailleurs.essai/api/v1/'),
        );
      },
    );
  });

  group('« Tester la connexion »', () {
    test('GET <racine>/up, sans jeton, rien d’écrit', () async {
      await b.appairer();
      final t = FauxTransport(
        (_) => const ReponseHttp(statut: 200, corps: null),
      );
      final avant = await File(b.cheminPoste).readAsString();
      final r = await service(t).tester('https://nouveau.essai/api');
      expect(r.succes, isTrue);
      expect(t.requetes.single.url.toString(), 'https://nouveau.essai/up');
      expect(t.requetes.single.jeton, isNull);
      expect(await File(b.cheminPoste).readAsString(), avant);
      expect(await trace(), isEmpty);
      expect((await service().etat())!.racine, 'https://serveur.essai');
    });

    test(
      'injoignable, réponse étrangère, adresse invalide, interrupteur éteint',
      () async {
        expect(
          (await service(
            FauxTransport((_) => const ServeurInjoignable('x')),
          ).tester('https://nouveau.essai')).succes,
          isFalse,
        );
        final etrangere = await service(
          FauxTransport((_) => const ReponseHttp(statut: 404, corps: null)),
        ).tester('https://nouveau.essai');
        expect(etrangere.succes, isFalse);
        expect(etrangere.message, contains('404'));
        expect(
          (await service().tester('http://x.com')).message,
          contains('https://'),
        );
        await b.ecrivain.enregistrerSynchronisationActivee(
          false,
          par: 'gerant',
          le: heure,
        );
        final t = FauxTransport(
          (_) => const ReponseHttp(statut: 200, corps: null),
        );
        final eteint = await service(t).tester('https://nouveau.essai');
        expect(eteint.succes, isFalse);
        expect(
          t.requetes,
          isEmpty,
          reason: 'interrupteur éteint : zéro requête',
        );
      },
    );
  });

  group('fréquence dans poste.json', () {
    test('écrite, relue, le défaut retire la clé, le reste demeure', () async {
      await poserFichier({'smtp_mot_de_passe': 'smtp-123'});
      await b.ecrivain.enregistrerFrequenceSynchronisation(15);
      expect(await b.lecteur.frequenceSynchronisationMinutes(), 15);
      await b.ecrivain.enregistrerFrequenceSynchronisation(0);
      expect(await b.lecteur.frequenceSynchronisationMinutes(), 0);
      await b.ecrivain.enregistrerFrequenceSynchronisation(5);
      expect(await b.lecteur.frequenceSynchronisationMinutes(), isNull);
      expect(await b.fichier(), {'smtp_mot_de_passe': 'smtp-123'});
    });
  });
}
