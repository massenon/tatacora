import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../../../core/impression/entete_etablissement.dart';
import '../impression/etat_clients.dart';

import '../../facturation/presentation/providers_paiements.dart';
import '../../hebergement/presentation/providers_hebergement.dart'
    show clientDaoProvider;
import '../domain/entities/registre_clients.dart';

/// Le registre des clients : les clients du poste et leurs créances.
///
/// Le solde est celui du SERVEUR (`SoldeClientService::registre()`) : la somme du
/// reste dû de leurs factures impayées, par la formule UNIQUE de `creances.dart`
/// que lit aussi le tableau de bord. Aucune requête SQL dédiée : une jointure
/// serait plus rapide et **dupliquerait la formule** — le jour où elle changerait,
/// l'écran Clients et le tableau de bord afficheraient deux dettes différentes
/// pour la même personne (PA-121).
///
/// `autoDispose`, comme les lectures de M11 : un registre gardé d'une visite à
/// l'autre montrerait le solde d'avant le dernier encaissement.
final registreClientsProvider = FutureProvider.autoDispose<List<LigneClient>>((
  ref,
) async {
  final clients = await ref.watch(clientDaoProvider).clients();
  final creances = await ref.watch(creancesProvider.future);

  return composerRegistre(clients: clients, creances: creances);
});

final rechercheClientProvider =
    NotifierProvider<_RechercheClientNotifier, String>(
      _RechercheClientNotifier.new,
    );

final class _RechercheClientNotifier extends Notifier<String> {
  @override
  String build() => '';

  void definir(String terme) => state = terme;
}

final etatCreanceProvider = NotifierProvider<_EtatCreanceNotifier, EtatCreance>(
  _EtatCreanceNotifier.new,
);

final class _EtatCreanceNotifier extends Notifier<EtatCreance> {
  @override
  EtatCreance build() => EtatCreance.tous;

  void definir(EtatCreance etat) => state = etat;
}

/// Le registre **tel que l'écran l'affiche**, filtres appliqués.
///
/// C'est cette liste-là que les exports emportent : « l'export porte sur ce
/// qui est affiché » (PA-119).
final registreFiltreProvider = FutureProvider.autoDispose<List<LigneClient>>((
  ref,
) async {
  final lignes = await ref.watch(registreClientsProvider.future);

  return filtrerRegistre(
    lignes,
    terme: ref.watch(rechercheClientProvider),
    etat: ref.watch(etatCreanceProvider),
  );
});

/// L'impression du registre, exposée comme **action injectable**.
///
/// Jamais un `Printing.layoutPdf` recopié dans un écran : un test de widget
/// n'a pas de greffon natif, et il doit exister un seul endroit où
/// l'impression est déclenchée.
final imprimerRegistreClientsProvider =
    Provider<Future<void> Function(List<LigneClient>, String)>(
      (ref) => (lignes, filtre) async {
        final octets = await EtatClients.pdf(
          lignes,
          filtre: filtre,
          entete: const EnteteEtablissement(),
        );
        await Printing.layoutPdf(
          onLayout: (_) => octets,
          name: EtatClients.titre,
          format: PdfPageFormat.a4,
        );
      },
    );

/// L'export tableur — rend le **chemin** du fichier écrit.
///
/// Un export silencieux est un export que personne ne retrouve.
///
/// Fichier **CSV**, pas XLSX : convention serveur RG-19, écart nommé en PA-111.
final exporterRegistreClientsProvider =
    Provider<Future<String> Function(List<LigneClient>, String)>(
      (ref) => (lignes, filtre) async {
        final dossier = await getApplicationDocumentsDirectory();
        final m = DateTime.now();
        final horodatage =
            '${m.year}'
            '${m.month.toString().padLeft(2, '0')}'
            '${m.day.toString().padLeft(2, '0')}-'
            '${m.hour.toString().padLeft(2, '0')}'
            '${m.minute.toString().padLeft(2, '0')}'
            '${m.second.toString().padLeft(2, '0')}';
        final fichier = File(
          p.join(dossier.path, 'registre-clients-$horodatage.csv'),
        );
        await fichier.writeAsBytes(
          EtatClients.csvOctets(lignes, filtre: filtre),
        );
        return fichier.path;
      },
    );
