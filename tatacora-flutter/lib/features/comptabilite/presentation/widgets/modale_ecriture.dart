// Vue Blade maîtresse (PA-183) : pwa/comptabilite/hub.blade.php
// (la modale « Passer écriture », `etatFormulaire === 'piece'`).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/format/formats.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../shared_widgets/bouton_standard.dart';
import '../../../transverse/presentation/widgets/briques_transverses.dart';
import '../../data/moteur_comptable.dart';
import '../../domain/entities/comptabilite.dart';
import '../../domain/montant_comptable.dart';
import '../../domain/refus_comptable.dart';
import '../providers_comptabilite.dart';
import '../providers_consultation_comptable.dart';

/// Les textes de la modale « Passer une écriture » — ceux de la modale de la
/// vue (`comptabilite_pwa.*`), sauf le titre et les messages de succès, dictés
/// par le Product Owner le 14/10/2026.
abstract final class TextesModaleEcriture {
  /// Titre dicté par le PO (la vue écrit « Passer écriture »).
  static const String titre = 'Passer une écriture';
  static const String introDetail =
      'Journal, date, libellé de pièce et lignes Compte / Libellé / Centre / '
      'Débit / Crédit. Contrôles appliqués à l’enregistrement : débit = crédit '
      '(une pièce déséquilibrée n’est jamais enregistrée), date dans un '
      'exercice ouvert, compte existant au plan, et centre analytique '
      'obligatoire sur les classes 6, 7 et 8.';
  static const String champJournal = 'Journal';
  static const String champDate = 'Date';
  static const String champLibellePiece = 'Libellé de la pièce';
  static const String champLibellePieceInvite =
      'Ex. Facture FAC-2026-0142 — séjour KORA';
  static const String choisir = 'Choisir…';
  static const String colCompte = 'Compte';
  static const String colLibelleLigne = 'Libellé de la ligne';
  static const String colCentre = 'Centre';
  static const String colDebit = 'Débit';
  static const String colCredit = 'Crédit';
  static const String colEcart = 'Écart';

  /// `comptabilite_pwa.piece_ecart` : « Écart de :montant. » — UNE phrase.
  static String pieceEcart(String montant) => 'Écart de $montant.';
  static const String centreDuCompte = '—';
  static const String tiret = '—';
  static const String totaux = 'Totaux';
  static const String pieceEquilibree = 'Pièce équilibrée.';
  static const String ligneAjouter = 'Ajouter une ligne';
  static const String ligneRetirer = 'Retirer la ligne';
  static const String immuabiliteTitre = 'Validation = immuabilité.';
  static const String immuabiliteDetail =
      'Une écriture validée ne peut plus être ni modifiée ni supprimée. Le '
      'brouillon reste corrigeable, mais il bloque la clôture tant qu’il '
      'n’est pas tranché.';
  static const String annuler = 'Annuler';
  static const String enregistrerBrouillon = 'Enregistrer en brouillon';
  static const String enregistrerValider = 'Enregistrer et valider';
  static const String aucunCompte = 'Aucun compte ne correspond.';

  /// Les refus de saisie, avant le moteur.
  static const String journalRequis = 'Choisissez un journal.';
  static const String libelleRequis = 'Le libellé de la pièce est obligatoire.';
  static String compteRequis(int position) =>
      'Ligne $position : choisissez un compte du plan.';
  static String montantRequis(int position) =>
      'Ligne $position : un montant est requis, au débit ou au crédit.';
  static String debitEtCredit(int position) =>
      'Ligne $position : le débit et le crédit ne peuvent pas être renseignés '
      'en même temps.';
  static const String echecInattendu =
      "L'écriture n'a pas pu être enregistrée sur ce poste. Rien n'a été "
      'écrit.';

  /// Les messages de succès dictés par le PO (14/10/2026).
  static const String enregistree = 'Écriture enregistrée sur ce poste.';
  static const String enregistreeValidee =
      'Écriture enregistrée sur ce poste et validée.';
}

