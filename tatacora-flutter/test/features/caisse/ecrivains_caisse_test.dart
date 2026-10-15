import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Les faits de structure que la caisse tient — et qui se périment en silence si
/// personne ne les garde (PA-144).
///
/// 1. **Un seul auteur** : `SessionsCaisseDao` est le SEUL code de `lib/` qui
///    écrit `sessions_caisse_local` (piège 9 : une colonne que personne n'écrit
///    n'est jamais affichée ; piège inverse : deux auteurs divergent).
/// 2. **Aucune pièce comptable** : le serveur n'en passe aucune à l'ouverture ni
///    à la clôture, donc ce code n'importe ni le moteur comptable ni la
///    comptabilité. Le jour où le serveur en passera une, ce test devra être
///    rouvert AVEC elle, dans la même transaction (règle du 31/08/2026).
/// 3. **Aucun réseau** : zéro réseau (décision du PO, 14/09/2026).
/// 4. **Deux lectures, un appelant chacune** (lot 5, 12/10/2026) :
///    `sessionOuverteLaPlusRecente` est appelée par l'encaissement de facture
///    (D169), `sessions` par le KPI « Trésorerie de caisse » de M11. Avant le
///    lot 5 elles n'avaient AUCUN appelant, et ce cas le disait ; il dit
///    maintenant QUI les appelle, pour qu'un troisième appelant rouvre la
///    question (l'indicateur de la barre supérieure, D222, n'en est pas un
///    encore).
///
/// Le balayage s'ANCRE sur le texte du code et prouve qu'il n'est pas vide : un
/// plancher de fichiers, et un échantillon fabriqué que les mêmes motifs doivent
/// dénoncer (sinon la garde serait verte à vide).
final _ecrivains = <RegExp>[
  RegExp(r'\b(into|update|delete)\(\s*(\w+\.)*sessionsCaisseLocal\b'),
  RegExp(r'\bSessionsCaisseLocalCompanion\b'),
  RegExp(r'\bbatch\.\w+\(\s*(\w+\.)*sessionsCaisseLocal\b'),
  RegExp(
    r'(INSERT\s+(OR\s+\w+\s+)?INTO|UPDATE|DELETE\s+FROM)\s+sessions_caisse_local',
    caseSensitive: false,
  ),
  // Le DAO écrit par `into(_t)` / `update(_t)` : l'alias privé de la table.
  RegExp(r'\b(into|update|delete)\(\s*_t\s*\)'),
];

const String _dao = 'lib/features/caisse/data/sessions_caisse_dao.dart';

String _code(File f) =>
    f.readAsLinesSync().where((l) => !l.trimLeft().startsWith('//')).join('\n');

List<File> _fichiers(Directory racine) => racine
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'))
    .toList();

