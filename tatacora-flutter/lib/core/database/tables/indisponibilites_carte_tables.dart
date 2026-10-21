/// Les RETRAITS de la carte du jour — boisson (M5) ou plat (M4) — lot de
/// synchronisation du 21/10/2026 (« ce que le web fait, le poste le fait »).
///
/// Une ligne par retrait, comme `indisponibilites_carte` du serveur : motif du
/// registre fermé (`rupture`, `saison`, `retire`), commentaire, instant du
/// retrait et, une fois l'article remis à la carte, instant du retour. Un
/// retrait EN COURS est une ligne sans `date_retour_disponibilite`.
///
/// Exactement UN des deux identifiants est renseigné. Ni l'un ni l'autre n'est
/// une clé étrangère : le catalogue et ses retraits descendent dans le même
/// flux mais pas forcément dans la même page, et une contrainte violée
/// emporterait tout le lot (leçon du piège 11).
///
/// | Qui l'écrit | Qui la lit |
/// |---|---|
/// | `IndisponibilitesCarteDao` (retrait, remise) ; `AligneurCatalogue` (descente) | `carteLocaleProvider` (bar), la carte du restaurant |
library;

import 'package:drift/drift.dart';

@DataClassName('IndisponibiliteCarteLigne')
class IndisponibilitesCarteLocal extends Table {
  TextColumn get id => text()();

  /// La boisson retirée (`cartes_boisson_local.id`), ou `null` pour un plat.
  TextColumn get boissonId => text().nullable()();

  /// Le plat retiré (`plats_local.id`), ou `null` pour une boisson.
  TextColumn get platId => text().nullable()();

  /// Code du registre FERMÉ `IndisponibiliteCarte::MOTIFS`.
  TextColumn get motif => text()();

  TextColumn get commentaire => text().nullable()();

  DateTimeColumn get dateIndisponibilite => dateTime()();

  /// `null` : le retrait est en cours.
  DateTimeColumn get dateRetourDisponibilite => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
