/// Lecture du plan comptable du Product Owner — UNE fonction, la seule.
///
/// Le fichier (`assets/data/plan-comptable-syscohada-revise.csv`, 1 332
/// comptes de 1 à 4 chiffres) est la COPIE OCTET POUR OCTET de
/// `tatacora-api/database/data/plan-comptable-syscohada-revise.csv`. Cette
/// fonction est la réplique de `ComptabiliteReferentielSeeder::lireFichier()` :
/// mêmes règles, mêmes refus, même numéro de ligne dans le message. Le test
/// `plan_comptable_fichier_test.dart` fait lire le MÊME fichier par la vraie
/// fonction PHP et compare les 1 332 couples, dans l'ordre.
///
/// ## Format
///
/// `Code;Libellé`, UTF-8, séparateur `;`, guillemet `"` autour d'un libellé qui
/// contient un `;` (la ligne 5024 : « Actions démembrées (certificats
/// d'investissement ; droits de vote) »), fins de ligne CRLF. La première
/// ligne est l'en-tête, ignorée sans être lue.
///
/// ## Aucun compte n'est écrit à la main
///
/// Le plan entre en base par cette fonction et par aucune autre
/// (`installerReferentielComptable`). Un compte recopié dans un seeder ou dans
/// un test diverge du fichier au premier ajout.
///
/// @see EF-M10-01 Plan comptable conforme SYSCOHADA révisé
library;

import 'refus_comptable.dart';

/// Un compte tel que le fichier le porte : numéro et libellé, rien d'autre.
final class LigneDuPlan {
  const LigneDuPlan(this.numero, this.libelle);

  final String numero;
  final String libelle;

  @override
  bool operator ==(Object other) =>
      other is LigneDuPlan &&
      other.numero == numero &&
      other.libelle == libelle;

  @override
  int get hashCode => Object.hash(numero, libelle);

  @override
  String toString() => 'LigneDuPlan($numero, $libelle)';
}

final RegExp _numeroValide = RegExp(r'^[1-9][0-9]*$');

/// Lit le contenu du fichier du PO.
///
/// Lève [RefusComptable] (`planFichierInvalide`) avec la phrase du serveur et
/// le numéro de la ligne fautive (l'en-tête est la ligne 1), sur : un numéro
/// qui n'est pas un entier positif sans zéro initial, un libellé vide, ou une
/// ligne qui ne compte pas EXACTEMENT deux champs.
List<LigneDuPlan> lirePlanComptable(String contenu) {
  final enregistrements = _enregistrements(contenu);
  final comptes = <LigneDuPlan>[];

  for (var i = 1; i < enregistrements.length; i++) {
    final champs = enregistrements[i];
    final numero = (champs.isNotEmpty ? champs[0] : '').trim();
    final libelle = (champs.length > 1 ? champs[1] : '').trim();
    if (!_numeroValide.hasMatch(numero) ||
        libelle.isEmpty ||
        champs.length != 2) {
      throw RefusComptable.dit(
        MotifRefus.planFichierInvalide,
        'comptabilite.plan_fichier_ligne_invalide',
        {'ligne': '${i + 1}'},
      );
    }
    comptes.add(LigneDuPlan(numero, libelle));
  }
  return comptes;
}

/// Découpe le contenu en enregistrements de champs (`;`, guillemet `"`, un
/// guillemet doublé dans un champ entre guillemets vaut un guillemet).
///
/// Une fin de ligne dans un champ entre guillemets reste dans le champ. La fin
/// de contenu après un saut de ligne ne produit pas d'enregistrement vide ; un
/// saut de ligne isolé AU MILIEU en produit un d'un seul champ vide — que
/// l'appelant refuse, comme `fgetcsv` le rend au serveur (`[null]`).
List<List<String>> _enregistrements(String contenu) {
  final resultat = <List<String>>[];
  var champs = <String>[];
  final champ = StringBuffer();
  var entreGuillemets = false;
  var champEntameParGuillemet = false;
  var enregistrementOuvert = false;

  void finirChamp() {
    champs.add(champ.toString());
    champ.clear();
    champEntameParGuillemet = false;
  }

  void finirEnregistrement() {
    finirChamp();
    resultat.add(champs);
    champs = <String>[];
    enregistrementOuvert = false;
  }

  var i = 0;
  while (i < contenu.length) {
    final c = contenu[i];
    if (entreGuillemets) {
      if (c == '"') {
        if (i + 1 < contenu.length && contenu[i + 1] == '"') {
          champ.write('"');
          i += 2;
          continue;
        }
        entreGuillemets = false;
        i++;
        continue;
      }
      champ.write(c);
      i++;
      continue;
    }

    if (c == '"' && champ.isEmpty && !champEntameParGuillemet) {
      entreGuillemets = true;
      champEntameParGuillemet = true;
      enregistrementOuvert = true;
      i++;
      continue;
    }
    if (c == ';') {
      enregistrementOuvert = true;
      finirChamp();
      i++;
      continue;
    }
    if (c == '\r' || c == '\n') {
      // CRLF compte pour UN saut de ligne.
      if (c == '\r' && i + 1 < contenu.length && contenu[i + 1] == '\n') i++;
      i++;
      finirEnregistrement();
      continue;
    }
    champ.write(c);
    enregistrementOuvert = true;
    i++;
  }

  // Dernier enregistrement sans saut de ligne final.
  if (enregistrementOuvert || champ.isNotEmpty || entreGuillemets) {
    finirEnregistrement();
  }
  return resultat;
}
