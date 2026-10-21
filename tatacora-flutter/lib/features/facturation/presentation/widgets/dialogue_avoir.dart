// Vue Blade maîtresse (PA-183) : pwa/facturation/facturation.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart' show sessionProvider;
import '../../../../core/format/formats.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../caisse/presentation/widgets/modale_ouverture_caisse.dart'
    show BoutonActionCaisse, BoutonAnnulerCaisse, ChampMontantCaisse;
import '../../../restaurant/presentation/widgets/coquille_modale_restaurant.dart';
import '../../domain/entities/piece_facturation.dart';
import '../providers_facturation.dart';

/// Les mots de la modale « Émettre un avoir » — `lang/fr/facturation_pwa.php`
/// (`avoir_*`) et `lang/fr/facturation.php` (`avoir_montant_excessif`).
abstract final class TextesAvoir {
  static const String titre = 'Émettre un avoir';
  static const String sousTitre =
      "La facture d'origine reste inchangée : l'avoir la neutralise, en tout ou partie. Les deux pièces coexistent.";
  static const String facture = 'Facture';
  static const String montant = "Montant de l'avoir (FCFA)";
  static const String motif = "Motif de l'avoir";
  static const String motifInvite =
      'ex. Prestation non fournie — nuitée annulée';
  static const String valider = "Émettre l'avoir";
  static const String montantExcessif =
      "Le montant de l'avoir ne peut pas dépasser celui de la facture.";

  /// `avoir_montant_aide` — [plafond] est DÉJÀ mis en forme (« 2 000 FCFA »).
  static String aide(String plafond) =>
      'Au plus le montant TTC de la facture — $plafond.';

  /// `avoir_emis` — [montant] déjà mis en forme.
  static String emis(String montant, String numero) =>
      'Avoir de $montant émis sur la facture $numero.';

  static const String montantObligatoire =
      "Le montant de l'avoir est obligatoire.";
  static const String montantIllisible =
      "Le montant de l'avoir doit être un nombre entier de francs.";
  static const String montantNul =
      "Le montant de l'avoir doit être supérieur à zéro.";
  static const String motifObligatoire = "Le motif de l'avoir est obligatoire.";
  static const String motifTropLong =
      "Le motif de l'avoir ne peut pas dépasser 255 caractères.";

  /// ÉCART DU POSTE, dit à l'écran et au refus : la vue accepte un avoir
  /// PARTIEL (`emettreAvoir($facture, $montant, $motif)`), mais le poste ne sait
  /// l'envoyer au serveur que sous la forme de l'annulation de la facture —
  /// `GestionnaireFactures` (modification `statut: annulee` + `motif`) émet
  /// « l'avoir du TTC entier » et refuse tout autre champ. Un avoir partiel
  /// écrit ici ne partirait jamais : le reste dû du poste ne rejoindrait plus
  /// celui du serveur, sans qu'aucun écran ne le dise (PA-59/60/61).
  static const String partielRefuse =
      'Sur ce poste, un avoir porte le montant TTC entier de la facture : '
      "l'avoir partiel n'est pas encore transmissible au serveur. Saisissez le "
      'montant TTC pour annuler la facture, ou émettez cet avoir partiel depuis '
      'la PWA.';
}

