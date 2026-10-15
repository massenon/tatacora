import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/fichiers/lecture_csv.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/features/stocks/domain/import_articles.dart';
import 'package:tatacora_flutter/features/transverse/data/importeurs_locaux.dart';
import 'package:tatacora_flutter/features/transverse/data/sauvegarde_locale.dart';
import 'package:tatacora_flutter/features/transverse/domain/import_referentiels.dart';
import 'package:tatacora_flutter/features/transverse/presentation/providers_import_export.dart';

import 'support/outils_import.dart';

/// Les huit IMPORTEURS du poste (demande du PO du 14/10/2026), par le câblage
/// de PRODUCTION (`importeursLocauxProvider`, `moteurImportProvider`) sur une
/// vraie base en mémoire : chaque ligne passe par le DAO propriétaire du
/// module, et ces cas relisent la TABLE en SQL brut (piège 5).
///
/// Règle de l'écran : AUCUN import partiel — une ligne refusée, et rien
/// n'entre en base ; le contrôle (« Valider et contrôler ») SIMULE l'écriture
/// et l'annule.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late ProviderContainer conteneur;
  late MoteurImportLocal moteur;

  setUp(() async {
    db = await baseImport();
    conteneur = conteneurImport(db);
    moteur = conteneur.read(moteurImportProvider);
  });
  tearDown(() async {
    conteneur.dispose();
    await db.close();
  });

  ImporteurLocal importeur(String cle) =>
      conteneur.read(importeursLocauxProvider).singleWhere((i) => i.cle == cle);

  List<int> octets(String texte) => utf8.encode(texte);

  test('les huit modules du registre du serveur, dans son ordre, chacun '
      'sous le droit de SON module', () {
    final importeurs = conteneur.read(importeursLocauxProvider);
    expect(
      [for (final i in importeurs) i.cle],
      [for (final c in casImport) c.cle],
    );
    expect(
      [for (final i in importeurs) i.module.code],
      [for (final c in casImport) c.code],
    );
    expect(
      [for (final i in importeurs) i.nom],
      [for (final c in casImport) c.nom],
    );
  });

  for (final cas in casImport) {
    group('${cas.code} ${cas.nom}', () {
      test('un CSV valide (point-virgule) importe ses ${cas.valides.length} '
          'lignes par le DAO du module', () async {
        final avant = await compterLignes(db, cas.table);
        final issue = await moteur.appliquer(
          importeur(cas.cle),
          octets(cas.fichier(cas.valides)),
        );
        expect(issue, isA<ImportFait>(), reason: '$issue');
        final fait = issue as ImportFait;
        expect((fait.importees, fait.ignorees), (cas.valides.length, 0));
        expect(await compterLignes(db, cas.table), avant + cas.valides.length);
        expect(
          await valeursDe(db, cas.table, cas.colonne),
          containsAll(cas.cles),
        );
      });

      test('le séparateur VIRGULE est reconnu à l’en-tête', () async {
        final contenu = cas.fichier(cas.valides, separateur: ',');
        expect(separateurDe(contenu), ',');
        final issue = await moteur.appliquer(
          importeur(cas.cle),
          octets(contenu),
        );
        expect(issue, isA<ImportFait>(), reason: '$issue');
        expect(
          await valeursDe(db, cas.table, cas.colonne),
          containsAll(cas.cles),
        );
      });

      test(
        'le BOM UTF-8 d’Excel est retiré : l’en-tête reste reconnue',
        () async {
          // Par les OCTETS (le chemin de l'écran) : `utf8.decode` retire déjà
          // le BOM de tête…
          final issue = await moteur.appliquer(
            importeur(cas.cle),
            octets(cas.fichier(cas.valides, bom: true)),
          );
          expect(issue, isA<ImportFait>(), reason: '$issue');
          expect(
            await valeursDe(db, cas.table, cas.colonne),
            containsAll(cas.cles),
          );

          // … par le TEXTE qui le porte encore : le lecteur CSV le retire (et
          // `normaliserImport` le rogne aussi : `String.trim` de Dart ôte
          // U+FEFF). La garde du lecteur LUI-MÊME est éprouvée plus bas
          // (`lireCsv`), seule à voir son retrait.
          final i = importeur(cas.cle);
          final texte = cas.fichier(cas.valides, bom: true);
          expect(texte.codeUnitAt(0), 0xFEFF);
          final rapport = controlerImport(
            colonnes: i.colonnes,
            identifiant: i.identifiant,
            tableau: analyserCsvImport(texte),
            existants: const {},
            references: await i.references(),
          );
          expect(
            rapport.ok,
            isTrue,
            reason: '${rapport.erreurs.map((e) => e.message)}',
          );
          expect(rapport.avertissements, isEmpty);
          expect(rapport.lignes, hasLength(cas.valides.length));
        },
      );

      test('une ligne fautive est DITE avec son numéro de ligne Excel, et le '
          'fichier n’écrit RIEN — pas même ses lignes valides', () async {
        final avant = await compterLignes(db, cas.table);
        final contenu = cas.fichier([
          cas.valides[0],
          cas.fautive,
          cas.valides[1],
        ]);
        final rapport = await moteur.controler(
          importeur(cas.cle),
          octets(contenu),
        );
        expect(rapport.ok, isFalse);
        expect(rapport.lignes, isEmpty, reason: 'aucun import partiel');
        expect((rapport.total, rapport.enErreur, rapport.valides), (3, 1, 2));
        final erreur = rapport.erreurs.single;
        expect(erreur.ligne, 3, reason: 'l’en-tête est la ligne 1');
        expect(erreur.colonne, cas.colonneFautive);
        expect(erreur.message, startsWith(cas.debutMessageFautif));

        final issue = await moteur.appliquer(
          importeur(cas.cle),
          octets(contenu),
        );
        expect(issue, isA<ImportNonConforme>());
        expect(await compterLignes(db, cas.table), avant);
        expect(
          await valeursDe(db, cas.table, cas.colonne),
          isNot(contains(cas.cles.first)),
        );
      });

      test('un doublon DÉJÀ EN BASE est ignoré et dit en avertissement ; la '
          'ligne neuve entre seule', () async {
        await moteur.appliquer(
          importeur(cas.cle),
          octets(cas.fichier([cas.valides[0]])),
        );
        final avant = await compterLignes(db, cas.table);

        final contenu = cas.fichier(cas.valides);
        final rapport = await moteur.controler(
          importeur(cas.cle),
          octets(contenu),
        );
        expect(rapport.ok, isTrue);
        expect(rapport.ignorees, 1);
        final avert = rapport.avertissements.single;
        expect(avert.ligne, 2);
        expect(
          avert.message,
          TextesControleImport.doublonExistantIgnore(cas.cles.first),
        );

        final issue = await moteur.appliquer(
          importeur(cas.cle),
          octets(contenu),
        );
        expect(issue, isA<ImportFait>(), reason: '$issue');
        final fait = issue as ImportFait;
        expect((fait.importees, fait.ignorees), (1, 1));
        expect(await compterLignes(db, cas.table), avant + 1);
      });

      test('un doublon DANS le fichier est une ERREUR (ligne de la seconde '
          'occurrence) ; rien n’est écrit', () async {
        final avant = await compterLignes(db, cas.table);
        final contenu = cas.fichier([
          cas.valides[0],
          cas.valides[1],
          cas.valides[0],
        ]);
        final rapport = await moteur.controler(
          importeur(cas.cle),
          octets(contenu),
        );
        expect(rapport.ok, isFalse);
        final erreur = rapport.erreurs.single;
        expect(erreur.ligne, 4);
        expect(
          erreur.message,
          TextesControleImport.doublonFichier(cas.cles.first),
        );
        expect(
          await moteur.appliquer(importeur(cas.cle), octets(contenu)),
          isA<ImportNonConforme>(),
        );
        expect(await compterLignes(db, cas.table), avant);
      });

      test('« Valider et contrôler » SIMULE : rapport conforme, et rien '
          'n’est écrit', () async {
        final avant = await compterLignes(db, cas.table);
        final rapport = await moteur.controler(
          importeur(cas.cle),
          octets(cas.fichier(cas.valides)),
        );
        expect(
          rapport.ok,
          isTrue,
          reason: '${rapport.erreurs.map((e) => e.message)}',
        );
        expect(rapport.lignes, hasLength(cas.valides.length));
        expect(await compterLignes(db, cas.table), avant);
      });

      test('le modèle : BOM, l’en-tête attendu au point-virgule, AUCUNE ligne '
          'de données — et rempli, il passe le contrôle', () async {
        final i = importeur(cas.cle);
        final modele = i.modeleOctets();
        expect(modele.sublist(0, 3), [0xEF, 0xBB, 0xBF], reason: 'BOM UTF-8');
        expect(utf8.decode(modele.sublist(3)), '${cas.entete}\r\n');
        final rempli = [
          ...i.modeleOctets(),
          ...utf8.encode('${cas.valides.first}\r\n'),
        ];
        final rapport = await moteur.controler(i, rempli);
        expect(rapport.ok, isTrue);
        expect(
          rapport.avertissements,
          isEmpty,
          reason: 'aucune colonne inconnue',
        );
        expect(rapport.lignes, hasLength(1));
      });
    });
  }

  test('M6 : le modèle est celui de l’écran Stocks (moteur PARTAGÉ)', () {
    final i = importeur('m6-stocks');
    expect(i.nomModele, TextesImportArticles.nomModele);
    expect(i.modeleOctets(), modeleImportArticlesOctets());
    expect([for (final c in i.colonnes) c.champ], colonnesImportArticles);
  });

  test('un refus d’un module PENDANT l’écriture réelle annule TOUT le lot '
      '(une transaction), ses lignes déjà écrites comprises', () async {
    // Un importeur dont l'écriture RÉELLE (la seconde passe : la première est
    // la simulation) refuse la deuxième ligne — la base a bougé entre le
    // contrôle et l'import.
    final clients = importeur('m3-clients');
    final capricieux = _ImporteurCapricieux(db, clients);
    final avant = await compterLignes(db, 'clients_local');
    final cas = casImport.first;

    final issue = await moteur.appliquer(
      capricieux,
      octets(cas.fichier(cas.valides)),
    );
    expect(issue, isA<ImportAnnule>(), reason: '$issue');
    expect(
      (issue as ImportAnnule).message,
      TextesControleImport.refusService(3, 'KORA', 'refus de l’essai'),
    );
    expect(capricieux.ecrites, 1, reason: 'la ligne 2 avait été écrite');
    expect(
      await compterLignes(db, 'clients_local'),
      avant,
      reason: 'et elle est annulée avec le lot',
    );
  });

  test('un refus d’un DAO à la SIMULATION figure au rapport, et rien n’est '
      'écrit', () async {
    // Le DAO a son mot à dire après le contrôle du fichier (comme le service
    // de domaine au serveur) : un importeur qui lève pour la ligne 3 dès la
    // simulation.
    final cas = casImport.first;
    final refuse = _ImporteurCapricieux(db, importeur(cas.cle), passe: 1);
    final avant = await compterLignes(db, cas.table);
    final rapport = await moteur.controler(
      refuse,
      octets(cas.fichier(cas.valides)),
    );
    expect(rapport.ok, isFalse);
    expect(rapport.erreurs.single.ligne, 3);
    expect(
      rapport.erreurs.single.message,
      TextesControleImport.refusModule('refus de l’essai'),
    );
    expect(await compterLignes(db, cas.table), avant);
  });

  group('lireCsv / separateurDe — le lecteur UNIQUE des imports', () {
    test(
      'guillemets, guillemet doublé, séparateur et saut de ligne protégés',
      () {
        expect(lireCsv('a;"b;c";"d ""e""";"f\ng"\r\nh;i'), [
          ['a', 'b;c', 'd "e"', 'f\ng'],
          ['h', 'i'],
        ]);
      },
    );

    test('le BOM de tête est retiré ; une ligne blanche garde sa POSITION', () {
      expect(lireCsv('\u{FEFF}nom;prenom\n\nKORA;Jean'), [
        ['nom', 'prenom'],
        [''],
        ['KORA', 'Jean'],
      ]);
      expect(separateurDe('\u{FEFF}a,b;c,d\nx;y;z;t'), ',');
    });

    test('le séparateur se lit à la PREMIÈRE ligne ; à égalité, le '
        'point-virgule', () {
      expect(separateurDe('a;b;c\nx,y,z,t,u'), ';');
      expect(separateurDe('a,b,c\nx;y'), ',');
      expect(separateurDe('a;b,c'), ';');
      expect(separateurDe('seule'), ';');
    });
  });

  group('Sauvegarde de la base et export d’une table', () {
    test('« Générer une sauvegarde » : une VRAIE base SQLite, qui se rouvre '
        'et se relit ; le fichier temporaire est effacé', () async {
      await moteur.appliquer(
        importeur('m3-clients'),
        octets(casImport.first.fichier(casImport.first.valides)),
      );
      final temp = Directory.systemTemp;
      Set<String> dossiersSvg() => {
        for (final e in temp.listSync())
          if (e is Directory &&
              e.uri.pathSegments.reversed
                  .firstWhere((s) => s.isNotEmpty)
                  .startsWith('tatacora_svg_'))
            e.path,
      };
      final avant = dossiersSvg();

      final copie = await SauvegardeLocale(db).composer();
      expect(ascii.decode(copie.sublist(0, 15)), 'SQLite format 3');
      expect(
        dossiersSvg().difference(avant),
        isEmpty,
        reason: 'le dossier temporaire de VACUUM INTO est effacé',
      );

      final dossier = await temp.createTemp('tatacora_relu_');
      addTearDown(() => dossier.delete(recursive: true));
      final fichier = File('${dossier.path}/copie.sqlite')
        ..writeAsBytesSync(copie);
      final relue = sqlite3.open(fichier.path, mode: OpenMode.readOnly);
      addTearDown(relue.close);
      final noms = relue.select('SELECT nom FROM clients_local ORDER BY nom');
      expect([for (final r in noms) r['nom']], ['Agence Bénin Tour', 'KORA']);
      final version = relue.select('PRAGMA user_version').single.values.first;
      expect(version, db.schemaVersion);
      final comptes = relue.select('SELECT login FROM utilisateurs_local');
      expect(comptes.single['login'], 'import');
    });

    test('le nom proposé : tatacora_sauvegarde_AAAA-MM-JJ_HHhMM.sqlite', () {
      expect(
        SauvegardeLocale.nomSuggere(le: DateTime(2026, 3, 4, 7, 5)),
        'tatacora_sauvegarde_2026-03-04_07h05.sqlite',
      );
    });

    test('l’export JSON d’une table EXCLUT utilisateurs_local, et rend le '
        'contenu réel des autres', () async {
      final service = SauvegardeLocale(db);
      final tables = service.tablesExportables();
      expect(tables, isNot(contains('utilisateurs_local')));
      expect(tables, containsAll(['clients_local', 'articles_local']));
      expect(tables.length, db.allTables.length - 1);
      await expectLater(
        service.exporterTableJson('utilisateurs_local'),
        throwsArgumentError,
      );

      final json =
          jsonDecode(
                utf8.decode(
                  await service.exporterTableJson(
                    'articles_local',
                    le: DateTime(2026, 10, 15, 8),
                  ),
                ),
              )
              as Map<String, dynamic>;
      expect(json['table'], 'articles_local');
      expect(json['genere_le'], '2026-10-15T08:00:00.000');
      expect(json['nombre_lignes'], 2);
      expect(
        {
          for (final l in json['lignes'] as List<dynamic>)
            (l as Map)['libelle'],
        },
        {'Béninoise 66 cl', 'Poulet entier'},
      );
    });
  });
}

