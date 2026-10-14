/// Le référentiel des taux de paie, et l'arithmétique qui les applique.
///
/// Vue Blade maîtresse (PA-183) : pwa/rh/paie.blade.php
///
/// ## Aucun flottant ne touche un montant
///
/// Règle du dépôt : comparaison et calcul de montants en entiers, jamais en
/// `double`. Un taux est donc lu comme un **rationnel entier** — « 3.6 »
/// devient 36/10 — et appliqué par `montant × numérateur ÷ (échelle × 100)`
/// avec un arrondi commercial au franc. `0.036 * 150000` en IEEE 754 vaut
/// 5400.000000000001 ; sur douze mois et dix salariés, l'écart devient visible
/// sur une déclaration.
library;

import '../refus_rh.dart';

/// Les clés du référentiel — **les mêmes que celles du serveur**.
///
/// Écrites ici plutôt que recopiées à chaque appel : une clé mal orthographiée
/// ne lèverait pas, elle rendrait simplement « taux absent », et l'écran
/// afficherait un référentiel incomplet que personne ne saurait compléter.
abstract final class ClesTaux {
  static const String cnssSalarie = 'taux_cnss_salarie';
  static const String cnssPensionEmployeur = 'taux_cnss_pension_employeur';
  static const String cnssPrestationsFamiliales =
      'taux_cnss_prestations_familiales';
  static const String vps = 'taux_vps';

  /// ⚠ **Délibérément absent du référentiel installé** (PA-53).
  ///
  /// La clé existe pour que le refus soit nommé — « le taux
  /// *taux_cnss_risques_professionnels* n'est pas paramétré » — et non pour
  /// qu'on la renseigne au premier écran rouge.
  static const String cnssRisquesProfessionnels =
      'taux_cnss_risques_professionnels';

  /// Les quatre taux **confirmés à la source**, exigés par tout calcul.
  static const List<String> confirmees = [
    cnssSalarie,
    cnssPensionEmployeur,
    cnssPrestationsFamiliales,
    vps,
  ];
}

/// Un taux confirmé et sa source.
final class TauxConfirme {
  const TauxConfirme({
    required this.cle,
    required this.valeur,
    required this.description,
  });

  final String cle;
  final String valeur;
  final String description;
}

/// Le référentiel **confirmé** installé sur un poste neuf.
///
/// ## Il a UN SEUL AUTEUR, et il a un appelant réel
///
/// Deux pièges du dépôt se croisent ici. PA-160/PA-161 : deux auteurs du même
/// référentiel finissent par semer des libellés différents, chacun se croyant
/// idempotent. PA-128 : une table lue partout et écrite nulle part laisse un
/// poste neuf sans issue — ici, aucun bulletin ne pourrait jamais être établi.
/// L'installation est donc unique ([PaieDao.installerReferentielConfirme]) et
/// réellement appelée au montage de l'écran.
///
/// ## Les quatre valeurs sont SOURCÉES, la cinquième est absente
///
/// Elles reprennent `PaieReferentielSeeder` du serveur, qui les tient de
/// cnss.bj et de `ATELIER_PLAN_COMPTABLE.md` §5.1. Le taux de risques
/// professionnels n'y figure pas, et ne doit jamais y entrer sans la décision
/// correspondante : « 1 % à 4 % selon l'activité » n'est pas une fourchette
/// qu'on moyenne, c'est une question ouverte auprès de la CNSS.
abstract final class ReferentielPaie {
  static const List<TauxConfirme> confirmes = [
    TauxConfirme(
      cle: ClesTaux.cnssSalarie,
      valeur: '3.6',
      description:
          'Cotisation CNSS part salariale, en % du brut, sans plafond. '
          'Source : cnss.bj (branche pension, 10 % dont 3,6 % salarié).',
    ),
    TauxConfirme(
      cle: ClesTaux.cnssPensionEmployeur,
      valeur: '6.4',
      description:
          'Cotisation CNSS pension part employeur, en % du brut. '
          'Source : cnss.bj.',
    ),
    TauxConfirme(
      cle: ClesTaux.cnssPrestationsFamiliales,
      valeur: '9',
      description:
          'Cotisation CNSS prestations familiales, employeur uniquement, '
          'en % du brut. Source : cnss.bj.',
    ),
    TauxConfirme(
      cle: ClesTaux.vps,
      valeur: '4',
      description:
          'VPS (Versement Patronal sur Salaires), en % du total des salaires '
          "bruts, SANS plafond. Taxe à la charge de l'employeur, jamais "
          'retenue sur le salaire. Déclaration et paiement au plus tard le 10 '
          'du mois suivant. Source : ATELIER_PLAN_COMPTABLE.md.',
    ),
  ];

