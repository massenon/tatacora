import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/format/formats.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../shared_widgets/bouton_standard.dart';
import '../../../transverse/presentation/widgets/briques_transverses.dart';
import '../../domain/montant_comptable.dart';
import '../../domain/tafire_notes.dart';
import '../providers_etats_financiers.dart';
import 'modales_hub_comptabilite.dart';
import 'onglets_etats_financiers.dart';

/// Les trois pages séparées de la vue du hub — « Tableau des flux de
/// trésorerie », « Notes annexes » et « États financiers » — rendues SUR CE
/// POSTE dans une fenêtre, depuis les mêmes écritures que le bilan et le compte
/// de résultat (pièces du poste, ou écritures reçues du serveur). Aucun
/// serveur n'est requis.
abstract final class TextesEtatsComptables {
  static const String titreFlux = 'Tableau des Flux de Trésorerie';
  static const String sousTitreFlux =
      'TAFIRE — Tableau Financier des Ressources et Emplois';
  static const String titreNotes = 'Notes Annexes';
  static const String sousTitreNotes =
      "Compléments d'information au Bilan et au Compte de Résultat";
  static const String titreEtats = 'États Financiers';
  static const String sousTitreEtats =
      'Vue consolidée — Bilan, Résultat, Flux, Notes Annexes';
  static const String ongletBilan = 'Bilan';
  static const String ongletResultat = 'Compte de Résultat';
  static const String ongletFlux = 'Flux de Trésorerie';
  static const String ongletNotes = 'Notes Annexes';
  static const String fermer = 'Fermer';
  static const String aucunExercice =
      "Aucun exercice comptable n'est sélectionné";
  static const String ressources = 'RESSOURCES';
  static const String emplois = 'EMPLOIS';
  static const String cafg = "Capacité d'Autofinancement Globale (CAFG)";
  static const String augmentationCapital = 'Augmentation de capital';
  static const String totalRessources = 'TOTAL RESSOURCES';
  static const String acquisitions = "Acquisitions d'immobilisations";
  static const String totalEmplois = 'TOTAL EMPLOIS';
  static const String titreBfr =
      'Variation du Besoin en Fonds de Roulement (BFR)';
  static const String variationStocks = 'Variation des stocks';
  static const String variationCreances = '+ Variation des créances';
  static const String variationDettes = '− Variation des dettes';
  static const String variationBfr = '= VARIATION DU BFR';
  static const String titreTresorerie = 'Variation de trésorerie nette';
  static const String calculee =
      'Total ressources − Total emplois − Variation BFR';
  static const String reelle =
      'Variation réelle des comptes de trésorerie (521/522/571/572/573)';
  static const String ecart = 'Écart';
  static const String ouvertureVariation =
      "Ouverture · variation de l'exercice";
  static String coherent(String montant) =>
      'Contrôle de cohérence réussi — variation calculée = variation réelle '
      'de trésorerie = $montant';
  static const String incoherent =
      'Incohérence détectée — écart entre variation calculée et réelle, '
      'signale une erreur de méthode (mouvement mal classé), pas une '
      '"différence normale"';
  static const String illisible = "Les écritures n'ont pas pu être lues.";
  static const String etatDisponible = 'Disponible';
  static const String etatIndisponible = 'Indisponible';
  static const String etatNonSaisie = 'Non saisie';
}

String _montant(int centimes) =>
    formaterMontantDecimal(
      chaineDepuisCentimes(centimes.abs()),
      suffixe: 'FCFA',
    ) ??
    '—';

String _montantSigne(int centimes) =>
    '${centimes < 0 ? '-' : ''}${_montant(centimes)}';

/// Ouvre la fenêtre du TAFIRE de l'exercice [annee].
Future<void> ouvrirFluxTresorerie(BuildContext context, int? annee) =>
    showDialog<void>(
      context: context,
      builder: (_) => _CadreEtats(
        cle: const Key('modale-flux-tresorerie'),
        titre: TextesEtatsComptables.titreFlux,
        sousTitre: TextesEtatsComptables.sousTitreFlux,
        annee: annee,
        contenu: (a) => ContenuFlux(annee: a),
      ),
    );

/// Ouvre la fenêtre des notes annexes de l'exercice [annee].
Future<void> ouvrirNotesAnnexes(BuildContext context, int? annee) =>
    showDialog<void>(
      context: context,
      builder: (_) => _CadreEtats(
        cle: const Key('modale-notes-annexes'),
        titre: TextesEtatsComptables.titreNotes,
        sousTitre: TextesEtatsComptables.sousTitreNotes,
        annee: annee,
        contenu: (a) => ContenuNotes(annee: a),
      ),
    );

/// Ouvre la fenêtre des quatre états financiers de l'exercice [annee].
Future<void> ouvrirEtatsFinanciers(BuildContext context, int? annee) =>
    showDialog<void>(
      context: context,
      builder: (_) => _CadreEtats(
        cle: const Key('modale-etats-financiers'),
        titre: TextesEtatsComptables.titreEtats,
        sousTitre: TextesEtatsComptables.sousTitreEtats,
        annee: annee,
        contenu: (a) => _QuatreEtats(annee: a),
      ),
    );

