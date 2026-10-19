import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// La règle absolue de l'Article 2 : **aucune valeur de style en dur dans un
/// widget.**
///
/// > « Toute couleur ou tout espacement littéral trouvé dans un écran est un
/// > défaut à corriger. » — `DIRECTIVE_CONFORMITE_100.md` Article 2
///
/// Cette garde balaye `lib/` et refuse cinq formes de littéral de style. Elle
/// ne remplace pas `conformite_jetons_maitre_test.dart`, qui vérifie que les
/// jetons **valent** ce que vaut le maître ; celle-ci vérifie qu'ils sont
/// **employés**. Les deux sont nécessaires : un jeton juste que personne
/// n'emploie ne rend aucun pixel juste.
///
/// ## Pourquoi cinq formes précises et pas un motif large
///
/// Un motif vague produirait des faux positifs légitimes — le `SizedBox` d'un
/// filet, la taille d'icône qu'impose Material, un `flex` — et le premier
/// développeur qui en rencontrerait un désarmerait la garde entière. Les cinq
/// formes retenues n'ont **aucun emploi légitime** dans la couche de
/// présentation de ce dépôt, et les rares exceptions sont **nommées une par
/// une** plus bas, jamais couvertes par un joker.
///
/// ## Elle prouve que ses motifs MORDENT
///
/// Un test relit ses cinq expressions régulières contre un échantillon
/// fabriqué. Sans lui, un motif cassé — par exemple un `\b` devenu l'octet 0x08
/// au passage d'un heredoc, ce qui est arrivé trois fois ici — ne
/// correspondrait plus à rien et le balayage passerait **à vide, donc vert**.
/// C'est le défaut même que cette garde protège.
///
/// ## Elle porte un plancher de fichiers
///
/// Sans lui, un dossier renommé rendrait la liste vide, donc verte.
void main() {
  /// Mesuré le 26/08/2026 : `lib/` compte 192 fichiers Dart écrits à la main.
  /// Le plancher est posé nettement en dessous pour tolérer une réorganisation,
  /// et assez haut pour qu'un répertoire perdu le franchisse.
  const plancherFichiers = 150;

  /// **Où les jetons vivent.** C'est le seul endroit du dépôt où une valeur de
  /// style s'écrit en clair — c'est sa raison d'être.
  const repertoireDesJetons = 'lib/core/theme/';

  /// **Le format d'un document imprimé n'est pas l'échelle d'écran du maître.**
  ///
  /// Les `pw.TextStyle` d'un ticket 80 mm et d'un A4 sont dictés par le papier,
  /// pas par la vue Blade de la PWA. L'exclusion est antérieure à cette garde et
  /// documentée en propre : `DOCTRINE_PORTAGE_FIDELE_FLUTTER.md`, historique
  /// des révisions v1.1.
  bool estImpression(String chemin) => chemin.contains('impression/');

  /// **Les quatre fichiers où une durée n'est pas une animation.**
  ///
  /// Liste nommée et fermée, jamais un motif. Un délai réseau, un repli de
  /// synchronisation et une fenêtre de validité de session se mesurent en
  /// secondes et ne décrivent rien de visible ; les faire passer par
  /// `AppDurations` mélangerait le temps de l'interface et celui du réseau.
  const fichiersOuUneDureeNEstPasUneAnimation = <String>{
    'lib/core/network/dio_client.dart',
    'lib/core/network/intercepteur_retry.dart',
    'lib/core/sync/declencheur_synchronisation.dart',
    'lib/features/auth/data/verificateur_hors_ligne.dart',
  };

  // -------------------------------------------------------------- Les motifs

  /// Une couleur écrite en hexadécimal — `Color(0xFF14213D)`.
  final motifCouleur = RegExp(r'Color(?:\.fromARGB)?\(\s*0x[0-9A-Fa-f]+\s*\)');

  /// Une taille de police littérale — `fontSize: 15`.
  final motifTaille = RegExp(r'fontSize:\s*[0-9]');

  /// Un rayon littéral — `BorderRadius.circular(8)`.
  final motifRayon = RegExp(r'circular\(\s*[0-9]');

  /// Une durée d'animation littérale — `Duration(milliseconds: 180)`.
  final motifDuree = RegExp(r'Duration\(\s*milliseconds\s*:');

  /// Un nombre nu — c'est-à-dire qui n'est ni un morceau d'identifiant
  /// (`AppSpacingLarge.p12`) ni un zéro (qui ne décrit aucun espacement).
  final motifNombreNu = RegExp(r'(?<![A-Za-z0-9_.])(?!0(?![0-9.]))\d+(\.\d+)?');

  List<File> fichiersDeLib() {
    final racine = Directory('lib');
    if (!racine.existsSync()) {
      fail(
        'Le répertoire `lib/` est introuvable depuis ${Directory.current.path}. '
        'Cette garde échoue plutôt que de sauter : un balayage vide est vert, '
        'et c est exactement le défaut qu elle protège.',
      );
    }
    return racine
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !f.path.endsWith('.g.dart'))
        .toList();
  }

  /// Le chemin en séparateurs POSIX — Windows rend `lib\core\theme\…`.
  String normaliser(File f) => f.path.replaceAll(r'\', '/');

  /// Les arguments d'un appel `EdgeInsets.…(…)`, parenthèses équilibrées.
  ///
  /// Une expression régulière `[^)]*` s'arrêterait à la première parenthèse
  /// fermante et manquerait `EdgeInsets.all(calcul(x))`. Ce balayage compte.
  List<String> argumentsEdgeInsets(String source) {
    final args = <String>[];
    final debut = RegExp(r'EdgeInsets\.(all|symmetric|only|fromLTRB)\(');
    for (final m in debut.allMatches(source)) {
      var profondeur = 1;
      var i = m.end;
      while (i < source.length && profondeur > 0) {
        if (source[i] == '(') profondeur++;
        if (source[i] == ')') profondeur--;
        i++;
      }
      // Les commentaires de fin de ligne sont retirés AVANT l'examen. Ils
      // citent presque toujours la classe du maître — `// px-3`, `// py-2.5` —
      // et les compter reviendrait à signaler comme défaut la trace même qui
      // prouve que la valeur a été mesurée. Une garde qui punit la
      // documentation se fait désarmer par le premier développeur qui la
      // rencontre.
      args.add(
        source.substring(m.end, i - 1).replaceAll(RegExp(r'//[^\n]*'), ''),
      );
    }
    return args;
  }

  // =========================================================================
  test('les cinq motifs mordent réellement sur un échantillon fabriqué', () {
    // Sans ce contrôle, un motif cassé ne correspondrait plus à rien et tout
    // le balayage passerait à vide — donc vert. Trois occurrences réelles dans
    // ce dépôt (piège 4) : c est le seul contrôle qui les aurait attrapées.
    expect(motifCouleur.hasMatch('const c = Color(0xFF14213D);'), isTrue);
    expect(motifCouleur.hasMatch('Color.fromARGB(0xFF112233)'), isTrue);
    expect(motifTaille.hasMatch('TextStyle(fontSize: 15)'), isTrue);
    expect(motifRayon.hasMatch('BorderRadius.circular(8)'), isTrue);
    expect(motifDuree.hasMatch('const Duration(milliseconds: 180)'), isTrue);

    // Et ils ne mordent PAS sur la forme correcte — un motif qui refuserait
    // tout serait aussi inutile qu un motif qui n accepte rien.
    expect(motifCouleur.hasMatch('AppColors.navy'), isFalse);
    expect(motifTaille.hasMatch('fontSize: Tailles.t13'), isFalse);
    expect(motifRayon.hasMatch('circular(AppRadius.md)'), isFalse);
    expect(motifDuree.hasMatch('AppDurations.modale'), isFalse);

    // Le nombre nu : il doit distinguer un littéral d un identifiant qui en
    // contient un. `AppSpacingLarge.p12` n est pas un `12` en dur.
    expect(motifNombreNu.hasMatch('bottom: 2'), isTrue);
    expect(motifNombreNu.hasMatch('horizontal: 12.5'), isTrue);
    expect(motifNombreNu.hasMatch('AppSpacingLarge.p12'), isFalse);
    expect(motifNombreNu.hasMatch('Largeurs.max2xl'), isFalse);
    expect(motifNombreNu.hasMatch('AppSpacing.md'), isFalse);
    expect(motifNombreNu.hasMatch('0, 0, 0, AppSpacing.md'), isFalse);

    // Et le commentaire qui cite le maître ne doit pas être pris pour une
    // valeur : c'est lui qui prouve que la mesure a eu lieu.
    expect(
      argumentsEdgeInsets(
        'EdgeInsets.symmetric(horizontal: AppSpacing.sm, // px-3\n)',
      ).single.contains('3'),
      isFalse,
      reason:
          'Le retrait des commentaires ne fonctionne plus : la garde '
          'signalerait `// px-3` comme un espacement en dur.',
    );
    // …mais la valeur réelle sur la même ligne est toujours vue.
    expect(
      argumentsEdgeInsets(
        'EdgeInsets.symmetric(vertical: 10, // py-2.5\n)',
      ).single.contains('10'),
      isTrue,
      reason:
          'Le retrait des commentaires est allé trop loin : il emporte la '
          'valeur qu il fallait justement voir.',
    );
  });

  test('aucune valeur de style en dur dans lib/', () {
    final fichiers = fichiersDeLib();
    expect(
      fichiers.length,
      greaterThanOrEqualTo(plancherFichiers),
      reason:
          'Seuls ${fichiers.length} fichiers Dart relus, contre '
          '$plancherFichiers attendus au minimum. Un répertoire a été renommé '
          'ou déplacé : le balayage est devenu creux, donc vert.',
    );

    final defauts = <String>[];
    var relus = 0;

    for (final f in fichiers) {
      final chemin = normaliser(f);
      if (chemin.contains(repertoireDesJetons)) continue;
      relus++;
      final source = f.readAsStringSync();

      void signaler(String regle, String extrait) {
        defauts.add('$chemin — $regle : $extrait');
      }

      for (final m in motifCouleur.allMatches(source)) {
        signaler('couleur en dur', m.group(0)!);
      }
      for (final m in motifRayon.allMatches(source)) {
        signaler('rayon en dur', m.group(0)!);
      }

      if (!estImpression(chemin)) {
        for (final m in motifTaille.allMatches(source)) {
          signaler('taille de police en dur', m.group(0)!);
        }
        for (final args in argumentsEdgeInsets(source)) {
          final nu = motifNombreNu.firstMatch(args);
          if (nu != null) {
            signaler('espacement en dur', 'EdgeInsets(… ${nu.group(0)} …)');
          }
        }
      }

      if (!fichiersOuUneDureeNEstPasUneAnimation.contains(chemin)) {
        for (final m in motifDuree.allMatches(source)) {
          signaler('durée d animation en dur', m.group(0)!);
        }
      }
    }

    expect(
      relus,
      greaterThanOrEqualTo(plancherFichiers - 20),
      reason:
          'Seuls $relus fichiers réellement soumis aux motifs après exclusion '
          'du répertoire des jetons. L exclusion s est élargie au point de '
          'vider le balayage.',
    );

    expect(
      defauts,
      isEmpty,
      reason:
          'Article 2 — « aucune valeur de style en dur dans un widget ». '
          'Chacune de ces valeurs doit passer par un jeton de '
          '`lib/core/theme/`. Une valeur juste écrite en clair est le pire '
          'des cas : elle ne se voit pas, et la suivante ne sera pas juste.\n'
          '${defauts.join('\n')}',
    );
  });

  test('le répertoire des jetons est le SEUL exempté de couleur en dur', () {
    // L exemption n a de sens que si elle est étroite. Si `lib/core/theme/`
    // cessait d exister, la boucle ci-dessus n exclurait plus rien et ce test
    // le dirait — au lieu de laisser l exclusion couvrir un dossier renommé.
    final jetons = Directory('lib/core/theme');
    expect(
      jetons.existsSync(),
      isTrue,
      reason:
          'Le répertoire des jetons a disparu : l exclusion de la garde ne '
          'porte plus sur rien de connu.',
    );
    final fichiersJetons = jetons
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
    expect(
      fichiersJetons.length,
      greaterThanOrEqualTo(7),
      reason:
          'Moins de sept fichiers de jetons. L Article 2 en nomme sept — '
          'couleurs, espacements, rayons, ombres, typographie, points de '
          'rupture, durées.',
    );

    // Et l inverse : au moins un fichier de jetons porte réellement une
    // couleur en dur. Si aucun n en portait, l exemption serait sans objet et
    // le contrôle ci-dessus ne prouverait rien.
    expect(
      fichiersJetons.any((f) => motifCouleur.hasMatch(f.readAsStringSync())),
      isTrue,
      reason:
          'Aucun fichier de `lib/core/theme/` ne porte de couleur en dur : '
          'l exemption ne protège plus rien, elle masque peut-être un '
          'répertoire vide.',
    );
  });
}
