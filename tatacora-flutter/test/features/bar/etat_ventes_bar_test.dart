import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/impression/texte_ticket.dart';
import 'package:tatacora_flutter/features/bar/domain/entities/carte_bar.dart';
import 'package:tatacora_flutter/features/bar/domain/entities/ventes_bar.dart';
import 'package:tatacora_flutter/features/bar/impression/etat_ventes_bar.dart';

/// Le document de l'onglet « Ventes du Bar » (PA-197) — réellement composé.
///
/// ## Ce que ces cas protègent
///
/// **Qu'il DISE son filtre** (PA-119) : la période en tête, toujours, même
/// sans borne ; puis le statut et la recherche s'il y en a.
///
/// **Que le résumé soit celui du SERVEUR** : les totaux du jeu filtré entier,
/// jamais une somme refaite sur les lignes reçues.
///
/// **Qu'un stock inconnu ne s'écrive jamais « 0 »** : article hors carte,
/// stock non consulté — case vide au tableur, « — » au PDF.
void main() {
  LigneVenteBar ligne({
    String id = 'l1',
    String? code = 'b1',
    String montant = '2400.00',
    bool annulee = false,
    String? utilisateur = 'barman.abcde',
  }) => LigneVenteBar(
    id: id,
    code: code,
    nom: 'Béninoise 66 cl',
    numero: 'V-2026-00012',
    date: DateTime(2026, 9, 10, 14, 5),
    prixUnitaire: '800.00',
    quantite: 3,
    montant: montant,
    annulee: annulee,
    motifAnnulation: annulee ? 'Erreur de saisie' : null,
    utilisateur: utilisateur,
  );

  const carte = [
    LigneCarte(
      id: 'b1',
      libelle: 'Béninoise 66 cl',
      categorie: 'locale',
      prix: 800,
      articleId: 'art-1',
      stock: 24,
    ),
    // Lié, mais le serveur n'a rien dit : « non consulté », jamais « 0 ».
    LigneCarte(
      id: 'b2',
      libelle: 'Flag 33 cl',
      categorie: 'locale',
      prix: 600,
      articleId: 'art-2',
      stock: null,
    ),
  ];

  const totaux = TotauxVentesBar(
    lignes: 13,
    annulees: 1,
    totalValide: '12000.00',
  );

  /* ================================================================== */
  group('Le document DIT son filtre', () {
    test('la période vient en tête, écrite même sans borne', () {
      expect(
        descriptionFiltreVentes(const FiltreVentesBar()),
        'Période : toutes les dates',
      );
      expect(
        descriptionFiltreVentes(
          FiltreVentesBar(du: DateTime(2026, 8, 18), au: DateTime(2026, 8, 20)),
        ),
        'Période : du 18/08/2026 au 20/08/2026 (bornes incluses)',
      );
      expect(
        descriptionFiltreVentes(FiltreVentesBar(du: DateTime(2026, 8, 18))),
        'Période : à partir du 18/08/2026 (borne incluse)',
      );
      expect(
        descriptionFiltreVentes(FiltreVentesBar(au: DateTime(2026, 8, 20))),
        "Période : jusqu'au 20/08/2026 (borne incluse)",
      );
    });

    test('le statut et la recherche suivent, avec les mots de la vue', () {
      expect(
        descriptionFiltreVentes(
          const FiltreVentesBar(
            statut: StatutVenteBar.annulee,
            recherche: '  V-2026 ',
          ),
        ),
        'Période : toutes les dates · Statut : Annulée · '
        'Recherche : « V-2026 »',
      );
    });
  });

  /* ================================================================== */
  group('Le résumé est celui du serveur', () {
    test('les totaux du FILTRE, annulations nommées hors total', () {
      expect(
        EtatVentesBar.resume(totaux),
        '13 ligne(s) · Total validé : 12 000 FCFA — '
        'dont 1 annulée(s), hors total',
      );
      expect(
        EtatVentesBar.resume(
          const TotauxVentesBar(lignes: 2, annulees: 0, totalValide: '1600.00'),
        ),
        '2 ligne(s) · Total validé : 1 600 FCFA',
      );
    });
  });

  /* ================================================================== */
  group('Le tableur', () {
    final csv = EtatVentesBar.csv(
      [
        ligne(),
        ligne(id: 'l2', code: 'retiree', annulee: true, utilisateur: null),
        ligne(id: 'l3', code: 'b2'),
      ],
      totaux,
      filtre: 'Période : toutes les dates',
      carte: carte,
    );
    final lignesCsv = csv.split('\n');

    test('BOM, titre, filtre et résumé en tête', () {
      expect(csv.codeUnitAt(0), 0xFEFF);
      expect(lignesCsv[0], '\u{FEFF}Ventes du Bar');
      expect(lignesCsv[1], 'Filtre appliqué : Période : toutes les dates');
      expect(lignesCsv[2], contains('13 ligne(s)'));
      expect(
        lignesCsv[4],
        'Date;N° vente;Article;Stock actuel;Prix unitaire;Quantité;Montant;'
        'Statut;Utilisateur',
      );
    });

    test('montants BRUTS ; stock connu en chiffre, inconnu en case VIDE', () {
      // Article à la carte, stock 24.
      expect(
        lignesCsv[5],
        '10/09/2026 14:05;V-2026-00012;Béninoise 66 cl;24;800.00;3;2400.00;'
        'Validée;barman.abcde',
      );
      // Hors carte ET sans auteur : case vide, « — » pour l'utilisateur.
      expect(lignesCsv[6], contains('Béninoise 66 cl;;800.00'));
      expect(lignesCsv[6], contains('Annulée;—'));
      // Lié mais non consulté : case vide, jamais « 0 ».
      expect(lignesCsv[7], contains('Béninoise 66 cl;;800.00'));
    });
  });

  /* ================================================================== */
  group('Le PDF', () {
    test('les octets sortent, et ce sont ceux d’un PDF', () async {
      final octets = await EtatVentesBar.pdf(
        [ligne(), ligne(id: 'l2', annulee: true)],
        totaux,
        filtre: 'Période : toutes les dates',
        carte: carte,
        edition: DateTime(2026, 9, 11, 16, 5),
      );
      expect(String.fromCharCodes(octets.take(4)), '%PDF');
    });

    test('tout texte composé tient dans Latin-1', () {
      final textes = [
        EtatVentesBar.titre,
        EtatVentesBar.aideStock,
        EtatVentesBar.resume(totaux),
        ...EtatVentesBar.entetes,
        ...EtatVentesBar.cellules(ligne(), {for (final l in carte) l.id: l}),
      ];
      for (final t in textes) {
        expect(caracteresNonImprimables(texteTicket(t)), isEmpty, reason: t);
      }
    });
  });
}
