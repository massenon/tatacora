/// Les providers de M8 — Véhicules & Locations.
///
/// ## Tout vient de la base LOCALE, et il n'y a aucune branche « si connecté »
///
/// Le poste est zéro réseau (`core/donnees_absentes.dart`, décision du Product
/// Owner du 14/09/2026), et le parc **se saisit sur le poste** depuis la même
/// décision. Ce fichier ne déclare donc aucun client HTTP : il n'y a rien à
/// rafraîchir, rien à réessayer, et **aucun état « injoignable » à porter**.
///
/// ⚠ Jusqu'à cette date, les cinq providers étaient en `autoDispose` « pour que
/// quitter l'écran oublie la réponse », et trois issues — reçu, refusé,
/// injoignable — traversaient chaque écran. Les deux dispositifs protégeaient
/// d'une donnée qui vieillit entre deux consultations d'un serveur ; la donnée
/// est maintenant sur le poste, et c'est l'écriture qui la change. Ne les
/// rétablissez pas : un `autoDispose` ferait recharger le parc à chaque
/// va-et-vient d'onglet, et une branche « injoignable » est un chemin que plus
/// rien n'emprunte.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../../../core/di/providers.dart';
import '../../../core/fichiers/enregistrement_export.dart';
import '../../../core/impression/entete_parametree.dart';
import '../../../core/impression/export_etat_a4.dart';
import '../data/vehicule_dao.dart';
import '../domain/entities/contrat_location.dart';
import '../domain/entities/vehicule.dart';
import '../domain/indicateurs_vehicules.dart';
import '../impression/etat_vehicules.dart';
import '../impression/recu_location.dart';

/// L'accès aux deux tables locales de M8.
final vehiculeDaoProvider = Provider<VehiculeDao>(
  (ref) => VehiculeDao(ref.watch(baseLocaleProvider)),
);

/* ====================================================================== */
/* Les quatre onglets — vue l.168-171                                      */
/* ====================================================================== */

/// Les onglets de la vue, **dans son ordre**.
enum OngletVehicules {
  parc('parc', 'Parc & disponibilité'),
  contrats('contrats', 'Contrats'),
  planning('planning', 'Planning du parc'),
  immobilisations('immo', 'Immobilisations');

  const OngletVehicules(this.cle, this.libelle);

  final String cle;
  final String libelle;
}

/// L'onglet actif — « Parc & disponibilité » par défaut, comme la vue.
final ongletVehiculesProvider =
    NotifierProvider<_OngletNotifier, OngletVehicules>(_OngletNotifier.new);

/* ====================================================================== */
/* Les filtres — un provider par contrôle de la vue                        */
/* ====================================================================== */

/// Les bornes « du » et « au » de l'en-tête.
///
/// Pré-remplies : aujourd'hui, et aujourd'hui + 14 jours. Un onglet « Parc »
/// qui s'ouvrirait sur « Choisissez une période » passerait pour cassé.
final periodeVehiculesProvider =
    NotifierProvider<_PeriodeNotifier, PeriodeVehicules>(_PeriodeNotifier.new);

/// La recherche — « Véhicule, client, n° de contrat… ».
final rechercheVehiculesProvider = NotifierProvider<_TexteNotifier, String>(
  _TexteNotifier.new,
);

/// Le filtre de statut des contrats — `actif` (par défaut, « Contrats
/// actifs »), vide (« Tous ») ou `annule` (« Annulés »), les trois valeurs de la
/// vue (`$statut`, `contratsFiltres`).
final statutContratsProvider =
    NotifierProvider<_StatutContratsNotifier, String>(
      _StatutContratsNotifier.new,
    );

/// Le filtre de catégorie.
final categorieVehiculesProvider =
    NotifierProvider<_CategorieNotifier, CategorieVehicule?>(
      _CategorieNotifier.new,
    );

final class PeriodeVehicules {
  const PeriodeVehicules({required this.debut, required this.fin});

