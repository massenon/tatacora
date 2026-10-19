import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/fiche_reservation.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/historique_reservations.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/periode_sejour.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/reservation.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/service_reservation.dart';
import 'package:tatacora_flutter/core/impression/texte_ticket.dart';
import 'package:tatacora_flutter/features/hebergement/impression/etat_historique.dart';

/// L'état « Historique des réservations » — CSV et PDF **réellement produits**.
///
/// Un test qui se contenterait de vérifier que la méthode existe ne prouverait
/// rien : la règle du dépôt est que le code livré a été exécuté, pas seulement
/// relu. Le PDF est donc composé pour de vrai, et ses octets contrôlés.
void main() {
  final maintenant = DateTime(2026, 9, 15);

  LigneHistorique ligne({
    String client = 'KORA Jean',
    CanalReservation? canal = CanalReservation.booking,
    int acompte = 0,
    StatutReservation statut = StatutReservation.confirmee,
  }) => LigneHistorique.deriver(
    Reservation(
      id: 'res-1',
      reference: 'LOC-AAA',
      clientId: 'cli-1',
      clientNom: client,
      uniteId: 'u-1',
      periode: PeriodeSejour(
        arrivee: DateTime(2026, 9, 20),
        depart: DateTime(2026, 9, 22),
      ),
      tarifNuit: 28000,
      statut: statut,
      statutSynchronisation: StatutSynchronisation.local,
      creeeLe: DateTime(2026, 9, 1),
      acompte: acompte,
      canal: canal,
      lignes: const [
        LigneService(
          id: 'l-1',
          service: ServiceReservation.hebergement,
          itemId: 'u-1',
          libelle: 'Bungalow (BNG-01)',
          prixUnitaire: 28000,
          quantite: 2,
        ),
      ],
    ),
    maintenant: maintenant,
  );

  EtatHistorique etat({
    List<LigneHistorique>? lignes,
    FiltreHistorique filtre = const FiltreHistorique(),
  }) {
    final l = lignes ?? [ligne()];
    return EtatHistorique.composer(
      lignes: l,
      kpis: KpisHistorique.calculer(l),
      filtre: filtre,
    );
  }

  /* ================================================================== */
  group('Le CSV s’ouvre vraiment dans un tableur', () {
    test('il commence par le BOM UTF-8', () {
      // Sans lui, Excel lit le fichier en ANSI : « Réservations » devient
      // « RÃ©servations », et l'état devient impubliable.
      expect(etat().csv().codeUnitAt(0), 0xFEFF);
    });

    test('le séparateur est le point-virgule', () {
      // Un Excel en configuration française — celle des postes du Gîte —
      // attend le point-virgule. Avec une virgule, tout arrive dans une seule
      // colonne et le fichier passe pour cassé.
      expect(etat().csv(), contains('"Client";"Canal";"Arrivée"'));
    });

    test('les montants partent en nombres BRUTS, jamais formatés', () {
      // Un tableur ne sait pas additionner « 56 000 FCFA ». Le formatage est
      // l'affaire de l'écran et du PDF, pas du fichier de travail.
      final csv = etat(lignes: [ligne(acompte: 20000)]).csv();
      expect(csv, contains('"56000";"36000"'));

      // Le bandeau d'indicateurs, LUI, reste formaté — c'est ce que fait le
      // maître (`etatExport().kpis` passe par `fcfa()`). La distinction n'est
      // pas cosmétique : les indicateurs se lisent, les colonnes se calculent.
      expect(csv, contains('"Chiffre d’affaires";"56 000 FCFA"'));
    });

    test('un guillemet dans un nom ne casse pas la ligne', () {
      final csv = etat(lignes: [ligne(client: 'Auberge "Le Baobab"')]).csv();
      expect(csv, contains('"Auberge ""Le Baobab"""'));
    });

    test('les quatre indicateurs de l’état y figurent', () {
      final csv = etat(lignes: [ligne(acompte: 20000)]).csv();
      expect(csv, contains('"Réservations";"1"'));
      expect(csv, contains('"Nuitées";"2"'));
      expect(csv, contains('Chiffre d’affaires'));
      expect(csv, contains('Reste à encaisser'));
    });
  });

  /* ================================================================== */
  group('La période est DITE, jamais devinée', () {
    test('sans borne : « Toutes périodes »', () {
      // Sans cette mention, un état partiel se lirait comme un état complet —
      // et c'est sur cet état qu'on décide d'une relance.
      expect(etat().periode, 'Toutes périodes');
    });

    test('avec bornes : les deux dates', () {
      final e = etat(
        filtre: FiltreHistorique(
          debut: DateTime(2026, 9, 1),
          fin: DateTime(2026, 9, 30),
        ),
      );
      expect(e.periode, contains('01/09/2026'));
      expect(e.periode, contains('30/09/2026'));
    });

    test('avec une seule borne, l’autre reste explicitement ouverte', () {
      final e = etat(filtre: FiltreHistorique(debut: DateTime(2026, 9, 1)));
      expect(e.periode, contains('01/09/2026'));
      expect(e.periode, contains('…'));
    });
  });

  /* ================================================================== */
  group('Le PDF est réellement produit', () {
    test('les octets sortent, et ce sont bien ceux d’un PDF', () async {
      final octets = await etat(lignes: [ligne(acompte: 20000)]).pdf();

      // `%PDF` — la signature du format. Un document composé mais jamais
      // sérialisé passerait tous les tests de structure et ne s'ouvrirait
      // chez personne.
      expect(octets.length, greaterThan(1000));
      expect(String.fromCharCodes(octets.take(4)), '%PDF');
    });

    test('un historique VIDE produit quand même un document, qui le dit', () {
      // Une page blanche laisserait croire à un document tronqué, et
      // l'utilisateur le rééditerait sans savoir quoi changer.
      final vide = etat(lignes: const []);
      expect(vide.lignes, isEmpty);
      expect(vide.indicateurs['Réservations'], '0');
    });

    test('aucun caractère ne peut être PERDU sur le papier', () {
      // Les polices intégrées du format PDF couvrent Latin-1, pas davantage.
      // À la première composition, `dart_pdf` a réellement écrit : « Unable to
      // find a font to draw ’ (U+2019) » — l'apostrophe de « Chiffre
      // d'affaires ». Le document se sérialisait quand même : le caractère
      // était simplement absent du papier, et rien ne le disait.
      //
      // La garde porte sur les textes RÉELLEMENT composés, jamais sur un
      // échantillon écrit à la main : c'est ce qui la rend valable pour un nom
      // de client qu'on ne connaît pas encore.
      final e = etat(lignes: [ligne(client: 'KORA Jean — l’Étoile')]);

      final textes = <String>[
        EtatHistorique.titre,
        e.periode,
        ...EtatHistorique.entetes,
        ...e.indicateurs.keys,
        ...e.indicateurs.values,
        ...e.lignes.expand(e.cellules),
      ].map(texteTicket);

      for (final texte in textes) {
        expect(
          caracteresNonImprimables(texte),
          isEmpty,
          reason: '« $texte » perdrait des caractères à l’impression.',
        );
      }
    });

    test('le PDF d’un historique vide se sérialise aussi', () async {
      final octets = await etat(lignes: const []).pdf();
      expect(String.fromCharCodes(octets.take(4)), '%PDF');
    });
  });

  /* ================================================================== */
  group('Une seule composition pour les deux rendus', () {
    test('les cellules du CSV sont celles du tableau PDF', () {
      // Le point : composer deux fois les mêmes cellules les ferait diverger,
      // et personne ne compare un PDF à un CSV avant de les envoyer.
      final e = etat(lignes: [ligne(acompte: 20000)]);
      final cellules = e.cellules(e.lignes.single);

      expect(cellules, hasLength(EtatHistorique.entetes.length));
      expect(cellules[0], 'KORA Jean');
      expect(cellules[1], 'Booking.com');
      expect(cellules[4], '2');
      expect(cellules[7], '56000');
      expect(cellules[8], '36000');
      expect(cellules[9], 'À venir');

      for (final cellule in cellules) {
        expect(e.csv(), contains('"$cellule"'));
      }
    });
  });
}
