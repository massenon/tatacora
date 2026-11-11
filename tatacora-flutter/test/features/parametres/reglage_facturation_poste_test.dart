import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/auth/domain/session.dart';
import 'package:tatacora_flutter/features/facturation/data/lecteur_mode_facturation.dart';
import 'package:tatacora_flutter/features/facturation/data/pilote_boitier.dart';
import 'package:tatacora_flutter/features/facturation/domain/adresse_boitier.dart';
import 'package:tatacora_flutter/features/facturation/domain/mode_facturation.dart';
import 'package:tatacora_flutter/features/parametres/data/parametres_depot_local.dart';
import 'package:tatacora_flutter/features/parametres/domain/enregistrer_parametres.dart';
import 'package:tatacora_flutter/features/parametres/domain/resultats_parametres.dart';
import 'package:tatacora_flutter/features/parametres/presentation/ecran_parametres.dart';
import 'package:tatacora_flutter/features/parametres/presentation/widgets/section_facturation_normalisee.dart';
import 'package:tatacora_flutter/features/synchronisation/presentation/providers_synchronisation.dart';
import 'package:tatacora_flutter/features/transverse/data/configuration_poste.dart';

import '../../support/faux_pilote_boitier.dart';

/// Lot 1 de la facturation normalisée, côté POSTE : le mode reçu du serveur en
/// LECTURE, la surcharge locale « ce poste certifie par », l'adresse du pilote
/// dans `poste.json`, « Tester le boîtier » contre un FAUX pilote HTTP, et la
/// règle qui ne se négocie pas : le JETON e-MECeF ne descend jamais ici.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  // `flutter_test` répond 400 à tout HttpClient : ces tests parlent à un VRAI
  // faux pilote sur la boucle locale (même levée que `reception_serveur_reel_test`).
  HttpOverrides.global = null;

  group('le mode, la surcharge et ce que le poste fait', () {
    test(
      'une valeur inconnue ou absente est « désactivé », jamais un mode réel',
      () {
        expect(ModeFacturation.depuisCode(null), ModeFacturation.desactive);
        expect(ModeFacturation.depuisCode(''), ModeFacturation.desactive);
        expect(ModeFacturation.depuisCode('BOITIER'), ModeFacturation.boitier);
        expect(
          ModeFacturation.depuisCode('nimportequoi'),
          ModeFacturation.desactive,
        );
        expect(modeDesParametres({}), ModeFacturation.desactive);
        expect(
          modeDesParametres({cleModeFacturation: 'emecef'}),
          ModeFacturation.emecef,
        );
      },
    );

    test(
      'la surcharge locale prime, sinon le mode du serveur (matrice complète)',
      () {
        const attendu = {
          (ModeFacturation.desactive, null): CertifiePar.rien,
          (ModeFacturation.emecef, null): CertifiePar.serveur,
          (ModeFacturation.boitier, null): CertifiePar.boitier,
          (ModeFacturation.desactive, SurchargeFacturation.boitier):
              CertifiePar.boitier,
          (ModeFacturation.emecef, SurchargeFacturation.boitier):
              CertifiePar.boitier,
          (ModeFacturation.boitier, SurchargeFacturation.serveur):
              CertifiePar.serveur,
          (ModeFacturation.boitier, SurchargeFacturation.rien):
              CertifiePar.rien,
          (ModeFacturation.emecef, SurchargeFacturation.rien): CertifiePar.rien,
          (ModeFacturation.desactive, SurchargeFacturation.serveur):
              CertifiePar.serveur,
        };
        expect(attendu.length, 9);
        attendu.forEach((entree, resultat) {
          expect(
            certifiePar(modeServeur: entree.$1, surcharge: entree.$2),
            resultat,
            reason: '${entree.$1} + ${entree.$2}',
          );
        });
      },
    );

    test('les phrases disent ce que le poste fait, et le réglage local', () {
      expect(
        phraseCertifiePar(CertifiePar.boitier, surchargeLocale: false),
        contains('boîtier CC300, même hors ligne'),
      );
      expect(
        phraseCertifiePar(CertifiePar.rien, surchargeLocale: true),
        endsWith('(réglage local de ce poste)'),
      );
      expect(
        phraseCertifiePar(CertifiePar.serveur, surchargeLocale: false),
        contains('laisse le serveur certifier'),
      );
    });
  });

  group('l’adresse du pilote', () {
    test('le défaut est le poste lui-même', () {
      expect(adresseBoitierParDefaut, 'http://localhost:38917');
      expect(
        (validerAdresseBoitier(adresseBoitierParDefaut) as AdresseBoitierValide)
            .racine,
        'http://localhost:38917',
      );
    });

    test('http seulement en local ; https permis ; aucun chemin ni secret', () {
      String? racine(String s) => switch (validerAdresseBoitier(s)) {
        AdresseBoitierValide(:final racine) => racine,
        AdresseBoitierInvalide() => null,
      };
      String? refus(String s) => switch (validerAdresseBoitier(s)) {
        AdresseBoitierValide() => null,
        AdresseBoitierInvalide(:final message) => message,
      };
      expect(racine(' http://127.0.0.1:38917/ '), 'http://127.0.0.1:38917');
      expect(racine('http://192.168.1.20:38917'), 'http://192.168.1.20:38917');
      expect(racine('http://10.0.0.5:38917'), 'http://10.0.0.5:38917');
      expect(racine('https://pilote.exemple.bj'), 'https://pilote.exemple.bj');
      expect(
        refus('http://pilote.exemple.bj'),
        TextesAdresseBoitier.httpLocalSeulement,
      );
      expect(refus(''), TextesAdresseBoitier.vide);
      expect(refus('localhost:38917'), TextesAdresseBoitier.schema);
      expect(refus('http://localhost:38917/bill'), TextesAdresseBoitier.chemin);
      expect(refus('http://localhost:38917?x=1'), TextesAdresseBoitier.chemin);
      expect(
        refus('http://u:p@localhost:38917'),
        TextesAdresseBoitier.identifiants,
      );
      expect(refus('http://local host:38917'), TextesAdresseBoitier.espaces);
      expect(refus('http://${'a' * 300}'), TextesAdresseBoitier.tropLongue);
    });
  });

  group('le registre : le mode se règle ici (Administrateur), le JETON jamais', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase.enMemoire();
      await db
          .into(db.utilisateursLocal)
          .insert(
            UtilisateursLocalCompanion.insert(
              id: 'u-essai',
              login: 'essai',
              nom: 'Essai',
              role: 'administrateur',
              droitsJson: '{}',
              sel: 's',
              empreinte: 'e',
              iterations: 1,
              dateCreation: DateTime(2026, 11, 7),
              dateMotDePasse: DateTime(2026, 11, 7),
            ),
          );
    });

    tearDown(() => db.close());

    test('l’IFU compte 13 chiffres : refus à 12, accepté à 13', () async {
      final cas = EnregistrerParametres(ParametresDepotLocal(db));
      final non = await cas.executer(
        {'entreprise_ifu': '320261234567'},
        peutEcrire: true,
        auteurId: 'u-essai',
      );
      expect(non, isA<EcritureRefusee>());
      final oui = await cas.executer(
        {'entreprise_ifu': '3202612345678'},
        peutEcrire: true,
        auteurId: 'u-essai',
      );
      expect(oui, isA<EcritureAcceptee>());
    });

    test('le mode DESCEND du serveur et se lit ; le poste garde la dernière '
        'valeur connue', () async {
      final depot = ParametresDepotLocal(db);
      final lecteur = LecteurModeFacturation(
        db,
        lecteur: LecteurConfigurationPoste(
          chemin: () async => 'inexistant.json',
        ),
      );
      expect((await lecteur.lire()).modeServeur, ModeFacturation.desactive);

      await depot.inscrireDescendue('facturation_mode', 'boitier');
      var etat = await lecteur.lire();
      expect(etat.modeServeur, ModeFacturation.boitier);
      expect(etat.certifiePar, CertifiePar.boitier);
      expect(etat.adresseBoitier, adresseBoitierParDefaut);

      // Hors ligne : rien ne descend, la ligne reste — le dernier mode connu vaut.
      etat = await lecteur.lire();
      expect(etat.modeServeur, ModeFacturation.boitier);

      // Descendu « vide » (effacé au serveur) : retour à « désactivé ».
      await depot.inscrireDescendue('facturation_mode', null);
      expect((await lecteur.lire()).certifiePar, CertifiePar.rien);
    });

    test('le JETON ne descend JAMAIS : une clé de jeton est ignorée, et rien '
        'dans lib/ ne la nomme', () async {
      final depot = ParametresDepotLocal(db);
      for (final cle in const ['mecef_jeton_api', 'mecef_jeton', 'jeton_jwt']) {
        await depot.inscrireDescendue(cle, 'eyJhbGciOiJIUzI1NiJ9.x.y');
      }
      expect(await db.select(db.parametresSystemeLocal).get(), isEmpty);

      // Garde LUE : aucun fichier du poste ne nomme la clé du secret du serveur.
      var lus = 0;
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        lus++;
        final source = f.readAsStringSync();
        expect(source, isNot(contains('mecef_jeton_api')), reason: f.path);
        expect(
          source,
          isNot(contains('secrets_configuration')),
          reason: f.path,
        );
      }
      expect(lus, greaterThan(200), reason: 'le balayage lit des fichiers');
    });

    test('la descente ne retient que des clés du registre : le registre local '
        'n’a aucune clé de secret', () {
      final source = File(
        'lib/features/parametres/domain/registre_parametres_local.dart',
      ).readAsStringSync();
      expect(source, isNot(contains('jeton')));
    });
  });

  group('l’écran', () {
    late Directory dossier;
    late AppDatabase db;
    late String cheminPoste;
    FauxPilote? pilote;

    setUp(() async {
      HttpOverrides.global = null;
      dossier = await Directory.systemTemp.createTemp('tatacora-mecef-poste-');
      cheminPoste = '${dossier.path}/poste.json';
      db = AppDatabase.surFichier(File('${dossier.path}/tatacora.sqlite'));
    });

    tearDown(() async {
      await pilote?.arreter();
      pilote = null;
      await db.close();
      if (dossier.existsSync()) await dossier.delete(recursive: true);
    });

    Future<void> laisserTourner(WidgetTester tester) async {
      for (var i = 0; i < 40; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
    }

    Future<void> monter(
      WidgetTester tester, {
      String role = 'administrateur',
      double largeur = 1200,
      bool ecranComplet = false,
    }) async {
      tester.view
        ..physicalSize = Size(largeur, 4000)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final droits = GardeAcces({'PARAM': 'C'});
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            baseLocaleProvider.overrideWithValue(db),
            droitsProvider.overrideWithValue(droits),
            sessionProvider.overrideWithBuild(
              (ref, n) => Session(
                utilisateurId: 'u-1',
                login: 'admin-essai',
                nom: 'Essai',
                role: role,
                droits: droits,
              ),
            ),
            cheminConfigurationPosteProvider.overrideWithValue(
              () async => cheminPoste,
            ),
            if (pilote != null)
              fabriquePiloteBoitierProvider.overrideWithValue(
                (racine) => PiloteBoitier(racine: racine),
              ),
          ],
          child: MaterialApp(
            theme: AppTheme.clair,
            home: Scaffold(
              body: ecranComplet
                  ? const EcranParametres()
                  : const SingleChildScrollView(
                      padding: EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [MentionJetonMecef(), CarteBoitierPoste()],
                      ),
                    ),
            ),
          ),
        ),
      );
      await laisserTourner(tester);
    }

    Future<Map<String, Object?>> fichier() async =>
        jsonDecode(await File(cheminPoste).readAsString())
            as Map<String, Object?>;

    testWidgets(
      'le réglage local s’écrit dans poste.json et la phrase le dit',
      (tester) async {
        await monter(tester);
        expect(find.byKey(const Key('param-mecef-phrase')), findsOneWidget);
        expect(
          find.textContaining('Mode reçu du serveur : Désactivé'),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const Key('param-mecef-surcharge')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Le boîtier CC300 de ce poste').last);
        await laisserTourner(tester);

        expect(
          (await tester.runAsync(fichier))!['facturation_surcharge'],
          'boitier',
        );
        expect(
          find.textContaining('réglage local de ce poste'),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const Key('param-mecef-surcharge')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Comme le réglage du serveur').last);
        await laisserTourner(tester);
        expect(
          (await tester.runAsync(
            fichier,
          ))!.containsKey('facturation_surcharge'),
          isFalse,
          reason: 'revenir au serveur retire la clé',
        );
      },
    );

    testWidgets('l’adresse du pilote : validée, enregistrée dans poste.json '
        'sans recompiler, défaut rétabli', (tester) async {
      await monter(tester);
      await tester.enterText(
        find.byKey(const Key('param-mecef-adresse')),
        'http://pilote.exemple.bj',
      );
      await tester.tap(find.byKey(const Key('param-mecef-enregistrer')));
      await laisserTourner(tester);
      expect(
        find.text(TextesAdresseBoitier.httpLocalSeulement),
        findsOneWidget,
      );
      expect(File(cheminPoste).existsSync(), isFalse);

      await tester.enterText(
        find.byKey(const Key('param-mecef-adresse')),
        'http://192.168.1.20:38917/',
      );
      await tester.tap(find.byKey(const Key('param-mecef-enregistrer')));
      await laisserTourner(tester);
      expect(
        (await tester.runAsync(fichier))!['facturation_boitier_adresse'],
        'http://192.168.1.20:38917',
      );
      expect(find.text('Actuelle : http://192.168.1.20:38917'), findsOneWidget);

      await tester.tap(find.byKey(const Key('param-mecef-defaut')));
      await laisserTourner(tester);
      expect(
        (await tester.runAsync(
          fichier,
        ))!.containsKey('facturation_boitier_adresse'),
        isFalse,
      );
      expect(find.text('Actuelle : $adresseBoitierParDefaut'), findsOneWidget);
    });

    testWidgets('un non-administrateur voit le réglage mais ne l’écrit pas', (
      tester,
    ) async {
      await monter(tester, role: 'caissier');
      expect(find.byKey(const Key('param-mecef-enregistrer')), findsNothing);
      expect(find.text(TextesFacturationPoste.reserve), findsOneWidget);
      final liste = tester.widget<DropdownButton<SurchargeFacturation?>>(
        find.byKey(const Key('param-mecef-surcharge')),
      );
      expect(liste.onChanged, isNull);
    });

    testWidgets('« Tester le boîtier » : /check puis /info — NIM, IFU, taux, '
        'dernière connexion', (tester) async {
      pilote = await tester.runAsync(FauxPilote.demarrer);
      await monter(tester);
      await tester.enterText(
        find.byKey(const Key('param-mecef-adresse')),
        pilote!.racine,
      );
      await tester.tap(find.byKey(const Key('param-mecef-tester')));
      await laisserTourner(tester);

      final texte = tester
          .widget<Text>(find.byKey(const Key('param-mecef-message')))
          .data!;
      expect(texte, contains('NIM ED04000623'));
      expect(texte, contains('IFU 3201910768821'));
      expect(texte, contains('B 18.00 %'));
      expect(texte, contains('Dernière connexion à la DGI : 2026-11-07 09:55'));
      expect(pilote!.requetes, ['GET /check', 'GET /info']);
      expect(
        pilote!.corpsPost,
        isEmpty,
        reason: 'aucune facture n’est envoyée',
      );
    });

    testWidgets('« Tester le boîtier » : appareil absent, pilote éteint, IFU '
        'différent — des phrases françaises', (tester) async {
      pilote = await tester.runAsync(FauxPilote.demarrer);
      pilote!.appareilAbsent = true;
      await monter(tester);
      await tester.enterText(
        find.byKey(const Key('param-mecef-adresse')),
        pilote!.racine,
      );
      await tester.tap(find.byKey(const Key('param-mecef-tester')));
      await laisserTourner(tester);
      expect(find.textContaining('n’est pas branché'), findsOneWidget);

      pilote!.appareilAbsent = false;
      await db
          .into(db.parametresSystemeLocal)
          .insert(
            ParametresSystemeLocalCompanion.insert(
              cle: 'entreprise_ifu',
              valeur: '0202011344660',
              modifieLe: DateTime(2026, 11, 7),
            ),
          );
      await tester.tap(find.byKey(const Key('param-mecef-tester')));
      await laisserTourner(tester);
      expect(
        find.textContaining(
          'l’IFU du boîtier (3201910768821) n’est pas celui de l’entreprise '
          '(0202011344660)',
        ),
        findsOneWidget,
      );

      await tester.runAsync(pilote!.arreter);
      await tester.tap(find.byKey(const Key('param-mecef-tester')));
      await laisserTourner(tester);
      expect(find.textContaining('ne répond pas'), findsOneWidget);
    });

    testWidgets('le jeton n’est jamais affiché, ni reçu, ni saisissable ici : '
        'l’écran complet dit « géré au serveur » (et le mode se modifie)', (
      tester,
    ) async {
      await db
          .into(db.parametresSystemeLocal)
          .insert(
            ParametresSystemeLocalCompanion.insert(
              cle: 'facturation_mode',
              valeur: 'boitier',
              modifieLe: DateTime(2026, 11, 7),
            ),
          );
      await monter(tester, ecranComplet: true);
      await tester.scrollUntilVisible(
        find.byKey(const Key('param-mecef-jeton')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Facturation normalisée (MECeF)'), findsOneWidget);
      expect(find.text('Jeton JWT e-MECeF'), findsOneWidget);
      expect(find.textContaining('ne reçoit jamais le jeton'), findsOneWidget);
      // Le mode se dit par son LIBELLÉ de la vue, et un Administrateur le MODIFIE
      // (09/11/2026 : « le poste fait ce que le web fait ») ; le jeton, lui, reste
      // « géré au serveur », sans aucun bouton ni champ.
      expect(
        find.byKey(const Key('param-ligne-facturation_mode')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('param-ligne-facturation_mode')),
          matching: find.text('Boîtier CC300 (poste)'),
        ),
        findsOneWidget,
        reason: 'le libellé de la vue, jamais le code « boitier »',
      );
      for (final cle in const [
        'facturation_mode',
        'mecef_api_url',
        'mecef_operateur_id',
        'mecef_operateur_nom',
      ]) {
        expect(
          find.byKey(Key('param-modifier-$cle')),
          findsOneWidget,
          reason: 'un Administrateur modifie $cle',
        );
      }
      expect(find.byKey(const Key('param-modifier-jeton')), findsNothing);
      expect(find.textContaining('Modifier le jeton'), findsNothing);
      // Aucun champ de mot de passe sur tout l'écran.
      expect(
        find.byWidgetPredicate((w) => w is TextField && w.obscureText),
        findsNothing,
      );
      expect(find.textContaining('eyJ'), findsNothing);
    });

    testWidgets(
      'un NON-administrateur voit les cinq réglages réservés sans bouton '
      '« Modifier » ; les documents gardent le leur (droit PARAM)',
      (tester) async {
        await monter(tester, role: 'caissier', ecranComplet: true);
        await tester.scrollUntilVisible(
          find.byKey(const Key('param-mecef-jeton')),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        for (final cle in const [
          'facturation_mode',
          'mecef_api_url',
          'mecef_operateur_id',
          'mecef_operateur_nom',
          'forme_juridique',
        ]) {
          expect(
            find.byKey(Key('param-ligne-$cle')),
            findsOneWidget,
            reason: '$cle se voit',
          );
          expect(
            find.byKey(Key('param-modifier-$cle')),
            findsNothing,
            reason: '$cle : pas de « Modifier » hors administrateur',
          );
        }
        expect(
          find.byKey(const Key('param-modifier-entreprise_activites')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('param-modifier-entreprise_ville_emission')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('param-modifier-proforma_validite_jours')),
          findsOneWidget,
        );
      },
    );

    testWidgets('un Administrateur modifie le mode : liste des trois libellés de '
        'la vue, écriture enfilée, jamais de normalisation', (tester) async {
      await db.transaction(() async {
        for (final e in const {
          'entreprise_ifu': '0202011344660',
          'mecef_operateur_id': 'RECEPTION01',
          'mecef_operateur_nom': 'Réception',
        }.entries) {
          await db
              .into(db.parametresSystemeLocal)
              .insert(
                ParametresSystemeLocalCompanion.insert(
                  cle: e.key,
                  valeur: e.value,
                  modifieLe: DateTime(2026, 11, 9),
                ),
              );
        }
        await db
            .into(db.utilisateursLocal)
            .insert(
              UtilisateursLocalCompanion.insert(
                id: 'u-1',
                login: 'admin-essai',
                nom: 'Essai',
                role: 'administrateur',
                droitsJson: '{}',
                sel: 's',
                empreinte: 'e',
                iterations: 1,
                dateCreation: DateTime(2026, 11, 9),
                dateMotDePasse: DateTime(2026, 11, 9),
              ),
            );
      });
      await monter(tester, ecranComplet: true);
      await tester.scrollUntilVisible(
        find.byKey(const Key('param-mecef-jeton')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(
        find.byKey(const Key('param-modifier-facturation_mode')),
      );
      await tester.tap(
        find.byKey(const Key('param-modifier-facturation_mode')),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text(
            'Désactivé : factures simples, sans valeur fiscale ni mention de normalisation. '
            'e-MECeF : le serveur certifie par l’API de la DGI (réseau exigé). '
            'Boîtier CC300 : le poste de la réception certifie par le boîtier '
            'branché en USB, même hors ligne. Réservé aux Administrateurs.',
          ),
        ),
        findsOneWidget,
        reason: 'la même aide que le web',
      );
      await tester.tap(find.byKey(const Key('param-champ-facturation_mode')));
      await tester.pumpAndSettle();
      for (final libelle in const [
        'Désactivé',
        'e-MECeF (en ligne)',
        'Boîtier CC300 (poste)',
      ]) {
        expect(find.text(libelle), findsWidgets, reason: libelle);
      }
      await tester.tap(find.text('Boîtier CC300 (poste)').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('param-enregistrer')));
      await laisserTourner(tester);

      final valeurs = {
        for (final r in await db.select(db.parametresSystemeLocal).get())
          r.cle: r.valeur,
      };
      expect(valeurs['facturation_mode'], 'boitier');
      final file = await db.select(db.operationsSyncLocal).get();
      expect(file, hasLength(1), reason: 'une écriture, aucune normalisation');
      expect(file.single.tableServeur, 'parametres_systeme');
      expect(jsonDecode(file.single.payload), {
        'valeurs': {'facturation_mode': 'boitier'},
      });
    });

    for (final largeur in [320.0, 360.0, 480.0, 768.0, 1024.0, 1600.0]) {
      testWidgets('aucun débordement, largeur $largeur (messages longs '
          'affichés)', (tester) async {
        pilote = await tester.runAsync(FauxPilote.demarrer);
        await monter(tester, largeur: largeur);
        await tester.enterText(
          find.byKey(const Key('param-mecef-adresse')),
          pilote!.racine,
        );
        await tester.tap(find.byKey(const Key('param-mecef-tester')));
        await laisserTourner(tester);
        expect(tester.takeException(), isNull, reason: 'essai $largeur');
        await tester.tap(find.byKey(const Key('param-mecef-surcharge')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'liste $largeur');
      });
    }
  });
}
