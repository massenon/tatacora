import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Garde : un mouvement d'argent du poste n'a qu'UN chemin, et ce chemin passe sa
/// pièce comptable (règle du Product Owner du 31/08/2026, lot 6 du 12/10/2026).
///
/// Trois mouvements sont gardés :
///
///  * **la vente** — un panier ne passe à `cloture` que par `PanierDao.cloturer`,
///    qui écrit la pièce `VTE` dans la même transaction ;
///  * **l'acompte** — une réservation ne naît avec son acompte que par
///    `ReservationDao.creer` (la pièce Dr trésorerie / Cr 4191) ;
///  * **l'annulation** — une réservation ne passe à `annulee` que par
///    `ReservationDao.annulerAvecConditions` (commission, remboursement, pièce
///    Dr 4191 / Cr 5711).
///
/// ## Un commentaire qui décrit un déclencheur n'est pas un déclencheur
///
/// Les trois gestes ont un APPELANT de production, relu ici dans le code : le
/// provider qui branche le moteur, et l'écran qui passe l'auteur. Un DAO sans
/// moteur LÈVE (jamais un mouvement sans pièce par omission) ; encore faut-il
/// que la production lui en donne un.
///
/// ## Le balayage s'ancre sur le texte, et prouve qu'il n'est pas vide
///
/// Un plancher de fichiers, et une copie contenant un écrivain factice que le
/// même balayage doit dénoncer — sinon la garde serait verte à vide.
///
/// ## Une garde qui ne connaît qu'UNE forme syntaxique est contournée par la deuxième
///
/// La première version ne reconnaissait que `statut: Value(StatutPanier.cloture.code)`
/// et un `UPDATE` nommant la table : un écrivain factice `statut: Value('cloture')`
/// (littéral) la laissait verte (réserve MAJEURE du contrôle indépendant du lot 6).
/// Les motifs visent donc la VALEUR écrite, pas la table ni le nom du paramètre :
///
///  * un `Value(…)`, `Variable(…)`, `Variable.withString(…)` ou `Constant(…)`
///    dont l'expression contient le mot (littéral simple ou double, enum
///    quelconque, `.code`, `.name`, ternaire) ;
///  * une clé de carte `'statut': 'cloture'` ;
///  * une constante qui porte le littéral (`const k = 'cloture';`) ;
///  * un alias d'enum `X.cloture.code|name|cle|valeur` ;
///  * un `UPDATE … SET … statut = 'cloture'` ou un `INSERT INTO … VALUES (…'cloture'…)`
///    sur n'importe quelle table, guillemets simples, doubles ou échappés.
///
/// Les enums d'AUTRES domaines qui portent le même mot ont leur écrivain propre
/// et sont nommés ici (`_etrangersCloture`, `_etrangersAnnulation`) : l'exercice
/// comptable (`StatutExercice.cloture`), la pièce de facturation, le bulletin de
/// paie et la réservation de circuit. Un nouvel enum qui entre dans ce cas doit
/// être ajouté à la main, donc relu.
///
/// **Limites dites** : une valeur passée par une variable (`Value(s)` où `s` vient
/// d'un paramètre) ou un `copyWith(statut: X.cloture)` sur une entité de domaine
/// ne sont pas dénoncés ; l'alias `X.cloture.code` qui alimente ce `s` l'est, lui.
const _etrangersCloture = 'StatutExercice';
const _etrangersAnnulation = 'StatutPiece|StatutBulletin|StatutReservationTour';

/// Un guillemet simple ou double, éventuellement échappé par un antislash.
const _guillemet = r'\\?[\x27\x22]';
const _guillemetNu = r'[\x27\x22]';

/// Les formes d'écriture de [mot] en base, hors enums d'autres domaines.
List<RegExp> _formesDEcriture(String mot, String etrangers) => <RegExp>[
  // Value / Variable / Constant dont l'expression (sans virgule ni parenthèse)
  // contient le mot : littéraux, enums, `.code`, `.name`, ternaire.
  RegExp(
    r'\b(?:Value|Variable|Constant)(?:\.withString)?(?:<[^>]*>)?\(\s*'
    '(?:const\\s+)?(?!(?:$etrangers)\\.)[^;,)]*?(?:\\.|$_guillemetNu)$mot\\b',
  ),
  // Clé de carte brute.
  RegExp('${_guillemetNu}statut$_guillemetNu\\s*:\\s*$_guillemetNu$mot\\b'),
  // Constante qui porte le littéral.
  RegExp(
    '\\b(?:const|final|static|var)\\b[^;=]*=\\s*$_guillemetNu$mot$_guillemetNu\\s*;',
  ),
  // Alias d'enum : `X.cloture.code`.
  RegExp('\\b(?!(?:$etrangers)\\.)\\w+\\.$mot\\.(?:code|name|cle|valeur)\\b'),
  // SQL direct, n'importe quelle table.
  RegExp(
    '\\bUPDATE\\s+\\w+\\s+SET\\b[^;]*?\\bstatut\\s*=\\s*$_guillemet$mot\\b',
    caseSensitive: false,
  ),
  RegExp(
    '\\bINSERT\\s+(?:OR\\s+\\w+\\s+)?INTO\\s+\\w+[^;]*?\\bVALUES\\b[^;]*?$_guillemet$mot\\b',
    caseSensitive: false,
  ),
];

