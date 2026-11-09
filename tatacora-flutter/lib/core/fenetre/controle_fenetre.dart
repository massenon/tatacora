import 'package:flutter/foundation.dart';

/// Ce que la barre supérieure sait demander à la FENÊTRE du poste.
///
/// Un SEAM : l'interface ne connaît aucun plugin, ni aucune plateforme. La
/// réalisation Windows (`controle_fenetre_windows.dart`) parle au plugin natif
/// `window_manager` ; les tests de widgets fournissent une fausse, de sorte
/// qu'aucun test ne dépend d'un code natif.
abstract interface class ControleFenetre {
  /// Vrai quand la fenêtre est agrandie : le bouton affiche alors
  /// « Restaurer » et deux carrés, sinon « Agrandir » et un carré.
  ValueListenable<bool> get agrandie;

  /// Réduit la fenêtre dans la barre des tâches.
  Future<void> reduire();

  /// Agrandit la fenêtre, ou la restaure si elle est déjà agrandie.
  Future<void> basculerAgrandissement();

  /// Ferme la fenêtre PAR LE MÊME CHEMIN que la croix native : le système
  /// reçoit une demande de fermeture (`SC_CLOSE`), jamais un `exit`.
  Future<void> fermer();

  /// Commence le déplacement de la fenêtre (glisser dans la zone libre de la
  /// barre supérieure).
  Future<void> deplacer();

  /// Commence le REDIMENSIONNEMENT de la fenêtre par le [bord] saisi. Sans
  /// barre de titre native, la fenêtre n'a plus de cadre sur son bord HAUT :
  /// la coquille pose des zones de saisie invisibles qui appellent cette
  /// méthode (voir `ZonesRedimensionnementFenetre`).
  Future<void> redimensionner(BordFenetre bord);
}

/// Le bord ou le coin de la fenêtre saisi pour la redimensionner. Un type du
/// seam, pour que l'interface ne connaisse aucun plugin.
enum BordFenetre { haut, hautGauche, hautDroite }
