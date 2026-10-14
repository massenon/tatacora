// Vue Blade maîtresse (PA-183) : pwa/stocks/stocks.blade.php
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/fichiers/selecteur_fichiers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../shared_widgets/bouton_standard.dart';
import '../../../restaurant/presentation/widgets/coquille_modale_restaurant.dart';
import '../../../restaurant/presentation/widgets/textes_modale_restaurant.dart';
import '../../data/service_import_articles.dart';
import '../../domain/import_articles.dart';
import '../providers_stocks.dart';

/// La modale **« Importer des articles »** — la vue des stocks
/// (`etatFormulaire === 'import'`, l.746-775) : titre, sous-titre, sélecteur
/// de fichier, la note des colonnes, la liste des lignes refusées, puis
/// « Annuler » / « Importer ».
///
/// L'import CRÉE réellement les articles sur ce poste (`importerArticles`,
/// réplique de `Stocks::lancerImport`), le stock d'ouverture entrant comme un
/// MOUVEMENT d'entrée. Comme au serveur, un import partiel GARDE la modale
/// ouverte sur la liste des lignes à corriger ; un import complet la ferme et
/// rend le bilan. Rend `null` si rien n'a été importé, sinon le bilan.
Future<BilanImportArticles?> ouvrirModaleImportArticles(BuildContext context) {
  return showDialog<BilanImportArticles>(
    context: context,
    barrierColor: AppColors.voileModale,
    builder: (_) => const _ModaleImport(),
  );
}

class _ModaleImport extends ConsumerStatefulWidget {
  const _ModaleImport();

  @override
  ConsumerState<_ModaleImport> createState() => _ModaleImportState();
}

class _ModaleImportState extends ConsumerState<_ModaleImport> {
  FichierLu? _fichier;
  BilanImportArticles? _bilan;
  bool _enCours = false;

  /// `fichierImport` sans fichier : la règle `required` du serveur.
  String? _erreur;

  /// Au moins un article créé pendant la vie de la modale : la fermer par
  /// « Annuler » doit quand même faire relire le stock.
  int _creesCumules = 0;

  Future<void> _choisir() async {
    final lu = await ref.read(selecteurFichiersProvider).ouvrirCsv();
    if (lu == null || !mounted) return;
    setState(() {
      _fichier = lu;
      _erreur = null;
      _bilan = null;
    });
  }

  Future<void> _importer() async {
    final fichier = _fichier;
    if (fichier == null) {
      // La règle `required` du serveur sur `fichierImport`.
      setState(() => _erreur = "Choisissez d'abord le fichier CSV à importer.");
      return;
    }
    setState(() {
      _enCours = true;
      _erreur = null;
    });

    String contenu;
    try {
      contenu = utf8.decode(fichier.octets);
    } on FormatException {
      setState(() {
        _enCours = false;
        _erreur = TextesImportArticles.fichierIllisible;
      });
      return;
    }

    final api = ref.read(stocksApiProvider);
    final points = await api.points();
    const uuid = Uuid();
    final bilan = await importerArticles(
      contenu: contenu,
      points: points,
      nouvelId: uuid.v4,
      enregistrer: (saisie) => enregistrerArticleImporte(api, saisie),
    );
    if (!mounted) return;
    _creesCumules += bilan.crees;
    if (bilan.crees > 0) ref.invalidate(etatStockProvider);

    // Comme au serveur : un import COMPLET ferme la modale ; un import partiel
    // (ou un fichier refusé) la garde ouverte sur ce qu'il faut corriger.
    if (bilan.complet && bilan.reserves.isEmpty) {
      Navigator.of(context).pop(bilan);
      return;
    }
    setState(() {
      _enCours = false;
      _bilan = bilan;
    });
  }

  void _fermer() {
    Navigator.of(
      context,
    ).pop(_creesCumules > 0 ? BilanImportArticles(crees: _creesCumules) : null);
  }

  @override
  Widget build(BuildContext context) {
    final bilan = _bilan;
    final rouge = TextesModaleRestaurant.aide.copyWith(
      color: PaletteMaitre.rouge600,
    );

    return CoquilleModaleRestaurant(
      cle: const Key('modale-import-articles'),
      titre: TextesImportArticles.titre,
      sousTitre: TextesImportArticles.sousTitre,
      largeur: AppLayout.modaleImportArticles,
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // `block text-[11px] font-semibold text-slate-500 mb-1`.
          const Padding(
            padding: EdgeInsets.only(bottom: AppSpacing.unit),
            child: Text(
              TextesImportArticles.fichier,
              style: TextStyle(
                fontFamily: AppTextStyles.police,
                fontSize: Tailles.t11,
                fontWeight: FontWeight.w600,
                color: Ardoise.c500,
              ),
            ),
          ),
          // `<input type="file" class="w-full text-[13px] border
          // border-slate-300 rounded-lg px-3 py-2.5">` : le bouton du
          // navigateur, puis le nom du fichier choisi.
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              border: Border.all(color: Ardoise.c300),
              borderRadius: BorderRadius.circular(AppRadius.roundedLg),
            ),
            child: Row(
              children: [
                BoutonStandard(
                  key: const Key('import-choisir-fichier'),
                  libelle: 'Choisir un fichier',
                  taillePolice: Tailles.t13,
                  onPressed: _enCours ? null : _choisir,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    _fichier?.nom ?? 'Aucun fichier choisi',
                    key: const Key('import-nom-fichier'),
                    overflow: TextOverflow.ellipsis,
                    style: TextesModaleRestaurant.corps,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.unit),
          Text(
            TextesImportArticles.colonnes,
            key: const Key('import-colonnes'),
            style: TextesModaleRestaurant.aide,
          ),
          if (_erreur != null || bilan != null) ...[
            const SizedBox(height: AppSpacing.unit),
            Text(
              _erreur ?? bilan!.phrase,
              key: const Key('import-bilan'),
              style: rouge,
            ),
          ],
          if (bilan != null &&
              (bilan.refusees.isNotEmpty || bilan.reserves.isNotEmpty)) ...[
            const SizedBox(height: AppSpacing.sm),
            // `list-disc pl-5 space-y-1 max-h-40 overflow-y-auto` : chaque
            // ligne fautive NOMMÉE (règle du serveur).
            ConstrainedBox(
              constraints: const BoxConstraints(
                maxHeight: AppLayout.listeRefusImport,
              ),
              child: ListView(
                key: const Key('import-lignes-refusees'),
                shrinkWrap: true,
                children: [
                  for (final l in [...bilan.refusees, ...bilan.reserves])
                    Padding(
                      padding: const EdgeInsets.only(
                        left: AppSpacing.mdPlus,
                        bottom: AppSpacing.unit,
                      ),
                      child: Text('• $l', style: rouge),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
      actions: [
        BoutonStandard(
          key: const Key('import-annuler'),
          libelle: 'Annuler',
          taillePolice: Tailles.t13,
          onPressed: _fermer,
        ),
        BoutonStandard(
          key: const Key('import-valider'),
          variante: VarianteBouton.primaire,
          libelle: TextesImportArticles.valider,
          taillePolice: Tailles.t13,
          onPressed: _enCours ? null : _importer,
        ),
      ],
    );
  }
}
