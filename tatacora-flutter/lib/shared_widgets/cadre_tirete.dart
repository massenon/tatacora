/// Un cadre à bordure TIRETÉE — le `border-dashed` de Tailwind, que Flutter
/// n'a pas en natif (`BorderStyle` ne connaît que `solid` et `none`).
///
/// ## Ce que rejoue ce widget, et ce qu'il ne rejoue pas
///
/// Une bordure CSS est peinte DANS la boîte : elle repousse le contenu de son
/// épaisseur, et son trait est centré à mi-épaisseur du bord. Le cadre fait de
/// même — le contenu est décalé de [epaisseur] sur les quatre côtés, et le
/// tracé suit le rectangle arrondi intérieur de [epaisseur] / 2, rayon réduit
/// d'autant (comme le navigateur, qui arrondit le bord intérieur au rayon moins
/// l'épaisseur).
///
/// Le motif est une suite régulière de tirets de [tiret] px séparés de
/// [espace] px, posée le long du contour à partir du coin haut-gauche. Le
/// navigateur, lui, AJUSTE ses tirets côté par côté pour que chaque coin tombe
/// sur un tiret : l'écart se voit au pixel près dans les coins, jamais sur la
/// taille de la boîte ni sur la place du contenu. Écart de RENDU nommé, daté du
/// 14/10/2026.
///
/// Brique commune (`shared_widgets/`) : aucune couleur ni mesure n'y est
/// écrite, l'appelant les prend dans `lib/core/theme/`.
library;

import 'dart:ui' show PathMetric;

import 'package:flutter/widgets.dart';

/// Un cadre arrondi à bordure tiretée, fond optionnel.
class CadreTirete extends StatelessWidget {
  const CadreTirete({
    required this.couleur,
    required this.epaisseur,
    required this.rayon,
    required this.tiret,
    required this.espace,
    required this.child,
    this.fond,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  /// La couleur du trait (`border-slate-300`, `border-[var(--navy)]`…).
  final Color couleur;

  /// L'épaisseur du trait (`border-2` = 2 px), comptée DANS la boîte.
  final double epaisseur;

  /// Le rayon EXTÉRIEUR des coins (`rounded-lg` = 8 px).
  final double rayon;

  /// La longueur d'un tiret et celle d'un espace, en pixels.
  final double tiret;
  final double espace;

  /// Le fond de la boîte (`bg-slate-50`), `null` pour transparent.
  final Color? fond;

  /// Le rembourrage intérieur (`px-3 py-2.5`), À L'INTÉRIEUR de la bordure.
  final EdgeInsetsGeometry padding;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _PeintreTirets(
        couleur: couleur,
        epaisseur: epaisseur,
        rayon: rayon,
        tiret: tiret,
        espace: espace,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: fond,
          borderRadius: BorderRadius.circular(rayon),
        ),
        padding: EdgeInsets.all(epaisseur),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class _PeintreTirets extends CustomPainter {
  const _PeintreTirets({
    required this.couleur,
    required this.epaisseur,
    required this.rayon,
    required this.tiret,
    required this.espace,
  });

  final Color couleur;
  final double epaisseur;
  final double rayon;
  final double tiret;
  final double espace;

  @override
  void paint(Canvas canvas, Size size) {
    final demi = epaisseur / 2;
    final rayonTrait = rayon - demi < 0 ? 0.0 : rayon - demi;
    final contour = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            demi,
            demi,
            size.width - epaisseur,
            size.height - epaisseur,
          ),
          Radius.circular(rayonTrait),
        ),
      );
    final pinceau = Paint()
      ..color = couleur
      ..style = PaintingStyle.stroke
      ..strokeWidth = epaisseur;

    final pas = tiret + espace;
    if (pas <= 0) return;
    for (final PathMetric mesure in contour.computeMetrics()) {
      var position = 0.0;
      while (position < mesure.length) {
        final fin = position + tiret > mesure.length
            ? mesure.length
            : position + tiret;
        canvas.drawPath(mesure.extractPath(position, fin), pinceau);
        position += pas;
      }
    }
  }

  @override
  bool shouldRepaint(_PeintreTirets ancien) =>
      ancien.couleur != couleur ||
      ancien.epaisseur != epaisseur ||
      ancien.rayon != rayon ||
      ancien.tiret != tiret ||
      ancien.espace != espace;
}
