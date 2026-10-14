/// La lecture des huit sources de la recherche globale — `RechercheGlobale::
/// SOURCES` du serveur, traduit en tables du poste. LECTURE SEULE : aucune
/// méthode n'écrit.
///
/// Pour chaque source : la table, les colonnes cherchées (`LIKE %terme%`, OU
/// entre elles), les colonnes affichées (jointes par une espace, le tout
/// `trim`), un tri sur la DERNIÈRE colonne affichée, cinq lignes au plus —
/// mot pour mot la requête du serveur. Le terme n'est pas échappé (`%` et `_`
/// gardent leur sens de joker), comme au serveur.
library;

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../domain/recherche_globale.dart';

/// Une source : la table du poste et ses colonnes.
typedef SourceRecherche = ({
  String table,
  List<String> colonnes,
  List<String> libelle,
  String? filtre,
});

class RechercheGlobaleDao {
  RechercheGlobaleDao(this._base);

  final AppDatabase _base;

  /// Les tables et colonnes du poste, source par source. Les noms de colonnes
  /// sont ceux du serveur, sauf pour les factures (voir l'en-tête du domaine :
  /// `numero` au lieu de `numero_mecef`, avoirs et tickets écartés).
  static const Map<FamilleRecherche, SourceRecherche> sources = {
    FamilleRecherche.clients: (
      table: 'clients_local',
      colonnes: ['nom', 'prenom', 'telephone'],
      libelle: ['prenom', 'nom'],
      filtre: null,
    ),
    FamilleRecherche.articles: (
      table: 'articles_local',
      colonnes: ['libelle'],
      libelle: ['libelle'],
      filtre: null,
    ),
    FamilleRecherche.plats: (
      table: 'plats_local',
      colonnes: ['libelle'],
      libelle: ['libelle'],
      filtre: null,
    ),
    FamilleRecherche.carteBar: (
      table: 'cartes_boisson_local',
      colonnes: ['libelle'],
      libelle: ['libelle'],
      filtre: null,
    ),
    FamilleRecherche.factures: (
      table: 'pieces_facturation_local',
      colonnes: ['numero'],
      libelle: ['numero'],
      filtre: "avoir_de IS NULL AND origine <> 'pos_comptant'",
    ),
    FamilleRecherche.fournisseurs: (
      table: 'fournisseurs_local',
      colonnes: ['raison_sociale'],
      libelle: ['raison_sociale'],
      filtre: null,
    ),
    FamilleRecherche.vehicules: (
      table: 'vehicules_local',
      colonnes: ['immatriculation'],
      libelle: ['immatriculation'],
      filtre: null,
    ),
    FamilleRecherche.circuits: (
      table: 'circuits_local',
      colonnes: ['nom'],
      libelle: ['nom'],
      filtre: null,
    ),
  };

  /// Les libellés des lignes de [famille] qui contiennent [terme].
  Future<List<String>> chercher(FamilleRecherche famille, String terme) async {
    final s = sources[famille]!;
    final ou = s.colonnes.map((c) => '$c LIKE ?').join(' OR ');
    final filtre = s.filtre == null ? '' : ' AND (${s.filtre})';
    final lignes = await _base
        .customSelect(
          'SELECT ${s.libelle.join(', ')} FROM ${s.table} '
          'WHERE ($ou)$filtre '
          'ORDER BY ${s.libelle.last} LIMIT $plafondRecherche',
          variables: [
            for (final _ in s.colonnes) Variable.withString('%$terme%'),
          ],
        )
        .get();
    return [
      for (final l in lignes)
        [for (final c in s.libelle) '${l.data[c] ?? ''}'].join(' ').trim(),
    ];
  }
}
