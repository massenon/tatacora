import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/bilan_synchronisation.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/cause_envoi.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';

import 'support/faux_transport.dart';

/// « AUCUNE OPÉRATION NE DOIT BLOQUER LA SYNCHRONISATION » (décision du PO du
/// 09/11/2026), côté POSTE : le moteur contre un faux serveur qui refuse, diffère ou
/// accepte chaque opération. Une opération refusée, différée (élément cité pas encore
/// reçu, erreur imprévue) ou réservée ne retient ni les autres opérations de la file,
/// ni celles du même lot, ni la descente ; ce qui dépend d'elle l'attend dans l'ordre ;
/// le poste ne reste pas en alerte ; « Renvoyer » la remet en file.
void main() {
  late BancSync b;

  setUp(() async => b = await BancSync.creer());
  tearDown(() => b.fermer());

  Map<String, Object?> rejet(
    Map<String, Object?> o,
    String code, {
    String motif = 'Refusée.',
  }) => {
    'uuid_operation': o['uuid_operation'],
    'statut': 'rejete',
    'entite_id': o['entite_id'],
    'motif': motif,
    'code_motif': code,
  };

  /// Un serveur qui rend [codes] (rang du client → code de rejet) et accepte le reste.
  FauxTransport serveur(List<String> ids, Map<int, String> codes) {
    return FauxTransport(
      (r) => reponseLot(
        r,
        particulier: (o) {
          final rang = ids.indexOf(o['entite_id']! as String);
          final code = codes[rang];
          return code == null ? null : rejet(o, code);
        },
      ),
    );
  }

  group('un rejet ne bloque rien d’autre que son propre élément', () {
    test('un refus au milieu du lot : les opérations d’AVANT et d’APRÈS passent, '
        'le bilan n’est PAS une alerte et le poste n’est pas en erreur '
        'permanente', () async {
      final ids = await b.enfilerClients(5);
      final t = serveur(ids, {2: 'regle_metier'});
      final bilan = await b.manager(t).synchroniserMaintenant();

      expect(bilan.etat, EtatSynchronisation.termine);
      expect((bilan.synchronisees, bilan.rejetees), (4, 1));
      expect(t.lots, hasLength(1), reason: 'un seul lot : rien n’a été rejoué');
      final c = await b.comptes();
      expect(c[StatutOperationSync.synchronise], 4);
      expect(c[StatutOperationSync.rejete], 1);

      // Le passage suivant n’a plus rien à envoyer : aucune boucle sur le refus.
      await b.manager(t).synchroniserMaintenant();
      expect(t.lots, hasLength(1));
    });

    test('un refus RÉSERVÉ (droit_manquant) est rejeté seul, lisiblement, '
        'renvoyable par tous ; les autres tables du lot passent', () async {
      final ids = await b.enfilerClients(3);
      final t = serveur(ids, {1: 'droit_manquant'});
      final bilan = await b.manager(t).synchroniserMaintenant();
      expect((bilan.synchronisees, bilan.rejetees), (2, 1));

      final refusee = await b.operationDe(ids[1]);
      expect(refusee.statut, StatutOperationSync.rejete);
      expect(renvoiOuvertATous(refusee), isTrue);
      final cause = causeDe(refusee, motif: 'Refusée.');
      expect(cause.titre, 'Opération réservée');
      expect(
        cause.conseil,
        isNot(contains('droit d’écrire dans ce module')),
        reason: 'plus la phrase d’un jugement par module',
      );
    });
  });

  group('une opération DIFFÉRÉE (dépendance, erreur imprévue) ne bloque rien', () {
    for (final code in ['dependance_manquante', 'erreur_serveur']) {
      test('$code : remise en file avec un repli de 30 s, jamais rejetée ; le '
          'lot et la file passent', () async {
        final ids = await b.enfilerClients(4);
        final t = serveur(ids, {1: code});
        final bilan = await b.manager(t).synchroniserMaintenant();

        expect(bilan.etat, EtatSynchronisation.termine);
        expect(
          (bilan.synchronisees, bilan.rejetees, bilan.differees),
          (3, 0, 1),
        );
        expect(
          bilan.prochaineTentative,
          b.maintenant.add(const Duration(seconds: 30)),
        );
        final op = await b.operationDe(ids[1]);
        expect(op.statut, StatutOperationSync.enAttente);
        expect(op.derniereErreur, 'Refusée.');
        expect(
          op.prochaineTentative,
          b.maintenant.add(const Duration(seconds: 30)),
        );
        expect((await b.comptes())[StatutOperationSync.rejete], 0);
      });
    }

    test('l’opération en repli ne retient PAS celles qui la suivent : une '
        'saisie faite après part tout de suite', () async {
      final ids = await b.enfilerClients(1);
      final t = serveur(ids, {0: 'dependance_manquante'});
      await b.manager(t).synchroniserMaintenant();
      expect(
        (await b.operationDe(ids[0])).statut,
        StatutOperationSync.enAttente,
      );

      // Une autre saisie, d’un AUTRE élément, arrive pendant le repli.
      final autres = await b.enfilerClients(2, prefixe: 'N');
      final avant = t.lots.length;
      await b.manager(t).synchroniserMaintenant();

      expect(t.lots, hasLength(avant + 1), reason: 'la nouvelle saisie part');
      expect(
        t.lots.last.uuids,
        hasLength(2),
        reason: 'seulement les deux nouvelles',
      );
      for (final id in autres) {
        expect(
          (await b.operationDe(id)).statut,
          StatutOperationSync.synchronise,
        );
      }
      expect(
        (await b.operationDe(ids[0])).statut,
        StatutOperationSync.enAttente,
        reason: 'son repli court encore',
      );
    });

    test('les opérations dépendantes (même élément) attendent DERRIÈRE, dans '
        'l’ordre, sans être rejetées ni bloquées : après le repli, la '
        'création puis la modification partent et passent', () async {
      final ids = await b.enfilerClients(1);
      await b.modifierClient(ids[0], 'Nom corrigé');

      var elementConnu = false;
      final t = FauxTransport(
        (r) => reponseLot(
          r,
          particulier: (o) {
            if (elementConnu) return null;
            // Le serveur ne connaît pas encore ce que la création cite : la création est
            // différée, et la modification du même élément attend derrière elle.
            return rejet(o, 'dependance_manquante');
          },
        ),
      );
      final m = b.manager(t);
      await m.synchroniserMaintenant();
      final ops = await b.dao.operations(entiteId: ids[0]);
      expect(ops.map((o) => o.statut).toList(), [
        StatutOperationSync.enAttente,
        StatutOperationSync.enAttente,
      ], reason: 'ni rejetée, ni bloquée : en file');

      // L’élément cité arrive ; le repli échoit.
      elementConnu = true;
      b.maintenant = b.maintenant.add(const Duration(seconds: 31));
      await m.synchroniserMaintenant();

      final apres = await b.dao.operations(entiteId: ids[0]);
      expect(apres.map((o) => o.statut).toList(), [
        StatutOperationSync.synchronise,
        StatutOperationSync.synchronise,
      ]);
      // Dans l’ordre d’écriture : la création, puis la modification.
      final vus = [
        for (final l in t.lots.skip(1))
          for (final o in l.operations) o['type'],
      ];
      expect(vus, ['creation', 'modification']);
    });

    test('un élément qui n’arrive jamais : huit essais puis un rejet LISIBLE '
        '(« À traiter »), renvoyable par tous, et « Renvoyer » remet l’opération '
        'en file', () async {
      final ids = await b.enfilerClients(1);
      var elementConnu = false;
      final t = FauxTransport(
        (r) => reponseLot(
          r,
          particulier: (o) => elementConnu
              ? null
              : rejet(
                  o,
                  'dependance_manquante',
                  motif:
                      'Séjour refusé : la réservation n’est pas connue du serveur.',
                ),
        ),
      );
      final m = b.manager(t);

      for (var i = 0; i < maxTentativesDifferees; i++) {
        await m.synchroniserMaintenant();
        b.maintenant = b.maintenant.add(const Duration(hours: 2));
      }
      final op = await b.operationDe(ids[0]);
      expect(t.lots, hasLength(maxTentativesDifferees));
      expect(
        op.statut,
        StatutOperationSync.rejete,
        reason: 'plus un report : un refus lisible',
      );
      expect(op.derniereErreur, contains('réservation'));
      expect(renvoiOuvertATous(op), isTrue);
      expect(
        causeDe(op, motif: op.derniereErreur!).titre,
        'Élément cité pas encore reçu',
      );

      // Plus aucune requête : le poste n’est pas en boucle ni en alerte permanente.
      final bilan = await m.synchroniserMaintenant();
      expect(bilan.etat, EtatSynchronisation.termine);
      expect(t.lots, hasLength(maxTentativesDifferees));

      // « Renvoyer » : l’élément est arrivé, la remplaçante passe.
      elementConnu = true;
      await b.dao.renvoyer(op.uuidOperation);
      await m.synchroniserMaintenant();
      final toutes = await b.dao.operations(entiteId: ids[0]);
      expect(toutes.last.statut, StatutOperationSync.synchronise);
      expect(
        toutes.first.statut,
        StatutOperationSync.rejete,
        reason: 'l’historique reste',
      );
    });
  });

  group(
    '« Renvoyer » : l’opération repart, et ce qui était bloqué derrière aussi',
    () {
      test('un rejet bloque la modification du même élément ; « Renvoyer » la '
          'création, une fois acceptée, DÉBLOQUE la modification d’elle-même, '
          'sans geste d’administrateur', () async {
        final ids = await b.enfilerClients(1);
        await b.modifierClient(ids[0], 'Nom corrigé');
        var accepte = false;
        final t = FauxTransport(
          (r) => reponseLot(
            r,
            particulier: (o) => accepte || o['type'] != 'creation'
                ? null
                : rejet(o, 'droit_manquant'),
          ),
        );
        // Lots d'UNE opération : la création part seule, son rejet bloque la suivante.
        final m = b.manager(t, tailleLot: 1);
        await m.synchroniserMaintenant();

        var ops = await b.dao.operations(entiteId: ids[0]);
        expect(ops.map((o) => o.statut).toList(), [
          StatutOperationSync.rejete,
          StatutOperationSync.bloque,
        ]);

        // Le geste « Renvoyer » (ouvert à tous pour ce code) ; le serveur accepte désormais.
        accepte = true;
        expect(renvoiOuvertATous(ops.first), isTrue);
        await b.dao.renvoyer(ops.first.uuidOperation);
        await m.synchroniserMaintenant();
        // Le passage suivant emporte la modification libérée.
        await m.synchroniserMaintenant();

        ops = await b.dao.operations(entiteId: ids[0]);
        expect(ops.map((o) => o.statut).toList(), [
          StatutOperationSync.rejete,
          StatutOperationSync.synchronise,
          StatutOperationSync.synchronise,
        ], reason: 'plus rien de bloqué, aucun « Débloquer » nécessaire');
        expect((await b.comptes())[StatutOperationSync.bloque], 0);
      });
    },
  );

  test('les codes différés sont ceux du SERVEUR (registre relu du PHP)', () {
    expect(codesRejetDiffere, {'dependance_manquante', 'erreur_serveur'});
    expect(codesRenvoiOuvertATous, {
      'droit_manquant',
      'dependance_manquante',
      'erreur_serveur',
    });
  });
}
