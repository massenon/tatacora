import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/comptabilite/data/comptabilite_dao.dart';
import 'package:tatacora_flutter/features/comptabilite/data/installateur_referentiel.dart';
import 'package:tatacora_flutter/features/comptabilite/data/moteur_comptable.dart';

/// Le plan du PO tel que l'application l'EMBARQUE (le même fichier que lit
/// `rootBundle` en production).
String lirePlanEmbarque() => File(cheminAssetPlanComptable).readAsStringSync();

/// L'identifiant de l'auteur de toutes les pièces d'essai.
const auteurEssai = 'u-compta';

/// Un utilisateur pour la clé étrangère `cree_par` (RG-15).
Future<void> semerAuteur(AppDatabase db, {String id = auteurEssai}) async {
  await db
      .into(db.utilisateursLocal)
      .insert(
        UtilisateursLocalCompanion.insert(
          id: id,
          login: 'compta-$id',
          nom: 'Comptable $id',
          role: 'comptable',
          droitsJson: '{}',
          sel: 's',
          empreinte: 'e',
          iterations: 1,
          dateCreation: DateTime(2026, 10, 1),
          dateMotDePasse: DateTime(2026, 10, 1),
        ),
      );
}

/// Installe le référentiel par la vraie fonction, à la date [maintenant]
/// (l'exercice de cette année est semé).
Future<BilanInstallation> baseInstalleeSur(
  AppDatabase db,
  DateTime maintenant,
) => installerReferentielComptable(
  db,
  contenuPlan: lirePlanEmbarque(),
  maintenant: maintenant,
);

/// Une base EN MÉMOIRE portant le référentiel installé par la vraie fonction,
/// à la date [maintenant], et un auteur.
Future<AppDatabase> baseInstallee({DateTime? maintenant}) async {
  final db = AppDatabase.enMemoire();
  await db.customStatement('SELECT 1');
  await semerAuteur(db);
  await baseInstalleeSur(db, maintenant ?? DateTime(2031, 6, 15));
  return db;
}

MoteurComptable moteurSur(AppDatabase db, {DateTime Function()? maintenant}) =>
    MoteurComptable(
      ComptabiliteDao(db),
      maintenant: maintenant ?? () => DateTime(2031, 6, 15, 10),
    );

/// Exécute un script PHP de `tool/<dossier>/` (`comptabilite` par défaut) :
/// l'entrée JSON sur stdin, la sortie JSON sur stdout. PHP absent, `vendor/`
/// absent ou MySQL injoignable : le test ÉCHOUE, il ne saute pas.
///
/// ## Un interblocage MySQL entre deux scripts n'est pas un verdict
///
/// `flutter test` lance plusieurs fichiers en parallèle, et plusieurs scripts
/// rejouent leur scénario sur la MÊME base `tatacora_test` (chacun dans une
/// transaction qu'il annule). Deux d'entre eux peuvent se bloquer l'un l'autre
/// sur le verrou de séquence : MySQL en tue un (`DeadlockException`). C'est de
/// la contention d'infrastructure, pas un écart entre le poste et le serveur —
/// le script est donc rejoué (quatre fois au plus, avec un délai croissant). Tout
/// AUTRE échec reste un échec, immédiatement.
///
/// ## L'accès à `tatacora_test` est SÉRIALISÉ entre processus (R1, 12/10/2026)
///
/// Rejouer après coup ne suffit pas : un `setUpAll` PHP a échoué sur une
/// `QueryException` que le motif de nouvel essai ne reconnaissait pas
/// (contention MySQL entre deux scripts d'amorçage — verrou, interblocage ou
/// délai d'attente, dont la phrase varie selon que PHP l'écrit sur la sortie
/// standard ou d'erreur). Plutôt que d'allonger sans fin la liste des phrases,
/// la CAUSE est retirée : un verrou de fichier, partagé par tous les processus
/// `flutter_tester` de la machine, garantit qu'un seul script touche à la base
/// de test à la fois. Le motif de nouvel essai reste, élargi, pour la
/// contention venue d'ailleurs (un autre outil sur la même base).
///
/// Le verrou ne protège que contre les AUTRES TESTS : un script lancé à la main
/// pendant la suite ne le prend pas, d'où le maintien des nouveaux essais.
///
/// [racine] et [nomVerrou] n'existent que pour les essais de cette fonction
/// elle-même (`executer_php_contention_test.dart`, R-B, D283) : un script
/// FACTICE, hors de `tool/`, sous un verrou à lui — sans quoi l'essai
/// attendrait la file des vrais scripts. Tout autre appelant garde les défauts.
Future<Map<String, dynamic>> executerPhp(
  String script, {
  Map<String, dynamic>? entree,
  String dossier = 'comptabilite',
  String racine = 'tool',
  String nomVerrou = 'tatacora_test_php',
}) async {
  const tentativesMax = 4;
  for (var tentative = 1; ; tentative++) {
    final (code, texte, erreurs) = await sousVerrouBaseDeTest(
      nom: nomVerrou,
      () async {
        final php = await Process.start('php', ['$racine/$dossier/$script']);
        if (entree != null) php.stdin.write(jsonEncode(entree));
        await php.stdin.close();

        final sortie = utf8.decodeStream(php.stdout);
        final erreur = utf8.decodeStream(php.stderr);
        final c = await php.exitCode;
        return (c, await sortie, await erreur);
      },
    );

    if (estContentionMysql(texte, erreurs) && tentative < tentativesMax) {
      await Future<void>.delayed(Duration(milliseconds: 500 * tentative));
      continue;
    }

    if (code != 0) {
      // Les DEUX flux : PHP écrit une exception non rattrapée sur la sortie
      // standard ou sur la sortie d'erreur selon sa configuration, et ne
      // citer que la seconde a déjà rendu un échec muet.
      fail(
        'Le serveur n’a pas pu rejouer $script (php, code $code) '
        'après $tentative tentative(s).\n'
        'STDERR : ${_tronquer(erreurs)}\n'
        'STDOUT : ${_tronquer(texte)}\n'
        'C’est un ÉCHEC, pas un saut.',
      );
    }
    return jsonDecode(texte) as Map<String, dynamic>;
  }
}

