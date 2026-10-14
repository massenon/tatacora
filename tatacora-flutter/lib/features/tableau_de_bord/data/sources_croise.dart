import '../../../core/database/app_database.dart';
import '../../depenses/domain/repositories/depenses_repository.dart';
import '../../pos/domain/entities/mode_reglement.dart';
import '../../pos/domain/entities/panier.dart';
import '../../pos/domain/repositories/panier_repository.dart';
import '../domain/croise_local.dart';

/// Les trois registres du tableau croisé, LUS sur le poste — les lignes
/// élémentaires que `Accueil::faitsCroises` lit au serveur.
///
/// | Registre | Table du poste | Qui l'écrit |
/// |---|---|---|
/// | ventes | `paniers_local` clôturés + `lignes_panier_local` | `PanierDao` (clôture : `cloturer`) |
/// | dépenses | `depenses_local` + `lignes_depense_local` | `DepenseDao` |
/// | réservations | `reservations_local` + `clients_local` | `ReservationDao`, `ClientDao` |
///
/// Aucune table n'est ajoutée, rien n'est écrit : le croisement est une
/// LECTURE (piège 9 : chaque colonne lue ici a un écrivain de production).
final class SourcesCroise {
  const SourcesCroise({
    required this.paniers,
    required this.depenses,
    required this.base,
  });

  final PanierRepository paniers;
  final DepensesRepository depenses;
  final AppDatabase base;

  /// Les lignes de vente : une par ligne de panier CLÔTURÉ.
  Future<List<LigneVenteCroisee>> ventes() async {
    final clotures = await paniers.paniers(statut: StatutPanier.cloture);
    return [
      for (final p in clotures)
        if (p.clotureLe != null)
          for (final l in p.lignes)
            () {
              final mode = ModeReglement.values
                  .where((m) => m.code == p.modePaiement)
                  .firstOrNull;
              return LigneVenteCroisee(
                clotureLe: p.clotureLe!,
                pointVente: p.pointVente ?? '',
                modeLibelle: mode?.libelle ?? '',
                encaisse: mode?.encaisse ?? false,
                module: l.reference.module.code,
                categorie: l.categorie ?? '',
                nom: l.libelle,
                quantite: l.quantite,
                montant: l.montant,
              );
            }(),
    ];
  }

  /// Les lignes de dépense : une par ligne d'achat.
  Future<List<LigneDepenseCroisee>> lignesDepense() async => [
    for (final d in await depenses.depenses())
      for (final l in d.lignes)
        LigneDepenseCroisee(
          dateTransaction: d.dateTransaction,
          tresorerie: d.tresorerie?.code ?? '',
          famille: l.famille,
          nature: l.nature,
          montant: l.montant,
        ),
  ];

  /// Les réservations, avec le nom et le prénom de leur client.
  Future<List<ReservationCroisee>> reservations() async {
    final rangees = await base
        .customSelect(
          'SELECT r.date_arrivee AS arrivee, r.statut AS statut, '
          'r.acompte AS acompte, c.nom AS nom, c.prenom AS prenom '
          'FROM reservations_local r '
          'LEFT JOIN clients_local c ON c.id = r.client_id',
          readsFrom: {base.reservationsLocal, base.clientsLocal},
        )
        .get();
    return [
      for (final r in rangees)
        ReservationCroisee(
          dateArrivee: r.read<DateTime>('arrivee'),
          annulee: r.read<String>('statut') == 'annulee',
          acompte: r.read<double>('acompte').round(),
          nom: r.readNullable<String>('nom') ?? '',
          prenom: r.readNullable<String>('prenom') ?? '',
        ),
    ];
  }

  /// La table de faits de la fenêtre, pour les sources cochées.
  Future<List<FaitCroise>> faits({
    required DateTime debut,
    required DateTime finExclue,
    required Set<SourceCroise> sources,
  }) async => faitsCroises(
    debut: debut,
    finExclue: finExclue,
    sources: sources,
    ventes: sources.contains(SourceCroise.ventes) ? await ventes() : const [],
    depenses: sources.contains(SourceCroise.depenses)
        ? await lignesDepense()
        : const [],
    reservations: sources.contains(SourceCroise.reservations)
        ? await reservations()
        : const [],
  );
}
