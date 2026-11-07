import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/facturation/domain/conversion_boitier.dart';
import 'package:tatacora_flutter/features/facturation/domain/erreur_boitier.dart';

/// La conversion TATACORA → JSON du pilote CC300 : des fonctions pures, prouvées
/// sans réseau. Chaque cas est un piège du pilote lu dans son code Go.
void main() {
  DemandeNormalisation demande({
    List<LigneDemande>? lignes,
    List<PaiementDemande>? paiements,
    String? reference,
    String operateurNom = 'Réception',
    String clientNom = 'Client de passage',
  }) {
    final l =
        lignes ??
        const [
          LigneDemande(
            libelle: 'Nuitée chambre 3',
            prixUnitaire: 15000,
            quantite: 2,
            groupe: GroupeTaxe.b,
          ),
        ];
    return DemandeNormalisation(
      pieceId: 'p-1',
      numero: 'F-2026-00001',
      lignes: l,
      paiements:
          paiements ??
          [
            PaiementDemande(
              mode: ModePaiementPilote.especes,
              montant: l.fold(0, (t, x) => t + x.montant),
            ),
          ],
      clientNom: clientNom,
      operateurId: 'RECEPTION01',
      operateurNom: operateurNom,
      referenceAvoir: reference,
    );
  }

  Map<String, dynamic> json(DemandeNormalisation d) =>
      jsonDecode(construireJsonPilote(d)) as Map<String, dynamic>;

  group('la forme du JSON (bill.spec.json)', () {
    test('une vente : vt = FV, prix et quantités ENTIERS, jamais de float', () {
      final texte = construireJsonPilote(demande());
      final j = jsonDecode(texte) as Map<String, dynamic>;
      expect(j['vt'], 'FV');
      expect(j.containsKey('rt'), isFalse);
      expect(j.containsKey('rn'), isFalse);
      expect(j['seller_id'], 'RECEPTION01');
      expect(j['seller_name'], 'Reception');
      expect(j['aib'], 'N/A');
      expect(j['buyer_ifu'], '');
      final p = (j['products'] as List).single as Map<String, dynamic>;
      expect(p['tax'], 'B');
      expect(p['price'], 15000);
      expect(p['items'], 2);
      expect(texte, contains('"price":15000,'));
      expect(texte, isNot(contains('15000.0')));
      expect((j['payments'] as List).single, {'mode': 'E', 'amount': 30000});
    });

    test('jamais specific_tax ni original_price : le pilote les décode en '
        'chaînes et échouerait', () {
      final j = json(demande());
      final p = (j['products'] as List).single as Map<String, dynamic>;
      expect(p.containsKey('specific_tax'), isFalse);
      expect(p.containsKey('original_price'), isFalse);
      expect(p.containsKey('specific_tax_desc'), isFalse);
      expect(p.containsKey('price_change_explanation'), isFalse);
    });

    test(
      'un avoir : rt = FA et rn = NIM-TC de la facture d’origine, sans vt',
      () {
        final j = json(demande(reference: 'ED04000623-41'));
        expect(j['rt'], 'FA');
        expect(j['rn'], 'ED04000623-41');
        expect(j.containsKey('vt'), isFalse);
      },
    );

    test('plusieurs paiements : un par mode', () {
      final j = json(
        demande(
          lignes: const [
            LigneDemande(
              libelle: 'Dîner',
              prixUnitaire: 10000,
              quantite: 1,
              groupe: GroupeTaxe.b,
            ),
          ],
          paiements: const [
            PaiementDemande(mode: ModePaiementPilote.especes, montant: 4000),
            PaiementDemande(
              mode: ModePaiementPilote.mobileMoney,
              montant: 6000,
            ),
          ],
        ),
      );
      expect(j['payments'], [
        {'mode': 'E', 'amount': 4000},
        {'mode': 'M', 'amount': 6000},
      ]);
    });
  });

  group('les montants : jamais envoyés s’ils ne concordent pas', () {
    void refuse(DemandeNormalisation d, CauseBoitier cause) {
      try {
        construireJsonPilote(d);
        fail('une ErreurBoitier était attendue');
      } on ErreurBoitier catch (e) {
        expect(e.cause, cause);
      }
    }

    test('somme des paiements ≠ total : refusé, avec la phrase des deux '
        'montants', () {
      try {
        construireJsonPilote(
          demande(
            paiements: const [
              PaiementDemande(mode: ModePaiementPilote.especes, montant: 29000),
            ],
          ),
        );
        fail('refus attendu');
      } on ErreurBoitier catch (e) {
        expect(e.cause, CauseBoitier.montantsIncoherents);
        expect(
          e.message,
          'Les montants ne concordent pas (lignes 30000 FCFA, paiements 29000 '
          'FCFA) : corrigez avant de normaliser.',
        );
      }
    });

    test('au-delà de 2^24 − 1 : refusé (float32 arrondirait en silence)', () {
      refuse(
        demande(
          lignes: const [
            LigneDemande(
              libelle: 'Gros',
              prixUnitaire: 16777216,
              quantite: 1,
              groupe: GroupeTaxe.a,
            ),
          ],
        ),
        CauseBoitier.nonConvertible,
      );
      // La limite exacte passe.
      expect(
        json(
          demande(
            lignes: const [
              LigneDemande(
                libelle: 'Limite',
                prixUnitaire: maxEntierFloat32,
                quantite: 1,
                groupe: GroupeTaxe.a,
              ),
            ],
          ),
        )['payments'],
        [
          {'mode': 'E', 'amount': 16777215},
        ],
      );
      // Un total qui dépasse sans qu'une ligne dépasse.
      refuse(
        demande(
          lignes: const [
            LigneDemande(
              libelle: 'A',
              prixUnitaire: 10000000,
              quantite: 1,
              groupe: GroupeTaxe.a,
            ),
            LigneDemande(
              libelle: 'B',
              prixUnitaire: 10000000,
              quantite: 1,
              groupe: GroupeTaxe.a,
            ),
          ],
          paiements: const [
            PaiementDemande(
              mode: ModePaiementPilote.especes,
              montant: 10000000,
            ),
            PaiementDemande(mode: ModePaiementPilote.carte, montant: 10000000),
          ],
        ),
        CauseBoitier.nonConvertible,
      );
    });

    test('ligne nulle ou négative, sans ligne, sans règlement : refusé', () {
      refuse(
        demande(
          lignes: const [
            LigneDemande(
              libelle: 'x',
              prixUnitaire: 0,
              quantite: 1,
              groupe: GroupeTaxe.a,
            ),
          ],
          paiements: const [
            PaiementDemande(mode: ModePaiementPilote.especes, montant: 1),
          ],
        ),
        CauseBoitier.nonConvertible,
      );
      refuse(demande(lignes: const []), CauseBoitier.nonConvertible);
      refuse(demande(paiements: const []), CauseBoitier.nonConvertible);
    });

    test('l’opérateur est obligatoire', () {
      refuse(demande(operateurNom: '   '), CauseBoitier.nonConvertible);
    });
  });

  group('les textes', () {
    test('accents et apostrophes transcrits en ASCII', () {
      expect(
        transcrireAscii('Séjour à l’hôtel « Noël » – œuf, ça va ?'),
        'Sejour a l\'hotel " Noel " - oeuf, ca va ?',
      );
      expect(transcrireAscii('Crème brûlée 🍮'), 'Creme brulee ');
    });

    test('les caractères que le pilote remplace ou qui séparent son protocole '
        'deviennent des espaces', () {
      expect(
        nettoyerTexte('Pain<b>&Co\r\nAB,CD;EF*GH\tIJ', 60),
        'Pain b Co AB CD EF GH IJ',
      );
      expect(nettoyerTexte('  a   b  ', 60), 'a b');
    });

    test('coupe à la limite SANS couper un mot quand une espace précède', () {
      // 60 caractères exacts : intact.
      expect(nettoyerTexte('x' * 60, 60).length, 60);
      // Le 61ᵉ caractère tombe au milieu de « magnifique » : la coupe revient à
      // l'espace précédente.
      final long =
          'Grande chambre climatisee avec terrasse et vue magnifique '
          'sur la montagne';
      final coupe = nettoyerTexte(long, 60);
      expect(coupe.length, lessThanOrEqualTo(60));
      expect(coupe, isNot(endsWith(' ')));
      expect(long.startsWith('$coupe '), isTrue, reason: 'coupe sur un mot');
      // Aucune espace proche : coupe sèche.
      expect(nettoyerTexte('y' * 100, 60).length, 60);
      // Un libellé accentué est transcrit AVANT la coupe : jamais un caractère
      // coupé en deux.
      expect(nettoyerTexte('é' * 70, 60), 'e' * 60);
      expect(nettoyerTexte('Cœur ' * 20, 60).length, lessThanOrEqualTo(60));
    });

    test('le nom du vendeur est limité à 30, le libellé à 60, le code-barres à '
        '24', () {
      final j = json(
        demande(
          operateurNom: 'Réceptionniste principale du gîte Chez Noël',
          lignes: [
            LigneDemande(
              libelle: 'Libellé ${'très ' * 30}long',
              prixUnitaire: 1000,
              quantite: 1,
              groupe: GroupeTaxe.b,
              codeArticle: 'CODE-${'9' * 40}',
            ),
          ],
        ),
      );
      expect((j['seller_name'] as String).length, lessThanOrEqualTo(30));
      final p = (j['products'] as List).single as Map<String, dynamic>;
      expect((p['label'] as String).length, lessThanOrEqualTo(60));
      expect((p['bar_code'] as String).length, lessThanOrEqualTo(24));
    });
  });

  group('la table de correspondance', () {
    test('modes de paiement : espèces E, mobile money M, carte C, chèque D, '
        'virement V, autre A', () {
      const attendu = {
        'especes': ModePaiementPilote.especes,
        'Espèces': ModePaiementPilote.especes,
        'mobile_money': ModePaiementPilote.mobileMoney,
        'Mobile Money': ModePaiementPilote.mobileMoney,
        'carte': ModePaiementPilote.carte,
        'Carte': ModePaiementPilote.carte,
        'cheque': ModePaiementPilote.cheque,
        'Chèque': ModePaiementPilote.cheque,
        'virement': ModePaiementPilote.virement,
        'Virement bancaire': ModePaiementPilote.virement,
        'autre': ModePaiementPilote.autre,
      };
      attendu.forEach((brut, mode) {
        expect(modePaiementPilote(brut), mode, reason: brut);
      });
      expect(ModePaiementPilote.especes.code, 'E');
      expect(ModePaiementPilote.mobileMoney.code, 'M');
      expect(ModePaiementPilote.carte.code, 'C');
      expect(ModePaiementPilote.cheque.code, 'D');
      expect(ModePaiementPilote.virement.code, 'V');
      expect(ModePaiementPilote.autre.code, 'A');
    });

    test('crédit, inconnu, vide : JAMAIS un repli sur espèces', () {
      expect(modePaiementPilote('credit'), isNull);
      expect(modePaiementPilote('Crédit'), isNull);
      expect(modePaiementPilote('troc'), isNull);
      expect(modePaiementPilote(''), isNull);
      expect(modePaiementPilote(null), isNull);
    });

    test('groupes de taxe : TVA active B, sinon A ; taxe de séjour F nommée '
        'TAXE DE SEJOUR', () {
      expect(groupeDeTaxe(tvaActive: true, libelle: 'Nuitée'), GroupeTaxe.b);
      expect(groupeDeTaxe(tvaActive: false, libelle: 'Nuitée'), GroupeTaxe.a);
      expect(
        groupeDeTaxe(tvaActive: true, libelle: 'Taxe de séjour (2 nuits)'),
        GroupeTaxe.f,
      );
      expect(
        groupeDeTaxe(tvaActive: false, libelle: 'TAXE DE SEJOUR'),
        GroupeTaxe.f,
      );
      final j = json(
        demande(
          lignes: const [
            LigneDemande(
              libelle: 'Taxe de séjour (2 nuits)',
              prixUnitaire: 500,
              quantite: 2,
              groupe: GroupeTaxe.f,
            ),
          ],
        ),
      );
      final p = (j['products'] as List).single as Map<String, dynamic>;
      expect(p['tax'], 'F');
      expect(p['label'], 'TAXE DE SEJOUR');
    });
  });
}
