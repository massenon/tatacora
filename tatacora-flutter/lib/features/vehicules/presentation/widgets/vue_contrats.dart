// Vue Blade maîtresse (PA-183) : pwa/vehicules/locations.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/format/formats.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../restaurant/presentation/widgets/coquille_restaurant.dart';
import '../../../restaurant/presentation/widgets/tableau_restaurant.dart';
import '../../domain/entities/contrat_location.dart';
import '../../domain/indicateurs_vehicules.dart';
import '../../domain/regles_vehicules.dart';
import '../providers_vehicules.dart';
import 'vue_parc.dart' show CarteVideVehicules, dateFrVehicules;

/// L'onglet **« Contrats »**.
///
/// @see EF-M8-03 Contrat de location
///
/// ## Quatre des dix colonnes de la vue n'ont aucune source LOCALE
///
/// « N° », « Acompte », « Reste dû » et « État » n'ont pas de colonne dans
/// `contrats_location_local`. Elles gardent leur place et portent « — » : les
/// retirer supprimerait des éléments visibles de la vue, et les remplir
/// inventerait des montants sur un écran où l'on décide de relancer un client.
///
/// ⚠ Le schéma **serveur** a gagné `numero`, `acompte`, `reste_a_payer` et
/// `statut` — la vue les rend. La table **locale** ne les a pas. C'est un écart
/// de schéma, consigné tel quel : le combler ici fabriquerait des valeurs que
/// personne n'a saisies.
class VueContrats extends ConsumerWidget {
  const VueContrats({super.key});

  /// Les colonnes de la vue, dans son ordre. « Véhicule » et « Client » sont à
  /// gauche, comme la première.
  static const colonnes = [
    ColonneRestaurant('N°'),
    ColonneRestaurant('Véhicule'),
    ColonneRestaurant('Client'),
    ColonneRestaurant('Période', aDroite: true),
    ColonneRestaurant('Jours', aDroite: true),
    ColonneRestaurant('Montant', aDroite: true),
    ColonneRestaurant('Acompte', aDroite: true),
    ColonneRestaurant('Reste dû', aDroite: true),
    ColonneRestaurant('État', aDroite: true),
    ColonneRestaurant('', aDroite: true),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contrats = ref.watch(contratsProvider);
    final periode = ref.watch(periodeVehiculesProvider);
    final terme = ref.watch(rechercheVehiculesProvider).trim().toLowerCase();

    return contrats.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => NoteRestaurant(
        cle: const Key('vehicules-contrats-erreur'),
        texte: '$e',
        icone: Icons.error_outline,
      ),
      data: (lignes) => _Corps(
        contrats: lignes
            .where((c) => c.chevauche(periode.debut, periode.fin))
            .where(
              (c) =>
                  terme.isEmpty ||
                  c.immatriculation.toLowerCase().contains(terme) ||
                  (c.clientNom?.toLowerCase().contains(terme) ?? false),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _Corps extends StatelessWidget {
  const _Corps({required this.contrats});

  final List<ContratLocation> contrats;

  @override
  Widget build(BuildContext context) {
    final total = sommeDecimales(contrats.map((c) => c.montant));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // `contrats_vide` (vue l.326) : sans contrat, la vue ne rend QUE ce
        // message dans une carte — ni titre, ni en-têtes, ni ligne TOTAL.
        if (contrats.isEmpty)
          const CarteVideVehicules(
            cle: Key('vehicules-contrats-vide'),
            message: 'Aucun contrat ne correspond à ces critères.',
          )
        else ...[
          CadreTableauRestaurant(
            // Le titre du cadre à la vue.
            titre: 'Contrats de location',
            corps: TableauRestaurant(
              gabarit: GabaritTableau.carte,
              colonnes: VueContrats.colonnes,
              clesLignes: [
                for (final c in contrats) Key('vehicules-contrat-${c.id}'),
              ],
              lignes: [
                for (final c in contrats)
                  [
                    const _Absent(
                      raison: 'Un contrat n’a pas de numéro sur ce poste.',
                    ),
                    _CelluleVehicule(contrat: c),
                    _CelluleClient(contrat: c),
                    // La période de la vue : deux dates sur deux lignes.
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          dateFrVehicules(c.debut),
                          style: TextesRestaurant.mention,
                        ),
                        Text(
                          dateFrVehicules(c.fin),
                          style: TextesRestaurant.mention,
                        ),
                      ],
                    ),
                    Text(
                      c.nombreJours.toString(),
                      style: TextesRestaurant.corps,
                    ),
                    Tooltip(
                      message:
                          'Montant RECALCULÉ au tarif courant du véhicule : '
                          'aucune colonne ne fige le tarif d’une location. '
                          'Modifier la grille réécrit le montant de ce contrat.',
                      child: Text(
                        formaterMontantDecimal(c.montant, suffixe: 'FCFA') ??
                            CarteIndicateurRestaurant.absent,
                        style: TextesRestaurant.corpsFort.copyWith(
                          color: AppColors.navy,
                        ),
                      ),
                    ),
                    const _Absent(
                      raison:
                          'Ce poste n’enregistre aucun acompte sur un '
                          'contrat. « 0 FCFA » se lirait « rien versé ».',
                    ),
                    const _Absent(
                      raison:
                          'Le reste dû se déduit de l’acompte, qui n’existe pas. '
                          '« Soldé » serait une bonne nouvelle que personne n’a '
                          'vérifiée.',
                    ),
                    const _EtatContrat(),
                    const _ActionAnnuler(),
                  ],
              ],
            ),
          ),
          // La ligne TOTAL de la vue — fond navy, texte blanc, gras. Rendue sous
          // le tableau plutôt que dans son gabarit, parce que trois de ses
          // quatre montants n'existent pas.
          _LigneTotal(nombre: contrats.length, montant: total),
        ],
        // L'encadré ambre « Un contrat ne s'annule pas » qui suivait est
        // RETIRÉ (directive du PO, 14/10/2026) : la page se termine après le
        // tableau. Le refus reste dit au clic sur « Annuler » (_ActionAnnuler).
      ],
    );
  }
}

