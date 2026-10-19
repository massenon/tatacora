import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// PA-105 — aucun caractère de contrôle invisible dans le code source.
///
/// Réplique du garde-fou posé d'abord sur `prototype_v2` (`tests/sanity.js`,
/// neuvième contrôle — une ancienne version, archivée depuis PA-183) puis sur
/// `tatacora-api` (`tests/Unit/Shared/CaracteresDeControleTest.php`). Même
/// règle, mêmes exclusions, même garde de garde.
///
/// ## Le défaut, rencontré deux fois
///
/// Un script de génération écrivant `\b` dans une expression régulière a
/// produit l'octet **0x08** — le retour arrière — au lieu des deux caractères
/// `\` et `b`. Le motif devenu `/<retour arrière>mot/` ne correspond **jamais
/// à rien**.
///
/// C'est arrivé sur `PwaLectureSeuleTest.php`, qui portait 0x08 et 0x01 là où
/// `\b` et `\1` étaient attendus : son dépouillement des balises `<script>`
/// n'avait jamais lieu, et le test passait **à vide**. C'est arrivé une
/// seconde fois le 24/08/2026 sur la garde du bouton « Facture A4 » du
/// prototype : le mutant qui émettait une deuxième facture passait au vert.
///
/// La forme est celle que ce dépôt connaît bien — **un contrôle qui affiche
/// « tout va bien » pendant qu'il ne vérifie rien**. Ce qui la rend
/// particulière, c'est qu'elle est **invisible à la relecture** : aucune revue
/// humaine ne distingue `\b` d'un octet 0x08 à l'écran. Seule une machine le
/// peut, d'où ce test.
///
/// ## Pourquoi il manquait ici, précisément
///
/// `flutter analyze` ne voit pas les caractères de contrôle : un 0x08 au
/// milieu d'un littéral de chaîne est du texte parfaitement valide pour
/// l'analyseur. Côté Dart, le vecteur est le même qu'ailleurs — un fichier
/// écrit par script.
///
/// ## Le second symptôme : NUL rend un fichier binaire pour grep
///
/// Un octet NUL dans un fichier source le fait classer **binaire** par grep,
/// qui le saute alors **sans un mot**. Un balayage du dépôt passe à côté sans
/// que rien ne le signale — même famille, autre mécanisme.
///
/// ## Ce qui est exclu, et pourquoi
///
/// `build/`, `.dart_tool/`, `ephemeral/` et `Pods/` : entièrement produits par
/// l'outillage, régénérés à chaque compilation, et jamais relus ligne à ligne.
/// C'est l'équivalent du `vendor/` des deux autres dépôts.
void main() {
  /// Les racines relues. `lib`, `test` et `integration_test` portent le code
  /// écrit à la main ; les trois dossiers de plateforme portent des fichiers
  /// de compilation qu'on édite réellement (Gradle, CMake, plist) et où un
  /// caractère de contrôle casserait un build de façon incompréhensible.
  const racines = <String>[
    'lib',
    'test',
    'integration_test',
    'assets',
    'android',
    'ios',
    'windows',
    // Le comparateur Blade -> Flutter (PA-183) : du JavaScript écrit à la
    // main, plein d'expressions régulières — le vecteur exact du défaut.
    'tool',
  ];

  const extensions = <String>[
    '.dart',
    '.js',
    '.yaml',
    '.yml',
    '.json',
    '.arb',
    '.md',
    '.xml',
    '.gradle',
    '.kts',
    '.cmake',
    '.cc',
    '.h',
    '.cpp',
    '.plist',
    '.kt',
    '.swift',
    '.txt',
    '.properties',
  ];

  const ignores = <String>['build', '.dart_tool', '.git', 'ephemeral', 'Pods'];

  /// Les fichiers de configuration posés à la racine du paquet, qui ne vivent
  /// dans aucune des racines ci-dessus.
  const racineDuPaquet = <String>[
    'pubspec.yaml',
    'analysis_options.yaml',
    'dart_test.yaml',
    'README.md',
    'RAPPORT_SPRINT_0.md',
    'RAPPORT_SPRINT_1.md',
  ];

  /// Seuls trois caractères de contrôle sont légitimes dans un fichier
  /// source : le saut de ligne, le retour chariot et la tabulation.
  const autorises = <int>[0x0A, 0x0D, 0x09];

  const noms = <int, String>{
    0x00: 'NUL — rend le fichier BINAIRE pour grep, qui le saute sans un mot',
    0x01: r'SOH — un \1 de groupe de capture qui a perdu son antislash',
    0x07: 'BEL',
    0x08: r'RETOUR ARRIERE — un \b de motif qui a perdu son antislash',
    0x0B: 'TABULATION VERTICALE',
    0x0C: 'SAUT DE PAGE',
    0x1A: 'SUBSTITUTE — fin de fichier DOS',
    0x1B: 'ECHAPPEMENT',
  };

  /// Plancher de fichiers relus.
  ///
  /// **Sans lui, ce test se trompe exactement comme ceux qu'il protège.** Une
  /// racine renommée, un dossier déplacé, et le balayage ne rend aucun
  /// fichier : zéro fichier lu, zéro anomalie trouvée, test VERT. Le dépôt
  /// comptait 179 fichiers relus le 24/08/2026 ; la borne est posée bas pour
  /// ne pas rougir à chaque suppression, mais assez haut pour qu'un balayage
  /// vide — ou amputé de `lib/` — ne passe pas.
  const plancherFichiers = 130;

  String normaliser(String chemin) => chemin.replaceAll('\\', '/');

  List<File> fichiers() {
    final trouves = <File>[];

    for (final racine in racines) {
      final dossier = Directory(racine);
      if (!dossier.existsSync()) continue;

      for (final entite in dossier.listSync(recursive: true)) {
        if (entite is! File) continue;

        final chemin = normaliser(entite.path);

        // Un dossier ignoré à n'importe quelle profondeur — voir l'en-tête.
        if (ignores.any((i) => chemin.contains('/$i/'))) continue;

        final minuscule = chemin.toLowerCase();
        if (!extensions.any(minuscule.endsWith)) continue;

        trouves.add(entite);
      }
    }

    for (final nom in racineDuPaquet) {
      final f = File(nom);
      if (f.existsSync()) trouves.add(f);
    }

    return trouves;
  }

  test('aucun fichier source ne porte de caractere de controle invisible', () {
    final anomalies = <String>[];
    var nbFichiers = 0;

    for (final fichier in fichiers()) {
      nbFichiers++;
      final octets = fichier.readAsBytesSync();

      var ligne = 1;
      for (final octet in octets) {
        if (octet == 0x0A) {
          ligne++;
          continue;
        }

        // Sur des OCTETS et non des caractères : une séquence UTF-8
        // multi-octet n'a que des octets >= 0x80, donc aucun accent ne peut
        // être confondu avec un caractère de contrôle.
        if (octet >= 0x20 || autorises.contains(octet)) continue;

        final code = octet.toRadixString(16).padLeft(4, '0').toUpperCase();
        anomalies.add(
          '${normaliser(fichier.path)}:$ligne — U+$code '
          '${noms[octet] ?? 'caractere de controle'}',
        );
      }
    }

    // La garde de la garde : un balayage vide ne doit JAMAIS passer pour un
    // balayage propre.
    expect(
      nbFichiers,
      greaterThanOrEqualTo(plancherFichiers),
      reason:
          'Seuls $nbFichiers fichiers ont ete relus, sous le plancher de '
          '$plancherFichiers. Le balayage ne couvre plus le depot : une racine '
          'a ete renommee ou deplacee, et ce test passerait a vide.',
    );

    expect(
      anomalies,
      isEmpty,
      reason:
          'Caractere(s) de controle invisible(s) dans le code source.\n'
          'Un \\b ou un \\1 a perdu son antislash a l’ecriture : le motif qui '
          'le porte ne correspond plus a rien, et la garde qu’il sert passe a '
          'vide sans rougir.\n\n'
          '${anomalies.take(20).join('\n')}'
          '${anomalies.length > 20 ? '\n… et ${anomalies.length - 20} autre(s)' : ''}',
    );
  });
}
