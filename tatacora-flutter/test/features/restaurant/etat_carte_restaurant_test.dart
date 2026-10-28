import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/impression/texte_ticket.dart';
import 'package:tatacora_flutter/features/restaurant/domain/entities/carte_restaurant.dart';
import 'package:tatacora_flutter/features/restaurant/impression/etat_carte_restaurant.dart';

/// Les documents de la carte du restaurant : la MARQUE de prix y est imprimée.
///
/// Le formulaire de plat dit, sous la case « Prix provisoire » : « La marque
/// s'imprime en regard du prix, y compris sur la fiche remise au client. » Cette
/// promesse n'est vraie que si le papier la tient — un tarif posé faute de
/// relevé, imprimé comme un tarif ferme, serait opposable au comptoir.
LigneCarteRestaurant ligne(
  String libelle, {
  bool provisoire = false,
  bool corrige = false,
  String prix = '4500.00',
  String categorie = 'plats',
}) => LigneCarteRestaurant(
  id: libelle,
  libelle: libelle,
  categorieBrute: categorie,
  prixVente: prix,
  lieAuStock: true,
  nbIngredients: 1,
  portionsVendables: 33,
  coutMatiere: '750.00',
  prixProvisoire: provisoire,
  prixCorrigeMain: corrige,
);

void main() {
  group('Les marques de prix', () {
    test('provisoire, puis corrigé à la main — dans l’ordre de la vue', () {
      expect(EtatCarteRestaurant.marquesDePrix(ligne('a')), isEmpty);
      expect(EtatCarteRestaurant.marquesDePrix(ligne('a', provisoire: true)), [
        'prix provisoire',
      ]);
      expect(EtatCarteRestaurant.marquesDePrix(ligne('a', corrige: true)), [
        'prix corrigé à la main',
      ]);
      expect(
        EtatCarteRestaurant.marquesDePrix(
          ligne('a', provisoire: true, corrige: true),
        ),
        ['prix provisoire', 'prix corrigé à la main'],
      );
    });

    test('elles passent la garde d’impression : aucun glyphe absent du '
        'papier', () {
      for (final m in EtatCarteRestaurant.marquesDePrix(
        ligne('a', provisoire: true, corrige: true),
      )) {
        expect(caracteresNonImprimables(texteTicket(m)), isEmpty, reason: m);
      }
    });
  });

  group('Le CSV', () {
    test('porte la marque dans sa dernière colonne, VIDE si le tarif est '
        'ferme', () {
      final csv = EtatCarteRestaurant.csv([
        ligne('Brochette', provisoire: true, corrige: true),
        ligne('Riz'),
      ], filtre: 'Carte complète, aucun filtre');
      final lignes = csv.split('\n');

      expect(csv.startsWith('\u{FEFF}'), isTrue, reason: 'BOM UTF-8 (RG-19)');
      expect(
        lignes[2],
        'Article;Categorie;Prix;Ingredients;Portions vendables;Cout matiere;'
        'Marque de prix',
      );
      expect(
        lignes[3],
        'Brochette;Plats complets;4500.00;1;33;750.00;'
        'prix provisoire · prix corrigé à la main',
      );
      expect(lignes[4], 'Riz;Plats complets;4500.00;1;33;750.00;');
    });

    test('les octets sont de l’UTF-8 : le BOM fait EF BB BF et les accents '
        'survivent', () {
      final octets = EtatCarteRestaurant.csvOctets([
        ligne('Brochette', corrige: true),
      ], filtre: 'x');
      expect(octets.sublist(0, 3), [0xEF, 0xBB, 0xBF]);
      // « é » et « à » valent DEUX octets en UTF-8 : un `codeUnits` en aurait
      // écrit un seul, et le décodage rendrait autre chose.
      expect(
        utf8.decode(octets.sublist(3)),
        contains('prix corrigé à la main'),
      );
    });
  });

  group('Les PDF se composent avec leurs marques', () {
    test('le tableau de gestion', () async {
      final octets = await EtatCarteRestaurant.pdf([
        ligne('Brochette', provisoire: true, corrige: true),
        ligne('Riz'),
      ], filtre: 'Carte complète, aucun filtre');
      expect(octets.length, greaterThan(1000));
    });

    test('la fiche des prix : les sans-tarif écartés et comptés, les marques '
        'imprimées', () async {
      final (octets, ecartes) = await EtatCarteRestaurant.ficheDesPrix([
        ligne('Brochette', provisoire: true),
        ligne('Riz', corrige: true),
        ligne('Offert', prix: ''),
      ]);
      expect(ecartes, 1);
      expect(octets.length, greaterThan(1000));
    });

    test('la fiche des prix groupe par catégorie du PLAT, dans l’ordre du '
        'registre, « Autres » en dernier (C1)', () {
      final groupes = EtatCarteRestaurant.groupesDeLaFiche([
        ligne('Sans', categorie: ''),
        ligne('Flan', categorie: 'desserts'),
        ligne('Riz', categorie: 'plats'),
        ligne('Beignet', categorie: 'entrees'),
        ligne('Alloco', categorie: 'plats'),
      ]);
      expect(
        [for (final g in groupes) g.$1],
        ['Entrées', 'Plats complets', 'Nos desserts', 'Autres'],
      );
      expect([for (final l in groupes[1].$2) l.libelle], ['Alloco', 'Riz']);
    });
  });
}