class _CadreEtats extends StatelessWidget {
  const _CadreEtats({
    required this.cle,
    required this.titre,
    required this.sousTitre,
    required this.annee,
    required this.contenu,
  });

  final Key cle;
  final String titre;
  final String sousTitre;
  final int? annee;
  final Widget Function(int annee) contenu;

  @override
  Widget build(BuildContext context) => CadreModaleComptabilite(
    cle: cle,
    largeur: AppLayout.modaleEtatsComptables,
    titre: titre,
    corps: [
      Text(
        sousTitre,
        style: styleTransverse(Tailles.t13, couleur: Ardoise.c500),
      ),
      const SizedBox(height: AppSpacing.sm),
      if (annee == null)
        Text(
          TextesEtatsComptables.aucunExercice,
          key: const Key('modale-etats-aucun-exercice'),
          style: styleTransverse(Tailles.t13, couleur: Ardoise.c500),
        )
      else ...[
        Text(
          'Exercice $annee',
          style: styleTransverse(
            Tailles.t13,
            poids: FontWeight.w600,
            couleur: AppColors.navy,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        contenu(annee!),
      ],
    ],
    pied: [
      BoutonStandard(
        key: const Key('modale-etats-fermer'),
        libelle: TextesEtatsComptables.fermer,
        variante: VarianteBouton.fantome,
        onPressed: () => Navigator.of(context).pop(),
      ),
    ],
  );
}

class _QuatreEtats extends StatefulWidget {
  const _QuatreEtats({required this.annee});

  final int annee;

  @override
  State<_QuatreEtats> createState() => _QuatreEtatsState();
}

class _QuatreEtatsState extends State<_QuatreEtats> {
  String _onglet = 'bilan';

  @override
  Widget build(BuildContext context) {
    const onglets = [
      ('bilan', TextesEtatsComptables.ongletBilan),
      ('resultat', TextesEtatsComptables.ongletResultat),
      ('flux', TextesEtatsComptables.ongletFlux),
      ('notes', TextesEtatsComptables.ongletNotes),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final (cle, libelle) in onglets)
              OngletTransverse(
                cle: Key('etats-onglet-$cle'),
                libelle: libelle,
                actif: cle == _onglet,
                onChoix: () => setState(() => _onglet = cle),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        switch (_onglet) {
          'resultat' => OngletResultat(annee: widget.annee),
          'flux' => ContenuFlux(annee: widget.annee),
          'notes' => ContenuNotes(annee: widget.annee),
          _ => OngletBilan(annee: widget.annee),
        },
      ],
    );
  }
}

class _Ligne extends StatelessWidget {
  const _Ligne(
    this.libelle,
    this.montant, {
    this.gras = false,
    this.cle,
    this.couleur,
  });

  final String libelle;
  final String montant;
  final bool gras;
  final Key? cle;
  final Color? couleur;

  @override
  Widget build(BuildContext context) {
    final style = styleTransverse(
      Tailles.t14,
      poids: gras ? FontWeight.bold : FontWeight.normal,
      couleur: couleur ?? (gras ? Ardoise.c800 : Ardoise.c600),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.unit),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(libelle, style: style)),
          const SizedBox(width: AppSpacing.sm),
          Text(
            montant,
            key: cle,
            style: style.copyWith(fontFamily: AppTextStyles.policeMonospace),
          ),
        ],
      ),
    );
  }
}

class _Carte extends StatelessWidget {
  const _Carte({required this.titre, required this.enfants});

  final String titre;
  final List<Widget> enfants;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: CarteTransverse(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            titre,
            style: styleTransverse(
              Tailles.t15,
              poids: FontWeight.bold,
              couleur: AppColors.navy,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          ...enfants,
        ],
      ),
    ),
  );
}

/// Le contenu du TAFIRE (`TafireService`).
class ContenuFlux extends ConsumerWidget {
  const ContenuFlux({required this.annee, super.key});

