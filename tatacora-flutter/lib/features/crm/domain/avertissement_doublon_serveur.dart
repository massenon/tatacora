/// RG-18 — l'avertissement de doublon que le SERVEUR rend à la création d'un
/// client depuis l'accueil (`EnregistrementClientService::creer` →
/// `DetectionDoublonService`), répliqué en fonction PURE (lot C, 14/10/2026).
///
/// ## Pourquoi pas `doublonsPotentiels`
///
/// `detection_doublons.dart` porte la règle de l'écran Clients (le maître :
/// nom normalisé identique, ou téléphone identique d'au moins huit chiffres).
/// Le serveur, lui, NOTE chaque fiche : téléphone identique (100), nom
/// identique (60), nom très proche — Levenshtein ≤ 2 sur des noms d'au moins
/// quatre caractères (35) —, et ne signale qu'à partir de 60. Ce sont deux
/// règles différentes pour la même RG ; les modales de l'accueil suivent celle
/// du serveur, au mot (règle « le serveur fait foi »). L'écart entre les deux
/// est une incohérence du dépôt, à remonter (D-ticket du lot C).
///
/// L'avertissement N'EMPÊCHE RIEN : la fiche est créée, la phrase est
/// affichée à la place du message de succès (`terminerFormulaire(
/// $resultat['avertissement_doublon'] ?? succes)`).
///
/// @see RG-18 Référentiel client unique
library;

import 'detection_doublons.dart' show cleDeNom, chiffresDe;
import 'entities/client.dart';

/// `DetectionDoublonService::messageAvertissement(rechercherDoublons(nom,
/// telephone))` — `null` quand aucune fiche n'atteint le seuil.
String? avertissementDoublonServeur({
  required List<Client> referentiel,
  required String nom,
  required String telephone,
}) {
  final nomNormalise = cleDeNom(nom);
  final telephoneNormalise = chiffresDe(telephone);

  final notes = <({Client client, int score, String motif, int rang})>[];
  for (final (rang, candidat) in referentiel.indexed) {
    var score = 0;
    final motifs = <String>[];
    if (telephoneNormalise.isNotEmpty &&
        chiffresDe(candidat.telephone) == telephoneNormalise) {
      score += 100;
      motifs.add('même numéro de téléphone');
    }
    final nomCandidat = cleDeNom(candidat.nom);
    if (nomCandidat == nomNormalise) {
      score += 60;
      motifs.add('nom identique');
    } else if (_nomsProches(nomCandidat, nomNormalise)) {
      score += 35;
      motifs.add('nom très proche');
    }
    if (score < 60) continue;
    notes.add((
      client: candidat,
      score: score,
      motif: motifs.join(', '),
      rang: rang,
    ));
  }
  if (notes.isEmpty) return null;

  // `sortByDesc('score')` : tri STABLE de PHP 8, l'ordre de lecture départage.
  notes.sort((a, b) {
    final parScore = b.score.compareTo(a.score);
    return parScore != 0 ? parScore : a.rang.compareTo(b.rang);
  });

  final noms = notes
      .take(3)
      // `nomComplet()` : `trim(prenom . ' ' . nom)`.
      .map(
        (n) =>
            '${'${n.client.prenom ?? ''} ${n.client.nom}'.trim()} (${n.motif})',
      )
      .join(' ; ');
  return 'Une fiche existante pourrait correspondre : $noms. '
      'Vérifiez avant de créer un doublon.';
}

/// `nomsProches` : une faute de frappe courte sur des noms assez longs.
bool _nomsProches(String a, String b) {
  if (a.isEmpty ||
      b.isEmpty ||
      (a.length < b.length ? a.length : b.length) < 4) {
    return false;
  }
  return _levenshtein(a, b) <= 2;
}

/// `levenshtein()` de PHP (coûts unitaires), sur les caractères normalisés.
int _levenshtein(String a, String b) {
  var precedente = List<int>.generate(b.length + 1, (j) => j);
  for (var i = 1; i <= a.length; i++) {
    final courante = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cout = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      final suppression = precedente[j] + 1;
      final insertion = courante[j - 1] + 1;
      final substitution = precedente[j - 1] + cout;
      var m = suppression < insertion ? suppression : insertion;
      if (substitution < m) m = substitution;
      courante[j] = m;
    }
    precedente = courante;
  }
  return precedente[b.length];
}
