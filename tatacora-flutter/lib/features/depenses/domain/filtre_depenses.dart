import 'categories_depense.dart';
import 'entities/depense.dart';

/// Les cinq filtres de la barre du maître : recherche, « À partir du »,
/// « Jusqu'au », trésorerie, catégorie.
///
/// ## Chaque champ peut être REMIS À VIDE
///
/// D'où des fabriques explicites plutôt qu'un `copyWith` : avec un `copyWith`
/// classique, passer `null` veut dire « ne change pas », et il devient
/// impossible d'effacer une date — le bouton « Réinitialiser » du maître ne
/// pourrait pas faire son travail sur un seul champ.
final class FiltreDepenses {
  const FiltreDepenses({
    this.terme = '',
    this.du,
    this.au,
    this.tresorerie,
    this.famille,
  });

  /// Invite du maître : « Libellé, nature, compte… ».
  final String terme;

  /// Bornes **incluses**, comparées au jour : une dépense du 12 entre dans
  /// « jusqu'au 12 ». Ce n'est pas le demi-ouvert d'une réservation, où le
  /// jour du départ n'est pas une nuit — ici, la date est celle d'un
  /// décaissement, pas d'une plage.
  final DateTime? du;
  final DateTime? au;

  final TresorerieDepense? tresorerie;

  /// La catégorie du filtre est la **famille** (« Marché », « Services »), pas
  /// la nature : c'est ce que le maître propose dans sa liste, qui est bâtie
  /// sur les clés de son registre.
  final FamilleDepense? famille;

  bool get applique =>
      terme.trim().isNotEmpty ||
      du != null ||
      au != null ||
      tresorerie != null ||
      famille != null;

  FiltreDepenses avecTerme(String valeur) => FiltreDepenses(
    terme: valeur,
    du: du,
    au: au,
    tresorerie: tresorerie,
    famille: famille,
  );

  FiltreDepenses avecDu(DateTime? valeur) => FiltreDepenses(
    terme: terme,
    du: valeur,
    au: au,
    tresorerie: tresorerie,
    famille: famille,
  );

  FiltreDepenses avecAu(DateTime? valeur) => FiltreDepenses(
    terme: terme,
    du: du,
    au: valeur,
    tresorerie: tresorerie,
    famille: famille,
  );

  FiltreDepenses avecTresorerie(TresorerieDepense? valeur) => FiltreDepenses(
    terme: terme,
    du: du,
    au: au,
    tresorerie: valeur,
    famille: famille,
  );

  FiltreDepenses avecFamille(FamilleDepense? valeur) => FiltreDepenses(
    terme: terme,
    du: du,
    au: au,
    tresorerie: tresorerie,
    famille: valeur,
  );

  /// Le filtre en toutes lettres — il PART avec le document (PA-119).
  ///
  /// Quelqu'un qui filtre puis exporte attend son filtre ; lui rendre le
  /// registre entier lui ferait envoyer au comptable un document qu'il croit
  /// avoir vérifié. Et un document qui ne dit pas sa portée se lit comme s'il
  /// portait tout.
  String get description {
    final morceaux = <String>[];

    if (terme.trim().isNotEmpty) {
      morceaux.add('recherche « ${terme.trim()} »');
    }
    if (du != null) morceaux.add('à partir du ${_jj(du!)}');
    if (au != null) morceaux.add('jusqu\'au ${_jj(au!)}');
    if (tresorerie != null) {
      morceaux.add('trésorerie « ${tresorerie!.libelle} »');
    }
    if (famille != null) morceaux.add('catégorie « ${famille!.libelle} »');

    return morceaux.isEmpty
        ? 'Registre entier, aucun filtre appliqué'
        : morceaux.join(' · ');
  }

  static String _jj(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';
}

/// La liste **telle que l'écran l'affiche**.
///
/// Fonction pure : c'est elle que l'export emporte, et c'est elle que les six
/// indicateurs somment. Trois chemins, une seule règle de filtrage — la
/// dupliquer ferait diverger la bande, le tableau et le fichier.
List<Depense> filtrerDepenses(
  List<Depense> depenses,
  FiltreDepenses filtre, {
  LibellesDesComptes libelles = const LibellesDesComptes(),
}) {
  final terme = filtre.terme.trim().toLowerCase();
  final du = filtre.du == null ? null : _jour(filtre.du!);
  final au = filtre.au == null ? null : _jour(filtre.au!);

  return depenses
      .where((depense) {
        if (du != null && _jour(depense.dateTransaction).isBefore(du)) {
          return false;
        }
        if (au != null && _jour(depense.dateTransaction).isAfter(au)) {
          return false;
        }

        if (filtre.tresorerie != null &&
            depense.tresorerie != filtre.tresorerie) {
          return false;
        }

        // La famille vit sur les LIGNES : une pièce est retenue dès qu'une de ses
        // lignes relève de la famille demandée — le `whereHas` du serveur, et pour
        // la même raison : un marché du matin mêlant tomates et transport doit
        // apparaître dans les deux catégories.
        if (filtre.famille != null &&
            !depense.familles.contains(filtre.famille!.libelle)) {
          return false;
        }

        if (terme.isEmpty) return true;
        return _correspond(depense, terme, libelles);
      })
      .toList(growable: false);
}

/// « Libellé, nature, compte… » — les trois que l'invite du maître annonce.
///
/// Le serveur cherche en plus dans le numéro de pièce ; ce poste n'en alloue
/// aucun (voir `depenses_tables.dart`). Le libellé de chaque LIGNE est
/// également relu : c'est là que vit « Tomates fraîches », et chercher un achat
/// sans le trouver ferait conclure qu'il n'a pas été saisi.
bool _correspond(Depense depense, String terme, LibellesDesComptes libelles) {
  if (depense.libelle.toLowerCase().contains(terme)) return true;

  for (final ligne in depense.lignes) {
    if (ligne.libelle.toLowerCase().contains(terme)) return true;
    if (ligne.nature.toLowerCase().contains(terme)) return true;
    if (ligne.compteCharge.toLowerCase().contains(terme)) return true;

    final libelleCompte = libelles.de(ligne.compteCharge);
    if (libelleCompte != null && libelleCompte.toLowerCase().contains(terme)) {
      return true;
    }
  }

  return false;
}

DateTime _jour(DateTime d) => DateTime(d.year, d.month, d.day);