  final int annee;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lu = ref.watch(donneesEtatsFinanciersProvider);
    if (lu.hasError) {
      return Text(
        TextesEtatsComptables.illisible,
        style: styleTransverse(Tailles.t13, couleur: AppColors.erreur),
      );
    }
    final d = lu.value;
    if (d == null) return const SizedBox.shrink();
    final t = tafireDe(annee, d);
    final bande = t.coherent
        ? (PaletteMaitre.emeraude50, PaletteMaitre.emeraude700)
        : (PaletteMaitre.rouge50, PaletteMaitre.rouge900);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CarteTransverse(
          key: const Key('flux-coherence'),
          fond: bande.$1,
          bordure: bande.$1,
          padding: const EdgeInsets.all(AppSpacing.smPlus),
          child: Text(
            t.coherent
                ? TextesEtatsComptables.coherent(
                    _montantSigne(t.variationCalculeeCentimes),
                  )
                : TextesEtatsComptables.incoherent,
            style: styleTransverse(
              Tailles.t13,
              poids: FontWeight.w600,
              couleur: bande.$2,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _Carte(
          titre: TextesEtatsComptables.ressources,
          enfants: [
            _Ligne(
              TextesEtatsComptables.cafg,
              _montantSigne(t.cafgCentimes),
              cle: const Key('flux-cafg'),
            ),
            _Ligne(
              TextesEtatsComptables.augmentationCapital,
              _montantSigne(t.augmentationCapitalCentimes),
            ),
            _Ligne(
              TextesEtatsComptables.totalRessources,
              _montantSigne(t.totalRessourcesCentimes),
              gras: true,
              cle: const Key('flux-total-ressources'),
            ),
          ],
        ),
        _Carte(
          titre: TextesEtatsComptables.emplois,
          enfants: [
            _Ligne(
              TextesEtatsComptables.acquisitions,
              _montantSigne(t.acquisitionsCentimes),
            ),
            _Ligne(
              TextesEtatsComptables.totalEmplois,
              _montantSigne(t.totalEmploisCentimes),
              gras: true,
              cle: const Key('flux-total-emplois'),
            ),
          ],
        ),
        _Carte(
          titre: TextesEtatsComptables.titreBfr,
          enfants: [
            _Ligne(
              TextesEtatsComptables.variationStocks,
              _montantSigne(t.variationStocksCentimes),
            ),
            _Ligne(
              TextesEtatsComptables.variationCreances,
              _montantSigne(t.variationCreancesCentimes),
            ),
            _Ligne(
              TextesEtatsComptables.variationDettes,
              _montantSigne(t.variationDettesCentimes),
            ),
            _Ligne(
              TextesEtatsComptables.variationBfr,
              _montantSigne(t.variationBfrCentimes),
              gras: true,
              cle: const Key('flux-bfr'),
            ),
          ],
        ),
        _Carte(
          titre: TextesEtatsComptables.titreTresorerie,
          enfants: [
            _Ligne(
              TextesEtatsComptables.calculee,
              _montantSigne(t.variationCalculeeCentimes),
              cle: const Key('flux-calculee'),
            ),
            _Ligne(
              TextesEtatsComptables.reelle,
              _montantSigne(t.variationReelleCentimes),
              gras: true,
              cle: const Key('flux-reelle'),
            ),
            if (!t.coherent)
              _Ligne(
                TextesEtatsComptables.ecart,
                _montantSigne(t.ecartCentimes),
                couleur: PaletteMaitre.rouge600,
              ),
          ],
        ),
      ],
    );
  }
}

/// Le contenu des sept notes annexes (`NotesAnnexesService`).
class ContenuNotes extends ConsumerWidget {
  const ContenuNotes({required this.annee, super.key});

  final int annee;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lu = ref.watch(donneesEtatsFinanciersProvider);
    if (lu.hasError) {
      return Text(
        TextesEtatsComptables.illisible,
        style: styleTransverse(Tailles.t13, couleur: AppColors.erreur),
      );
    }
    final d = lu.value;
    if (d == null) return const SizedBox.shrink();
    final petit = styleTransverse(Tailles.t12, couleur: Ardoise.c400);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final n in notesDe(annee, d))
          _Carte(
            titre: '${n.numero}. ${n.titre}',
            enfants: [
              if (n.texte != null)
                Text(
                  n.texte!,
                  style: styleTransverse(Tailles.t14, couleur: Ardoise.c600),
                ),
              for (final p in n.postes) ...[
                _Ligne(p.libelle, _montantSigne(p.montantCentimes)),
                if (p.ouvertureCentimes != null)
                  Padding(
                    padding: const EdgeInsets.only(left: AppSpacing.md),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          TextesEtatsComptables.ouvertureVariation,
                          style: petit,
                        ),
                        Text(
                          '${_montantSigne(p.ouvertureCentimes!)} · '
                          '${_montantSigne(p.variationCentimes!)}',
                          style: petit,
                        ),
                      ],
                    ),
                  ),
              ],
              if (n.motif != null)
                Padding(
                  padding: EdgeInsets.only(
                    top: n.postes.isNotEmpty || n.texte != null
                        ? AppSpacing.xs
                        : 0,
                  ),
                  child: Text(
                    motifsNotes[n.motif] ?? n.motif!,
                    key: Key('note-${n.numero}-motif'),
                    style: styleTransverse(
                      Tailles.t13,
                      couleur: Ardoise.c400,
                    ).copyWith(fontStyle: FontStyle.italic),
                  ),
                ),
              if (n.texte == null && n.postes.isEmpty && n.motif == null)
                Text(switch (n.etat) {
                  EtatNote.disponible => TextesEtatsComptables.etatDisponible,
                  EtatNote.indisponible =>
                    TextesEtatsComptables.etatIndisponible,
                  EtatNote.nonSaisie => TextesEtatsComptables.etatNonSaisie,
                }, style: petit),
            ],
          ),
      ],
    );
  }
}
