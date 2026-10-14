/// Les providers de M9 — Tourisme.
///
/// ## Tout vient de la base LOCALE, et il n'y a aucune branche « si connecté »
///
/// Le poste est zéro réseau (`core/donnees_absentes.dart`, décision du Product
/// Owner du 14/09/2026). Les trois tables de M9 vivent sur le poste, et ce
/// fichier ne déclare **aucun client HTTP** : il n'y a rien à rafraîchir, rien
/// à réessayer, et donc aucun état « injoignable » à porter. C'est l'inverse
/// exact de M8, dont les providers sont tous en `autoDispose` parce que leur
/// donnée vient d'ailleurs et vieillit.
///
/// ## Les filtres sont des registres FERMÉS
///
/// Les trois listes de la barre (`prestation`, `remplissage`, `statut`) sont
/// des `enum` avec `switch` exhaustif, jamais des chaînes libres : une valeur
/// ajoutée demain ne doit pas obtenir un comportement par omission — elle doit
/// faire échouer la compilation.
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/di/providers.dart';
import '../../../core/format/formats.dart';
import '../../../core/rbac/garde_acces.dart';
import '../../crm/data/client_dao.dart';
import '../../crm/domain/entities/client.dart';
import '../data/tourisme_dao.dart';
import '../domain/departs.dart';
import '../domain/entities/circuit.dart';
import '../domain/entities/guide.dart';
import '../domain/entities/reservation_tour.dart';
import '../impression/etat_tourisme.dart';

/// L'accès aux trois tables locales de M9.
/// L'écriture est-elle permise sur M9 ?
///
/// ⚠ Ajouté le 14/09/2026 : il n'existait AUCUN contrôle de droits dans tout
/// `features/tourisme/`, alors que la vue en pose cinq (`departs.blade.php`
/// l.213, 326, 458, 568 — `@if ($peutEcrire)`). Un profil `M9 = 'L'` pouvait
/// créer une prestation, prendre une réservation, réaffecter un guide et
/// annuler un départ vendu.
///
/// Premier des trois niveaux de RBAC seulement : il évite de proposer ce qui
/// serait refusé, il ne protège rien. Et ici, **il n'y a pas de second niveau
/// à invoquer** — le DAO est local pur, sans contrôle de droits —, ce qui est
/// écrit plutôt que sous-entendu : le masquage est l'unique barrière.
final peutEcrireTourismeProvider = Provider<bool>(
  (ref) => ref.watch(droitsProvider).peutEcrire(ModuleTatacora.m9Tourisme),
);

final tourismeDaoProvider = Provider<TourismeDao>(
  (ref) => TourismeDao(ref.watch(baseLocaleProvider)),
);

/// La donnée d'un `AsyncValue`, ou `null` tant qu'elle n'est pas là.
///
/// `valueOrNull` n'existe pas dans la version de Riverpod de ce dépôt : le
/// motif employé partout ici est le filtrage de `AsyncData`. Une seule
/// écriture, pour que « pas encore chargé » et « en erreur » se traitent de la
/// même façon sur tout l'écran — il affiche alors « — », jamais un zéro qui
/// aurait l'air d'une mesure.
T? donneeOuNull<T>(AsyncValue<T> etat) => switch (etat) {
  AsyncData(value: final v) => v,
  _ => null,
};

/* ====================================================================== */
/* Les trois onglets — vue l.170-172                                       */
/* ====================================================================== */

/// Les onglets de la vue, **dans son ordre**, avec ses libellés au mot.
enum OngletTourisme {
  departs('departs', 'Départs planifiés'),
  reservations('reservations', 'Réservations'),
  catalogue('catalogue', 'Catalogue');

  const OngletTourisme(this.cle, this.libelle);

  final String cle;
  final String libelle;
}

/// `Departs::$onglet = 'departs'` — « Départs planifiés » est l'onglet par
/// défaut de la vue.
final ongletTourismeProvider =
    NotifierProvider<_OngletNotifier, OngletTourisme>(_OngletNotifier.new);

final class _OngletNotifier extends Notifier<OngletTourisme> {
  @override
  OngletTourisme build() => OngletTourisme.departs;

  void definir(OngletTourisme valeur) => state = valeur;
}

/* ====================================================================== */
/* Les filtres — un provider par contrôle de la vue                        */
/* ====================================================================== */

