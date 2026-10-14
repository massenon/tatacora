// Vue Blade maîtresse (PA-183) : pwa/bar/carte.blade.php
// Le partiel `modale-export` est celui des DEUX cartes : la carte du
// restaurant (pwa/restaurant/carte.blade.php) ouvre cette même modale depuis
// son bouton « Exporter » (09/10/2026) — un seul auteur, comme dans la vue.
// La dépense courante (pwa/depenses/depenses.blade.php, l.515-517) l'ouvre
// aussi depuis son bouton « Exporter » (09/10/2026) : le partiel est inclus par
// une troisième vue, et la modale Flutter reste UNE seule. Ce n'est ni un refus
// ni un contournement — le fichier sert réellement cette vue (même raison que
// pour le restaurant).
// L'écran Personnel & Paie (pwa/rh/paie.blade.php, l.1185-1188) l'ouvre aussi
// depuis son bouton « Exporter » (09/10/2026) : le partiel `modale-export` est
// inclus par une quatrième vue, et la modale Flutter reste UNE seule. Ce n'est
// ni un refus ni un contournement — le fichier sert réellement cette vue
// (même raison que pour le restaurant et la dépense courante).
// L'écran Hébergement (pwa/hebergement/hebergement.blade.php, l.701-706) l'ouvre
// aussi depuis « Générer & Télécharger » (09/10/2026) : cinquième vue qui
// inclut le partiel, une seule modale Flutter. Même raison, même précédent ;
// ce n'est pas un refus. Elle y passe son propre sous-titre (`sousTitre`).
// L'écran Fournisseurs & Achats (pwa/achats/achats.blade.php, l.523-535) l'ouvre
// aussi depuis son bouton « Exporter » (09/10/2026), un titre par onglet et le
// décompte des lignes en sous-titre : sixième vue qui inclut le partiel, une
// seule modale Flutter. Même raison, même précédent ; ce n'est pas un refus.
// L'écran Notifications (pwa/notifications/hub.blade.php, l.119 et l.622-625)
// l'ouvre aussi depuis son bouton « Exporter » (09/10/2026), un titre par
// onglet (« Exporter — File d'attente ») : septième vue qui inclut le partiel,
// une seule modale Flutter. Même raison, même précédent ; ce n'est pas un
// refus. Le choix PDF y est refusé avec son message, comme à la dépense.
// L'écran Véhicules & Locations (pwa/vehicules/locations.blade.php,
// l.845-851) l'ouvre aussi depuis son bouton « Exporter » (09/10/2026), avec le
// titre « Exporter le rapport Véhicules & Locations » : huitième vue qui inclut
// le partiel, une seule modale Flutter. Même raison, même précédent ; ce n'est
// pas un refus. Le choix PDF y est refusé avec son message, comme aux
// Notifications.
// L'écran Tourisme (pwa/tourisme/departs.blade.php, l.862-868) l'ouvre aussi
// depuis son bouton « Exporter » (09/10/2026), avec le titre « Exporter le
// rapport Tourisme » : neuvième vue qui inclut le partiel, une seule modale
// Flutter. Même raison, même précédent ; ce n'est pas un refus. Le choix PDF y
// est refusé avec son message, comme à Véhicules.
// L'écran Gestion des Stocks (pwa/stocks/stocks.blade.php, l.800-808) l'ouvre
// aussi depuis son bouton « Exporter » (09/10/2026), avec le titre « Exporter —
// Articles en stock » : dixième vue qui inclut le partiel, une seule modale
// Flutter. Même raison, même précédent ; ce n'est pas un refus. Le choix PDF y
// est refusé avec son message, le tableur (CSV) est présélectionné.
// Le pilotage consolidé de la vue d'accueil (livewire/accueil, l.873 et
// l.1748-1749) l'ouvre aussi depuis son bouton « Exporter » (12/10/2026), titre
// « Exporter le tableau de bord », la note des rapports en sous-titre : onzième
// vue qui inclut le partiel, une seule modale Flutter. Le PDF y est produit, le
// tableur refusé avec son message. Le chemin est écrit SANS son préfixe : ce
// fichier n'est pas un porteur de la vue d'accueil (piège 13).
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../shared_widgets/bouton_standard.dart';
import '../../../restaurant/presentation/widgets/coquille_modale_restaurant.dart';
import '../../../restaurant/presentation/widgets/textes_modale_restaurant.dart';

