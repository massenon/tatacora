/// Les phrases de refus du moteur comptable — RECOPIÉES MOT POUR MOT du serveur
/// (`lang/fr/comptabilite.php` et `lang/fr/depenses.php`), clé par clé.
///
/// ## Pourquoi recopiées, et comment on sait qu'elles ne divergent pas
///
/// Un refus du poste doit dire la même chose que celui du serveur : c'est la
/// règle du PO du 10/10/2026 (le serveur est la référence, le poste le
/// réplique). Une phrase reformulée ici serait une seconde source qui dérive
/// en silence. `messages_comptables_test.dart` EXÉCUTE PHP, relit chacune de
/// ces 26 clés dans les fichiers de langue du serveur et exige l'égalité
/// exacte, des deux côtés (aucune clé en trop, aucune manquante).
///
/// Les clés gardent leur préfixe de fichier (`comptabilite.` / `depenses.`) :
/// `exercice_clos` existe dans les DEUX fichiers avec deux phrases différentes
/// (la saisie sur un exercice non ouvert, et l'observer RG-11).
///
/// ## Le remplacement des variables est celui de Laravel
///
/// `:cle`, `:CLE` et `:Cle`, les clés les plus longues d'abord
/// (`Illuminate\Translation\Translator::makeReplacements`).
library;

abstract final class MessagesComptables {
  /// Les gabarits bruts, tels que le serveur les stocke.
  static const gabarits = <String, String>{
    'comptabilite.piece_vide':
        'Une pièce comptable doit comporter au moins une ligne.',
    'comptabilite.piece_sans_montant':
        "Une pièce à zéro est équilibrée mais n'enregistre rien.",
    'comptabilite.piece_desequilibree':
        "Pièce déséquilibrée : :debit au débit contre :credit au crédit (écart de :ecart). Une écriture non équilibrée fausse le bilan sans qu'aucun compte pris isolément ne le montre.",
    'comptabilite.ecriture_immuable':
        'Cette écriture est validée : elle ne peut plus être modifiée. La seule correction admise est la contre-passation, qui conserve la trace des deux mouvements.',
    'comptabilite.ecriture_suppression_interdite':
        "Une écriture comptable ne se supprime jamais, même en brouillon : un trou dans la séquence est précisément ce qu'un contrôle fiscal recherche. Utilisez la contre-passation.",
    'comptabilite.exercice_clos':
        'Cet exercice est clôturé : aucune écriture ne peut plus y être ajoutée ni modifiée.',
    'comptabilite.ecriture_deja_validee': 'Cette écriture est déjà validée.',
    'comptabilite.contrepassation_sur_brouillon':
        'Une écriture en brouillon se corrige directement : la contre-passer ajouterait deux lignes inutiles au grand livre.',
    'comptabilite.deja_contrepassee':
        "Cette écriture a déjà été contre-passée. Une seconde contre-passation rétablirait l'écriture d'origine tout en laissant croire à une annulation.",
    'comptabilite.libelle_contrepassation': 'Contre-passation — :libelle',
    'comptabilite.compte_division':
        'Le compte :numero est une division du plan comptable : il ne reçoit aucun mouvement. Choisissez un de ses sous-comptes.',
    'comptabilite.compte_numero_invalide':
        'Numéro de compte invalide : « :numero ». Un compte du plan comptable porte de deux à quatre chiffres, le premier de 1 à 9.',
    'comptabilite.compte_libelle_requis':
        "L'intitulé du compte est obligatoire.",
    'comptabilite.compte_nature_invalide':
        'Nature de compte inconnue : « :nature ». Valeurs admises : actif, passif, charge, produit.',
    'comptabilite.compte_deja_existant':
        'Le compte :numero existe déjà au plan comptable.',
    'comptabilite.exercice_annee_invalide':
        "L'année de l'exercice doit être comprise entre 2000 et 2100.",
    'comptabilite.exercice_deja_existant': "L'exercice :annee existe déjà.",
    'comptabilite.exercice_deja_cloture': "L'exercice :annee est déjà clôturé.",
    'comptabilite.cloture_brouillons_restants':
        "L'exercice :annee ne peut pas être clôturé : :nombre écriture(s) en brouillon y subsistent encore. Validez-les ou contre-passez-les avant de clôturer — une pièce en brouillon n'est pas opposable, la clôturer verrouillerait l'exercice sur un état que personne n'a confirmé.",
    'comptabilite.plan_fichier_illisible':
        'Le fichier du plan comptable est introuvable ou illisible.',
    'comptabilite.plan_fichier_ligne_invalide':
        'Le fichier du plan comptable est invalide à la ligne :ligne.',
    'depenses.journal_inconnu':
        "Journal comptable inconnu : :code. Le référentiel des journaux doit être renseigné avant toute saisie — l'écriture est refusée plutôt qu'imputée à un journal choisi au hasard.",
    'depenses.compte_inconnu':
        "Compte comptable inconnu : :numero. Le plan comptable ne le contient pas. Choisissez un compte du plan plutôt qu'un numéro saisi de mémoire : une imputation erronée sur une pièce validée ne se corrige que par contre-passation.",
    'depenses.exercice_absent':
        "Aucun exercice comptable ne couvre la date :date. Créez-le avant de saisir : une écriture hors exercice n'apparaîtrait dans aucun état.",
    'depenses.exercice_clos':
        "L'exercice :annee est :statut : aucune écriture ne peut plus y être ajoutée. Datez la pièce sur un exercice ouvert, ou faites rouvrir celui-ci.",
    'depenses.centre_absent':
        "Le compte :numero ne porte aucun centre de coût par défaut, et aucun centre n'a été précisé. RG-12 rend le centre de coût obligatoire : sans lui, la comptabilité analytique serait fausse sans qu'aucun total ne bouge.",
  };

