import '../../../core/database/app_database.dart';
import '../../rh/data/paie_dao.dart';
import '../../rh/domain/entities/taux_paie.dart';
import '../../synchronisation/data/operations_sync_dao.dart';
import '../../synchronisation/domain/charges_synchronisation.dart';
import '../../synchronisation/domain/operation_sync.dart';
import '../domain/enregistrer_parametres.dart';
import '../domain/registre_parametres_local.dart';
import 'parametres_dao.dart';
import 'package:uuid/uuid.dart';

/// Le stockage LOCAL des paramètres — deux tables, un seul registre.
///
/// ## Qui possède quoi (piège 11 : un référentiel n'a qu'UN auteur)
///
///  * Les 26 clés ordinaires vivent dans `parametres_systeme_local`, dont
///    `ParametresDao` est l'unique auteur.
///  * Les 5 taux de charges sociales ([RegistreParametresLocal.clesDeLaPaie])
///    vivent dans `taux_paie_local`, dont `PaieDao` est l'unique auteur : c'est
///    là que le calcul de la paie les lit. Les copier dans l'autre table
///    ferait deux sources pour un même taux, chacune se croyant la bonne
///    (PA-160/161). Ce dépôt ne fait que ROUTER.
///
/// L'écriture des deux se fait dans UNE transaction de la base : un lot dont
/// une moitié échoue n'écrit rien.
final class ParametresDepotLocal implements StockageParametres {
  ParametresDepotLocal(this._base, {PaieDao? paie, ParametresDao? parametres})
    : _paie = paie ?? PaieDao(_base),
      _parametres = parametres ?? ParametresDao(_base);

  final AppDatabase _base;
  final PaieDao _paie;
  final ParametresDao _parametres;

  static bool _estDeLaPaie(String cle) =>
      RegistreParametresLocal.clesDeLaPaie.contains(cle);

  @override
  Future<Map<String, String>> lireTout() async {
    final ordinaires = await _parametres.lireTout();
    final taux = await _paie.taux();
    return {
      // Seules les clés du registre : `taux_paie_local` peut porter d'autres
      // lignes (le référentiel de la paie n'est pas le nôtre), qui n'ont pas à
      // apparaître dans un écran dont le registre est fermé.
      for (final e in ordinaires.entries)
        if (RegistreParametresLocal.existe(e.key) && !_estDeLaPaie(e.key))
          e.key: e.value,
      for (final cle in RegistreParametresLocal.clesDeLaPaie)
        if (taux[cle] != null) cle: taux[cle]!,
    };
  }

  /// Pose les paramètres INITIAUX d'un poste vierge
  /// ([parametresEtablissementInitiaux], `ParametresEtablissementSeeder` du
  /// serveur) — chaque clé ABSENTE seulement, jamais une valeur déjà saisie.
  /// Routés comme toute écriture : les taux de la paie par `PaieDao`, les
  /// autres par `ParametresDao`, dans UNE transaction.
  ///
  /// Appelants : la création du premier compte (`FormulairePremierCompte`,
  /// le seul moment où le poste est vierge) et « Réinitialiser comme neuf »
  /// (`ReinitialisationLocale.executer`). Aucune migration, aucun démarrage :
  /// une clé vidée exprès à l'écran ne revient pas d'elle-même.
  Future<void> installerParametresInitiaux() {
    return _base.transaction(() async {
      await _paie.installerReferentielConfirme(
        confirmes: [
          for (final p in parametresEtablissementInitiaux)
            if (_estDeLaPaie(p.cle))
              TauxConfirme(
                cle: p.cle,
                valeur: p.valeur,
                description: p.description ?? '',
              ),
        ],
      );
      await _parametres.semerSiAbsentes({
        for (final p in parametresEtablissementInitiaux)
          if (!_estDeLaPaie(p.cle)) p.cle: p.valeur,
      });
    });
  }

  @override
  Future<List<String>> ecrire(
    Map<String, String?> valeurs, {
    required String? auteurId,
  }) {
    return _base.transaction(() async {
      final modifiees = <String>[];

      // Les taux de la paie D'ABORD, les clés ordinaires ensuite : si l'écriture
      // ordinaire échoue (clé étrangère de l'auteur, disque), la transaction
      // défait aussi les taux déjà écrits. Dans l'ordre inverse, le test
      // d'atomicité ne prouverait rien — l'échec précéderait toute écriture de
      // la paie.
      for (final e in valeurs.entries) {
        if (!_estDeLaPaie(e.key)) continue;
        final v = e.value;
        final change = v == null
            ? await _paie.retirerTaux(e.key)
            : await _paie.enregistrerTaux(e.key, v);
        if (change) modifiees.add(e.key);
      }

      final ordinaires = <String, String?>{
        for (final e in valeurs.entries)
          if (!_estDeLaPaie(e.key)) e.key: e.value,
      };
      modifiees.addAll(
        await _parametres.ecrire(ordinaires, auteurId: auteurId),
      );
      // Lot 10e : UN enregistrement part au serveur — les clés réellement
      // modifiées, en lot (la cohérence s'y juge sur l'état résultant).
      if (modifiees.isNotEmpty) {
        await OperationsSyncDao(_base).enfiler(
          table: TableSynchronisee.parametresSysteme,
          entiteId: const Uuid().v4(),
          type: TypeOperationSync.creation,
          payload: chargeEnregistrementParametres({
            for (final cle in modifiees) cle: valeurs[cle],
          }),
        );
      }
      return modifiees;
    });
  }

  /// Une valeur DESCENDUE du serveur (lot 10e), routée comme toute
  /// écriture — les taux de la paie par `PaieDao`, les autres par
  /// `ParametresDao` — et jamais renvoyée. `null` (vide au serveur) vide la
  /// clé. Une clé hors du registre du poste est ignorée : rien ici ne la lit.
  /// Seul appelant : l'aligneur du catalogue.
  Future<void> inscrireDescendue(String cle, String? valeur) async {
    if (RegistreParametresLocal.parCle(cle) == null) return;
    if (_estDeLaPaie(cle)) {
      valeur == null
          ? await _paie.retirerTaux(cle)
          : await _paie.enregistrerTaux(cle, valeur, duServeur: true);
      return;
    }
    await _parametres.inscrireDescendue(cle, valeur);
  }
}