/// La fenêtre « du … au … » de l'en-tête (vue l.98-101).
///
/// `Departs::JOURS_PAR_DEFAUT = 30` : aujourd'hui, et aujourd'hui + 30 jours.
/// Un écran qui s'ouvrirait sur « choisissez une période » passerait pour
/// cassé.
final class PeriodeTourisme {
  const PeriodeTourisme({required this.debut, required this.fin});

  final DateTime debut;
  final DateTime fin;

  /// La borne haute ne peut pas précéder la borne basse : `Departs::fenetre()`
  /// repart alors sur la fenêtre par défaut plutôt que de rendre une plage
  /// vide, qui afficherait « aucun départ » sur un registre plein.
  PeriodeTourisme get corrigee => fin.isBefore(debut)
      ? PeriodeTourisme(
          debut: debut,
          fin: debut.add(const Duration(days: joursParDefaut)),
        )
      : this;

  static const int joursParDefaut = 30;
}

final periodeTourismeProvider =
    NotifierProvider<_PeriodeNotifier, PeriodeTourisme>(_PeriodeNotifier.new);

final class _PeriodeNotifier extends Notifier<PeriodeTourisme> {
  @override
  PeriodeTourisme build() {
    final aujourdhui = jourDe(DateTime.now());
    return PeriodeTourisme(
      debut: aujourdhui,
      fin: aujourdhui.add(const Duration(days: PeriodeTourisme.joursParDefaut)),
    );
  }

  void definirDebut(DateTime v) =>
      state = PeriodeTourisme(debut: jourDe(v), fin: state.fin);

  void definirFin(DateTime v) =>
      state = PeriodeTourisme(debut: state.debut, fin: jourDe(v));
}

/// La recherche (vue l.180) — « Circuit, client, guide, n°… ».
final rechercheTourismeProvider = NotifierProvider<_TexteNotifier, String>(
  _TexteNotifier.new,
);

final class _TexteNotifier extends Notifier<String> {
  @override
  String build() => '';

  void definir(String valeur) => state = valeur;
}

/// Le filtre par PRESTATION (vue l.191), et non par type.
///
/// La vue garde le libellé par défaut du maître — « Circuits et excursions » —
/// mais ses options sont la liste RÉELLE des circuits : le schéma ne porte
/// **aucun discriminant** entre un circuit et une excursion. Filtrer « par
/// type » serait une commande qui ne filtrerait jamais rien, c'est-à-dire une
/// entrée inerte (Article 3.3).
final prestationTourismeProvider =
    NotifierProvider<_PrestationNotifier, String?>(_PrestationNotifier.new);

final class _PrestationNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void definir(String? valeur) => state = valeur;
}

/// Le filtre de remplissage (vue l.198-203) — registre fermé.
enum FiltreRemplissage {
  tous('Tous les départs'),
  disponible('Places disponibles'),
  complet('Complets'),
  vide('Aucune réservation');

  const FiltreRemplissage(this.libelle);

  final String libelle;

  bool retient(Depart depart) => switch (this) {
    FiltreRemplissage.tous => true,
    FiltreRemplissage.disponible => depart.placesRestantes > 0,
    FiltreRemplissage.complet => depart.placesRestantes == 0,
    FiltreRemplissage.vide => depart.placesVendues == 0,
  };
}

final remplissageTourismeProvider =
    NotifierProvider<_RemplissageNotifier, FiltreRemplissage>(
      _RemplissageNotifier.new,
    );

final class _RemplissageNotifier extends Notifier<FiltreRemplissage> {
  @override
  FiltreRemplissage build() => FiltreRemplissage.tous;

  void definir(FiltreRemplissage valeur) => state = valeur;
}

/// Le filtre de statut (vue l.205-209) — registre fermé.
///
/// ⚠ L'ordre des options est celui de la vue : « Planifiés » d'abord, et
/// SÉLECTIONNÉ par défaut (`Departs::$statut = 'planifie'`), puis « Tous »,
/// puis « Annulés ». Ce n'est pas l'ordre habituel d'une liste, et le
/// réordonner serait choisir à la place du maître.
enum FiltreStatutDepart {
  planifie('Planifiés'),
  tous('Tous'),
  annule('Annulés');

  const FiltreStatutDepart(this.libelle);

  final String libelle;

  bool retientDepart(Depart depart) => switch (this) {
    FiltreStatutDepart.planifie => !depart.annule,
    FiltreStatutDepart.tous => true,
    FiltreStatutDepart.annule => depart.annule,
  };

  bool retientReservation(ReservationTour reservation) => switch (this) {
    FiltreStatutDepart.planifie => !reservation.estAnnulee,
    FiltreStatutDepart.tous => true,
    FiltreStatutDepart.annule => reservation.estAnnulee,
  };
}