  /// La phrase de la clé [cle], variables remplacées.
  ///
  /// Une clé inconnue LÈVE : rendre la clé brute à l'écran serait un message
  /// plausible et faux.
  static String dire(String cle, [Map<String, String> variables = const {}]) {
    final gabarit = gabarits[cle];
    if (gabarit == null) {
      throw ArgumentError.value(
        cle,
        'cle',
        'Clé de langue comptable inconnue.',
      );
    }
    final noms = variables.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    var texte = gabarit;
    for (final nom in noms) {
      final valeur = variables[nom]!;
      texte = texte
          .replaceAll(':$nom', valeur)
          .replaceAll(':${nom.toUpperCase()}', valeur.toUpperCase())
          .replaceAll(':${_ucfirst(nom)}', _ucfirst(valeur));
    }
    return texte;
  }

  static String _ucfirst(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

/// Les SEULES phrases de ce poste qui n'ont pas d'équivalent dans la langue du
/// serveur, et pourquoi (ticket D194).
///
/// Chacune correspond à un refus que le serveur porte autrement qu'en phrase :
/// une contrainte MySQL (erreur SQL), un `ValueError` de `bcmath`, un
/// `ModelNotFoundException`, ou une identité fournie par le garde `auth()`. Le
/// poste refuse au MÊME endroit du déroulement, mais dit quelque chose de
/// lisible. Aucune ne se confond avec une clé de [MessagesComptables] : le test
/// de langue exige que le serveur n'en ait AUCUNE.
abstract final class PhrasesDuPoste {
  static const ligneNegative =
      'Une ligne de pièce ne peut porter aucun montant négatif : '
      'une écriture est un débit ou un crédit, jamais une soustraction.';

  static const debitEtCredit =
      'Une ligne de pièce est un débit OU un crédit, jamais les deux : '
      'écrivez deux lignes.';

  static const referenceRefusee =
      'La base refuse cette ligne : une référence (compte, centre de coût, '
      'journal, exercice, auteur) est inconnue ou un montant est invalide.';

  static const auteurAbsent =
      'Aucune écriture comptable sans auteur : chaque pièce nomme celui qui '
      "l'a passée (RG-15).";

  static String montantIllisible(String valeur) =>
      "Montant illisible : « $valeur ». Un montant s'écrit avec des chiffres "
      'et, au plus, un point décimal.';

  static String ecritureIntrouvable(String id) =>
      "L'écriture $id n'existe plus sur ce poste : la pièce ne peut pas être "
      'relue.';
}