final _ecrivainsDeCloture = _formesDEcriture('cloture', _etrangersCloture);

final _ecrivainsDAnnulation = _formesDEcriture('annulee', _etrangersAnnulation);

/// L'ANCIENNE garde (une forme Drift, un UPDATE nommant la table) : conservée
/// comme TÉMOIN, pour prouver que les écrivains factices ci-dessous lui
/// échappaient réellement.
final _ancienneGardeDeCloture = <RegExp>[
  RegExp(r'statut:\s*Value\(\s*StatutPanier\.cloture\.code\s*\)'),
  RegExp(
    r"UPDATE\s+paniers_local\s+SET[^;']*statut\s*=\s*'cloture'",
    caseSensitive: false,
  ),
];

/// Les fichiers de [racine] dont le CODE (hors commentaires) contient un des
/// motifs.
List<String> _fichiersQuiEcrivent(Directory racine, List<RegExp> motifs) {
  final trouves = <String>[];
  for (final f in racine.listSync(recursive: true).whereType<File>()) {
    if (!f.path.endsWith('.dart') || f.path.endsWith('.g.dart')) continue;
    final code = f
        .readAsLinesSync()
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');
    if (motifs.any((r) => r.hasMatch(code))) {
      trouves.add(f.path.replaceAll(r'\', '/'));
    }
  }
  return trouves..sort();
}

String _source(String chemin) => File(chemin).readAsStringSync();

void main() {
  test('plancher : le balayage voit assez de fichiers pour compter', () {
    final n = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .length;
    expect(n, greaterThan(300));
  });

  group('un panier ne se clôture que par PanierDao.cloturer', () {
    test('un seul fichier de lib/ écrit le statut `cloture`', () {
      final fichiers = _fichiersQuiEcrivent(
        Directory('lib'),
        _ecrivainsDeCloture,
      );
      expect(
        fichiers.map((f) => f.split('/lib/').last.replaceFirst('lib/', '')),
        ['features/pos/data/panier_dao.dart'],
        reason:
            'Une clôture hors de `PanierDao.cloturer` encaisserait sans '
            'pièce comptable : la caisse bougerait, le grand livre non.',
      );
    });

    test('et ce fichier passe la pièce dans la même transaction', () {
      final code = _source('lib/features/pos/data/panier_dao.dart');
      final cloturer = code.substring(code.indexOf('Future<Panier> cloturer('));
      // Le moteur est exigé AVANT toute lecture, la pièce passée AVANT l'écriture
      // du statut : une pièce refusée n'écrit rien.
      final exige = cloturer.indexOf('_moteurObligatoire()');
      final piece = cloturer.indexOf('moteurComptable.passerEtValider(');
      final statut = cloturer.indexOf('StatutPanier.cloture.code');
      expect(exige, greaterThan(-1));
      expect(piece, greaterThan(exige));
      expect(statut, greaterThan(piece));
      expect(cloturer, contains('await transaction('));
    });

    test('la production branche le moteur et nomme l\'auteur', () {
      expect(
        _source('lib/features/pos/presentation/providers_pos.dart'),
        contains('moteur: () => ref.read(moteurComptableProvider.future)'),
      );
      expect(
        _source('lib/features/pos/presentation/widgets/vue_panier.dart'),
        contains('auteurId: ref.read(sessionProvider)?.utilisateurId'),
      );
      expect(
        _source(
          'lib/features/pos/presentation/widgets/modale_cloture_sejour.dart',
        ),
        contains('auteurId: ref.read(sessionProvider)?.utilisateurId'),
      );
    });
  });

  group('une réservation naît avec la pièce de son acompte', () {
    test('la création de production passe par `creer`, jamais `enregistrer`', () {
      expect(
        _source(
          'lib/features/hebergement/domain/usecases/creer_reservation.dart',
        ),
        contains('_depot.creer(reservation, auteurId: auteurId)'),
      );
      // Aucune autre écriture brute de réservation dans lib/ que le dépôt
      // lui-même, le DAO et le mode démo (qui écrit des données d'exemple, comme
      // `enregistrerHistoriqueSansPiece` des dépenses).
      final appelants = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        if (f.path.endsWith('.g.dart')) continue;
        final code = f
            .readAsLinesSync()
            .where((l) => !l.trimLeft().startsWith('//'))
            .join('\n');
        final touche =
            code.contains('ReservationDao') ||
            code.contains('ReservationRepository') ||
            code.contains('depotReservationProvider');
        if (touche && RegExp(r'\.enregistrer\(').hasMatch(code)) {
          appelants.add(f.path.replaceAll(r'\', '/'));
        }
      }
      expect(appelants..sort(), [
        'lib/core/dev/mode_demo.dart',
        'lib/features/hebergement/data/reservation_repository_local.dart',
      ]);
    });

    test('la production branche le moteur et nomme l\'auteur', () {
      expect(
        _source(
          'lib/features/hebergement/presentation/providers_hebergement.dart',
        ),
        contains('moteur: () => ref.read(moteurComptableProvider.future)'),
      );
      expect(
        _source('lib/features/hebergement/presentation/fiche_reservation.dart'),
        contains('auteurId: ref.read(sessionProvider)?.utilisateurId'),
      );
    });
  });

  group('une réservation ne s\'annule que par annulerAvecConditions', () {
    test('un seul fichier de lib/ écrit le statut `annulee`', () {
      final fichiers = _fichiersQuiEcrivent(
        Directory('lib'),
        _ecrivainsDAnnulation,
      );
      expect(
        fichiers.map((f) => f.split('/lib/').last.replaceFirst('lib/', '')),
        ['features/hebergement/data/reservation_dao.dart'],
        reason:
            'Une annulation hors de `annulerAvecConditions` laisserait '
            'l\'acompte dans les comptes comme s\'il était encore dû au client.',
      );
    });

    test('et la modale appelle le cas d\'usage avec l\'auteur', () {
      final modale = _source(
        'lib/features/hebergement/presentation/widgets/modale_annulation_reservation.dart',
      );
      expect(modale, contains('annulerReservationProvider'));
      expect(modale, contains('auteurId: ref.read(sessionProvider)'));
    });
  });

  group('preuve par mutation : un écrivain factice dans une COPIE', () {
    late Directory copie;

    // La copie est faite UNE fois ; chaque cas y pose son faux écrivain puis le
    // retire (copier lib/ une quarantaine de fois coûterait trois minutes).
    setUpAll(() {
      copie = Directory.systemTemp.createTempSync('pieces_garde_');
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        File('${copie.path}/${f.path}')
          ..createSync(recursive: true)
          ..writeAsStringSync(f.readAsStringSync());
      }
    });

    tearDown(() {
      final faux = File('${copie.path}/lib/features/faux_mouvement.dart');
      if (faux.existsSync()) faux.deleteSync();
    });

    tearDownAll(() => copie.deleteSync(recursive: true));

    void ajouter(String contenu) =>
        File('${copie.path}/lib/features/faux_mouvement.dart')
          ..createSync(recursive: true)
          ..writeAsStringSync(contenu);

    test('la copie intacte a ses écrivains légitimes, et eux seuls', () {
      expect(_fichiersQuiEcrivent(copie, _ecrivainsDeCloture), hasLength(1));
      expect(_fichiersQuiEcrivent(copie, _ecrivainsDAnnulation), hasLength(1));
    });

    // Chaque forme est jouée pour LES DEUX statuts gardés. Un écrivain factice
    // ajouté à la copie doit faire passer le décompte de 1 à 2.
    final antislash = String.fromCharCode(92);
    final formes = <String, String Function(String mot, String enumQualifie)>{
      'littéral simple dans Value': (m, e) =>
          "final c = XCompanion(statut: Value('$m'));",
      'littéral double dans Value': (m, e) =>
          'final c = XCompanion(statut: Value("$m"));',
      'Value typé': (m, e) =>
          "final c = XCompanion(statut: Value<String>('$m'));",
      'const Value': (m, e) =>
          "final c = XCompanion(statut: const Value('$m'));",
      'Variable liée': (m, e) => "final v = Variable.withString('$m');",
      'ternaire dans Value': (m, e) =>
          "final c = XCompanion(statut: Value(ok ? '$m' : 'x'));",
      'enum quelconque .code': (m, e) =>
          'final c = XCompanion(statut: Value($e.code));',
      'enum quelconque .name': (m, e) =>
          'final c = XCompanion(statut: Value($e.name));',
      'alias d\'enum dans une variable': (m, e) => 'final s = $e.code;',
      'clé de carte brute': (m, e) => "final r = {'statut': '$m'};",
      'constante littérale': (m, e) => "const kStatut = '$m';",
      'customStatement, guillemets simples dans du double': (m, e) =>
          'Future<void> f(d) => d.customStatement('
          "\"UPDATE autre_table SET statut = '$m' WHERE id = 1\");",
      'customStatement, guillemets doubles dans du simple': (m, e) =>
          'Future<void> f(d) => d.customStatement('
          "'UPDATE autre_table SET statut = \"$m\" WHERE id = 1');",
      'customUpdate, guillemets échappés': (m, e) =>
          'Future<int> f(d) => d.customUpdate('
          "'UPDATE autre_table SET montant = 1, statut = "
          "$antislash'$m$antislash' WHERE id = 1');",
      'UPDATE en minuscules et sans espaces': (m, e) =>
          "const s = \"update autre set statut='$m'\";",
      'INSERT SQL': (m, e) =>
          "const s = \"INSERT INTO autre (id, statut) VALUES ('1', '$m')\";",
    };
    final statuts = <String, ({List<RegExp> motifs, String enumQualifie})>{
      'cloture': (
        motifs: _ecrivainsDeCloture,
        enumQualifie: 'StatutPanier.cloture',
      ),
      'annulee': (
        motifs: _ecrivainsDAnnulation,
        enumQualifie: 'StatutReservation.annulee',
      ),
    };

    for (final s in statuts.entries) {
      for (final f in formes.entries) {
        test('${s.key} : ${f.key} est dénoncé', () {
          // La copie intacte n'a que son écrivain légitime.
          expect(_fichiersQuiEcrivent(copie, s.value.motifs), hasLength(1));
          ajouter(f.value(s.key, s.value.enumQualifie));
          expect(
            _fichiersQuiEcrivent(copie, s.value.motifs),
            hasLength(2),
            reason: 'La forme « ${f.key} » doit être dénoncée.',
          );
        });
      }
    }

    test(
      'l\'ANCIENNE garde laissait passer le littéral : le témoin le prouve',
      () {
        // Sans cela, rien ne dirait que les nouvelles formes ferment un trou
        // réel plutôt que d'en décrire un imaginaire.
        ajouter("final c = PaniersLocalCompanion(statut: Value('cloture'));");
        expect(
          _fichiersQuiEcrivent(copie, _ancienneGardeDeCloture),
          hasLength(1),
        );
        expect(_fichiersQuiEcrivent(copie, _ecrivainsDeCloture), hasLength(2));
      },
    );

    test('une clôture par l\'enum de Drift est dénoncée', () {
      ajouter(
        'final c = PaniersLocalCompanion(statut: Value(StatutPanier.cloture.code));',
      );
      expect(_fichiersQuiEcrivent(copie, _ecrivainsDeCloture), hasLength(2));
    });

    test('une annulation par l\'enum de Drift est dénoncée', () {
      ajouter(
        'final c = ReservationsLocalCompanion('
        'statut: Value(StatutReservation.annulee.code));',
      );
      expect(_fichiersQuiEcrivent(copie, _ecrivainsDAnnulation), hasLength(2));
    });

    test('un simple commentaire ne l\'est pas', () {
      ajouter(
        '// statut: Value(StatutPanier.cloture.code) : ne jamais écrire.\n'
        "// statut: Value('annulee')",
      );
      expect(_fichiersQuiEcrivent(copie, _ecrivainsDeCloture), hasLength(1));
      expect(_fichiersQuiEcrivent(copie, _ecrivainsDAnnulation), hasLength(1));
    });

    test('une LECTURE du même mot n\'est pas dénoncée', () {
      ajouter(
        "final q = d.customSelect(\"SELECT * FROM x WHERE statut = 'cloture'\");\n"
        "final r = t.statut.equals('annulee').not();",
      );
      expect(_fichiersQuiEcrivent(copie, _ecrivainsDeCloture), hasLength(1));
      expect(_fichiersQuiEcrivent(copie, _ecrivainsDAnnulation), hasLength(1));
    });

    test(
      'l\'enum d\'un AUTRE domaine a son écrivain et n\'est pas dénoncé',
      () {
        ajouter(
          'final a = C(statut: Value(StatutExercice.cloture.valeur));\n'
          'final b = C(statut: Value(StatutPiece.annulee.code));',
        );
        expect(_fichiersQuiEcrivent(copie, _ecrivainsDeCloture), hasLength(1));
        expect(
          _fichiersQuiEcrivent(copie, _ecrivainsDAnnulation),
          hasLength(1),
        );
      },
    );
  });
}
