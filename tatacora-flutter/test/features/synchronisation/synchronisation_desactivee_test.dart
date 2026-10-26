import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/synchronisation/data/controle_coherence.dart';
import 'package:tatacora_flutter/features/synchronisation/data/descente_catalogue.dart';
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/data/service_appairage.dart';
import 'package:tatacora_flutter/features/synchronisation/data/service_suivi_postes.dart';
import 'package:tatacora_flutter/features/synchronisation/data/sync_manager.dart';
import 'package:tatacora_flutter/features/synchronisation/data/transport_synchronisation.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/appairage.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/bilan_synchronisation.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/voyant_synchronisation.dart';

import 'support/faux_transport.dart';
import 'support/scenario_file.dart';

/// L'INTERRUPTEUR « Synchronisation activée » : le poste est PLUS privilégié
/// que le serveur. Éteint, il travaille seul — AUCUNE requête réseau, la file
/// d'envoi continue de se remplir, et tout part, dans l'ordre, à la
/// réactivation.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late BancSync b;
  late AppDatabase db;

  /// Un transport qui LÈVE dès qu'on l'appelle : le moindre appel réseau
  /// fait échouer l'essai (et la requête est consignée).
  late FauxTransport interdit;

  setUp(() async {
    b = await BancSync.creer();
    db = AppDatabase.enMemoire();
    interdit = FauxTransport((r) => throw StateError('RÉSEAU : ${r.url}'));
    await b.ecrivain.enregistrerSynchronisationActivee(
      false,
      par: 'gerant',
      le: DateTime(2026, 10, 15),
    );
  });
  tearDown(() async {
    await db.close();
    await b.fermer();
  });

  SyncManager manager(TransportSynchronisation t) => SyncManager(
    dao: OperationsSyncDao(db, maintenant: () => b.maintenant),
    transport: t,
    urlServeur: BancSync.urlServeur,
    demonstration: false,
    lecteur: b.lecteur,
    ecrivain: b.ecrivain,
    maintenant: () => b.maintenant,
    descente: DescenteCatalogue(
      db: db,
      transport: t,
      auteur: () async => null,
      maintenant: () => b.maintenant,
    ),
  );

  test('l’interrupteur vit dans poste.json, activé par défaut, et la '
      'réactivation le retire', () async {
    final neuf = await BancSync.creer();
    addTearDown(neuf.fermer);
    expect(await neuf.lecteur.synchronisationActivee(), isTrue);

    expect(await b.lecteur.synchronisationActivee(), isFalse);
    final f = await b.fichier();
    expect(f['synchronisation_activee'], false);
    expect(f['synchronisation_desactivee_par'], 'gerant');
    expect(f['jeton_api'], isNotNull, reason: 'l’appairage est conservé');

    await b.ecrivain.enregistrerSynchronisationActivee(
      true,
      par: 'gerant',
      le: DateTime(2026, 10, 16),
    );
    expect(await b.lecteur.synchronisationActivee(), isTrue);
    expect((await b.fichier()).containsKey('synchronisation_activee'), isFalse);
    expect((await b.fichier())['jeton_api'], isNotNull);
  });

  test('DÉSACTIVÉE : une journée complète (vente, dépense, réservation, '
      'stock, paie…) se joue sans UNE requête, la file se remplit, puis la '
      'réactivation envoie TOUT dans l’ordre', () async {
    // 1. Le parcours complet, par les vrais écrivains.
    await jouerJourneeComplete(db);
    final dao = OperationsSyncDao(db, maintenant: () => b.maintenant);
    final avant = await dao.operations();
    expect(avant, isNotEmpty);
    expect(
      {for (final o in avant) o.statut},
      {StatutOperationSync.enAttente},
      reason: 'rien n’est parti : tout attend',
    );
    final tables = {for (final o in avant) o.table.nomServeur};
    expect(tables, containsAll(<String>['ventes', 'depenses', 'reservations']));

    // 2. Tous les chemins réseau du poste, interrupteur éteint.
    final m = manager(interdit);
    final bilan = await m.synchroniserMaintenant();
    expect(bilan.etat, EtatSynchronisation.desactivee);
    expect(await m.suivreDemandeDuServeur(), isFalse);
    final coherence = await ControleCoherence(
      db: db,
      transport: interdit,
      urlServeur: BancSync.urlServeur,
      lecteur: b.lecteur,
    ).controler(aujourdHui: DateTime(2026, 10, 22));
    expect(coherence, isA<CoherenceIndisponible>());
    final appairage = ServiceAppairage(
      transport: interdit,
      urlServeur: BancSync.urlServeur,
      lecteur: b.lecteur,
      ecrivain: b.ecrivain,
    );
    expect(
      await appairage.appairer(
        identifiant: 'a',
        motDePasse: 'b',
        nomPoste: 'POSTE',
      ),
      isA<AppairageRefuse>(),
    );
    expect(await appairage.testerConnexion(), TextesAppairage.desactivee);
    final suivi = ServiceSuiviPostes(
      transport: interdit,
      urlServeur: BancSync.urlServeur,
      lecteur: b.lecteur,
    );
    expect(await suivi.lire(), isA<SuiviPostesIndisponible>());
    expect(await suivi.demander(), isNull);
    expect(await suivi.revoquer('AUTRE'), ServiceSuiviPostes.desactivee);
    expect(interdit.requetes, isEmpty, reason: 'AUCUNE requête réseau');
    expect(
      {for (final o in await dao.operations()) o.statut},
      {StatutOperationSync.enAttente},
      reason: 'le passage n’a rien consommé',
    );

    // 3. Réactivation : tout part, dans l’ordre de la file (seq).
    await b.ecrivain.enregistrerSynchronisationActivee(
      true,
      par: 'gerant',
      le: DateTime(2026, 10, 16),
    );
    final serveur = FauxTransport(
      (r) => r.url.path.endsWith('/sync')
          ? reponseLot(r)
          : FauxCatalogue(const []).repondre(r),
    );
    final apres = await manager(serveur).synchroniserMaintenant();
    expect(apres.etat, EtatSynchronisation.termine);
    expect(apres.synchronisees, avant.length);
    expect(
      {for (final o in await dao.operations()) o.statut},
      {StatutOperationSync.synchronise},
    );
    expect(
      [for (final l in serveur.lots) ...l.uuids],
      [for (final o in avant) o.uuidOperation],
      reason: 'l’ordre d’enfilement est l’ordre d’envoi',
    );
    expect(serveur.descentes, isNotEmpty, reason: 'le poste rattrape');
  });

  test('le voyant dit « Synchronisation désactivée » (gris), avec le nombre '
      'd’opérations en attente', () {
    final v = voyantDe(
      interdite: false,
      appaire: true,
      refusJeton: false,
      desactivee: true,
      comptes: const {StatutOperationSync.enAttente: 4},
      bilan: null,
      enCours: false,
    );
    expect(v.teinte, TeinteVoyant.gris);
    expect(v.badge, 4);
    expect(v.phrase, contains('Synchronisation désactivée'));
    final vide = voyantDe(
      interdite: false,
      appaire: true,
      refusJeton: false,
      desactivee: true,
      comptes: const {},
      bilan: null,
      enCours: false,
    );
    expect(vide.phrase, TextesVoyant.desactivee);
    expect(vide.badge, isNull);
  });
}
