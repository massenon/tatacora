// Vue Blade maîtresse (PA-183) : pwa/vehicules/locations.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/format/formats.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../achats/presentation/widgets/modale_archivage_achats.dart';
import '../../../restaurant/presentation/widgets/coquille_restaurant.dart';
import '../../../restaurant/presentation/widgets/tableau_restaurant.dart';
import '../../domain/entities/vehicule.dart';
import '../../domain/indicateurs_vehicules.dart';
import '../../domain/regles_vehicules.dart';
import '../providers_vehicules.dart';
import 'modale_contrat.dart';
import 'modale_vehicule.dart';

/// L'onglet **« Parc & disponibilité »** — l'onglet actif par défaut.
///
/// @see EF-M8-01 Référentiel véhicules
/// @see EF-M8-02 Disponibilité et planning
///
/// ## Sept colonnes sur huit ont une source, la huitième porte les actions
///
/// | Colonne de la vue | Source locale |
/// |---|---|
/// | Véhicule | `immatriculation` — la table n'a pas de nom |
/// | Catégorie | `categorie`, rendue par son libellé d'affichage |
/// | Places | **aucune colonne locale** → « — » |
/// | Permis | dérivé de la catégorie (RG-09, unique auteur) |
/// | Tarif / jour | `tarifJour` |
/// | Montant période | `tarif × jours`, en décimal exact |
/// | Disponibilité | calculée sur les contrats du poste |
/// | (actions) | Louer, Éditer, Archiver / Remettre en service |
class VueParc extends ConsumerWidget {
  const VueParc({super.key});

  /// Les colonnes de la vue, dans son ordre. Seule la première est à gauche.
  ///
  /// ⚠ Le NOM de la sixième est « Montant période » et non « N jour(s) » : un
  /// en-tête qui change de texte selon la fenêtre affichée devient faux dès
  /// qu'il quitte l'écran, et il ne nomme pas ce que la colonne contient — un
  /// montant. La fenêtre en jours est une précision, pas un titre.
  static List<ColonneRestaurant> colonnes(int? jours) => [
    const ColonneRestaurant('Véhicule'),
    const ColonneRestaurant('Catégorie', aDroite: true),
    const ColonneRestaurant('Places', aDroite: true),
    const ColonneRestaurant('Permis', aDroite: true),
    const ColonneRestaurant('Tarif / jour', aDroite: true),
    const ColonneRestaurant('Montant période', aDroite: true),
    const ColonneRestaurant('Disponibilité', aDroite: true),
    const ColonneRestaurant('', aDroite: true),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final periode = ref.watch(periodeVehiculesProvider);

    // La disponibilité n'a pas de sens sans plage — le texte de la vue, au mot.
    if (!periode.complete) {
      return const EncadreRestaurant(
        cle: Key('vehicules-parc-sans-periode'),
        ton: TonEncadre.gris,
        titre: 'Choisissez une période.',
        // Explication technique (bornes demi-ouvertes) retirée de l'écran le
        // 14/10/2026 (directive du PO) : la règle vit dans regles_vehicules.
        texte:
            'La disponibilité se lit sur une plage de dates : renseignez '
            '« du » et « au ».',
      );
    }

    final parc = ref.watch(parcProvider);
    final terme = ref.watch(rechercheVehiculesProvider).trim().toLowerCase();

    return parc.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => NoteRestaurant(
        cle: const Key('vehicules-parc-erreur'),
        texte: '$e',
        icone: Icons.error_outline,
      ),
      data: (vehicules) => _Corps(
        vehicules: vehicules
            .where(
              (v) =>
                  terme.isEmpty ||
                  v.immatriculation.toLowerCase().contains(terme) ||
                  (v.categorieLibelle?.toLowerCase().contains(terme) ?? false),
            )
            .toList(growable: false),
        jours: periode.jours,
      ),
    );
  }
}

class _Corps extends ConsumerWidget {
  const _Corps({required this.vehicules, required this.jours});

