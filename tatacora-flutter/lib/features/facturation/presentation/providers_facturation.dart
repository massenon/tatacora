import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

import '../../comptabilite/presentation/exercice_consulte.dart';
import '../../../core/di/providers.dart';
import '../../../core/fichiers/enregistrement_export.dart';
import '../../../core/impression/bloc_signature_a4.dart';
import '../../../core/impression/entete_parametree.dart';
import '../../parametres/data/parametres_dao.dart';
import '../data/images_document_poste.dart';
import '../domain/reglages_documents.dart';
import '../../../core/theme/app_assets.dart';
import '../../auth/domain/session.dart';
import '../../hebergement/presentation/providers_hebergement.dart';
import '../../pos/domain/entities/panier.dart';
import '../data/facture_dao.dart';
import '../data/facture_repository_local.dart';
import '../data/lecteur_mode_facturation.dart';
import '../data/service_facturation_en_ligne.dart';
import '../data/service_normalisation.dart';
import '../domain/acheteur_facture.dart';
import '../domain/mode_facturation.dart';
import '../../synchronisation/presentation/providers_synchronisation.dart';
import 'package:drift/drift.dart' show Variable;
import '../../transverse/data/configuration_poste.dart';
import '../domain/entities/piece_facturation.dart';
import '../impression/etat_registre_factures.dart';
import '../domain/repositories/facture_repository.dart';
import '../domain/usecases/facturer.dart';
import '../impression/facture_a4.dart';

/// Providers de la facturation — Riverpod exclusivement.
///
/// ## Les écrans ne voient ni DAO ni table
///
/// Comme pour M1 et pour le panier : ils ne connaissent que [Facturer] et le
/// contrat de dépôt. La provenance de la donnée reste invisible à l'interface —
/// ce qui compte particulièrement ici, puisqu'elle est **exclusivement locale**
/// et qu'elle ne le restera pas éternellement.

final factureDaoProvider = Provider<FactureDao>(
  (ref) => FactureDao(ref.watch(baseLocaleProvider)),
);

/// La normalisation par le boîtier CC300 de CE poste (07/11/2026). Aucune requête
/// tant que le mode effectif du poste n'est pas « boîtier ». Remplaçable par un
/// test (faux pilote).
final serviceNormalisationProvider = Provider<ServiceNormalisation>(
  (ref) => ServiceNormalisation(
    ref.watch(baseLocaleProvider),
    lecteur: LecteurModeFacturation(
      ref.watch(baseLocaleProvider),
      lecteur: LecteurConfigurationPoste(
        chemin: ref.watch(cheminConfigurationPosteProvider),
      ),
    ),
  ),
);

/// Les gestes qui ne se font QU'EN LIGNE (07/11/2026) : l'avoir d'une facture normalisée, et la
/// normalisation e-MECeF demandée au serveur. Remplaçable par un test (faux serveur).
final serviceFacturationEnLigneProvider = Provider<ServiceFacturationEnLigne>(
  (ref) => ServiceFacturationEnLigne(
    transport: ref.watch(transportSynchronisationProvider),
    url: ref.watch(urlServeurSynchronisationProvider),
    base: ref.watch(baseLocaleProvider),
    demonstration: ref.watch(synchronisationInterditeProvider),
    lecteur: LecteurConfigurationPoste(
      chemin: ref.watch(cheminConfigurationPosteProvider),
    ),
    envoyerLaFile: () async {
      await ref.read(syncManagerProvider).synchroniserMaintenant();
    },
    descendre: () async {
      await ref.read(syncManagerProvider).synchroniserDescenteSeule();
    },
  ),
);

/// L'ACHETEUR saisi pour la PROCHAINE facture du POS au comptoir (décision du PO du 07/11/2026) :
/// posé par le dialogue « IFU du client », lu par l'encaissement, remis à zéro après l'émission.
final acheteurFactureProvider =
    NotifierProvider<AcheteurFactureNotifier, AcheteurFacture>(
      AcheteurFactureNotifier.new,
    );

final class AcheteurFactureNotifier extends Notifier<AcheteurFacture> {
  @override
  AcheteurFacture build() => AcheteurFacture.aucun;

  void poser(AcheteurFacture acheteur) => state = acheteur;

  void reinitialiser() => state = AcheteurFacture.aucun;
}

