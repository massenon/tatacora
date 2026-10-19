import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/notifications/data/notifications_dao.dart';
import 'package:tatacora_flutter/features/notifications/domain/entities/canal_notification.dart';
import 'package:tatacora_flutter/features/notifications/domain/entities/declencheur_notification.dart';
import 'package:tatacora_flutter/features/synchronisation/data/aligneur_catalogue.dart';
import 'package:tatacora_flutter/features/synchronisation/data/descente_catalogue_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/descente_catalogue.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';

/// Lot 10f : un modèle de notification part avec son état entier ; celui du
/// serveur descend, apparié par son couple (événement, canal), sans écraser
/// une retouche locale qui attend de partir.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.enMemoire());
  tearDown(() => db.close());

  Future<IssueAlignement> descendre(
    String id,
    Map<String, Object?> donnees, {
    bool actif = true,
  }) => db.transaction(
    () =>
        AligneurCatalogue(
          db,
          DescenteCatalogueDao(db),
          auteur: () async => null,
        ).aligner(
          ElementCatalogue(
            table: TableDescendue.modelesNotification,
            id: id,
            actif: actif,
            modifieLe: '2026-10-18 10:00:00',
            donnees: donnees,
          ),
        ),
  );

  Future<String> poser() async => (await NotificationsDao(db).creerModele(
    declencheur: DeclencheurNotification.sejourDemain,
    canal: CanalNotification.whatsapp,
    contenuTemplate: 'Bonjour {client}',
  )).id;

  test('créer puis basculer part au serveur, état entier', () async {
    final id = await poser();
    await NotificationsDao(db).basculerActivation(id);

    final ops = await OperationsSyncDao(
      db,
    ).operations(table: TableSynchronisee.modelesNotification);
    expect(ops.map((o) => o.type), [
      TypeOperationSync.creation,
      TypeOperationSync.modification,
    ]);
    expect(jsonDecode(ops.last.payload), {
      'evenement': 'sejour_demain',
      'canal': 'whatsapp',
      'objet': null,
      'contenu_template': 'Bonjour {client}',
      'actif': false,
    });
  });

  test('le modèle du serveur s’apparie par son couple, rien ne repart ; '
      'une retouche en attente est gardée', () async {
    final id = await poser();
    expect(
      await descendre('srv-1', {
        'evenement': 'sejour_demain',
        'canal': 'whatsapp',
        'contenu_template': 'Texte du serveur',
      }),
      isA<ConserveLocalement>(),
    );

    await db.customStatement(
      "UPDATE operations_sync_local SET statut = 'synchronise'",
    );
    expect(
      await descendre('srv-1', {
        'evenement': 'sejour_demain',
        'canal': 'whatsapp',
        'contenu_template': 'Texte du serveur',
      }, actif: false),
      isA<Aligne>(),
    );
    final m = (await NotificationsDao(
      db,
    ).parCouple('sejour_demain', 'whatsapp'))!;
    expect((m.id, m.contenuTemplate, m.actif), (id, 'Texte du serveur', false));
    expect(
      await DescenteCatalogueDao(db).idLocal('modeles_notification', 'srv-1'),
      id,
    );
    expect(
      await OperationsSyncDao(
        db,
      ).operations(statut: StatutOperationSync.enAttente),
      isEmpty,
    );
  });
}