/// Les proportions des colonnes de la grille — `width:28%`, `18%`, `14%`,
/// `14%` de la vue, le libellé prenant le reste (26 %).
abstract final class _Flex {
  static const int compte = 28;
  static const int libelle = 26;
  static const int centre = 18;
  static const int montant = 14;
}

/// Le nombre maximal de comptes proposés à la frappe : la liste se resserre en
/// tapant, elle ne pagine pas.
const int _comptesProposes = 40;

/// Ouvre la modale « Passer une écriture » et DIT le résultat (SnackBar). Le
/// journal du hub est relu à chaque enregistrement réussi.
Future<void> ouvrirModaleEcriture(
  BuildContext context, {
  required List<JournalComptable> journaux,
  required List<CentreDeCout> centres,
}) async {
  final validee = await showDialog<bool>(
    context: context,
    builder: (_) => ModaleEcriture(journaux: journaux, centres: centres),
  );
  if (validee == null || !context.mounted) return;
  direTransverse(
    context,
    validee
        ? TextesModaleEcriture.enregistreeValidee
        : TextesModaleEcriture.enregistree,
    cle: const Key('compta-ecriture-enregistree'),
  );
}

/// La modale « Passer une écriture » (PO, 14/10/2026) — la modale de la vue
/// (`comptabilite/hub`, `etatFormulaire === 'piece'`), écrite par le moteur
/// LOCAL : « Enregistrer en brouillon » appelle [MoteurComptable.passer],
/// « Enregistrer et valider » [MoteurComptable.passerEtValider].
///
/// Les deux boutons d'enregistrement restent grisés tant que la pièce compte
/// moins de deux lignes renseignées, ou que débit et crédit diffèrent (ou
/// valent zéro). Tout refus du moteur est DIT dans la modale, à sa phrase :
/// rien n'est écrit (une transaction), et la saisie reste à corriger.
///
/// Écart assumé : la vue pose aussi un champ « Centre » par ligne ; il est
/// rendu ici, parce que le moteur du poste exige un centre sur CHAQUE ligne
/// (explicite, ou centre par défaut du compte) — sans lui, la plupart des
/// pièces seraient refusées.
class ModaleEcriture extends ConsumerStatefulWidget {
  const ModaleEcriture({
    required this.journaux,
    required this.centres,
    super.key,
  });

  final List<JournalComptable> journaux;
  final List<CentreDeCout> centres;

  @override
  ConsumerState<ModaleEcriture> createState() => _ModaleEcritureState();
}

/// Une ligne de la grille, avec ses contrôleurs : elle survit au retrait d'une
/// autre ligne (clé stable [numero]).
final class _LigneSaisie {
  _LigneSaisie(this.numero);

  final int numero;
  final compte = TextEditingController();
  final focusCompte = FocusNode();
  final libelle = TextEditingController();
  final debit = TextEditingController();
  final credit = TextEditingController();
  CompteDuPlan? compteChoisi;
  String? centreId;

  int get debitCentimes => _centimes(debit.text);
  int get creditCentimes => _centimes(credit.text);

  /// Une ligne RENSEIGNÉE : un compte choisi ou un montant saisi.
  bool get renseignee =>
      compteChoisi != null || debitCentimes > 0 || creditCentimes > 0;

  /// Des francs ENTIERS (`step="1"` de la vue), en centimes.
  static int _centimes(String texte) => (int.tryParse(texte) ?? 0) * 100;

  void liberer() {
    compte.dispose();
    focusCompte.dispose();
    libelle.dispose();
    debit.dispose();
    credit.dispose();
  }
}

class _ModaleEcritureState extends ConsumerState<ModaleEcriture> {
  String? _journal;
  String _date = formaterDateIso(DateTime.now());
  final _libelle = TextEditingController();
  final List<_LigneSaisie> _lignes = [];
  int _prochain = 0;
  String? _erreur;
  bool _envoi = false;

  @override
  void initState() {
    super.initState();
    // Deux lignes au départ, comme la vue : une pièce en a au moins deux.
    _ajouterLigne();
    _ajouterLigne();
  }

  @override
  void dispose() {
    _libelle.dispose();
    for (final l in _lignes) {
      l.liberer();
    }
    super.dispose();
  }

