import 'package:flutter/painting.dart';

/// La largeur « max-content » d'un texte : sur une seule ligne, sans borne.
///
/// Sert à poser les bases d'un partage flex ([partagerRetrecissement]). Le
/// navigateur et Flutter ne mesurent pas un texte au pixel près ; la mesure est
/// donc faite **par Flutter**, avec le style qui sera réellement peint — un
/// plancher mesuré par un autre moteur ferait couper un mot en deux.
double largeurMaxContent(String texte, TextStyle style) {
  final peintre = TextPainter(
    text: TextSpan(text: texte, style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  final largeur = peintre.width;
  peintre.dispose();
  return largeur;
}

/// La largeur « min-content » d'un texte : celle de son plus long mot.
///
/// C'est le plancher d'un élément flex dont le contenu se replie (le
/// `min-width: auto` du navigateur).
double largeurMinContent(String texte, TextStyle style) {
  var plus = 0.0;
  for (final mot in texte.split(' ')) {
    if (mot.isEmpty) continue;
    final largeur = largeurMaxContent(mot, style);
    if (largeur > plus) plus = largeur;
  }
  return plus;
}
