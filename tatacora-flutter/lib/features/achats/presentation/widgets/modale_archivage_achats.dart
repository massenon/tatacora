// Vue Blade maîtresse (PA-183) : pwa/achats/achats.blade.php
// (composant `modale-archivage`, invoqué l.504-511).
// Le composant est AUSSI invoqué par pwa/vehicules/locations.blade.php
// (l.835-843) pour archiver un véhicule : sa question y est un `message`
// (« Voulez-vous archiver le véhicule :element ? ») que le composant accepte
// (`@props 'message'`). Une seule modale Flutter pour les deux vues
// (09/10/2026) — ce n'est ni un refus ni un contournement, le fichier sert
// réellement la seconde vue.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';

/// La confirmation d'archivage d'un ou de plusieurs fournisseurs — et la vue
/// n'y supprime pas : elle ARCHIVE (composant `modale-archivage` de la PWA).
///
/// ## Trois états, et le premier est celui qui compte
///
/// 1. **BLOQUÉ** — tout ce qui est visé est engagé ailleurs. La vue affiche
///    « Archivage impossible », liste les motifs, et MASQUE le bouton de
///    confirmation : le laisser visible et inerte laisserait croire à une
///    panne, le masquer dit que la décision n'appartient pas à cet écran.
/// 2. **PARTIEL** — une partie seulement est bloquée : le geste part, et
///    l'écran annonce AVANT le clic combien d'éléments resteront.
/// 3. **NOMINAL** — la question, puis le rappel : rien n'est effacé.
///
/// ## Les trois états sont ALIMENTÉS par le DAO (D63, 12/10/2026)
///
/// La vue relit en base, pour chaque fiche, les commandes d'achat qui l'engagent
/// (`ReferentielFournisseurService::engagements()`) et en tire `messagesVerrou`,
/// `bloque` et `conserves`. Le poste fait de même : `AchatsDao.composerLotArchivage`
/// rend un `LotArchivage` dont `VueFournisseurs` nourrit cette modale. Jusqu'au
/// 12/10/2026 l'appelant passait l'état NOMINAL faute de commandes à lire ; la
/// confirmation n'écrivait rien. Elle écrit désormais (`actif = false`), et les
/// motifs datent de l'OUVERTURE : le verrou qui tranche est recontrôlé à
/// l'exécution, un engagement pouvant naître entre l'ouverture et le clic.
///
/// ## Le titre dit « suppression », le corps dit « archiver »
///
/// Ce n'est pas une incohérence à lisser : le titre et le bouton sont le texte
/// que le client a validé, le corps est ce que l'utilisateur lit juste avant de
/// cliquer. Côté serveur, aucun de ces boutons ne supprime quoi que ce soit.
///
/// Rend `true` si l'utilisateur confirme, `false` ou `null` sinon.
Future<bool?> ouvrirArchivageAchats(
  BuildContext context, {
  String? element,
  int? nombre,
  List<String> messagesVerrou = const [],
  bool bloque = false,
  int conserves = 0,
  String? message,
}) {
  assert(
    element != null || nombre != null || message != null,
    'la question porte sur un élément nommé, sur un nombre, ou est un message',
  );
  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierColor: AppColors.voileOverlayCss,
    builder: (_) => ModaleArchivageAchats(
      element: element,
      nombre: nombre,
      messagesVerrou: messagesVerrou,
      bloque: bloque,
      conserves: conserves,
      message: message,
    ),
  );
}

class ModaleArchivageAchats extends StatelessWidget {
  const ModaleArchivageAchats({
    super.key,
    this.element,
    this.nombre,
    this.messagesVerrou = const [],
    this.bloque = false,
    this.conserves = 0,
    this.message,
  });

  /// La question en TEXTE, qui remplace celle construite sur [element] ou
  /// [nombre] — la prop `message` du composant de la vue.
  final String? message;

  final String? element;
  final int? nombre;
  final List<String> messagesVerrou;
  final bool bloque;
  final int conserves;