final statutTourismeProvider =
    NotifierProvider<_StatutNotifier, FiltreStatutDepart>(_StatutNotifier.new);

final class _StatutNotifier extends Notifier<FiltreStatutDepart> {
  @override
  FiltreStatutDepart build() => FiltreStatutDepart.planifie;

  void definir(FiltreStatutDepart valeur) => state = valeur;
}

/* ====================================================================== */
/* Les lectures                                                            */
/* ====================================================================== */

/// Le catalogue entier — il alimente aussi le filtre par prestation.
final circuitsProvider = FutureProvider<List<Circuit>>(
  (ref) => ref.watch(tourismeDaoProvider).circuits(),
);

/// Le référentiel des guides.
///
/// Vide sur un poste neuf : aucune route n'a jamais exposé les guides, et rien
/// ne les descend. C'est la modale qui le dit, avec les mots du maître.
final guidesTourismeProvider = FutureProvider<List<Guide>>(
  (ref) => ref.watch(tourismeDaoProvider).guides(),
);

/// Le DAO du référentiel client (M3).
///
/// ## Pourquoi il est redéclaré ici, et non repris de M1
///
/// `clientDaoProvider` existe déjà dans `providers_hebergement.dart`, et le
/// réutiliser aurait été le bon réflexe — c'est ce que fait M8. Ce n'est pas
/// possible **aujourd'hui** : ce fichier-là importe encore
/// `core/sync/declencheur_synchronisation.dart` et
/// `core/sync/file_synchronisation.dart`, alors que `core/sync/` a été retiré
/// avec la couche réseau (décision du Product Owner du 14/09/2026, voir
/// `core/donnees_absentes.dart`). L'importer ferait entrer M9 dans une unité
/// de compilation cassée, et l'écran Tourisme deviendrait inconstruisible pour
/// une raison qui ne le concerne pas.
///
/// C'est le MÊME `ClientDao` sur la MÊME base : il n'y a pas deux lectures du
/// référentiel, seulement deux points d'injection. Le jour où M1 sera remis
/// d'aplomb, ce provider disparaît au profit du sien — la ligne à supprimer
/// est celle-ci, et elle est nommée pour être retrouvée.
final _clientDaoProvider = Provider<ClientDao>(
  (ref) => ClientDao(ref.watch(baseLocaleProvider)),
);

/// Le référentiel client (M3).
///
/// RG-18 : le client d'une réservation est une vraie **clé étrangère**, jamais
/// un nom libre. En réécrire une lecture ici donnerait deux registres clients.
final clientsTourismeProvider = FutureProvider<List<Client>>(
  (ref) => ref.watch(_clientDaoProvider).clients(),
);

/// Les lignes de la fenêtre, **et le compte de celles qui sont illisibles**.
final class RegistreTourisme {
  const RegistreTourisme({
    required this.reservations,
    required this.illisibles,
  });

  final List<ReservationTour> reservations;

  /// Des lignes écartées faute de statut connu ou de référence résoluble.
  /// Comptées et affichées, jamais avalées (PA-127).
  final int illisibles;
}

final registreTourismeProvider = FutureProvider<RegistreTourisme>((ref) async {
  final periode = ref.watch(periodeTourismeProvider).corrigee;
  final lu = await ref
      .watch(tourismeDaoProvider)
      .reservationsSurFenetre(periode.debut, periode.fin);

  return RegistreTourisme(
    reservations: lu.reservations,
    illisibles: lu.illisibles,
  );
});

/// Les DÉPARTS affichés : dérivés des lignes, puis filtrés comme la vue.
final departsProvider = FutureProvider<List<Depart>>((ref) async {
  final registre = await ref.watch(registreTourismeProvider.future);
  final prestation = ref.watch(prestationTourismeProvider);
  final statut = ref.watch(statutTourismeProvider);
  final remplissage = ref.watch(remplissageTourismeProvider);
  final terme = ref.watch(rechercheTourismeProvider).trim().toLowerCase();

  return departsDerives(registre.reservations)
      .where((d) => prestation == null || d.circuitId == prestation)
      .where(statut.retientDepart)
      .where(remplissage.retient)
      .where(
        (d) =>
            terme.isEmpty ||
            '${d.circuitNom} ${d.guideNom ?? ''}'.toLowerCase().contains(terme),
      )
      .toList(growable: false);
});

