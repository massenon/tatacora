import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/di/providers.dart';
import '../../../core/fichiers/enregistrement_export.dart';
import '../../../core/impression/entete_parametree.dart';
import '../../synchronisation/presentation/providers_synchronisation.dart';
import '../data/archive_cloture_locale.dart';
import '../data/cloture_exercice_locale.dart';
import '../domain/cloture_exercice.dart';
import '../domain/entities/comptabilite.dart';
import '../domain/messages_cloture.dart';
import 'exercice_consulte.dart';
import 'providers_comptabilite.dart';
import 'providers_consultation_comptable.dart';
import 'providers_etats_financiers.dart';

/// Les gestes de la clôture annuelle, tels que l'onglet « Clôtures » du hub les
/// lit (26/10/2026) : le service des gestes, l'archive légale, l'état de la
/// liste de contrôle d'un exercice et sa clôture active.

/// Le dossier des archives légales : `archives/` à côté de `poste.json`. Un
/// dossier du poste, hors de la base — la sauvegarde de la base ne le contient
/// pas (à copier avec elle, comme le dossier `archives` du serveur).
final dossierArchivesProvider = Provider<Future<Directory> Function()>((ref) {
  final chemin = ref.watch(cheminConfigurationPosteProvider);
  return () async => Directory(p.join(p.dirname(await chemin()), 'archives'));
});

/// Le service des gestes de clôture — jamais servi avant le moteur comptable
/// (donc le référentiel).
final clotureExerciceLocaleProvider = FutureProvider<ClotureExerciceLocale>((
  ref,
) async {
  final moteur = await ref.watch(moteurComptableProvider.future);
  return ClotureExerciceLocale(ref.watch(baseLocaleProvider), moteur);
});

final archiveClotureLocaleProvider = FutureProvider<ArchiveClotureLocale>((
  ref,
) async {
  return ArchiveClotureLocale(
    ref.watch(comptabiliteDaoProvider),
    await ref.watch(clotureExerciceLocaleProvider.future),
    ref.watch(dossierArchivesProvider),
  );
});

/// La liste de contrôle de [exerciceId] (aucun brouillon, balance et bilan
/// équilibrés…), le résultat à reporter, les avertissements.
final etatClotureProvider = FutureProvider.autoDispose
    .family<EtatClotureLocal, String>((ref, exerciceId) async {
      final service = await ref.watch(clotureExerciceLocaleProvider.future);
      return service.etat(exerciceId);
    });

/// Les clôtures du poste, la plus récente d'abord — celles d'un exercice se
/// retrouvent par son identifiant ; l'ACTIVE est celle qui n'est pas rouverte.
final cloturesDuPosteProvider =
    FutureProvider.autoDispose<List<ClotureExercice>>((ref) async {
      final service = await ref.watch(clotureExerciceLocaleProvider.future);
      return service.clotures();
    });

/// Ce que le hub relit après un geste de clôture : les exercices (leur statut
/// pilote le sélecteur, les bandeaux et la saisie), les pièces, les états, la
/// liste de contrôle et l'historique des clôtures.
void invaliderApresCloture(WidgetRef ref) {
  ref
    ..invalidate(donneesComptabiliteProvider)
    ..invalidate(exercicesDuPosteProvider)
    ..invalidate(donneesEtatsFinanciersProvider)
    ..invalidate(donneesEtatsDuPosteProvider)
    ..invalidate(provenanceEtatsFinanciersProvider)
    ..invalidate(etatClotureProvider)
    ..invalidate(cloturesDuPosteProvider);
}

/// Les gestes de l'onglet, avec le compte connecté — une classe pour qu'un test
/// les appelle sans widget. Chaque geste rend la PHRASE de succès (celle de la
/// vue) ou LÈVE un `RefusComptable` aux mots du serveur.
final class GestesCloture {
  const GestesCloture(this._ref);

  final WidgetRef _ref;

  String get _auteur => _ref.read(sessionProvider)?.utilisateurId ?? '';

  Future<ClotureExerciceLocale> get _service =>
      _ref.read(clotureExerciceLocaleProvider.future);

  Future<String> demarrer(ExerciceComptable exercice) async {
    await (await _service).demarrer(exercice.id, auteurId: _auteur);
    return MessagesCloture.dire('comptabilite_pwa.cloture_demarree', {
      'annee': '${exercice.annee}',
    });
  }

  Future<String> reprendreSaisie(ExerciceComptable exercice) async {
    await (await _service).reprendreSaisie(exercice.id, auteurId: _auteur);
    return MessagesCloture.dire('comptabilite_pwa.saisie_reprise', {
      'annee': '${exercice.annee}',
    });
  }

  /// La clôture définitive, puis l'archive légale — HORS de la clôture : une
  /// archive qui échoue ne la défait pas, l'onglet propose alors « Générer
  /// l'archive ».
  Future<String> cloturer(ExerciceComptable exercice) async {
    final cloture = await (await _service).cloturer(
      exercice.id,
      auteurId: _auteur,
    );
    try {
      await _archiver(cloture.id);
    } on Object {
      // La clôture tient ; l'archive se génère à la demande.
    }
    return MessagesCloture.dire('comptabilite_pwa.exercice_cloture', {
      'annee': '${exercice.annee}',
    });
  }

  Future<String> genererArchive(ExerciceComptable exercice) async {
    final cloture = await (await _service).clotureActive(exercice.id);
    if (cloture == null) {
      throw StateError(
        MessagesCloture.dire('comptabilite.archive_sans_cloture'),
      );
    }
    await _archiver(cloture.id);
    return MessagesCloture.dire('comptabilite_pwa.archive_generee', {
      'annee': '${exercice.annee}',
    });
  }

  Future<String> rouvrir(ExerciceComptable exercice, String motif) async {
    await (await _service).rouvrir(
      exercice.id,
      auteurId: _auteur,
      motif: motif,
    );
    return MessagesCloture.dire('comptabilite_pwa.exercice_rouvert', {
      'annee': '${exercice.annee}',
    });
  }

  /// Enregistre l'archive (ZIP) par la fenêtre « Enregistrer sous ». `null` :
  /// annulé. Une archive altérée LÈVE `RefusComptable` : elle n'est pas
  /// délivrée.
  Future<String?> telechargerArchive(ExerciceComptable exercice) async {
    final cloture = await (await _service).clotureActive(exercice.id);
    if (cloture == null || cloture.archiveEmpreinte == null) {
      throw StateError(
        MessagesCloture.dire('comptabilite.archive_sans_cloture'),
      );
    }
    final Uint8List octets = await (await _ref.read(
      archiveClotureLocaleProvider.future,
    )).zip(cloture);
    return _ref
        .read(enregistrementExportProvider)
        .exporter(
          base: 'archive_exercice_${exercice.annee}',
          type: TypeFichierEnregistre.zip,
          octets: octets,
        );
  }

  Future<void> _archiver(String clotureId) async {
    final entete = await _ref.read(lireEnteteEtablissementProvider)();
    await (await _ref.read(
      archiveClotureLocaleProvider.future,
    )).archiver(clotureId, entete: entete);
  }
}
