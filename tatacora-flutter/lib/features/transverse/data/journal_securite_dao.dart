import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/auteur_ecriture.dart';
import '../domain/journal_poste.dart';

/// L'UNIQUE écrivain de `journal_securite_local` — le journal de sécurité du
/// poste (v46, 29/10/2026, mot de passe perdu SANS e-mail).
///
/// Le poste n'a pas de table d'audit : son Journal d'Audit relit la file
/// d'envoi, qui ne porte que ce qui part au serveur. Une réinitialisation de mot
/// de passe ne doit JAMAIS y entrer (les comptes ne se synchronisent pas) : elle
/// est consignée ICI, en local, et le Journal d'Audit lit les deux.
///
/// ## Jamais un secret
///
/// [tracer] ne prend ni mot de passe, ni code, ni dérivé : QUI (le compte
/// connecté), QUEL compte, QUAND, depuis QUELLE machine.
///
/// ## Dans la transaction du geste
///
/// [tracer] s'appelle DANS la transaction qui écrit le geste (Drift rejoint la
/// transaction ambiante) : un geste sans trace, ou une trace sans geste, ne
/// peut pas exister.
class JournalSecuriteDao {
  JournalSecuriteDao(this._base, {DateTime Function()? horloge})
    : _horloge = horloge ?? DateTime.now;

  final AppDatabase _base;
  final DateTime Function() _horloge;

  static const _uuid = Uuid();

  /// Consigne un geste. [auteurLogin] est le compte connecté (`null` : personne,
  /// le recours par code de secours se fait sans session) ; le nom du poste est
  /// celui de la machine.
  Future<void> tracer({
    required ActionJournalPoste action,
    String? auteurLogin,
    String? cibleId,
    String? cibleLogin,
  }) async {
    assert(
      action.estDeSecurite,
      'Seules les actions de sécurité se consignent ici.',
    );
    await _base
        .into(_base.journalSecuriteLocal)
        .insert(
          JournalSecuriteLocalCompanion.insert(
            id: _uuid.v4(),
            action: action.code,
            auteurLogin: Value(auteurLogin),
            posteNom: Value(nomDuPosteLocal()),
            cibleId: Value(cibleId),
            cibleLogin: Value(cibleLogin),
            creeLe: _horloge(),
          ),
        );
  }

  /// Toutes les entrées, les plus récentes d'abord.
  Future<List<EntreeSecurite>> entrees() => (_base.select(
    _base.journalSecuriteLocal,
  )..orderBy([(t) => OrderingTerm.desc(t.creeLe)])).get();

  /// Les refus du code de secours depuis [depuis] (les tentatives BLOQUÉES ne
  /// comptent pas : un blocage qui se prolongerait à chaque essai ne finirait
  /// jamais).
  Future<List<DateTime>> refusDepuis(DateTime depuis) async {
    final lignes =
        await (_base.select(_base.journalSecuriteLocal)
              ..where(
                (t) =>
                    t.action.equals(ActionJournalPoste.codeSecoursRefuse.code) &
                    t.creeLe.isBiggerOrEqualValue(depuis),
              )
              ..orderBy([(t) => OrderingTerm.desc(t.creeLe)]))
            .get();
    return [for (final l in lignes) l.creeLe];
  }
}
