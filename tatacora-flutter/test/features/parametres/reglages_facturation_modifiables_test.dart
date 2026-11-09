import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show OrderingTerm, driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/parametres/data/parametres_dao.dart';
import 'package:tatacora_flutter/features/parametres/data/parametres_depot_local.dart';
import 'package:tatacora_flutter/features/parametres/domain/enregistrer_parametres.dart';
import 'package:tatacora_flutter/features/parametres/domain/resultats_parametres.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/bilan_synchronisation.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/cause_envoi.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';

import '../synchronisation/support/faux_transport.dart';

/// Les réglages de la facturation normalisée, la forme juridique et les documents,
/// MODIFIABLES SUR LE POSTE par l'administrateur (09/11/2026, décision du PO : « le poste
/// fait ce que le web fait, plus la synchronisation ») : l'écriture passe par l'écrivain
/// unique des paramètres, est ENFILÉE dans la même transaction (jamais de réseau, hors
/// ligne comme en ligne), redescend aux autres postes, et ne déclenche JAMAIS une
/// normalisation. Le JETON e-MECeF reste exclu de toute charge. Le jugement contre le vrai
/// serveur est dans `reglages_facturation_contre_serveur_test.dart`.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late EnregistrerParametres cas;

  const ifu = '0202011344660';
  const complet = {
    'entreprise_ifu': ifu,
    'mecef_operateur_id': 'RECEPTION01',
    'mecef_operateur_nom': 'Réception',
  };

  setUp(() async {
    db = AppDatabase.enMemoire();
    await db
        .into(db.utilisateursLocal)
        .insert(
          UtilisateursLocalCompanion.insert(
            id: 'u-admin',
            login: 'admin',
            nom: 'Admin',
            role: 'administrateur',
            droitsJson: '{}',
            sel: 's',
            empreinte: 'e',
            iterations: 1,
            dateCreation: DateTime(2026, 11, 9),
            dateMotDePasse: DateTime(2026, 11, 9),
          ),
        );
    cas = EnregistrerParametres(
      ParametresDepotLocal(db),
      affectationActive: () async => false,
    );
  });

  tearDown(() => db.close());

  Future<ResultatEcriture> ecrire(
    Map<String, Object?> valeurs, {
    bool admin = true,
  }) => cas.executer(
    valeurs,
    peutEcrire: true,
    auteurId: 'u-admin',
    estAdministrateur: admin,
  );

  Future<List<Map<String, Object?>>> charges() async => [
    for (final o in await (db.select(
      db.operationsSyncLocal,
    )..orderBy([(o) => OrderingTerm.asc(o.seq)])).get())
      jsonDecode(o.payload) as Map<String, Object?>,
  ];

  test(
    'un administrateur écrit le mode, l’adresse, l’opérateur et la forme : '
    'chaque lot est ENFILÉ dans la même transaction, clés modifiées seules',
    () async {
      expect(await ecrire({...complet}), isA<EcritureAcceptee>());
      expect(
        await ecrire({
          'mecef_api_url': 'https://sygmef.exemple.bj/api',
          'facturation_mode': 'boitier',
          'forme_juridique': 'sarl',
        }),
        isA<EcritureAcceptee>(),
      );

      final valeurs = await ParametresDao(db).lireTout();
      expect(valeurs['facturation_mode'], 'boitier');
      expect(valeurs['mecef_api_url'], 'https://sygmef.exemple.bj/api');
      expect(valeurs['mecef_operateur_nom'], 'Réception');
      expect(valeurs['forme_juridique'], 'sarl');

      expect(await charges(), [
        {'valeurs': complet},
        {
          'valeurs': {
            'mecef_api_url': 'https://sygmef.exemple.bj/api',
            'facturation_mode': 'boitier',
            'forme_juridique': 'sarl',
          },
        },
      ]);

      // Rien de modifié : rien ne part.
      await ecrire({'facturation_mode': 'boitier'});
      expect(await charges(), hasLength(2));
    },
  );

  test(
    'un refus n’écrit RIEN et n’enfile RIEN (droit, forme, cohérence)',
    () async {
      for (final soumis in <Map<String, Object?>>[
        {'facturation_mode': 'boitier'}, // IFU et opérateur absents
        {'mecef_api_url': 'http://pas-https.exemple.bj'},
        {'mecef_operateur_nom': 'x' * 31},
        {'forme_juridique': 'gie'},
      ]) {
        expect(await ecrire(soumis), isA<EcritureRefusee>(), reason: '$soumis');
      }
      final r = await ecrire({'facturation_mode': 'desactive'}, admin: false);
      expect(
        (r as EcritureRefusee).motif,
        'Le mode de facturation normalisée et ses réglages sont réservés aux '
        'Administrateurs.',
      );
      expect(await ParametresDao(db).lireTout(), isEmpty);
      expect(await charges(), isEmpty);
    },
  );

  test('jamais de normalisation automatique : passer en « Boîtier CC300 » ou '
      '« e-MECeF » n’enfile que le paramètre', () async {
    await ecrire({...complet});
    for (final mode in const ['boitier', 'emecef']) {
      await ecrire({'facturation_mode': mode});
    }
    final tables = {
      for (final o in await db.select(db.operationsSyncLocal).get())
        o.tableServeur,
    };
    expect(tables, {
      'parametres_systeme',
    }, reason: 'aucune facture, aucun avoir');
    expect(await db.select(db.piecesFacturationLocal).get(), isEmpty);
  });

  test('HORS LIGNE : l’écriture ne fait AUCUNE requête réseau (aucun client '
      'HTTP n’est même créé)', () async {
    final surveille = _InterdireReseau();
    await HttpOverrides.runWithHttpOverrides(() async {
      expect(
        await ecrire({...complet, 'facturation_mode': 'boitier'}),
        isA<EcritureAcceptee>(),
      );
    }, surveille);
    expect(surveille.clientsCrees, 0, reason: 'zéro requête');
    expect(await charges(), hasLength(1));
  });

  test('Synchronisation DÉSACTIVÉE : zéro requête, la file attend, la valeur '
      'reste modifiée', () async {
    final b = await BancSync.creer();
    addTearDown(b.fermer);
    await b.ecrivain.enregistrerSynchronisationActivee(
      false,
      par: 'admin',
      le: DateTime(2026, 11, 9),
    );
    final ecrivain = EnregistrerParametres(
      ParametresDepotLocal(b.db),
      affectationActive: () async => false,
    );
    await b.db
        .into(b.db.utilisateursLocal)
        .insert(
          UtilisateursLocalCompanion.insert(
            id: 'u-admin',
            login: 'admin',
            nom: 'Admin',
            role: 'administrateur',
            droitsJson: '{}',
            sel: 's',
            empreinte: 'e',
            iterations: 1,
            dateCreation: DateTime(2026, 11, 9),
            dateMotDePasse: DateTime(2026, 11, 9),
          ),
        );
    expect(
      await ecrivain.executer(
        {...complet, 'facturation_mode': 'boitier'},
        peutEcrire: true,
        auteurId: 'u-admin',
        estAdministrateur: true,
      ),
      isA<EcritureAcceptee>(),
    );

    final interdit = FauxTransport(
      (r) => throw StateError('RÉSEAU : ${r.url}'),
    );
    final bilan = await b.manager(interdit).synchroniserMaintenant();
    expect(bilan.etat, EtatSynchronisation.desactivee);
    expect(interdit.requetes, isEmpty, reason: 'AUCUNE requête réseau');
    expect(
      {for (final o in await b.dao.operations()) o.statut},
      {StatutOperationSync.enAttente},
    );
    expect(
      (await ParametresDao(b.db).lireTout())['facturation_mode'],
      'boitier',
    );
  });

  test('envoyé : l’opération part en `parametres_systeme`, sans jeton ni '
      'secret ; refusée `droit_manquant`, la cause est LISIBLE et la valeur '
      'reste modifiée ici', () async {
    final b = await BancSync.creer();
    addTearDown(b.fermer);
    await b.db
        .into(b.db.utilisateursLocal)
        .insert(
          UtilisateursLocalCompanion.insert(
            id: 'u-admin',
            login: 'admin',
            nom: 'Admin',
            role: 'administrateur',
            droitsJson: '{}',
            sel: 's',
            empreinte: 'e',
            iterations: 1,
            dateCreation: DateTime(2026, 11, 9),
            dateMotDePasse: DateTime(2026, 11, 9),
          ),
        );
    await EnregistrerParametres(
      ParametresDepotLocal(b.db),
      affectationActive: () async => false,
    ).executer(
      {...complet, 'facturation_mode': 'boitier'},
      peutEcrire: true,
      auteurId: 'u-admin',
      estAdministrateur: true,
    );

    const phrase =
        'Le mode de facturation normalisée et ses réglages sont réservés aux '
        'Administrateurs.';
    final serveur = FauxTransport(
      (r) => r.url.path.endsWith('/sync')
          ? reponseLot(
              r,
              particulier: (o) => {
                'uuid_operation': o['uuid_operation'],
                'statut': 'rejete',
                'entite_id': o['entite_id'],
                'motif': phrase,
                'code_motif': 'droit_manquant',
              },
            )
          : FauxCatalogue(const []).repondre(r),
    );
    await b.manager(serveur).synchroniserMaintenant();

    // Ce qui est PARTI : la table des paramètres, les valeurs, rien d'autre.
    final envoyees = serveur.lots.expand((l) => l.operations).toList();
    expect(envoyees, hasLength(1));
    expect(envoyees.single['table'], 'parametres_systeme');
    final corps = jsonEncode(envoyees);
    expect(corps, contains('facturation_mode'));
    expect(corps.toLowerCase(), isNot(contains('jeton')));
    expect(corps, isNot(contains('mecef_jeton_api')));
    expect(corps, isNot(contains('secret')));

    final rejetee = (await b.dao.operations()).single;
    expect(rejetee.statut, StatutOperationSync.rejete);
    expect(rejetee.derniereErreur, phrase);
    expect(causeDe(rejetee, motif: phrase).titre, 'Droit manquant');
    // La valeur reste modifiée localement : le poste fonctionne sans le serveur.
    expect(
      (await ParametresDao(b.db).lireTout())['facturation_mode'],
      'boitier',
    );
  });

  test('la descente RETOUR : la valeur du serveur arrive aux autres postes, '
      'sans rien renvoyer', () async {
    final b = await BancSync.creer();
    addTearDown(b.fermer);
    final serveur = FauxTransport(
      (r) => FauxCatalogue([
        for (final e in const {
          'facturation_mode': 'boitier',
          'mecef_api_url': 'https://sygmef.exemple.bj/api',
          'mecef_operateur_id': 'RECEPTION01',
          'mecef_operateur_nom': 'Réception',
          'forme_juridique': 'sarl',
          'entreprise_activites': 'Tourisme',
        }.entries)
          element('parametres_systeme', 'p-${e.key}', {
            'cle': e.key,
            'valeur': e.value,
          }),
      ]).repondre(r),
    );
    await b
        .descente(serveur)
        .descendre((await b.lecteur.appairage())!, surRefus: (_) async {});

    final valeurs = await ParametresDao(b.db).lireTout();
    expect(valeurs['facturation_mode'], 'boitier');
    expect(valeurs['forme_juridique'], 'sarl');
    expect(valeurs['mecef_operateur_nom'], 'Réception');
    expect(valeurs['entreprise_activites'], 'Tourisme');
    expect(
      await b.dao.operations(),
      isEmpty,
      reason: 'la descente n’enfile JAMAIS',
    );
  });

  test('le JETON e-MECeF reste exclu : même un lot qui le nomme est refusé, '
      'jamais écrit, jamais enfilé', () async {
    for (final cle in const ['mecef_jeton_api', 'mecef_jeton', 'jeton_jwt']) {
      final r = await ecrire({cle: 'eyJhbGciOiJIUzI1NiJ9.x.y'});
      expect(r, isA<EcritureRefusee>(), reason: cle);
    }
    expect(await ParametresDao(db).lireTout(), isEmpty);
    expect(await charges(), isEmpty);
  });
}

/// Un [HttpOverrides] qui COMPTE les clients HTTP créés : zéro = aucune requête.
final class _InterdireReseau extends HttpOverrides {
  int clientsCrees = 0;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    clientsCrees++;
    throw StateError('RÉSEAU interdit');
  }
}