  final List<Vehicule> vehicules;
  final int? jours;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final periode = ref.watch(periodeVehiculesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Le bandeau de la vue (l.233-237), au mot de `lang/fr/vehicules.php`.
        // La référence RG-09 vit dans le fichier de langue, jamais à l'écran.
        const EncadreRestaurant(
          cle: Key('vehicules-parc-chauffeur'),
          ton: TonEncadre.gris,
          titreSepare: true,
          titre: 'Tarifs « chauffeur inclus ».',
          texte:
              'C\'est une caractéristique du tarif catalogue, pas une option '
              'facturée en plus. Le permis n\'est exigé que pour les catégories '
              'qui le requièrent.',
        ),
        const SizedBox(height: AppSpacing.md),
        // `parc_vide` (vue l.241) : sans véhicule, la vue ne rend QUE ce
        // message dans une carte — ni titre « Parc — du … au … », ni en-têtes
        // (le tableau reste dans son DOM, masqué par `hidden`).
        if (vehicules.isEmpty)
          const CarteVideVehicules(
            cle: Key('vehicules-parc-vide'),
            message: 'Aucun véhicule ne correspond.',
            // Ajout de ce client, sous le message de la vue : sur un poste
            // neuf le parc est vide et personne ne le remplit à la place de
            // l'exploitant (décision zéro réseau du 14/09/2026).
            precision: 'Le parc se saisit sur ce poste : « + Véhicule ».',
          )
        else
          CadreTableauRestaurant(
            // Le titre du cadre à la vue (`parc_titre`, l.246) : « Parc — du
            // :debut au :fin », dates au format `d/m/Y`.
            titre:
                'Parc — du ${dateFrVehicules(periode.debut)} '
                'au ${dateFrVehicules(periode.fin)}',
            corps: TableauRestaurant(
              gabarit: GabaritTableau.carte,
              colonnes: VueParc.colonnes(jours),
              clesLignes: [
                for (final v in vehicules) Key('vehicules-ligne-${v.id}'),
              ],
              lignes: [
                for (final v in vehicules)
                  [
                    _CelluleVehicule(vehicule: v),
                    Text(
                      v.categorieLibelle ?? CarteIndicateurRestaurant.absent,
                      style: TextesRestaurant.corps,
                    ),
                    // Aucune colonne `capacite` sur ce poste — « — », jamais 0.
                    Tooltip(
                      message:
                          'Le nombre de places n’est pas enregistré sur ce '
                          'poste.',
                      child: Text(
                        v.capacite?.toString() ??
                            CarteIndicateurRestaurant.absent,
                        style: TextesRestaurant.corps,
                      ),
                    ),
                    _PastillePermis(exige: v.exigePermis),
                    Text(
                      formaterMontantDecimal(v.tarifJour, suffixe: 'FCFA') ??
                          CarteIndicateurRestaurant.absent,
                      style: TextesRestaurant.corps,
                    ),
                    Text(
                      formaterMontantDecimal(
                            _montantPeriode(v.tarifJour, jours),
                            suffixe: 'FCFA',
                          ) ??
                          CarteIndicateurRestaurant.absent,
                      style: TextesRestaurant.corpsFort,
                    ),
                    _Disponibilite(vehicule: v),
                    _ActionsLigne(vehicule: v),
                  ],
              ],
            ),
          ),
      ],
    );
  }
}

/// La première cellule — l'immatriculation, et ce qui devrait la suivre.
class _CelluleVehicule extends StatelessWidget {
  const _CelluleVehicule({required this.vehicule});

  final Vehicule vehicule;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: 'L’immatriculation est le seul identifiant d’un véhicule.',
          child: Text(
            vehicule.immatriculation,
            style: TextesRestaurant.corpsFort,
          ),
        ),
        // La vue affiche ici « année · transmission ». Aucune des deux colonnes
        // n'existe dans `vehicules_local` : la sous-ligne porte le STATUT, qui
        // existe et qui commande la disponibilité, plutôt qu'une ligne vide.
        Text(
          vehicule.statutLibelle ?? CarteIndicateurRestaurant.absent,
          style: TextesRestaurant.mentionFine,
        ),
      ],
    );
  }
}

/// La pastille « exigé » / « dispensé », aux couleurs de la vue.
class _PastillePermis extends StatelessWidget {
  const _PastillePermis({required this.exige});

  final bool exige;

  @override
  Widget build(BuildContext context) {
    return PastilleRestaurant(
      cle: Key('vehicules-permis-${exige ? 'exige' : 'dispense'}'),
      compacte: true,
      // Les libellés de la vue, en minuscules.
      texte: exige ? 'exigé' : 'dispensé',
      fond: exige ? PaletteMaitre.ambre50 : AppColors.badgeVertFond,
      couleur: exige ? PaletteMaitre.ambre700 : AppColors.succes,
    );
  }
}

