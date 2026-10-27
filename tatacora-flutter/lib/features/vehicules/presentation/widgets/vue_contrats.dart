// Vue Blade maîtresse (PA-183) : pwa/vehicules/locations.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/format/formats.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared_widgets/liste_paginee.dart';
import '../../../restaurant/presentation/widgets/coquille_restaurant.dart';
import '../../../restaurant/presentation/widgets/tableau_restaurant.dart';
import '../../../../core/di/providers.dart';
import '../../../../core/rbac/garde_acces.dart';
import '../../../achats/presentation/widgets/modale_archivage_achats.dart';
import '../../domain/entities/contrat_location.dart';
import '../../domain/indicateurs_vehicules.dart';
import '../../domain/regles_vehicules.dart';
import '../providers_vehicules.dart';
import 'vue_parc.dart' show CarteVideVehicules, dateFrVehicules;

/// L'onglet **« Contrats »**.
///
/// @see EF-M8-03 Contrat de location
///
/// ## Les dix colonnes de la vue sont portées (v41, 27/10/2026)
///
/// « N° » (`LOC-…`, rendu par le serveur), « Montant » (net, FIGÉ à la
/// signature), « Acompte » et « Reste dû » ont chacun leur colonne locale. Un
/// contrat d'avant la v41 (ou dont le N° n'est pas encore revenu du serveur) porte
/// « — » : ni le tarif d'aujourd'hui, ni « Soldé » sur un reste inconnu, ni un
/// zéro. Comme la vue : l'acompte nul se rend « — », un reste nul « Soldé », un
/// reste positif en rouge ; la ligne TOTAL additionne les montants, acomptes et
/// restes des contrats NON annulés (« — » si l'un d'eux est inconnu).
///
/// ## « État » et « Annuler » SONT portés (v38, 26/10/2026)
///
/// `contrats_location_local.statut` existe : la pastille « Actif » / « Annulé »,
/// le bouton « Annuler » (derrière la modale de confirmation de la vue), le
/// filtre « Contrats actifs / Tous / Annulés » et la ligne TOTAL (contrats
/// actifs seuls) rendent ce que la vue rend. L'annulation passe par
/// `VehiculeDao.annulerContrat`, seul écrivain.
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
    final statut = ref.watch(statutContratsProvider);
    final peutEcrire = ref
        .watch(droitsProvider)
        .peutEcrire(ModuleTatacora.m8Vehicules);

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
        cleFiltre: (terme, periode, statut),
        peutEcrire: peutEcrire,
        contrats: lignes
            .where((c) => c.chevauche(periode.debut, periode.fin))
            // `contratsFiltres()` : `actif` = tout sauf `annule`, vide = tous,
            // `annule` = les annulés.
            .where(
              (c) => switch (statut) {
                statutContratActif => !c.annule,
                statutContratAnnule => c.annule,
                _ => true,
              },
            )
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
  const _Corps({
    required this.contrats,
    required this.cleFiltre,
    required this.peutEcrire,
  });

  final List<ContratLocation> contrats;

  /// Le droit d'écriture sur M8 : « Annuler » n'est offert qu'avec lui
  /// (`@if ($peutEcrire && ! $estAnnule)`).
  final bool peutEcrire;

  /// La recherche et la période : les changer ramène à la page 1.
  final Object cleFiltre;

  @override
  Widget build(BuildContext context) {
    // La vue n'additionne que les contrats NON annulés (`@if (! $estAnnule)`) et
    // compte « contrat(s) actif(s) » de même.
    final actifs = contrats.where((c) => !c.annule).toList(growable: false);
    String? somme(String? Function(ContratLocation) lire) =>
        actifs.isEmpty ? '0.00' : sommeDecimales(actifs.map(lire));
    final total = somme((c) => c.montant);
    final totalAcompte = somme((c) => c.acompte);
    final totalReste = somme((c) => c.resteDu);

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
            // Dix contrats par page (PO, 14/10/2026) ; la ligne TOTAL
            // ci-dessous porte TOUS les contrats retenus, jamais la page.
            corps: ListePaginee<ContratLocation>(
              elements: contrats,
              prefixeCle: 'vehicules-contrats-pagination',
              cleRemiseAZero: cleFiltre,
              constructeur: (_, page) => TableauRestaurant(
                gabarit: GabaritTableau.carte,
                colonnes: VueContrats.colonnes,
                clesLignes: [
                  for (final c in page) Key('vehicules-contrat-${c.id}'),
                ],
                lignes: [
                  for (final c in page)
                    [
                      _Numero(contrat: c),
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
                      // `MontantFcfa::format($c->montant)` : le montant FIGÉ.
                      Text(
                        formaterMontantDecimal(c.montant, suffixe: 'FCFA') ??
                            CarteIndicateurRestaurant.absent,
                        key: Key('vehicules-contrat-montant-${c.id}'),
                        style: TextesRestaurant.corpsFort.copyWith(
                          color: AppColors.navy,
                        ),
                      ),
                      _Acompte(contrat: c),
                      _ResteDu(contrat: c),
                      _EtatContrat(contrat: c),
                      _ActionAnnuler(contrat: c, peutEcrire: peutEcrire),
                    ],
                ],
              ),
            ),
          ),
          // La ligne TOTAL de la vue — fond navy, texte blanc, gras, avec ses
          // trois totaux (montant, acompte, reste dû). Rendue sous le tableau
          // plutôt que dans son gabarit.
          _LigneTotal(
            nombre: actifs.length,
            montant: total,
            acompte: totalAcompte,
            reste: totalReste,
          ),
        ],
        // La page se termine après le tableau (directive du PO, 14/10/2026).
      ],
    );
  }
}

