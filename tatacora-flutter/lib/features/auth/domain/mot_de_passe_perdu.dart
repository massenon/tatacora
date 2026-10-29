// Vue Blade maîtresse (PA-183) : pwa/transverse/comptes-utilisateurs.blade.php
// Vue Blade maîtresse (PA-183) : pwa/transverse/mon-profil.blade.php
// Vue Blade maîtresse (PA-183) : pwa/livewire/changement-mot-de-passe-obligatoire.blade.php
// Vue Blade maîtresse (PA-183) : pwa/livewire/code-secours.blade.php
/// MOT DE PASSE PERDU, SANS E-MAIL — décision du Product Owner du 29/10/2026
/// (option A) : pas de « mot de passe oublié » automatique. Un administrateur
/// réinitialise le compte d'un autre (mot de passe TEMPORAIRE), et le dernier
/// administrateur se rattrape par son CODE DE SECOURS.
///
/// Ce fichier porte les règles et les phrases UNE fois ; le web a les mêmes
/// (`MotDePassePerduService`, `lang/fr/pwa.php` groupes `comptes`,
/// `changement_mdp`, `code_secours`) et un test confronte chaque phrase à la
/// langue du serveur, résolue par PHP. Les comptes du poste sont DISTINCTS de
/// ceux du web : rien ne se synchronise, aucun dérivé de mot de passe ne part.
library;

import 'dart:math';

/// Les règles chiffrées.
abstract final class ReglesMotDePassePerdu {
  /// Validité du mot de passe temporaire.
  static const Duration validiteTemporaire = Duration(hours: 24);

  /// Essais permis avant blocage du code de secours.
  static const int essaisMax = 5;

  /// Durée du blocage après [essaisMax] échecs.
  static const Duration blocage = Duration(minutes: 15);

  /// La règle de force existante (« Mon profil », création de compte).
  static const int longueurMin = 8;

  /// Tours PBKDF2 du code de secours. Le code porte ~125 bits d'aléa : aucune
  /// attaque par dictionnaire n'a de prise, la dérivation lente d'un mot de
  /// passe humain (120 000 tours) n'apporterait rien ici.
  static const int iterationsCodeSecours = 20000;
}

