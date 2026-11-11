/// Les quatre canaux de diffusion — REGISTRE FERMÉ, et aucun n'est branché.
///
/// Maître : `pwa/notifications/hub.blade.php`, onglet Canaux, et le registre
/// serveur `App\Domain\Notifications\Services\RegistreCanaux`. Les libellés et
/// les motifs de blocage sont ceux de `lang/fr/notifications_pwa.php`, mot pour
/// mot, apostrophe typographique du maître comprise (voir la note
/// d'apostrophe de `declencheur_notification.dart`).
///
/// ## Pourquoi un registre plutôt qu'une table
///
/// Un canal n'est pas une donnée de gestion : c'est une capacité technique du
/// produit. Une table le rendrait créable depuis l'écran, et quelqu'un pourrait
/// poser « Fax » sans que rien ne sache l'emprunter.
///
/// ## `branché` se DÉRIVE, il ne se pose pas
///
/// C'est la leçon exacte du badge MECeF (PA-61) : un drapeau posé à la main
/// serait passé au vert le jour de l'inscription DGI pendant que chaque facture
/// partait encore en démonstration. Ici, l'état d'un canal se dérive de
/// [TransportsLocaux] — l'existence RÉELLE d'un client qui porte le canal.
///
/// Sur ce poste, ce jeu est **vide par construction** : l'application est hors
/// ligne, aucun transport n'y est monté, et il n'existe aucun code qui en
/// ajoute un. Ce n'est pas la même chose qu'un `false` écrit en dur — le jour
/// où un transport sera branché, l'écran suivra sans qu'on le touche.
library;

enum CanalNotification {
  whatsapp(
    'whatsapp',
    'WhatsApp',
    'API WhatsApp Business non contractée — contrat commercial et numéro '
        'vérifié requis.',
    4096,
    'telephone',
  ),
  email('email', 'E-mail', 'Aucun relais SMTP réel configuré.', null, 'email'),
  android(
    'android',
    'Android (push)',
    'L’application Flutter n’est pas démarrée : aucun appareil n’est '
        'enregistré.',
    240,
    'appareil',
  ),
  sms('sms', 'SMS', 'Aucun agrégateur SMS retenu.', 160, 'telephone');

  const CanalNotification(
    this.code,
    this.libelle,
    this.blocage,
    this.limite,
    this.cible,
  );

  final String code;
  final String libelle;

  /// Ce qui empêche ce canal de partir. Affiché tel quel à l'onglet Canaux :
  /// c'est lui qui dit que la levée est un contrat ou une décision, pas un
  /// développement.
  final String blocage;

  /// Le nombre de caractères au-delà duquel le canal découpe ou refuse le
  /// message. `null` pour l'e-mail : il n'en impose aucune.
  final int? limite;

  /// Ce que le canal attend comme destinataire.
  final String cible;

  static CanalNotification? parCode(String? code) {
    for (final c in values) {
      if (c.code == code) return c;
    }
    return null;
  }

  static List<String> get codes =>
      values.map((c) => c.code).toList(growable: false);
}

/// Les transports RÉELLEMENT montés sur ce poste.
///
/// Depuis le 26/10/2026 (l'envoi réel d'e-mails, décision du PO), l'e-mail est
/// monté quand la configuration SMTP du poste est COMPLÈTE
/// (`transportsLocauxProvider`, dérivé de la configuration relue) ; WhatsApp,
/// Android et SMS n'ont aucun client dans ce dépôt. Sans configuration, le jeu
/// est vide. La
/// classe existe pour que l'état d'un canal reste une DÉRIVATION — si un
/// transport était monté demain, [estBranche] le dirait sans qu'aucun écran ne
/// change.
///
/// Ne jamais remplacer un appel à [estBranche] par `false` : ce serait
/// exactement le drapeau posé à la main que PA-61 a corrigé.
final class TransportsLocaux {
  const TransportsLocaux(this._montes);

  /// L'état de ce poste : aucun transport.
  const TransportsLocaux.aucun() : _montes = const <CanalNotification>{};

  final Set<CanalNotification> _montes;

  bool estBranche(CanalNotification canal) => _montes.contains(canal);

  /// Se COMPTE, jamais ne s'écrit. Un « 0 » posé à la main serait juste
  /// aujourd'hui et faux le jour du premier branchement, sans que personne ne
  /// rouvre la question.
  int get nombreBranches => _montes.length;

  /// L'étiquette affichée à la place d'un geste d'envoi, pour TOUT canal.
  ///
  /// Le maître distingue l'e-mail des trois autres parce que SON serveur peut
  /// avoir un relais SMTP. Ce poste-ci ne le peut pas : il n'a pas de réseau.
  /// La ligne porte donc partout l'étiquette du maître plutôt qu'un bouton dont
  /// on saurait d'avance qu'il échoue — un bouton qui échoue toujours est la
  /// version cliquable de l'entrée inerte que l'Article 3.3 refuse.
  static const String etiquetteSansTransport = 'à paramétrer au déploiement';

  /// La raison affichée à la place du bouton « Envoyer » d'un message du canal
  /// e-mail (`lang/fr/notifications_pwa.php`, `file_sans_configuration`).
  ///
  /// La vue (`hub.blade.php` l.278-286) distingue deux raisons : l'adresse du
  /// destinataire inconnue, puis le relais absent. Seule la seconde est
  /// VÉRIFIABLE ici (09/10/2026) : une notification locale ne porte aucune
  /// adresse e-mail, donc « Aucune adresse e-mail connue » affirmerait un état
  /// que ce poste n'a pas lu. Le relais, lui, se dérive de [estBranche].
  static const String etiquetteSansRelais = 'Aucun relais SMTP réel configuré';
}

/// Les phrases de « Envoyer » / « Renvoyer » (e-mail) — celles de la vue
/// (`lang/fr/notifications_pwa.php`), au mot.
abstract final class TextesEnvoiNotification {
  static const String envoyer = 'Envoyer';
  static const String renvoyer = 'Renvoyer';
  static const String envoiReussi = 'Message envoyé par e-mail.';
  static const String sansAdresse =
      'Aucune adresse e-mail connue pour ce destinataire — à transmettre à la main.';
  static const String sansRelais =
      'Aucun relais SMTP réel n’est configuré — à transmettre à la main.';
  static const String dejaEnCours = 'Ce message est déjà en cours d’envoi.';
  static const String relancesEpuisees = 'Relances automatiques épuisées';

  static String tentatives(int n) => 'Tentatives d’envoi : $n';
  static String derniereErreur(String erreur) => 'Dernière erreur : $erreur';
}
