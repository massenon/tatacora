import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../core/database/app_database.dart';
import '../../../core/di/providers.dart';
import '../../../core/impression/entete_parametree.dart';
import '../data/images_document_poste.dart';
import '../data/proforma_dao.dart';
import '../impression/proforma_a4.dart';
import 'providers_facturation.dart';

/// L'écrivain UNIQUE des proformas du poste (`ProformaDao`), sur la base locale.
final proformaDaoProvider = Provider<ProformaDao>(
  (ref) => ProformaDao(ref.watch(baseLocaleProvider)),
);

/// La liste des proformas, suivie en direct (saisie locale ou descente du serveur).
final proformasProvider = FutureProvider.autoDispose<List<ProformasLocalData>>((
  ref,
) {
  final dao = ref.watch(proformaDaoProvider);
  final abonnement = dao.surveiller().listen((_) => ref.invalidateSelf());
  ref.onDispose(abonnement.cancel);
  return dao.liste();
});

/// Les lignes d'une proforma.
final lignesProformaProvider = FutureProvider.autoDispose
    .family<List<LignesProformaLocalData>, String>(
      (ref, id) => ref.watch(proformaDaoProvider).lignes(id),
    );

/// L'impression A4 d'une proforma, par le mécanisme d'impression du poste
/// (`Printing.layoutPdf` : imprimer ou « Enregistrer au format PDF »). Hors ligne : aucune
/// requête réseau. Le logo vient du paquet (comme la facture), l'en-tête et les réglages sont
/// relus à CHAQUE édition, la signature et le cachet seulement si l'interrupteur est sur Oui.
final imprimerProformaProvider = Provider<Future<void> Function(String)>(
  (ref) => (id) async {
    final dao = ref.read(proformaDaoProvider);
    final proforma = await dao.parId(id);
    if (proforma == null) return;
    final lignes = await dao.lignes(id);
    final reglages = await ref.read(reglagesDocumentsProvider.future);
    final logo = await ref.read(logoEtablissementProvider.future);
    final entete = (await ref.read(
      lireEnteteEtablissementProvider,
    )()).avecLogo(logo);
    final images = reglages.signatureAffichee;
    final document = ProformaA4.composer(
      proforma: proforma,
      lignes: lignes,
      entete: entete,
      reglages: reglages,
      maintenant: DateTime.now(),
      signature: images
          ? await ref.read(signatureDocumentProvider.future)
          : null,
      cachet: images ? await ref.read(cachetDocumentProvider.future) : null,
    );
    await Printing.layoutPdf(
      onLayout: (_) => document.pdf(),
      name: proforma.numero ?? 'proforma',
      format: formatProformaA4,
    );
  },
);
