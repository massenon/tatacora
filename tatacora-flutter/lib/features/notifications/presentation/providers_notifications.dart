/// Les providers de M12 — Riverpod, déclarés à la main.
///
/// ## Tout vient de la base LOCALE
///
/// Aucun client HTTP n'apparaît dans ce fichier, et c'est la garantie la plus
/// simple à vérifier : ce module ne peut pas appeler le serveur, même par
/// erreur, même plus tard. Ce n'est pas une précaution de style — c'est ce qui
/// rend vraie la phrase que l'écran affiche au Gérant.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/fichiers/enregistrement_export.dart';
import '../../../core/impression/export_etat_a4.dart';
import '../../hebergement/presentation/providers_hebergement.dart';
import '../../transverse/data/boite_envoi_emails_dao.dart';
import '../../transverse/data/envoi_boite_emails.dart';
import '../../transverse/data/envoi_messages_editeur.dart'
    show ConfigurationSmtp;
import '../../transverse/domain/boite_envoi_emails.dart';
import '../../transverse/presentation/providers_contact_editeur.dart';
import '../data/notifications_dao.dart';
import '../domain/entities/canal_notification.dart';
import '../domain/entities/declencheur_notification.dart';
import '../domain/entities/message_notification.dart';
import '../domain/entities/modele_notification.dart';
import '../domain/registre_notifications.dart';
import '../impression/etat_notifications.dart';

final notificationsDaoProvider = Provider<NotificationsDao>(
  (ref) => NotificationsDao(ref.watch(baseLocaleProvider)),
);

/// Le seul écrivain de `boite_envoi_emails_local` (schéma v39).
final boiteEnvoiEmailsDaoProvider = Provider<BoiteEnvoiEmailsDao>(
  (ref) => BoiteEnvoiEmailsDao(ref.watch(baseLocaleProvider)),
);

/// L'unique expéditeur des e-mails de notification — UNE instance pour le
/// geste de l'écran et la relance : c'est elle qui empêche un double envoi.
/// Le message de notification passe « Envoyé par le système » dans la MÊME
/// transaction que la boîte, après l'accusé du relais SMTP.
final serviceBoiteEnvoiEmailsProvider = Provider<ServiceBoiteEnvoiEmails>((
  ref,
) {
  final notifications = ref.watch(notificationsDaoProvider);
  return ServiceBoiteEnvoiEmails(
    dao: ref.watch(boiteEnvoiEmailsDaoProvider),
    lecteur: ref.watch(serviceMessagesEditeurProvider).lecteurSmtp,
    auSucces: (email, envoyeLe) async {
      final messageId = email.sourceId;
      if (email.source == SourceEmail.notification && messageId != null) {
        await notifications.marquerEnvoyeParLeSysteme(
          messageId,
          envoyeLe: envoyeLe,
        );
      }
    },
  );
});

/// Un compteur qui avance à chaque écriture de la boîte (geste, relance) : la
/// file et les états se relisent.
final revisionBoiteEmailsProvider = NotifierProvider<_RevisionBoiteEmails, int>(
  _RevisionBoiteEmails.new,
);

final class _RevisionBoiteEmails extends Notifier<int> {
  @override
  int build() => 0;

  void avancer() => state++;
}

/// L'e-mail en boîte de chaque message de notification, par identifiant du
/// message — l'état VRAI de l'envoi (tentatives, cause, statut).
final emailsDesMessagesProvider =
    FutureProvider.autoDispose<Map<String, EmailEnBoite>>((ref) {
      ref.watch(revisionBoiteEmailsProvider);
      return ref
          .watch(boiteEnvoiEmailsDaoProvider)
          .parSources(SourceEmail.notification);
    });

/// La configuration SMTP de ce poste est-elle COMPLÈTE (serveur, utilisateur,
/// mot de passe) ? Relue du poste (paramètres + `poste.json`) — jamais posée.
final smtpCompletProvider = FutureProvider.autoDispose<bool>((ref) async {
  ref.watch(revisionBoiteEmailsProvider);
  final lecture = await ref
      .watch(serviceMessagesEditeurProvider)
      .lecteurSmtp
      .lire();
  return lecture is ConfigurationSmtp;
});

/// Les transports RÉELLEMENT montés sur ce poste : l'e-mail, et lui seul,
/// quand la configuration SMTP est complète.
///
/// DÉRIVÉ de la configuration relue (`smtpCompletProvider`), jamais écrit :
/// WhatsApp, Android et SMS n'ont aucun client dans ce dépôt. Tant que la
/// lecture n'est pas revenue, aucun transport n'est affirmé.
final transportsLocauxProvider = Provider<TransportsLocaux>((ref) {
  final complet = ref.watch(smtpCompletProvider).value ?? false;
  return complet
      ? const TransportsLocaux({CanalNotification.email})
      : const TransportsLocaux.aucun();
});

