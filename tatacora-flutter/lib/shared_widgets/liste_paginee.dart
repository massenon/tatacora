import 'package:flutter/material.dart';

import '../core/theme/mesures_transverses.dart';
import 'pied_pagination.dart';

/// Un tableau PAGINÉ par le pied commun ([PiedPagination]) — demande du PO du
/// 14/10/2026 : toute liste qui peut croître sans borne s'affiche dix lignes à
/// la fois, comme le journal comptable et l'historique des ventes.
///
/// Le widget ne découpe QUE l'affichage : [elements] est la liste filtrée
/// ENTIÈRE, et les exports de l'écran continuent de la lire en entier depuis
/// leur provider — jamais la page affichée.
///
/// ## Retour à la page 1
///
/// [cleRemiseAZero] porte ce qui, en changeant, ramène à la première page :
/// filtre, recherche, onglet. Rester en page 3 d'un résultat qui n'en a plus
/// qu'une montrerait un tableau vide sous un filtre qui trouve pourtant des
/// lignes (et [TranchePage] ramène de toute façon la page dans ses bornes).
class ListePaginee<T> extends StatefulWidget {
  const ListePaginee({
    required this.elements,
    required this.constructeur,
    required this.prefixeCle,
    this.cleRemiseAZero,
    this.parPage = MesuresTransverses.lignesParPage,
    this.masquerSiVide = false,
    super.key,
  });

  /// La liste filtrée entière.
  final List<T> elements;

  /// Construit le tableau pour la page affichée.
  final Widget Function(BuildContext context, List<T> page) constructeur;

  /// Préfixe des clés du pied (`<prefixe>-decompte`, `-precedent`…).
  final String prefixeCle;

  /// Ce qui, en changeant (`==`), ramène à la page 1.
  final Object? cleRemiseAZero;
  final int parPage;

  /// `true` : aucun pied sous une liste vide (l'état vide du tableau suffit).
  final bool masquerSiVide;

  @override
  State<ListePaginee<T>> createState() => _ListePagineeState<T>();
}

class _ListePagineeState<T> extends State<ListePaginee<T>> {
  int _page = 1;

  @override
  void didUpdateWidget(covariant ListePaginee<T> ancien) {
    super.didUpdateWidget(ancien);
    if (ancien.cleRemiseAZero != widget.cleRemiseAZero) _page = 1;
  }

  @override
  Widget build(BuildContext context) {
    final tranche = TranchePage.de(
      total: widget.elements.length,
      page: _page,
      parPage: widget.parPage,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        widget.constructeur(context, tranche.decouper(widget.elements)),
        if (!(widget.masquerSiVide && widget.elements.isEmpty))
          PiedPagination(
            key: Key(widget.prefixeCle),
            tranche: tranche,
            prefixeCle: widget.prefixeCle,
            onPage: (p) => setState(() => _page = p),
          ),
      ],
    );
  }
}
