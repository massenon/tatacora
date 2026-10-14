import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../shared_widgets/bouton_standard.dart';
import '../../impression/etat_liste_achats.dart';
import '../providers_achats.dart';

/// La barre d'outils commune aux quatre listes — `m7-approvisionnement.html`
/// l.118-130 (`barreOutils`) et l.140-175 (`brancherOutils`).
///
/// Le maître la factorise et dit pourquoi (l.108-111) : trois barres
/// différentes pour quatre listes obligent l'utilisateur à réapprendre l'écran
/// à chaque onglet, *« et c'est ainsi qu'on cesse de se servir des filtres »*.
///
/// ## L'export part de CE QUI EST AFFICHÉ
///
/// [construireListe] est appelée **au clic**, sur l'état courant de l'écran :
/// elle rend exactement les lignes visibles, avec leur filtre. Construire la
/// liste à l'avance exporterait l'état d'avant la dernière frappe.
///
/// Une liste vide se **refuse** — même mot que le maître (l.157). Une page
/// blanche remise au Gérant se lit comme « aucun élément », alors qu'elle veut
/// dire « le filtre n'a rien retenu ».
class BarreOutilsAchats extends ConsumerWidget {
  const BarreOutilsAchats({
    required Key cle,
    required this.prefixeCle,
    required this.placeholder,
    required this.controleurRecherche,
    required this.onRecherche,
    required this.construireListe,
    this.filtre,
    this.largeurRecherche = AppLayout.rechercheAchats,
    this.actionSupplementaire,
    this.rechercheActive = true,
  }) : super(key: cle);

  /// Le préfixe des clés de widget — `cmd`, `rec`, `bes`, `four`. Il reprend
  /// celui du maître (`rech-cmd`, `excel-cmd`, `pdf-cmd`).
  final String prefixeCle;

  final String placeholder;
  final TextEditingController controleurRecherche;
  final ValueChanged<String> onRecherche;

  /// `null` quand la liste rendue est vide ou illisible : l'export refuse
  /// alors, avec sa raison.
  final ListeAchats? Function() construireListe;

  final Widget? filtre;
  final double largeurRecherche;
  final Widget? actionSupplementaire;

  /// `false` quand l'API ne sert AUCUNE recherche sur cette liste — le champ
  /// reste a sa place, grise, avec sa raison en texte d'aide.
  ///
  /// Le retirer ferait disparaitre un controle du maitre sans rien dire ; le
  /// laisser actif et filtrer localement une liste **paginee** dirait « aucun
  /// resultat » sur un registre qui en contient. Un champ grise dit la
  /// troisieme chose, qui est la vraie : la fonction manque.
  final bool rechercheActive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: largeurRecherche,
          child: TextField(
            key: Key('rech-$prefixeCle'),
            controller: controleurRecherche,
            enabled: rechercheActive,
            decoration: InputDecoration(
              hintText: placeholder,
              prefixIcon: const Icon(Icons.search, size: 18),
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            onChanged: onRecherche,
          ),
        ),
        ?filtre,
        // Bouton standard (PO, 14/10/2026). Le libellé du maître. L'écart de
        // FORMAT (CSV et non XLSX) est nommé au bloc « Ce que cet écran ne
        // rend pas », pas masqué sous un autre mot : c'est la convention du
        // serveur (RG-19) et ce qu'attend un Excel en configuration française.
        BoutonStandard(
          key: Key('excel-$prefixeCle'),
          libelle: 'Export Excel',
          onPressed: () => _exporter(context, ref),
        ),
        BoutonStandard(
          key: Key('pdf-$prefixeCle'),
          libelle: 'Export PDF',
          variante: VarianteBouton.primaire,
          onPressed: () => _imprimer(context, ref),
        ),
        ?actionSupplementaire,
      ],
    );
  }

  Future<void> _exporter(BuildContext context, WidgetRef ref) async {
    final liste = construireListe();
    if (_refuse(context, liste)) return;

    final chemin = await ref.read(exporterListeAchatsProvider)(liste!);
    if (!context.mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Export écrit : $chemin')));
  }

  Future<void> _imprimer(BuildContext context, WidgetRef ref) async {
    final liste = construireListe();
    if (_refuse(context, liste)) return;

    await ref.read(imprimerListeAchatsProvider)(liste!);
  }

  /// Vrai quand l'export a été refusé — et il DIT pourquoi.
  bool _refuse(BuildContext context, ListeAchats? liste) {
    if (liste != null && !liste.estVide) return false;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        key: Key('export-refuse'),
        content: Text(messageExportVide),
      ),
    );
    return true;
  }
}
