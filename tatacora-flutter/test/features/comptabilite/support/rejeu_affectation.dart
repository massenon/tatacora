import 'dart:convert';

import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/comptabilite/data/affectation_resultat_locale.dart';
import 'package:tatacora_flutter/features/comptabilite/data/cloture_exercice_locale.dart';
import 'package:tatacora_flutter/features/comptabilite/data/comptabilite_dao.dart';
import 'package:tatacora_flutter/features/comptabilite/data/moteur_comptable.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/affectation_resultat.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/entities/comptabilite.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/etats_financiers.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/forme_juridique.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/montant_comptable.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/refus_comptable.dart';
import 'package:drift/drift.dart' show Value;

import 'outils_comptabilite.dart';

/// Le REJEU d'un scénario d'affectation du résultat sur le POSTE — le pendant de
/// `tool/comptabilite/rejouer_affectation.php` (le vrai serveur), partagé par les
/// tests qui confrontent le poste à ce script (09/11/2026).
///
/// Chaque événement du scénario JSON est joué par les vraies classes du poste
/// (`MoteurComptable`, `ClotureExerciceLocale`, `AffectationResultatLocale`) et rend
/// le MÊME dictionnaire que le script PHP, pour que le test compare les deux sorties
/// clé par clé. L'horloge du poste est UNE variable (événement `horloge`) : le jour
/// de la contre-passation se pose dans le scénario.
typedef Ev = Map<String, Object?>;

Ev evPiece(
  String journal,
  String date,
  String libelle,
  List<(String, String?, String?, String?)> lignes, {
  String? ref,
}) => {
  't': 'piece',
  'journal': journal,
  'date': date,
  'libelle': libelle,
  'valide': true,
  'ref': ?ref,
  'lignes': [
    for (final (compte, debit, credit, centre) in lignes)
      {'compte': compte, 'debit': ?debit, 'credit': ?credit, 'centre': ?centre},
  ],
};

Ev evGeste(String action, int annee, {String? motif, String? role}) => {
  't': 'geste',
  'action': action,
  'annee': annee,
  'motif': ?motif,
  'role': ?role,
};

Ev evAffecter(
  int annee,
  String date,
  Map<String, String> ventilation, {
  String? role,
}) => {
  't': 'affecter',
  'annee': annee,
  'date': date,
  'ventilation': ventilation,
  'role': ?role,
};

Ev evContrepasser(int annee, String motif, {String? role, String? reference}) =>
    {
      't': 'contrepasser_affectation',
      'annee': annee,
      'motif': motif,
      'reference': ?reference,
      'role': ?role,
    };

Ev evCarte(int annee, {String? role}) => {
  't': 'etat_affectation',
  'annee': annee,
  'role': ?role,
};

Ev evForme(String valeur) => {'t': 'forme', 'valeur': valeur};

Ev evHorloge(String date) => {'t': 'horloge', 'date': date};

Ev evContrepasserPiece(String ref) => {'t': 'contrepasser_piece', 'ref': ref};

/// Ce que le rejeu rend : la base du poste, son DAO et un dictionnaire par événement.
final class RejeuPoste {
  RejeuPoste(this.db, this.dao, this.sortie);

  final AppDatabase db;
  final ComptabiliteDao dao;
  final List<Map<String, Object?>> sortie;
}

