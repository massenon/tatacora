import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../../core/fichiers/zip_stocke.dart';
import '../../../core/impression/entete_etablissement.dart';
import '../domain/cloture_exercice.dart';
import '../domain/etats_financiers.dart';
import '../domain/messages_cloture.dart';
import '../domain/montant_comptable.dart';
import '../domain/refus_comptable.dart';
import '../impression/etat_cloture_archive.dart';
import 'cloture_exercice_locale.dart';
import 'comptabilite_dao.dart';

/// L'ARCHIVE LÉGALE d'un exercice clôturé sur le poste — réplique de
/// `ArchiveClotureService` du serveur (26/10/2026, « export du fichier des
/// écritures et PDF des états de clôture avec empreinte d'intégrité », format
/// SYSCOHADA révisé / DGI Bénin).
///
/// Une archive par clôture, dans le sous-dossier `exercices/AAAA/ID` du dossier
/// des archives du poste (ID : l'identifiant de la clôture) :
///
///  - `ecritures.csv` : le fichier des écritures de l'exercice, une ligne par
///    ligne d'écriture, journal de clôture et contre-passations compris, aux
///    COLONNES du serveur ; UTF-8 avec BOM, séparateur `;`, dates AAAAMMJJ,
///    montants à virgule, guillemets comme `fputcsv` de PHP ;
///  - `balance.csv` : la balance générale de clôture (avant solde des comptes de
///    gestion, journal CL exclu) ;
///  - `etats-cloture.pdf` : la clôture, la balance, le compte de résultat, le
///    bilan et les visas ([EtatClotureArchive]) ;
///  - `manifeste.json` : l'empreinte SHA-256 et la taille de chaque fichier.
///
/// L'EMPREINTE de l'archive est le SHA-256 du manifeste : écrite sur la clôture
/// (`archive_empreinte`) et imprimée à l'écran. [verifier] relit les fichiers et
/// la confronte ; [zip] ne délivre qu'une archive INTACTE.
///
/// ## Immuable
///
/// On ne la régénère jamais ([archiver] rend celle qui existe). Une réouverture
/// suivie d'une nouvelle clôture crée une nouvelle clôture, donc une nouvelle
/// archive ; l'ancienne reste.
///
/// ## Écarts nommés
///
///  - Les fichiers vivent sur le DISQUE du poste, à côté de `poste.json`, et non
///    dans la base : la sauvegarde de la base (Import & Export) ne les contient
///    pas — à copier avec elle, comme le dossier `archives` du serveur.
///  - Les chiffres sont ceux des pièces de CE poste (voir
///    [ClotureExerciceLocale]) ; le manifeste le dit (`origine: poste`).
///  - Le format exact attendu par la DGI du Bénin reste à confirmer avec
///    l'expert-comptable, ici comme au serveur : les colonnes sont nommées une à
///    une ([colonnesEcritures]) pour qu'un ajustement ne touche qu'un endroit.
class ArchiveClotureLocale {
  ArchiveClotureLocale(
    this._dao,
    this._clotures,
    this._racine, {
    DateTime Function()? maintenant,
  }) : _maintenant = maintenant ?? DateTime.now;

  final ComptabiliteDao _dao;
  final ClotureExerciceLocale _clotures;

  /// Le dossier des archives du poste (créé au besoin).
  final Future<Directory> Function() _racine;
  final DateTime Function() _maintenant;

  static const String fichierEcritures = 'ecritures.csv';
  static const String fichierBalance = 'balance.csv';
  static const String fichierEtats = EtatClotureArchive.nomFichier;
  static const String fichierManifeste = 'manifeste.json';

  /// `ArchiveClotureService::COLONNES_ECRITURES`, au mot.
  static const colonnesEcritures = [
    'JournalCode',
    'JournalLib',
    'EcritureNum',
    'EcritureDate',
    'CompteNum',
    'CompteLib',
    'CentreCout',
    'EcritureLib',
    'Debit',
    'Credit',
    'Statut',
    'EcritureContrepassee',
    'DateSaisie',
    'SaisiPar',
  ];

  /// `ArchiveClotureService::COLONNES_BALANCE`, au mot.
  static const colonnesBalance = [
    'CompteNum',
    'CompteLib',
    'Classe',
    'TotalDebit',
    'TotalCredit',
    'SoldeDebiteur',
    'SoldeCrediteur',
  ];

  /// Le dossier d'une clôture, relatif au dossier des archives.
  static String dossierDe(int annee, String clotureId) =>
      'exercices/$annee/$clotureId';