  /// `text-sm text-slate-500 leading-relaxed` — les modales sont hors de
  /// `<main>` : l'échelle DÉCLARÉE s'applique, pas la remappée.
  static const TextStyle _corps = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: Tailles.t14,
    height: AppLayout.interligneDetendu,
    color: Ardoise.c500,
  );

  @override
  Widget build(BuildContext context) {
    final gras = _corps.copyWith(
      fontWeight: FontWeight.bold,
      color: Ardoise.c500,
    );

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(false),
      },
      child: Focus(
        autofocus: true,
        child: Dialog(
          key: const Key('modale-archivage-achats'),
          backgroundColor: AppColors.neutre0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.roundedXl),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppLayout.modaleArchivageAchats,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg), // p-6
                    child: Column(
                      children: [
                        // `w-14 h-14 rounded-full bg-red-50` et sa corbeille.
                        Container(
                          width: AppSpacingLarge.p14,
                          height: AppSpacingLarge.p14,
                          decoration: const BoxDecoration(
                            color: PaletteMaitre.rouge50,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.delete_outline,
                            color: AppColors.erreur,
                            size: AppSpacing.lgPlus,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md), // mb-4
                        const Text(
                          'Confirmer la suppression',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: AppTextStyles.police,
                            fontSize: Tailles.t16,
                            fontWeight: FontWeight.bold,
                            color: Ardoise.c800,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs), // mb-2
                        if (bloque) ..._etatBloque() else ..._etatNominal(gras),
                      ],
                    ),
                  ),
                  // `flex justify-center gap-3 px-6 pb-6` : boutons CENTRÉS.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      0,
                      AppSpacing.lg,
                      AppSpacing.lg,
                    ),
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      children: [
                        OutlinedButton(
                          key: const Key('achats-archivage-annuler'),
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('Annuler'),
                        ),
                        // Le bouton DISPARAÎT quand tout est bloqué : il n'est
                        // pas grisé. Un bouton grisé invite à cliquer.
                        if (!bloque)
                          FilledButton(
                            key: const Key('achats-archivage-confirmer'),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.erreur,
                            ),
                            onPressed: () => Navigator.of(context).pop(true),
                            child: const Text('Supprimer définitivement'),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// ÉTAT 1 — plus rien n'est archivable.
  List<Widget> _etatBloque() => [
    const Text(
      'Archivage impossible',
      key: Key('achats-archivage-impossible'),
      textAlign: TextAlign.center,
      style: TextStyle(
        fontFamily: AppTextStyles.police,
        fontSize: Tailles.t14,
        fontWeight: FontWeight.w600,
        height: AppLayout.interligneDetendu,
        color: AppColors.erreur,
      ),
    ),
    const SizedBox(height: AppSpacing.xxs),
    for (final motif in messagesVerrou)
      Text(
        motif,
        textAlign: TextAlign.center,
        style: _corps.copyWith(color: Ardoise.c600),
      ),
    const SizedBox(height: AppSpacing.xs),
    const Text(
      "Retirez d'abord l'élément des opérations concernées, ou laissez-le en place : une carte historique reste lisible.",
      textAlign: TextAlign.center,
      style: _corps,
    ),
  ];

  /// ÉTATS 2 et 3 — la question, le rappel, puis (partiel) le décompte.
  ///
  /// Le nom de l'élément est rendu en gras comme dans la vue (`<strong>`).
  List<Widget> _etatNominal(TextStyle gras) => [
    if (message != null)
      Text(
        message!,
        key: const Key('achats-archivage-question'),
        textAlign: TextAlign.center,
        style: _corps,
      )
    else
      Text.rich(
        key: const Key('achats-archivage-question'),
        textAlign: TextAlign.center,
        TextSpan(
          style: _corps,
          children: nombre != null
              ? [
                  const TextSpan(text: 'Voulez-vous archiver les '),
                  TextSpan(text: '$nombre', style: gras),
                  const TextSpan(text: ' élément(s) sélectionnés ?'),
                ]
              : [
                  const TextSpan(text: 'Voulez-vous archiver '),
                  TextSpan(text: element, style: gras),
                  const TextSpan(text: ' ?'),
                ],
        ),
      ),
    const SizedBox(height: AppSpacing.xs),
    Text.rich(
      key: const Key('achats-archivage-rappel'),
      textAlign: TextAlign.center,
      TextSpan(
        style: _corps,
        children: [
          const TextSpan(text: "L'élément part aux "),
          TextSpan(text: 'archives', style: gras),
          const TextSpan(text: " et reste restaurable — rien n'est effacé."),
        ],
      ),
    ),
    if (conserves > 0) ...[
      const SizedBox(height: AppSpacing.xs),
      Text(
        '$conserves élément(s) seront conservés : ils sont engagés ailleurs.',
        key: const Key('achats-archivage-conserves'),
        textAlign: TextAlign.center,
        style: _corps.copyWith(color: AppColors.alerte),
      ),
    ],
    for (final motif in messagesVerrou) ...[
      const SizedBox(height: AppSpacing.unit),
      Text(
        motif,
        textAlign: TextAlign.center,
        style: _corps.copyWith(color: Ardoise.c600),
      ),
    ],
  ];
}