/// Ce que ce poste FAIT pour normaliser : le boîtier, le serveur (e-MECeF, en ligne), ou rien
/// (mode désactivé = facture simple, sans bouton). Relu à chaque affichage.
final certifieParProvider = FutureProvider.autoDispose<CertifiePar>((
  ref,
) async {
  final etat = await LecteurModeFacturation(
    ref.watch(baseLocaleProvider),
    lecteur: LecteurConfigurationPoste(
      chemin: ref.watch(cheminConfigurationPosteProvider),
    ),
  ).lire();
  return etat.certifiePar;
});

/// L'IFU retenu sur la fiche d'un client (descendu du serveur), `null` si aucun : il préremplit
/// l'IFU de la facture.
Future<String?> ifuDeLaFiche(WidgetRef ref, String? clientId) async {
  if (clientId == null) return null;
  final base = ref.read(baseLocaleProvider);
  final ligne = await base
      .customSelect(
        'SELECT ifu FROM clients_local WHERE id = ?',
        variables: [Variable<String>(clientId)],
      )
      .getSingleOrNull();
  final ifu = ligne?.data['ifu'];
  return ifu is String && ifu.trim().isNotEmpty ? ifu.trim() : null;
}

/// « Normaliser maintenant », APRÈS l'émission : le boîtier de ce poste, ou le serveur (e-MECeF)
/// quand le poste est en ligne. JAMAIS bloquant : toute issue, échec compris, devient une phrase ;
/// la facture reste émise, « en attente », rejouable par le bouton « Normaliser ».
Future<String?> normaliserMaintenant(
  WidgetRef ref,
  PieceFacturation piece,
) async {
  try {
    final par = await ref.read(certifieParProvider.future);
    switch (par) {
      case CertifiePar.rien:
        return null;
      case CertifiePar.boitier:
        final r = await ref
            .read(serviceNormalisationProvider)
            .normaliser(piece.id);
        return switch (r) {
          NormalisationFaite(:final piece) when piece.estNormalisee =>
            'Facture ${piece.numero} normalisée.',
          NormalisationFaite(:final piece) =>
            'Facture émise, normalisation en attente : '
                '${piece.normalisationMotif ?? 'à relancer avec « Normaliser »'}',
          DejaNormalisee() => null,
          NormalisationIgnoree() => null,
        };
      case CertifiePar.serveur:
        final r = await ref
            .read(serviceFacturationEnLigneProvider)
            .normaliserParLeServeur(piece.id);
        return switch (r) {
          NormalisationServeur(:final piece) when piece.estNormalisee =>
            'Facture ${piece.numero} normalisée.',
          NormalisationServeur(:final motif) =>
            'Facture émise, normalisation en attente : ${motif ?? 'à relancer'}',
          RefusEnLigne(:final phrase) =>
            'Facture émise, normalisation en attente : $phrase',
          AvoirCree() => null,
        };
    }
  } on Object catch (e) {
    return 'Facture émise, normalisation en attente : $e';
  }
}

/// Ce poste certifie-t-il par son boîtier ? Relu à chaque affichage du registre.
final boitierActifProvider = FutureProvider.autoDispose<bool>(
  (ref) => ref.watch(serviceNormalisationProvider).boitierActif(),
);

final depotFactureProvider = Provider<FactureRepository>(
  (ref) => FactureRepositoryLocal(ref.watch(factureDaoProvider)),
);

final facturerProvider = Provider<Facturer>(
  (ref) => Facturer(ref.watch(depotFactureProvider)),
);