/// Vrai si l'échec d'un script est de la CONTENTION sur la base de test, et
/// non un écart entre le poste et le serveur.
///
/// Reconnaît, sur l'un ou l'autre flux : l'exception rattrapée par un script
/// (`DeadlockException`), le texte MySQL brut (« Deadlock found », « Lock wait
/// timeout »), l'état SQL 40001 (échec de sérialisation), les codes 1213 et
/// 1205, et — nouveau — la `QueryException` qui les enveloppe. Une
/// `QueryException` SANS aucune de ces marques n'est PAS de la contention : une
/// requête fausse doit échouer tout de suite, pas être rejouée.
bool estContentionMysql(String sortie, String erreurs) {
  final tout = '$sortie\n$erreurs';
  const marques = [
    'DeadlockException',
    'Deadlock found',
    'Lock wait timeout',
    'SQLSTATE[40001]',
    'Serialization failure',
    'General error: 1205',
    'General error: 1213',
    'try restarting transaction',
  ];
  return marques.any(tout.contains);
}

String _tronquer(String texte) =>
    texte.length <= 2000 ? texte : '${texte.substring(0, 2000)} […]';

/// Exécute [travail] en tenant le verrou de fichier qui sérialise les scripts
/// PHP touchant `tatacora_test`, entre tous les processus de test.
///
/// Le verrou est pris avant le lancement de PHP et relâché après la fin du
/// script. S'il ne peut pas être pris (système de fichiers exotique), on
/// continue sans lui : les nouveaux essais restent le filet.
///
/// [nom] distingue le fichier de verrou : les essais du verrou lui-même en
/// prennent un à eux, sans quoi ils attendraient la file des vrais scripts PHP.
/// Toute attente de plus de 20 s est DITE sur la sortie du test : la file
/// allonge la suite, et un `@Timeout` de fichier qui la dépasserait doit se
/// voir avant d'échouer.
Future<T> sousVerrouBaseDeTest<T>(
  Future<T> Function() travail, {
  String nom = 'tatacora_test_php',
}) async {
  // File d'attente DANS le processus, avant le verrou de fichier : sous Linux
  // et macOS, `RandomAccessFile.lock` est un verrou POSIX (fcntl), attaché au
  // PROCESSUS — deux accès du même `flutter_tester` le prennent ensemble, là
  // où Windows (LockFileEx, par descripteur) les sérialise. Mesuré le
  // 15/10/2026 : trois accès simultanés d'un même test se chevauchaient.
  final precedent = _filesDuProcessus[nom] ?? Future<void>.value();
  final tour = Completer<void>();
  _filesDuProcessus[nom] = tour.future;
  await precedent;
  try {
    return await _sousVerrouDeFichier(travail, nom: nom);
  } finally {
    tour.complete();
  }
}

/// Le dernier accès en file, par nom de verrou (voir [sousVerrouBaseDeTest]).
final Map<String, Future<void>> _filesDuProcessus = {};

Future<T> _sousVerrouDeFichier<T>(
  Future<T> Function() travail, {
  required String nom,
}) async {
  RandomAccessFile? acces;
  try {
    final fichier = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}$nom.verrou',
    );
    acces = await fichier.open(mode: FileMode.append);
    final debut = DateTime.now();
    await acces.lock(FileLock.blockingExclusive);
    final attente = DateTime.now().difference(debut);
    if (attente > const Duration(seconds: 20)) {
      // ignore: avoid_print
      print(
        'VERROU tatacora_test : ${attente.inSeconds} s d’attente avant '
        'de rejouer un script PHP.',
      );
    }
  } on FileSystemException {
    await acces?.close();
    acces = null;
  }
  try {
    return await travail();
  } finally {
    if (acces != null) {
      try {
        await acces.unlock();
      } on FileSystemException {
        // Déjà relâché par la fermeture du descripteur.
      }
      await acces.close();
    }
  }
}

/// Un exercice de [annee] CLÔTURÉ — la façon de faire refuser une pièce
/// depuis le 20/10/2026 : l'exercice MANQUANT de l'année en cours s'ouvre
/// désormais de lui-même à sa première pièce (passage d'année).
Future<void> exerciceClos(AppDatabase db, int annee) async {
  final dao = ComptabiliteDao(db);
  final existant =
      await dao.exerciceDeLAnnee(annee) ??
      await dao.insererExercice(
        annee: annee,
        dateDebut: '$annee-01-01',
        dateFin: '$annee-12-31',
      );
  await dao.marquerCloture(
    existant.id,
    quand: DateTime(annee, 12, 31),
    auteurId: auteurEssai,
  );
}
