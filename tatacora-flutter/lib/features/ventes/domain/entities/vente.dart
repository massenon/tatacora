// Vue Blade maîtresse (PA-183) : pwa/pos/historique-ventes.blade.php
/// Le **journal des ventes** — `prototype_v2/pages/historique-ventes.html`.
///
/// ## Ce n'est PAS le registre des factures, et les confondre coûte cher
///
/// `shell.js` le dit en toutes lettres sur l'entrée de menu : *« le JOURNAL
/// des ventes, distinct du registre des factures : une vente peut exister
/// sans facture, et une vente annulée reste une vente là où une facture
/// annulée produit un avoir. »*
///
/// Les deux écrans lisent donc des choses différentes et **ne doivent jamais
/// afficher le même total** :
///
///  - `EcranFacturation` lit `pieces_facturation_local` — des pièces
///    numérotées, dont les avoirs, à montant négatif ;
///  - cet écran lit `paniers_local` — des ventes, dont certaines n'ont
///    **aucune** pièce, et dont l'annulation ne produit rien du tout.
///
/// Chercher une vente dans le registre des factures ferait conclure qu'elle
/// n'a jamais eu lieu.
///
/// ## Une vente est un panier CLÔTURÉ (ou annulé), jamais un panier ouvert
///
/// Un panier ouvert est une table en cours de service : rien n'a été encaissé,
/// rien n'est décidé — pas même le mode de règlement, qui se fige à la clôture
/// (`providers_pos.dart`, `ModeReglementNotifier`). Le faire entrer au journal
/// annoncerait un chiffre d'affaires que personne n'a encore réalisé. L'écran
/// **dit** que ces paniers en sont exclus, plutôt que de les taire.
///
/// ## Une vente annulée a deux origines, et elles se distinguent
///
/// Depuis le 21/10/2026 (ordre du PO : « tout doit être au complet »), le poste
/// annule aussi une vente DÉJÀ ENCAISSÉE, comme `VenteService::annuler` :
/// `PanierDao.annulerVente` contre-passe la pièce et passe le panier à `annule`
/// en gardant son montant figé, son mode et sa session. Reste l'autre origine,
/// `PanierDao.annuler` : un service abandonné avant paiement, qui n'écrit
/// aucun `montantCloture`.
///
/// La conséquence tenue par ce fichier : [Vente.montantFige] dit laquelle des
/// deux on lit. Vrai = la vente avait été encaissée puis annulée ; faux = elle
/// n'a jamais été payée. Présenter les deux de la même façon laisserait croire
/// qu'un montant abandonné a été encaissé puis rendu.
///
/// @see prototype_v2/pages/historique-ventes.html
/// @see prototype_v2/assets/js/ventes-engine.js
library;

import '../../../pos/domain/entities/mode_reglement.dart';
import '../../../pos/domain/entities/panier.dart';
import '../../../pos/domain/entities/reference_catalogue.dart';

/// L'état d'une vente au journal — **registre fermé**.
///
/// Deux valeurs seulement, et ce sont celles des deux options du filtre du
/// maître (l.42-43). Un panier `ouvert` n'en a pas : il n'est pas une vente,
/// et lui inventer un troisième état le ferait entrer dans les totaux.
enum StatutVente {
  validee('validee', 'Validées'),
  annulee('annulee', 'Annulées');

  const StatutVente(this.code, this.libelleFiltre);

  /// Le code du maître (`option value="validee"`).
  final String code;

  /// Le libellé du filtre, au mot du maître.
  final String libelleFiltre;

  /// Traduit l'état d'un panier. `null` pour un panier **ouvert**, qui n'est
  /// pas une vente — et ce `null` est lu par [Vente.depuisPanier], qui l'écarte
  /// du journal.
  ///
  /// Un `switch` exhaustif plutôt qu'une comparaison : le jour où un état de
  /// panier s'ajoute, ce fichier ne compilera plus tant que la question « est-ce
  /// une vente ? » n'aura pas reçu une réponse écrite.
  static StatutVente? depuisPanier(StatutPanier statut) => switch (statut) {
    StatutPanier.ouvert => null,
    StatutPanier.cloture => StatutVente.validee,
    StatutPanier.annule => StatutVente.annulee,
  };
}

/// Une ligne de vente — **une copie**, jamais une jointure.
///
/// ## Pourquoi ce n'est pas `LignePanier`
///
/// Le journal doit pouvoir être servi un jour par une table `ventes` du
/// serveur sans qu'aucun écran ne change : lui faire porter l'entité du panier
/// l'attacherait à sa provenance actuelle. C'est la même frontière qu'entre un
/// DAO et un écran, appliquée entre deux domaines.
///
/// Le prix et le libellé sont déjà figés à l'ajout au panier (règle 3 du
/// panier) : cette copie ne fige rien de plus, elle transporte.
final class LigneVente {
  const LigneVente({
    required this.libelle,
    required this.module,
    required this.prixUnitaire,
    required this.quantite,
    this.sansLienStock = false,
  });