/// La ligne TOTAL — `.total-fort { background: var(--navy); color: #fff;
/// font-weight: 700 }`.
class _LigneTotal extends StatelessWidget {
  const _LigneTotal({
    required this.nombre,
    required this.montant,
    required this.acompte,
    required this.reste,
  });

  final int nombre;
  final String? montant;
  final String? acompte;
  final String? reste;

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
            // La formulation de la vue : seuls les contrats NON annulés comptent.
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
          Text(
            formaterMontantDecimal(acompte, suffixe: 'FCFA') ??
                CarteIndicateurRestaurant.absent,
            key: const Key('vehicules-contrats-total-acompte'),
            style: style,
          ),
          Text(
            formaterMontantDecimal(reste, suffixe: 'FCFA') ??
                CarteIndicateurRestaurant.absent,
            key: const Key('vehicules-contrats-total-reste'),
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
            'avec guide',
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

/// La pastille « État » — « Actif » / « Annulé » (`contrat_actif`,
/// `contrat_annule`). Un contrat sans statut (d'avant la v38) est actif.
class _EtatContrat extends StatelessWidget {
  const _EtatContrat({required this.contrat});

  final ContratLocation contrat;

  @override
  Widget build(BuildContext context) {
    return contrat.annule
        ? PastilleRestaurant(
            cle: Key('vehicules-etat-annule-${contrat.id}'),
            compacte: true,
            texte: 'Annulé',
            fond: Ardoise.c100,
            couleur: Ardoise.c500,
          )
        : PastilleRestaurant(
            cle: Key('vehicules-etat-actif-${contrat.id}'),
            compacte: true,
            texte: 'Actif',
            fond: AppColors.badgeVertFond,
            couleur: AppColors.succes,
          );
  }
}

/// Le bouton « Annuler » de la vue (`annuler_contrat`), derrière la modale de
/// confirmation du composant partagé (« Voulez-vous annuler le contrat :element ? »).
/// Offert avec le droit d'écriture M8 et sur un contrat NON annulé seulement.
///
/// Le succès dit la phrase de la vue (« Contrat :numero annulé — le véhicule
/// redevient disponible. »), le refus du DAO s'affiche tel quel.
///
/// La vue nomme le contrat par son NUMÉRO (`numero ?? id`, v41) : la question et
/// le message le nomment ainsi. ÉCART DÉLIBÉRÉ — tant que le N° n'est pas revenu
/// du serveur (contrat d'avant, ou pas encore envoyé), c'est le véhicule qui le
/// nomme, lisible, plutôt qu'un identifiant. La vue calcule AVANT la modale ses
/// verrous (`$verrousArchivage`) ; le seul ici est « déjà annulé », et le bouton
/// n'est pas offert dans ce cas.
class _ActionAnnuler extends ConsumerWidget {
  const _ActionAnnuler({required this.contrat, required this.peutEcrire});

  final ContratLocation contrat;
  final bool peutEcrire;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!peutEcrire || contrat.annule) return const SizedBox.shrink();

    return InkWell(
      key: Key('vehicules-annuler-${contrat.id}'),
      borderRadius: BorderRadius.circular(AppRadius.rounded),
      onTap: () => _annuler(context, ref),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.demi,
        ),
        decoration: BoxDecoration(
          border: Border.all(color: Ardoise.c300),
          borderRadius: BorderRadius.circular(AppRadius.rounded),
        ),
        child: Text(
          'Annuler',
          style: TextesRestaurant.mention.copyWith(color: Ardoise.c700),
        ),
      ),
    );
  }

  Future<void> _annuler(BuildContext context, WidgetRef ref) async {
    final element = contrat.numero ?? contrat.immatriculation;
    final confirme = await ouvrirArchivageAchats(
      context,
      message: MessagesVehicules.questionAnnulerContrat(element),
    );
    if (confirme != true || !context.mounted) return;

    try {
      await ref.read(vehiculeDaoProvider).annulerContrat(contrat.id);
      if (!context.mounted) return;
      rechargerVehicules(ref);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const Key('vehicules-contrat-annule'),
          content: Text(MessagesVehicules.contratAnnule(element)),
        ),
      );
    } on RefusVehicule catch (refus) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const Key('vehicules-annulation-refusee'),
          content: Text(refus.message),
        ),
      );
    }
  }
}

