import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/parametres/data/parametres_dao.dart';
import 'package:tatacora_flutter/features/parametres/data/parametres_depot_local.dart';
import 'package:tatacora_flutter/features/parametres/domain/enregistrer_parametres.dart';
import 'package:tatacora_flutter/features/parametres/domain/entities/parametre.dart';
import 'package:tatacora_flutter/features/parametres/domain/regles_parametres.dart';
import 'package:tatacora_flutter/features/parametres/domain/registre_parametres_local.dart';
import 'package:tatacora_flutter/features/parametres/domain/resultats_parametres.dart';
import 'package:tatacora_flutter/features/rh/data/paie_dao.dart';
import 'package:tatacora_flutter/features/rh/domain/entities/taux_paie.dart';

import 'registre_serveur.dart';

/// Le cas d'usage d'enregistrement ET le dépôt local, sur une VRAIE base.
///
/// Les cas qui comptent passent par le chemin réel : `EnregistrerParametres`
/// -> `ParametresDepotLocal` -> `ParametresDao` / `PaieDao` -> SQLite.
void main() {
  late AppDatabase db;
  late EnregistrerParametres cas;
  late ParametresDepotLocal depot;
  var horloge = DateTime(2026, 10, 9, 8);

  setUp(() async {
    db = AppDatabase.enMemoire();
    horloge = DateTime(2026, 10, 9, 8);
    depot = ParametresDepotLocal(
      db,
      parametres: ParametresDao(db, maintenant: () => horloge),
    );
    cas = EnregistrerParametres(depot);

    await db
        .into(db.utilisateursLocal)
        .insert(
          UtilisateursLocalCompanion.insert(
            id: 'u-1',
            login: 'admin',
            nom: 'Admin',
            role: 'administrateur',
            droitsJson: '{}',
            sel: 's',
            empreinte: 'e',
            iterations: 1,
            dateCreation: DateTime(2026, 10, 9),
            dateMotDePasse: DateTime(2026, 10, 9),
          ),
        );
  });

  tearDown(() => db.close());

  Future<ResultatEcriture> ecrire(
    Map<String, Object?> lot, {
    bool droit = true,
    String? auteur = 'u-1',
  }) => cas.executer(lot, peutEcrire: droit, auteurId: auteur);

  Future<Map<String, String>> ordinaires() async => {
    for (final l in await db.select(db.parametresSystemeLocal).get())
      l.cle: l.valeur,
  };

  Future<Map<String, String>> tauxPaie() => PaieDao(db).taux();

  String refus(ResultatEcriture r) => switch (r) {
    EcritureRefusee(:final motif) => motif,
    EcritureAcceptee() => fail('attendu un refus, reçu une écriture acceptée'),
  };

  List<String> modifiees(ResultatEcriture r) => switch (r) {
    EcritureAcceptee(:final modifiees) => modifiees,
    EcritureRefusee(:final motif) => fail('attendu une écriture : $motif'),
  };

  group('refus — et RIEN n’est écrit', () {
    test('sans le droit PARAM en écriture : refus, aucune ligne', () async {
      final r = await ecrire({'entreprise_ifu': '123'}, droit: false);
      expect(refus(r), refusDroitParametres);
      expect(
        refusDroitParametres,
        'Vous n’avez pas le droit de modifier les paramètres du système.',
      );
      expect(await ordinaires(), isEmpty);
    });

    test('une clé inconnue est refusée avec la phrase du serveur, jamais '
        'créée', () async {
      final langue = RegistreServeur.charger().langue;
      final r = await ecrire({'mecef_actif': 'true'});

      expect(
        refus(r),
        (langue['cle_inconnue'] as String).replaceAll(':cle', 'mecef_actif'),
      );
      expect((r as EcritureRefusee).parCle.keys, ['mecef_actif']);
      expect(await ordinaires(), isEmpty);
      expect(await tauxPaie(), isEmpty);
    });

    test('une clé inconnue dans un lot refuse le lot ENTIER : la clé valide '
        'voisine n’est pas écrite', () async {
      final r = await ecrire({'entreprise_ifu': '123', 'cle_fantome': 'x'});
      expect((r as EcritureRefusee).parCle.keys, ['cle_fantome']);
      expect(await ordinaires(), isEmpty);
    });

    test(
      'toutes les erreurs de forme sont rendues ensemble, par champ',
      () async {
        final r = await ecrire({'taux_tva': '200', 'entreprise_email': 'nope'});
        expect((r as EcritureRefusee).parCle, {
          'taux_tva': '« Taux de TVA (%) » doit être compris entre 0 et 100.',
          'entreprise_email':
              '« Email de contact » n’est pas une adresse électronique valide.',
        });
        expect(await ordinaires(), isEmpty);
      },
    );

    test('un lot vide est refusé', () async {
      expect(refus(await ecrire({})), 'Aucun paramètre à enregistrer.');
    });

    test('activer la TVA seule est refusé ; la base reste vide', () async {
      final r = await ecrire({'tva_active': true});
      expect(refus(r), refusTvaSansTaux);
      expect(await ordinaires(), isEmpty);
    });

    test('vider le taux d’une TVA active est refusé ; le taux reste', () async {
      modifiees(await ecrire({'tva_active': true, 'taux_tva': '18'}));

      final r = await ecrire({'taux_tva': ''});

      expect(refus(r), refusTvaSansTaux);
      expect((await ordinaires())['taux_tva'], '18');
      expect((await ordinaires())['tva_active'], 'true');
    });
  });

  group('écriture — seules les clés TOUCHÉES, avec leur trace', () {
    test('activer la TVA et poser son taux du même geste : accepté, les deux '
        'clés écrites, rien d’autre', () async {
      final r = await ecrire({'tva_active': true, 'taux_tva': '18'});

      expect(modifiees(r)..sort(), ['taux_tva', 'tva_active']);
      expect((r as EcritureAcceptee).message, 'Paramètres enregistrés.');
      expect(await ordinaires(), {'tva_active': 'true', 'taux_tva': '18'});
    });

    test(
      'qui et quand : modifiePar et modifieLe sont ceux de la saisie',
      () async {
        await ecrire({'entreprise_ifu': '3202612345678'});

        final l = await db.select(db.parametresSystemeLocal).getSingle();
        expect(l.cle, 'entreprise_ifu');
        expect(l.modifiePar, 'u-1');
        expect(l.modifieLe, DateTime(2026, 10, 9, 8));
      },
    );

    test('une clé inchangée n’est PAS réécrite : son horodatage et son auteur '
        'restent ceux de la dernière vraie modification', () async {
      await ecrire({'entreprise_ifu': '111'});
      horloge = DateTime(2026, 10, 9, 17);

      final r = await ecrire({'entreprise_ifu': '111'});

      expect(modifiees(r), isEmpty);
      expect((r as EcritureAcceptee).message, 'Aucune valeur modifiée.');
      final l = await db.select(db.parametresSystemeLocal).getSingle();
      expect(l.modifieLe, DateTime(2026, 10, 9, 8));
    });

    test('un lot ne touche QUE ses clés : une autre clé, déjà saisie, est '
        'intacte (aucun renvoi du formulaire entier)', () async {
      await ecrire({'entreprise_ifu': '111', 'entreprise_rccm': 'RB/1'});
      horloge = DateTime(2026, 10, 9, 17);

      await ecrire({'entreprise_ifu': '222'});

      final lignes = {
        for (final l in await db.select(db.parametresSystemeLocal).get())
          l.cle: l,
      };
      expect(lignes['entreprise_ifu']!.valeur, '222');
      expect(lignes['entreprise_ifu']!.modifieLe, DateTime(2026, 10, 9, 17));
      expect(lignes['entreprise_rccm']!.valeur, 'RB/1');
      expect(lignes['entreprise_rccm']!.modifieLe, DateTime(2026, 10, 9, 8));
    });

    test(
      'vider SUPPRIME la ligne : la clé redevient « non renseignée »',
      () async {
        await ecrire({'entreprise_ifu': '111'});

        final r = await ecrire({'entreprise_ifu': ''});

        expect(modifiees(r), ['entreprise_ifu']);
        expect(await ordinaires(), isEmpty);
        final lu = await cas.lire();
        expect(
          lu.definitions.firstWhere((d) => d.cle == 'entreprise_ifu').valeur,
          isNull,
        );
      },
    );

    test('vider une clé déjà vide n’écrit rien', () async {
      final r = await ecrire({'entreprise_ifu': ''});
      expect(modifiees(r), isEmpty);
    });
  });

  group('routage — un taux de la paie a UN auteur, taux_paie_local', () {
    test('un taux social part dans taux_paie_local, jamais dans '
        'parametres_systeme_local', () async {
      final r = await ecrire({'taux_vps': '5', 'entreprise_ifu': '111'});

      expect(modifiees(r)..sort(), ['entreprise_ifu', 'taux_vps']);
      expect(await ordinaires(), {'entreprise_ifu': '111'});
      expect((await tauxPaie())['taux_vps'], '5');
    });

    test('le taux saisi remplace la valeur installée et perd sa « source » : '
        'la description ne prétend plus citer cnss.bj', () async {
      final paie = PaieDao(db);
      await paie.installerReferentielConfirme();
      expect((await tauxPaie())['taux_cnss_salarie'], '3.6');

      await ecrire({'taux_cnss_salarie': '3,9'});

      expect((await tauxPaie())['taux_cnss_salarie'], '3.9');
      final ligne = await (db.select(
        db.tauxPaieLocal,
      )..where((t) => t.cle.equals('taux_cnss_salarie'))).getSingle();
      expect(
        ligne.description,
        'Valeur saisie depuis l’écran Paramètres : la source d’origine, si '
        'elle existait, ne vaut plus pour cette valeur.',
      );
    });

    test('le taux de risques professionnels : renseigné puis vidé, la ligne '
        'est retirée', () async {
      await ecrire({'taux_cnss_risques_professionnels': '2,5'});
      expect((await tauxPaie())['taux_cnss_risques_professionnels'], '2.5');

      final r = await ecrire({'taux_cnss_risques_professionnels': ''});
      expect(modifiees(r), ['taux_cnss_risques_professionnels']);
      expect(await tauxPaie(), isEmpty);
    });

    test('un taux confirmé ne se vide pas — et la raison est vraie : '
        'l’installateur de la paie le réinstallerait', () async {
      final paie = PaieDao(db);
      await paie.installerReferentielConfirme();

      final r = await ecrire({'taux_vps': ''});
      expect(refus(r), raisonTauxConfirmeNonVidable);
      expect((await tauxPaie())['taux_vps'], '4');

      // La preuve de la raison : si on retirait la ligne à la main,
      // l'ouverture de l'écran Paie la remettrait.
      await paie.retirerTaux('taux_vps');
      expect((await tauxPaie()).containsKey('taux_vps'), isFalse);
      await paie.installerReferentielConfirme();
      expect((await tauxPaie())['taux_vps'], '4');
    });

    test(
      'lecture : les taux déjà installés par la paie sont lus tels quels '
      'dans le registre, les autres lignes de taux_paie_local sont ignorées',
      () async {
        await PaieDao(db).installerReferentielConfirme();
        await db
            .into(db.tauxPaieLocal)
            .insert(
              TauxPaieLocalCompanion.insert(cle: 'autre_taux', valeur: '9'),
            );

        final lu = await depot.lireTout();

        expect(lu, {
          for (final t in ReferentielPaie.confirmes) t.cle: t.valeur,
        });
        expect(lu.containsKey('autre_taux'), isFalse);
        expect(lu.containsKey(ClesTaux.cnssRisquesProfessionnels), isFalse);
      },
    );

    test('atomicité : si l’écriture ordinaire échoue, le taux de la paie déjà '
        'écrit est DÉFAIT', () async {
      // Un auteur inconnu viole la clé étrangère de `modifie_par` APRÈS que le
      // taux de la paie ait été écrit (le dépôt écrit la paie d'abord).
      await expectLater(
        ecrire({'taux_vps': '6', 'entreprise_ifu': '111'}, auteur: 'u-inconnu'),
        throwsA(anything),
      );

      expect(await tauxPaie(), isEmpty);
      expect(await ordinaires(), isEmpty);
    });
  });

  group('lecture — ce que l’écran affiche', () {
    test(
      'base vide : 31 définitions, AUCUNE valeur, rien de plausible',
      () async {
        final lu = await cas.lire();

        expect(lu.definitions.length, 31);
        expect(lu.definitions.where((d) => d.valeur != null), isEmpty);
      },
    );

    test(
      'base vide : les badges sont « inactive » et « non_configuree »',
      () async {
        final lu = await cas.lire();
        expect(lu.etats['tva']!.code, 'inactive');
        expect(lu.etats['mecef']!.code, 'non_configuree');
      },
    );

    test(
      'les badges suivent les valeurs ÉCRITES, jamais le champ brut',
      () async {
        await ecrire({'tva_active': true, 'taux_tva': '18'});
        await ecrire({'entreprise_numero_mecef': 'M-1'});

        final lu = await cas.lire();
        expect(lu.etats['tva']!.code, 'parametree_non_appliquee');
        expect(lu.etats['mecef']!.code, 'en_attente_implementation');
        expect(
          lu.definitions.firstWhere((d) => d.cle == 'taux_tva').valeur,
          '18',
        );
      },
    );

    test('une clé sans lecteur le DIT dans ses notes, une clé lue non ; '
        'l’aide du serveur n’est jamais altérée', () async {
      final lu = await cas.lire();
      DefinitionParametre def(String cle) =>
          lu.definitions.firstWhere((d) => d.cle == cle);

      expect(def('delai_preavis_conge_jours').notes, [
        'Aucun module de ce poste ne lit encore cette valeur.',
      ]);
      expect(def('delai_preavis_conge_jours').aide, isNull);
      // Le taux de TVA, lui, A UN LECTEUR depuis le 12/10/2026 (lot 6) : la
      // pièce comptable d'une vente. Le dire « sans effet » serait faux, et
      // l'exploitant ne le renseignerait pas — alors que sans lui une vente est
      // refusée dès que la TVA est active.
      expect(def('taux_tva').notes, isEmpty);
      // La bascule de suppression est LUE (fournisseurs M7, lot 7) : elle ne
      // porte plus « aucun module ne la lit », mais une correction qui borne sa
      // portée — l'aide du serveur (« tous les modules ») reste intacte.
      expect(def('activation_suppression').notes, isEmpty);
      expect(
        def('activation_suppression').correction,
        contains('les unités d’hébergement (M1)'),
      );
      expect(def('activation_suppression').aide, contains('tous les modules'));
      // Un secret voisin : la phrase de refus PUIS « aucun module ».
      expect(def('entreprise_numero_mecef').notes, [
        'Sur ce poste, aucune clé d’API MECeF n’est enregistrable : un secret '
            'n’entre jamais dans cette base.',
        'Aucun module de ce poste ne lit encore cette valeur.',
      ]);
      expect(
        def('entreprise_numero_mecef').aide,
        startsWith('Fourni par la DGI.'),
      );
      expect(
        def('entreprise_numero_mecef').aide,
        isNot(contains('enregistrable')),
      );
      // Une clé lue par la paie : aucune note.
      expect(def('taux_vps').notes, isEmpty);
      expect(
        def('taux_vps').aide,
        'Assiette : total des bruts, sans plafond. Jamais une retenue '
        'salariale.',
      );
    });

    test('le registre est FERMÉ jusque dans la lecture : une ligne étrangère '
        'en base n’apparaît pas', () async {
      await db
          .into(db.parametresSystemeLocal)
          .insert(
            ParametresSystemeLocalCompanion.insert(
              cle: 'cle_posee_a_la_main',
              valeur: 'x',
              modifieLe: DateTime(2026, 10, 9),
            ),
          );

      final lu = await cas.lire();
      expect(
        lu.definitions.map((d) => d.cle),
        isNot(contains('cle_posee_a_la_main')),
      );
      expect(lu.definitions.length, 31);
      // Le dépôt lui-même ne la remonte pas : c'est lui qui nourrit la
      // cohérence et les badges, pas seulement l'écran.
      expect(
        (await depot.lireTout()).containsKey('cle_posee_a_la_main'),
        isFalse,
      );
    });
  });

  group('le cas d’usage n’envoie au stockage QUE les clés qui changent', () {
    test('un lot mixte : la clé inchangée n’atteint pas le stockage', () async {
      final espion = _Espion({'entreprise_ifu': '111'});
      final cas = EnregistrerParametres(espion);

      final r = await cas.executer(
        {'entreprise_ifu': '111', 'entreprise_rccm': 'RB/1'},
        peutEcrire: true,
        auteurId: null,
      );

      expect(espion.ecritures, [
        {'entreprise_rccm': 'RB/1'},
      ]);
      expect((r as EcritureAcceptee).modifiees, ['entreprise_rccm']);
    });

    test('un lot sans aucun changement n’appelle PAS le stockage', () async {
      final espion = _Espion({'entreprise_ifu': '111'});
      final cas = EnregistrerParametres(espion);

      final r = await cas.executer(
        {'entreprise_ifu': ' 111 '},
        peutEcrire: true,
        auteurId: null,
      );

      expect(espion.ecritures, isEmpty);
      expect((r as EcritureAcceptee).message, 'Aucune valeur modifiée.');
    });

    test('vider une clé absente n’appelle pas le stockage non plus', () async {
      final espion = _Espion({});
      await EnregistrerParametres(
        espion,
      ).executer({'entreprise_ifu': ''}, peutEcrire: true, auteurId: null);
      expect(espion.ecritures, isEmpty);
    });
  });
}

/// Un stockage en mémoire qui ENREGISTRE ce qu'on lui demande d'écrire.
class _Espion implements StockageParametres {
  _Espion(this._valeurs);

  final Map<String, String> _valeurs;
  final List<Map<String, String?>> ecritures = [];

  @override
  Future<Map<String, String>> lireTout() async => Map.of(_valeurs);

  @override
  Future<List<String>> ecrire(
    Map<String, String?> valeurs, {
    required String? auteurId,
  }) async {
    ecritures.add(Map.of(valeurs));
    return valeurs.keys.toList();
  }
}
