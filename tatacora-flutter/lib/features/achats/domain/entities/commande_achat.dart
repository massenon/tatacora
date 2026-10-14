// Vue Blade maîtresse (PA-183) : pwa/achats/achats.blade.php
// Vue Blade maîtresse (PA-183) : pwa/achats/approvisionnement.blade.php
/// Les commandes d'achat — M7, EF-M7-02, UC-29.
///
/// Sources serveur : `CommandeAchatResource`, `CommandeAchatDetailResource`,
/// `CreerCommandeAchatRequest`, `CommandeAchatService`. Maîtres :
/// `prototype_v2/pages/m7-achats.html` (onglet « Commandes d'achat ») et
/// `prototype_v2/pages/m7-approvisionnement.html` (onglet « Commandes »).
///
/// ## Les montants restent des CHAÎNES
///
/// `commandes_achat` ne porte aucune colonne de montant : le total se somme
/// depuis les lignes par `bcadd` côté serveur et descend en chaîne. Le
/// convertir en `double` pour le réafficher le réarrondirait, et l'écran dirait
/// un autre chiffre que le bon de commande remis au fournisseur.
library;

import '../decimal_texte.dart';
import 'bon_reception.dart';

/// Les cinq statuts de l'`enum` du schéma — celui qu'on FILTRE.
///
/// ## Deux registres, pas un — et [saisissable] est une DONNÉE
///
/// `CommandeAchat::STATUTS` en compte cinq ; `CommandeAchatService::
/// STATUTS_SAISISSABLES` n'en compte que **deux**. Les trois autres sont
/// produits par une réception qui a réellement généré ses entrées de stock :
/// les offrir à la création permettrait d'afficher une commande « Reçue » dont
/// aucune marchandise n'est entrée en stock — un indicateur qui affirme un état
/// qu'il n'a pas vérifié (PA-59/60/61).
///
/// [saisissable] est porté **cas par cas**, jamais dérivé d'un autre champ : un
/// prédicat dérivé du champ qu'il vérifie ne vérifie rien (piège 12). Il est
/// confronté au registre du serveur, relu dans son code source par
/// `test/features/achats/conformite_achats_test.dart`.
///
/// ## UN seul registre de libellés, celui de la PWA (PA-185)
///
/// Les deux vues de la PWA — `pwa/achats/achats.blade.php` et
/// `pwa/achats/approvisionnement.blade.php` (l.146, l.252) — lisent le MÊME
/// registre, `Achats::STATUTS` : « Réceptionnée partiellement »,
/// « Réceptionnée »… Jusqu'au 11/09/2026, ce client portait un second jeu
/// (« Reçue partiellement », « Reçue ») hérité de l'ancien prototype, dont les
/// deux pages nommaient différemment le même statut. La vue Blade est le seul
/// maître : un seul jeu, pour les deux écrans.
enum StatutCommande {
  brouillon('brouillon', 'Brouillon', true),
  envoyee('envoyee', 'Envoyée', true),
  receptionneePartiellement(
    'receptionnee_partiellement',
    'Réceptionnée partiellement',
    false,
  ),
  receptionnee('receptionnee', 'Réceptionnée', false),
  cloturee('cloturee', 'Clôturée', false);

  const StatutCommande(this.code, this.libelle, this.saisissable);

  /// Le code tel que le serveur l'attend et le renvoie — il part et revient
  /// tel quel. Une seconde table de correspondance finirait par envoyer un
  /// code refusé en 422, sur un écran qui semblait fonctionner.
  final String code;

  /// Le libellé de `Achats::STATUTS`, commun aux deux vues de la PWA.
  final String libelle;

  /// Vrai pour les deux statuts que `POST /achats/commandes` accepte.
  final bool saisissable;

  /// Les deux statuts offerts au formulaire, dans l'ordre du maître.
  static List<StatutCommande> get saisissables =>
      values.where((s) => s.saisissable).toList(growable: false);

  /// Les trois statuts que le maître offre au formulaire et que le serveur
  /// REFUSE à la création — nommés à l'écran, jamais retirés en silence.
  static List<StatutCommande> get refusesALaCreation =>
      values.where((s) => !s.saisissable).toList(growable: false);

  /// `null` sur un code inconnu — jamais un repli sur un cas plausible.
  static StatutCommande? depuisCode(String? code) {
    if (code == null) return null;
    for (final s in values) {
      if (s.code == code) return s;
    }
    return null;
  }
}

/// Une commande telle que le REGISTRE la rend (`CommandeAchatResource`).
final class CommandeAchat {
  const CommandeAchat({
    required this.id,
    required this.dateCommande,
    required this.statutCode,
    required this.fournisseurId,
    required this.fournisseurRaisonSociale,
    required this.nombreLignes,
    required this.montantTotal,
    required this.montantRegle,
    required this.resteDu,
    required this.receptionnable,
    required this.cloturable,
  });

