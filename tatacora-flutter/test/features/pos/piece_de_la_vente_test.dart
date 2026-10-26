import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/comptabilite/data/moteur_comptable.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/calcul_tva.dart';
import 'package:tatacora_flutter/features/pos/data/piece_de_la_vente.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/mode_reglement.dart';
import 'package:tatacora_flutter/features/pos/domain/messages_ventes.dart';

/// La pièce d'une vente, en FONCTION PURE : les lignes que `VenteService::
/// lignesDeLaPiece` produit, sans base ni moteur.
///
/// La confrontation au vrai serveur (`ventes_contre_serveur_test.dart`) compare
/// ces mêmes lignes au serveur sur plus de soixante opérations ; ces cas-ci
/// disent POURQUOI chaque ligne est là, et ils tiennent sans MySQL.
void main() {
  const sansTva = ParametresTva();
  const tva18Ttc = ParametresTva(active: 'true', taux: '18', convention: 'ttc');

  String? centre(String module) => switch (module) {
    'M4' => 'centre-restaurant',
    'M5' => 'centre-bar',
    _ => null,
  };

  DemandePiece piece({
    ModeReglement mode = ModeReglement.especes,
    Map<String, int> montants = const {'M5': 300000},
    ParametresTva tva = sansTva,
  }) => pieceDeLaVente(
    libelle: 'Vente X',
    dateIso: '2031-06-15',
    mode: mode,
    montantsParModule: montants,
    tva: tva,
    centreDuModule: centre,
  );

  /// Un résumé lisible : compte, sens, montant, centre.
  List<String> lignes(DemandePiece p) => [
    for (final l in p.lignes)
      '${l.compte} '
          '${l.debitCentimes > 0 ? 'D${l.debitCentimes}' : 'C${l.creditCentimes}'}'
          '${l.centreId == null ? '' : ' @${l.centreId}'}',
  ];

  group('Le journal et le libellé', () {
    test('toute vente va au journal des ventes, jamais à la caisse', () {
      expect(piece().journal, 'VTE');
      expect(piece(mode: ModeReglement.carte).journal, 'VTE');
      expect(piece(mode: ModeReglement.noteChambre).journal, 'VTE');
    });

    test('toutes les lignes portent le libellé de la pièce (le seul lien)', () {
      final p = piece();
      expect(p.libelle, 'Vente X');
      // Aucune ligne ne porte son propre libellé : le moteur leur donne celui de
      // la pièce, c'est ce qui les rassemble (PA-52).
      expect(p.lignes.every((l) => l.libelle == null), isTrue);
    });

    test('le libellé nomme la vente ET son identifiant entier', () {
      final l = libelleDeLaPiece('3f2a1b9c-aaaa-4000-8000-000000000001');
      expect(l, startsWith('Vente 3F2A1B9C — '));
      expect(l, endsWith('3f2a1b9c-aaaa-4000-8000-000000000001'));
    });
  });

  group('Où va l’argent : la contrepartie au DÉBIT', () {
    test('espèces -> caisse 5711 ; carte et virement -> banque 5211', () {
      expect(lignes(piece()).first, '5711 D300000');
      expect(lignes(piece(mode: ModeReglement.carte)).first, '5211 D300000');
      expect(lignes(piece(mode: ModeReglement.virement)).first, '5211 D300000');
    });

    test('Mobile Money -> 552 (et non la banque)', () {
      expect(
        lignes(piece(mode: ModeReglement.mobileMoney)).first,
        '552 D300000',
      );
    });

    test('la note de chambre est une CRÉANCE : 4111, aucune trésorerie', () {
      final p = piece(mode: ModeReglement.noteChambre);
      expect(lignes(p).first, '4111 D300000');
      // Débiter la caisse gonflerait le fond d'un argent que personne n'a remis.
      expect(p.lignes.any((l) => l.compte == '5711'), isFalse);
    });

    test('un seul débit, au total', () {
      final p = piece(montants: {'M4': 250000, 'M5': 300000});
      expect(p.lignes.where((l) => l.debitCentimes > 0), hasLength(1));
      expect(p.lignes.first.debitCentimes, 550000);
    });
  });

  group('Le produit : un crédit par module, sur SON compte, à SON centre', () {
    test('le bar crédite 7011 au centre Bar', () {
      expect(lignes(piece()), ['5711 D300000', '7011 C300000 @centre-bar']);
    });

    test('le restaurant crédite 7061 au centre Restaurant', () {
      expect(lignes(piece(montants: {'M4': 250000})), [
        '5711 D250000',
        '7061 C250000 @centre-restaurant',
      ]);
    });

    test('M4 puis M5, QUEL QUE SOIT l’ordre du panier', () {
      final a = lignes(piece(montants: {'M5': 300000, 'M4': 250000}));
      final b = lignes(piece(montants: {'M4': 250000, 'M5': 300000}));
      expect(a, b);
      expect(a, [
        '5711 D550000',
        '7061 C250000 @centre-restaurant',
        '7011 C300000 @centre-bar',
      ]);
    });

    test('un centre introuvable laisse la ligne SANS centre : le moteur '
        'refusera en nommant le compte, jamais un centre deviné', () {
      final p = pieceDeLaVente(
        libelle: 'Vente X',
        dateIso: '2031-06-15',
        mode: ModeReglement.especes,
        montantsParModule: const {'M5': 1000},
        tva: sansTva,
        centreDuModule: (_) => null,
      );
      expect(p.lignes.last.centreId, isNull);
    });

    test('un module sans compte de produits est REFUSÉ, nommé comme le '
        'serveur le nomme', () {
      expect(
        () => piece(montants: {'M1': 450000}),
        throwsA(
          isA<RefusVente>().having(
            (e) => e.message,
            'message',
            MessagesVentes.compteProduitAbsent('Hébergement'),
          ),
        ),
      );
    });
  });

  group('La TVA — l’intention ET la capacité, comme le serveur', () {
    test('inactive : le produit reçoit le montant entier, pas de ligne de '
        'TVA', () {
      expect(lignes(piece()).any((l) => l.startsWith('443')), isFalse);
    });

    test('active, convention TTC : HT au produit, TVA à son compte', () {
      // 3 000 F TTC à 18 % : 457,63 F de TVA (3 000 x 18 / 118, arrondi demi
      // vers le haut), 2 542,37 F hors taxe.
      expect(lignes(piece(tva: tva18Ttc)), [
        '5711 D300000',
        '7011 C254237 @centre-bar',
        '4431 C45763',
      ]);
    });

    test('la TVA du bar va à 4431, celle du restaurant à 4432, chacune une '
        'fois', () {
      final l = lignes(
        piece(montants: {'M4': 250000, 'M5': 300000}, tva: tva18Ttc),
      );
      // 2 500 F -> 381,36 F ; 3 000 F -> 457,63 F.
      expect(l, [
        '5711 D550000',
        '7061 C211864 @centre-restaurant',
        '7011 C254237 @centre-bar',
        '4432 C38136',
        '4431 C45763',
      ]);
    });

    test('la pièce S’ÉQUILIBRE au centime, quel que soit l’arrondi', () {
      for (final montant in [1, 7, 333, 99999, 1234567, 3333300]) {
        final p = piece(
          montants: {'M4': montant, 'M5': 1000 + montant},
          tva: tva18Ttc,
        );
        final debit = p.lignes.fold<int>(0, (t, l) => t + l.debitCentimes);
        final credit = p.lignes.fold<int>(0, (t, l) => t + l.creditCentimes);
        expect(credit, debit, reason: 'montant $montant');
      }
    });

    test('une part de TVA NULLE n’écrit aucune ligne', () {
      // 1 centime : 0,0015 F de TVA, arrondi à zéro.
      final p = piece(montants: {'M5': 1}, tva: tva18Ttc);
      expect(p.lignes.any((l) => l.compte == '4431'), isFalse);
      expect(lignes(p), ['5711 D1', '7011 C1 @centre-bar']);
    });

    test('convention HT : le taux est exigé, la taxe n’est PAS ajoutée — le '
        'défaut du serveur, répliqué', () {
      // `ventiler` rend HT = montant : la part TVA vaut zéro et la pièce ne
      // porte aucune ligne de TVA. Le serveur fait exactement cela (le montant
      // du catalogue est pris hors taxe sans que la taxe s'ajoute à ce qui est
      // encaissé).
      const ht = ParametresTva(active: 'true', taux: '18', convention: 'ht');
      expect(lignes(piece(tva: ht)), [
        '5711 D300000',
        '7011 C300000 @centre-bar',
      ]);
      // Et sans taux, même en HT, la vente est refusée.
      const htSansTaux = ParametresTva(active: 'true', convention: 'ht');
      expect(() => piece(tva: htSansTaux), throwsA(isA<RefusTva>()));
    });

    test('active SANS taux : refus aux mots du serveur', () {
      const sansTaux = ParametresTva(active: 'true');
      expect(
        () => piece(tva: sansTaux),
        throwsA(
          isA<RefusTva>().having(
            (e) => e.message,
            'message',
            PhrasesTva.tauxAbsent('taux_tva'),
          ),
        ),
      );
    });

    test('la convention est jugée AVANT le taux', () {
      const les2 = ParametresTva(active: 'true', convention: 'xyz');
      expect(
        () => piece(tva: les2),
        throwsA(
          isA<RefusTva>().having(
            (e) => e.message,
            'message',
            PhrasesTva.conventionInconnue('xyz', 'convention_prix'),
          ),
        ),
      );
    });
  });
}
