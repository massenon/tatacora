// Vue Blade maîtresse (PA-183) : pwa/restaurant/restauration.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../data/restaurant_api.dart';
import '../../domain/entities/plat.dart';
import '../../domain/messages_restaurant.dart';
import '../providers_restaurant.dart';
import 'coquille_modale_restaurant.dart';
import 'modale_fiche.dart';
import 'modale_menu.dart';
import 'textes_modale_restaurant.dart';

/// La modale de formulaire d'un plat — création ou modification (EF-M4-01).
///
/// @see EF-M4-01 Gestion des menus et cartes
/// @see EF-M4-02 Fiches techniques — la fiche est ce qui rend le plat
///   décrémentable
///
/// ## Les champs de la VUE, dans son ordre (09/10/2026)
///
/// Nom du plat, prix de vente (et sa marque « prix provisoire »), menu, fiche
/// technique. La version précédente reprenait les cinq champs de l'ancien
/// maître — dont « Disponible » et « Ingrédients principaux », deux champs
/// rendus INERTES avec leur raison — parce qu'aucune table ne portait ni le
/// menu ni la fiche. La v14 en a une : la vue n'a plus ces deux champs, et les
/// afficher inertes aurait été garder un contrôle mort (Article 3.3).
///
/// ## Le champ « Catégorie » de la vue n'est PAS porté, et c'est un arbitrage
/// OUVERT (D100)
///
/// La vue écrit une colonne `plats.categorie` de dix valeurs (« Entrées »,
/// « Plats complets »…) que ce poste ne porte pas : la catégorie d'un plat est
/// ici celle de son MENU (`menus.type`, trois valeurs), comme l'API du serveur.
/// Les deux ne sont pas la même notion ; trancher n'est pas à cet écran. Le
/// sélecteur de menu affiche donc le type de chaque menu, pour que le geste
/// « classer le plat » reste le même.
///
/// ## Menu et fiche sont de VRAIES clés étrangères, créables sur place
///
/// `plats.menu_id` et `plats.recette_id` sont obligatoires. Sur un poste neuf
/// les deux sélecteurs sont VIDES : la vue le dit (« Aucun menu n'existe encore
/// ») et pose, à côté du champ, le bouton qui crée l'élément manquant. Le menu
/// ou la fiche qui vient d'être créé est PRÉSÉLECTIONNÉ, et la saisie en cours
/// est conservée : faire retaper le plat serait punir l'utilisateur d'avoir
/// suivi le seul chemin possible.
///
/// ## « Corrigé à la main » est un état, pas un champ
///
/// Il est DÉDUIT à l'enregistrement quand le prix d'un plat provisoire change.
/// Quand le plat le porte déjà, la modale le dit en lecture seule : il ne se
/// lève pas depuis cet écran.
Future<bool?> ouvrirModalePlat(BuildContext context, {Plat? plat}) =>
    showDialog<bool>(
      context: context,
      // Fermeture au voile — Article 4.6.
      barrierDismissible: true,
      barrierColor: AppColors.voileModale,
      builder: (_) => _ModalePlat(plat: plat),
    );

class _ModalePlat extends ConsumerStatefulWidget {
  const _ModalePlat({this.plat});

  final Plat? plat;

  @override
  ConsumerState<_ModalePlat> createState() => _ModalePlatState();
}

class _ModalePlatState extends ConsumerState<_ModalePlat> {
  late final TextEditingController _libelle = TextEditingController(
    text: widget.plat?.libelle ?? '',
  );
  late final TextEditingController _prix = TextEditingController(
    text: _prixInitial(widget.plat?.prixVente),
  );

  late String? _menuId = widget.plat?.menuId;
  late String? _recetteId = widget.plat?.recetteId;
  late bool _provisoire = widget.plat?.prixProvisoire ?? false;

  bool _envoi = false;
  String? _refus;
  Map<String, String> _parChamp = const {};

  bool get _modification => widget.plat != null;

  /// « 4500.00 » -> « 4500 » : le prix se saisit en francs entiers.
  static String _prixInitial(String? brut) {
    if (brut == null) return '';
    final i = brut.indexOf('.');
    return i < 0 ? brut : brut.substring(0, i);
  }

