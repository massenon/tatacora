import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/impression/texte_ticket.dart';
import 'package:tatacora_flutter/features/vehicules/domain/entities/contrat_location.dart';
import 'package:tatacora_flutter/features/vehicules/impression/recu_location.dart';

import '../../support/vue_blade.dart';

/// Le REÇU de location (PDF A4 d'un contrat) — jumeau de
/// `pdf/location-recu.blade.php` (`Locations::imprimerRecu`).
///
/// Ce que ces cas protègent : un contrat ANNULÉ ne montre AUCUN montant ; le
/// tarif n'est écrit que s'il explique le montant figé ; les libellés sont CEUX
/// du fichier de langue du serveur (relus, jamais recopiés) ; le PDF se compose
/// hors ligne.
void main() {
  ContratLocation contrat({
    String? statut,
    String? montant = '210000.00',
    String? acompte = '50000.00',
    String? numero = 'LOC-2026-00007',
  }) => ContratLocation(
    id: 'c-1',
    immatriculation: 'AB 1234 RB',
    clientId: 'cli-1',
    clientNom: 'Agence Bénin Tour',
    debut: '2026-09-01',
    fin: '2026-09-04',
    nombreJours: 3,
    packageAvecGuide: false,
    montant: montant,
    acompte: acompte,
    numero: numero,
    statut: statut,
  );

  RecuLocation recu(ContratLocation c, {String? tarif = '70000.00'}) =>
      RecuLocation(
        contrat: c,
        emisLe: DateTime(2026, 10, 28),
        emisPar: 'Awa Kora — Gérant',
        tarifJour: tarif,
      );

  Map<String, String> table(RecuLocation r) => {
    for (final (k, v) in r.lignes) k: v,
  };

  test('un contrat actif : toutes les lignes, en entiers FCFA', () {
    final t = table(recu(contrat()));

    expect(t['N° du contrat'], 'LOC-2026-00007');
    expect(t['Client'], 'Agence Bénin Tour');
    expect(t['Véhicule'], 'AB 1234 RB');
    expect(t['Période'], 'Du 01/09/2026 au 04/09/2026');
    expect(t['Durée'], '3 jour(s)');
    expect(t['Tarif journalier'], '70 000 FCFA');
    expect(t['Montant total'], '210 000 FCFA');
    expect(t['Acompte versé'], '50 000 FCFA');
    expect(t['Reste dû'], '160 000 FCFA');
    expect(t['Statut'], 'Actif');
    expect(t['Émis le'], '28/10/2026');
    expect(t['Émis par'], 'Awa Kora — Gérant');
  });

  test('un contrat ANNULÉ : bandeau, statut, et AUCUN montant', () {
    final r = recu(contrat(statut: 'annule'));
    final t = table(r);

    expect(t['Statut'], 'Annulé');
    for (final interdit in [
      'Tarif journalier',
      'Montant total',
      'Acompte versé',
      'Reste dû',
    ]) {
      expect(t.containsKey(interdit), isFalse, reason: interdit);
    }
    expect(
      r.lignes.any((l) => l.$2.contains('FCFA')),
      isFalse,
      reason: 'aucun montant, quelle que soit la ligne',
    );
    expect(RecuLocation.bandeauAnnule, 'ANNULÉ');
  });

  test('le tarif ne s’imprime que s’il explique le montant figé', () {
    // Le tarif du véhicule a changé depuis la signature : 80 000 x 3 != 210 000.
    expect(table(recu(contrat(), tarif: '80000.00'))['Tarif journalier'], '—');
    expect(table(recu(contrat(), tarif: null))['Tarif journalier'], '—');
    expect(
      table(recu(contrat(), tarif: '80000.00'))['Montant total'],
      isNotNull,
    );
  });

  test('un reste nul se dit « Soldé » ; un montant inconnu, le tiret '
      '(jamais « Soldé »)', () {
    expect(table(recu(contrat(acompte: '210000.00')))['Reste dû'], 'Soldé');
    final inconnu = table(recu(contrat(montant: null, acompte: null)));
    expect(inconnu['Montant total'], '—');
    expect(inconnu['Reste dû'], '—');
    expect(inconnu['Acompte versé'], '—');
    expect(table(recu(contrat(acompte: '0.00')))['Acompte versé'], '—');
  });

  test('aucun numéro n’est inventé : le tiret sans N° de contrat', () {
    expect(table(recu(contrat(numero: null)))['N° du contrat'], '—');
  });

  test('les libellés sont ceux du fichier de langue du serveur', () {
    String l(String cle) => VueBlade.libelle('vehicules.pwa.$cle')!;
    final t = table(recu(contrat()));

    expect(RecuLocation.titre, l('recu_titre'));
    expect(RecuLocation.bandeauAnnule, l('recu_annule_bandeau'));
    expect(RecuLocation.mention, l('recu_mention'));
    expect(RecuLocation.mentionAnnule, l('recu_annule_mention'));
    expect(t.containsKey(l('recu_numero')), isTrue);
    expect(t.containsKey(l('col_client')), isTrue);
    expect(t.containsKey(l('col_vehicule')), isTrue);
    expect(t.containsKey(l('col_periode')), isTrue);
    expect(t.containsKey(l('recu_duree')), isTrue);
    expect(t.containsKey(l('recu_tarif')), isTrue);
    expect(t.containsKey(l('recu_montant')), isTrue);
    expect(t.containsKey(l('recu_acompte')), isTrue);
    expect(t.containsKey(l('recu_reste')), isTrue);
    expect(t.containsKey(l('recu_statut')), isTrue);
    expect(t.containsKey(l('recu_emis_le')), isTrue);
    expect(t.containsKey(l('recu_emis_par')), isTrue);
    expect(t[l('col_periode')], startsWith('Du '));
    expect(t[l('recu_duree')], l('recu_jours').replaceAll(':jours', '3'));
    expect(t[l('recu_statut')], l('contrat_actif'));
    expect(
      table(recu(contrat(acompte: '210000.00')))[l('recu_reste')],
      l('solde'),
    );
    expect(
      table(recu(contrat(statut: 'annule')))[l('recu_statut')],
      l('contrat_annule'),
    );
  });

  test('le PDF se compose hors ligne, actif comme annulé', () async {
    for (final c in [contrat(), contrat(statut: 'annule')]) {
      final octets = await recu(c).pdf();
      expect(String.fromCharCodes(octets.take(5)), '%PDF-');
      expect(octets.length, greaterThan(1000));
    }
  });

  test('rien de ce que le reçu écrit ne disparaît du papier (Latin-1)', () {
    for (final c in [contrat(), contrat(statut: 'annule')]) {
      final r = recu(c);
      final textes = [
        RecuLocation.titre,
        RecuLocation.bandeauAnnule,
        RecuLocation.mention,
        RecuLocation.mentionAnnule,
        for (final (k, v) in r.lignes) ...[k, v],
      ];
      for (final t in textes) {
        expect(caracteresNonImprimables(texteTicket(t)), isEmpty, reason: t);
      }
    }
  });
}