  /// `Y-m-d`, ou `null` si l'utilisateur a vidé le champ.
  final String? debut;
  final String? fin;

  /// `null` tant que la période n'est pas complète et valide. La restitution
  /// est **strictement** après le départ : `fin == debut` ne vaut rien.
  int? get jours => nombreDeJours(debut, fin);

  bool get complete => jours != null;

  DateTime? get debutDate => debut == null ? null : DateTime.tryParse(debut!);
  DateTime? get finDate => fin == null ? null : DateTime.tryParse(fin!);
}

final class _PeriodeNotifier extends Notifier<PeriodeVehicules> {
  @override
  PeriodeVehicules build() {
    final aujourdhui = DateTime.now();
    return PeriodeVehicules(
      debut: _iso(aujourdhui),
      fin: _iso(aujourdhui.add(const Duration(days: 14))),
    );
  }

  void definirDebut(String? v) =>
      state = PeriodeVehicules(debut: v, fin: state.fin);

  void definirFin(String? v) =>
      state = PeriodeVehicules(debut: state.debut, fin: v);

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

final class _TexteNotifier extends Notifier<String> {
  @override
  String build() => '';

  void definir(String valeur) => state = valeur;
}

final class _StatutContratsNotifier extends Notifier<String> {
  @override
  String build() => statutContratActif;

  void definir(String valeur) => state = valeur;
}

final class _CategorieNotifier extends Notifier<CategorieVehicule?> {
  @override
  CategorieVehicule? build() => null;

  void definir(CategorieVehicule? valeur) => state = valeur;
}

final class _OngletNotifier extends Notifier<OngletVehicules> {
  @override
  OngletVehicules build() => OngletVehicules.parc;