/// **Le seul point d'entrée d'émission depuis un panier.**
///
/// ## Pourquoi une fonction plutôt qu'un appel dans chaque écran
///
/// Les deux points de vente partagent le même widget de panier, mais pas la
/// même origine de facture. Recopier l'aiguillage dans chacun ferait vivre deux
/// fois la même décision — et c'est la seconde copie qui divergerait, celle que
/// personne ne relit. C'est le raisonnement du registre unique, appliqué au
/// code qui l'alimente.
///
/// L'aiguillage repose sur `typeVente`, **le même attribut** qui distingue les
/// deux POS. Il n'y a donc aucune information nouvelle à tenir à jour.
final emettrePourPanierProvider =
    Provider<
      Future<PieceFacturation> Function(Panier, {AcheteurFacture acheteur})
    >(
      (ref) => (panier, {acheteur = AcheteurFacture.aucun}) async {
        final facturer = ref.read(facturerProvider);

        if (panier.typeVente == TypeVente.comptant) {
          return facturer.emettreAuComptant(panier, acheteur: acheteur);
        }

        final reservationId = panier.reservationId;
        if (reservationId == null) {
          // Inatteignable si `PanierDao.ouvrir` a fait son travail — mais un
          // `!` ici transformerait une incohérence de données en plantage muet
          // au moment de l'encaissement.
          throw StateError(
            'Panier de séjour sans réservation : impossible de composer la '
            'facture de départ.',
          );
        }

        final reservation = await ref
            .read(depotReservationProvider)
            .parId(reservationId);
        if (reservation == null) {
          throw StateError(
            'La réservation $reservationId est introuvable localement : la '
            'nuitée ne peut pas être portée à la facture.',
          );
        }

        return facturer.emettrePourSejour(
          panier: panier,
          reservation: reservation,
          acheteur: acheteur,
        );
      },
    );

/// « Payer séparément » : l'émission de la facture des SEULES consommations d'un
/// séjour (`Facturer.emettreConsommationsDuSejour`). Le même aiguillage que
/// [emettrePourPanierProvider], pour un panier de séjour uniquement.
final emettreConsommationsPourPanierProvider =
    Provider<
      Future<PieceFacturation> Function(Panier, {AcheteurFacture acheteur})
    >(
      (ref) => (panier, {acheteur = AcheteurFacture.aucun}) async {
        final reservationId = panier.reservationId;
        if (panier.typeVente != TypeVente.surSejour || reservationId == null) {
          throw StateError(
            'Seul un panier de séjour se facture sans son hébergement.',
          );
        }
        final reservation = await ref
            .read(depotReservationProvider)
            .parId(reservationId);
        if (reservation == null) {
          throw StateError(
            'La réservation $reservationId est introuvable localement : les '
            'consommations ne peuvent pas être facturées à son client.',
          );
        }
        return ref
            .read(facturerProvider)
            .emettreConsommationsDuSejour(
              panier: panier,
              reservation: reservation,
              acheteur: acheteur,
            );
      },
    );

/* ====================================================================== */
/* Édition A4 — l'auteur et le logo                                        */
/* ====================================================================== */

/// L'auteur de l'édition, **dérivé de la session réellement connectée**.
///
/// ## Pourquoi un provider dédié plutôt qu'une lecture dans l'écran
///
/// Parce que c'est exactement la non-conformité que
/// `RESPECT_TABLEAU_RAPPORT.md` §4 recense : *« Auteur affiché =
/// "Administrateur" par défaut au lieu du vrai utilisateur connecté — valeur de
/// test laissée en dur, jamais reliée à la session RBAC réelle »*. Un seul
/// endroit fait la dérivation ; il n'y a donc aucun endroit où une valeur de
/// repli puisse s'installer.
///
/// **`null` quand personne n'est connecté**, et le bouton d'édition est alors
/// désactivé. Un repli sur « Administrateur » ferait sortir un document signé
/// par quelqu'un qui n'a rien édité.
final auteurEditionProvider = Provider<AuteurEdition?>(
  (ref) => auteurDepuisSession(ref.watch(sessionProvider)),
);

/// La dérivation elle-même, isolée du conteneur.
///
/// `SessionNotifier` est une classe `final` : aucun test ne peut lui poser une
/// session à la main. Sortir la règle du provider est donc la seule façon de
/// l'**exécuter** sur une session réellement peuplée, plutôt que de la déclarer
/// et d'espérer. Le provider n'est plus que du câblage — et son autre branche,
/// celle du conteneur sans session, est éprouvée par le provider lui-même.
AuteurEdition? auteurDepuisSession(Session? session) => session == null
    ? null
    : AuteurEdition(nom: session.nom, role: session.role);