/// Joue [scenario] sur un poste neuf daté de 15/06/2031 ; [anneesAvant] sont les
/// exercices à ouvrir en plus de celui de 2031 (semé par l'installation du référentiel).
Future<RejeuPoste> rejouerSurLePoste(
  List<Ev> scenario, {
  List<int> anneesAvant = const [2029, 2030],
}) async {
  var courant = DateTime(2031, 6, 15, 10);
  final db = await baseInstallee(maintenant: DateTime(2031, 6, 15));
  final dao = ComptabiliteDao(db);
  for (final annee in anneesAvant) {
    await dao.insererExercice(
      annee: annee,
      dateDebut: '$annee-01-01',
      dateFin: '$annee-12-31',
    );
  }
  await db
      .into(db.utilisateursLocal)
      .insert(
        UtilisateursLocalCompanion.insert(
          id: 'u-admin',
          login: 'admin-essai',
          nom: 'Administrateur',
          role: 'administrateur',
          droitsJson: '{}',
          sel: 's',
          empreinte: 'e',
          iterations: 1,
          dateCreation: DateTime(2026, 10, 1),
          dateMotDePasse: DateTime(2026, 10, 1),
        ),
      );
  DateTime maintenant() => courant;
  final moteur = MoteurComptable(dao, maintenant: maintenant);
  final service = ClotureExerciceLocale(db, moteur, maintenant: maintenant);
  final affectation = AffectationResultatLocale(
    db,
    moteur,
    maintenant: maintenant,
  );

  final centres = {for (final c in await dao.centres()) c.libelle: c.id};
  Future<String> exerciceDe(int annee) async =>
      (await dao.exerciceDeLAnnee(annee))!.id;
  Future<Map<String, String>> statuts() async => {
    for (final e in await dao.exercices()) '${e.annee}': e.statut.valeur,
  };
  String auteurDe(Object? role) =>
      (role ?? 'comptable') == 'comptable' ? auteurEssai : 'u-admin';
  final piecesPosees = <String, List<EcritureComptable>>{};

  final sortie = <Map<String, Object?>>[];
  for (final ev in scenario) {
    try {
      switch (ev['t']) {
        case 'piece':
          final posee = await moteur.passerEtValider(
            DemandePiece(
              journal: ev['journal']! as String,
              date: ev['date']! as String,
              libelle: ev['libelle']! as String,
              lignes: [
                for (final l in ev['lignes']! as List)
                  LigneDemandee(
                    compte: (l as Map)['compte'] as String,
                    debitCentimes: centimesDepuisChaine(
                      (l['debit'] as String?) ?? '',
                    ),
                    creditCentimes: centimesDepuisChaine(
                      (l['credit'] as String?) ?? '',
                    ),
                    centreId: centres[l['centre']],
                  ),
              ],
            ),
            auteurId: auteurEssai,
          );
          if (ev['ref'] != null) piecesPosees['${ev['ref']}'] = posee;
          sortie.add({'ok': true});
        case 'contrepasser_piece':
          await moteur.contrepasserPiece(
            piecesPosees['${ev['ref']}']!,
            auteurId: auteurEssai,
            motif: 'Annulation',
          );
          sortie.add({'ok': true});
        case 'forme':
          await db
              .into(db.parametresSystemeLocal)
              .insertOnConflictUpdate(
                ParametresSystemeLocalCompanion(
                  cle: const Value(cleFormeJuridique),
                  valeur: Value('${ev['valeur']}'),
                  modifieLe: Value(courant),
                ),
              );
          sortie.add({'ok': true, 'forme': (await affectation.forme()).code});
        case 'horloge':
          courant = DateTime.parse('${ev['date']} 10:00:00');
          sortie.add({'ok': true});
        case 'geste':
          final id = await exerciceDe(ev['annee']! as int);
          final auteur = auteurDe(ev['role']);
          final apres = switch (ev['action']) {
            'demarrer' => await service.demarrer(id, auteurId: auteur),
            'cloturer' => (await dao.exercice(
              (await service.cloturer(id, auteurId: auteur)).exerciceId,
            ))!,
            'rouvrir' => await service.rouvrir(
              id,
              auteurId: auteur,
              motif: (ev['motif'] as String?) ?? '',
            ),
            _ => throw StateError('geste inconnu'),
          };
          final c = await service.clotureActive(apres.id);
          sortie.add({
            'ok': true,
            'statut': apres.statut.valeur,
            'cloture': c == null
                ? null
                : {
                    'piece_cloture': c.pieceCloture,
                    'piece_a_nouveaux': c.pieceANouveaux,
                    'resultat': chaineDepuisCentimes(c.resultatCentimes),
                  },
            'statuts': await statuts(),
          });
        case 'affecter':
          final annee = ev['annee']! as int;
          final piece = await affectation.affecter(
            await exerciceDe(annee),
            ventilation: ventilationDepuisSaisie({
              for (final e in (ev['ventilation']! as Map).entries)
                '${e.key}': '${e.value}',
            }),
            date: ev['date']! as String,
            auteurId: auteurDe(ev['role']),
          );
          sortie.add({'ok': true, 'piece': piece});
        case 'contrepasser_affectation':
          await affectation.contrepasser(
            await exerciceDe(ev['annee']! as int),
            auteurId: auteurDe(ev['role']),
            motif: (ev['motif'] as String?) ?? '',
            reference: ev['reference'] as String?,
          );
          sortie.add({'ok': true});
        case 'etat_affectation':
          final e = await affectation.etat(
            await exerciceDe(ev['annee']! as int),
          );
          final estComptable = auteurDe(ev['role']) == auteurEssai;
          sortie.add(
            e == null
                ? {'ok': true, 'carte': false}
                : {
                    'ok': true,
                    'carte': true,
                    'annee': e.annee,
                    'annee_affectation': e.anneeAffectation,
                    'resultat': chaineDepuisCentimes(e.resultatCentimes),
                    'est_benefice': e.estBenefice,
                    'compte_resultat': e.compteResultat,
                    'affectable': e.affectable,
                    'active_piece': e.active?.numeroPiece,
                    'date_par_defaut': e.dateParDefaut,
                    'proposition': {
                      for (final p in postesAffectation)
                        p: chaineDepuisCentimes(e.proposition[p] ?? 0),
                    },
                    'reserve_legale_proposee': e.reserveLegalePropose,
                    'plafond_atteint': e.plafondReserveLegaleAtteint,
                    'peut_affecter': estComptable,
                    'forme': e.forme.code,
                    'est_societe': e.forme.estSociete,
                    'postes': e.postes,
                    'poste_du_reste': e.posteDuReste,
                    'alertes': e.alertes,
                    'avertissements': e.avertissements,
                  },
          );
        case 'etat':
          final e = await service.etat(await exerciceDe(ev['annee']! as int));
          sortie.add({
            'ok': true,
            'blocages': [for (final b in e.blocages) b.code],
            'avertissements': [for (final a in e.avertissements) a.code],
            'conditions_reunies': e.conditionsReunies,
            'resultat_a_reporter': chaineDepuisCentimes(
              e.resultatAReporterCentimes,
            ),
            'compte_destination': e.compteDeDestination,
            'statut': e.statut,
          });
        case 'bilan':
          final annee = ev['annee']! as int;
          final b = bilanDe(annee, await service.donneesDesEtats());
          sortie.add({
            'ok': true,
            'equilibre': b.equilibre,
            'ecart': chaineDepuisCentimes(b.ecartCentimes),
            'total_actif': chaineDepuisCentimes(b.totalActifCentimes),
            'total_passif': chaineDepuisCentimes(b.totalPassifCentimes),
            'resultat_exercice': chaineDepuisCentimes(
              b.resultatExerciceCentimes,
            ),
            'resultat_reporte': chaineDepuisCentimes(b.resultatReporteCentimes),
            'hors_rubrique': [
              for (final c in b.comptesHorsRubrique) c.numeroCompte,
            ],
            'passif': [
              for (final p in b.passif)
                {'code': p.code, 'net': chaineDepuisCentimes(p.netCentimes)},
            ],
          });
        case 'balance':
          final annee = ev['annee']! as int;
          final b = balanceDe(annee, await service.donneesDesEtats());
          sortie.add({
            'ok': true,
            'a_nouveaux_provisoires_de': b.aNouveauxProvisoiresDe,
            'lignes': [
              for (final l in b.lignes)
                {
                  'numero_compte': l.numeroCompte,
                  'libelle': l.libelle,
                  'classe': l.classe,
                  'debit': chaineDepuisCentimes(l.debitCentimes),
                  'credit': chaineDepuisCentimes(l.creditCentimes),
                },
            ],
          });
        case 'instantane':
          final lignes = <String, List<Map<String, Object?>>>{};
          for (final e in await dao.exercices()) {
            lignes['${e.annee}'] = [
              for (final l in await dao.lignesPourArchive(e.id))
                {
                  'journal': l.codeJournal,
                  'numero_piece': l.numeroPiece,
                  'date': l.dateEcriture,
                  'compte': l.numeroCompte,
                  'centre': l.libelleCentre,
                  'libelle': l.libelle,
                  'debit': chaineDepuisCentimes(l.debitCentimes),
                  'credit': chaineDepuisCentimes(l.creditCentimes),
                  'statut': l.statut,
                  'contrepasse': l.pieceContrepassee != null,
                },
            ];
          }
          sortie.add({
            'ok': true,
            'statuts': await statuts(),
            'lignes': lignes,
          });
      }
    } on RefusComptable catch (e) {
      sortie.add({'refus': true, 'message': e.message});
    }
  }
  return RejeuPoste(db, dao, sortie);
}

/// La clé qui compare deux lignes de journal (journal, pièce, date, compte, centre,
/// montants, statut, libellé).
String cleLigne(Map<String, Object?> l) =>
    '${l['journal']}|${l['numero_piece'] ?? ''}|${l['date']}|${l['compte']}|'
    '${l['centre']}|${l['debit']}|${l['credit']}|${l['statut']}|'
    '${l['contrepasse']}|${l['libelle']}';

/// Le scénario sérialisé, pour les messages d'échec.
String texte(Object? o) => jsonEncode(o);
