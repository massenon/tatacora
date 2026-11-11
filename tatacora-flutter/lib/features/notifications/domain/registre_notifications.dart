/// Ce que l'écran M12 affiche : onglets, indicateurs, filtres, groupes — et la
/// DÉTECTION, qui compose de vrais messages à partir des données du poste.
///
/// Tout est **pur** ici : aucune base, aucun widget. C'est ce qui rend la
/// détection éprouvable sans monter d'écran, et c'est aussi ce qui empêche une
/// seconde formule de naître dans un panneau.
library;

import '../../../core/format/formats.dart';
import '../../hebergement/domain/entities/reservation.dart';
import 'entities/canal_notification.dart';
import 'entities/declencheur_notification.dart';
import 'entities/message_notification.dart';
import 'entities/modele_notification.dart';

/// Les cinq onglets du maître, dans son ordre.
enum OngletNotifications {
  file('File d’attente'),
  modeles('Modèles'),
  declencheurs('Déclencheurs'),
  journal('Journal'),
  canaux('Canaux');

  const OngletNotifications(this.libelle);

  final String libelle;
}

/// Le filtre d'état des modèles — les libellés du maître.
///
/// ⚠ Le maître distingue le PLURIEL du SINGULIER : une option de filtre désigne
/// un ENSEMBLE (« Actifs », « Désactivés »), une pastille qualifie UN modèle
/// (« actif », « désactivé »). Les deux vocabulaires coexistent et ne se
/// factorisent pas.
enum EtatModeleFiltre {
  tous('Tous les états'),
  actif('Actifs'),
  inactif('Désactivés');

  const EtatModeleFiltre(this.libelle);

  final String libelle;
}

/// Les six indicateurs du maître — tous COMPTÉS, aucun posé.
final class KpisNotifications {
  const KpisNotifications({
    required this.enAttente,
    required this.envoyesReels,
    required this.transmis,
    required this.abandonnes,
    required this.modelesActifs,
    required this.modelesTotal,
    required this.canauxBranches,
    required this.canauxTotal,
  });

  /// Comptés sur les listes réellement chargées, jamais par une seconde requête.
  factory KpisNotifications.calculer({
    required List<MessageNotification> messages,
    required List<ModeleNotification> modeles,
    required TransportsLocaux transports,
  }) {
    var enAttente = 0;
    var envoyes = 0;
    var transmis = 0;
    var abandonnes = 0;

    for (final m in messages) {
      switch (m.statut) {
        case StatutMessageNotification.enAttente:
          enAttente++;
        case StatutMessageNotification.envoyeParLeSysteme:
          envoyes++;
        case StatutMessageNotification.transmisALaMain:
          transmis++;
        case StatutMessageNotification.abandonne:
          abandonnes++;
      }
    }

    return KpisNotifications(
      enAttente: enAttente,
      envoyesReels: envoyes,
      transmis: transmis,
      abandonnes: abandonnes,
      modelesActifs: modeles.where((m) => m.actif).length,
      modelesTotal: modeles.length,
      canauxBranches: transports.nombreBranches,
      canauxTotal: CanalNotification.values.length,
    );
  }

  final int enAttente;

  /// Se DÉRIVE du statut des messages, sur la table réelle.
  ///
  /// Il vaut zéro parce qu'aucun geste de ce poste ne peut produire le statut
  /// « envoyé », pas parce qu'une constante le dit (PA-61).
  final int envoyesReels;

  final int transmis;
  final int abandonnes;
  final int modelesActifs;
  final int modelesTotal;
  final int canauxBranches;
  final int canauxTotal;

  int get nombreDeclencheurs => DeclencheurNotification.values.length;
}

/// Le comptage des modèles rattachés à un déclencheur.
final class ComptageModeles {
  const ComptageModeles({required this.total, required this.actifs});

  final int total;
  final int actifs;
}

ComptageModeles comptageParDeclencheur(
  List<ModeleNotification> modeles,
  DeclencheurNotification declencheur,
) {
  final duDeclencheur = modeles.where(
    (m) => m.evenementCode == declencheur.code,
  );
  return ComptageModeles(
    total: duDeclencheur.length,
    actifs: duDeclencheur.where((m) => m.actif).length,
  );
}

