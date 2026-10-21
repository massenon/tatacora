import '../../../core/database/app_database.dart';
import '../../bar/data/boissons_api.dart' show ResultatBar, BarRecu, BarRefuse;
import '../../bar/domain/motif_indisponibilite.dart';
import '../../pos/data/indisponibilites_carte_dao.dart';

/// Le retrait d'un PLAT de la carte du jour (M4), côté poste — 21/10/2026.
///
/// Même geste que la boisson (`BoissonsApi.retirer`), même table, même file
/// d'envoi : [IndisponibilitesCarteDao] en est l'unique écrivain. Ce fichier ne
/// fait que valider (plat connu, motif du registre fermé, commentaire borné) et
/// DIRE le refus, au féminin comme au masculin près.
class RetraitsPlats {
  RetraitsPlats(this._db, {IndisponibilitesCarteDao? retraits})
    : _retraits = retraits ?? IndisponibilitesCarteDao(_db);

  final AppDatabase _db;
  final IndisponibilitesCarteDao _retraits;

  /// Rend le libellé du plat retiré.
  Future<ResultatBar<String>> retirer({
    required String platId,
    required String motif,
    String? commentaire,
  }) async {
    final m = MotifIndisponibilite.values
        .where((x) => x.code == motif)
        .firstOrNull;
    if (m == null) {
      return BarRefuse(
        motif: 'Le motif « $motif » n’existe pas.',
        erreurs: {'motif': 'Choisissez un des motifs proposés.'},
      );
    }
    final libelle = await _libelle(platId);
    if (libelle == null) return _introuvable();
    if ((commentaire?.trim().length ?? 0) > 500) {
      return const BarRefuse(
        motif: 'Le commentaire est trop long.',
        erreurs: {'commentaire': '500 caractères au plus.'},
      );
    }
    final ecrit = await _retraits.retirer(
      platId: platId,
      motif: m,
      commentaire: commentaire,
    );
    if (ecrit == null) {
      final dit = '« $libelle » est déjà retiré de la carte du jour.';
      return BarRefuse(motif: dit, erreurs: {'etat': dit});
    }
    return BarRecu(libelle);
  }

  /// Remet le plat à la carte ; refusé en le disant quand rien n'est retiré.
  Future<ResultatBar<String>> remettre(String platId) async {
    final libelle = await _libelle(platId);
    if (libelle == null) return _introuvable();
    if (!await _retraits.remettre(platId: platId)) {
      final dit = '« $libelle » n’est pas retiré de la carte du jour.';
      return BarRefuse(motif: dit, erreurs: {'etat': dit});
    }
    return BarRecu(libelle);
  }

  Future<String?> _libelle(String platId) async {
    final p = _db.platsLocal;
    final ligne = await (_db.select(
      p,
    )..where((x) => x.id.equals(platId))).getSingleOrNull();
    return ligne?.libelle;
  }

  ResultatBar<String> _introuvable() =>
      const BarRefuse(motif: 'Ce plat n’existe pas sur ce poste.');
}