/// La RELANCE des e-mails de notification en attente : une première fois au
/// démarrage du poste, puis toutes les `PolitiqueRelanceEmail.periode` tant que
/// l'application tourne. Démarrée par `main.dart` (PAS par `main_demo.dart`).
///
/// Aucune sonde de connectivité : la tentative est l'autorité. L'interrupteur
/// « Synchronisation activée » ne la coupe pas : l'e-mail n'est pas de la
/// synchronisation, il part directement au relais SMTP.
final relanceBoiteEmailsProvider = Provider<void>((ref) {
  final service = ref.watch(serviceBoiteEnvoiEmailsProvider);

  Future<void> relancer() async {
    try {
      final bilan = await service.relancer();
      if (bilan != null && (bilan.envoyes > 0 || bilan.restants > 0)) {
        ref.read(revisionBoiteEmailsProvider.notifier).avancer();
      }
    } on Object {
      // Une base fermée pendant l'arrêt, par exemple : la relance suivante
      // recommencera. Rien ne doit remonter jusqu'à l'interface.
    }
  }

  unawaited(relancer());
  final minuteur = Timer.periodic(
    PolitiqueRelanceEmail.periode,
    (_) => unawaited(relancer()),
  );
  ref.onDispose(minuteur.cancel);
});

/* ============================================================== filtres */

final ongletNotificationsProvider =
    NotifierProvider<_OngletNotifier, OngletNotifications>(_OngletNotifier.new);

final class _OngletNotifier extends Notifier<OngletNotifications> {
  @override
  OngletNotifications build() => OngletNotifications.file;

  void definir(OngletNotifications onglet) => state = onglet;
}

/// L'état de la bande d'indicateurs : dépliée à l'ouverture, comme la vue
/// (`hub.blade.php` l.140, `localStorage.getItem('pwa_kpis_m12') !== 'false'`).
///
/// ⚠ La vue retient cet état d'une session à l'autre ; ce poste ne le fait pas
/// (09/10/2026) : aucun magasin de préférences n'est embarqué, et la bande se
/// rouvre à chaque lancement. Écart assumé, pas oublié.
final kpisNotificationsDepliesProvider =
    NotifierProvider<_KpisDepliesNotifier, bool>(_KpisDepliesNotifier.new);

final class _KpisDepliesNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void basculer() => state = !state;
}

final rechercheNotificationsProvider =
    NotifierProvider<_RechercheNotifier, String>(_RechercheNotifier.new);

final class _RechercheNotifier extends Notifier<String> {
  @override
  String build() => '';

  void definir(String terme) => state = terme;
}

final canalFiltreProvider =
    NotifierProvider<_CanalNotifier, CanalNotification?>(_CanalNotifier.new);

final class _CanalNotifier extends Notifier<CanalNotification?> {
  @override
  CanalNotification? build() => null;

  void definir(CanalNotification? canal) => state = canal;
}

final publicFiltreProvider =
    NotifierProvider<_PublicNotifier, PublicNotification?>(_PublicNotifier.new);

final class _PublicNotifier extends Notifier<PublicNotification?> {
  @override
  PublicNotification? build() => null;

  void definir(PublicNotification? public) => state = public;
}

final etatModeleFiltreProvider =
    NotifierProvider<_EtatNotifier, EtatModeleFiltre>(_EtatNotifier.new);

final class _EtatNotifier extends Notifier<EtatModeleFiltre> {
  @override
  EtatModeleFiltre build() => EtatModeleFiltre.tous;

  void definir(EtatModeleFiltre etat) => state = etat;
}

/* ================================================================ vue */

/// Tout ce que l'écran affiche, chargé EN UNE FOIS.
///
/// Un provider par panneau aurait relu la base cinq fois par rendu, et surtout
/// les six indicateurs auraient pu être calculés sur un instantané différent de
/// celui des listes — deux vérités sur le même écran.
final class VueNotifications {
  const VueNotifications({
    required this.file,
    required this.groupes,
    required this.journal,
    required this.modeles,
    required this.declencheurs,
    required this.kpis,
    required this.enFile,
    required this.tousModeles,
  });

  /// La file, FILTRÉE — c'est elle que l'export emporte (PA-119).
  final List<MessageNotification> file;

  /// La même file, groupée par déclencheur.
  final List<GroupeFile> groupes;