  /// Les six services du gîte — l'organigramme du maître.
  ///
  /// Repris de `PersonnelSeeder::SERVICES` côté serveur, à l'identique : le
  /// service est une clé étrangère, et un poste dont le référentiel serait vide
  /// ne pourrait créer aucune fiche. Les inventer eût été pire que de les
  /// reprendre — ce sont des données d'établissement, pas des constantes.
  static const List<String> services = [
    'Hébergement',
    'Restauration',
    'Bar',
    'Tourisme',
    'Véhicules',
    'Administration',
  ];
}

/// Un taux en pourcentage, porté comme un rationnel entier.
final class Taux {
  const Taux._(this.numerateur, this.echelle);

  /// Lit « 3.6 », « 6,4 », « 9 » — rend `null` sur toute entrée illisible.
  ///
  /// `null` et jamais zéro : un taux que le référentiel n'a pas rendu n'est pas
  /// un taux nul, et les confondre calculerait une CNSS de 0 F sans qu'aucun
  /// écran ne s'en aperçoive.
  static Taux? depuisTexte(String? brut) {
    if (brut == null) return null;

    final texte = brut.trim().replaceAll(',', '.');
    if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(texte)) return null;

    final point = texte.indexOf('.');
    if (point < 0) {
      final entier = int.tryParse(texte);
      return entier == null ? null : Taux._(entier, 1);
    }

    final decimales = texte.substring(point + 1);
    final numerateur = int.tryParse(texte.replaceAll('.', ''));
    if (numerateur == null) return null;

    var echelle = 1;
    for (var i = 0; i < decimales.length; i++) {
      echelle *= 10;
    }
    return Taux._(numerateur, echelle);
  }

  /// `36` pour 3,6 %.
  final int numerateur;

  /// `10` pour 3,6 % — la puissance de dix qui ramène [numerateur] au taux.
  final int echelle;

  /// Le pourcentage appliqué à un montant, arrondi au franc.
  int pourcentDe(int montant) =>
      arrondiCommercial(montant * numerateur, echelle * 100);

  /// « 3,6 » — la virgule française, comme au maître.
  String get libelle {
    if (echelle == 1) return '$numerateur';
    final entier = numerateur ~/ echelle;
    final reste = numerateur % echelle;
    if (reste == 0) return '$entier';
    final decimales = reste.toString().padLeft(
      echelle.toString().length - 1,
      '0',
    );
    return '$entier,$decimales';
  }
}

/// Arrondi commercial au franc près — la demie s'éloigne de zéro.
///
/// Le FCFA n'a pas de subdivision en circulation : un bulletin au centime
/// serait impayable en espèces. C'est l'arrondi que le serveur applique
/// (`CalculPaieService::arrondir`), reproduit en arithmétique entière pour que
/// les deux côtés rendent le même franc.
int arrondiCommercial(int numerateur, int denominateur) {
  assert(denominateur > 0, 'le dénominateur doit être strictement positif');

  if (numerateur >= 0) {
    return (2 * numerateur + denominateur) ~/ (2 * denominateur);
  }
  return -((2 * -numerateur + denominateur) ~/ (2 * denominateur));
}

/// L'état réel du référentiel, **avant tout calcul**.
///
/// C'est le geste d'`etatTva()` (PA-62) : nommer l'incohérence avant qu'elle
/// atteigne une opération. Sans lui, l'écran laisserait un [TauxNonParametre]
/// traverser le rendu, et l'utilisateur verrait une pile d'appels là où il
/// fallait lui dire quelle clé renseigner.
final class EtatReferentiel {
  const EtatReferentiel({
    required this.clesAbsentes,
    required this.risquesProfessionnels,
  });

  /// Les clés **confirmées** qui manquent. Vide = installation complète.
  final List<String> clesAbsentes;

  /// Le taux de risques professionnels est-il renseigné ?
  ///
  /// ⚠ Son absence est **voulue** et ne figure jamais dans [clesAbsentes] :
  /// ce n'est pas une installation incomplète, c'est une question non tranchée
  /// (PA-53).
  final bool risquesProfessionnels;

  bool get complet => clesAbsentes.isEmpty;

  bool get salarial => !clesAbsentes.contains(ClesTaux.cnssSalarie);

  bool get patronal =>
      !clesAbsentes.contains(ClesTaux.cnssPensionEmployeur) &&
      !clesAbsentes.contains(ClesTaux.cnssPrestationsFamiliales) &&
      !clesAbsentes.contains(ClesTaux.vps);

  /// Le refus correspondant, ou `null` si tout est en place.
  ReferentielIncomplet? get refus =>
      complet ? null : ReferentielIncomplet(clesAbsentes);
}
