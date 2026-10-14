// Vue Blade maîtresse (PA-183) : pwa/transverse/parametres.blade.php
/// Les paramètres système tels que le serveur les décrit — `PARAM`.
///
/// ## L'écran est PILOTÉ par le serveur, il ne réécrit pas la liste
///
/// `RegistreParametres` (Laravel) déclare les clés, leur type, leurs choix et
/// leur aide. Recopier cette liste ici en donnerait une seconde, et les deux
/// finiraient par diverger — le symptôme étant un champ que l'écran propose et
/// que le serveur refuse, sans que rien n'explique pourquoi.
///
/// Conséquence assumée : une clé ajoutée côté serveur apparaît **toute seule**
/// dans l'écran, sans livraison Flutter.
library;

/// Comment un paramètre se saisit.
///
/// Registre fermé, et **la valeur inconnue est une issue à part entière** :
/// le poste peut tourner une version plus ancienne que le serveur. Rendre un
/// type inconnu comme du texte libre laisserait éditer un booléen au clavier,
/// ou un montant sans borne — l'écran dit qu'il ne sait pas le rendre.
enum TypeParametre {
  texte('texte'),
  booleen('booleen'),
  entier('entier'),
  decimal('decimal'),
  choix('choix');

  const TypeParametre(this.code);

  final String code;

  /// `null` si cette version du client ne connaît pas le type.
  static TypeParametre? depuisCode(String code) {
    for (final t in TypeParametre.values) {
      if (t.code == code) return t;
    }
    return null;
  }
}

/// Un paramètre modifiable, décrit par le serveur.
final class DefinitionParametre {
  const DefinitionParametre({
    required this.cle,
    required this.groupe,
    required this.libelle,
    required this.typeBrut,
    required this.choix,
    required this.aide,
    required this.valeur,
    this.notes = const [],
    this.correction,
  });

  final String cle;

  /// Le code de groupe du serveur — **une chaîne, pas un `enum`**.
  ///
  /// Un registre fermé ferait DISPARAÎTRE de l'écran tout paramètre d'un
  /// groupe ajouté plus tard : l'Administrateur ne le verrait pas, et rien ne
  /// le lui dirait. Même raisonnement que l'activité inconnue du tableau de
  /// bord (PA-122), qui reste visible avec son code.
  final String groupe;

  final String libelle;

  /// Ce que le serveur a annoncé, conservé même quand il est inconnu — c'est
  /// lui que l'écran montre pour expliquer son refus de rendre un éditeur.
  final String typeBrut;

  final List<String> choix;
  final String? aide;
  final String? valeur;

  /// Ce que CE POSTE ajoute à l'aide du serveur, une phrase par élément : le
  /// refus d'un secret, ou « aucun module ne lit cette valeur ». Jamais fondu
  /// dans [aide], qui reste celle de la vue Blade mot pour mot.
  final List<String> notes;

  /// Correction VISIBLE en ligne d'une aide du serveur fausse sur ce poste.
  final String? correction;

  TypeParametre? get type => TypeParametre.depuisCode(typeBrut);

  bool get estRendable => type != null;

  /// Valeur affichée dans un champ de saisie — jamais `null`, sans quoi le
  /// contrôleur de texte repartirait du libellé précédent.
  String get valeurTexte => valeur ?? '';

  bool get valeurBooleenne => valeur == 'true';
}

/// Un état DÉRIVÉ, calculé par le serveur — jamais recomposé ici.
///
/// C'est l'obligation de PA-61 portée au client. Un écran qui afficherait
/// « TVA active » parce que le champ `tva_active` vaut `true` mentirait dès que
/// le taux est absent : chaque vente serait refusée à la clôture (au serveur,
/// chaque émission de facture) pendant que le badge serait vert. Le serveur seul sait ce qui est réellement en place —
/// `etatTva()`, `MecefServiceProvider::etatConfiguration()`.
final class EtatDerive {
  const EtatDerive({required this.code, required this.libelle});

  final String code;
  final String libelle;

  /// Un état qui appelle une correction. Sert à la couleur du bandeau, pas au
  /// texte : le texte vient du serveur, en entier.
  bool get estAnormal => code != 'active' && code != 'inactive';
}

/// La réponse complète de `GET /api/v1/parametres`.
final class Parametres {
  const Parametres({required this.definitions, required this.etats});

  final List<DefinitionParametre> definitions;

  /// Clé technique (`tva`, `mecef`) vers l'état dérivé.
  final Map<String, EtatDerive> etats;

  /// Les groupes dans **l'ordre où le serveur les a envoyés**.
  ///
  /// Trier alphabétiquement ou figer un ordre ici recréerait la seconde liste
  /// que ce fichier existe pour éviter.
  List<String> get groupes {
    final vus = <String>[];
    for (final d in definitions) {
      if (!vus.contains(d.groupe)) vus.add(d.groupe);
    }
    return vus;
  }

  List<DefinitionParametre> duGroupe(String groupe) =>
      definitions.where((d) => d.groupe == groupe).toList(growable: false);
}

/// Intitulés d'onglets — repris de `prototype_v2/pages/parametres.html` l.30-36
/// pour les groupes que le maître couvre.
///
/// Un groupe absent de cette table s'affiche **avec son code** plutôt que de
/// disparaître : c'est un onglet en trop, jamais un paramètre en moins.
String libelleGroupe(String code) => switch (code) {
  // « Identité & Légal » au maître : le groupe serveur porte les mêmes champs
  // (raison sociale, adresse, IFU, RCCM, n° MECeF).
  'entreprise' => 'Identité & Légal',
  'fiscalite' => 'Fiscalité',
  'social' => 'Charges sociales',
  'exploitation' => 'Exploitation',
  _ => code,
};
