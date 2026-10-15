import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/achats/domain/dettes_fournisseurs.dart';
import 'package:tatacora_flutter/features/achats/domain/entities/commande_achat.dart';
import 'package:tatacora_flutter/features/achats/domain/messages_reglement.dart';
import 'package:tatacora_flutter/features/achats/domain/regles_reglement.dart';
import 'package:tatacora_flutter/features/depenses/domain/categories_depense.dart';

/// Les règles PURES du règlement fournisseur, seules : les cas de bord qu'un
/// scénario joué contre le serveur n'atteint pas (un reste dû de quelques
/// centimes, une ancienneté à la minute près, une saisie exotique).
///
/// Ces cas ne remplacent PAS la confrontation au vrai service
/// (`reglement_contre_serveur_test.dart`) : ils fixent les arrondis et les
/// planchers que la formule du serveur implique.
void main() {
  CommandeAchat commande({
    String id = 'c',
    String fournisseurId = 'f',
    String fournisseur = 'F',
    String statut = 'envoyee',
    String total = '1000.00',
    String regle = '0.00',
    String reste = '1000.00',
  }) => CommandeAchat(
    id: id,
    dateCommande: '2026-10-01',
    statutCode: statut,
    fournisseurId: fournisseurId,
    fournisseurRaisonSociale: fournisseur,
    nombreLignes: 1,
    montantTotal: total,
    montantRegle: regle,
    resteDu: reste,
    receptionnable: true,
    cloturable: false,
  );

  group('resteDuCentimes', () {
    test('total moins réglé', () {
      expect(
        resteDuCentimes(
          totalCommandeCentimes: 400000,
          regleActifCentimes: 150000,
        ),
        250000,
      );
    });

    test(
      'est PLANCHÉ à zéro : un trop-payé ne devient pas un reste négatif',
      () {
        expect(
          resteDuCentimes(
            totalCommandeCentimes: 1000,
            regleActifCentimes: 1500,
          ),
          0,
        );
        expect(
          resteDuCentimes(
            totalCommandeCentimes: 1000,
            regleActifCentimes: 1000,
          ),
          0,
        );
      },
    );
  });

  group('montantFcfaOuTiret (MontantFcfa::formatOuTiret)', () {
    test('zéro APRÈS arrondi à l’unité : un tiret', () {
      expect(montantFcfaOuTiret(0), '—');
      expect(montantFcfaOuTiret(49), '—'); // 0,49 F -> 0
      expect(montantFcfaOuTiret(-49), '—');
    });

    test('la demi-unité s’éloigne de zéro', () {
      expect(montantFcfaOuTiret(50), '1 FCFA');
      expect(montantFcfaOuTiret(149), '1 FCFA');
      expect(montantFcfaOuTiret(150), '2 FCFA');
      expect(montantFcfaOuTiret(-150), '-2 FCFA');
    });

    test('groupes de trois chiffres', () {
      expect(montantFcfaOuTiret(680000), '6 800 FCFA');
      expect(montantFcfaOuTiret(123456700), '1 234 567 FCFA');
    });
  });

  group('montantAffichableDuChamp (MontantFcfa::format sur le champ)', () {
    test('une saisie vide vaut zéro', () {
      expect(montantAffichableDuChamp(''), '0 FCFA');
    });

    test(
      'les formes que bcmath accepte, tronquées à 2 décimales puis arrondies',
      () {
        expect(montantAffichableDuChamp('4000.00'), '4 000 FCFA');
        expect(montantAffichableDuChamp('.5'), '1 FCFA');
        expect(montantAffichableDuChamp('5.'), '5 FCFA');
        expect(montantAffichableDuChamp('+5'), '5 FCFA');
        expect(montantAffichableDuChamp('00012'), '12 FCFA');
        expect(montantAffichableDuChamp('0.004'), '0 FCFA');
        expect(montantAffichableDuChamp('-5'), '-5 FCFA');
        expect(montantAffichableDuChamp('9000'), '9 000 FCFA');
      },
    );

    test(
      'ce que le serveur ne sait pas lire rend NULL (il plante au rendu)',
      () {
        for (final brut in ['abc', '1e3', ' 100', '100 ', '1,5', '1.2.3']) {
          expect(montantAffichableDuChamp(brut), isNull, reason: '« $brut »');
        }
      },
    );
  });

  group('montantDuReglementCentimes', () {
    test('tronque, ne tronque jamais vers le haut', () {
      expect(montantDuReglementCentimes('100.999'), BigInt.from(10099));
      expect(montantDuReglementCentimes('1.000'), BigInt.from(100));
      expect(montantDuReglementCentimes('0.01'), BigInt.one);
    });

    test(
      'zéro, négatif et « tronqué à zéro » : le montant n’est pas valable',
      () {
        for (final brut in ['0', '-1', '0.004', '0.009', 'abc', '']) {
          expect(
            () => montantDuReglementCentimes(brut),
            throwsA(
              isA<RefusReglement>().having(
                (e) => e.message,
                'message',
                MessagesReglement.montantInvalide,
              ),
            ),
            reason: '« $brut »',
          );
        }
      },
    );

    test('un nombre que bcmath refuse est « mal formé », pas « invalide »', () {
      for (final brut in ['1e3', ' 100', '100 ', '1,5']) {
        // « 1,5 » n'est pas numérique pour PHP : montant invalide.
        final attendu = brut == '1,5'
            ? MessagesReglement.montantInvalide
            : MessagesReglement.malForme;
        expect(
          () => montantDuReglementCentimes(brut),
          throwsA(
            isA<RefusReglement>().having((e) => e.message, 'message', attendu),
          ),
          reason: '« $brut »',
        );
      }
    });
  });

  group('La validation du composant', () {
    test(
      'le montant : obligatoire, nombre, strictement positif — dans cet ordre',
      () {
        void refus(String? brut, String message) => expect(
          () => validerMontantReglement(brut),
          throwsA(
            isA<RefusReglement>()
                .having((e) => e.message, 'message', message)
                .having((e) => e.champ, 'champ', ChampReglement.montant),
          ),
          reason: '« $brut »',
        );

        refus(null, 'Le champ reg montant est obligatoire.');
        refus('', 'Le champ reg montant est obligatoire.');
        refus('  ', 'Le champ reg montant est obligatoire.');
        refus('abc', 'Le champ reg montant doit être un nombre.');
        refus('0', 'validation.gt.numeric');
        refus('-5', 'validation.gt.numeric');
        // 0.004 est strictement positif pour Laravel : le SERVICE le refusera.
        validerMontantReglement('0.004');
        validerMontantReglement('1e3');
      },
    );

    test('la trésorerie : obligatoire, puis dans le registre fermé', () {
      expect(validerTresorerieReglement('banque'), TresorerieDepense.banque);
      expect(
        () => validerTresorerieReglement('cheque'),
        throwsA(
          isA<RefusReglement>().having(
            (e) => e.message,
            'message',
            'La valeur sélectionnée pour reg tresorerie est invalide.',
          ),
        ),
      );
      expect(
        () => validerTresorerieReglement(''),
        throwsA(
          isA<RefusReglement>().having(
            (e) => e.message,
            'message',
            'Le champ reg tresorerie est obligatoire.',
          ),
        ),
      );
    });

    test(
      'les libellés de la liste sont ceux de la vue, pas ceux des Dépenses',
      () {
        expect(
          [
            for (final t in TresorerieDepense.values)
              libelleTresorerieDuReglement(t),
          ],
          ['Caisse', 'Mobile Money', 'Banque'],
        );
      },
    );
  });

  group('La liste des dettes (Approvisionnement::dettes)', () {
    test('écarte receptionnee et cloturee, garde tout le reste', () {
      final liste = [
        commande(id: 'a', statut: 'brouillon'),
        commande(id: 'b', statut: 'envoyee'),
        commande(id: 'c', statut: 'receptionnee_partiellement'),
        commande(id: 'd', statut: 'receptionnee'),
        commande(id: 'e', statut: 'cloturee'),
        commande(id: 'f', statut: 'statut_inconnu'),
      ];

      expect(
        [for (final c in composerDettes(liste).single.commandes) c.id],
        ['a', 'b', 'c', 'f'],
      );
    });

    test('groupe par fournisseur dans l’ordre de PREMIÈRE apparition', () {
      final liste = [
        commande(id: '1', fournisseurId: 'B', fournisseur: 'Bravo'),
        commande(id: '2', fournisseurId: 'A', fournisseur: 'Alpha'),
        commande(id: '3', fournisseurId: 'B', fournisseur: 'Bravo'),
      ];

      final groupes = composerDettes(liste);
      expect([for (final g in groupes) g.fournisseur], ['Bravo', 'Alpha']);
      expect([for (final c in groupes.first.commandes) c.id], ['1', '3']);
    });

    test('le total d’un groupe somme le RESTE DÛ de ses commandes', () {
      final liste = [
        commande(id: '1', reste: '2500.00', regle: '1500.00'),
        commande(id: '2', reste: '1000.00'),
      ];

      expect(composerDettes(liste).single.totalCentimes, 350000);
    });

    test(
      'une commande soldée reste dans la liste (sa ligne affiche « — »)',
      () {
        final liste = [commande(id: '1', reste: '0.00', regle: '1000.00')];
        expect(composerDettes(liste).single.commandes, hasLength(1));
      },
    );
  });

  group('Les deux cartes (render du serveur)', () {
    test(
      '« à payer » compte les FOURNISSEURS dont une commande a un reste',
      () {
        final liste = [
          commande(id: '1', fournisseurId: 'A', reste: '300.00'),
          commande(id: '2', fournisseurId: 'A', reste: '200.00'),
          commande(id: '3', fournisseurId: 'B', reste: '0.00'),
          commande(id: '4', fournisseurId: 'C', reste: '10.00'),
        ];

        final i = composerIndicateursDettes(liste);
        expect(i.fournisseursAPayer, 2); // A et C, pas 3 commandes
      },
    );

    test(
      '« total dû » somme TOUTES les commandes, closes comprises (D262)',
      () {
        final liste = [
          commande(id: '1', reste: '300.00'),
          commande(id: '2', statut: 'receptionnee', reste: '3000.00'),
          commande(id: '3', statut: 'cloturee', reste: '800.00'),
        ];

        final i = composerIndicateursDettes(liste);
        expect(i.totalDuCentimes, 410000);
        // … alors que la LISTE n'en montre qu'une.
        expect(composerDettes(liste).single.commandes, hasLength(1));
        // Et « à payer » ne compte que les fournisseurs de la liste.
        expect(i.fournisseursAPayer, 1);
      },
    );

    test('une liste vide : zéro, et pas d’erreur', () {
      final i = composerIndicateursDettes(const []);
      expect(i.fournisseursAPayer, 0);
      expect(i.totalDuCentimes, 0);
    });
  });

  group('joursAnciennete (diffInDays, tronqué vers zéro)', () {
    final midi = DateTime(2026, 10, 13, 12);

    test('à la journée entière près, du minuit de la commande', () {
      expect(joursAnciennete('2026-10-13', midi), 0);
      expect(joursAnciennete('2026-10-12', midi), 1);
      expect(joursAnciennete('2026-10-01', midi), 12);
      expect(joursAnciennete('2026-07-01', DateTime(2026, 10, 13, 10)), 104);
    });

    test('une date du FUTUR donne un nombre NÉGATIF, tronqué vers zéro', () {
      // Le 20/10 à minuit, vu le 13/10 à 10 h : -6,58 jours -> -6.
      expect(joursAnciennete('2026-10-20', DateTime(2026, 10, 13, 10)), -6);
      expect(joursAnciennete('2026-10-14', midi), 0); // -0,5 jour
    });

    test('une date illisible vaut zéro, jamais une exception', () {
      expect(joursAnciennete('pas une date', midi), 0);
    });
  });

  group('libellePieceReglement', () {
    test('est le lien entre le règlement et sa pièce (PA-52)', () {
      expect(
        libellePieceReglement('Grand Marche SARL', 'abc'),
        'Règlement fournisseur Grand Marche SARL — abc',
      );
    });
  });

  group('figureAuxDettes', () {
    test('« inconnu » n’est pas « clos »', () {
      expect(figureAuxDettes(null), isTrue);
      expect(figureAuxDettes(StatutCommande.brouillon), isTrue);
      expect(figureAuxDettes(StatutCommande.receptionnee), isFalse);
      expect(figureAuxDettes(StatutCommande.cloturee), isFalse);
    });
  });
}
