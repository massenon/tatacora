/// Préparation du texte d'un ticket avant composition.
///
/// ## Le défaut que ce module évite, constaté en D0.6
///
/// Les polices intégrées au format PDF (Helvetica et consorts) couvrent
/// **Latin-1**, pas l'Unicode. Constaté sur un ticket d'essai :
///
/// - `GÎTE`, `NOËL`, `Béninoise`, `braisé`, `DÉMONSTRATION` sortent **corrects** ;
/// - le tiret cadratin `—` (U+2014) **disparaît**, sans erreur ni message.
///
/// « Natitingou — Bénin » s'imprime donc « Natitingou  Bénin ».
///
/// **C'est la disparition silencieuse qui est le problème, pas le tiret.** Un
/// caractère absent ne se voit pas : le texte reste lisible, simplement amputé.
/// Or huit fichiers du client emploient l'apostrophe typographique `’`
/// (U+2019), elle aussi hors Latin-1 : « l’addition » s'imprimerait
/// « laddition », et personne ne saurait dire d'où vient la faute.
///
/// ## Pourquoi normaliser plutôt que d'embarquer une police Unicode
///
/// Trois raisons, dans cet ordre :
///
/// 1. **Une imprimante thermique de comptoir n'est pas une imprimante de
///    bureau.** Elle rend un jeu restreint ; lui envoyer des tirets cadratins
///    et des guillemets courbes, c'est déplacer le problème du PDF vers le
///    papier.
/// 2. **Aucune police ne se télécharge à l'exécution.** Le poste du Gîte
///    travaille hors connexion ; une police récupérée sur le réseau au moment
///    d'imprimer serait le seul endroit du logiciel qui exigerait Internet
///    pour encaisser.
/// 3. Embarquer un fichier de police reste possible plus tard, et cette
///    normalisation n'y fera pas obstacle.
///
/// Ce module **ne touche pas aux accents** : ils fonctionnent, les retirer
/// appauvrirait le ticket sans raison.
library;

/// Substitutions appliquées avant composition.
///
/// Registre **fermé** et volontairement court : chaque entrée est un caractère
/// dont on a constaté qu'il disparaît. Y ajouter des accents serait une faute —
/// ils passent, et « Beninoise » sur un ticket ferait mauvais effet là où
/// « Béninoise » sort très bien.
const Map<String, String> substitutionsImpression = {
  '—': '-', // — tiret cadratin
  '–': '-', // – tiret demi-cadratin
  '’': "'", // ’ apostrophe typographique
  '‘': "'", // ‘
  '“': '"', // “
  '”': '"', // ”
  '…': '...', // … points de suspension
  ' ': ' ', // espace insécable
  ' ': ' ', // espace fine insécable
  '−': '-', // − signe moins
  '×': 'x', // × signe multiplier
  // → flèche vers la droite. Constatée le 25/08/2026 sur la confirmation de
  // réservation, qui écrit « 20/09/2026 → 22/09/2026 ». Elle disparaissait
  // en silence : la période se serait imprimée « 20/09/2026  22/09/2026 »,
  // deux dates sans rien entre elles, et rien n'aurait dit laquelle est
  // l'arrivée.
  '→': '->',
};

/// Prépare un texte pour l'impression.
///
/// Renvoie le texte avec les caractères non imprimables substitués. Les
/// accents Latin-1 sont conservés tels quels.
String texteTicket(String? source) {
  if (source == null || source.isEmpty) return '';
  var t = source;
  substitutionsImpression.forEach((de, vers) => t = t.replaceAll(de, vers));
  return t;
}

/// Caractères qui seraient perdus à l'impression, s'il en reste.
///
/// Sert de garde-fou : un test peut vérifier qu'un ticket composé n'en contient
/// aucun, plutôt que de constater l'amputation après coup sur le papier.
///
/// La borne est Latin-1 (U+00FF) parce que c'est exactement ce que couvrent les
/// polices intégrées du format PDF — ni plus, ni moins.
List<String> caracteresNonImprimables(String source) {
  final restants = <String>{};
  for (final rune in source.runes) {
    if (rune > 0xFF) restants.add(String.fromCharCode(rune));
  }
  return restants.toList()..sort();
}
