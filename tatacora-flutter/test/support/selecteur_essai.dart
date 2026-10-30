/// Le sélecteur natif REMPLACÉ pour les tests : la fenêtre « Enregistrer
/// sous » de Windows n'a pas de greffon sous `flutter test`.
///
/// Tout export du poste passe par `selecteurFichiersProvider`
/// (`core/fichiers/enregistrement_export.dart`, PO du 14/10/2026) : surcharger
/// ce seul point fait emprunter au test le VRAI chemin d'enregistrement —
/// composition, nom suggéré, type, puis toast. Ce qui « aurait été écrit » est
/// retenu pour l'assertion ; rien ne touche le disque.
library;

import 'dart:convert';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:tatacora_flutter/core/fichiers/enregistrement_export.dart';
import 'package:tatacora_flutter/core/fichiers/selecteur_fichiers.dart';

/// Un fichier que la fenêtre « Enregistrer sous » aurait écrit.
final class FichierEnregistreEssai {
  const FichierEnregistreEssai({
    required this.nom,
    required this.octets,
    required this.type,
    required this.dossierInitial,
  });

  final String nom;
  final List<int> octets;
  final TypeFichierEnregistre type;
  final String? dossierInitial;

  /// Le contenu lu en UTF-8 (BOM compris) — pour un CSV.
  String get texte => utf8.decode(octets);

  /// Vrai quand les octets sont ceux d'un PDF (`%PDF`).
  bool get estUnPdf =>
      octets.length > 4 && ascii.decode(octets.sublist(0, 4)) == '%PDF';
}

/// Le faux sélecteur : il retient chaque enregistrement et rend un chemin,
/// ou `null` (l'utilisateur a annulé) quand [annuler] est vrai.
final class SelecteurEssai implements SelecteurFichiers {
  SelecteurEssai({this.lu, this.annuler = false});

  /// Ce que rend « Ouvrir ».
  final FichierLu? lu;

  /// Simule « Annuler » dans la fenêtre « Enregistrer sous ».
  bool annuler;

  /// Les fichiers « écrits », dans l'ordre.
  final List<FichierEnregistreEssai> ecrits = [];

  /// Le dernier fichier écrit (échoue s'il n'y en a aucun).
  FichierEnregistreEssai get dernier => ecrits.last;

  @override
  Future<FichierLu?> ouvrirTableur() async => lu;

  /// Ce que rend « Ouvrir » pour une image : le même [lu].
  @override
  Future<FichierLu?> ouvrirImage({required List<String> extensions}) async =>
      lu;

  @override
  Future<String?> enregistrerSous({
    required String nomSuggere,
    required List<int> octets,
    TypeFichierEnregistre type = TypeFichierEnregistre.csv,
    String? dossierInitial,
  }) async {
    if (annuler) return null;
    ecrits.add(
      FichierEnregistreEssai(
        nom: nomSuggere,
        octets: List<int>.unmodifiable(octets),
        type: type,
        dossierInitial: dossierInitial,
      ),
    );
    return 'C:/essai/$nomSuggere';
  }

  /// Le dossier où la fenêtre « s'ouvre » — Documents, sans greffon.
  static const String dossierDocuments = 'C:/Users/essai/Documents';

  /// Les surcharges à poser dans le `ProviderScope` (ou le conteneur) : le
  /// sélecteur, et l'enregistrement RÉEL (`EnregistrementExport`) branché sur
  /// lui avec un dossier par défaut fixe — `path_provider` n'a pas de greffon
  /// sous `flutter test`, et son canal ne répond pas en temps simulé.
  List<Override> get surcharges => [
    selecteurFichiersProvider.overrideWithValue(this),
    enregistrementExportProvider.overrideWithValue(
      EnregistrementExport(
        selecteur: this,
        dossierParDefaut: () async => dossierDocuments,
      ),
    ),
  ];
}
