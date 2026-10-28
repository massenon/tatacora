// Vue Blade maîtresse (PA-183) : pwa/depenses/depenses.blade.php
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/fichiers/selecteur_fichiers.dart';
import '../../../../core/format/formats.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../comptabilite/domain/refus_comptable.dart';
import '../../../restaurant/presentation/widgets/coquille_modale_restaurant.dart';
import '../../domain/categories_depense.dart';
import '../../domain/entities/depense.dart';
import '../../domain/recu_depense.dart';
import '../../domain/reduction_recu.dart';
import '../providers_depenses.dart';

/// La modale **« Nouvelle Dépense »** de la vue (l.324-511), posée dans le
/// châssis partagé des modales (`x-pwa.modale`, ici [CoquilleModaleRestaurant]).
///
/// Les blocs sont ceux de la vue, dans son ordre : l'introduction (l.328-330),
/// le refus (l.336-339), « Date » et « Libellé » côte à côte (l.341-352), les
/// lignes d'achat (l.359-462), le compte de trésorerie (l.464-485), le reçu
/// (l.487-493), puis « Annuler » et « Enregistrer la dépense » (l.498-508).
///
/// ## Le montant décaissé NE SE SAISIT PAS
///
/// C'est la règle n° 2 du dépôt, et la vue la porte à son pied de tableau : le
/// libellé du maître, « Montant décaissé (FCFA) », nomme désormais un TOTAL en
/// lecture seule — c'est bien le montant qui sort de la caisse, il n'est
/// simplement plus tapé. Il est recalculé à chaque frappe, puis **recalculé une
/// seconde fois** par le dépôt à l'enregistrement, qui seul fait foi. Aucun
/// total n'est transmis.
///
/// Sa place est celle de la vue : l'étiquette court sur les deux premières
/// colonnes (`colspan="2"`), le total tombe sous la TROISIÈME (l.454-456), pas
/// sous « Prix ». Ce n'est pas une erreur de ce portage.
///
/// ## Une ligne à moitié tapée est IGNORÉE du total, pas comptée à zéro
///
/// Le total est un AFFICHAGE : une frappe intermédiaire (« 12x ») ne doit pas
/// faire tomber la modale. Le refus des lignes vides tombe à l'enregistrement,
/// là où il peut **nommer la ligne fautive** — une dépense à six lignes dont
/// une est vide doit dire laquelle, sans quoi l'opérateur relit les six.
///
/// ## L'échelle typographique est celle des MODALES
///
/// Les conteneurs de modales sont hors `<main>` : le remappage de `app.css` ne
/// les atteint pas, et `text-[15px]` y vaut bien 15 px — non 14. C'est
/// [Tailles], pas `TaillesContenu`.
///
/// ÉCART DÉLIBÉRÉ — `depenses.blade.php` l.461.
/// La vue : « … le montant écrit en comptabilité est celui que le serveur
/// recalcule à l'enregistrement. »
/// Ici : « … le montant écrit en comptabilité est celui que ce poste recalcule
/// des lignes. »
/// Raison (10/10/2026) : ce poste écrit bien en comptabilité depuis la v16 —
/// la pièce est passée dans la même transaction que la dépense —, mais il ne
/// parle à aucun serveur : dire que « le serveur » recalcule décrirait un geste
/// qu'il ne fait pas. La règle — le total ne se saisit pas, il est recalculé des
/// lignes réellement écrites — est tenue à l'identique.
///
/// ÉCART DÉLIBÉRÉ — `depenses.blade.php` l.409-415.
/// La vue : le `<select>` de catégorie groupe ses natures par `<optgroup>`.
/// Ici : chaque nature porte sa famille sur sa propre ligne (« Marché ·
/// Tomate »).
/// Raison : `DropdownButton` exige UNE valeur par entrée, et un intitulé de
/// groupe est sans valeur — il concourrait pour `null` avec le repère « —
/// Choisir — » (trouvé le 14/09/2026). Le groupement reste visible, il passe de
/// l'en-tête à la ligne.
Future<bool?> ouvrirModaleDepense(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierColor: AppColors.voileModale,
    builder: (context) => const ModaleDepense(),
  );
}

class ModaleDepense extends ConsumerStatefulWidget {
  const ModaleDepense({super.key});

  @override
  ConsumerState<ModaleDepense> createState() => _ModaleDepenseState();
}

class _ModaleDepenseState extends ConsumerState<ModaleDepense> {
  final _libelle = TextEditingController();

  /// La date du jour par défaut, comme la vue : c'est le cas courant, et une
  /// date vide ferait ressaisir la même valeur vingt fois par semaine.
  DateTime _date = DateTime.now();

  TresorerieDepense? _tresorerie;

