/// Les providers du journal des ventes — Riverpod exclusivement.
///
/// ## Le PREMIER écran hors ligne depuis quatre lots
///
/// M11, Paramètres, M6 et M7 exigent tous le réseau. Celui-ci **non** : ses
/// trois lectures viennent de Drift — les paniers, le référentiel des tables,
/// le registre de facturation. Aucun `dio`, aucune branche « si connecté »,
/// aucune issue « injoignable » : il n'y a rien à joindre.
///
/// ## ⚠ Ce journal ne part PAS au serveur, et aucun écran ne doit l'annoncer
///
/// `SynchronisationService::TABLES_SYNCHRONISABLES` ne connaît que
/// `reservations` et `clients`. Ni `paniers` ni les pièces de facturation n'y
/// sont : une vente ne quittera jamais ce poste. Un badge « en attente de
/// synchronisation » sur ce qui ne partira jamais serait l'indicateur qui
/// affirme un état qu'il n'a pas vérifié — la famille PA-59/60/61. L'écran dit
/// **« enregistré sur ce poste »**.
///
/// ## Aucun `autoDispose`, contrairement à M6 et M7
///
/// Et c'est la raison inverse : là-bas, garder la réponse ferait réafficher au
/// retour un registre qui date de la visite précédente, sans qu'aucune copie
/// locale n'existe pour le corriger. Ici la source **est** la base du poste :
/// une lecture conservée est exacte tant que personne n'écrit, et
/// [rafraichirJournalVentes] la rejette dès qu'on écrit.
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../../facturation/presentation/providers_facturation.dart';
import '../../pos/presentation/providers_pos.dart';
import '../domain/entities/vente.dart';
import '../domain/journal_ventes.dart';
import '../impression/etat_journal_ventes.dart';

/* ====================================================================== */
/* Le journal — trois lectures locales, une composition                    */
/* ====================================================================== */

/// Le journal complet du poste, **avant filtrage**.
///
/// Les trois lectures sont lancées **en parallèle** : elles ne dépendent pas
/// les unes des autres, et les enchaîner tripleraient l'attente sur l'écran
/// qu'un gérant ouvre en fin de service.
///
/// `libelles()` et non `toutes()` sur le référentiel des tables : `toutes()`
/// **sème** le jeu initial quand le référentiel est vide, et une lecture ne
/// doit rien écrire (voir `TablesPosDao.libelles`).
final journalVentesProvider = FutureProvider<JournalVentes>((ref) async {
  final depotPanier = ref.watch(depotPanierProvider);
  final tables = ref.watch(tablesPosDaoProvider);
  final factures = ref.watch(factureDaoProvider);

  final (paniers, libelles, numeros) = await (
    depotPanier.paniers(),
    tables.libelles(),
    factures.numerosFactureParPanier(),
  ).wait;

  return composerJournal(
    paniers: paniers,
    libellesTables: libelles,
    numeroFactureParPanier: numeros,
  );
});

/* ====================================================================== */
/* Les filtres — un seul état pour les sept contrôles du maître            */
/* ====================================================================== */

/// Les sept contrôles vivent dans **un seul** objet d'état.
///
/// Sept providers séparés obligeraient chaque lecture à les rassembler, et
/// c'est la reconstitution qui finirait par oublier le septième — celui qu'on
/// ajoute en dernier. Ici, l'export reçoit le même [FiltreVentes] que la liste :
/// « l'export porte sur ce qui est affiché » devient structurel, pas
/// documentaire (PA-119).
final filtreVentesProvider =
    NotifierProvider<FiltreVentesNotifier, FiltreVentes>(
      FiltreVentesNotifier.new,
    );

final class FiltreVentesNotifier extends Notifier<FiltreVentes> {
  @override
  FiltreVentes build() => const FiltreVentes();

  void definir(FiltreVentes filtre) => state = filtre;

  /// Remet tous les contrôles à leur position neutre.
  void reinitialiser() => state = const FiltreVentes();
}

/// Les ventes **telles que l'écran les affiche**, filtre appliqué.
final ventesAfficheesProvider = Provider<List<Vente>>((ref) {
  final journal = ref.watch(journalVentesProvider).value;
  if (journal == null) return const <Vente>[];
  return filtrerVentes(journal.ventes, ref.watch(filtreVentesProvider));
});

