import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/periode_sejour.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/reservation.dart';
import 'package:tatacora_flutter/features/notifications/domain/entities/canal_notification.dart';
import 'package:tatacora_flutter/features/notifications/domain/entities/declencheur_notification.dart';
import 'package:tatacora_flutter/features/notifications/domain/entities/modele_notification.dart';
import 'package:tatacora_flutter/features/notifications/domain/registre_notifications.dart';

/// M12 — les deux registres fermés, la composition, la détection.
///
/// ## Ces cas relisent le SERVEUR, ils ne figent pas une liste
///
/// Un test qui recopierait les neuf codes côté Dart ne vérifierait que
/// lui-même, et resterait vert le jour où le registre serveur changerait
/// (`conformite_stocks_test.dart` fait de même sur les `FormRequest`, PA-136).
/// Ils ÉCHOUENT si le fichier serveur est introuvable — ils ne sautent pas — et
/// chaque extraction est prouvée non vide, sans quoi le balayage serait vert à
/// vide.
void main() {
  String lireServeur(String chemin) {
    final fichier = File(chemin);
    if (!fichier.existsSync()) {
      fail(
        'Source serveur introuvable : $chemin. Ce test relit le registre du '
        'serveur ; sans lui il ne vérifierait que lui-même.',
      );
    }
    return fichier.readAsStringSync();
  }

  /* ================================================================== */
  group('Le registre des neuf déclencheurs', () {
    final source = lireServeur(
      '../tatacora-api/app/Domain/Notifications/Services/RegistreDeclencheurs.php',
    );

    test('les NEUF codes du serveur sont ceux du client, dans son ordre', () {
      final codes = RegExp(
        r"'([a-z_]+)'\s*=>\s*\[\s*'public'",
      ).allMatches(source).map((m) => m.group(1)!).toList(growable: false);

      // Sans ce plancher, un renommage côté serveur viderait l'extraction et
      // rendrait la comparaison vraie à vide — le défaut même que ce test
      // protège.
      expect(
        codes.length,
        9,
        reason: 'extraction vide ou partielle du registre serveur',
      );
      expect(DeclencheurNotification.codes, codes);
    });

    test('le public et le module de chacun suivent le serveur', () {
      for (final d in DeclencheurNotification.values) {
        final entree = RegExp(
          "'${d.code}'\\s*=>\\s*\\[\\s*'public'\\s*=>\\s*'([a-z]+)',\\s*"
          "'module'\\s*=>\\s*'([A-Z0-9]+)'",
        ).firstMatch(source);

        expect(entree, isNotNull, reason: '${d.code} absent du serveur');
        expect(d.public.code, entree!.group(1));
        expect(d.module, entree.group(2));
      }
    });

    test('les variables offertes sont celles du serveur', () {
      // Les changer ferait mentir l'aide « Variables disponibles » de la
      // modale, puis refuserait à la composition des messages que l'écran
      // présentait comme valides.
      for (final d in DeclencheurNotification.values) {
        final bloc = RegExp(
          "'${d.code}'\\s*=>\\s*\\[.*?'variables'\\s*=>\\s*\\[(.*?)\\]",
          dotAll: true,
        ).firstMatch(source);

        expect(bloc, isNotNull, reason: '${d.code} : variables introuvables');
        final variables = RegExp("'([a-z_]+)'")
            .allMatches(bloc!.group(1)!)
            .map((m) => m.group(1)!)
            .toList(growable: false);

        expect(variables, isNotEmpty);
        expect(d.variables, variables, reason: d.code);
      }
    });

    test('un code hors registre rend null, jamais une entrée fabriquée', () {
      // Un modèle dont l'événement a disparu doit se VOIR à l'écran, pas se
      // fondre derrière son propre code affiché comme un libellé.
      expect(DeclencheurNotification.parCode('facture_emise'), isNull);
      expect(DeclencheurNotification.parCode(null), isNull);
      expect(PublicNotification.parCode('actionnaire'), isNull);
    });

    test('les libellés sont ceux du fichier de langue du maître', () {
      final langue = lireServeur(
        '../tatacora-api/lang/fr/notifications_pwa.php',
      );

      for (final d in DeclencheurNotification.values) {
        final attendu = RegExp(
          "'declencheur\\.${d.code}\\.libelle'\\s*=>\\s*'(.*?)',",
        ).firstMatch(langue);

        expect(attendu, isNotNull, reason: '${d.code} absent du fichier fr');
        // Comparaison LITTÉRALE, apostrophe comprise. La garde de conformité
        // compare de la même façon : un libellé recopié avec une apostrophe
        // droite y compterait comme ABSENT et gonflerait la dette. Normaliser
        // ici masquerait précisément l'écart qu'il faut voir.
        expect(d.libelle, attendu!.group(1), reason: d.code);
      }
    });

    test('les descriptions aussi, apostrophe typographique comprise', () {
      // C'est ici que l'écart se logeait : TROIS descriptions portent un
      // U+2019, contre un seul libellé. Comparer les libellés seuls aurait
      // laissé passer l'essentiel.
      final langue = lireServeur(
        '../tatacora-api/lang/fr/notifications_pwa.php',
      );
      var avecApostropheTypographique = 0;

      for (final d in DeclencheurNotification.values) {
        final attendu = RegExp(
          "'declencheur\\.${d.code}\\.description'\\s*=>\\s*'(.*?)',",
        ).firstMatch(langue);

        expect(attendu, isNotNull, reason: '${d.code} : description absente');
        expect(d.description, attendu!.group(1), reason: d.code);
        if (d.description.contains('’')) avecApostropheTypographique++;
      }

      // Plancher : sans lui, ce cas resterait vert le jour où les apostrophes
      // disparaîtraient des DEUX côtés à la fois — un test qui ne compare que
      // lui-même.
      expect(
        avecApostropheTypographique,
        greaterThanOrEqualTo(3),
        reason:
            'extraction suspecte : le maître pose U+2019 sur trois '
            'descriptions au moins',
      );
    });

    test('chaque déclencheur NON détecté porte un motif, daté', () {
      // Une raison de refus qui a cessé d'être vraie transforme une décision en
      // oubli (PA-144). Un motif vide ferait lire « aucune occurrence » là où
      // il faut lire « ce poste ne sait pas regarder ».
      for (final d in DeclencheurNotification.values) {
        if (d.estDetecteSurCePoste) {
          expect(d.motifNonDetecte, isEmpty, reason: d.code);
        } else {
          expect(d.motifNonDetecte, isNotEmpty, reason: d.code);
          expect(d.motifNonDetecte.length, greaterThan(40), reason: d.code);
        }
      }
    });
  });

  /* ================================================================== */
  group('Les quatre canaux', () {
    final source = lireServeur(
      '../tatacora-api/app/Domain/Notifications/Services/RegistreCanaux.php',
    );

    test('les codes suivent le serveur', () {
      final codes = RegExp(
        r"public const [A-Z]+ = '([a-z]+)';",
      ).allMatches(source).map((m) => m.group(1)!).toList(growable: false);

      expect(codes.length, 4, reason: 'extraction vide ou partielle');
      expect(CanalNotification.codes, codes);
    });

    test('les limites suivent le serveur, e-mail sans limite', () {
      expect(CanalNotification.whatsapp.limite, 4096);
      expect(CanalNotification.android.limite, 240);
      expect(CanalNotification.sms.limite, 160);
      // `null`, jamais 0 : « 0 caractère » se lirait comme un canal qui
      // n'accepte rien.
      expect(CanalNotification.email.limite, isNull);
    });

    test('AUCUN canal n est branché, et l état se DÉRIVE', () {
      // C'est la leçon du badge MECeF (PA-61) : un drapeau posé à la main
      // serait passé au vert le jour du branchement pendant que rien ne part.
      const transports = TransportsLocaux.aucun();

      for (final c in CanalNotification.values) {
        expect(transports.estBranche(c), isFalse, reason: c.code);
        expect(c.blocage, isNotEmpty, reason: c.code);
      }
      expect(transports.nombreBranches, 0);

      // Et la dérivation fonctionne réellement : montée à la main, elle suit.
      // Sans ce cas, `estBranche` pourrait rendre `false` en dur sans que rien
      // ne le signale.
      const avecEmail = TransportsLocaux({CanalNotification.email});
      expect(avecEmail.estBranche(CanalNotification.email), isTrue);
      expect(avecEmail.nombreBranches, 1);
    });
  });

  /* ================================================================== */
  group('La composition', () {
    ModeleNotification modele(String contenu, {String? objet}) =>
        ModeleNotification(
          id: 'm1',
          evenementCode: DeclencheurNotification.sejourDemain.code,
          declencheur: DeclencheurNotification.sejourDemain,
          canalCode: CanalNotification.whatsapp.code,
          canal: CanalNotification.whatsapp,
          contenuTemplate: contenu,
          objet: objet,
          actif: true,
          creeLe: DateTime(2026, 9, 14),
        );

    test('les variables sont remplacées par les vraies valeurs', () {
      final resultat = modele(
        'Bonjour {client}, {nuits} nuit(s).',
      ).composer({'client': 'KORA', 'nuits': '3'});

      expect(resultat, isA<MessageCompose>());
      final compose = resultat as MessageCompose;
      expect(compose.contenu, 'Bonjour KORA, 3 nuit(s).');
      expect(compose.longueur, compose.contenu.length);
    });

    test('une variable non résolue REFUSE le message', () {
      // « Un client ne doit jamais lire une accolade. » Rien n'est mis en
      // file, pas même tronqué.
      final resultat = modele('Vous devez {montant} FCFA.').composer({});

      expect(resultat, isA<CompositionRefusee>());
      expect((resultat as CompositionRefusee).variables, ['montant']);
      expect(resultat.message, contains('{montant}'));
    });

    test('une valeur VIDE compte comme absente', () {
      // « vous devez  FCFA » est aussi faux que « vous devez {montant} FCFA »,
      // et bien plus difficile à repérer à la relecture.
      final resultat = modele('Solde {reste_du}.').composer({'reste_du': ''});

      expect(resultat, isA<CompositionRefusee>());
    });

    test('l objet est composé lui aussi, et contrôlé', () {
      final resultat = modele(
        'Bonjour {client}.',
        objet: 'Séjour de {client} le {date_arrivee}',
      ).composer({'client': 'KORA'});

      // `{date_arrivee}` reste littérale dans l'OBJET : le message est refusé
      // même si le corps, lui, est complet.
      expect(resultat, isA<CompositionRefusee>());
      expect((resultat as CompositionRefusee).variables, ['date_arrivee']);
    });

    test('la longueur ne compte QUE le corps', () {
      final resultat =
          modele(
                'Court.',
                objet: 'Un objet nettement plus long que le corps',
              ).composer({})
              as MessageCompose;

      expect(resultat.longueur, 'Court.'.length);
    });

    test('les variables hors déclencheur sont signalées', () {
      final m = modele('Bonjour {client}, votre {vehicule}.');

      expect(m.variablesCitees, containsAll(['client', 'vehicule']));
      // `vehicule` appartient à un AUTRE déclencheur : le message serait
      // refusé, et l'écran doit le dire à la relecture.
      expect(m.variablesInconnues, ['vehicule']);
    });
  });

  /* ================================================================== */
  group('La détection', () {
    final aujourdHui = DateTime(2026, 9, 14);

    Reservation reservation({
      required String id,
      required DateTime arrivee,
      required DateTime depart,
      StatutReservation statut = StatutReservation.confirmee,
      int tarif = 25000,
      int acompte = 0,
    }) => Reservation(
      id: id,
      reference: 'LOC-$id',
      clientId: 'c-$id',
      clientNom: 'KORA',
      uniteId: 'u-1',
      periode: PeriodeSejour(arrivee: arrivee, depart: depart),
      tarifNuit: tarif,
      statut: statut,
      statutSynchronisation: StatutSynchronisation.local,
      creeeLe: aujourdHui,
      acompte: acompte,
    );

    test('« arrivée demain » retient le séjour du lendemain, et lui seul', () {
      final occurrences = detecterOccurrences(
        declencheur: DeclencheurNotification.sejourDemain,
        aujourdHui: aujourdHui,
        reservations: [
          reservation(
            id: 'demain',
            arrivee: DateTime(2026, 9, 15),
            depart: DateTime(2026, 9, 18),
          ),
          reservation(
            id: 'apres-demain',
            arrivee: DateTime(2026, 9, 16),
            depart: DateTime(2026, 9, 18),
          ),
          reservation(
            id: 'hier',
            arrivee: DateTime(2026, 9, 13),
            depart: DateTime(2026, 9, 18),
          ),
        ],
      );

      expect(occurrences.length, 1);
      expect(occurrences.single.destinataire, 'KORA');
      expect(occurrences.single.variables['nuits'], '3');
      expect(occurrences.single.variables['date_arrivee'], '15/09/2026');
    });

    test('une réservation ANNULÉE ne déclenche rien', () {
      // Prévenir un client d'une arrivée annulée est pire que ne rien
      // envoyer : il se présenterait.
      final occurrences = detecterOccurrences(
        declencheur: DeclencheurNotification.sejourDemain,
        aujourdHui: aujourdHui,
        reservations: [
          reservation(
            id: 'annulee',
            arrivee: DateTime(2026, 9, 15),
            depart: DateTime(2026, 9, 18),
            statut: StatutReservation.annulee,
          ),
        ],
      );

      expect(occurrences, isEmpty);
    });

    test('« départ du jour » porte le reste dû, REMISE COMPRISE', () {
      // Le montant vient de `Reservation.resteAPayer`, jamais d'une seconde
      // formule : celle-ci tient compte de la remise depuis PA-111, et une
      // copie réclamerait au client l'argent qu'on vient de lui accorder.
      final r = reservation(
        id: 'part',
        arrivee: DateTime(2026, 9, 11),
        depart: aujourdHui,
        tarif: 20000,
        acompte: 15000,
      );

      final occurrences = detecterOccurrences(
        declencheur: DeclencheurNotification.sejourDepart,
        aujourdHui: aujourdHui,
        reservations: [r],
      );

      expect(occurrences.length, 1);
      expect(occurrences.single.variables['reste_du'], contains('45 000'));
    });

    test(
      'la référence est STABLE — elle ne dépend pas du jour d exécution',
      () {
        // C'est la moitié de la clé d'idempotence : une référence horodatée
        // recomposerait le même message à chaque relance.
        final r = reservation(
          id: 'stable',
          arrivee: DateTime(2026, 9, 15),
          depart: DateTime(2026, 9, 18),
        );

        final premiere = detecterOccurrences(
          declencheur: DeclencheurNotification.sejourDemain,
          aujourdHui: aujourdHui,
          reservations: [r],
        ).single.reference;

        final seconde = detecterOccurrences(
          declencheur: DeclencheurNotification.sejourDemain,
          aujourdHui: DateTime(2026, 9, 14, 23, 59),
          reservations: [r],
        ).single.reference;

        expect(premiere, seconde);
        expect(premiere, 'sejour_demain:stable');
      },
    );

    test('les SEPT déclencheurs non détectés rendent une liste vide', () {
      // Et leur motif est vérifié plus haut : rendre vide SANS le dire ferait
      // lire « aucune occurrence aujourd hui ».
      for (final d in DeclencheurNotification.values) {
        if (d.estDetecteSurCePoste) continue;

        expect(
          detecterOccurrences(
            declencheur: d,
            aujourdHui: aujourdHui,
            reservations: [
              // DEUX séjours réels, choisis pour que les deux déclencheurs
              // DÉTECTÉS y trouvent chacun leur compte : une arrivée demain et
              // un départ aujourd'hui. Les sept autres doivent rester vides
              // malgré cette matière — sans quoi le cas ne prouverait que
              // l'absence de données.
              reservation(
                id: 'arrive-demain',
                arrivee: DateTime(2026, 9, 15),
                depart: DateTime(2026, 9, 18),
              ),
              reservation(
                id: 'part-aujourd-hui',
                arrivee: DateTime(2026, 9, 11),
                depart: aujourdHui,
              ),
            ],
          ),
          isEmpty,
          reason: d.code,
        );
      }
    });
  });
}
