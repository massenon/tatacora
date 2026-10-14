/// Les espaces de service — **registre fermé**, porté de `tables-engine.js`.
///
/// ## Pourquoi les espaces sont fermés et les tables ne le sont pas
///
/// Les **tables** se créent, se renomment, s'activent et se désactivent depuis
/// Paramètres, sans intervention technique : leur nombre change avec la
/// saison. Les **espaces**, eux, forment un registre fermé — ajouter un espace
/// change la convention de nommage et l'organisation du service, ce qui ne
/// relève pas d'un écran de paramétrage.
///
/// ## Le comptoir n'a pas de table, et c'est structurel
///
/// Une vente au comptoir n'a **aucune** table associée : `tableId` reste nul.
/// Lui en inventer une (« Comptoir 1 ») créerait une table qu'il faudrait
/// ensuite ouvrir, fermer et compter comme les autres, alors qu'elle ne
/// correspond à rien dans la salle.
///
/// @see prototype_v2/assets/js/tables-engine.js
library;

enum EspacePos {
  restaurant(code: 'restaurant', libelle: 'Restaurant', prefixe: 'R'),
  jardin(code: 'jardin', libelle: 'Jardin', prefixe: 'J'),
  plage(code: 'plage', libelle: 'Plage', prefixe: 'P'),

  /// Sans préfixe **et sans tables** — voir l'en-tête.
  comptoir(code: 'comptoir', libelle: 'Comptoir', prefixe: '');

  const EspacePos({
    required this.code,
    required this.libelle,
    required this.prefixe,
  });

  /// Le code persisté, identique à celui du maître.
  final String code;

  final String libelle;

  /// La lettre qui précède le numéro : `T3`, `J2`, `P1`.
  final String prefixe;

  /// Un espace porte-t-il des tables ?
  ///
  /// Dérivé du préfixe plutôt que déclaré à part : les deux ne peuvent pas
  /// diverger, et un espace sans préfixe ne saurait de toute façon pas nommer
  /// ses tables.
  bool get avecTables => prefixe.isNotEmpty;

  /// Les espaces qui apparaissent dans le panneau Salle.
  static List<EspacePos> get avecTablesSeulement =>
      values.where((e) => e.avecTables).toList();

  /// Relit un code persisté.
  ///
  /// Lève plutôt que de rendre un repli : une table rangée dans un espace
  /// inconnu disparaîtrait de la salle sans un mot, et le serveur la
  /// chercherait.
  static EspacePos parCode(String code) => values.firstWhere(
    (e) => e.code == code,
    orElse: () =>
        throw ArgumentError.value(code, 'code', 'Espace de service inconnu.'),
  );
}
