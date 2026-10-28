import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/descente_catalogue.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/journal_reception.dart';

/// La CAUSE d'un élément reçu, déduite de la phrase de l'aligneur : le
/// registre fermé, les phrases françaises, et — surtout — le balayage de
/// CHAQUE motif que `aligneur_catalogue.dart` et `aligneur_documents.dart`
/// savent produire (un motif nouveau, non reconnu, fait rougir cet essai
/// plutôt que de tomber en silence sur « règle du poste »).
void main() {
  /// Les motifs écrits dans les aligneurs : `(issue, motif)`, les
  /// interpolations (`${d['x']}`) remplacées par une valeur d'essai.
  List<(IssueReception, String)> motifsDesAligneurs() {
    final appel = RegExp(
      r'(RefuseParLePoste|EnAttenteDeDependance|ConserveLocalement)\(\s*'
      r"((?:'(?:\$\{[^}]*\}|\\.|[^'\\])*'\s*)+)",
    );
    final litteral = RegExp(r"'((?:\$\{[^}]*\}|\\.|[^'\\])*)'");
    final motifs = <(IssueReception, String)>[];
    for (final f in const [
      'aligneur_catalogue.dart',
      'aligneur_documents.dart',
    ]) {
      final code = File(
        'lib/features/synchronisation/data/$f',
      ).readAsStringSync();
      for (final m in appel.allMatches(code)) {
        final motif = litteral
            .allMatches(m.group(2)!)
            .map((l) => l.group(1)!)
            .join()
            .replaceAll(RegExp(r'\$\{[^}]*\}'), '7')
            .replaceAll(RegExp(r'\$\w+'), '7')
            .replaceAll(r"\'", "'");
        motifs.add((
          switch (m.group(1)) {
            'RefuseParLePoste' => IssueReception.refuse,
            'EnAttenteDeDependance' => IssueReception.enAttente,
            _ => IssueReception.conserve,
          },
          motif,
        ));
      }
    }
    return motifs;
  }

  test('le balayage trouve les motifs (plancher : il ne passe pas à vide)', () {
    final m = motifsDesAligneurs();
    expect(m.length, greaterThan(150));
    expect(
      m.where((e) => e.$1 == IssueReception.enAttente).length,
      greaterThan(30),
    );
    expect(
      m.where((e) => e.$1 == IssueReception.conserve).length,
      greaterThan(4),
    );
  });

  test('CHAQUE motif « en attente » a une cause : l’élément lié est nommé '
      '(ou plusieurs sont possibles, ou c’est le compte)', () {
    for (final (issue, motif) in motifsDesAligneurs()) {
      if (issue != IssueReception.enAttente) continue;
      final a = analyserMotif(issue, motif);
      if (motif.contains('compte local')) {
        expect(a.cause, CauseReception.sansCompteLocal, reason: motif);
        continue;
      }
      expect(a.cause, CauseReception.dependanceManquante, reason: motif);
      final ambigu = motif.contains(' ou ') || motif.contains(',');
      if (ambigu) {
        expect(a.dependance, isNull, reason: motif);
        expect(a.champ, isNotNull, reason: 'les noms possibles : $motif');
      } else {
        expect(
          a.dependance,
          isNotNull,
          reason: 'quelle dépendance manque ? $motif',
        );
        expect(
          TableDescendue.depuisNom(a.dependance!),
          isNotNull,
          reason: 'une table du serveur : $motif',
        );
      }
    }
  });

  test('CHAQUE motif « conservé » est un conflit avec une saisie locale', () {
    for (final (issue, motif) in motifsDesAligneurs()) {
      if (issue != IssueReception.conserve) continue;
      expect(
        analyserMotif(issue, motif).cause,
        anyOf(CauseReception.conflitLocal, CauseReception.homonymeLocal),
        reason: motif,
      );
    }
  });

  /// Les refus qui sont des règles propres du poste, nommés un à un : tout
  /// autre refus doit tomber dans une cause plus précise.
  const reglesNommees = [
    'la fin précède le début',
    'départ antérieur ou égal à l’arrivée',
    'pointée sur ce poste',
    'montant réclamé négatif',
    'pas sur les deux',
    'unité de mesure changée au serveur',
    'sans menu ou sans fiche technique',
    'sans réservation au serveur',
    'sans ligne retrouvée au serveur',
    // Purge définitive (A5) : règle propre du poste (le compte du plan
    // illisible (A12) se classe « donnée illisible »).
    'suppression non admise pour cette table',
  ];

  test('CHAQUE motif « refusé » a une cause précise — sauf les règles du '
      'poste NOMMÉES', () {
    final regles = <String>[];
    for (final (issue, motif) in motifsDesAligneurs()) {
      if (issue != IssueReception.refuse) continue;
      final a = analyserMotif(issue, motif);
      expect(a.cause, isNot(CauseReception.aucune), reason: motif);
      if (a.cause == CauseReception.regleDuPoste) {
        regles.add(motif);
        continue;
      }
      if (a.champ != null) {
        expect(a.champ, isNot(contains('«')), reason: motif);
        expect(a.champ, isNot(contains(':')), reason: motif);
        expect(a.champ!.length, lessThan(49), reason: motif);
        expect(a.champ![0], a.champ![0].toUpperCase(), reason: motif);
      }
    }
    for (final r in regles) {
      expect(
        reglesNommees.any(r.contains),
        isTrue,
        reason:
            'motif non classé : « $r » — lui donner une cause, ou le '
            'nommer ici',
      );
    }
    for (final nom in reglesNommees) {
      expect(regles.any((r) => r.contains(nom)), isTrue, reason: nom);
    }
  });

  test('les valeurs inconnues citent leur champ ET leur valeur', () {
    final a = analyserMotif(
      IssueReception.refuse,
      'type de point de stockage inconnu « futur »',
    );
    expect(a.cause, CauseReception.valeurInconnue);
    expect(a.champ, 'Type de point de stockage');
    expect(a.valeur, 'futur');
    final sansValeur = analyserMotif(
      IssueReception.refuse,
      'statut de congé inconnu',
    );
    expect(sansValeur.cause, CauseReception.valeurInconnue);
    expect(sansValeur.valeur, isNull);
    expect(
      expliquer(
        tableServeur: 'conges',
        issue: IssueReception.refuse,
        motif: 'statut de congé inconnu',
      ).phrase,
      contains('porte une valeur'),
    );
  });

  test('chaque cause s’explique en FRANÇAIS : une phrase, une correction, '
      'aucun code ni nom de table brut', () {
    final cas = <(String, IssueReception, String)>[
      ('clients', IssueReception.enAttente, 'client pas encore reçu'),
      ('plats', IssueReception.enAttente, 'menu pas encore reçu'),
      (
        'x',
        IssueReception.enAttente,
        'circuit, client ou guide pas encore reçu',
      ),
      (
        'menus',
        IssueReception.enAttente,
        'aucun compte local pour porter l’écriture',
      ),
      (
        'articles',
        IssueReception.conserve,
        'une modification locale de cet élément attend encore de partir',
      ),
      (
        'articles',
        IssueReception.conserve,
        'un élément du même nom, créé sur ce poste, attend encore de partir',
      ),
      ('articles', IssueReception.refuse, 'libellé absent'),
      ('articles', IssueReception.refuse, 'suivi inconnu « x »'),
      (
        'articles',
        IssueReception.refuse,
        'seuil d’alerte « 1.234 » : deux décimales au plus',
      ),
      (
        'articles',
        IssueReception.refuse,
        'écriture impossible sur ce poste (StateError)',
      ),
      ('conges', IssueReception.refuse, 'congé : la fin précède le début'),
    ];
    for (final (table, issue, motif) in cas) {
      final x = expliquer(tableServeur: table, issue: issue, motif: motif);
      final tout = '${x.titre} ${x.phrase} ${x.correction} ${x.libelleRoute}';
      expect(x.phrase, isNotEmpty, reason: motif);
      expect(x.correction, isNotEmpty, reason: motif);
      expect(tout, isNot(matches(RegExp(r'[a-z]+_[a-z]+'))), reason: tout);
      expect(x.phrase, endsWith('.'), reason: motif);
    }
    // Un élément lié manquant NOMME la table (en français) et mène à son écran.
    final lie = expliquer(
      tableServeur: 'reservations',
      issue: IssueReception.enAttente,
      motif: 'client pas encore reçu',
    );
    expect(lie.dependance, 'clients');
    expect(lie.phrase, contains('Clients'));
    expect(lie.route, '/crm');
    expect(lie.action, ActionCorrection.ouvrirEcran);
    // Pas d'écran connu : on propose de voir les éléments liés.
    final sansEcran = expliquer(
      tableServeur: 'x',
      issue: IssueReception.enAttente,
      motif: 'commande pas encore reçue',
    );
    expect(sansEcran.dependance, 'commandes_achat');
    // Le compte manquant mène à l'écran des comptes — la correction applicable.
    final compte = expliquer(
      tableServeur: 'menus',
      issue: IssueReception.enAttente,
      motif: 'aucun compte local pour porter l’écriture',
    );
    expect(compte.route, '/comptes-utilisateurs');
    expect(compte.correction, contains('Créez un compte'));
  });

  test('un élément aligné n’a rien à corriger', () {
    final x = expliquer(
      tableServeur: 'clients',
      issue: IssueReception.aligne,
      motif: '',
    );
    expect(x.cause, CauseReception.aucune);
    expect(x.action, ActionCorrection.aucune);
  });

  test('un élément illisible est diagnostiqué sans rien deviner', () {
    expect(diagnosticIllisible('texte', 3).id, 'illisible-3');
    expect(
      diagnosticIllisible({'table': 'inconnue_du_futur', 'id': 'a'}, 0).motif,
      contains('table'),
    );
    expect(
      diagnosticIllisible({'table': 'clients'}, 4).id,
      'illisible-4',
      reason: 'sans identifiant',
    );
    expect(
      diagnosticIllisible({'table': 'clients', 'id': 'c-1'}, 0).motif,
      contains('données'),
    );
    for (final d in [
      diagnosticIllisible('texte', 0),
      diagnosticIllisible({'table': 'clients'}, 0),
      diagnosticIllisible({'table': 'clients', 'id': 'c-1'}, 0),
      diagnosticIllisible({'table': 'inconnue_du_futur', 'id': 'a'}, 0),
    ]) {
      expect(
        analyserMotif(IssueReception.refuse, d.motif).cause,
        CauseReception.donneeIllisible,
        reason: d.motif,
      );
    }
  });

  test('l’étiquette d’un élément est son nom lisible', () {
    expect(etiquetteElement({'libelle': 'Riz'}), 'Riz');
    expect(etiquetteElement({'nom': 'Kossi', 'prenom': 'A'}), 'Kossi A');
    expect(etiquetteElement({'numero': '101'}), 'N° 101');
    expect(etiquetteElement({'raison_sociale': 'SOBEBRA'}), 'SOBEBRA');
    expect(etiquetteElement({'x': 1}), isNull);
    expect(etiquetteElement({'libelle': 'a' * 100})!.length, 58);
  });

  test('toute table descendue a un libellé français (jamais son nom brut)', () {
    for (final t in TableDescendue.values) {
      expect(
        libelleTableServeur(t.nomServeur),
        isNot(t.nomServeur),
        reason: t.nomServeur,
      );
    }
  });

  test('l’issue se relit de son code, une issue inconnue est refusée', () {
    for (final i in IssueReception.values) {
      expect(IssueReception.depuisCode(i.code), i);
    }
    expect(IssueReception.depuisCode('perdu'), isNull);
    expect(CauseReception.depuisCode('inconnue'), CauseReception.regleDuPoste);
    expect(IssueReception.aligne.ouverte, isFalse);
    expect(IssueReception.refuse.ouverte, isTrue);
  });
}
