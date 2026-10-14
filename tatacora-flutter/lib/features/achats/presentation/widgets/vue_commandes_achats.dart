// Vue Blade maîtresse (PA-183) : pwa/achats/achats.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/format/formats.dart';
import '../../../../core/impression/visas.dart';
import '../../../../core/rbac/garde_acces.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../shared_widgets/tableau_tatacora.dart';
import '../../../../shared_widgets/modale_export.dart';
import 'barre_outils_achats.dart';
import '../../../restaurant/presentation/widgets/corps_carte_commun.dart'
    show styleContenuCarte;
import '../../../restaurant/presentation/widgets/tableau_restaurant.dart'
    show ColonneRestaurant;
import '../../data/achats_api.dart';
import '../../domain/entities/commande_achat.dart';
import '../../impression/etat_liste_achats.dart';
import '../providers_achats.dart';
import 'composants_crud_achats.dart';
import 'vue_fournisseurs.dart' show motifInjoignable;

/// L'onglet **« Commandes d'achat »** — `pwa/achats/achats.blade.php`
/// l.294-370.
///
/// Même gabarit que les fournisseurs, avec ses quatre colonnes : Fournisseur,
/// Date de commande, Montant estimé (à droite), Statut — puis « Actions », qui
/// clôt TOUJOURS le tableau (l.309-310).
///
/// ## Une commande ne se crée ni ne se règle ici
///
/// ÉCART DÉLIBÉRÉ — il est celui de la vue elle-même (l.153-166 et l.337-343),
/// reproduit tel quel : « Ajouter commande d'achat » et « Voir le détail »
/// MÈNENT À l'Approvisionnement, qui porte la création, la réception et le
/// règlement. `commandes_achat` n'a aucune colonne de montant qu'un chemin du
/// dépôt écrive : le montant estimé se SOMME depuis les lignes, et les lignes
/// n'existent que là où la commande se construit. Le formulaire à quatre champs
/// de l'ancien prototype (fournisseur en texte libre, date, montant, statut)
/// échouerait à tous les coups : le serveur exige au moins une ligne, refuse le
/// montant et refuse trois des cinq statuts.
///
/// ## « Supprimer » n'existe pas sur cet onglet
///
/// La vue ne l'y pose pas (l.183) : une commande d'achat ne s'archive pas.
/// `commandes_achat.statut` n'admet aucune valeur « annulée » (lacune de schéma
/// relue dans la vue, l.380-383, 09/10/2026).
class VueCommandesAchats extends ConsumerStatefulWidget {
  const VueCommandesAchats({super.key});

  @override
  ConsumerState<VueCommandesAchats> createState() => _VueCommandesAchatsState();
}

class _VueCommandesAchatsState extends ConsumerState<VueCommandesAchats> {
  final _recherche = TextEditingController();
  final Set<String> _selection = {};

  @override
  void initState() {
    super.initState();
    _recherche.text = ref.read(rechercheCommandesAchatsProvider);
  }

  @override
  void dispose() {
    _recherche.dispose();
    super.dispose();
  }

  void _revenirPage1() {
    ref.read(pageCommandesAchatsProvider.notifier).definir(1);
    _selection.clear();
  }

  void _actualiser() {
    setState(_selection.clear);
    ref.invalidate(commandesAchatsProvider(null));
  }

  /// Vers l'Approvisionnement : le geste que la vue pose en lien
  /// (`route('pwa.achats.approvisionnement')`, l.162 et l.345).
  void _versApprovisionnement() => context.go('/approvisionnement');

  List<CommandeAchat> _visees(PageAchats<CommandeAchat> page) {
    if (_selection.isEmpty) return page.elements;
    return [
      for (final c in page.elements)
        if (_selection.contains(c.id)) c,
    ];
  }

  ListeAchats? _liste(PageAchats<CommandeAchat> page) {
    final lignes = _visees(page);
    if (lignes.isEmpty) return null;

    final statut = ref.read(statutCommandesAchatsProvider);
    final terme = ref.read(rechercheCommandesAchatsProvider).trim();

    return ListeAchats(
      titre: 'Bons de commande fournisseurs',
      visas: Visas.achats,
      portee: Portee(
        filtre: [
          // Le libellé que l'utilisateur A VU au filtre (PA-119).
          statut == null ? 'Tous les statuts' : 'Statut : ${statut.libelle}',
          if (terme.isNotEmpty) 'recherche « $terme »',
          if (_selection.isNotEmpty) 'sélection de ${lignes.length} ligne(s)',
        ].join(' — '),
        lignesRapportees: lignes.length,
        totalServeur: _selection.isEmpty ? page.total : lignes.length,
      ),
      entetes: const [
        'Fournisseur',
        'Date de commande',
        'Montant estimé',
        'Statut',
      ],
      colonnesNumeriques: const {2},
      lignes: [
        for (final c in lignes)
          [
            c.fournisseurRaisonSociale,
            c.dateCommande,
            // Le montant du serveur, tel quel — nombre brut : un tableur ne
            // sait pas additionner « 56 000 FCFA ».
            c.montantTotal,
            c.libelleStatut,
          ],
      ],
    );
  }

