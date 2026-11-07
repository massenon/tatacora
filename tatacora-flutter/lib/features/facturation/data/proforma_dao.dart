import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
// Les classes de tables doivent être dans la portée du fichier (leçon `reservation_dao.dart`).
import '../../../core/database/tables/proformas_tables.dart';
import '../../synchronisation/data/operations_sync_dao.dart';
import '../../synchronisation/domain/charges_synchronisation.dart';
import '../../synchronisation/domain/operation_sync.dart';
import '../domain/entities/piece_facturation.dart';
import '../domain/ifu_client.dart';
import '../domain/numero_proforma.dart';
import '../domain/reglages_documents.dart';
import '../domain/repositories/facture_repository.dart';
import 'facture_dao.dart';

part 'proforma_dao.g.dart';

/// Un refus métier de la proforma — la phrase est dite à l'écran.
final class RefusProforma implements Exception {
  const RefusProforma(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Les statuts STOCKÉS (« expirée » est dérivé, jamais écrit). Un ENUM (le code est son nom) :
/// aucun littéral `annulee` ici, qui ferait croire à `pieces_des_mouvements_test` qu'une
/// réservation s'annule hors de `annulerAvecConditions`.
enum StatutProforma {
  brouillon,
  emise,
  convertie,
  annulee;

  String get code => name;
}

/// Une ligne de saisie : désignation libre, quantité entière, prix unitaire TTC en FCFA entiers.
typedef LigneProformaSaisie = ({
  String designation,
  int quantite,
  int prixUnitaire,
});

/// FACTURE PROFORMA du poste — document NON FISCAL, HORS LIGNE (PO, 07/11/2026).
///
/// ## L'ÉCRIVAIN UNIQUE
/// Toute écriture des tables `proformas_local` / `lignes_proforma_local` passe ici, et dépose
/// son document dans la file d'envoi DANS la même transaction ([OperationsSyncDao.enfiler]) :
/// une coupure entre les deux ne laisse jamais une proforma que rien ne pousse.
///
/// ## Le numéro
/// Un brouillon n'en a pas. À l'ÉMISSION le poste pose un numéro PROVISOIRE
/// `PROV-FP-AAAA-NNNNN` (compteur persisté, jamais déduit du nombre de lignes) ; à l'accusé le
/// serveur rend le numéro continu `N°0045 FP-GCN/2026` et [regulariserNumero] le remplace.
/// Le poste ne choisit JAMAIS un numéro définitif. Hors synchronisation (démonstration, tests
/// sans file) l'émission pose le numéro local directement.
///
/// ## Jamais fiscal
/// Aucune colonne ni aucun geste MECeF, QR, normalisation ; aucune pièce comptable, aucun
/// mouvement de stock.
///
/// ## La conversion
/// Crée la VRAIE facture du poste par [FactureDao.emettre] (même chemin que toute facture :
/// numéro provisoire, file `factures`), puis lie les deux et passe la proforma à « convertie »
/// (immuable). Une seule fois : un rejeu rend la même facture. Le mode de facturation décide
/// ensuite ; la normalisation ne vient jamais d'ici.
@DriftAccessor(
  tables: [ProformasLocal, LignesProformaLocal, SequencesProformaLocal],
)
class ProformaDao extends DatabaseAccessor<AppDatabase>
    with _$ProformaDaoMixin {
  ProformaDao(super.db, {Uuid? uuid, DateTime Function()? maintenant})
    : _uuid = uuid ?? const Uuid(),
      _maintenant = maintenant ?? DateTime.now;

  final Uuid _uuid;
  final DateTime Function() _maintenant;

  /// Le module de la LIGNE de facture selon le flux d'origine (comme le serveur).
  static const modulesDeLigne = <String, ModuleFacturable>{
    'libre': ModuleFacturable.m9Tourisme,
    'hebergement': ModuleFacturable.m1Hebergement,
    'evenement': ModuleFacturable.m4Restaurant,
    'location': ModuleFacturable.m8Vehicules,
    'tourisme': ModuleFacturable.m9Tourisme,
  };

  static const totalMax = 99999999999;

  /* ------------------------------------------------------------------ lecture */

  Future<List<ProformasLocalData>> liste() =>
      (select(proformasLocal)..orderBy([
            (p) => OrderingTerm.desc(p.dateEmission),
            (p) => OrderingTerm.desc(p.id),
          ]))
          .get();

  Future<ProformasLocalData?> parId(String id) =>
      (select(proformasLocal)..where((p) => p.id.equals(id))).getSingleOrNull();

  Future<List<LignesProformaLocalData>> lignes(String proformaId) =>
      (select(lignesProformaLocal)
            ..where((l) => l.proformaId.equals(proformaId))
            ..orderBy([(l) => OrderingTerm.asc(l.position)]))
          .get();

  /// « Expirée » : émise, validité ENREGISTRÉE et dépassée (dérivé ; la conversion reste possible).
  bool estExpiree(ProformasLocalData p) =>
      p.statut == StatutProforma.emise.code &&
      p.valideJusquAu != null &&
      p.valideJusquAu!.isBefore(_debutDuJour());

  bool estModifiable(ProformasLocalData p) =>
      p.statut == StatutProforma.brouillon.code ||
      p.statut == StatutProforma.emise.code;

  /* ---------------------------------------------------------------- écriture */

  /// Crée un BROUILLON (sans numéro). [id] : l'identifiant né ici (tests).
  Future<ProformasLocalData> creer({
    required String clientNom,
    required List<LigneProformaSaisie> lignes,
    String? clientId,
    String? clientTelephone,
    String? clientIfu,
    String? objet,
    String sourceModule = 'libre',
    String? sourceId,
    bool emettre = false,
    ReglagesDocuments reglages = ReglagesDocuments.parDefaut,
    String? id,
  }) async {
    final client = _client(clientNom, clientTelephone, clientIfu);
    final total = _total(lignes);
    final identifiant = id ?? _uuid.v4();
    final flux = modulesDeLigne.containsKey(sourceModule)
        ? sourceModule
        : 'libre';

    await transaction(() async {
      await into(proformasLocal).insert(
        ProformasLocalCompanion.insert(
          id: identifiant,
          statut: StatutProforma.brouillon.code,
          clientNom: client.nom,
          clientId: Value(clientId),
          clientTelephone: Value(client.telephone),
          clientIfu: Value(client.ifu),
          objet: Value(_net(objet)),
          total: Value(total),
          sourceModule: Value(flux),
          sourceId: Value(sourceId),
        ),
      );
      await _ecrireLignes(identifiant, lignes);
      // La création part TOUJOURS en brouillon ; l'émission est une opération à part quand
      // elle suit (le serveur numérote à l'émission, jamais à la création d'un brouillon).
      await OperationsSyncDao(attachedDatabase).enfiler(
        table: TableSynchronisee.proformas,
        entiteId: identifiant,
        type: TypeOperationSync.creation,
        payload: chargeProforma(
          clientNom: client.nom,
          clientId: clientId,
          clientTelephone: client.telephone,
          clientIfu: client.ifu,
          objet: _net(objet),
          sourceModule: flux,
          lignes: lignes,
        ),
      );
    });

    return emettre
        ? this.emettre(identifiant, reglages: reglages)
        : (await parId(identifiant))!;
  }

  /// Modifie une proforma NON convertie ni annulée : client, objet, lignes. Les SEULS champs
  /// changés partent. Le journal d'audit du serveur garde l'avant / après.
  Future<ProformasLocalData> modifier(
    String id, {
    String? clientNom,
    String? clientTelephone,
    String? clientIfu,
    String? objet,
    List<LigneProformaSaisie>? lignes,
  }) async {
    await transaction(() async {
      final p = await _exiger(id);
      _exigerModifiable(p);

      final champs = ProformasLocalCompanion(
        clientNom: clientNom == null
            ? const Value.absent()
            : Value(_client(clientNom, null, null).nom),
        clientTelephone: clientTelephone == null
            ? const Value.absent()
            : Value(_net(clientTelephone)),
        clientIfu: clientIfu == null
            ? const Value.absent()
            : Value(_client('x', null, clientIfu).ifu),
        objet: objet == null ? const Value.absent() : Value(_net(objet)),
        total: lignes == null ? const Value.absent() : Value(_total(lignes)),
      );
      await (update(
        proformasLocal,
      )..where((t) => t.id.equals(id))).write(champs);
      if (lignes != null) {
        await (delete(
          lignesProformaLocal,
        )..where((l) => l.proformaId.equals(id))).go();
        await _ecrireLignes(id, lignes);
      }

      await OperationsSyncDao(attachedDatabase).enfiler(
        table: TableSynchronisee.proformas,
        entiteId: id,
        type: TypeOperationSync.modification,
        payload: chargeProformaModification(
          clientNom: clientNom == null
              ? null
              : _client(clientNom, null, null).nom,
          clientTelephone: clientTelephone == null
              ? null
              : (_net(clientTelephone) ?? ''),
          clientIfu: clientIfu == null
              ? null
              : (_client('x', null, clientIfu).ifu ?? ''),
          objet: objet == null ? null : (_net(objet) ?? ''),
          lignes: lignes,
        ),
      );
    });
    return (await parId(id))!;
  }

  /// Émet : numéro PROVISOIRE, date, ville, validité (calculée ICI et ENREGISTRÉE). Idempotent.
  Future<ProformasLocalData> emettre(
    String id, {
    ReglagesDocuments reglages = ReglagesDocuments.parDefaut,
  }) async {
    await transaction(() async {
      final p = await _exiger(id);
      if (p.numero != null) return;
      _exigerModifiable(p);
      if ((await lignes(id)).isEmpty) {
        throw const RefusProforma('Ajoutez au moins une ligne à la proforma.');
      }

      final maintenant = _maintenant();
      final jour = DateTime(maintenant.year, maintenant.month, maintenant.day);
      final valide = reglages.validiteAffichee
          ? jour.add(Duration(days: reglages.validiteJours))
          : null;
      final numero = await _numeroProvisoireSuivant(maintenant.year);

      await (update(proformasLocal)..where((t) => t.id.equals(id))).write(
        ProformasLocalCompanion(
          numero: Value(numero),
          reference: Value(reglages.referenceFacture),
          statut: Value(StatutProforma.emise.code),
          dateEmission: Value(jour),
          ville: Value(
            reglages.villeEmission.isEmpty ? null : reglages.villeEmission,
          ),
          valideJusquAu: Value(valide),
        ),
      );

      await OperationsSyncDao(attachedDatabase).enfiler(
        table: TableSynchronisee.proformas,
        entiteId: id,
        type: TypeOperationSync.modification,
        payload: chargeProformaModification(
          statut: StatutProforma.emise.code,
          dateEmission: jour,
          avecValidite: true,
          valideJusquAu: valide,
        ),
      );
    });
    return (await parId(id))!;
  }

  /// Annule avec motif (brouillon ou émise). Garde son numéro. Idempotent.
  Future<ProformasLocalData> annuler(String id, String motif) async {
    await transaction(() async {
      final p = await _exiger(id);
      if (p.statut == StatutProforma.annulee.code) return;
      _exigerModifiable(p);
      final m = motif.trim();
      if (m.isEmpty) {
        throw const RefusProforma('Le motif d’annulation est obligatoire.');
      }
      await (update(proformasLocal)..where((t) => t.id.equals(id))).write(
        ProformasLocalCompanion(
          statut: Value(StatutProforma.annulee.code),
          motifAnnulation: Value(m),
        ),
      );
      await OperationsSyncDao(attachedDatabase).enfiler(
        table: TableSynchronisee.proformas,
        entiteId: id,
        type: TypeOperationSync.modification,
        payload: chargeProformaModification(
          statut: StatutProforma.annulee.code,
          motif: m,
        ),
      );
    });
    return (await parId(id))!;
  }

  /// Convertit en VRAIE facture du poste (même chemin que toute facture). Une seule fois :
  /// rejeu = la même facture. Rend l'identifiant de la facture.
  Future<String> convertirEnFacture(String id) async {
    late String factureId;
    await transaction(() async {
      final p = await _exiger(id);
      if (p.statut == StatutProforma.convertie.code && p.factureId != null) {
        factureId = p.factureId!;
        return;
      }
      if (p.statut == StatutProforma.annulee.code) {
        throw const RefusProforma(
          'Cette proforma est annulée : elle ne peut pas être convertie.',
        );
      }
      if (p.statut == StatutProforma.brouillon.code) {
        throw const RefusProforma(
          'Émettez d’abord la proforma : un brouillon ne se convertit pas en facture.',
        );
      }

      final module =
          modulesDeLigne[p.sourceModule] ?? ModuleFacturable.m9Tourisme;
      final lignesProforma = await lignes(id);
      // La facture naît par SON écrivain : numéro provisoire, file `factures`, même transaction.
      final piece = await FactureDao(attachedDatabase, maintenant: _maintenant)
          .emettre(
            BrouillonFacture(
              origine: OrigineFacture.factureDirecte,
              clientNom: p.clientNom,
              clientId: p.clientId,
              acheteurIfu: p.clientIfu,
              acheteurNom: p.clientNom,
              lignes: [
                for (final l in lignesProforma)
                  LigneBrouillon(
                    module: module,
                    libelle: l.designation,
                    prixUnitaire: l.prixUnitaire,
                    quantite: l.quantite,
                  ),
              ],
            ),
          );
      factureId = piece.id;

      await (update(proformasLocal)..where((t) => t.id.equals(id))).write(
        ProformasLocalCompanion(
          statut: Value(StatutProforma.convertie.code),
          factureId: Value(piece.id),
        ),
      );
      await OperationsSyncDao(attachedDatabase).enfiler(
        table: TableSynchronisee.proformas,
        entiteId: id,
        type: TypeOperationSync.modification,
        payload: chargeProformaModification(
          statut: StatutProforma.convertie.code,
          factureId: piece.id,
        ),
      );
    });
    return factureId;
  }

  /// Pose le numéro DÉFINITIF rendu par le serveur à l'accusé (remplace le provisoire).
  /// Idempotent. Jamais deux numéros définitifs identiques : un numéro déjà porté par
  /// une AUTRE proforma est une incohérence — la régularisation LÈVE, rien n'est écrit.
  Future<void> regulariserNumero(String id, String numero) async {
    if (numero.isEmpty || estNumeroProformaProvisoire(numero)) return;
    await transaction(() async {
      final p = await parId(id);
      if (p == null || p.numero == numero) return;
      final autre =
          await (select(proformasLocal)
                ..where((t) => t.numero.equals(numero) & t.id.isNotValue(id)))
              .getSingleOrNull();
      if (autre != null) {
        throw StateError(
          'Le numéro $numero est déjà porté par une autre proforma du poste.',
        );
      }
      await (update(proformasLocal)..where((t) => t.id.equals(id))).write(
        ProformasLocalCompanion(numero: Value(numero)),
      );
    });
  }

  /* ------------------------------------------------------------------ interne */

  Future<ProformasLocalData> _exiger(String id) async =>
      await parId(id) ?? (throw const RefusProforma('Proforma introuvable.'));

  void _exigerModifiable(ProformasLocalData p) {
    if (!estModifiable(p)) {
      final etat = p.statut == StatutProforma.convertie.code
          ? 'convertie'
          : p.statut == StatutProforma.annulee.code
          ? 'annulée'
          : p.statut;
      throw RefusProforma(
        'Cette proforma est $etat : elle n’est plus modifiable.',
      );
    }
  }

  int _total(List<LigneProformaSaisie> lignes) {
    if (lignes.isEmpty) {
      throw const RefusProforma('Ajoutez au moins une ligne à la proforma.');
    }
    var total = 0;
    for (final l in lignes) {
      if (l.designation.trim().isEmpty ||
          l.quantite < 1 ||
          l.prixUnitaire < 0) {
        throw const RefusProforma(
          'Chaque ligne exige une désignation, une quantité entière et un prix unitaire en francs entiers.',
        );
      }
      total += l.quantite * l.prixUnitaire;
    }
    if (total > totalMax) {
      throw const RefusProforma(
        'Le montant de la proforma dépasse la limite admise.',
      );
    }
    return total;
  }

  Future<void> _ecrireLignes(
    String id,
    List<LigneProformaSaisie> lignes,
  ) async {
    for (var i = 0; i < lignes.length; i++) {
      final l = lignes[i];
      await into(lignesProformaLocal).insert(
        LignesProformaLocalCompanion.insert(
          id: _uuid.v4(),
          proformaId: id,
          position: i,
          designation: l.designation.trim(),
          quantite: l.quantite,
          prixUnitaire: l.prixUnitaire,
          montant: l.quantite * l.prixUnitaire,
        ),
      );
    }
  }

  ({String nom, String? telephone, String? ifu}) _client(
    String nom,
    String? telephone,
    String? ifu,
  ) {
    final n = nom.trim();
    if (n.isEmpty) {
      throw const RefusProforma('Le nom du client est obligatoire.');
    }
    if (!IfuClient.valide(ifu)) {
      throw const RefusProforma(
        'L’IFU du client doit compter exactement 13 chiffres.',
      );
    }
    return (
      nom: n.length > 150 ? n.substring(0, 150) : n,
      telephone: _net(telephone),
      ifu: IfuClient.nettoyer(ifu),
    );
  }

  String? _net(String? v) {
    final t = (v ?? '').trim();
    return t.isEmpty ? null : t;
  }

  DateTime _debutDuJour() {
    final m = _maintenant();
    return DateTime(m.year, m.month, m.day);
  }

  /// `PROV-FP-2026-00007` sous synchronisation ; sans file (démonstration), le même format
  /// sans prétendre à un numéro du serveur (rien ne le régularisera).
  Future<String> _numeroProvisoireSuivant(int annee) async {
    final courant = await (select(
      sequencesProformaLocal,
    )..where((s) => s.annee.equals(annee))).getSingleOrNull();
    final suivant = (courant?.dernierNumero ?? 0) + 1;
    await into(sequencesProformaLocal).insertOnConflictUpdate(
      SequencesProformaLocalCompanion.insert(
        annee: Value(annee),
        dernierNumero: suivant,
      ),
    );
    return formaterNumeroProformaProvisoire(annee, suivant);
  }
}
