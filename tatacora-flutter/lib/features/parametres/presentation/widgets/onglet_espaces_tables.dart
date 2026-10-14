import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../shared_widgets/bouton_standard.dart';
import '../../../pos/data/tables_pos_dao.dart';
import '../../../pos/domain/entities/espace_pos.dart';
import '../../../pos/domain/entities/table_pos.dart';
import '../../../pos/presentation/providers_pos.dart';

/// Les mots de l'onglet « Espaces & tables » (`pwa.parametres.tables_*`,
/// `table_*`).
abstract final class TextesEspacesTables {
  static const String introA = 'Les tables proposées au point de vente.';
  static const String introFortNumeros =
      'Les numéros ne sont pas codés dans le logiciel';
  static const String introB =
      ' : créez, renumérotez, activez ou désactivez sans intervention '
      'technique. Le ';
  static const String introFortComptoir = 'Comptoir';
  static const String introC =
      " n'a pas de table — une vente au comptoir n'en exige aucune.";
  static const String introFortPanier =
      'Une table dont le panier est ouvert ne se désactive pas';
  static const String introD =
      " : les consommations servies n'auraient plus de table pour les porter "
      "jusqu'à l'addition.";
  static const String boutonAjouter = 'Ajouter une table';
  static const String boutonRenumeroter = 'Renuméroter';
  static const String boutonDesactiver = 'Désactiver';
  static const String boutonReactiver = 'Réactiver';
  static String prefixe(String prefixe) => 'préfixe $prefixe';
  static String places(int places) => '$places place(s)';
  static const String badgePanierOuvert = 'panier ouvert';
  static const String badgeLibre = 'libre';
  static const String badgeDesactivee = 'désactivée';
  static const String espaceVide = 'Aucune table dans cet espace.';
  static const String comptoirSansTable =
      'Aucune table — une vente au comptoir ne se rattache à aucune table.';
  static const String modaleTitreAjout = 'Nouvelle table';
  static String modaleTitreRenumerotation(String libelle) =>
      'Renuméroter $libelle';
  static const String aideRenumerotation =
      'Le libellé suivra le nouveau numéro.';
  static const String champEspace = 'Espace';
  static const String champNumero = 'Numéro';
  static const String champPlaces = 'Places';
  static String tableCreee(String libelle) => 'Table $libelle créée.';
  static const String tableRenumerotee = 'Table renumérotée.';
  static const String tableBasculee = 'État de la table mis à jour.';
  static const String annuler = 'Annuler';
  static const String enregistrer = 'Enregistrer';
  static const String entierAttendu = 'Un nombre entier positif est attendu.';
  static String numeroPris(String libelle) =>
      'La table $libelle existe déjà dans cet espace.';
  static String tableOccupee(String libelle) =>
      'La table $libelle a un panier ouvert : elle ne se désactive pas.';
}

/// L'onglet « Espaces & tables » de Paramètres — le référentiel des tables
/// de salle du poste (`tables_local`, seul écrivain `TablesPosDao`), lu par
/// `salleProvider` comme le point de vente : chaque espace, TOUTES ses tables
/// (désactivées comprises), l'occupation DÉDUITE des paniers ouverts, et le
/// Comptoir affiché avec la raison de son vide.
///
/// Gestes : « Ajouter une table », « Renuméroter », « Désactiver » /
/// « Réactiver ». Non porté : « Rétablir le jeu initial » — la vue REMPLACE
/// la configuration par les treize tables d'origine, ce qui supprimerait des
/// tables, et le référentiel du poste ne supprime jamais (une vente passée
/// pointerait vers une table inexistante).
class OngletEspacesTables extends ConsumerWidget {
  const OngletEspacesTables({required this.peutEcrire, super.key});

  final bool peutEcrire;