/// Les deux formats de la modale — `value="pdf"` / `value="excel"`.
enum FormatExport { pdf, excel }

/// La modale d'export — le partiel PARTAGÉ `modale-export` de la PWA, inclus
/// par le corps des cartes (l.885-889) derrière le bouton unique « Exporter »
/// (l.101-102).
///
/// Elle ne produit rien : elle rend le FORMAT choisi, et c'est l'écran
/// appelant qui compose le document — il porte le filtre, et PA-119 impose
/// qu'un export porte sur ce qui est affiché et le dise. `null` : annulé.
///
/// ## Le libellé est celui de la Directive, et le document ne le tient pas
///
/// « PDF Officiel A4 Imprimable — Document certifié avec en-tête et
/// signatures » est la formulation de `Directive.txt` §6 (l.411), reprise par
/// `lang/fr/pwa.php` et portée ici **au mot**, sur décision du 11/09/2026 :
/// ne pas s'écarter seul d'une directive du Product Owner. ⚠ Le PDF de la
/// carte, lui, porte l'en-tête de l'établissement mais NI signature NI
/// certification — ni ici ni dans la PWA. L'écart entre la promesse et le
/// document est inscrit au plan d'action (PA-192) pour arbitrage : corriger
/// les PDF ou la formulation. « Certifié » y est signalé comme risqué — au
/// Bénin, le mot se lit « certifié MECeF ».
///
/// ## Pas de `Radio` Material
///
/// Les deux choix sont des étiquettes bordées cliquables, comme la vue
/// (`<label class="flex items-center gap-3 p-3 rounded-lg border …">`), avec
/// l'indicateur du bouton radio à gauche.
///
/// ## PDF présélectionné PARTOUT (demande du PO du 14/10/2026)
///
/// Le paramètre `formatParDefaut` est RETIRÉ : sept écrans présélectionnaient
/// le tableur parce que leur PDF est refusé sur ce poste. Le PO veut la modale
/// de la vue, identique partout (`$formatExport = 'pdf'`) ; un PDF non produit
/// reste refusé APRÈS le clic, avec son message.
///
/// [aide] est OPTIONNELLE : une ligne d'aide propre à l'écran, sous les choix.
///
/// ## Une ligne dit que le tableur est un CSV
///
/// « Tableur Excel (.xlsx / .csv) » est le libellé de la vue ; aucune
/// bibliothèque XLSX n'est embarquée sur ce poste. [TextesExport.noteCsv] le
/// dit sous les choix, sur tous les écrans (14/10/2026).
///
/// [sousTitre] l'est aussi (09/10/2026) : le partiel de la vue le reçoit en
/// paramètre, avec « Choisissez le format d'exportation certifié » pour défaut
/// (`modale-export.blade.php` l.38 et l.40), et l'Hébergement y pose le sien —
/// « Le parc tel qu'il est affiché, filtres compris. ». Absent, la modale reste
/// ce qu'elle était pour les autres écrans.
Future<FormatExport?> choisirFormatExport(
  BuildContext context, {
  required String titre,
  String? aide,
  String sousTitre = TextesExport.sousTitre,
}) => showDialog<FormatExport>(
  context: context,
  barrierDismissible: true,
  barrierColor: AppColors.voileModale,
  builder: (_) => _ModaleExport(titre: titre, sousTitre: sousTitre, aide: aide),
);

/// Les mots de la vue — `lang/fr/pwa.php`, `export`.
abstract final class TextesExport {
  static const String bouton = 'Exporter';
  static const String sousTitre = "Choisissez le format d'exportation certifié";
  static const String format = 'Format du document';
  static const String pdfTitre = 'PDF Officiel A4 Imprimable';
  static const String pdfDetail =
      'Document certifié avec en-tête et signatures';
  static const String excelTitre = 'Tableur Excel (.xlsx / .csv)';
  static const String excelDetail = 'Données numériques brutes réutilisables';
  static const String annuler = 'Annuler';
  static const String generer = 'Générer & Télécharger';

  /// La ligne qui dit ce que produit réellement le choix « Tableur » sur ce
  /// poste (aucune bibliothèque XLSX embarquée) — demande du PO, 14/10/2026.
  static const String noteCsv =
      "Le tableur est enregistré en CSV (point-virgule), qu'Excel ouvre "
      'directement.';