  @override
  void dispose() {
    _libelle.dispose();
    _prix.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final menus = ref.watch(menusProvider);
    final recettes = ref.watch(recettesProvider);

    return CoquilleModaleRestaurant(
      cle: const Key('modale-plat'),
      // Les titres de la vue — `form_titre_creation` et
      // `form_titre_modification`.
      titre: _modification ? 'Modifier le plat' : 'Nouveau plat',
      largeur: AppLayout.modalePlat,
      refus: _parChamp.isEmpty ? _refus : null,
      cleRefus: const Key('modale-plat-refus'),
      corps: _Corps(
        libelle: _libelle,
        prix: _prix,
        menus: menus,
        recettes: recettes,
        menuId: _menuId,
        recetteId: _recetteId,
        provisoire: _provisoire,
        corrigeMain: widget.plat?.prixCorrigeMain ?? false,
        erreurs: _parChamp,
        onMenu: (v) => setState(() => _menuId = v),
        onRecette: (v) => setState(() => _recetteId = v),
        onProvisoire: (v) => setState(() => _provisoire = v),
        onCreerMenu: _creerMenu,
        onCreerFiche: _creerFiche,
      ),
      actions: [
        TextButton(
          key: const Key('modale-plat-annuler'),
          onPressed: _envoi ? null : () => Navigator.of(context).pop(false),
          // Le libellé commun des modales (`pwa.modale.annuler`).
          child: const Text('Annuler', style: TextesModaleRestaurant.bouton),
        ),
        FilledButton(
          key: const Key('modale-plat-enregistrer'),
          // Jamais grisé faute de menu ou de fiche : un bouton grisé sans
          // explication se lit comme un écran cassé. Le refus, lui, nomme le
          // champ et dit quoi faire.
          onPressed: _envoi ? null : _enregistrer,
          // `bouton_enregistrer` — le même mot en création et en modification.
          child: const Text(
            'Enregistrer',
            style: TextesModaleRestaurant.bouton,
          ),
        ),
      ],
    );
  }

  /// Le menu créé depuis ce formulaire est présélectionné, et la saisie en cours
  /// reste là.
  Future<void> _creerMenu() async {
    final menu = await ouvrirModaleMenu(context);
    if (menu != null && mounted) setState(() => _menuId = menu.id);
  }

  Future<void> _creerFiche() async {
    final fiche = await ouvrirModaleFiche(context);
    if (fiche != null && mounted) setState(() => _recetteId = fiche.id);
  }

  Future<void> _enregistrer() async {
    setState(() {
      _envoi = true;
      _refus = null;
      _parChamp = const {};
    });

    final messager = ScaffoldMessenger.of(context);
    final navigateur = Navigator.of(context);

    final resultat = await ref
        .read(restaurantApiProvider)
        .enregistrerPlat(
          SaisiePlat(
            id: widget.plat?.id,
            libelle: _libelle.text,
            menuId: _menuId ?? '',
            recetteId: _recetteId ?? '',
            prixVente: _prix.text,
            prixProvisoire: _provisoire,
          ),
          modification: _modification,
        );

    if (!mounted) return;

    switch (resultat) {
      case RestaurantRecu<Plat>(:final donnees):
        invaliderRestaurant(ref);
        // Le message REMPLACE le précédent : les files d'attente de messages
        // feraient lire « menu créé » quatre secondes après avoir créé la fiche.
        messager
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Text(
                MessagesRestaurant.platEnregistre(
                  donnees.libelle,
                  creation: !_modification,
                ),
                key: const Key('toast-plat-enregistre'),
              ),
            ),
          );
        navigateur.pop(true);
      case RestaurantRefuse<Plat>(:final motif, :final erreurs):
        setState(() {
          _envoi = false;
          _refus = motif;
          _parChamp = erreurs;
        });
      case RestaurantInjoignable<Plat>():
        // Jamais produite : une base locale n'est pas hors connexion.
        setState(() => _envoi = false);
    }
  }
}

class _Corps extends StatelessWidget {
  const _Corps({
    required this.libelle,
    required this.prix,
    required this.menus,
    required this.recettes,
    required this.menuId,
    required this.recetteId,
    required this.provisoire,
    required this.corrigeMain,
    required this.erreurs,
    required this.onMenu,
    required this.onRecette,
    required this.onProvisoire,
    required this.onCreerMenu,
    required this.onCreerFiche,
  });

