/// Les formats d'affichage partagés.
///
/// **Ils vivaient dans `features/hebergement/presentation/widgets/
/// badge_synchronisation.dart`** — un badge de synchronisation. Tout écran qui
/// affiche un montant devait donc importer un widget d'un AUTRE domaine, ce que
/// la règle de dépendance du dépôt interdit : « un domaine ne référence un
/// autre domaine que pour les relations documentées au CdCF ».
///
/// Déplacés ici au moment où la Facturation en a eu besoin (21/08/2026) —
/// c'est-à-dire au moment où la dépendance croisée serait devenue réelle, et
/// non au moment où elle était seulement possible.
library;

/// Montant en francs CFA, sans décimale.
///
/// Le XOF n'a pas de sous-unité en circulation : afficher « 56 000,00 F »
/// suggère une précision qui n'existe pas et allonge inutilement la ligne.
String formaterFcfa(int montant) {
  final chiffres = montant.abs().toString();
  final groupes = <String>[];
  for (var i = chiffres.length; i > 0; i -= 3) {
    groupes.insert(0, chiffres.substring(i - 3 < 0 ? 0 : i - 3, i));
  }
  return '${montant < 0 ? '-' : ''}${groupes.join(' ')} FCFA';
}

/// Un montant reçu du serveur en `DECIMAL(15,2)` sérialisé (« 4500.00 »),
/// rendu comme le maître le rend.
///
/// ## Le suffixe est un PARAMÈTRE — et il vaut « FCFA » partout
///
/// L'ancien prototype écrivait « F » sur une page et « FCFA » sur une autre ;
/// le paramètre date de là. Depuis la décision du Product Owner du 11/09/2026
/// (PA-186, « on maintient FCFA dans tout »), le suffixe affiché est « FCFA »
/// PARTOUT, la PWA comprise : chaque appel passe `'FCFA'`. Ne pas réaligner
/// un écran sur « F ».
///
/// ## Le calcul reste ENTIER
///
/// Aucun `double` n'apparaît : `4500.50` est arrondi à l'entier supérieur par
/// comparaison des centièmes, exactement comme le `Math.round` du maître, et
/// jamais en passant par un flottant qui réarrondirait à l'affichage
/// (règle projet depuis PA-55).
///
/// `null` sur toute entrée illisible — **jamais zéro** : un montant que le
/// serveur n'a pas rendu n'est pas un montant nul, et les confondre afficherait
/// « 0 F » sur un plat dont on ignore le prix (Article 7).
String? formaterMontantDecimal(String? brut, {required String suffixe}) {
  if (brut == null) return null;

  final texte = brut.trim().replaceAll(',', '.');
  if (!RegExp(r'^-?\d+(\.\d+)?$').hasMatch(texte)) return null;

  final negatif = texte.startsWith('-');
  final absolu = negatif ? texte.substring(1) : texte;
  final point = absolu.indexOf('.');

  final unites = int.tryParse(point < 0 ? absolu : absolu.substring(0, point));
  if (unites == null) return null;

  // Les deux premières décimales, complétées à droite : « .5 » vaut cinquante
  // centièmes, pas cinq. `padLeft` diviserait la partie décimale par dix.
  final decimales = point < 0
      ? '00'
      : absolu.substring(point + 1).padRight(2, '0').substring(0, 2);
  final centiemes = int.tryParse(decimales) ?? 0;

  final arrondi = centiemes >= 50 ? unites + 1 : unites;

  return '${negatif ? '-' : ''}${_grouper(arrondi)} $suffixe';
}

/// Les milliers séparés par une espace — `Intl.NumberFormat('fr-FR')`.
String _grouper(int valeur) {
  final chiffres = valeur.toString();
  final groupes = <String>[];
  for (var i = chiffres.length; i > 0; i -= 3) {
    groupes.insert(0, chiffres.substring(i - 3 < 0 ? 0 : i - 3, i));
  }
  return groupes.join(' ');
}

/// Date au format court français — `toLocaleDateString('fr-FR')` du maître.
String formaterDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/'
    '${d.month.toString().padLeft(2, '0')}/'
    '${d.year}';

/// Date et heure `d/m/Y H:i` — le `format('d/m/Y H:i')` du serveur (échéance du
/// mot de passe temporaire, 29/10/2026).
String formaterDateHeure(DateTime d) =>
    '${formaterDate(d)} '
    '${d.hour.toString().padLeft(2, '0')}:'
    '${d.minute.toString().padLeft(2, '0')}';