  final String id;
  final String dateCommande;

  /// Le code brut, conservé même inconnu : c'est lui qu'on affiche alors.
  final String statutCode;

  final String fournisseurId;

  /// Vide quand la relation n'a pas été jointe : l'écran affiche alors
  /// l'identifiant, jamais une raison sociale de remplacement.
  final String fournisseurRaisonSociale;

  final int nombreLignes;

  /// CALCULÉ par le serveur depuis les lignes, en chaîne. Jamais saisi : le
  /// maître porte « Montant estimé (FCFA) » en champ de formulaire (l.276) et
  /// `CreerCommandeAchatRequest` le refuse (PA-24).
  final String montantTotal;

  /// La somme des règlements ACTIFS de la commande (`totalRegle()` du service) :
  /// « Réglé » de la vue. Une chaîne à deux décimales, calculée de
  /// `reglements_fournisseur_local`, jamais stockée (voir
  /// `reglements_fournisseur_tables.dart`).
  final String montantRegle;

  /// Le reste dû tel que la VUE le calcule (`Approvisionnement::render`) :
  /// `montantTotal() − totalRegle()`, planché à zéro. « Reste dû » de la vue.
  final String resteDu;

  /// Dérivés par le serveur (`estCloturee()`, `statut === 'receptionnee'`).
  ///
  /// **Jamais recalculés ici** : deux lectures indépendantes finiraient par
  /// diverger, et l'écran proposerait un bouton que le serveur refuse — ou
  /// masquerait une action permise.
  final bool receptionnable;
  final bool cloturable;

  StatutCommande? get statut => StatutCommande.depuisCode(statutCode);

  /// Le libellé de `Achats::STATUTS` — le même pour les deux écrans depuis
  /// PA-185 —, ou le code brut s'il est inconnu : jamais un repli sur un cas
  /// plausible.
  String get libelleStatut => statut?.libelle ?? statutCode;

  /// Une commande en brouillon se laisse émettre — `PATCH /commandes/{id}/envoi`.
  ///
  /// Dérivé du statut et non d'un drapeau du serveur : la ressource n'en
  /// expose pas. Le service, lui, refuse tout ce qui n'est pas `brouillon`
  /// (`CommandeAchatService::envoyer`), et c'est cette règle-là qui est reprise
  /// mot pour mot.
  bool get envoyable => statutCode == StatutCommande.brouillon.code;
}

/// Une ligne du détail (`CommandeAchatDetailResource::ligne()`).
final class LigneCommande {
  const LigneCommande({
    required this.id,
    required this.articleId,
    required this.articleLibelle,
    required this.uniteMesure,
    required this.quantiteCommandee,
    required this.prixUnitaire,
    required this.montant,
    required this.quantiteRecue,
    required this.resteARecevoir,
  });

  final String id;
  final String articleId;

  /// `null` quand la relation `article` n'a pas été chargée — l'écran affiche
  /// l'identifiant plutôt qu'un libellé inventé.
  final String? articleLibelle;
  final String? uniteMesure;

  final String quantiteCommandee;
  final String prixUnitaire;
  final String montant;

  /// **Reconstituée** depuis les mouvements de stock, faute de lignes de bon
  /// de réception au schéma (PA-39). Le drapeau `recuReconstitue` du détail
  /// porte cet aveu jusqu'à l'écran.
  final String quantiteRecue;

  /// Calculé par le serveur, **planché à zéro** : un excédent ne devient pas un
  /// reste négatif à recevoir. Repris tel quel, jamais recalculé.
  final String resteARecevoir;

  String get libelleArticle => articleLibelle ?? articleId;
}

/// Le détail d'une commande (`CommandeAchatDetailResource`).
final class CommandeAchatDetail {
  const CommandeAchatDetail({
    required this.commande,
    required this.fournisseurContact,
    required this.fournisseurConditionsPaiement,
    required this.lignes,
    required this.receptions,
    required this.recuReconstitue,
  });

  final CommandeAchat commande;
  final String? fournisseurContact;
  final String? fournisseurConditionsPaiement;
  final List<LigneCommande> lignes;

  /// Les bons de réception déjà enregistrés — la modale les affiche pour que
  /// le magasinier voie ce qui a déjà été porté au stock avant de saisir.
  final List<BonReception> receptions;

  /// `true` en permanence côté serveur, et affiché : la quantité déjà reçue est
  /// relue du journal de stock, pas d'une table de lignes de réception. Une
  /// entrée saisie à la main avec un motif ressemblant serait comptée comme une
  /// réception (PA-39).
  final bool recuReconstitue;

  /// Les lignes qui restent à recevoir, dans l'ordre du serveur.
  List<LigneCommande> get lignesARecevoir => lignes
      .where((l) => estStrictementPositif(l.resteARecevoir))
      .toList(growable: false);
}

