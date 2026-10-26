import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Décision du Product Owner : **aucune note de conception à l'écran.**
///
/// > « Les expressions ou mots-clés corrigés à la main doivent être SUPPRIMÉS
/// > de toutes les pages web et postes. »
///
/// Précisé : il s'agit des phrases techniques ajoutées par l'équipe —
/// « Sur ce poste : … », mentions d'écart, codes internes visibles
/// (`PA-xx`, `D2xx`, `EF-Mx-xx`, `RG-xx`), « non porté / non calculé »,
/// « le maître propose… », « jeu d'essai », noms de classes ou de colonnes.
/// L'écran ne garde que du texte métier utile à l'utilisateur final.
///
/// ## Ce que balaye cette garde
///
/// Les **littéraux de chaîne** de `lib/`, **hors commentaires** : un
/// commentaire (`//`, `///`, `/* */`) n'est jamais à l'écran et garde sa place.
/// Un petit analyseur lexical retire les commentaires en respectant les
/// chaînes (une apostrophe dans un commentaire n'ouvre rien), les chaînes
/// brutes, les chaînes triples et les interpolations `${…}`.
///
/// ## Elle prouve que ses motifs MORDENT
///
/// Un test relit chaque motif contre un échantillon fabriqué — positif ET
/// négatif — et un autre prouve que l'analyseur voit un littéral et ignore un
/// commentaire. Sans eux, un motif cassé (un `\b` devenu l'octet 0x08 par un
/// heredoc, piège 4) passerait **à vide, donc vert**.
///
/// ## Elle porte un plancher de fichiers
///
/// Sans lui, un dossier renommé rendrait le balayage vide, donc vert.
void main() {
  /// Mesuré le 26/10/2026 : `lib/` compte plus de 300 fichiers Dart écrits à
  /// la main. Le plancher est posé nettement en dessous pour tolérer une
  /// réorganisation, et assez haut pour qu'un répertoire perdu le franchisse.
  const plancherFichiers = 250;

  // ------------------------------------------------------------ Les motifs

  /// Les motifs interdits dans un littéral affiché. Chacun porte la raison
  /// pour laquelle il est interdit.
  final motifs = <String, RegExp>{
    'note « Sur ce poste » (conception, pas métier)': RegExp(r'Sur ce poste'),
    'mention « non porté / pas porté / non calculé »': RegExp(
      r'[Nn]on port[ée]|\bpas port[ée]|port[ée]e?s? sur ce poste|'
      r'non calcul[ée]|donn[ée]e sans source',
    ),
    'code interne PA-xx / D2xx / EF-Mx / RG-xx / UC-xx': RegExp(
      r'\bPA-\d|\bD\d{3}\b|\bEF-M\d|\bRG-\d|\bUC-\d',
    ),
    'code de module (Mx) accolé à un libellé': RegExp(
      r'\(M\d{1,2}\)|\ben M\d{1,2}\b|[Mm]odule M\d{1,2}\b|\bM\d{1,2}\)',
    ),
    '« le maître » (référence à la maquette)': RegExp(r'[Mm]a[iî]tre\b'),
    'mention d’écart nommé / déclaré': RegExp(
      r'[ée]cart nomm|[ée]cart d[ée]clar|ÉCART',
    ),
    '« jeu d’essai » / « refus déclaré »': RegExp(
      r'jeu d[’'
      "'"
      r']essai|refus d[ée]clar',
    ),
    'panneau « ce que cet écran ne rend pas »': RegExp(r'ne rend pas'),
    'date de constat (« constaté le 12/10/2026 »)': RegExp(
      r'constat[ée]e? le \d',
    ),
    'identifiant de code entre accents graves': RegExp(
      r'`[A-Za-z_][\w@>.:()-]*`',
    ),
  };

  /// **Exemptions NOMMÉES et motivées** — fichier et fragment exact du
  /// littéral. Jamais un joker, jamais un répertoire entier.
  ///
  /// Chacune est une phrase que le poste doit rendre **au mot** parce que le
  /// serveur (registre des paramètres, graines, fichiers de langue) l'écrit
  /// encore ainsi et qu'un test confronte les deux (aide du registre,
  /// descriptions des paramètres initiaux, message de dépense). Elle disparaît
  /// avec la phrase côté serveur — c'est alors à ce fichier de l'oublier.
  const exemptions = <({String fichier, String fragment, String motif})>[
    (
      fichier: 'lib/features/parametres/domain/registre_parametres_local.dart',
      fragment: 'RG-10 — écart de quantité toléré',
      motif:
          'Aide du paramètre « tolérance de réception », confrontée mot pour '
          'mot au registre du serveur (RegistreParametres.php).',
    ),
    (
      fichier: 'lib/features/parametres/domain/registre_parametres_local.dart',
      fragment: 'n’est pas tranchée (PA-08)',
      motif:
          'Aide du paramètre « rétention du journal d’audit », confrontée mot '
          'pour mot au registre du serveur.',
    ),
    (
      fichier: 'lib/features/parametres/domain/registre_parametres_local.dart',
      fragment: '(voir PA-36)',
      motif:
          'Description initiale du taux de TVA, égale au graineur serveur '
          '(parametres_initiaux_test).',
    ),
    (
      fichier: 'lib/features/parametres/domain/registre_parametres_local.dart',
      fragment: 'Convention des prix du catalogue',
      motif:
          'Description initiale de la convention de prix, égale au graineur '
          'serveur (parametres_initiaux_test).',
    ),
    (
      fichier: 'lib/features/parametres/domain/registre_parametres_local.dart',
      fragment: 'Résout PA-37',
      motif: 'Suite de la description initiale ci-dessus (même graineur).',
    ),
    (
      fichier: 'lib/features/parametres/domain/registre_parametres_local.dart',
      fragment: 'ou `ttc` (les tarifs',
      motif: 'Suite de la description initiale ci-dessus (même graineur).',
    ),
    (
      fichier:
          'lib/features/tourisme/presentation/widgets/modale_reservation.dart',
      fragment: 'départ entier (UC-39)',
      motif:
          'Note « note_guide_du_depart » de la vue (lang/fr/tourisme.php), '
          'rendue au mot tant que la vue web porte encore le code.',
    ),
  ];

  // ----------------------------------------------------- L'analyseur lexical

  /// Les littéraux de chaîne d'un source Dart, **commentaires exclus**. Une
  /// interpolation `${…}` est retirée du texte du littéral ; les littéraux
  /// qu'elle contient sont rendus à part.
  List<({int ligne, String texte})> litteraux(String src) {
    final sortie = <({int ligne, String texte})>[];

    /// Lit un littéral dont le guillemet ouvrant est en [debut] ; rend la
    /// position après le guillemet fermant.
    int lireLitteral(int debut, bool brut) {
      final triple =
          src.startsWith("'''", debut) || src.startsWith('"""', debut);
      final q = triple ? src.substring(debut, debut + 3) : src[debut];
      var i = debut + q.length;
      final texte = StringBuffer();
      while (i < src.length) {
        final c = src[i];
        if (!brut && c == r'\') {
          // Un échappement : on garde le caractère échappé tel quel.
          if (i + 1 < src.length) texte.write(src[i + 1]);
          i += 2;
          continue;
        }
        if (src.startsWith(q, i)) {
          i += q.length;
          break;
        }
        if (!brut && c == r'$' && i + 1 < src.length && src[i + 1] == '{') {
          // Interpolation : on saute l'expression, accolades équilibrées, en
          // relevant les littéraux qu'elle contient.
          var profondeur = 1;
          i += 2;
          while (i < src.length && profondeur > 0) {
            final d = src[i];
            if (d == '{') {
              profondeur++;
            } else if (d == '}') {
              profondeur--;
            } else if (d == "'" || d == '"') {
              i = lireLitteral(i, false);
              continue;
            }
            i++;
          }
          texte.write(' ');
          continue;
        }
        texte.write(c);
        i++;
      }
      sortie.add((
        ligne: '\n'.allMatches(src.substring(0, debut)).length + 1,
        texte: texte.toString(),
      ));
      return i;
    }

    var i = 0;
    while (i < src.length) {
      if (src.startsWith('//', i)) {
        final fin = src.indexOf('\n', i);
        i = fin < 0 ? src.length : fin;
        continue;
      }
      if (src.startsWith('/*', i)) {
        final fin = src.indexOf('*/', i + 2);
        i = fin < 0 ? src.length : fin + 2;
        continue;
      }
      final c = src[i];
      if (c == "'" || c == '"') {
        final brut = i > 0 && src[i - 1] == 'r';
        i = lireLitteral(i, brut);
        continue;
      }
      i++;
    }
    return sortie;
  }

  List<File> fichiersDeLib() {
    final racine = Directory('lib');
    if (!racine.existsSync()) {
      fail(
        'Le répertoire `lib/` est introuvable depuis ${Directory.current.path}. '
        'Cette garde échoue plutôt que de sauter : un balayage vide est vert, '
        'et c’est exactement le défaut qu’elle protège.',
      );
    }
    return racine
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !f.path.endsWith('.g.dart'))
        .toList();
  }

  String normaliser(File f) => f.path.replaceAll(r'\', '/');

  bool exempte(String fichier, String texte) =>
      exemptions.any((e) => e.fichier == fichier && texte.contains(e.fragment));

  /// Les violations d'un source : « ligne : motif : extrait ».
  List<String> violations(String fichier, String src) {
    final trouvees = <String>[];
    for (final l in litteraux(src)) {
      for (final e in motifs.entries) {
        if (e.value.hasMatch(l.texte) && !exempte(fichier, l.texte)) {
          final extrait = l.texte.length > 90
              ? '${l.texte.substring(0, 90)}…'
              : l.texte;
          trouvees.add('$fichier:${l.ligne} [${e.key}] « $extrait »');
        }
      }
    }
    return trouvees;
  }

  // =========================================================================
  test('l’analyseur voit un littéral et ignore un commentaire', () {
    const src = '''
// 'Sur ce poste : dans un commentaire'
/// 'PA-12 dans une doc'
/* 'RG-3 dans un bloc' */
const a = 'Sur ce poste : visible';
const b = r'PA-1 brut';
const c = "n'est pas porté";
const d = 'x \${cond ? 'D250' : 'ok'} y';
const e = \'\'\'multi
EF-M4-02 ligne\'\'\';
''';
    final textes = [for (final l in litteraux(src)) l.texte];
    expect(textes, contains('Sur ce poste : visible'));
    expect(textes, contains('PA-1 brut'));
    expect(textes, contains("n'est pas porté"));
    expect(textes, contains('D250'), reason: 'littéral dans une interpolation');
    expect(textes.any((t) => t.contains('EF-M4-02')), isTrue);
    expect(
      textes.any((t) => t.contains('dans un commentaire')),
      isFalse,
      reason: 'un commentaire n’est pas à l’écran',
    );
    expect(textes.any((t) => t.contains('dans une doc')), isFalse);
    expect(textes.any((t) => t.contains('dans un bloc')), isFalse);
  });

  test(
    'les motifs mordent sur un échantillon fabriqué, et épargnent le métier',
    () {
      String? mordu(String texte) {
        for (final e in motifs.entries) {
          if (e.value.hasMatch(texte)) return e.key;
        }
        return null;
      }

      // Positifs : une note de conception de chaque famille.
      expect(mordu('Sur ce poste : aperçu du jour.'), isNotNull);
      expect(mordu('Sur ce poste, aucune purge n’a lieu.'), isNotNull);
      expect(mordu('« Bilan » n’est pas porté sur ce poste.'), isNotNull);
      expect(mordu('Écran non porté.'), isNotNull);
      expect(mordu('Le total est non calculé.'), isNotNull);
      expect(mordu('Voir PA-36.'), isNotNull);
      expect(mordu('Écart D417 déclaré.'), isNotNull);
      expect(mordu('Fiche absente (EF-M4-02).'), isNotNull);
      expect(mordu('refusée (RG-05).'), isNotNull);
      expect(mordu('Le droit manque (M6).'), isNotNull);
      expect(mordu('Canaux (Module M12)'), isNotNull);
      expect(mordu('Le maître propose un texte libre.'), isNotNull);
      expect(mordu('ÉCART nommé avec la vue'), isNotNull);
      expect(mordu('un écart nommé'), isNotNull);
      expect(mordu('refus déclaré'), isNotNull);
      expect(mordu('jeu d’essai'), isNotNull);
      expect(mordu("jeu d'essai"), isNotNull);
      expect(mordu('ce que cet écran ne rend pas'), isNotNull);
      expect(mordu('constaté le 12/10/2026'), isNotNull);
      expect(mordu('colonne `reservations_tour.guide_id` absente'), isNotNull);

      // Négatifs : du texte métier légitime.
      expect(mordu('Écriture enregistrée sur ce poste.'), isNull);
      expect(mordu('Aucun compte sur ce poste.'), isNull);
      expect(mordu("Maîtrise d'œuvre"), isNull);
      expect(mordu('Cabinet FAGUEZ SARL / PAEB'), isNull);
      expect(
        mordu('Exercice 2026 clôturé : consultation en lecture seule.'),
        isNull,
      );
      expect(mordu('Écart de caisse : 1 500 FCFA'), isNull);
      expect(mordu('Le document est porté au dossier du client.'), isNull);
      expect(mordu('TOTAL ACTIF'), isNull);
      expect(
        mordu('M1'),
        isNull,
        reason: 'une clé de module seule est un code',
      );
    },
  );

  test(
    'la garde est armée : le moindre « Sur ce poste : » est vu (mutation)',
    () {
      // Preuve par mutation : on prend un littéral propre, on lui injecte
      // chaque famille de note, et la garde DOIT rougir. Sans ce test, un
      // analyseur qui ne rendrait plus aucun littéral laisserait la garde
      // verte sur n’importe quelle note.
      const propre = "const a = 'Écriture enregistrée.';";
      expect(violations('lib/x.dart', propre), isEmpty);
      for (final note in const [
        'Sur ce poste : rien ne se synchronise.',
        'Voir PA-12.',
        'écran non porté',
        'Le maître propose',
        'sera refusée (RG-05)',
      ]) {
        expect(
          violations('lib/x.dart', "const a = '$note';"),
          isNotEmpty,
          reason: note,
        );
      }
      // Et la même note en COMMENTAIRE ne rougit pas.
      expect(
        violations(
          'lib/x.dart',
          "// 'Sur ce poste : commentaire'\nconst a = 1;",
        ),
        isEmpty,
      );
    },
  );

  test('une exemption est nommée, motivée, et ne couvre qu’un fragment', () {
    for (final e in exemptions) {
      expect(e.motif.length, greaterThan(30), reason: e.fragment);
      expect(e.fragment.length, greaterThan(5), reason: 'pas un joker');
      expect(e.fichier, startsWith('lib/'));
      expect(File(e.fichier).existsSync(), isTrue, reason: e.fichier);
    }
    // Elle ne couvre que SON fragment, dans SON fichier.
    const e =
        'lib/features/tourisme/presentation/widgets/modale_reservation.dart';
    expect(
      exempte(e, 'le guide », qui porte sur le départ entier (UC-39).'),
      isTrue,
    );
    expect(
      exempte('lib/features/autre.dart', 'départ entier (UC-39)'),
      isFalse,
    );
    expect(exempte(e, 'RG-99 autre chose'), isFalse);
  });

  test('aucune note de conception dans les littéraux affichés de lib/', () {
    final fichiers = fichiersDeLib();
    expect(
      fichiers.length,
      greaterThanOrEqualTo(plancherFichiers),
      reason:
          'plancher de fichiers : un balayage sur trop peu de fichiers serait '
          'vert à vide',
    );

    final trouvees = <String>[];
    var litterauxVus = 0;
    for (final f in fichiers) {
      final src = f.readAsStringSync();
      litterauxVus += litteraux(src).length;
      trouvees.addAll(violations(normaliser(f), src));
    }
    expect(
      litterauxVus,
      greaterThan(5000),
      reason: 'l’analyseur doit voir des milliers de littéraux',
    );
    expect(
      trouvees,
      isEmpty,
      reason:
          'Notes de conception à l’écran (décision du Product Owner : '
          'aucune) — retirer ou réécrire en phrase métier :\n'
          '${trouvees.join('\n')}',
    );
  });

  test('chaque exemption est encore utile (sinon elle est retirée)', () {
    final sources = {
      for (final f in fichiersDeLib()) normaliser(f): f.readAsStringSync(),
    };
    for (final e in exemptions) {
      final src = sources[e.fichier]!;
      final utile = litteraux(src).any(
        (l) =>
            l.texte.contains(e.fragment) &&
            motifs.values.any((m) => m.hasMatch(l.texte)),
      );
      expect(
        utile,
        isTrue,
        reason:
            'L’exemption « ${e.fragment} » ne couvre plus aucun motif : la '
            'phrase a disparu ou a changé, retirer l’exemption.',
      );
    }
  });
}
