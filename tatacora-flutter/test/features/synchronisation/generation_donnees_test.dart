import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/config/environnement.dart';
import 'package:tatacora_flutter/features/synchronisation/data/descente_catalogue_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/data/transport_synchronisation.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/bilan_synchronisation.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/voyant_synchronisation.dart';
import 'package:tatacora_flutter/features/transverse/data/reinitialisation_locale.dart';

import 'support/faux_transport.dart';

/// La GÉNÉRATION des données (décision du PO du 19/10/2026 : essais en
/// production, puis réinitialisation sur le web ET les postes). Le poste
/// retient la génération du serveur, la rappelle à chaque envoi ; un serveur
/// réinitialisé depuis refuse (409) : la file d'essai reste INTACTE ici,
/// plus rien ne part ni n'arrive, et la remise à neuf du poste s'ouvre —
/// même en build de production — pour repartir sur la génération nouvelle.
void main() {
  late BancSync b;

  setUp(() async => b = await BancSync.creer());
  tearDown(() => b.fermer());

  const g0 = 'generation-avant';
  const g1 = 'generation-apres';

  DescenteCatalogueDao etat() => DescenteCatalogueDao(b.db);

  FauxTransport serveur({
    required String generation,
    bool refuse = false,
    bool phaseEssais = false,
  }) => FauxTransport((r) {
    // Comme le serveur : une génération ABSENTE (poste neuf ou
    // réinitialisé) est acceptée, une autre est refusée.
    final rappelee = r.corps?['generation'];
    if (refuse && rappelee != null && rappelee != generation) {
      return ReponseHttp(
        statut: 409,
        corps: {
          'code': 'generation_perimee',
          'generation': generation,
          'reinitialisee_le': '2026-10-19T08:00:00+00:00',
        },
        entetes: {enteteGeneration: generation},
      );
    }
    final ok = reponseLot(r);
    return ReponseHttp(
      statut: ok.statut,
      corps: ok.corps,
      entetes: {
        enteteGeneration: generation,
        'x-tatacora-phase-essais': phaseEssais ? '1' : '0',
      },
    );
  });

  test('un poste neuf ADOPTE la génération du serveur, puis la rappelle à '
      'chaque envoi', () async {
    await b.enfilerClients(1);
    final t = serveur(generation: g0);
    expect(
      (await b.manager(t).synchroniserMaintenant()).etat,
      EtatSynchronisation.termine,
    );
    expect(t.requetes.single.corps!.containsKey('generation'), isFalse);
    expect(await etat().generation(), g0);

    await b.enfilerClients(1);
    await b.manager(t).synchroniserMaintenant();
    expect(t.requetes.last.corps!['generation'], g0);

    // La phase d'essais annoncée par le serveur est retenue, puis oubliée
    // quand il ne l'annonce plus.
    expect(await etat().phaseEssaisServeur(), isFalse);
    await b.enfilerClients(1);
    await b
        .manager(serveur(generation: g0, phaseEssais: true))
        .synchroniserMaintenant();
    expect(await etat().phaseEssaisServeur(), isTrue);
    await b.enfilerClients(1);
    await b.manager(t).synchroniserMaintenant();
    expect(await etat().phaseEssaisServeur(), isFalse);

    // Une génération différente dans une réponse n'est JAMAIS adoptée en
    // silence : seule la première est retenue.
    await etat().retenirGeneration('autre');
    expect(await etat().generation(), g0);
  });

  test('serveur réinitialisé depuis : 409, la file reste INTACTE, l’état est '
      'consigné, plus aucune requête ; le voyant passe au rouge', () async {
    await etat().retenirGeneration(g0);
    await b.enfilerClients(3);
    final t = serveur(generation: g1, refuse: true);

    final bilan = await b.manager(t).synchroniserMaintenant();
    expect(bilan.etat, EtatSynchronisation.serveurReinitialise);
    expect(t.requetes, hasLength(1));
    expect(t.requetes.single.corps!['generation'], g0);
    expect((await b.comptes())[StatutOperationSync.enAttente], 3);
    expect(
      await etat().reinitialisationServeur(),
      DateTime.utc(2026, 10, 19, 8).toLocal(),
    );

    final encore = await b.manager(t).synchroniserMaintenant();
    expect(encore.etat, EtatSynchronisation.serveurReinitialise);
    expect(t.requetes, hasLength(1));
    expect(await b.manager(t).suivreDemandeDuServeur(), isFalse);
    expect(t.requetes, hasLength(1));

    final voyant = voyantDe(
      interdite: false,
      appaire: true,
      refusJeton: false,
      serveurReinitialise: true,
      comptes: await b.comptes(),
      bilan: bilan,
      enCours: false,
    );
    expect(voyant.teinte, TeinteVoyant.rouge);
    expect(voyant.phrase, TextesVoyant.serveurReinitialise);
  });

  test('la remise à neuf du poste s’ouvre alors MÊME en production et '
      'bascule fermée ; elle oublie la génération et la file d’essai, et '
      'le poste repart sur la nouvelle', () async {
    await b.semerAuteur();
    await etat().retenirGeneration(g0);
    await b.enfilerClients(2);
    final moteur = ReinitialisationLocale(
      b.db,
      environnement: Environnement.production,
    );

    // Avant la réinitialisation du serveur : la production refuse.
    await expectLater(
      moteur.executer(role: 'administrateur'),
      throwsA(
        isA<ReinitialisationRefusee>().having(
          (e) => e.message,
          'message',
          RefusReinitialisation.production,
        ),
      ),
    );
    expect((await b.comptes())[StatutOperationSync.enAttente], 2);

    // Le serveur a été réinitialisé : le refus 409 est constaté.
    await b
        .manager(serveur(generation: g1, refuse: true))
        .synchroniserMaintenant();
    expect(await moteur.reinitialisationServeur(), isNotNull);

    // Le rôle reste exigé.
    await expectLater(
      moteur.executer(role: 'caissier'),
      throwsA(isA<ReinitialisationRefusee>()),
    );

    await moteur.executer(role: 'administrateur');
    expect((await b.comptes()).values.fold<int>(0, (a, v) => a + v), 0);
    expect(await etat().generation(), isNull);
    expect(await moteur.reinitialisationServeur(), isNull);

    // Il repart : adopte la génération nouvelle.
    await b.enfilerClients(1);
    final t = serveur(generation: g1, refuse: true);
    expect(
      (await b.manager(t).synchroniserMaintenant()).etat,
      EtatSynchronisation.termine,
    );
    expect(await etat().generation(), g1);
  });
}
