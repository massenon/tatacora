@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/stocks/data/stocks_api.dart';
import 'package:tatacora_flutter/features/stocks/data/stocks_dao.dart';
import 'package:tatacora_flutter/features/stocks/domain/calcul_inventaire.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/etat_stock.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/mouvement_stock.dart';
import 'package:tatacora_flutter/features/stocks/domain/messages_stock.dart';

import '../comptabilite/support/outils_comptabilite.dart';
import 'support/scenario_file.dart';

/// L'ANCRAGE EXTÉRIEUR de l'inventaire physique et de l'archivage d'un article
/// (21/10/2026, piège 12) : ce que les VRAIS écrivains du poste enfilent est
/// poussé TEL QUEL au vrai moteur de synchronisation du serveur
/// (`tool/sync/valider_charge.php` -> `SynchronisationService::traiterLot`),
/// puis relu. Un document hors contrat rend `rejete` avec la phrase du serveur.
///
/// Mutations éprouvées : un écart qui n'est pas `constaté − théorique`, un
/// constaté envoyé en unités (au lieu de centièmes), un manquant envoyé en
/// `inventaire`, ou un archivage envoyé sans `actif` font rougir ce fichier.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late List<Map<String, Object?>> operations;
  late List<Map<String, dynamic>> resultats;
  late Map<String, dynamic> etats;
  late String inventaireId;
  late String sel; // l'article archivé
  late String plein; // l'article engagé, dont l'archivage est refusé

  setUpAll(() async {
    final db = AppDatabase.enMemoire();
    await db
        .into(db.utilisateursLocal)
        .insert(
          UtilisateursLocalCompanion.insert(
            id: 'u-1',
            login: 'admin',
            nom: 'Aïcha',
            role: 'administrateur',
            droitsJson: '{}',
            sel: 's',
            empreinte: 'e',
            iterations: 1,
            dateCreation: DateTime(2026, 10, 1),
            dateMotDePasse: DateTime(2026, 10, 1),
          ),
        );
    final dao = StocksDao(db, maintenant: () => DateTime(2026, 10, 12, 9));
    final api = StocksApi(
      dao: dao,
      peutLire: () => true,
      peutEcrire: () => true,
      auteurId: () => 'u-1',
    );

    final magasin =
        ((await api.creerPoint(libelle: 'Magasin')) as PointEnregistre)
            .point
            .id;
    Future<void> article(String id, String libelle) async {
      final r = await api.enregistrerArticle(
        SaisieArticle(
          id: id,
          libelle: libelle,
          categorie: 'Denrées',
          uniteMesure: 'sac',
          seuilAlerte: '5',
          suivi: SuiviArticle.permanent,
          pointStockageId: magasin,
        ),
      );
      expect(r, isA<ArticleEnregistre>(), reason: '$r');
    }

    await article(const Uuid4Essai('riz').valeur, 'Riz local');
    await article(const Uuid4Essai('huile').valeur, 'Huile');
    await article(const Uuid4Essai('sel').valeur, 'Sel');
    await article(const Uuid4Essai('plein').valeur, 'Farine');
    final riz = const Uuid4Essai('riz').valeur;
    final huile = const Uuid4Essai('huile').valeur;
    sel = const Uuid4Essai('sel').valeur;
    plein = const Uuid4Essai('plein').valeur;

    Future<void> entree(String id, String quantite, {String? cout}) async {
      final r = await api.enregistrerMouvement(
        SaisieMouvement(
          articleId: id,
          pointId: magasin,
          type: TypeMouvement.entree,
          quantite: quantite,
          motif: 'Ouverture',
          coutUnitaire: cout,
        ),
      );
      expect(r, isA<MouvementEnregistre>(), reason: '$r');
    }

    await entree(riz, '10', cout: '1250');
    await entree(huile, '4');
    await entree(plein, '3');

    // L'inventaire : +2 de riz, −1 d'huile, la farine non comptée (partiel).
    final bilan = await dao.cloturerInventaire(
      pointId: magasin,
      date: DateTime(2026, 10, 12),
      comptages: {
        riz: const ComptageBrouillon(
          theoriqueCentiemes: 1000,
          constateCentiemes: 1200,
        ),
        huile: const ComptageBrouillon(
          theoriqueCentiemes: 400,
          constateCentiemes: 300,
        ),
      },
      auteurId: 'u-1',
      partielAutorise: true,
    );
    inventaireId = bilan.inventaireId;

    // L'archivage : le sel est libre, la farine a du stock (le serveur REFUSE).
    await dao.archiverArticle(sel);
    await db.customStatement(
      'UPDATE articles_local SET actif = 1 WHERE id = ?',
      [plein],
    );
    // Le poste a refusé l'archivage de la farine (du stock) : on enfile quand
    // même la demande au protocole pour que le SERVEUR dise non, avec sa phrase.
    operations = await fileAuProtocole(db);
    operations.add({
      'uuid_operation': '00000000-0000-4000-8000-0000000000a1',
      'table': 'articles',
      'type': 'modification',
      'entite_id': plein,
      'payload': {'actif': false},
      'horodatage_client': '2026-10-12T09:30:00+00:00',
    });
    await db.close();

    final sortie = await executerPhp(
      'valider_charge.php',
      dossier: 'sync',
      nomVerrou:
          Platform.environment['TATACORA_BASE_ESSAI'] ?? 'tatacora_test_php',
      entree: {
        'aujourdhui': '2026-10-12',
        'poste_id': 'poste-essai-inventaire',
        'operations': operations,
      },
    );
    expect(sortie['enveloppe'], isEmpty);
    resultats = [
      for (final r in sortie['resultats'] as List) r as Map<String, dynamic>,
    ];
    etats = sortie['etats'] as Map<String, dynamic>;
  });

  Map<String, dynamic> resultatDe(String table, String type, String id) {
    final rang = operations.indexWhere(
      (o) => o['table'] == table && o['type'] == type && o['entite_id'] == id,
    );
    expect(rang, isNot(-1), reason: 'aucune opération $type $table $id');
    return resultats[rang];
  }

  test('la file porte l’inventaire AVANT ses mouvements, et tout ce qui le '
      'précède', () {
    final noms = [for (final o in operations) '${o['type']} ${o['table']}'];
    final inventaire = noms.indexOf('creation inventaires');
    expect(inventaire, isNot(-1));
    // Les deux mouvements de régularisation suivent immédiatement le document.
    expect(noms[inventaire + 1], 'creation mouvements_stock');
    expect(noms[inventaire + 2], 'creation mouvements_stock');
    expect(
      noms.take(inventaire).where((n) => n == 'creation articles'),
      hasLength(4),
      reason: 'les articles qu’il cite partent avant lui',
    );
  });

  test('le serveur ACCEPTE l’inventaire, ses mouvements et l’archivage du '
      'sel ; il REFUSE celui de la farine avec la phrase du verrou', () {
    for (var i = 0; i < resultats.length; i++) {
      final o = operations[i];
      final refusAttendu =
          o['table'] == 'articles' &&
          o['type'] == 'modification' &&
          o['entite_id'] == plein;
      if (refusAttendu) {
        expect(
          resultats[i]['statut'],
          'rejete',
          reason: jsonEncode(resultats[i]),
        );
        // Le serveur dit POURQUOI, avec la phrase du poste : du stock reste.
        expect(
          resultats[i]['motif'],
          startsWith(MessagesStock.verrouStock('3.00')),
        );
      } else {
        expect(
          resultats[i]['statut'],
          'synchronise',
          reason: '${o['type']} ${o['table']} : ${jsonEncode(resultats[i])}',
        );
      }
    }
  });

  test('l’inventaire écrit par le serveur est CELUI du poste : point, jour, '
      'lignes en décimal au centième, écart = constaté − théorique', () {
    final inventaire =
        etats['inventaires:$inventaireId'] as Map<String, dynamic>;
    expect('${inventaire['date_inventaire']}', startsWith('2026-10-12'));
    final lignes = (inventaire['lignes'] as List).cast<Map<String, dynamic>>();
    expect(lignes, hasLength(2));
    final parArticle = {
      for (final l in lignes)
        l['article_id'] as String: (
          l['quantite_theorique'],
          l['quantite_constatee'],
          l['ecart'],
        ),
    };
    expect(parArticle[const Uuid4Essai('riz').valeur], (
      '10.00',
      '12.00',
      '2.00',
    ));
    expect(parArticle[const Uuid4Essai('huile').valeur], (
      '4.00',
      '3.00',
      '-1.00',
    ));
  });

  test('la régularisation du poste est écrite par le service du serveur : '
      'l’excédent en `inventaire`, le manquant en `perte`, sous le motif du '
      'poste', () {
    final mouvements = [
      for (final e in etats.entries)
        if (e.key.startsWith('mouvements_stock:') &&
            '${(e.value as Map)['motif']}'.startsWith('Régularisation'))
          (e.value as Map<String, dynamic>),
    ];
    expect(mouvements, hasLength(2));
    final parType = {for (final m in mouvements) '${m['type_mouvement']}': m};
    expect(parType.keys, {'inventaire', 'perte'});
    expect('${parType['inventaire']!['quantite']}', '2.00');
    expect('${parType['perte']!['quantite']}', '1.00');
    expect(
      parType['inventaire']!['motif'],
      MessagesStock.motifRegularisation(
        inventaire: inventaireId,
        ecart: '2.00',
      ),
    );
    expect(
      parType['perte']!['motif'],
      MessagesStock.motifRegularisation(
        inventaire: inventaireId,
        ecart: '-1.00',
      ),
    );
  });

  test('l’archivage du sel est appliqué : `actif` faux au serveur', () {
    final serveur = etats['articles:$sel'] as Map<String, dynamic>;
    expect(serveur['actif'], 0);
    expect(
      resultatDe('articles', 'modification', sel)['statut'],
      'synchronise',
    );
  });

  test('une fois archivée au serveur, la farine garde son stock : rien n’a '
      'été écrit pour elle', () {
    expect(etats['articles:$plein']!['actif'], 1);
  });
}

/// Un UUID v4 STABLE dérivé d'un nom : les identifiants d'un poste sont des
/// UUID, et le moteur du serveur les exige (`entite_id` uuid).
final class Uuid4Essai {
  const Uuid4Essai(this.nom);
  final String nom;

  String get valeur {
    final h = nom.codeUnits.fold<int>(7, (a, c) => (a * 31 + c) & 0xFFFFFFFF);
    final hex = h.toRadixString(16).padLeft(8, '0');
    return '$hex-0000-4000-8000-${hex.padRight(12, '0')}';
  }
}
