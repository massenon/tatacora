// Vue Blade maîtresse (PA-183) : pwa/achats/approvisionnement.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../depenses/domain/categories_depense.dart';
import '../../data/achats_api.dart';
import '../../domain/entities/reglement_fournisseur.dart';
import '../../domain/messages_reglement.dart';
import '../../domain/regles_reglement.dart';
import '../providers_achats.dart';
import 'coquille_modale_achats.dart';

/// Ce que la modale rend à son appelant : le règlement écrit, et la SAISIE telle
/// que le serveur l'a reçue (le message de succès la recopie brute, D260).
final class ReglementSaisi {
  const ReglementSaisi({
    required this.reglement,
    required this.montantSaisi,
    required this.fournisseurNom,
  });

  final ReglementFournisseur reglement;
  final String montantSaisi;
  final String fournisseurNom;
}

/// La modale **« Régler »** — `approvisionnement.blade.php` l.574-608, ouverte
/// par le bouton de la ligne d'une commande (`ouvrirFormulaireReglement`).
///
/// ## Ce qu'elle porte, dans l'ordre de la vue
///
/// Le titre « Régler — [fournisseur] » et le sous-titre « Commande [id] — reste
/// dû [montant] », la saisie du montant (proposé : le reste dû), la liste de
/// trésorerie (Caisse, Mobile Money, Banque), puis « Annuler » et « Enregistrer
/// le règlement ». Largeur `420px`.
///
/// ## Le sous-titre suit le CHAMP, pas le reste dû (D261)
///
/// La vue écrit `MontantFcfa::format($regMontant)` : la valeur courante du champ
/// côté serveur, qui est le reste dû À L'OUVERTURE et devient la dernière saisie
/// ENVOYÉE après un refus. Un opérateur qui tape 9 000 sur une commande dont il
/// reste 2 500 lit « reste dû 9 000 FCFA » sous le message qui dit 2 500.00. Le
/// poste réplique ce comportement (règle du PO : le serveur fait foi) et le
/// consigne ; une valeur qui ne se lit pas ne le met pas à jour (le serveur,
/// lui, plante au rendu — D259).
///
/// ## Un refus s'affiche SOUS le champ montant
///
/// Quel que soit le refus du service (sur-règlement, montant nul, trésorerie
/// inconnue) : `addError('regMontant', …)`. La modale reste ouverte — un refus
/// qu'on masquerait en la fermant ferait croire à un paiement qui n'a pas eu
/// lieu (PA-59/60/61). Un droit manquant, lui, n'a pas de champ : il s'affiche en
/// tête de la modale.
Future<ReglementSaisi?> ouvrirModaleReglement(
  BuildContext context, {
  required String commandeId,
  required OuvertureReglement ouverture,
}) {
  return showDialog<ReglementSaisi>(
    context: context,
    builder: (_) =>
        _ModaleReglement(commandeId: commandeId, ouverture: ouverture),
  );
}

class _ModaleReglement extends ConsumerStatefulWidget {
  const _ModaleReglement({required this.commandeId, required this.ouverture});

  final String commandeId;
  final OuvertureReglement ouverture;

  @override
  ConsumerState<_ModaleReglement> createState() => _ModaleReglementState();
}

class _ModaleReglementState extends ConsumerState<_ModaleReglement> {
  late final TextEditingController _montant;
  late TresorerieDepense _tresorerie;

  /// La valeur du champ telle que le serveur la connaît (voir l'en-tête).
  late String _montantConnu;

  bool _envoiEnCours = false;
  String? _erreurMontant;
  String? _refus;

  @override
  void initState() {
    super.initState();
    // Le reste dû, à deux décimales comme `bcsub` (« 4000.00 »).
    _montantConnu = chaineDuReglement(widget.ouverture.resteDuCentimes);
    _montant = TextEditingController(text: _montantConnu);
    _tresorerie = widget.ouverture.tresorerieDeDepart;
  }

  @override
  void dispose() {
    _montant.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    final saisie = _montant.text;
    setState(() {
      _envoiEnCours = true;
      _erreurMontant = null;
      _refus = null;
      // La saisie PART au serveur avec l'action : le sous-titre la reflète au
      // retour, même refusée.
      if (montantAffichableDuChamp(saisie) != null) _montantConnu = saisie;
    });

    final resultat = await ref
        .read(achatsApiProvider)
        .reglerCommande(
          commandeId: widget.commandeId,
          montant: saisie,
          tresorerie: _tresorerie.code,
        );
    if (!mounted) return;

    switch (resultat) {
      case AchatsRecu(:final donnees):
        Navigator.of(context).pop(
          ReglementSaisi(
            reglement: donnees,
            montantSaisi: saisie,
            fournisseurNom: widget.ouverture.fournisseurNom,
          ),
        );
      case AchatsRefuse(:final motif, :final erreurs):
        setState(() {
          _envoiEnCours = false;
          final surLeChamp = erreurs[ChampReglement.montant.propriete];
          _erreurMontant = surLeChamp;
          // Une erreur de commande ou de trésorerie n'a PAS de place dans la vue
          // (seul `@error('regMontant')` s'y trouve) : le poste la dit en tête
          // de la modale plutôt que de se taire (écart nommé, D259).
          _refus = surLeChamp == null ? motif : null;
        });
      case AchatsInjoignable():
        setState(() {
          _envoiEnCours = false;
          // Jamais produite (la base est locale) ; le type la garde.
          _refus =
              'La base du poste n’a pas répondu : rien n’a été enregistré, '
              'ni le règlement ni sa pièce comptable.';
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;
    final reste = montantAffichableDuChamp(_montantConnu) ?? '';

    return CoquilleModaleAchats(
      cle: const Key('modale-reglement'),
      titre: MessagesReglement.titreModale(widget.ouverture.fournisseurNom),
      sousTitre: MessagesReglement.sousTitreModale(widget.commandeId, reste),
      libelleValidation: MessagesReglement.libelleValider,
      cleValidation: const Key('reglement-valider'),
      envoiEnCours: _envoiEnCours,
      onValider: _valider,
      refus: _refus,
      cleRefus: const Key('reglement-refus'),
      largeur: AppLayout.modaleReglementAchats,
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            MessagesReglement.libelleMontant,
            style: textes.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: AppColors.neutre500,
            ),
          ),
          const SizedBox(height: AppSpacing.unit),
          TextField(
            key: const Key('reglement-montant'),
            controller: _montant,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          if (_erreurMontant != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.unit),
              child: Text(
                _erreurMontant!,
                key: const Key('reglement-erreur-montant'),
                style: textes.labelMedium?.copyWith(color: AppColors.erreur),
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            MessagesReglement.libelleTresorerie,
            style: textes.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: AppColors.neutre500,
            ),
          ),
          const SizedBox(height: AppSpacing.unit),
          DropdownButtonFormField<TresorerieDepense>(
            key: const Key('reglement-tresorerie'),
            initialValue: _tresorerie,
            isExpanded: true,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
            ),
            items: [
              for (final t in TresorerieDepense.values)
                DropdownMenuItem(
                  value: t,
                  child: Text(libelleTresorerieDuReglement(t)),
                ),
            ],
            onChanged: (t) {
              if (t != null) setState(() => _tresorerie = t);
            },
          ),
        ],
      ),
    );
  }
}
