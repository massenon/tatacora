import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/vehicules/domain/entities/contrat_location.dart';
import 'package:tatacora_flutter/features/vehicules/domain/entities/vehicule.dart';
import 'package:tatacora_flutter/features/vehicules/domain/indicateurs_vehicules.dart';
import 'package:tatacora_flutter/features/vehicules/domain/regles_vehicules.dart';

/// Les six indicateurs de M8.
///
/// ## Pourquoi ces cas et pas d'autres
///
/// Aucun KPI n'est calculé ailleurs : tout l'est ici. Deux familles de risques,
/// et un cas pour chacune :
///
///  1. **L'arithmétique des montants.** La règle projet interdit l'égalité
///     flottante sur un montant ; [sommeDecimales] travaille en centimes
///     entiers. Le cas éprouve une somme que `double` ne rend PAS exactement.
///  2. **Les absences structurelles.** Deux indicateurs sont `null` par
///     construction, et un zéro à leur place serait plausible — donc invisible.
///     Le cas les fige.
void main() {
  Vehicule vehicule(
    String id, {
    String statut = 'disponible',
    String tarif = '25000.00',
    String categorie = 'voiture',
  }) => Vehicule(
    id: id,
    immatriculation: 'AB-$id-BJ',
    categorie: CategorieVehicule.depuisCode(categorie),
    categorieBrute: categorie,
    // Les trois colonnes que la table locale n'a pas.
    annee: null,
    transmission: null,
    capacite: null,
    tarifJour: tarif,
    statut: StatutVehicule.depuisCode(statut),
    statutBrut: statut,
    exigePermis: exigePermisPour(categorie),
  );

  ContratLocation contrat(
    String id, {
    required String debut,
    required String fin,
    required int jours,
    required String montant,
  }) => ContratLocation(
    id: id,
    immatriculation: 'AB-1-BJ',
    clientId: 'cli-1',
    debut: debut,
    fin: fin,
    nombreJours: jours,
    montant: montant,
    packageAvecGuide: false,
  );

  /* ================================================================== */
  group('sommeDecimales — en centimes entiers, jamais en double', () {
    test('une somme que le flottant ne rend PAS exactement est exacte ici', () {
      // 0.10 + 0.20 vaut 0.30000000000000004 en IEEE 754. Le cas est choisi
      // pour cela : sur un registre de plusieurs centaines de contrats,
      // l'erreur s'accumule sans jamais se voir ligne à ligne.
      expect(sommeDecimales(['0.10', '0.20']), '0.30');

      // Le contrôle qui prouve que le cas mord réellement : la voie flottante
      // échoue là où la voie entière réussit. Sans lui, on ne saurait pas si
      // l'assertion ci-dessus distingue quoi que ce soit.
      expect(0.10 + 0.20 == 0.30, isFalse);
    });

    test('les milliers s\'additionnent sans perte', () {
      expect(sommeDecimales(['25000.00', '25000.00', '12500.50']), '62500.50');
    });

    test('une valeur ILLISIBLE rend null, jamais une somme amputée', () {
      // Une somme à laquelle il manque un contrat est plausible et fausse.
      // « — » se voit ; un total minoré non.
      expect(sommeDecimales(['25000.00', 'quinze mille']), isNull);
      expect(sommeDecimales(['25000.00', '']), isNull);
      // Plus de deux décimales : deviner l'arrondi serait inventer un centime.
      expect(sommeDecimales(['1.005']), isNull);
    });

    test('une liste vide rend null, et non « 0.00 »', () {
      // « 0 F » de chiffre d'affaires se lit « rien vendu » ; « — » se lit
      // « aucun contrat sur la période ». Les deux ne se corrigent pas pareil.
      expect(sommeDecimales(const []), isNull);
    });

    test('un montant négatif reste négatif', () {
      expect(sommeDecimales(['-1500.25']), '-1500.25');
    });
  });

  /* ================================================================== */
  group('nombreDeJours — bornes demi-ouvertes', () {
    test('du 12 au 13 fait UN jour', () {
      expect(nombreDeJours('2026-08-12', '2026-08-13'), 1);
    });

    test('une période nulle ou inversée rend null, jamais 0', () {
      // La restitution est STRICTEMENT après le départ. Rendre 0 ferait
      // afficher « 0 F » sur un tarif réel, au lieu de dire que la période est
      // fausse.
      expect(nombreDeJours('2026-08-12', '2026-08-12'), isNull);
      expect(nombreDeJours('2026-08-13', '2026-08-12'), isNull);
      expect(nombreDeJours(null, '2026-08-13'), isNull);
      expect(nombreDeJours('pas une date', '2026-08-13'), isNull);
    });
  });

  /* ================================================================== */
  group('calculerIndicateurs — les six cartes', () {
    final parc = [
      vehicule('1'),
      vehicule('2', statut: 'entretien'),
      vehicule('3', statut: 'hors_service'),
      vehicule('4', statut: 'loue'),
    ];

    final contrats = [
      contrat(
        'c1',
        debut: '2026-08-10',
        fin: '2026-08-15',
        jours: 5,
        montant: '125000.00',
      ),
      contrat(
        'c2',
        debut: '2026-09-20',
        fin: '2026-09-22',
        jours: 2,
        montant: '50000.00',
      ),
    ];

    test('le parc et les immobilisés se comptent sur le STATUT courant', () {
      final k = calculerIndicateurs(
        parc: parc,
        contrats: contrats,
        debut: '2026-08-01',
        fin: '2026-08-31',
        joursPeriode: 30,
      );

      expect(k.parc, 4);
      // `entretien` et `hors_service` — mais PAS `loue` : un véhicule loué est
      // engagé, pas immobilisé, et il redeviendra libre.
      expect(k.immobilises, 2);
    });

    test('seuls les contrats qui CHEVAUCHENT la période sont retenus', () {
      final k = calculerIndicateurs(
        parc: parc,
        contrats: contrats,
        debut: '2026-08-01',
        fin: '2026-08-31',
        joursPeriode: 30,
      );

      expect(k.contratsSurPeriode, 1);
      expect(k.joursLoues, 5);
      expect(k.chiffreAffaires, '125000.00');
    });

    test(
      'un montant ILLISIBLE sur un contrat retenu rend null, jamais 0.00',
      () {
        // « 0 FCFA » est la mesure d'une somme VIDE ; une somme dont un terme
        // est illisible n'est pas vide, elle est inconnue.
        final k = calculerIndicateurs(
          parc: parc,
          contrats: [
            contrat(
              'c9',
              debut: '2026-08-10',
              fin: '2026-08-15',
              jours: 5,
              montant: 'abc',
            ),
          ],
          debut: '2026-08-01',
          fin: '2026-08-31',
          joursPeriode: 30,
        );

        expect(k.contratsSurPeriode, 1);
        expect(k.chiffreAffaires, isNull);
      },
    );

    test('un contrat rendu le premier jour de la période COMPTE (bornes '
        'incluses du serveur, D398)', () {
      // `ParcVehiculeService::contratsSurFenetre` : `date_fin >= début ET
      // date_debut <= fin`. La FENÊTRE d'affichage retient le contrat rendu le
      // jour où elle commence ; RG-08 (disponibilité) reste demi-ouverte.
      final k = calculerIndicateurs(
        parc: parc,
        contrats: [
          contrat(
            'c3',
            debut: '2026-08-01',
            fin: '2026-09-01',
            jours: 31,
            montant: '10000.00',
          ),
        ],
        debut: '2026-09-01',
        fin: '2026-09-30',
        joursPeriode: 29,
      );

      expect(k.contratsSurPeriode, 1);
      // Le contrat retenu porte son montant, comme au serveur.
      expect(k.chiffreAffaires, '10000.00');
    });

    test('le taux d\'occupation vaut jours loués ÷ (parc × jours)', () {
      final k = calculerIndicateurs(
        parc: parc,
        contrats: contrats,
        debut: '2026-08-01',
        fin: '2026-08-31',
        joursPeriode: 30,
      );

      // 5 jours loués sur 4 véhicules × 30 jours = 120 jours-véhicule.
      expect(k.tauxOccupation, 4);
    });

    test('sans période, le taux est null — jamais « 0 % »', () {
      // « 0 % » se lirait « le parc ne travaille pas » ; « — » se lit
      // « choisissez une période ».
      final k = calculerIndicateurs(
        parc: parc,
        contrats: contrats,
        debut: null,
        fin: null,
        joursPeriode: null,
      );

      expect(k.tauxOccupation, isNull);
    });

    test('sur un parc VIDE, le taux est null et non une division par zéro', () {
      final k = calculerIndicateurs(
        parc: const [],
        contrats: contrats,
        debut: '2026-08-01',
        fin: '2026-08-31',
        joursPeriode: 30,
      );

      expect(k.parc, 0);
      expect(k.tauxOccupation, isNull);
    });

    test(
      'les annulations et le reste à encaisser sont TOUJOURS null (PA-50)',
      () {
        // Ce n'est pas « il n'y en a pas » : c'est « la colonne n'existe pas ».
        // `contrats_location_local` n'a ni statut ni acompte. Un « 0 » ici
        // annoncerait « aucune annulation » et « tout est soldé » — deux bonnes
        // nouvelles que personne n'a vérifiées, sur l'écran où l'on décide de
        // relancer un client.
        final k = calculerIndicateurs(
          parc: parc,
          contrats: contrats,
          debut: '2026-08-01',
          fin: '2026-08-31',
          joursPeriode: 30,
        );

        expect(k.contratsAnnules, isNull);
        expect(k.resteAEncaisser, isNull);

        // Et les deux raisons sont écrites quelque part, à un seul endroit :
        // la carte les lit, elle ne réécrit pas la phrase.
        // La raison est dite en clair, sans référence interne (consigne du
        // PO, 14/10/2026).
        expect(
          IndicateursVehicules.raisons['contrats_annules'],
          allOf(contains('ne peut pas être annulé'), isNot(contains('PA-50'))),
        );
        expect(
          IndicateursVehicules.raisons['reste_a_encaisser'],
          contains('acompte'),
        );
      },
    );
  });

  /* ================================================================== */
  group('Vehicule — ce que la règle dit, jamais ce qu\'on suppose', () {
    test('`exigePermis` suit la catégorie, par l\'unique auteur', () {
      // ⚠ L'ancien prototype écrivait « moto, scooter et vélo sont dispensés » ;
      // la règle appliquée ne dispense que la moto. Le cas fige qu'un scooter
      // reste exigeant — la divergence est ouverte (PA-50), pas tranchée.
      expect(vehicule('s1', categorie: 'scooter').exigePermis, isTrue);
      expect(vehicule('m1', categorie: 'moto').exigePermis, isFalse);
    });

    test('`loue` reste LOUABLE, `entretien` ne l\'est pas', () {
      // Un véhicule loué aujourd'hui est relouable demain. Les confondre ferait
      // disparaître du parc tout ce qui est en cours de location.
      expect(vehicule('a', statut: 'loue').estLouable, isTrue);
      expect(vehicule('b', statut: 'entretien').estLouable, isFalse);
      expect(vehicule('c', statut: 'hors_service').estLouable, isFalse);
    });

    test('les trois colonnes absentes valent null, jamais un zéro', () {
      // `annee`, `transmission` et `capacite` n'existent pas dans
      // `vehicules_local`. « 0 place » se lirait comme une mesure.
      final v = vehicule('1');
      expect(v.annee, isNull);
      expect(v.transmission, isNull);
      expect(v.capacite, isNull);
    });

    test('une catégorie inconnue du registre ne se range PAS par défaut', () {
      // `null` plutôt qu'un repli sur `voiture` : une valeur ajoutée à l'enum
      // demain doit se voir, pas se ranger en silence dans la mauvaise case.
      expect(CategorieVehicule.depuisCode('trottinette'), isNull);
      expect(CategorieVehicule.depuisCode(null), isNull);
      expect(
        CategorieVehicule.depuisCode('4x4'),
        CategorieVehicule.quatreQuatre,
      );
    });

    test('le libellé d\'AFFICHAGE n\'est pas le code stocké', () {
      // « voiture » se dit « Berline » — l'arbitrage du seeder, pris dans ce
      // sens-là. Un libellé dérivé du code par une mise en majuscule sortirait
      // « Voiture », et « velo » sortirait en valeur d'enum brute.
      expect(CategorieVehicule.voiture.libelle, 'Berline');
      expect(CategorieVehicule.velo.libelle, 'Vélo');
      expect(CategorieVehicule.pickup.libelle, 'Pick-up');
    });

    test('les sept valeurs de l\'enum du schéma sont portées', () {
      // Un registre amputé rangerait un vrai véhicule dans « inconnu ».
      expect(CategorieVehicule.values.map((c) => c.code).toSet(), {
        'voiture',
        '4x4',
        'pickup',
        'moto',
        'scooter',
        'velo',
        'bus',
      });
    });
  });

  /* ================================================================== */
  group('ContratLocation — le chevauchement d\'affichage', () {
    test('un contrat hors période n\'est pas retenu', () {
      final c = contrat(
        'c1',
        debut: '2026-08-10',
        fin: '2026-08-15',
        jours: 5,
        montant: '125000.00',
      );

      expect(c.chevauche('2026-08-01', '2026-08-31'), isTrue);
      expect(c.chevauche('2026-09-01', '2026-09-30'), isFalse);
      // Bornes INCLUSES (D398, comme `contratsSurFenetre`) : le contrat qui
      // finit le jour où la période commence est retenu ; la veille, non.
      expect(c.chevauche('2026-08-15', '2026-08-20'), isTrue);
      expect(c.chevauche('2026-08-16', '2026-08-20'), isFalse);
    });

    test('une période ouverte retient tout', () {
      final c = contrat(
        'c1',
        debut: '2026-08-10',
        fin: '2026-08-15',
        jours: 5,
        montant: '125000.00',
      );

      expect(c.chevauche(null, null), isTrue);
    });
  });
}