/// Le logo de l'établissement, **embarqué dans le paquet applicatif**.
///
/// [AppAssets.logo] — le PNG du Product Owner depuis le 14/10/2026 (D392),
/// le même fichier que l'en-tête des états du serveur. Le package `pdf` le
/// décode (PNG 24 bits sans alpha) et le pose en `BoxFit.contain` dans son
/// cadre : paysage, jamais étiré.
///
/// Il est **lu du paquet, jamais du réseau** : le poste du Gîte encaisse hors
/// connexion, et une facture qui attendrait un téléchargement pour s'imprimer
/// serait le seul endroit du logiciel à exiger Internet.
///
/// Une lecture qui échoue rend `null` plutôt que de lever : une facture sans
/// logo reste une facture remise au client, une exception à l'impression lui
/// fait perdre son document.
final logoEtablissementProvider = FutureProvider<Uint8List?>((ref) async {
  try {
    final donnees = await rootBundle.load(AppAssets.logo);
    return donnees.buffer.asUint8List();
  } on Object {
    return null;
  }
});

/// Les réglages des documents (activités, ville, référence, signataire, interrupteurs), descendus du
/// serveur en lecture — relus à CHAQUE édition (autoDispose) : un réglage changé au serveur figure
/// sur le document suivant, sans redémarrer le poste.
final reglagesDocumentsProvider = FutureProvider.autoDispose<ReglagesDocuments>(
  (ref) async => ReglagesDocuments.depuis(
    Map<String, String?>.of(
      await ParametresDao(ref.read(baseLocaleProvider)).lireTout(),
    ),
  ),
);

/// Le bloc signature d'un document A4 : `null` quand l'interrupteur est sur Non (ni nom, ni
/// images) ; sinon nom, fonction et les images descendues, s'il y en a (PO, 07/11/2026).
Future<BlocSignatureA4?> composerBlocSignature(
  T Function<T>(ProviderListenable<T>) lire, {
  required String? raisonSociale,
  ReglagesDocuments? reglages,
}) async {
  final r =
      reglages ??
      await lire<Future<ReglagesDocuments>>(reglagesDocumentsProvider.future);
  if (!r.signatureAffichee) return null;
  return BlocSignatureA4.depuis(
    r,
    raisonSociale: raisonSociale ?? 'TATACORA AFRIQUE',
    signature: await lire(signatureDocumentProvider.future),
    cachet: await lire(cachetDocumentProvider.future),
  );
}

/* ====================================================================== */
/* Filtres — des COLONNES, jamais des entrepôts                            */
/* ====================================================================== */

/// L'origine affichée, `null` pour « toutes ».
///
/// C'est un **filtre de lecture** sur un registre unique. Le stocker ici plutôt
/// que de lire trois listes distinctes n'est pas un détail d'implémentation :
/// trois listes voudraient dire trois entrepôts, donc trois séquences de
/// numéros qui se recouvrent — le défaut n°1 que le moteur évite.
final origineFiltreeProvider =
    NotifierProvider<OrigineFiltreeNotifier, OrigineFacture?>(
      OrigineFiltreeNotifier.new,
    );

final class OrigineFiltreeNotifier extends Notifier<OrigineFacture?> {
  @override
  OrigineFacture? build() => null;

  void definir(OrigineFacture? origine) => state = origine;
}

/// Le terme cherché — « N°, client… », comme au maître.
///
/// Il porte sur le **numéro** et sur le **client**, et sur rien d'autre. Un
/// registre se retrouve par l'un ou par l'autre : c'est le numéro qu'un client
/// cite au téléphone, et le nom qu'un comptable cherche dans une liasse.
final rechercheFactureProvider =
    NotifierProvider<_RechercheFactureNotifier, String>(
      _RechercheFactureNotifier.new,
    );

final class _RechercheFactureNotifier extends Notifier<String> {
  @override
  String build() => '';

  void definir(String terme) => state = terme;
}

/// L'activité affichée, `null` pour « toutes » — le `filtre-fac-module` du
/// maître.
///
/// ## Une facture porte PLUSIEURS activités
///
/// C'est ce qui distingue ce filtre de celui d'origine. Une pièce est d'une
/// seule origine, mais elle peut recouvrir une chambre **et** des
/// consommations : filtrer sur « Bar » doit donc retenir toute facture qui
/// **contient** une ligne de bar, pas seulement celles qui n'en contiendraient
/// que. Retenir l'inverse ferait disparaître du filtre les factures les plus
/// fournies — celles qui portent le plus d'argent.
final moduleFiltreProvider =
    NotifierProvider<_ModuleFiltreNotifier, ModuleFacturable?>(
      _ModuleFiltreNotifier.new,
    );

