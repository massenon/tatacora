import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/fichiers/enregistrement_export.dart';
import '../../../core/impression/export_etat_a4.dart';
import '../domain/entities/comptabilite.dart';
import '../impression/etat_journal_comptable.dart';
import 'providers_comptabilite.dart';

/// Ce que le hub Comptabilité lit du moteur du poste — relu à chaque visite,
/// aucun cache (lot D, 14/10/2026, D417). LECTURE seule : `MoteurComptable`
/// reste le seul auteur des écritures.
final class DonneesComptabilite {
  const DonneesComptabilite({
    required this.exercices,
    required this.journaux,
    required this.centres,
    required this.ecritures,
    required this.comptes,
    required this.exerciceOuvert,
  });

  final List<ExerciceComptable> exercices;
  final List<JournalComptable> journaux;
  final List<CentreDeCout> centres;
  final List<EcritureComptable> ecritures;

  /// Les comptes MOUVEMENTÉS, par identifiant — le plan entier (1 332
  /// comptes) n'est pas relu pour afficher quelques lignes.
  final Map<String, CompteDuPlan> comptes;

  /// L'exercice ouvert le plus récent — le choix par défaut du sélecteur.
  final ExerciceComptable? exerciceOuvert;
}

final donneesComptabiliteProvider =
    FutureProvider.autoDispose<DonneesComptabilite>((ref) async {
      final dao = ref.watch(comptabiliteDaoProvider);
      final ecritures = await dao.toutesLesEcritures();
      final comptes = <String, CompteDuPlan>{};
      for (final id in {for (final e in ecritures) e.compteId}) {
        final c = await dao.compteParId(id);
        if (c != null) comptes[id] = c;
      }
      return DonneesComptabilite(
        exercices: await dao.exercices(),
        journaux: await dao.journaux(),
        centres: await dao.centres(),
        ecritures: ecritures,
        comptes: comptes,
        exerciceOuvert: await dao.exerciceOuvertLePlusRecent(),
      );
    });

/// Les comptes IMPUTABLES du plan local, triés par numéro — la liste du champ
/// « Compte » de la modale « Passer une écriture » (PO, 14/10/2026).
///
/// Le plan entier, classe par classe (`comptesDeClasse`, non paginé : une page
/// manquante ferait imputer au mauvais compte). Une DIVISION (numéro de moins
/// de quatre chiffres qui porte des sous-comptes) est écartée : le moteur la
/// refuserait (`compte_division`), la proposer serait offrir un refus.
final comptesImputablesProvider =
    FutureProvider.autoDispose<List<CompteDuPlan>>((ref) async {
      final dao = ref.watch(comptabiliteDaoProvider);
      final tous = <CompteDuPlan>[
        for (final classe in const [
          '1',
          '2',
          '3',
          '4',
          '5',
          '6',
          '7',
          '8',
          '9',
        ])
          ...await dao.comptesDeClasse(classe),
      ];
      final numeros = [for (final c in tous) c.numero];
      bool estDivision(CompteDuPlan c) =>
          c.numero.length < 4 &&
          numeros.any((n) => n != c.numero && n.startsWith(c.numero));
      return [
        for (final c in tous)
          if (!estDivision(c)) c,
      ];
    });

/// L'export tableur du journal affiché — rend le **chemin** du fichier écrit
/// par la fenêtre « Enregistrer sous », `null` : annulé (directive du PO du
/// 14/10/2026). Action injectable : un test de widget n'a pas de greffon
/// natif, et il doit exister un seul endroit où ce fichier est écrit.
final exporterJournalComptableProvider =
    Provider<Future<String?> Function(EtatJournalComptable)>(
      (ref) =>
          (etat) => ref
              .read(enregistrementExportProvider)
              .exporter(
                base: EtatJournalComptable.prefixeFichier,
                type: TypeFichierEnregistre.csv,
                octets: etat.csvOctets(),
              ),
    );

/// L'export « PDF Officiel A4 Imprimable » du journal affiché — paysage, mêmes
/// colonnes et lignes que le CSV, totaux débit / crédit, en-tête lu des
/// paramètres.
final exporterJournalComptablePdfProvider =
    Provider<Future<String?> Function(EtatJournalComptable)>(
      (ref) =>
          (etat) => enregistrerEtatA4(
            ref,
            etat.etatA4(),
            base: EtatJournalComptable.prefixeFichier,
          ),
    );
