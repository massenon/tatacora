/// Les sélecteurs de fichier NATIFS du poste — « Ouvrir » et « Enregistrer
/// sous » de Windows (demande du PO du 14/10/2026 : l'import d'articles lit un
/// CSV choisi par l'utilisateur, le modèle d'import s'enregistre où il le
/// décide).
///
/// Action INJECTABLE ([selecteurFichiersProvider]), comme les impressions et
/// les exports : un test de widget n'a pas de greffon natif, et il doit exister
/// un seul endroit où ces fenêtres sont ouvertes.
///
/// Implémentation : `file_selector_windows` (plugin officiel flutter.dev). Aucun
/// réseau ; la cible est le bureau seul (décision du PO du 08/10/2026).
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Un fichier lu : son nom (pour l'afficher) et ses octets.
final class FichierLu {
  const FichierLu({required this.nom, required this.octets});

  final String nom;
  final Uint8List octets;
}

/// Le type d'un fichier enregistré — il fixe le filtre de la fenêtre
/// « Enregistrer sous » (14/10/2026 : les exports PDF passent aussi par elle).
enum TypeFichierEnregistre {
  csv('CSV', ['csv', 'txt']),
  pdf('PDF', ['pdf']);

  const TypeFichierEnregistre(this.libelle, this.extensions);

  /// Le nom du filtre dans la fenêtre native.
  final String libelle;

  /// Les extensions acceptées — la première est celle du fichier.
  final List<String> extensions;

  /// L'extension du fichier, sans point.
  String get extension => extensions.first;
}

/// Ce que le poste sait faire avec un fichier choisi par l'utilisateur.
abstract interface class SelecteurFichiers {
  /// Ouvre la fenêtre « Ouvrir » filtrée sur les CSV. `null` : annulé.
  Future<FichierLu?> ouvrirCsv();

  /// Ouvre la fenêtre « Enregistrer sous » avec [nomSuggere], filtrée sur
  /// [type] et ouverte sur [dossierInitial] quand il est donné, puis écrit
  /// [octets] à l'emplacement choisi. Rend le CHEMIN écrit, `null` : annulé
  /// (et rien n'est écrit).
  Future<String?> enregistrerSous({
    required String nomSuggere,
    required List<int> octets,
    TypeFichierEnregistre type = TypeFichierEnregistre.csv,
    String? dossierInitial,
  });
}

/// L'implémentation native.
final class SelecteurFichiersNatif implements SelecteurFichiers {
  const SelecteurFichiersNatif();

  static const XTypeGroup _csv = XTypeGroup(
    label: 'CSV',
    extensions: ['csv', 'txt'],
  );

  static XTypeGroup _groupe(TypeFichierEnregistre type) =>
      XTypeGroup(label: type.libelle, extensions: type.extensions);

  @override
  Future<FichierLu?> ouvrirCsv() async {
    final fichier = await FileSelectorPlatform.instance.openFile(
      acceptedTypeGroups: const [_csv],
    );
    if (fichier == null) return null;
    return FichierLu(nom: fichier.name, octets: await fichier.readAsBytes());
  }

  @override
  Future<String?> enregistrerSous({
    required String nomSuggere,
    required List<int> octets,
    TypeFichierEnregistre type = TypeFichierEnregistre.csv,
    String? dossierInitial,
  }) async {
    final emplacement = await FileSelectorPlatform.instance.getSaveLocation(
      acceptedTypeGroups: [_groupe(type)],
      options: SaveDialogOptions(
        suggestedName: nomSuggere,
        initialDirectory: dossierInitial,
      ),
    );
    if (emplacement == null) return null;
    final fichier = File(emplacement.path);
    await fichier.writeAsBytes(octets, flush: true);
    return fichier.path;
  }
}

/// Le sélecteur du poste — à surcharger dans les tests.
final selecteurFichiersProvider = Provider<SelecteurFichiers>(
  (ref) => const SelecteurFichiersNatif(),
);