final class _ModuleFiltreNotifier extends Notifier<ModuleFacturable?> {
  @override
  ModuleFacturable? build() => null;

  void definir(ModuleFacturable? module) => state = module;
}

/// La SÉLECTION du registre — identifiants cochés (`Facturation::$selection`).
///
/// Elle n'écrit rien : c'est le périmètre que « Exporter » reprend, comme le
/// conseil de la modale d'export de la vue (« utilisez la case à cocher du
/// tableau pour n'exporter qu'une sélection »).
///
/// ## Un filtre qui change la remet à zéro
///
/// La vue la vide quand la recherche ou l'activité change (`updated()`) : sans
/// cela, une sélection faite sous un filtre précédent survivrait, invisible, et
/// l'export porterait sur des lignes que personne ne voit (PA-119). Le notifier
/// LIT les trois filtres du poste (recherche, activité, origine) : en changer un
/// reconstruit l'état, donc le vide.
final selectionFacturesProvider =
    NotifierProvider<SelectionFacturesNotifier, Set<String>>(
      SelectionFacturesNotifier.new,
    );

final class SelectionFacturesNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    ref
      ..watch(rechercheFactureProvider)
      ..watch(moduleFiltreProvider)
      ..watch(origineFiltreeProvider);
    return const {};
  }

  void basculer(String id) {
    final suivant = {...state};
    if (!suivant.remove(id)) suivant.add(id);
    state = suivant;
  }

  /// La case d'en-tête : coche (ou décoche) les pièces de la PAGE affichée.
  void definirPage(Iterable<String> ids, {required bool coche}) {
    final suivant = {...state};
    if (coche) {
      suivant.addAll(ids);
    } else {
      suivant.removeAll(ids);
    }
    state = suivant;
  }

  void vider() => state = const {};
}

/// Combien d'avoirs chaque facture porte, par NUMÉRO de la facture — le
/// `facture->avoirs->count()` de la vue (« 2 avoir(s) » à côté du statut).
///
/// Lu sur le registre ENTIER, filtres exclus : l'avoir d'une facture peut ne
/// pas passer la recherche tapée, et le décompte de la facture ne doit pas
/// bouger avec elle.
final avoirsParFactureProvider = FutureProvider<Map<String, int>>((ref) async {
  // Relu après chaque écriture du registre.
  ref.watch(registreProvider);
  final pieces = await ref.watch(depotFactureProvider).pieces();
  final decompte = <String, int>{};
  for (final p in pieces) {
    final de = p.avoirDe;
    if (de != null) decompte[de] = (decompte[de] ?? 0) + 1;
  }
  return decompte;
});

/* ====================================================================== */
/* Lectures                                                                */
/* ====================================================================== */

/// L'export PDF du **registre**, exposé comme action injectable — enregistré
/// par la fenêtre « Enregistrer sous » (14/10/2026), rend le CHEMIN écrit,
/// `null` : annulé.
///
/// Un seul endroit où le document est produit : un `Printing.layoutPdf` ou
/// une écriture de fichier recopiés dans chaque écran seraient un chemin de
/// plus à ne jamais exécuter (PA-63), et un test de widget n'a pas de greffon
/// natif.
final exporterRegistrePdfProvider =
    Provider<Future<String?> Function(EtatRegistreFactures)>(
      (ref) =>
          (etat) async => ref
              .read(enregistrementExportProvider)
              .exporter(
                base: 'registre_factures',
                type: TypeFichierEnregistre.pdf,
                octets: await etat
                    .avecEntete(
                      await ref.read(lireEnteteEtablissementProvider)(),
                    )
                    .pdf(),
              ),
    );

/// L'export tableur du registre — rend le **chemin** du fichier écrit, `null`
/// : annulé.
///
/// Le nom du fichier est dit par le toast commun : un export silencieux est
/// un export que personne ne retrouve.
///
/// ⚠ Fichier **CSV**, pas XLSX — l'écart avec le maître et ses raisons sont en
/// tête de `impression/etat_historique.dart` (convention serveur RG-19).
final exporterRegistreProvider =
    Provider<Future<String?> Function(EtatRegistreFactures)>(
      (ref) =>
          (etat) => ref
              .read(enregistrementExportProvider)
              .exporter(
                base: 'registre_factures',
                type: TypeFichierEnregistre.csv,
                octets: etat.csvOctets(),
              ),
    );