  static TextStyle _t(
    double taille, {
    FontWeight poids = FontWeight.normal,
    Color couleur = AppColors.neutre500,
  }) => TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: taille,
    fontWeight: poids,
    color: couleur,
  );

  void _dire(BuildContext context, String texte, {bool erreur = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: erreur ? AppColors.erreur : AppColors.succes,
          content: Text(texte, key: const Key('param-tables-message')),
        ),
      );
  }

  static String _motif(Object e) => switch (e) {
    ArgumentError(:final message) => '$message',
    TableOccupee(:final libelle) => TextesEspacesTables.tableOccupee(libelle),
    _ => '$e',
  };

  Future<void> _ajouter(
    BuildContext context,
    WidgetRef ref,
    List<RayonSalle> salle,
  ) async {
    final saisie = await showDialog<_SaisieTable>(
      context: context,
      barrierColor: AppColors.voileModale,
      builder: (_) => const _ModaleTable(),
    );
    if (saisie == null || !context.mounted) return;
    final espace = saisie.espace;
    final deja = salle
        .where((r) => r.espace == espace)
        .expand((r) => r.cases)
        .any((c) => c.table.numero == saisie.numero);
    if (deja) {
      _dire(
        context,
        TextesEspacesTables.numeroPris('${espace.prefixe}${saisie.numero}'),
        erreur: true,
      );
      return;
    }
    try {
      final t = await ref
          .read(tablesPosDaoProvider)
          .creer(espace: espace, numero: saisie.numero, places: saisie.places);
      ref.invalidate(salleProvider);
      if (context.mounted) {
        _dire(context, TextesEspacesTables.tableCreee(t.libelle));
      }
    } on Object catch (e) {
      if (context.mounted) _dire(context, _motif(e), erreur: true);
    }
  }

  Future<void> _renumeroter(
    BuildContext context,
    WidgetRef ref,
    TablePos table,
  ) async {
    final saisie = await showDialog<_SaisieTable>(
      context: context,
      barrierColor: AppColors.voileModale,
      builder: (_) => _ModaleTable(table: table),
    );
    if (saisie == null || !context.mounted) return;
    try {
      await ref.read(tablesPosDaoProvider).renumeroter(table.id, saisie.numero);
      ref.invalidate(salleProvider);
      if (context.mounted) {
        _dire(context, TextesEspacesTables.tableRenumerotee);
      }
    } on Object catch (e) {
      if (context.mounted) _dire(context, _motif(e), erreur: true);
    }
  }

  Future<void> _basculer(
    BuildContext context,
    WidgetRef ref,
    TablePos table,
  ) async {
    try {
      await ref.read(tablesPosDaoProvider).basculer(table.id);
      ref.invalidate(salleProvider);
      if (context.mounted) _dire(context, TextesEspacesTables.tableBasculee);
    } on Object catch (e) {
      if (context.mounted) _dire(context, _motif(e), erreur: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final salle = ref.watch(salleProvider);
    final rayons = salle.value ?? const <RayonSalle>[];
    final fort = _t(TaillesContenu.t13, poids: FontWeight.bold);

    Widget badge(String texte, Color fond, Color encre) => Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.demi,
      ),
      decoration: BoxDecoration(
        color: fond,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        texte,
        style: _t(TaillesContenu.t11, poids: FontWeight.w600, couleur: encre),
      ),
    );

    Widget lien(Key cle, String texte, Color couleur, VoidCallback geste) =>
        InkWell(
          key: cle,
          onTap: geste,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
            child: Text(
              texte,
              style: _t(
                TaillesContenu.t12,
                poids: FontWeight.w600,
                couleur: couleur,
              ),
            ),
          ),
        );

    return Column(
      key: const Key('param-onglet-tables'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: '${TextesEspacesTables.introA} '),
                    TextSpan(
                      text: TextesEspacesTables.introFortNumeros,
                      style: fort,
                    ),
                    const TextSpan(text: TextesEspacesTables.introB),
                    TextSpan(
                      text: TextesEspacesTables.introFortComptoir,
                      style: fort,
                    ),
                    const TextSpan(text: '${TextesEspacesTables.introC}\n'),
                    TextSpan(
                      text: TextesEspacesTables.introFortPanier,
                      style: fort,
                    ),
                    const TextSpan(text: TextesEspacesTables.introD),
                  ],
                ),
                style: _t(TaillesContenu.t13),
              ),
            ),
            if (peutEcrire) ...[
              const SizedBox(width: AppSpacing.md),
              BoutonStandard(
                key: const Key('param-tables-ajouter'),
                variante: VarianteBouton.primaire,
                libelle: TextesEspacesTables.boutonAjouter,
                onPressed: salle.hasValue
                    ? () => _ajouter(context, ref, rayons)
                    : null,
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (salle.hasError)
          Text('${salle.error}', style: _t(TaillesContenu.t13))
        else if (!salle.hasValue)
          const Center(child: CircularProgressIndicator())
        else ...[
          for (final rayon in rayons) ...[
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: '${rayon.espace.libelle} '),
                  TextSpan(
                    text: TextesEspacesTables.prefixe(rayon.espace.prefixe),
                    style: _t(TaillesContenu.t11, couleur: AppColors.neutre400),
                  ),
                ],
              ),
              style: _t(
                TaillesContenu.t13,
                poids: FontWeight.bold,
                couleur: AppColors.navy,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            if (rayon.cases.isEmpty)
              Text(
                TextesEspacesTables.espaceVide,
                style: _t(TaillesContenu.t12, couleur: AppColors.neutre400),
              ),
            for (final c in rayon.cases)
              Container(
                key: Key('param-table-${c.table.id}'),
                margin: const EdgeInsets.only(bottom: AppSpacing.xxs),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.neutre200),
                  borderRadius: BorderRadius.circular(AppRadius.roundedLg),
                ),
                child: Row(
                  children: [
                    Text(
                      c.table.libelle,
                      style: _t(
                        TaillesContenu.t14,
                        poids: FontWeight.bold,
                        couleur: AppColors.navy,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      TextesEspacesTables.places(c.table.places),
                      style: _t(
                        TaillesContenu.t12,
                        couleur: AppColors.neutre400,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    if (c.panierOuvertId != null)
                      badge(
                        TextesEspacesTables.badgePanierOuvert,
                        PaletteMaitre.ambre50,
                        PaletteMaitre.ambre700,
                      )
                    else if (c.table.actif)
                      badge(
                        TextesEspacesTables.badgeLibre,
                        PaletteMaitre.vert50,
                        AppColors.succes,
                      )
                    else
                      badge(
                        TextesEspacesTables.badgeDesactivee,
                        AppColors.neutre100,
                        AppColors.neutre600,
                      ),
                    const Spacer(),
                    if (peutEcrire) ...[
                      lien(
                        Key('param-table-renumeroter-${c.table.id}'),
                        TextesEspacesTables.boutonRenumeroter,
                        AppColors.navy,
                        () => _renumeroter(context, ref, c.table),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      lien(
                        Key('param-table-basculer-${c.table.id}'),
                        c.table.actif
                            ? TextesEspacesTables.boutonDesactiver
                            : TextesEspacesTables.boutonReactiver,
                        AppColors.gold,
                        () => _basculer(context, ref, c.table),
                      ),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.md),
          ],
          Container(
            padding: const EdgeInsets.all(AppSpacing.smPlus),
            decoration: BoxDecoration(
              color: AppColors.neutre50,
              border: Border.all(color: AppColors.neutre200),
              borderRadius: BorderRadius.circular(AppRadius.roundedLg),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  EspacePos.comptoir.libelle,
                  style: _t(
                    TaillesContenu.t13,
                    poids: FontWeight.bold,
                    couleur: AppColors.neutre700,
                  ),
                ),
                const SizedBox(height: AppSpacing.unit),
                Text(
                  TextesEspacesTables.comptoirSansTable,
                  style: _t(TaillesContenu.t12),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

typedef _SaisieTable = ({EspacePos espace, int numero, int places});

/// « Nouvelle table » (espace, numéro, places) ou « Renuméroter » (numéro
/// seul) — une fenêtre COMPACTE.
class _ModaleTable extends StatefulWidget {
  const _ModaleTable({this.table});

  /// `null` : création.
  final TablePos? table;

  @override
  State<_ModaleTable> createState() => _ModaleTableState();
}

class _ModaleTableState extends State<_ModaleTable> {
  late EspacePos _espace = widget.table?.espace ?? EspacePos.restaurant;
  late final _numero = TextEditingController(
    text: widget.table == null ? '' : '${widget.table!.numero}',
  );
  final _places = TextEditingController(text: '4');
  String? _erreur;

  @override
  void dispose() {
    _numero.dispose();
    _places.dispose();
    super.dispose();
  }

  void _valider() {
    final numero = int.tryParse(_numero.text.trim());
    final places = int.tryParse(_places.text.trim());
    if (numero == null ||
        numero < 1 ||
        (widget.table == null && (places == null || places < 1))) {
      setState(() => _erreur = TextesEspacesTables.entierAttendu);
      return;
    }
    Navigator.of(
      context,
    ).pop((espace: _espace, numero: numero, places: places ?? 4));
  }

  @override
  Widget build(BuildContext context) {
    final creation = widget.table == null;
    final etiquette = OngletEspacesTables._t(
      TaillesContenu.t13,
      poids: FontWeight.w600,
      couleur: AppColors.neutre700,
    );
    const decoration = InputDecoration(
      isDense: true,
      border: OutlineInputBorder(),
    );
    return Dialog(
      key: const Key('param-modale-table'),
      backgroundColor: AppColors.neutre0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: Largeurs.maxSm),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                creation
                    ? TextesEspacesTables.modaleTitreAjout
                    : TextesEspacesTables.modaleTitreRenumerotation(
                        widget.table!.libelle,
                      ),
                style: OngletEspacesTables._t(
                  TaillesContenu.base,
                  poids: FontWeight.bold,
                  couleur: AppColors.navy,
                ),
              ),
              if (!creation) ...[
                const SizedBox(height: AppSpacing.unit),
                Text(
                  TextesEspacesTables.aideRenumerotation,
                  style: OngletEspacesTables._t(TaillesContenu.t13),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              if (creation) ...[
                Text(TextesEspacesTables.champEspace, style: etiquette),
                const SizedBox(height: AppSpacing.unit),
                DropdownButtonFormField<EspacePos>(
                  key: const Key('param-table-espace'),
                  initialValue: _espace,
                  decoration: decoration,
                  items: [
                    for (final e in EspacePos.avecTablesSeulement)
                      DropdownMenuItem(value: e, child: Text(e.libelle)),
                  ],
                  onChanged: (e) => setState(() => _espace = e ?? _espace),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              Text(TextesEspacesTables.champNumero, style: etiquette),
              const SizedBox(height: AppSpacing.unit),
              TextField(
                key: const Key('param-table-numero'),
                controller: _numero,
                keyboardType: TextInputType.number,
                decoration: decoration,
                onSubmitted: (_) => _valider(),
              ),
              if (creation) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(TextesEspacesTables.champPlaces, style: etiquette),
                const SizedBox(height: AppSpacing.unit),
                TextField(
                  key: const Key('param-table-places'),
                  controller: _places,
                  keyboardType: TextInputType.number,
                  decoration: decoration,
                  onSubmitted: (_) => _valider(),
                ),
              ],
              if (_erreur != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _erreur!,
                  style: OngletEspacesTables._t(
                    TaillesContenu.t12,
                    couleur: AppColors.erreur,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.mdPlus),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  BoutonStandard(
                    key: const Key('param-table-annuler'),
                    libelle: TextesEspacesTables.annuler,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  BoutonStandard(
                    key: const Key('param-table-valider'),
                    variante: VarianteBouton.primaire,
                    libelle: TextesEspacesTables.enregistrer,
                    onPressed: _valider,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