  final List<MessageNotification> journal;
  final List<ModeleNotification> modeles;
  final List<DeclencheurNotification> declencheurs;

  /// Les six indicateurs, calculés sur TOUT — jamais sur la vue filtrée : le
  /// maître les veut globaux, et un compteur qui suivrait le filtre dirait
  /// « 0 en file » à qui a simplement tapé un nom dans la recherche.
  final KpisNotifications kpis;

  /// Le décompte par canal, mesuré sur la file RÉELLE, non filtrée.
  final Map<CanalNotification, int> enFile;

  /// Tous les modèles — pour le comptage par déclencheur de l'onglet éponyme,
  /// qui compte les modèles rattachés, pas les modèles affichés.
  final List<ModeleNotification> tousModeles;
}

final vueNotificationsProvider = FutureProvider<VueNotifications>((ref) async {
  final dao = ref.watch(notificationsDaoProvider);
  final transports = ref.watch(transportsLocauxProvider);

  final tousModeles = await dao.modeles();
  final tousMessages = await dao.messages();

  final terme = ref.watch(rechercheNotificationsProvider);
  final canal = ref.watch(canalFiltreProvider);
  final public = ref.watch(publicFiltreProvider);
  final etat = ref.watch(etatModeleFiltreProvider);

  final fileBrute = tousMessages.where((m) => m.estEnAttente).toList();
  final fileFiltree = filtrerFile(
    fileBrute,
    terme: terme,
    canal: canal,
    public: public,
  );

  final journalBrut = tousMessages.where((m) => m.estAuJournal).toList()
    ..sort((a, b) {
      final da = a.traiteLe ?? a.composeLe;
      final db = b.traiteLe ?? b.composeLe;
      return db.compareTo(da);
    });

  return VueNotifications(
    file: fileFiltree,
    groupes: grouperParDeclencheur(fileFiltree),
    journal: filtrerFile(
      journalBrut,
      terme: terme,
      canal: canal,
      public: public,
    ),
    modeles: filtrerModeles(
      tousModeles,
      terme: terme,
      canal: canal,
      public: public,
      etat: etat,
    ),
    declencheurs: filtrerDeclencheurs(terme: terme, public: public),
    kpis: KpisNotifications.calculer(
      messages: tousMessages,
      modeles: tousModeles,
      transports: transports,
    ),
    enFile: enFileParCanal(fileBrute),
    tousModeles: tousModeles,
  );
});

/* ============================================================== gestes */

/// Le login de qui fait le geste — `null` si aucune session n'est ouverte.
///
/// Il n'est PAS remplacé par un libellé de repli : RG-15 veut que la trace
/// porte le nom de qui a agi, et « compte inconnu » écrit en base serait une
/// identité inventée. L'écran refuse le geste plutôt que de le tracer au nom de
/// personne.
final auteurGesteProvider = Provider<String?>(
  (ref) => ref.watch(sessionProvider)?.login,
);

/// « Détecter maintenant » — compose les messages du jour à partir des
/// RÉSERVATIONS RÉELLES du poste. N'envoie rien.
///
/// Les réservations viennent du dépôt de M1, jamais d'une requête écrite ici :
/// c'est lui qui porte la formule du reste à payer, remise comprise (PA-111).
final detecterMaintenantProvider = Provider<Future<BilanDetection> Function()>(
  (ref) => () async {
    final reservations = await ref
        .read(depotReservationProvider)
        .reservations();
    final dao = ref.read(notificationsDaoProvider);
    final bilan = await dao.detecter(
      reservations: reservations,
      aujourdHui: DateTime.now(),
      emailsClients: await dao.emailsDesClients(),
    );
    ref.read(revisionBoiteEmailsProvider.notifier).avancer();
    // Les e-mails mis en boîte partent tout de suite si le relais répond ; un
    // échec est noté et la relance le reprendra. Jamais attendu par l'écran.
    unawaited(
      ref
          .read(serviceBoiteEnvoiEmailsProvider)
          .relancer()
          .then((_) => ref.read(revisionBoiteEmailsProvider.notifier).avancer())
          .catchError((Object _) {}),
    );
    return bilan;
  },
);

/// Ce que « Envoyer » / « Renvoyer » a fait d'un message, avec la phrase que
/// l'écran dit — les mots de la vue (`lang/fr/notifications_pwa.php`).
typedef ResultatGesteEnvoiNotification = ({bool succes, String phrase});

