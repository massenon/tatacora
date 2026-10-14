/// L'export de l'écran M12 — CSV, et il DIT ce qu'il porte.
///
/// ## Trois règles du dépôt, toutes applicables ici
///
/// 1. **Un export porte sur CE QUI EST AFFICHÉ, et il dit son filtre** (PA-119).
///    Quelqu'un qui filtre puis exporte attend son filtre ; lui rendre le
///    registre entier lui ferait transmettre un document qu'il croit avoir
///    vérifié.
/// 2. **Une liste vide se REFUSE**, elle ne produit pas une page blanche.
/// 3. **« Excel » est rendu en CSV** — BOM UTF-8 et point-virgule, la
///    convention serveur RG-19 et ce qu'attend un Excel en configuration
///    française. Aucune bibliothèque XLSX n'est embarquée ; l'écart est nommé,
///    pas masqué (PA-111).
///
/// ## L'apostrophe : ce fichier en porte DEUX formes, et c'est VOULU
///
/// ⚠ Ne pas « harmoniser ». Les deux formes répondent à deux règles
/// différentes, et les aligner casserait l'une ou l'autre :
///
///  - les libellés qui **traversent** cet export — « File d’attente »,
///    « Article sous le seuil d’alerte », le blocage d'un canal — viennent du
///    fichier de langue du maître et portent son apostrophe typographique
///    (U+2019). Les convertir ici ferait diverger le document de l'écran qu'il
///    est censé reproduire ;
///  - les phrases qui **nous appartiennent** ([mentionAucunEnvoi], les en-têtes
///    de colonne) sont en apostrophe droite.
///
/// **Le CSV supporte les deux sans réserve** : il est écrit en UTF-8 avec BOM,
/// et U+2019 y est rendu exactement. La règle « apostrophe droite » du dépôt ne
/// vise pas l'encodage — elle vise le **PDF**, dont les polices intégrées
/// couvrent Latin-1 et rien de plus : U+2019 y DISPARAÎT du papier sans erreur
/// ni trace. Le dépôt s'est fait prendre une fois, sur « Chiffre d'affaires ».
///
/// ⚠ **Conséquence le jour où un PDF sera ajouté ici** (voir le refus
/// ci-dessous) : il ne pourra PAS imprimer ces libellés tels quels. Il devra
/// les faire passer par la conversion Latin-1 du dépôt (`texteTicket` et sa
/// garde `caracteresNonImprimables`), sans quoi chaque apostrophe du maître
/// s'évaporera du document — silencieusement. Ce n'est pas une question de
/// style : c'est une raison de plus de ne pas produire un PDF à la légère.
///
/// ## Le PDF du maître n'est PAS produit, et voici pourquoi
///
/// La modale d'export du maître offre PDF **et** Excel. Le PDF n'est pas rendu
/// ici : tout document A4 de ce dépôt passe par `core/impression/entete_a4.dart`
/// et doit être **classé au registre** de `test/core/impression/
/// pdf_directive_test.dart`, qui relit les gabarits serveur — un fichier hors du
/// périmètre de ce lot. Produire un A4 sans l'y inscrire ferait échouer cette
/// garde, ou pire, passerait un état non relu. L'absence est déclarée à l'écran.
library;

import 'dart:convert';

import '../domain/entities/canal_notification.dart';
import '../domain/entities/declencheur_notification.dart';
import '../domain/entities/message_notification.dart';
import '../domain/entities/modele_notification.dart';
import '../domain/registre_notifications.dart';

/// Le refus d'exporter une liste vide — le libellé est celui du maître.
final class ExportVide implements Exception {
  const ExportVide();

  static const String message =
      'Aucune ligne à exporter : la liste affichée est vide.';

  @override
  String toString() => message;
}

abstract final class EtatNotifications {
  /// La mention qui BORNE la portée du document.
  ///
  /// Elle s'imprime avec lui, jamais seulement à l'écran : un export qui
  /// circulerait sans elle laisserait croire que ces messages ont été
  /// transmis. Même règle que la fiche de stock non cohérente (PA-135).
  /// Apostrophe DROITE, délibérément : c'est une phrase à NOUS, et c'est la
  /// première qu'un futur PDF devrait imprimer. Voir la note d'apostrophe en
  /// tête de fichier.
  static const String mentionAucunEnvoi =
      "Aucun de ces messages n'a été envoyé par le logiciel. "
      "Ils sont composés et tracés ; le destinataire n'en a rien reçu.";

  /// Le CSV de l'onglet affiché.
  ///
  /// [filtre] est repris tel quel en tête du document (PA-119).
  static String csv({
    required OngletNotifications onglet,
    required String filtre,
    required List<MessageNotification> file,
    required List<MessageNotification> journal,
    required List<ModeleNotification> modeles,
    required List<DeclencheurNotification> declencheurs,
    required TransportsLocaux transports,
  }) {
    final lignes = switch (onglet) {
      OngletNotifications.file => _file(file),
      OngletNotifications.journal => _journal(journal),
      OngletNotifications.modeles => _modeles(modeles),
      OngletNotifications.declencheurs => _declencheurs(declencheurs, modeles),
      OngletNotifications.canaux => _canaux(transports, file),
    };

    if (lignes.corps.isEmpty) throw const ExportVide();

    final tampon = StringBuffer('\u{FEFF}')
      ..writeln(_echapper('Notifications — ${onglet.libelle}'))
      ..writeln(_echapper(filtre))
      ..writeln(_echapper(mentionAucunEnvoi))
      ..writeln()
      ..writeln(lignes.entetes.map(_echapper).join(';'));

    for (final ligne in lignes.corps) {
      tampon.writeln(ligne.map(_echapper).join(';'));
    }

    return tampon.toString();
  }