/// Un groupe de la file — le maître lit sa file par déclencheur, « c'est ainsi
/// qu'on relit une campagne, pas message par message ».
final class GroupeFile {
  const GroupeFile({
    required this.code,
    required this.declencheur,
    required this.messages,
  });

  final String code;

  /// `null` si le message porte un événement hors registre : le groupe s'affiche
  /// alors sous son code brut, sans libellé fabriqué.
  final DeclencheurNotification? declencheur;

  final List<MessageNotification> messages;
}

/// Regroupe en conservant l'ordre d'apparition — donc l'ordre de tri de la file.
List<GroupeFile> grouperParDeclencheur(List<MessageNotification> messages) {
  final ordre = <String>[];
  final parCode = <String, List<MessageNotification>>{};
  final declencheurs = <String, DeclencheurNotification?>{};

  for (final m in messages) {
    final code = m.declencheur?.code ?? '';
    if (!parCode.containsKey(code)) {
      ordre.add(code);
      parCode[code] = <MessageNotification>[];
      declencheurs[code] = m.declencheur;
    }
    parCode[code]!.add(m);
  }

  return [
    for (final code in ordre)
      GroupeFile(
        code: code,
        declencheur: declencheurs[code],
        messages: parCode[code]!,
      ),
  ];
}

/// La file telle que l'écran l'affiche — c'est elle que l'export emporte
/// (PA-119).
List<MessageNotification> filtrerFile(
  List<MessageNotification> messages, {
  String terme = '',
  CanalNotification? canal,
  PublicNotification? public,
}) {
  final recherche = terme.trim().toLowerCase();

  return messages
      .where((m) {
        if (canal != null && m.canal != canal) return false;
        if (public != null && m.declencheur?.public != public) return false;
        if (recherche.isEmpty) return true;

        final champs = [
          m.destinataire,
          m.contenu,
          m.objet ?? '',
          m.declencheur?.libelle ?? '',
          m.declencheur?.code ?? '',
        ].join(' ').toLowerCase();

        return champs.contains(recherche);
      })
      .toList(growable: false);
}

/// Les modèles tels que l'écran les affiche.
List<ModeleNotification> filtrerModeles(
  List<ModeleNotification> modeles, {
  String terme = '',
  CanalNotification? canal,
  PublicNotification? public,
  EtatModeleFiltre etat = EtatModeleFiltre.tous,
}) {
  final recherche = terme.trim().toLowerCase();

  return modeles
      .where((m) {
        if (canal != null && m.canal != canal) return false;
        if (public != null && m.declencheur?.public != public) return false;
        if (etat == EtatModeleFiltre.actif && !m.actif) return false;
        if (etat == EtatModeleFiltre.inactif && m.actif) return false;
        if (recherche.isEmpty) return true;

        final champs = [
          m.evenementCode,
          m.declencheur?.libelle ?? '',
          m.contenuTemplate,
          m.objet ?? '',
        ].join(' ').toLowerCase();

        return champs.contains(recherche);
      })
      .toList(growable: false);
}

/// Les déclencheurs tels que l'onglet les affiche.
List<DeclencheurNotification> filtrerDeclencheurs({
  String terme = '',
  PublicNotification? public,
}) {
  final recherche = terme.trim().toLowerCase();

  return DeclencheurNotification.values
      .where((d) {
        if (public != null && d.public != public) return false;
        if (recherche.isEmpty) return true;

        return '${d.libelle} ${d.description} ${d.code}'.toLowerCase().contains(
          recherche,
        );
      })
      .toList(growable: false);
}

/// Le décompte des messages EN FILE par canal — la colonne « En file » du
/// maître, mesurée sur la file déjà chargée.
///
/// Zéro s'écrit « 0 » : c'est une mesure de la file, pas un état affirmé sans
/// vérification.
Map<CanalNotification, int> enFileParCanal(List<MessageNotification> messages) {
  final compte = <CanalNotification, int>{};
  for (final m in messages) {
    if (!m.estEnAttente) continue;
    final canal = m.canal;
    if (canal == null) continue;
    compte[canal] = (compte[canal] ?? 0) + 1;
  }
  return compte;
}

