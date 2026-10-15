// Vue Blade maîtresse (PA-183) : pwa/livewire/accueil.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/fichiers/enregistrement_export.dart';
import '../../../../core/impression/entete_parametree.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../shared_widgets/modale_export.dart';
import '../../../../shared_widgets/toast_export.dart';
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
/// rendus en PDF A4 (`EtatRapportAccueil.pdf`) ou en tableur CSV, enregistrés
/// par la fenêtre « Enregistrer sous » ([exporterRapportAccueilProvider]). Une liste vide se REFUSE, modale
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

/// L'enregistrement d'un rapport — PDF ou tableur — par la fenêtre
/// « Enregistrer sous » (14/10/2026) : rend le CHEMIN du fichier, `null` :
/// annulé. Le nom suggéré reste celui du serveur
/// (`EtatRapportAccueil.nomFichier`).
final exporterRapportAccueilProvider =
    Provider<Future<String?> Function(EtatRapportAccueil, FormatExport)>(
      (ref) => (etat, format) async {
        final type = switch (format) {
          FormatExport.pdf => TypeFichierEnregistre.pdf,
          FormatExport.excel => TypeFichierEnregistre.csv,
        };
        final octets = switch (format) {
          FormatExport.pdf =>
            await etat
                .avecEntete(await ref.read(lireEnteteEtablissementProvider)())
                .pdf(),
          FormatExport.excel => etat.csvOctets(),
        };
        return ref
            .read(enregistrementExportProvider)
            .enregistrerFichier(
              nomSuggere:
                  '${etat.nomFichier(DateTime.now())}.${type.extension}',
              octets: octets,
              type: type,
            );
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

/// Produit [etat] dans [format] par la fenêtre « Enregistrer sous », puis
/// dit l'issue par le toast commun ([messager] : pris avant qu'une modale ne
/// se ferme).
Future<void> produireRapportAccueil(
  WidgetRef ref,
  ScaffoldMessengerState messager,
  EtatRapportAccueil etat,
  FormatExport format, {
  required Key cleSucces,
}) => executerExportAvec(
  messager,
  () => ref.read(exporterRapportAccueilProvider)(etat, format),
  cleSucces: cleSucces,
);

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
  await produireRapportAccueil(
    ref,
    messager,
    etat,
    format,
    cleSucces: const Key('tdb-exporter-csv'),
  );
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
    await produireRapportAccueil(
      ref,
      messager,
      etat,
      _format,
      cleSucces: const Key('tdb-rapport-csv'),
    );
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