/// La colonne « Disponibilité » — **calculée sur les contrats du poste**.
///
/// Trois états, et ils ne se confondent pas :
///
///  - « Hors service » — la vue le distingue de « Engagé » (l.290) : un
///    véhicule retiré du parc n'est pas un véhicule pris ;
///  - « Disponible » — calendrier libre ET statut louable ;
///  - « Engagé » — l'un des deux manque.
class _Disponibilite extends ConsumerWidget {
  const _Disponibilite({required this.vehicule});

  final Vehicule vehicule;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (vehicule.statut == StatutVehicule.horsService) {
      return PastilleRestaurant(
        cle: Key('vehicules-hors-service-${vehicule.id}'),
        compacte: true,
        texte: 'Hors service',
        fond: Ardoise.c100,
        couleur: Ardoise.c500,
      );
    }

    final d = ref.watch(disponibiliteProvider(vehicule.id));

    return switch (d) {
      AsyncData(value: final dispo?) =>
        dispo.disponible
            ? PastilleRestaurant(
                cle: Key('vehicules-dispo-${vehicule.id}'),
                compacte: true,
                texte: 'Disponible',
                fond: AppColors.badgeVertFond,
                couleur: AppColors.succes,
              )
            : PastilleRestaurant(
                cle: Key('vehicules-engage-${vehicule.id}'),
                compacte: true,
                texte: 'Engagé',
                fond: PaletteMaitre.rouge50,
                couleur: PaletteMaitre.rouge700,
              ),
      // Période incomplète : la question n'a pas de sens, et « Engagé » ferait
      // refuser une location possible.
      AsyncData() => Text(
        CarteIndicateurRestaurant.absent,
        key: Key('vehicules-dispo-inconnue-${vehicule.id}'),
        style: TextesRestaurant.corps,
      ),
      AsyncError() => Text(
        CarteIndicateurRestaurant.absent,
        key: Key('vehicules-dispo-erreur-${vehicule.id}'),
        style: TextesRestaurant.corps,
      ),
      _ => const SizedBox(
        width: AppLayout.iconeChamp,
        height: AppLayout.iconeChamp,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    };
  }
}

/// Les actions d'une ligne — l'ordre de la vue (l.298-313).
///
/// « Louer » n'apparaît que sur un véhicule disponible, comme à la vue.
/// « Archiver » et « Remettre en service » s'excluent : la vue montre le second
/// sur un véhicule `hors_service` ou `entretien`, le premier sinon.
class _ActionsLigne extends ConsumerWidget {
  const _ActionsLigne({required this.vehicule});

  final Vehicule vehicule;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(disponibiliteProvider(vehicule.id));
    final libre = switch (d) {
      AsyncData(value: final dispo?) => dispo.disponible,
      _ => false,
    };
    final immobilise = vehicule.statut?.estImmobilise ?? false;

