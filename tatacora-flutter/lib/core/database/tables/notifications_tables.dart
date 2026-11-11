/// M12 Notifications — le logiciel TRACE un message ; l'ENVOI par e-mail est
/// RÉEL depuis le 26/10/2026 (schéma v39).
///
/// ⚠ MISE À JOUR du 26/10/2026 (décision du PO : « l'envoi réel d'e-mails DOIT
/// ÊTRE IMPLÉMENTÉ EN POSTE ET WEB »). Le canal e-mail part par SMTP, depuis la
/// boîte d'envoi (`boite_envoi_emails_tables.dart`) ; `envoye` s'écrit
/// UNIQUEMENT dans la transaction qui consigne l'accusé du relais SMTP
/// (`NotificationsDao.marquerEnvoyeParLeSysteme`). WhatsApp, Android et SMS ne
/// partent toujours pas (aucun canal contracté). Les paragraphes ci-dessous
/// décrivent l'état d'AVANT et restent vrais pour ces trois canaux.
///
/// ══════════════════════════════════════════════════════════════════════════
/// ⚠ LIRE AVANT TOUTE REPRISE DE CE FICHIER
/// ══════════════════════════════════════════════════════════════════════════
///
/// **RG-20 (diffusion automatique) n'est pas implementee, et aucun canal n'est
/// contracte** : ni l'API WhatsApp Business, ni un relais SMTP, ni un
/// agregateur SMS, ni un appareil Android enregistre. Sur CE poste, qui est
/// hors ligne par construction, aucun envoi n'est meme techniquement possible.
///
/// Le maitre ecrit lui-meme la consequence, et elle commande tout le module :
/// « un message marque "envoye" alors que rien n'est parti serait pire que pas
/// de module du tout : le Gerant croirait son client prevenu ». C'est la
/// famille PA-59/60/61 — un indicateur qui affirme un etat que rien n'a
/// verifie.
///
/// Deux consequences de schema, deliberees :
///
/// 1. **Aucune colonne `statutSync`.** Les MESSAGES traces ne partent
///    jamais (aucune entree de file : un badge « en attente » sur ce qui ne
///    partira pas est le defaut PA-98) ; l'ecran dit « enregistre sur ce
///    poste ». Les MODELES, eux, sont une configuration : depuis le lot 10f
///    (18/10/2026), `NotificationsDao` enfile leur creation et leurs
///    retouches (`modeles_notification`, etat entier) et l'aligneur du
///    catalogue inscrit ceux du serveur (`inscrireDescendu`, appariement par
///    le couple evenement × canal). L'attente se lit dans la file.
/// 2. **Aucune table `notifications_envoyees`.** Le serveur en a une, et son
///    KPI « Reellement envoyes » la COMPTE. La transposer ici creerait une
///    table que RIEN n'ecrit — le defaut n° 09 du guide Flutter, celui de
///    `clients_local.solde` (PA-126) et des trois tables de stock (PA-134).
///    Le compteur se derive donc du STATUT des messages traces
///    ([MessagesNotificationLocal.statut]), sur la table reelle : il vaut zero
///    parce qu'aucun geste local ne peut produire ce statut, pas parce qu'une
///    constante le dit. Le jour ou un transport existera, le compteur suivra
///    sans qu'on touche a l'ecran.
///
/// ## Ce qui n'est PAS une table ici, et pourquoi
///
/// Les **declencheurs** (neuf evenements) et les **canaux** (quatre) sont des
/// REGISTRES FERMES, portes par des `enum` du domaine
/// (`features/notifications/domain/entities/`), jamais des tables. Le
/// raisonnement est celui de `RegistreCanaux` cote serveur : un canal n'est
/// pas une donnee de gestion, c'est une capacite technique du produit. Une
/// table le rendrait creable depuis l'ecran, et quelqu'un poserait « Fax »
/// sans que rien ne sache l'emprunter.
library;

import 'package:drift/drift.dart';

/// Un modele de message — une CONFIGURATION, jamais une promesse d'envoi.
///
/// `actif` dit que le modele « sera pris en compte a la prochaine detection »
/// (les mots du maitre). Il ne dit pas qu'un message part.
///
/// `evenement` porte le CODE du declencheur, jamais une phrase : le libelle
/// lisible vit dans le registre ferme. Deux listes de libelles, une en base et
/// une au code, finissent par diverger — c'est le defaut rencontre cinq fois
/// sur les seeders du serveur (PA-161).
class ModelesNotificationLocal extends Table {
  /// UUID pose **cote client**, comme partout ailleurs dans ce depot.
  TextColumn get id => text()();

  /// Code du registre ferme `DeclencheurNotification`.
  TextColumn get evenement => text()();

  /// Code du registre ferme `CanalNotification`.
  TextColumn get canal => text()();