  /// La ligne ne sortirait AUCUN stock : boisson sans article de stock, plat dont
  /// la fiche n'a aucun ingrédient (`stock_non_impacte` du serveur). Lue du
  /// catalogue d'AUJOURD'HUI — voir `CatalogueDao.referencesSansLienDeStock`.
  final bool sansLienStock;

  final String libelle;

  /// L'activité, **estampillée à la vente** — jamais devinée après coup depuis
  /// la catégorie, ce que le maître refuse explicitement
  /// (`ventes-engine.js` l.267-274 : deviner sur une donnée financière).
  final ModuleVendable module;

  final int prixUnitaire;
  final int quantite;

  /// Montant de ligne — **calculé, jamais stocké**.
  int get montant => prixUnitaire * quantite;
}

/// Une vente du journal.
final class Vente {
  const Vente({
    required this.id,
    required this.date,
    required this.statut,
    required this.typeVente,
    required this.lignes,
    required this.montant,
    required this.montantFige,
    this.mode,
    this.pointVente,
    this.tableLibelle,
    this.clientNom,
    this.espace,
    this.reservationId,
    this.motifAnnulation,
    this.numeroFacture,
    this.numero,
  });

  /// Compose une vente depuis un panier. Rend `null` pour un panier **ouvert**.
  ///
  /// [libelleTable] et [numeroFacture] viennent d'ailleurs et sont donc
  /// **passés**, jamais lus ici : une entité qui irait chercher sa propre
  /// jointure obligerait à monter une base pour la construire, et le filtrage
  /// du journal ne serait plus éprouvable sans elle.
  static Vente? depuisPanier(
    Panier panier, {
    String? libelleTable,
    String? numeroFacture,
    Set<String> sansLienStock = const {},
  }) {
    final statut = StatutVente.depuisPanier(panier.statut);
    if (statut == null) return null;

    final fige = panier.montantCloture;
    final code = panier.modePaiement;

    return Vente(
      id: panier.id,
      // `clotureLe` est écrit par les DEUX chemins de sortie du panier —
      // `cloturer` et `annuler`. Le repli sur l'ouverture ne sert donc qu'à
      // une ligne écrite par une autre version : il vaut mieux une date trop
      // ancienne, qui se voit, qu'une vente absente du journal, qui ne se voit
      // pas.
      date: panier.clotureLe ?? panier.ouvertLe,
      statut: statut,
      typeVente: panier.typeVente,
      lignes: [
        for (final l in panier.lignes)
          LigneVente(
            libelle: l.libelle,
            module: l.reference.module,
            prixUnitaire: l.prixUnitaire,
            quantite: l.quantite,
            sansLienStock: sansLienStock.contains(l.reference.toString()),
          ),
      ],
      // Le montant FIGÉ à la clôture l'emporte : c'est celui qui a été annoncé
      // au client et encaissé. Le recalculer depuis les lignes donnerait un
      // autre chiffre le jour où une ligne bougerait — ce que l'immuabilité du
      // panier clôturé interdit, mais qu'une migration maladroite pourrait
      // faire.
      montant: fige ?? panier.total,
      montantFige: fige != null,
      mode: code == null ? null : ModeReglement.parCode(code),
      pointVente: panier.pointVente,
      tableLibelle: libelleTable,
      clientNom: panier.clientNom,
      espace: panier.espace,
      reservationId: panier.reservationId,
      motifAnnulation: panier.motifAnnulation,
      numeroFacture: numeroFacture,
      numero: panier.numeroVente,
    );
  }

  /// L'identifiant du panier qui porte cette vente.
  final String id;

  /// La date de clôture — celle de la vente, jamais celle de l'ouverture de la
  /// table.
  final DateTime date;

  final StatutVente statut;
  final TypeVente typeVente;
  final List<LigneVente> lignes;

  /// Montant de la vente, en francs CFA.
  final int montant;

  /// La remise, DÉRIVÉE — lignes brutes − net encaissé
  /// (`Vente::remiseDeduite()`), jamais une colonne recopiée. Zéro quand
  /// aucune remise ne s'applique, ou quand le montant n'est pas figé (vente
  /// annulée, panier d'avant la clôture).
  int get remiseDeduite {
    if (!montantFige) return 0;
    final brut = lignes.fold<int>(0, (t, l) => t + l.montant);
    return brut > montant ? brut - montant : 0;
  }

  /// [montant] vient-il du montant **figé à la clôture** ?
  ///
  /// Faux sur une vente annulée : `PanierDao.annuler` n'écrit aucun
  /// `montantCloture`, parce qu'aucun montant n'a été arrêté — le service a été
  /// abandonné avant paiement.
  final bool montantFige;

  /// ⚠ **`null` veut dire « non renseigné », jamais « espèces »**.
  ///
  /// `PanierDao.cloturer` accepte un `modePaiement` nul. Retomber sur les
  /// espèces ferait entrer en caisse un argent que personne n'a compté ; le
  /// ranger en note de chambre inventerait une créance. Le cas existe donc dans
  /// le type, il est compté à part, et il s'affiche.
  final ModeReglement? mode;