/// Le registre **tel que l'écran l'affiche** — les trois filtres appliqués.
///
/// L'origine est filtrée **en base** (le dépôt sait le faire) ; le terme et
/// l'activité le sont ensuite en mémoire, faute d'index utile sur un registre
/// de poste. Les trois se cumulent, et c'est cette liste-là que les exports
/// emportent : « l'export porte sur ce qui est affiché » (PA-119).
final registreProvider = FutureProvider<List<PieceFacturation>>((ref) async {
  final pieces = await ref
      .watch(depotFactureProvider)
      .pieces(origine: ref.watch(origineFiltreeProvider));

  final terme = ref.watch(rechercheFactureProvider).trim().toLowerCase();
  final module = ref.watch(moduleFiltreProvider);
  // Sélecteur d'exercice global (PO, 20/10/2026) : les pièces ÉMISES dans
  // l'exercice consulté.
  final exercice = ref.watch(exerciceConsulteProvider);

  return pieces
      .where((p) {
        if (!dansLExercice(exercice, p.dateEmission.toIso8601String())) {
          return false;
        }
        if (terme.isNotEmpty) {
          final champs = '${p.numero} ${p.clientNom}'.toLowerCase();
          if (!champs.contains(terme)) return false;
        }
        // `any` et non `every` : une facture qui recouvre une chambre ET des
        // consommations appartient aux deux activités.
        if (module != null && !p.lignes.any((l) => l.module == module)) {
          return false;
        }
        return true;
      })
      .toList(growable: false);
});

final kpisFacturationProvider = FutureProvider<KpisFacturation>(
  (ref) => KpisFacturation.calculer(ref.watch(depotFactureProvider)),
);

/// La facture émise d'une réservation — ⚠ **avoirs exclus**.
///
/// C'est la lecture qui décide d'afficher, ou non, un bouton de téléchargement
/// sur une fiche de séjour. Sans l'exclusion des avoirs, elle proposerait au
/// client un document à montant négatif à la place de sa facture.
final facturePourReservationProvider =
    FutureProvider.family<PieceFacturation?, String>(
      (ref, reservationId) =>
          ref.watch(depotFactureProvider).facturePourReservation(reservationId),
    );

/// La facture émise d'un panier — ⚠ **avoirs exclus**.
///
/// C'est cette lecture qui décide si le pied du panier propose « Émettre la
/// facture » ou « Voir le ticket ». Proposer un téléchargement qui ne pointe
/// vers rien est pire qu'un bouton absent : l'utilisateur ne sait alors pas si
/// le document manque ou si l'écran est cassé (leçon PA-89).
final facturePourPanierProvider =
    FutureProvider.family<PieceFacturation?, String>(
      (ref, panierId) =>
          ref.watch(depotFactureProvider).facturePourPanier(panierId),
    );

/// La pièce affichée à l'écran, par identifiant.
///
/// L'identifiant, pas l'objet : la pièce vit en base, et la garder en mémoire
/// ferait diverger l'écran de la base dès la première annulation.
final pieceAfficheeProvider = NotifierProvider<PieceAfficheeNotifier, String?>(
  PieceAfficheeNotifier.new,
);

final class PieceAfficheeNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void definir(String? pieceId) => state = pieceId;
}

final pieceCouranteProvider = FutureProvider<PieceFacturation?>((ref) {
  final id = ref.watch(pieceAfficheeProvider);
  if (id == null) return Future.value(null);
  return ref.watch(depotFactureProvider).parId(id);
});

/// Recharge tout ce qui dépend du registre, après une écriture.
///
/// Une seule fonction plutôt qu'un `invalidate` recopié dans chaque écran :
/// oublier d'invalider une liste laisserait une facture absente de l'écran
/// alors qu'elle est en base — et le comptoir la rééditerait, donc en émettrait
/// une seconde avec un second numéro.
void rafraichirFacturation(WidgetRef ref) {
  ref
    ..invalidate(registreProvider)
    ..invalidate(kpisFacturationProvider)
    ..invalidate(pieceCouranteProvider)
    ..invalidate(facturePourReservationProvider)
    ..invalidate(facturePourPanierProvider);
}
