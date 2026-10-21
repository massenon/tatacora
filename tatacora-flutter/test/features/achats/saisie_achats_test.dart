import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/impression/visas.dart';
import 'package:tatacora_flutter/features/achats/domain/decimal_texte.dart';
import 'package:tatacora_flutter/features/achats/domain/entities/bon_reception.dart';
import 'package:tatacora_flutter/features/achats/domain/entities/commande_achat.dart';
import 'package:tatacora_flutter/features/achats/impression/etat_liste_achats.dart';

/// Le domaine de M7 : l'arithmétique en chaînes, et les deux saisies.
///
/// ## Ce que ces cas protègent
///
/// **Qu'aucun montant ne passe par un `double`.** Le montant d'une commande
/// valorise l'entrée de stock à la réception, donc recalcule le coût moyen
/// pondéré, donc alimente le poste de stocks au bilan. Un centime perdu à
/// l'arrondi s'y retrouve.
///
/// **Qu'un article ne puisse pas figurer deux fois.** C'est le défaut le plus
/// coûteux du module : `ReceptionService::evaluerConformite()` relit les
/// quantités par `pluck('quantite_commandee', 'article_id')`, et la seconde
/// ligne écrase la première. Une commande de 30 + 20 sacs serait contrôlée
/// contre 20, une livraison de 50 déclarée en excédent hors tolérance, donc
/// `non_conforme` — et la commande deviendrait inclôturable.
void main() {
  /* ================================================================== */
  group('L’arithmétique décimale, sans `double`', () {
    test('la soustraction est exacte au centième', () {
      expect(soustraire('10.00', '4.50'), '5.50');
      expect(soustraire('10', '10'), '0.00');
      // Un manque NÉGATIF garde son signe : un excédent n'est pas un manque
      // nul, et l'écran doit pouvoir le montrer.
      expect(soustraire('4.00', '10.00'), '-6.00');
    });

    test('« 12.5 » vaut douze et DEMI, pas douze et cinq centièmes', () {
      // Le piège du remplissage : `padLeft` au lieu de `padRight` diviserait la
      // partie décimale par dix, en silence, sur toutes les quantités saisies
      // avec une seule décimale.
      expect(enCentiemes('12.5'), 1250);
      expect(enCentiemes('12.05'), 1205);
      expect(soustraire('12.5', '0.5'), '12.00');
    });

    test('la virgule française est acceptée', () {
      // Au Gîte on tape « 12,5 ». La refuser localement serait refuser une
      // écriture correcte en français ; l'envoyer telle quelle ferait rendre au
      // serveur un 422 incompréhensible sur une saisie qui paraît juste.
      expect(enCentiemes('12,5'), 1250);
      expect(soustraire('12,5', '2,5'), '10.00');
    });

    test('le produit est tronqué au centième, comme `bcmul` du serveur', () {
      expect(multiplier('10', '29000'), '290000.00');
      expect(multiplier('2.50', '3.33'), '8.32');
      expect(multiplier('0', '29000'), '0.00');
    });

    test('l’addition ne dérive pas sur un cumul', () {
      // Le cas qui perd un `double` : 0,1 + 0,2 y vaut 0,30000000000000004.
      var total = '0.00';
      for (var i = 0; i < 3; i++) {
        total = additionner(total, '0.10')!;
      }
      expect(total, '0.30');
    });

    test('une entrée illisible rend `null`, JAMAIS zéro', () {
      // « on ne sait pas » n'est pas « il n'y a rien ». Les confondre
      // afficherait « manque 0 » sur un article dont on ignore le stock, sur
      // l'écran où l'on décide de commander.
      expect(enCentiemes('abc'), isNull);
      expect(enCentiemes(''), isNull);
      // Trois décimales : le schéma en porte deux (`decimal:0,2`). Les
      // accepter ferait refuser en 422 une saisie que l'écran vient
      // d'accepter.
      expect(enCentiemes('1.234'), isNull);
      expect(soustraire('10.00', 'abc'), isNull);
      expect(multiplier('abc', '2'), isNull);
      expect(comparer('abc', '2'), isNull);
      expect(estStrictementPositif('abc'), isFalse);
    });

    test(
      'la quantité suggérée est celle du maître : max(1, ceil(2×seuil − stock))',
      () {
        // Le maître écrit lui-même sa raison : remonter au DOUBLE du seuil, pas
        // au seuil pile — recommander à l'exact ferait repasser sous alerte à la
        // première sortie.
        expect(quantiteSuggeree(seuilAlerte: '10', stock: '4'), '16');
        // Plafond entier : on ne commande pas 15,5 sacs.
        expect(quantiteSuggeree(seuilAlerte: '10.00', stock: '4.50'), '16');
        expect(quantiteSuggeree(seuilAlerte: '10.00', stock: '4.01'), '16');
        // Plancher de 1 : un stock déjà supérieur au double du seuil ne propose
        // jamais zéro, ce qui reviendrait à décocher la ligne en silence.
        expect(quantiteSuggeree(seuilAlerte: '5', stock: '100'), '1');
        // Illisible : `null`, et le champ reste vide plutôt que d'afficher un
        // « 1 » qui passerait pour une mesure.
        expect(quantiteSuggeree(seuilAlerte: 'x', stock: '4'), isNull);
      },
    );
  });

  /* ================================================================== */
  group('La saisie d’une commande', () {
    LigneSaisieCommande ligne({
      required String id,
      String libelle = 'Riz local',
      String quantite = '10',
      String prix = '29000',
    }) => LigneSaisieCommande(
      articleId: id,
      libelle: libelle,
      uniteMesure: 'sac',
      quantite: quantite,
      prixUnitaire: prix,
    );

    SaisieCommande saisie(List<LigneSaisieCommande> lignes) => SaisieCommande(
      fournisseurId: 'f-1',
      dateCommande: '2026-08-26',
      statut: StatutCommande.brouillon,
      lignes: lignes,
    );

    test('un même article DEUX FOIS est refusé, avec la raison', () {
      final refus = saisie([
        ligne(id: 'a-1', libelle: 'Riz local'),
        ligne(id: 'a-2', libelle: 'Sucre'),
        ligne(id: 'a-1', libelle: 'Riz local'),
      ]).erreurArticlesEnDouble;

      expect(refus, isNotNull);
      // Le refus NOMME l'article. Le serveur, lui, désigne un index de ligne
      // (`lignes.2.article_id`) que l'utilisateur ne peut pas relier à ce qu'il
      // voit.
      expect(refus, contains('Riz local'));
      expect(refus, contains('écraserait la première'));
    });

    test('deux articles DIFFÉRENTS passent', () {
      expect(
        saisie([ligne(id: 'a-1'), ligne(id: 'a-2')]).erreurArticlesEnDouble,
        isNull,
      );
    });

    test('le total se somme ligne à ligne, en chaînes', () {
      final s = saisie([
        ligne(id: 'a-1', quantite: '10', prix: '29000'),
        ligne(id: 'a-2', quantite: '2.50', prix: '1200'),
      ]);

      expect(s.montantTotal, '293000.00');
      expect(s.lignes.first.montant, '290000.00');
    });

    test('une ligne illisible rend le total NUL, pas amputé', () {
      // Mieux vaut ne rien afficher qu'un total amputé d'une ligne : il se lit
      // exactement comme un total juste.
      final s = saisie([
        ligne(id: 'a-1', quantite: '10', prix: '29000'),
        ligne(id: 'a-2', quantite: '2', prix: ''),
      ]);

      expect(s.montantTotal, isNull);
    });

    test('le corps envoyé porte le statut et les trois champs de ligne', () {
      final corps = saisie([ligne(id: 'a-1')]).versJson();

      expect(corps['fournisseur_id'], 'f-1');
      expect(corps['date_commande'], '2026-08-26');
      expect(corps['statut'], 'brouillon');

      final l = (corps['lignes'] as List).single as Map<String, dynamic>;
      expect(l.keys.toSet(), {
        'article_id',
        'quantite_commandee',
        'prix_unitaire',
      });
      // Le libellé n'est PAS envoyé : le serveur relit `articles`. L'envoyer
      // laisserait croire qu'on fige le nom sur la commande, ce que le schéma
      // ne fait pas.
      expect(l.containsKey('libelle'), isFalse);
    });
  });

  /* ================================================================== */
  group('La saisie d’une réception', () {
    LigneSaisieReception ligne({
      required String id,
      String libelle = 'Riz local',
      required String recue,
    }) => LigneSaisieReception(
      articleId: id,
      libelle: libelle,
      uniteMesure: 'sac',
      quantiteCommandee: '10.00',
      quantiteDejaRecue: '0.00',
      quantiteRecue: recue,
    );

    SaisieReception saisie(List<LigneSaisieReception> lignes) =>
        SaisieReception(
          commandeId: 'c-1',
          pointStockageId: 'p-1',
          dateReception: null,
          lignes: lignes,
        );

    test('une quantité à ZÉRO est OMISE, jamais déclarée', () {
      // `gt:0` côté serveur. Le service ignorerait une ligne à zéro pour le
      // mouvement de stock mais la compterait dans le verdict de conformité :
      // deux comportements pour une même saisie. L'absence de l'article vaut
      // déjà « rien reçu » pour RG-10.
      final s = saisie([
        ligne(id: 'a-1', recue: '10'),
        ligne(id: 'a-2', recue: '0'),
        ligne(id: 'a-3', recue: ''),
      ]);

      expect(s.lignesRetenues.map((l) => l.articleId), ['a-1']);

      final envoyees = (s.versJson()['lignes'] as List)
          .cast<Map<String, dynamic>>();
      expect(envoyees, hasLength(1));
      expect(envoyees.single['article_id'], 'a-1');
      expect(envoyees.single['quantite_recue'], '10');
    });

    test('une réception SANS aucune ligne positive est refusée', () {
      final refus = saisie([
        ligne(id: 'a-1', recue: '0'),
        ligne(id: 'a-2', recue: '0,00'),
      ]).erreur;

      expect(refus, isNotNull);
      expect(refus, contains('au moins un article'));
    });

    test('un même article DEUX FOIS est refusé, avec la raison', () {
      final refus = saisie([
        ligne(id: 'a-1', libelle: 'Riz local', recue: '4'),
        ligne(id: 'a-1', libelle: 'Riz local', recue: '6'),
      ]).erreur;

      expect(refus, isNotNull);
      expect(refus, contains('Riz local'));
      expect(refus, contains('écraserait la première'));
    });

    test('une réception normale ne porte AUCUNE erreur', () {
      expect(saisie([ligne(id: 'a-1', recue: '10')]).erreur, isNull);
    });

    test('la date n’est PAS envoyée quand elle est absente', () {
      // `null` laisse le serveur dater du jour. Une date posée sur l'horloge du
      // poste divergerait de celle du serveur sur un poste mal réglé, et c'est
      // elle qui situe l'entrée de stock.
      final corps = saisie([ligne(id: 'a-1', recue: '10')]).versJson();
      expect(corps.containsKey('date_reception'), isFalse);
      expect(corps['point_stockage_id'], 'p-1');
    });
  });

  /* ================================================================== */
  group('Ce que le serveur DÉRIVE n’est jamais recalculé ici', () {
    CommandeAchat commande({
      required String statut,
      required bool receptionnable,
      required bool cloturable,
    }) => CommandeAchat(
      id: 'c-1',
      dateCommande: '2026-08-26',
      statutCode: statut,
      fournisseurId: 'f-1',
      fournisseurRaisonSociale: 'SODIS Bénin',
      nombreLignes: 2,
      montantTotal: '185000.00',
      montantRegle: '0.00',
      resteDu: '185000.00',
      receptionnable: receptionnable,
      cloturable: cloturable,
    );

    test('« réceptionnable » et « clôturable » viennent du serveur', () {
      // Deux lectures indépendantes finiraient par diverger, et l'écran
      // proposerait un bouton que le serveur refuse — ou masquerait une action
      // permise. Une commande CLÔTURÉE reste non réceptionnable même si son
      // statut était mal lu.
      final cloturee = commande(
        statut: 'cloturee',
        receptionnable: false,
        cloturable: false,
      );
      expect(cloturee.receptionnable, isFalse);
      expect(cloturee.cloturable, isFalse);

      final recue = commande(
        statut: 'receptionnee',
        receptionnable: true,
        cloturable: true,
      );
      expect(recue.cloturable, isTrue);
    });

    test('« envoyable » reprend la règle du service, mot pour mot', () {
      // `CommandeAchatService::envoyer` refuse tout ce qui n'est pas
      // `brouillon` : sans ce bouton, `brouillon` serait un état SANS SORTIE.
      expect(
        commande(
          statut: 'brouillon',
          receptionnable: true,
          cloturable: false,
        ).envoyable,
        isTrue,
      );
      for (final autre in const [
        'envoyee',
        'receptionnee',
        'receptionnee_partiellement',
        'cloturee',
      ]) {
        expect(
          commande(
            statut: autre,
            receptionnable: true,
            cloturable: false,
          ).envoyable,
          isFalse,
          reason: 'un bon parti chez le fournisseur ne se dé-envoie pas',
        );
      }
    });

    test('un statut INCONNU affiche son code brut, pas un libellé', () {
      final inconnue = commande(
        statut: 'annulee',
        receptionnable: false,
        cloturable: false,
      );

      expect(inconnue.statut, isNull);
      // PA-185 : un seul registre, donc un seul accesseur — l'ancien
      // `libelleStatutApprovisionnement` n'existe plus.
      expect(inconnue.libelleStatut, 'annulee');
      expect(inconnue.envoyable, isFalse);
    });
  });

  /* ================================================================== */
  group('Un export DIT sa portée, et refuse le vide', () {
    ListeAchats liste({int rapportees = 2, int total = 2}) => ListeAchats(
      titre: 'Bons de commande fournisseurs',
      visas: Visas.achats,
      portee: Portee(
        filtre: 'Statut : Envoyée',
        lignesRapportees: rapportees,
        totalServeur: total,
      ),
      entetes: const ['Référence', 'Montant'],
      colonnesNumeriques: const {1},
      lignes: List.generate(rapportees, (i) => ['cmd-$i', '185000.00']),
    );

    test('une page PARTIELLE le dit, en toutes lettres', () {
      // Un document qui montrerait 50 commandes sur 213 sans le dire serait lu
      // comme le registre entier, et quelqu'un déciderait d'un règlement
      // fournisseur sur cette base.
      final partielle = liste(rapportees: 50, total: 213);

      expect(partielle.portee.estTronquee, isTrue);
      expect(partielle.portee.mention, contains('sur 213'));
      expect(
        partielle.portee.mention,
        contains('NE PORTE PAS SUR LE REGISTRE ENTIER'),
      );
    });

    test('une liste COMPLÈTE n’annonce aucune troncature', () {
      // La mention alarmante ne doit apparaître que quand elle est vraie :
      // sinon on cesse de la lire.
      final complete = liste();

      expect(complete.portee.estTronquee, isFalse);
      expect(complete.portee.mention, isNot(contains('NE PORTE PAS')));
      expect(complete.portee.mention, contains('Statut : Envoyée'));
    });

    test('le CSV porte le BOM, le point-virgule, et la portée', () {
      final csv = csvListeAchats(liste());

      expect(csv.codeUnitAt(0), 0xFEFF, reason: 'BOM UTF-8 attendu (RG-19)');
      expect(csv, contains('Référence;Montant'));
      // Le montant part en NOMBRE BRUT : un tableur ne sait pas additionner
      // « 185 000 FCFA ».
      expect(csv, contains('cmd-0;185000.00'));
      expect(csv, contains('Statut : Envoyée'));
    });

    test('un point-virgule dans une cellule ne DÉCALE pas les colonnes', () {
      final avecSeparateur = ListeAchats(
        titre: 'x',
        visas: Visas.achats,
        portee: const Portee(
          filtre: 'Aucun filtre',
          lignesRapportees: 1,
          totalServeur: 1,
        ),
        entetes: const ['Fournisseur', 'Contact'],
        lignes: const [
          ['SODIS ; Bénin', '01 90 12 34 56'],
        ],
      );

      // Le point-virgule de la cellule est ramene a une virgule : le laisser
      // decalerait toutes les colonnes suivantes, en silence, et le fichier
      // paraitrait valide a l'ouverture.
      expect(
        csvListeAchats(avecSeparateur),
        contains('SODIS , Bénin;01 90 12 34 56'),
      );
    });

    test('une liste vide se reconnaît, et son refus dit POURQUOI', () {
      expect(liste(rapportees: 0, total: 0).estVide, isTrue);
      expect(liste().estVide, isFalse);
      // Le mot du maître : une page blanche se lirait comme « aucun élément ».
      expect(messageExportVide, contains('le filtre n’a rien retenu'));
    });
  });

  group('arrondirAuCentieme — le prix unitaire PRÉ-REMPLI du bon', () {
    test('arrondit au centième, demi vers le haut, sur les chiffres', () {
      expect(arrondirAuCentieme('1250.4349'), '1250.43');
      expect(arrondirAuCentieme('1250.435'), '1250.44');
      expect(arrondirAuCentieme('2500'), '2500.00');
      expect(arrondirAuCentieme('0.005'), '0.01');
    });

    test('illisible ou nul : null, jamais un zéro inventé', () {
      expect(arrondirAuCentieme(''), isNull);
      expect(arrondirAuCentieme('abc'), isNull);
      expect(arrondirAuCentieme('-3'), isNull);
      expect(arrondirAuCentieme('0.004'), isNull);
    });
  });
}
