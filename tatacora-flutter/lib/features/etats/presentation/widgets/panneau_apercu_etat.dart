import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../restaurant/presentation/widgets/coquille_restaurant.dart';
import '../../../restaurant/presentation/widgets/tableau_restaurant.dart';
import '../../domain/apercu_etat.dart';
import '../../domain/entities/etat_catalogue.dart';
import '../providers_etats.dart';
import 'textes_etats.dart';

/// Le panneau de droite — `pwa/etats/studio.blade.php` l.117-204.
///
/// Deux états : l'**accueil** tant qu'aucun état n'est choisi (l.119-131), et
/// l'**aperçu** ensuite (l.132-203) — un en-tête (titre, période, module
/// source, nombre de lignes, indicateurs) surmontant le tableau calculé.
///
/// ## L'aperçu est CALCULÉ sur ce poste (10/10/2026)
///
/// Jusqu'au 10/10/2026 le contenu de l'aperçu était refusé : `calculer()` est
/// le moteur d'états du serveur, et ce poste n'en avait aucun. Il en a un
/// désormais (`apercus_etats.dart`) pour les états dont TOUTES les sources sont
/// détenues et écrites ici. Pour les autres, l'état reste listé et l'aperçu
/// rend la raison vraie et datée du registre — jamais un tableau vide, qui se
/// lirait « rien à signaler ».
///
/// L'ancienne raison (« le moteur d'états vit au serveur ») est CADUQUE pour ce
/// poste ; elle reste vraie du document remis (en-tête normalisée, archivage
/// EF-M14-06), que ce poste ne produit pas (PA-192, non tranché).
///
/// ## Et rien d'autre n'est affiché
///
/// Pas de bouton d'export ni d'impression : la vue n'en offre pas (directive
/// du Product Owner du 31/08/2026) et le PDF A4 est l'arbitrage PA-192. Pas de
/// panneau de refus non plus : la vue l'a retiré. L'encadré « Sur ce poste »
/// qui disait ce que l'aperçu ne mesure pas est retiré de l'écran le
/// 14/10/2026 (directive du PO) ; les « — » restent, jamais un zéro.
class PanneauApercuEtat extends ConsumerWidget {
  const PanneauApercuEtat({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final code = ref.watch(etatSelectionneProvider);
    final etats = ref.watch(catalogueEtatsProvider).value;

    // La sélection ne vaut que si l'état est RÉELLEMENT dans le catalogue : un
    // code qui n'y est pas ne contourne pas le filtrage RBAC.
    EtatCatalogue? choisi;
    for (final e in etats ?? const <EtatCatalogue>[]) {
      if (e.code == code) choisi = e;
    }

    if (choisi == null) return _Accueil(nombre: etats?.length);
    return _Apercu(etat: choisi);
  }
}

/// Le décompte de l'accueil — `pwa.etats.accueil_detail`, AU MOT.
///
/// [nombre] est `null` tant que le catalogue n'est pas lu : le décompte est
/// alors « — » et non « 0 ». Un « 0 état(s) sont éditables » affirmerait que
/// le rôle n'a droit à rien, ce que personne n'a constaté (Article 7).
String decompteAccueilEtats(int? nombre) =>
    '${nombre ?? '—'} état(s) sont éditables avec vos droits.';

/// La phrase d'une lecture qui échoue : FERMÉE. L'exception brute (`Bad state:
/// …`) nomme des types internes qu'un exploitant ne peut pas lire, et dit
/// moins que cette phrase : rien n'est affiché plutôt qu'un chiffre douteux.
const String messageLectureEchouee =
    'La lecture des modules sources a échoué : l\'état n\'a pas pu être '
    'calculé. Aucun chiffre n\'est affiché plutôt qu\'un chiffre douteux.';

/// L'écran d'accueil de l'aperçu — `studio.blade.php` l.119-131.
///
/// `h-full flex items-center justify-center p-8` dans une zone
/// `overflow-auto` : le bloc est CENTRÉ dans la hauteur disponible, et la zone
/// défile s'il est plus haut qu'elle.
class _Accueil extends StatelessWidget {
  const _Accueil({required this.nombre});