/// Délègue à un vrai importeur, mais REFUSE la ligne 3 à son appel numéro
/// [passe] : `appliquer` écrit chaque ligne deux fois — la SIMULATION du
/// contrôle (appel 1, transaction annulée), puis l'écriture RÉELLE (appel 2).
final class _ImporteurCapricieux extends ImporteurLocal {
  _ImporteurCapricieux(super.base, this._vrai, {this.passe = 2});

  final ImporteurLocal _vrai;

  /// L'appel (1 = simulation, 2 = écriture réelle) qui refuse la ligne 3.
  final int passe;
  final Map<int, int> _appels = {};

  /// Les lignes écrites par la passe RÉELLE avant le refus.
  int ecrites = 0;

  @override
  String get cle => _vrai.cle;
  @override
  ModuleTatacora get module => _vrai.module;
  @override
  String get nom => _vrai.nom;
  @override
  String get description => _vrai.description;
  @override
  String get identifiant => _vrai.identifiant;
  @override
  List<ColonneImport> get colonnes => _vrai.colonnes;
  @override
  Future<Set<String>> existants() => _vrai.existants();
  @override
  Future<Map<String, Map<String, String>>> references() => _vrai.references();
  @override
  Future<void> preparer() => _vrai.preparer();

  @override
  Future<String?> ecrire(LigneImport ligne) async {
    final appel = _appels[ligne.numero] = (_appels[ligne.numero] ?? 0) + 1;
    if (ligne.numero == 3 && appel == passe) {
      throw const RefusLigneImport('refus de l’essai');
    }
    final r = await _vrai.ecrire(ligne);
    if (appel == 2) ecrites++;
    return r;
  }
}
