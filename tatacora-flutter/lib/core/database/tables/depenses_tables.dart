/// M10 — **Dépense courante**, en local pur.
///
/// Maître : la vue `depenses/depenses.blade.php` — chemin écrit **sans son
/// préfixe**, délibérément : ce fichier ne porte pas la vue, et la citer en
/// entier le ferait compter comme porteur par le comparateur de conformité
/// (PA-187). Seul `ecran_depenses.dart` la cite.
///
/// ## Deux colonnes que le serveur porte et qui ne sont PAS ici, une qui y est
///
/// **`numero`** (absente) — `DepenseService` alloue « DEP-… » par
/// `SequenceDocumentService`. Ce poste n'alloue aucun numéro de cette séquence :
/// la dépense ne monte pas au serveur — `TABLES_SYNCHRONISABLES` ne connaît que
/// `reservations` et `clients` — et un « DEP-00007 » fabriqué ici serait la
/// version comptable de PA-113. Ce que la dépense porte à la place est le
/// numéro de PIÈCE comptable, alloué par le moteur (voir ci-dessous).
///
/// **`ecriture_id` et `ecriture_refus`** (présentes depuis la v16, 10/10/2026)
/// — le moteur comptable local existe (v15) et la dépense l'appelle. Qui les
/// écrit, qui les lit, qui les descend (pièges 9 et 11) :
///
/// | Colonne | Qui l'écrit | Qui la lit | Qui la descend |
/// |---|---|---|---|
/// | `ecriture_id` | `DepenseDao.enregistrer` (la ligne de TRESORERIE de la pièce, dans la même transaction que la dépense) et `DepenseDao.comptabiliser` (rattrapage d'une dépense antérieure) ; NULL tant qu'aucune pièce n'existe | l'écran (numéro de pièce, pastille, indicateur, bouton de rattrapage), l'export | personne : zéro réseau |
/// | `ecriture_refus` | `DepenseDao.comptabiliser`, seul, quand le rattrapage est refusé (hors transaction, pour survivre au rejet) ; remise à NULL au succès | l'infobulle de la pastille | personne |
///
/// `ecriture_id` désigne UNE ligne, celle de trésorerie, comme au serveur ; le
/// NUMÉRO de pièce n'est pas recopié, il est lu de l'écriture. Une dépense
/// saisie avant la v16 n'a ni l'un ni l'autre : elle s'affiche « sans pièce
/// comptable », jamais comme comptabilisée (PA-59/60/61).
///
/// **`montant_total`** — il n'est pas stocké : il se SOMME des lignes à chaque
/// lecture. Le maître l'écrit lui-même, « il ne se saisit pas », et une colonne
/// dénormalisée deviendrait fausse au premier correctif de ligne. C'est la
/// règle n° 2 du dépôt appliquée au schéma et pas seulement à l'écran.
///
/// ## Aucune colonne de synchronisation
///
/// Pas de `statutSync`, pas de `statutTransmission`. `depenses` n'est à aucun
/// registre synchronisable : une entrée de file y serait rejetée à chaque
/// tentative, et un badge « en attente de synchronisation » sur ce qui ne
/// partira jamais est exactement l'indicateur qui affirme un état qu'il n'a pas
/// vérifié. L'écran dit « enregistré sur ce poste ».
library;

import 'package:drift/drift.dart';

import 'comptabilite_tables.dart';

/// L'en-tête d'une dépense — ce qui est GLOBAL à la pièce.
///
/// Le décaissement est unique : une seule sortie d'argent, donc une seule date,
/// une seule trésorerie et un seul libellé de pièce. Ce qui est par LIGNE — le
/// libellé de l'achat, son compte de charge, sa catégorie et son prix — vit
/// dans [LignesDepenseLocal].
class DepensesLocal extends Table {
  /// UUID posé **côté client**, comme partout ailleurs dans ce dépôt.
  TextColumn get id => text()();

  /// Le jour de la sortie d'argent — « Date de la transaction » du maître.
  DateTimeColumn get dateTransaction => dateTime()();

  /// `caisse` | `momo` | `banque`.
  ///
  /// Ce sont les **clés** de `DepenseService::TRESORERIES`, jamais ses
  /// libellés : un test serveur les fige, et stocker « Mobile Money » à la
  /// place de `momo` casserait le jour où la dépense monterait.
  TextColumn get tresorerie => text()();

  /// « Libellé de la dépense » — celui de la pièce, pas celui d'un achat.
  TextColumn get libelle => text()();

  /// L'horodatage de saisie, pour départager deux dépenses du même jour.
  ///
  /// Sans lui, deux pièces saisies le même jour auraient un ordre indéfini et
  /// la liste changerait d'ordre à chaque rafraîchissement sans qu'aucune
  /// donnée n'ait bougé (même raison que `PanierDao.paniers`).
  DateTimeColumn get saisieLe => dateTime().withDefault(currentDateAndTime)();

