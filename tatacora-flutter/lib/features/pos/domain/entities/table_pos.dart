import 'espace_pos.dart';

/// Une table de salle.
///
/// Entité de domaine : ni l'écran ni le cas d'usage ne voient jamais la ligne
/// Drift, pour que la bascule offline/online reste invisible à l'interface.
final class TablePos {
  const TablePos({
    required this.id,
    required this.espace,
    required this.numero,
    required this.libelle,
    required this.places,
    required this.actif,
  });

  final String id;
  final EspacePos espace;
  final int numero;

  /// `T3`, `J2`, `P1` — dérivé du préfixe et du numéro à l'écriture.
  final String libelle;

  final int places;

  /// Désactivée, jamais supprimée : une table effacée laisserait les ventes
  /// passées pointer vers un identifiant inexistant.
  final bool actif;
}

/// Une case de la salle : la table, **et son occupation déduite**.
///
/// L'occupation n'est pas un champ de [TablePos] : elle ne vient pas du
/// référentiel mais des paniers, et la porter sur l'entité laisserait croire
/// qu'elle se persiste.
final class CaseSalle {
  const CaseSalle({required this.table, this.panierOuvertId});

  final TablePos table;

  /// L'identifiant du panier ouvert sur cette table, ou `null`.
  final String? panierOuvertId;

  /// Les quatre états que le maître distingue, et qu'il ne faut jamais
  /// confondre :
  ///
  ///  - **fermée** — désactivée en Paramètres, mais toujours visible ;
  ///  - **libre** — active, aucun panier ;
  ///  - **ouverte** — un panier existe mais il est **vide** : la table est
  ///    prise, rien n'est commandé. La confondre avec « en cours » ferait
  ///    croire qu'une commande est passée ;
  ///  - **en cours** — des consommations sont servies.
  ///
  /// [ouverte] et [enCours] se distinguent par les lignes, que cette entité ne
  /// porte pas : c'est l'appelant qui tranche, avec le panier en main.
  bool get occupee => panierOuvertId != null;

  bool get libre => table.actif && !occupee;

  bool get fermee => !table.actif;
}

/// Les tables d'un espace — ce qu'un bloc du panneau Salle affiche.
final class RayonSalle {
  const RayonSalle({required this.espace, required this.cases});

  final EspacePos espace;
  final List<CaseSalle> cases;
}
