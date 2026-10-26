import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/cause_envoi.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/charges_synchronisation.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';

/// La CAUSE d'un refus de la file d'envoi et le formulaire de correction de
/// la charge (26/10/2026) : le registre des codes relu du serveur, la lecture
/// des phrases par champ, les champs que la charge permet de corriger, et la
/// validation de chaque saisie contre son contrat.
void main() {
  OperationSync op(
    Map<String, Object?> charge, {
    StatutOperationSync statut = StatutOperationSync.rejete,
    Map<String, Object?>? resultat,
    TableSynchronisee table = TableSynchronisee.clients,
    int tentatives = 1,
    int? codeHttp = 200,
  }) => OperationSync(
    seq: 1,
    uuidOperation: 'u-1',
    table: table,
    entiteId: 'e-1',
    type: TypeOperationSync.creation,
    payload: jsonEncode(charge),
    horodatageClient: '2026-10-26T08:00:00Z',
    dateMetier: null,
    statut: statut,
    lotId: null,
    verrouJusqua: null,
    tentatives: tentatives,
    prochaineTentative: null,
    derniereErreur: 'motif',
    codeHttp: codeHttp,
    resultatJson: resultat == null ? null : jsonEncode(resultat),
    idServeur: null,
    creeLe: DateTime(2026, 10, 26, 8),
    synchroniseLe: null,
  );

  group('le registre des codes de refus', () {
    /// Les codes que `SynchronisationService.php` rend : les arguments de
    /// `rejet(...)` (3e argument) et les retours de `codeDeLException`.
    Set<String> codesDuServeur() {
      final php = File(
        '../tatacora-api/app/Shared/Sync/Services/SynchronisationService.php',
      ).readAsStringSync();
      final codes = <String>{};
      // Le code par défaut de `rejet(...)`.
      for (final m in RegExp(
        r"function rejet\([^)]*string \$code = '([a-z_]+)'",
      ).allMatches(php)) {
        codes.add(m.group(1)!);
      }
      // Chaque appel `$this->rejet(` : ses arguments littéraux en snake_case
      // (le code, ou les deux d'un ternaire ; les clés de langue ont un point).
      var depuis = 0;
      while (true) {
        final i = php.indexOf(r'$this->rejet(', depuis);
        if (i < 0) break;
        var profondeur = 0;
        var fin = i + r'$this->rejet'.length;
        do {
          final c = php[fin];
          if (c == '(') profondeur++;
          if (c == ')') profondeur--;
          fin++;
        } while (profondeur > 0);
        final appel = php.substring(i, fin);
        final lit = RegExp(
          r"'([a-z]+(?:_[a-z]+)*)'(?!\s*=>)",
        ).allMatches(appel);
        for (final l in lit) {
          codes.add(l.group(1)!);
        }
        depuis = fin;
      }
      final corps = RegExp(
        r'function codeDeLException[\s\S]*?\n    }',
      ).firstMatch(php)!.group(0)!;
      for (final m in RegExp(r"=> '([a-z_]+)'").allMatches(corps)) {
        codes.add(m.group(1)!);
      }
      return codes;
    }

    test('chaque code du serveur a sa cause française, et le poste n’en '
        'invente aucun', () {
      final serveur = codesDuServeur();
      expect(serveur.length, greaterThan(9), reason: '$serveur');
      expect(
        causesRefusServeur.keys.toSet().difference(serveur),
        isEmpty,
        reason: 'des codes inventés par le poste',
      );
      expect(
        serveur.difference(causesRefusServeur.keys.toSet()),
        isEmpty,
        reason: 'des codes du serveur sans cause française',
      );
    });

    test(
      'chaque cause dit un titre et un conseil, sans code ni snake_case',
      () {
        for (final e in causesRefusServeur.entries) {
          expect(e.value.titre, isNotEmpty);
          expect(e.value.conseil, endsWith('.'));
          expect(
            '${e.value.titre} ${e.value.conseil}',
            isNot(matches(RegExp(r'[a-z]+_[a-z]+'))),
            reason: e.key,
          );
        }
      },
    );
  });

  group('causeDe', () {
    test(
      'refus : le titre du code, le motif du serveur, les phrases par champ',
      () {
        final o = op(
          {'nom': 'K', 'telephone': '1'},
          resultat: {
            'statut': 'rejete',
            'motif': 'Le téléphone est trop court.',
            'code_motif': 'donnees_invalides',
            'erreurs': {
              'telephone': ['Le téléphone est trop court.', 'Autre phrase.'],
              'lignes.0.montant': ['Le montant est obligatoire.'],
            },
          },
        );
        final c = causeDe(o, motif: 'Le téléphone est trop court.');
        expect(c.titre, 'Donnée refusée par le serveur');
        expect(c.code, 'donnees_invalides');
        expect(c.erreurs, hasLength(2));
        expect(c.erreurs.first.libelle, 'Téléphone');
        expect(c.erreurs.first.messages, hasLength(2));
        expect(c.erreurs.last.libelle, 'Ligne 1 : Montant');
        expect(codeMotifDe(o), 'donnees_invalides');
      },
    );

    test('un code inconnu, ou absent (serveur plus ancien), se lit comme une '
        'règle de gestion — jamais comme un code brut', () {
      for (final r in [
        {'statut': 'rejete', 'code_motif': 'code_du_futur'},
        {'statut': 'rejete'},
      ]) {
        final c = causeDe(op({'a': 'b'}, resultat: r), motif: 'Phrase.');
        expect(c.titre, 'Refusé par une règle de gestion');
      }
      expect(causeDe(op({'a': 'b'}), motif: 'Phrase.').erreurs, isEmpty);
    });

    test('bloquée et conflit : leur propre cause, sans action locale', () {
      final b = causeDe(
        op({'a': 'b'}, statut: StatutOperationSync.bloque),
        motif: 'Bloquée : …',
      );
      expect(b.titre, 'Bloquée derrière une opération refusée');
      expect(b.conseil, contains('Débloquer'));
      final k = causeDe(
        op({'a': 'b'}, statut: StatutOperationSync.conflit),
        motif: 'Arbitrage.',
      );
      expect(k.titre, 'Conflit financier');
      expect(k.conseil, contains('aucune action possible'));
    });

    test('les noms de champs sont français, même ceux que le registre ne '
        'connaît pas', () {
      expect(libelleChampServeur('date_arrivee'), 'Date d’arrivée');
      expect(libelleChampServeur('client_id'), 'Client');
      expect(
        libelleChampServeur('lignes.2.prix_unitaire'),
        'Ligne 3 : Prix unitaire',
      );
      expect(libelleChampServeur('type_client'), 'Type client');
    });
  });

  group('champsEditables', () {
    test('un client : nom, prénom, téléphone, e-mail — pas le type', () {
      final o = op(
        chargeClient(
          nom: 'Kossi',
          prenom: null,
          telephone: '97001234',
          email: 'k@exemple.bj',
          typeClient: 'particulier',
        ),
      );
      final champs = champsEditables(o);
      expect(champs.map((c) => c.cle), ['nom', 'telephone', 'email']);
      expect(champs.every((c) => c.genre == GenreChamp.texte), isTrue);
      expect(champs.map((c) => c.libelle), [
        'Nom',
        'Téléphone',
        'Adresse e-mail',
      ]);
    });

    test('montants, dates et quantités sont typés selon la charge', () {
      final o = op(
        chargeReservation(
          clientId: 'c',
          uniteId: 'u',
          dateArrivee: DateTime(2026, 11, 2),
          dateDepart: DateTime(2026, 11, 4),
          statut: 'confirmee',
          acompteFrancs: 15000,
          tarifNuitFrancs: 25000,
          remiseType: 'aucune',
          remiseValeur: null,
          modePaiement: null,
        ),
        table: TableSynchronisee.reservations,
      );
      final par = {for (final c in champsEditables(o)) c.cle: c};
      expect(par['date_arrivee']!.genre, GenreChamp.date);
      expect(par['date_arrivee']!.valeur, '2026-11-02');
      expect(par['date_arrivee']!.libelle, 'Date d’arrivée');
      expect(par['acompte']!.genre, GenreChamp.decimal);
      expect(par['acompte']!.decimales, 2);
      expect(par['acompte']!.valeur, '15000.00');
      expect(par.containsKey('client_id'), isFalse);
      expect(par.containsKey('unite_id'), isFalse);
      expect(par.containsKey('statut'), isFalse);
    });

    test('un montant entier et un instant (vente)', () {
      final o = op(
        chargeVente(
          modePaiement: 'especes',
          sessionEncaissementId: null,
          clotureLe: DateTime(2026, 10, 25, 14, 30, 5),
          pointVente: 'bar',
          tableId: null,
          clientNom: 'Ama',
          montantCloture: 3500,
          lignes: const [],
        ),
        table: TableSynchronisee.ventes,
      );
      final par = {for (final c in champsEditables(o)) c.cle: c};
      expect(par['montant_cloture'], isNull, reason: 'pas dans le registre');
      expect(par['cloture_le']!.genre, GenreChamp.instant);
      expect(par['cloture_le']!.valeur, '2026-10-25 14:30:05');
      expect(par['client_nom']!.valeur, 'Ama');
    });

    test('une charge illisible n’offre aucun champ', () {
      final o = OperationSync(
        seq: 1,
        uuidOperation: 'u',
        table: TableSynchronisee.clients,
        entiteId: 'e',
        type: TypeOperationSync.creation,
        payload: '{pas du json',
        horodatageClient: 'x',
        dateMetier: null,
        statut: StatutOperationSync.rejete,
        lotId: null,
        verrouJusqua: null,
        tentatives: 0,
        prochaineTentative: null,
        derniereErreur: null,
        codeHttp: null,
        resultatJson: null,
        idServeur: null,
        creeLe: DateTime(2026),
        synchroniseLe: null,
      );
      expect(champsEditables(o), isEmpty);
      expect(corrigerCharge(o, {'nom': 'x'}).charge, isNull);
    });
  });

  group('corrigerCharge valide chaque saisie contre le contrat', () {
    final base = op({
      'nom': 'Kossi',
      'prix_vente': 1500,
      'acompte': '15000.00',
      'seuil_alerte': '12.500',
      'date_arrivee': '2026-11-02',
      'cloture_le': '2026-10-25 14:30:05',
      'montant_cloture': 3500,
      'client_id': 'c-1',
      'statut': 'confirmee',
    });

    Map<String, String> erreurs(Map<String, String> saisies) =>
        corrigerCharge(base, saisies).erreurs;

    test('une saisie valide change CE champ, laisse les autres intacts, et '
        'garde le type du contrat', () {
      final v = corrigerCharge(base, {
        'nom': '  Ama  ',
        'prix_vente': '2000',
        'acompte': '15000,5',
        'seuil_alerte': '9',
        'date_arrivee': '2026-12-01',
        'cloture_le': '2026-10-26 08:00:00',
      });
      expect(v.erreurs, isEmpty);
      final c = v.charge!;
      expect(c['nom'], 'Ama');
      expect(c['prix_vente'], 2000, reason: 'entier, pas une chaîne');
      expect(c['acompte'], '15000.50', reason: 'deux décimales du contrat');
      expect(c['seuil_alerte'], '9.000', reason: 'trois décimales du contrat');
      expect(c['date_arrivee'], '2026-12-01');
      expect(c['cloture_le'], '2026-10-26 08:00:00');
      expect(c['client_id'], 'c-1');
      expect(c['statut'], 'confirmee');
      expect(c['montant_cloture'], 3500, reason: 'hors registre : intact');
    });

    test('un champ obligatoire vide est refusé', () {
      expect(erreurs({'nom': '  '}), {'nom': 'Nom est obligatoire.'});
    });

    test('un entier : ni lettres, ni négatif, ni fraction', () {
      for (final v in ['abc', '-5', '12.5', '1 000']) {
        expect(erreurs({'prix_vente': v}).keys, ['prix_vente'], reason: v);
      }
      expect(erreurs({'prix_vente': '0'}), isEmpty);
    });

    test('un décimal ne dépasse pas la précision du contrat', () {
      expect(erreurs({'acompte': '15000.555'}).keys, ['acompte']);
      expect(erreurs({'acompte': 'beaucoup'}).keys, ['acompte']);
      expect(erreurs({'seuil_alerte': '1.2345'}).keys, ['seuil_alerte']);
      expect(erreurs({'acompte': '7'}), isEmpty);
    });

    test('une date doit exister, un instant aussi', () {
      for (final v in ['2026-13-01', '2026-02-30', '02/11/2026', 'demain']) {
        expect(erreurs({'date_arrivee': v}).keys, ['date_arrivee'], reason: v);
      }
      expect(erreurs({'date_arrivee': '2028-02-29'}), isEmpty);
      for (final v in [
        '2026-10-25',
        '2026-10-25 25:00:00',
        '2026-10-25 14:61:00',
      ]) {
        expect(erreurs({'cloture_le': v}).keys, ['cloture_le'], reason: v);
      }
    });

    test('un texte ne dépasse pas sa longueur maximale', () {
      expect(erreurs({'nom': 'x' * 256}).keys, ['nom']);
      expect(erreurs({'nom': 'x' * 255}), isEmpty);
    });

    test('une clé hors registre est ignorée : jamais un identifiant ou un '
        'statut modifié par le formulaire', () {
      final v = corrigerCharge(base, {'client_id': 'pirate', 'statut': 'x'});
      expect(v.erreurs, isEmpty);
      expect(v.charge!['client_id'], 'c-1');
      expect(v.charge!['statut'], 'confirmee');
    });
  });
}