/// La ligne TOTAL — `.total-fort { background: var(--navy); color: #fff;
/// font-weight: 700 }`.
class _LigneTotal extends StatelessWidget {
  const _LigneTotal({required this.nombre, required this.montant});

  final int nombre;
  final String? montant;

  @override
  Widget build(BuildContext context) {
    final style = TextesRestaurant.corpsFort.copyWith(
      color: AppColors.neutre0,
      fontWeight: FontWeight.w700,
    );

    return Container(
      // `px-3 py-2.5` — le gabarit de cellule de la vue.
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xsPlus,
      ),
      color: AppColors.navy,
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xs,
        children: [
          Text(
            // La formulation de la vue. ⚠ Elle écrit « contrat(s) actif(s) » :
            // faute de colonne de statut, TOUT contrat est actif, et le mot
            // reste donc exact — pour une raison qui n'est pas la sienne.
            'TOTAL — $nombre contrat(s) actif(s)',
            key: const Key('vehicules-contrats-total'),
            style: style,
          ),
          Text(
            formaterMontantDecimal(montant, suffixe: 'FCFA') ??
                CarteIndicateurRestaurant.absent,
            key: const Key('vehicules-contrats-total-montant'),
            style: style,
          ),
        ],
      ),
    );
  }
}

class _CelluleVehicule extends StatelessWidget {
  const _CelluleVehicule({required this.contrat});

