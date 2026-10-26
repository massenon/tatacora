import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/fichiers/selecteur_fichiers.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/theme/app_colors.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/periode_sejour.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/reservation.dart';
import 'package:tatacora_flutter/features/notifications/data/notifications_dao.dart';
import 'package:tatacora_flutter/features/notifications/domain/entities/canal_notification.dart';
import 'package:tatacora_flutter/features/notifications/domain/entities/declencheur_notification.dart';
import 'package:tatacora_flutter/features/notifications/presentation/ecran_notifications.dart';
import 'package:tatacora_flutter/features/notifications/presentation/providers_notifications.dart';

import '../../support/selecteur_essai.dart';

/// L'écran M12 — les mots du maître, et la règle qui commande le module.
///
/// ## Ce que ces cas protègent
///
/// **Qu'aucun élément de cet écran n'annonce un envoi.** Un bouton
/// « Envoyer », un statut « envoyé », un compteur vert : chacun ferait croire
/// au Gérant que son client est prévenu. C'est la famille PA-59/60/61, et le
/// maître écrit lui-même que ce serait « pire que pas de module du tout ».
///
/// La détection n'est PAS déclenchée par le bouton ici : la file est semée par
/// le DAO, qui est le seul à écrire. Presser « Détecter maintenant » ferait
/// entrer le dépôt de réservations de M1 dans ce test, qui ne dirait alors plus
/// rien de l'écran. Le chemin du bouton est couvert par
/// `notifications_dao_test.dart`.
void main() {
  late AppDatabase db;
  late NotificationsDao dao;

  final aujourdHui = DateTime(2026, 9, 14);

  setUp(() {
    db = AppDatabase.enMemoire();
    dao = NotificationsDao(db);
  });

  tearDown(() => db.close());

  /// Sème un modèle actif ET son message composé, par le seul chemin d'écriture.
  Future<void> semerUnMessage({
    CanalNotification canal = CanalNotification.whatsapp,
  }) async {
    await dao.creerModele(
      declencheur: DeclencheurNotification.sejourDemain,
      canal: canal,
      contenuTemplate: 'Bonjour {client}, arrivée le {date_arrivee}.',
    );

    await dao.detecter(
      aujourdHui: aujourdHui,
      reservations: [
        Reservation(
          id: 'r1',
          reference: 'LOC-1',
          clientId: 'c1',
          clientNom: 'KORA',
          uniteId: 'u1',
          periode: PeriodeSejour(
            arrivee: DateTime(2026, 9, 15),
            depart: DateTime(2026, 9, 18),
          ),
          tarifNuit: 25000,
          statut: StatutReservation.confirmee,
          statutSynchronisation: StatutSynchronisation.local,
          creeeLe: aujourdHui,
        ),
      ],
    );
  }

  Future<void> monter(
    WidgetTester tester, {
    GardeAcces? droits,
    List<Override> surcharges = const [],
  }) async {
    tester.view
      ..physicalSize = const Size(2200, 2400)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseLocaleProvider.overrideWithValue(db),
          droitsProvider.overrideWithValue(
            droits ?? GardeAcces.depuisJson(const {'M12': 'C'}),
          ),
          ...surcharges,
        ],
        child: MaterialApp(
          theme: AppTheme.clair,
          home: const Scaffold(body: EcranNotifications()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> ouvrir(WidgetTester tester, String onglet) async {
    await tester.tap(find.byKey(Key('notifications-onglet-$onglet')));
    await tester.pumpAndSettle();
  }

  /* ================================================================== */
  group('AUCUN envoi n’est annoncé', () {
    testWidgets('le bandeau DIT que rien ne part de ce poste', (tester) async {
      // C'est la seule phrase de la page qui dise au Gérant que rien ne part.
      await monter(tester);

      expect(find.byKey(const Key('notifications-bandeau')), findsOneWidget);
      // Les deux phrases de la vue (`notifications_pwa.bandeau_titre` et
      // `bandeau_texte`), mot pour mot : elles restent VRAIES de ce poste.
      expect(
        find.text('Seul l’e-mail peut réellement partir, et sous conditions.'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'sinon le message reste en file, avec la raison affichée.',
        ),
        findsOneWidget,
      );
      // Et la phrase du POSTE, qui dit ce que ces conditions donnent ici.
      expect(
        find.textContaining('Aucun message ne part de ce poste'),
        findsOneWidget,
      );
      // La conséquence, dans les mots du maître — sans elle, la phrase se
      // lirait comme une limite technique, pas comme une consigne.
      expect(
        find.textContaining('le Gérant croirait son client prévenu'),
        findsOneWidget,
      );
      // Et la consigne du manuel : ce qu'il faut FAIRE à la place.
      expect(
        find.textContaining('appelez-le, puis tracez la transmission'),
        findsOneWidget,
      );
    });

    testWidgets('AUCUN bouton « Envoyer » n’existe nulle part', (tester) async {
      // ⚠ LE cas du module. La vue rend ce bouton pour le canal e-mail ; ici
      // aucun transport n'existe, et un bouton qui échoue toujours est la
      // version cliquable de l'entrée inerte que l'Article 3.3 refuse.
      await semerUnMessage(canal: CanalNotification.email);
      await monter(tester);

      expect(find.widgetWithText(OutlinedButton, 'Envoyer'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Envoyer'), findsNothing);
      expect(find.widgetWithText(TextButton, 'Envoyer'), findsNothing);
      expect(find.widgetWithText(InkWell, 'Envoyer'), findsNothing);

      // Le panneau « Ce que la maquette prévoit et qui n'est pas rendu » a été
      // retiré le 09/10/2026 (la vue n'en porte pas) : le mot n'apparaît plus
      // nulle part. La raison de l'absence vit dans le commentaire de l'écran
      // et, sur la ligne e-mail, dans la pastille qui remplace le bouton.
      expect(find.text('Envoyer'), findsNothing);
    });

    testWidgets(
      'un message e-mail porte « non envoyé » et la RAISON du relais',
      (tester) async {
        await semerUnMessage(canal: CanalNotification.email);
        await monter(tester);

        final message = (await dao.file()).single;

        expect(
          find.byKey(Key('notifications-non-envoye-${message.id}')),
          findsOneWidget,
        );
        expect(find.text('non envoyé'), findsOneWidget);
        // Comme la vue (l.281-282) : la RAISON remplace le bouton, dérivée de
        // `estBranche`.
        expect(
          find.byKey(Key('notifications-sans-relais-${message.id}')),
          findsOneWidget,
        );
        expect(find.text('Aucun relais SMTP réel configuré'), findsOneWidget);
        // Et pas l'étiquette des trois autres canaux.
        expect(
          find.byKey(Key('notifications-a-parametrer-${message.id}')),
          findsNothing,
        );
        expect(find.text('à paramétrer au déploiement'), findsNothing);
      },
    );

    testWidgets('un message WhatsApp porte l’étiquette du maître', (
      tester,
    ) async {
      await semerUnMessage();
      await monter(tester);

      final message = (await dao.file()).single;

      expect(
        find.byKey(Key('notifications-a-parametrer-${message.id}')),
        findsOneWidget,
      );
      expect(find.text('à paramétrer au déploiement'), findsOneWidget);
      expect(
        find.byKey(Key('notifications-sans-relais-${message.id}')),
        findsNothing,
      );
      expect(find.text('Aucun relais SMTP réel configuré'), findsNothing);
    });

    testWidgets('« Réellement envoyés » affiche zéro', (tester) async {
      await semerUnMessage();
      await monter(tester);

      expect(
        find.byKey(const Key('notifications-kpi-envoyes')),
        findsOneWidget,
      );
      expect(find.text('Réellement envoyés'.toUpperCase()), findsOneWidget);
      // Et il ne promet aucun transport : la vue écrit « E-mails partis »,
      // ce poste n'en a aucun.
      expect(find.text('Aucun transport sur ce poste'), findsOneWidget);
    });

    testWidgets('le journal dit « non » en Envoi système après un geste '
        'manuel', (tester) async {
      // « Transmis à la main » n'est JAMAIS un envoi système : ce n'est pas le
      // logiciel qui a fait partir le message.
      await semerUnMessage();
      final message = (await dao.file()).single;
      await dao.marquerTransmis(message.id, auteur: 'reception');

      await monter(tester);
      await ouvrir(tester, 'journal');

      expect(
        find.byKey(Key('notifications-envoi-systeme-${message.id}')),
        findsOneWidget,
      );
      expect(find.text('non'), findsOneWidget);
      expect(find.text('oui'), findsNothing);
      expect(find.text('Transmis à la main'), findsWidgets);
      expect(find.text('Journal — 1 message(s)'), findsOneWidget);
    });
  });

  /* ================================================================== */
  group('Les libellés du maître', () {
    testWidgets('le titre et les CINQ onglets, dans son ordre', (tester) async {
      await monter(tester);

      expect(find.text('Notifications'), findsOneWidget);
      // ⚠ Apostrophe TYPOGRAPHIQUE (U+2019), comme `lang/fr/notifications_pwa.php`.
      // La forme droite était une consigne de ma part, fausse pour ce module :
      // la règle qui prime est la fidélité au maître, caractère pour
      // caractère — le comparateur compare littéralement.
      expect(find.text('File d’attente'), findsOneWidget);
      expect(find.text('Modèles'), findsOneWidget);
      expect(find.text('Déclencheurs'), findsOneWidget);
      expect(find.text('Journal'), findsOneWidget);
      expect(find.text('Canaux'), findsOneWidget);
    });

    testWidgets('les SIX indicateurs sont rendus', (tester) async {
      await monter(tester);

      for (final cle in [
        'attente',
        'envoyes',
        'transmis',
        'abandonnes',
        'modeles',
        'canaux',
      ]) {
        expect(
          find.byKey(Key('notifications-kpi-$cle')),
          findsOneWidget,
          reason: cle,
        );
      }
    });

    testWidgets('une file vide le DIT, avec les mots du maître', (
      tester,
    ) async {
      // Un écran qui ne rend jamais rien passe pour cassé (leçon PA-90).
      await monter(tester);

      expect(find.byKey(const Key('notifications-file-vide')), findsOneWidget);
      // UNE seule phrase, comme la vue (l.314) — et non un titre suivi d'un
      // détail.
      expect(
        find.text(
          'Aucun message en attente. Lancez « Détecter maintenant » pour '
          'composer les messages du jour.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('les QUATRE canaux sont « non branché », avec leur blocage', (
      tester,
    ) async {
      await monter(tester);
      await ouvrir(tester, 'canaux');

      for (final c in CanalNotification.values) {
        expect(
          find.byKey(Key('notifications-canal-${c.code}')),
          findsOneWidget,
          reason: c.code,
        );
      }
      expect(find.text('non branché'), findsNWidgets(4));
      expect(find.text('branché'), findsNothing);
      // Ce qui bloque chacun — c'est cette colonne qui dit que la levée est un
      // contrat, pas un développement.
      expect(
        find.textContaining('API WhatsApp Business non contractée'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Aucun agrégateur SMS retenu'),
        findsOneWidget,
      );
    });

    testWidgets('les NEUF déclencheurs sont rendus, les non détectés avec '
        'leur motif', (tester) async {
      await monter(tester);
      await ouvrir(tester, 'declencheurs');

      for (final d in DeclencheurNotification.values) {
        expect(
          find.byKey(Key('notifications-declencheur-${d.code}')),
          findsOneWidget,
          reason: d.code,
        );
      }

      // Les sept que ce poste ne sait pas regarder DISENT pourquoi : rendre
      // vide sans le dire ferait lire « aucune occurrence aujourd'hui ».
      for (final d in DeclencheurNotification.values) {
        final motif = find.byKey(Key('notifications-motif-${d.code}'));
        if (d.estDetecteSurCePoste) {
          expect(motif, findsNothing, reason: d.code);
        } else {
          expect(motif, findsOneWidget, reason: d.code);
        }
      }
    });

    testWidgets('un modèle dont une variable est inconnue est SIGNALÉ', (
      tester,
    ) async {
      // Le maître le signale en rouge : « le message serait refusé ». C'est le
      // seul moment où la correction est gratuite.
      final m = await dao.creerModele(
        declencheur: DeclencheurNotification.sejourDemain,
        canal: CanalNotification.whatsapp,
        contenuTemplate: 'Bonjour {client}, votre {vehicule}.',
      );

      await monter(tester);
      await ouvrir(tester, 'modeles');

      expect(
        find.byKey(Key('notifications-variables-${m.id}')),
        findsOneWidget,
      );
      expect(find.textContaining('{vehicule}'), findsWidgets);
    });
  });

  /* ================================================================== */
  group('« Détecter » ne conclut pas sur ce qu’il n’a pas regardé', () {
    testWidgets('sans aucun modèle, l’écran dit que rien n’a été regardé', (
      tester,
    ) async {
      // ⚠ Le défaut que ce cas ferme : l'écran répondait « Aucun nouvel
      // événement à notifier » sur un poste neuf — une conclusion sur les
      // ÉVÉNEMENTS alors que seuls les MODÈLES avaient été mesurés, et que
      // rien ne sème le référentiel ici. Le Gérant lisait « rien à faire »
      // pendant qu'une arrivée était prévue le lendemain (PA-59/60/61).
      await monter(tester);

      await tester.tap(find.byKey(const Key('notifications-detecter')));
      await tester.pumpAndSettle();

      expect(find.textContaining('rien n’a été regardé'), findsOneWidget);
      expect(find.textContaining('Aucun nouvel événement'), findsNothing);
    });

    testWidgets('avec un modèle examiné, c’est le libellé du maître', (
      tester,
    ) async {
      // CONTRÔLE, et il n'est pas décoratif : sans lui, le cas ci-dessus
      // passerait aussi bien si l'écran affichait toujours la même phrase.
      // Ici le modèle est actif et détectable — il est réellement passé au
      // crible, ne trouve rien, et « rien à notifier » devient vrai.
      await dao.creerModele(
        declencheur: DeclencheurNotification.sejourDemain,
        canal: CanalNotification.whatsapp,
        contenuTemplate: 'Bonjour {client}.',
      );
      await monter(tester);

      await tester.tap(find.byKey(const Key('notifications-detecter')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Aucun nouvel événement'), findsOneWidget);
      expect(find.textContaining('rien n’a été regardé'), findsNothing);
    });
  });

  /* ================================================================== */
  group('Le RBAC', () {
    testWidgets('un rôle en LECTURE ne voit aucun geste d’écriture', (
      tester,
    ) async {
      // Premier niveau du RBAC seulement — il ne protège rien, il évite de
      // proposer ce qui serait refusé.
      await semerUnMessage();
      await monter(tester, droits: GardeAcces.depuisJson(const {'M12': 'L'}));

      expect(find.byKey(const Key('notifications-detecter')), findsNothing);
      expect(
        find.byKey(const Key('notifications-nouveau-modele')),
        findsNothing,
      );

      final message = (await dao.file()).single;
      expect(
        find.byKey(Key('notifications-transmis-${message.id}')),
        findsNothing,
      );
      expect(
        find.byKey(Key('notifications-abandonner-${message.id}')),
        findsNothing,
      );
    });

    testWidgets('« Exporter » reste offert en lecture seule', (tester) async {
      // Un export ne produit rien de neuf : il rend sur un autre papier ce que
      // l'écran affiche déjà.
      await monter(tester, droits: GardeAcces.depuisJson(const {'M12': 'L'}));

      expect(find.byKey(const Key('notifications-exporter')), findsOneWidget);
    });
  });

  /* ================================================================== */
  group('Ce que la vue ne porte pas n’est pas inventé', () {
    testWidgets('aucun panneau « Ce que la maquette prévoit » (retiré le '
        '09/10/2026)', (tester) async {
      await monter(tester);

      expect(find.byKey(const Key('notifications-absents')), findsNothing);
      expect(
        find.text('Ce que la maquette prévoit et qui n\'est pas rendu'),
        findsNothing,
      );
      expect(find.text('Export PDF'), findsNothing);
      expect(find.text('Aperçu avec une occurrence réelle'), findsNothing);
    });
  });

  /* ================================================================== */
  group('La bande d’indicateurs est repliable', () {
    const six = [
      'attente',
      'envoyes',
      'transmis',
      'abandonnes',
      'modeles',
      'canaux',
    ];

    testWidgets('elle s’ouvre dépliée, se replie, se déplie', (tester) async {
      await monter(tester);

      expect(find.text('Indicateurs des notifications'), findsOneWidget);
      for (final cle in six) {
        expect(find.byKey(Key('notifications-kpi-$cle')), findsOneWidget);
      }

      await tester.tap(find.byKey(const Key('notifications-kpis-bascule')));
      await tester.pumpAndSettle();

      // Replié : les six cartes disparaissent, le bandeau de bascule reste.
      for (final cle in six) {
        expect(
          find.byKey(Key('notifications-kpi-$cle')),
          findsNothing,
          reason: cle,
        );
      }
      expect(find.text('Indicateurs des notifications'), findsOneWidget);

      await tester.tap(find.byKey(const Key('notifications-kpis-bascule')));
      await tester.pumpAndSettle();

      for (final cle in six) {
        expect(find.byKey(Key('notifications-kpi-$cle')), findsOneWidget);
      }
    });

    testWidgets('l’aide « Repliez la bande… » est rendue à cette largeur', (
      tester,
    ) async {
      await monter(tester);

      expect(
        find.text('Repliez la bande pour gagner de la hauteur de tableau.'),
        findsOneWidget,
      );
    });
  });

  /* ================================================================== */
  group('Les onglets', () {
    testWidgets('l’actif est plein navy sans bordure, les autres blancs '
        'bordés', (tester) async {
      await monter(tester);

      BoxDecoration decoration(String onglet) =>
          tester
                  .widget<Container>(
                    find.descendant(
                      of: find.byKey(Key('notifications-onglet-$onglet')),
                      matching: find.byType(Container),
                    ),
                  )
                  .decoration!
              as BoxDecoration;

      expect(decoration('file').color, AppColors.navy);
      expect(decoration('file').border, isNull);
      expect(decoration('modeles').color, AppColors.neutre0);
      expect(decoration('modeles').border, isNotNull);

      await ouvrir(tester, 'modeles');

      expect(decoration('modeles').color, AppColors.navy);
      expect(decoration('modeles').border, isNull);
      expect(decoration('file').color, AppColors.neutre0);
    });
  });

  /* ================================================================== */
  group('Les tableaux', () {
    testWidgets('les en-têtes sont rendus en MAJUSCULES, et restent quand la '
        'liste est vide', (tester) async {
      await monter(tester);
      await ouvrir(tester, 'journal');

      // Le journal est vide : la vue pose son <thead> hors de la boucle, les
      // huit en-têtes existent quand même.
      expect(
        find.byKey(const Key('notifications-journal-vide')),
        findsOneWidget,
      );
      for (final colonne in [
        'DATE',
        'DESTINATAIRE',
        'DÉCLENCHEUR',
        'CANAL',
        'STATUT',
        'ENVOI SYSTÈME',
        'PAR',
        'COMMENTAIRE',
      ]) {
        expect(find.text(colonne), findsOneWidget, reason: colonne);
      }
      expect(find.text('Envoi système'), findsNothing);

      // La phrase de la vue, au mot, puis ce que la vue ne peut pas dire de
      // ce poste : aucun des quatre canaux n'a de transport.
      expect(
        find.text(
          'La colonne « Envoi système » dit « oui » uniquement pour un '
          'message que le transport a réellement accepté — WhatsApp, '
          'Android et SMS restent « non » tant qu’aucun n’est branché.',
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('notifications-journal-aucun-transport')),
        findsNothing,
      );
      expect(find.text('Journal — 0 message(s)'), findsOneWidget);
    });

    testWidgets('les Déclencheurs filtrés à vide gardent leurs en-têtes ET '
        'disent pourquoi', (tester) async {
      await monter(tester);
      await ouvrir(tester, 'declencheurs');

      await tester.enterText(
        find.byKey(const Key('notifications-recherche')),
        'zzz-introuvable',
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('notifications-declencheurs-vide')),
        findsOneWidget,
      );
      expect(find.text('Aucun déclencheur ne correspond.'), findsOneWidget);
      // Les en-têtes sont posés hors de la boucle, comme à la vue (l.394).
      expect(find.text('DÉCLENCHEUR'), findsOneWidget);
      expect(find.text('DÉTECTÉ SUR CE POSTE'), findsOneWidget);
    });

    testWidgets('l’onglet Déclencheurs porte ses six en-têtes en MAJUSCULES', (
      tester,
    ) async {
      await monter(tester);
      await ouvrir(tester, 'declencheurs');

      for (final colonne in [
        'DÉCLENCHEUR',
        'PUBLIC',
        'MODULE',
        'MODÈLES',
        'VARIABLES',
        'DÉTECTÉ SUR CE POSTE',
      ]) {
        expect(find.text(colonne), findsOneWidget, reason: colonne);
      }
    });
  });

  /* ================================================================== */
  group('Les filtres', () {
    testWidgets('la recherche réduit la file, et le vide le DIT', (
      tester,
    ) async {
      await semerUnMessage();
      await monter(tester);

      final message = (await dao.file()).single;
      expect(
        find.byKey(Key('notifications-message-${message.id}')),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const Key('notifications-recherche')),
        'zzz-introuvable',
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(Key('notifications-message-${message.id}')),
        findsNothing,
      );
      expect(find.byKey(const Key('notifications-file-vide')), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('notifications-recherche')),
        'KORA',
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(Key('notifications-message-${message.id}')),
        findsOneWidget,
      );
    });

    testWidgets('le filtre de canal écarte les messages des autres canaux', (
      tester,
    ) async {
      await semerUnMessage(); // WhatsApp
      await monter(tester);

      final message = (await dao.file()).single;
      expect(
        find.byKey(Key('notifications-message-${message.id}')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('notifications-filtre-canal')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('E-mail').last);
      await tester.pumpAndSettle();

      expect(
        find.byKey(Key('notifications-message-${message.id}')),
        findsNothing,
      );
    });
  });

  /* ================================================================== */
  group('« Exporter » ouvre la modale de la vue', () {
    Future<void> ouvrirModale(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('notifications-exporter')));
      await tester.pumpAndSettle();
    }

    testWidgets('titre « Exporter — <onglet> », deux formats, note du CSV', (
      tester,
    ) async {
      await monter(tester);
      await ouvrirModale(tester);

      expect(find.text('Exporter — File d’attente'), findsOneWidget);
      expect(find.text('Format du document'), findsOneWidget);
      expect(find.text('PDF Officiel A4 Imprimable'), findsOneWidget);
      expect(find.text('Tableur Excel (.xlsx / .csv)'), findsOneWidget);
      expect(find.text('Générer & Télécharger'), findsOneWidget);
      // Le PDF est produit depuis le 14/10/2026 : plus d'aide qui l'annonce
      // refusé, la note commune dit ce que produit le tableur.
      expect(find.byKey(const Key('export-note-csv')), findsOneWidget);
      expect(find.byKey(const Key('export-aide')), findsNothing);
    });

    testWidgets('le titre suit l’onglet affiché', (tester) async {
      await monter(tester);
      await ouvrir(tester, 'canaux');
      await ouvrirModale(tester);

      expect(find.text('Exporter — Canaux'), findsOneWidget);
    });

    testWidgets('choisir le PDF PRODUIT l’état A4 de l’onglet, enregistré '
        'en .pdf, et le toast le dit', (tester) async {
      final selecteur = SelecteurEssai();
      var appelsCsv = 0;
      await monter(
        tester,
        surcharges: [
          ...selecteur.surcharges,
          exporterNotificationsProvider.overrideWithValue(() async {
            appelsCsv++;
            return 'jamais.csv';
          }),
        ],
      );
      // Les canaux du poste sont toujours listés : l'onglet n'est pas vide.
      await ouvrir(tester, 'canaux');
      await ouvrirModale(tester);

      await tester.tap(find.text('PDF Officiel A4 Imprimable'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Générer & Télécharger'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('notifications-export-pdf-absent')),
        findsNothing,
      );
      expect(appelsCsv, 0, reason: 'le PDF ne passe pas par le tableur');
      expect(selecteur.ecrits, hasLength(1));
      final pdf = selecteur.ecrits.single;
      expect(pdf.type, TypeFichierEnregistre.pdf);
      expect(
        pdf.nom,
        matches(RegExp(r'^notifications_canaux_\d{4}-\d{2}-\d{2}\.pdf$')),
      );
      expect(pdf.estUnPdf, isTrue);
      expect(find.byKey(const Key('export-enregistre')), findsOneWidget);
    });

    testWidgets('le tableur écrit le CSV et AFFICHE le chemin', (tester) async {
      var appels = 0;
      await monter(
        tester,
        surcharges: [
          exporterNotificationsProvider.overrideWithValue(() async {
            appels++;
            return 'C:/export/notifications.csv';
          }),
        ],
      );
      await ouvrirModale(tester);

      // D434 : le PDF est présélectionné partout ; le tableur se choisit.
      await tester.tap(find.byKey(const Key('export-format-excel')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Générer & Télécharger'));
      await tester.pumpAndSettle();

      expect(appels, 1);
      // Le toast commun dit le NOM du fichier enregistré.
      expect(
        find.text('Export enregistré : notifications.csv'),
        findsOneWidget,
      );
    });

    testWidgets('une liste vide est REFUSÉE avec le message du maître', (
      tester,
    ) async {
      // Le vrai fournisseur, sur une file vide : il lève avant d'écrire.
      await monter(tester);
      await ouvrirModale(tester);

      await tester.tap(find.byKey(const Key('export-format-excel')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Générer & Télécharger'));
      await tester.pumpAndSettle();

      expect(
        find.text('Aucune ligne à exporter : la liste affichée est vide.'),
        findsOneWidget,
      );
    });
  });
}
