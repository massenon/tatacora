@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/achats/data/achats_dao.dart';
import 'package:tatacora_flutter/features/achats/domain/entities/commande_achat.dart';
import 'package:tatacora_flutter/features/depenses/domain/categories_depense.dart';
import 'package:tatacora_flutter/features/depenses/domain/entities/depense.dart';
import 'package:tatacora_flutter/features/etats/data/etats_api.dart';
import 'package:tatacora_flutter/features/etats/domain/apercu_etat.dart';
import 'package:tatacora_flutter/features/etats/domain/registre_etats.dart';
import 'package:tatacora_flutter/features/etats/presentation/ecran_etats.dart';
import 'package:tatacora_flutter/features/etats/presentation/providers_etats.dart';
import 'package:tatacora_flutter/features/stocks/data/stocks_dao.dart';
import 'package:tatacora_flutter/features/tableau_de_bord/presentation/ecran_pilotage_consolide.dart';

import '../depenses/support/outils_depenses.dart';
import '../facturation/support/outils_encaissement.dart'
    show caissierEssai, creerClient, emettreFacture, paiementsDaoSur;
import '../achats/support/outils_reglement.dart';
import '../comptabilite/support/outils_comptabilite.dart';
import 'jeu_etats.dart';
import 'registre_serveur_etats.dart';

