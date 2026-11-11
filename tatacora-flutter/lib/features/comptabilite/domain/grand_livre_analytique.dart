/// Grand livre et Analytique, calculés sur les écritures du POSTE — sans
/// serveur. Fonctions PURES, en centimes entiers, réplique de
/// `GrandLivreService` et `AnalytiqueService` (confrontées au serveur par
/// `grand_livre_analytique_contre_serveur_test.dart`).
///
/// La portée est celle du Journal et de la Balance du hub : un exercice, le
/// filtre de statut choisi à l'écran ([porteeEcritures]). Le journal choisi ne
/// filtre ni l'un ni l'autre (le serveur ne le passe pas non plus).
library;

import '../data/ecritures_serveur_dao.dart' show EcritureServeur;
import 'consultation_comptable.dart';
import 'entities/comptabilite.dart';
import 'etats_financiers.dart';

/// Une ligne du grand livre : l'écriture et le solde PROGRESSIF (débit moins
/// crédit, cumulé depuis la première ligne de l'exercice).
final class LigneGrandLivrePoste {
  const LigneGrandLivrePoste({
    required this.ecriture,
    required this.soldeProgressifCentimes,
  });

  final EcritureComptable ecriture;
  final int soldeProgressifCentimes;
}

/// Le grand livre d'UN compte.
final class GrandLivrePoste {
  const GrandLivrePoste({
    required this.compte,
    required this.lignes,
    required this.soldeMouvementsCentimes,
    required this.soldeOuvertureCentimes,
    required this.soldeClotureCentimes,
    required this.ouvertureProvisoire,
    required this.anneeOuverture,
  });

  final CompteDuPlan compte;
  final List<LigneGrandLivrePoste> lignes;

  /// Débit moins crédit de toutes les lignes (positif : débiteur).
  final int soldeMouvementsCentimes;

  /// `null` : l'ouverture est INCONNUE (précédent clôturé sans pièce
  /// d'à-nouveaux) — « — », jamais zéro.
  final int? soldeOuvertureCentimes;
  final int? soldeClotureCentimes;

  /// L'ouverture est un à-nouveau PROVISOIRE (exercice précédent non clôturé).
  final bool ouvertureProvisoire;
  final int? anneeOuverture;

  bool get estSansMouvement => lignes.isEmpty;
}

/// Les comptes réellement mouvementés de la portée, par numéro (le sélecteur
/// de la vue : « un compte jamais mouvementé n'apparaît pas »).
List<CompteDuPlan> comptesMouvementes(
  List<EcritureComptable> portee,
  Map<String, CompteDuPlan> comptes,
) {
  final ids = {for (final e in portee) e.compteId};
  return [
    for (final id in ids)
      if (comptes[id] != null) comptes[id]!,
  ]..sort((a, b) => a.numero.compareTo(b.numero));
}

/// Le grand livre de [compte] sur [portee] (écritures déjà bornées à
/// l'exercice et au statut, et ordonnées par [porteeEcritures]).
///
/// [reportCentimes] : le solde d'ouverture du compte lu du report à nouveau —
/// `null` quand il est inconnu. Les comptes de gestion (classes 6 à 9)
/// repartent de zéro chaque exercice.
GrandLivrePoste grandLivreDe({
  required CompteDuPlan compte,
  required List<EcritureComptable> portee,
  required int? reportCentimes,
  required bool reportProvisoire,
  required int? anneeReport,
}) {
  var solde = 0;
  final lignes = <LigneGrandLivrePoste>[];
  for (final e in portee) {
    if (e.compteId != compte.id) continue;
    solde += e.debitCentimes - e.creditCentimes;
    lignes.add(
      LigneGrandLivrePoste(ecriture: e, soldeProgressifCentimes: solde),
    );
  }
  final gestion = const [
    '6',
    '7',
    '8',
    '9',
  ].contains(compte.numero.isEmpty ? '' : compte.numero.substring(0, 1));
  final inconnue = !gestion && reportCentimes == null;
  final ouverture = gestion ? 0 : reportCentimes ?? 0;
  return GrandLivrePoste(
    compte: compte,
    lignes: lignes,
    soldeMouvementsCentimes: solde,
    soldeOuvertureCentimes: inconnue ? null : ouverture,
    soldeClotureCentimes: inconnue
        ? null
        : (reportProvisoire ? ouverture + solde : solde),
    ouvertureProvisoire: reportProvisoire && !gestion,
    anneeOuverture: anneeReport,
  );
}