  /// La ligne de TRESORERIE de la pièce comptable de cette dépense — NULL tant
  /// qu'aucune pièce n'existe (dépense saisie avant la v16, ou rattrapage
  /// refusé). Clé étrangère : une dépense ne peut pas désigner une écriture qui
  /// n'existe pas. Voir l'en-tête du fichier pour qui l'écrit et qui la lit.
  TextColumn get ecritureId =>
      text().nullable().references(EcrituresLocal, #id)();

  /// La raison du dernier rattrapage refusé, ou NULL. Écrite pour être VUE
  /// (infobulle de la pastille), jamais pour décider d'un état : l'état d'une
  /// dépense se lit de `ecriture_id`, seule preuve qu'une pièce existe.
  TextColumn get ecritureRefus => text().nullable()();

  /// LE REÇU EN IMAGE (v42, 27/10/2026 — lot L4, décision du PO : la dépense du
  /// poste joint un reçu comme l'écran web, et le fichier voyage par la
  /// synchronisation). SIX colonnes NULLABLES, toutes nulles pour l'existant :
  /// aucune valeur n'est fabriquée (« sans reçu »). **Le fichier n'est JAMAIS
  /// dans Drift** : il est rangé dans `recus_depenses/` à côté de `poste.json`
  /// (comme les archives de clôture), et la ligne n'en garde que la RÉFÉRENCE.
  ///
  /// Le nom du fichier rangé (`<id de la dépense>.<ext>`). `null` tant que le
  /// fichier n'est pas sur ce poste (reçu d'un autre poste, pas encore
  /// téléchargé) — la présence d'un reçu se lit de [recuStatut], pas d'ici.
  TextColumn get recuNom => text().nullable()();

  /// L'empreinte SHA-256 (hexadécimale) : elle rend le dépôt idempotent au
  /// serveur et permet de vérifier un téléchargement. `null` pour un reçu que
  /// l'écran web a joint avant que les empreintes existent.
  TextColumn get recuSha256 => text().nullable()();

  /// La taille en octets.
  IntColumn get recuTaille => integer().nullable()();

  /// Le type MIME (`image/png`…), lu du CONTENU.
  TextColumn get recuType => text().nullable()();

  /// L'état du reçu : `en_attente` | `envoye` | `refuse` | `du_serveur`
  /// (`StatutRecu`). `null` = la dépense n'a pas de reçu. **`envoye` n'est
  /// écrit qu'après l'accusé du serveur** (piège 1).
  TextColumn get recuStatut => text().nullable()();

  /// La cause d'un refus du serveur (`recu_statut = refuse`), dite à l'écran.
  TextColumn get recuCause => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Une LIGNE d'achat de la dépense.
///
/// ## Le multi-lignes vient du Product Owner, pas de la maquette
///
/// Décision du 31/08/2026, reprise par la vue : *« une dépense globale peut
/// contenir une ou plusieurs lignes de libellé d'achats ou autre avec son
/// prix »*. La maquette d'origine portait UN montant et UN compte ; l'écart est
/// donc dans le sens où l'écran fait PLUS qu'elle, et il se déclare.
///
/// ## Compte, nature et famille sont FIGÉS à l'enregistrement
///
/// Les trois sont recopiés au moment de la saisie, jamais rejoints à la
/// lecture. Même raisonnement que le prix et le libellé d'une ligne de panier
/// (règle 3) et que `tarifNuit` (PA-55) : le registre dit ce qu'on propose
/// aujourd'hui, la ligne dit ce qui a été acheté. Déplacer demain « Transport »
/// de « Services » vers « Marché » ne doit pas réécrire les dépenses de l'an
/// dernier, ni les deux indicateurs qui les somment.
class LignesDepenseLocal extends Table {
  TextColumn get id => text()();

  TextColumn get depenseId => text().references(DepensesLocal, #id)();

  /// « Libellé » de la colonne des lignes — l'achat, pas la pièce.
  TextColumn get libelle => text()();

  /// Le numéro SYSCOHADA à six chiffres — « Catégorie des charges (SYSCOHADA) ».
  ///
  /// Six chiffres (`601100`), jamais trois : le composant serveur portait
  /// `601`, `614`, `628` — des numéros qu'aucun plan comptable du dépôt ne
  /// contient, et qui n'ont jamais été confrontés à un référentiel puisqu'aucune
  /// écriture n'était tentée.
  TextColumn get compteCharge => text()();

  /// « Catégorie de dépenses » — l'une des douze natures du registre fermé.
  TextColumn get nature => text()();

  /// La famille de la nature — « Marché » ou « Services ».
  ///
  /// Elle est **stockée** et non déduite à la lecture, pour la raison écrite
  /// plus haut, et parce que ce sont les deux indicateurs du maître qui la
  /// somment : une dépense mêlée compte chaque ligne dans SA famille.
  TextColumn get famille => text()();

  /// Prix en francs CFA — **entier**. Le XOF n'a pas de sous-unité en
  /// circulation, et un `REAL` rendrait deux lignes à 0,1 F différentes de
  /// 0,2 F sur le total.
  IntColumn get montant => integer()();

  DateTimeColumn get ajouteeLe => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
