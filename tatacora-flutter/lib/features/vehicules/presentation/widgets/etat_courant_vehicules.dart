// Vue Blade maîtresse (PA-183) : pwa/vehicules/locations.blade.php
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/contrat_location.dart';
import '../../domain/entities/vehicule.dart';
import '../../domain/indicateurs_vehicules.dart';
import '../../impression/etat_vehicules.dart';
import '../providers_vehicules.dart';

/// L'état exporté par « Excel », **construit depuis l'onglet actif**.
///
/// Un export porte sur ce qui est AFFICHÉ, filtre compris, et le document le
/// dit (PA-119). La vue le fait explicitement : des états distincts, un par
/// onglet, avec des en-têtes différentes.
///
/// Rend `null` quand il n'y a rien à écrire — l'écran refuse alors l'export au
/// lieu de produire un fichier vide qui se lirait « aucun contrat ».
Future<EtatVehicules?> construireEtatCourant(WidgetRef ref) async {
  final onglet = ref.read(ongletVehiculesProvider);
  final periode = ref.read(periodeVehiculesProvider);
  final terme = ref.read(rechercheVehiculesProvider).trim().toLowerCase();
  final categorie = ref.read(categorieVehiculesProvider);

  final libellePeriode = periode.complete
      ? 'Du ${periode.debut} au ${periode.fin}'
      : 'Toutes périodes';

  final statutContrats = ref.read(statutContratsProvider);
  final filtres = <String>[
    if (terme.isNotEmpty) 'recherche : $terme',
    if (categorie != null) 'catégorie : ${categorie.libelle}',
    // Le document porte sur ce qui est AFFICHÉ, et il le DIT (PA-119) : la liste
    // des contrats est filtrée par le statut, ce que la description de la vue
    // (`descriptionDuFiltre`) ne mentionne pas.
    if (onglet == OngletVehicules.contrats ||
        onglet == OngletVehicules.planning)
      switch (statutContrats) {
        statutContratActif => 'statut : contrats actifs',
        statutContratAnnule => 'statut : annulés',
        _ => 'statut : tous',
      },
  ];
  final mentionFiltre = filtres.isEmpty
      ? 'Aucun filtre appliqué.'
      : 'Filtre appliqué — ${filtres.join(' · ')}';

  switch (onglet) {
    case OngletVehicules.parc:
      final parc = await ref.read(parcProvider.future);

      final lignes = parc
          .where((v) => _correspond(v, terme))
          .toList(growable: false);

      return EtatVehicules(
        titre: 'Disponibilité du parc',
        periode: libellePeriode,
        // Les en-têtes de la vue, dans son ordre.
        entetes: const [
          'Véhicule',
          'Catégorie',
          'Places',
          'Permis',
          'Tarif/jour',
          'Montant période',
          'Statut',
        ],
        lignes: [
          for (final v in lignes)
            [
              v.immatriculation,
              v.categorieLibelle,
              // `null` (véhicule d'avant la v41) s'écrit vide : « 0 » se lirait
              // « aucune place ».
              v.capacite?.toString(),
              v.exigePermis ? 'exigé' : 'dispensé',
              v.tarifJour,
              _montantPeriode(v.tarifJour, periode.jours),
              v.statutLibelle,
            ],
        ],
        mentions: [
          mentionFiltre,
          // La colonne « Disponibilité » de l'écran est remplacée par le
          // STATUT : la disponibilité dépend de la période affichée, et un
          // document qui la porterait sans la période serait faux le lendemain.
          'Colonne « Statut » et non « Disponibilité » : la disponibilité se '
              'calcule sur la période affichée, et ne veut plus rien dire une '
              'fois le fichier remis. La période du document est en en-tête.',
          'Colonne « Places » vide pour un véhicule saisi avant que ce poste '
              'l\'enregistre : « 0 » se lirait « aucune place ».',
          'Le « Véhicule » est son IMMATRICULATION : la table n\'a aucune '
              'colonne de nom.',
        ],
      );

    case OngletVehicules.immobilisations:
      // ⚠ Le motif d'origine (« aucune table locale ne porte les
      // immobilisations ») est PÉRIMÉ depuis la v32 (`entretiens_vehicule_local`).
      // Cet onglet n'a toujours pas d'export ici, alors que le web exporte cinq
      // colonnes (véhicule, motif, date, coût, auteur) : écart OUVERT, signalé
      // le 27/10/2026, non traité par ce nettoyage.
      return null;

    case OngletVehicules.planning:
    case OngletVehicules.contrats:
      final contrats = await ref.read(contratsProvider.future);

      final lignes = contrats
          .where((c) => c.chevauche(periode.debut, periode.fin))
          // Le filtre de statut de la vue, comme l'écran : le document porte sur
          // ce qui est AFFICHÉ.
          .where(
            (c) => switch (statutContrats) {
              statutContratActif => !c.annule,
              statutContratAnnule => c.annule,
              _ => true,
            },
          )
          .where((c) => _correspondContrat(c, terme))
          .toList(growable: false);

      return EtatVehicules(
        titre: 'Contrats de location',
        periode: libellePeriode,
        // Les en-têtes du document de la vue, dans son ordre.
        entetes: const [
          'N°',
          'Véhicule',
          'Client',
          'Pièce',
          'Permis',
          'Du',
          'Au',
          'Jours',
          'Montant',
          'Acompte',
          'Reste dû',
          'État',
        ],
        lignes: [
          for (final c in lignes)
            [
              // Le N° `LOC-…` du serveur (v41) ; vide tant qu'il n'est pas revenu.
              c.numero,
              c.immatriculation,
              c.clientNom,
              // Exigés à la saisie, stockés nulle part.
              null,
              null,
              c.debut,
              c.fin,
              c.nombreJours.toString(),
              // Le montant FIGÉ, l'acompte et le reste dû (v41) ; vides pour un
              // contrat d'avant (la case vide dit « inconnu », jamais « soldé »).
              c.montant,
              c.acompte,
              c.resteDu,
              // `contrat_annule` / `contrat_actif`.
              c.annule ? 'Annulé' : 'Actif',
            ],
        ],
        mentions: [
          mentionFiltre,
          'Colonnes « N° », « Montant », « Acompte » et « Reste dû » vides pour '
              'un contrat signé avant que ce poste les enregistre (ou dont le '
              'numéro n\'est pas encore revenu du serveur). Une case vide dit '
              '« la donnée n\'existe pas » ; un « 0 » dirait « soldé ».',
          'Colonnes « Pièce » et « Permis » vides : les deux numéros sont '
              'exigés pour établir un contrat, et ne sont conservés nulle '
              'part — la table ne porte que des chemins de fichier.',
        ],
      );
  }
}

bool _correspond(Vehicule v, String terme) =>
    terme.isEmpty ||
    v.immatriculation.toLowerCase().contains(terme) ||
    (v.categorieLibelle?.toLowerCase().contains(terme) ?? false);

bool _correspondContrat(ContratLocation c, String terme) =>
    terme.isEmpty ||
    c.immatriculation.toLowerCase().contains(terme) ||
    (c.clientNom?.toLowerCase().contains(terme) ?? false);

/// `tarif_jour × jours`, en décimal exact — jamais un `double`.
String? _montantPeriode(String tarif, int? jours) {
  if (jours == null || jours <= 0) return null;
  return sommeDecimales(List<String>.filled(jours, tarif));
}
