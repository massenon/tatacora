/// ⚠ **POINT Q1 — le rattachement d'une ligne de panier à son catalogue.**
///
/// Ce fichier est le **seul endroit** du client Flutter où se décide comment
/// une ligne de panier désigne l'article qu'elle vend. Si l'Architecte tranche
/// Q1 autrement que ce qui est porté ici, c'est ce fichier qu'on rouvre —
/// plus la colonne `moduleSource`/`codeArticle` de `panier_tables.dart` et la
/// vérification de `PanierDao.ajouterLigne`. Rien d'autre.
///
/// ## Ce que le document propose, et pourquoi ce n'est pas ce qui est porté
///
/// `docs/PROPOSITION_MODELE_PANIER_POS.md` §3 retient l'**option A** : quatre
/// clés étrangères nullables (`boisson_id`, `plat_id`, `circuit_id`,
/// `vehicule_id`) dont exactement une est renseignée, sous contrainte `CHECK`.
/// Elle **exclut** l'option C — un `type` et un identifiant libre — parce que
/// c'est exactement le défaut de `commandes_restaurant.table_ou_chambre_id`
/// (PA-76), où le champ peut viser une table de restaurant qui n'existe pas.
///
/// **L'option A n'était pas portable telle quelle sur ce client**, et il fallait
/// le dire plutôt que de l'approcher en silence : la table `plats` (M4
/// Restaurant) **n'était pas répliquée localement**. On ne déclare pas une clé
/// étrangère vers une table absente, et on n'ajoute pas une table au périmètre
/// offline « pendant qu'on y est ».
///
/// ## Ce qui est porté à la place : un registre fermé + une vérification réelle
///
/// Le rattachement tient en deux valeurs, `module` et `code`. Ce n'est pas
/// l'option C pour autant, et la différence est celle qui compte :
///
///  - `module` est un **enum fermé** — on ne peut pas écrire une valeur qui ne
///    désigne aucun catalogue ;
///  - `code` est **vérifié contre le catalogue local** avant écriture, pour les
///    QUATRE modules (M4, M5, M8, M9). Une ligne dont le code ne désigne rien
///    est refusée, comme le ferait une clé étrangère.
///
/// **La limite de M4 est levée le 09/10/2026** (schéma v14, `plats_local`) : M4
/// était le seul module dont le code n'était adossé à rien. Le rattachement reste
/// un couple (module, code) et non quatre clés nullables — l'arbitrage Q1 de
/// l'Architecte reste ouvert, et tient dans ce seul fichier.
library;

/// Les catalogues vendables, et rien d'autre.
///
/// Registre **fermé**, jamais dérivé d'une chaîne libre : c'est lui qui
/// distingue ce modèle de l'identifiant polymorphe que le document exclut.
/// Les codes reprennent la numérotation des modules du CdCF.
enum ModuleVendable {
  /// M4 Restaurant — `plats_local` (schéma v14, 09/10/2026).
  m4Restaurant('M4', 'Restaurant'),

  /// M5 Bar — `cartes_boisson`.
  m5Bar('M5', 'Bar'),

  /// M8 Véhicules — `vehicules`, au tarif jour.
  m8Vehicules('M8', 'Location'),

  /// M9 Tourisme — `circuits`.
  m9Tourisme('M9', 'Tourisme');

  const ModuleVendable(this.code, this.libelle);

  final String code;
  final String libelle;

  /// Le catalogue de ce module est-il dans la base locale ?
  ///
  /// Vrai pour les quatre depuis le 09/10/2026. Le getter reste : il sert à
  /// l'écran, qui doit **dire** pourquoi un rayon est vide plutôt que de
  /// l'afficher sans article — un filtre qui ne rend jamais rien passe pour
  /// cassé (leçon PA-90).
  bool get replicationLocale => true;

  /// Un code inconnu n'est **jamais** deviné : la lecture échoue.
  ///
  /// Retomber sur `m5Bar` par défaut ferait apparaître une prestation de
  /// tourisme dans la ventilation du bar, et le chiffre serait faux sans que
  /// rien ne le signale.
  static ModuleVendable depuisCode(String code) => values.firstWhere(
    (m) => m.code == code,
    orElse: () =>
        throw ArgumentError.value(code, 'code', 'Module vendable inconnu'),
  );
}

/// Le rattachement d'une ligne de panier à son catalogue d'origine.
final class ReferenceCatalogue {
  const ReferenceCatalogue({required this.module, required this.code});

  final ModuleVendable module;

  /// Identifiant de l'article dans le catalogue de son module.
  final String code;

  @override
  bool operator ==(Object other) =>
      other is ReferenceCatalogue &&
      other.module == module &&
      other.code == code;

  @override
  int get hashCode => Object.hash(module, code);

  @override
  String toString() => '${module.code}:$code';
}