  /// Les octets du fichier, BOM compris.
  ///
  /// ⚠ Encodés en UTF-8 (corrigé le 09/10/2026) : `codeUnits` rendait des unités
  /// UTF-16, que `writeAsBytes` tronque à un octet — le BOM devenait `0xFF`, le
  /// tiret long « — » du titre devenait `0x14`, et le fichier n'était plus de
  /// l'UTF-8 valide. Aucun test n'avait jamais relu les octets écrits.
  static List<int> csvOctets({
    required OngletNotifications onglet,
    required String filtre,
    required List<MessageNotification> file,
    required List<MessageNotification> journal,
    required List<ModeleNotification> modeles,
    required List<DeclencheurNotification> declencheurs,
    required TransportsLocaux transports,
  }) => utf8.encode(
    csv(
      onglet: onglet,
      filtre: filtre,
      file: file,
      journal: journal,
      modeles: modeles,
      declencheurs: declencheurs,
      transports: transports,
    ),
  );

  // ------------------------------------------------------------- par onglet

  static _Tableau _file(List<MessageNotification> messages) => _Tableau(
    entetes: const [
      'Destinataire',
      'Déclencheur',
      'Canal',
      'Objet',
      'Message',
      'Envoi système',
    ],
    corps: [
      for (final m in messages)
        [
          m.destinataire,
          m.declencheur?.libelle ?? '',
          m.canal?.libelle ?? '',
          m.objet ?? '',
          m.contenu,
          // Jamais dérivé d'une constante : c'est le statut du message qui le
          // dit, et il ne peut pas valoir « oui » sur ce poste.
          m.statut.estUnEnvoiDuSysteme ? 'oui' : 'non',
        ],
    ],
  );

  static _Tableau _journal(List<MessageNotification> messages) => _Tableau(
    entetes: const [
      'Date',
      'Destinataire',
      'Déclencheur',
      'Canal',
      'Statut',
      'Envoi système',
      'Par',
      'Commentaire',
    ],
    corps: [
      for (final m in messages)
        [
          _horodatage(m.traiteLe ?? m.composeLe),
          m.destinataire,
          m.declencheur?.libelle ?? '',
          m.canal?.libelle ?? '',
          m.statut.libelle,
          m.statut.estUnEnvoiDuSysteme ? 'oui' : 'non',
          m.auteurAffiche,
          m.commentaireAffiche,
        ],
    ],
  );

  static _Tableau _modeles(List<ModeleNotification> modeles) => _Tableau(
    entetes: const ['Déclencheur', 'Canal', 'Objet', 'Message', 'État'],
    corps: [
      for (final m in modeles)
        [
          m.declencheur?.libelle ?? m.evenementCode,
          m.canal?.libelle ?? m.canalCode,
          m.objet ?? '',
          m.contenuTemplate,
          m.actif ? 'actif' : 'désactivé',
        ],
    ],
  );

  static _Tableau _declencheurs(
    List<DeclencheurNotification> declencheurs,
    List<ModeleNotification> modeles,
  ) => _Tableau(
    entetes: const [
      'Déclencheur',
      'Public',
      'Module',
      'Modèles',
      'Variables',
      'Détecté sur ce poste',
    ],
    corps: [
      for (final d in declencheurs)
        [
          d.libelle,
          d.public.libelle,
          d.module,
          () {
            final c = comptageParDeclencheur(modeles, d);
            return '${c.actifs} / ${c.total}';
          }(),
          d.variables.map((v) => '{$v}').join(' '),
          // La colonne n'existe pas au maître : elle est AJOUTÉE parce que
          // l'information n'existe que sur ce poste, et qu'un déclencheur muet
          // se lirait sinon comme un déclencheur sans occurrence.
          d.estDetecteSurCePoste ? 'oui' : 'non — ${d.motifNonDetecte}',
        ],
    ],
  );

  static _Tableau _canaux(
    TransportsLocaux transports,
    List<MessageNotification> file,
  ) {
    final enFile = enFileParCanal(file);

    return _Tableau(
      entetes: const [
        'Canal',
        'État',
        'Ce qui bloque',
        'Limite',
        'Destinataire attendu',
        'En file',
      ],
      corps: [
        for (final c in CanalNotification.values)
          [
            c.libelle,
            transports.estBranche(c) ? 'branché' : 'non branché',
            c.blocage,
            c.limite == null ? '—' : '${c.limite} car.',
            c.cible,
            '${enFile[c] ?? 0}',
          ],
      ],
    );
  }

  // ---------------------------------------------------------------- internes

  static String _horodatage(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/'
      '${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';

  /// Guillemets doublés, et les sauts de ligne ramenés à une espace.
  ///
  /// Le contenu d'un message est multiligne par nature : le laisser tel quel
  /// couperait la ligne CSV en deux, et le tableur afficherait une ligne
  /// orpheline sans destinataire.
  static String _echapper(String valeur) {
    final propre = valeur.replaceAll('\r\n', ' ').replaceAll('\n', ' ');
    return '"${propre.replaceAll('"', '""')}"';
  }
}

final class _Tableau {
  const _Tableau({required this.entetes, required this.corps});

  final List<String> entetes;
  final List<List<String>> corps;
}
