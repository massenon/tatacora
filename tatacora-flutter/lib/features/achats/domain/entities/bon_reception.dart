// Vue Blade maîtresse (PA-183) : pwa/achats/approvisionnement.blade.php
/// Les bons de réception et le rapprochement — M7, EF-M7-03, EF-M7-04, RG-10.
///
/// Sources serveur : `BonReceptionResource`, `RapprochementResource`,
/// `EnregistrerReceptionRequest`, `ReceptionService`. Maître :
/// `prototype_v2/pages/m7-approvisionnement.html`, onglet « Réceptions » et
/// modale « Réception » (l.617-687).
library;

import '../decimal_texte.dart';

/// Le verdict RG-10, tel que l'`enum` du schéma le porte.
///
/// ## Trois valeurs, pas deux — et le maître n'en montre que deux
///
/// L'onglet du maître ne connaît que « Conformes » / « Avec écart » (l.421-422)
/// et regroupe donc `partielle` et `non_conforme`. `BonReception::CONFORMITES`
/// refuse ce regroupement, et la raison est écrite au serveur : recevoir MOINS
/// que commandé ouvre une **créance sur le fournisseur** ; recevoir un article
/// **hors commande**, ou un excédent hors tolérance, est une anomalie d'une
/// tout autre nature — une facture plus élevée que prévu.
///
/// Le filtre de l'écran porte donc sur les trois valeurs réelles :
/// `FiltrerReceptionsRequest` n'accepte pas « avec écart », et le regrouper
/// côté client sur une liste **paginée par le serveur** ne filtrerait que la
/// page affichée.
enum ConformiteReception {
  totale('totale', 'Totale'),
  partielle('partielle', 'Partielle'),
  nonConforme('non_conforme', 'Non conforme');

  const ConformiteReception(this.code, this.libelle);

  final String code;

  /// Le libellé français. **Écart nommé** : le maître interpole le code brut
  /// dans son badge (l.474, `${r.conformite}`) — il affiche donc « totale » en
  /// minuscule, ce qui est un artefact de prototype et non un choix de
  /// copywriting. Le code brut reste affiché quand la valeur est inconnue.
  final String libelle;

  /// Vrai pour les deux verdicts que le maître regroupe sous « Avec écart ».
  ///
  /// Donnée dérivée du **code**, pas d'un champ jumeau : la comparer à un
  /// booléen porté par le même cas ne vérifierait rien (piège 12).
  bool get avecEcart => this != ConformiteReception.totale;

  static ConformiteReception? depuisCode(String? code) {
    if (code == null) return null;
    for (final c in values) {
      if (c.code == code) return c;
    }
    return null;
  }
}

/// Un bon de réception, tel que `BonReceptionResource` le rend.
///
/// ## Trois colonnes du maître n'ont AUCUNE source, et ne sont pas inventées
///
/// `bons_reception` n'a ni séquence, ni point de stockage conservé, ni table de
/// lignes (PA-39). Le serveur le dit lui-même par `lignes_non_stockees` :
///
/// - **le numéro** (« N° », l.430) — seulement un UUID. Fabriquer un
///   « BR-0001 » à l'affichage donnerait un numéro qui changerait au prochain
///   tri ;
/// - **le point de stockage** (l.434) — il est passé à la réception, sert à
///   imputer l'entrée de stock, et n'est **jamais conservé** sur le bon ;
/// - **le nombre d'articles reçus** (l.435) — la table n'a pas de lignes.
final class BonReception {
  const BonReception({
    required this.id,
    required this.commandeId,
    required this.dateReception,
    required this.conformiteCode,
    required this.fournisseurRaisonSociale,
    required this.lignesNonStockees,
    this.pointLibelle,
    this.nombreArticles,
  });

  final String id;
  final String commandeId;
  final String dateReception;

  /// Le code brut, conservé même inconnu.
  final String conformiteCode;

  /// `null` quand la relation n'a pas été jointe.
  final String? fournisseurRaisonSociale;

  /// L'aveu du serveur, porté jusqu'à l'écran : ni les quantités reçues ni le
  /// point d'imputation ne sont conservés par cette table.
  ///
  /// **Jamais un défaut permissif.** Une réponse muette est lue comme « non
  /// stocké » : un `?? false` laisserait croire que le détail existe quelque
  /// part, et quelqu'un le chercherait.
  final bool lignesNonStockees;