/// Les réservations affichées — mêmes filtres, appliqués aux LIGNES.
///
/// Le filtre de remplissage ne s'y applique pas : il qualifie un départ, pas
/// une réservation. C'est ce que fait la vue (`reservationsAffichees()`).
final reservationsAfficheesProvider = FutureProvider<List<ReservationTour>>((
  ref,
) async {
  final registre = await ref.watch(registreTourismeProvider.future);
  final prestation = ref.watch(prestationTourismeProvider);
  final statut = ref.watch(statutTourismeProvider);
  final terme = ref.watch(rechercheTourismeProvider).trim().toLowerCase();

  return registre.reservations
      .where((r) => prestation == null || r.circuitId == prestation)
      .where(statut.retientReservation)
      .where(
        (r) =>
            terme.isEmpty ||
            '${r.clientNom} ${r.circuitNom}'.toLowerCase().contains(terme),
      )
      .toList(growable: false);
});

/// La bande d'indicateurs — calculée sur les départs AFFICHÉS.
///
/// C'est ce que fait la vue : `agregerDeparts($departsAffiches)`. Les calculer
/// sur le registre entier afficherait des chiffres qui ne correspondent pas au
/// tableau qu'on a sous les yeux.
final agregatsTourismeProvider = FutureProvider<AgregatsDeparts>((ref) async {
  return agregerDeparts(await ref.watch(departsProvider.future));
});

/// Le nombre de départs planifiés par circuit — colonne du catalogue.
///
/// Compte des DATES distinctes, sur les lignes non annulées : deux groupes
/// partis le même jour sont **un** départ, pas deux.
final departsParCircuitProvider = FutureProvider<Map<String, int>>((ref) async {
  final registre = await ref.watch(registreTourismeProvider.future);
  final parCircuit = <String, Set<String>>{};

  for (final r in registre.reservations) {
    if (r.estAnnulee) continue;
    parCircuit
        .putIfAbsent(r.circuitId, () => <String>{})
        .add(cleDeJour(r.dateCircuit));
  }

  return {for (final e in parCircuit.entries) e.key: e.value.length};
});

/// La clé d'un départ pour les deux providers `family` ci-dessous.
typedef CleDepart = (String circuitId, String jourIso);

/// Les places restantes d'un départ — **calculées par le DAO**.
final placesRestantesProvider = FutureProvider.family<int?, CleDepart>((
  ref,
  cle,
) {
  // La modale se rafraîchit quand le registre change : sans cette dépendance,
  // le bloc « Restantes » afficherait le compte d'avant la réservation qu'on
  // vient d'enregistrer.
  ref.watch(registreTourismeProvider);
  return ref
      .watch(tourismeDaoProvider)
      .placesRestantes(cle.$1, DateTime.parse(cle.$2));
});

/// Le catalogue AFFICHÉ : filtré sur le nom ET la zone, comme la vue
/// (`Departs::catalogueFiltre()`, l.715-728).
///
/// Un seul auteur : l'onglet et l'export lisent cette liste, jamais deux
/// filtres écrits à deux endroits (un export porte sur ce qui est affiché,
/// PA-119).
final catalogueAfficheProvider = FutureProvider<List<Circuit>>((ref) async {
  final liste = await ref.watch(circuitsProvider.future);
  final terme = ref.watch(rechercheTourismeProvider).trim().toLowerCase();

  return liste
      .where(
        (c) =>
            terme.isEmpty ||
            c.nom.toLowerCase().contains(terme) ||
            c.zone.toLowerCase().contains(terme),
      )
      .toList(growable: false);
});

/// Le guide DÉJÀ en place sur un départ, ou `null` s'il n'existe pas encore.
final guideDuDepartProvider = FutureProvider.family<Guide?, CleDepart>((
  ref,
  cle,
) {
  ref.watch(registreTourismeProvider);
  return ref
      .watch(tourismeDaoProvider)
      .guideDuDepart(cle.$1, DateTime.parse(cle.$2));
});

/// Recharge tout ce que l'écran affiche après une écriture.
///
/// Un seul point d'entrée : trois `invalidate` recopiés dans trois modales
/// finiraient par diverger, et c'est la modale oubliée qui laisserait un
/// tableau périmé sous les yeux de l'opérateur.
void rechargerTourisme(WidgetRef ref) {
  ref
    ..invalidate(registreTourismeProvider)
    ..invalidate(circuitsProvider)
    ..invalidate(guidesTourismeProvider);
}

/* ====================================================================== */
/* L'export — le bouton « Exporter » de la vue (l.116-117)                 */
/* ====================================================================== */

