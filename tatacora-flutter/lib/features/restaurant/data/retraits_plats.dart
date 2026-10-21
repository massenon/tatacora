import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../pos/data/dto/catalogue_dto.dart' show IndisponibiliteDistante;
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

  /// Les retraits en cours, par plat — de quoi rendre la colonne « Disponible »
  /// du catalogue et le motif en ambre, comme la vue.
  Future<Map<String, IndisponibiliteDistante>> retires() =>
      _retraits.platsRetires();

  /// Ce qui EMPÊCHE de retirer ce plat de la carte, en clair — les deux verrous
  /// de la vue (`verrousDuPlat`), dans son ordre.
  ///
  /// Écart nommé : la vue compte les commandes du restaurant en préparation ou
  /// transmises à la cuisine. Ce poste n'a pas de table de commandes ; son
  /// équivalent est l'addition OUVERTE (panier non clôturé) qui porte une ligne
  /// de ce plat. L'identifiant cité est celui de l'addition, tronqué à huit
  /// caractères.
  Future<List<String>> verrous(String platId) async {
    final verrous = <String>[];

    final retrait = (await _retraits.platsRetires())[platId];
    if (retrait != null) {
      verrous.add(
        'Ce plat est déjà retiré de la carte (${retrait.libelle}). Il se '
        'remet en ligne depuis la carte du restaurant.',
      );
    }

    final p = _db.paniersLocal;
    final l = _db.lignesPanierLocal;
    final engages =
        await (_db.select(p).join([innerJoin(l, l.panierId.equalsExp(p.id))])
              ..where(
                p.statut.equals('ouvert') &
                    l.moduleSource.equals('M4') &
                    l.codeArticle.equals(platId),
              )
              ..orderBy([OrderingTerm.desc(p.ouvertLe)]))
            .get();
    final paniers = {
      for (final ligne in engages) ligne.readTable(p).id,
    }.take(5).toList();
    if (paniers.isNotEmpty) {
      final liste = paniers.map((id) => id.substring(0, 8)).join(', ');
      verrous.add(
        'Élément engagé dans ${paniers.length} commande(s) en cours : $liste',
      );
    }
    return verrous;
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
