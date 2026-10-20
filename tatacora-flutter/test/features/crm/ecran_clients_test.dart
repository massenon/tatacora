import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/impression/entete_etablissement.dart';
import 'package:tatacora_flutter/core/theme/app_colors.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/crm/domain/entities/client.dart';
import 'package:tatacora_flutter/features/crm/domain/entities/registre_clients.dart';
import 'package:tatacora_flutter/features/crm/impression/etat_clients.dart';
import 'package:tatacora_flutter/features/crm/presentation/ecran_clients.dart';
import 'package:tatacora_flutter/features/facturation/domain/creances.dart';
import 'package:tatacora_flutter/features/facturation/domain/entities/piece_facturation.dart';
import 'package:tatacora_flutter/features/facturation/domain/messages_encaissement.dart';

import '../comptabilite/support/outils_comptabilite.dart' show exerciceClos;
import '../facturation/support/outils_encaissement.dart';

/// L'écran Clients & Créances — ses quatre onglets, et le geste « Recouvrement ».
///
/// ## Ce que ces cas protègent
///
/// **Que le solde affiché soit celui qui est calculé (le reste dû des factures),
/// que le geste d'encaissement le fasse BAISSER pour de bon, et que ce qui n'a
/// pas de source soit dit.** Deux onglets et trois cartes ne sont pas rendus,
/// chacun pour une raison nommée : sans ces cas, quelqu'un les « compléterait »
/// en inventant une relance ou un zéro.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = await baseEncaissement();
  });

  tearDown(() => db.close());

  Future<void> monter(
    WidgetTester tester, {
    Map<String, String> droits = const {'M3': 'C', 'M2': 'C'},
  }) async {
    tester.view
      ..physicalSize = const Size(1600, 2400)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: surchargesEncaissement(db, droits: droits),
        child: MaterialApp(
          theme: AppTheme.clair,
          home: const Scaffold(body: EcranClients()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  String texte(WidgetTester tester, Key cle) =>
      tester.widget<Text>(find.byKey(cle)).data!;

  /* ================================================================== */
  group('L’écran', () {
    testWidgets('un registre vide le DIT', (tester) async {
      // Un écran qui ne rend jamais rien passe pour cassé (leçon PA-90).
      await monter(tester);

      expect(find.byKey(const Key('clients-registre-vide')), findsOneWidget);
    });

    testWidgets('le solde vient du CALCUL des factures, jamais de la colonne '
        '`solde`', (tester) async {
      // `clients_local.solde` vaut 0 pour tout le monde : rien ne l'écrit.
      // L'afficher donnerait un zéro plausible sur la fiche d'un débiteur.
      final c = await creerClient(db);
      await emettreFacture(db, montant: 50000, clientId: c.id);

      await monter(tester);

      expect(find.byKey(Key('clients-ligne-${c.id}')), findsOneWidget);
      expect(texte(tester, Key('clients-solde-${c.id}')), '50 000 FCFA');
    });

    testWidgets('un séjour ou une consommation NON facturés ne sont PAS une '
        'créance', (tester) async {
      // Le serveur ne connaît pas cette grandeur : une réservation à reste à
      // payer est une avance à encaisser, pas une facture impayée.
      final c = await creerClient(db);
      await semerReservation(db, id: 'r1', clientId: c.id, total: 80000);

      await monter(tester);

      expect(texte(tester, Key('clients-solde-${c.id}')), '—');
      expect(find.byKey(Key('clients-recouvrement-${c.id}')), findsNothing);
    });

    testWidgets('les colonnes sont CELLES DE LA VUE : plus de « Séjours » ni de '
        '« Consommations », une ancienneté', (tester) async {
      // En-têtes en capitales : la vue les met en `uppercase` (CSS), le client
      // n'a pas de transformation de texte.
      await creerClient(db);
      await monter(tester);

      expect(find.text('SOLDE DÛ'), findsOneWidget);
      expect(find.text('PIÈCES'), findsOneWidget);
      expect(find.text('ANCIENNETÉ'), findsOneWidget);
      expect(find.text('SÉJOURS'), findsNothing);
      expect(find.text('CONSOMMATIONS'), findsNothing);
    });

    testWidgets('l’ancienneté est celle de la plus ancienne facture impayée', (
      tester,
    ) async {
      final c = await creerClient(db);
      await emettreFacture(
        db,
        clientId: c.id,
        horloge: DateTime(2026, 9, 1, 15),
      );

      await monter(tester);

      // Du 01/09 au 12/10/2026 : 41 jours.
      expect(texte(tester, Key('clients-anciennete-${c.id}')), '41 j');
    });

    testWidgets(
      'un client sans dette rend « — » à l’ancienneté, jamais « 0 j »',
      (tester) async {
        final c = await creerClient(db);
        await monter(tester);

        expect(texte(tester, Key('clients-anciennete-${c.id}')), '—');
      },
    );

    testWidgets('les onglets relances et avances sont CLIQUABLES et DISENT ce '
        'qui n’a pas de source', (tester) async {
      await monter(tester);

      for (final (cle, tableau) in const [
        ('relances', 'clients-relances-tableau'),
        ('avances', 'clients-avances-tableau'),
      ]) {
        await tester.tap(find.byKey(Key('clients-onglet-$cle')));
        await tester.pumpAndSettle();

        expect(find.byKey(Key(tableau)), findsOneWidget);
        // Le corps dit que la donnée n'a pas de source ici : « Aucune créance »
        // affirmerait que personne ne doit rien.
        expect(
          find.textContaining('ne figurent pas sur ce poste'),
          findsWidgets,
        );
        expect(find.textContaining('Aucune créance en cours'), findsNothing);
      }

      await tester.tap(find.byKey(const Key('clients-onglet-clients')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('clients-registre-vide')), findsOneWidget);
    });

    testWidgets('la carte sans source rend « — », jamais « 0 »', (
      tester,
    ) async {
      await monter(tester);

      // « Clients à relancer » : aucun historique de relances (M12 est vide).
      expect(
        find.descendant(
          of: find.byKey(const Key('clients-kpi-4')),
          matching: find.text('—'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('les deux tranches de la balance âgée rendent « — » à zéro, '
        'jamais « 0 FCFA » (`formatOuTiret`)', (tester) async {
      await monter(tester);

      for (final i in [1, 2]) {
        expect(
          find.descendant(
            of: find.byKey(Key('clients-kpi-$i')),
            matching: find.text('—'),
          ),
          findsOneWidget,
        );
      }
    });

    testWidgets('« Dont + de 90 jours » et « 0 à 30 jours » lisent la balance '
        'âgée, en rouge pour les créances douteuses', (tester) async {
      final c = await creerClient(db);
      await emettreFacture(
        db,
        montant: 7000,
        clientId: c.id,
        horloge: DateTime(2026, 6, 1, 9), // 133 jours
      );
      await emettreFacture(
        db,
        montant: 2500,
        clientId: c.id,
        horloge: DateTime(2026, 10, 1, 9), // 11 jours
      );
      await monter(tester);

      expect(
        find.descendant(
          of: find.byKey(const Key('clients-kpi-1')),
          matching: find.text('7 000 FCFA'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('clients-kpi-2')),
          matching: find.text('2 500 FCFA'),
        ),
        findsOneWidget,
      );
      final valeur = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('clients-kpi-1')),
          matching: find.text('7 000 FCFA'),
        ),
      );
      expect(valeur.style!.color, AppColors.erreur);
    });

    testWidgets(
      '« Créances totales » et « Encaissé sur 30 j » ont une source',
      (tester) async {
        final c = await creerClient(db);
        final f = await emettreFacture(db, montant: 50000, clientId: c.id);
        await ouvrirCaissePour(db);
        await paiementsDaoSur(db).encaisser(
          pieceId: f.id,
          montant: '20000',
          mode: 'especes',
          auteurId: caissierEssai,
        );

        await monter(tester);

        expect(
          find.descendant(
            of: find.byKey(const Key('clients-kpi-0')),
            matching: find.text('30 000 FCFA'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('clients-kpi-3')),
            matching: find.text('20 000 FCFA'),
          ),
          findsOneWidget,
        );
        expect(find.text('1 pièce(s) · 1 client(s)'), findsOneWidget);
      },
    );

    testWidgets('« Encaissé sur 30 j » ne compte NI un encaissement annulé NI '
        'un encaissement plus ancien', (tester) async {
      final c = await creerClient(db);
      final f = await emettreFacture(db, montant: 90000, clientId: c.id);
      await ouvrirCaissePour(db);
      final dao = paiementsDaoSur(db);
      final ancien = paiementsDaoSur(db, horloge: DateTime(2026, 8, 1, 10));
      await ancien.encaisser(
        pieceId: f.id,
        montant: '1000',
        mode: 'especes',
        auteurId: caissierEssai,
      );
      final annule = await dao.encaisser(
        pieceId: f.id,
        montant: '4000',
        mode: 'especes',
        auteurId: caissierEssai,
      );
      await dao.annuler(annule.id, 'Doublon', auteurId: caissierEssai);
      await dao.encaisser(
        pieceId: f.id,
        montant: '2000',
        mode: 'carte',
        auteurId: caissierEssai,
      );

      await monter(tester);

      expect(
        find.descendant(
          of: find.byKey(const Key('clients-kpi-3')),
          matching: find.text('2 000 FCFA'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('un client saisi au comptoir n’annonce AUCUNE attente', (
      tester,
    ) async {
      // ⚠ Ce cas vérifiait l'inverse : le badge « en attente de
      // synchronisation », qui disait alors quelque chose de VRAI — les
      // clients partaient réellement au serveur, à la différence d'un panier
      // (PA-98).
      //
      // Zéro réseau (14/09/2026) : plus de file, plus de départ. Le même badge
      // annoncerait désormais une attente que rien ne viendra lever — l'exact
      // défaut PA-59/60/61 —, et c'est pourquoi `ClientDao` écrit `local`.
      final c = await creerClient(db);
      await monter(tester);

      expect(find.byKey(Key('clients-attente-${c.id}')), findsNothing);
      expect(
        find.textContaining('en attente de synchronisation'),
        findsNothing,
      );
    });

    testWidgets('la recherche filtre la liste', (tester) async {
      await creerClient(db, nom: 'KORA', telephone: '97111111');
      await creerClient(db, nom: 'DOSSOU', telephone: '96222222');
      await monter(tester);

      await tester.enterText(
        find.byKey(const Key('clients-recherche')),
        'dossou',
      );
      await tester.pumpAndSettle();

      expect(find.text('DOSSOU'), findsOneWidget);
      expect(find.text('KORA'), findsNothing);
    });

    testWidgets('« Débiteurs uniquement » écarte les clients à jour', (
      tester,
    ) async {
      final debiteur = await creerClient(db, nom: 'KORA');
      final ajour = await creerClient(db, nom: 'DOSSOU', telephone: '96222222');
      await emettreFacture(db, clientId: debiteur.id);
      await monter(tester);

      await tester.tap(find.byKey(const Key('clients-filtre-etat')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(EtatCreance.debiteur.libelle).last);
      await tester.pumpAndSettle();

      expect(find.byKey(Key('clients-ligne-${debiteur.id}')), findsOneWidget);
      expect(find.byKey(Key('clients-ligne-${ajour.id}')), findsNothing);
    });

    testWidgets('un rôle en LECTURE ne voit pas « Nouveau client »', (
      tester,
    ) async {
      // Premier niveau du RBAC seulement : le serveur refuse de toute façon,
      // et un client refusé ferait rejeter la réservation qui le référence.
      await monter(tester, droits: const {'M3': 'L'});

      expect(find.byKey(const Key('clients-nouveau')), findsNothing);
    });
  });

  /* ================================================================== */
  group('L’onglet « Suivi des dettes »', () {
    Future<void> ouvrirOnglet(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('clients-onglet-dettes')));
      await tester.pumpAndSettle();
    }

    testWidgets('sans créance : les en-têtes de la vue ET la phrase « tous les '
        'clients sont à jour »', (tester) async {
      await monter(tester);
      await ouvrirOnglet(tester);

      expect(find.byKey(const Key('clients-dettes-tableau')), findsOneWidget);
      for (final t in [
        'CLIENT',
        '0 À 30 JOURS',
        '31 À 60 JOURS',
        '61 À 90 JOURS',
        'PLUS DE 90 JOURS',
        'TOTAL DÛ',
      ]) {
        expect(
          find.descendant(
            of: find.byKey(const Key('clients-dettes-tableau')),
            matching: find.text(t),
          ),
          findsOneWidget,
          reason: t,
        );
      }
      expect(
        texte(tester, const Key('clients-dettes-vide')),
        'Aucune créance en cours. Tous les clients sont à jour.',
      );
      // La phrase de refus d'avant est FAUSSE depuis que la source existe.
      expect(find.textContaining('ne figurent pas sur ce poste'), findsNothing);
      expect(find.byKey(const Key('clients-dettes-total')), findsNothing);
    });

    testWidgets('chaque facture impayée tombe dans SA tranche, les montants '
        'nuls sont des tirets, le pied additionne', (tester) async {
      final k = await creerClient(db, nom: 'KORA');
      final y = await creerClient(db, nom: 'YAYI', telephone: '96000000');
      await emettreFacture(
        db,
        montant: 30000,
        clientId: k.id,
        horloge: DateTime(2026, 10, 1, 9), // 11 jours
      );
      await emettreFacture(
        db,
        montant: 10000,
        clientId: k.id,
        horloge: DateTime(2026, 9, 1, 9), // 41 jours
      );
      await emettreFacture(
        db,
        montant: 7000,
        clientId: y.id,
        horloge: DateTime(2026, 6, 1, 9), // 133 jours
      );
      await monter(tester);
      await ouvrirOnglet(tester);

      String ligne(String clientId) => tester
          .widgetList<Text>(
            find.descendant(
              of: find.byKey(Key('clients-dette-$clientId')),
              matching: find.byType(Text),
            ),
          )
          .map((t) => t.data)
          .join(' | ');

      // Les plus gros débiteurs d'abord.
      expect(
        ligne(k.id),
        'KORA | 30 000 FCFA | 10 000 FCFA | — | — | 40 000 FCFA',
      );
      expect(ligne(y.id), 'YAYI | — | — | — | 7 000 FCFA | 7 000 FCFA');
      expect(
        tester
            .widgetList<Text>(
              find.descendant(
                of: find.byKey(const Key('clients-dettes-total')),
                matching: find.byType(Text),
              ),
            )
            .map((t) => t.data)
            .join(' | '),
        'Total | 30 000 FCFA | 10 000 FCFA | — | 7 000 FCFA | 47 000 FCFA',
      );
      expect(
        tester.getTopLeft(find.byKey(Key('clients-dette-${k.id}'))).dy,
        lessThan(
          tester.getTopLeft(find.byKey(Key('clients-dette-${y.id}'))).dy,
        ),
      );
    });

    testWidgets('un encaissement fait BAISSER la tranche, et la recherche ne '
        'filtre que le corps (pas le pied de la bande)', (tester) async {
      final k = await creerClient(db, nom: 'KORA');
      final y = await creerClient(db, nom: 'YAYI', telephone: '96000000');
      final f = await emettreFacture(
        db,
        montant: 30000,
        clientId: k.id,
        horloge: DateTime(2026, 10, 1, 9),
      );
      await emettreFacture(
        db,
        montant: 7000,
        clientId: y.id,
        horloge: DateTime(2026, 6, 1, 9),
      );
      await ouvrirCaissePour(db);
      await paiementsDaoSur(db).encaisser(
        pieceId: f.id,
        montant: '12000',
        mode: 'especes',
        auteurId: caissierEssai,
      );
      await monter(tester);
      await ouvrirOnglet(tester);

      expect(
        find.descendant(
          of: find.byKey(Key('clients-dette-${k.id}')),
          matching: find.text('18 000 FCFA'),
        ),
        findsWidgets,
      );

      await tester.enterText(find.byKey(const Key('clients-recherche')), 'kor');
      await tester.pumpAndSettle();

      expect(find.byKey(Key('clients-dette-${k.id}')), findsOneWidget);
      expect(find.byKey(Key('clients-dette-${y.id}')), findsNothing);
      // La carte « + de 90 jours » est calculée sur la balance COMPLÈTE.
      expect(
        find.descendant(
          of: find.byKey(const Key('clients-kpi-1')),
          matching: find.text('7 000 FCFA'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('clients-kpi-2')),
          matching: find.text('18 000 FCFA'),
        ),
        findsOneWidget,
      );
    });
  });

  /* ================================================================== */
  group('Le bouton « Recouvrement »', () {
    Future<Client> debiteur() async {
      final c = await creerClient(db);
      await emettreFacture(db, montant: 50000, clientId: c.id);
      return c;
    }

    testWidgets('existe pour un client qui doit, avec M3 ET M2 en écriture', (
      tester,
    ) async {
      final c = await debiteur();
      await monter(tester);

      expect(find.byKey(Key('clients-recouvrement-${c.id}')), findsOneWidget);
      expect(find.text('Recouvrement'), findsOneWidget);
    });

    testWidgets('n’existe PAS pour un client qui ne doit rien', (tester) async {
      final c = await creerClient(db);
      await monter(tester);

      expect(find.byKey(Key('clients-recouvrement-${c.id}')), findsNothing);
    });

    testWidgets('n’existe PAS sans l’écriture sur M2 : le serveur exige les '
        'deux droits', (tester) async {
      final c = await debiteur();
      await monter(tester, droits: const {'M3': 'C', 'M2': 'L'});

      expect(find.byKey(Key('clients-recouvrement-${c.id}')), findsNothing);
    });

    testWidgets('n’existe PAS sans l’écriture sur M3', (tester) async {
      final c = await debiteur();
      await monter(tester, droits: const {'M3': 'L', 'M2': 'C'});

      expect(find.byKey(Key('clients-recouvrement-${c.id}')), findsNothing);
    });

    testWidgets('n’existe PAS pour un client dont la facture est SOLDÉE', (
      tester,
    ) async {
      final c = await creerClient(db);
      final f = await emettreFacture(db, montant: 5000, clientId: c.id);
      await ouvrirCaissePour(db);
      await paiementsDaoSur(db).encaisser(
        pieceId: f.id,
        montant: '5000',
        mode: 'especes',
        auteurId: caissierEssai,
      );
      await monter(tester);

      expect(find.byKey(Key('clients-recouvrement-${c.id}')), findsNothing);
      expect(texte(tester, Key('clients-solde-${c.id}')), '—');
    });
  });

  /* ================================================================== */
  group('Le geste d’encaissement, de bout en bout', () {
    Future<Client> debiteurAvecCaisse({bool caisse = true}) async {
      final c = await creerClient(db);
      await emettreFacture(db, montant: 50000, clientId: c.id);
      if (caisse) await ouvrirCaissePour(db);
      return c;
    }

    Future<void> ouvrirModale(WidgetTester tester, Client c) async {
      await tester.tap(find.byKey(Key('clients-recouvrement-${c.id}')));
      await tester.pumpAndSettle();
    }

    Future<void> saisir(WidgetTester tester, String montant) async {
      await tester.enterText(
        find.byKey(const Key('recouvrement-montant')),
        montant,
      );
      await tester.pump();
    }

    Future<void> enregistrer(WidgetTester tester) async {
      await tester.ensureVisible(
        find.byKey(const Key('recouvrement-enregistrer')),
      );
      await tester.tap(find.byKey(const Key('recouvrement-enregistrer')));
      await tester.pumpAndSettle();
    }

    testWidgets('la modale porte les mots de la vue, le client, le reste dû '
        'pré-rempli et l’avertissement', (tester) async {
      final c = await debiteurAvecCaisse();
      await monter(tester);
      await ouvrirModale(tester, c);

      expect(find.text('Ajouter un recouvrement'), findsOneWidget);
      expect(texte(tester, const Key('recouvrement-client')), 'KORA');
      // Chaque libellé porte son astérisque rouge (`<span class="text-red-500">*`),
      // d'où la lecture du texte RICHE.
      expect(
        find.textContaining('Pièce réglée', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('Montant reçu (FCFA)', findRichText: true),
        findsOneWidget,
      );
      expect(find.textContaining('Mode', findRichText: true), findsWidgets);
      expect(find.text('Enregistrer le recouvrement'), findsOneWidget);
      expect(find.text('Annuler'), findsOneWidget);
      expect(
        texte(tester, const Key('recouvrement-avertissement')),
        'Un montant supérieur au reste dû est refusé.',
      );
      // `$this->recouvrementMontant = $factures[0]['reste']` : « 50000.00 ».
      final champ = tester.widget<TextField>(
        find.byKey(const Key('recouvrement-montant')),
      );
      expect(champ.controller!.text, '50000.00');
      // La facture proposée porte son reste dû.
      expect(find.textContaining('— dû 50 000 FCFA'), findsWidgets);
    });

    testWidgets('« Référence » et « Commentaire » ne sont PAS rendus : le '
        'serveur jette leur saisie', (tester) async {
      final c = await debiteurAvecCaisse();
      await monter(tester);
      await ouvrirModale(tester, c);

      expect(find.text('Référence'), findsNothing);
      expect(find.text('Commentaire'), findsNothing);
    });

    testWidgets(
      'encaisser FAIT BAISSER le solde, écrit la pièce et alimente le '
      'tableau des recouvrements',
      (tester) async {
        final c = await debiteurAvecCaisse();
        await monter(tester);

        await ouvrirModale(tester, c);
        await saisir(tester, '20000');
        await enregistrer(tester);

        // La modale est fermée, le message du serveur est dit.
        expect(find.byKey(const Key('modale-recouvrement')), findsNothing);
        expect(
          find.text('Recouvrement de 20 000 FCFA enregistré pour KORA.'),
          findsOneWidget,
        );
        // Le solde a BAISSÉ : c'était l'objet du lot.
        expect(texte(tester, Key('clients-solde-${c.id}')), '30 000 FCFA');

        // Et l'argent a sa pièce comptable.
        expect(await compterLignes(db, 'paiements_facture_local'), 1);
        expect(await compterLignes(db, 'ecritures_local'), 2);

        await tester.tap(find.byKey(const Key('clients-onglet-avances')));
        await tester.pumpAndSettle();
        expect(find.text('Recouvrements encaissés (1)'), findsOneWidget);
        final p = (await paiementsDaoSur(db).paiements()).single;
        expect(
          find.byKey(Key('clients-recouvrement-ligne-${p.id}')),
          findsOneWidget,
        );
        expect(find.text('KORA'), findsWidgets);
        expect(find.text('Espèces'), findsOneWidget);
        expect(find.text('20 000 FCFA'), findsWidgets);
        expect(find.text('compta-$caissierEssai'), findsOneWidget);
      },
    );

    testWidgets('un sur-encaissement est refusé SOUS le montant, la modale '
        'reste ouverte et rien n’est écrit', (tester) async {
      final c = await debiteurAvecCaisse();
      await monter(tester);

      await ouvrirModale(tester, c);
      await saisir(tester, '60000');
      await enregistrer(tester);

      expect(find.byKey(const Key('modale-recouvrement')), findsOneWidget);
      expect(
        texte(tester, const Key('recouvrement-refus')),
        MessagesEncaissement.superieurAuReste('50000.00'),
      );
      expect(await compterLignes(db, 'paiements_facture_local'), 0);
      expect(await compterLignes(db, 'ecritures_local'), 0);
      // La saisie est toujours là, corrigeable.
      final champ = tester.widget<TextField>(
        find.byKey(const Key('recouvrement-montant')),
      );
      expect(champ.controller!.text, '60000');
    });

    testWidgets('une caisse fermée est dite sous le montant aussi', (
      tester,
    ) async {
      final c = await debiteurAvecCaisse(caisse: false);
      await monter(tester);

      await ouvrirModale(tester, c);
      await enregistrer(tester);

      expect(
        texte(tester, const Key('recouvrement-refus')),
        MessagesEncaissement.caisseFermee,
      );
      expect(await compterLignes(db, 'paiements_facture_local'), 0);
    });

    testWidgets('un montant nul affiche la clé de langue du serveur, telle '
        'quelle', (tester) async {
      final c = await debiteurAvecCaisse();
      await monter(tester);

      await ouvrirModale(tester, c);
      await saisir(tester, '0');
      await enregistrer(tester);

      // `validation.gt.numeric` n'existe pas dans lang/fr/validation.php : le
      // serveur rend la clé. Défaut du serveur répliqué (D233), pas corrigé.
      expect(
        texte(tester, const Key('recouvrement-refus')),
        'validation.gt.numeric',
      );
    });

    testWidgets('changer de pièce re-remplit le montant du reste dû de la '
        'nouvelle pièce', (tester) async {
      final c = await creerClient(db);
      await emettreFacture(
        db,
        montant: 50000,
        clientId: c.id,
        horloge: DateTime(2026, 9, 1, 9),
      );
      await emettreFacture(
        db,
        montant: 12000,
        clientId: c.id,
        horloge: DateTime(2026, 10, 1, 9),
      );
      await ouvrirCaissePour(db);
      await monter(tester);
      await ouvrirModale(tester, c);

      // La plus ANCIENNE d'abord (`orderBy date_emission`).
      var champ = tester.widget<TextField>(
        find.byKey(const Key('recouvrement-montant')),
      );
      expect(champ.controller!.text, '50000.00');

      await tester.tap(find.byKey(const Key('recouvrement-piece')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('— dû 12 000 FCFA').last);
      await tester.pumpAndSettle();

      champ = tester.widget<TextField>(
        find.byKey(const Key('recouvrement-montant')),
      );
      expect(champ.controller!.text, '12000.00');
    });

    testWidgets('une pièce comptable refusée emporte l’encaissement : le motif '
        'comptable est dit, rien n’est écrit', (tester) async {
      // Référentiel installé en 2025 : pas d'exercice 2026.
      await db.close();
      db = await baseEncaissement(maintenant: DateTime(2025, 6, 1));
      // Et l'exercice du jour est CLÔTURÉ (manquant, il s'ouvrirait de lui-même
      // depuis le 20/10/2026).
      await exerciceClos(db, jourEncaissement.year);
      final c = await debiteurAvecCaisse();
      await monter(tester);

      await ouvrirModale(tester, c);
      await saisir(tester, '1000');
      await enregistrer(tester);

      expect(find.byKey(const Key('modale-recouvrement')), findsOneWidget);
      expect(find.byKey(const Key('recouvrement-refus')), findsOneWidget);
      expect(await compterLignes(db, 'paiements_facture_local'), 0);
      expect(await compterLignes(db, 'ecritures_local'), 0);
      expect(texte(tester, Key('clients-solde-${c.id}')), '50 000 FCFA');
    });

    testWidgets('« Annuler » ferme la modale sans rien écrire', (tester) async {
      final c = await debiteurAvecCaisse();
      await monter(tester);
      await ouvrirModale(tester, c);

      await tester.tap(find.byKey(const Key('caisse-annuler')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('modale-recouvrement')), findsNothing);
      expect(await compterLignes(db, 'paiements_facture_local'), 0);
    });
  });

  /* ================================================================== */
  group('Le tableau « Recouvrements encaissés »', () {
    testWidgets('sans encaissement : il le DIT, avec un compte vrai', (
      tester,
    ) async {
      await monter(tester);
      await tester.tap(find.byKey(const Key('clients-onglet-avances')));
      await tester.pumpAndSettle();

      expect(find.text('Recouvrements encaissés (0)'), findsOneWidget);
      expect(
        find.byKey(const Key('clients-recouvrements-vide')),
        findsOneWidget,
      );
    });

    testWidgets(
      'un encaissement ANNULÉ y figure sans marque, comme au serveur',
      (tester) async {
        final c = await creerClient(db);
        final f = await emettreFacture(db, montant: 9000, clientId: c.id);
        await ouvrirCaissePour(db);
        final dao = paiementsDaoSur(db);
        final p = await dao.encaisser(
          pieceId: f.id,
          montant: '3000',
          mode: 'mobile_money',
          auteurId: caissierEssai,
        );
        await dao.annuler(p.id, 'Doublon', auteurId: caissierEssai);

        await monter(tester);
        await tester.tap(find.byKey(const Key('clients-onglet-avances')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(Key('clients-recouvrement-ligne-${p.id}')),
          findsOneWidget,
        );
        expect(find.text('Mobile Money'), findsOneWidget);
        // L'annulé ne diminue plus le solde : la facture est de nouveau due.
        await tester.tap(find.byKey(const Key('clients-onglet-clients')));
        await tester.pumpAndSettle();
        expect(texte(tester, Key('clients-solde-${c.id}')), '9 000 FCFA');
      },
    );

    testWidgets('N° et Référence portent les huit premiers caractères de '
        'l’identifiant', (tester) async {
      final c = await creerClient(db);
      final f = await emettreFacture(db, montant: 9000, clientId: c.id);
      await ouvrirCaissePour(db);
      final p = await paiementsDaoSur(db).encaisser(
        pieceId: f.id,
        montant: '3000',
        mode: 'virement',
        auteurId: caissierEssai,
      );

      await monter(tester);
      await tester.tap(find.byKey(const Key('clients-onglet-avances')));
      await tester.pumpAndSettle();

      expect(find.text(p.numeroCourt), findsNWidgets(2));
    });
  });

  /* ================================================================== */
  group('L’export', () {
    final kora = Client(
      id: 'c1',
      nom: 'KORA',
      telephone: '97111111',
      type: TypeClientReferentiel.particulier,
    );

    test('le CSV porte le filtre ET la définition du solde', () async {
      // « L'export porte sur ce qui est affiché » (PA-119), et un état de
      // créances remis sans la définition de son solde servirait à relancer
      // des clients qui ont peut-être déjà payé.
      final registre = composerRegistre(
        clients: [kora],
        creances: const <CreanceFacture>[],
      );

      final csv = EtatClients.csv(registre, filtre: 'Débiteurs uniquement');

      expect(csv.startsWith('﻿'), isTrue, reason: 'BOM UTF-8 (RG-19)');
      expect(csv, contains('Débiteurs uniquement'));
      expect(csv, contains('après déduction des avoirs'));
      // L'ancienne mention est FAUSSE depuis le premier encaissement.
      expect(csv, isNot(contains('ne sont pas déduits')));
      expect(csv, contains('KORA'));
      expect(csv, contains('Client;Telephone;Type;Solde du;Pieces'));
      expect(csv, isNot(contains('Sejours')));
    });

    test('le CSV écrit le solde en nombre brut à deux décimales', () async {
      final f = PieceFacturation(
        id: 'f1',
        numero: 'F-2026-1',
        origine: OrigineFacture.factureDirecte,
        dateEmission: DateTime(2026, 10, 1),
        clientNom: 'KORA',
        statut: StatutPiece.emise,
        clientId: 'c1',
        lignes: [
          LigneFacture(
            id: 'l1',
            module: ModuleFacturable.m5Bar,
            libelle: 'x',
            prixUnitaire: 12500,
            quantite: 1,
            ordre: 0,
          ),
        ],
      );
      final registre = composerRegistre(
        clients: [kora],
        creances: composerCreances(
          pieces: [f],
          paiements: const [],
          acomptesParReservation: const {},
        ),
      );

      final csv = EtatClients.csv(registre, filtre: 'Tous les clients');

      // Un tableur ne sait pas additionner « 12 500 FCFA ».
      expect(csv, contains('KORA;97111111;Particulier;12500.00;1;'));
    });

    test('le PDF se compose réellement, en-tête comprise', () async {
      final registre = composerRegistre(
        clients: [kora],
        creances: const <CreanceFacture>[],
      );

      final octets = await EtatClients.pdf(
        registre,
        filtre: 'Tous les clients',
        entete: const EnteteEtablissement(),
      );

      // Un document composé, pas seulement un objet construit : c'est la
      // composition qui lève sur un glyphe absent de la police.
      expect(octets.length, greaterThan(1000));
    });
  });
}