/// Le dossier où l'export écrit — injectable, pour qu'un test écrive dans un
/// répertoire temporaire au lieu des Documents de la personne qui lance la
/// suite (précédent : l'export des notifications, 09/10/2026).
final dossierExportTourismeProvider = Provider<Future<Directory> Function()>(
  (ref) => getApplicationDocumentsDirectory,
);

/// Écrit le CSV de l'état et rend le CHEMIN du fichier : un export silencieux
/// est un export que personne ne retrouve.
///
/// Injecté comme **action**, jamais appelé depuis un widget : un test de widget
/// n'a pas de dossier Documents, et il doit exister un seul endroit où le
/// fichier s'écrit.
final exporterTourismeProvider =
    Provider<Future<String> Function(EtatTourisme)>(
      (ref) => (etat) async {
        final dossier = await ref.read(dossierExportTourismeProvider)();
        final m = DateTime.now();
        final horodatage =
            '${m.year}'
            '${m.month.toString().padLeft(2, '0')}'
            '${m.day.toString().padLeft(2, '0')}-'
            '${m.hour.toString().padLeft(2, '0')}'
            '${m.minute.toString().padLeft(2, '0')}'
            '${m.second.toString().padLeft(2, '0')}';
        final fichier = File(p.join(dossier.path, 'tourisme-$horodatage.csv'));
        await fichier.writeAsBytes(etat.csvOctets());
        return fichier.path;
      },
    );

/// La description du filtre APPLIQUÉ à l'onglet [onglet], écrite en tête du
/// fichier (`Departs::descriptionDuFiltre()`).
///
/// Le serveur ne cite que la période, le statut et la recherche ; celle-ci dit
/// aussi la prestation et le remplissage, parce qu'ils filtrent réellement les
/// lignes exportées. Chaque filtre n'est cité que pour les onglets qu'il
/// touche : le remplissage ne qualifie qu'un départ, et le catalogue ne
/// connaît que la recherche (la période n'y règle que la colonne des départs).
String descriptionFiltreTourisme({
  required OngletTourisme onglet,
  required PeriodeTourisme periode,
  required FiltreStatutDepart statut,
  required FiltreRemplissage remplissage,
  required String? prestation,
  required String recherche,
}) {
  final morceaux = <String>[
    'du ${formaterDate(periode.debut)} au ${formaterDate(periode.fin)}',
  ];

  if (onglet != OngletTourisme.catalogue) {
    morceaux.add('Statut : ${statut.libelle}');
    if (prestation != null) morceaux.add('Prestation : $prestation');
  }

  if (onglet == OngletTourisme.departs &&
      remplissage != FiltreRemplissage.tous) {
    morceaux.add('Remplissage : ${remplissage.libelle}');
  }

  final terme = recherche.trim();
  if (terme.isNotEmpty) morceaux.add('Recherche : $terme');

  return morceaux.join(' · ');
}

/// L'état exporté, **construit depuis l'onglet actif** et ses filtres.
///
/// Rend un état sans ligne quand l'onglet est vide : c'est l'écran qui refuse
/// alors l'export, au lieu de produire un fichier à en-têtes seules qui se
/// lirait « aucun départ » (PA-119).
Future<EtatTourisme> construireEtatCourantTourisme(WidgetRef ref) async {
  final onglet = ref.read(ongletTourismeProvider);
  final periode = ref.read(periodeTourismeProvider).corrigee;
  final idPrestation = ref.read(prestationTourismeProvider);

  String? nomPrestation;
  if (idPrestation != null) {
    final circuits = await ref.read(circuitsProvider.future);
    for (final c in circuits) {
      if (c.id == idPrestation) nomPrestation = c.nom;
    }
  }

  final filtre = descriptionFiltreTourisme(
    onglet: onglet,
    periode: periode,
    statut: ref.read(statutTourismeProvider),
    remplissage: ref.read(remplissageTourismeProvider),
    prestation: nomPrestation,
    recherche: ref.read(rechercheTourismeProvider),
  );

  switch (onglet) {
    case OngletTourisme.departs:
      return EtatTourisme.departs(
        await ref.read(departsProvider.future),
        filtre: filtre,
      );
    case OngletTourisme.reservations:
      return EtatTourisme.reservations(
        await ref.read(reservationsAfficheesProvider.future),
        filtre: filtre,
      );
    case OngletTourisme.catalogue:
      return EtatTourisme.catalogue(
        await ref.read(catalogueAfficheProvider.future),
        departsParCircuit: await ref.read(departsParCircuitProvider.future),
        filtre: filtre,
      );
  }
}