  /// Écrit l'archive de la clôture [clotureId], ou rend celle qui existe déjà.
  Future<ClotureExercice> archiver(
    String clotureId, {
    required EnteteEtablissement entete,
  }) async {
    final cloture = await _cloture(clotureId);
    if (cloture.archiveEmpreinte != null) return cloture;
    if (!cloture.estActive) {
      throw RefusComptable(
        MotifRefus.archiveClotureRouverte,
        MessagesCloture.dire('comptabilite.archive_cloture_rouverte'),
      );
    }
    final exercice = (await _dao.exercice(cloture.exerciceId))!;
    final donnees = await _clotures.donneesDesEtats();
    final balance = balanceDe(exercice.annee, donnees);
    final etatsPdf = await EtatClotureArchive(
      exercice: exercice,
      cloture: cloture,
      balance: balance,
      compteResultat: compteResultatDe(exercice.annee, donnees),
      bilan: bilanDe(exercice.annee, donnees),
    ).etatA4().pdf(entete: entete, edition: _maintenant());

    final contenus = <String, List<int>>{
      fichierEcritures: utf8.encode(
        csvEcritures(await _dao.lignesPourArchive(exercice.id)),
      ),
      fichierBalance: utf8.encode(csvBalance(balance)),
      fichierEtats: etatsPdf,
    };

    final relatif = dossierDe(exercice.annee, cloture.id);
    final dossier = Directory(p.join((await _racine()).path, relatif));
    await dossier.create(recursive: true);
    final fichiers = <String, Map<String, Object>>{};
    for (final MapEntry(key: nom, value: octets) in contenus.entries) {
      await File(p.join(dossier.path, nom)).writeAsBytes(octets, flush: true);
      fichiers[nom] = {
        'sha256': sha256.convert(octets).toString(),
        'octets': octets.length,
      };
    }

    final manifeste = utf8.encode(
      const JsonEncoder.withIndent('    ').convert({
        'etablissement': entete.raisonSociale,
        'exercice': exercice.annee,
        'periode': [exercice.dateDebut, exercice.dateFin],
        'referentiel': 'SYSCOHADA révisé',
        'origine': 'poste',
        'cloture': {
          'id': cloture.id,
          'le': _atom(cloture.clotureeLe),
          'piece_cloture': cloture.pieceCloture,
          'piece_a_nouveaux': cloture.pieceANouveaux,
          'resultat': chaineDepuisCentimes(cloture.resultatCentimes),
        },
        'genere_le': _atom(_maintenant()),
        'algorithme': 'sha256',
        'fichiers': fichiers,
      }),
    );
    await File(
      p.join(dossier.path, fichierManifeste),
    ).writeAsBytes(manifeste, flush: true);

    await _clotures.consignerArchive(
      cloture.id,
      chemin: relatif,
      empreinte: sha256.convert(manifeste).toString(),
    );
    return _cloture(cloture.id);
  }

  /// L'archive est-elle intacte ? Le manifeste rend l'empreinte enregistrée, et
  /// chaque fichier celle que le manifeste a notée.
  Future<bool> verifier(ClotureExercice cloture) async {
    final chemin = cloture.archiveChemin;
    if (cloture.archiveEmpreinte == null || chemin == null) return false;
    final dossier = Directory(p.join((await _racine()).path, chemin));
    final fManifeste = File(p.join(dossier.path, fichierManifeste));
    if (!fManifeste.existsSync()) return false;
    final manifeste = await fManifeste.readAsBytes();
    if (sha256.convert(manifeste).toString() != cloture.archiveEmpreinte) {
      return false;
    }
    final lu = jsonDecode(utf8.decode(manifeste));
    final fichiers = lu is Map ? lu['fichiers'] : null;
    if (fichiers is! Map || fichiers.isEmpty) return false;
    for (final MapEntry(key: nom, value: note) in fichiers.entries) {
      final f = File(p.join(dossier.path, '$nom'));
      if (!f.existsSync() || note is! Map) return false;
      if (sha256.convert(await f.readAsBytes()).toString() != note['sha256']) {
        return false;
      }
    }
    return true;
  }