/// « Envoyer » / « Renvoyer » — met le message en boîte (adresse lue au geste),
/// puis le tente aussitôt. JAMAIS « envoyé » avant l'accusé du relais : l'issue
/// est celle du transport.
final envoyerMessageNotificationProvider =
    Provider<Future<ResultatGesteEnvoiNotification> Function(String messageId)>(
      (ref) => (messageId) async {
        final dao = ref.read(notificationsDaoProvider);
        final service = ref.read(serviceBoiteEnvoiEmailsProvider);
        final reservations = await ref
            .read(depotReservationProvider)
            .reservations();
        try {
          final mise = await dao.mettreEnBoite(
            messageId,
            reservations: reservations,
          );
          if (mise.issue == IssueMiseEnBoite.sansAdresse) {
            return (succes: false, phrase: TextesEnvoiNotification.sansAdresse);
          }
          final email = mise.email!;
          final resultat = email.tentatives > 0
              ? await service.renvoyer(email.id)
              : await service.envoyer(email.id);
          return switch (resultat.issue) {
            IssueEnvoiEmail.envoye => (
              succes: true,
              phrase: TextesEnvoiNotification.envoiReussi,
            ),
            IssueEnvoiEmail.dejaEnCours => (
              succes: false,
              phrase: TextesEnvoiNotification.dejaEnCours,
            ),
            IssueEnvoiEmail.nonConfigure || IssueEnvoiEmail.echoue => (
              succes: false,
              phrase: resultat.raison ?? TextesEnvoiNotification.sansRelais,
            ),
          };
        } on RefusNotification catch (refus) {
          return (succes: false, phrase: refus.message);
        } finally {
          ref.read(revisionBoiteEmailsProvider.notifier).avancer();
          ref.invalidate(vueNotificationsProvider);
        }
      },
    );

/// La description du filtre courant — reprise TELLE QUELLE en tête de l'export.
///
/// « L'export porte sur ce qui est affiché, et il dit son filtre » (PA-119).
final descriptionFiltreProvider = Provider<String>((ref) {
  final morceaux = <String>[
    'Onglet : ${ref.watch(ongletNotificationsProvider).libelle}',
  ];

  final canal = ref.watch(canalFiltreProvider);
  if (canal != null) morceaux.add('Canal : ${canal.libelle}');

  final public = ref.watch(publicFiltreProvider);
  if (public != null) morceaux.add('Public : ${public.libelle}');

  final etat = ref.watch(etatModeleFiltreProvider);
  if (etat != EtatModeleFiltre.tous) {
    morceaux.add('État : ${etat.libelle}');
  }

  final terme = ref.watch(rechercheNotificationsProvider).trim();
  if (terme.isNotEmpty) morceaux.add('Recherche : $terme');

  return morceaux.join(' · ');
});

/// L'export tableur — enregistré par la fenêtre « Enregistrer sous »
/// (14/10/2026), rend le CHEMIN du fichier écrit, `null` : annulé.
///
/// Un export silencieux est un export que personne ne retrouve. Il lève
/// [ExportVide] sur une liste vide : une page blanche laisserait croire que le
/// registre est vide alors que c'est le filtre qui l'a vidé.
final exporterNotificationsProvider = Provider<Future<String?> Function()>(
  (ref) => () async {
    final vue = await ref.read(vueNotificationsProvider.future);
    final onglet = ref.read(ongletNotificationsProvider);

    final contenu = EtatNotifications.csvOctets(
      onglet: onglet,
      filtre: ref.read(descriptionFiltreProvider),
      file: vue.file,
      journal: vue.journal,
      modeles: vue.modeles,
      declencheurs: vue.declencheurs,
      transports: ref.read(transportsLocauxProvider),
    );

    return ref
        .read(enregistrementExportProvider)
        .exporter(
          base: 'notifications_${onglet.name}',
          type: TypeFichierEnregistre.csv,
          octets: contenu,
        );
  },
);

/// L'export « PDF Officiel A4 Imprimable » de l'onglet affiché — mêmes
/// colonnes, mêmes lignes, même filtre que le CSV ; en-tête lu des
/// paramètres. Lève [ExportVide] sur une liste vide, comme le tableur.
final exporterNotificationsPdfProvider = Provider<Future<String?> Function()>(
  (ref) => () async {
    final vue = await ref.read(vueNotificationsProvider.future);
    final onglet = ref.read(ongletNotificationsProvider);

    final etat = EtatNotifications.etatA4(
      onglet: onglet,
      filtre: ref.read(descriptionFiltreProvider),
      file: vue.file,
      journal: vue.journal,
      modeles: vue.modeles,
      declencheurs: vue.declencheurs,
      transports: ref.read(transportsLocauxProvider),
    );

    return enregistrerEtatA4(ref, etat, base: 'notifications_${onglet.name}');
  },
);
