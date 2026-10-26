import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../synchronisation/domain/operation_sync.dart';
import '../../synchronisation/presentation/providers_synchronisation.dart';
import '../../../core/di/providers.dart';
import '../../transverse/data/configuration_poste.dart';
import '../data/comptabilite_dao.dart' show ComptabiliteDao;
import '../data/ecritures_serveur_dao.dart';
import '../../tableau_de_bord/domain/indicateurs_locaux.dart' show ChargeDatee;
import '../domain/entities/comptabilite.dart';
import '../domain/etats_financiers.dart';
import 'providers_comptabilite.dart';
import 'providers_consultation_comptable.dart';

/// D'OÙ viennent les chiffres du compte de résultat et du bilan.
///
///  * [miroirDuServeur] : les écritures validées de TOUS les postes, reçues du
///    serveur (le serveur est le comptable de l'entreprise) ;
///  * [piecesDuPoste] : les écritures validées PASSÉES PAR CE POSTE. C'est la
///    source quand la synchronisation est désactivée, ou que rien n'a encore
///    été reçu du serveur : le poste est opérationnel sans lui, ses états
///    financiers aussi. Jamais mêlée à l'autre (le serveur passe sa propre
///    pièce pour chaque document reçu : additionner compterait chaque vente
///    deux fois).
enum SourceEtatsFinanciers { miroirDuServeur, piecesDuPoste }

final sourceEtatsFinanciersProvider =
    FutureProvider.autoDispose<SourceEtatsFinanciers>(
      (ref) => lireSourceEtats(ref),
    );

/// L'interrupteur de synchronisation, lu du fichier du poste. Illisible :
/// réputé ACTIVÉ (le comportement d'avant l'interrupteur).
Future<bool> _synchronisationActivee(Ref ref) async {
  try {
    return await LecteurConfigurationPoste(
      chemin: ref.read(cheminConfigurationPosteProvider),
    ).synchronisationActivee();
  } on Object {
    return true;
  }
}

/// Le choix de la source, hors de tout fournisseur `autoDispose` : un lecteur
/// qui n'en est pas un (le tableau de bord, le pilotage) l'appelle sans que
/// son `Ref` ne soit libéré en cours de route.
Future<SourceEtatsFinanciers> lireSourceEtats(Ref ref) async {
  final recu = await EcrituresServeurDao(
    ref.read(baseLocaleProvider),
  ).reception();
  // Rien reçu du serveur : les pièces du poste, sans autre question.
  if (recu.nombre == 0) return SourceEtatsFinanciers.piecesDuPoste;
  return await _synchronisationActivee(ref)
      ? SourceEtatsFinanciers.miroirDuServeur
      : SourceEtatsFinanciers.piecesDuPoste;
}

/// Les écritures VALIDÉES du poste d'une année d'exercice, au format du
/// miroir : le même calcul (`etats_financiers.dart`) sert les deux sources.
List<EcritureServeur> ecrituresValideesDuPoste(
  DonneesComptabilite d,
  ExerciceComptable exercice,
) {
  final codes = {for (final j in d.journaux) j.id: j.code};
  return [
    for (final e in d.ecritures)
      if (e.exerciceId == exercice.id && e.estValidee)
        EcritureServeur(
          annee: exercice.annee,
          codeJournal: codes[e.journalId] ?? '',
          numeroCompte: d.comptes[e.compteId]?.numero ?? e.compteId,
          libelleCompte: d.comptes[e.compteId]?.libelle ?? '',
          classe: d.comptes[e.compteId]?.classe ?? '',
          debitCentimes: e.debitCentimes,
          creditCentimes: e.creditCentimes,
        ),
  ];
}

/// Ce que lisent le compte de résultat et le bilan du poste : les écritures
/// VALIDÉES reçues du serveur, par année, et le statut de chaque exercice.
/// Relu à chaque visite, aucun cache (LECTURE seule).
final donneesEtatsFinanciersProvider = FutureProvider.autoDispose<DonneesEtats>(
  (ref) => lireDonneesEtats(ref),
);

/// Les données des états, d'après la source choisie — hors de tout
/// fournisseur `autoDispose` (voir [lireSourceEtats]).
Future<DonneesEtats> lireDonneesEtats(Ref ref) async {
  if (await lireSourceEtats(ref) == SourceEtatsFinanciers.piecesDuPoste) {
    return lireDonneesEtatsDuPoste(ref);
  }
  final dao = ref.read(comptabiliteDaoProvider);
  final miroir = EcrituresServeurDao(ref.read(baseLocaleProvider));
  final exercices = await dao.exercices();
  return DonneesEtats(
    ecrituresParAnnee: {
      for (final e in exercices) e.annee: await miroir.deLAnnee(e.annee),
    },
    statutParAnnee: {for (final e in exercices) e.annee: e.statut},
    plan: await _planDeReport(dao),
  );
}