/// La modale **« Émettre un avoir »** (RG-03) — la seule façon de corriger une
/// facture. Rend `true` quand l'avoir a été émis.
///
/// ## Pourquoi cette fonction existe séparément
///
/// Elle vivait dans le widget de ligne, remplacé le 21/08/2026 par le tableau
/// du maître. **Le remplacement l'a emportée**, et l'écran a passé quelques
/// minutes sans aucun moyen d'annuler une facture — un défaut de la famille
/// PA-81 : un retrait vérifié sur son rôle d'affichage, pas sur l'ensemble de
/// ce que le code retiré faisait. Extraite ici, elle ne dépend plus d'une mise
/// en page.
///
/// ## Les mots sont ceux de la vue, et le geste aussi
///
/// Titre, sous-titre, rappel « Facture … — TTC », « Montant de l'avoir
/// (FCFA) » avec son aide « Au plus le montant TTC de la facture — … », « Motif
/// de l'avoir », « Émettre l'avoir ». Les refus se disent SOUS le champ qu'ils
/// visent (`@error('avoirMontant')`), la saisie reste. Rien n'est effacé : la
/// facture reste au registre, et l'avoir porte son propre numéro (propriété
/// n°4 du moteur, PA-99).
///
/// ## Un seul écart : le montant partiel (voir [TextesAvoir.partielRefuse])
///
/// Il est REFUSÉ et nommé, jamais écrit à part. Le montant TTC entier émet
/// l'avoir qui neutralise la facture, comme `annuler`.
///
/// ## Le motif est obligatoire
///
/// Une annulation sans raison est indistinguable d'une erreur de manipulation,
/// et c'est le seul élément qu'un contrôle pourra lire des années plus tard.
Future<bool> emettreUnAvoir(
  BuildContext context,
  PieceFacturation piece,
) async {
  final emis = await showDialog<bool>(
    context: context,
    builder: (_) => ModaleAvoir(piece: piece),
  );
  return emis ?? false;
}

class ModaleAvoir extends ConsumerStatefulWidget {
  const ModaleAvoir({required this.piece, super.key});

  final PieceFacturation piece;

  @override
  ConsumerState<ModaleAvoir> createState() => _EtatModaleAvoir();
}

class _EtatModaleAvoir extends ConsumerState<ModaleAvoir> {
  final _montant = TextEditingController();
  final _motif = TextEditingController();
  String? _refusMontant;
  String? _refusMotif;
  String? _refus;
  bool _envoi = false;

  @override
  void dispose() {
    _montant.dispose();
    _motif.dispose();
    super.dispose();
  }

  /// Les validations de la vue, dans son ordre (`required|numeric|gt:0|max:TTC`
  /// puis `required|string|max:255`), puis l'écart du poste.
  bool _valider() {
    final ttc = widget.piece.montantTotal;
    String? refusMontant;
    final brut = _montant.text.trim();
    if (brut.isEmpty) {
      refusMontant = TextesAvoir.montantObligatoire;
    } else {
      final saisi = int.tryParse(brut);
      if (saisi == null) {
        refusMontant = TextesAvoir.montantIllisible;
      } else if (saisi <= 0) {
        refusMontant = TextesAvoir.montantNul;
      } else if (saisi > ttc) {
        refusMontant = TextesAvoir.montantExcessif;
      } else if (saisi < ttc) {
        refusMontant = TextesAvoir.partielRefuse;
      }
    }

    final motif = _motif.text.trim();
    String? refusMotif;
    if (motif.isEmpty) {
      refusMotif = TextesAvoir.motifObligatoire;
    } else if (motif.length > 255) {
      refusMotif = TextesAvoir.motifTropLong;
    }

    setState(() {
      _refusMontant = refusMontant;
      _refusMotif = refusMotif;
      _refus = null;
    });
    return refusMontant == null && refusMotif == null;
  }

  Future<void> _emettre() async {
    if (!_valider()) return;
    setState(() => _envoi = true);
    final navigateur = Navigator.of(context);
    final messages = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(facturerProvider)
          .annuler(
            widget.piece.id,
            _motif.text.trim(),
            auteurId: ref.read(sessionProvider)?.utilisateurId,
          );
      rafraichirFacturation(ref);
      navigateur.pop(true);
      messages.showSnackBar(
        SnackBar(
          content: Text(
            TextesAvoir.emis(
              formaterFcfa(widget.piece.montantTotal),
              widget.piece.numero,
            ),
          ),
        ),
      );
    } on Object catch (e) {
      // Le refus du service est dit DANS la modale, saisie intacte : une
      // annulation qui n'a pas eu lieu ne doit jamais ressembler à une réussie.
      if (mounted) setState(() => _refus = '$e');
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  static const TextStyle _etiquette = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: Tailles.t15,
    fontWeight: FontWeight.w600,
    color: Ardoise.c700,
  );

