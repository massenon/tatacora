import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/notifications/domain/entities/canal_notification.dart';
import 'package:tatacora_flutter/features/notifications/domain/entities/declencheur_notification.dart';
import 'package:tatacora_flutter/features/notifications/domain/registre_notifications.dart';
import 'package:tatacora_flutter/features/notifications/impression/etat_notifications.dart';

/// L'export de M12 — et la RÈGLE D'APOSTROPHE, écrite ici pour qu'elle ne se
/// « corrige » pas toute seule dans six mois.
///
/// ## Les deux moitiés de la règle
///
/// 1. **Chaîne citée du maître** — on recopie ses caractères, U+2019 compris.
///    Le comparateur de conformité l'exige, et le document doit reproduire
///    l'écran.
/// 2. **Chaîne qui nous appartient** — apostrophe droite, parce que c'est elle
///    qu'un PDF devra imprimer un jour : les polices intégrées du format
///    couvrent Latin-1, et U+2019 y disparaît du papier sans erreur ni trace.
///
/// Ce lot ne produit **aucun PDF** — l'export est un CSV en UTF-8 avec BOM, qui
/// rend les deux formes exactement. Ces cas figent donc le RAISONNEMENT, pas
/// une préférence : sans eux, quelqu'un alignerait les deux formes « par
/// propreté » et casserait l'une des deux garanties.
void main() {
  String csvDeclencheurs({String filtre = 'Onglet : Déclencheurs'}) =>
      EtatNotifications.csv(
        onglet: OngletNotifications.declencheurs,
        filtre: filtre,
        file: const [],
        journal: const [],
        modeles: const [],
        declencheurs: DeclencheurNotification.values,
        transports: const TransportsLocaux.aucun(),
      );

  /* ================================================================== */
  group('Le CSV', () {
    test('porte le BOM, le point-virgule et SON FILTRE', () {
      // « L'export porte sur ce qui est affiché, et il dit son filtre »
      // (PA-119) : sans cette ligne, on transmettrait au Gérant un document
      // qu'il croit avoir vérifié en entier.
      final csv = csvDeclencheurs(
        filtre: 'Onglet : Déclencheurs · Public : Client',
      );

      expect(csv.startsWith('\u{FEFF}'), isTrue, reason: 'BOM UTF-8 (RG-19)');
      expect(csv, contains(';'));
      expect(csv, contains('Public : Client'));
    });

    test('porte la mention qui BORNE sa portée', () {
      // Un export qui circulerait sans elle laisserait croire que ces messages
      // ont été transmis. Même règle que la fiche de stock non cohérente
      // (PA-135) : la mention s'imprime AVEC le document.
      expect(csvDeclencheurs(), contains(EtatNotifications.mentionAucunEnvoi));
    });

    test('une liste vide est REFUSÉE, pas rendue en page blanche', () {
      expect(
        () => EtatNotifications.csv(
          onglet: OngletNotifications.file,
          filtre: 'Onglet : File d’attente',
          file: const [],
          journal: const [],
          modeles: const [],
          declencheurs: const [],
          transports: const TransportsLocaux.aucun(),
        ),
        throwsA(isA<ExportVide>()),
      );
    });

    test('les neuf déclencheurs y sont, avec leur détection sur ce poste', () {
      final csv = csvDeclencheurs();

      for (final d in DeclencheurNotification.values) {
        expect(csv, contains(d.libelle), reason: d.code);
      }
      // La colonne ajoutée : un déclencheur muet doit dire POURQUOI, y compris
      // sur le papier.
      expect(csv, contains('non — '));
    });
  });

  /* ================================================================== */
  group("L'apostrophe", () {
    test('un libellé du maître garde son U+2019 en traversant l export', () {
      // FIDÉLITÉ. Le CSV est en UTF-8 : convertir ici ferait diverger le
      // document de l'écran qu'il reproduit.
      final csv = csvDeclencheurs();

      expect(csv, contains('Article sous le seuil d’alerte'));
      // ⚠ La DESCRIPTION d'un déclencheur n'est pas exportée : la colonne
      // « Déclencheur » ne porte que le libellé. Une première version de ce
      // cas la cherchait ici et échouait — vérifié sur le CSV réellement
      // produit, pas supposé.
      //
      // Second témoin, par l'AUTRE chemin qu'emprunte un nom du maître pour
      // entrer dans le document : la ligne de filtre.
      final avecFiltre = csvDeclencheurs(
        filtre: 'Onglet : ${OngletNotifications.file.libelle}',
      );
      expect(avecFiltre, contains('Onglet : File d’attente'));
    });

    test('le blocage d un canal aussi', () {
      final csv = EtatNotifications.csv(
        onglet: OngletNotifications.canaux,
        filtre: 'Onglet : Canaux',
        file: const [],
        journal: const [],
        modeles: const [],
        declencheurs: const [],
        transports: const TransportsLocaux.aucun(),
      );

      expect(csv, contains('L’application Flutter n’est pas démarrée'));
    });

    test('NOS phrases restent en apostrophe DROITE', () {
      // C'est la moitié de la règle qui protège le papier : ces chaînes sont
      // les premières qu'un futur PDF imprimerait, et U+2019 s'y évaporerait
      // sans erreur ni trace (le dépôt s'est fait prendre sur « Chiffre
      // d'affaires »).
      expect(
        EtatNotifications.mentionAucunEnvoi.contains('’'),
        isFalse,
        reason:
            'une phrase à nous ne porte jamais U+2019 : elle peut finir '
            'sur un PDF, dont les polices ne la rendraient pas',
      );
      expect(EtatNotifications.mentionAucunEnvoi, contains("n'a été envoyé"));
    });

    test('les en-têtes de colonne ne portent aucun U+2019', () {
      // Ce sont nos chaînes, et ce sont celles qu'un PDF poserait en tête de
      // chaque page.
      final entetes = csvDeclencheurs().split('\n')[4];

      expect(entetes.contains('’'), isFalse, reason: entetes);
      expect(entetes, contains('Déclencheur'));
    });
  });
}
