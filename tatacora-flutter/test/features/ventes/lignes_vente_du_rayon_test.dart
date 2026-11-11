import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/bar/domain/entities/ventes_bar.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/panier.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/reference_catalogue.dart';
import 'package:tatacora_flutter/features/ventes/domain/lignes_vente_du_rayon.dart';

LignePanier ligne(String id, ModuleVendable m, String nom, int prix, int q) =>
    LignePanier(
      id: id,
      reference: ReferenceCatalogue(module: m, code: 'code-$id'),
      libelle: nom,
      prixUnitaire: prix,
      quantite: q,
      ajouteeLe: DateTime(2026, 10, 20),
    );

Panier panier(
  String id,
  StatutPanier statut,
  DateTime le,
  List<LignePanier> lignes, {
  String? motif,
  String? numeroVente,
  String? auteur,
}) => Panier(
  id: id,
  typeVente: TypeVente.comptant,
  statut: statut,
  ouvertLe: le,
  clotureLe: statut == StatutPanier.ouvert ? null : le,
  lignes: lignes,
  motifAnnulation: motif,
  numeroVente: numeroVente,
  auteurLogin: auteur,
);

/// Les ventes du rayon se calculent SUR LE POSTE, comme le service du serveur.
void main() {
  final paniers = [
    // Un ticket MIXTE : la bière est au bar, le poulet au restaurant.
    panier('p1', StatutPanier.cloture, DateTime(2026, 10, 20, 19, 40), [
      ligne('l1', ModuleVendable.m5Bar, 'Bière', 1000, 3),
      ligne('l2', ModuleVendable.m4Restaurant, 'Poulet', 4000, 1),
    ]),
    panier('p2', StatutPanier.annule, DateTime(2026, 10, 21, 9), [
      ligne('l3', ModuleVendable.m5Bar, 'Soda', 500, 2),
    ], motif: 'Erreur de saisie'),
    panier('p3', StatutPanier.ouvert, DateTime(2026, 10, 22, 9), [
      ligne('l4', ModuleVendable.m5Bar, 'Jus', 700, 1),
    ]),
  ];

  test('le filtre de module est celui de la LIGNE, pas de la vente', () {
    final bar = lignesDuRayon(
      paniers,
      ModuleVendable.m5Bar,
      const FiltreVentesBar(),
    );
    expect(bar.map((l) => l.nom), ['Soda', 'Bière']);
    final resto = lignesDuRayon(
      paniers,
      ModuleVendable.m4Restaurant,
      const FiltreVentesBar(),
    );
    expect(resto.map((l) => l.nom), ['Poulet']);
  });

  test('un panier OUVERT n’est pas une vente', () {
    final bar = lignesDuRayon(
      paniers,
      ModuleVendable.m5Bar,
      const FiltreVentesBar(),
    );
    expect(bar.any((l) => l.nom == 'Jus'), isFalse);
  });

  test('le total n’additionne que les lignes validées ; l’annulée reste', () {
    final bar = lignesDuRayon(
      paniers,
      ModuleVendable.m5Bar,
      const FiltreVentesBar(),
    );
    final t = totauxDuRayon(bar);
    expect(t.lignes, 2);
    expect(t.annulees, 1);
    expect(t.totalValide, '3000.00');
    final soda = bar.firstWhere((l) => l.nom == 'Soda');
    expect(soda.annulee, isTrue);
    expect(soda.motifAnnulation, 'Erreur de saisie');
    expect(soda.montant, '1000.00');
    expect(soda.utilisateur, isNull, reason: '« — », jamais un système');
    expect(soda.numero, isNull, reason: 'aucun numéro n’est inventé');
  });

  test('le NUMÉRO est le V- du serveur et l’UTILISATEUR le login de l’auteur '
      '(v38) — pas le numéro d’une facture', () {
    final ventes = [
      panier(
        'v1',
        StatutPanier.cloture,
        DateTime(2026, 10, 20, 10),
        [ligne('a1', ModuleVendable.m5Bar, 'Bière', 1000, 1)],
        numeroVente: 'V-2026-00016',
        auteur: 'caissier1',
      ),
      panier('v2', StatutPanier.cloture, DateTime(2026, 10, 20, 11), [
        ligne('a2', ModuleVendable.m5Bar, 'Soda', 500, 1),
      ]),
    ];
    final lignes = lignesDuRayon(
      ventes,
      ModuleVendable.m5Bar,
      const FiltreVentesBar(),
    );
    final biere = lignes.firstWhere((l) => l.nom == 'Bière');
    final soda = lignes.firstWhere((l) => l.nom == 'Soda');
    expect(biere.numero, 'V-2026-00016');
    expect(biere.utilisateur, 'caissier1');
    // Pas encore envoyée : « — », ni numéro ni compte inventés.
    expect(soda.numero, isNull);
    expect(soda.utilisateur, isNull);
  });

  test('bornes de date INCLUSES, les deux, sur le jour de la vente', () {
    final jour = lignesDuRayon(
      paniers,
      ModuleVendable.m5Bar,
      FiltreVentesBar(du: DateTime(2026, 10, 20), au: DateTime(2026, 10, 20)),
    );
    expect(jour.map((l) => l.nom), ['Bière'], reason: '19 h 40 est retenue');
    final apres = lignesDuRayon(
      paniers,
      ModuleVendable.m5Bar,
      FiltreVentesBar(du: DateTime(2026, 10, 21)),
    );
    expect(apres.map((l) => l.nom), ['Soda']);
  });

  test('statut et recherche (nom, numéro de vente, auteur)', () {
    expect(
      lignesDuRayon(
        paniers,
        ModuleVendable.m5Bar,
        const FiltreVentesBar(statut: StatutVenteBar.annulee),
      ).map((l) => l.nom),
      ['Soda'],
    );
    final numerotees = [
      panier(
        'p1',
        StatutPanier.cloture,
        DateTime(2026, 10, 20, 19, 40),
        [ligne('l1', ModuleVendable.m5Bar, 'Bière', 1000, 3)],
        numeroVente: 'V-2026-7',
        auteur: 'awa',
      ),
      panier('p2', StatutPanier.cloture, DateTime(2026, 10, 21, 9), [
        ligne('l3', ModuleVendable.m5Bar, 'Soda', 500, 2),
      ]),
    ];
    for (final terme in ['V-2026-7', 'awa']) {
      expect(
        lignesDuRayon(
          numerotees,
          ModuleVendable.m5Bar,
          FiltreVentesBar(recherche: terme),
        ).map((l) => l.nom),
        ['Bière'],
        reason: terme,
      );
    }
    expect(
      lignesDuRayon(
        paniers,
        ModuleVendable.m5Bar,
        const FiltreVentesBar(recherche: 'bi'),
      ).map((l) => l.nom),
      ['Bière'],
    );
  });

  test('la pagination est de dix, le total est celui du jeu ENTIER', () {
    final beaucoup = [
      for (var i = 0; i < 23; i++)
        panier('q$i', StatutPanier.cloture, DateTime(2026, 10, 1, 8, i), [
          ligne('m$i', ModuleVendable.m5Bar, 'Bière $i', 1000, 1),
        ]),
    ];
    final tout = lignesDuRayon(
      beaucoup,
      ModuleVendable.m5Bar,
      const FiltreVentesBar(),
    );
    final p3 = pageDuRayon(tout, const FiltreVentesBar(page: 3));
    expect(p3.lignes.length, 3);
    expect(p3.derniere, 3);
    expect(p3.totaux.lignes, 23);
    expect(p3.totaux.totalValide, '23000.00');
    expect(p3.totalPage, '3000.00');
    expect(pageDuRayon(tout, const FiltreVentesBar(page: 99)).page, 3);
  });
}