  final int? nombre;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, contrainte) => SingleChildScrollView(
        key: const Key('etats-accueil'),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: contrainte.maxHeight),
          child: Center(
            child: Padding(
              // `p-8` (l.123).
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: ConstrainedBox(
                // `max-w-lg text-center` (l.124).
                constraints: const BoxConstraints(maxWidth: Largeurs.maxLg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // `mb-4`, stroke `#CBD5E1` = slate-300 (l.125).
                    const Icon(
                      Icons.description_outlined,
                      size: AppLayout.iconeAccueilEtats,
                      color: Ardoise.c300,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    // `pwa.etats.accueil_titre` (l.126), au mot.
                    Text(
                      'Choisissez un état dans le catalogue',
                      textAlign: TextAlign.center,
                      style: TextesEtats.accrocheAccueil,
                    ),
                    // `mt-2` (l.127).
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      decompteAccueilEtats(nombre),
                      key: const Key('etats-accueil-decompte'),
                      textAlign: TextAlign.center,
                      style: TextesRestaurant.corps.copyWith(
                        color: Ardoise.c500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// L'en-tête d'aperçu et le tableau — `studio.blade.php` l.133-203.
class _Apercu extends ConsumerWidget {
  const _Apercu({required this.etat});

  final EtatCatalogue etat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resultat = ref.watch(apercuEtatProvider(etat.code));

    final apercu = resultat.value is ApercuRecu
        ? (resultat.value! as ApercuRecu).apercu
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _EnTete(
          titre: apercu?.titre ?? etat.libelle,
          // Sans aperçu calculé, la période et le décompte n'ont aucune
          // source : « — » et non « 0 » (Article 7).
          periode: apercu?.periode ?? tiretApercu,
          moduleSource: apercu?.moduleSource ?? etat.module,
          lignes: apercu == null ? tiretApercu : '${apercu.nombreLignes}',
          indicateurs: apercu?.indicateurs ?? const [],
        ),
        Expanded(
          child: resultat.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ListView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              children: [
                EncadreRestaurant(
                  cle: const Key('etats-apercu-erreur'),
                  ton: TonEncadre.ambre,
                  titre: 'Aperçu indisponible',
                  texte: messageLectureEchouee,
                ),
              ],
            ),
            data: (r) => switch (r) {
              ApercuRecu(:final apercu) => _Corps(apercu: apercu),
              ApercuRefuse(:final motif) => ListView(
                padding: const EdgeInsets.all(AppSpacing.xl),
                children: [
                  EncadreRestaurant(
                    cle: const Key('etats-apercu-refuse'),
                    ton: TonEncadre.ambre,
                    titre: 'Aperçu indisponible',
                    texte: motif,
                  ),
                ],
              ),
            },
          ),
        ),
      ],
    );
  }
}

/// `px-5 py-3.5 border-b border-slate-200 bg-white` (l.136) : le titre, la
/// sous-ligne « période · module source · N ligne(s) » et les indicateurs.
class _EnTete extends StatelessWidget {
  const _EnTete({
    required this.titre,
    required this.periode,
    required this.moduleSource,
    required this.lignes,
    required this.indicateurs,
  });

  final String titre;
  final String periode;
  final String moduleSource;
  final String lignes;
  final List<IndicateurApercu> indicateurs;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.mdPlus,
        vertical: AppSpacing.smPlus,
      ),
      decoration: const BoxDecoration(
        color: AppColors.neutre0,
        border: Border(bottom: BorderSide(color: Ardoise.c200)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            titre,
            key: const Key('etats-apercu-titre'),
            style: TextesEtats.titreBarre,
          ),
          const SizedBox(height: AppSpacing.demi),
          // `{{ $periodeEtat }} · module source M6 · N ligne(s)` (l.140-144) :
          // les puces sont `text-slate-300`.
          Text.rich(
            key: const Key('etats-apercu-sous-ligne'),
            TextSpan(
              style: TextesEtats.etiquetteBarre,
              children: [
                TextSpan(text: periode),
                const TextSpan(
                  text: ' · ',
                  style: TextesEtats.separateurApercu,
                ),
                TextSpan(text: 'module source $moduleSource'),
                const TextSpan(
                  text: ' · ',
                  style: TextesEtats.separateurApercu,
                ),
                TextSpan(text: '$lignes ligne(s)'),
              ],
            ),
          ),
          if (indicateurs.isNotEmpty) ...[
            // `mt-3` (l.147) ; `flex flex-wrap gap-2`.
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              key: const Key('etats-apercu-indicateurs'),
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final i in indicateurs) _Indicateur(indicateur: i),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// `px-3 py-1.5 rounded-lg bg-slate-50 border border-slate-200` (l.150).
class _Indicateur extends StatelessWidget {
  const _Indicateur({required this.indicateur});

  final IndicateurApercu indicateur;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: Key('etats-indicateur-${indicateur.libelle}'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: Ardoise.c50,
        borderRadius: BorderRadius.circular(AppRadius.roundedLg),
        border: Border.all(color: Ardoise.c200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            indicateur.libelle.toUpperCase(),
            style: TextesEtats.indicateurLibelle,
          ),
          Text(
            // Une valeur vide est « sans valeur », jamais zéro (Article 7).
            indicateur.valeur.isEmpty ? tiretApercu : indicateur.valeur,
            key: Key('etats-indicateur-valeur-${indicateur.libelle}'),
            style: TextesEtats.indicateurValeur,
          ),
        ],
      ),
    );
  }
}

