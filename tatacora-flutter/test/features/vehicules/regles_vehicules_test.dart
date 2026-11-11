import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/vehicules/domain/entities/vehicule.dart';
import 'package:tatacora_flutter/features/vehicules/domain/regles_vehicules.dart';

/// RG-09 et RG-08 — **relues contre le schéma de référence**.
///
/// ## Ces cas relisent le SERVEUR, ils ne figent pas une liste
///
/// PA-50 nomme `Vehicule::CATEGORIES_SANS_PERMIS` comme « le seul endroit à
/// modifier le jour où la décision tombe ». Le poste est zéro réseau et ne peut
/// plus l'interroger : `domain/regles_vehicules.dart` en porte la
/// transcription. Une liste recopiée côté Dart ne vérifierait qu'elle-même et
/// resterait verte le jour de l'arbitrage — ces cas relisent donc le fichier
/// PHP, ÉCHOUENT s'il est introuvable (ils ne sautent pas), et chaque
/// extraction est prouvée non vide, sans quoi le balayage serait vert à vide
/// (même discipline que PA-136).
void main() {
  String lireServeur(String chemin) {
    final fichier = File(chemin);
    if (!fichier.existsSync()) {
      fail(
        'Source serveur introuvable : $chemin. Ce test relit la règle du '
        'schéma de référence ; sans lui il ne vérifierait que lui-même.',
      );
    }
    return fichier.readAsStringSync();
  }

  /// Les valeurs d'une constante PHP `const NOM = ['a', 'b'];`.
  Set<String> constantePhp(String source, String nom) {
    final bloc = RegExp('$nom\\s*=\\s*\\[([^\\]]*)\\]').firstMatch(source);
    if (bloc == null) {
      fail(
        'La constante $nom est introuvable au serveur : elle a été renommée ou '
        'déplacée, et la règle locale ne suit plus rien.',
      );
    }
    return RegExp(
      "'([^']+)'",
    ).allMatches(bloc.group(1)!).map((m) => m.group(1)!).toSet();
  }

  final source = lireServeur(
    '../tatacora-api/app/Domain/Vehicules/Models/Vehicule.php',
  );

  /* ================================================================== */
  group('RG-09 — les catégories dispensées de permis', () {
    test('la liste locale est CELLE du schéma de référence', () {
      final serveur = constantePhp(source, 'CATEGORIES_SANS_PERMIS');

      // Prouvé non vide : sans ce contrôle, une extraction ratée rendrait la
      // comparaison vraie à vide — le défaut même que ce test protège.
      expect(
        serveur,
        isNotEmpty,
        reason: 'extraction vide de CATEGORIES_SANS_PERMIS',
      );
      expect(categoriesSansPermis, serveur);
    });

    test('seule la MOTO est dispensée — scooter et vélo ne le sont pas', () {
      // ⚠ L'ancien prototype écrivait « moto, scooter et vélo en sont
      // dispensés ». PA-50 laisse l'arbitrage ouvert ; tant qu'il n'est pas
      // tranché, la règle appliquée est celle du CdCF, littéralement « hors
      // motos ». Ce cas fige l'écart pour qu'il se voie, et non pour qu'il
      // s'oublie.
      expect(exigePermisPour('moto'), isFalse);
      expect(exigePermisPour('scooter'), isTrue);
      expect(exigePermisPour('velo'), isTrue);
      expect(exigePermisPour('voiture'), isTrue);
      expect(exigePermisPour('4x4'), isTrue);
    });

    test('une catégorie INCONNUE exige un permis', () {
      // Le défaut sûr est d'exiger la pièce : un registre qui gagnerait une
      // valeur demain ne doit pas obtenir la dispense par omission.
      expect(exigePermisPour('trottinette'), isTrue);
      expect(exigePermisPour(null), isTrue);
    });

    test('les sept catégories du schéma sont portées', () {
      // Le PHPDoc du serveur : « Ne pas la restreindre aux 5 valeurs du
      // prototype ». Un registre amputé rangerait un vrai véhicule dans
      // « inconnu ».
      //
      // ⚠ Ce cas a été écrit avec un nom de migration DEVINÉ
      // (`..._000012_...`), et il est passé quand même : son repli comparait
      // alors le registre à lui-même. C'est le « vert à vide » que ce fichier
      // dit combattre, reproduit dans le fichier qui le dit. Le chemin est
      // désormais relu, et son absence FAIT ÉCHOUER le cas — jamais un repli
      // silencieux.
      final migration = File(
        '../tatacora-api/database/migrations/'
        '2026_08_01_000700_create_vehicules.php',
      );
      if (!migration.existsSync()) {
        fail(
          'Migration introuvable : ${migration.path}. Sans elle, le registre '
          'des catégories ne serait vérifié que contre lui-même.',
        );
      }

      final trouve = RegExp(
        r"enum\('categorie',\s*\[([^\]]*)\]",
      ).firstMatch(migration.readAsStringSync());
      if (trouve == null) {
        fail(
          'L’enum `categorie` est introuvable dans la migration : elle a '
          'changé de forme, et le registre local ne suit plus rien.',
        );
      }

      final codes = RegExp(
        "'([^']+)'",
      ).allMatches(trouve.group(1)!).map((m) => m.group(1)!).toSet();

      expect(codes, hasLength(7), reason: 'extraction partielle de l’enum');
      expect(CategorieVehicule.values.map((c) => c.code).toSet(), codes);
    });
  });

  /* ================================================================== */
  group('Les statuts louables', () {
    test('la liste locale est CELLE du schéma de référence', () {
      final serveur = constantePhp(source, 'STATUTS_LOUABLES');

      expect(
        serveur,
        isNotEmpty,
        reason: 'extraction vide de STATUTS_LOUABLES',
      );
      expect(statutsLouables, serveur);
    });

    test('`loue` reste louable, `entretien` et `hors_service` non', () {
      // Le statut n'est pas la disponibilité : un véhicule loué aujourd'hui
      // reste louable pour une période future. Les confondre ferait disparaître
      // du parc tout ce qui est en cours de location.
      expect(statutsLouables.contains('loue'), isTrue);
      expect(statutsLouables.contains('disponible'), isTrue);
      expect(statutsLouables.contains('entretien'), isFalse);
      expect(statutsLouables.contains('hors_service'), isFalse);
    });
  });

  /* ================================================================== */
  group('RG-08 — les bornes sont demi-ouvertes', () {
    DateTime j(int jour) => DateTime(2026, 9, jour);

    test('deux plages qui se recouvrent se chevauchent', () {
      expect(
        plagesSeChevauchent(
          debutA: j(10),
          finA: j(15),
          debutB: j(12),
          finB: j(18),
        ),
        isTrue,
      );
    });

    test('une plage qui commence où l’autre finit NE chevauche pas', () {
      // « Un véhicule rendu le 15 est relouable dès le 15 ». Fermer la borne
      // immobiliserait le parc un jour sur deux.
      expect(
        plagesSeChevauchent(
          debutA: j(10),
          finA: j(15),
          debutB: j(15),
          finB: j(18),
        ),
        isFalse,
      );
      expect(
        plagesSeChevauchent(
          debutA: j(15),
          finA: j(18),
          debutB: j(10),
          finB: j(15),
        ),
        isFalse,
      );
    });

    test('une plage incluse dans l’autre chevauche', () {
      expect(
        plagesSeChevauchent(
          debutA: j(10),
          finA: j(20),
          debutB: j(12),
          finB: j(14),
        ),
        isTrue,
      );
    });

    test('le nombre de jours refuse une plage nulle ou inversée', () {
      expect(nombreDeJoursEntre(j(10), j(15)), 5);
      expect(nombreDeJoursEntre(j(10), j(10)), isNull);
      expect(nombreDeJoursEntre(j(15), j(10)), isNull);
    });

    test('l’heure ne change pas le nombre de jours', () {
      expect(
        nombreDeJoursEntre(
          DateTime(2026, 9, 10, 23, 59),
          DateTime(2026, 9, 11),
        ),
        1,
      );
    });
  });

  /* ================================================================== */
  group('Les messages sont ceux du fichier de langue du serveur', () {
    test('chevauchement, pièce et permis sont repris au mot', () {
      final langue = lireServeur('../tatacora-api/lang/fr/vehicules.php');

      expect(langue, contains(MessagesVehicules.chevauchement));
      expect(langue, contains(MessagesVehicules.pieceIdentiteRequise));
      // Le message de permis porte un paramètre `:categorie` côté serveur : on
      // compare la part fixe, qui est ce que l'exploitant lit.
      expect(
        langue,
        contains(
          'Un permis de conduire est obligatoire pour la '
          'catégorie',
        ),
      );
    });

    test('aucun message de refus ne porte d’apostrophe typographique', () {
      // Les polices intégrées des PDF ne couvrent pas U+2019, qui disparaît du
      // papier sans rien signaler — et ces phrases peuvent atteindre un export.
      const messages = [
        MessagesVehicules.chevauchement,
        MessagesVehicules.pieceIdentiteRequise,
        MessagesVehicules.vehiculeInexistant,
        MessagesVehicules.clientInexistant,
        MessagesVehicules.finApresDebut,
        MessagesVehicules.immatriculationRequise,
        MessagesVehicules.tarifInvalide,
        MessagesVehicules.contratDejaAnnule,
        MessagesVehicules.contratInexistant,
      ];

      for (final m in messages) {
        expect(
          m.contains('’'),
          isFalse,
          reason: 'apostrophe typographique dans « $m »',
        );
      }
    });
  });
}