  /// Où se trouve l'argent — `null` sur une vente de séjour, qu'aucun écran
  /// n'ouvre depuis une caisse (`ecran_pos_heberges.dart`).
  final String? pointVente;

  /// Le libellé **courant** de la table, joint au référentiel.
  ///
  /// ⚠ Écart avec le maître, qui fige `table` ET `table_id` sur la vente et
  /// écrit pourquoi (`ventes-engine.js` l.289-293) : la clé seule obligerait à
  /// relire le référentiel pour afficher une vente ancienne dont la table a été
  /// renommée depuis.
  ///
  /// `paniers_local` ne fige que `tableId` et `espace`. Le risque est **borné
  /// et vérifiable** : aucune méthode de `TablesPosDao` ne renomme une table —
  /// `libelle` est dérivé du préfixe et du numéro à la création, et `basculer`
  /// ne touche que `actif`. Un libellé ne peut donc pas changer sans qu'on
  /// ajoute d'abord le chemin qui le changerait ; le jour où on l'ajoutera,
  /// c'est ici qu'il faudra figer.
  final String? tableLibelle;

  final String? clientNom;

  /// Le code de l'espace, **figé à l'ouverture du panier** — lui, il ne bouge
  /// pas.
  final String? espace;

  final String? reservationId;
  final String? motifAnnulation;

  /// Le numéro de la facture émise pour cette vente, **s'il en existe une**.
  ///
  /// Une vente sans facture est le cas normal ici, pas une anomalie : aucun des
  /// deux points de vente n'oblige à facturer. Un `null` ne doit donc jamais
  /// s'afficher comme un manquement.
  final String? numeroFacture;

  /// Le numéro `V-AAAA-NNNNN` du SERVEUR (v38), `null` tant qu'il ne l'a pas
  /// rendu : le poste n'en invente aucun.
  final String? numero;

  bool get estValidee => statut == StatutVente.validee;

  bool get estAnnulee => statut == StatutVente.annulee;

  bool get aUneFacture => numeroFacture != null;

  /// Les libellés des lignes qui n'ont décrémenté aucun stock
  /// (`stock_non_impacte`, colonne `ligne`).
  List<String> get lignesSansImpactStock => [
    for (final l in lignes)
      if (l.sansLienStock) l.libelle,
  ];

  /// `Vente::aDesLignesSansImpactStock()`.
  bool get aDesLignesSansImpactStock => lignes.any((l) => l.sansLienStock);

  /// L'argent est-il entré en caisse ? **`null` = on ne sait pas.**
  ///
  /// Trois réponses, pas deux — même discipline que les trois issues des écrans
  /// en ligne (reçu / refusé / injoignable) : « pas encaissé » et « on ignore
  /// comment cela a été réglé » ne se corrigent pas de la même façon.
  bool? get encaisse => mode?.encaisse;

  /// La référence lue à l'écran — **et ce n'est pas un `V-`**.
  ///
  /// ⚠ Aucune séquence de numéros de vente n'existe sur ce client : ni le
  /// schéma Drift ni le schéma serveur ne portent de numéro sur un panier
  /// (vérifié : la forme `V-` n'apparaît que dans `ventes-engine.js`). En
  /// fabriquer un à l'affichage serait pire que de ne pas en avoir — deux
  /// postes hors ligne attribueraient les mêmes numéros, et la numérotation du
  /// maître elle-même (l'année suivie du nombre de ventes plus une) est
  /// exactement le défaut que `FactureDao.numeroSuivant` refuse : un compteur
  /// déduit de la longueur d'une liste réattribue un numéro dès qu'une ligne
  /// disparaît.
  ///
  /// Ce qui est rendu est donc l'identifiant **réel** de la vente, abrégé pour
  /// tenir dans une colonne. L'écart est nommé à l'écran, pas dissimulé.
  String get referenceLocale {
    final brut = id.replaceAll('-', '').toUpperCase();
    return brut.length <= 8 ? brut : brut.substring(0, 8);
  }

  /// Les activités que cette vente recouvre, sans doublon et dans l'ordre du
  /// registre fermé — l'ordre des lignes ferait varier l'affichage d'une vente
  /// à l'autre pour le même contenu.
  List<ModuleVendable> get activites {
    final presents = lignes.map((l) => l.module).toSet();
    return [
      for (final m in ModuleVendable.values)
        if (presents.contains(m)) m,
    ];
  }

  /// Ventilation par activité — ce que la vente recouvre, et où.
  Map<ModuleVendable, int> get ventilation {
    final parModule = <ModuleVendable, int>{};
    for (final l in lignes) {
      parModule[l.module] = (parModule[l.module] ?? 0) + l.montant;
    }
    return parModule;
  }

  int get nombreArticles => lignes.fold(0, (t, l) => t + l.quantite);

  @override
  bool operator ==(Object other) => other is Vente && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'Vente($referenceLocale, ${statut.code}, ${lignes.length} ligne(s), '
      '$montant FCFA)';
}