/// Le gabarit du tableau d'aperçu — `<thead class="bg-[var(--navy)]">`, `<th
/// class="px-3 py-2.5 ...">` (l.169-172) et `<td class="px-3 py-1.5
/// border-b border-slate-50">` (l.182).
const GabaritTableau _gabaritApercu = GabaritTableau(
  enteteFond: AppColors.navy,
  entete: TextesEtats.enteteApercu,
  cellule: EdgeInsets.symmetric(
    horizontal: AppSpacing.sm,
    vertical: AppSpacing.xxs,
  ),
  enteteCellule: EdgeInsets.symmetric(
    horizontal: AppSpacing.sm,
    vertical: AppSpacing.xsPlus,
  ),
  enBas: true,
);

/// Ce qui occupe `#zone-apercu` : les mentions, puis le tableau — ou la phrase
/// de l'état vide.
class _Corps extends ConsumerWidget {
  const _Corps({required this.apercu});

  final ApercuEtat apercu;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      children: [
        // L'encadré ambre « Sur ce poste » (`_Mentions`, ajout à la vue) est
        // RETIRÉ de l'écran le 14/10/2026 (directive absolue du PO : aucune
        // explication longue en bloc). Les « — » restent ; les mentions
        // vivent toujours dans `ApercuEtat.mentions`.
        if (apercu.estVide)
          const Padding(
            // `p-10 text-center text-[13px] text-slate-400` (l.166), phrase de
            // `pwa.etats.aucune_ligne`.
            padding: EdgeInsets.all(AppSpacingLarge.p10),
            child: Text(
              'Aucune ligne sur cette période.',
              key: Key('etats-apercu-vide'),
              textAlign: TextAlign.center,
              style: TextesEtats.videApercu,
            ),
          )
        else
          TableauRestaurant(
            colonnes: [for (final e in apercu.entetes) ColonneRestaurant(e)],
            gabarit: _gabaritApercu,
            // `table w-full` : le tableau remplit son cadre et partage le
            // surplus au prorata du contenu, comme l'algorithme `auto`.
            pleineLargeur: true,
            repartitionProportionnelle: true,
            decorationsLignes: [
              for (var i = 0; i < apercu.lignes.length; i++)
                BoxDecoration(
                  // `$index % 2 ? 'bg-slate-50/40' : ''` (l.178).
                  color: i.isOdd ? TextesEtats.fondRayure : null,
                  border: const Border(bottom: BorderSide(color: Ardoise.c50)),
                ),
            ],
            lignes: [
              for (var l = 0; l < apercu.lignes.length; l++)
                [
                  for (var c = 0; c < apercu.lignes[l].length; c++)
                    Text(
                      // `$cellule !== '' ? $cellule : MontantFcfa::TIRET`
                      // (l.183) : une cellule vide est « — ».
                      apercu.lignes[l][c].isEmpty
                          ? tiretApercu
                          : apercu.lignes[l][c],
                      key: Key('etats-cellule-$l-$c'),
                      style: TextesEtats.celluleApercu,
                    ),
                ],
            ],
          ),
      ],
    );
  }
}
