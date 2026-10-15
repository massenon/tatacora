/// L'étape d'enregistrement UNIQUE de tous les exports du poste — PDF comme
/// tableur (demande du PO du 14/10/2026).
///
/// Avant elle, chaque module écrivait son CSV en silence dans le dossier
/// Documents, sous un nom horodaté que personne ne choisissait, et ses PDF
/// partaient au dialogue d'impression. Désormais « Générer & Télécharger »
/// ouvre la fenêtre « Enregistrer sous » de Windows, ouverte sur Documents,
/// avec un nom suggéré lisible (`journal_ventes_2026-10-14.pdf`) ; le fichier
/// n'est écrit qu'à l'emplacement choisi. Annuler n'écrit RIEN.
///
/// Le service ne compose aucun document : il reçoit des octets déjà produits
/// (le format CSV — BOM UTF-8, point-virgule — reste celui de chaque module).
/// Le message rendu à l'écran vit dans `shared_widgets/toast_export.dart`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'selecteur_fichiers.dart';

export 'selecteur_fichiers.dart' show TypeFichierEnregistre;

/// Le nom suggéré d'un export : `<base>_<AAAA-MM-JJ>.<extension>`.
///
/// [base] est en minuscules et sans espace (`journal_ventes`) ; [le] vaut
/// aujourd'hui par défaut.
String nomFichierExport(
  String base,
  TypeFichierEnregistre type, {
  DateTime? le,
}) {
  final d = le ?? DateTime.now();
  final date =
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
  return '${base}_$date.${type.extension}';
}

/// La base d'un nom de fichier tirée d'un TITRE de document : minuscules,
/// accents retirés, tout autre caractère remplacé par `_`
/// (« Commandes d'achat » → `commandes_d_achat`).
String baseDepuisTitre(String titre) {
  const accents = {
    'à': 'a', 'â': 'a', 'ä': 'a', 'ç': 'c', 'é': 'e', 'è': 'e', 'ê': 'e', //
    'ë': 'e', 'î': 'i', 'ï': 'i', 'ô': 'o', 'ö': 'o', 'ù': 'u', 'û': 'u', //
    'ü': 'u', 'ÿ': 'y', 'œ': 'oe', 'æ': 'ae',
  };
  final sansAccents = titre
      .toLowerCase()
      .split('')
      .map((c) => accents[c] ?? c)
      .join();
  final base = sansAccents
      .replaceAll(RegExp('[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return base.isEmpty ? 'export' : base;
}

/// Enregistre un export par la fenêtre « Enregistrer sous ».
final class EnregistrementExport {
  const EnregistrementExport({
    required this.selecteur,
    required this.dossierParDefaut,
  });

  /// La fenêtre native — `selecteurFichiersProvider`.
  final SelecteurFichiers selecteur;

  /// Le dossier où la fenêtre s'ouvre (Documents).
  final Future<String?> Function() dossierParDefaut;

  /// Ouvre la fenêtre sur le dossier par défaut (Documents) avec
  /// [nomSuggere], écrit [octets] à l'emplacement choisi et rend son CHEMIN.
  /// `null` : annulé, rien n'est écrit. Une erreur d'écriture LÈVE — l'écran
  /// la dit (`executerExport`).
  Future<String?> enregistrerFichier({
    required String nomSuggere,
    required List<int> octets,
    required TypeFichierEnregistre type,
  }) async {
    String? dossier;
    try {
      dossier = await dossierParDefaut();
    } on Object {
      // Sans dossier par défaut, la fenêtre s'ouvre où Windows le décide :
      // ce n'est pas une raison de refuser l'export.
      dossier = null;
    }
    return selecteur.enregistrerSous(
      nomSuggere: nomSuggere,
      octets: octets,
      type: type,
      dossierInitial: dossier,
    );
  }

  /// [enregistrerFichier] sous le nom suggéré `<base>_<AAAA-MM-JJ>.<extension>`
  /// ([nomFichierExport]) — la forme qu'emploient tous les exports.
  Future<String?> exporter({
    required String base,
    required TypeFichierEnregistre type,
    required List<int> octets,
  }) => enregistrerFichier(
    nomSuggere: nomFichierExport(base, type),
    octets: octets,
    type: type,
  );
}

/// Le dossier Documents de l'utilisateur — défaut de la fenêtre.
Future<String?> _dossierDocuments() async =>
    (await getApplicationDocumentsDirectory()).path;

/// L'enregistrement des exports du poste — à surcharger dans les tests
/// (ou surcharger [selecteurFichiersProvider]).
final enregistrementExportProvider = Provider<EnregistrementExport>(
  (ref) => EnregistrementExport(
    selecteur: ref.watch(selecteurFichiersProvider),
    dossierParDefaut: _dossierDocuments,
  ),
);