/// Un refus lisible (français), à afficher tel quel.
final class RefusMotDePassePerdu implements Exception {
  const RefusMotDePassePerdu(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Les phrases — au caractère près celles de `lang/fr/pwa.php`.
abstract final class MessagesMotDePassePerdu {
  // pwa.comptes.*
  static const String refusSoiMeme =
      'Vous ne pouvez pas réinitialiser votre propre mot de passe par ce '
      'chemin. Utilisez « Mon profil » avec votre ancien mot de passe.';
  static const String refusSuperAdmin =
      "Seul un super administrateur peut réinitialiser le mot de passe d'un "
      'super administrateur.';

  // pwa.changement_mdp.*
  static const String nouveauRequis =
      'Veuillez saisir votre nouveau mot de passe.';
  static const String confirmationRequise =
      'Veuillez confirmer votre nouveau mot de passe.';
  static const String tropCourt =
      'Le mot de passe doit compter au moins 8 caractères.';
  static const String identiqueTemporaire =
      'Le nouveau mot de passe doit être différent du mot de passe temporaire.';
  static const String identiqueAncien =
      "Le nouveau mot de passe doit être différent de l'ancien.";
  static const String expire =
      "Ce mot de passe temporaire a expiré. Demandez-en un nouveau à l'administrateur.";
  static const String succes =
      'Mot de passe défini. Connectez-vous avec votre nouveau mot de passe.';

  // pwa.code_secours.*
  static const String loginRequis = "Veuillez saisir votre nom d'utilisateur.";
  static const String codeRequis = 'Veuillez saisir votre code de secours.';

  /// UN SEUL refus : le compte existe ou non, est administrateur ou non.
  static const String refusCode =
      "Nom d'utilisateur ou code de secours incorrect.";
  static String bloque(int minutes) =>
      'Trop de tentatives. Réessayez dans $minutes minute(s).';
  static const String mdpReinitialise = 'Mot de passe réinitialisé.';

  // pwa.profil.* — mot de passe de confirmation du code de secours
  static const String mdpIncorrect = "L'ancien mot de passe est incorrect.";

  // pwa.profil.code_secours_* — « Mon profil → Code de secours » et le code posé
  // au premier démarrage.
  static const String codeSecoursTitre = 'Code de secours';
  static const String codeSecoursSousTitre =
      "À usage unique : il permet au dernier administrateur de retrouver l'accès si son mot de passe est perdu.";
  static String codeSecoursPresent(String date) =>
      'Un code de secours est enregistré (posé le $date).';
  static const String codeSecoursAbsent =
      "Aucun code de secours n'est enregistré.";
  static const String codeSecoursOuvrir = 'Générer un code de secours';
  static const String codeSecoursModaleTitre = 'Générer un code de secours';
  static const String codeSecoursModaleSousTitre =
      'Confirmez votre mot de passe. Le code précédent, s\'il existe, ne '
      'fonctionnera plus.';
  static const String codeSecoursMotDePasse = 'Mot de passe actuel';
  static const String codeSecoursGenerer = 'Générer le code';
  static const String codeSecoursAfficheTitre = 'Votre code de secours';
  static const String codeSecoursConsigne =
      'Ce code ne sera plus affiché. Notez-le ou imprimez-le et rangez-le au '
      'coffre.';
  static const String codeSecoursFermer = "J'ai rangé ce code";
}

/// Fabrique les deux secrets à usage humain : le mot de passe temporaire et le
/// code de secours. `Random.secure()` seul (jamais `Random()`, prédictible) ;
/// [aleatoire] n'existe que pour les tests.
///
/// Aucun caractère ambigu : ni `0`/`O`, ni `1`/`l`/`I` — un secret lu à voix
/// haute ou recopié d'un papier ne doit pas dépendre d'une police.
abstract final class GenerateurDeSecret {
  static const String majuscules = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
  static const String minuscules = 'abcdefghijkmnpqrstuvwxyz';
  static const String chiffres = '23456789';

  /// ≥ 12 exigé par le PO.
  static const int longueurTemporaire = 14;

  /// 5 groupes de 5 = 25 caractères (≥ 20 exigé), ~125 bits.
  static const int groupesCode = 5;
  static const int tailleGroupe = 5;

  /// Au moins une majuscule, une minuscule et un chiffre, mélangés.
  static String motDePasseTemporaire({Random? aleatoire}) {
    final r = aleatoire ?? Random.secure();
    const tous = majuscules + minuscules + chiffres;
    final caracteres = <String>[
      _tirer(majuscules, r),
      _tirer(minuscules, r),
      _tirer(chiffres, r),
    ];
    while (caracteres.length < longueurTemporaire) {
      caracteres.add(_tirer(tous, r));
    }
    for (var i = caracteres.length - 1; i > 0; i--) {
      final j = r.nextInt(i + 1);
      final tmp = caracteres[i];
      caracteres[i] = caracteres[j];
      caracteres[j] = tmp;
    }
    return caracteres.join();
  }

  /// `XXXXX-XXXXX-XXXXX-XXXXX-XXXXX` : majuscules et chiffres, 32 symboles.
  static String codeDeSecours({Random? aleatoire}) {
    final r = aleatoire ?? Random.secure();
    const alphabet = majuscules + chiffres;
    return [
      for (var g = 0; g < groupesCode; g++)
        [for (var i = 0; i < tailleGroupe; i++) _tirer(alphabet, r)].join(),
    ].join('-');
  }

  /// La forme comparée d'un code saisi : majuscules, sans tiret ni espace.
  static String normaliserCode(String saisie) =>
      saisie.replaceAll(RegExp(r'[\s\-]+'), '').toUpperCase();

  static String _tirer(String alphabet, Random r) =>
      alphabet[r.nextInt(alphabet.length)];
}

/// Les routes des deux écrans « invité » ajoutés par ce lot — littérales,
/// comme toutes les routes du dépôt (les gardes de cohérence les relisent dans
/// le code source du routeur).
const String routeChangementMotDePasse = '/changement-mot-de-passe';
const String routeMotDePasseAdministrateurPerdu =
    '/mot-de-passe-administrateur-perdu';
