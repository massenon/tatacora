@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/crm/domain/entities/relance.dart';
import 'package:tatacora_flutter/features/crm/domain/messages_archivage_client.dart';
import 'package:tatacora_flutter/features/crm/domain/messages_relance.dart';

/// Les phrases du poste sont CELLES du serveur, EXÉCUTÉ par PHP : un fichier de
/// langue y est concaténé et commenté (une recherche de texte brut ne le
/// retrouverait pas), et une règle de validation Laravel compose elle-même sa
/// phrase. Ni phrase recopiée « à l'oreille », ni test qui ne vérifierait que
/// lui-même (piège 12).
void main() {
  dynamic php(String code) {
    final r = Process.runSync('php', [
      '-r',
      'require "vendor/autoload.php";'
          r'$app = require "bootstrap/app.php";'
          r'$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();'
          r'app()->setLocale("fr");'
          '$code',
    ], workingDirectory: '../tatacora-api');
    if (r.exitCode != 0) fail('PHP a échoué : ${r.stdout}${r.stderr}');
    return jsonDecode(r.stdout as String);
  }

  late Map<String, dynamic> crm;
  late Map<String, dynamic> pwa;

  setUpAll(() {
    crm =
        php(r'echo json_encode(__("crm"), JSON_UNESCAPED_UNICODE);')
            as Map<String, dynamic>;
    pwa =
        php(r'echo json_encode(__("pwa.clients"), JSON_UNESCAPED_UNICODE);')
            as Map<String, dynamic>;
    // Prouvé non vide : une extraction ratée rendrait tout vrai à vide.
    expect(crm['archivage'], isA<Map<String, dynamic>>());
    expect(pwa['modale_relance_titre'], isNotNull);
  });

  String traduire(String modele, Map<String, String> params) =>
      params.entries.fold(modele, (t, e) => t.replaceAll(':${e.key}', e.value));

  test('les trois refus de RelanceClientService::enregistrer', () {
    expect(
      MessagesRelance.canalInconnu('pigeon'),
      traduire(crm['relance_canal_inconnu'] as String, {'canal': 'pigeon'}),
    );
    expect(
      MessagesRelance.clientInconnu,
      traduire(crm['relance_client_inconnu'] as String, {}),
    );
    expect(
      MessagesRelance.montantInvalide,
      traduire(crm['relance_montant_invalide'] as String, {}),
    );
  });

  test('la validation du montant : la phrase que LARAVEL compose pour la '
      'propriété relanceMontant', () {
    final v =
        php(r'''
      $e = [];
      foreach (["" => "vide", "abc" => "texte", "-5" => "negatif"] as $saisie => $nom) {
        $r = Illuminate\Support\Facades\Validator::make(
          ["relanceMontant" => (string) $saisie],
          ["relanceMontant" => ["required", "numeric", "min:0"]],
        );
        $e[$nom] = $r->errors()->first("relanceMontant");
      }
      $d = Illuminate\Support\Facades\Validator::make(
        ["relancePromesse" => "pas une date"],
        ["relancePromesse" => ["nullable", "date"]],
      );
      $e["date"] = $d->errors()->first("relancePromesse");
      echo json_encode($e, JSON_UNESCAPED_UNICODE);
    ''')
            as Map<String, dynamic>;
    expect(v['vide'], MessagesRelance.montantObligatoire);
    expect(v['texte'], MessagesRelance.montantIllisible);
    expect(v['negatif'], MessagesRelance.montantNegatif);
    expect(v['date'], MessagesRelance.promesseIllisible);
  });

  test('le succès, l’encadré, l’avertissement et les libellés des canaux', () {
    expect(
      MessagesRelance.succes('KORA Jean'),
      traduire(pwa['relance_succes'] as String, {'client': 'KORA Jean'}),
    );
    expect(pwa['relance_jamais'], 'Jamais relancé');
    expect(
      pwa['relances_a_relancer_vide'],
      'Aucun client à relancer : toutes les créances de plus de 30 jours ont '
      'été relancées récemment.',
    );
    for (final c in CanalRelance.values) {
      expect(c.libelle, pwa['canal_${c.code}'], reason: c.code);
    }
  });

  test('les quatre verrous et les messages d’archivage d’un client', () {
    final a = crm['archivage'] as Map<String, dynamic>;
    expect(
      MessagesArchivageClient.verrouSejour(2),
      traduire(a['verrou_sejour'] as String, {'nombre': '2'}),
    );
    expect(
      MessagesArchivageClient.verrouLocation(1),
      traduire(a['verrou_location'] as String, {'nombre': '1'}),
    );
    expect(
      MessagesArchivageClient.verrouCircuit(3),
      traduire(a['verrou_circuit'] as String, {'nombre': '3'}),
    );
    expect(
      MessagesArchivageClient.verrouCreance(4),
      traduire(a['verrou_creance'] as String, {'nombre': '4'}),
    );
    expect(
      MessagesArchivageClient.restaure('KORA'),
      traduire(a['restaure'] as String, {'nom': 'KORA'}),
    );
    // `trans_choice('{1} … |[2,*] …')`, exécuté.
    final choix =
        php(r'''
      echo json_encode([
        trans_choice("crm.archivage.succes", 1, ["nombre" => 1]),
        trans_choice("crm.archivage.succes", 3, ["nombre" => 3]),
      ], JSON_UNESCAPED_UNICODE);
    ''')
            as List<dynamic>;
    expect(MessagesArchivageClient.succes(1), choix[0]);
    expect(MessagesArchivageClient.succes(3), choix[1]);
  });
}
