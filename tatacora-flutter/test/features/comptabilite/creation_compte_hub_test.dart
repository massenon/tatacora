import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/comptabilite/data/moteur_comptable.dart';
import 'package:tatacora_flutter/features/comptabilite/presentation/widgets/modales_hub_comptabilite.dart';

/// Créer un compte depuis le hub ABOUTIT, avec UNE règle : deux à quatre
/// chiffres, la même que le service du serveur (relu dans son code source).
void main() {
  String lire(String chemin) {
    final f = File(chemin).existsSync()
        ? File(chemin)
        : File('../tatacora-api/$chemin');
    return f.readAsStringSync();
  }

  test('l’invite du champ est un numéro que le moteur accepte', () {
    expect(
      MoteurComptable.formatNumeroCompte.hasMatch(
        TextesModalesHubComptabilite.champNumeroInvite,
      ),
      isTrue,
    );
    expect(TextesModalesHubComptabilite.champNumeroInvite, '6056');
    expect(
      TextesModalesHubComptabilite.champNumeroInvite.length,
      lessThanOrEqualTo(MoteurComptable.numeroCompteChiffresMax),
    );
  });

  test(
    'GARDE : la règle du poste est celle du service et de la vue du hub',
    () {
      final service = lire(
        'app/Domain/Comptabilite/Services/PlanComptableService.php',
      );
      final regexPhp = RegExp(
        r"NUMERO_COMPTE_FORMAT\s*=\s*'/(.+?)/'",
      ).firstMatch(service);
      expect(regexPhp, isNotNull, reason: 'la constante du service est lue');
      expect(
        regexPhp!.group(1),
        MoteurComptable.formatNumeroCompte.pattern,
        reason: 'une seule règle, côté poste et côté serveur',
      );
      final max = RegExp(
        r'NUMERO_COMPTE_CHIFFRES_MAX\s*=\s*(\d+)',
      ).firstMatch(service)!;
      expect(int.parse(max.group(1)!), MoteurComptable.numeroCompteChiffresMax);
      final exemple = RegExp(
        r"NUMERO_COMPTE_EXEMPLE\s*=\s*'(\d+)'",
      ).firstMatch(service)!;
      expect(exemple.group(1), MoteurComptable.numeroCompteExemple);

      final hub = lire('app/Pwa/Livewire/Comptabilite/Hub.php');
      expect(
        hub.contains('[1-9][0-9]'),
        isFalse,
        reason: 'le hub ne porte aucune règle de numéro à lui',
      );
    },
  );
}
