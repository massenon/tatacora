import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import 'proforma_dao.dart';

/// Le PRÉREMPLISSAGE d'une proforma depuis un module du poste (PO, 07/11/2026, point 4) : client
/// (nom, téléphone, IFU si connu), objet et lignes, à partir de ce qui existe RÉELLEMENT en base
/// locale — mêmes règles et mêmes libellés que `PrefillProforma.php` du serveur :
///  - location : le contrat (véhicule x jours au tarif journalier) ;
///  - tourisme : la réservation de circuit (circuit x participants) ;
///  - hébergement : nuitées au tarif figé + lignes de services (remises non reprises) ;
///  - événement : aucun module événement n'existe : proforma vide.
/// Les lignes restent modifiables ; rien n'est inventé (une réservation sans tarif donne 0).
final class PrefillProformaPoste {
  const PrefillProformaPoste({
    required this.clientId,
    required this.clientNom,
    required this.clientTelephone,
    required this.clientIfu,
    required this.objet,
    required this.sourceModule,
    required this.sourceId,
    required this.lignes,
  });

  final String? clientId;
  final String clientNom;
  final String clientTelephone;
  final String clientIfu;
  final String objet;
  final String sourceModule;
  final String? sourceId;
  final List<LigneProformaSaisie> lignes;

  static const vide = PrefillProformaPoste(
    clientId: null,
    clientNom: '',
    clientTelephone: '',
    clientIfu: '',
    objet: '',
    sourceModule: 'libre',
    sourceId: null,
    lignes: [],
  );

  /// `null` : flux ou source inconnus (la saisie s'ouvre alors vide).
  static Future<PrefillProformaPoste?> depuis(
    AppDatabase db,
    String flux,
    String? source,
  ) async => switch (flux) {
    'location' => source == null ? null : _location(db, source),
    'tourisme' => source == null ? null : _tourisme(db, source),
    'hebergement' => source == null ? null : _hebergement(db, source),
    'evenement' => const PrefillProformaPoste(
      clientId: null,
      clientNom: '',
      clientTelephone: '',
      clientIfu: '',
      objet: '',
      sourceModule: 'evenement',
      sourceId: null,
      lignes: [],
    ),
    _ => null,
  };

  static String _jour(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  static Future<ClientsLocalData?> _client(AppDatabase db, String id) =>
      (db.select(
        db.clientsLocal,
      )..where((c) => c.id.equals(id))).getSingleOrNull();

  static PrefillProformaPoste _avec(
    ClientsLocalData? c, {
    required String flux,
    required String source,
    required String objet,
    required List<LigneProformaSaisie> lignes,
  }) => PrefillProformaPoste(
    clientId: c?.id,
    clientNom: c == null ? '' : '${c.prenom ?? ''} ${c.nom}'.trim(),
    clientTelephone: c?.telephone ?? '',
    clientIfu: c?.ifu ?? '',
    objet: objet,
    sourceModule: flux,
    sourceId: source,
    lignes: lignes,
  );

  static Future<PrefillProformaPoste?> _location(
    AppDatabase db,
    String id,
  ) async {
    final contrat = await (db.select(
      db.contratsLocationLocal,
    )..where((c) => c.id.equals(id))).getSingleOrNull();
    if (contrat == null) return null;
    final v = await (db.select(
      db.vehiculesLocal,
    )..where((t) => t.id.equals(contrat.vehiculeId))).getSingle();
    final jours = contrat.dateFin.difference(contrat.dateDebut).inDays;
    return _avec(
      await _client(db, contrat.clientId),
      flux: 'location',
      source: id,
      objet: 'Location de véhicule — ${v.categorie} ${v.immatriculation}',
      lignes: [
        (
          designation:
              'Location ${v.categorie} ${v.immatriculation} du ${_jour(contrat.dateDebut)} au ${_jour(contrat.dateFin)}',
          quantite: jours < 1 ? 1 : jours,
          prixUnitaire: v.tarifJour.round(),
        ),
      ],
    );
  }

  static Future<PrefillProformaPoste?> _tourisme(
    AppDatabase db,
    String id,
  ) async {
    final r = await (db.select(
      db.reservationsTourLocal,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (r == null) return null;
    final circuit = await (db.select(
      db.circuitsLocal,
    )..where((c) => c.id.equals(r.circuitId))).getSingle();
    return _avec(
      await _client(db, r.clientId),
      flux: 'tourisme',
      source: id,
      objet: 'Circuit touristique — ${circuit.nom}',
      lignes: [
        (
          designation:
              'Circuit ${circuit.nom} du ${_jour(r.dateCircuit)} (par participant)',
          quantite: r.nbParticipants < 1 ? 1 : r.nbParticipants,
          prixUnitaire: circuit.prix.round(),
        ),
      ],
    );
  }

  static Future<PrefillProformaPoste?> _hebergement(
    AppDatabase db,
    String id,
  ) async {
    final r = await (db.select(
      db.reservationsLocal,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (r == null) return null;
    final unite = await (db.select(
      db.unitesHebergementLocal,
    )..where((u) => u.id.equals(r.uniteId))).getSingle();
    final services =
        await (db.select(db.lignesReservationLocal)
              ..where((l) => l.reservationId.equals(id))
              ..orderBy([(l) => OrderingTerm.asc(l.ordre)]))
            .get();
    final nuits = r.dateDepart.difference(r.dateArrivee).inDays;
    return _avec(
      await _client(db, r.clientId),
      flux: 'hebergement',
      source: id,
      objet: 'Séjour du ${_jour(r.dateArrivee)} au ${_jour(r.dateDepart)}',
      lignes: [
        (
          designation:
              'Hébergement — unité ${unite.numero}, du ${_jour(r.dateArrivee)} au ${_jour(r.dateDepart)}',
          quantite: nuits < 1 ? 1 : nuits,
          prixUnitaire: r.tarifNuit,
        ),
        for (final s in services)
          (
            designation: s.libelle,
            quantite: s.quantite < 1 ? 1 : s.quantite,
            prixUnitaire: s.prixUnitaire,
          ),
      ],
    );
  }
}
