// Vue Blade maîtresse (PA-183) : pwa/livewire/accueil.blade.php
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../bar/presentation/widgets/modale_export_carte.dart';
import '../../../facturation/presentation/providers_paiements.dart';
import '../../../hebergement/presentation/providers_hebergement.dart';
import '../../../restaurant/presentation/widgets/coquille_modale_restaurant.dart';
import '../../../stocks/data/stocks_api.dart';
import '../../../stocks/presentation/providers_stocks.dart';
import '../../data/tableau_de_bord_local.dart';
import '../../domain/croise_local.dart';
import '../../domain/exploitation_locale.dart';
import '../../domain/modules_pilotage.dart';
import '../../domain/periode_locale.dart';
import '../../domain/rapports_accueil.dart';
import '../../impression/etat_rapport_accueil.dart';
import '../ecran_pilotage_consolide.dart'
    show horlogeTableauDeBordProvider, noteExportPilotage, titreExportPilotage;
import '../ecran_tableau_croise.dart' show sourcesCroiseProvider;
import '../ecran_tableau_de_bord.dart'
    show
        EcranTableauDeBord,
        periodeTableauDeBordProvider,
        tableauDeBordLocalProvider;
import 'champs_modale_accueil.dart';

/// La modale « Générer un rapport » de la vue d'accueil (l.1721-1746) et le
/// document que produit « Exporter » (l.300, `ouvrirExport` → `genererExport`,
/// rapport `synthese` par défaut) — lot C du plan du PO, 14/10/2026.
///
/// Les six rapports sont COMPOSÉS sur ce poste ([rapports_accueil.dart]) et
/// rendus en PDF A4 (`EtatRapportAccueil.pdf`, action injectable
/// [imprimerRapportAccueilProvider]) ou en tableur CSV
/// ([exporterRapportAccueilProvider]). Une liste vide se REFUSE, modale
/// ouverte, avec la phrase de la vue (PA-119).
///
/// ## Écarts nommés (14/10/2026)
///
/// * **Tableur** : un CSV (repli du serveur sans Maatwebsite), jamais un
///   `.xlsx` — aucune bibliothèque XLSX embarquée (PA-111).
/// * **Synthèse** : « Dépenses cumulées » porte « — » (indicateur non établi
///   sur ce poste, raison datée), le serveur un chiffre.
/// * **« Exporter » sur une liste vide** : la modale d'export de la vue
///   n'affiche pas l'erreur `typeRapport` (rien ne se passe) ; ce poste DIT
///   le refus (Article 3.3 : aucun contrôle muet).

/// L'impression d'un rapport — un seul endroit déclenche `Printing`.
final imprimerRapportAccueilProvider =
    Provider<Future<void> Function(EtatRapportAccueil)>(
      (ref) => (etat) async {
        await Printing.layoutPdf(
          onLayout: (_) => etat.pdf(),
          name: etat.titre,
          format: PdfPageFormat.a4,
        );
      },
    );

/// L'écriture du tableur — rend le CHEMIN du fichier, pour être affiché : un
/// export silencieux est un export que personne ne retrouve.
final exporterRapportAccueilProvider =
    Provider<Future<String> Function(EtatRapportAccueil)>(
      (ref) => (etat) async {
        final dossier = await getApplicationDocumentsDirectory();
        final fichier = File(
          p.join(dossier.path, '${etat.nomFichier(DateTime.now())}.csv'),
        );
        await fichier.writeAsBytes(etat.csvOctets());
        return fichier.path;
      },
    );

/// `Accueil::lignesRapport($type)` sur la période de l'écran, mises en
/// document. Les lecteurs sont ceux des écrans sources, appelés DIRECTEMENT
/// (jamais un fournisseur `autoDispose` lu sans écouteur).
Future<EtatRapportAccueil> composerRapportAccueil(
  WidgetRef ref,
  TypeRapportAccueil type,
) async {
  final selection = ref.read(periodeTableauDeBordProvider);
  final maintenant = ref.read(horlogeTableauDeBordProvider)();
  final fenetre = FenetreTableauDeBord.resoudre(selection, maintenant);

  // La synthèse lit la bande ; son libellé de période est celui du serveur.
  final bande = await ref.read(tableauDeBordLocalProvider).consulter(selection);
  final tableau = switch (bande) {
    TableauDeBordRecu(:final tableau) => tableau,
    _ => null,
  };
  final periode = tableau?.libellePeriode ?? fenetre.libelle;

  final List<List<String>> lignes;
  switch (type) {
    case TypeRapportAccueil.synthese:
      lignes = tableau == null
          ? const []
          : lignesSyntheseRapport(tableau, EcranTableauDeBord.libelles);
    case TypeRapportAccueil.reservations:
      lignes = lignesReservationsRapport(
        reservations: await ref.read(depotReservationProvider).reservations(),
        debut: fenetre.debut,
        finExclue: fenetre.finExclue,
      );
    case TypeRapportAccueil.stocks:
      final stock = await ref.read(stocksApiProvider).etat();
      lignes = switch (stock) {
        StockRecu(:final etat) => lignesStocksRapport(
          articlesCritiques(etat.lignes),
        ),
        _ => const [],
      };
    case TypeRapportAccueil.creances:
      lignes = lignesCreancesRapport(
        creancesParAnciennete(await lireCreances(ref.read), maintenant),
      );
    case TypeRapportAccueil.recettes:
      lignes = lignesRecettesRapport(
        await ref
            .read(sourcesCroiseProvider)
            .faits(
              debut: fenetre.debut,
              finExclue: fenetre.finExclue,
              sources: {SourceCroise.ventes, SourceCroise.reservations},
            ),
      );
    case TypeRapportAccueil.ventes:
      lignes = lignesVentesRapport(
        await ref
            .read(sourcesCroiseProvider)
            .faits(
              debut: fenetre.debut,
              finExclue: fenetre.finExclue,
              sources: {SourceCroise.ventes},
            ),
      );
  }

  return EtatRapportAccueil(
    titre: type.libelle,
    periode: periode,
    entetes: type.entetes,
    lignes: lignes,
    code: type.code,
  );
}