  void definir(OngletVehicules valeur) => state = valeur;
}

/* ====================================================================== */
/* Les lectures                                                            */
/* ====================================================================== */

/// Le parc entier, filtré par catégorie **en base** — sur la valeur stockée,
/// jamais sur le libellé affiché.
final parcProvider = FutureProvider<List<Vehicule>>(
  (ref) => ref
      .watch(vehiculeDaoProvider)
      .parc(categorie: ref.watch(categorieVehiculesProvider)),
);

/// Les immobilisations (entretiens et carburations) du parc — v32.
final entretiensProvider = FutureProvider<List<EntretienVehicule>>(
  (ref) => ref.watch(vehiculeDaoProvider).entretiens(),
);

/// Les contrats, **nom du client résolu par le DAO**.
///
/// ⚠ La résolution vit au DAO, pas ici : elle lit `clients_local` dans la même
/// passe que les contrats. La faire à l'écran obligerait chaque écran à la
/// refaire, et deux d'entre eux finiraient par diverger.
final contratsProvider = FutureProvider<List<ContratLocation>>(
  (ref) => ref.watch(vehiculeDaoProvider).contrats(),
);

/// La bande d'indicateurs — calculée ici, faute d'un KPI serveur pour M8.
final indicateursVehiculesProvider = FutureProvider<IndicateursVehicules>((
  ref,
) async {
  final parc = await ref.watch(parcProvider.future);
  final contrats = await ref.watch(contratsProvider.future);
  final periode = ref.watch(periodeVehiculesProvider);
  // La vue calcule ses chiffres sur les contrats DÉJÀ filtrés par le statut.
  final statut = ref.watch(statutContratsProvider);

  return calculerIndicateurs(
    parc: parc,
    contrats: contrats,
    debut: periode.debut,
    fin: periode.fin,
    joursPeriode: periode.jours,
    statut: statut,
  );
});

/// La disponibilité d'UN véhicule sur la période courante.
///
/// `null` quand la période est incomplète : la disponibilité n'a pas de sens
/// sans plage, et rendre « disponible » ferait louer deux fois le même
/// véhicule.
final disponibiliteProvider =
    FutureProvider.family<DisponibiliteVehicule?, String>((
      ref,
      vehiculeId,
    ) async {
      final periode = ref.watch(periodeVehiculesProvider);
      final debut = periode.debutDate;
      final fin = periode.finDate;
      if (debut == null || fin == null || !periode.complete) return null;

      // Sans cette dépendance, la colonne « Disponibilité » garderait l'état
      // d'avant le contrat qu'on vient d'établir, et le bouton « Louer »
      // resterait offert sur un véhicule qui vient d'être pris.
      ref.watch(contratsProvider);

      return ref
          .watch(vehiculeDaoProvider)
          .disponibilite(vehiculeId: vehiculeId, debut: debut, fin: fin);
    });

/// Recharge tout ce que l'écran affiche après une écriture.
///
/// Un seul point d'entrée : trois `invalidate` recopiés dans trois modales
/// finiraient par diverger, et c'est la modale oubliée qui laisserait un
/// tableau périmé sous les yeux de l'opérateur.
void rechargerVehicules(WidgetRef ref) {
  ref
    ..invalidate(parcProvider)
    ..invalidate(contratsProvider)
    ..invalidate(entretiensProvider)
    ..invalidate(disponibiliteProvider);
}

/* ====================================================================== */
/* Les exports                                                             */
/* ====================================================================== */

/// Enregistre le CSV de l'onglet courant par la fenêtre « Enregistrer sous »
/// (14/10/2026) et rend son chemin, `null` : annulé.
///
/// Injecté comme **action**, jamais appelé depuis un widget.
final exporterVehiculesProvider =
    Provider<Future<String?> Function(EtatVehicules)>(
      (ref) =>
          (etat) => ref
              .read(enregistrementExportProvider)
              .exporter(
                base: 'vehicules',
                type: TypeFichierEnregistre.csv,
                octets: etat.csvOctets(),
              ),
    );

/// L'export « PDF Officiel A4 Imprimable » de l'onglet affiché — mêmes
/// colonnes, mêmes lignes que le CSV, en-tête lu des paramètres.
final exporterVehiculesPdfProvider =
    Provider<Future<String?> Function(EtatVehicules)>(
      (ref) =>
          (etat) => enregistrerEtatA4(ref, etat.etatA4(), base: 'vehicules'),
    );

/// Le tarif courant du véhicule d'un contrat, lu sur le parc LOCAL (zéro
/// réseau), ou `null` quand ce poste ne détient pas le véhicule.
Future<String?> _tarifDuVehicule(Ref ref, String immatriculation) async {
  final parc = await ref.read(vehiculeDaoProvider).parc();
  for (final v in parc) {
    if (v.immatriculation == immatriculation) return v.tarifJour;
  }
  return null;
}

/// Le reçu de location d'UN contrat, exposé comme **action** (jamais appelé
/// depuis un widget) : composé sous l'en-tête lu des paramètres, puis remis à
/// l'impression du poste (`Printing.layoutPdf`).
///
/// Une LECTURE : rien n'est écrit, aucun numéro n'est alloué, et le poste n'a
/// besoin d'aucune synchronisation — toutes les données sont locales. L'émetteur
/// est « Nom — Rôle » de la session, comme `ReportHeaderService` du serveur.
final imprimerRecuLocationProvider =
    Provider<Future<void> Function(ContratLocation)>(
      (ref) => (contrat) async {
        final session = ref.read(sessionProvider);
        final recu = RecuLocation(
          contrat: contrat,
          emisLe: DateTime.now(),
          emisPar: session == null
              ? 'Auteur non identifié'
              : '${session.nom} — ${session.role}',
          tarifJour: await _tarifDuVehicule(ref, contrat.immatriculation),
        ).avecEntete(await ref.read(lireEnteteEtablissementProvider)());
        await Printing.layoutPdf(
          onLayout: (_) => recu.pdf(),
          name: 'Reçu de location ${contrat.numero ?? contrat.immatriculation}',
          format: PdfPageFormat.a4,
        );
      },
    );