String _p(File f) => f.path.replaceAll(r'\', '/');

void main() {
  final lib = Directory('lib');
  final caisse = Directory('lib/features/caisse');

  test('le balayage n’est pas vide, et ses motifs mordent', () {
    expect(_fichiers(lib).length, greaterThan(200));
    expect(_fichiers(caisse).length, greaterThanOrEqualTo(8));

    // Un échantillon fabriqué que CHAQUE famille de motif doit dénoncer.
    for (final factice in [
      'await db.into(db.sessionsCaisseLocal).insert(x);',
      'await (update(db.sessionsCaisseLocal)..where(w)).write(y);',
      'final c = SessionsCaisseLocalCompanion.insert(a);',
      "await db.customStatement('INSERT INTO sessions_caisse_local VALUES (1)');",
      "await customStatement('update SESSIONS_CAISSE_LOCAL set x = 1');",
      'await into(_t).insert(z);',
      'await (update(_t)..where(w)).write(y);',
    ]) {
      expect(
        _ecrivains.any((r) => r.hasMatch(factice)),
        isTrue,
        reason: 'le motif ne dénonce pas : $factice',
      );
    }
    // Et une lecture n'est pas une écriture.
    expect(
      _ecrivains.any((r) => r.hasMatch('final l = select(_t)..where(w);')),
      isFalse,
    );
  });

  test('un seul auteur : SessionsCaisseDao écrit sessions_caisse_local', () {
    final auteurs = <String>[];
    for (final f in _fichiers(lib)) {
      if (_p(f).contains('lib/core/database/')) continue;
      if (_ecrivains.any((r) => r.hasMatch(_code(f)))) auteurs.add(_p(f));
    }
    // Le DAO écrit : sans cette ligne, un motif cassé ferait croire que PERSONNE
    // n'écrit — et le test serait vert sur une table sans auteur.
    expect(auteurs, contains(_dao));
    expect(
      auteurs.where((a) => a != _dao),
      isEmpty,
      reason:
          'Un second auteur de `sessions_caisse_local` est apparu : deux '
          'chemins d’écriture divergeront (règle « un référentiel a UN SEUL '
          'AUTEUR »).',
    );
  });

  test('la caisse ne touche ni le moteur comptable ni la comptabilité', () {
    // Le serveur ne passe aucune pièce à l'ouverture/clôture de caisse
    // (`PosComptant::ouvrirCaisse` / `cloturerCaisse`).
    for (final f in _fichiers(caisse)) {
      final code = _code(f);
      expect(
        RegExp(
              r"import\s+'[^']*(comptabilite|moteur_comptable|ecritures)[^']*'",
            )
            .allMatches(code)
            .where(
              // Le SEUL import toléré : la conversion pure centimes <-> chaîne à
              // deux décimales (« 28000.00 »), que la modale de clôture écrit dans le
              // champ compté. Ni le moteur, ni un DAO, ni une écriture.
              (m) => !m.group(0)!.contains('montant_comptable.dart'),
            ),
        isEmpty,
        reason: '${_p(f)} importe la comptabilité',
      );
      expect(code.contains('MoteurComptable'), isFalse, reason: _p(f));
      expect(code.contains('ecritures_local'), isFalse, reason: _p(f));
    }
  });

  test('aucun réseau dans la caisse (zéro réseau)', () {
    for (final f in _fichiers(caisse)) {
      final code = _code(f);
      expect(
        RegExp(
          r"import\s+'package:(dio|http)/|HttpClient|localhost|/api/",
        ).hasMatch(code),
        isFalse,
        reason: '${_p(f)} parle au réseau',
      );
    }
  });

  test('aucune session « en attente de synchronisation » : la caisse ne part '
      'nulle part', () {
    for (final f in _fichiers(caisse)) {
      final code = _code(f).toLowerCase();
      // Les phrases qui NIENT la synchronisation sont des commentaires/docs ;
      // le code rendu ne doit jamais l'affirmer.
      expect(code.contains('statutsync'), isFalse, reason: _p(f));
      expect(code.contains("'en_attente"), isFalse, reason: _p(f));
    }
  });

  test('deux lectures ont DÉSORMAIS des appelants de production, ÉPINGLÉS '
      '(lot 5 et lot 1 « coquille », 12/10/2026)', () {
    // Ce cas ÉPINGLE les appelants RÉELS de production (revu le 12/10/2026,
    // R5 : prouvé par mutation — écrire `.sessions( )` dans l'écran du tableau
    // de bord le fait rougir sur une liste vide). Historique : avant le lot 5,
    // il affirmait qu'il n'y en avait aucun, ce qui était vrai alors.
    // L'encaissement de facture appelle `sessionOuverteLaPlusRecente` (tous
    // points confondus, comme `EncaissementFactureService`) ; le KPI
    // « Trésorerie de caisse » de M11 appelle `sessions()`. Un troisième appelant
    // rouvre la question de savoir quelle définition du tiroir il lit.
    //
    // Rouverte et tranchée le 12/10/2026 (lot 1 « coquille », D310) :
    // l'indicateur de caisse de la barre supérieure (`indicateurCaisseProvider`,
    // `providers_caisse.dart`) réplique `IndicateurCaisse::pour()`, qui lit
    // EXACTEMENT cette définition — `whereNull('date_cloture')
    // ->orderByDesc('date_ouverture')->first()`, tous points confondus. Même
    // tiroir que l'encaissement de facture, par construction du serveur.
    final appelants = <String, List<String>>{
      'sessionOuverteLaPlusRecente': [],
      'sessions()': [],
    };
    for (final f in _fichiers(lib)) {
      final chemin = _p(f);
      if (chemin == _dao ||
          chemin.endsWith('sessions_caisse_repository.dart')) {
        continue;
      }
      final code = _code(f);
      if (code.contains('sessionOuverteLaPlusRecente')) {
        appelants['sessionOuverteLaPlusRecente']!.add(chemin);
      }
      if (RegExp(r'\.sessions\(\)').hasMatch(code)) {
        appelants['sessions()']!.add(chemin);
      }
    }
    expect(appelants['sessionOuverteLaPlusRecente'], [
      'lib/features/caisse/presentation/providers_caisse.dart',
      'lib/features/facturation/data/paiements_facture_dao.dart',
    ]);
    // Lot B du 14/10/2026 : la cloche dérive l'alerte « caisse ouverte depuis
    // la veille » de la même lecture (`providers_alertes.dart`).
    expect(appelants['sessions()'], [
      'lib/features/alertes/presentation/providers_alertes.dart',
      'lib/features/tableau_de_bord/presentation/ecran_tableau_de_bord.dart',
    ]);
  });
}