  /// L'archive en UN fichier ZIP (le téléchargement de l'onglet Clôtures) — les
  /// fichiers de son dossier, vérifiés d'abord : une archive altérée n'est pas
  /// délivrée.
  Future<Uint8List> zip(ClotureExercice cloture) async {
    if (!await verifier(cloture)) {
      throw RefusComptable(
        MotifRefus.archiveAlteree,
        MessagesCloture.dire('comptabilite.archive_alteree'),
      );
    }
    final dossier = Directory(
      p.join((await _racine()).path, cloture.archiveChemin!),
    );
    final noms =
        dossier
            .listSync()
            .whereType<File>()
            .map((f) => p.basename(f.path))
            .toList()
          ..sort();
    return zipStocke({
      for (final nom in noms)
        nom: await File(p.join(dossier.path, nom)).readAsBytes(),
    }, le: _maintenant());
  }

  /* ================================================================== */
  /* Les deux fichiers CSV                                               */
  /* ================================================================== */

  /// Le fichier des écritures — `ArchiveClotureService::fichierEcritures`.
  static String csvEcritures(List<LigneDArchive> lignes) => ecrireCsv([
    colonnesEcritures,
    for (final l in lignes)
      [
        l.codeJournal,
        l.libelleJournal,
        l.numeroPiece ?? '',
        l.dateEcriture.replaceAll('-', ''),
        l.numeroCompte,
        l.libelleCompte,
        l.libelleCentre,
        l.libelle,
        _montant(l.debitCentimes),
        _montant(l.creditCentimes),
        l.statut,
        l.pieceContrepassee ?? '',
        _jourCompact(l.saisieLe),
        l.saisiePar ?? '',
      ],
  ]);

  /// La balance générale de clôture — `ArchiveClotureService::fichierBalance`.
  static String csvBalance(BalanceEtat balance) => ecrireCsv([
    colonnesBalance,
    for (final l in balance.lignes)
      [
        l.numeroCompte,
        l.libelle,
        l.classe,
        _montant(l.debitCentimes),
        _montant(l.creditCentimes),
        _montant(
          l.debitCentimes > l.creditCentimes
              ? l.debitCentimes - l.creditCentimes
              : 0,
        ),
        _montant(
          l.creditCentimes > l.debitCentimes
              ? l.creditCentimes - l.debitCentimes
              : 0,
        ),
      ],
  ]);

  /// `fputcsv($flux, $ligne, ';', '"', '')` de PHP, derrière un BOM UTF-8 : un
  /// champ est entouré de guillemets s'il contient le séparateur, un guillemet,
  /// un saut de ligne, un retour chariot, une tabulation OU UNE ESPACE (c'est la
  /// règle de PHP) ; les guillemets s'y doublent ; chaque ligne finit par `\n`.
  static String ecrireCsv(List<List<String>> lignes) {
    final b = StringBuffer('﻿');
    for (final ligne in lignes) {
      b
        ..writeAll(ligne.map(_champ), ';')
        ..write('\n');
    }
    return b.toString();
  }

  static String _champ(String v) {
    final aProteger =
        v.contains(';') ||
        v.contains('"') ||
        v.contains('\n') ||
        v.contains('\r') ||
        v.contains('\t') ||
        v.contains(' ');
    return aProteger ? '"${v.replaceAll('"', '""')}"' : v;
  }

  /// `str_replace('.', ',', bcadd($v, '0', 2))`.
  static String _montant(int centimes) =>
      chaineDepuisCentimes(centimes).replaceAll('.', ',');

  static String _jourCompact(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}'
      '${d.month.toString().padLeft(2, '0')}'
      '${d.day.toString().padLeft(2, '0')}';

  /// `DATE_ATOM` (`2026-12-31T10:00:00+01:00`) — l'instant en heure LOCALE, avec
  /// son décalage.
  static String _atom(DateTime d) {
    final l = d.toLocal();
    String deux(int n) => n.toString().padLeft(2, '0');
    final decalage = l.timeZoneOffset;
    final signe = decalage.isNegative ? '-' : '+';
    final h = decalage.inMinutes.abs() ~/ 60;
    final m = decalage.inMinutes.abs() % 60;
    return '${l.year.toString().padLeft(4, '0')}-${deux(l.month)}-${deux(l.day)}'
        'T${deux(l.hour)}:${deux(l.minute)}:${deux(l.second)}'
        '$signe${deux(h)}:${deux(m)}';
  }

  Future<ClotureExercice> _cloture(String id) async {
    final c = (await _clotures.clotures()).where((c) => c.id == id).firstOrNull;
    if (c == null) {
      throw RefusComptable(
        MotifRefus.archiveSansCloture,
        MessagesCloture.dire('comptabilite.archive_sans_cloture'),
      );
    }
    return c;
  }
}