/// Une ligne du formulaire de commande.
final class LigneSaisieCommande {
  const LigneSaisieCommande({
    required this.articleId,
    required this.libelle,
    required this.uniteMesure,
    required this.quantite,
    required this.prixUnitaire,
  });

  final String articleId;

  /// Affiché seulement — il ne part pas au serveur, qui relit le libellé
  /// depuis `articles`. L'envoyer laisserait croire qu'on fige le nom de
  /// l'article sur la commande, ce que le schéma ne fait pas.
  final String libelle;
  final String uniteMesure;

  final String quantite;
  final String prixUnitaire;

  /// `quantite × prixUnitaire`, en chaîne, `null` si l'un des deux est
  /// illisible. Affiché en lecture seule : le serveur recalcule le sien.
  String? get montant => multiplier(quantite, prixUnitaire);

  LigneSaisieCommande copyWith({String? quantite, String? prixUnitaire}) =>
      LigneSaisieCommande(
        articleId: articleId,
        libelle: libelle,
        uniteMesure: uniteMesure,
        quantite: quantite ?? this.quantite,
        prixUnitaire: prixUnitaire ?? this.prixUnitaire,
      );
}

/// Ce que le formulaire « Nouveau bon de commande » soumet —
/// `m7-approvisionnement.html` l.560-614.
final class SaisieCommande {
  const SaisieCommande({
    required this.fournisseurId,
    required this.dateCommande,
    required this.statut,
    required this.lignes,
  });

  /// Une VRAIE clé étrangère. Le maître propose une liste de raisons sociales
  /// écrites en dur dans son JavaScript (l.555-556) ; `commandes_achat.
  /// fournisseur_id` est une relation, et le texte libre casserait
  /// silencieusement le rapprochement à trois voies (EF-M7-04).
  final String fournisseurId;

  final String dateCommande;
  final StatutCommande statut;
  final List<LigneSaisieCommande> lignes;

  /// Le total de la commande, sommé ligne à ligne **en chaînes**.
  ///
  /// `null` dès qu'une ligne est illisible : mieux vaut ne rien afficher qu'un
  /// total amputé d'une ligne, qui se lit exactement comme un total juste.
  String? get montantTotal {
    var total = '0.00';
    for (final l in lignes) {
      final m = l.montant;
      if (m == null) return null;
      final somme = additionner(total, m);
      if (somme == null) return null;
      total = somme;
    }
    return total;
  }

  /// Le motif de refus des articles en double, ou `null` si la saisie est
  /// saine — EF-M7-02.
  ///
  /// ## Pourquoi c'est refusé ICI et pas seulement au serveur
  ///
  /// `ReceptionService::evaluerConformite()` relit les quantités commandées par
  /// `pluck('quantite_commandee', 'article_id')` : un article présent sur deux
  /// lignes verrait la seconde **écraser** la première. La commande porterait
  /// 30 + 20 sacs, le contrôle RG-10 n'en verrait que 20, et une livraison de
  /// 50 serait déclarée en excédent hors tolérance — donc `non_conforme`.
  ///
  /// Le serveur refuse (`distinct`), mais il refuse **le lot entier** après un
  /// aller-retour : le refus est posé en amont, là où l'utilisateur peut encore
  /// corriger la ligne fautive, et avec la raison plutôt qu'un code 422.
  String? get erreurArticlesEnDouble {
    final vus = <String>{};
    for (final l in lignes) {
      if (!vus.add(l.articleId)) {
        return 'L’article « ${l.libelle} » figure deux fois. Les quantités '
            'commandées sont relues article par article : la seconde ligne '
            'écraserait la première, et le contrôle de réception comparerait '
            'le reçu à une quantité commandée sous-évaluée.';
      }
    }
    return null;
  }

  /// Le corps de `POST /achats/commandes`.
  ///
  /// **Aucun `id`** : `CreerCommandeAchatRequest` le pose `prohibited` —
  /// `commandes_achat` n'est pas au registre `TABLES_SYNCHRONISABLES` et aucun
  /// mécanisme de rejeu n'existe. En envoyer un laisserait croire à une
  /// idempotence qui n'a pas lieu.
  ///
  /// **Aucun `montant_estime`** : il figure dans
  /// `CreerCommandeAchatRequest::CHAMPS_CALCULES`, donc **interdit**, pas
  /// ignoré (PA-24). Le maître le porte pourtant en champ de saisie (l.276).
  Map<String, dynamic> versJson() => {
    'fournisseur_id': fournisseurId,
    'date_commande': dateCommande,
    'statut': statut.code,
    'lignes': [
      for (final l in lignes)
        {
          'article_id': l.articleId,
          'quantite_commandee': l.quantite,
          'prix_unitaire': l.prixUnitaire,
        },
    ],
  };
}