Future<Map<String, CompteDeReport>> _planDeReport(ComptabiliteDao dao) async {
  final plan = <String, CompteDeReport>{};
  for (final numero in const ['131', '139']) {
    final c = await dao.compteParNumero(numero);
    if (c != null) {
      plan[numero] = CompteDeReport(libelle: c.libelle, classe: c.classe);
    }
  }
  return plan;
}

/// Les mêmes données, tirées des écritures VALIDÉES PASSÉES PAR CE POSTE
/// (`ecritures_local`) : la source quand la synchronisation est désactivée ou
/// que rien n'a été reçu du serveur, et celle du grand livre et du report à
/// nouveau, qui se lisent toujours sur les pièces du poste.
final donneesEtatsDuPosteProvider = FutureProvider.autoDispose<DonneesEtats>(
  (ref) => lireDonneesEtatsDuPoste(ref),
);

Future<DonneesEtats> lireDonneesEtatsDuPoste(Ref ref) async {
  final dao = ref.read(comptabiliteDaoProvider);
  final poste = await lireDonneesComptabilite(dao);
  return DonneesEtats(
    ecrituresParAnnee: {
      for (final e in poste.exercices)
        e.annee: ecrituresValideesDuPoste(poste, e),
    },
    statutParAnnee: {for (final e in poste.exercices) e.annee: e.statut},
    plan: await _planDeReport(dao),
    anneesAvecClotureActive: await dao.anneesAvecClotureActive(),
  );
}

/// D'où viennent les chiffres, pour le dire sous les états : ce que ce poste
/// a reçu du serveur, et ce qu'il n'a pas encore envoyé (ces opérations n'ont
/// pas encore leur pièce au serveur, donc pas leur écriture ici).
final class ProvenanceEtatsFinanciers {
  const ProvenanceEtatsFinanciers({
    required this.reception,
    required this.enAttenteDEnvoi,
    this.source = SourceEtatsFinanciers.miroirDuServeur,
  });

  final SourceEtatsFinanciers source;

  final ReceptionEcrituresServeur reception;
  final int enAttenteDEnvoi;
}

final provenanceEtatsFinanciersProvider =
    FutureProvider.autoDispose<ProvenanceEtatsFinanciers>((ref) async {
      final comptes = await ref
          .watch(operationsSyncDaoProvider)
          .compteParStatut();
      return ProvenanceEtatsFinanciers(
        source: await ref.watch(sourceEtatsFinanciersProvider.future),
        reception: await EcrituresServeurDao(
          ref.watch(baseLocaleProvider),
        ).reception(),
        enAttenteDEnvoi:
            (comptes[StatutOperationSync.enAttente] ?? 0) +
            (comptes[StatutOperationSync.enCours] ?? 0),
      );
    });

/// L'exercice [annee] est-il équilibré (balance ET bilan) ? `true` tant que le
/// poste n'a rien reçu : un zéro égale un zéro, et l'encadré rouge du hub
/// (`indicateurs->equilibre`) ne s'allume que sur un écart réel.
final comptabiliteEquilibreeProvider = FutureProvider.autoDispose
    .family<bool, int>((ref, annee) async {
      final d = await ref.watch(donneesEtatsFinanciersProvider.future);
      return comptabiliteEquilibree(annee, d);
    });

/// Les six indicateurs du bandeau du hub, d'un exercice — calculés sur la
/// source des états financiers (pièces du poste ou miroir du serveur).
final indicateursComptablesProvider = FutureProvider.autoDispose
    .family<IndicateursEtat, int>((ref, annee) async {
      final d = await ref.watch(donneesEtatsFinanciersProvider.future);
      return indicateursDe(annee, d);
    });

/// Les écritures validées de classe 6 (charges), datées — « Dépenses cumulées »
/// du tableau de bord et sa courbe. Même source que les états financiers :
/// les écritures du serveur quand la synchronisation est active et qu'elles
/// sont arrivées, sinon les pièces de CE poste.
Future<List<ChargeDatee>> lireChargesDatees(Ref ref) async {
  if (await lireSourceEtats(ref) == SourceEtatsFinanciers.miroirDuServeur) {
    return EcrituresServeurDao(ref.read(baseLocaleProvider)).chargesDatees();
  }
  final d = await lireDonneesComptabilite(ref.read(comptabiliteDaoProvider));
  return [
    for (final e in d.ecritures)
      if (e.estValidee && d.comptes[e.compteId]?.classe == '6')
        ChargeDatee(
          date: e.dateEcriture,
          debitCentimes: e.debitCentimes,
          creditCentimes: e.creditCentimes,
        ),
  ];
}