  void _ajouterLigne() => _lignes.add(_LigneSaisie(_prochain++));

  void _retirerLigne(_LigneSaisie ligne) => setState(() {
    _lignes.remove(ligne);
    // Libéré APRÈS le retrait du cadre : le champ démonté ne le lit plus.
    WidgetsBinding.instance.addPostFrameCallback((_) => ligne.liberer());
  });

  int get _totalDebit => _lignes.fold(0, (s, l) => s + l.debitCentimes);
  int get _totalCredit => _lignes.fold(0, (s, l) => s + l.creditCentimes);
  int get _renseignees => _lignes.where((l) => l.renseignee).length;

  /// La règle des deux boutons d'enregistrement (PO, 14/10/2026).
  bool get _enregistrable =>
      !_envoi &&
      _renseignees >= 2 &&
      _totalDebit == _totalCredit &&
      _totalDebit > 0;

  /// Les refus de saisie que l'écran peut dire avant le moteur, dans l'ordre
  /// des champs. `null` : la demande part au moteur.
  String? _refusDeSaisie() {
    if (_journal == null) return TextesModaleEcriture.journalRequis;
    if (_libelle.text.trim().isEmpty) {
      return TextesModaleEcriture.libelleRequis;
    }
    for (final (i, l) in _lignes.where((l) => l.renseignee).indexed) {
      final position = i + 1;
      if (l.compteChoisi == null) {
        return TextesModaleEcriture.compteRequis(position);
      }
      if (l.debitCentimes > 0 && l.creditCentimes > 0) {
        return TextesModaleEcriture.debitEtCredit(position);
      }
      if (l.debitCentimes == 0 && l.creditCentimes == 0) {
        return TextesModaleEcriture.montantRequis(position);
      }
    }
    return null;
  }

  Future<void> _enregistrer({required bool valider}) async {
    final refus = _refusDeSaisie();
    if (refus != null) {
      setState(() => _erreur = refus);
      return;
    }
    setState(() {
      _envoi = true;
      _erreur = null;
    });

    final demande = DemandePiece(
      journal: _journal!,
      date: _date,
      libelle: _libelle.text.trim(),
      lignes: [
        for (final l in _lignes.where((l) => l.renseignee))
          LigneDemandee(
            compte: l.compteChoisi!.numero,
            debitCentimes: l.debitCentimes,
            creditCentimes: l.creditCentimes,
            libelle: l.libelle.text.trim().isEmpty
                ? null
                : l.libelle.text.trim(),
            centreId: l.centreId,
          ),
      ],
    );
    final auteurId = ref.read(sessionProvider)?.utilisateurId ?? '';

    try {
      final moteur = await ref.read(moteurComptableProvider.future);
      if (valider) {
        await moteur.passerEtValider(demande, auteurId: auteurId);
      } else {
        await moteur.passer(demande, auteurId: auteurId);
      }
    } on RefusComptable catch (e) {
      if (!mounted) return;
      setState(() {
        _envoi = false;
        _erreur = e.message;
      });
      return;
    } on Object {
      // Aucune exception ne doit faire tomber la modale : le moteur écrit en
      // UNE transaction, donc rien n'a été écrit.
      if (!mounted) return;
      setState(() {
        _envoi = false;
        _erreur = TextesModaleEcriture.echecInattendu;
      });
      return;
    }

    // Le journal et la balance du hub relisent la base.
    ref.invalidate(donneesComptabiliteProvider);
    if (mounted) Navigator.of(context).pop(valider);
  }