  /// Objet — e-mail et push seulement. Nul ailleurs.
  TextColumn get objet => text().nullable()();

  /// Le texte a trous, avec ses variables `{nom}`.
  TextColumn get contenuTemplate => text()();

  BoolColumn get actif => boolean().withDefault(const Constant(true))();

  DateTimeColumn get creeLe => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get modifieLe => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  /// Un seul modele par couple (evenement, canal) — la contrainte du serveur.
  ///
  /// Elle est ici la GARANTIE ; le controle explicite du DAO ne sert qu'a
  /// NOMMER le refus, une violation de contrainte remontant un message que
  /// personne ne rattache au couple concerne. Meme partage des roles que
  /// `ModeleNotificationService::creerModele()`.
  @override
  List<Set<Column>> get uniqueKeys => [
    {evenement, canal},
  ];
}

/// Un message COMPOSE — file d'attente ou journal, selon [statut].
///
/// ## Il est COMPOSE avec de vraies donnees, et il ne part pas
///
/// C'est precisement la valeur du module tant qu'aucun canal n'est contracte :
/// relire le texte exact qu'un client lira, avec son vrai nom et son vrai
/// montant, pendant que la correction est encore gratuite. Le manuel le dit au
/// chapitre 12 : « Les messages sont composes, mis en file et consultables —
/// mais le client n'a rien recu. »
///
/// ## `statut` est un registre ferme de QUATRE valeurs
///
/// Les trois premieres sont atteignables sur ce poste : `en_attente` a la
/// composition, `traite_manuellement` et `abandonne` par un geste de l'ecran.
/// La quatrieme, `envoye`, n'est atteignable par AUCUN geste de l'ecran : seul
/// l'accusé du relais SMTP l'ecrit (canal e-mail, depuis le 26/10/2026, par
/// `NotificationsDao.marquerEnvoyeParLeSysteme`, appele par
/// `ServiceBoiteEnvoiEmails` — un test enumere les gestes). Elle est conservee parce qu'elle existe au registre
/// du serveur et parce que le compteur « Reellement envoyes » se derive d'elle :
/// la retirer forcerait a poser un `0` en dur, soit exactement PA-61.
class MessagesNotificationLocal extends Table {
  TextColumn get id => text()();

  TextColumn get modeleId => text().references(ModelesNotificationLocal, #id)();

  /// Le canal, **copie** du modele au moment de la composition.
  ///
  /// Redondant avec le modele, et volontairement : un message compose lundi
  /// doit rester lisible tel qu'il a ete compose, meme si le modele a change de
  /// canal depuis. Meme raisonnement que le libelle fige d'une ligne de panier.
  TextColumn get canal => text()();

  /// L'occurrence d'origine — « ce sejour-la », « ce contrat-la ».
  ///
  /// C'est la moitie de la cle d'idempotence : deux detections successives sur
  /// la meme occurrence ne composent qu'un message.
  TextColumn get reference => text()();

  /// Le nom AFFICHE du destinataire. Ce n'est pas une adresse.
  ///
  /// Aucune colonne d'adresse n'existe ici, et c'est delibere : sur un poste
  /// sans transport, une adresse collectee ne servirait a rien et donnerait a
  /// l'ecran l'apparence d'un envoi possible.
  TextColumn get destinataire => text()();

  TextColumn get objet => text().nullable()();

  /// Le texte REEL, variables substituees. Un message dont une variable
  /// resterait litterale n'est jamais mis en file — un client ne doit jamais
  /// lire une accolade.
  TextColumn get contenu => text()();

  IntColumn get longueur => integer()();

  /// `en_attente` | `traite_manuellement` | `abandonne` | `envoye`.
  TextColumn get statut => text().withDefault(const Constant('en_attente'))();

  /// Comment le message a ete transmis HORS du systeme — saisi a la main.
  TextColumn get commentaire => text().nullable()();

  /// Obligatoire a l'abandon : un message qui ne partira jamais doit dire
  /// pourquoi.
  TextColumn get motifAbandon => text().nullable()();

  /// Le login de qui a transmis ou abandonne.
  ///
  /// Un compte desactive n'est jamais supprime (RG-15) : la trace doit
  /// continuer de porter le nom de qui a fait le geste.
  TextColumn get traitePar => text().nullable()();

  DateTimeColumn get composeLe => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get traiteLe => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  /// L'idempotence de « Detecter maintenant », posee au SCHEMA.
  ///
  /// Deux clics, deux ouvertures de l'ecran, une detection relancee le
  /// lendemain : aucune ne peut dupliquer le message d'une occurrence deja
  /// composee. Sans elle, la file se remplirait de doublons a chaque geste, et
  /// le Gerant relancerait deux fois le meme client.
  @override
  List<Set<Column>> get uniqueKeys => [
    {modeleId, reference},
  ];
}
