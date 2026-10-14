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

  final filtres = <String>[
    if (terme.isNotEmpty) 'recherche : $terme',
    if (categorie != null) 'catégorie : ${categorie.libelle}',
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
              // `null` s'écrit vide : aucune colonne locale, et « 0 » se
              // lirait « aucune place ».
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
          'Colonne « Places » vide : aucune colonne de capacité sur ce poste.',
          'Le « Véhicule » est son IMMATRICULATION : la table n\'a aucune '
              'colonne de nom.',
        ],
      );

    case OngletVehicules.immobilisations:
      // Aucune table locale ne porte les immobilisations : il n'y a rien à
      // exporter, et un fichier à en-têtes seules se lirait « aucune
      // immobilisation ».
      return null;

    case OngletVehicules.planning:
    case OngletVehicules.contrats:
      final contrats = await ref.read(contratsProvider.future);

      final lignes = contrats
          .where((c) => c.chevauche(periode.debut, periode.fin))
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
              // Aucune colonne de numéro.
              null,
              c.immatriculation,
              c.clientNom,
              // Exigés à la saisie, stockés nulle part.
              null,
              null,
              c.debut,
              c.fin,
              c.nombreJours.toString(),
              c.montant,
              // Aucune colonne d'acompte, donc aucun reste dû.
              null,
              null,
              // Aucune colonne de statut (PA-50).
              null,
            ],
        ],
        mentions: [
          mentionFiltre,
          'Colonnes « N° », « Acompte », « Reste dû » et « État » vides : '
              'ce poste ne les enregistre pas. Une case vide dit '
              '« la donnée n\'existe pas » ; un « 0 » dirait « soldé ».',
          'Colonnes « Pièce » et « Permis » vides : les deux numéros sont '
              'exigés pour établir un contrat, et ne sont conservés nulle '
              'part — la table ne porte que des chemins de fichier.',
          'Colonne « Montant » RECALCULÉE au tarif courant du véhicule : '
              'aucune colonne ne fige le tarif d\'une location, et modifier la '
              'grille réécrit le montant des contrats déjà signés.',
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