/* ======================================================================== */
/* DÉTECTION — de vraies données du poste, jamais un jeu de démonstration    */
/* ======================================================================== */

/// Une occurrence réelle à notifier.
final class OccurrenceDetectee {
  const OccurrenceDetectee({
    required this.reference,
    required this.destinataire,
    required this.variables,
    this.adresseEmail,
  });

  /// L'identité STABLE de l'occurrence — « ce séjour-là ».
  ///
  /// C'est la moitié de la clé d'idempotence `(modele, reference)` : elle ne
  /// doit dépendre d'aucune date d'exécution, sans quoi relancer la détection
  /// le lendemain recomposerait le même message.
  final String reference;

  final String destinataire;
  final Map<String, String> variables;

  /// L'adresse e-mail RÉELLE du client, quand elle est connue — jamais le nom
  /// d'affichage ([destinataire]). `null` : aucune adresse lue, l'e-mail ne
  /// peut pas partir (le message reste à transmettre à la main).
  final String? adresseEmail;
}

/// Les occurrences du jour pour ce déclencheur.
///
/// ## Deux déclencheurs sur neuf, et le `switch` le dit lui-même
///
/// Les sept autres rendent une liste vide **et portent leur raison** dans
/// [DeclencheurNotification.motifNonDetecte], affichée à l'écran. Rendre une
/// liste vide sans le dire ferait lire « aucune occurrence aujourd'hui » là où
/// il faut lire « ce poste ne sait pas regarder ».
///
/// ⚠ Ce fichier importe l'entité `Reservation` de M1. C'est la seule dépendance
/// croisée du module, et elle est **documentée par le registre lui-même** :
/// chaque déclencheur nomme son module d'origine, et les deux qui sont détectés
/// ici portent `M1`. Les variables monétaires reprennent
/// `Reservation.resteAPayer` — jamais une seconde formule : celle-ci tient
/// compte de la remise depuis PA-111, et une copie divergerait au premier
/// changement.
List<OccurrenceDetectee> detecterOccurrences({
  required DeclencheurNotification declencheur,
  required List<Reservation> reservations,
  required DateTime aujourdHui,
  Map<String, String> emailsClients = const {},
}) {
  final demain = aujourdHui.add(const Duration(days: 1));

  switch (declencheur) {
    case DeclencheurNotification.sejourDemain:
      return [
        for (final r in reservations)
          if (r.estActive && _memeJour(r.periode.arrivee, demain))
            OccurrenceDetectee(
              reference: '${declencheur.code}:${r.id}',
              destinataire: r.clientNom,
              adresseEmail: emailsClients[r.clientId],
              variables: {
                'client': r.clientNom,
                'date_arrivee': formaterDate(r.periode.arrivee),
                'date_depart': formaterDate(r.periode.depart),
                'nuits': '${r.nuits}',
              },
            ),
      ];

    case DeclencheurNotification.sejourDepart:
      return [
        for (final r in reservations)
          if (r.estActive && _memeJour(r.periode.depart, aujourdHui))
            OccurrenceDetectee(
              reference: '${declencheur.code}:${r.id}',
              destinataire: r.clientNom,
              adresseEmail: emailsClients[r.clientId],
              variables: {
                'client': r.clientNom,
                'date_depart': formaterDate(r.periode.depart),
                'reste_du': formaterFcfa(r.resteAPayer),
              },
            ),
      ];

    // Les sept déclencheurs que ce poste ne sait pas regarder. Chacun porte sa
    // raison, datée, dans `motifNonDetecte` — et l'écran l'affiche.
    case DeclencheurNotification.creanceEchue:
    case DeclencheurNotification.creanceDouteuse:
    case DeclencheurNotification.stockSousSeuil:
    case DeclencheurNotification.departCircuitDemain:
    case DeclencheurNotification.restitutionVehicule:
    case DeclencheurNotification.bulletinDisponible:
    case DeclencheurNotification.echeanceVps:
      return const [];
  }
}

bool _memeJour(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