  Widget _libelle(String texte) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
    child: Text.rich(
      TextSpan(
        style: _etiquette,
        children: [
          TextSpan(text: texte),
          const TextSpan(
            text: ' *',
            style: TextStyle(color: PaletteMaitre.rouge500),
          ),
        ],
      ),
    ),
  );

  Widget _erreur(String? message, Key cle) => message == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: AppSpacing.unit),
          child: Text(
            message,
            key: cle,
            style: const TextStyle(
              fontFamily: AppTextStyles.police,
              fontSize: Tailles.t12,
              color: PaletteMaitre.rouge600,
            ),
          ),
        );

  @override
  Widget build(BuildContext context) {
    final bordure = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      borderSide: const BorderSide(color: Ardoise.c200),
    );

    return CoquilleModaleRestaurant(
      cle: const Key('facturation-modale-avoir'),
      titre: TextesAvoir.titre,
      sousTitre: TextesAvoir.sousTitre,
      largeur: AppLayout.modaleAvoirFacture,
      refus: _refus,
      cleRefus: const Key('facturation-avoir-refus'),
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // `rounded-lg bg-slate-50 px-3 py-2 text-[13px] text-slate-600` : la
          // facture visée et son TTC — le plafond de l'avoir.
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: Ardoise.c50,
              borderRadius: BorderRadius.circular(AppRadius.roundedLg),
            ),
            child: Text.rich(
              TextSpan(
                style: const TextStyle(
                  fontFamily: AppTextStyles.police,
                  fontSize: Tailles.t13,
                  color: Ardoise.c600,
                ),
                children: [
                  const TextSpan(
                    text: TextesAvoir.facture,
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(text: ' ${widget.piece.numero}'),
                  TextSpan(
                    text: ' — ${formaterFcfa(widget.piece.montantTotal)}',
                  ),
                ],
              ),
              key: const Key('facturation-avoir-facture'),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _libelle(TextesAvoir.montant),
          ChampMontantCaisse(
            cle: const Key('facturation-montant-avoir'),
            controleur: _montant,
          ),
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.unit),
            child: Text(
              TextesAvoir.aide(formaterFcfa(widget.piece.montantTotal)),
              key: const Key('facturation-avoir-aide'),
              style: const TextStyle(
                fontFamily: AppTextStyles.police,
                fontSize: Tailles.t12,
                color: Ardoise.c400,
              ),
            ),
          ),
          _erreur(_refusMontant, const Key('facturation-avoir-erreur-montant')),
          const SizedBox(height: AppSpacing.md),
          _libelle(TextesAvoir.motif),
          TextField(
            key: const Key('facturation-motif-avoir'),
            controller: _motif,
            style: const TextStyle(
              fontFamily: AppTextStyles.police,
              fontSize: Tailles.t13,
            ),
            decoration: InputDecoration(
              isDense: true,
              hintText: TextesAvoir.motifInvite,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              enabledBorder: bordure,
              border: bordure,
              focusedBorder: bordure.copyWith(
                borderSide: const BorderSide(color: AppColors.gold),
              ),
            ),
          ),
          _erreur(_refusMotif, const Key('facturation-avoir-erreur-motif')),
        ],
      ),
      actions: [
        BoutonAnnulerCaisse(
          onPressed: _envoi ? null : () => Navigator.of(context).pop(false),
        ),
        BoutonActionCaisse(
          cle: const Key('facturation-confirmer-avoir'),
          libelle: TextesAvoir.valider,
          onPressed: _envoi ? null : _emettre,
        ),
      ],
    );
  }
}
