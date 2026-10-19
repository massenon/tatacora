/// Les providers de M12 — Riverpod, déclarés à la main.
///
/// ## Tout vient de la base LOCALE
///
/// Aucun client HTTP n'apparaît dans ce fichier, et c'est la garantie la plus
/// simple à vérifier : ce module ne peut pas appeler le serveur, même par
/// erreur, même plus tard. Ce n'est pas une précaution de style — c'est ce qui
/// rend vraie la phrase que l'écran affiche au Gérant.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/fichiers/enregistrement_export.dart';
import '../../../core/impression/export_etat_a4.dart';
import '../../hebergement/presentation/providers_hebergement.dart';
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

/// Les transports RÉELLEMENT montés sur ce poste : aucun.
///
/// Exposé comme provider plutôt qu'écrit en dur dans l'écran : le jour où un
/// transport existera, il se déclarera ici, et les quatre endroits qui lisent
/// l'état d'un canal suivront sans être touchés.
final transportsLocauxProvider = Provider<TransportsLocaux>(
  (ref) => const TransportsLocaux.aucun(),
);

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
    return ref
        .read(notificationsDaoProvider)
        .detecter(reservations: reservations, aujourdHui: DateTime.now());
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