  /// Le centre de coût EXPLICITE (RG-12). `null` = « Défaut du compte » : c'est
  /// alors le centre par défaut du compte qui joue, et un compte sans défaut est
  /// refusé par le moteur avec la phrase du serveur. Rien n'est deviné.
  String? _centreId;

  /// UNE ligne vierge à l'ouverture, jamais zéro : une modale sans ligne
  /// n'offrirait rien à remplir, et il faudrait deviner qu'un bouton
  /// « Ajouter une ligne » commence la saisie.
  final List<_LigneEnSaisie> _lignes = [_LigneEnSaisie()];

  String? _refus;
  bool _envoiEnCours = false;

  /// Le reçu choisi (lot L4), déjà jugé par la règle du web ; `null` : aucun.
  RecuAJoindre? _recu;

  /// Pourquoi le dernier fichier choisi a été refusé — sous le champ, en rouge,
  /// comme le `@error('photoRecu')` de la vue (l.513).
  String? _refusRecu;

  @override
  void dispose() {
    _libelle.dispose();
    for (final ligne in _lignes) {
      ligne.dispose();
    }
    super.dispose();
  }

  /// Le total de la saisie — somme d'ENTIERS, les lignes illisibles ignorées.
  int get _total {
    var total = 0;
    for (final ligne in _lignes) {
      final montant = ligne.montant;
      if (montant != null && montant > 0) total += montant;
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    return CoquilleModaleRestaurant(
      cle: const Key('depense-modale'),
      titre: 'Nouvelle Dépense',
      largeur: AppLayout.modaleDepense,
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // L'intro de la vue (l.328-330), au mot : `text-[13px]
          // text-slate-400 bg-slate-50 rounded-lg px-3 py-2`.
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: Ardoise.c50,
              borderRadius: BorderRadius.circular(AppRadius.roundedLg),
            ),
            child: const Text(
              'Enregistrez une charge d\'exploitation de trésorerie directe.',
              style: _Textes.intro,
            ),
          ),
          if (_refus != null) ...[
            // `space-y-4` — 16 px.
            const SizedBox(height: AppSpacing.md),
            // Le refus est affiché DANS la modale, jamais en `SnackBar` : la
            // saisie est encore là, et le message doit rester lisible pendant
            // qu'on la corrige. Il porte sur la pièce entière (l.332-339).
            Container(
              key: const Key('depense-refus'),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: AppColors.erreurFond,
                borderRadius: BorderRadius.circular(AppRadius.roundedLg),
                border: Border.all(color: AppColors.erreurBordure),
              ),
              child: Text(_refus!, style: _Textes.refus),
            ),
          ],
          const SizedBox(height: AppSpacing.md),

          // La rangée à deux colonnes de la vue (l.341-352) : `gap-3`.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _champDate()),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: _champLibelle()),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          _blocLignes(),
          const SizedBox(height: AppSpacing.md),