  Future<void> _choisirDate() async {
    final actuelle = DateTime.tryParse(_date) ?? DateTime.now();
    final choisie = await showDatePicker(
      context: context,
      initialDate: actuelle,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (choisie == null) return;
    setState(() => _date = formaterDateIso(choisie));
  }

  @override
  Widget build(BuildContext context) {
    final comptes = ref.watch(comptesImputablesProvider).value ?? const [];
    final ecart = _totalDebit - _totalCredit;

    return Dialog(
      key: const Key('modale-ecriture'),
      backgroundColor: AppColors.neutre0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.roundedXl),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: AppLayout.modaleEcriture,
          maxHeight: AppLayout.hauteurMaxModaleEcriture,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // L'en-tête : le titre, et un filet.
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.mdPlus,
                vertical: AppSpacing.md,
              ),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Ardoise.c200)),
              ),
              child: Text(
                TextesModaleEcriture.titre,
                style: styleTransverse(
                  Tailles.t16,
                  poids: FontWeight.bold,
                  couleur: AppColors.navy,
                ),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.mdPlus),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_erreur != null) ...[
                      EncadreTransverse(
                        key: const Key('modale-ecriture-refus'),
                        fond: PaletteMaitre.rouge50,
                        bordure: PaletteMaitre.rouge200,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: AppSpacing.xs,
                        ),
                        child: Text(
                          _erreur!,
                          style: styleTransverse(
                            Tailles.t13,
                            poids: FontWeight.w600,
                            couleur: AppColors.erreur,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    EncadreTransverse(
                      fond: Ardoise.c50,
                      bordure: Ardoise.c200,
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      child: Text(
                        TextesModaleEcriture.introDetail,
                        style: styleTransverse(
                          Tailles.t12,
                          couleur: Ardoise.c700,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _enTete(),
                    const SizedBox(height: AppSpacing.md),
                    _grille(comptes, ecart),
                    const SizedBox(height: AppSpacing.sm),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: BoutonStandard(
                        key: const Key('modale-ecriture-ajouter-ligne'),
                        libelle: '+ ${TextesModaleEcriture.ligneAjouter}',
                        compact: true,
                        onPressed: _envoi
                            ? null
                            : () => setState(_ajouterLigne),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    EncadreTransverse(
                      fond: PaletteMaitre.ambre50,
                      bordure: PaletteMaitre.ambre200,
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '${TextesModaleEcriture.immuabiliteTitre} ',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const TextSpan(
                              text: TextesModaleEcriture.immuabiliteDetail,
                            ),
                          ],
                        ),
                        style: styleTransverse(
                          Tailles.t12,
                          couleur: PaletteMaitre.ambre900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Le pied : `flex justify-end gap-2`.
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.mdPlus,
                vertical: AppSpacing.sm,
              ),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Ardoise.c200)),
              ),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  BoutonStandard(
                    key: const Key('modale-ecriture-annuler'),
                    libelle: TextesModaleEcriture.annuler,
                    variante: VarianteBouton.fantome,
                    onPressed: _envoi
                        ? null
                        : () => Navigator.of(context).pop(),
                  ),
                  BoutonStandard(
                    key: const Key('modale-ecriture-brouillon'),
                    libelle: TextesModaleEcriture.enregistrerBrouillon,
                    onPressed: _enregistrable
                        ? () => _enregistrer(valider: false)
                        : null,
                  ),
                  BoutonStandard(
                    key: const Key('modale-ecriture-valider'),
                    libelle: TextesModaleEcriture.enregistrerValider,
                    variante: VarianteBouton.primaire,
                    onPressed: _enregistrable
                        ? () => _enregistrer(valider: true)
                        : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// `grid md:grid-cols-4 gap-3` : journal, date, libellé (deux colonnes).
  Widget _enTete() {
    final valeur = styleTransverse(Tailles.t13);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _Champ(
            libelle: TextesModaleEcriture.champJournal,
            requis: true,
            child: DropdownButtonFormField<String>(
              key: const Key('modale-ecriture-journal'),
              initialValue: _journal,
              isExpanded: true,
              isDense: true,
              style: valeur,
              decoration: _decoration(),
              hint: Text(TextesModaleEcriture.choisir, style: valeur),
              items: [
                for (final j in widget.journaux)
                  DropdownMenuItem(
                    value: j.code,
                    child: Text(
                      '${j.code} — ${j.libelle}',
                      overflow: TextOverflow.ellipsis,
                      style: valeur,
                    ),
                  ),
              ],
              onChanged: _envoi ? null : (v) => setState(() => _journal = v),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _Champ(
            libelle: TextesModaleEcriture.champDate,
            requis: true,
            child: InkWell(
              key: const Key('modale-ecriture-date'),
              onTap: _envoi ? null : _choisirDate,
              child: InputDecorator(
                decoration: _decoration(
                  suffixe: const Icon(
                    Icons.calendar_today_outlined,
                    size: AppLayout.iconeChamp,
                    color: Ardoise.c500,
                  ),
                ),
                child: Text(_dateAffichee(_date), style: valeur),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          flex: 2,
          child: _Champ(
            libelle: TextesModaleEcriture.champLibellePiece,
            requis: true,
            child: TextField(
              key: const Key('modale-ecriture-libelle'),
              controller: _libelle,
              enabled: !_envoi,
              style: valeur,
              decoration: _decoration(
                invite: TextesModaleEcriture.champLibellePieceInvite,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// La grille des lignes : en-tête `bg-slate-50`, une rangée par ligne, puis
  /// les totaux et l'écart.
  Widget _grille(List<CompteDuPlan> comptes, int ecart) {
    final entete = styleTransverse(
      Tailles.t11,
      poids: FontWeight.w600,
      couleur: Ardoise.c500,
    );
    final total = styleTransverse(
      Tailles.t13,
      poids: FontWeight.bold,
      couleur: AppColors.navy,
    );
    Widget cellule(int flex, Widget enfant) => Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.unit,
          vertical: AppSpacing.unit,
        ),
        child: enfant,
      ),
    );
    const retrait = SizedBox(width: AppSpacing.xl);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.roundedLg),
        border: Border.all(color: Ardoise.c200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: Ardoise.c50,
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
            child: Row(
              children: [
                cellule(
                  _Flex.compte,
                  Text(
                    TextesModaleEcriture.colCompte.toUpperCase(),
                    style: entete,
                  ),
                ),
                cellule(
                  _Flex.libelle,
                  Text(
                    TextesModaleEcriture.colLibelleLigne.toUpperCase(),
                    style: entete,
                  ),
                ),
                cellule(
                  _Flex.centre,
                  Text(
                    TextesModaleEcriture.colCentre.toUpperCase(),
                    style: entete,
                  ),
                ),
                cellule(
                  _Flex.montant,
                  Text(
                    TextesModaleEcriture.colDebit.toUpperCase(),
                    textAlign: TextAlign.right,
                    style: entete,
                  ),
                ),
                cellule(
                  _Flex.montant,
                  Text(
                    TextesModaleEcriture.colCredit.toUpperCase(),
                    textAlign: TextAlign.right,
                    style: entete,
                  ),
                ),
                retrait,
              ],
            ),
          ),
          for (final l in _lignes)
            Container(
              key: ValueKey('modale-ecriture-ligne-${l.numero}'),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Ardoise.c100)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  cellule(_Flex.compte, _champCompte(l, comptes)),
                  cellule(
                    _Flex.libelle,
                    TextField(
                      key: Key('modale-ecriture-libelle-${l.numero}'),
                      controller: l.libelle,
                      enabled: !_envoi,
                      style: styleTransverse(Tailles.t13),
                      decoration: _decoration(),
                    ),
                  ),
                  cellule(_Flex.centre, _champCentre(l)),
                  cellule(_Flex.montant, _champMontant(l.debit, 'debit', l)),
                  cellule(_Flex.montant, _champMontant(l.credit, 'credit', l)),
                  SizedBox(
                    width: AppSpacing.xl,
                    child: _lignes.length > 2
                        ? IconButton(
                            key: Key('modale-ecriture-retirer-${l.numero}'),
                            tooltip: TextesModaleEcriture.ligneRetirer,
                            iconSize: AppLayout.iconeChamp,
                            color: Ardoise.c400,
                            onPressed: _envoi ? null : () => _retirerLigne(l),
                            icon: const Icon(Icons.close),
                          )
                        : null,
                  ),
                ],
              ),
            ),
          // Les totaux : Débit, Crédit, Écart — recalculés à chaque frappe.
          Container(
            decoration: const BoxDecoration(
              color: Ardoise.c50,
              // `border-t-2 border-slate-300`.
              border: Border(
                top: BorderSide(color: Ardoise.c300, width: AppSpacing.demi),
              ),
            ),
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
            child: Row(
              children: [
                cellule(
                  _Flex.compte + _Flex.libelle + _Flex.centre,
                  Text(TextesModaleEcriture.totaux, style: total),
                ),
                cellule(
                  _Flex.montant,
                  Text(
                    _montant(_totalDebit),
                    key: const Key('modale-ecriture-total-debit'),
                    textAlign: TextAlign.right,
                    style: total,
                  ),
                ),
                cellule(
                  _Flex.montant,
                  Text(
                    _montant(_totalCredit),
                    key: const Key('modale-ecriture-total-credit'),
                    textAlign: TextAlign.right,
                    style: total,
                  ),
                ),
                retrait,
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xs),
            child: Align(
              alignment: Alignment.centerLeft,
              child: _pastilleEcart(ecart),
            ),
          ),
        ],
      ),
    );
  }

  /// « Écart de X. » en rouge, ou « Pièce équilibrée. » en vert — la pastille
  /// de la vue, toujours affichée pour que l'écart se lise en continu.
  Widget _pastilleEcart(int ecart) {
    final equilibree = ecart == 0 && _totalDebit > 0;
    final (fond, bord, texte) = equilibree
        ? (
            PaletteMaitre.emeraude50,
            PaletteMaitre.emeraude200,
            PaletteMaitre.emeraude700,
          )
        : (
            PaletteMaitre.rouge50,
            PaletteMaitre.rouge200,
            PaletteMaitre.rouge700,
          );
    return Container(
      key: const Key('modale-ecriture-ecart'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.unit,
      ),
      decoration: BoxDecoration(
        color: fond,
        borderRadius: BorderRadius.circular(AppRadius.rounded),
        border: Border.all(color: bord),
      ),
      child: Text(
        equilibree
            ? TextesModaleEcriture.pieceEquilibree
            : TextesModaleEcriture.pieceEcart(_montant(ecart.abs())),
        style: styleTransverse(Tailles.t12, couleur: texte),
      ),
    );
  }

  /// Le compte : une saisie qui propose les comptes IMPUTABLES du plan local
  /// (numéro au début, ou libellé contenant la frappe).
  Widget _champCompte(_LigneSaisie l, List<CompteDuPlan> comptes) {
    return LayoutBuilder(
      builder: (context, contraintes) => RawAutocomplete<CompteDuPlan>(
        textEditingController: l.compte,
        focusNode: l.focusCompte,
        displayStringForOption: _affichageCompte,
        optionsBuilder: (saisie) {
          final q = saisie.text.trim().toLowerCase();
          final retenus = q.isEmpty
              ? comptes
              : comptes.where(
                  (c) =>
                      c.numero.startsWith(q) ||
                      c.libelle.toLowerCase().contains(q) ||
                      _affichageCompte(c).toLowerCase() == q,
                );
          return retenus.take(_comptesProposes);
        },
        onSelected: (c) => setState(() => l.compteChoisi = c),
        fieldViewBuilder: (context, controleur, focus, valider) => TextField(
          key: Key('modale-ecriture-compte-${l.numero}'),
          controller: controleur,
          focusNode: focus,
          enabled: !_envoi,
          style: styleTransverse(Tailles.t13),
          decoration: _decoration(invite: TextesModaleEcriture.choisir),
          onChanged: (texte) {
            // Retoucher le texte d'un compte choisi le désélectionne : le
            // compte imputé est TOUJOURS celui qu'on lit dans le champ.
            final choisi = l.compteChoisi;
            if (choisi != null && texte != _affichageCompte(choisi)) {
              setState(() => l.compteChoisi = null);
            }
          },
          onSubmitted: (_) => valider(),
        ),
        optionsViewBuilder: (context, choisir, options) => Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: AppSpacing.unit,
            borderRadius: BorderRadius.circular(AppRadius.roundedLg),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: AppLayout.hauteurMaxPropositionsCompte,
                maxWidth: contraintes.maxWidth * 2,
              ),
              child: options.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      child: Text(
                        TextesModaleEcriture.aucunCompte,
                        style: styleTransverse(
                          Tailles.t13,
                          couleur: Ardoise.c500,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      itemCount: options.length,
                      itemBuilder: (context, i) {
                        final c = options.elementAt(i);
                        return InkWell(
                          onTap: () => choisir(c),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm,
                              vertical: AppSpacing.xs,
                            ),
                            child: Text(
                              _affichageCompte(c),
                              style: styleTransverse(Tailles.t13),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ),
      ),
    );
  }

  /// Le centre : « — » laisse le moteur prendre le centre par défaut du
  /// compte (et refuser s'il n'en porte pas).
  Widget _champCentre(_LigneSaisie l) {
    final valeur = styleTransverse(Tailles.t13);
    return DropdownButtonFormField<String?>(
      key: Key('modale-ecriture-centre-${l.numero}'),
      initialValue: l.centreId,
      isExpanded: true,
      isDense: true,
      style: valeur,
      decoration: _decoration(),
      items: [
        DropdownMenuItem<String?>(
          child: Text(TextesModaleEcriture.centreDuCompte, style: valeur),
        ),
        for (final c in widget.centres)
          DropdownMenuItem<String?>(
            value: c.id,
            child: Text(
              c.libelle,
              overflow: TextOverflow.ellipsis,
              style: valeur,
            ),
          ),
      ],
      onChanged: _envoi ? null : (v) => setState(() => l.centreId = v),
    );
  }

  /// Un montant en francs ENTIERS (`type="number" step="1"` de la vue).
  Widget _champMontant(
    TextEditingController controleur,
    String sens,
    _LigneSaisie l,
  ) => TextField(
    key: Key('modale-ecriture-$sens-${l.numero}'),
    controller: controleur,
    enabled: !_envoi,
    textAlign: TextAlign.right,
    keyboardType: TextInputType.number,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    style: styleTransverse(Tailles.t13),
    decoration: _decoration(),
    onChanged: (_) => setState(() {}),
  );

  InputDecoration _decoration({String? invite, Widget? suffixe}) {
    OutlineInputBorder bord(Color couleur) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.roundedMd),
      borderSide: BorderSide(color: couleur),
    );
    return InputDecoration(
      isDense: true,
      hintText: invite,
      hintStyle: styleTransverse(Tailles.t13, couleur: Ardoise.c400),
      suffixIcon: suffixe,
      suffixIconConstraints: const BoxConstraints(minWidth: AppSpacing.xl),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xs,
      ),
      border: bord(Ardoise.c300),
      enabledBorder: bord(Ardoise.c300),
      disabledBorder: bord(Ardoise.c200),
      focusedBorder: bord(AppColors.navy),
    );
  }

  static String _affichageCompte(CompteDuPlan c) =>
      '${c.numero} — ${c.libelle}';

  /// `d/m/Y` — la date comptable `AAAA-MM-JJ`.
  static String _dateAffichee(String iso) {
    final p = iso.split('-');
    return p.length == 3 ? '${p[2]}/${p[1]}/${p[0]}' : iso;
  }

  /// `MontantFcfa::formatOuTiret` : un zéro s'affiche « — ».
  static String _montant(int centimes) => centimes == 0
      ? TextesModaleEcriture.tiret
      : (formaterMontantDecimal(
              chaineDepuisCentimes(centimes),
              suffixe: 'FCFA',
            ) ??
            TextesModaleEcriture.tiret);
}

/// Un champ étiqueté : `block text-[12px] font-semibold text-slate-600 mb-1`,
/// l'astérisque rouge des champs obligatoires.
class _Champ extends StatelessWidget {
  const _Champ({
    required this.libelle,
    required this.child,
    this.requis = false,
  });

  final String libelle;
  final Widget child;
  final bool requis;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text.rich(
        TextSpan(
          children: [
            TextSpan(text: libelle),
            if (requis)
              const TextSpan(
                text: ' *',
                style: TextStyle(color: PaletteMaitre.rouge500),
              ),
          ],
        ),
        style: styleTransverse(
          Tailles.t12,
          poids: FontWeight.w600,
          couleur: Ardoise.c600,
        ),
      ),
      const SizedBox(height: AppSpacing.unit),
      child,
    ],
  );
}