/// Produit [etat] dans [format] ; rend le message à afficher (chemin du
/// tableur) ou `null`.
Future<String?> produireRapportAccueil(
  WidgetRef ref,
  EtatRapportAccueil etat,
  FormatExport format,
) async {
  switch (format) {
    case FormatExport.pdf:
      await ref.read(imprimerRapportAccueilProvider)(etat);
      return null;
    case FormatExport.excel:
      final chemin = await ref.read(exporterRapportAccueilProvider)(etat);
      return 'Tableur (CSV) enregistré sur ce poste : $chemin';
  }
}

/// « Exporter » de l'en-tête — `ouvrirExport` puis `genererExport` : la modale
/// partagée (titre `accueil_pwa.export_titre`, sous-titre de la note des
/// rapports), puis la SYNTHÈSE du tableau de bord, le rapport par défaut du
/// composant.
Future<void> exporterSyntheseAccueil(
  BuildContext context,
  WidgetRef ref,
) async {
  final format = await choisirFormatExport(
    context,
    titre: titreExportPilotage,
    sousTitre: noteExportPilotage,
  );
  if (format == null || !context.mounted) return;
  final messager = ScaffoldMessenger.of(context);
  final etat = await composerRapportAccueil(ref, TypeRapportAccueil.synthese);
  if (etat.lignes.isEmpty) {
    messager
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(messageRapportVide, key: Key('tdb-exporter-vide')),
        ),
      );
    return;
  }
  final message = await produireRapportAccueil(ref, etat, format);
  if (message != null) {
    messager
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message, key: const Key('tdb-exporter-csv'))),
      );
  }
}

/// `$set('etatFormulaire', 'rapport')`.
Future<void> ouvrirModaleRapport(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _ModaleRapport());

class _ModaleRapport extends ConsumerStatefulWidget {
  const _ModaleRapport();

  @override
  ConsumerState<_ModaleRapport> createState() => _ModaleRapportState();
}

class _ModaleRapportState extends ConsumerState<_ModaleRapport> {
  TypeRapportAccueil _type = TypeRapportAccueil.synthese;
  FormatExport _format = FormatExport.pdf;
  String? _erreur;
  bool _enCours = false;

  Future<void> _telecharger() async {
    setState(() => _enCours = true);
    final etat = await composerRapportAccueil(ref, _type);
    if (!mounted) return;
    if (etat.lignes.isEmpty) {
      // PA-119 — une liste vide se REFUSE, modale OUVERTE.
      setState(() {
        _erreur = messageRapportVide;
        _enCours = false;
      });
      return;
    }
    final messager = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    final message = await produireRapportAccueil(ref, etat, _format);
    if (message != null) {
      messager
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(message, key: const Key('tdb-rapport-csv'))),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return CoquilleModaleRestaurant(
      cle: const Key('tdb-modale-rapport'),
      titre: 'Générer un rapport',
      largeur: MesuresAccueil.modaleRapide,
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          BlocChampAccueil(
            libelle: 'Type de rapport',
            champ: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                ChampChoixAccueil<TypeRapportAccueil>(
                  key: const Key('tdb-rapport-type'),
                  valeur: _type,
                  choix: [
                    for (final t in TypeRapportAccueil.values) (t, t.libelle),
                  ],
                  onChange: (t) {
                    if (t != null) setState(() => _type = t);
                  },
                ),
                // `text-[12px] text-slate-400 mt-1`.
                const Padding(
                  padding: EdgeInsets.only(top: AppSpacing.unit),
                  child: Text(
                    noteExportPilotage,
                    style: TextStyle(
                      fontFamily: AppTextStyles.police,
                      fontSize: Tailles.t12,
                      color: AppColors.neutre400,
                    ),
                  ),
                ),
              ],
            ),
            erreur: _erreur,
          ),
          BlocChampAccueil(
            libelle: 'Format',
            champ: ChampChoixAccueil<FormatExport>(
              key: const Key('tdb-rapport-format'),
              valeur: _format,
              choix: const [
                (FormatExport.pdf, 'PDF'),
                (FormatExport.excel, 'Excel'),
              ],
              onChange: (f) {
                if (f != null) setState(() => _format = f);
              },
            ),
          ),
        ],
      ),
      actions: [
        const BoutonAnnulerAccueil(cle: Key('tdb-rapport-annuler')),
        BoutonValiderAccueil(
          cle: const Key('tdb-rapport-telecharger'),
          libelle: 'Télécharger',
          fond: AppColors.navy,
          onPressed: _enCours ? null : _telecharger,
        ),
      ],
    );
  }
}