          // `grid grid-cols-1 sm:grid-cols-2` (l.464-491) : la trésorerie et le
          // centre de coût, côte à côte.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _champTresorerie()),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: _champCentre()),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          _ChampRecu(
            recu: _recu,
            refus: _refusRecu,
            occupe: _envoiEnCours,
            surChoisir: _choisirRecu,
            surRetirer: () => setState(() {
              _recu = null;
              _refusRecu = null;
            }),
          ),
        ],
      ),
      actions: [
        OutlinedButton(
          key: const Key('depense-annuler'),
          style: _Textes.styleBouton(),
          onPressed: _envoiEnCours ? null : () => Navigator.of(context).pop(),
          // Le libellé partagé des modales de la PWA (`pwa.modale.annuler`).
          child: const Text('Annuler', style: _Textes.bouton),
        ),
        FilledButton(
          key: const Key('depense-enregistrer'),
          style: _Textes.styleBouton(plein: true),
          // Désactivé pendant l'envoi, pas seulement occupé : un second clic
          // créerait une seconde dépense pour le même argent.
          onPressed: _envoiEnCours ? null : _enregistrer,
          child: const Text(
            'Enregistrer la dépense',
            style: _Textes.boutonPlein,
          ),
        ),
      ],
    );
  }

  /* ------------------------------------------------------------ les champs */

  Widget _champDate() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      const _Etiquette('Date de la transaction', obligatoire: true),
      InkWell(
        key: const Key('depense-date'),
        borderRadius: BorderRadius.circular(AppRadius.roundedLg),
        onTap: () async {
          final choisi = await showDatePicker(
            context: context,
            initialDate: _date,
            firstDate: DateTime(DateTime.now().year - 5),
            lastDate: DateTime(DateTime.now().year + 1),
          );
          if (choisi == null) return;
          setState(() => _date = choisi);
        },
        child: _BoiteChamp(
          remplissage: _Textes.remplissageChamp,
          child: Text(formaterDate(_date), style: _Textes.champ),
        ),
      ),
    ],
  );

  Widget _champLibelle() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      const _Etiquette('Libellé de la dépense', obligatoire: true),
      TextField(
        key: const Key('depense-libelle'),
        controller: _libelle,
        style: _Textes.champ,
        decoration: _Textes.decoration(
          // L'invite de la vue (l.349), au mot.
          'ex. Marché du matin — légumes',
          _Textes.remplissageChamp,
        ),
      ),
    ],
  );

  Widget _champTresorerie() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      // « Compte de trésorerie » et non « compte débité » : régler une charge
      // CRÉDITE la trésorerie et DÉBITE le compte de charge. Nommer l'un pour
      // l'autre sur un écran qui affiche des comptes SYSCOHADA enseignerait
      // l'inverse de la règle.
      const _Etiquette('Compte de trésorerie', obligatoire: true),
      _BoiteChamp(
        remplissage: _Textes.remplissageChamp,
        child: DropdownButtonHideUnderline(
          child: DropdownButton<TresorerieDepense?>(
            key: const Key('depense-tresorerie'),
            value: _tresorerie,
            isExpanded: true,
            isDense: true,
            itemHeight: null,
            iconSize: AppLayout.iconeChamp,
            style: _Textes.champ,
            items: [
              const DropdownMenuItem<TresorerieDepense?>(
                child: Text('— Choisir —'),
              ),
              for (final t in TresorerieDepense.values)
                DropdownMenuItem<TresorerieDepense?>(
                  value: t,
                  child: Text(t.libelle),
                ),
            ],
            onChanged: (v) => setState(() => _tresorerie = v),
          ),
        ),
      ),
      // `mt-1` — 4 px.
      const SizedBox(height: AppSpacing.unit),
      const Text('D\'où l\'argent est sorti.', style: _Textes.aide),
    ],
  );

  /// « Centre de coût » (l.481-490) : « Défaut du compte » puis les sept centres
  /// du moteur local, dans l'ordre de la vue. Facultatif à la saisie — la vue le
  /// pose sans astérisque —, mais la comptabilité l'exige (RG-12) : c'est le
  /// moteur qui refuse, avec la phrase du serveur, un compte sans centre par
  /// défaut. Le champ n'invente donc aucun centre.
  Widget _champCentre() {
    final centres = ref.watch(centresDeCoutProvider).value ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _Etiquette('Centre de coût'),
        _BoiteChamp(
          remplissage: _Textes.remplissageChamp,
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              key: const Key('depense-centre'),
              value: _centreId,
              isExpanded: true,
              isDense: true,
              itemHeight: null,
              iconSize: AppLayout.iconeChamp,
              style: _Textes.champ,
              items: [
                const DropdownMenuItem<String?>(
                  child: Text('Défaut du compte'),
                ),
                for (final c in centres)
                  DropdownMenuItem<String?>(
                    value: c.id,
                    child: Text(c.libelle),
                  ),
              ],
              onChanged: (v) => setState(() => _centreId = v),
            ),
          ),
        ),
      ],
    );
  }

  /* ------------------------------------------------------- les lignes */

  Widget _blocLignes() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      // `flex flex-wrap items-end justify-between gap-2 mb-1.5` (l.360).
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.end,
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const _Etiquette('Lignes de la dépense', obligatoire: true),
              const Text(
                'Une dépense peut porter plusieurs achats. Chaque ligne a '
                'son libellé, son compte de charge et son prix.',
                style: _Textes.aide,
              ),
            ],
          ),
          OutlinedButton(
            key: const Key('depense-ligne-ajouter'),
            style: _Textes.styleBouton(petit: true),
            onPressed: () => setState(() => _lignes.add(_LigneEnSaisie())),
            child: const Text('+ Ajouter une ligne', style: _Textes.petit),
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.xxs),

      // `overflow-x-auto border border-slate-200 rounded-lg` (l.371).
      Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.roundedLg),
          border: Border.all(color: Ardoise.c200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // L'en-tête navy des cinq colonnes de la vue (l.373-384).
            Container(
              color: AppColors.navy,
              child: Row(
                children: [
                  // Les proportions du tableau de la vue : le sélecteur de
                  // compte est le plus large — les libellés du plan comptable
                  // vont jusqu'à cinquante caractères, et c'est la raison que
                  // la vue donne elle-même pour sa boîte de 760 px.
                  _enteteColonne('Libellé', 3),
                  _enteteColonne('Catégorie des charges (SYSCOHADA)', 4),
                  _enteteColonne('Catégorie de dépenses', 3),
                  _enteteColonne('Prix', 2, aDroite: true),
                  // La colonne du bouton de retrait — son en-tête est un
                  // `sr-only` à la vue : aucun titre visible.
                  const SizedBox(width: AppLayout.colonneRetraitDepense),
                ],
              ),
            ),

            for (var i = 0; i < _lignes.length; i++) _ligne(i),

            // Le pied du tableau — le TOTAL, en lecture seule (l.446-458).
            Container(
              decoration: const BoxDecoration(
                color: Ardoise.c50,
                border: Border(top: BorderSide(color: Ardoise.c200)),
              ),
              child: Row(
                children: [
                  // `colspan="2"` : l'étiquette court sur « Libellé » et sur
                  // le compte (3 + 4 parts).
                  const Expanded(
                    flex: 7,
                    child: Padding(
                      padding: _Textes.cellulePied,
                      child: Text(
                        'Montant décaissé (FCFA)',
                        textAlign: TextAlign.right,
                        style: _Textes.totalEtiquette,
                      ),
                    ),
                  ),
                  // Le total tombe sous la TROISIÈME colonne (3 parts), comme
                  // dans la vue.
                  Expanded(
                    flex: 3,
                    child: Padding(
                      padding: _Textes.celluleTotal,
                      child: Text(
                        formaterFcfa(_total),
                        key: const Key('depense-total'),
                        textAlign: TextAlign.right,
                        style: _Textes.total,
                      ),
                    ),
                  ),
                  // Le `<td></td>` vide sous « Prix ».
                  const Expanded(flex: 2, child: SizedBox.shrink()),
                  // La cinquième colonne (le « × ») : la vue n'y pose aucune
                  // cellule, mais elle existe — sans elle les parts du pied ne
                  // s'alignent plus sur celles des lignes.
                  const SizedBox(width: AppLayout.colonneRetraitDepense),
                ],
              ),
            ),
          ],
        ),
      ),
      // `mt-1` — 4 px.
      const SizedBox(height: AppSpacing.unit),
      // ÉCART nommé avec la vue (`depenses_pwa.total_aide`). Elle dit, mot pour
      // mot : « Total général des lignes, recalculé à chaque saisie. Il ne se saisit pas : le montant écrit en comptabilité est celui que le serveur recalcule à l'enregistrement. »
      // Ici la pièce est écrite par CE poste (`DepenseDao` → `MoteurComptable`),
      // à partir des lignes : « que le serveur recalcule » y serait faux au
      // moment où l'écriture passe (le serveur passe la sienne plus tard, à la
      // réception du document). La phrase rendue dit « que ce poste recalcule
      // des lignes ». La mesure la compte « nommée », pas « rendue ».
      const Text(
        'Total général des lignes, recalculé à chaque saisie. Il ne se saisit '
        'pas : le montant écrit en comptabilité est celui que ce poste '
        'recalcule des lignes.',
        style: _Textes.aide,
      ),
    ],
  );

  /// Un en-tête du tableau des lignes — `px-4 py-2.5`, capitales (`uppercase`
  /// est une transformation CSS : on applique la même).
  Widget _enteteColonne(String titre, int part, {bool aDroite = false}) =>
      Expanded(
        flex: part,
        child: Padding(
          padding: _Textes.celluleEntete,
          child: Text(
            titre.toUpperCase(),
            textAlign: aDroite ? TextAlign.right : TextAlign.left,
            style: _Textes.entete,
          ),
        ),
      );

  Widget _ligne(int i) {
    final ligne = _lignes[i];
    final comptes = ref.watch(comptesDeChargeProvider).value ?? const [];

    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Ardoise.c100)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Padding(
              padding: _Textes.celluleLigne,
              child: TextField(
                key: Key('depense-ligne-libelle-$i'),
                controller: ligne.libelle,
                style: _Textes.champLigne,
                decoration: _Textes.decoration(
                  'ex. Marché du matin — légumes',
                  _Textes.remplissageLigne,
                  style: _Textes.champLigne,
                ),
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Padding(
              padding: _Textes.celluleLigne,
              child: _BoiteChamp(
                remplissage: _Textes.remplissageLigne,
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    key: Key('depense-ligne-compte-$i'),
                    value: ligne.compte,
                    isExpanded: true,
                    isDense: true,
                    itemHeight: null,
                    iconSize: AppLayout.iconeChamp,
                    style: _Textes.champLigne,
                    items: [
                      const DropdownMenuItem<String?>(
                        child: Text('— Choisir —'),
                      ),
                      // Classe 6, quatre chiffres, LUS du plan installé :
                      // proposer un compte de bilan permettrait un décaissement
                      // sans charge, invisible au compte de résultat, et une
                      // division (60, 601…) n'est pas imputable.
                      for (final c in comptes)
                        DropdownMenuItem<String?>(
                          value: c.numero,
                          child: Text(
                            CompteDeCharge(c.numero, c.libelle).affichage,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (v) => setState(() => ligne.compte = v),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Padding(
              padding: _Textes.celluleLigne,
              child: _BoiteChamp(
                remplissage: _Textes.remplissageLigne,
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<NatureDepense?>(
                    key: Key('depense-ligne-nature-$i'),
                    value: ligne.nature,
                    isExpanded: true,
                    isDense: true,
                    itemHeight: null,
                    iconSize: AppLayout.iconeChamp,
                    style: _Textes.champLigne,
                    // ⚠ UN SEUL élément peut porter la valeur courante, et
                    // `DropdownButton` le vérifie par une assertion. Le repère
                    // « — Choisir — » ET chaque intitulé de famille étaient
                    // tous SANS `value`, donc tous à `null` : tant qu'aucune
                    // nature n'était choisie, Flutter en trouvait quatre et
                    // levait, ce qui faisait échouer la modale entière (trouvé
                    // le 14/09/2026).
                    //
                    // Les intitulés de famille quittent donc l'espace des
                    // valeurs : chaque nature porte sa famille sur sa PROPRE
                    // ligne (« Marché · Tomate »). Le champ FERMÉ, lui,
                    // n'affiche que la nature (`selectedItemBuilder`, aligné
                    // index par index sur `items`) : la famille y serait une
                    // redite dans une largeur déjà contrainte.
                    selectedItemBuilder: (_) => [
                      const Text('— Choisir —'),
                      for (final famille in FamilleDepense.values)
                        for (final n in NatureDepense.deLaFamille(famille))
                          Text(n.libelle),
                    ],
                    items: [
                      const DropdownMenuItem<NatureDepense?>(
                        value: null,
                        child: Text('— Choisir —'),
                      ),
                      for (final famille in FamilleDepense.values) ...[
                        for (final n in NatureDepense.deLaFamille(famille))
                          DropdownMenuItem<NatureDepense?>(
                            value: n,
                            child: Text(
                              '${famille.libelle} · ${n.libelle}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ],
                    onChanged: (v) => setState(() => ligne.nature = v),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: _Textes.celluleLigne,
              child: TextField(
                key: Key('depense-ligne-montant-$i'),
                controller: ligne.prix,
                textAlign: TextAlign.right,
                keyboardType: TextInputType.number,
                // Le XOF n'a pas de sous-unité : ni virgule, ni point.
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: _Textes.champLigne.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
                decoration: _Textes.decoration(
                  'ex. 12 500',
                  _Textes.remplissageLigne,
                  style: _Textes.champLigne,
                ),
                // C'est ce qui fait recalculer le total à chaque frappe.
                onChanged: (_) => setState(() {}),
              ),
            ),
          ),
          // Le bouton n'existe QUE s'il reste une ligne après le retrait : une
          // dépense sans ligne n'existe pas. Le dépôt refuse aussi le geste —
          // la vue cache, elle ne protège pas.
          SizedBox(
            width: AppLayout.colonneRetraitDepense,
            child: _lignes.length > 1
                ? IconButton(
                    key: Key('depense-ligne-retirer-$i'),
                    tooltip: 'Retirer cette ligne',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.close, color: Ardoise.c400),
                    onPressed: () => setState(() {
                      _lignes.removeAt(i).dispose();
                      // Les refus nomment un rang : après un retrait, les rangs
                      // ont glissé et le message désignerait la ligne voisine.
                      // L'effacer vaut mieux que de le faire mentir.
                      _refus = null;
                    }),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  /* ------------------------------------------------------ enregistrement */

  /// « Choisir un fichier » : la fenêtre native « Ouvrir », puis la règle de
  /// saisie (PO, 28/10/2026) : image reconnue à son contenu ; si elle pèse plus
  /// de 400 Ko elle est RÉDUITE (`preparerRecu`), jamais refusée pour son poids.
  /// Un fichier refusé (non-image, illisible) n'est pas gardé, et la phrase du
  /// web est dite sous le champ.
  Future<void> _choisirRecu() async {
    final FichierLu? fichier;
    try {
      fichier = await ref
          .read(selecteurFichiersProvider)
          .ouvrirImage(extensions: TypeRecu.extensionsProposees);
    } on Object {
      if (mounted) {
        setState(
          () => _refusRecu = 'Le fichier n’a pas pu être ouvert. Réessayez.',
        );
      }
      return;
    }
    if (fichier == null || !mounted) return;
    final issue = await preparerRecu(fichier.octets);
    if (!mounted) return;
    setState(() {
      switch (issue) {
        case RecuAccepte(:final type, :final octets, :final reduit):
          _recu = RecuAJoindre(
            nom: fichier!.nom,
            octets: octets ?? fichier.octets,
            type: type,
            tailleOrigine: reduit ? fichier.octets.length : null,
          );
          _refusRecu = null;
        case RecuRefuse(:final phrase):
          _recu = null;
          _refusRecu = phrase;
      }
    });
  }

  Future<void> _enregistrer() async {
    final tresorerie = _tresorerie;

    // Les refus de FORME sont rendus ici, dans les mots du registre fermé de
    // `RefusDepense` : aucun message technique n'atteint l'opérateur.
    if (_libelle.text.trim().isEmpty) {
      setState(() => _refus = const RefusDepense.libelleManquant().message);
      return;
    }
    if (tresorerie == null) {
      setState(() => _refus = const RefusDepense.tresorerieManquante().message);
      return;
    }

    final saisies = <SaisieLigneDepense>[];
    for (var i = 0; i < _lignes.length; i++) {
      final ligne = _lignes[i];
      final rang = i + 1;
      final nature = ligne.nature;
      final compte = ligne.compte;

      if (ligne.libelle.text.trim().isEmpty) {
        setState(() => _refus = RefusDepense.libelleLigne(rang).message);
        return;
      }
      if (compte == null) {
        setState(() => _refus = RefusDepense.compteLigne(rang).message);
        return;
      }
      if (nature == null) {
        setState(() => _refus = RefusDepense.natureLigne(rang).message);
        return;
      }
      final montant = ligne.montant;
      if (montant == null) {
        setState(() => _refus = RefusDepense.montantLigne(rang).message);
        return;
      }
      if (montant <= 0) {
        setState(() => _refus = RefusDepense.montantNul(rang).message);
        return;
      }

      saisies.add(
        SaisieLigneDepense(
          libelle: ligne.libelle.text,
          compteCharge: compte,
          nature: nature,
          montant: montant,
        ),
      );
    }

    setState(() {
      _envoiEnCours = true;
      _refus = null;
    });

    try {
      // UN SEUL appel, avec la liste COMPLÈTE. Aucun total n'est transmis : le
      // dépôt le recalcule des lignes réellement écrites.
      final depense = await ref
          .read(depotDepensesProvider)
          .enregistrer(
            dateTransaction: _date,
            tresorerie: tresorerie,
            libelle: _libelle.text,
            lignes: saisies,
            auteurId: ref.read(sessionProvider)?.utilisateurId ?? '',
            centreId: _centreId,
            recu: _recu,
          );

      ref
          .read(messageSuccesDepenseProvider.notifier)
          .definir(
            'Dépense de ${formaterFcfa(depense.montantTotal)} enregistrée.',
          );
      // La liste lit la base : sans invalidation, la dépense n'apparaîtrait
      // qu'au prochain passage sur l'écran, et on la ressaisirait.
      ref.invalidate(depensesProvider);

      if (mounted) Navigator.of(context).pop(true);
    } on RefusDepense catch (refus) {
      // Le dépôt refait la même validation, et c'est lui qui fait foi : la
      // garde de l'écran est redondante, délibérément.
      setState(() {
        _refus = refus.message;
        _envoiEnCours = false;
      });
    } on RefusComptable catch (refus) {
      // La pièce est refusée (exercice, centre de coût, compte, journal) : la
      // modale reste ouverte avec la saisie, la phrase est celle du serveur, et
      // RIEN n'a été écrit — ni dépense, ni pièce, ni numéro consommé. Le refus
      // porte sur la dépense ENTIÈRE, jamais sur une ligne en particulier.
      setState(() {
        _refus = refus.message;
        _envoiEnCours = false;
      });
    }
  }
}

/// Une ligne **en cours de saisie** — ses contrôleurs, et rien de persisté.
final class _LigneEnSaisie {
  final TextEditingController libelle = TextEditingController();
  final TextEditingController prix = TextEditingController();
  String? compte;
  NatureDepense? nature;

  /// `null` quand le champ est vide ou illisible — distinct d'un zéro, qui est
  /// une saisie explicite et se refuse par un autre message.
  int? get montant {
    final texte = prix.text.trim().replaceAll(' ', '');
    if (texte.isEmpty) return null;
    return int.tryParse(texte);
  }

  void dispose() {
    libelle.dispose();
    prix.dispose();
  }
}

/// La boîte d'un contrôle non textuel — `border border-slate-200 rounded-lg`,
/// au même remplissage que les champs voisins pour qu'ils aient la même
/// hauteur.
class _BoiteChamp extends StatelessWidget {
  const _BoiteChamp({required this.remplissage, required this.child});

  final EdgeInsets remplissage;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: remplissage,
      decoration: BoxDecoration(
        color: AppColors.neutre0,
        borderRadius: BorderRadius.circular(AppRadius.roundedLg),
        border: Border.all(color: Ardoise.c200),
      ),
      child: child,
    );
  }
}

/// L'étiquette d'un champ — `block text-[15px] font-semibold text-slate-700
/// mb-1.5`, l'astérisque rouge des champs obligatoires en plus.
class _Etiquette extends StatelessWidget {
  const _Etiquette(this.texte, {this.obligatoire = false});

  final String texte;
  final bool obligatoire;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // `mb-1.5` — 6 px.
      padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: texte, style: _Textes.etiquette),
            if (obligatoire)
              const TextSpan(text: ' *', style: _Textes.asterisque),
          ],
        ),
      ),
    );
  }
}

/// « Reçu / facture (photo) » — le champ de la vue (l.487-493), PORTÉ depuis le
/// lot L4 (27/10/2026, décision du PO : la dépense du poste joint un reçu comme
/// l'écran web, et le fichier voyage par la synchronisation).
///
/// La vue : `<input type="file" accept="image/*">`, la règle `image|max:400`,
/// l'aide `champ_recu_aide` et l'erreur `photoRecu` en rouge dessous. Ici : un
/// bouton qui ouvre la fenêtre native « Ouvrir » (JPG, PNG, GIF, BMP, WEBP), la
/// MÊME règle (jugée sur le contenu, 400 Ko — `verifierRecu`) et les MÊMES
/// phrases de refus, dessous, en rouge.
///
/// L'aide `champ_recu_aide` est reprise AU MOT, puis complétée de ce que fait ce
/// poste : depuis le 28/10/2026 la réduction existe réellement, sur le serveur
/// (`RecuDepenseService::preparer`) comme ici (`preparerRecu`,
/// `reduction_recu.dart`), et la vue a retiré sa 2ᵉ phrase (« le navigateur ne
/// peut en conserver qu'une douzaine », qui décrivait le stockage du prototype).
/// L'ancien écart du lot L4 (piège 13 : la vue promettait une réduction que rien
/// ne faisait) est donc SOLDÉ. Un test relit la phrase de la vue dans le PHP.
class _ChampRecu extends StatelessWidget {
  const _ChampRecu({
    required this.recu,
    required this.refus,
    required this.occupe,
    required this.surChoisir,
    required this.surRetirer,
  });

  final RecuAJoindre? recu;
  final String? refus;
  final bool occupe;
  final VoidCallback surChoisir;
  final VoidCallback surRetirer;

  /// L'aide du champ : la phrase de la vue, au mot (apostrophe droite, comme le
  /// maître), puis ce que fait ce poste. « 400 Ko » est écrit en clair (le
  /// comparateur lit le texte du code) ; un test le lie à [tailleMaxRecuKo].
  static const String aide =
      'L\'image est réduite automatiquement avant enregistrement si elle pèse '
      'plus de 400 Ko. Elle est rangée sur ce poste (JPG, PNG, GIF, BMP ou '
      'WEBP), puis envoyée au serveur à la synchronisation.';

  /// Le texte du champ vide — celui du navigateur devant un `<input type=file>`.
  static const String aucunFichier = 'Aucun fichier choisi';

  @override
  Widget build(BuildContext context) {
    final choisi = recu;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _Etiquette('Reçu / facture (photo)'),
        Row(
          children: [
            OutlinedButton(
              key: const Key('depense-recu-choisir'),
              style: _Textes.styleBouton(),
              onPressed: occupe ? null : surChoisir,
              child: const Text('Choisir un fichier', style: _Textes.bouton),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                choisi == null
                    ? aucunFichier
                    : '${choisi.nom} · ${(choisi.octets.length / 1024).ceil()} Ko'
                          '${choisi.tailleOrigine == null ? '' : ' (réduite de ${(choisi.tailleOrigine! / 1024).ceil()} Ko)'}',
                key: const Key('depense-recu-nom'),
                overflow: TextOverflow.ellipsis,
                style: _Textes.aide,
              ),
            ),
            if (choisi != null)
              TextButton(
                key: const Key('depense-recu-retirer'),
                onPressed: occupe ? null : surRetirer,
                child: const Text('Retirer', style: _Textes.bouton),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xxs),
        const Text(aide, key: Key('depense-recu-aide'), style: _Textes.aide),
        if (refus != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xxs),
            child: Text(
              refus!,
              key: const Key('depense-recu-refus'),
              style: _Textes.refus,
            ),
          ),
      ],
    );
  }
}

/// Les styles de la modale — échelle **déclarée** ([Tailles]), pas celle du
/// contenu de page : une modale est hors `<main>`.
abstract final class _Textes {
  /// `text-[13px] text-slate-400` — l'introduction (l.328).
  static const TextStyle intro = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: Tailles.t13,
    color: Ardoise.c400,
  );

  /// `text-[15px] font-semibold text-slate-700`.
  static const TextStyle etiquette = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: Tailles.t15,
    fontWeight: FontWeight.w600,
    color: Ardoise.c700,
  );

  /// `text-red-500` — l'astérisque des champs obligatoires.
  static const TextStyle asterisque = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: Tailles.t15,
    fontWeight: FontWeight.w600,
    color: PaletteMaitre.rouge500,
  );

  /// `text-sm` d'un champ de la modale (l.65).
  static const TextStyle champ = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: Tailles.t14,
    color: Ardoise.c700,
  );

  /// `text-[13px]` d'un champ du tableau des lignes (l.391).
  static const TextStyle champLigne = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: Tailles.t13,
    color: Ardoise.c700,
  );

  /// `text-[12px] text-slate-400` — les aides sous les champs.
  static const TextStyle aide = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: Tailles.t12,
    color: Ardoise.c400,
  );

  /// `text-[11px] uppercase tracking-wide text-white/90` — l'en-tête navy du
  /// tableau des lignes.
  static const TextStyle entete = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: Tailles.t11,
    fontWeight: FontWeight.w600,
    letterSpacing: Tailles.t11 * AppTextStyles.suiviLarge,
    color: AppColors.blanc90,
  );

  /// `text-right font-semibold text-slate-600` du pied de tableau.
  static const TextStyle totalEtiquette = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: Tailles.t13,
    fontWeight: FontWeight.w600,
    color: Ardoise.c600,
  );

  /// `text-[15px] font-bold tabular-nums` navy — le total.
  static const TextStyle total = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: Tailles.t15,
    fontWeight: FontWeight.bold,
    color: AppColors.navy,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const TextStyle refus = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: Tailles.t13,
    fontWeight: FontWeight.w600,
    color: AppColors.erreur,
  );

  /// `text-[13px]` d'un bouton de pied (l.505).
  static const TextStyle bouton = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: Tailles.t13,
  );

  /// `text-[13px] font-semibold` du bouton « Enregistrer la dépense » (l.507).
  static const TextStyle boutonPlein = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: Tailles.t13,
    fontWeight: FontWeight.w600,
  );

  /// `text-[12px] font-semibold` de « + Ajouter une ligne » (l.366).
  static const TextStyle petit = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: Tailles.t12,
    fontWeight: FontWeight.w600,
  );

  /// `px-3 py-2.5` d'un champ (l.65) plus la bordure, que le navigateur compte
  /// dans la boîte et pas Flutter.
  static const EdgeInsets remplissageChamp = EdgeInsets.symmetric(
    horizontal: AppSpacing.sm + AppLayout.bordureControle,
    vertical: AppSpacing.xsPlus + AppLayout.bordureControle,
  );

  /// `px-2.5 py-2` d'un champ du tableau des lignes (l.391) plus la bordure.
  static const EdgeInsets remplissageLigne = EdgeInsets.symmetric(
    horizontal: AppSpacing.xsPlus + AppLayout.bordureControle,
    vertical: AppSpacing.xs + AppLayout.bordureControle,
  );

  /// `px-4 py-2.5` — une cellule d'en-tête (l.60).
  static const EdgeInsets celluleEntete = EdgeInsets.symmetric(
    horizontal: AppSpacing.md,
    vertical: AppSpacing.xsPlus,
  );

  /// `px-2 py-2` — une cellule de ligne (l.388).
  static const EdgeInsets celluleLigne = EdgeInsets.all(AppSpacing.xs);

  /// `px-4 py-2.5` — l'étiquette du total (l.454).
  static const EdgeInsets cellulePied = EdgeInsets.symmetric(
    horizontal: AppSpacing.md,
    vertical: AppSpacing.xsPlus,
  );

  /// `px-2 py-2.5` — le total (l.455).
  static const EdgeInsets celluleTotal = EdgeInsets.symmetric(
    horizontal: AppSpacing.xs,
    vertical: AppSpacing.xsPlus,
  );

  static InputDecoration decoration(
    String invite,
    EdgeInsets remplissage, {
    TextStyle style = champ,
  }) {
    final bordure = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      borderSide: const BorderSide(color: Ardoise.c200),
    );
    return InputDecoration(
      hintText: invite,
      hintStyle: style.copyWith(color: Ardoise.c400),
      isDense: true,
      contentPadding: remplissage,
      enabledBorder: bordure,
      focusedBorder: bordure,
    );
  }

  /// Le gabarit d'un bouton de la modale : `rounded-lg`, bordé en `slate-300`
  /// ou plein navy ([plein]), `px-4 py-2` ou `px-3 py-1.5` ([petit]).
  static ButtonStyle styleBouton({bool plein = false, bool petit = false}) {
    final remplissage = petit
        ? const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm + AppLayout.bordureControle,
            vertical: AppSpacing.xxs + AppLayout.bordureControle,
          )
        : const EdgeInsets.symmetric(
            horizontal: AppSpacing.md + AppLayout.bordureControle,
            vertical: AppSpacing.xs + AppLayout.bordureControle,
          );
    final forme = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.roundedLg),
    );
    return plein
        ? FilledButton.styleFrom(
            padding: remplissage,
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            backgroundColor: AppColors.navy,
            foregroundColor: AppColors.neutre0,
            shape: forme,
          )
        : OutlinedButton.styleFrom(
            padding: remplissage,
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: Ardoise.c700,
            side: const BorderSide(color: Ardoise.c300),
            shape: forme,
          );
  }
}