  final TextEditingController libelle;
  final TextEditingController prix;
  final AsyncValue<List<MenuRestaurant>?> menus;
  final AsyncValue<List<Recette>?> recettes;
  final String? menuId;
  final String? recetteId;
  final bool provisoire;
  final bool corrigeMain;
  final Map<String, String> erreurs;
  final ValueChanged<String?> onMenu;
  final ValueChanged<String?> onRecette;
  final ValueChanged<bool> onProvisoire;
  final VoidCallback onCreerMenu;
  final VoidCallback onCreerFiche;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 1. « Nom du plat » — `label_nom`, invite comprise (`invite_nom`).
        const EtiquetteChampRestaurant(texte: 'Nom du plat', obligatoire: true),
        TextField(
          key: const Key('modale-plat-libelle'),
          controller: libelle,
          style: TextesModaleRestaurant.etiquette,
          decoration: InputDecoration(
            hintText: 'Ex. Poulet DG',
            isDense: true,
            border: const OutlineInputBorder(),
            errorText: erreurs['libelle'],
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        // 2. « Prix de vente (FCFA) » — `label_prix`, libellé au caractère près.
        const EtiquetteChampRestaurant(
          texte: 'Prix de vente (FCFA)',
          obligatoire: true,
        ),
        TextField(
          key: const Key('modale-plat-prix'),
          controller: prix,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: TextesModaleRestaurant.etiquette,
          decoration: InputDecoration(
            isDense: true,
            border: const OutlineInputBorder(),
            errorText: erreurs['prix_vente'],
            errorMaxLines: 4,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),

        // PA-161 (b) — la marque « prix provisoire », une DÉCISION qui se
        // coche. « Corrigé à la main » n'est pas ici : c'est un fait, déduit.
        InkWell(
          key: const Key('modale-plat-provisoire'),
          onTap: () => onProvisoire(!provisoire),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: AppLayout.casePrixProvisoire,
                height: AppLayout.casePrixProvisoire,
                child: Checkbox(
                  value: provisoire,
                  onChanged: (v) => onProvisoire(v ?? false),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      // `label_prix_provisoire`.
                      'Prix provisoire',
                      style: TextesModaleRestaurant.sousTitre.copyWith(
                        fontWeight: FontWeight.bold,
                        color: PaletteMaitre.rouge600,
                      ),
                    ),
                    const Text(
                      // `aide_prix_provisoire`.
                      "À cocher quand le tarif a été posé faute de relevé : il reste à confronter à la carte physique. La marque s'imprime en regard du prix, y compris sur la fiche remise au client.",
                      style: TextesModaleRestaurant.aide,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (corrigeMain)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              // `etat_prix_corrige_main` — un ÉTAT dérivé, en lecture seule.
              "Ce tarif a été corrigé à la main : la marque « corrigé à la main » s'imprime en regard du prix. Elle est posée automatiquement quand le prix d'un article provisoire est modifié, et ne se lève pas depuis cet écran.",
              key: const Key('modale-plat-corrige-main'),
              style: TextesModaleRestaurant.aide.copyWith(
                color: PaletteMaitre.ambre600,
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.md),

        // 3. « Menu » — `label_menu`. À la place de « Catégorie » : le menu,
        // qui la porte (voir l'en-tête, D100).
        const EtiquetteChampRestaurant(texte: 'Menu', obligatoire: true),
        _SelecteurReferentiel(
          cle: const Key('modale-plat-menu'),
          valeur: menuId,
          onChange: onMenu,
          erreur: erreurs['menu_id'],
          // `invite_menu`.
          invite: 'Choisir un menu',
          etat: etatDe(menus),
          entrees: [
            for (final m in listeChargee(menus) ?? const <MenuRestaurant>[])
              (m.id, '${m.libelle} — ${m.typeLibelle}'),
          ],
          vide: MessagesRestaurant.aucunMenu,
          inconnu:
              'Le référentiel des menus n’a pas pu être lu. Ce n’est pas « il '
              'n’y en a aucun » : on ne sait pas.',
          cleCreer: const Key('modale-plat-creer-menu'),
          libelleCreer: 'Créer un menu',
          onCreer: onCreerMenu,
        ),
        const SizedBox(height: AppSpacing.md),

        // 4. « Fiche technique (recette) » — `label_fiche`.
        const EtiquetteChampRestaurant(
          texte: 'Fiche technique (recette)',
          obligatoire: true,
        ),
        _SelecteurReferentiel(
          cle: const Key('modale-plat-recette'),
          valeur: recetteId,
          onChange: onRecette,
          erreur: erreurs['recette_id'],
          // `invite_fiche`.
          invite: 'Choisir une fiche technique',
          etat: etatDe(recettes),
          entrees: [
            for (final r in listeChargee(recettes) ?? const <Recette>[])
              (r.id, r.libelle),
          ],
          vide: MessagesRestaurant.aucuneFiche,
          inconnu:
              'Le référentiel des fiches techniques n’a pas pu être lu. Ce '
              'n’est pas « il n’y en a aucune » : on ne sait pas.',
          // `aide_fiche`.
          aide:
              "Obligatoire : un plat se décrémente par sa fiche technique. Créez d'abord la recette si elle n'existe pas.",
          cleCreer: const Key('modale-plat-creer-fiche'),
          libelleCreer: 'Créer une fiche technique',
          onCreer: onCreerFiche,
        ),
      ],
    );
  }
}

/// L'état d'un référentiel qui remplit un sélecteur.
///
/// Quatre, pas deux : « en cours », « prêt », **« vide »** et **« on ne sait
/// pas »**. Confondre les deux derniers ferait afficher un sélecteur vide sous
/// un formulaire qui semble fonctionner (PA-129).
enum EtatReferentiel { charge, pret, vide, inconnu }

/// La liste effectivement reçue, ou `null` tant qu'aucune donnée n'est arrivée.
///
/// `AsyncData` est filtré par motif plutôt que lu par un accesseur nullable :
/// `AsyncValue` distingue « en cours », « en erreur » et « reçu », et un
/// accesseur qui replie les trois sur `null` perdrait exactement la distinction
/// que [EtatReferentiel] existe pour tenir.
List<T>? listeChargee<T>(AsyncValue<List<T>?> valeur) => switch (valeur) {
  AsyncData(value: final v) => v,
  _ => null,
};

/// Les quatre états d'un référentiel, dérivés d'une seule source.
EtatReferentiel etatDe<T>(AsyncValue<List<T>?> valeur) => switch (valeur) {
  AsyncLoading() => EtatReferentiel.charge,
  // `AsyncData(null)` = on n'a rien pu lire (droit manquant). Ce n'est PAS
  // « il n'y en a aucun ».
  AsyncData(value: null) => EtatReferentiel.inconnu,
  AsyncData(value: final v) when v!.isEmpty => EtatReferentiel.vide,
  AsyncData() => EtatReferentiel.pret,
  _ => EtatReferentiel.inconnu,
};

class _SelecteurReferentiel extends StatelessWidget {
  const _SelecteurReferentiel({
    required Key cle,
    required this.valeur,
    required this.onChange,
    required this.invite,
    required this.etat,
    required this.entrees,
    required this.vide,
    required this.inconnu,
    required this.cleCreer,
    required this.libelleCreer,
    required this.onCreer,
    this.erreur,
    this.aide,
  }) : super(key: cle);

  final String? valeur;
  final ValueChanged<String?> onChange;
  final String invite;
  final EtatReferentiel etat;
  final List<(String, String)> entrees;
  final String vide;
  final String inconnu;
  final String? erreur;
  final String? aide;
  final Key cleCreer;
  final String libelleCreer;
  final VoidCallback onCreer;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        switch (etat) {
          EtatReferentiel.charge => const LinearProgressIndicator(),
          EtatReferentiel.vide => _Avertissement(texte: vide, erreur: erreur),
          EtatReferentiel.inconnu => _Avertissement(
            texte: inconnu,
            erreur: erreur,
          ),
          EtatReferentiel.pret => DropdownButtonFormField<String>(
            initialValue: entrees.any((e) => e.$1 == valeur) ? valeur : null,
            isExpanded: true,
            style: TextesModaleRestaurant.etiquette,
            decoration: InputDecoration(
              hintText: invite,
              isDense: true,
              border: const OutlineInputBorder(),
              errorText: erreur,
              errorMaxLines: 4,
            ),
            items: [
              for (final (id, libelle) in entrees)
                DropdownMenuItem(value: id, child: Text(libelle)),
            ],
            onChanged: onChange,
          ),
        },
        if (aide != null) ...[
          const SizedBox(height: AppSpacing.unit),
          Text(aide!, style: TextesModaleRestaurant.aide),
        ],
        // Le bouton qui lève l'impasse, rendu dans TOUS les cas : sans lui, il
        // faudrait fermer le formulaire pour créer un second menu, et retaper
        // le plat.
        const SizedBox(height: AppSpacing.unit),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            key: cleCreer,
            onPressed: onCreer,
            child: Text(libelleCreer, style: TextesModaleRestaurant.aide),
          ),
        ),
      ],
    );
  }
}

class _Avertissement extends StatelessWidget {
  const _Avertissement({required this.texte, this.erreur});

  final String texte;

  /// Le refus du champ quand le sélecteur n'existe pas (référentiel vide) : le
  /// dire sous l'avertissement, pas le taire.
  final String? erreur;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.xsPlus),
          decoration: BoxDecoration(
            color: PaletteMaitre.ambre50,
            borderRadius: BorderRadius.circular(AppRadius.roundedLg),
            border: Border.all(color: PaletteMaitre.ambre200),
          ),
          child: Text(
            texte,
            style: TextesModaleRestaurant.aide.copyWith(
              color: PaletteMaitre.ambre900,
            ),
          ),
        ),
        if (erreur != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.unit),
            child: Text(
              erreur!,
              style: TextesModaleRestaurant.aide.copyWith(
                color: AppColors.erreur,
              ),
            ),
          ),
      ],
    );
  }
}