/// La colonne « N° » — `$c->numero ?? —`, en police mono 11 px. Le numéro est celui
/// du serveur (séquence `LOC-`) : « — » tant qu'il n'est pas revenu.
class _Numero extends StatelessWidget {
  const _Numero({required this.contrat});

  final ContratLocation contrat;

  @override
  Widget build(BuildContext context) {
    return Text(
      contrat.numero ?? CarteIndicateurRestaurant.absent,
      key: Key('vehicules-contrat-numero-${contrat.id}'),
      style: TextesRestaurant.mentionFine.copyWith(
        fontFamily: 'monospace',
        color: Ardoise.c500,
      ),
    );
  }
}

/// La colonne « Acompte » — `MontantFcfa::formatOuTiret` : un acompte nul se rend
/// « — » (comme la vue), et un acompte INCONNU aussi.
class _Acompte extends StatelessWidget {
  const _Acompte({required this.contrat});

  final ContratLocation contrat;

  @override
  Widget build(BuildContext context) {
    final texte = _nonNul(contrat.acompte)
        ? formaterMontantDecimal(contrat.acompte, suffixe: 'FCFA')
        : null;
    return Text(
      texte ?? CarteIndicateurRestaurant.absent,
      key: Key('vehicules-contrat-acompte-${contrat.id}'),
      style: TextesRestaurant.corps.copyWith(color: PaletteMaitre.emeraude700),
    );
  }
}

/// La colonne « Reste dû » — positif : le montant en rouge ; nul : « Soldé »
/// (`vehicules.pwa.solde`) ; INCONNU (montant ou acompte absent) : « — », jamais
/// « Soldé » — une bonne nouvelle que personne n'a vérifiée.
class _ResteDu extends StatelessWidget {
  const _ResteDu({required this.contrat});

  final ContratLocation contrat;

  @override
  Widget build(BuildContext context) {
    final reste = contrat.resteDu;
    final String texte;
    final Color couleur;
    if (reste == null) {
      texte = CarteIndicateurRestaurant.absent;
      couleur = Ardoise.c400;
    } else if (_positif(reste)) {
      texte =
          formaterMontantDecimal(reste, suffixe: 'FCFA') ??
          CarteIndicateurRestaurant.absent;
      couleur = PaletteMaitre.rouge600;
    } else {
      texte = 'Soldé';
      couleur = Ardoise.c400;
    }
    return Text(
      texte,
      key: Key('vehicules-contrat-reste-${contrat.id}'),
      style: TextesRestaurant.corpsFort.copyWith(color: couleur),
    );
  }
}

bool _nonNul(String? montant) =>
    montant != null && (double.tryParse(montant) ?? 0) != 0;

bool _positif(String montant) => (double.tryParse(montant) ?? 0) > 0;
