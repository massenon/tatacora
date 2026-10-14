// Vue Blade maîtresse (PA-183) : pwa/achats/achats.blade.php
/// Le référentiel fournisseurs — M7, EF-M7-01.
///
/// Source serveur : `FournisseurResource`, `EnregistrerFournisseurRequest`,
/// `FiltrerFournisseursRequest`. Maître de mise en page :
/// `prototype_v2/pages/m7-achats.html`, onglet « Fournisseurs ».
///
/// ## `evaluation` est un registre FERMÉ, et `null` n'en fait pas partie
///
/// La colonne est un `enum` MySQL à quatre valeurs. `null` veut dire « pas
/// encore évalué », ce qui **n'est pas** « À revoir » : le maître rend les deux
/// par un badge, et les confondre reprocherait à un fournisseur neuf une
/// mauvaise note que personne ne lui a donnée (`FournisseurResource` l'écrit
/// noir sur blanc).
library;

/// Les quatre valeurs de l'`enum` serveur, avec les libellés du maître.
///
/// Les codes sont ceux du schéma (`excellent`, `bon`, `moyen`, `a_revoir`) ;
/// les libellés sont ceux que le maître affiche (`m7-achats.html` l.78-82).
/// L'API rend le code, la traduction appartient au client — le dire à l'envers
/// ferait rejeter l'écriture par la base avec un message SQL illisible.
enum EvaluationFournisseur {
  excellent('excellent', 'Excellent'),
  bon('bon', 'Bon'),
  moyen('moyen', 'Moyen'),
  aRevoir('a_revoir', 'À revoir');

  const EvaluationFournisseur(this.code, this.libelle);

  final String code;
  final String libelle;

  /// `null` sur un code inconnu — **jamais un repli sur un cas plausible**.
  ///
  /// Une valeur ajoutée à l'enum demain ne doit pas hériter du comportement
  /// d'`excellent` par omission : l'écran affiche alors le code brut, ce qui se
  /// voit, plutôt qu'un libellé faux, qui ne se voit pas. Même règle que
  /// `TypeMouvement.depuisCode` (M6) et que les types de champ inconnus de
  /// l'écran Paramètres (PA-125).
  static EvaluationFournisseur? depuisCode(String? code) {
    if (code == null) return null;
    for (final e in values) {
      if (e.code == code) return e;
    }
    return null;
  }
}

/// Un fournisseur du référentiel, tel que `FournisseurResource` le rend.
final class Fournisseur {
  const Fournisseur({
    required this.id,
    required this.raisonSociale,
    required this.contact,
    required this.categorie,
    required this.conditionsPaiement,
    required this.evaluationCode,
    required this.actif,
  });

  final String id;
  final String raisonSociale;

  /// `fournisseurs.actif` — faux : le fournisseur est ARCHIVÉ (vue Blade
  /// `pwa/achats/achats.blade.php` l.226-229 et l.257-267). Il reste dans la
  /// liste, marqué « Archivé », et se restaure : le masquer le rendrait
  /// indiscernable d'une fiche inexistante. Colonne ajoutée côté serveur le
  /// 03/09/2026 (migration `ajouter_archivage_aux_referentiels`) et sur ce poste
  /// le 12/10/2026 (v21, écrite par `AchatsDao.archiverFournisseur`).
  ///
  /// OBLIGATOIRE : le défaut `true` n'existe plus — il ne couvrait que les fiches
  /// construites sans source, et « dette datée » disait de le retirer dès qu'une
  /// source existe. Elle existe.
  final bool actif;

  /// Nullable au schéma. `null` n'est pas la chaîne vide : l'écran affiche un
  /// tiret, jamais un contact nommé « ».
  final String? contact;
  final String? categorie;
  final String? conditionsPaiement;

  /// Le code brut du serveur, **conservé même inconnu** : c'est lui qu'on
  /// affiche quand [evaluation] rend `null` sur un code hors registre.
  final String? evaluationCode;

  EvaluationFournisseur? get evaluation =>
      EvaluationFournisseur.depuisCode(evaluationCode);

  /// Le texte du badge.
  ///
  /// Trois cas distincts, et ils ne se confondent pas : évalué (le libellé),
  /// pas encore évalué (`null`), ou évalué avec un code que ce client ne
  /// connaît pas (le code brut).
  String get libelleEvaluation {
    if (evaluationCode == null) return 'Non évaluée';
    return evaluation?.libelle ?? evaluationCode!;
  }

  bool get estEvalue => evaluationCode != null;
}

/// Ce que le formulaire « Fournisseur » soumet — `m7-achats.html` l.133-184.
///
/// ## Aucun champ calculé, et aucun encours
///
/// `EnregistrerFournisseurRequest::CHAMPS_CALCULES` **interdit**
/// `montant_commande`, `montant_regle`, `encours`, `total_du` et
/// `nombre_commandes` — interdit, pas ignore (PA-24). Les trois premiers n'ont
/// d'ailleurs **aucune table** : il n'existe ni facture ni règlement
/// fournisseur au schéma (PA-21). Ils ne figurent donc pas ici, et l'écran
/// nomme le refus au lieu de le taire.
///
/// ## `id` n'est envoyé qu'à la création
///
/// `prohibited` en modification côté serveur : l'identifiant d'un fournisseur
/// ne se modifie pas. L'envoyer quand même ferait refuser en 422 une
/// modification par ailleurs valide — le même piège que M6.
final class SaisieFournisseur {
  const SaisieFournisseur({
    required this.id,
    required this.raisonSociale,
    required this.contact,
    required this.categorie,
    required this.conditionsPaiement,
    required this.evaluationCode,
  });

  final String id;
  final String raisonSociale;
  final String? contact;
  final String? categorie;
  final String? conditionsPaiement;
  final String? evaluationCode;

  Map<String, dynamic> versJson({required bool modification}) => {
    if (!modification) 'id': id,
    'raison_sociale': raisonSociale,
    'contact': contact,
    'categorie': categorie,
    'conditions_paiement': conditionsPaiement,
    'evaluation': evaluationCode,
  };
}

/// Les catégories proposées par le maître — `m7-achats.html` l.153-159.
///
/// ## Une liste du maître, pas un référentiel du serveur
///
/// `fournisseurs.categorie` est une **chaîne libre** au schéma, et
/// `EnregistrerFournisseurRequest` la laisse libre **délibérément** : fermer le
/// registre côté serveur rendrait inmodifiable tout fournisseur déjà
/// enregistré hors de cette liste. L'arbitrage appartient au Product Owner —
/// la liste du maître ne connaît ni prestataire de service ni transporteur.
///
/// Le formulaire y ajoute donc la valeur **déjà portée par la fiche**, sans
/// quoi corriger un numéro de téléphone remplacerait la catégorie en silence.
const categoriesFournisseurMaitre = <String>[
  'Denrées alimentaires',
  'Boissons',
  'Fournitures',
  'Carburant',
  'Pièces auto',
];

/// Les conditions de paiement proposées par le maître — `m7-achats.html`
/// l.166-170. Même statut que les catégories : chaîne libre au schéma.
const conditionsPaiementMaitre = <String>['Comptant', '30 jours', '60 jours'];