/// Le report à nouveau de l'exercice [annee], compte par compte (débit moins
/// crédit), lu des écritures VALIDÉES du poste ([d]) :
///
///  * précédent NON clôturé : les à-nouveaux provisoires, calculés (la
///    balance de l'exercice moins ses propres mouvements) ;
///  * précédent clôturé : les lignes du journal d'à-nouveaux `AN` de
///    l'exercice, quand il y en a ; sans pièce d'à-nouveaux, l'ouverture est
///    CONNUE (zéro) si la clôture du précédent est enregistrée sur ce poste,
///    sinon INCONNUE (clôturé avant la clôture SYSCOHADA, ou par le serveur
///    seul : ce poste n'en sait rien) ;
///  * aucun précédent : exercice inaugural, aucun report.
({Map<String, int> soldes, bool provisoire, int? annee, bool connu})
reportOuverture(int annee, DonneesEtats d) {
  final precedent = annee - 1;
  if (d.existe(precedent) &&
      d.statutParAnnee[precedent] != StatutExercice.cloture) {
    final propres = <String, int>{};
    for (final e in d.ecrituresParAnnee[annee] ?? const <EcritureServeur>[]) {
      if (e.codeJournal == 'CL') continue;
      propres[e.numeroCompte] =
          (propres[e.numeroCompte] ?? 0) + e.debitCentimes - e.creditCentimes;
    }
    final soldes = <String, int>{};
    for (final l in balanceDe(annee, d).lignes) {
      final net =
          l.debitCentimes - l.creditCentimes - (propres[l.numeroCompte] ?? 0);
      if (net != 0) soldes[l.numeroCompte] = net;
    }
    return (soldes: soldes, provisoire: true, annee: precedent, connu: true);
  }
  final soldes = <String, int>{};
  var aDesNouveaux = false;
  for (final e in d.ecrituresParAnnee[annee] ?? const <EcritureServeur>[]) {
    if (e.codeJournal != 'AN') continue;
    aDesNouveaux = true;
    soldes[e.numeroCompte] =
        (soldes[e.numeroCompte] ?? 0) + e.debitCentimes - e.creditCentimes;
  }
  final inaugural = !d.existe(precedent);
  return (
    soldes: soldes,
    provisoire: false,
    annee: null,
    connu:
        inaugural ||
        aDesNouveaux ||
        d.anneesAvecClotureActive.contains(precedent),
  );
}

/// Une ligne de l'analytique : un centre de coût.
final class LigneAnalytiquePoste {
  const LigneAnalytiquePoste({
    required this.centreId,
    required this.libelle,
    required this.type,
    required this.produitsCentimes,
    required this.chargesCentimes,
    required this.nombreLignes,
  });

  final String centreId;
  final String libelle;
  final String? type;
  final int produitsCentimes;
  final int chargesCentimes;
  final int nombreLignes;

  int get resultatCentimes => produitsCentimes - chargesCentimes;

  /// Le taux de marge en dixièmes de pourcent, tronqué comme `bcdiv(.., 1)` ;
  /// `null` sans produit : une absence de taux, pas un taux nul.
  int? get tauxMargeDixiemes => produitsCentimes == 0
      ? null
      : (resultatCentimes * 1000) ~/ produitsCentimes;
}

final class AnalytiquePoste {
  const AnalytiquePoste({
    required this.centres,
    required this.totalProduitsCentimes,
    required this.totalChargesCentimes,
  });

  final List<LigneAnalytiquePoste> centres;
  final int totalProduitsCentimes;
  final int totalChargesCentimes;

  int get totalResultatCentimes => totalProduitsCentimes - totalChargesCentimes;
}

/// `AnalytiqueService::genererPourExercice` : par centre, les produits
/// (classe 7, et 8 créditrice) et les charges (classe 6, et 8 débitrice) ;
/// les classes 1 à 5 sont du bilan et ne comptent pas. Un centre sans
/// mouvement n'a pas de ligne. Tri par marge décroissante.
AnalytiquePoste analytiqueDe({
  required List<EcritureComptable> portee,
  required Map<String, CompteDuPlan> comptes,
  required List<CentreDeCout> centres,
}) {
  // (centre, classe) -> [débit, crédit, lignes]
  final agregats = <String, Map<String, List<int>>>{};
  for (final e in portee) {
    final classe = comptes[e.compteId]?.classe;
    if (classe == null) continue;
    final a = agregats
        .putIfAbsent(e.centreId, () => {})
        .putIfAbsent(classe, () => [0, 0, 0]);
    a[0] += e.debitCentimes;
    a[1] += e.creditCentimes;
    a[2] += 1;
  }
  final parId = {for (final c in centres) c.id: c};
  final lignes = <LigneAnalytiquePoste>[];
  for (final entree in agregats.entries) {
    final centre = parId[entree.key];
    if (centre == null) continue;
    var produits = 0;
    var charges = 0;
    var nombre = 0;
    for (final c in entree.value.entries) {
      final net = c.value[0] - c.value[1];
      nombre += c.value[2];
      final produit = c.key == '7' || (c.key == '8' && net < 0);
      if (produit) {
        produits += -net;
      } else if (c.key == '6' || c.key == '8') {
        charges += net;
      }
    }
    lignes.add(
      LigneAnalytiquePoste(
        centreId: entree.key,
        libelle: centre.libelle,
        type: centre.type,
        produitsCentimes: produits,
        chargesCentimes: charges,
        nombreLignes: nombre,
      ),
    );
  }
  lignes.sort((a, b) {
    final d = b.resultatCentimes.compareTo(a.resultatCentimes);
    return d != 0 ? d : a.libelle.compareTo(b.libelle);
  });
  return AnalytiquePoste(
    centres: lignes,
    totalProduitsCentimes: lignes.fold(0, (t, l) => t + l.produitsCentimes),
    totalChargesCentimes: lignes.fold(0, (t, l) => t + l.chargesCentimes),
  );
}