  /// Le point de stockage qui a reçu l'entrée de stock — `null` quand la
  /// source ne le conserve pas (le serveur, PA-39). Ce poste le conserve
  /// (`bons_reception_local.point_stockage_id`) et l'écran l'affiche ; `null`
  /// s'affiche « — », jamais un point deviné.
  final String? pointLibelle;

  /// Le nombre d'articles distincts reçus — `null` sans lignes de bon (le
  /// serveur). Ici : le nombre de lignes de `lignes_bon_reception_local`.
  final int? nombreArticles;

  ConformiteReception? get conformite =>
      ConformiteReception.depuisCode(conformiteCode);

  String get libelleConformite => conformite?.libelle ?? conformiteCode;

  /// `null` quand le code est inconnu — l'écran neutralise alors la pastille
  /// plutôt que de déclarer conforme ce qu'il ne sait pas lire.
  bool? get avecEcart => conformite?.avecEcart;
}

/// Une ligne du formulaire de réception — `m7-approvisionnement.html`
/// l.642-653.
final class LigneSaisieReception {
  const LigneSaisieReception({
    required this.articleId,
    required this.libelle,
    required this.uniteMesure,
    required this.quantiteCommandee,
    required this.quantiteDejaRecue,
    required this.quantiteRecue,
  });

  final String articleId;
  final String libelle;
  final String uniteMesure;

  /// Les deux colonnes de contexte du maître (« Commandé », « Déjà reçu »),
  /// affichées en lecture seule. Sans le « déjà reçu », une seconde réception
  /// repartirait de la quantité commandée entière et ferait entrer la
  /// marchandise **deux fois** en stock.
  final String quantiteCommandee;
  final String quantiteDejaRecue;

  /// La seule valeur saisie. Vide = « rien reçu sur cet article ».
  final String quantiteRecue;

  LigneSaisieReception copyWith({String? quantiteRecue}) =>
      LigneSaisieReception(
        articleId: articleId,
        libelle: libelle,
        uniteMesure: uniteMesure,
        quantiteCommandee: quantiteCommandee,
        quantiteDejaRecue: quantiteDejaRecue,
        quantiteRecue: quantiteRecue ?? this.quantiteRecue,
      );
}

/// Ce que la modale « Réception » soumet — `POST /achats/commandes/{id}/receptions`.
///
/// ## Une quantité à zéro s'OMET, elle ne se déclare pas
///
/// `EnregistrerReceptionRequest` pose `gt:0` sur chaque ligne. Le maître, lui,
/// pré-remplit toutes les lignes et n'envoie que celles `> 0` (l.673-677) : la
/// même règle, et pour la raison qu'écrit le serveur — le service ignorerait
/// une ligne à zéro pour le mouvement de stock mais la compterait dans le
/// verdict de conformité, soit deux comportements pour une même saisie.
///
/// L'absence d'un article vaut déjà « rien reçu » pour RG-10.
///
/// ## Aucun champ calculé
///
/// `EnregistrerReceptionRequest::CHAMPS_CALCULES` interdit `conformite`,
/// `statut`, `tolerance_pct` et `ecart_pct`. Le verdict est produit par
/// `ReceptionService::evaluerConformite()` ; l'accepter en entrée permettrait
/// de déclarer « totale » une livraison amputée de moitié, et la créance sur le
/// fournisseur serait perdue sans que rien ne le signale.
final class SaisieReception {
  const SaisieReception({
    required this.commandeId,
    required this.pointStockageId,
    required this.dateReception,
    required this.lignes,
  });

  final String commandeId;

  /// Une VRAIE clé étrangère (`exists:points_stockage,id`). Le maître envoie un
  /// libellé (`point_stockage: 'Bar'`, l.680) parce que son moteur travaille en
  /// `localStorage` — ici il serait rejeté.
  final String pointStockageId;

  /// Facultative côté serveur (`sometimes|nullable`) : `null` laisse le serveur
  /// dater du jour. Une date posée par le client sur l'horloge du poste
  /// divergerait de celle du serveur sur un poste mal réglé, et c'est cette
  /// date qui situe l'entrée de stock.
  final String? dateReception;

  final List<LigneSaisieReception> lignes;

  /// Les lignes réellement envoyées : celles dont la quantité est lisible et
  /// strictement positive.
  List<LigneSaisieReception> get lignesRetenues =>
      lignes.where((l) => _positive(l.quantiteRecue)).toList(growable: false);

