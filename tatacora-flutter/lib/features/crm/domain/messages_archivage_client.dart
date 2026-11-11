// Vue Blade maîtresse (PA-183) : pwa/crm/clients-creances.blade.php
/// Les phrases de l'archivage d'un client — celles du SERVEUR
/// (`lang/fr/crm.php`, clé `archivage`), confrontées à son code par
/// `messages_archivage_client_test.dart` (PHP exécuté).
///
/// Les quatre VERROUS sont les raisons de refuser : un séjour en cours ou à
/// venir, une location de véhicule non terminée, une réservation de circuit à
/// venir, une facture non soldée (`ReferentielClientService::verrous`).
library;

abstract final class MessagesArchivageClient {
  /// `crm.archivage.verrou_sejour`.
  static String verrouSejour(int nombre) =>
      'Il a $nombre séjour(s) en cours ou à venir : la réception a besoin de '
      "ce client au sélecteur jusqu'au départ.";

  /// `crm.archivage.verrou_location`.
  static String verrouLocation(int nombre) =>
      'Il a $nombre location(s) de véhicule non terminée(s).';

  /// `crm.archivage.verrou_circuit`.
  static String verrouCircuit(int nombre) =>
      'Il a $nombre réservation(s) de circuit à venir.';

  /// `crm.archivage.verrou_creance`.
  static String verrouCreance(int nombre) =>
      'Il porte $nombre facture(s) non soldée(s) : '
      "l'archiver le retirerait de l'écran où l'on décide de le relancer.";

  /// `crm.archivage.succes` : `{1}` un client, `[2,*]` plusieurs.
  static String succes(int nombre) => nombre == 1
      ? 'Client archivé — il reste restaurable.'
      : '$nombre clients archivés — ils restent restaurables.';

  /// `crm.archivage.restaure`.
  static String restaure(String nom) => 'Client « $nom » restauré.';

  /// Le client n'existe pas (ou plus) sur ce poste.
  static const String introuvable =
      "Ce client n'existe pas dans le référentiel.";
}
