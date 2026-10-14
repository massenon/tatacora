/// La marge sur coûts directs PAR CENTRE, calculée sur le poste — réplique de
/// `AnalytiqueService::genererPourExercice` (`App\Domain\Comptabilite`), le
/// calcul que la vue d'accueil trace dans « Marge sur coûts directs par
/// activité » (`Accueil::margeParActivite`, 13/10/2026, décision du PO).
///
/// ## Ce qui est répliqué, à l'identique
///
///  * L'agrégation porte sur les écritures de l'exercice OUVERT, statuts
///    `brouillon` ET `validee` (`EcritureComptable::STATUTS`), groupées par
///    (centre, CLASSE du compte) — la classe, jamais la `nature`, qui est
///    nullable.
///  * Classe 7 = produit ; classe 6 = charge ; classe 8 selon le SENS RÉEL du
///    solde (créditeur = produit, débiteur = charge). Les classes 1 à 5 (bilan)
///    ne sont ni l'un ni l'autre : un encaissement n'est pas un produit.
///  * ⚠ Le solde de la classe 8 est celui de la CLASSE ENTIÈRE du centre, pas
///    celui de chaque compte : une cession (821, créditrice) et sa valeur
///    comptable (812, débitrice) se compensent, et seul le net va aux produits
///    ou aux charges — alors que le commentaire du serveur promet de les
///    classer séparément. Défaut du SERVEUR (son `GROUP BY` porte sur la
///    classe), répliqué tel quel et à remonter à l'Architecte ; confronté par
///    `moteur_contre_serveur_test.dart`.
///  * `résultat = produits − charges` ; un centre sans écriture n'a PAS de
///    ligne (« Tourisme : 0 F » laisserait croire à une activité déficitaire).
///  * Tri par résultat décroissant, stable sur l'ordre des libellés.
///
/// ## Un écart, nommé
///
/// Le serveur trie d'abord ses agrégats par libellé selon la collation
/// `utf8mb4_unicode_ci` (insensible à la casse et aux accents) ; ce poste
/// approche cette collation (minuscules, accents retirés). L'ordre ne compte
/// qu'entre deux centres de MÊME résultat.
///
/// Montants en CENTIMES entiers (le serveur : `DECIMAL(15,2)` et `bc*`).
///
/// @see EF-M10-03 Comptabilité analytique par centre de coût
/// @see RG-12 Centre de coût obligatoire sur toute écriture
library;

import 'entities/pilotage.dart';

/// Un agrégat (centre, classe) — la ligne du `GROUP BY` du serveur.
final class AgregatAnalytique {
  const AgregatAnalytique({
    required this.centreId,
    required this.centreLibelle,
    required this.classe,
    required this.debitCentimes,
    required this.creditCentimes,
    required this.nombreLignes,
  });

  final String centreId;
  final String centreLibelle;
  final String classe;
  final int debitCentimes;
  final int creditCentimes;
  final int nombreLignes;
}

/// Une ligne du résultat, en centimes.
final class MargeCentre {
  const MargeCentre({
    required this.centreId,
    required this.libelle,
    required this.produitsCentimes,
    required this.chargesCentimes,
    required this.nombreLignes,
  });

  final String centreId;
  final String libelle;
  final int produitsCentimes;
  final int chargesCentimes;
  final int nombreLignes;

  int get resultatCentimes => produitsCentimes - chargesCentimes;
}

/// `genererPourExercice` sur des agrégats déjà groupés par (centre, classe).
List<MargeCentre> margesParCentre(List<AgregatAnalytique> agregats) {
  // L'ordre d'arrivée du serveur : `orderBy('centres_cout.libelle')`.
  final tries = [...agregats]
    ..sort(
      (a, b) => _cleCollation(
        a.centreLibelle,
      ).compareTo(_cleCollation(b.centreLibelle)),
    );

  final parCentre = <String, _Cumul>{};
  for (final a in tries) {
    final c = parCentre.putIfAbsent(
      a.centreId,
      () => _Cumul(a.centreId, a.centreLibelle),
    );
    c.lignes += a.nombreLignes;
    // `net = débit − crédit` : un produit est créditeur (net négatif).
    final net = a.debitCentimes - a.creditCentimes;
    final estProduit = a.classe == '7' || (a.classe == '8' && net < 0);
    if (estProduit) {
      c.produits += -net;
      continue;
    }
    if (a.classe == '6' || a.classe == '8') {
      c.charges += net;
    }
  }

  final lignes = [
    for (final c in parCentre.values)
      MargeCentre(
        centreId: c.id,
        libelle: c.libelle,
        produitsCentimes: c.produits,
        chargesCentimes: c.charges,
        nombreLignes: c.lignes,
      ),
  ];
  // `usort` par résultat décroissant (PHP 8 : tri STABLE).
  final indexes = List<int>.generate(lignes.length, (i) => i)
    ..sort((i, j) {
      final c = lignes[j].resultatCentimes.compareTo(
        lignes[i].resultatCentimes,
      );
      return c != 0 ? c : i.compareTo(j);
    });
  return [for (final i in indexes) lignes[i]];
}

/// Ce que l'onglet Pilotage consomme : le libellé et le résultat en chaîne
/// décimale à deux chiffres, comme `LigneAnalytique::resultat`.
AnalytiquePilotage versAnalytiquePilotage(List<MargeCentre> marges) =>
    AnalytiquePilotage(
      // `repartitionStructureEffectuee: false` au serveur, toujours.
      repartitionStructureEffectuee: false,
      centres: [
        for (final m in marges)
          CentreAnalytique(
            libelle: m.libelle,
            resultat: decimaleDeCentimes(m.resultatCentimes),
            nombreLignes: m.nombreLignes,
          ),
      ],
    );

/// `12345` -> `'123.45'`, `-5` -> `'-0.05'`.
String decimaleDeCentimes(int centimes) {
  final negatif = centimes < 0;
  final absolu = centimes.abs();
  return '${negatif ? '-' : ''}${absolu ~/ 100}.'
      '${(absolu % 100).toString().padLeft(2, '0')}';
}

final class _Cumul {
  _Cumul(this.id, this.libelle);

  final String id;
  final String libelle;
  int produits = 0;
  int charges = 0;
  int lignes = 0;
}

/// Une approximation de `utf8mb4_unicode_ci` : minuscules, accents français
/// retirés.
String _cleCollation(String s) {
  const accents = {
    'à': 'a',
    'â': 'a',
    'ä': 'a',
    'á': 'a',
    'ç': 'c',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'î': 'i',
    'ï': 'i',
    'í': 'i',
    'ô': 'o',
    'ö': 'o',
    'ó': 'o',
    'ù': 'u',
    'û': 'u',
    'ü': 'u',
    'ú': 'u',
    'ÿ': 'y',
    'œ': 'oe',
    'æ': 'ae',
  };
  final b = StringBuffer();
  for (final r in s.toLowerCase().split('')) {
    b.write(accents[r] ?? r);
  }
  return b.toString();
}