    return Wrap(
      alignment: WrapAlignment.end,
      spacing: AppSpacing.unit,
      runSpacing: AppSpacing.unit,
      children: [
        if (libre)
          FilledButton(
            key: Key('vehicules-louer-${vehicule.id}'),
            onPressed: () async {
              final cree = await ouvrirModaleContrat(
                context,
                vehicule: vehicule,
              );
              if (cree != true || !context.mounted) return;
              rechargerVehicules(ref);
            },
            child: const Text('Louer', style: TextesRestaurant.pastille),
          ),
        OutlinedButton(
          key: Key('vehicules-editer-${vehicule.id}'),
          onPressed: () async {
            final ecrit = await ouvrirModaleVehicule(
              context,
              vehicule: vehicule,
            );
            if (ecrit != true || !context.mounted) return;
            rechargerVehicules(ref);
          },
          child: const Text('Éditer', style: TextesRestaurant.pastille),
        ),
        if (immobilise)
          OutlinedButton(
            key: Key('vehicules-remettre-${vehicule.id}'),
            onPressed: () => _changer(
              context,
              ref,
              StatutVehicule.disponible,
              'Véhicule ${vehicule.immatriculation} remis en service.',
            ),
            child: const Text(
              'Remettre en service',
              style: TextesRestaurant.pastille,
            ),
          )
        else
          OutlinedButton(
            key: Key('vehicules-archiver-${vehicule.id}'),
            onPressed: () => _archiver(context, ref),
            child: const Text('Archiver', style: TextesRestaurant.pastille),
          ),
      ],
    );
  }

  Future<void> _changer(
    BuildContext context,
    WidgetRef ref,
    StatutVehicule statut,
    String message,
  ) async {
    try {
      await ref.read(vehiculeDaoProvider).changerStatut(vehicule.id, statut);
      if (!context.mounted) return;
      rechargerVehicules(ref);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const Key('vehicules-statut-change'),
          content: Text(message),
        ),
      );
    } on RefusVehicule catch (refus) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const Key('vehicules-statut-refus'),
          content: Text(refus.message),
        ),
      );
    }
  }

  /// « Archiver » — le geste que la vue propose, et qui n'est **pas** une
  /// suppression.
  ///
  /// Le véhicule passe `hors_service` : il quitte le parc louable et **reste
  /// consultable**, ce que la vue écrit elle-même. Supprimer la ligne rendrait
  /// illisible tout contrat qui la désigne. Le refus du DAO — véhicule engagé —
  /// est affiché tel quel.
  Future<void> _archiver(BuildContext context, WidgetRef ref) async {
    // La modale PARTAGÉE `modale-archivage` (vue l.835-843), avec sa question
    // propre : « Voulez-vous archiver le véhicule :element ? »
    // (`archiver_vehicule`). Son rappel — « L'élément part aux archives et reste
    // restaurable — rien n'est effacé » — est vrai ici : le véhicule passe
    // `hors_service` et reste consultable.
    //
    // ÉCART — la vue calcule AVANT d'ouvrir la modale les motifs de blocage
    // (`$verrousArchivage`, `$archivageBloque`). Ici le refus du DAO
    // (véhicule engagé) est affiché APRÈS la confirmation, tel quel : le DAO
    // est l'auteur de la règle, et la dupliquer avant la modale ferait deux
    // listes qui divergeront (RG-08 intouchée, 09/10/2026).
    final confirme = await ouvrirArchivageAchats(
      context,
      message: 'Voulez-vous archiver le véhicule ${vehicule.immatriculation} ?',
    );

    if (confirme != true || !context.mounted) return;

    try {
      await ref.read(vehiculeDaoProvider).archiverVehicule(vehicule.id);
      if (!context.mounted) return;
      rechargerVehicules(ref);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const Key('vehicules-archive'),
          content: Text(
            'Véhicule ${vehicule.immatriculation} retiré du parc actif — il '
            'reste consultable.',
          ),
        ),
      );
    } on RefusVehicule catch (refus) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const Key('vehicules-archivage-refuse'),
          content: Text(refus.message),
        ),
      );
    }
  }
}

/// `Y-m-d` -> `d/m/Y`, comme `->format('d/m/Y')` de la vue ; une date illisible
/// reste « — », jamais une date inventée.
String dateFrVehicules(String? iso) {
  final d = iso == null ? null : DateTime.tryParse(iso);
  return d == null ? CarteIndicateurRestaurant.absent : formaterDate(d);
}

/// L'état vide des tableaux de M8 — `py-14 text-center text-slate-400
/// text-[13px]`. Ce n'est PAS l'état vide du moteur CRUD : un message par
/// onglet, sans illustration.
///
/// [message] est le texte de la vue, AU MOT, dans son propre `Text` ; [precision]
/// est ce que ce client ajoute dessous (voir l'appelant), dans un second `Text` :
/// concaténés, ils feraient un message qui n'est plus celui de la vue.
class EtatVideVehicules extends StatelessWidget {
  const EtatVideVehicules({Key? cle, required this.message, this.precision})
    : super(key: cle);

  final String message;
  final String? precision;

  @override
  Widget build(BuildContext context) {
    final style = TextesRestaurant.corps.copyWith(color: Ardoise.c400);

    return Padding(
      // `py-14` — 56 px.
      padding: const EdgeInsets.symmetric(vertical: AppSpacingLarge.p14),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center, style: style),
            if (precision != null)
              Text(precision!, textAlign: TextAlign.center, style: style),
          ],
        ),
      ),
    );
  }
}

/// L'état vide dans SA CARTE — `bg-white rounded-xl border border-slate-200
/// py-14 text-center` (vue l.241 et l.326) : quand il n'y a aucune ligne, la
/// vue rend cette carte à la place du tableau.
class CarteVideVehicules extends StatelessWidget {
  const CarteVideVehicules({
    required Key cle,
    required this.message,
    this.precision,
  }) : super(key: cle);

  final String message;
  final String? precision;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.neutre0,
        borderRadius: BorderRadius.circular(AppRadius.roundedXl),
        border: Border.all(color: Ardoise.c200),
      ),
      child: EtatVideVehicules(message: message, precision: precision),
    );
  }
}

String? _montantPeriode(String tarif, int? jours) {
  if (jours == null || jours <= 0) return null;
  return sommeDecimales(List<String>.filled(jours, tarif));
}