  Future<void> _exporter(PageAchats<CommandeAchat>? page, String? motif) async {
    final messager = ScaffoldMessenger.of(context);

    if (page == null) {
      messager.showSnackBar(
        SnackBar(
          key: const Key('achats-export-indisponible'),
          content: Text(motif ?? ''),
        ),
      );
      return;
    }

    final liste = _liste(page);
    if (liste == null) {
      messager.showSnackBar(
        const SnackBar(
          key: Key('export-refuse'),
          content: Text(messageExportVide),
        ),
      );
      return;
    }

    final format = await choisirFormatExport(
      context,
      titre: "Exporter — Commandes d'achat",
      sousTitre: _selection.isEmpty
          ? 'Le document portera exactement les ${liste.lignes.length} '
                'ligne(s) affichées, filtres compris.'
          : 'Le document portera exactement les ${liste.lignes.length} '
                'ligne(s) sélectionnées.',
    );
    if (format == null || !mounted) return;

    await enregistrerListeAchats(context, ref, liste, format);
  }

  @override
  Widget build(BuildContext context) {
    final resultat = ref.watch(commandesAchatsProvider(null));
    final peutEcrire = ref
        .watch(droitsProvider)
        .peutEcrire(ModuleTatacora.m7Achats);

    final (
      PageAchats<CommandeAchat>? page,
      String? motif,
      bool charge,
    ) = switch (resultat) {
      AsyncData(:final value) => switch (value) {
        AchatsRecu(:final donnees) => (donnees, null, true),
        AchatsRefuse(:final motif) => (null, motif, true),
        AchatsInjoignable() => (null, motifInjoignable, true),
      },
      AsyncError(:final error) => (null, '$error', true),
      _ => (null, null, false),
    };

    final lignes = page?.elements ?? const <CommandeAchat>[];
    final affichees = {for (final c in lignes) c.id};
    final selection = _selection.intersection(affichees);
    final numeroPage = ref.watch(pageCommandesAchatsProvider);

    final Widget vide;
    if (!charge) {
      vide = const Padding(
        key: Key('commandes-achats-chargement'),
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (page == null) {
      vide = CorpsIndisponibleAchats(
        cle: const Key('commandes-achats-indisponible'),
        motif: motif ?? '',
      );
    } else {
      vide = const EtatVideTableauAchats();
    }

    final decompte = decompteAchats(
      disponible: page != null,
      total: page?.total ?? 0,
      numeroPage: numeroPage,
      affiches: lignes.length,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BarreOutilsCrudAchats(
          cle: const Key('outils-commandes-achats'),
          prefixeCle: 'commandes',
          placeholder: 'Rechercher une commande (fournisseur)...',
          controleurRecherche: _recherche,
          onRecherche: (v) {
            ref.read(rechercheCommandesAchatsProvider.notifier).definir(v);
            setState(_revenirPage1);
          },
          filtre: FiltreListeAchats<StatutCommande?>(
            cle: const Key('filtre-commandes-achats'),
            valeur: ref.watch(statutCommandesAchatsProvider),
            items: [
              const DropdownMenuItem<StatutCommande?>(
                child: Text('Tous les statuts'),
              ),
              // Les CINQ statuts, y compris les trois qu'on ne peut pas saisir :
              // on filtre un état constaté, on ne le pose pas.
              for (final s in StatutCommande.values)
                DropdownMenuItem<StatutCommande?>(
                  value: s,
                  child: Text(s.libelle),
                ),
            ],
            onChanged: (s) {
              ref.read(statutCommandesAchatsProvider.notifier).definir(s);
              setState(_revenirPage1);
            },
          ),
          onActualiser: _actualiser,
          onExporter: () => _exporter(page, motif),
          libelleAjout: "Ajouter commande d'achat",
          onAjout: peutEcrire ? _versApprovisionnement : null,
        ),
        if (selection.isNotEmpty)
          BarreSelectionAchats(
            nombre: selection.length,
            // Pas de « Supprimer » : une commande d'achat ne s'archive pas.
            onSupprimer: null,
            onExporter: () => _exporter(page, motif),
            onEffacer: () => setState(_selection.clear),
          ),
        CadreTableauAchats(
          colonnes: [
            ColonneRestaurant(
              '',
              enteteSpecial: CaseSelectionAchats(
                cle: const Key('achats-commandes-tout'),
                valeur:
                    lignes.isNotEmpty &&
                    lignes.every((c) => selection.contains(c.id)),
                etiquette: 'Tout sélectionner',
                surMarine: true,
                onChanged: (coche) => setState(() {
                  _selection.clear();
                  if (coche) _selection.addAll(affichees);
                }),
              ),
            ),
            // Les colonnes de la vue, dans son ordre et à ses mots (l.305-310).
            const ColonneRestaurant('Fournisseur'),
            const ColonneRestaurant('Date de commande'),
            const ColonneRestaurant('Montant estimé', aDroite: true),
            const ColonneRestaurant('Statut'),
            const ColonneRestaurant('Actions', aDroite: true),
          ],
          vide: vide,
          lignes: [
            for (final c in lignes)
              [
                CaseSelectionAchats(
                  cle: Key('commande-case-${c.id}'),
                  valeur: selection.contains(c.id),
                  etiquette: 'Sélectionner cette ligne',
                  onChanged: (coche) => setState(() {
                    coche ? _selection.add(c.id) : _selection.remove(c.id);
                  }),
                ),
                Text(
                  // Sans raison sociale jointe : « — », comme la vue (l.320).
                  c.fournisseurRaisonSociale.isEmpty
                      ? '—'
                      : c.fournisseurRaisonSociale,
                  key: Key('commande-fournisseur-${c.id}'),
                  style: styleContenuCarte(
                    TaillesContenu.t13,
                    poids: FontWeight.w500,
                    couleur: Ardoise.c800,
                  ),
                ),
                Text(
                  _date(c.dateCommande),
                  style: styleContenuCarte(
                    TaillesContenu.t13,
                    couleur: Ardoise.c600,
                  ),
                ),
                // CALCULÉ depuis les lignes par le serveur, jamais saisi.
                // `null` n'est pas zéro : un montant illisible rend « — ».
                Text(
                  formaterMontantDecimal(c.montantTotal, suffixe: 'FCFA') ??
                      '—',
                  key: Key('commande-montant-${c.id}'),
                  style: styleContenuCarte(
                    TaillesContenu.t13,
                    poids: FontWeight.w600,
                    couleur: AppColors.anthracite,
                  ),
                ),
                _Statut(commande: c),
                BoutonLigneAchats(
                  cle: Key('commande-detail-${c.id}'),
                  libelle: 'Voir le détail',
                  onTap: _versApprovisionnement,
                ),
              ],
          ],
          pied: PiedTableauAchats(
            debut: decompte.debut,
            fin: decompte.fin,
            total: decompte.total,
            page: numeroPage,
            derniere: page?.derniere ?? 1,
            onPage: (p) {
              ref.read(pageCommandesAchatsProvider.notifier).definir(p);
              setState(_selection.clear);
            },
          ),
        ),
      ],
    );
  }

  /// `d/m/Y` de la vue (l.321). Une date illisible reste telle que le serveur
  /// l'a rendue : la reformater en inventerait une.
  static String _date(String brut) {
    final d = DateTime.tryParse(brut);
    return d == null ? brut : formaterDate(d);
  }
}

/// La pastille de statut, aux couleurs de `Achats::STATUTS` (l.328-336).
class _Statut extends StatelessWidget {
  const _Statut({required this.commande});

  final CommandeAchat commande;

  @override
  Widget build(BuildContext context) {
    final (couleur, fond) = switch (commande.statut) {
      StatutCommande.envoyee => (
        AppColors.infoBleuTexte,
        AppColors.badgeBleuFond,
      ),
      StatutCommande.receptionneePartiellement => (
        AppColors.gold,
        AppColors.reserveGoldFond,
      ),
      StatutCommande.receptionnee => (
        AppColors.succes,
        AppColors.badgeVertFond,
      ),
      // `brouillon` et `cloturee` sont gris ; un statut INCONNU l'est aussi, et
      // son code brut s'affiche — jamais un libellé de remplacement, qui
      // donnerait une couleur à un état qu'on ne sait pas lire.
      _ => (JetonsCssMaitre.neutre600, AppColors.badgeGrisFond),
    };

    return PastilleStatut(
      commande.libelleStatut,
      key: Key('commande-statut-${commande.id}'),
      fond: fond,
      texte: couleur,
    );
  }
}