  /// Le motif de refus, ou `null`. Deux refus, tous deux repris du serveur.
  String? get erreur {
    if (lignesRetenues.isEmpty) {
      return 'Une réception porte sur au moins un article reçu. Une quantité à '
          'zéro n’est pas une réception : elle serait ignorée pour le stock '
          'mais comptée dans le verdict de conformité.';
    }

    final vus = <String>{};
    for (final l in lignesRetenues) {
      if (!vus.add(l.articleId)) {
        return 'L’article « ${l.libelle} » figure deux fois. Les quantités '
            'reçues sont relues article par article : la seconde ligne '
            'écraserait la première, et la marchandise entrerait en stock '
            'amputée de la première.';
      }
    }
    return null;
  }

  Map<String, dynamic> versJson() => {
    'point_stockage_id': pointStockageId,
    if (dateReception != null) 'date_reception': dateReception,
    'lignes': [
      for (final l in lignesRetenues)
        {'article_id': l.articleId, 'quantite_recue': l.quantiteRecue},
    ],
  };

  /// « Est-ce strictement positif ? », en centièmes entiers.
  ///
  /// Jamais `double.tryParse` : la quantité part au serveur **telle qu'elle a
  /// été frappée**, et ouvrir une conversion ici, même pour un simple test,
  /// rouvrirait la porte que `decimal_texte.dart` existe pour fermer. Une
  /// saisie mal formée (« 2. », « abc ») n'est pas positive : elle est
  /// illisible, donc écartée — le champ, lui, la refuse avec sa raison.
  static bool _positive(String brut) => estStrictementPositif(brut);
}

/// Une ligne du rapprochement (`ControleTroisVoiesService::rapprocher`).
final class LigneRapprochement {
  const LigneRapprochement({
    required this.articleId,
    required this.commandee,
    required this.recue,
    required this.ecart,
    required this.concordance,
    this.libelle,
  });

  final String articleId;

  /// Le libellé de l'article tel qu'il était à la commande (FIGÉ à l'ajout),
  /// ou `null` quand la source ne le joint pas (le serveur). Sans lui l'écran
  /// affiche l'identifiant, jamais un nom inventé.
  final String? libelle;
  final String commandee;
  final String recue;

  /// `recue - commandee`, calculé par le serveur en `bcsub`. Négatif = manque.
  final String ecart;

  /// `conforme`, `manquant` ou `excedent` — le code du serveur, affiché tel
  /// quel s'il est inconnu.
  final String concordance;
}

/// Le rapprochement d'une commande — EF-M7-04.
///
/// ## Il ne porte JAMAIS sur trois voies, et il le dit
///
/// `facture_verifiable` sort toujours à `false` : aucune table du schéma ne
/// porte de facture fournisseur — `factures` est la facturation CLIENT (M2), de
/// nature opposée. `ControleTroisVoiesService` accepte bien un tableau de
/// montants facturés, mais **ne le compare à rien** : il le teste contre `null`
/// et retire l'avertissement. La route ne l'expose donc pas, et cet écran ne
/// peut pas l'envoyer.
///
/// C'est la forme exacte de PA-59/60/61, sur la pièce qui autorise le paiement
/// d'un fournisseur : un rapprochement présenté comme complet alors qu'il ne
/// porte que sur deux voies est pire que pas de rapprochement du tout — il
/// donne une assurance qu'il n'a pas.
///
/// [avertissements] descend du serveur et **doit être affiché**.
final class Rapprochement {
  const Rapprochement({
    required this.commandeId,
    required this.concordanceGlobale,
    required this.factureVerifiable,
    required this.voiesVerifiees,
    required this.avertissements,
    required this.lignes,
  });

  final String commandeId;

  /// `conforme` ou `ecart_constate`.
  final String concordanceGlobale;

  /// **Jamais un défaut permissif** : une réponse muette est lue comme non
  /// vérifiable. Un `?? true` annoncerait un contrôle à trois voies dont on
  /// ignore le résultat.
  final bool factureVerifiable;

  /// Les voies réellement confrontées, telles que le serveur les nomme.
  final List<String> voiesVerifiees;

  final List<String> avertissements;
  final List<LigneRapprochement> lignes;

  bool get estConforme => concordanceGlobale == 'conforme';
}
