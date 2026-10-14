// Vue Blade maîtresse (PA-183) : pwa/pos/comptant.blade.php
// Vue Blade maîtresse (PA-183) : pwa/pos/heberges.blade.php
/// Le vocabulaire de chaque point de vente — **un registre fermé**.
///
/// ## Le défaut que ce fichier corrige (24/08/2026)
///
/// `VueCatalogue` et `VuePanier` sont partagés par les deux POS. C'est le bon
/// choix — les deux écrans font le même geste, et le maître les a dessinés
/// avec la même ossature. Mais ils ne disent **pas les mêmes mots**, et rien
/// ne portait cette différence :
///
/// | | `pos.html` (comptoir) | `pos-heberges.html` (séjours) |
/// |---|---|---|
/// | Bouton principal | « Encaisser » | « Clôturer et facturer » |
/// | Recherche | « Rechercher un article… » | « Rechercher une consommation ou une prestation… » |
/// | Retrait | « Vider » + « Abandonner » | « Annuler » |
/// | Règlement | libellé « Mode de règlement » | — |
///
/// Le client Flutter employait le vocabulaire des **séjours sur les deux
/// écrans**. Ce n'est pas un détail de traduction : au comptoir, « Clôturer et
/// facturer » nomme un geste de fin de séjour là où le caissier encaisse une
/// vente de passage — et « Abandonner », qui libère la table, disparaissait
/// derrière un « Annuler » qui ne dit pas qu'une table se libère.
///
/// ## Pourquoi un registre fermé et non un booléen
///
/// Un `bool estComptoir` marcherait aujourd'hui et se tromperait au troisième
/// point de vente : le cas non prévu prendrait silencieusement le vocabulaire
/// de l'un des deux. Ici, ajouter un point de vente **oblige** à écrire ses
/// mots — c'est la même règle que les 16 droits de PA-54 et que
/// `TABLES_SYNCHRONISABLES` : rien ne s'obtient par omission.
///
/// ## Ce que ce fichier n'est pas
///
/// Ce n'est pas un fichier d'internationalisation. `lang/`/ARB porte la
/// traduction ; ceci porte **quel maître parle**. Deux écrans français
/// peuvent employer deux mots français différents pour deux gestes différents,
/// et c'est précisément le cas ici.
///
/// @see docs/DOCTRINE_PORTAGE_FIDELE_FLUTTER.md §2
/// @see docs/AUDIT_CONFORMITE_ECRANS_FLUTTER.md §7.2, §7.6
library;

/// Les deux points de vente du maître. Registre **fermé**.
enum PointDeVentePos {
  /// `prototype_v2/pages/pos.html` — client de passage, encaissement immédiat.
  comptoir,

  /// `prototype_v2/pages/pos-heberges.html` — panier de séjour, réglé au
  /// départ.
  sejours,
}

/// Les mots d'un point de vente, tels que son maître les écrit.
final class VocabulairePos {
  const VocabulairePos._({
    required this.indicationRecherche,
    required this.actionPrincipale,
    required this.retirerLignes,
    required this.fermerPanier,
    required this.libelleReglement,
  });

  /// `placeholder` du champ de recherche du catalogue.
  final String indicationRecherche;

  /// Le bouton du pied de panier — celui qui engage l'argent.
  final String actionPrincipale;

  /// Vider les lignes **sans** fermer le panier. `null` quand le maître ne
  /// propose pas ce geste — les séjours n'ont qu'un seul bouton.
  final String? retirerLignes;

  /// Fermer le panier et libérer la table.
  ///
  /// Le mot compte : au comptoir le maître dit « Abandonner », et il libère la
  /// table — sans ce geste, une table ouverte par erreur restait bloquée pour
  /// toujours, le moteur refusant de clôturer un panier vide.
  final String fermerPanier;

  /// Le libellé au-dessus du choix de règlement. `null` quand le maître n'en
  /// pose pas : un séjour ne se règle pas dans ce panneau.
  final String? libelleReglement;

  /// Le vocabulaire d'un point de vente. `switch` **exhaustif** : ajouter une
  /// valeur à [PointDeVentePos] sans l'écrire ici ne compile pas.
  static VocabulairePos de(PointDeVentePos pdv) => switch (pdv) {
    PointDeVentePos.comptoir => const VocabulairePos._(
      indicationRecherche: 'Rechercher un article…',
      actionPrincipale: 'Encaisser',
      retirerLignes: 'Vider',
      fermerPanier: 'Abandonner',
      libelleReglement: 'Mode de règlement',
    ),
    PointDeVentePos.sejours => const VocabulairePos._(
      indicationRecherche: 'Rechercher une consommation ou une prestation…',
      actionPrincipale: 'Clôturer et facturer',
      retirerLignes: null,
      fermerPanier: 'Annuler',
      libelleReglement: null,
    ),
  };
}