/// Les indicateurs — calculés sur la liste **filtrée**, comme au maître.
///
/// Le journal entier donnerait un chiffre d'affaires qui ne correspond à
/// aucune des lignes visibles, et personne ne saurait laquelle des deux
/// valeurs croire.
final kpisJournalVentesProvider = Provider<KpisJournalVentes>(
  (ref) => KpisJournalVentes.calculer(ref.watch(ventesAfficheesProvider)),
);

/// Les postes offerts au filtre — dérivés du journal **entier**.
///
/// Volontairement pas de la liste filtrée : dériver les options de ce qui est
/// déjà filtré ferait disparaître l'option qu'on vient de choisir dès que le
/// filtre ne retient rien, et le contrôle deviendrait impossible à défaire.
final postesJournalProvider = Provider<List<String>>((ref) {
  final journal = ref.watch(journalVentesProvider).value;
  return journal == null ? const <String>[] : postesDuJournal(journal.ventes);
});

/// L'état à exporter — construit **au clic**, sur ce qui est affiché.
EtatJournalVentes composerEtatJournal(WidgetRef ref) =>
    EtatJournalVentes.composer(
      ventes: ref.read(ventesAfficheesProvider),
      filtre: ref.read(filtreVentesProvider),
    );

/* ====================================================================== */
/* Documents — des actions INJECTABLES, jamais un layoutPdf dans un écran  */
/* ====================================================================== */

/// L'impression du journal filtré.
///
/// Jamais un `Printing.layoutPdf` recopié dans l'écran : un test de widget n'a
/// pas de greffon natif, et il doit exister un seul endroit où l'impression est
/// déclenchée.
final imprimerJournalVentesProvider =
    Provider<Future<void> Function(EtatJournalVentes)>(
      (ref) => (etat) async {
        await Printing.layoutPdf(
          onLayout: (_) => etat.pdf(),
          name: EtatJournalVentes.titre,
          format: PdfPageFormat.a4,
        );
      },
    );

/// L'export tableur du journal — rend le **chemin** du fichier écrit.
///
/// Le chemin est rendu pour être affiché : un export silencieux est un export
/// que personne ne retrouve.
final exporterJournalVentesProvider =
    Provider<Future<String> Function(EtatJournalVentes)>(
      (ref) =>
          (etat) async => _ecrire(etat.csvOctets(), 'journal-ventes', 'csv'),
    );

/// L'impression du détail d'une vente — bouton « Imprimer » de la modale.
final imprimerVenteProvider = Provider<Future<void> Function(EtatVente)>(
  (ref) => (etat) async {
    await Printing.layoutPdf(
      onLayout: (_) => etat.pdf(),
      name: '${EtatVente.titre} ${etat.vente.referenceLocale}',
      format: PdfPageFormat.a4,
    );
  },
);

/// L'enregistrement du détail d'une vente — bouton « Télécharger ».
///
/// ## Pourquoi deux boutons qui ne font pas la même chose
///
/// Le maître en pose deux (l.315-316) : `window.print()` et un export PDF. Les
/// brancher tous les deux sur la même action donnerait un contrôle qui fait
/// doublon — et un contrôle qui fait doublon finit par être retiré, en
/// emportant celui des deux dont on avait besoin. « Imprimer » ouvre le
/// dialogue d'impression ; « Télécharger » écrit un fichier et dit **où**.
final exporterVenteProvider = Provider<Future<String> Function(EtatVente)>(
  (ref) =>
      (etat) async => _ecrire(
        await etat.pdf(),
        'vente-${etat.vente.referenceLocale}',
        'pdf',
      ),
);

/// Recharge tout ce qui dépend du journal, après une écriture ailleurs.
///
/// Une seule fonction plutôt qu'un `invalidate` recopié : oublier d'invalider
/// laisserait une vente encaissée absente du journal alors qu'elle est en base,
/// et le gérant conclurait qu'elle n'a pas été enregistrée.
void rafraichirJournalVentes(WidgetRef ref) {
  ref.invalidate(journalVentesProvider);
}

Future<String> _ecrire(
  List<int> octets,
  String prefixe,
  String extension,
) async {
  final dossier = await getApplicationDocumentsDirectory();
  final m = DateTime.now();
  final horodatage =
      '${m.year}'
      '${m.month.toString().padLeft(2, '0')}'
      '${m.day.toString().padLeft(2, '0')}-'
      '${m.hour.toString().padLeft(2, '0')}'
      '${m.minute.toString().padLeft(2, '0')}'
      '${m.second.toString().padLeft(2, '0')}';
  final fichier = File(p.join(dossier.path, '$prefixe-$horodatage.$extension'));
  await fichier.writeAsBytes(octets);
  return fichier.path;
}
