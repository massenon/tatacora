import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/facturation/domain/entities/piece_facturation.dart';
import 'package:tatacora_flutter/features/facturation/domain/ifu_client.dart';
import 'package:tatacora_flutter/features/pos/presentation/widgets/modale_cloture_sejour.dart';
import 'package:tatacora_flutter/features/facturation/domain/mode_facturation.dart';
import 'package:tatacora_flutter/features/facturation/domain/statut_normalisation.dart';
import 'package:tatacora_flutter/features/parametres/domain/regles_parametres.dart';
import 'package:tatacora_flutter/features/parametres/domain/registre_parametres_local.dart';

/// PARITÉ serveur / poste des règles communes de la facturation normalisée :
/// le mode, la lecture d'une valeur inconnue, l'IFU de 13 chiffres, les statuts.
/// Le poste est confronté au VRAI PHP (`tool/facturation/rejouer_regles_communes.php`),
/// jamais à une liste recopiée. PHP absent : le test ÉCHOUE, il ne saute pas.
void main() {
  late Map<String, dynamic> serveur;

  setUpAll(() {
    final r = Process.runSync('php', [
      'tool/facturation/rejouer_regles_communes.php',
    ], stdoutEncoding: utf8);
    if (r.exitCode != 0) {
      fail(
        'Le serveur n’a pas pu être rejoué (php, code ${r.exitCode}) : '
        '${r.stderr}. C’est un ÉCHEC, pas un saut.',
      );
    }
    serveur = jsonDecode(r.stdout as String) as Map<String, dynamic>;
  });

  test('le balayage n’est pas vide', () {
    expect((serveur['modes'] as List), hasLength(3));
    expect((serveur['statuts'] as List), hasLength(4));
    expect((serveur['mode_depuis'] as Map).length, greaterThanOrEqualTo(8));
    expect((serveur['ifu_valide'] as Map).length, greaterThanOrEqualTo(9));
  });

  test('la clé du mode et les modes sont ceux du serveur, libellés compris', () {
    expect(cleModeFacturation, serveur['cle_mode']);
    final modes = serveur['modes'] as List;
    expect(
      [for (final m in ModeFacturation.values) m.code],
      [for (final m in modes) (m as Map)['valeur']],
    );
    expect(
      [for (final m in ModeFacturation.values) m.libelle],
      [for (final m in modes) (m as Map)['libelle']],
    );
    // Les libellés du registre local (choix du mode) sont ceux du serveur aussi.
    final spec = RegistreParametresLocal.parCle(cleModeFacturation)!;
    expect(spec.choix, [for (final m in modes) (m as Map)['valeur']]);
  });

  test('lire une valeur de mode : même résultat que le serveur, y compris '
      'pour une valeur inconnue (toujours « désactivé »)', () {
    final attendu = serveur['mode_depuis'] as Map<String, dynamic>;
    attendu.forEach((brut, mode) {
      expect(ModeFacturation.depuisCode(brut).code, mode, reason: '« $brut »');
    });
  });

  test('l’IFU : mêmes 13 chiffres, mêmes refus (espace, retour à la ligne, '
      'chiffres pleine chasse)', () {
    final spec = RegistreParametresLocal.parCle('entreprise_ifu')!;
    final attendu = serveur['ifu_valide'] as Map<String, dynamic>;
    attendu.forEach((brut, valide) {
      // Le poste normalise (trim) AVANT de juger ; le serveur juge la valeur
      // brute reçue. Comparer les deux sur la valeur déjà rognée.
      final ecran = normaliser(spec, brut.trim());
      final accepte = ecran is ValeurNormalisee && ecran.valeur != null;
      final serveurValide = valide as bool;
      if (brut == brut.trim()) {
        expect(accepte, serveurValide, reason: '« $brut »');
      } else {
        // Une espace de bord est rognée par le poste ; le serveur la refuse :
        // le poste n'envoie JAMAIS la valeur brute, il envoie la rognée.
        expect(accepte, isTrue, reason: 'rognée : « ${brut.trim()} »');
      }
    });
  });

  test('la colonne « N° » du registre : même numéro et même nature que '
      '`NumeroRegistre::pour` du serveur (fiscal si réel, sinon interne)', () {
    final cas = serveur['numero_registre'] as List;
    expect(cas.length, greaterThanOrEqualTo(10));
    for (final c in cas) {
      final m = c as Map<String, dynamic>;
      final p = PieceFacturation(
        id: 'x',
        numero: m['numero'] as String,
        origine: OrigineFacture.posComptant,
        dateEmission: DateTime(2026, 11, 9),
        clientNom: 'C',
        statut: StatutPiece.emise,
        numeroMecef: m['numero_mecef'] as String?,
        lignes: const [],
      );
      expect(p.numeroRegistre, m['valeur'], reason: '$m');
      expect(p.numeroRegistreEstInterne, m['interne'], reason: '$m');
    }
    // Au moins un cas de chaque nature : sinon la parité serait verte à vide.
    expect(cas.where((c) => (c as Map)['interne'] == true), isNotEmpty);
    expect(cas.where((c) => (c as Map)['interne'] == false), isNotEmpty);
    expect(serveur['numero_interne_legende'], 'n° interne');
  });

  test('les statuts de normalisation : mêmes codes, mêmes libellés, même '
      'notion de « rejouable », dans le même ordre', () {
    final statuts = serveur['statuts'] as List;
    expect(
      [for (final s in StatutNormalisation.values) s.code],
      [for (final s in statuts) (s as Map)['valeur']],
    );
    expect(
      [for (final s in StatutNormalisation.values) s.libelle],
      [for (final s in statuts) (s as Map)['libelle']],
    );
    expect(
      [for (final s in StatutNormalisation.values) s.rejouable],
      [for (final s in statuts) (s as Map)['rejouable']],
    );
  });

  test(
    'les clés RÉSERVÉES aux administrateurs sont celles du serveur : cinq '
    'réglages, ni plus ni moins — et AUCUNE clé n’est « serveur seulement »',
    () {
      final cles = (serveur['cles_administrateur'] as List).cast<String>();
      expect(cles, hasLength(5));
      for (final cle in cles) {
        expect(
          RegistreParametresLocal.parCle(cle)!.reserveAdministrateur,
          isTrue,
          reason: cle,
        );
      }
      expect(
        [
          for (final s in RegistreParametresLocal.definitions)
            if (s.reserveAdministrateur) s.cle,
        ]..sort(),
        ([...cles]..sort()),
      );
      // Les neuf réglages des documents sont modifiables avec le seul droit PARAM.
      final documents = (serveur['cles_documents'] as List).cast<String>();
      expect(documents, hasLength(9));
      for (final cle in documents) {
        expect(
          RegistreParametresLocal.parCle(cle)!.reserveAdministrateur,
          isFalse,
          reason: cle,
        );
      }
    },
  );

  test('l’IFU du CLIENT : facultatif, 13 chiffres s’il est rempli, séparateurs '
      'ôtés — comme le serveur', () {
    final valide = serveur['ifu_client_valide'] as Map<String, dynamic>;
    final nettoye = serveur['ifu_client_nettoye'] as Map<String, dynamic>;
    expect(valide.length, greaterThanOrEqualTo(12), reason: 'balayage vide');
    valide.forEach((brut, attendu) {
      expect(IfuClient.valide(brut), attendu, reason: 'valide « $brut »');
    });
    nettoye.forEach((brut, attendu) {
      expect(IfuClient.nettoyer(brut), attendu, reason: 'nettoyé « $brut »');
    });
  });

  test('les phrases du champ et de l’avoir en ligne sont celles du serveur, '
      'au mot près', () {
    final p = serveur['phrases'] as Map<String, dynamic>;
    expect(TextesIfuClient.label, p['ifu_label']);
    expect(TextesIfuClient.nomLabel, p['ifu_nom_label']);
    expect(TextesIfuClient.aide, p['ifu_aide']);
    expect(TextesIfuClient.invalide, p['ifu_invalide']);
    expect(TextesIfuClient.retenir, p['ifu_retenir']);
    expect(TextesIfuClient.nomDivers, p['ifu_nom_divers']);
    expect(TextesIfuClient.normaliserMaintenant, p['normaliser_maintenant']);
    expect(TextesFacturationModes.avoirEnLigne, p['avoir_en_ligne']);
    // Les mots écrits dans la modale de clôture (lus par le comparateur Blade) sont ceux du serveur.
    expect(ModaleClotureSejour.acheteurNom, p['ifu_nom_label']);
    expect(ModaleClotureSejour.acheteurAide, p['ifu_aide']);
  });
}