/// M14 par la CHAÎNE RÉELLE : écran -> fournisseurs -> `EtatsApi` -> dépôts de
/// chaque module -> base. Aucune liste n'est surchargée (piège 5) : seules
/// l'horloge et la base du test le sont.
///
/// Le jeu (`jeu_etats.dart`) est écrit par les VRAIS dépôts — `StocksDao`,
/// `DepenseDao`, `PanierDao`, `VehiculeDao`, `TourismeDao`, `AchatsDao`,
/// `EmployeDao`, `BulletinPaieService`, `ReservationRepositoryLocal` — et les
/// valeurs attendues sont écrites ci-dessous À LA MAIN, une par cellule, avec
/// le calcul qui les justifie. Les mots (libellés, statuts, « Oui » / « Non »)
/// viennent du serveur par l'exécution de PHP, jamais d'une recopie.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final serveur = ServeurEtats.charger();
  final maintenant = DateTime(2026, 10, 10, 14, 30);
  const tous = <String, String>{
    'M1': 'C',
    'M3': 'C',
    'M5': 'C',
    'M6': 'C',
    'M7': 'C',
    'M8': 'C',
    'M9': 'C',
    'M10': 'C',
    'M11': 'C',
    'M13': 'C',
    'M14': 'C',
  };

  late AppDatabase db;
  late JeuEtats jeu;

  setUp(() async {
    db = AppDatabase.enMemoire();
    jeu = await semerJeuEtats(db, maintenant);
  });

  tearDown(() => db.close());

  /// Le référentiel comptable du poste, pour qu'un règlement puisse passer sa
  /// pièce (le jeu d'états n'en installe pas : aucun autre cas n'écrit d'argent).
  Future<void> semerAuteurEtReferentiel() async {
    await baseInstalleeSur(db, maintenant);
  }

  List<Override> surcharges(Map<String, String> droits) => [
    baseLocaleProvider.overrideWithValue(db),
    droitsProvider.overrideWithValue(GardeAcces(droits)),
    horlogeEtatsProvider.overrideWithValue(() => maintenant),
    horlogeTableauDeBordProvider.overrideWithValue(() => maintenant),
  ];

  ProviderContainer conteneur({Map<String, String> droits = tous}) {
    final c = ProviderContainer(overrides: surcharges(droits));
    addTearDown(c.dispose);
    return c;
  }

  Future<ApercuEtat> lire(ProviderContainer c, String code) async {
    final r = await c.read(apercuEtatProvider(code).future);
    expect(r, isA<ApercuRecu>(), reason: '$code devrait être calculé');
    return (r as ApercuRecu).apercu;
  }

  Future<ApercuRefuse> refuse(ProviderContainer c, String code) async {
    final r = await c.read(apercuEtatProvider(code).future);
    expect(r, isA<ApercuRefuse>(), reason: '$code devrait être refusé');
    return r as ApercuRefuse;
  }

  List<String> valeurs(ApercuEtat a) => [
    for (final i in a.indicateurs) i.valeur,
  ];
  List<String> libelles(ApercuEtat a) => [
    for (final i in a.indicateurs) i.libelle,
  ];

  /// L'identifiant abrégé de la vente : la colonne « N° ».
  String refVente(String nom) {
    final brut = jeu.panierIds[nom]!.replaceAll('-', '').toUpperCase();
    return brut.substring(0, 8);
  }

  group('Le catalogue est composé des droits sur le module SOURCE', () {
    test('tous les droits : les douze états, dans l’ordre du serveur', () {
      final c = conteneur();
      final catalogue = c.read(etatsApiProvider).catalogue();

      expect(
        [for (final e in catalogue) e.code],
        [for (final s in serveur.etats) s.code],
      );
      expect(
        [for (final e in catalogue) e.module],
        [for (final s in serveur.etats) s.module],
      );
      expect(catalogue.every((e) => e.niveau == NiveauAcces.complet), isTrue);
    });

    test('éditer l’état des stocks exige M6, pas M14', () {
      // M14 seul : aucun état. C'est le point de la règle — l'accès au hub ne
      // donne aucun état.
      expect(
        conteneur(droits: {'M14': 'C'}).read(etatsApiProvider).catalogue(),
        isEmpty,
      );

      final seulM6 = conteneur(
        droits: {'M6': 'L'},
      ).read(etatsApiProvider).catalogue();
      expect([for (final e in seulM6) e.code], ['stocks']);
      expect(seulM6.single.niveau, NiveauAcces.lecture);
      expect(seulM6.single.module, 'M6');
    });

    test("un module sans droit ('-') est ABSENT, pas grisé", () {
      final c = conteneur(droits: {...tous, 'M6': '-'});
      final codes = [
        for (final e in c.read(etatsApiProvider).catalogue()) e.code,
      ];
      expect(codes, isNot(contains('stocks')));
      expect(codes.length, 11);
    });

    test(
      'M8 porte DEUX états, M10 en porte DEUX : le droit est par module',
      () {
        final c = conteneur(droits: {'M8': 'C', 'M10': 'L'});
        expect(
          [for (final e in c.read(etatsApiProvider).catalogue()) e.code],
          ['parc-vehicules', 'depenses', 'locations-vehicules', 'balance'],
        );
      },
    );
  });

  group('Chaque état, calculé sur la base du poste', () {
    test(
      'stocks : Farine en rupture, Huile sous seuil, Sel sans coût',
      () async {
        final a = await lire(conteneur(), 'stocks');

        expect(a.titre, 'État des stocks — tous points de stockage');
        expect(a.periode, 'Arrêté au 10/10/2026 à 14:30');
        expect(a.moduleSource, 'M6');
        expect(libelles(a), serveur.etat('stocks').indicateurs);
        expect(a.entetes, serveur.etat('stocks').entetes);

        final sousSeuil = serveur.langue('stocks.etat.sous_seuil');
        final normal = serveur.langue('stocks.etat.normal');
        expect(a.lignes, [
          // Rupture : la quantité est <= au seuil, donc « Sous seuil » comme au
          // serveur. Son stock est 0 et sa valeur 0 : une MESURE, pas un tiret.
          ['Farine', '', 'kg', '0.00', '1.00', sousSeuil, '0.00'],
          // 2 L à 500 F = 1 000 F, seuil 6.
          ['Huile', '', 'L', '2.00', '6.00', sousSeuil, '1000.00'],
          // Achat journalier : ni quantité, ni seuil, ni statut, ni valeur.
          ['Pain', '', 'unité', 'non suivi', '', '', ''],
          // 10 sacs à 1 250,50 F = 12 505 F.
          ['Riz', '', 'sac', '10.00', '5.00', normal, '12505.00'],
          // Du stock sans aucune entrée valorisée : valeur INCONNUE, non nulle.
          ['Sel', '', 'sac', '4.00', '1.00', normal, ''],
        ]);
        expect(valeurs(a), [
          '5', // Références : les cinq lignes.
          '2', // Sous seuil : Farine et Huile — Pain n'est pas suivi.
          '13505.00 (hors 1 article(s) sans coût)', // 12505 + 1000 + 0.
        ]);
        expect(a.mentions.length, 2);
        expect(a.mentions.first, contains('1 article(s) en achat journalier'));
        // Le compte « Sous seuil » diffère du serveur pour les journaliers.
        expect(a.mentions.first, contains('diffère donc de celui du serveur'));
        // Aucune référence interne affichée (consigne du PO, 14/10/2026) :
        // la mention dit l'écart, jamais le numéro de décision.
        expect(a.mentions.first, isNot(contains('D146')));
        expect(a.mentions.last, contains('ventes du bar'));
      },
    );

    test('tableau de bord : le CA encaissé, la trésorerie et les factures non '
        'soldées sont CALCULÉS ; une seule carte garde sa raison datée', () async {
      final a = await lire(conteneur(), 'tableau-de-bord');

      expect(a.titre, 'Tableau de bord — synthèse consolidée');
      expect(a.periode, 'Du 11/09/2026 au 10/10/2026');
      expect(a.moduleSource, 'M11');
      expect(libelles(a), serveur.etat('tableau-de-bord').indicateurs);
      expect(valeurs(a), [
        '0.00', // CA encaissé : aucun encaissement dans la fenêtre — un zéro VRAI.
        '11.66 %', // 7 nuitées / (2 unités louables x 30 jours), tronqué.
        '8000.00', // Dépenses cumulées : les 8 000 F de la dépense du jeu, lus de ses pièces de classe 6.
        '2 / 4', // actifs / effectif retenu (le salarié parti n'en est pas).
      ]);

      expect(a.entetes, serveur.etat('tableau-de-bord').entetes);
      String l(String cle) => serveur.langue('tableaux_de_bord.kpi.$cle');
      expect(a.lignes, [
        // Aucun encaissement dans la fenêtre ni avant : zéros VRAIS (la source
        // est complète), une base précédente nulle ne produit pas « +100 % ».
        [l('chiffre_affaires_encaisse'), '0.00', '0.00', '—'],
        [l('taux_occupation'), '11.66', '3.33', '250.15 %'],
        // Le fond de la caisse ouverte par le jeu, identique aux deux périodes.
        [l('tresorerie_caisse'), '1000.00', '1000.00', '0.00 %'],
        [l('depenses_cumulees'), '8000.00', '0.00', '—'],
        // Une base précédente nulle ne produit pas « +100 % ».
        [l('reservations_en_attente'), '1', '0', '—'],
        [l('factures_impayees'), '0', '0', '—'],
        // Photographie : « — » sous « Période précédente », jamais 0.00.
        [l('valeur_stock'), '13505.00 (hors 1 article(s) sans coût)', '', '—'],
        [l('employes_actifs'), '2', '', '—'],
      ]);

      // Toutes les sources du tableau sont détenues : aucune mention d'absence.
      final absents = a.mentions.where(
        (m) => m.startsWith('${l('depenses_cumulees')} : '),
      );
      expect(absents, isEmpty);
      expect(a.mentions.any((m) => m.contains('constaté le')), isFalse);
      expect(a.mentions.any((m) => m.contains('aucun paiement')), isFalse);
    });

    test(
      'parc de véhicules : valeur BRUTE du registre, louables seuls cumulés',
      () async {
        final a = await lire(conteneur(), 'parc-vehicules');

        expect(a.titre, 'État du parc de véhicules');
        expect(a.periode, 'Arrêté au 10/10/2026 à 14:30');
        expect(a.entetes, serveur.etat('parc-vehicules').entetes);
        final oui = serveur.langue('vehicules.etat.permis_oui');
        final non = serveur.langue('vehicules.etat.permis_non');
        expect(a.lignes, [
          // Tri : catégorie STOCKÉE puis immatriculation (« 4x4 » < « moto »).
          ['CD-456-BJ', '4x4', '', '', '60000.00', 'entretien', oui],
          // Les contrats ont passé ces deux véhicules à « loue » : ils restent
          // louables (le statut n'est pas la disponibilité).
          ['EF-789-BJ', 'moto', '', '', '15000.00', 'loue', non],
          ['GH-000-BJ', 'velo', '', '', '5000.00', 'disponible', oui],
          // « voiture », pas « Berline » : la valeur stockée, comme le serveur.
          ['AB-123-BJ', 'voiture', '', '', '35000.00', 'loue', oui],
        ]);
        expect(valeurs(a), [
          '4', // Véhicules
          '3', // Louables : loué, loué, disponible.
          '1', // Immobilisés : le 4x4 en entretien.
          '55000.00', // 15 000 + 5 000 + 35 000 : le 4x4 n'y entre pas.
        ]);
        expect(a.mentions, isEmpty);
      },
    );

    test(
      'réservations : statut déduit, tarif absent -> « — », annulée exclue',
      () async {
        final a = await lire(conteneur(), 'reservations');

        expect(a.titre, 'État des réservations');
        expect(a.periode, 'Toutes dates');
        expect(libelles(a), serveur.etat('reservations').indicateurs);
        expect(a.entetes, serveur.etat('reservations').entetes);
        final enCours = serveur.langue(
          'etats_m14.reservations.statut.en_cours',
        );
        final terminee = serveur.langue(
          'etats_m14.reservations.statut.terminee',
        );
        expect(a.lignes, [
          // r2 : 3 nuits à 28 000, arrivée aujourd'hui -> en cours.
          [
            'KORA Jean',
            'BNG-01',
            '10/10/2026',
            '13/10/2026',
            '3',
            enCours,
            '84000.00',
            '84000.00',
          ],
          // r4 : 4 nuits = 112 000, acompte 20 000 -> reste 92 000.
          [
            'KORA Jean',
            'BNG-02',
            '08/10/2026',
            '12/10/2026',
            '4',
            enCours,
            '112000.00',
            '92000.00',
          ],
          // r1 : départ le 05/10 -> terminée.
          [
            'KORA Jean',
            'BNG-01',
            '01/10/2026',
            '05/10/2026',
            '4',
            terminee,
            '112000.00',
            '112000.00',
          ],
          // r5 : reprise d'avant le tarif figé -> ni montant ni reste.
          [
            'DOSSOU Awa',
            'BNG-02',
            '01/09/2026',
            '03/09/2026',
            '2',
            terminee,
            '—',
            '—',
          ],
        ]);
        expect(valeurs(a), [
          '4', // r3, annulée, n'y est pas.
          '308000.00', // 84 000 + 112 000 + 112 000, r5 exclue.
          '288000.00', // 84 000 + 92 000 + 112 000.
          '1', // Sans tarif figé.
        ]);
        expect(a.mentions.length, 2);
        expect(a.mentions.last, startsWith('1 réservation(s) sans tarif figé'));
      },
    );

    test(
      'ventes : « Encaissée » à trois valeurs, annulée et panier ouvert exclus',
      () async {
        final a = await lire(conteneur(), 'ventes');

        expect(a.titre, 'État des ventes');
        expect(a.periode, 'Toutes dates');
        expect(libelles(a), serveur.etat('ventes').indicateurs);
        expect(a.entetes, serveur.etat('ventes').entetes);
        final oui = serveur.langue('etats_m14.ventes.encaisse_oui');
        final non = serveur.langue('etats_m14.ventes.encaisse_non');
        expect(a.lignes, [
          // Portée sur la note de chambre : non encaissée, et le dit.
          [
            refVente('v6'),
            '08/10/2026 20:00',
            'Bar principal',
            'KORA Jean',
            'note_chambre',
            non,
            '2000.00',
          ],
          // Aucun mode de règlement : « on ne sait pas », ni Oui ni Non.
          [
            refVente('v5'),
            '07/10/2026 21:00',
            'Bar principal',
            '—',
            '',
            '',
            '1000.00',
          ],
          [
            refVente('v2'),
            '06/10/2026 20:00',
            'Bar principal',
            '—',
            'especes',
            oui,
            '1000.00',
          ],
          [
            refVente('v1'),
            '05/10/2026 19:00',
            'Bar principal',
            '—',
            'especes',
            oui,
            '2000.00',
          ],
          [
            refVente('v3'),
            '03/08/2026 20:00',
            'Bar principal',
            '—',
            'especes',
            oui,
            '5000.00',
          ],
        ]);
        expect(valeurs(a), [
          '5', // v4 (annulée) et v7 (ouverte) n'y sont pas.
          '3 / 5', // v5 (inconnu) et v6 (note de chambre) ne sont pas encaissées.
          '11000.00', // 2 000 + 1 000 + 1 000 + 2 000 + 5 000.
        ]);
        expect(a.mentions.length, 3);
        expect(a.mentions[1], startsWith('1 vente(s) sans mode de règlement'));
        expect(a.mentions[2], startsWith('1 panier(s) encore ouvert(s)'));
      },
    );

    test(
      'dépenses : du plus récent au plus ancien, « Écriture » lue de la pièce',
      () async {
        final a = await lire(conteneur(), 'depenses');

        expect(a.titre, 'État des dépenses');
        expect(libelles(a), serveur.etat('depenses').indicateurs);
        expect(a.entetes, serveur.etat('depenses').entetes);
        expect(a.lignes, [
          [
            '',
            '10/10/2026',
            NatureDepense.transport.libelle,
            'caisse',
            '3000.00',
            'Passée',
          ],
          [
            '',
            '09/10/2026',
            NatureDepense.riz.libelle,
            'caisse',
            '5000.00',
            'Passée',
          ],
          [
            '',
            '01/08/2026',
            NatureDepense.riz.libelle,
            'caisse',
            '99000.00',
            'Passée',
          ],
        ]);
        expect(valeurs(a), ['3', '107000.00']);
        expect(a.mentions.length, 2);
        expect(a.mentions.last, isNot(contains('constaté le')));
        expect(
          a.mentions.last,
          startsWith('Écriture : « Passée » pour chaque'),
        );
      },
    );

    test('dépenses : une dépense d’AVANT la comptabilité se lit « Absente », '
        'jamais « Passée »', () async {
      // Une dépense sans pièce, écrite directement (l'état d'une base d'avant la
      // v16). Les trois autres ont leur pièce.
      await semerDepenseAncienne(db);

      final a = await lire(conteneur(), 'depenses');

      expect(a.nombreLignes, 4);
      final colonne = a.entetes.indexOf('Écriture');
      expect(colonne, 5);
      final cellules = [for (final l in a.lignes) l[colonne]]..sort();
      expect(cellules, ['Absente', 'Passée', 'Passée', 'Passée']);
      final ancienne = a.lignes.firstWhere((l) => l[colonne] == 'Absente');
      expect(ancienne[3], 'caisse');
      expect(ancienne[4], '12000.00');
      expect(a.mentions.last, startsWith('Écriture : « Absente » pour 1 '));
    });

    test('les deux mots de la colonne « Écriture » sont ceux du serveur', () {
      // Relus du fichier de langue du serveur : un mot recopié ici ne
      // vérifierait que lui-même (piège 12).
      final langue = File(
        '../tatacora-api/lang/fr/etats_m14.php',
      ).readAsStringSync();
      expect(langue, contains("'ecriture_passee' => 'Passée'"));
      expect(langue, contains("'ecriture_absente' => 'Absente'"));
    });

    test('achats : « Réglé » et « Reste dû » lus des règlements (D264)', () async {
      final a = await lire(conteneur(), 'achats-fournisseurs');

      expect(a.titre, 'État des achats et dettes fournisseurs');
      expect(libelles(a), serveur.etat('achats-fournisseurs').indicateurs);
      expect(a.entetes, serveur.etat('achats-fournisseurs').entetes);
      // Aucun règlement n'est enregistré : « Réglé » vaut 0.00 (une mesure LUE,
      // pas un tiret) et le reste dû est le montant entier — comme le serveur,
      // dont `montant_regle` vaut 0.00 par défaut.
      expect(a.lignes, [
        // 2 x 2 500,50 F.
        ['SODIS', '05/10/2026', 'envoyee', '5001.00', '0.00', '5001.00'],
        // 10 x 1 000 F.
        ['SODIS', '01/10/2026', 'brouillon', '10000.00', '0.00', '10000.00'],
      ]);
      expect(valeurs(a), ['2', '15001.00', '15001.00']);
      // Le motif « aucun règlement n'est enregistré sur ce poste » est périmé : le
      // serveur ne porte aucune mention sur cet état, le poste non plus.
      expect(a.mentions, isEmpty);
    });

    test('achats : un règlement RÉEL fait baisser le reste dû, et un règlement '
        'annulé ne compte plus', () async {
      await semerAuteurEtReferentiel();
      final commande = (await db.select(db.commandesAchatLocal).get())
          .firstWhere((c) => c.dateCommande == '2026-10-05');
      final reglements = reglementsDaoSur(db, maintenant: maintenant);

      final r = await reglements.regler(
        commandeId: commande.id,
        montantSaisi: '2000.50',
        tresorerieSaisie: 'caisse',
        auteurId: 'u-essai',
      );
      var a = await lire(conteneur(), 'achats-fournisseurs');
      expect(a.lignes.first, [
        'SODIS',
        '05/10/2026',
        'envoyee',
        '5001.00',
        '2000.50',
        '3000.50',
      ]);
      // La seconde commande n'est pas touchée.
      expect(a.lignes.last.sublist(4), ['0.00', '10000.00']);
      expect(valeurs(a), ['2', '15001.00', '13000.50']);

      await reglements.annuler(r.id, 'Erreur de saisie', auteurId: 'u-essai');
      a = await lire(conteneur(), 'achats-fournisseurs');
      expect(a.lignes.first.sublist(4), ['0.00', '5001.00']);
      expect(valeurs(a).last, '15001.00');
    });

    test(
      'locations : le véhicule se lit « catégorie — immatriculation »',
      () async {
        final a = await lire(conteneur(), 'locations-vehicules');

        expect(a.titre, 'État des locations de véhicules');
        expect(libelles(a), serveur.etat('locations-vehicules').indicateurs);
        expect(a.entetes, serveur.etat('locations-vehicules').entetes);
        expect(a.lignes, [
          [
            'KORA Jean',
            'voiture — AB-123-BJ',
            '05/10/2026',
            '08/10/2026',
            '3',
            '105000.00',
          ],
          [
            'DOSSOU Awa',
            'moto — EF-789-BJ',
            '01/10/2026',
            '02/10/2026',
            '1',
            '15000.00',
          ],
        ]);
        expect(valeurs(a), ['2', '120000.00']);
        // v41 : le montant est le montant FIGÉ du contrat ; aucune mention tant
        // que chaque contrat en a un.
        expect(a.mentions, isEmpty);
      },
    );

    test(
      'tourisme : la réservation annulée est exclue, les dates futures non',
      () async {
        final a = await lire(conteneur(), 'tourisme');

        expect(a.titre, 'État des réservations de circuits');
        expect(libelles(a), serveur.etat('tourisme').indicateurs);
        expect(a.entetes, serveur.etat('tourisme').entetes);
        expect(a.lignes, [
          [
            'Pendjari',
            'DOSSOU Awa',
            'Koffi',
            '20/10/2026',
            '2',
            'reservee',
            '50000.00',
          ],
          [
            'Cascades de Tanougou',
            'KORA Jean',
            'Koffi',
            '12/10/2026',
            '4',
            'reservee',
            '60000.00',
          ],
        ]);
        expect(valeurs(a), [
          '2', // La troisième, annulée, n'y est pas.
          '6', // 2 + 4 : les 3 de l'annulée ne comptent pas.
          '110000.00', // 50 000 + 60 000.
        ]);
        expect(a.mentions.single, contains('prix actuel du circuit'));
      },
    );

    test('paie : le bulletin établi, le net lu du bulletin', () async {
      final a = await lire(conteneur(), 'paie-effectif');

      expect(a.titre, 'État Paie & Effectif');
      expect(a.periode, 'Période 2026-10');
      expect(libelles(a), serveur.etat('paie-effectif').indicateurs);
      expect(a.entetes, serveur.etat('paie-effectif').entetes);
      String m(String nom) => jeu.employes[nom]!.matricule;
      expect(a.lignes, [
        [
          'AGBO X',
          m('AGBO'),
          'Poste',
          'Administration',
          '01/01/2024',
          'conge',
          '150000.00',
        ],
        [
          'DOSSOU X',
          m('DOSSOU'),
          'Poste',
          'Administration',
          '01/01/2024',
          'actif',
          '150000.00',
        ],
        [
          'KORA X',
          m('KORA'),
          'Poste',
          'Administration',
          '01/01/2024',
          'actif',
          '150000.00',
        ],
        [
          'MENSAH X',
          m('MENSAH'),
          'Poste',
          'Administration',
          '01/01/2024',
          'suspendu',
          '150000.00',
        ],
        [
          'ZINSOU X',
          m('ZINSOU'),
          'Poste',
          'Administration',
          '01/01/2024',
          'parti',
          '150000.00',
        ],
      ]);
      expect(valeurs(a), [
        '5', // Effectif total : tous les statuts.
        '2', // Actifs : KORA et DOSSOU — les trois autres ne le sont pas.
        '${jeu.bulletinKora.brut}.00',
        '${jeu.bulletinKora.netAPayer}.00',
        '1',
      ]);
      expect(a.mentions, isEmpty);
    });

    test('créances clients : CALCULÉES depuis le lot 5 (12/10/2026), le solde '
        'est celui de l\'écran Clients & Créances', () async {
      final client = await creerClient(db, nom: 'AGBO', telephone: '97555555');
      final facture = await emettreFacture(
        db,
        montant: 40000,
        clientId: client.id,
        horloge: DateTime(2026, 9, 20, 9),
      );
      await paiementsDaoSur(db, horloge: DateTime(2026, 10, 2, 10)).encaisser(
        pieceId: facture.id,
        montant: '15000',
        mode: 'especes',
        auteurId: caissierEssai,
      );

      final a = await lire(conteneur(), 'creances-clients');

      expect(a.titre, 'État des créances clients');
      expect(a.periode, 'Arrêté au 10/10/2026 à 14:30');
      expect(a.moduleSource, 'M3');
      expect(
        libelles(a),
        serveur.etat('creances-clients').indicateurs,
        reason: 'les libellés sont ceux du serveur, « (maximum) » compris',
      );
      expect(a.entetes, serveur.etat('creances-clients').entetes);
      expect(valeurs(a), ['1', '1', '25000.00']);
      // Le type est la valeur BRUTE du registre (« particulier »), comme au
      // serveur — pas le libellé de l'écran (« Particulier »).
      expect(a.lignes, [
        ['AGBO', '97555555', 'particulier', '1', '25000.00'],
      ]);
      expect(a.mentions, isEmpty);
    });

    test(
      'créances clients : un client sans dette n\'est PAS une ligne',
      () async {
        await creerClient(db, nom: 'AGBO', telephone: '97555555');
        final a = await lire(conteneur(), 'creances-clients');
        expect(valeurs(a), ['0', '0', '0.00']);
        expect(a.lignes, isEmpty);
      },
    );

    test('balance : CALCULÉE sur ce poste, aux mots du serveur', () async {
      final a = await lire(conteneur(), 'balance');

      expect(a.titre, startsWith('Balance générale — Exercice '));
      expect(a.moduleSource, 'M10');
      expect(a.periode, matches(RegExp(r'^Du 01/01/\d{4} au 31/12/\d{4}$')));
      expect(libelles(a), serveur.etat('balance').indicateurs);
      expect(a.entetes, serveur.etat('balance').entetes);
      // Les deux égalités tiennent : une pièce équilibrée par construction.
      expect(valeurs(a).last, 'Oui');
      final debit = valeurs(a)[1];
      final credit = valeurs(a)[2];
      expect(debit, credit);
      expect(a.lignes.length, int.parse(valeurs(a).first));
      expect(a.mentions, contains('Écritures validées seulement.'));
    });
  });

  group('Le droit est revérifié sur la donnée, pas seulement sur le menu', () {
    test(
      'un code tapé à la main ne contourne pas le droit du module source',
      () async {
        final c = conteneur(droits: {'M14': 'C'});
        final r = await refuse(c, 'stocks');
        expect(r.motif, EtatsApi.refusModuleSource);
        expect(r.moduleSource, 'M6');
      },
    );

    test(
      'un code hors du registre fermé est refusé, sans état par défaut',
      () async {
        final r = await refuse(conteneur(), 'inconnu');
        expect(r.motif, EtatsApi.refusCodeInconnu);
        expect(r.titre, isNull);
      },
    );

    test('L suffit pour lire : l’aperçu ne modifie rien', () async {
      final c = conteneur(droits: {'M6': 'L'});
      final a = await lire(c, 'stocks');
      expect(a.nombreLignes, 5);
    });
  });

  group('Aucun cache : chaque lecture relit les modules (PA-120)', () {
    test(
      'une dépense saisie entre deux lectures figure dans la seconde',
      () async {
        final c = conteneur();
        expect((await lire(c, 'depenses')).nombreLignes, 3);

        await (await depenseDaoPrepare(db, maintenant)).enregistrer(
          dateTransaction: DateTime(2026, 10, 10),
          tresorerie: TresorerieDepense.caisse,
          libelle: 'Gaz',
          auteurId: auteurDepense,
          centreId: await centreDe(db, 'Restaurant'),
          lignes: [
            const SaisieLigneDepense(
              libelle: 'Gaz',
              compteCharge: '6011',
              nature: NatureDepense.transport,
              montant: 7000,
            ),
          ],
        );

        // Un NOUVEAU conteneur n'est pas requis : le fournisseur est autoDispose.
        final apres = await lire(conteneur(), 'depenses');
        expect(apres.nombreLignes, 4);
        expect(valeurs(apres), ['4', '114000.00']);
      },
    );

    test('l’aperçu est autoDispose : on le relit à chaque sélection', () async {
      final c = conteneur();
      final sub = c.listen(apercuEtatProvider('depenses'), (_, _) {});
      await c.read(apercuEtatProvider('depenses').future);
      sub.close();
      await Future<void>.delayed(Duration.zero);

      await (await depenseDaoPrepare(db, maintenant)).enregistrer(
        dateTransaction: DateTime(2026, 10, 10),
        tresorerie: TresorerieDepense.caisse,
        libelle: 'Gaz',
        auteurId: auteurDepense,
        centreId: await centreDe(db, 'Restaurant'),
        lignes: [
          const SaisieLigneDepense(
            libelle: 'Gaz',
            compteCharge: '6011',
            nature: NatureDepense.transport,
            montant: 7000,
          ),
        ],
      );
      // Même conteneur : si la réponse avait été gardée, on lirait 3.
      expect((await lire(c, 'depenses')).nombreLignes, 4);
    });
  });

  group('Un état est la liste ENTIÈRE, jamais une page', () {
    test('205 commandes d’achat : aucune n’est tronquée à 200', () async {
      final achats = AchatsDao(db, stocks: StocksDao(db));
      for (var i = 0; i < 203; i++) {
        await achats.creerCommande(
          SaisieCommande(
            fournisseurId: 'f-1',
            dateCommande: '2026-09-01',
            statut: StatutCommande.brouillon,
            lignes: const [
              LigneSaisieCommande(
                articleId: 'riz',
                libelle: 'Riz',
                uniteMesure: 'sac',
                quantite: '1.00',
                prixUnitaire: '100.00',
              ),
            ],
          ),
          auteurId: 'u-essai',
        );
      }
      final a = await lire(conteneur(), 'achats-fournisseurs');
      expect(a.nombreLignes, 205);
      expect(valeurs(a).first, '205');
      // 15 001 + 203 x 100.
      expect(valeurs(a)[1], '35301.00');
    });
  });

  group(
    'Un poste neuf : des mesures, jamais un zéro qui se fait passer pour un chiffre',
    () {
      late AppDatabase vide;

      setUp(() => vide = AppDatabase.enMemoire());
      tearDown(() => vide.close());

      Future<ApercuEtat> sur(String code) async {
        final c = ProviderContainer(
          overrides: [
            baseLocaleProvider.overrideWithValue(vide),
            droitsProvider.overrideWithValue(const GardeAcces(tous)),
            horlogeEtatsProvider.overrideWithValue(() => maintenant),
            horlogeTableauDeBordProvider.overrideWithValue(() => maintenant),
          ],
        );
        addTearDown(c.dispose);
        return lire(c, code);
      }

      test(
        'les dix états se calculent sur une base vide, sans ligne',
        () async {
          for (final e in EtatLocal.values.where(
            (e) => e.estCalculable && e != EtatLocal.balance,
          )) {
            final a = await sur(e.code);
            // Le tableau de bord rend huit lignes d'indicateurs, pas des
            // enregistrements : il n'est pas une liste de la base.
            if (e != EtatLocal.tableauDeBord) {
              expect(a.estVide, isTrue, reason: e.code);
            }
            expect(a.titre, e.libelle, reason: e.code);
          }
        },
      );

      test(
        'les comptages sont des mesures : « 0 » veut dire « lu, et vide »',
        () async {
          expect(valeurs(await sur('depenses')), ['0', '0.00']);
          expect(valeurs(await sur('ventes')), ['0', '0 / 0', '0.00']);
          expect(valeurs(await sur('tourisme')), ['0', '0', '0.00']);
          expect(valeurs(await sur('locations-vehicules')), ['0', '0.00']);
          // Trois indicateurs seulement : « Sans tarif figé » n'existe que s'il y a
          // une réservation sans tarif.
          expect(valeurs(await sur('reservations')), ['0', '0.00', '0.00']);
          expect(valeurs(await sur('stocks')), ['0', '0', '0.00']);
        },
      );

      test(
        'sans bulletin, la masse salariale et le net se lisent « — »',
        () async {
          final a = await sur('paie-effectif');
          expect(valeurs(a), ['0', '0', '', '', '0']);
          expect(
            a.mentions.single,
            startsWith('Aucun bulletin établi pour la période 2026-10'),
          );
        },
      );

      test('sans parc, le taux d’occupation n’est pas « 0 % »', () async {
        final a = await sur('tableau-de-bord');
        expect(a.indicateur("Taux d'occupation (nuitées)"), '');
      });
    },
  );

  group('L’écran, sur la chaîne réelle', () {
    Future<void> monter(
      WidgetTester tester, {
      Map<String, String> droits = tous,
    }) async {
      tester.view
        ..physicalSize = const Size(1600, 1200)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: surcharges(droits),
          child: MaterialApp(
            theme: AppTheme.clair,
            home: const Scaffold(body: EcranEtats()),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    String texte(WidgetTester tester, Key cle) {
      final w = tester.widget<Text>(find.byKey(cle));
      return w.data ?? w.textSpan!.toPlainText();
    }

    testWidgets('le compteur et les groupes viennent des droits', (
      tester,
    ) async {
      await monter(tester);
      expect(
        texte(tester, const Key('etats-compteur')),
        '12 état(s) · droits portés par le module source',
      );
      expect(find.byKey(const Key('etats-entree-balance')), findsOne);
    });

    testWidgets('sans M6, l’état des stocks n’est pas au catalogue', (
      tester,
    ) async {
      await monter(tester, droits: {...tous, 'M6': '-'});
      expect(find.byKey(const Key('etats-entree-stocks')), findsNothing);
      expect(
        texte(tester, const Key('etats-compteur')),
        '11 état(s) · droits portés par le module source',
      );
    });

    testWidgets('choisir les stocks affiche le tableau calculé', (
      tester,
    ) async {
      await monter(tester);
      await tester.tap(find.byKey(const Key('etats-entree-stocks')));
      await tester.pumpAndSettle();

      expect(
        texte(tester, const Key('etats-apercu-sous-ligne')),
        'Arrêté au 10/10/2026 à 14:30 · module source M6 · 5 ligne(s)',
      );
      expect(texte(tester, const Key('etats-cellule-0-0')), 'Farine');
      expect(texte(tester, const Key('etats-cellule-1-6')), '1000.00');
      // Une valeur inconnue, un « — » et non « 0 ».
      expect(texte(tester, const Key('etats-cellule-4-6')), '—');
      expect(
        texte(
          tester,
          const Key('etats-indicateur-valeur-Valeur du stock (CMP)'),
        ),
        '13505.00 (hors 1 article(s) sans coût)',
      );
      expect(find.text('ARTICLE'), findsOne);
      // L'encadré des mentions est retiré de l'écran (directive du PO,
      // 14/10/2026) ; elles restent dans `ApercuEtat.mentions` (testé plus haut).
      expect(find.byKey(const Key('etats-mention-0')), findsNothing);
    });

    testWidgets('choisir les ventes affiche « Oui », « Non » et « — »', (
      tester,
    ) async {
      await monter(tester);
      await tester.tap(find.byKey(const Key('etats-entree-ventes')));
      await tester.pumpAndSettle();

      expect(texte(tester, const Key('etats-cellule-0-5')), 'Non');
      expect(texte(tester, const Key('etats-cellule-1-5')), '—');
      expect(texte(tester, const Key('etats-cellule-2-5')), 'Oui');
      expect(
        texte(tester, const Key('etats-indicateur-valeur-Encaissées')),
        '3 / 5',
      );
    });

    testWidgets('la balance générale est CALCULÉE : l’exercice, ses lignes', (
      tester,
    ) async {
      await monter(tester);
      await tester.tap(find.byKey(const Key('etats-entree-balance')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('etats-apercu-refuse')), findsNothing);
      expect(find.byType(Table), findsWidgets);
      expect(
        texte(tester, const Key('etats-apercu-sous-ligne')),
        startsWith('Du 01/01/'),
      );
    });
  });
}