  final ContratLocation contrat;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(contrat.immatriculation, style: TextesRestaurant.corpsFort),
        // La vue écrit ici « Permis <n°> » ou « Sans permis ». Le numéro est
        // EXIGÉ à la saisie et conservé nulle part : la table ne porte que des
        // chemins de fichier.
        Tooltip(
          message:
              'Le numéro de permis est exigé pour établir le contrat, et n’est '
              'conservé nulle part sur ce poste.',
          child: Text(
            CarteIndicateurRestaurant.absent,
            style: TextesRestaurant.mentionFine,
          ),
        ),
        if (contrat.packageAvecGuide)
          Text(
            'avec guide (EF-M8-04)',
            style: TextesRestaurant.mentionFine.copyWith(color: AppColors.gold),
          ),
      ],
    );
  }
}

/// La colonne « Client » — résolue sur `clients_local` par le DAO.
class _CelluleClient extends StatelessWidget {
  const _CelluleClient({required this.contrat});

  final ContratLocation contrat;

  @override
  Widget build(BuildContext context) {
    final nom = contrat.clientNom;

    if (nom == null || nom.isEmpty) {
      return Tooltip(
        message:
            'Ce poste ne connaît pas ce client. Afficher son identifiant ne '
            'dirait rien à personne au comptoir.',
        child: Text(
          CarteIndicateurRestaurant.absent,
          key: Key('vehicules-client-absent-${contrat.id}'),
          style: TextesRestaurant.corps,
        ),
      );
    }

    return Text(
      nom,
      key: Key('vehicules-client-${contrat.id}'),
      style: TextesRestaurant.corps,
    );
  }
}

/// La pastille « État » — la vue pose « Actif » / « Annulé ».
///
/// Faute de colonne de statut, tout contrat est actif. La pastille le dit, et
/// son infobulle dit **pourquoi** : sans elle, « Actif » se lirait comme un
/// état parmi deux, alors qu'il n'y en a qu'un.
class _EtatContrat extends StatelessWidget {
  const _EtatContrat();

  @override
  Widget build(BuildContext context) {
    return const Tooltip(
      message:
          'Un contrat ne peut pas être annulé sur ce poste : tout contrat est '
          'actif, et il le reste.',
      child: PastilleRestaurant(
        cle: Key('vehicules-etat-actif'),
        compacte: true,
        texte: 'Actif',
        fond: AppColors.badgeVertFond,
        couleur: AppColors.succes,
      ),
    );
  }
}

/// Le bouton « Annuler » de la vue — **refusé**, et c'est PA-50.
///
/// Sa modale de confirmation (« Voulez-vous annuler le contrat ») et le filtre
/// « Annulés » sont refusés avec lui ; ils étaient nommés dans le bloc « Ce que
/// cet écran ne rend pas », retiré par directive du PO le 14/10/2026 — le refus
/// reste nommé ici, avec les mots de la vue.
///
/// ÉCART DÉLIBÉRÉ. La vue propose « Annuler » sur chaque ligne active.
/// Ici : la place du bouton est tenue par une mention inerte qui dit pourquoi.
/// Raison : il n'existe **aucune colonne de statut** à écrire, ni sur ce poste
/// ni au schéma de référence. Aucune méthode `annuler()` n'est exposée,
/// délibérément — « une méthode qui ne libère rien laisserait croire que le cas
/// est traité ». La seule façon de libérer le véhicule serait de supprimer la
/// ligne, et la suppression est interdite sur une table transactionnelle.
class _ActionAnnuler extends StatelessWidget {
  const _ActionAnnuler();

  @override
  Widget build(BuildContext context) {
    return const Tooltip(
      message: refusAnnulationContrat,
      child: Text(
        'Annuler : —',
        key: Key('vehicules-annuler-absent'),
        style: TextesRestaurant.mentionFine,
      ),
    );
  }
}

/// Une cellule sans source — « — » et sa raison, jamais un zéro.
class _Absent extends StatelessWidget {
  const _Absent({required this.raison});

  final String raison;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: raison,
      child: const Text(
        CarteIndicateurRestaurant.absent,
        style: TextesRestaurant.corps,
      ),
    );
  }
}
