// Vue Blade maîtresse (PA-183) : pwa/pos/comptant.blade.php
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart' show baseLocaleProvider;
import '../../achats/domain/decimal_texte.dart' show enCentiemes;
import '../../stocks/presentation/providers_stocks.dart'
    show stockEnAttenteProvider, stocksDaoProvider;
import '../domain/entities/panier.dart';
import '../domain/entities/reference_catalogue.dart';
import '../domain/rupture_stock.dart';

/// Le point de stockage dont le serveur sort les boissons vendues
/// (`VenteService::TYPE_POINT_BAR`).
const String typePointBar = 'bar';

/// Constate, AVANT d'encaisser, la rupture que la vente provoquerait — la
/// lecture que `PosComptant` fait faire par `RuptureStockException` (RG-06).
///
/// Une action injectable : un test la remplace par une rupture ou par rien.
/// Elle LIT (mouvements, file d'envoi, catalogue) et n'écrit rien. Voir
/// `rupture_stock.dart` pour ce qui est estimé et ce qui ne l'est pas.
final constaterRuptureComptoirProvider =
    Provider<Future<RuptureConstatee?> Function(Panier)>(
      (ref) => (panier) async {
        final lignes = [
          for (final l in panier.lignes)
            if (l.reference.module == ModuleVendable.m5Bar)
              (boissonId: l.reference.code, quantite: l.quantite),
        ];
        if (lignes.isEmpty) return null;

        final dao = ref.read(stocksDaoProvider);
        final points = await dao.points();
        final bar = points.where((p) => p.type == typePointBar).firstOrNull;
        // Sans point « bar », aucune estimation : le serveur refuserait la
        // sortie par un autre motif, que cette question ne sait pas dire.
        if (bar == null) return null;

        final etat = await dao.etat(pointId: bar.id);
        final stock = <String, int>{
          for (final l in etat.lignes)
            if (!l.estJournalier && enCentiemes(l.stock) != null)
              l.id: enCentiemes(l.stock)!,
        };

        final db = ref.read(baseLocaleProvider);
        final boissons = {
          for (final b in await db.select(db.cartesBoissonLocal).get())
            b.id: (articleId: b.articleId, facteur: b.unitesVendables),
        };

        return constaterRupture(
          lignes: lignes,
          boissons: boissons,
          stockCentiemes: stock,
          enAttente: await ref.read(stockEnAttenteProvider.future),
        );
      },
    );