  /// `carte_pwa.export_vide` — un export vide se REFUSE (PA-119).
  static const String vide =
      "La liste affichée est vide : il n'y a rien à exporter. Élargissez le filtre plutôt que de produire un document que l'on croirait complet.";
}

class _ModaleExport extends StatefulWidget {
  const _ModaleExport({
    required this.titre,
    required this.sousTitre,
    required this.aide,
  });

  final String titre;
  final String sousTitre;
  final String? aide;

  @override
  State<_ModaleExport> createState() => _ModaleExportState();
}

class _ModaleExportState extends State<_ModaleExport> {
  // `public string $formatExport = 'pdf';` — `EcranDeCarte` l.183.
  FormatExport _format = FormatExport.pdf;

  @override
  Widget build(BuildContext context) {
    return CoquilleModaleRestaurant(
      cle: const Key('modale-export-carte'),
      titre: widget.titre,
      sousTitre: widget.sousTitre,
      largeur: AppLayout.modaleExportPwa,
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const EtiquetteChampRestaurant(texte: TextesExport.format),
          _Choix(
            cle: const Key('export-format-pdf'),
            titre: TextesExport.pdfTitre,
            detail: TextesExport.pdfDetail,
            choisi: _format == FormatExport.pdf,
            onChoix: () => setState(() => _format = FormatExport.pdf),
          ),
          const SizedBox(height: AppSpacing.xs),
          _Choix(
            cle: const Key('export-format-excel'),
            titre: TextesExport.excelTitre,
            detail: TextesExport.excelDetail,
            choisi: _format == FormatExport.excel,
            onChoix: () => setState(() => _format = FormatExport.excel),
          ),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            TextesExport.noteCsv,
            key: Key('export-note-csv'),
            style: TextesModaleRestaurant.aide,
          ),
          if (widget.aide != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              widget.aide!,
              key: const Key('export-aide'),
              style: TextesModaleRestaurant.aide,
            ),
          ],
        ],
      ),
      // Pied du partiel : `px-4 py-2 rounded-lg border border-slate-300`
      // (« Annuler ») puis `bg-[var(--navy)] text-white font-semibold`
      // (« Générer & Télécharger », fond sombre) — le bouton standard
      // (14/10/2026). « Annuler » est en `px-4` dans la vue : variante
      // secondaire à 14 px, écart de 2 px assumé pour garder UN bouton.
      actions: [
        BoutonStandard(
          key: const Key('export-annuler'),
          libelle: TextesExport.annuler,
          // Hors `<main>` : `text-[13px]` vaut 13 px dans une modale.
          taillePolice: Tailles.t13,
          onPressed: () => Navigator.of(context).pop(),
        ),
        BoutonStandard(
          key: const Key('export-generer'),
          variante: VarianteBouton.primaire,
          taillePolice: Tailles.t13,
          libelle: TextesExport.generer,
          onPressed: () => Navigator.of(context).pop(_format),
        ),
      ],
    );
  }
}

/// Un choix de format — `flex items-center gap-3 p-3 rounded-lg border
/// border-slate-200 hover:bg-slate-50`, titre en gras, détail en dessous.
class _Choix extends StatelessWidget {
  const _Choix({
    required this.cle,
    required this.titre,
    required this.detail,
    required this.choisi,
    required this.onChoix,
  });

  final Key cle;
  final String titre;
  final String detail;
  final bool choisi;
  final VoidCallback onChoix;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: choisi,
      child: InkWell(
        key: cle,
        onTap: onChoix,
        borderRadius: BorderRadius.circular(AppRadius.roundedLg),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            border: Border.all(color: choisi ? AppColors.navy : Ardoise.c200),
            borderRadius: BorderRadius.circular(AppRadius.roundedLg),
          ),
          child: Row(
            children: [
              Icon(
                choisi ? Icons.radio_button_checked : Icons.radio_button_off,
                // `<input type="radio">` : le navigateur le dessine à sa
                // taille (~13 px). Le jeton d'icône de champ en tient lieu.
                size: AppLayout.iconeChamp,
                color: choisi ? AppColors.navy : Ardoise.c400,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titre,
                      style: TextesModaleRestaurant.corps.copyWith(
                        fontWeight: FontWeight.w700,
                        color: Ardoise.c800,
                      ),
                    ),
                    Text(detail, style: TextesModaleRestaurant.aide),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
